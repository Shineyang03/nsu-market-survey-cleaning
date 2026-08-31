"""Outcome 1's MECE partition of cases, and what the pooling question is there.

Outcome 1 publishes grams by SIZE (small/medium/large or conventional). It has no price
dimension, so the price file runs the OTHER way from Outcome 2: instead of prices
determining how many groups the weights are cut into, a price rung determines which SIZE
a weighing is called.

Applies Outcome 1's own exclusions first (missing corrected_weight, unique_mun_price, and the
mixed-branch carrot rule), then partitions what remains by branch x whether the case
pools more than one weighed raw spelling. The rows sum to the file, which is the check
that the partition is exhaustive.

Also reports the two things the partition exposes: the price-quantity collision where a
municipality median and a province median both map to size_ord 2, and the share of
"medium" rows that come from a median rather than from a real mp50.

RUN
    python dofiles/scope_outcome1_partition.py
"""
import re
import pandas as pd

pd.set_option("display.width", 210)
BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"
BR = {1.0: "conventional", 2.0: "price-quantity", 3.0: "size-based"}
LBL = {1: "conventional", 2: "small", 3: "medium", 4: "large", 5: "mp25", 6: "mp50",
       7: "mp75", 8: "mun_median", 9: "prov_median", 10: "uniq6", 11: "uniq7"}
K = ["prov", "mun", "item", "harm", "corrected_unit"]


def A(s): return str(s).encode("ascii", "ignore").decode("ascii")
def nz(s): return re.sub(r"\s+", " ", A(s).lower().strip())
def ng(s): return re.sub(r"\s+", " ", A(s).strip().upper())


def ni(s):
    s = nz(s)
    return "drinks at restaurant, hotel, cafe, or kiosk" if "restaurant" in s else s


ms = pd.read_stata(DC + r"\outputs\master_rename_build\temp\nsu_weights_restated.dta",
                   convert_categoricals=False)
ms["prov"] = ms.pull_province.map(ng); ms["mun"] = ms.pull_municipal_city.map(ng)
ms["item"] = ms.pull_item.map(ni); ms["raw"] = ms.pull_nsu_unit.map(nz)
ms["harm"] = ms.harmonized_nsu_unit.map(nz)
ms["branch"] = ms.weighing_approach.map(lambda v: BR.get(float(v), "?"))
ms["lbl"] = ms.item_nsu_hetero_type.map(lambda v: LBL.get(int(v), v))

print("=" * 74)
print("OUTCOME 1 SCOPE: WHAT IT DROPS BEFORE PARTITIONING")
print("=" * 74)
print(f"  restated weighings                          {len(ms):>6,}")
d = ms[ms.corrected_weight.notna()]
print(f"  after dropping missing corrected_weight                {len(d):>6,}")
d = d[~d.item_nsu_hetero_type.isin([10, 11])]
print(f"  after excluding unique_mun_price (10, 11)   {len(d):>6,}")
g = d.groupby(K, dropna=False).weighing_approach
d = d[~(g.transform(lambda s: (s == 3).any()) & g.transform(lambda s: (s == 2).any())
        & (d.weighing_approach == 2))]
print(f"  after the mixed-branch (carrot) rule        {len(d):>6,}")

gg = d.groupby(K, dropna=False)
tab = pd.DataFrame({"n_spell": gg.raw.nunique(),
                    "branch": gg.branch.agg(lambda s: "+".join(sorted(set(s)))),
                    "n_w": gg.size(),
                    "labels": gg.lbl.agg(lambda s: sorted(set(s)))})
tab["pooled"] = tab.n_spell > 1
print(f"\n  cases entering Outcome 1                    {len(tab):>6,}")
print("\n" + tab.groupby(["branch", "pooled"]).agg(
    cases=("n_w", "size"), weighings=("n_w", "sum")).to_string())

print("\n" + "=" * 74)
print("THE POOLED PRICE-QUANTITY CASES -- WHICH RUNGS, AND DO THEY COLLIDE")
print("=" * 74)
pq = tab[(tab.branch == "price-quantity") & tab.pooled]
MEDS = {"mp50", "mun_median", "prov_median"}
for k in pq.index:
    sub = d[d.set_index(K).index == k]
    per = sub.groupby(["raw", "lbl"]).agg(n=("corrected_weight", "size"),
                                          med=("corrected_weight", "median"),
                                          price=("pull_price", "first"))
    labs = set(sub.lbl)
    coll = len(labs & MEDS) > 1 or (len(labs & MEDS) == 1 and sub.raw.nunique() > 1
                                    and sub[sub.lbl.isin(MEDS)].raw.nunique() > 1)
    print(f"\n  {' / '.join(str(x) for x in k)}")
    print("   " + per.to_string().replace("\n", "\n   "))
    print(f"   labels: {sorted(labs)}   -> all medians map to size_ord 2:"
          f" {'COLLISION' if coll else 'no collision'}")

print("\n" + "=" * 74)
print("THE BIGGER OUTCOME 1 QUESTION: WHAT 'MEDIUM' IS MADE OF")
print("=" * 74)
pqall = d[d.branch == "price-quantity"]
v = pqall.lbl.value_counts()
print("   " + v.to_string().replace("\n", "\n   "))
med = int(v.get("mun_median", 0) + v.get("prov_median", 0))
mp50 = int(v.get("mp50", 0))
print(f"\n  rows Outcome 1 publishes as 'medium':  {med + mp50:,}")
print(f"    from a real mp50:                    {mp50:,}")
print(f"    from a median, not a size:           {med:,}"
      f"   ({100*med/max(1, med+mp50):.0f}%)")
print(f"\n  price-quantity cases whose ONLY label is a median:"
      f" {int(sum(1 for l in tab[tab.branch=='price-quantity'].labels if set(l) <= {'mun_median','prov_median'}))}"
      f" of {int((tab.branch=='price-quantity').sum())}")
print("  Those cases publish exactly one row, called 'medium', and no small or large.")
