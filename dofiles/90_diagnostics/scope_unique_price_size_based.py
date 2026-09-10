"""Size-based MS cases whose price data carries a unique_mun_price (issue #23).

THE GAP. The Branch S pseudo-code slices a size-based case by "what the price file
holds" and lists three possibilities: a full mp25/mp50/mp75 triple, a municipality
median, or a province median. It has no arm for `unique_mun_price`, so a case that is
size-based in the market survey but whose price row carries a unique observed price
falls through the design with no stated treatment.

WHY THAT MATTERS. A unique_mun_price is not a percentile of anything. It is a single
observed transaction price, recorded because the item-unit had too few distinct prices
in that municipality to support quartiles. The recording rule (per the price-file
design):

    if an item-unit has <= 2 unique prices in a municipality, record the province
    median ALONGSIDE the 1-2 municipality-level prices -- unless those municipality
    prices differ from the province median by 20 pesos or less, in which case record
    only the province median.

Two consequences the pseudo-code has to answer for. First, a unique price should never
appear without a province median beside it. Second, because the <=20-peso cases were
folded away, every unique price that survives is by construction MORE than 20 pesos
from the province median -- so mapping a pooled S/M/L weight distribution onto it means
pricing the case off a value that was kept precisely because it was far from the
central tendency. If that value is an outlier rather than a real level, the resulting
conversion factor inherits the error.

WHAT THIS SCRIPT DOES. It measures the exposure and tests the two stated design rules.
It decides nothing.

  Q1  how many size-based MS cases have a unique_mun_price in the price data, and what
      else those cases carry (province median, municipality median, a triple)
  Q2  does a unique price ever appear WITHOUT a province median (the design rule)
  Q3  the >20-peso rule: how far is each unique price from its province median, and
      does any surviving unique price violate the rule by sitting within 20 pesos
  Q4  the exposure: how many MS weighings sit in these cases, and how the choice of
      price point would move the conversion factor
  Q5  what the existing point-count rule already does with them, which is not what the
      Branch S pseudo-code says

HARMONIZATION IS NOT RE-DERIVED. The raw -> harmonized map is read from
outputs/tables/master_nsu_rename.csv (written by dofiles/00_shared/01_build_crosswalk.py). The
nz/ni/ng normalizers are copied from that file only to join onto it; order matters and
NFKD decomposition must never be used -- DUENAS must become DUEAS, not DUENAS.

RUN
    python dofiles/90_diagnostics/scope_unique_price_size_based.py

OUTPUTS  (outputs/tables/)
    issue23_unique_price_size_based.csv   one row per affected case: what the price file
                                          holds, the unique prices, the province median,
                                          the gap, and the MS weighing count
    a printed report on stdout
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

BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"
PRICE = BOX + r"\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv"
XW = DC + r"\outputs\tables\master_nsu_rename.csv"
MS = DC + r"\outputs\master_rename_build\intermediate\nsu_weighings_cpi.dta"
OUT = DC + r"\outputs\tables"

QUART = ["mp25_price", "mp50_price", "mp75_price"]
UNIQ = "unique_mun_price"
# The price CSV spells these with SPACES ("province median"), while the SurveyCTO case
# files spell the same concepts with underscores as COLUMN names ("province_median").
# Mixing the two conventions silently matches nothing and returns a clean-looking zero,
# so the names are asserted against the file below rather than trusted.
PROV = "province median"
MUN = "municipality median"
PESO_RULE = 20.0          # the price-file design threshold, in pesos
BRANCH = {1.0: "conventional", 2.0: "price-quantity", 3.0: "size-based"}


# The one definition of the project's string normalization, imported rather than
# copied. There used to be eleven byte-identical copies of these four functions across
# 90_diagnostics/; a fix to any one of them reached none of the others. The Stata
# counterpart is nsu_normalize in 00_shared/00_globals.do and must agree with it
# character for character -- see the module docstring.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import A, nz, ni, ng


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


KEY = ["province", "pull_municipal_city", "cons_name"]
HKEY = KEY + ["harmonized_nsu_unit"]


def main():
    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)
    for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
                 ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
        xw[c] = xw[c].map(f)

    pr = pd.read_csv(PRICE, encoding="utf-8-sig", dtype=str)
    pr["province"] = pr.province.map(ng)
    pr["pull_municipal_city"] = pr.pull_municipal_city.map(ng)
    pr["cons_name"] = pr.cons_name.map(ni)
    pr["pull_nsu_unit"] = pr.Unit_lbl.map(nz)
    pr["price"] = pd.to_numeric(pr.Price, errors="coerce")
    pr = pr.merge(xw[KEY + ["pull_nsu_unit", "harmonized_nsu_unit"]],
                  on=KEY + ["pull_nsu_unit"], how="left", validate="m:1")
    unm = pr[pr.harmonized_nsu_unit.isna()]
    intended = unm[unm.pull_nsu_unit.map(is_dropped_label)]
    broken = unm[~unm.pull_nsu_unit.map(is_dropped_label)]
    if len(intended):
        print(f"  dropped-label price rows ignored: {len(intended)}"
              f" ({intended.pull_nsu_unit.nunique()} labels)")
    if len(broken):
        print(broken[KEY + ["pull_nsu_unit"]].drop_duplicates().to_string(index=False))
        sys.exit("unmatched price rows -- fix the join before reading any figure below")
    pr = pr[pr.harmonized_nsu_unit.notna()]

    ms = pd.read_stata(MS, convert_categoricals=False)
    ms = ms.rename(columns={"pull_province": "province", "pull_item": "cons_name"})
    for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
                 ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
        ms[c] = ms[c].map(f)
    ms["w"] = pd.to_numeric(ms.corrected_weight, errors="coerce")
    ms = ms[ms.w.notna()]

    print(f"price rows {len(pr):,}   MS weighings {len(ms):,}")
    print("\nprice_type values present:")
    print(pr.price_type.value_counts(dropna=False).to_string())

    # ---- the MS branch of each case. A case is size-based here if ANY of its weighings
    # is size-based; the mixed-branch cell is reported separately rather than hidden.
    br = ms.groupby(HKEY).weighing_approach.agg(
        lambda s: "/".join(sorted({BRANCH.get(float(x), str(x)) for x in s.dropna()})))
    n_ms = ms.groupby(HKEY).size().rename("n_weighings")

    # ================================================================ Q1
    h("Q1  SIZE-BASED MS CASES WHOSE PRICE DATA CARRIES A UNIQUE PRICE")
    uniq_cases = set(pr[pr.price_type == UNIQ].set_index(HKEY).index)
    print(f"price-file cases holding >=1 unique_mun_price: {len(uniq_cases)}")
    if not uniq_cases:
        sys.exit("no unique_mun_price rows -- nothing to scope")

    ub = br.reindex(sorted(uniq_cases))
    print("\nMS branch of those cases:")
    for k, v in ub.value_counts(dropna=False).items():
        lbl = "NO MS weighings (price-file-only cell)" if pd.isna(k) else k
        print(f"  {lbl:<44} {v:>4}")

    sb = {k for k in uniq_cases if isinstance(ub.get(k), str)
          and "size-based" in ub.get(k)}
    print(f"\n>>> SIZE-BASED cases with a unique price: {len(sb)}   <- the issue #23 ask")

    # what else do those cases carry
    def holds(k):
        g = pr[pr.set_index(HKEY).index == k]
        t = set(g.price_type)
        bits = []
        if len(set(QUART) & t) == 3:
            bits.append("full_triple")
        elif set(QUART) & t:
            bits.append("partial_quartile")
        if MUN in t:
            bits.append("mun_median")
        if PROV in t:
            bits.append("prov_median")
        if UNIQ in t:
            bits.append(f"unique x{g[g.price_type == UNIQ].price.nunique()}")
        return " + ".join(bits)

    comp = {k: holds(k) for k in sb}
    print("\nwhat those size-based cases hold in the price file:")
    print(pd.Series(comp).value_counts().to_string())

    # ================================================================ Q2
    h("Q2  DOES A UNIQUE PRICE EVER APPEAR WITHOUT A PROVINCE MEDIAN")
    print("The price-file design says it should not: a unique price is recorded only")
    print("alongside the province median. Tested on ALL cases with a unique price, not")
    print("just the size-based ones.")
    no_prov = []
    for k in sorted(uniq_cases):
        t = set(pr[pr.set_index(HKEY).index == k].price_type)
        if PROV not in t:
            no_prov.append((k, sorted(t)))
    print(f"\ncases with a unique price and NO province median: {len(no_prov)}"
          f" / {len(uniq_cases)}")
    if no_prov:
        print("  RULE VIOLATED. What they carry instead:")
        for k, t in no_prov[:10]:
            print(f"    {' / '.join(str(x) for x in k)}")
            print(f"       {t}")
    else:
        print("  rule holds on every case")

    # ================================================================ Q3
    h("Q3  THE >20-PESO RULE, AND HOW FAR THE UNIQUE PRICES SIT FROM THE MEDIAN")
    print("Every surviving unique price should be MORE than 20 pesos from its province")
    print("median -- the <=20 cases were folded into the median alone by design. A")
    print("violation means the recording rule was not applied as described, and a very")
    print("large gap means the value kept is a long way from the central tendency.")
    rows = []
    for k in sorted(uniq_cases):
        g = pr[pr.set_index(HKEY).index == k]
        pv = g[g.price_type == PROV].price.dropna()
        pv = float(pv.iloc[0]) if len(pv) else float("nan")
        for u in g[g.price_type == UNIQ].price.dropna().unique():
            rows.append(dict(zip(HKEY, k)) | {
                "branch": ub.get(k) if isinstance(ub.get(k), str) else "(no MS rows)",
                "unique_price": float(u), "prov_median": pv,
                "abs_gap": abs(float(u) - pv) if pv == pv else float("nan"),
                "ratio": (float(u) / pv) if pv == pv and pv else float("nan"),
                "n_weighings": int(n_ms.get(k, 0)),
                "holds": holds(k)})
    u = pd.DataFrame(rows)
    print(f"\n(case, unique price) pairs: {len(u)}")
    have = u[u.abs_gap.notna()]
    print(f"  with a province median to compare against: {len(have)}")
    if len(have):
        print("\nabsolute gap |unique - province median| in pesos:")
        print(have.abs_gap.describe()[["min", "25%", "50%", "75%", "max"]].to_string())
        viol = have[have.abs_gap <= PESO_RULE]
        print(f"\npairs sitting WITHIN {PESO_RULE:.0f} pesos of the median: {len(viol)}"
              + ("   <- rule violated" if len(viol) else "   (rule holds)"))
        if len(viol):
            print(viol[["province", "pull_municipal_city", "cons_name",
                        "harmonized_nsu_unit", "unique_price", "prov_median",
                        "abs_gap", "branch"]].head(15).to_string(index=False))
        print("\nratio unique / province median:")
        print(have.ratio.describe()[["min", "50%", "max"]].to_string())
        print("\nhow extreme the kept value is, as a ratio:")
        bands = pd.cut(have.ratio, [0, .5, .8, 1.25, 2, 5, 1e9],
                       labels=["<0.5x", "0.5-0.8x", "0.8-1.25x", "1.25-2x",
                               "2-5x", ">5x"])
        print(bands.value_counts().sort_index().to_string())

    sbu = u[u.branch.str.contains("size-based", na=False)]
    print(f"\n--- restricted to SIZE-BASED cases: {len(sbu)} pairs across"
          f" {sbu.set_index(HKEY).index.nunique() if len(sbu) else 0} cases")
    if len(sbu):
        print(sbu.sort_values("abs_gap", ascending=False)[
            ["province", "pull_municipal_city", "cons_name", "harmonized_nsu_unit",
             "unique_price", "prov_median", "abs_gap", "ratio", "n_weighings", "holds"]
        ].to_string(index=False))

    # ================================================================ Q4
    h("Q4  EXPOSURE, AND HOW MUCH THE CHOICE OF PRICE POINT MOVES THE ANSWER")
    print("CF_h = p_h * w_g / p_g, so the conversion factor is inversely proportional")
    print("to p_g. Pricing a case off a unique value instead of the province median")
    print("scales every conversion factor in that case by prov_median / unique_price.")
    if len(sbu):
        w = int(sbu.drop_duplicates(subset=HKEY).n_weighings.sum())
        print(f"\nMS weighings in the affected size-based cases: {w}")
        sc = (sbu.prov_median / sbu.unique_price).dropna()
        if len(sc):
            print("\nCF scale factor if the province median is used instead"
                  " (prov/unique):")
            print(sc.describe()[["min", "50%", "max"]].to_string())
            print(f"  pairs where the two choices differ by >=2x: "
                  f"{int(((sc >= 2) | (sc <= 0.5)).sum())} / {len(sc)}")

    # ================================================================ Q5
    h("Q5  WHAT THE EXISTING POINT-COUNT RULE ALREADY DOES WITH THESE")
    print("dofiles/90_diagnostics/tally_price_points.py and scope_multi_price_points.py use:")
    print("    quartiles take precedence; else count distinct unique_mun_price levels;")
    print("    else one point.")
    print("So a size-based case holding prov_median + unique prices is ALREADY counted")
    print("as having as many points as it has unique prices, with the province median")
    print("ignored. That is a third treatment, agreeing with neither the Branch S")
    print("pseudo-code (which has no unique-price arm at all) nor Outcome 1 (which")
    print("excludes unique_mun_price weighings outright, 10_reference_set/10_size_assignment.do sec 1).")
    print("The three need reconciling; this script does not choose between them.")
    if len(sb):
        tally = {}
        for k in sb:
            g = pr[pr.set_index(HKEY).index == k]
            t = set(g.price_type)
            if set(QUART) & t:
                n = int(g[g.price_type.isin(QUART)].price.dropna().nunique())
                how = "quartile levels"
            else:
                n = int(g[g.price_type == UNIQ].price.dropna().nunique()) or 1
                how = "unique-price levels"
            tally[k] = f"{n} ({how})"
        print("\npoints these size-based cases are currently credited with:")
        print(pd.Series(tally).value_counts().to_string())

    # ================================================================ Q6
    h("Q6  HOW MANY PSPS HOUSEHOLD OBSERVATIONS RIDE ON THE UNDECIDED ARM")
    print("Q1-Q5 count CASES and MS weighings. Neither says how much household data")
    print("the decision moves, and that is the number that says whether the arm is")
    print("worth arguing about. Joined from psps_conversion_exposure.csv, written by")
    print("90_diagnostics/scope_psps_exposure.py, on province x municipality x item x")
    print("harmonized unit -- the same case grain used above.")
    expo = Path(OUT) / "psps_conversion_exposure.csv"
    if not expo.exists():
        print(f"\n  SKIPPED: {expo} not found."
              "\n  Run: python dofiles/90_diagnostics/scope_psps_exposure.py")
    else:
        ex = pd.read_csv(expo, encoding="utf-8-sig")
        ex = ex.rename(columns={"prov": "province",
                                "mun": "pull_municipal_city",
                                "item": "cons_name",
                                "harm": "harmonized_nsu_unit"})
        # one row per case in u; n_psps_obs is already a per-cell total
        cases = u.drop_duplicates(subset=HKEY)[HKEY + ["branch"]]
        j = cases.merge(ex, on=HKEY, how="left")
        tot = int(ex.n_psps_obs.sum())
        print(f"\nPSPS food observations in a non-standard unit, all cells: {tot:,}")
        for br, lab in [("size-based", "SIZE-BASED cases (the #23 ask)"),
                        (None, "ALL cases carrying a unique price")]:
            sel = j if br is None else j[j.branch.str.contains(br, na=False)]
            n = int(sel.n_psps_obs.fillna(0).sum())
            print(f"\n{lab}: {len(sel)} cases, {n:,} PSPS observations"
                  f"  ({100 * n / tot:.1f}% of all)")
            nomatch = int(sel.n_psps_obs.isna().sum())
            if nomatch:
                print(f"  ({nomatch} of those cases have no exposure row -- no PSPS"
                      " household reported that cell)")
        print("\nby conversion bucket, size-based cases only:")
        sb_j = j[j.branch.str.contains("size-based", na=False)]
        print(sb_j.groupby("bucket").n_psps_obs.agg(["size", "sum"])
              .rename(columns={"size": "cases", "sum": "psps_obs"})
              .sort_values("psps_obs", ascending=False).to_string())

    u.sort_values("abs_gap", ascending=False).to_csv(
        OUT + r"\issue23_unique_price_size_based.csv", index=False,
        encoding="utf-8-sig")
    print(f"\nwrote {OUT}\\issue23_unique_price_size_based.csv")


if __name__ == "__main__":
    main()
