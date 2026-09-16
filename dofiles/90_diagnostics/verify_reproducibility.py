r"""Check that re-running the pipeline reproduces the outputs it produced last time.

WHY THIS EXISTS. "The build ran without error" is not the same as "the build produced
the same answer". Two failure modes are invisible to a normal run:

  1. NON-DETERMINISM. Stata's sort randomizes TIED observations from the sort seed, so
     a bysort on a non-unique key can put different rows in different groups from one
     run to the next. This pipeline had exactly that defect.
  2. STALE INPUTS. A step whose input path points at an old build subtree runs happily
     against months-old data. Nothing errors; the numbers are just from a dataset that
     no longer exists. Two such paths existed here.

Neither shows up unless you clear the outputs, rebuild, and compare. This file is the
compare half.

BYTE COMPARISON DOES NOT WORK, which is why this is a script and not md5sum. Stata
writes a creation timestamp into every .dta header and Excel writes one into every
.xlsx, so an identical rebuild produces different bytes every time. Comparison here is
on VALUES: each table is read, sorted on all its columns, and compared cell by cell.

HOW TO USE IT. Three commands, in this order:

    python dofiles/90_diagnostics/verify_reproducibility.py --save
        Snapshot the current build outputs to a side folder.

    (clear the build outputs, then rebuild:
     rm outputs/build/intermediate/*.dta
     rm outputs/build/deliverables/*.dta
     rm outputs/build/diagnostics/*.xlsx
     cd dofiles && StataSE-64 -e do master_outcome1.do)

    python dofiles/90_diagnostics/verify_reproducibility.py
        Compare the rebuilt outputs against the snapshot.

CLEAR THE TABLES, NOT JUST THE TEMP FOLDER. A stale output that no live step writes any
more is not detectable if it is left sitting on disk -- nothing overwrites it, so it
compares SAME and reads as reproduced. Deleting the tables first is what turns such a
file into a MISSING line. This is how three orphaned stepA_*.xlsx were found; they are
written only by the archived nsu_step_a_rungs.do. The build's .xlsx/.csv exports are all
git-tracked, so `git checkout -- outputs/build/diagnostics
outputs/build/deliverables outputs/build/summary` restores
anything the rebuild turns out not to produce.

HOW TO READ THE OUTPUT.

    SAME        every value matches. The file reproduced.
    DIFFERENT   values moved. Either the pipeline is non-deterministic, or an input
                changed, or a code change legitimately moved the number -- the diff
                names the columns and cell counts involved so it can be told apart.
    SHAPE       row or column count changed. Read this before any DIFFERENT line.
    MISSING     in the snapshot but not rebuilt. Either an orphan output that no live
                step writes any more, or a step that silently did not run.
    NEW         rebuilt but not in the snapshot.

Exit status is 1 if anything is DIFFERENT, SHAPE or MISSING, so this can be wired into
a pre-commit hook or run after any pipeline change.

THE SNAPSHOT GOES TO LOCAL TEMP, not under outputs/ and not anywhere on the Box drive.
Under outputs/ it would end up inside the next snapshot; on Box it would push ~90 MB
through the sync client on every --save. Override with --snapshot if you want to keep
one around, but put it on local disk.

THERE USED TO BE A SECOND MODE, `--reference`, byte-comparing the crosswalk build against
copies of its own outputs frozen before 01_build_crosswalk.py was split apart (issue #33).
It is retired -- see the note further down. The single confirmed copy of the crosswalk is
outputs/tables/master_nsu_rename.csv.

RUN
    python dofiles/90_diagnostics/verify_reproducibility.py --save
    python dofiles/90_diagnostics/verify_reproducibility.py
    python dofiles/90_diagnostics/verify_reproducibility.py --snapshot D:\some\dir

A LIMITATION THAT USED TO BITE, NOW FIXED AT SOURCE -- kept because the failure mode
is worth recognising if it ever returns.

This compares row-by-row in file order. `id' USED TO BE a bare `gen id = _n' in
03_clean_ms.do, assigned on whatever order the upstream merges happened to leave. Stata's m:1 merge
re-sorts the master by the merge key, so changing ANY value that sits in the
crosswalk's own sort key (province, item, municipality, harmonized_nsu_unit,
pull_nsu_unit) reorders the merge output and reassigns `id' across most of the file.

The result is that a 6-row intended change can report as 10 DIFFERENT files with
thousands of changed cells, including columns the change could not possibly touch
(vendor_id, submissiondate). That is id drift, not a regression.

FIRST FIX, WHICH WAS NOT ENOUGH: sort on a content key, then `gen id = _n'. That makes
the numbering DETERMINISTIC -- the same rows always number the same way -- and it was
verified that way, by rebuilding the crosswalk and comparing the id -> weighing map.

But `_n' is a POSITION. Determinism means "same rows, same numbers"; it does not mean a
given weighing keeps its number when the ROW SET changes. Dropping five non-unit labels
later removed 16 weighings and shifted every id after them, and nine hand corrections
keyed on `id' landed on the wrong weighings -- one setting a chicken bilog to the weight
of a camote bilog. The test had varied the processing ORDER, not the row set, so it
proved the weaker property and the stronger one was claimed.

FIXED PROPERLY: ids are now ASSIGNED ONCE and remembered.
00_shared/00a_weighing_ids.do numbers every weighing on the raw file and owns
outputs/tables/weighing_id_registry.csv; every later step looks the id up and none
creates one. Attrition cannot touch an id -- an excluded weighing keeps its number, so a
label re-admitted later returns as the same weighing. Verified against the property that
actually failed: drop 16 rows, re-merge, every survivor keeps its id.

The multiset recipe below is still the right tool when a change DOES move rows.
05_manual_corrections.do section 5 records the same fragility from the other direction:
its hand corrections are keyed on CONTENT, not on `id', because a count assertion on a
positional key proves the id exists and nothing about what it points at.

To tell the two apart, compare the row MULTISET with `id' excluded:

    cols = [c for c in old.columns if c != "id"]
    ta = old[cols].astype(str).agg("".join, axis=1).value_counts()
    tb = new[cols].astype(str).agg("".join, axis=1).value_counts()
    # rows present in one and not the other ARE the real change

If that comes back with only the rows you meant to change, the run reproduced.
"""
import argparse
import shutil
import sys
import tempfile
from pathlib import Path

import pandas as pd

DC = Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel"
          r"\14 NSU Market Survey\Data Cleaning")
BUILD = DC / "outputs" / "build"

# What a rebuild is expected to reproduce. Only the build subtree: outputs/temp/ and
# outputs/tables/ hold hand-made inputs and pre-Aug11 artefacts that no live step
# writes, and snapshotting those would report them as MISSING on every run.
#
# FIVE SUBTREES, not two, since the restructure that split `temp/' into
# `intermediate/' + `deliverables/' and `tables/' into `diagnostics/' + `summary/'.
# Each pattern below covers exactly what its predecessor covered before the files
# moved -- deliverables/*.dta is new only because six .dta files used to sit in
# temp/ and now sit beside their own .xlsx/.csv export instead.
WATCHED = [
    (BUILD / "intermediate", "*.dta"),
    (BUILD / "deliverables", "*.dta"),
    (BUILD / "deliverables", "*.xlsx"),
    (BUILD / "deliverables", "*.csv"),
    (BUILD / "diagnostics", "*.xlsx"),
    (BUILD / "diagnostics", "*.csv"),
    (BUILD / "summary", "*.csv"),
]

# Local temp, deliberately: a snapshot under outputs/ would land inside the next
# snapshot, and one on the Box drive would push ~90 MB through the sync client every
# time it is written.
DEFAULT_SNAPSHOT = Path(tempfile.gettempdir()) / "nsu_repro_snapshot"


def watched_files():
    """Every file a rebuild is expected to reproduce, as (relative path, full path)."""
    out = []
    for folder, pattern in WATCHED:
        for f in sorted(folder.glob(pattern)):
            # Skip Excel's lock files. Opening a watched workbook creates a
            # `~$name.xlsx' beside it, which is not a spreadsheet -- pandas cannot
            # determine its format and the run reports an ERROR that looks like a
            # reproducibility failure. Reading a workbook must not fail the check.
            if f.name.startswith("~$"):
                continue
            out.append((f.relative_to(BUILD).as_posix(), f))
    return out


def save(snap: Path):
    if snap.exists():
        shutil.rmtree(snap)
    n = 0
    for rel, full in watched_files():
        dest = snap / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(full, dest)
        n += 1
    print(f"snapshot: {n} files -> {snap}")
    if n == 0:
        print("  nothing to snapshot -- did the build run?")
    return 0


def read_tables(path: Path):
    """Read one output file as {sheet name: DataFrame}. One entry for non-Excel."""
    if path.suffix == ".dta":
        return {"": pd.read_stata(path, convert_categoricals=False)}
    if path.suffix == ".xlsx":
        return pd.read_excel(path, sheet_name=None, dtype=str)
    return {"": pd.read_csv(path, dtype=str, encoding="utf-8-sig")}


def norm(df):
    """Sort on all columns so a pure row-order change does not read as a value change.

    Row order is deliberately NOT compared. It is not part of any output's meaning --
    every consumer reads these by key -- and comparing it would flag the sort-seed
    noise this file exists to look past. A genuine order dependency would still show
    up, as a value difference in the column that depends on the order.
    """
    d = df.copy()
    d.columns = [str(c) for c in d.columns]
    d = d.astype(str)
    return d.sort_values(list(d.columns), kind="stable").reset_index(drop=True)


def compare_one(rel, snap_path, live_path):
    """Compare one file. Returns (verdict, detail)."""
    try:
        a = read_tables(snap_path)
        b = read_tables(live_path)
    except Exception as e:
        return "ERROR", f"could not read: {e}"

    sheets = sorted(set(a) | set(b))
    notes = []
    verdict = "SAME"
    for s in sheets:
        tag = f"[{s}] " if s else ""
        if s not in a or s not in b:
            verdict = "SHAPE"
            notes.append(f"{tag}sheet only in {'snapshot' if s in a else 'rebuild'}")
            continue
        da, db = norm(a[s]), norm(b[s])
        if list(da.columns) != list(db.columns):
            verdict = "SHAPE"
            only_a = [c for c in da.columns if c not in db.columns]
            only_b = [c for c in db.columns if c not in da.columns]
            notes.append(f"{tag}columns differ: snapshot-only {only_a}, "
                         f"rebuild-only {only_b}")
            continue
        if len(da) != len(db):
            verdict = "SHAPE"
            notes.append(f"{tag}{len(da):,} rows -> {len(db):,} rows")
            continue
        neq = (da != db)
        if neq.to_numpy().any():
            if verdict == "SAME":
                verdict = "DIFFERENT"
            cols = [c for c in da.columns if neq[c].any()]
            per_col = ", ".join(f"{c} ({int(neq[c].sum()):,} cells)" for c in cols[:6])
            more = "" if len(cols) <= 6 else f", +{len(cols) - 6} more columns"
            notes.append(f"{tag}{len(da):,} rows; changed columns: {per_col}{more}")
        else:
            notes.append(f"{tag}{len(da):,} rows x {len(da.columns)} cols match")
    return verdict, "; ".join(notes)


def compare(snap: Path):
    if not snap.exists():
        print(f"no snapshot at {snap}")
        print("run with --save before the rebuild.")
        return 1

    snap_files = {p.relative_to(snap).as_posix(): p
                  for p in sorted(snap.rglob("*"))
                  if p.is_file() and not p.name.startswith("~$")}
    live_files = dict(watched_files())

    rows = []
    for rel in sorted(set(snap_files) | set(live_files)):
        if rel not in live_files:
            rows.append((rel, "MISSING", "in snapshot, not reproduced by the rebuild"))
        elif rel not in snap_files:
            rows.append((rel, "NEW", "produced by the rebuild, not in the snapshot"))
        else:
            v, d = compare_one(rel, snap_files[rel], live_files[rel])
            rows.append((rel, v, d))

    width = max((len(r[0]) for r in rows), default=10)
    print("=" * 78)
    print(f"REPRODUCIBILITY  snapshot: {snap}")
    print("=" * 78)
    for rel, v, d in rows:
        print(f"  [{v:<9}] {rel:<{width}}  {d}")

    tally = {}
    for _, v, _ in rows:
        tally[v] = tally.get(v, 0) + 1
    print("-" * 78)
    print("  " + "   ".join(f"{k} {v}" for k, v in sorted(tally.items())))

    bad = sum(tally.get(k, 0) for k in ("DIFFERENT", "SHAPE", "MISSING", "ERROR"))
    if bad:
        print(f"\n{bad} file(s) did not reproduce. A MISSING file is either an orphan "
              f"output no live step writes, or a step that did not run.")
    else:
        print("\nevery watched output reproduced.")
    return 1 if bad else 0


# ---- the pre-split reference set: RETIRED -------------------------------------------
# There used to be a `--reference` mode here comparing the crosswalk build against copies
# of its own outputs frozen before 01_build_crosswalk.py was split apart (issue #33).
#
# It was retired because it had stopped carrying information. The baseline was six rows
# and 87 harmonized values behind the live crosswalk, every one of those differences
# INTENDED -- the non-NSU label trim and the #36 harmonization work -- so the check
# reported three failures on every run and a reader learned nothing from them. A baseline
# that is always red is indistinguishable from no baseline, except that it costs attention.
#
# What replaces it is the snapshot mode below, which compares a build against the LAST
# build rather than against a fixed past one. That is the question worth asking now: the
# split is long since done, and the risk this file exists to catch is a change today
# moving an output nobody expected it to move.
#
# The single confirmed copy of the crosswalk is outputs/tables/master_nsu_rename.csv,
# written by 01_build_crosswalk.py and read by 03_clean_ms.do.


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--save", action="store_true",
                    help="snapshot the current build outputs instead of comparing")
    ap.add_argument("--snapshot", default=str(DEFAULT_SNAPSHOT),
                    help=f"snapshot folder (default {DEFAULT_SNAPSHOT})")
    args = ap.parse_args()
    snap = Path(args.snapshot)
    sys.exit(save(snap) if args.save else compare(snap))
