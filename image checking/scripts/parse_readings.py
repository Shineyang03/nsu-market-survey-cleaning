"""parse_readings.py -- validate reader output and turn it into a tidy table.

WHAT IT DOES. Readers emit one JSON object per photograph, keyed on the label printed
on the contact-sheet tile. This validates those objects against the manifest, joins
them back to `id`, and writes one row per (reader, image).

IT IS A GATE, NOT A CONVERTER. Every check below exists because the corresponding
failure is silent and produces plausible, wrong data:

  * A LABEL THAT IS NOT ON THE SHEET the reader was given. The danger is not a typo;
    it is a reader that lost its place and started numbering from the grid position.
    Rejected, never guessed at.
  * A DUPLICATE LABEL within one reader's output for one sheet. Two readings of one
    tile means the reader double-counted, and silently keeping the first would hide it.
  * A MISSING TILE. Reported per sheet, because a reader that quietly skips the hard
    images produces a high agreement rate on the easy remainder.
  * AN OUT-OF-VOCABULARY photo_type or display_legible. A reader inventing a category
    is a reader that has stopped following the instrument.
  * A display_text THAT LOOKS PARSED RATHER THAN COPIED -- "0.8" where the display
    shows "0.800". This cannot be detected on one reading; it is why trailing zeros
    are preserved verbatim and why decimal recovery is scored separately downstream.

UNBLINDING HAPPENS HERE AND NOWHERE EARLIER. The manifest carries the id; the readers
never saw it. Nothing in this file may be fed back to a reader.

USAGE
    python parse_readings.py --tag calib_v1 --out ../outputs/qc/readings_calib_v1.csv
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
IMGCHK = os.path.dirname(HERE)
SHEETDIR = os.path.join(IMGCHK, "outputs", "sheets")
RAWDIR = os.path.join(IMGCHK, "outputs", "readings", "raw")

PHOTO_TYPES = {
    "scale_with_item", "scale_no_item", "item_no_scale",
    "label_closeup", "jug_graduated", "other", "unreadable",
}
LEGIBLE = {"clear", "probable", "ambiguous", "not_visible"}
UNITS_SHOWN = {"kg", "g", "none_shown", "indeterminate", None}

OBJ_RE = re.compile(r"\{.*?\}")


def extract_objects(text: str):
    """Pull JSON objects out of a reader's output.

    Readers are told to emit bare JSON lines, but a stray code fence or a sentence of
    preamble should not cost a whole batch. Anything that does not parse is returned
    as a parse failure rather than dropped, so the count of bad lines is visible.
    """
    good, bad = [], []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("```"):
            continue
        if not s.startswith("{"):
            m = OBJ_RE.search(s)
            if not m:
                continue
            s = m.group(0)
        try:
            good.append(json.loads(s))
        except json.JSONDecodeError:
            bad.append(s[:160])
    return good, bad


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True, help="e.g. calib_v1")
    ap.add_argument("--out", required=True)
    ap.add_argument("--raw-dir", default=None)
    ap.add_argument("--prompt-version", default="v1.0")
    ap.add_argument("--expect-readers", type=int, default=None,
                    help="how many readers every image should have. Defaults to the "
                         "observed maximum, which flags relative gaps but cannot "
                         "notice that EVERY reader missed the same image.")
    args = ap.parse_args(argv)

    mpath = os.path.join(SHEETDIR, f"manifest_{args.tag}.csv")
    if not os.path.exists(mpath):
        print(f"manifest not found: {mpath}", file=sys.stderr)
        return 2
    mf = pd.read_csv(mpath)
    mf["label"] = mf.seq.map(lambda s: f"{int(s):04d}")
    by_label = mf.set_index("label")

    rawdir = args.raw_dir or os.path.join(RAWDIR, args.tag)
    files = sorted(glob.glob(os.path.join(rawdir, "*.jsonl")))
    if not files:
        print(f"no reader output in {rawdir}", file=sys.stderr)
        return 2

    rows, problems = [], []
    for fp in files:
        reader = os.path.splitext(os.path.basename(fp))[0]
        with open(fp, "r", encoding="utf-8") as fh:
            objs, bad = extract_objects(fh.read())
        for b in bad:
            problems.append({"reader": reader, "kind": "unparseable_line", "detail": b})

        seen = set()
        for o in objs:
            lab = str(o.get("label", "")).strip().lstrip("#").zfill(4)
            if lab not in by_label.index:
                problems.append({"reader": reader, "kind": "label_not_in_manifest",
                                 "detail": lab})
                continue
            if lab in seen:
                problems.append({"reader": reader, "kind": "duplicate_label",
                                 "detail": lab})
                continue
            seen.add(lab)

            pt = o.get("photo_type")
            if pt not in PHOTO_TYPES:
                problems.append({"reader": reader, "kind": "bad_photo_type",
                                 "detail": f"{lab}: {pt}"})
            lg = o.get("display_legible")
            if lg is not None and lg not in LEGIBLE:
                problems.append({"reader": reader, "kind": "bad_display_legible",
                                 "detail": f"{lab}: {lg}"})

            m = by_label.loc[lab]
            dt = o.get("display_text")
            dt = None if dt in ("", None) else str(dt).strip()

            rows.append({
                "reader": reader,
                "prompt_version": args.prompt_version,
                "tag": args.tag,
                "label": lab,
                "sheet": m["sheet"],
                "id": int(m["id"]),
                "filename": m["filename"],
                "img_sha16": m.get("img_sha16", ""),
                "photo_type": pt,
                "item_on_scale": o.get("item_on_scale"),
                "display_text": dt,
                # `has_decimal` is recorded separately from the text because decimal
                # recovery is scored on its own -- folding it into a string match
                # would let a systematic miss hide inside a high agreement rate.
                "has_decimal": (None if dt is None else ("." in dt)),
                "display_legible": lg,
                "display_unit_shown": o.get("display_unit_shown"),
                "package_text": o.get("package_text"),
                "package_qty": o.get("package_qty"),
                "package_unit": o.get("package_unit"),
                "notes": o.get("notes", ""),
            })

        # Missing tiles WITHIN a sheet the reader touched. This alone is not enough --
        # see the coverage check after the loop, which catches a sheet skipped whole.
        touched = {r["sheet"] for r in rows if r["reader"] == reader}
        missing = set(by_label.index[by_label.sheet.isin(touched)]) - seen
        for lab in sorted(missing):
            problems.append({"reader": reader, "kind": "missing_tile", "detail": lab})

    df = pd.DataFrame(rows)

    # ---- COVERAGE, checked against the manifest rather than against what a reader
    # happened to touch. The per-reader check above cannot see a sheet that was
    # skipped ENTIRELY: with no readings from it, the sheet is not in `touched`, so
    # none of its tiles are counted as missing. That is exactly how four images went
    # unread while the parser reported only one problem.
    #
    # An unread image is not a cosmetic gap. It shrinks the agreement denominator
    # silently, and a reader that skips the images it finds hardest would leave a
    # high agreement rate computed on the easy remainder.
    if len(df):
        cov = df.groupby("id").reader.nunique()
        expect = args.expect_readers or int(cov.max())
        short = cov[cov < expect]
        for img_id, n in short.items():
            problems.append({"reader": "(coverage)", "kind": "image_under_read",
                             "detail": f"id {img_id}: {n} of {expect} readers"})
        unread = set(mf.id) - set(df.id)
        for img_id in sorted(unread):
            problems.append({"reader": "(coverage)", "kind": "image_never_read",
                             "detail": f"id {img_id}"})

        sheets_seen = df.groupby("reader").sheet.nunique()
        print("\nsheets per reader:")
        print(sheets_seen.to_string())

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    df.to_csv(args.out, index=False)

    pr = pd.DataFrame(problems)
    ppath = args.out.replace(".csv", "_problems.csv")
    pr.to_csv(ppath, index=False)

    print(f"readers            {df.reader.nunique() if len(df) else 0}")
    print(f"readings           {len(df)}")
    print(f"distinct images    {df.id.nunique() if len(df) else 0} "
          f"of {mf.id.nunique()} in the manifest")
    if len(df):
        print("\nper reader:")
        print(df.groupby("reader").agg(n=("id", "size"),
                                       imgs=("id", "nunique")).to_string())
        print("\nphoto_type:")
        print(df.photo_type.value_counts(dropna=False).to_string())
    if len(pr):
        print("\nPROBLEMS:")
        print(pr.kind.value_counts().to_string())
        print(f"detail -> {ppath}")
    else:
        print("\nno validation problems")
    print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
