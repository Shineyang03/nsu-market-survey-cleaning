"""Price-type combinations at the RAW vs the HARMONIZED grain.

THE PROBLEM. dofiles/90_diagnostics/tally_price_points.py keys its tally on the RAW price-file label
(province x municipality x item x Unit_lbl), and docs/conversion_factor_methodology.md
reports the result as four combinations that "map one-to-one onto the four branches of
the field protocol". Both outcomes, however, pool at the HARMONIZED unit. Harmonization
merges spellings, and two spellings of one unit can carry DIFFERENT price_types -- so
the harmonized cell holds combinations that never existed at the raw grain and that no
protocol branch produced.

This script reports both grains side by side and traces where the extra combinations
come from. It measures; it decides nothing.

OVERLAP NOTE. This answers the same question as dofiles/90_diagnostics/tally_price_points.py at a
second grain. The two should be merged into one file rather than left to drift apart --
see the shared-logic rule. Kept separate only until that consolidation is agreed.

RUN
    python dofiles/90_diagnostics/scope_price_combo_grain.py
"""
import re
from pathlib import Path
import pandas as pd

import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    "_dropnonnsu",
    Path(__file__).resolve().parent.parent / "00_shared" / "02_drop_non_nsu_labels.py")
_mod = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
is_dropped_label = _mod.is_dropped_label

BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"


# The one definition of the project's string normalization, imported rather than
# copied. There used to be eleven byte-identical copies of these four functions across
# 90_diagnostics/; a fix to any one of them reached none of the others. The Stata
# counterpart is nsu_normalize in 00_shared/00_globals.do and must agree with it
# character for character -- see the module docstring.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import A, nz, ni, ng


KEY = ["province", "pull_municipal_city", "cons_name"]
QUART = ["mp25_price", "mp50_price", "mp75_price"]
MUN, PROV, UNIQ = "municipality median", "province median", "unique_mun_price"

xw = pd.read_csv(DC + r"\outputs\tables\master_nsu_rename.csv",
                 encoding="utf-8-sig", dtype=str)
for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
             ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
    xw[c] = xw[c].map(f)

pr = pd.read_csv(DC + r"\inputs\NSU_prices_from_Makayla.csv",
                 encoding="utf-8-sig", dtype=str)
pr["province"] = pr.province.map(ng)
pr["pull_municipal_city"] = pr.pull_municipal_city.map(ng)
pr["cons_name"] = pr.cons_name.map(ni)
pr["pull_nsu_unit"] = pr.Unit_lbl.map(nz)
pr["price"] = pd.to_numeric(pr.Price, errors="coerce")
pr = pr.merge(xw[KEY + ["pull_nsu_unit", "harmonized_nsu_unit"]],
              on=KEY + ["pull_nsu_unit"], how="left", validate="m:1")
# The crosswalk deliberately no longer carries standard-quantity, ambiguous and
# not-a-unit labels (dofiles/00_shared/02_drop_non_nsu_labels.py). Those price rows will not match,
# and that is intended -- so distinguish an intended removal from a broken join.
_unm = pr[pr.harmonized_nsu_unit.isna()]
_broken = _unm[~_unm.pull_nsu_unit.map(is_dropped_label)]
if len(_unm) - len(_broken):
    print(f"  price rows on deliberately dropped labels, ignored:"
          f" {len(_unm) - len(_broken)}")
if len(_broken):
    print(_broken[["province", "pull_municipal_city", "cons_name", "pull_nsu_unit"]]
          .drop_duplicates().to_string(index=False))
    raise SystemExit("unmatched price rows -- fix the join before reading any figure")
pr = pr[pr.harmonized_nsu_unit.notna()]


def combo(types):
    t = set(types)
    bits = []
    q = len(set(QUART) & t)
    if q == 3:
        bits.append("mp25+mp50+mp75")
    elif q:
        bits.append(f"partial_quartile({q})")
    if MUN in t:
        bits.append("municipality median")
    if PROV in t:
        bits.append("province median")
    if UNIQ in t:
        bits.append("unique_mun_price")
    return " + ".join(bits)


for label, unit_col in [("RAW grain (what tally_price_points.py counts)", "pull_nsu_unit"),
                        ("HARMONIZED grain (what the pipeline pools on)",
                         "harmonized_nsu_unit")]:
    g = pr.groupby(KEY + [unit_col]).price_type.agg(combo)
    print("=" * 78)
    print(f"{label}:  {len(g):,} cells")
    print("=" * 78)
    print(g.value_counts().to_string())
    both = g.str.contains("municipality median") & g.str.contains("province median")
    print(f"\ncells holding BOTH a municipality median AND a province median: "
          f"{int(both.sum())}")
    print()

# where do the harmonized-only combinations come from?
gh = pr.groupby(KEY + ["harmonized_nsu_unit"]).price_type.agg(combo)
both = gh[gh.str.contains("municipality median") & gh.str.contains("province median")]
if len(both):
    print("=" * 78)
    print("Provenance of the both-medians cells: which raw spellings supplied each type")
    print("=" * 78)
    shown = 0
    for k in both.index:
        sub = pr[(pr.province == k[0]) & (pr.pull_municipal_city == k[1])
                 & (pr.cons_name == k[2]) & (pr.harmonized_nsu_unit == k[3])]
        per = sub.groupby("pull_nsu_unit").price_type.agg(lambda s: sorted(set(s)))
        if len(per) > 1 and shown < 8:
            print(f"\n{k[0]} / {k[1]} / {k[2][:38]} / {k[3]}")
            for u, t in per.items():
                pv = sub[(sub.pull_nsu_unit == u)].groupby("price_type").price.first()
                print(f"    {u:<28} {t}")
                print(f"    {'':<28} {dict(pv)}")
            shown += 1
    n_multi = sum(1 for k in both.index
                  if pr[(pr.province == k[0]) & (pr.pull_municipal_city == k[1])
                        & (pr.cons_name == k[2])
                        & (pr.harmonized_nsu_unit == k[3])].pull_nsu_unit.nunique() > 1)
    print(f"\nof the {len(both)} both-medians harmonized cells, "
          f"{n_multi} pool more than one raw spelling"
          f" (so the combination is CREATED by harmonization)")


# ---------------------------------------------------------------------------
# The hetero-group split, at both grains.
#
# docs/conversion_factor_methodology.md quotes 3 -> 32.5% / 2 -> 3.3% / 1 -> 64.2%.
# That is a RAW-grain figure over 2,950 cells, quoted to describe a pipeline that
# pools 2,550 harmonized cells. Both are computed here so the doc can state the one
# it actually means.
#
# The counting rule is tally_price_points.py's "reference reading": a full quartile
# triple gives 3 groups; otherwise the distinct unique_mun_price levels give 1-2; a
# lone median gives 1. An accompanying province median is a fallback reference, not
# a second group. The alternative reading -- every distinct price level counts -- is
# reported beside it, as the doc does.
# ---------------------------------------------------------------------------
def n_groups_reference(g):
    t = set(g.price_type)
    q = len(set(QUART) & t)
    if q:
        return q
    mun = g.loc[g.price_type == UNIQ, "price"].dropna().nunique()
    return mun if mun else 1


def n_groups_every_level(g):
    t = set(g.price_type)
    q = len(set(QUART) & t)
    if q:
        return q
    return max(1, g.loc[g.price_type.isin([UNIQ, MUN, PROV]), "price"].dropna().nunique())


print("=" * 78)
print("HETERO-GROUPS PER CELL, BOTH GRAINS AND BOTH READINGS")
print("=" * 78)
for label, unit_col in [("raw", "pull_nsu_unit"), ("harmonized", "harmonized_nsu_unit")]:
    keys = KEY + [unit_col]
    ref = pr.groupby(keys).apply(n_groups_reference, include_groups=False)
    alt = pr.groupby(keys).apply(n_groups_every_level, include_groups=False)
    n = len(ref)
    print(f"\n{label} grain -- {n:,} cells")
    print("  groups | reference reading      | every-level reading")
    for k in sorted(set(ref.unique()) | set(alt.unique())):
        a, b = int((ref == k).sum()), int((alt == k).sum())
        print(f"  {k:>6} | {a:>6} ({100*a/n:>5.1f}%)        | {b:>6} ({100*b/n:>5.1f}%)")
