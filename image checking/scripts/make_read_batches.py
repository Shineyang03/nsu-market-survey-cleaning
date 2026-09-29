"""make_read_batches.py -- assign unread images to numbered reading batches, once.

WHY BATCHES RATHER THAN ONE SWEEP. Reading accuracy is not known in advance and cannot
be self-assessed: a reader scoring its own output measures its confidence, not its
accuracy. The only way to learn the error rate is for a human to re-read a sample. That
argues for reading in batches -- read a batch, have a sample of it checked, feed what the
check found into the instructions for the next batch -- rather than committing thousands
of readings to a method whose error rate nobody has measured.

The expected shape is a declining return to checking: early batches teach the reader
something (the unlit-segment ghost, which digits get confused), later ones teach it less.
When two consecutive checks find nothing new, the remaining batches can be read in
parallel without a human in the loop.

WHY THE ASSIGNMENT IS PERSISTED. Batch membership must not move. The cropper is still
running, so the unread population grows between batches; a fresh shuffle each time would
reassign images that were already read, silently double-reading some and skipping others.
So this writes a LEDGER -- one row per id, recording its batch -- and on a later run
appends only ids the ledger has never seen. An id's batch, once assigned, is permanent.

SIZES ESCALATE because the value of a human check falls as the error rate becomes known.
Five sheets is enough to catch a systematic failure mode and small enough to check
carefully; by batch four the checking is a spot sample, not a census.

USAGE
    python make_read_batches.py --track crop          # assign, print the schedule
    python make_read_batches.py --track crop --emit 1 # write batch 1's ids CSV
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "outputs", "tables"))

# sheets per batch. The tail entry repeats for every batch beyond the list.
SCHEDULE = [5, 15, 40, 60]
TAIL = 60

PER_SHEET = {"crop": 17, "photo": 9}
SOURCE = {"crop": "read_crop_ids.csv", "photo": "read_photo_ids.csv"}
SEED = "20260929"


def _order_key(img_id: str) -> str:
    """A stable pseudo-random order: hash of the id under a fixed seed.

    Sorting by this rather than by id keeps a batch from being all one market or all
    one day, which id order would produce because ids run in collection sequence.
    """
    return hashlib.sha256(f"{SEED}:{img_id}".encode()).hexdigest()


def batch_sizes(track: str, n: int) -> list[int]:
    """Sheet counts converted to image counts, extended to cover n images."""
    per = PER_SHEET[track]
    sizes, total = [], 0
    i = 0
    while total < n:
        sheets = SCHEDULE[i] if i < len(SCHEDULE) else TAIL
        sizes.append(sheets * per)
        total += sheets * per
        i += 1
    return sizes


def load_ledger(path: str) -> dict[str, int]:
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8-sig") as fh:
        return {r["id"]: int(r["batch"]) for r in csv.DictReader(fh)}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--track", choices=sorted(PER_SHEET), required=True)
    ap.add_argument("--emit", type=int, default=None,
                    help="also write this batch's ids to a CSV for the sheet builder")
    args = ap.parse_args(argv)

    src = os.path.join(OUT, SOURCE[args.track])
    if not os.path.exists(src):
        print(f"no population file: {src}", file=sys.stderr)
        return 2
    with open(src, encoding="utf-8-sig") as fh:
        ids = [r["id"] for r in csv.DictReader(fh)]

    ledger_path = os.path.join(OUT, f"read_batches_{args.track}.csv")
    ledger = load_ledger(ledger_path)

    # Only ids the ledger has never seen are assignable. Assigned ids keep their batch
    # even if they have since been read, so the record of what each batch contained
    # stays true.
    fresh = sorted((i for i in ids if i not in ledger), key=_order_key)

    if fresh:
        counts: dict[int, int] = {}
        for b in ledger.values():
            counts[b] = counts.get(b, 0) + 1
        sizes = batch_sizes(args.track, len(ledger) + len(fresh))
        cursor = 0
        for b, cap in enumerate(sizes, start=1):
            room = cap - counts.get(b, 0)
            if room <= 0:
                continue
            take = fresh[cursor:cursor + room]
            for i in take:
                ledger[i] = b
            cursor += len(take)
            if cursor >= len(fresh):
                break

        tmp = ledger_path + ".tmp"
        with open(tmp, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["id", "batch"])
            for i, b in sorted(ledger.items(), key=lambda kv: (kv[1], _order_key(kv[0]))):
                w.writerow([i, b])
        os.replace(tmp, ledger_path)
        print(f"assigned {len(fresh)} new ids; ledger now {len(ledger)}")
    else:
        print(f"no new ids; ledger holds {len(ledger)}")

    per = PER_SHEET[args.track]
    by_batch: dict[int, int] = {}
    for b in ledger.values():
        by_batch[b] = by_batch.get(b, 0) + 1
    print(f"\n{args.track} track, {per} per sheet")
    print(f"{'batch':>6} {'images':>8} {'sheets':>8}")
    for b in sorted(by_batch):
        print(f"{b:>6} {by_batch[b]:>8} {-(-by_batch[b] // per):>8}")

    if args.emit is not None:
        sel = sorted((i for i, b in ledger.items() if b == args.emit), key=_order_key)
        if not sel:
            print(f"\nbatch {args.emit} is empty", file=sys.stderr)
            return 1
        path = os.path.join(OUT, f"batch_{args.track}_{args.emit:02d}_ids.csv")
        with open(path, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["id"])
            for i in sel:
                w.writerow([i])
        print(f"\nwrote {os.path.relpath(path, HERE)}  ({len(sel)} ids)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
