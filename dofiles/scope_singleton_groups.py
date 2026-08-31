"""Hetero-groups resting on a single market-survey weighing.

THE CONCERN. Both outcomes publish a weight per
    province x municipality x item x harmonized_nsu_unit x corrected_unit x hetero_group
where the hetero-group is a size (small / medium / large) on the size-based branch, a
price rung on the price-quantity branch, and the whole case on the conventional branch.
Where a group rests on ONE weighing there is no way to tell a representative unit from
an outlier: if ALTAVAS has a single "large bilog" cabbage at 900 g, nothing in the data
says whether that is a typical large or a freak.

This is distinct from `d_thin` in nsu_reference_set.do, which flags fewer than THIN = 3
weighings behind a PUBLISHED reference row. That count is taken after re-terciling, so
it describes the published groups. This file counts the raw field groups the pipeline
starts from, before any re-cut, which is the level at which an outlier enters.

WHAT THIS SCRIPT DOES. It measures; it decides nothing.

  Q1  how many (case x hetero-group) cells rest on exactly one weighing, by branch
  Q2  how exposed each outcome is -- how many published rows trace back to a singleton
  Q3  whether a singleton is plausibly an outlier: how far it sits from the same
      item x harmonized unit x hetero-group measured elsewhere in the province
  Q4  the cases where EVERY group is a singleton, which have no internal check at all

RUN
    python dofiles/scope_singleton_groups.py

OUTPUT  outputs/tables/singleton_hetero_groups.csv
"""
import re

import pandas as pd

pd.set_option("display.width", 220)
DC = (r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel"
      r"\14 NSU Market Survey\Data Cleaning")
MS = DC + r"\outputs\master_rename_build\temp\nsu_weights_restated.dta"
REF = DC + r"\outputs\master_rename_build\temp\nsu_reference_set.dta"
OUT = DC + r"\outputs\tables\singleton_hetero_groups.csv"

BR = {1.0: "conventional", 2.0: "price-quantity", 3.0: "size-based"}
LBL = {1: "conventional", 2: "small", 3: "medium", 4: "large", 5: "mp25", 6: "mp50",
       7: "mp75", 8: "mun_median", 9: "prov_median", 10: "uniq6", 11: "uniq7"}
CASE = ["pull_province", "pull_municipal_city", "pull_item",
        "harmonized_nsu_unit", "corrected_unit"]
GROUP = CASE + ["item_nsu_hetero_type"]


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def main():
    d = pd.read_stata(MS, convert_categoricals=False)
    d = d[d.corrected_weight.notna()]
    d["branch"] = d.weighing_approach.map(lambda v: BR.get(float(v), "?"))
    d["label"] = d.item_nsu_hetero_type.map(lambda v: LBL.get(int(v), str(v)))
    print(f"weighings with a usable weight: {len(d):,}")

    g = d.groupby(GROUP, dropna=False).agg(
        n=("corrected_weight", "size"),
        w=("corrected_weight", "median"),
        branch=("branch", "first"),
        label=("label", "first"),
        vendors=("vendor_id", "nunique"))

    # ================================================================ Q1
    h("Q1  HETERO-GROUPS RESTING ON A SINGLE WEIGHING")
    print(f"  (case x hetero-group) cells:              {len(g):>6,}")
    print(f"  ...with exactly ONE weighing:             {int((g.n == 1).sum()):>6,}"
          f"   ({100*(g.n == 1).mean():.1f}%)")
    print(f"  ...with two:                              {int((g.n == 2).sum()):>6,}")
    print(f"  ...with three or more:                    {int((g.n >= 3).sum()):>6,}")
    print("\n  singletons by branch:")
    t = g.assign(single=(g.n == 1)).groupby("branch").agg(
        cells=("n", "size"), singletons=("single", "sum"))
    t["pct"] = (100 * t.singletons / t.cells).round(1)
    print("   " + t.to_string().replace("\n", "\n   "))
    print("\n  singletons by hetero-group label:")
    t2 = g.assign(single=(g.n == 1)).groupby("label").agg(
        cells=("n", "size"), singletons=("single", "sum"))
    t2["pct"] = (100 * t2.singletons / t2.cells).round(1)
    print("   " + t2.sort_values("singletons", ascending=False)
          .to_string().replace("\n", "\n   "))

    # ================================================================ Q2
    h("Q2  HOW MUCH OF EACH OUTCOME RESTS ON A SINGLETON")
    weigh_single = int(d.set_index(GROUP).index.isin(
        set(g[g.n == 1].index)).sum())
    print(f"  weighings sitting in a singleton group:   {weigh_single:>6,}"
          f"   ({100*weigh_single/len(d):.1f}% of all weighings)")
    try:
        ref = pd.read_stata(REF, convert_categoricals=False)
        ncol = next((c for c in ["n_g", "n_obs", "n"] if c in ref.columns), None)
        if ncol:
            print(f"\n  OUTCOME 1 published rows:                {len(ref):>6,}")
            print(f"    resting on ONE weighing:               "
                  f"{int((ref[ncol] == 1).sum()):>6,}"
                  f"   ({100*(ref[ncol] == 1).mean():.1f}%)")
            print(f"    resting on two:                        "
                  f"{int((ref[ncol] == 2).sum()):>6,}")
            print("  (Outcome 1 re-terciles first, so its groups are not the field")
            print("   groups above -- these are the published rows.)")
    except Exception as e:
        print(f"  reference set unreadable: {e}")

    # ================================================================ Q3
    h("Q3  IS A SINGLETON PLAUSIBLY AN OUTLIER")
    print("Compare each singleton against the same item x harmonized unit x label")
    print("measured in OTHER municipalities of the same province. A singleton far from")
    print("that distribution is the one to worry about.")
    prov = d.groupby(["pull_province", "pull_item", "harmonized_nsu_unit",
                      "corrected_unit", "item_nsu_hetero_type"]).corrected_weight
    pmed = prov.median()
    pn = prov.size()
    s = g[g.n == 1].reset_index()
    key = list(zip(s.pull_province, s.pull_item, s.harmonized_nsu_unit,
                   s.corrected_unit, s.item_nsu_hetero_type))
    s["prov_median"] = [pmed.get(k) for k in key]
    s["prov_n"] = [int(pn.get(k, 0)) for k in key]
    # exclude the singleton itself from the comparison pool
    s["prov_n_other"] = s.prov_n - 1
    cmp = s[(s.prov_n_other >= 3) & s.prov_median.notna() & (s.prov_median > 0)].copy()
    cmp["ratio"] = cmp.w / cmp.prov_median
    print(f"\n  singletons with >=3 other weighings in the province to compare against:"
          f" {len(cmp):,} of {len(s):,}")
    if len(cmp):
        print("   " + cmp.ratio.describe()[["min", "25%", "50%", "75%", "max"]]
              .to_string().replace("\n", "\n   "))
        for lo, hi, lab in [(0, 0.5, "less than half"), (2, 99, "more than double")]:
            n = int(((cmp.ratio < hi) & (cmp.ratio > lo)).sum()) if lab.startswith("less") \
                else int((cmp.ratio > lo).sum())
            print(f"    singleton {lab} the province median for its group: {n}")
        print("\n  worst 12:")
        cmp["x"] = cmp.ratio.apply(lambda r: max(r, 1 / r) if r else None)
        print("   " + cmp.sort_values("x", ascending=False).head(12)[
            ["pull_province", "pull_municipal_city", "pull_item",
             "harmonized_nsu_unit", "label", "w", "prov_median", "prov_n_other",
             "ratio"]].to_string(index=False).replace("\n", "\n   "))
    print(f"\n  singletons with NO province comparison at all:"
          f" {int((s.prov_n_other < 3).sum()):,}")
    print("    -- these cannot be checked against anything.")

    # ================================================================ Q4
    h("Q4  CASES WHERE EVERY GROUP IS A SINGLETON")
    per_case = g.reset_index().groupby(CASE, dropna=False).agg(
        groups=("n", "size"), singles=("n", lambda x: int((x == 1).sum())),
        weighings=("n", "sum"), branch=("branch", "first"))
    allsingle = per_case[per_case.groups == per_case.singles]
    print(f"  cases:                                    {len(per_case):>6,}")
    print(f"  ...where EVERY group is a singleton:      {len(allsingle):>6,}"
          f"   ({100*len(allsingle)/len(per_case):.1f}%)")
    print("   " + allsingle.groupby("branch").agg(
        cases=("groups", "size"), weighings=("weighings", "sum"))
        .to_string().replace("\n", "\n   "))
    print("\n  These have no internal check of any kind: no second weighing in any")
    print("  group, so nothing in the case can contradict a bad measurement.")

    s.to_csv(OUT, index=False, encoding="utf-8-sig")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
