"""Measure the implicit assumptions embedded in the pipeline's thresholds and rules.

WHY. docs/conversion_factor_methodology.md has an "Assumptions to keep visible" section
listing six METHODOLOGICAL assumptions. It does not cover the assumptions embedded in
code: hard-coded thresholds, tie rules, normalizer choices and fallbacks that each
encode a claim about the data. Those are invisible unless someone reads the do-files.

This script tests the ones that are testable, so the claim behind each threshold is a
measurement rather than an assertion. It decides nothing and changes nothing.

  A1  non-ASCII stripping: does dropping accented characters ever collide two names
      that are actually distinct
  A2  the "restaurant" collapse in ni(): how many distinct items it merges
  A3  KGMAX = 30: how sensitive the kg/g cut is to where it is placed
  A4  THIN = 3: how much of the reference set is flagged thin
  A5  the tercile tie rule (lower-inclusive): how often a size group comes back empty
  A6  medians as "medium": how many Outcome 1 rows get size_ord = 2 from a median
      rather than from an mp50
  A7  cell-independent harmonization: does one raw spelling ever map to two different
      harmonized units in different cells
  A8  conventional units standard within a locality: spread of the same conventional
      unit across municipalities

RUN
    python dofiles/90_diagnostics/audit_implicit_assumptions.py
"""
import re
import sys
from collections import defaultdict

import pandas as pd

BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"
TEMP = DC + r"\outputs\master_rename_build\temp"
XW = DC + r"\outputs\tables\master_nsu_rename.csv"


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def A(s):
    return str(s).encode("ascii", "ignore").decode("ascii")


def main():
    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)
    rest = pd.read_stata(TEMP + r"\nsu_weighings_cpi.dta", convert_categoricals=False)
    prelim = pd.read_stata(TEMP + r"\prelim_nsu_data.dta", convert_categoricals=False)
    ref = pd.read_stata(TEMP + r"\nsu_reference_set.dta", convert_categoricals=False)
    print(f"crosswalk {len(xw):,}   restated {len(rest):,}   prelim {len(prelim):,}"
          f"   reference set {len(ref):,}")

    # ---------------------------------------------------------------- A1
    h("A1  DOES DROPPING NON-ASCII EVER COLLIDE TWO DISTINCT NAMES")
    print("The normalizer drops non-ASCII outright rather than transliterating, so")
    print("DUENAS becomes DUEAS. That is safe only while no two genuinely different")
    print("names become identical once stripped.")
    bad = 0
    for col in ["province", "pull_municipal_city", "cons_name", "pull_nsu_unit",
                "harmonized_nsu_unit"]:
        if col not in xw.columns:
            continue
        vals = xw[col].dropna().unique()
        groups = defaultdict(set)
        for v in vals:
            groups[re.sub(r"\s+", " ", A(v).strip().lower())].add(v)
        clash = {k: v for k, v in groups.items() if len(v) > 1}
        print(f"  {col:<22} {len(vals):>5} distinct -> "
              f"{len(groups):>5} stripped;  collisions: {len(clash)}")
        for k, v in list(clash.items())[:4]:
            print(f"      '{k}'  <-  {sorted(v)}")
        bad += len(clash)
    print(f"\n  total collisions: {bad}"
          + ("   (stripping is safe on this data)" if not bad else
             "   <- distinct names are being merged"))

    # ---------------------------------------------------------------- A2
    h("A2  THE 'restaurant' COLLAPSE IN ni()")
    print("ni() maps any item containing 'restaurant' to one canonical string. That")
    print("assumes only one such item exists.")
    items = set(xw.cons_name.dropna().unique()) | set(rest.pull_item.dropna().unique())
    hits = sorted({i for i in items if "restaurant" in str(i).lower()})
    print(f"  distinct items containing 'restaurant': {len(hits)}")
    for i in hits:
        print(f"    {i}")
    print("  Merging is correct only if these are spellings of ONE item."
          if len(hits) > 1 else "  Only one -- the collapse is a no-op today.")

    # ---------------------------------------------------------------- A3
    h("A3  KGMAX = 30 -- HOW SENSITIVE IS THE kg/g CUT")
    print("correct_unit_snap.do believes a 'kg' tick at or below 30 and reads anything")
    print("above it as grams mis-ticked. The claim is that no real weight sits near the")
    print("cut. Test: how many rows would change verdict at other cut points.")
    kg = prelim[(prelim.unit == 1) & prelim.weight.notna()].weight.astype(float)
    print(f"  rows ticked kg: {len(kg):,}")
    for cut in [10, 20, 25, 30, 40, 50, 60, 100]:
        print(f"    cut {cut:>4}: {int((kg > cut).sum()):>5} read as grams,"
              f" {int((kg <= cut).sum()):>5} believed as kg")
    band = kg[(kg > 30) & (kg <= 50)]
    print(f"\n  rows in the (30, 50] band: {len(band)}"
          + ("   -- the band is empty, so 30 vs 50 changes nothing"
             if not len(band) else f"   values: {sorted(band.unique())[:10]}"))
    print("  An empty band makes the cut non-decisive TODAY. It is not a justification")
    print("  for 30 specifically; new data in the band would need a real rule.")

    # ---------------------------------------------------------------- A4
    h("A4  THIN = 3 -- HOW MUCH OF THE REFERENCE SET IS FLAGGED THIN")
    col = "d_thin" if "d_thin" in ref.columns else None
    ncol = next((c for c in ["n_g", "n_obs", "n"] if c in ref.columns), None)
    if col:
        print(f"  reference rows: {len(ref):,}")
        print(f"  flagged thin:   {int(ref[col].sum()):,}"
              f"   ({100*ref[col].mean():.1f}%)")
    if ncol:
        print(f"\n  distribution of {ncol} (weighings behind each published value):")
        print("   " + ref[ncol].describe()[["min", "25%", "50%", "75%", "max"]]
              .to_string().replace("\n", "\n   "))
        for t in [2, 3, 4, 5, 10]:
            print(f"    threshold {t}: {int((ref[ncol] < t).sum()):>5} rows flagged"
                  f" ({100*(ref[ncol] < t).mean():.1f}%)")
    if not col and not ncol:
        print("  neither d_thin nor an n column present -- skipped")

    # ---------------------------------------------------------------- A5
    h("A5  THE TERCILE TIE RULE -- HOW OFTEN A SIZE GROUP COMES BACK EMPTY")
    print("The cut is lower-inclusive (w <= cut1 | cut1 < w <= cut2 | w > cut2).")
    print("Weights are whole grams, so ties on a cut are common and a group can empty.")
    print("nsu_reference_set.do detects this and reports the case rather than patching.")
    if "size_ord" in ref.columns:
        CELL = [c for c in ["pull_province", "pull_municipal_city", "pull_item",
                            "harmonized_nsu_unit", "corrected_unit"] if c in ref.columns]
        sizes = ref[ref.size_ord.isin([1, 2, 3])]
        per = sizes.groupby(CELL, dropna=False).size_ord.nunique()
        print(f"\n  size-based reference cases: {len(per):,}")
        print("  published size groups per case:")
        print("   " + per.value_counts().sort_index().to_string().replace("\n", "\n   "))
        print("  A case that recorded 3 field labels but publishes 2 lost a group to a")
        print("  tie. Cross-check against outputs/.../ref_underfilled_sizes.xlsx.")
    else:
        print("  size_ord absent -- skipped")

    # ---------------------------------------------------------------- A6
    h("A6  MEDIANS PUBLISHED AS 'MEDIUM'")
    print("nsu_reference_set.do sec 2b sends mp50 AND municipality median AND province")
    print("median all to size_ord = 2. A median is a central tendency, not a size.")
    pq = rest[(rest.weighing_approach == 2)]
    lbl = {5: "mp25", 6: "mp50", 7: "mp75", 8: "mun_median", 9: "prov_median",
           10: "uniq6", 11: "uniq7"}
    v = pq.item_nsu_hetero_type.map(lbl).value_counts()
    print("\n  price-quantity weighings by rung:")
    print("   " + v.to_string().replace("\n", "\n   "))
    med = int(v.get("mun_median", 0) + v.get("prov_median", 0))
    mp50 = int(v.get("mp50", 0))
    print(f"\n  rows landing on size_ord = 2:  {med + mp50:,}")
    print(f"    from a real mp50:            {mp50:,}")
    print(f"    from a median (not a size):  {med:,}"
          f"   ({100*med/max(1, med+mp50):.0f}% of the 'medium' rows)")

    # ---------------------------------------------------------------- A7
    h("A7  IS HARMONIZATION REALLY CELL-INDEPENDENT")
    print("master_rename.md sec 3 states the fold is item-conditioned but")
    print("cell-independent: one raw spelling of one item maps to ONE harmonized unit")
    print("everywhere. Tested directly.")
    if {"cons_name", "pull_nsu_unit", "harmonized_nsu_unit"} <= set(xw.columns):
        g = xw.groupby(["cons_name", "pull_nsu_unit"]).harmonized_nsu_unit.nunique()
        viol = g[g > 1]
        print(f"  (item, raw spelling) pairs: {len(g):,}")
        print(f"  mapping to >1 harmonized unit: {len(viol)}"
              + ("   (rule holds)" if not len(viol) else "   <- NOT cell-independent"))
        for k in list(viol.index)[:6]:
            got = sorted(xw[(xw.cons_name == k[0])
                            & (xw.pull_nsu_unit == k[1])].harmonized_nsu_unit.unique())
            print(f"    {k[0][:40]} / '{k[1]}' -> {got}")
    else:
        print("  crosswalk columns missing -- skipped")

    # ---------------------------------------------------------------- A8
    h("A8  ARE CONVENTIONAL UNITS STANDARD ACROSS MUNICIPALITIES")
    print("Assumption 6 in the methodology says conventional units may vary across")
    print("municipalities and that this is testable wherever the MS weighed the same")
    print("unit in several. Doing that test.")
    cv = rest[(rest.weighing_approach == 1) & rest.corrected_weight.notna()]
    per = cv.groupby(["pull_item", "harmonized_nsu_unit", "corrected_unit",
                      "pull_municipal_city"], dropna=False).corrected_weight.median()
    across = per.groupby(level=[0, 1, 2]).agg(["size", "min", "max"])
    multi = across[across["size"] > 1].copy()
    multi["ratio"] = multi["max"] / multi["min"].replace(0, pd.NA)
    print(f"\n  conventional (item, unit) combos weighed in >1 municipality: {len(multi)}")
    if len(multi):
        print("  ratio of the highest municipal median to the lowest:")
        print("   " + multi.ratio.describe()[["50%", "75%", "max"]]
              .to_string().replace("\n", "\n   "))
        print(f"    combos varying >=1.5x across municipalities:"
              f" {int((multi.ratio >= 1.5).sum())}")
        print(f"    combos varying >=2x:"
              f" {int((multi.ratio >= 2).sum())}")
        print("\n  worst 8:")
        print("   " + multi.sort_values("ratio", ascending=False).head(8)
              .to_string().replace("\n", "\n   "))


if __name__ == "__main__":
    main()
