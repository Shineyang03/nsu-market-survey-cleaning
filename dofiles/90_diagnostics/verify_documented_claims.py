from pathlib import Path
"""Re-derive every quantitative claim in docs/ that is not produced by a build file.

WHY THIS EXISTS. Most numbers in docs/ come out of a build step whose code is saved:
the reference-set counts from 10_reference_set/12_publish_reference_set.do, the inflation figures from
plot_cpi_inflation.py, the price-point tally from tally_price_points.py, the summary
tables from summary_statistics.py. A second group of numbers came from one-off
verification checks -- "does harmonization cost uniqueness", "does pull_price really
match the preload", "is the kg band empty" -- which were run to settle a question and
then discarded. Those numbers are load-bearing (several of them are the reason a
pipeline rule looks the way it does) but were unreproducible. This file is the one
place they are re-derived.

HOW TO READ THE OUTPUT. Each check prints the value recorded in docs/ beside the value
computed now, and a verdict:

    OK        the two agree -- the documented number is still true
    CHANGED   they differ. Not automatically a bug: the pipeline moves, and a number
              written before a fix landed can be legitimately superseded. But every
              CHANGED line needs a human decision -- update the doc, or fix the code.
    SKIPPED   an input is missing, so the check could not run

The exit status is 1 if anything is CHANGED, so this can be wired into a pre-commit
hook or run after any pipeline change.

WHERE EACH CLAIM LIVES. The `doc` field of each check names the file and section, so a
CHANGED verdict points straight at the text that needs editing.

RUN
    python dofiles/90_diagnostics/verify_documented_claims.py
"""
import glob
import re
import sys

import numpy as np
import pandas as pd

BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"
LAUNCH = BOX + r"\NSU Market Survey Launch"
TEMP = DC + r"\outputs\master_rename_build\temp"

RAW = LAUNCH + r"\data\PSPS NSU Market Survey Launch.dta"
PRICE = LAUNCH + r"\data\NSU_prices_from_Makayla.csv"
CASES = LAUNCH + r"\cases\nsu_cases_*.csv"
PRELIM = TEMP + r"\prelim_nsu_data.dta"
RESTATED = TEMP + r"\nsu_weighings_cpi.dta"
SIZED = TEMP + r"\ref_10_sized.dta"
XW = DC + r"\outputs\tables\master_nsu_rename.csv"

results = []


# The one definition of the project's string normalization, imported rather than
# copied. There used to be eleven byte-identical copies of these four functions across
# 90_diagnostics/; a fix to any one of them reached none of the others. The Stata
# counterpart is nsu_normalize in 00_shared/00_globals.do and must agree with it
# character for character -- see the module docstring.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import A, nz, ni, ng


def check(name, doc, recorded, computed, note=""):
    same = recorded == computed
    results.append((name, doc, recorded, computed, "OK" if same else "CHANGED", note))
    print(f"  [{'OK     ' if same else 'CHANGED'}] {name}")
    print(f"            doc: {recorded}")
    print(f"            now: {computed}")
    if note:
        print(f"            {note}")


def skip(name, doc, why):
    results.append((name, doc, "", "", "SKIPPED", why))
    print(f"  [SKIPPED] {name}\n            {why}")


def head(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


# ============================================================ 1. harmonization
def c_harmonization_uniqueness(d):
    """Pooling raw NSU spellings into a harmonized unit must not make two distinct
    weighings collide. If the harmonized key is as unique as the raw key, the fold
    costs nothing in identification -- which is what licenses using the harmonized
    unit as the pooling key everywhere downstream.

    docs/conversion_factor_methodology.md, "What identifies a row, at each stage"
    """
    base = ["pull_province", "pull_municipal_city", "pull_item",
            "market_type", "vendor_id", "item_nsu_hetero_type"]
    raw = d.groupby(base + ["pull_nsu_unit"], dropna=False).ngroups
    harm = d.groupby(base + ["harmonized_nsu_unit"], dropna=False).ngroups
    check("harmonization costs no uniqueness",
          "conversion_factor_methodology.md / What identifies a row",
          "rows == raw groups == harmonized groups",
          "rows == raw groups == harmonized groups"
          if len(d) == raw == harm else
          f"NOT equal: rows {len(d):,}, raw {raw:,}, harmonized {harm:,}",
          f"rows {len(d):,}, raw-key groups {raw:,},"
          f" harmonized-key groups {harm:,};"
          " if these ever diverge the harmonized unit is not a safe pooling key")


# ============================================================ 2. pull_price
def c_pull_price_preload(d):
    """pull_price is documented as system-filled from the PSPS price the enumerator was
    sent to spend, not entered by hand. The SurveyCTO case files carry that preload, so
    the two can be compared directly.

    docs/data_oddities.md sec.3; conversion_factor_methodology.md Notation
    """
    files = sorted(glob.glob(CASES))
    if not files:
        return skip("pull_price matches the case-file preload",
                    "data_oddities.md sec.3", f"no case files at {CASES}")
    cs = []
    for f in files:
        try:
            c = pd.read_csv(f, dtype=str, encoding="utf-8-sig", low_memory=False)
        except Exception:
            continue
        if "uuid" not in c.columns:
            continue
        cs.append(c)
    cf = pd.concat(cs, ignore_index=True)

    # The preload the enumerator was sent with, by hetero-group label. uuid alone is
    # UNSAFE as a key (item_unit_MUNICIPALITY, no province: PONTEVEDRA and SAN ENRIQUE
    # each occur in two provinces), so join on province as well.
    long = []
    labmap = {"mp25_price": 5, "mp50_price": 6, "mp75_price": 7,
              "municipality_median": 8, "province_median": 9,
              "unique_mun_price1": 10, "unique_mun_price2": 11}
    for col, code in labmap.items():
        if col not in cf.columns:
            continue
        t = cf[["province", "pull_municipal_city", "item", "unit_lbl", col]].copy()
        t["item_nsu_hetero_type"] = float(code)
        t["preload"] = pd.to_numeric(t[col], errors="coerce")
        long.append(t.drop(columns=[col]))
    cl = pd.concat(long, ignore_index=True).dropna(subset=["preload"])
    for c, f in [("province", ng), ("pull_municipal_city", ng),
                 ("item", ni), ("unit_lbl", nz)]:
        cl[c] = cl[c].map(f)
    cl = cl.rename(columns={"item": "cons_name", "unit_lbl": "pull_nsu_unit"})
    cl = cl.groupby(["province", "pull_municipal_city", "cons_name",
                     "pull_nsu_unit", "item_nsu_hetero_type"], dropna=False) \
           .preload.median().reset_index()

    m = d[d.weighing_approach == 2].copy()
    m["province"] = m.pull_province.map(ng)
    m["pull_municipal_city"] = m.pull_municipal_city.map(ng)
    m["cons_name"] = m.pull_item.map(ni)
    m["pull_nsu_unit"] = m.pull_nsu_unit.map(nz)
    m["pp"] = pd.to_numeric(m.pull_price, errors="coerce")
    m = m.dropna(subset=["pp"])
    j = m.merge(cl, on=["province", "pull_municipal_city", "cons_name",
                        "pull_nsu_unit", "item_nsu_hetero_type"], how="left")
    matched = j.preload.notna()
    agree = (matched & ((j.pp - j.preload).abs() < 0.01)).sum()
    check("pull_price matches the case-file preload",
          "data_oddities.md sec.3",
          "1,105 of 1,105 matched rows agree; 98.5% coverage",
          f"{agree:,} of {int(matched.sum()):,} matched rows agree;"
          f" {100 * matched.mean():.1f}% coverage",
          "join is on province + municipality + item + raw unit + hetero-group;"
          " uuid alone is ambiguous across provinces")


# ============================================================ 3. unique_mun_price
def c_unique_mun_never_alone():
    """unique_mun_price is a municipal price level, not a size. The pipeline drops it
    from the size ladder (hetero-group codes 10 and 11), which is only safe if it never
    arrives as a case's ONLY price information.

    docs/conversion_factor_methodology.md, Step A
    """
    pr = pd.read_csv(PRICE, encoding="utf-8-sig", dtype=str)
    pr["province"] = pr.province.map(ng)
    pr["pull_municipal_city"] = pr.pull_municipal_city.map(ng)
    pr["cons_name"] = pr.cons_name.map(ni)
    pr["pull_nsu_unit"] = pr.Unit_lbl.map(nz)
    key = ["province", "pull_municipal_city", "cons_name", "pull_nsu_unit"]
    QUART = {"mp25_price", "mp50_price", "mp75_price"}
    combos = {}
    alone = 0
    with_prov = 0
    with_triple = 0
    for _, g in pr.groupby(key):
        types = set(g.price_type)
        if "unique_mun_price" not in types:
            continue
        rest = types - {"unique_mun_price"}
        combos[frozenset(rest)] = combos.get(frozenset(rest), 0) + 1
        if not rest:
            alone += 1
        if rest == {"province median"}:
            with_prov += 1
        if QUART <= types:
            with_triple += 1
    check("unique_mun_price never appears alone",
          "conversion_factor_methodology.md / Step A",
          "0 alone; 350 with province median; 4 with the full triple",
          f"{alone} alone; {with_prov} with province median;"
          f" {with_triple} with the full triple",
          "co-occurring types: "
          + ", ".join(f"{sorted(k) or ['(alone)']}={v}" for k, v in
                      sorted(combos.items(), key=lambda kv: -kv[1])))


# ============================================================ 4. price coverage
def c_size_cells_have_prices(d):
    """Every size-based case must have a price-file row, or its sizes cannot be paired
    with a price point and Outcome 2 has nothing to convert.

    docs/conversion_factor_methodology.md, Step A
    """
    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)
    for c, f in [("province", ng), ("pull_municipal_city", ng),
                 ("cons_name", ni), ("harmonized_nsu_unit", nz)]:
        xw[c] = xw[c].map(f)
    priced = set(map(tuple, xw[xw.source.isin(["MS & Price", "Price Only"])]
                     [["province", "pull_municipal_city", "cons_name",
                       "harmonized_nsu_unit"]].dropna().values))
    s = d[d.weighing_approach == 3].copy()
    s["province"] = s.pull_province.map(ng)
    s["pull_municipal_city"] = s.pull_municipal_city.map(ng)
    s["cons_name"] = s.pull_item.map(ni)
    s["harmonized_nsu_unit"] = s.harmonized_nsu_unit.map(nz)
    cells = set(map(tuple, s[["province", "pull_municipal_city", "cons_name",
                              "harmonized_nsu_unit"]].drop_duplicates().values))
    miss = sorted(cells - priced)
    hit = len(cells) - len(miss)
    check("every size-based cell has a price-file row",
          "conversion_factor_methodology.md / Step A",
          "1 uncovered: ILOILO / DUEAS / cabbage / putos (mix vegetable)",
          # Was temporarily 2. The ANTIQUE / HAMTIC "bottle 500ml" cell was uncovered
          # only because the crosswalk had already dropped the raw label "500" while
          # the restated .dta still carried its five weighings. The pipeline re-run
          # cleared that: those rows are now excluded upstream as an ambiguous
          # quantity, and the count is back to the single genuine exception.
          #
          # That one is DELIBERATE and is issue #22: putos (mix vegetable) is a fold
          # target that exists on the market-survey side only, so the price file --
          # keyed on the raw label -- has nothing that folds to it in this cell. A
          # SECOND uncovered cell means a new fold target with no price counterpart,
          # which is a finding, not noise.
          ("all size-based cells covered" if not miss else
           f"{len(miss)} uncovered: "
           + "; ".join(" / ".join(m) for m in miss[:5])),
          f"{hit:,} of {len(cells):,} covered."
          + ("" if not miss else "  UNCOVERED: "
             + "; ".join(" / ".join(m) for m in miss[:5])))


# ============================================================ 5-6. magnitude rules
def c_kg_band_empty(prelim):
    """KGMAX = 30 splits a believed kg tick from a gram value mis-ticked as kg. The
    threshold is defensible only because the band just above it is empty -- there is no
    observation whose classification the exact cut-point decides.

    docs/data_oddities.md sec.9, "Why KGMAX = 30"
    """
    w = pd.to_numeric(prelim.weight, errors="coerce")
    kg = prelim.unit == 1
    bands = {"(20,30]": int(((w > 20) & (w <= 30) & kg).sum()),
             "(30,50]": int(((w > 30) & (w <= 50) & kg).sum()),
             "(50,inf)": int(((w > 50) & kg).sum())}
    check("the kg band (30,50] is empty",
          "data_oddities.md sec.9",
          "0 rows in (30,50]",
          f"{bands['(30,50]']} rows in (30,50]",
          f"neighbouring bands: (20,30] = {bands['(20,30]']},"
          f" (50,inf) = {bands['(50,inf)']}")
    check("rows read as grams mis-ticked as kg",
          "data_oddities.md sec.9",
          "86 rows with weight > 30 & unit == kg",
          f"{int(((w > 30) & kg).sum())} rows with weight > 30 & unit == kg")


def c_litres_rule(prelim):
    """The litres rule reads weight >= 10 with unit == Litres as "already mL". A
    truthful 20 L would therefore become 20 mL. The rule is safe today only because
    every row in that band happens to be a mL mis-tick -- an accident, not a design.

    docs/data_oddities.md sec.9, "Known hazard, not yet fixed"
    """
    w = pd.to_numeric(prelim.weight, errors="coerce")
    sel = (prelim.unit == 3) & (w >= 10)
    n = int(sel.sum())
    check("rows exposed to the litres >= 10 rule",
          "data_oddities.md sec.9 (known hazard)",
          "67 rows",
          f"{n} rows",
          f"range {w[sel].min():.0f}-{w[sel].max():.0f}; every row here is treated as"
          " already-mL, so a genuine litre reading would be silently divided by 1,000."
          " The rule is safe only while this band holds no true litre value -- check the"
          " range, not just the count.")


def c_snap_band_partition(prelim):
    """The five threshold bands in sec.9's table, each re-counted, plus the assertion
    that they partition the rows with a weight EXHAUSTIVELY and without overlap.

    Why this check exists. The table's litres row read 1,620 for a while against an
    actual 1,615 -- it had absorbed the 5 rows that carry no weight at all. That made
    the bands appear to sum to 11,453, the full arrival count, when the population they
    can possibly cover is the 11,448 rows that HAVE a weight. A band table that sums to
    the wrong total is the one kind of error a reader cannot catch by adding it up, so
    the total is asserted here rather than written down.

    docs/data_oddities.md sec.9, band table
    """
    w = pd.to_numeric(prelim.weight, errors="coerce")
    u = pd.to_numeric(prelim.unit, errors="coerce")
    KGMAX = 30
    has = w.notna() & u.isin([1, 2, 3])

    bands = {
        "grams": (u == 2) & has,
        "litres": (u == 3) & has,
        "kg < 1": (u == 1) & (w < 1) & has,
        f"kg [1, {KGMAX}]": (u == 1) & (w >= 1) & (w <= KGMAX) & has,
        f"kg > {KGMAX}": (u == 1) & (w > KGMAX) & has,
    }
    recorded = {"grams": 9151, "litres": 1615, "kg < 1": 15,
                f"kg [1, {KGMAX}]": 581, f"kg > {KGMAX}": 86}
    counts = {k: int(m.sum()) for k, m in bands.items()}

    for k in bands:
        check(f"snap band: {k}",
              "data_oddities.md sec.9 band table",
              f"{recorded[k]:,} rows",
              f"{counts[k]:,} rows")

    # exhaustive and disjoint, both asserted rather than assumed
    stacked = sum(m.astype(int) for m in bands.values())
    overlap = int((stacked > 1).sum())
    uncovered = int((has & (stacked == 0)).sum())
    check("the snap bands partition every row that has a weight",
          "data_oddities.md sec.9 band table",
          f"{sum(recorded.values()):,} rows, 0 overlapping, 0 uncovered",
          f"{sum(counts.values()):,} rows, {overlap} overlapping, {uncovered} uncovered",
          f"population is unit in (1,2,3) & weight non-missing = {int(has.sum()):,} of"
          f" {len(prelim):,} rows reaching this step; the other {int((~has).sum())} carry"
          " no weight, so no magnitude rule can reach them. If the bands stop summing to"
          " the population, a row is being decided twice or not at all.")


def c_threshold_direction(prelim, corrected):
    """Every corrected weight is the canonical base times an INTEGER POWER OF TEN.

    This replaces an older check that asserted every row was scaled by exactly 1,000
    or left alone. That was the old magnitude rule's invariant. Since issue #18 A1 the
    decade is chosen by the cell anchor and can be any integer, so the surviving
    invariant is the weaker one tested here: the snap only ever moves the decimal
    point. A row that is NOT a power of ten off its base means something other than
    the snap edited the weight -- a manual correction, or a bug.

    docs/data_oddities.md sec.9
    """
    d = prelim[["id", "weight", "unit"]].merge(
        corrected[["id", "corrected_weight"]], on="id", how="inner", validate="1:1")
    d["w"] = pd.to_numeric(d.weight, errors="coerce")
    d["cw"] = pd.to_numeric(d.corrected_weight, errors="coerce")
    # canonical base: grams for mass, mL for volume. kg (1) and L (3) are x1000.
    d["base"] = d.w.where(d.unit == 2, d.w * 1000)

    ok = d.cw.notna() & d.base.notna() & (d.base > 0) & (d.cw > 0)
    # Compare against the ROUNDED target, not the raw ratio. The snap rounds to the
    # whole g/mL, so 95 g snapped down one decade is round(9.5) = 10, whose ratio is
    # 0.105 rather than 0.1. A log-distance tolerance flags that as a violation; a
    # rounded comparison recognises it as the decade shift it is. Stata's round() is
    # half-away-from-zero, so use floor(x + 0.5) rather than numpy's half-to-even.
    lg = np.log10(d.cw[ok] / d.base[ok])
    k = lg.round()
    target = np.floor(d.base[ok] * (10.0 ** k) + 0.5)
    # One unit of slack. `weight' is a Stata float, so base*10^k carries float32 error,
    # and the question here is "did the decimal point move", not "do these match to the
    # last bit". A rule other than the snap moves a weight by far more than 1 g/mL.
    is_pow10 = (d.cw[ok] - target).abs() <= 1.0
    n_pow, n_bad = int(is_pow10.sum()), int((~is_pow10).sum())
    shifts = lg[is_pow10].round().astype(int).value_counts().sort_index()
    spread = ", ".join(f"10^{k}: {v:,}" for k, v in shifts.items())

    check("the snap only moves the decimal point",
          "data_oddities.md sec.9",
          "every corrected weight is its base times an integer power of ten",
          "every corrected weight is its base times an integer power of ten"
          if n_bad == 0 else f"{n_bad:,} rows are not a power of ten off their base",
          f"{n_pow:,} rows verified. Decade shifts applied -- {spread}."
          " More than one shift is EXPECTED since #18 A1: the anchor picks the"
          " decade per cell. A non-power-of-ten row means something other than the"
          " snap moved the weight.")


# ============================================================ 7. item_group
def c_item_group_normalization(d):
    """item_group is a merge key in 00_shared/07_cpi_factor.do but passes through no
    normalizer, and it carries a non-ASCII character. The join survives only because
    both sides come from the same writer.

    GitHub issue #18
    """
    if "item_group" not in d.columns:
        return skip("item_group carries non-ASCII text",
                    "issue #18", "item_group absent from the restated file")
    ig = d.item_group.astype(str)
    bad = ig[ig != ig.map(A)]
    check("item_group carries non-ASCII text and is never normalized",
          "issue #18",
          "189 rows, 1 distinct value",
          f"{len(bad)} rows, {bad.nunique()} distinct value"
          + ("" if bad.nunique() == 1 else "s"),
          "the value, ASCII-stripped: "
          + "; ".join(A(v) for v in sorted(bad.unique()))
          + ". Used as a merge key in 00_shared/07_cpi_factor.do but passed through no"
          " normalizer, so a second producer of this string breaks the join.")


# ============================================================ 8. case counts
def c_case_counts(d):
    """The three case counts quoted in the Notation section, at the three vocabulary
    layers. They differ only by how many raw spellings each layer pools.

    docs/conversion_factor_methodology.md, Notation
    """
    base = ["pull_province", "pull_municipal_city", "pull_item"]
    n = {lvl: d.groupby(base + [lvl], dropna=False).ngroups
         for lvl in ["harmonized_nsu_unit", "cleaned_nsu_unit", "pull_nsu_unit"]}
    check("case counts by vocabulary layer",
          "conversion_factor_methodology.md / Notation",
          "1,951 harmonized / 1,963 cleaned / 1,991 raw",
          f"{n['harmonized_nsu_unit']:,} harmonized /"
          f" {n['cleaned_nsu_unit']:,} cleaned /"
          f" {n['pull_nsu_unit']:,} raw",
          "counted on the restated file, so post-attrition; the doc figure was taken"
          " at the same stage")


# ================================================== 11. the Outcome 1 label ranking
def c_label_rank_is_load_bearing(d):
    """Why 10_reference_set/10_size_assignment.do sec 2c ranks the field labels instead of mapping the
    tercile group number straight onto small/medium/large.

    The tercile cut returns groups numbered 1..k by ASCENDING WEIGHT; they carry no
    names. The names available are the labels the case actually recorded, which can be
    any subset of {S,M,L}. The do-file joins the two by rank: empirical group j takes
    the j-th smallest label PRESENT. The naive alternative -- group j takes the j-th
    label of the canonical ladder, so group 1 is always "small" -- is wrong for every
    case whose label set is not {S}, {S,M} or {S,M,L}.

    This check counts the cases where the two maps disagree, i.e. how much work the
    ranking is doing. If it ever falls to zero the ranking block is dead code and can
    be replaced by the naive map; while it is large, removing it silently mislabels
    that many cases.

    Scope note: this is the SIZE-BASED branch only (weighing_approach == 3), whose
    labels are the enumerator's small/medium/large. The price-quantity branch reads its
    size straight off the price-file rung (sec 2b) and needs no ranking.

    docs/conversion_factor_methodology.md / Outcome 1, size assignment
    """
    CELL = ["pull_province", "pull_municipal_city", "pull_item",
            "harmonized_nsu_unit", "corrected_unit"]      # the Outcome 1 case grain
    d = d[d.corrected_weight.notna() & ~d.item_nsu_hetero_type.isin([10, 11])]
    # mixed-branch cells: Outcome 1 keeps the size-based rows only
    g = d.groupby(CELL, dropna=False).weighing_approach
    d = d[~(g.transform(lambda s: (s == 3).any())
            & g.transform(lambda s: (s == 2).any())
            & (d.weighing_approach == 2))]
    sb = d[d.weighing_approach == 3].copy()
    sb["field_ord"] = sb.item_nsu_hetero_type.map({2: 1, 3: 2, 4: 3})
    if sb.field_ord.isna().any():
        skip("the label ranking is load-bearing",
             "conversion_factor_methodology.md / Outcome 1",
             "a size-based row carries a hetero_type outside 2/3/4")
        return
    lab = sb.groupby(CELL, dropna=False).field_ord.agg(
        lambda s: tuple(sorted({int(x) for x in s})))
    # the naive map agrees only where the labels present are the first k of the ladder
    naive_ok = lab.map(lambda t: t == tuple(range(1, len(t) + 1)))
    bad = int((~naive_ok).sum())
    NAME = {1: "S", 2: "M", 3: "L"}
    detail = (lab[~naive_ok].map(lambda t: "{" + ",".join(NAME[x] for x in t) + "}")
              .value_counts())
    check("the label ranking is load-bearing",
          "conversion_factor_methodology.md / Outcome 1, size assignment",
          "450 of 1,570 size-based cases would be mislabelled by a naive grp->S/M/L map",
          f"{bad:,} of {len(lab):,} size-based cases would be mislabelled"
          " by a naive grp->S/M/L map",
          "disagreeing label sets: "
          + ", ".join(f"{k} x{v}" for k, v in detail.items())
          + ". A case holding only {L} would publish its weight as 'small'.")


def c_underfilled_shapes(sized):
    """The (k_sizes, groups-filled) partition that the under-filled naming rule in
    10_size_assignment.do sec 2d is keyed on, and the exposure of getting that key wrong.

    conversion_factor_methodology.md / "Under-filled cases: naming the groups that
    actually survived"
    """
    d = sized[(sized.weighing_approach == 3) & sized.grp.notna()].copy()
    d["n_filled"] = d.groupby("cell").grp.transform("nunique")
    cells = d.drop_duplicates("cell")

    under = cells[cells.n_filled < cells.k_sizes]
    check("under-filled size-based cases",
          "methodology.md / under-filled cases",
          "104 cases fill fewer groups than the field recorded labels",
          f"{len(under):,} cases fill fewer groups than the field recorded labels",
          "must equal the count 11_size_checks.do sec 3 prints and"
          " ref_underfilled_sizes.xlsx holds")

    shape1 = under[under.n_filled == 1]
    fills = d.groupby("cell").grp.apply(lambda s: tuple(sorted(s.unique().astype(int))))
    two = under[under.n_filled == 2].set_index("cell")
    g12 = sum(1 for c in two.index if fills[c] == (1, 2))
    g13 = sum(1 for c in two.index if fills[c] == (1, 3))
    check("under-filled shapes: which groups emptied",
          "methodology.md / under-filled cases table",
          "39 with one group filled; 51 filled (1,2); 14 filled (1,3)",
          f"{len(shape1)} with one group filled; {g12} filled (1,2); {g13} filled (1,3)",
          "the (1,2) and (1,3) split is why the rule cannot be keyed on the number of"
          " filled groups alone -- 'small + large' is right for (1,3) and wrong for (1,2)")

    # exposure of the mis-keyed reading: cases that are NOT under-filled but would be
    # caught by a rule written as "one group filled -> medium"
    ok1 = cells[(cells.n_filled == 1) & (cells.n_filled == cells.k_sizes)]
    lab = (d[d.cell.isin(ok1.cell)].groupby("cell").item_nsu_hetero_type
             .apply(lambda s: tuple(sorted({int(x) for x in s}))))
    n_s = int((lab == (2,)).sum())
    n_l = int((lab == (4,)).sum())
    check("exposure if the rule were keyed on filled-groups alone",
          "methodology.md / under-filled cases, the keying warning",
          "757 not-under-filled cases would be caught; 411 field-small, 156 field-large",
          f"{len(ok1):,} not-under-filled cases would be caught;"
          f" {n_s} field-small, {n_l} field-large",
          "these have one label recorded AND one group filled, so they are correctly"
          " labelled today; a rule reading 'n_filled == 1' would overwrite them")


def c_modal_label_criterion(sized):
    """ASSUMPTION 7. The under-filled naming rule was chosen by asking whether a group's
    published label matches the MODAL field label of its own weighings. That treats the
    field label as noisy per weighing but informative in aggregate -- which is in tension
    with re-terciling existing at all.

    Measured on the cases where all three groups filled, so terciles and labels are both
    observable. The signed error is the part that matters: if it is not ~0, the criterion
    is biased toward one end of the ladder and every conclusion drawn from it inherits
    that bias.

    conversion_factor_methodology.md / Assumptions to keep visible, assumption 7
    """
    d = sized[(sized.weighing_approach == 3) & sized.grp.notna()].copy()
    d["n_filled"] = d.groupby("cell").grp.transform("nunique")
    LBL = {2: 1, 3: 2, 4: 3}
    d["field_sml"] = d.item_nsu_hetero_type.map(LBL)
    full = d[(d.k_sizes == 3) & (d.n_filled == 3)]

    per_row = int((full.field_sml == full.grp).sum())
    check("field label agrees with the tercile, per weighing",
          "methodology.md / assumption 7",
          "57.5% (3,201 of 5,566)",
          f"{per_row / len(full) * 100:.1f}% ({per_row:,} of {len(full):,})",
          "this is the number that justifies re-terciling in the first place -- the"
          " field label is wrong about a third of the time at row level")

    g = (full.groupby(["cell", "grp"]).field_sml
              .agg(lambda x: x.mode().iloc[0]).reset_index())
    per_grp = int((g.field_sml == g.grp).sum())
    check("modal field label agrees with the tercile, per group",
          "methodology.md / assumption 7",
          "66.5% (966 of 1,452)",
          f"{per_grp / len(g) * 100:.1f}% ({per_grp:,} of {len(g):,})",
          "aggregating recovers signal, which is what the naming criterion needs")

    err = (g.field_sml - g.grp)
    below = int((err < 0).sum())
    above = int((err > 0).sum())
    check("the modal-label criterion is biased low",
          "methodology.md / assumption 7",
          "mean signed error -0.176; 356 groups below their tercile, 130 above",
          f"mean signed error {err.mean():+.3f};"
          f" {below} groups below their tercile, {above} above",
          "NOT symmetric. The modal field label runs systematically low, so a criterion"
          " built on it favours the LOWER of two candidate names -- the same direction as"
          " the status quo it was used to judge. Settling this needs evidence independent"
          " of the field labels (the reference photographs).")


def main():
    head("INPUTS")
    prelim = pd.read_stata(PRELIM, convert_categoricals=False)
    corrected = pd.read_stata(DC + r"\outputs\master_rename_build\temp"
                                   r"\standard_weight_unit_correction.dta",
                              convert_categoricals=False)
    rest = pd.read_stata(RESTATED, convert_categoricals=False)
    sized = pd.read_stata(SIZED, convert_categoricals=False)
    print(f"  prelim_nsu_data              {len(prelim):>7,} rows")
    print(f"  ref_10_sized              {len(sized):>7,} rows")
    print(f"  standard_weight_unit_corr    {len(corrected):>7,} rows")
    print(f"  nsu_weighings_cpi         {len(rest):>7,} rows")

    head("CLAIMS ABOUT IDENTIFICATION AND VOCABULARY")
    c_harmonization_uniqueness(rest)
    c_case_counts(rest)

    head("CLAIMS ABOUT PRICES")
    c_pull_price_preload(rest)
    c_unique_mun_never_alone()
    c_size_cells_have_prices(rest)

    head("CLAIMS ABOUT MAGNITUDE CORRECTION")
    c_kg_band_empty(prelim)
    c_litres_rule(prelim)
    c_snap_band_partition(prelim)
    c_threshold_direction(prelim, corrected)

    head("CLAIMS ABOUT NORMALIZATION")
    c_item_group_normalization(rest)

    head("CLAIMS ABOUT OUTCOME 1")
    c_label_rank_is_load_bearing(rest)
    c_underfilled_shapes(sized)
    c_modal_label_criterion(sized)

    head("SUMMARY")
    df = pd.DataFrame(results, columns=["check", "doc", "recorded", "computed",
                                        "verdict", "note"])
    print(df.verdict.value_counts().to_string())
    out = DC + r"\outputs\tables\verify_documented_claims.csv"
    df.to_csv(out, index=False, encoding="utf-8-sig")
    print(f"\nwrote {out}")
    changed = df[df.verdict == "CHANGED"]
    if len(changed):
        print("\nCHANGED -- each of these needs a doc edit or a code fix:")
        for _, r in changed.iterrows():
            print(f"  {r['check']}  ({r['doc']})")
            print(f"    doc: {r['recorded']}")
            print(f"    now: {r['computed']}")
    return 1 if len(changed) else 0


if __name__ == "__main__":
    sys.exit(main())
