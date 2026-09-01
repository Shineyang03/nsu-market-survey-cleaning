"""Remove labels from master_nsu_rename that are not NSUs at all.

WHY. The crosswalk's universe is the union of the market-survey and price-file raw
labels, so it carries some entries that are not non-standard units in any useful sense.
They generate price points and price-only cells that nothing downstream should convert,
and they clutter every diagnostic that reads the crosswalk.

`03_clean_ms.do` already drops standard-quantity labels from the MS WEIGHINGS
(`looks_standard`, 33 rows), but it never touched the crosswalk, so the same labels
still arrive on the price side. This file closes that gap and applies the same idea to
two further categories.

THREE CATEGORIES REMOVED, and why each is safe to remove:

  1. STANDARD QUANTITY. The label states its own quantity -- "bottle (500 ml)",
     "1/2 sack of rice (25kls.)", "each 10 litres of gallon". No measured conversion is
     needed: the PSPS side converts these directly from the stated quantity (issue #14).
     Detection reuses `03_clean_ms.do`'s own pattern list rather than a new one.

  2. AMBIGUOUS QUANTITY. The label mentions a standard unit but its meaning is unclear
     -- "pieces/ kilo" could be pieces-per-kilo or pieces-or-kilo; "500" states a
     magnitude with no unit. Dropped even where MS weights exist, because a conversion
     factor whose unit is ambiguous is worse than none.

  3. NOT A UNIT. Free text that records a transaction rather than a unit --
     "1 whole pigs for her grandson's birthday", "he buy cooked food for his meals",
     "1 sack is 2900/for salary/inkind". Nothing can convert these.

WHAT THIS CHANGES DOWNSTREAM. Price rows whose raw label is removed no longer match the
crosswalk. Four diagnostics previously called sys.exit on any unmatched price row -- a
deliberate tripwire against a broken join. That check is kept, but it now ignores rows
whose label is on this list, so a genuine join break still fails loudly while an
intentional removal does not. See `is_dropped_label()`, which those scripts import.

RUN
    python dofiles/00_shared/02_drop_non_nsu_labels.py            # report only
    python dofiles/00_shared/02_drop_non_nsu_labels.py --apply    # rewrite the crosswalk

OUTPUTS
    outputs/tables/master_nsu_rename.csv      filtered (with --apply)
    outputs/tables/master_nsu_rename.xlsx     filtered (with --apply)
    outputs/tables/master_rename_dropped_labels.csv   what was removed, and why
    outputs/tables/master_nsu_rename_prefilter.csv    the unfiltered original, kept so
                                                      the removal is reversible

RE-RUNNING IS SAFE, AND IS A NO-OP. The removal is applied in place, so once --apply
has run there is nothing left for a second run to find. Both outputs are then left
untouched rather than rewritten -- an empty removal report would otherwise overwrite
the record of what was removed. To rebuild the unfiltered crosswalk and run a fresh
cycle, re-run 01_build_crosswalk.py first.
"""
import re
import sys
from pathlib import Path

import pandas as pd

DC = Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel"
          r"\14 NSU Market Survey\Data Cleaning")
T = DC / "outputs" / "tables"
CSV = T / "master_nsu_rename.csv"
XLSX = T / "master_nsu_rename.xlsx"
BACKUP = T / "master_nsu_rename_prefilter.csv"
REPORT = T / "master_rename_dropped_labels.csv"

# Copied from 03_clean_ms.do's looks_standard. Kept identical on purpose: one
# definition of "states a standard quantity", used on both the MS and price sides.
STANDARD_PAT = ["(kg)", "(g)", "(l)", "(ml)", "ml", "kg", "kilo", "(25kls.)",
                "litres", "liters"]

# Category 2 -- mentions a standard unit but the meaning is not recoverable.
#
# Exact-match literals, not patterns, because each is a specific label that was read
# and judged rather than a family of labels. Every literal here must match at least
# one crosswalk row on a fresh cycle -- asserted below, so a re-spelling upstream
# fails the build instead of quietly keeping the row.
#
#   "500"           a magnitude with no unit
#   "pieces/ kilo"  pieces-per-kilo or pieces-or-kilo, unrecoverable
#   the cabbage     bundles a count, the item name and a PRICE into one label
#                   ("2 kapinutos nga cabbage/20pesos"). Whether the unit is a
#                   kapinutos, or two-of-them-for-20-pesos, is not recoverable, and
#                   the 20 pesos is a transaction not a unit. This is the ILOILO /
#                   DUEAS cabbage cell of issue #22 -- the size-based cell that had
#                   no price row. Dropping the label resolves that cell by removing
#                   it rather than by manufacturing a harmonized unit for it.
AMBIGUOUS = {"500", "pieces/ kilo", "2 kapinutos nga cabbage/20pesos"}

# ---- exact-match removals with a per-label reason -------------------------------
# These five were found by reading the PUBLISHED reference set rather than the label
# list: each had reached the deliverable as a harmonized unit that is not a unit.
# Matched exactly, not by substring, because every substring that would catch them
# also catches labels that are fine -- "galon" also matches `4 later galon',
# "gallon" also matches `gallon', `black gallon' and `5 gallon black container'.
# One entry per label, with the reason it carries into the removal report.
#
# Dropping them at the LABEL level is what removes them from both deliverables at
# once: Outcome 1 and the PSPS retro-fitting both join through the crosswalk, so a
# label that is not in the crosswalk cannot reach either.
EXACT = {
    # a bare number. Not a unit at all, and nothing states what 10 of what.
    "10":                             "ambiguous quantity",
    # count + item + PRICE in one label, exactly the cabbage case above.
    "3 for 25 pesos (putos)":         "ambiguous quantity",
    # free text describing where it was bought, with a quantity inside it.
    "pack 25 per pack in the market": "not a unit",
    # states its own standard quantity: a gallon. Spelled `galon' in the raw data.
    "1.3 galon":                      "standard quantity",
    # a count of standard containers, not a local unit.
    "6 bottles of redhorse":          "standard quantity",
}

# Category 3 -- free text describing a transaction, not a unit.
NOT_A_UNIT_PAT = ["for salary", "birthday", "he buy", "his meals", "serving of",
                  "and 10 pop", "2900", "inkind", "per bowl serving"]


def _n(s):
    return re.sub(r"\s+", " ", str(s).strip().lower())


def classify(label):
    """Return the removal reason for a raw NSU label, or None to keep it."""
    t = _n(label)
    if t in EXACT:
        return EXACT[t]
    if t in AMBIGUOUS:
        return "ambiguous quantity"
    if any(p in t for p in NOT_A_UNIT_PAT):
        return "not a unit"
    if any(p in t for p in STANDARD_PAT):
        return "standard quantity"
    return None


def is_dropped_label(label):
    """True if this raw label is one the crosswalk deliberately no longer carries.

    Imported by the price-side diagnostics so their unmatched-row tripwire can tell an
    intentional removal from a broken join.
    """
    return classify(label) is not None


def main(apply=False):
    xw = pd.read_csv(CSV, encoding="utf-8-sig", dtype=str)
    print(f"crosswalk rows: {len(xw):,}")

    # A row goes if either its raw label or its harmonized target is droppable. The
    # harmonized side matters because a raw label can be clean while the canonical
    # label it folds into is not (e.g. "500" -> "bottle 500ml").
    xw["_reason"] = xw.pull_nsu_unit.map(classify)
    xw["_reason_h"] = xw.harmonized_nsu_unit.map(classify)
    xw["_drop_reason"] = xw._reason.fillna(xw._reason_h)
    drop = xw[xw._drop_reason.notna()].copy()
    keep = xw[xw._drop_reason.isna()].copy()

    print(f"  to remove: {len(drop):>4}   keep: {len(keep):,}")
    print("\n  by reason:")
    print("   " + drop._drop_reason.value_counts().to_string().replace("\n", "\n   "))
    if "source" in drop.columns:
        print("\n  by source:")
        print("   " + drop.source.value_counts().to_string().replace("\n", "\n   "))

    print("\n  distinct raw labels removed:")
    for r, g in drop.groupby("_drop_reason"):
        print(f"    [{r}]")
        for v in sorted(g.pull_nsu_unit.dropna().unique()):
            print(f"       {v}")

    # Safety: no harmonized unit that survives may lose all its rows.
    lost = set(drop.harmonized_nsu_unit.dropna()) - set(keep.harmonized_nsu_unit.dropna())
    print(f"\n  harmonized units disappearing entirely: {len(lost)}")
    for u in sorted(lost):
        print(f"    {u}")
    orphaned = set(keep.harmonized_nsu_unit.dropna()) & set(
        drop.harmonized_nsu_unit.dropna())
    print(f"  harmonized units that keep some rows and lose others: {len(orphaned)}"
          + ("   (these need a second look)" if orphaned else ""))
    for u in sorted(orphaned):
        print(f"    {u}")

    # THIS SCRIPT MUST NOT DESTROY ITS OWN EVIDENCE. The removal is applied in place,
    # so on any run after --apply the crosswalk holds nothing left to remove and `drop'
    # is empty. Writing that empty frame to REPORT overwrites the record of which
    # labels were removed and why -- down to a bare header row. That is the only
    # machine-readable copy of it, and build_pipeline_explorer.py reads it to explain a
    # dropped label to a reader. Report-only mode did this too, so merely LOOKING at
    # the crosswalk destroyed the report.
    #
    # An empty `drop' plus an existing backup means "already applied", not "nothing was
    # ever removed", and the two must not write the same output. Re-run
    # 01_build_crosswalk.py to rebuild the unfiltered crosswalk if you want a fresh
    # removal cycle.
    already_applied = drop.empty and BACKUP.exists()

    # Every exact-match literal must have found its row. Gated on the report actually
    # being written: after --apply the labels are gone from the crosswalk, so a re-run
    # legitimately matches none of them and must not fail. Rebuild the unfiltered
    # crosswalk with 01_build_crosswalk.py to get a fresh cycle.
    if not already_applied:
        seen = set(drop.pull_nsu_unit.map(_n))
        missed = sorted((AMBIGUOUS | set(EXACT)) - seen)
        if missed:
            raise SystemExit(
                "exact-match literal(s) matched no crosswalk row: "
                + ", ".join(repr(m) for m in missed)
                + "\nThe label was probably re-spelled upstream."
                  " Fix the literal; do not delete it.")
    if already_applied:
        print(f"\nthe crosswalk is already filtered ({BACKUP.name} exists and there is"
              f" nothing left to remove).")
        print(f"kept {REPORT} as it stands -- an empty report here would overwrite the"
              f" record of what was removed.")
    else:
        drop.drop(columns=["_reason", "_reason_h"]).rename(
            columns={"_drop_reason": "drop_reason"}).to_csv(
            REPORT, index=False, encoding="utf-8-sig")
        print(f"\nwrote {REPORT}")

    if not apply:
        print("\nreport only. Re-run with --apply to rewrite the crosswalk.")
        return

    if not BACKUP.exists():
        xw.drop(columns=["_reason", "_reason_h", "_drop_reason"]).to_csv(
            BACKUP, index=False, encoding="utf-8-sig")
        print(f"wrote {BACKUP}  (unfiltered original, kept so this is reversible)")

    out = keep.drop(columns=["_reason", "_reason_h", "_drop_reason"])
    out.to_csv(CSV, index=False, encoding="utf-8-sig")
    print(f"rewrote {CSV}  ({len(out):,} rows)")
    try:
        out.to_excel(XLSX, index=False)
        print(f"rewrote {XLSX}")
    except Exception as e:
        print(f"could not rewrite {XLSX}: {e}")


if __name__ == "__main__":
    main(apply="--apply" in sys.argv)
