"""rectify_display.py -- cut the Micromatic WEIGHT display out of a market photograph
by homography, so a reader sees the display instead of the stall.

THE PROBLEM THIS SOLVES. `sevenseg.py` had to FIND the display in a full 8 MP photograph
using a red-pixel mask, in a scene containing carrots, tarpaulins, crates and brake
lights. That search is what failed, and its confident wrong answers -- `88` where the
display reads `0.430` -- were worse than its failures. The README's own verdict was that
one method had been tried and it was the weakest plausible one.

THE OBSERVATION THAT MAKES THIS EASY. Every photograph shows the SAME SCALE: one rigid,
planar front panel carrying an identical keypad (M+ 7 8 9 TARE / M1 4 5 6 ZERO /
M2 1 2 3 SAVE / M3 0 . C CHANGE) and the MICROMATIC logo. A keypad of high-contrast
glyphs on a flat panel is the textbook case for feature matching. So this file does not
look for the display at all -- it matches the KEYPAD, which is easy and textured, solves
a homography, and derives the display from it, which is exact. The display and the
keypad are coplanar, so one homography serves both.

WHAT IT IS FOR, AND IT IS TWO THINGS.

  1. A rectified crop is a far better thing to show a READER -- model or human -- than a
     tile of a whole market photograph. The display fills the frame, upright and at
     known scale. This is a presentation change, and its effect on reading accuracy is
     measurable: run the blind instrument over both and compare.
  2. It is the precondition for a deterministic segment decoder. Decoding seven
     segments is easy once the digits are at known positions in a canonical rectangle,
     and impossible while they are somewhere in a photograph of a stall.

WHAT IT DOES NOT DO. It does not read anything. It finds and rectifies; what the digits
say is the next step's problem.

THE REFERENCE FRAME. One photograph is the reference, chosen because its panel is
frontal and legible. Two boxes are defined in ITS pixel coordinates -- the panel, which
is what gets matched on, and the WEIGHT row, which is what gets cut out. Every other
photograph is mapped into that frame. Changing the reference image means re-measuring
both boxes; they are not derivable from anything else.

MEASURED, on the 40 human-validated photographs: 38 found a display, with RANSAC inlier
counts of 27-344. The two failures were reported, not silently skipped -- a rectifier
that quietly returns the wrong crop is the sevenseg failure mode again.

USAGE
    python rectify_display.py --ids ../outputs/tables/some_ids.csv --out ../outputs/rect
    python rectify_display.py --all --out ../outputs/rect
"""

from __future__ import annotations

import argparse
import csv
import os
import sys

import cv2
import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
IMGCHK = os.path.dirname(HERE)
BRIDGE = os.path.join(IMGCHK, "outputs", "bridge", "photo_id_bridge.csv")

# The reference photograph, and two boxes in ITS pixel coordinates (2448 x 3264).
REF_CODE = "1774487698787"
PANEL = (200, 2180, 2150, 3150)      # x0,y0,x1,y1 -- front panel: display + keypad
DISPLAY = (300, 2255, 1175, 2550)    # x0,y0,x1,y1 -- the WEIGHT row alone
OUT_W, OUT_H = 880, 300              # canonical rectified size

# Below this many RANSAC inliers the homography is not trusted and NOTHING is written.
# A wrong crop that looks plausible is the failure this whole approach exists to avoid.
MIN_INLIERS = 12
RATIO = 0.75                         # Lowe ratio test
RANSAC_PX = 6.0


def build_reference(path: str):
    im = cv2.imread(path)
    if im is None:
        raise SystemExit(f"cannot read the reference photograph: {path}")
    x0, y0, x1, y1 = PANEL
    panel = im[y0:y1, x0:x1]
    sift = cv2.SIFT_create(nfeatures=4000)
    kp, des = sift.detectAndCompute(cv2.cvtColor(panel, cv2.COLOR_BGR2GRAY), None)
    # shift keypoints back into full-reference coordinates, so the DISPLAY box and the
    # keypoints live in one frame
    for k in kp:
        k.pt = (k.pt[0] + x0, k.pt[1] + y0)
    return kp, des


def rectify(path, refkp, refdes, sift, matcher):
    """Return (crop, status). crop is None whenever the display was not located."""
    im = cv2.imread(path)
    if im is None:
        return None, "unreadable"
    kp, des = sift.detectAndCompute(cv2.cvtColor(im, cv2.COLOR_BGR2GRAY), None)
    if des is None or len(kp) < MIN_INLIERS:
        return None, "no features"
    raw = matcher.knnMatch(des, refdes, k=2)
    good = [m for m, n in raw if m.distance < RATIO * n.distance]
    if len(good) < MIN_INLIERS:
        return None, f"only {len(good)} good matches"
    src = np.float32([kp[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
    dst = np.float32([refkp[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
    H, mask = cv2.findHomography(dst, src, cv2.RANSAC, RANSAC_PX)   # REF -> TARGET
    if H is None:
        return None, "no homography"
    inl = int(mask.sum())
    if inl < MIN_INLIERS:
        return None, f"only {inl} inliers"
    x0, y0, x1, y1 = DISPLAY
    quad = np.float32([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]).reshape(-1, 1, 2)
    tq = cv2.perspectiveTransform(quad, H)
    canon = np.float32([[0, 0], [OUT_W, 0], [OUT_W, OUT_H], [0, OUT_H]])
    M = cv2.getPerspectiveTransform(tq.reshape(4, 2), canon)
    return cv2.warpPerspective(im, M, (OUT_W, OUT_H)), f"ok inliers={inl}/{len(good)}"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default="", help="CSV with an `id' column")
    ap.add_argument("--all", action="store_true", help="every photograph in the bridge")
    ap.add_argument("--out", required=True)
    ap.add_argument("--status", default="", help="where to write the per-image status")
    args = ap.parse_args(argv)

    if not args.ids and not args.all:
        print("give --ids or --all", file=sys.stderr)
        return 2

    bridge = pd.read_csv(BRIDGE)
    bridge["image_code"] = bridge.filename.str.replace(".jpg", "", regex=False)
    if args.ids:
        want = pd.read_csv(args.ids)[["id"]]
        bridge = bridge.merge(want, on="id", how="inner")

    ref_row = bridge[bridge.image_code == REF_CODE]
    if ref_row.empty:
        full = pd.read_csv(BRIDGE)
        full["image_code"] = full.filename.str.replace(".jpg", "", regex=False)
        ref_row = full[full.image_code == REF_CODE]
    if ref_row.empty:
        print(f"the reference photograph {REF_CODE} is not in the bridge",
              file=sys.stderr)
        return 2

    refkp, refdes = build_reference(ref_row.iloc[0]["photo_path"])
    print(f"reference {REF_CODE}: {len(refkp)} keypoints on the panel")

    os.makedirs(args.out, exist_ok=True)
    sift = cv2.SIFT_create(nfeatures=8000)
    matcher = cv2.BFMatcher()

    rows, ok = [], 0
    for _, r in bridge.iterrows():
        crop, status = rectify(r["photo_path"], refkp, refdes, sift, matcher)
        if crop is not None:
            cv2.imwrite(os.path.join(args.out, f"{r['image_code']}.png"), crop)
            ok += 1
        rows.append({"id": r["id"], "image_code": r["image_code"], "status": status})

    print(f"rectified {ok} of {len(bridge)}")
    dest = args.status or os.path.join(args.out, "_status.csv")
    with open(dest, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["id", "image_code", "status"])
        w.writeheader()
        w.writerows(rows)
    print("status ->", dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
