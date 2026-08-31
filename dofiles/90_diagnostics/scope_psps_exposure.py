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

# NSU_Price.R's exclusion list, verbatim: labels where the household already answered
# in a standard unit, so no NSU conversion is needed.
STD = {"Grams (g)", "Kilograms (Kg)", "Grams", "Kilo", "Kilograms", "Kilos",
       "5-gallon blue container", "Litro (L)", "Liters", "Liters (L)",
       "Millileters (mL)", "Bote (330ml)", "Bote (500ml)", "Botelya (330ml)",
       "Botelya (500ml)", "Gallons", "Gantang", "Lata (330 ml)", "Lata (500 ml)"}


def A(s): return str(s).encode("ascii", "ignore").decode("ascii")
def nz(s): return re.sub(r"\s+", " ", A(s).lower().strip())
def ng(s): return re.sub(r"\s+", " ", A(s).strip().upper())


def ni(s):
    s = nz(s)
    return "drinks at restaurant, hotel, cafe, or kiosk" if "restaurant" in s else s


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
    d["std_unit"] = d.Unit_lbl.isin(STD)
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
