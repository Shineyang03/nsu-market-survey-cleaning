"""Where a fold merged two WEIGHED spellings, do their price rows agree? (issue #21)

THE SCOPE. This is the residual case after two things are set aside:

  - a `pull_nsu_unit` with NO market-survey observations in a cell contributes no
    weight, so it cannot inform a weight moment. Its price row matters only later,
    for matching a PSPS household that reports that spelling. Such spellings are
    EXCLUDED here.
  - price-file cells with no MS weighing at all are likewise out of scope.

What remains is the case that genuinely has to be decided: one harmonized unit, two or
more raw spellings that were BOTH weighed in that cell, each carrying its own price row.
If those price rows disagree, the pooled case has no unambiguous price to pair its
weights with.

WHY THE PRICE ROWS CAN DISAGREE AT ALL. The price file is constructed per RAW label:
each `Unit_lbl` gets its own price_type depending on how many distinct prices existed
for that label in that municipality (>=3 with a wide IQR gives quartiles; <=2 gives the
province median alongside the observed prices; and so on). So two spellings of one unit
can end up with different summary types simply because the evidence base under each
label differed. The right object would be the price distribution recomputed on the
POOLED observations, which we do not have -- only the per-label summaries.

THREE WAYS THEY CAN DISAGREE, all tested:
  1. different COMPOSITION      one spelling has a full mp25/50/75 triple, the other
                                only a median
  2. same rung, different LEVEL both quote mp50, with different pesos
  3. different CENTRAL TENDENCY one quotes a municipality median, the other a province
                                median, with different pesos

Test 3 is easy to miss: both spellings classify as "median_only", and neither rung has
two values, so tests 1 and 2 both pass them as agreeing. They are not agreeing -- they
are two competing central-tendency estimates for the same unit, differing here by up
to 2x.

RUN
    python dofiles/scope_pooled_spelling_price_conflicts.py

OUTPUT  outputs/tables/issue21_pooled_spelling_conflicts.csv
        one row per pooled case: the spellings, their price types and values, which of
        the three disagreements fire, and the MS weighing count
"""
import re
import sys

import pandas as pd

pd.set_option("display.width", 220)
BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"
PRICE = BOX + r"\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv"
MS = DC + r"\outputs\master_rename_build\temp\nsu_weights_restated.dta"
XW = DC + r"\outputs\tables\master_nsu_rename.csv"
OUT = DC + r"\outputs\tables\issue21_pooled_spelling_conflicts.csv"

QUART = ["mp25_price", "mp50_price", "mp75_price"]
CENTRAL = ["municipality median", "province median", "unique_mun_price"]
K = ["prov", "mun", "item", "harm"]


def A(s):
    return str(s).encode("ascii", "ignore").decode("ascii")


def nz(s):
    return re.sub(r"\s+", " ", A(s).lower().strip())


def ng(s):
    return re.sub(r"\s+", " ", A(s).strip().upper())


def ni(s):
    s = nz(s)
    return "drinks at restaurant, hotel, cafe, or kiosk" if "restaurant" in s else s


def composition(types):
    t = set(types)
    q = [p for p in QUART if p in t]
    if len(q) == 3:
        return "full_triple"
    if q:
        return "partial_quartile"
    if "unique_mun_price" in t:
        return "unique_only"
    return "median_only"


def main():
    ms = pd.read_stata(MS, convert_categoricals=False)
    ms["prov"] = ms.pull_province.map(ng)
    ms["mun"] = ms.pull_municipal_city.map(ng)
    ms["item"] = ms.pull_item.map(ni)
    ms["raw"] = ms.pull_nsu_unit.map(nz)
    ms["harm"] = ms.harmonized_nsu_unit.map(nz)

    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)
    for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
                 ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
        xw[c] = xw[c].map(f)

    pr = pd.read_csv(PRICE, encoding="utf-8-sig", dtype=str)
    pr["prov"] = pr.province.map(ng)
    pr["mun"] = pr.pull_municipal_city.map(ng)
    pr["item"] = pr.cons_name.map(ni)
    pr["raw"] = pr.Unit_lbl.map(nz)
    pr["p"] = pd.to_numeric(pr.Price, errors="coerce")
    pr = pr.merge(xw[["province", "pull_municipal_city", "cons_name",
                      "pull_nsu_unit", "harmonized_nsu_unit"]],
                  left_on=["prov", "mun", "item", "raw"],
                  right_on=["province", "pull_municipal_city", "cons_name",
                            "pull_nsu_unit"],
                  how="left", validate="m:1")
    if pr.harmonized_nsu_unit.isna().any():
        sys.exit("unmatched price rows -- fix the join before reading any figure below")
    pr["harm"] = pr.harmonized_nsu_unit

    seen = set(pr.price_type.dropna())
    need = set(QUART) | set(CENTRAL)
    if need - seen:
        sys.exit("price_type constants match nothing: " + repr(sorted(need - seen))
                 + "; present: " + repr(sorted(seen)))

    weighed = ms.groupby(K).raw.agg(set)
    pooled = {k for k, v in weighed.items() if len(v) > 1}
    n_ms = ms.groupby(K).size()

    rows = []
    for k in sorted(pooled):
        q = pr[(pr.prov == k[0]) & (pr.mun == k[1])
               & (pr.item == k[2]) & (pr.harm == k[3])]
        q = q[q.raw.isin(weighed[k])]          # weighed spellings only
        if q.raw.nunique() < 2:
            continue
        comps = q.groupby("raw").price_type.agg(composition)
        diff_comp = comps.nunique() > 1
        diff_level = bool((q.groupby("price_type").p.nunique() > 1).any())
        cen = q[q.price_type.isin(CENTRAL)]
        per = cen.groupby("raw").p.first().dropna()
        diff_central = bool(cen.raw.nunique() > 1 and per.nunique() > 1)
        ratio = float(per.max() / per.min()) if len(per) > 1 and per.min() else None
        rows.append({
            "province": k[0], "municipality": k[1], "item": k[2],
            "harmonized_nsu_unit": k[3],
            "spellings": " + ".join(sorted(set(q.raw))),
            "price_types": " vs ".join(
                q.groupby("raw").price_type.agg(lambda s: "/".join(sorted(set(s))))),
            "central_values": " vs ".join(f"{v:g}" for v in per) if len(per) else "",
            "central_ratio": round(ratio, 2) if ratio else None,
            "diff_composition": int(diff_comp),
            "diff_level_same_rung": int(diff_level),
            "diff_central_tendency": int(diff_central),
            "conflict": int(diff_comp or diff_level or diff_central),
            "n_ms_weighings": int(n_ms.get(k, 0))})
    t = pd.DataFrame(rows)

    print("=" * 78)
    print("POOLED CASES WHERE BOTH SPELLINGS WERE WEIGHED AND PRICED")
    print("=" * 78)
    print(f"  MS cases pooling >1 raw spelling             {len(pooled):>4}")
    print(f"  ...with >=2 weighed spellings also priced    {len(t):>4}")
    print(f"  ...whose price rows DISAGREE                 {int(t.conflict.sum()):>4}"
          f"   ({int(t[t.conflict == 1].n_ms_weighings.sum())} weighings)")
    print(f"  ...whose price rows are IDENTICAL            "
          f"{int((t.conflict == 0).sum()):>4}"
          f"   ({int(t[t.conflict == 0].n_ms_weighings.sum())} weighings)")
    print("\n  how they disagree (a case can trip more than one):")
    print(f"    different composition                      {int(t.diff_composition.sum()):>4}")
    print(f"    same rung, different level                 {int(t.diff_level_same_rung.sum()):>4}")
    print(f"    different central tendency (mun vs prov)   {int(t.diff_central_tendency.sum()):>4}")

    ok = t[t.conflict == 0]
    print(f"\n  SAFE TO POOL AS-IS -- one price, no ambiguity ({len(ok)}):")
    print("   " + ok[["province", "municipality", "item", "harmonized_nsu_unit",
                      "spellings", "price_types", "n_ms_weighings"]]
          .to_string(index=False).replace("\n", "\n   "))

    bad = t[t.conflict == 1].sort_values("n_ms_weighings", ascending=False)
    print(f"\n  NEEDS A DECISION ({len(bad)}), largest first:")
    print("   " + bad[["province", "municipality", "item", "harmonized_nsu_unit",
                       "spellings", "price_types", "central_ratio", "n_ms_weighings"]]
          .to_string(index=False).replace("\n", "\n   "))

    t.sort_values(["conflict", "n_ms_weighings"], ascending=False).to_csv(
        OUT, index=False, encoding="utf-8-sig")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
