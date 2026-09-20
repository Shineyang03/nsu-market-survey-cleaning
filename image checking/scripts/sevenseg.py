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


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True,
                    help="CSV with photo_path (and seq/id) columns")
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args(argv)

    mf = pd.read_csv(args.manifest)
    if args.limit:
        mf = mf.head(args.limit)

    rows = []
    for i, r in mf.iterrows():
        out = read_display(r["photo_path"])
        out["seq"] = r.get("seq")
        out["id"] = r.get("id")
        out["filename"] = r.get("filename")
        rows.append(out)
        print(f"  #{out['seq']:>4}  {out['ocr_text']:<10} "
              f"rows={out['n_rows_found']:<3} {out['ocr_status']}")

    df = pd.DataFrame(rows)
    cols = ["seq", "id", "filename", "ocr_text", "ocr_value", "ocr_status",
            "n_rows_found", "n_digits", "n_unknown", "row_density"]
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
