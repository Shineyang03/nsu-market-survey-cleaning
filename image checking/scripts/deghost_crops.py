"""deghost_crops.py -- suppress the unlit-segment ghost on a rectified display crop.

THE PROBLEM, MEASURED RATHER THAN ASSUMED. These Micromatic displays show a faint
dark-red `8.8.8.8.8` behind whatever is lit, because unlit segments still glow. On a dim
or underexposed crop the ghost is bright enough to pass for a lit segment, and the reader
adds strokes that are not there. On the first pilot sheet that produced two wrong
readings out of seventeen -- `0.880` read where the display says `0.380`, and `0.010`
where it says `0.115`. Both were flagged uncertain by the reader, so the error was
visible, but a flagged wrong number is still a wrong number.

THE FIX IS CHEAP BECAUSE THE TWO POPULATIONS DIFFER IN BRIGHTNESS, NOT HUE. Lit and
unlit segments are both red; the lit ones are simply far brighter. So work in the red
channel, stretch it over the crop's own percentile range, and apply a gamma that pushes
the mid-tones -- where the ghost lives -- toward black while keeping the bright tail.

    blur 1.2px        sensor noise would otherwise survive the stretch as speckle
    p60 .. p99.5      the crop's OWN range. A global threshold cannot work: these
                      photographs span bright stalls and near-dark interiors.
    gamma 2.2         separates the two populations. Lower leaves ghost, higher eats
                      genuinely dim but lit segments.

VALIDATED ON THE FIVE TILES A READER COULD NOT SETTLE. All five became legible. The two
with independent ground truth -- read by the project owner off the original crops --
came back exactly right, and both were ones the reader had previously got WRONG.

THE ORIGINAL CROPS ARE NOT TOUCHED. This writes a parallel directory. The as-shot crop
stays the evidence; the de-ghosted one is a reading aid, and anything surprising in a
reading can be checked against the original.

USAGE
    python deghost_crops.py --in ../outputs/rect_all --out ../outputs/rect_all_dg
"""

from __future__ import annotations

import argparse
import os
import sys
import time

import cv2
import numpy as np

BLUR_PX = 1.2
PCT_LO, PCT_HI = 60, 99.5
GAMMA = 2.2


def deghost(im):
    """Return a de-ghosted grayscale-as-BGR copy of one crop."""
    r = im[:, :, 2].astype(np.float32)          # OpenCV is BGR; index 2 is red
    r = cv2.GaussianBlur(r, (0, 0), BLUR_PX)
    lo, hi = np.percentile(r, PCT_LO), np.percentile(r, PCT_HI)
    if hi - lo < 1:                              # a flat crop: nothing to stretch
        lo, hi = float(r.min()), float(max(r.max(), r.min() + 1))
    z = np.clip((r - lo) / (hi - lo), 0, 1) ** GAMMA
    return cv2.cvtColor((z * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", dest="dst", required=True)
    ap.add_argument("--restart", dest="resume", action="store_false", default=True,
                    help="redo crops that already have a de-ghosted copy")
    args = ap.parse_args(argv)

    if not os.path.isdir(args.src):
        print(f"no such directory: {args.src}", file=sys.stderr)
        return 2
    os.makedirs(args.dst, exist_ok=True)

    names = sorted(f for f in os.listdir(args.src) if f.endswith(".png"))
    todo = names if not args.resume else [
        f for f in names if not os.path.exists(os.path.join(args.dst, f))]
    print(f"{len(names)} crops, {len(todo)} to process")

    t0 = time.time()
    done = failed = 0
    for i, f in enumerate(todo, start=1):
        im = cv2.imread(os.path.join(args.src, f))
        if im is None:
            failed += 1
            continue
        cv2.imwrite(os.path.join(args.dst, f), deghost(im))
        done += 1
        if i % 500 == 0 or i == len(todo):
            el = time.time() - t0
            print(f"  {i}/{len(todo)}  {el/i*1000:.0f} ms/img  "
                  f"eta {(len(todo)-i)*el/i/60:.1f} min", flush=True)

    print(f"de-ghosted {done}, unreadable {failed}, in {(time.time()-t0)/60:.1f} min")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
