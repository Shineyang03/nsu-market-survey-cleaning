"""merge_reader_output.py -- assemble per-sheet reader files and say what is missing.

WHY READERS CHECKPOINT PER SHEET. A reader that writes its whole output in one call at
the end loses everything if it dies, and these readers do die: three were killed
mid-assignment by an account rate limit and one by a stalled stream, each taking roughly
a sheet's worth of completed work per minute down with it. The run is long enough that
being interrupted is the normal case, not the exceptional one.

So a reader writes one file per sheet, as soon as that sheet is read:

    outputs/qc/b03/reader_a/sheet_001.jsonl
    outputs/qc/b03/reader_a/sheet_002.jsonl
    ...

A death then costs at most the sheet in progress. A restart skips every sheet whose file
already exists and carries on, which is why the files are per sheet rather than appended
to one handle: appending needs a read-modify-write, and a reader killed inside that window
corrupts what it had.

THIS SCRIPT DOES NOT DECIDE ANYTHING. It concatenates, checks, and reports. The checks are
the point -- a merged file that silently lacks forty labels looks exactly like a complete
one, and the labels are what join a reading back to a weighing.

USAGE
    python merge_reader_output.py --batch b03 --reader a
    python merge_reader_output.py --batch b03 --reader a --expect 0001-0144
"""

from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
QC = os.path.normpath(os.path.join(HERE, "..", "outputs", "qc"))

REQUIRED = {"label", "display_text", "display_legible", "display_unit_shown", "notes"}


def parse_range(spec: str) -> list[str]:
    lo, hi = spec.split("-")
    return [f"{i:04d}" for i in range(int(lo), int(hi) + 1)]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", required=True, help="e.g. b03")
    ap.add_argument("--reader", required=True, help="e.g. a")
    ap.add_argument("--expect", default=None,
                    help="label range the reader was assigned, e.g. 0001-0144")
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)

    src = os.path.join(QC, args.batch, f"reader_{args.reader}")
    if not os.path.isdir(src):
        print(f"no such directory: {src}", file=sys.stderr)
        return 2

    parts = sorted(f for f in os.listdir(src) if f.endswith(".jsonl"))
    rows, bad = [], []
    for f in parts:
        with open(os.path.join(src, f), encoding="utf-8") as fh:
            for n, line in enumerate(fh, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except json.JSONDecodeError as exc:
                    bad.append(f"{f}:{n} not JSON ({exc.msg})")
                    continue
                missing = REQUIRED - set(r)
                if missing:
                    bad.append(f"{f}:{n} missing {sorted(missing)}")
                    continue
                rows.append(r)

    labels = [r["label"] for r in rows]
    dupes = sorted({x for x in labels if labels.count(x) > 1})

    print(f"{len(parts)} sheet files, {len(rows)} readings")
    if bad:
        print(f"\n{len(bad)} malformed line(s):")
        for b in bad[:20]:
            print("  " + b)

    gaps: list[str] = []
    if args.expect:
        want = parse_range(args.expect)
        have = set(labels)
        gaps = [l for l in want if l not in have]
        extra = sorted(have - set(want))
        print(f"expected {len(want)} labels {args.expect}")
        print(f"  present {len(want) - len(gaps)}, MISSING {len(gaps)}")
        if gaps:
            print("  missing: " + ", ".join(gaps[:40])
                  + (" ..." if len(gaps) > 40 else ""))
        if extra:
            print(f"  UNEXPECTED labels: {', '.join(extra[:20])}")
    if dupes:
        print(f"  DUPLICATE labels: {', '.join(dupes[:20])}")

    out = args.out or os.path.join(QC, f"{args.batch}_reader_{args.reader}.jsonl")
    # Written even when incomplete: partial work is worth keeping, and the counts above
    # are what tell a reader of this output whether to trust it as a whole batch.
    with open(out, "w", encoding="utf-8") as fh:
        for r in sorted(rows, key=lambda x: x["label"]):
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"\nwrote {os.path.relpath(out, HERE)}")

    if bad or dupes or gaps:
        print("\nINCOMPLETE OR MALFORMED -- do not treat this as a finished batch.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
