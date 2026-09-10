"""Candidate "sufficiently similar" rules for merging price points in a pooled case.

CONTEXT. Where one harmonized unit pools two raw spellings that were both weighed, the
size-based branch inherits the union of their price points. Merging points that are
close enough in pesos avoids splitting the weight distribution on a distinction the
price data does not really support. Merging is on the VALUE, not the rung label: mp25
of one spelling may legitimately merge with mp50 of the other.

THE THRESHOLD SHOULD NOT BE INVENTED. NSU_Price.R -- the script that builds the price
file -- already encodes a view of when two peso figures are "the same":

    Rule 1  Collect_mun_prices = ifelse(province_variance < 20, FALSE, TRUE)
            a municipal price within PHP 20 of the province median is not recorded
            separately at all
    Rule 2  low_var_1 = (mp75 - mp50) <= 20 ; low_var_2 = (mp50 - mp25) <= 20
            if both hold, only the municipality median is kept -- the quartiles are
            judged not distinct enough to be separate points

So the price file's own construction says: differences of PHP 20 or less are not worth
distinguishing. Reusing that number keeps the merge rule internally consistent with the
data it operates on, rather than adding a second, unrelated tolerance.

This script measures what each candidate rule does. It recommends nothing on its own.

RUN
    python dofiles/90_diagnostics/scope_price_point_merge_rule.py

OUTPUT  outputs/tables/issue21_merge_rule_candidates.csv
"""
import re
import sys

from pathlib import Path
import pandas as pd

# The crosswalk deliberately no longer carries standard-quantity, ambiguous and
# not-a-unit labels (dofiles/00_shared/02_drop_non_nsu_labels.py). Price rows carrying them will not
# match, and that is intended -- so the unmatched-row tripwire below has to tell an
# intended removal from a broken join.
from pathlib import Path as _P
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    "_dropnonnsu",
    _P(__file__).resolve().parent.parent / "00_shared" / "02_drop_non_nsu_labels.py")
_mod = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
is_dropped_label = _mod.is_dropped_label

pd.set_option("display.width", 220)
BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"
OUT = DC + r"\outputs\tables\issue21_merge_rule_candidates.csv"
BR = {1.0: "conventional", 2.0: "price-quantity", 3.0: "size-based"}
K = ["prov", "mun", "item", "harm"]


# The one definition of the project's string normalization, imported rather than
# copied. There used to be eleven byte-identical copies of these four functions across
# 90_diagnostics/; a fix to any one of them reached none of the others. The Stata
# counterpart is nsu_normalize in 00_shared/00_globals.do and must agree with it
# character for character -- see the module docstring.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import A, nz, ni, ng


def cluster(points, abs_tol=None, rel_tol=None):
    """Single-linkage merge of sorted price points.

    Two adjacent points join when they are within abs_tol pesos, or within rel_tol of
    the lower one, whichever test is supplied. Single-linkage because the merge should
    be transitive over a chain of near-equal values; the alternative (complete linkage)
    would leave a chain of 5-peso steps unmerged for no principled reason.
    """
    pts = sorted(points)
    if not pts:
        return []
    groups = [[pts[0]]]
    for p in pts[1:]:
        prev = groups[-1][-1]
        near = False
        if abs_tol is not None and (p - prev) <= abs_tol:
            near = True
        if rel_tol is not None and prev and (p - prev) / prev <= rel_tol:
            near = True
        if near:
            groups[-1].append(p)
        else:
            groups.append([p])
    return groups


def main():
    ms = pd.read_stata(DC + r"\outputs\build\intermediate\nsu_weighings_cpi.dta",
                       convert_categoricals=False)
    ms["prov"] = ms.pull_province.map(ng); ms["mun"] = ms.pull_municipal_city.map(ng)
    ms["item"] = ms.pull_item.map(ni); ms["raw"] = ms.pull_nsu_unit.map(nz)
    ms["harm"] = ms.harmonized_nsu_unit.map(nz)
    ms["branch"] = ms.weighing_approach.map(
        lambda v: BR.get(float(v), "?") if pd.notna(v) else "?")

    xw = pd.read_csv(DC + r"\outputs\tables\master_nsu_rename.csv",
                     encoding="utf-8-sig", dtype=str)
    for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
                 ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
        xw[c] = xw[c].map(f)
    pr = pd.read_csv(BOX + r"\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv",
                     encoding="utf-8-sig", dtype=str)
    pr["prov"] = pr.province.map(ng); pr["mun"] = pr.pull_municipal_city.map(ng)
    pr["item"] = pr.cons_name.map(ni); pr["raw"] = pr.Unit_lbl.map(nz)
    pr["p"] = pd.to_numeric(pr.Price, errors="coerce")
    pr = pr.merge(xw[["province", "pull_municipal_city", "cons_name",
                      "pull_nsu_unit", "harmonized_nsu_unit"]],
                  left_on=["prov", "mun", "item", "raw"],
                  right_on=["province", "pull_municipal_city", "cons_name",
                            "pull_nsu_unit"], how="left", validate="m:1")
    unm = pr[pr.harmonized_nsu_unit.isna()]
    broken = unm[~unm.raw.map(is_dropped_label)]
    if len(intended := unm[unm.raw.map(is_dropped_label)]):
        print(f"  dropped-label price rows ignored: {len(intended)}")
    if len(broken):
        print(broken[["prov", "mun", "item", "raw"]].drop_duplicates()
              .to_string(index=False))
        sys.exit("unmatched price rows -- fix the join first")
    pr = pr[pr.harmonized_nsu_unit.notna()]
    pr["harm"] = pr.harmonized_nsu_unit

    weighed = ms.groupby(K).raw.agg(set)
    pooled = {k for k, v in weighed.items() if len(v) > 1}

    print("=" * 74)
    print("THE POOLED CASES BY BRANCH")
    print("=" * 74)
    br = ms[ms.set_index(K).index.isin(pooled)].groupby(K).branch.agg(
        lambda s: "/".join(sorted(set(s))))
    print(br.value_counts().to_string())
    print(f"\n  conventional-only pooled cases: "
          f"{int((br == 'conventional').sum())}")

    # size-based only: the branch the merge rule applies to
    sb = {k for k in pooled if br.get(k) == "size-based"}
    print(f"  size-based-only pooled cases:   {len(sb)}")

    CANDS = [("no merge", None, None),
             ("abs <= P5", 5, None), ("abs <= P10", 10, None),
             ("abs <= P20  (the price file's own rule)", 20, None),
             ("abs <= P30", 30, None),
             ("rel <= 10%", None, 0.10), ("rel <= 20%", None, 0.20),
             ("abs<=P20 OR rel<=10%", 20, 0.10)]

    rows = []
    for k in sorted(sb):
        q = pr[(pr.prov == k[0]) & (pr.mun == k[1])
               & (pr.item == k[2]) & (pr.harm == k[3])]
        q = q[q.raw.isin(weighed[k])]
        pts = sorted(q.p.dropna().unique())
        n_w = int((ms.set_index(K).index == k).sum())
        best_single = int(q.groupby("raw").p.nunique().max()) if len(q) else 0
        r = {"case": " / ".join([k[0], k[1], str(k[2])[:24], k[3]]),
             "n_weighings": n_w, "n_points_union": len(pts),
             "n_points_best_single": best_single}
        for name, a, rel in CANDS:
            r[name] = len(pts) if a is None and rel is None else len(cluster(pts, a, rel))
        rows.append(r)
    t = pd.DataFrame(rows)

    print("\n" + "=" * 74)
    print("WHAT EACH CANDIDATE RULE LEAVES  (size-based pooled cases)")
    print("=" * 74)
    print(f"  {'rule':<42} {'mean pts':>9} {'>3 pts':>7} {'<2 w/pt':>8}")
    for name, _, _ in CANDS:
        gt3 = int((t[name] > 3).sum())
        thin = int((t.n_weighings / t[name] < 2).sum())
        print(f"  {name:<42} {t[name].mean():>9.2f} {gt3:>7} {thin:>8}")
    print(f"\n  ({len(t)} cases; 'best single ladder' would give"
          f" mean {t.n_points_best_single.mean():.2f}, max"
          f" {int(t.n_points_best_single.max())})")

    print("\n  cases still above 3 points under the P20 rule:")
    col = "abs <= P20  (the price file's own rule)"
    bad = t[t[col] > 3]
    if len(bad):
        print("   " + bad[["case", "n_weighings", "n_points_union", col]]
              .to_string(index=False).replace("\n", "\n   "))
    else:
        print("    none")

    t.to_csv(OUT, index=False, encoding="utf-8-sig")
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
