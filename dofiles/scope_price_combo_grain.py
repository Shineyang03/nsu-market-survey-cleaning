"""Price-type combinations at the RAW vs the HARMONIZED grain.

THE PROBLEM. dofiles/tally_price_points.py keys its tally on the RAW price-file label
(province x municipality x item x Unit_lbl), and docs/conversion_factor_methodology.md
reports the result as four combinations that "map one-to-one onto the four branches of
the field protocol". Both outcomes, however, pool at the HARMONIZED unit. Harmonization
merges spellings, and two spellings of one unit can carry DIFFERENT price_types -- so
the harmonized cell holds combinations that never existed at the raw grain and that no
protocol branch produced.

This script reports both grains side by side and traces where the extra combinations
come from. It measures; it decides nothing.

OVERLAP NOTE. This answers the same question as dofiles/tally_price_points.py at a
second grain. The two should be merged into one file rather than left to drift apart --
see the shared-logic rule. Kept separate only until that consolidation is agreed.

RUN
    python dofiles/scope_price_combo_grain.py
"""
import re
import pandas as pd

BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"


def A(s):
    return str(s).encode("ascii", "ignore").decode("ascii")


def nz(s):
    return re.sub(r"\s+", " ", A(s).lower().strip())


def ni(s):
    s = nz(s)
    return "drinks at restaurant, hotel, cafe, or kiosk" if "restaurant" in s else s


def ng(s):
    return re.sub(r"\s+", " ", A(s).strip().upper())


KEY = ["province", "pull_municipal_city", "cons_name"]
QUART = ["mp25_price", "mp50_price", "mp75_price"]
MUN, PROV, UNIQ = "municipality median", "province median", "unique_mun_price"

xw = pd.read_csv(DC + r"\outputs\tables\master_nsu_rename.csv",
                 encoding="utf-8-sig", dtype=str)
for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
             ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
    xw[c] = xw[c].map(f)

pr = pd.read_csv(BOX + r"\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv",
                 encoding="utf-8-sig", dtype=str)
pr["province"] = pr.province.map(ng)
pr["pull_municipal_city"] = pr.pull_municipal_city.map(ng)
pr["cons_name"] = pr.cons_name.map(ni)
pr["pull_nsu_unit"] = pr.Unit_lbl.map(nz)
pr["price"] = pd.to_numeric(pr.Price, errors="coerce")
pr = pr.merge(xw[KEY + ["pull_nsu_unit", "harmonized_nsu_unit"]],
              on=KEY + ["pull_nsu_unit"], how="left", validate="m:1")
assert pr.harmonized_nsu_unit.notna().all()


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
