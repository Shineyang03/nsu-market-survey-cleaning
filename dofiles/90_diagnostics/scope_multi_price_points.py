"""Scope the multi-price-point problem inside a single harmonized case (issue #21).

THE PROBLEM. A case is prov x mun x item x harmonized_nsu_unit. Harmonization pools
several raw `pull_nsu_unit` spellings into one harmonized unit. The price file, however,
is keyed on the RAW unit label, so a case that pools two raw units can inherit two
price ladders. If both carry mp25/mp50/mp75 and the levels disagree, the case arrives
with up to six candidate price points instead of three -- and both outcomes need to
know how many groups a case has:

  Outcome 1  maps price points onto size groups (S/M/L). Six points, three sizes.
  Outcome 2  re-slices the pooled size-based weighings into as many groups as the
             price file has points, so the point count IS the group count.

WHAT THIS SCRIPT DOES. It measures the problem; it decides nothing. Nine questions:

  Q1   how many harmonized cases pool more than one PRICED raw unit, and how many
       price points they end up with under two readings (pooled levels vs naive
       label union)
  Q2   when two raw units both carry a ladder, how far apart are the prices
  Q3   do the pooled raw units have different median WEIGHTS in the market survey,
       and how much precision is bought by pooling them (n per unit)
  Q4   which weighing branch the affected cases sit on, and whether the inflation
       adjustment interacts with any of this
  Q5   whether the duplication reaches the MS weighing rows at all
  Q6   whether the FOLD holds where Outcome 1 pools two raw units: does pooling inflate
       the size count, do the re-cut terciles track the raw unit instead of the field
       label, and -- the part that decides it -- can any weight comparison attribute a
       gap to the fold at all, given that spelling turns out to be a vendor-level
       attribute (no vendor in the file ever used two spellings)
  Q7   whether the pooled raw units carry DIFFERENT rung compositions (a bare median
       against a full triple), and the 'medium' collision that creates in Outcome 1
  Q8   what 'quartiles take precedence' costs in a mixed-composition case: how many
       weighings sit on a price ladder measured for a different raw unit
  Q9   which MS branch the level disagreements sit on, and whether the median-only
       cases ever disagree (the assumption points_pooled() makes silently)

HARMONIZATION IS NOT RE-DERIVED HERE. The raw -> harmonized map is read from
outputs/tables/master_nsu_rename.csv, written by dofiles/00_shared/01_build_crosswalk.py, which
is the single authoritative implementation. The nz/ni/ng normalizers below are copied
from that file only to join onto it: drop non-ASCII outright, case-fold, trim, collapse
internal whitespace. Never NFKD-decompose first -- DUENAS must become DUEAS, not
DUENAS, or the join silently loses rows.

RUN
    python dofiles/90_diagnostics/scope_multi_price_points.py

OUTPUTS  (outputs/tables/)
    issue21_points_per_case.csv     one row per harmonized case in the price file:
                                    price points under each reading, raw units pooled
    issue21_price_disagreement.csv  case x price_type pairs whose raw units disagree
    issue21_weight_disagreement.csv case-level weight comparison across pooled units
    issue21_outcome1_fold_check.csv per pooled size-based case: pooled vs single-unit
                                    size count, between-unit weight ratio, and whether
                                    the tercile splits units or sizes -- a shortlist of
                                    folds for validate_folds.py to adjudicate
    issue21_median_disagreement.csv per case whose spellings all carry only a
                                    median, where those medians disagree
    issue21_rung_composition_mix.csv            per case: what rung composition each
                                    pooled raw unit carries, and whether they differ
    issue21_discarded_median_units.csv          cases where a median-only raw unit's
                                    price is dropped in favour of another unit's triple,
                                    with the weight gap between the two sides
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
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    "_dropnonnsu",
    Path(__file__).resolve().parent.parent / "00_shared" / "02_drop_non_nsu_labels.py")
_mod = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
is_dropped_label = _mod.is_dropped_label

BOX = (r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey")
DC = BOX + r"\Data Cleaning"
PRICE = BOX + r"\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv"
XW = DC + r"\outputs\tables\master_nsu_rename.csv"
MS = DC + r"\outputs\master_rename_build\temp\nsu_weighings_cpi.dta"
OUT = DC + r"\outputs\tables"

QUART = ["mp25_price", "mp50_price", "mp75_price"]
DIM = {1.0: "g", 2.0: "mL"}
BRANCH = {1.0: "conventional", 2.0: "price-quantity", 3.0: "size-based"}


# ---------------------------------------------------------------- normalizers
# Copied from dofiles/00_shared/01_build_crosswalk.py. Order matters; see the module docstring.
def A(s):
    return str(s).encode("ascii", "ignore").decode("ascii")


def nz(s):
    return re.sub(r"\s+", " ", A(s).lower().strip())


def ni(s):
    s = nz(s)
    return "drinks at restaurant, hotel, cafe, or kiosk" if "restaurant" in s else s


def ng(s):
    return re.sub(r"\s+", " ", A(s).strip().upper())


def h(title):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


KEY = ["province", "pull_municipal_city", "cons_name"]
HKEY = KEY + ["harmonized_nsu_unit"]


# ------------------------------------------------------------------ load
def load_crosswalk():
    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)
    for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
                 ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
        xw[c] = xw[c].map(f)
    return xw


def load_prices(xw):
    pr = pd.read_csv(PRICE, encoding="utf-8-sig", dtype=str)
    pr["province"] = pr.province.map(ng)
    pr["pull_municipal_city"] = pr.pull_municipal_city.map(ng)
    pr["cons_name"] = pr.cons_name.map(ni)
    pr["pull_nsu_unit"] = pr.Unit_lbl.map(nz)
    pr["price"] = pd.to_numeric(pr.Price, errors="coerce")
    pr = pr.merge(xw[KEY + ["pull_nsu_unit", "harmonized_nsu_unit"]],
                  on=KEY + ["pull_nsu_unit"], how="left", validate="m:1")
    miss = int(pr.harmonized_nsu_unit.isna().sum())
    # A price_type constant that matches nothing makes every downstream count
    # zero, which reads as "no problem found" rather than as an error.
    seen = set(pr.price_type.dropna())
    need = set(QUART) | {"unique_mun_price", "province median",
                         "municipality median"}
    if need - seen:
        sys.exit("price_type constants match nothing: "
                 + repr(sorted(need - seen))
                 + "; present in the file: " + repr(sorted(seen)))
    print(f"price rows                          {len(pr):>6}")
    print(f"  unmatched to the crosswalk        {miss:>6}")
    unm = pr[pr.harmonized_nsu_unit.isna()]
    intended = unm[unm.pull_nsu_unit.map(is_dropped_label)]
    broken = unm[~unm.pull_nsu_unit.map(is_dropped_label)]
    if len(intended):
        print(f"  price rows on deliberately dropped labels, ignored: {len(intended)}"
              f" ({intended.pull_nsu_unit.nunique()} labels)")
    if len(broken):
        print(broken[KEY + ["pull_nsu_unit"]].drop_duplicates().to_string(index=False))
        sys.exit("unmatched price rows -- fix the join before reading any figure below")
    pr = pr[pr.harmonized_nsu_unit.notna()]
    return pr


def load_ms(xw):
    ms = pd.read_stata(MS, convert_categoricals=False)
    ms = ms.rename(columns={"pull_province": "province", "pull_item": "cons_name"})
    for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
                 ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
        ms[c] = ms[c].map(f)
    ms["w"] = pd.to_numeric(ms.corrected_weight, errors="coerce")
    print(f"market-survey weighings             {len(ms):>6}")
    return ms


# --------------------------------------------------------- point-count rules
def points_pooled(grp):
    """Distinct price LEVELS in the case, quartiles taking precedence.

    Follows dofiles/90_diagnostics/tally_price_points.py: a full mp25/50/75 triple gives 3 points; a
    province median accompanying a municipal price is a fallback reference, not a
    second point. Extended here over ALL raw units in the harmonized case, so two raw
    units quoting the same level collapse to one point and two quoting different
    levels do not.
    """
    qq = grp[grp.price_type.isin(QUART)]
    if len(qq):
        return int(qq.price.dropna().nunique())
    mm = int(grp[grp.price_type == "unique_mun_price"].price.dropna().nunique())
    return mm if mm else 1


def points_naive(grp):
    """One point per (raw unit x price_type) label -- what you get if the raw units
    are never reconciled at all. The upper bound on the problem."""
    qq = grp[grp.price_type.isin(QUART)]
    if len(qq):
        return int(len(qq.groupby(["pull_nsu_unit", "price_type"])))
    mm = grp[grp.price_type == "unique_mun_price"]
    return int(len(mm.groupby("pull_nsu_unit"))) or 1


def main():
    xw = load_crosswalk()
    pr = load_prices(xw)
    ms = load_ms(xw)

    # ================================================================ Q1
    h("Q1  HOW MANY HARMONIZED CASES POOL MORE THAN ONE PRICED RAW UNIT")
    g = pr.groupby(HKEY)
    tab = g.pull_nsu_unit.nunique().rename("n_raw_units").reset_index()
    print(f"harmonized cases present in the price file   {len(tab):>6}")
    print("\nraw priced units pooled into one case:")
    print(tab.n_raw_units.value_counts().sort_index().to_string())
    multi = tab[tab.n_raw_units > 1]
    print(f"\ncases pooling >1 priced raw unit             {len(multi):>6}"
          f"   ({100 * len(multi) / len(tab):.1f}%)")

    q = pr[pr.price_type.isin(QUART)]
    qu = q.groupby(HKEY).pull_nsu_unit.nunique().rename("n_ladder_units").reset_index()
    print("\nOf the cases that have any mp25/50/75 ladder, how many raw units carry one:")
    print(qu.n_ladder_units.value_counts().sort_index().to_string())
    print("(n_ladder_units = 2 is the scenario in the issue: two ladders, up to 6 points)")

    rec = []
    for k, grp in pr.groupby(HKEY):
        rec.append(dict(zip(HKEY, k)) | {
            "n_raw_units": int(grp.pull_nsu_unit.nunique()),
            "raw_units": " | ".join(sorted(grp.pull_nsu_unit.unique())),
            "points_pooled": points_pooled(grp),
            "points_naive": points_naive(grp)})
    pts = pd.DataFrame(rec)
    print("\nprice points per case: pooled levels (rows) x naive label union (cols)")
    print(pd.crosstab(pts.points_pooled, pts.points_naive, margins=True).to_string())
    print(f"\ncases where the two readings disagree        "
          f"{int((pts.points_pooled != pts.points_naive).sum()):>6} / {len(pts)}")
    print("cases with MORE than 3 pooled points         "
          f"{int((pts.points_pooled > 3).sum()):>6}"
          "   <- these cannot map onto S/M/L as-is")
    pts.sort_values(["points_pooled", "n_raw_units"], ascending=False) \
       .to_csv(OUT + r"\issue21_points_per_case.csv", index=False,
               encoding="utf-8-sig")

    # ================================================================ Q2
    h("Q2  WHEN TWO RAW UNITS BOTH CARRY A LADDER, HOW FAR APART ARE THE PRICES")
    mq = set(map(tuple, qu[qu.n_ladder_units > 1][HKEY].values))
    rows = []
    if mq:
        sub = q[q.set_index(HKEY).index.isin(mq)]
        for kk, grp in sub.groupby(HKEY + ["price_type"]):
            lv = grp.price.dropna().unique()
            if len(lv) > 1:
                rows.append(dict(zip(HKEY, kk[:4])) | {
                    "price_type": kk[4], "n_levels": len(lv),
                    "lo": lv.min(), "hi": lv.max(), "ratio": lv.max() / lv.min()})
    dp = pd.DataFrame(rows)
    print(f"case x price_type pairs whose raw units disagree on the level: {len(dp)}")
    if len(dp):
        print("\nratio hi/lo:")
        print(dp.ratio.describe()[["mean", "50%", "min", "max"]].to_string())
        print("\nratio bands (how many pairs could be merged under a tolerance):")
        bands = pd.cut(dp.ratio, [0, 1.05, 1.1, 1.25, 1.5, 2, 1e9],
                       labels=["<=5%", "5-10%", "10-25%", "25-50%", "50-100%", ">100%"])
        print(bands.value_counts().sort_index().to_string())
        print("\nworst 12:")
        print(dp.sort_values("ratio", ascending=False).head(12).to_string(index=False))
        dp.sort_values("ratio", ascending=False).to_csv(
            OUT + r"\issue21_price_disagreement.csv", index=False, encoding="utf-8-sig")

    print("\n--- unique_mun_price, same question ---")
    um = pr[pr.price_type == "unique_mun_price"]
    rows = []
    for k, grp in um.groupby(HKEY):
        if grp.pull_nsu_unit.nunique() > 1:
            lv = grp.price.dropna().unique()
            rows.append(dict(zip(HKEY, k)) | {
                "n_raw_units": int(grp.pull_nsu_unit.nunique()), "n_levels": len(lv),
                "lo": lv.min(), "hi": lv.max(),
                "ratio": lv.max() / lv.min() if len(lv) else float("nan")})
    d2 = pd.DataFrame(rows)
    print(f"cases with >1 raw unit carrying unique_mun_price: {len(d2)}")
    if len(d2):
        print(d2.sort_values("ratio", ascending=False).to_string(index=False))

    # ================================================================ Q3
    h("Q3  DO THE POOLED RAW UNITS DIFFER IN MEDIAN WEIGHT, AND WHAT DOES POOLING BUY")
    # Weight comparison is done at the case grain the pipeline actually uses, which
    # includes corrected_unit: g and mL never pool.
    mkey = HKEY + ["corrected_unit"]
    aff = set(map(tuple, multi[HKEY].values))
    rows = []
    for k, grp in ms.groupby(mkey, dropna=False):
        if tuple(k[:4]) not in aff:
            continue
        per = grp.groupby("pull_nsu_unit").w.agg(["median", "count"]).dropna()
        per = per[per["count"] > 0]
        if len(per) < 2:
            continue
        rows.append(dict(zip(HKEY, k[:4])) | {
            "corrected_unit": DIM.get(k[4], k[4]),
            "n_units_in_MS": len(per),
            "n_weighings": int(per["count"].sum()),
            "n_min": int(per["count"].min()),
            "med_lo": per["median"].min(), "med_hi": per["median"].max(),
            "med_ratio": per["median"].max() / per["median"].min(),
            "branches": "/".join(sorted({BRANCH.get(b, str(b))
                                         for b in grp.weighing_approach.dropna().unique()})),
            "detail": "; ".join(f"{u}: {r['median']:.0f} (n={int(r['count'])})"
                                for u, r in per.iterrows())})
    dw = pd.DataFrame(rows)
    print(f"affected cases where >=2 pooled raw units both have weighings: {len(dw)}")
    if len(dw):
        print("\nmedian-weight ratio across the pooled units:")
        print(dw.med_ratio.describe()[["mean", "50%", "min", "max"]].to_string())
        bands = pd.cut(dw.med_ratio, [0, 1.05, 1.1, 1.25, 1.5, 2, 1e9],
                       labels=["<=5%", "5-10%", "10-25%", "25-50%", "50-100%", ">100%"])
        print(bands.value_counts().sort_index().to_string())
        print("\nWhat pooling buys: n in the SMALLER contributing unit")
        print(dw.n_min.describe()[["mean", "50%", "min", "max"]].to_string())
        print(f"  cases where the thinner unit has n < 3: "
              f"{int((dw.n_min < 3).sum())} / {len(dw)}"
              "   <- splitting back to raw units would leave these unusable")
        print("\nworst 12 by median-weight ratio:")
        print(dw.sort_values("med_ratio", ascending=False)
                .head(12)[["cons_name", "province", "pull_municipal_city",
                           "harmonized_nsu_unit", "corrected_unit", "med_ratio",
                           "n_min", "detail"]].to_string(index=False))
        dw.sort_values("med_ratio", ascending=False).to_csv(
            OUT + r"\issue21_weight_disagreement.csv", index=False, encoding="utf-8-sig")

    # ================================================================ Q4
    h("Q4  BRANCH COMPOSITION, AND WHETHER INFLATION INTERACTS")
    msa = ms[ms.set_index(HKEY).index.isin(aff)]
    print("weighings in affected cases, by branch:")
    print(msa.weighing_approach.map(BRANCH).value_counts().to_string())
    percase = msa.groupby(HKEY).weighing_approach.agg(
        lambda s: "/".join(sorted({BRANCH.get(b, str(b)) for b in s.dropna()})))
    print("\naffected cases by branch mix:")
    print(percase.value_counts().to_string())

    print("\nDoes pooling raw units add an inflation dimension?")
    # pi is province x COICOP group x month-pair. Within a case, province and item are
    # fixed, so pi can only vary through the MS month of the weighing. If the pooled raw
    # units were surveyed in different months, restatement differs across them -- which
    # matters only on the price-quantity branch.
    # cpi_factor is (1+pi) as actually applied per weighing row, so comparing it across
    # the pooled raw units answers the question directly: if it is constant within the
    # case, pooling adds no inflation dimension.
    pq = msa[msa.weighing_approach == 2]
    print(f"  price-quantity weighings in affected cases: {len(pq)}")
    if not len(pq):
        print("  none -- pi is not engaged by this problem at all")
    elif "cpi_factor" not in ms.columns:
        print("  cpi_factor absent from the restated file -- skipped")
    else:
        f = pq.groupby(HKEY).cpi_factor.agg(["nunique", "min", "max"])
        vary = f[f["nunique"] > 1]
        print(f"  affected price-quantity cases with >1 distinct (1+pi):"
              f" {len(vary)} / {len(f)}")
        if len(vary):
            print((vary["max"] / vary["min"]).describe()[["50%", "max"]].to_string())
        u = pq.groupby(HKEY + ["pull_nsu_unit"]).cpi_factor.nunique()
        print(f"  max distinct (1+pi) within one raw unit: {int(u.max())}"
              "   (>1 means the spread is within-unit, not caused by pooling)")


    # ================================================================ Q5
    h("Q5  DOES THE DUPLICATION REACH THE MS WEIGHING ROWS (the Outcome 1 question)")
    # Outcome 1 counts groups from the DISTINCT FIELD LABELS in item_nsu_hetero_type,
    # not from the price file. So the question for Outcome 1 is narrower: does a case
    # ever carry the same label twice because two pooled raw units each recorded it?
    LBL = {1: "conventional", 2: "small", 3: "medium", 4: "large", 5: "mp25",
           6: "mp50", 7: "mp75", 8: "mun_median", 9: "prov_median",
           10: "uniq_mun_p6", 11: "uniq_mun_p7"}
    d = ms.groupby(HKEY + ["corrected_unit", "item_nsu_hetero_type"]) \
          .pull_nsu_unit.nunique().rename("n_raw_units").reset_index()
    dup = d[d.n_raw_units > 1].copy()
    dup["label"] = dup.item_nsu_hetero_type.map(LBL)
    print(f"case x label combos carried by >1 pooled raw unit: {len(dup)}")
    print(dup.label.value_counts().to_string())
    print(f"distinct cases affected: {dup[HKEY].drop_duplicates().shape[0]}")
    price_lbls = dup[dup.item_nsu_hetero_type.isin([5, 6, 7, 8, 9, 10, 11])]
    print(f"\nof those, combos on a PRICE label (5-11): {len(price_lbls)}")
    print("A price label duplicated within a case would be the MS-side mirror of the")
    print("price-file duplication measured in Q1-Q2. Zero here means the duplication")
    print("reaches the MS rows only as repeated SIZE labels.")
    print("DO NOT read that as harmless. Outcome 1 does not publish the label -- it")
    print("re-terciles the pooled WEIGHTS behind the labels, so a size label carried by")
    print("two physically different raw units is exactly the contamination case. Q6")
    print("measures it.")


    # ================================================================ Q6
    h("Q6  IS THE FOLD SOUND WHERE OUTCOME 1 POOLS TWO RAW UNITS (size-based branch)")
    # READ THE SIGN OF THIS SECTION CAREFULLY. Outcome 1 pools the WEIGHTS behind the
    # size labels and re-cuts them into terciles (nsu_reference_set.do sec 2c), so two
    # pooled raw units both enter one tercile computation. That is NOT a defect: if
    # bilog == binilog is a correct fold, a small bilog and a small binilog are the same
    # object and pooling them is precisely the intent -- it buys precision.
    #
    # What this section tests is therefore the FOLD, not Outcome 1's design. A case
    # whose terciles split cleanly by raw unit rather than by field label is evidence
    # that the two raw units are different objects in that municipality and should not
    # have been folded. dofiles/90_diagnostics/validate_folds.py is the tool for adjudicating that;
    # this section only says where to point it.
    #
    # Two things are measured, both replicating nsu_reference_set.do exactly:
    #   (a) k_sizes -- pooling can RAISE the distinct-label count (unit A holds
    #       {small,medium}, unit B holds {large} -> pooled k=3, neither unit alone has 3)
    #   (b) whether the tercile groups line up with raw unit instead of field label
    FIELD = {2: 1, 3: 2, 4: 3}  # hetero_type -> natural size position
    sb = ms[(ms.weighing_approach == 3) & ms.w.notna()].copy()
    sb["field_ord"] = sb.item_nsu_hetero_type.map(FIELD)
    sb = sb[sb.field_ord.notna()]
    CKEY = HKEY + ["corrected_unit"]

    nunits = sb.groupby(CKEY).pull_nsu_unit.nunique()
    pooled_cases = set(nunits[nunits > 1].index)
    print(f"size-based cases                              {nunits.size:>6}")
    print(f"  pooling >1 raw unit                         {len(pooled_cases):>6}"
          f"   ({100 * len(pooled_cases) / nunits.size:.1f}%)")

    def cut(w, k):
        """The do-file's tie rule, lower-inclusive. Returns group 1..k."""
        w = w.astype(float)
        if k >= 3:
            a, b = w.quantile(1 / 3), w.quantile(2 / 3)
            return pd.Series([1 if x <= a else (2 if x <= b else 3) for x in w],
                             index=w.index)
        if k == 2:
            m = w.quantile(0.5)
            return pd.Series([1 if x <= m else 2 for x in w], index=w.index)
        return pd.Series(1, index=w.index)

    rows = []
    for k, g in sb.groupby(CKEY):
        if k not in pooled_cases:
            continue
        k_pooled = int(g.field_ord.nunique())
        k_best_unit = int(g.groupby("pull_nsu_unit").field_ord.nunique().max())
        grp = cut(g.w, k_pooled)
        # how cleanly does the raw unit predict the tercile group?
        ct = pd.crosstab(grp, g.pull_nsu_unit)
        # purity = share of weighings sitting in the modal unit of their own group
        purity = ct.max(axis=1).sum() / ct.values.sum()
        # the same statistic against the FIELD label, for comparison
        ctf = pd.crosstab(grp, g.field_ord)
        purity_lbl = ctf.max(axis=1).sum() / ctf.values.sum()
        med = g.groupby("pull_nsu_unit").w.median()
        n = g.groupby("pull_nsu_unit").w.size()
        # A RAW MEDIAN RATIO ACROSS SPELLINGS IS NOT A FOLD TEST. If one spelling holds
        # a full S/M/L ladder and the other holds only smalls, the first has the higher
        # median for reasons that have nothing to do with whether the two spellings mean
        # the same thing -- it is comparing a medium to a small. The fair comparison is
        # within a label, and it only exists where both spellings recorded that label.
        shared = [lb for lb, u in g.groupby("field_ord").pull_nsu_unit.nunique().items()
                  if u > 1]
        wl = float("nan")
        if shared:
            sub = g[g.field_ord.isin(shared)]
            per = sub.groupby(["field_ord", "pull_nsu_unit"]).w.median()
            ratios = [float(v.max() / v.min())
                      for _, v in per.groupby(level=0) if v.min()]
            wl = max(ratios) if ratios else float("nan")
        # Vendor heterogeneity is the rival explanation. Where each spelling was used by
        # a disjoint set of vendors, spelling and vendor cannot be told apart from this
        # data, so a gap is not evidence against the fold.
        vsets = [set(v.dropna()) for _, v in g.groupby("pull_nsu_unit").vendor_id]
        disjoint = all(not (a & b) for i, a in enumerate(vsets) for b in vsets[i + 1:])
        rows.append(dict(zip(CKEY, k)) | {
            "n": len(g), "n_units": int(g.pull_nsu_unit.nunique()),
            "k_pooled": k_pooled, "k_best_single_unit": k_best_unit,
            "k_inflated_by_pooling": int(k_pooled > k_best_unit),
            "n_shared_labels": len(shared),
            "within_label_ratio": round(wl, 2) if wl == wl else None,
            "vendors_disjoint": int(disjoint),
            "unit_med_ratio_UNFAIR": float(med.max() / med.min()) if med.min() else float("nan"),
            "grp_purity_by_unit": round(float(purity), 3),
            "grp_purity_by_label": round(float(purity_lbl), 3),
            "n_min_unit": int(n.min()),
            "units": " | ".join(f"{u}:n{n[u]:.0f},med{med[u]:.0f}" for u in med.index)})
    c1 = pd.DataFrame(rows)
    if not len(c1):
        print("  none -- Outcome 1 is genuinely untouched")
    else:
        print(f"\n(a) POOLING RAISES THE SIZE COUNT")
        print(f"  cases where pooled k_sizes exceeds any single raw unit's k:"
              f" {int(c1.k_inflated_by_pooling.sum())} / {len(c1)}")
        print("  k_pooled (rows) x k of the richest single raw unit (cols):")
        print(pd.crosstab(c1.k_pooled, c1.k_best_single_unit, margins=True).to_string())
        print("  Off-diagonal rows are cases whose size ladder EXISTS ONLY BECAUSE of")
        print("  pooling: no single raw unit recorded that many labels.")

        print(f"\n(b) DO THE TERCILES SEPARATE UNITS OR SIZES")
        print("  purity = share of weighings in the modal category of their own tercile.")
        print("  1.00 by unit means the cut is a perfect unit split -- the published")
        print("  S/M/L is really 'which raw unit', not 'what size', which indicts the")
        print("  FOLD rather than the tercile rule. Send these to validate_folds.py.")
        print(c1[["grp_purity_by_unit", "grp_purity_by_label"]].describe()
              .loc[["mean", "50%", "max"]].to_string())
        worse = c1[c1.grp_purity_by_unit > c1.grp_purity_by_label]
        print(f"\n  cases where the tercile tracks the UNIT better than the LABEL:"
              f" {len(worse)} / {len(c1)}")
        perfect = c1[(c1.grp_purity_by_unit == 1.0) & (c1.n_units > 1)]
        print(f"  cases where the tercile is a PERFECT unit split:  {len(perfect)}")
        print(f"\n(c) IS THE GAP EVEN ATTRIBUTABLE TO THE FOLD")
        print("  A cross-spelling median ratio is only a fold test when both spellings")
        print("  recorded the SAME label, and only when the spellings are not simply")
        print("  proxies for different vendors.")
        nosh = c1[c1.n_shared_labels == 0]
        print(f"  cases with NO label recorded under >1 spelling: {len(nosh)} / {len(c1)}")
        print("    -> no fair comparison exists in these; the raw median ratio compares")
        print("       unlike labels and must not be read as a fold gap")
        sh = c1[c1.n_shared_labels > 0]
        print(f"  cases WITH a shared label:                      {len(sh)} / {len(c1)}")
        if len(sh):
            print(f"    of those, within-label ratio >=1.5x:          "
                  f"{int((sh.within_label_ratio >= 1.5).sum())}")
            print(f"    of those, within-label ratio >=2x:            "
                  f"{int((sh.within_label_ratio >= 2).sum())}")
            print(f"    of those, vendors DISJOINT across spellings:  "
                  f"{int(sh.vendors_disjoint.sum())}"
                  "   <- spelling confounded with vendor")
            fair = sh[(sh.within_label_ratio >= 1.5) & (sh.vendors_disjoint == 0)]
            print(f"\n  CASES WHERE THE FOLD IS GENUINELY SUSPECT: {len(fair)}")
            print("  (shared label, gap >=1.5x, and at least one vendor used both"
                  " spellings)")
            if len(fair):
                print(fair[["cons_name", "harmonized_nsu_unit", "n",
                            "within_label_ratio", "units"]].to_string(index=False))

        # ---------------------------------------------------------------- (d)
        print("\n(d) WHY (c) CAN NEVER FIRE: SPELLING IS A VENDOR-LEVEL ATTRIBUTE")
        # If no vendor ever uses two spellings, then spelling is perfectly collinear
        # with vendor and NO weight comparison across spellings can separate "the fold
        # merged two different objects" from "these two vendors sell different-sized
        # things". That is a property of the survey design, not a gap in the analysis:
        # the enumerator recorded the unit name once per vendor interaction, so the
        # spelling IS the vendor's word.
        allms = ms[ms.w.notna() & ms.vendor_id.notna()]
        nsp = allms.groupby(CKEY, dropna=False).pull_nsu_unit.nunique()
        msp = set(nsp[nsp > 1].index)
        msub = allms[allms.set_index(CKEY).index.isin(msp)]
        pairs = msub.groupby(CKEY + ["vendor_id"], dropna=False).pull_nsu_unit.nunique()
        vend_all = allms.groupby("vendor_id").pull_nsu_unit.nunique()
        print(f"  cases pooling >1 spelling, all branches:      {len(msp):>6}")
        print(f"  (case, vendor) pairs inside them:             {len(pairs):>6}")
        print(f"    ...that used more than one spelling:        {int((pairs > 1).sum()):>6}")
        print(f"  vendors in the whole file:                    {len(vend_all):>6}")
        print(f"    ...that ever used more than one spelling:   {int((vend_all > 1).sum()):>6}")
        if int((vend_all > 1).sum()) == 0:
            print("\n  ZERO. Spelling is a vendor-level attribute throughout the file.")
            print("  CONSEQUENCE: the weight evidence is structurally incapable of")
            print("  adjudicating any of these folds. Sending them to validate_folds.py")
            print("  would return a number, and the number would not be a fold test.")
            print("  The fold decision has to rest on whether the two strings are the")
            print("  same word (pack/packs, bilog/binilog, gamay/gmay -- plainly yes),")
            print("  and the weight gaps then belong to VENDOR heterogeneity, which is")
            print("  what the pooled re-tercile exists to absorb (Oseni, Durazo & McGee")
            print("  2017 sec 3 step 3: a small in one market can outweigh a large in")
            print("  another).")
            print("\n  The residual problem is real but different: where one vendor's")
            print("  whole ladder sits above another's, a 3-way tercile publishes one")
            print("  vendor's SMALL as the cell's MEDIUM. See the cabbage example in")
            print("  dofiles/90_diagnostics/case_lookup.py (CAPIZ/DUMARAO, harmonized unit 'pack').")
        else:
            print("\n  Some vendors used more than one spelling, so a within-vendor")
            print("  across-spelling comparison exists after all -- build it before")
            print("  concluding anything about these folds.")

        print("\n  worst 12 by WITHIN-LABEL ratio (blank = no shared label):")
        print(c1.sort_values("within_label_ratio", ascending=False, na_position="last")
              .head(12)[["cons_name", "harmonized_nsu_unit", "n", "k_pooled",
                         "n_shared_labels", "within_label_ratio", "vendors_disjoint",
                         "unit_med_ratio_UNFAIR", "grp_purity_by_unit", "units"]]
              .to_string(index=False))
        c1.sort_values("within_label_ratio", ascending=False,
                       na_position="last").to_csv(
            OUT + r"\issue21_outcome1_fold_check.csv", index=False,
            encoding="utf-8-sig")

    # ================================================================ Q7
    h("Q7  DO THE POOLED RAW UNITS CARRY DIFFERENT RUNG COMPOSITIONS")
    # The scenario: one raw unit carries only a municipality median, the other carries
    # the full mp25/50/75 triple. Neither has "two full ladders", so a count of
    # two-ladder cases misses it entirely -- but the pooled case still has to reconcile
    # a median against a triple. Worse for Outcome 1: nsu_reference_set.do sec 2b maps
    # mp50 AND municipality median AND province median all onto size_ord = 2, so the
    # median from unit B is averaged into the same "medium" cell as the mp50 weighings
    # from unit A.
    def composition(types):
        t = set(types)
        q = [p for p in QUART if p in t]
        if len(q) == 3:
            return "full_triple"
        if q:
            return "partial_quartile(" + ",".join(x[2:4] for x in q) + ")"
        if "unique_mun_price" in t:
            return "unique_only"
        if t:
            return "median_only"
        return "none"

    comp = (pr.groupby(HKEY + ["pull_nsu_unit"]).price_type
              .agg(composition).rename("comp").reset_index())
    per = comp.groupby(HKEY).comp.agg([("n_units", "size"),
                                       ("n_distinct", "nunique"),
                                       ("mix", lambda s: " + ".join(sorted(s)))])
    multi = per[per.n_units > 1]
    print(f"cases pooling >1 priced raw unit               {len(multi):>6}")
    print(f"  raw units carry DIFFERENT compositions      "
          f"{int((multi.n_distinct > 1).sum()):>6}"
          "   <- the scenario in the question")
    print(f"  raw units carry the SAME composition        "
          f"{int((multi.n_distinct == 1).sum()):>6}")
    print("\ncomposition mixes, most common first:")
    print(multi.mix.value_counts().head(15).to_string())
    print("\nOf the mismatched cases, how many involve a triple against a bare median:")
    tvm = multi[(multi.n_distinct > 1)
                & multi.mix.str.contains("full_triple")
                & multi.mix.str.contains("median_only")]
    print(f"  full_triple + median_only                   {len(tvm):>6}")
    multi.reset_index().to_csv(OUT + r"\issue21_rung_composition_mix.csv",
                               index=False, encoding="utf-8-sig")

    # --- and the Outcome 1 collision this creates
    # The size-based branch reads its groups off the enumerator's own S/M/L judgement,
    # so the price file is absent there. The PRICE-QUANTITY branch does not: sec 2b of
    # nsu_reference_set.do reads size_ord straight off the rung recorded in obs_type,
    # and that rung is a copy of the price-file structure -- the enumerator was sent to
    # spend a preloaded mp25/mp50/mp75/median, so the MS label echoes the price file
    # rather than observing size independently. 311 of 2,005 Outcome 1 cases (15.5%)
    # are on that branch, so the price file DOES reach Outcome 1; it just reaches it
    # through a different door than the terciles.
    print("\nOUTCOME 1 COLLISION: mp50 / mun_median / prov_median all -> size_ord 2.")
    MED = [6, 8, 9]
    pqms = ms[(ms.weighing_approach == 2) & ms.w.notna()].copy()
    med = pqms[pqms.item_nsu_hetero_type.isin(MED)]
    coll = med.groupby(CKEY).agg(n_units=("pull_nsu_unit", "nunique"),
                                 n_lbls=("item_nsu_hetero_type", "nunique"),
                                 n=("w", "size"))
    hit = coll[(coll.n_units > 1) | (coll.n_lbls > 1)]
    print(f"  price-quantity cases whose 'medium' cell pools >1 raw unit or >1 label:"
          f" {len(hit)} / {len(coll)}")
    if len(hit):
        j = med.set_index(CKEY).index.isin(set(hit.index))
        sp = med[j].groupby(CKEY).w.agg(["min", "max", "size"])
        sp["ratio"] = sp["max"] / sp["min"].replace(0, float("nan"))
        print("  spread of weights inside those merged 'medium' cells:")
        print(sp.ratio.describe()[["50%", "max"]].to_string())
        print(f"  cells whose merged 'medium' spans >=2x in weight:"
              f" {int((sp.ratio >= 2).sum())}")
        # name them: at this count the cases are worth inspecting individually rather
        # than only being counted
        print("\n  every price-quantity case pooling >1 raw unit, in full:")
        for kk, gg in med[j].groupby(CKEY):
            parts = [f"{u}:[{','.join(sorted(LBL[int(t)] for t in v.item_nsu_hetero_type))}]"
                     f" n{len(v)} med{v.w.median():.0f}g"
                     for u, v in gg.groupby("pull_nsu_unit")]
            print(f"    {kk[0]}/{kk[1]} {str(kk[2])[:32]:32s} {str(kk[3])[:18]:18s} "
                  + " | ".join(parts))
        print("  Both sides collapse to a single published 'medium', so the spread"
              " above is BETWEEN raw units, not within a size.")

    # ================================================================ Q8
    h("Q8  THE COST OF 'QUARTILES TAKE PRECEDENCE' IN A MIXED-COMPOSITION CASE")
    # points_pooled() in this file (and tally_price_points.py, which it follows) counts
    # quartile LEVELS whenever any quartile is present, and ignores every median in the
    # case. So a case where raw unit A carries the full mp25/50/75 triple and raw unit B
    # carries only a municipality median reports points_pooled = 3 and looks CLEAN in
    # Q1 -- the mixed composition is invisible to that statistic by construction.
    #
    # It is not clean. B's price is discarded, but B's WEIGHINGS are still pooled into
    # the case and get re-sliced onto A's three rungs. The weighings therefore sit on a
    # price ladder measured for a different raw unit. This section counts the rows that
    # happens to, and asks whether the two units are even the same size.
    comp_m = comp.set_index(HKEY + ["pull_nsu_unit"]).comp
    tri = comp_m[comp_m == "full_triple"]
    med_only = comp_m[comp_m == "median_only"]
    tri_cases = {k[:4] for k in tri.index}
    med_cases = {k[:4] for k in med_only.index}
    mixed = tri_cases & med_cases
    print(f"cases with a full triple AND a median-only raw unit   {len(mixed):>6}")

    # which raw units in those cases are the discarded-price side
    disc = {(k[:4], k[4]) for k in med_only.index if k[:4] in mixed}
    keep = {(k[:4], k[4]) for k in tri.index if k[:4] in mixed}
    print(f"  raw units whose price is DISCARDED by the rule       {len(disc):>6}")
    print(f"  raw units whose ladder is KEPT                       {len(keep):>6}")

    msi = ms[ms.w.notna()].copy()
    msi["_c"] = list(zip(*[msi[c] for c in HKEY]))
    msi["_cu"] = list(zip(msi._c, msi.pull_nsu_unit))
    aff_rows = msi[msi._cu.isin(disc)]
    keep_rows = msi[msi._cu.isin(keep)]
    print(f"\nMS weighings on a discarded-price raw unit           {len(aff_rows):>6}")
    print(f"MS weighings on the kept-ladder raw unit             {len(keep_rows):>6}")
    print("Every row in the first group is re-sliced onto a price ladder that was")
    print("measured for the OTHER raw unit.")
    if len(aff_rows):
        print("\nbranch of the discarded-price weighings:")
        print(aff_rows.weighing_approach.map(BRANCH).value_counts().to_string())

    # are the two sides even the same size? if not, the transplant is not defensible
    rows = []
    for c in sorted(mixed):
        a = keep_rows[keep_rows._c == c]
        b = aff_rows[aff_rows._c == c]
        if not len(a) or not len(b):
            continue
        ma, mb = a.w.median(), b.w.median()
        rows.append(dict(zip(HKEY, c)) | {
            "n_kept": len(a), "n_discarded": len(b),
            "med_kept": ma, "med_discarded": mb,
            "med_ratio": max(ma, mb) / min(ma, mb) if min(ma, mb) else float("nan"),
            "units_kept": " | ".join(sorted(a.pull_nsu_unit.unique())),
            "units_discarded": " | ".join(sorted(b.pull_nsu_unit.unique()))})
    q8 = pd.DataFrame(rows)
    print(f"\ncases where BOTH sides were actually weighed          {len(q8):>6}")
    if len(q8):
        print("  between-side median weight ratio:")
        print(q8.med_ratio.describe()[["50%", "max"]].to_string())
        print(f"  sides differing >=1.5x in median weight:            "
              f"{int((q8.med_ratio >= 1.5).sum()):>6}")
        print(f"  sides differing >=2x:                               "
              f"{int((q8.med_ratio >= 2).sum()):>6}")
        print("\n  worst 10:")
        print(q8.sort_values("med_ratio", ascending=False).head(10)[
            ["cons_name", "harmonized_nsu_unit", "n_kept", "n_discarded",
             "med_kept", "med_discarded", "med_ratio",
             "units_kept", "units_discarded"]].to_string(index=False))
        q8.sort_values("med_ratio", ascending=False).to_csv(
            OUT + r"\issue21_discarded_median_units.csv", index=False,
            encoding="utf-8-sig")

    # ================================================================ Q9
    h("Q9  WHICH BRANCH THE DISAGREEMENTS SIT ON, AND WHETHER MEDIANS EVER DISAGREE")
    # Two questions that decide how much of this issue is actionable.
    #
    # (a) Level disagreement -- two spellings quoting different values for the SAME rung
    #     -- only matters where the price file supplies the rungs. On a price-quantity
    #     case the enumerator spent an actual observed amount (pull_price), so the
    #     price-file level is not what the conversion rests on. If every disagreeing
    #     case is size-based, the exposure is confined to Outcome 2's size-based branch.
    #
    # (b) The median-only cases. points_pooled() returns 1 point for a case whose
    #     spellings all carry only a median, which silently assumes the medians AGREE.
    #     If they ever disagree, that assumption hides an unresolved choice of which
    #     median to use. Checked directly rather than assumed.
    # The price CSV spells these with SPACES; the SurveyCTO case files use
    # underscored COLUMN names for the same concepts. An earlier version of this
    # check used the underscored spellings against the CSV, matched nothing, and
    # reported zero disagreements -- a false negative that read as a clean result.
    # The assertion near the top of main() now fails loudly on such a drift.
    MED = ["municipality median", "province median"]
    branch_of = ms.groupby(HKEY).weighing_approach.agg(
        lambda s: "/".join(sorted({BRANCH.get(int(x), str(x)) for x in s.dropna()})))

    print("(a) LEVEL DISAGREEMENT, BY MS BRANCH")
    qq = pr[pr.price_type.isin(QUART)]
    nl = qq.groupby(HKEY).pull_nsu_unit.nunique()
    cand = set(nl[nl > 1].index)
    dis = set()
    for kk, g in qq[qq.set_index(HKEY).index.isin(cand)].groupby(HKEY + ["price_type"]):
        if g.price.dropna().nunique() > 1:
            dis.add(kk[:4])
    print(f"  cases with >=1 rung whose spellings quote different levels: {len(dis)}")
    bb = branch_of.reindex(sorted(dis))
    print("  MS branch of those cases:")
    for k, v in bb.value_counts(dropna=False).items():
        lbl = "no MS weighings at all (price-file-only cell)" if pd.isna(k) else k
        print(f"    {lbl:<48} {v:>4}")
    if not (bb.dropna() != "size-based").any():
        print("  ALL are size-based. The price file supplies the rungs only there, so")
        print("  this is confined to Outcome 2's size-based branch. It is a precision")
        print("  question -- two estimates of one unit's price distribution, computed on")
        print("  differently-spelled subsets -- not a correctness one.")

    print("\n(b) DO THE MEDIAN-ONLY CASES EVER DISAGREE")
    def comp_all_median(s):
        t = set(s)
        return (not (t & set(QUART))) and ("unique_mun_price" not in t) and bool(t)
    cm = pr.groupby(HKEY + ["pull_nsu_unit"]).price_type.agg(comp_all_median)
    per = cm.groupby(level=[0, 1, 2, 3]).agg([("n", "size"), ("all_med", "all")])
    mmed = per[(per.n > 1) & per.all_med]
    print(f"  cases where EVERY pooled spelling carries only a median: {len(mmed)}")
    nbad, gaps = 0, []
    for k in mmed.index:
        g = pr[pr.set_index(HKEY).index == k]
        g = g[g.price_type.isin(MED)]
        hit = False
        for pt, v in g.groupby("price_type"):
            lv = v.price.dropna().unique()
            if len(lv) > 1:
                hit = True
                gaps.append({"case": " / ".join(str(x) for x in k),
                             "price_type": pt, "n_levels": len(lv),
                             "lo": lv.min(), "hi": lv.max(),
                             "ratio": (lv.max() / lv.min()) if lv.min() else None,
                             "branch": branch_of.get(k, "(no MS rows)")})
        nbad += int(hit)
    print(f"    ...where a median TYPE has spellings quoting different levels: {nbad}")
    if nbad:
        gd = pd.DataFrame(gaps)
        print("")
        print("  NOT ZERO. points_pooled() credits each of these cases with ONE")
        print("  price point, which assumes the medians agree. They do not, so the")
        print("  case carries an unresolved choice of WHICH median to use.")
        print("")
        print("  ratio hi/lo across the disagreeing spellings:")
        print(gd.ratio.describe()[["50%", "75%", "max"]].to_string())
        print("")
        print("  MS branch of the disagreeing cases:")
        vc = gd.drop_duplicates("case").branch.value_counts(dropna=False)
        for kk, vv in vc.items():
            lbl = "no MS weighings" if pd.isna(kk) else str(kk)
            print(f"    {lbl:<44} {vv:>4}")
        print("")
        print("  worst 10 by ratio:")
        print(gd.sort_values("ratio", ascending=False).head(10)[
            ["case", "price_type", "lo", "hi", "ratio", "branch"]]
            .to_string(index=False))
        gd.sort_values("ratio", ascending=False).to_csv(
            OUT + r"\issue21_median_disagreement.csv", index=False,
            encoding="utf-8-sig")
    else:
        print("  ZERO -- the medians always agree, so one point is safe here.")

    print("\nwrote tables to outputs/tables/issue21_*.csv")


if __name__ == "__main__":
    main()
