"""Remove labels from master_nsu_rename that are not NSUs at all.

WHY. The crosswalk's universe is the union of the market-survey and price-file raw
labels, so it carries some entries that are not non-standard units in any useful sense.
They generate price points and price-only cells that nothing downstream should convert,
and they clutter every diagnostic that reads the crosswalk.

`cleaning_Aug11.do` already drops standard-quantity labels from the MS WEIGHINGS
(`looks_standard`, 33 rows), but it never touched the crosswalk, so the same labels
still arrive on the price side. This file closes that gap and applies the same idea to
two further categories.

THREE CATEGORIES REMOVED, and why each is safe to remove:

  1. STANDARD QUANTITY. The label states its own quantity -- "bottle (500 ml)",
     "1/2 sack of rice (25kls.)", "each 10 litres of gallon". No measured conversion is
     needed: the PSPS side converts these directly from the stated quantity (issue #14).
     Detection reuses `cleaning_Aug11.do`'s own pattern list rather than a new one.

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

# Copied from cleaning_Aug11.do's looks_standard. Kept identical on purpose: one
# definition of "states a standard quantity", used on both the MS and price sides.
STANDARD_PAT = ["(kg)", "(g)", "(l)", "(ml)", "ml", "kg", "kilo", "(25kls.)",
                "litres", "liters"]

# Category 2 -- mentions a standard unit but the meaning is not recoverable.
AMBIGUOUS = {"500", "pieces/ kilo"}

# Category 3 -- free text describing a transaction, not a unit.
NOT_A_UNIT_PAT = ["for salary", "birthday", "he buy", "his meals", "serving of",
                  "and 10 pop", "2900", "inkind", "per bowl serving"]


def _n(s):
    return re.sub(r"\s+", " ", str(s).strip().lower())


def classify(label):
    """Return the removal reason for a raw NSU label, or None to keep it."""
    t = _n(label)
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
