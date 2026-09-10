"""How many PSPS observations does each conversion-path bucket affect? (issue #30)

The case-level counts on issue #30 say how many harmonized cells have no market-survey
weighing. They do not say how much of the PSPS consumption data those cells carry, which
is what decides whether the gap matters.

This maps every PSPS food consumption observation onto a harmonized case and reports how
many land in each bucket: convertible from the cell's own weighings, needing a province
fallback, needing an any-province fallback, or having no weight anywhere.

SCOPE MIRRORS NSU_Price.R, the script that built the price file, so the population here
is the same one the price points were computed on:
  - food only (item_type == 1)
  - the three acquisition slots fd_cons_2a / 3a / 4a, reshaped long
  - Quantity != 0
  - the standard-unit label list excluded (households answering in kg, litres, etc.)

RUN
    python dofiles/90_diagnostics/scope_psps_exposure.py

OUTPUT  outputs/tables/psps_conversion_exposure.csv
"""
import os
import re
import sys

from pathlib import Path
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    "_dropnonnsu",
    Path(__file__).resolve().parent.parent / "00_shared" / "02_drop_non_nsu_labels.py")
_mod = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
is_dropped_label = _mod.is_dropped_label

pd.set_option("display.width", 220)
BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel"
DC = BOX + r"\14 NSU Market Survey\Data Cleaning"
CONS = (BOX + r"\08 Analysis & Data\14 Wave 1_Pub\Household survey"
              r"\5_outputs\2_publication_data\2_consumption\2_consumption.dta")
# The consumption file carries municipal_code, not the municipality name.
# NSU_Price.R joins the name from this mapping before grouping; do the same
# so the key matches.
MUNMAP = (BOX + r"\08 Analysis & Data\14 Wave 1_Pub\Household survey"
                r"\3_input_data\municipal_mapping.dta")
MS = DC + r"\outputs\master_rename_build\temp\nsu_weighings_cpi.dta"
XW = DC + r"\outputs\tables\master_nsu_rename.csv"
OUT = DC + r"\outputs\tables\psps_conversion_exposure.csv"

# THE STANDARD-UNIT SET, READ FROM THE BUILD. One definition, in
# 20_psps_retrofitting/20a_psps_households.do section 1, which also carries each unit's
# gram factor and the reasoning for every entry.
#
# THIS USED TO BE A NINETEEN-ENTRY LITERAL DESCRIBED AS "NSU_Price.R's exclusion list,
# verbatim". It was not verbatim, and the discrepancy mattered. That script -- actually
# NSU_Analysis.R, in "13 Non-Standard Units & Market Survey/code/" -- has TEN entries:
#
#     Kilograms (KG), Grams (g), Gallons, Liters (L), 5-gallon blue container,
#     Cans (500 mL), Cans (330 mL), Bottle (500 ml), Bottle (330 ml), Millileters (mL)
#
# Most of the additions on our side are correct: the publication file spells the same
# metric units differently from the R's free-text `unitoth`, so "Litro (L)", "Kilo" and
# the Bote/Botelya/Lata variants genuinely belong. But "Gantang" is not a metric unit,
# and adding it under a comment claiming the list was unchanged removed 11,647 household
# rows -- a third of the NSU conversion population -- from every figure this script
# produces, and therefore from every figure on issue #30, with nothing recording that a
# decision had been taken.
#
# Gantang IS now treated as a standard unit, at 2,250 g from our own 28 weighings, but as
# a documented decision (implicit_assumptions.md A17) rather than as an unremarked edit to
# a list attributed to someone else. Reading the table keeps the two sides from diverging
# again.
def _load_std():
    fac = (DC + r"\outputs\master_rename_build\temp\standard_unit_factors.dta")
    if not os.path.exists(fac):
        raise SystemExit(
            "standard_unit_factors.dta is missing. Run 20a_psps_households.do first --\n"
            "this script no longer carries its own copy of the standard-unit list, so\n"
            "there is nothing to fall back to, deliberately.")
    f = pd.read_stata(fac, convert_categoricals=False)
    return set(f.pull_nsu_unit.astype(str))


# The one definition of the project's string normalization, imported rather than
# copied. There used to be eleven byte-identical copies of these four functions across
# 90_diagnostics/; a fix to any one of them reached none of the others. The Stata
# counterpart is nsu_normalize in 00_shared/00_globals.do and must agree with it
# character for character -- see the module docstring.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import A, nz, ni, ng


def main():
    print("reading the consumption file (large, on a synced drive -- be patient)")
    keep = None
    c = pd.read_stata(CONS, convert_categoricals=False, columns=keep)
    print(f"  consumption rows: {len(c):,}   columns: {len(c.columns)}")

    mm = pd.read_stata(MUNMAP, convert_categoricals=False)
    keepm = [x for x in ["municipal_code", "pull_municipal_city", "province"]
             if x in mm.columns]
    mm = mm[keepm].drop_duplicates("municipal_code")
    before = set(c.columns)
    c = c.merge(mm, on="municipal_code", how="left",
                suffixes=("", "_map"), validate="m:1")
    for col in ["pull_municipal_city", "province"]:
        if col not in before and col + "_map" in c.columns:
            c[col] = c[col + "_map"]
        elif col not in c.columns and col + "_map" in c.columns:
            c[col] = c[col + "_map"]
    print(f"  municipality mapping joined; unmatched municipal_code: "
          f"{int(c.pull_municipal_city.isna().sum()):,}")

    if "item_type" in c.columns:
        c = c[c.item_type == 1]
        print(f"  food only:        {len(c):,}")

    # reshape the three acquisition slots long
    frames = []
    for slot in ["2", "3", "4"]:
        q, u = f"fd_cons_{slot}a", f"fd_cons_{slot}aunit_lbl"
        if q not in c.columns or u not in c.columns:
            print(f"  slot {slot}: columns missing, skipped")
            continue
        cols = ["province", "pull_municipal_city", "cons_name", q, u]
        cols = [x for x in cols if x in c.columns]
        f = c[cols].rename(columns={q: "Quantity", u: "Unit_lbl"})
        f["slot"] = slot
        frames.append(f)
    d = pd.concat(frames, ignore_index=True)
    print(f"  reshaped long:    {len(d):,}")

    d = d[d.Quantity.notna() & (d.Quantity != 0)]
    print(f"  quantity != 0:    {len(d):,}")
    # The table is keyed on the NORMALIZED label, so the household side has to be
    # normalized before the membership test. The old literal set held raw-cased strings
    # and compared them to raw-cased labels, which worked only because both sides came
    # from the same file.
    STD = _load_std()
    print(f"  standard-unit labels read from the build: {len(STD)}")
    d["std_unit"] = d.Unit_lbl.map(nz).isin(STD)
    n_std = int(d.std_unit.sum())
    d = d[~d.std_unit]
    print(f"  standard-unit answers excluded: {n_std:,}")
    print(f"  NSU observations to convert:    {len(d):,}")

    d["prov"] = d.province.map(ng)
    d["mun"] = d.pull_municipal_city.map(ng)
    d["item"] = d.cons_name.map(ni)
    d["raw"] = d.Unit_lbl.map(nz)

    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)
    for col, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
                   ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
        xw[col] = xw[col].map(f)
    d = d.merge(xw[["province", "pull_municipal_city", "cons_name",
                    "pull_nsu_unit", "harmonized_nsu_unit"]],
                left_on=["prov", "mun", "item", "raw"],
                right_on=["province", "pull_municipal_city", "cons_name",
                          "pull_nsu_unit"], how="left")
    d["harm"] = d.harmonized_nsu_unit

    ms = pd.read_stata(MS, convert_categoricals=False)
    ms["prov"] = ms.pull_province.map(ng); ms["mun"] = ms.pull_municipal_city.map(ng)
    ms["item"] = ms.pull_item.map(ni); ms["harm"] = ms.harmonized_nsu_unit.map(nz)
    ms = ms[ms.corrected_weight.notna()]
    cells = set(ms.groupby(["prov", "mun", "item", "harm"]).size().index)
    prov_pool = ms.groupby(["prov", "item", "harm"]).size()
    any_pool = ms.groupby(["item", "harm"]).size()

    def bucket(r):
        if pd.isna(r.harm):
            return ("dropped label (not an NSU)" if is_dropped_label(r.raw)
                    else "no crosswalk entry")
        if (r.prov, r.mun, r["item"], r.harm) in cells:
            return "convertible from its own cell"
        if (r.prov, r["item"], r.harm) in prov_pool.index:
            return "province fallback available"
        if (r["item"], r.harm) in any_pool.index:
            return "any-province fallback only"
        return "no weight anywhere"

    d["bucket"] = d.apply(bucket, axis=1)

    print("\n" + "=" * 74)
    print("PSPS OBSERVATIONS BY CONVERSION PATH")
    print("=" * 74)
    v = d.bucket.value_counts()
    for k, n in v.items():
        print(f"  {k:<34} {n:>8,}   {100*n/len(d):>5.1f}%")
    print(f"  {'TOTAL':<34} {len(d):>8,}")

    print("\n  the harmonized cells behind each bucket:")
    cb = d.groupby("bucket").apply(
        lambda g: g[["prov", "mun", "item", "harm"]].drop_duplicates().shape[0],
        include_groups=False)
    print("   " + cb.to_string().replace("\n", "\n   "))

    d.groupby(["bucket", "prov", "mun", "item", "harm"], dropna=False).size() \
     .rename("n_psps_obs").reset_index().sort_values("n_psps_obs", ascending=False) \
     .to_csv(OUT, index=False, encoding="utf-8-sig")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
