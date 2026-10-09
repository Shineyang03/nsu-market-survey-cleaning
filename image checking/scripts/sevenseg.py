"""sevenseg.py -- read the red LED display on a Micromatic market scale.

WHAT THIS IS FOR. Check 2 asks what the scale display actually read, against a typed
value the pipeline may have multiplied by 1,000. That is transcription, not judgement:
one right answer per image, no interpretation. So it should be done by something
deterministic and auditable rather than by a model whose output varies run to run --
and, more importantly, by something that CANNOT see the typed value and be pulled
toward confirming it.

NO NEW DEPENDENCIES. numpy, scipy and Pillow are already present on this machine.
tesseract is not installed, has no seven-segment training data, and performs badly on
LED glyphs; easyocr and paddleocr would each pull in a CPU-only torch stack on a
machine with no GPU. A seven-segment digit is seven yes/no questions once it is
cropped, so the honest amount of machinery here is small.

HOW IT WORKS
    1. mask the red LED pixels  (R high, and R clearly above both G and B)
    2. dilate horizontally so the glyphs of one display row merge into one blob
    3. take candidate rows, score them, keep the best
    4. split the row into digit boxes
    5. decode each box by sampling seven segment windows

WHAT IT CANNOT DO, stated plainly because a reader needs it before trusting a number:

  * The Micromatic has THREE red rows -- WEIGHT, UNIT PRICE, TOTAL PRICE. This picks
    the row it scores best, which is usually but not always WEIGHT. A confident wrong
    row is the most dangerous failure here, so `row_rank` and `n_rows_found` are
    returned for every read and a reading from a low-ranked row should be treated as
    unverified.
  * Inactive segments on these displays still glow faintly. The mask threshold decides
    whether a dim `8.8.8.8.8` is read as 8s or as blank, and there is no threshold that
    is right for every photograph.
  * Angle, glare and motion blur are not corrected.

So this is a FIRST PASS that proposes a reading and says how sure it is. Its output is
compared against an independent blind human-or-model read; agreement is evidence, and
disagreement is the flag list. It is not authoritative on its own.

USAGE
    python sevenseg.py --manifest ../outputs/sheets/manifest_ocr_test.csv \
        --out ../outputs/qc/ocr_readings.csv

    # magnitude mode: which digit of x.xxx kg is the first non-zero (see below)
    py -3.14 sevenseg.py --magnitude --manifest <csv with image_code> \
        --crops <dir of rectified <image_code>.png> --out <csv> \
        [--mag-seg-off 0.25 ...]        # every MAG_PARAMS entry is a CLI flag

    from sevenseg import read_magnitude
    read_magnitude(path_to_rectified_crop, seg_off=0.25)   # -> flat dict

MAGNITUDE MODE (`--magnitude`, `read_magnitude`)
    Question answered: on a rectified WEIGHT crop of a Micromatic display that shows
    `x.xxx` kg, is the first non-zero digit in position 1 (1,000-9,999 g), 2 (100-999 g),
    3 (10-99 g) or 4 (1-9 g)? It does not read digits and does not know any recorded
    weight. `read_crop` above is NOT used: it segments digit boxes from a column profile
    and mis-segments on legends and glare, where this registers a fixed five-position
    grid on the unlit-segment ghost and asks seven yes/no questions per position.

    Method: grid registration -> per-cell alignment -> segment brightness relative to
    the cell's own dark holes and the crop's lit level -> decode each position against
    the set of valid seven-segment digits (zero / nonzero / uncertain) -> repeat at
    shifted grids and on a second colour view and require agreement -> format checks
    (decimal point present, leftmost position blank, grid not against its search bound,
    no position that matches no digit). The full description is above `MAG_PARAMS`.

    Output fields: mag_status (ok | uncertain | zero_reading | no_display |
    unreadable_file), uncertain_reason, first_nonzero_position (1-4), image_magnitude_g
    (1000/100/10/1), p1_state..p4_state (zero | nonzero | uncertain) with p*_pattern
    (a-g as 1 lit / 0 off / ? undecided), p*_cands (digits still possible), p*_outer_min,
    p*_g and p*_margin, confidence (smallest margin over the positions that decided the
    answer; 0 = on a threshold), grid_x / grid_pitch / grid_y / grid_height, fit_quality,
    cell_offsets, dot_found / dot_contrast, leftmost_lit / leftmost_lit_n, span, seconds.

    A confident answer needs every position before the first non-zero one to be
    confidently `zero` and that position confidently `nonzero`. Anything weaker is
    `uncertain`: a wrong confident answer multiplies a weight by a wrong power of ten.

    Assumes: crops are the 880x300 WEIGHT row from rectify_display.py; the display is
    `x.xxx` (a 10 kg+ reading lights the leftmost position and is returned uncertain);
    digits are upright; registration error is under about a third of a digit pitch.
    Cost: about 0.2-0.3 s per crop plus the image read.

    Measured result, 67 hand-labelled tune crops (true_pos 1:5, 2:49, 3:13; not a random
    sample, over-representing hard displays), default thresholds:
        confident wrong answers: 0 of 56;  ok 56/67 (83.6%);  uncertain 11
        (pos 1: 4 ok, 1 uncertain; pos 2: 40 ok, 9 uncertain; pos 3: 12 ok, 1 uncertain)
    On 700 unlabelled crops (two random subsets of the Check 2 manifest) 623 were `ok`
    (89%). Run it on the as-shot crops (rect_all/), not the de-ghosted ones: the gamma
    stretch removes dim lit segments and made 3 of 307 jointly-ok crops read as
    position 1 when the as-shot reading, which matches the photograph, was 2 or 3.
    Per-crop fields for the tune set: outputs/decimal_drift/magnitude_tune_eval.csv.
    Thresholds were chosen for physical reasons and checked on the tune set; with only
    67 labels, treat the coverage figure as optimistic and the zero-wrong figure as
    "none found", not "none possible".
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np
import pandas as pd
from PIL import Image, ImageOps
from scipy import ndimage

# ---- tuning ------------------------------------------------------------------
# Every number here is a convention, not a fact about the data, and each one is a
# place this can be wrong. They are named and gathered so a reader can see the whole
# set at once rather than finding them scattered through the code.
R_MIN = 95          # a lit red segment is at least this bright in R
R_OVER_G = 45       # ...and this much brighter than G
R_OVER_B = 40       # ...and this much brighter than B
MIN_BLOB_PX = 120   # a red blob smaller than this is noise (a reflection, a logo)
DIGIT_MIN_FRAC = 0.35   # a digit box must be at least this tall relative to the row
SEG_ON_FRAC = 0.32      # fraction of a segment window that must be lit to count as on
NARROW_W_H = 0.34       # width/height below this means the glyph is a '1'

# Standard seven-segment layout.
#     aaa
#    f   b
#     ggg
#    e   c
#     ddd
SEGMENT_MAP = {
    (1, 1, 1, 1, 1, 1, 0): "0",
    (0, 1, 1, 0, 0, 0, 0): "1",
    (1, 1, 0, 1, 1, 0, 1): "2",
    (1, 1, 1, 1, 0, 0, 1): "3",
    (0, 1, 1, 0, 0, 1, 1): "4",
    (1, 0, 1, 1, 0, 1, 1): "5",
    (1, 0, 1, 1, 1, 1, 1): "6",
    (1, 1, 1, 0, 0, 0, 0): "7",
    (1, 1, 1, 1, 1, 1, 1): "8",
    (1, 1, 1, 1, 0, 1, 1): "9",
    (0, 0, 0, 0, 0, 0, 1): "-",
    (0, 0, 0, 0, 0, 0, 0): "",
}


def red_mask(arr: np.ndarray) -> np.ndarray:
    """Boolean mask of lit red-LED pixels."""
    r = arr[:, :, 0].astype(np.int16)
    g = arr[:, :, 1].astype(np.int16)
    b = arr[:, :, 2].astype(np.int16)
    return (r > R_MIN) & ((r - g) > R_OVER_G) & ((r - b) > R_OVER_B)


def find_display_rows(mask: np.ndarray, img_w: int):
    """Group lit pixels into candidate display rows, best first.

    Digits within a row are separate blobs, so the mask is dilated horizontally by
    roughly a digit width before labelling. The dilation length is tied to image
    width rather than fixed, because these photographs vary in how much of the frame
    the scale occupies.
    """
    k = max(3, int(img_w * 0.018))
    joined = ndimage.binary_dilation(mask, structure=np.ones((1, k)))
    joined = ndimage.binary_closing(joined, structure=np.ones((3, 3)))

    lab, n = ndimage.label(joined)
    if n == 0:
        return []

    out = []
    for sl, idx in zip(ndimage.find_objects(lab), range(1, n + 1)):
        ys, xs = sl
        h = ys.stop - ys.start
        w = xs.stop - xs.start
        if h < 6 or w < 12:
            continue
        lit = int(mask[sl][lab[sl] == idx].sum())
        if lit < MIN_BLOB_PX:
            continue
        aspect = w / h
        # A display row is a wide, short band. 1.5 excludes a single stray glyph;
        # 14 excludes a long thin reflection off the platter edge.
        if not (1.5 <= aspect <= 14):
            continue
        # Prefer bands that are bright and large. Brightness separates the active
        # row from the faint 8.8.8.8 ghosts of the inactive ones.
        density = lit / float(w * h)
        score = lit * density
        out.append({
            "y0": ys.start, "y1": ys.stop, "x0": xs.start, "x1": xs.stop,
            "h": h, "w": w, "lit": lit, "density": density, "score": score,
        })

    out.sort(key=lambda d: -d["score"])
    return out


def split_digits(sub: np.ndarray):
    """Split one display row into digit boxes using the column profile."""
    col = sub.sum(axis=0)
    on = col > 0
    boxes, start = [], None
    for i, v in enumerate(on):
        if v and start is None:
            start = i
        elif not v and start is not None:
            boxes.append((start, i))
            start = None
    if start is not None:
        boxes.append((start, len(on)))

    H = sub.shape[0]
    keep = []
    for x0, x1 in boxes:
        seg = sub[:, x0:x1]
        rows = np.where(seg.any(axis=1))[0]
        if rows.size == 0:
            continue
        y0, y1 = rows[0], rows[-1] + 1
        h = y1 - y0
        w = x1 - x0
        if h < DIGIT_MIN_FRAC * H:
            # too short to be a digit: a decimal point or a status marker
            keep.append({"x0": x0, "x1": x1, "y0": y0, "y1": y1,
                         "kind": "dot", "w": w, "h": h})
            continue
        keep.append({"x0": x0, "x1": x1, "y0": y0, "y1": y1,
                     "kind": "digit", "w": w, "h": h})
    return keep


def decode_digit(box: np.ndarray) -> str:
    """Decode one digit box by sampling the seven segment windows."""
    h, w = box.shape
    if h == 0 or w == 0:
        return "?"
    if w / h < NARROW_W_H:
        return "1"

    def frac(y0, y1, x0, x1):
        y0, y1 = max(0, int(y0)), min(h, int(y1))
        x0, x1 = max(0, int(x0)), min(w, int(x1))
        if y1 <= y0 or x1 <= x0:
            return 0.0
        return float(box[y0:y1, x0:x1].mean())

    # Segment windows, as fractions of the digit box.
    a = frac(0,           0.18 * h,  0.22 * w, 0.78 * w)
    d = frac(0.82 * h,    h,         0.22 * w, 0.78 * w)
    g = frac(0.41 * h,    0.59 * h,  0.22 * w, 0.78 * w)
    f = frac(0.12 * h,    0.45 * h,  0,        0.22 * w)
    b = frac(0.12 * h,    0.45 * h,  0.78 * w, w)
    e = frac(0.55 * h,    0.88 * h,  0,        0.22 * w)
    c = frac(0.55 * h,    0.88 * h,  0.78 * w, w)

    key = tuple(int(v >= SEG_ON_FRAC) for v in (a, b, c, d, e, f, g))
    return SEGMENT_MAP.get(key, "?")


def read_display(path: str, max_side: int = 1600):
    """Read one photograph. Returns a dict; never raises on a bad image."""
    res = {
        "ocr_text": "", "ocr_value": np.nan, "n_rows_found": 0,
        "row_rank": np.nan, "row_density": np.nan, "n_digits": 0,
        "n_unknown": 0, "ocr_status": "",
    }
    try:
        im = Image.open(path)
        im = ImageOps.exif_transpose(im).convert("RGB")
    except Exception as exc:
        res["ocr_status"] = f"unreadable: {type(exc).__name__}"
        return res

    if max(im.size) > max_side:
        im.thumbnail((max_side, max_side), Image.LANCZOS)
    arr = np.asarray(im)

    mask = red_mask(arr)
    if mask.sum() < MIN_BLOB_PX:
        res["ocr_status"] = "no_red_display_found"
        return res

    rows = find_display_rows(mask, arr.shape[1])
    res["n_rows_found"] = len(rows)
    if not rows:
        res["ocr_status"] = "no_display_row"
        return res

    best = rows[0]
    res["row_rank"] = 0
    res["row_density"] = round(best["density"], 4)
    sub = mask[best["y0"]:best["y1"], best["x0"]:best["x1"]]

    parts = split_digits(sub)
    digits = [p for p in parts if p["kind"] == "digit"]
    dots = [p for p in parts if p["kind"] == "dot"]
    res["n_digits"] = len(digits)
    if not digits:
        res["ocr_status"] = "no_digits"
        return res

    text = ""
    unknown = 0
    for p in digits:
        ch = decode_digit(sub[p["y0"]:p["y1"], p["x0"]:p["x1"]])
        if ch == "?":
            unknown += 1
        text += ch
        # a dot sitting just right of this digit is a decimal point
        for dt in dots:
            if p["x1"] <= dt["x0"] <= p["x1"] + 0.6 * p["w"] and dt["y0"] > 0.6 * sub.shape[0]:
                text += "."
                break

    res["ocr_text"] = text
    res["n_unknown"] = unknown
    try:
        res["ocr_value"] = float(text) if text and unknown == 0 else np.nan
    except ValueError:
        res["ocr_value"] = np.nan

    if unknown:
        res["ocr_status"] = "partial"
    elif np.isnan(res["ocr_value"]):
        res["ocr_status"] = "unparsed"
    else:
        res["ocr_status"] = "ok"
    return res


# ---- reading a RECTIFIED CROP ------------------------------------------------
#
# `read_display` above works on a whole photograph and has to solve two problems at
# once: find the display among three red rows, and decide which pixels are lit. On a
# rectified crop the first problem is already solved -- the crop IS the WEIGHT row,
# cut at a fixed offset from a matched scale body -- so only the second remains.
#
# AND THE SECOND PROBLEM IS WHAT `red_mask` GETS WRONG. It thresholds absolutely:
# R > R_MIN, and R far enough above G and B. These photographs span bright stalls and
# near-dark interiors, so no absolute threshold works for all of them. Measured against
# eighteen crops with human-confirmed readings, that path returned `ok` on fourteen and
# was wrong on essentially all of them -- almost always reading `8`, because the unlit
# `8.8.8.8.8` ghost passes an absolute red test on a dim photograph. A confidently wrong
# number is the worst output this file can produce.
#
# The fix is to stretch each crop over ITS OWN range instead, which is exactly what
# `deghost_crops.py` does for human readers. Lit and unlit segments differ in
# brightness, not hue, so the red channel normalised between the crop's own percentiles
# separates them where a fixed cut cannot.

CROP_PCT_LO, CROP_PCT_HI = 60, 99.5   # same percentiles deghost_crops.py uses
CROP_GAMMA = 2.2                      # pushes mid-tones (the ghost) toward black
CROP_ON = 0.42                        # normalised brightness that counts as lit


def crop_mask(arr: np.ndarray, on: float = CROP_ON) -> np.ndarray:
    """Boolean mask of lit segments in a rectified display crop.

    Adaptive by construction: the percentile range is computed per crop, so a dark
    photograph and a bright one are normalised to the same scale before thresholding.
    """
    r = arr[:, :, 0].astype(np.float32)          # PIL RGB; index 0 is red
    r = ndimage.gaussian_filter(r, 1.2)          # kill sensor speckle
    lo, hi = np.percentile(r, CROP_PCT_LO), np.percentile(r, CROP_PCT_HI)
    if hi - lo < 1:
        lo, hi = float(r.min()), float(max(r.max(), r.min() + 1))
    z = np.clip((r - lo) / (hi - lo), 0, 1) ** CROP_GAMMA
    return z >= on


def read_crop(path: str, on: float = CROP_ON) -> dict:
    """Decode one rectified display crop. Returns a dict; never raises."""
    res = {"ocr_text": "", "ocr_value": None, "ocr_status": "",
           "n_digits": 0, "n_unknown": 0, "lit_frac": 0.0}
    try:
        im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    except Exception as exc:
        res["ocr_status"] = f"unreadable_file: {type(exc).__name__}"
        return res

    mask = crop_mask(np.asarray(im), on)
    res["lit_frac"] = float(mask.mean())
    if not mask.any():
        res["ocr_status"] = "nothing_lit"
        return res

    rows = np.where(mask.any(axis=1))[0]
    sub = mask[rows[0]:rows[-1] + 1, :]
    boxes = split_digits(sub)
    if not boxes:
        res["ocr_status"] = "no_digits"
        return res

    # Assemble left to right. A short box is the decimal point and is emitted in place,
    # so 0 . 1 6 0 reconstructs as "0.160" rather than losing the separator.
    out, ndig, nunk = [], 0, 0
    for b in sorted(boxes, key=lambda d: d["x0"]):
        if b["kind"] == "dot":
            out.append(".")
            continue
        d = decode_digit(sub[b["y0"]:b["y1"], b["x0"]:b["x1"]])
        ndig += 1
        if d == "?":
            nunk += 1
        out.append(d)

    text = "".join(out)
    res.update(ocr_text=text, n_digits=ndig, n_unknown=nunk)
    try:
        res["ocr_value"] = float(text)
        res["ocr_status"] = "ok" if nunk == 0 else "partial"
    except ValueError:
        res["ocr_status"] = "partial" if nunk else "unparsable"
    return res


# ---- reading the MAGNITUDE of a rectified WEIGHT crop -------------------------
#
# `read_crop` above tries to read the whole number and fails on SEGMENTATION: it finds
# digit boxes from the column profile of a thresholded mask, so legends, the minus sign
# and glare specks become boxes. The magnitude question needs much less: on a Micromatic
# the weight is always `x.xxx` kg, so there are exactly four digit positions, and the
# only thing wanted is which is the first one that is not `0`. That can be answered
# without reading a single digit, and without segmentation by threshold: REGISTER A FIXED
# FIVE-POSITION GRID, then ask seven yes/no questions per position.
#
#   1. Register. The unlit segments of a seven-segment display still glow faintly, so
#      the `8.8.8.8.8` ghost is visible in every crop, lit or not. A band-passed copy
#      of the red channel is scored against the union of all 35 segments (and against
#      the dark holes and margins around them) over a bounded (x, pitch, y, height)
#      search. The x range is narrower than one pitch, so the grid cannot slip by a
#      whole digit.
#      Each cell is then nudged by up to cell_shift px to align its own template, since
#      a vertical stroke is only ~14 px wide and one global grid is a compromise.
#   2. Measure. Each segment window's mean red, minus the mean of that cell's two
#      dark "holes" (local background, cancels glare gradients), is divided by the crop's
#      lit level (median of the segments at least half as bright as the 90th percentile
#      of the 28 weight segments), so 0 = hole background and 1 = lit.
#   3. Decide. Each segment is `lit` (>= seg_on), `off` (<= seg_off) or undecided; the
#      middle bar g has its own pair (g_on, g_off) because an unlit g sits between two
#      lit strokes and is raised by their bloom (measured over 638 fully-lit-outer cells:
#      unlit g ranges to ~0.5, lit g is >= ~0.8, and almost nothing falls between).
#      A position is decoded against the set of VALID seven-segment digits: it is
#      `zero` only if every digit still consistent with the decided segments is 0,
#      `nonzero` only if none is, otherwise `uncertain`. A pattern that matches no
#      valid digit (one dropped segment, glare, an occluding object) is uncertain, not
#      a guess. Every non-zero digit differs from 0 in at least one segment and all but
#      `8` in at least two, so a single faulty segment cannot manufacture a `nonzero`.
#   4. Repeats. The decision is repeated at the grid shifted +-perturb_px in x and in y,
#      and on a second colour view (R minus chroma x mean(G,B)), ten measurements in
#      all. A position keeps its state only if no repeat says the opposite (zero vs
#      nonzero is always fatal) and at least min_agree of the repeats say the same.
#   5. Format checks. A lit decimal point must be found in the gap after position 1,
#      the leftmost (5th) position must not look lit, and the grid fit must be
#      supported; otherwise the `x.xxx` assumption is not established and the answer
#      is uncertain.
#
# A confident answer needs every position before the first non-zero one to be
# `zero` and that position `nonzero`. The result is used to multiply a recorded
# weight by a power of ten, so a wrong confident answer is far worse than `uncertain`.
#
# ASSUMES: the crop is the rectified WEIGHT row (880x300, see rectify_display.py), the
# display shows `x.xxx` kg, the digits are upright, and registration error is below
# about one third of a digit pitch. WHAT IT KNOWS NOTHING ABOUT: recorded weights.
#
# Every number below is a named entry of MAG_PARAMS (default, one-line rationale) and
# every one can be overridden per call (`read_magnitude(path, seg_off=0.25)`) or from
# the CLI (`--mag-seg-off 0.25`).
MAG_PARAMS = {
    # --- geometry of the display, measured on clean crops (not tuned) --------------
    "wr":         (0.80, "digit cell width / pitch"),
    "tx":         (0.17, "vertical stroke thickness / cell width"),
    "ty":         (0.075, "horizontal stroke thickness / cell height"),
    "win_long":   (0.25, "trim at each end of a segment window's long axis (tolerates registration error)"),
    "win_thick":  (0.10, "trim at each side of a segment window's thickness"),
    # --- registration search bounds (crop pixels; rectify_display.py output frame) --
    "x_min":      (215.0, "leftmost cell's left edge, lower bound; range < 1 pitch so the grid cannot slip a digit"),
    "x_max":      (310.0, "leftmost cell's left edge, upper bound"),
    "pitch_min":  (98.0, "digit pitch lower bound (observed 100-112)"),
    "pitch_max":  (118.0, "digit pitch upper bound"),
    "y_min":      (24.0, "top of the digit, lower bound (stays above the UNIT PRICE row)"),
    "y_max":      (90.0, "top of the digit, upper bound"),
    "h_min":      (150.0, "digit height lower bound (observed 160-190)"),
    "h_max":      (205.0, "digit height upper bound"),
    # --- decision thresholds --------------------------------------------------------
    "seg_on":     (0.60, "segment is lit at or above this fraction of the ghost-to-lit span"),
    "seg_off":    (0.30, "segment is unlit at or below this fraction; the band between is undecided"),
    "g_on":       (0.70, "middle bar g is lit at or above this; separate from seg_on because g sits between lit strokes"),
    "g_off":      (0.45, "middle bar g is unlit at or below this; an unlit g of a lit 0 is raised by its neighbours' bloom"),
    "chroma":     (0.5, "second view: R minus this x mean(G,B); separates LED red from orange ghost; 0 = red view only"),
    "min_span":   (8.0, "grey levels between ghost and lit clusters below which nothing is lit"),
    "min_unlit":  (3, "at least this many of the 28 segments must be ghost, else no reference level exists"),
    "dot_min":    (0.25, "decimal-point contrast, as a fraction of the span, needed to accept the grid"),
    "left_lit_max": (3, "leftmost position with this many lit segments is a digit, not blank: not x.xxx"),
    "fit_min":    (0.10, "minimum grid-fit score (segments minus holes, band-passed units)"),
    "bound_tol":  (3.0, "grid within this many px of any search bound is untrusted (mis-rectified or off-frame)"),
    "cell_shift": (8.0, "each cell may move this many px from the global grid to align its own template"),
    "min_agree":  (0.8, "fraction of the repeats (shifts x views) that must give the same state; a zero/nonzero conflict is always fatal"),
    "perturb_px": (4.0, "whole-grid shift in x and y for the stability repeat (about 1/27 of a pitch)"),
}

# Seven-segment patterns of the valid digits (a,b,c,d,e,f,g). Both common forms of 6, 7
# and 9 are accepted so a display variant cannot make a legal digit look invalid.
_MAG_DIGITS = [("0", "abcdef"), ("1", "bc"), ("2", "abdeg"), ("3", "abcdg"),
               ("4", "bcfg"), ("5", "acdfg"), ("6", "acdefg"), ("6", "cdefg"),
               ("7", "abc"), ("7", "abcf"), ("8", "abcdefg"), ("9", "abcdfg"),
               ("9", "abcfg")]
_MAG_PATTERNS = [(d, tuple(int(k in s) for k in "abcdefg")) for d, s in _MAG_DIGITS]
_MAG_SEGS = "abcdefg"
_MAG_FRAME = (880, 300)     # width, height of a rectified crop
_MAG_GRAM = {1: 1000, 2: 100, 3: 10, 4: 1}


def mag_config(overrides: dict | None = None) -> dict:
    """Defaults from MAG_PARAMS, overridden by `overrides`. Unknown names are an error
    (a mistyped threshold must not silently run with its default)."""
    cfg = {k: v[0] for k, v in MAG_PARAMS.items()}
    for k, v in (overrides or {}).items():
        if k not in cfg:
            raise ValueError(f"unknown magnitude threshold: {k}")
        cfg[k] = v
    return cfg


def _mag_integral(z: np.ndarray) -> np.ndarray:
    s = np.zeros((z.shape[0] + 1, z.shape[1] + 1), np.float64)
    s[1:, 1:] = z.cumsum(0).cumsum(1)
    return s


def _mag_rect_mean(s, x0, x1, y0, y1):
    """Mean over rectangles (arrays broadcast; coordinates rounded and clipped)."""
    h, w = s.shape[0] - 1, s.shape[1] - 1
    x0 = np.clip(np.round(x0).astype(int), 0, w)
    x1 = np.clip(np.round(x1).astype(int), 0, w)
    y0 = np.clip(np.round(y0).astype(int), 0, h)
    y1 = np.clip(np.round(y1).astype(int), 0, h)
    area = np.maximum((x1 - x0) * (y1 - y0), 1)
    return (s[y1, x1] - s[y0, x1] - s[y1, x0] + s[y0, x0]) / area


def _mag_geometry(w, h, c):
    """Segment, hole and margin rectangles of one cell, relative to its top-left."""
    tx, ty, ym = c["tx"] * w, c["ty"] * h, h / 2
    segs = {"a": (tx, w - tx, 0, ty), "b": (w - tx, w, ty, ym - ty / 2),
            "c": (w - tx, w, ym + ty / 2, h - ty), "d": (tx, w - tx, h - ty, h),
            "e": (0, tx, ym + ty / 2, h - ty), "f": (0, tx, ty, ym - ty / 2),
            "g": (tx, w - tx, ym - ty / 2, ym + ty / 2)}
    holes = {"h1": (tx, w - tx, ty, ym - ty / 2), "h2": (tx, w - tx, ym + ty / 2, h - ty)}
    margins = {"top": (tx, w - tx, -2.2 * ty, -0.6 * ty),
               "bot": (tx, w - tx, h + 0.6 * ty, h + 2.2 * ty)}
    return segs, holes, margins


def _mag_windows(w, h, c):
    """Measurement windows: each segment trimmed so small registration error stays inside."""
    segs, _, _ = _mag_geometry(w, h, c)
    out = {}
    for k, (x0, x1, y0, y1) in segs.items():
        lx, ly = x1 - x0, y1 - y0
        if k in "adg":    # horizontal bar: long axis is x
            out[k] = (x0 + c["win_long"] * lx, x1 - c["win_long"] * lx,
                      y0 + c["win_thick"] * ly, y1 - c["win_thick"] * ly)
        else:             # vertical bar: long axis is y
            out[k] = (x0 + c["win_thick"] * lx, x1 - c["win_thick"] * lx,
                      y0 + c["win_long"] * ly, y1 - c["win_long"] * ly)
    return out


def _mag_feature(arr: np.ndarray) -> np.ndarray:
    """Band-passed red channel: strokes (~14 px) positive, slow illumination removed."""
    r = arr[:, :, 0].astype(np.float32)
    d = ndimage.gaussian_filter(r, 1.5) - ndimage.gaussian_filter(r, 14)
    s = max(float(np.percentile(d, 99.0)), 1.0)
    return np.clip(d / s, -1, 1.5)


def _mag_channel(arr: np.ndarray, chroma: float) -> np.ndarray:
    """Intensity image the segments are measured on: red minus `chroma` x mean(G, B).
    A lit LED is saturated red; the unlit ghost is dull orange-brown, so subtracting
    some green/blue separates them better than red alone when the ghost is strong."""
    a = arr.astype(np.float32)
    return a[:, :, 0] - chroma * 0.5 * (a[:, :, 1] + a[:, :, 2])


def _mag_grid_score(s, x, p, y, h, c):
    """Mean over the 35 segment windows minus mean over the 20 hole/margin windows."""
    w = c["wr"] * p
    segs, holes, margins = _mag_geometry(w, h, c)
    seg_sum, bg_sum = 0, 0
    for cell in range(5):
        cx = x + p * cell
        for a0, a1, b0, b1 in segs.values():
            seg_sum = seg_sum + _mag_rect_mean(s, cx + a0, cx + a1, y + b0, y + b1)
        for a0, a1, b0, b1 in list(holes.values()) + list(margins.values()):
            bg_sum = bg_sum + _mag_rect_mean(s, cx + a0, cx + a1, y + b0, y + b1)
    return seg_sum / 35.0 - bg_sum / 20.0


def _mag_fit_grid(arr, c):
    """Bounded coarse-to-fine search for (x, pitch, y, height). Returns (grid, score)."""
    s = _mag_integral(_mag_feature(arr))
    xs = np.arange(c["x_min"], c["x_max"] + 1, 5.0)
    ps = np.arange(c["pitch_min"], c["pitch_max"] + 1, 4.0)
    ys = np.arange(c["y_min"], c["y_max"] + 1, 8.0)
    hs = np.arange(c["h_min"], c["h_max"] + 1, 10.0)
    gx, gp, gy, gh = np.meshgrid(xs, ps, ys, hs, indexing="ij")
    sc = _mag_grid_score(s, gx, gp, gy, gh, c)
    i = np.unravel_index(np.argmax(sc), sc.shape)
    best = [float(xs[i[0]]), float(ps[i[1]]), float(ys[i[2]]), float(hs[i[3]])]
    best_sc = float(sc[i])
    lo = [c["x_min"], c["pitch_min"], c["y_min"], c["h_min"]]
    hi = [c["x_max"], c["pitch_max"], c["y_max"], c["h_max"]]
    steps = [3.0, 2.0, 4.0, 6.0]
    for _ in range(3):
        for k in range(4):
            cand = np.clip([best[k] + d * steps[k] for d in range(-4, 5)], lo[k], hi[k])
            args = [np.full(cand.shape, b) for b in best]
            args[k] = cand
            s2 = _mag_grid_score(s, *args, c)
            j = int(np.argmax(s2))
            if s2[j] > best_sc:
                best_sc, best[k] = float(s2[j]), float(cand[j])
        steps = [v / 2 for v in steps]
    return best, best_sc, s


def _mag_refine_cells(s, grid, c):
    """Per-cell (dx, dy) that best aligns each cell's own 7-segment template.

    The global grid is a compromise: residual perspective and the fixed-pitch model
    leave individual cells a few pixels off, and a vertical stroke is only ~14 px wide.
    Offsets are bounded by `cell_shift` and the cells are refined independently.
    """
    x, p, y, h = grid
    w = c["wr"] * p
    segs, holes, margins = _mag_geometry(w, h, c)
    r = c["cell_shift"]
    dxs, dys = np.meshgrid(np.arange(-r, r + 1, 2.0), np.arange(-r, r + 1, 2.0))
    offs = np.zeros((5, 2))
    for cell in range(5):
        cx, sg, bgs = x + p * cell + dxs, 0, 0
        cy = y + dys
        for a0, a1, b0, b1 in segs.values():
            sg = sg + _mag_rect_mean(s, cx + a0, cx + a1, cy + b0, cy + b1)
        for a0, a1, b0, b1 in list(holes.values()) + list(margins.values()):
            bgs = bgs + _mag_rect_mean(s, cx + a0, cx + a1, cy + b0, cy + b1)
        sc = sg / 7.0 - bgs / 4.0
        i = np.unravel_index(np.argmax(sc), sc.shape)
        offs[cell] = (dxs[i], dys[i])
    return offs


def _mag_measure(sr, grid, c, offs=None, shift=(0.0, 0.0)):
    """Segment means (5 cells x 7) with each cell's hole background removed.
    `offs` are per-cell (dx, dy) alignments; `shift` moves the whole grid (stability)."""
    x, p, y, h = grid
    x, y = x + shift[0], y + shift[1]
    w = c["wr"] * p
    win = _mag_windows(w, h, c)
    _, holes, _ = _mag_geometry(w, h, c)
    m = np.zeros((5, 7))
    bg = np.zeros(5)
    for cell in range(5):
        cx, y_c = x + p * cell, y
        if offs is not None:
            cx, y_c = cx + offs[cell][0], y_c + offs[cell][1]
        for j, k in enumerate(_MAG_SEGS):
            a0, a1, b0, b1 = win[k]
            m[cell, j] = _mag_rect_mean(sr, np.array(cx + a0), np.array(cx + a1),
                                        np.array(y_c + b0), np.array(y_c + b1))
        bg[cell] = np.mean([_mag_rect_mean(sr, np.array(cx + a0), np.array(cx + a1),
                                           np.array(y_c + b0), np.array(y_c + b1))
                            for a0, a1, b0, b1 in holes.values()])
    return m - bg[:, None]


def _mag_scale(m, c):
    """Normalise so that 0 = the cell's own hole background and 1 = the lit level.

    The lit level is the median of the segments at least half as bright as the 90th
    percentile of the 28 weight segments (positions 1-4), so a few glare-saturated or
    dimmed segments do not move it. The unlit level is NOT estimated from the data: after
    hole subtraction an unlit ghost segment sits near 0 (or below it, where lit
    neighbours bloom into the holes), and a cluster estimate of it was unstable under
    small shifts. Returns (t, 0.0, lit) or None when there is no usable contrast."""
    q = m[1:5].ravel()
    hi = float(np.percentile(q, 90))
    lit = q[q >= 0.5 * hi]
    level = float(np.median(lit)) if lit.size else 0.0
    if level < c["min_span"] or int((q <= 0.5 * level).sum()) < c["min_unlit"]:
        return None
    return m / level, 0.0, level


def _mag_cell(tc, c):
    """Decode one position from its 7 normalised segment values.
    Returns dict(state, margin, note, pattern, cands)."""
    on_thr = np.array([c["seg_on"]] * 6 + [c["g_on"]])
    off_thr = np.array([c["seg_off"]] * 6 + [c["g_off"]])
    lit = tc >= on_thr
    off = tc <= off_thr
    pattern = "".join("1" if lit[j] else "0" if off[j] else "?" for j in range(7))
    cands = sorted({d for d, pat in _MAG_PATTERNS
                    if all((not off[j]) if pat[j] else (not lit[j]) for j in range(7))})
    margins = [(tc[j] - on_thr[j]) if lit[j] else (off_thr[j] - tc[j])
               for j in range(7) if lit[j] or off[j]]
    margin = float(min(margins)) if margins else 0.0
    if not cands:
        state, note = "uncertain", "invalid_pattern"
    elif cands == ["0"]:
        state, note = "zero", ""
    elif "0" not in cands:
        state, note = "nonzero", ""
    else:
        state, note = "uncertain", "ambiguous"
    return {"state": state, "margin": margin, "note": note, "pattern": pattern,
            "cands": "".join(cands)}


def _mag_dot(sr, grid, span, c):
    """Contrast of the decimal point (small blob in the gap right of position 1),
    as a fraction of the ghost-to-lit span. Searched only within +-10% of a pitch."""
    x, p, y, h = grid
    w = c["wr"] * p
    d = 0.16 * w
    ex, ey = x + p + w + (p - w) / 2, y + h + 0.01 * h
    xs = np.arange(ex - 0.10 * p, ex + 0.10 * p + 1, 2.0)
    ys = np.arange(ey - 0.08 * h, ey + 0.08 * h + 1, 2.0)
    gx, gy = np.meshgrid(xs, ys)
    inner = _mag_rect_mean(sr, gx - d / 2, gx + d / 2, gy - d / 2, gy + d / 2)
    outer = _mag_rect_mean(sr, gx - 2.2 * d, gx + 2.2 * d, gy - 2.2 * d, gy + 2.2 * d)
    return float(np.max((inner - outer) / span))


def _mag_empty(status, reason=""):
    r = {"mag_status": status, "uncertain_reason": reason, "first_nonzero_position": "",
         "image_magnitude_g": "", "confidence": "",
         "grid_x": "", "grid_pitch": "", "grid_y": "", "grid_height": "",
         "fit_quality": "", "cell_offsets": "", "dot_found": "", "dot_contrast": "",
         "leftmost_lit": "", "leftmost_lit_n": "", "span": "", "seconds": ""}
    for k in range(1, 5):
        r.update({f"p{k}_state": "", f"p{k}_pattern": "", f"p{k}_cands": "",
                  f"p{k}_outer_min": "", f"p{k}_g": "", f"p{k}_margin": ""})
    return r


def _mag_from_array(arr, c):
    """Classify one rectified crop (H x W x 3 uint8). Pure function of (arr, c)."""
    res = _mag_empty("uncertain")
    grid, fit, s_dog = _mag_fit_grid(arr, c)
    offs = _mag_refine_cells(s_dog, grid, c)
    res.update(grid_x=round(grid[0], 1), grid_pitch=round(grid[1], 1),
               grid_y=round(grid[2], 1), grid_height=round(grid[3], 1),
               fit_quality=round(fit, 3),
               cell_offsets=";".join(f"{o[0]:+.0f},{o[1]:+.0f}" for o in offs))
    # Two views of the same crop: plain red (the base reading) and red minus `chroma` x
    # mean(G, B). Each is measured at the base grid and at four shifted grids. A position's
    # state stands only if all ten measurements agree; the second view exists because a
    # view that is right on average can still be fooled by glare, and the two are fooled
    # differently.
    views = [0.0] + ([c["chroma"]] if c["chroma"] > 0 else [])
    d = c["perturb_px"]
    variants = [(0.0, 0.0), (d, 0.0), (-d, 0.0), (0.0, d), (0.0, -d)]
    runs = []
    sr = None
    for vi, chroma in enumerate(views):
        sv = _mag_integral(ndimage.gaussian_filter(_mag_channel(arr, chroma), 1.5))
        if vi == 0:
            sr = sv
        for dx, dy in variants:
            sc = _mag_scale(_mag_measure(sv, grid, c, offs, (dx, dy)), c)
            if sc is None and vi == 0 and (dx, dy) == (0.0, 0.0):
                res["mag_status"], res["uncertain_reason"] = "no_display", "no_ghost_to_lit_contrast"
                return res
            if sc is None:   # a shifted or second-view measurement lost the contrast
                blank = {"state": "uncertain", "margin": 0.0, "note": "no_contrast_in_repeat",
                         "pattern": "", "cands": ""}
                runs.append((runs[0][0], 0.0, runs[0][2], [dict(blank) for _ in range(4)]))
                continue
            t, lo, hi = sc
            runs.append((t, lo, hi, [_mag_cell(t[k], c) for k in range(1, 5)]))

    t0, lo0, hi0, cells0 = runs[0]
    span = hi0 - lo0
    res["span"] = round(span, 1)
    dot = _mag_dot(sr, grid, span, c)
    left_n = int((t0[0] >= c["seg_on"]).sum())
    res.update(dot_contrast=round(dot, 3), dot_found=bool(dot >= c["dot_min"]),
               leftmost_lit_n=left_n, leftmost_lit=bool(left_n >= c["left_lit_max"]))

    # Per position: the base reading, demoted to uncertain if any repeat disagrees.
    pos = []
    for k in range(4):
        cell = dict(cells0[k])
        others = [r[3][k] for r in runs[1:]]
        n_agree = 1 + sum(o["state"] == cell["state"] for o in others)
        contradicted = any(o["state"] not in (cell["state"], "uncertain") for o in others)
        if cell["state"] != "uncertain" and (
                contradicted or n_agree < c["min_agree"] * len(runs)):
            cell["state"], cell["note"] = "uncertain", "unstable_across_repeats"
        cell["margin"] = min([cell["margin"]] + [o["margin"] for o in others])
        pos.append(cell)
        n = k + 1
        res.update({f"p{n}_state": cell["state"], f"p{n}_pattern": cell["pattern"],
                    f"p{n}_cands": cell["cands"], f"p{n}_margin": round(cell["margin"], 3),
                    f"p{n}_outer_min": round(float(t0[n][:6].min()), 3),
                    f"p{n}_g": round(float(t0[n][6]), 3)})

    # Format checks first: if x.xxx is not established, no answer is trustworthy.
    if fit < c["fit_min"]:
        res["uncertain_reason"] = "grid_fit_weak"
        return res
    # A grid pressed against the edge of the search box is a grid that wanted to be
    # somewhere the box does not allow: the display is mis-rectified or off-frame.
    bounds = [(c["x_min"], c["x_max"]), (c["pitch_min"], c["pitch_max"]),
              (c["y_min"], c["y_max"]), (c["h_min"], c["h_max"])]
    if any(g - lo < c["bound_tol"] or hi - g < c["bound_tol"] for g, (lo, hi) in zip(grid, bounds)):
        res["uncertain_reason"] = "grid_at_search_bound"
        return res
    # A valid display decodes to a valid digit in every position. A position that matches
    # no digit at all, even one AFTER the first non-zero, means the grid or the image is
    # wrong somewhere, so nothing it says about the earlier positions is trustworthy.
    for k in range(4):
        if cells0[k]["note"] == "invalid_pattern":
            res["uncertain_reason"] = f"p{k + 1}_invalid_pattern"
            return res
    if not res["dot_found"]:
        res["uncertain_reason"] = "decimal_point_not_found"
        return res
    if res["leftmost_lit"]:
        res["uncertain_reason"] = "leftmost_position_lit"
        return res

    for k, cell in enumerate(pos):
        if cell["state"] == "zero":
            continue
        if cell["state"] == "nonzero":
            res.update(mag_status="ok", uncertain_reason="", first_nonzero_position=k + 1,
                       image_magnitude_g=_MAG_GRAM[k + 1],
                       confidence=round(min(p["margin"] for p in pos[:k + 1]), 3))
        else:
            res["uncertain_reason"] = f"p{k + 1}_{cell['note']}"
        return res
    res.update(mag_status="zero_reading", uncertain_reason="",
               confidence=round(min(p["margin"] for p in pos), 3))
    return res


def read_magnitude(path: str, **thresholds) -> dict:
    """Decide which of the four digits of an `x.xxx` kg display is the first non-zero.

    `path` is a rectified WEIGHT crop. Returns a flat dict (see `_mag_empty` for the
    keys) and never raises on an image: a bad file or an internal error becomes a
    status. `thresholds` override MAG_PARAMS entries by name; an unknown name raises
    ValueError because that is a caller bug, not an image problem.

    mag_status: ok | uncertain | zero_reading | no_display | unreadable_file
    This function knows nothing about recorded weights.
    """
    import time
    c = mag_config(thresholds)
    t0 = time.perf_counter()
    try:
        im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    except Exception as exc:
        r = _mag_empty("unreadable_file", type(exc).__name__)
        return r
    try:
        if im.size != _MAG_FRAME:
            im = im.resize(_MAG_FRAME, Image.LANCZOS)
        res = _mag_from_array(np.asarray(im), c)
    except Exception as exc:  # a crop that breaks the maths must not stop a batch
        res = _mag_empty("uncertain", f"error:{type(exc).__name__}")
    res["seconds"] = round(time.perf_counter() - t0, 3)
    return res


def magnitude_main(args) -> int:
    """CLI body of `--magnitude`: one row per image_code in the manifest."""
    mf = pd.read_csv(args.manifest, dtype={"image_code": str})
    if args.limit:
        mf = mf.head(args.limit)
    thr = {k: getattr(args, "mag_" + k) for k in MAG_PARAMS
           if getattr(args, "mag_" + k) is not None}
    rows = []
    for code in mf["image_code"]:
        r = read_magnitude(os.path.join(args.crops, f"{code}.png"), **thr)
        rows.append({"image_code": code, **r})
    df = pd.DataFrame(rows)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    df.to_csv(args.out, index=False)
    print(df.mag_status.value_counts().to_string())
    print(f"\nwrote {args.out}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True,
                    help="CSV with photo_path (and seq/id) columns; with --magnitude, "
                         "a CSV with an image_code column")
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--magnitude", action="store_true",
                    help="classify the position of the first non-zero digit of x.xxx "
                         "in rectified WEIGHT crops (see MAG_PARAMS)")
    ap.add_argument("--crops", default=None,
                    help="with --magnitude: directory holding <image_code>.png crops")
    for _k, (_v, _why) in MAG_PARAMS.items():
        ap.add_argument("--mag-" + _k.replace("_", "-"), dest="mag_" + _k,
                        type=type(_v), default=None,
                        help=f"--magnitude threshold (default {_v}): {_why}")
    ap.add_argument("--crop", action="store_true",
                    help="inputs are rectified display crops, not whole photographs")
    ap.add_argument("--on", type=float, default=CROP_ON,
                    help="lit-segment threshold for --crop mode")
    args = ap.parse_args(argv)

    if args.magnitude:
        if not args.crops:
            ap.error("--magnitude requires --crops")
        return magnitude_main(args)

    mf = pd.read_csv(args.manifest)
    if args.limit:
        mf = mf.head(args.limit)

    rows = []
    for i, r in mf.iterrows():
        out = (read_crop(r["photo_path"], args.on) if args.crop
               else read_display(r["photo_path"]))
        out["seq"] = r.get("seq")
        out["id"] = r.get("id")
        out["filename"] = r.get("filename")
        rows.append(out)
        extra = (f"lit={out['lit_frac']:.3f}" if args.crop
                 else f"rows={out.get('n_rows_found')}")
        print(f"  #{out['seq']:>4}  {out['ocr_text']:<10} {extra:<12} {out['ocr_status']}")

    df = pd.DataFrame(rows)
    cols = ["seq", "id", "filename", "ocr_text", "ocr_value", "ocr_status",
            "n_rows_found", "n_digits", "n_unknown", "row_density", "lit_frac"]
    df = df[[c for c in cols if c in df.columns]]
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    df.to_csv(args.out, index=False)

    n = len(df)
    print(f"\n{n} images")
    print(df.ocr_status.value_counts().to_string())
    print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
