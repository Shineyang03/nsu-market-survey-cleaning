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

WHAT THIS SCRIPT DOES. It measures the problem; it decides nothing. Eight questions:

  Q1   how many harmonized cases pool more than one PRICED raw unit, and how many
       price points they end up with under two readings (pooled levels vs naive
       label union)
  Q2   when two raw units both carry a ladder, how far apart are the prices
  Q3   do the pooled raw units have different median WEIGHTS in the market survey,
       and how much precision is bought by pooling them (n per unit)
  Q4   which weighing branch the affected cases sit on, and whether the inflation
       adjustment interacts with any of this
  Q5   whether the duplication reaches the MS weighing rows at all
  Q6   whether pooling contaminates Outcome 1: does it inflate the size count, and do
       the re-cut terciles track the raw unit instead of the field label
  Q7   whether the pooled raw units carry DIFFERENT rung compositions (a bare median
       against a full triple), and the 'medium' collision that creates in Outcome 1
  Q8   what 'quartiles take precedence' costs in a mixed-composition case: how many
       weighings sit on a price ladder measured for a different raw unit

HARMONIZATION IS NOT RE-DERIVED HERE. The raw -> harmonized map is read from
outputs/tables/master_nsu_rename.csv, written by dofiles/diagnose_price_only.py, which
is the single authoritative implementation. The nz/ni/ng normalizers below are copied
from that file only to join onto it: drop non-ASCII outright, case-fold, trim, collapse
internal whitespace. Never NFKD-decompose first -- DUENAS must become DUEAS, not
DUENAS, or the join silently loses rows.

RUN
    python dofiles/scope_multi_price_points.py

OUTPUTS  (outputs/tables/)
    issue21_points_per_case.csv     one row per harmonized case in the price file:
                                    price points under each reading, raw units pooled
    issue21_price_disagreement.csv  case x price_type pairs whose raw units disagree
    issue21_weight_disagreement.csv case-level weight comparison across pooled units
    issue21_outcome1_tercile_contamination.csv   per pooled size-based case: pooled vs
                                    single-unit size count, between-unit weight ratio,
                                    and whether the tercile splits units or sizes
    issue21_rung_composition_mix.csv            per case: what rung composition each
                                    pooled raw unit carries, and whether they differ
    issue21_discarded_median_units.csv          cases where a median-only raw unit's
                                    price is dropped in favour of another unit's triple,
                                    with the weight gap between the two sides
    a printed report on stdout
"""
import re
import sys

import pandas as pd

BOX = (r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey")
DC = BOX + r"\Data Cleaning"
PRICE = BOX + r"\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv"
XW = DC + r"\outputs\tables\master_nsu_rename.csv"
MS = DC + r"\outputs\master_rename_build\temp\nsu_weights_restated.dta"
OUT = DC + r"\outputs\tables"

QUART = ["mp25_price", "mp50_price", "mp75_price"]
DIM = {1.0: "g", 2.0: "mL"}
BRANCH = {1.0: "conventional", 2.0: "price-quantity", 3.0: "size-based"}


# ---------------------------------------------------------------- normalizers
# Copied from dofiles/diagnose_price_only.py. Order matters; see the module docstring.
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
    print(f"price rows                          {len(pr):>6}")
    print(f"  unmatched to the crosswalk        {miss:>6}")
    if miss:
        # A miss means the normalizer or the crosswalk disagrees with the price file,
        # not that the row is uninteresting. Do not silently proceed.
        print(pr[pr.harmonized_nsu_unit.isna()][KEY + ["pull_nsu_unit"]]
              .drop_duplicates().to_string(index=False))
        sys.exit("unmatched price rows -- fix the join before reading any figure below")
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

    Follows dofiles/tally_price_points.py: a full mp25/50/75 triple gives 3 points; a
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
    h("Q6  DOES POOLING CONTAMINATE OUTCOME 1's TERCILES (size-based branch)")
    # Q5 established that the duplication reaches the MS rows only as repeated SIZE
    # labels, and concluded that pooling "already collapses" them. That conclusion was
    # wrong and this section is why. Outcome 1 does not publish the label -- it pools
    # the WEIGHTS behind the labels and re-cuts them into terciles
    # (dofiles/nsu_reference_set.do sec 2c). So when two physically different raw units
    # are pooled, the cut points are computed on a MIXTURE of two units. If the units
    # differ in size more than the sizes differ within a unit, the terciles separate
    # UNITS and the published "small/medium/large" is really "unit A / unit B".
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
        rows.append(dict(zip(CKEY, k)) | {
            "n": len(g), "n_units": int(g.pull_nsu_unit.nunique()),
            "k_pooled": k_pooled, "k_best_single_unit": k_best_unit,
            "k_inflated_by_pooling": int(k_pooled > k_best_unit),
            "unit_med_ratio": float(med.max() / med.min()) if med.min() else float("nan"),
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
        print("  S/M/L is really 'which raw unit', not 'what size'.")
        print(c1[["grp_purity_by_unit", "grp_purity_by_label"]].describe()
              .loc[["mean", "50%", "max"]].to_string())
        worse = c1[c1.grp_purity_by_unit > c1.grp_purity_by_label]
        print(f"\n  cases where the tercile tracks the UNIT better than the LABEL:"
              f" {len(worse)} / {len(c1)}")
        perfect = c1[(c1.grp_purity_by_unit == 1.0) & (c1.n_units > 1)]
        print(f"  cases where the tercile is a PERFECT unit split:  {len(perfect)}")
        big = c1[c1.unit_med_ratio >= 2]
        print(f"  cases whose pooled raw units differ >=2x in median weight: {len(big)}")
        print("\n  worst 12 by between-unit median ratio:")
        print(c1.sort_values("unit_med_ratio", ascending=False)
              .head(12)[["cons_name", "harmonized_nsu_unit", "n", "k_pooled",
                         "k_best_single_unit", "unit_med_ratio",
                         "grp_purity_by_unit", "grp_purity_by_label", "units"]]
              .to_string(index=False))
        c1.sort_values("unit_med_ratio", ascending=False).to_csv(
            OUT + r"\issue21_outcome1_tercile_contamination.csv", index=False,
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

    print("\nwrote tables to outputs/tables/issue21_*.csv")


if __name__ == "__main__":
    main()
