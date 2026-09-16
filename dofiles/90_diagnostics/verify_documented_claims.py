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
TEMP = DC + r"\outputs\build\intermediate"
DELIV = DC + r"\outputs\build\deliverables"

RAW = DC + r"\inputs\PSPS NSU Market Survey Launch.dta"
PRICE = DC + r"\inputs\NSU_prices_from_Makayla.csv"
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
from nsu_fold_rule import CELL_MIX


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


def c_no_corrupt_source_files():
    """No tracked text file may contain a NUL byte.

    A NUL in a .do or .py file is not a data problem, it is a WRITE problem, and it can
    sit there working. Two files in this repo carried one for several commits: a script
    that generated Stata paths wrote "00_shared" + backslash + "00b..." through a layer
    that collapsed the doubled backslash, leaving Python to read the result as the octal
    escape \000 followed by "b". Stata ran the file anyway and grep quietly reclassified
    it as binary, so nothing complained.

    Cheap to check and there is no legitimate reason for one, so it is asserted.

    found while auditing ids; see the commit that added this check
    """
    exts = {".do", ".py", ".md", ".csv", ".txt", ".json", ".r"}
    bad = []
    for f in Path(DC).rglob("*"):
        if not f.is_file() or f.suffix.lower() not in exts:
            continue
        if any(x in f.parts for x in (".git", "__pycache__")):
            continue
        try:
            if bytes([0]) in f.read_bytes():   # bytes([0]), not an escape -- see the docstring
                bad.append(str(f.relative_to(DC)))
        except OSError:
            continue
    check("no tracked text file contains a NUL byte",
          "build hygiene",
          "0 files with a NUL byte",
          f"{len(bad)} files with a NUL byte",
          "" if not bad else "; ".join(bad[:5]))


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
          # Moved by the 16 MS weighings behind the five non-unit labels dropped in
          # 02_drop_non_nsu_labels.py EXACT -- they had reached the published reference
          # set as harmonized units. See that file for the per-label counts.
          "1,096 of 1,096 matched rows agree; 98.5% coverage",
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


def c_ascii_strip_no_collisions(d):
    """Dropping non-ASCII must never make two distinct names the same name.

    The project normalizer strips non-ASCII rather than transliterating, so DUENAS with
    a tilde-n becomes DUEAS and not DUENAS. That is deliberate and is the only rule the
    Stata and Python sides can both implement identically. It is safe only while no two
    distinct names collapse onto one -- if DUEAS ever collided with a genuinely separate
    DUEAS, two municipalities would silently pool.

    Tests the ASCII strip ALONE, not full normalization: case-folding and whitespace
    collapse are supposed to merge names, and do (`Ice Cream in cone' and
    `ice cream  in cone' are one label on purpose). Only the strip must be injective.

    issue #27 item 8
    """
    fields = {"pull_province": d.pull_province, "pull_municipal_city": d.pull_municipal_city,
              "pull_item": d.pull_item, "pull_nsu_unit": d.pull_nsu_unit,
              "harmonized_nsu_unit": d.harmonized_nsu_unit}
    total = 0
    detail = []
    for name, col in fields.items():
        vals = sorted({str(v) for v in col.dropna().unique()})
        groups = {}
        for v in vals:
            groups.setdefault(A(v), set()).add(v)
        bad = {k: v for k, v in groups.items() if len(v) > 1}
        total += len(bad)
        detail.append(f"{name} {len(vals)} distinct, {len(bad)} collisions")
        if bad:
            for k, v in list(bad.items())[:3]:
                detail.append(f"    {k!r} <- {sorted(v)}")
    check("the ASCII strip collides no two distinct names",
          "issue #27 item 8",
          "0 collisions across province, municipality, item, raw unit, harmonized unit",
          f"{total} collisions across province, municipality, item, raw unit,"
          f" harmonized unit",
          "; ".join(detail))


def c_restaurant_collapse_is_one_item(d):
    """ni() folds anything containing "restaurant" onto one canonical item name.

    The collapse exists because the price file and the market survey spell the
    restaurant item differently. It is a no-op while only one spelling is present: there
    is nothing to fold it onto. A SECOND spelling appearing is the case the collapse was
    written for, and also the case that would tell us whether the fold is right -- so it
    is worth knowing the moment it happens rather than discovering it in a join.

    issue #27 item 8
    """
    items = {ni(v) for v in d.pull_item.dropna().unique()
             if "restaurant" in str(v).lower()}
    check("the restaurant collapse maps to one item",
          "issue #27 item 8",
          "1 distinct item(s) after the collapse",
          f"{len(items)} distinct item(s) after the collapse",
          f"{sorted(items)}")


def c_harmonization_is_cell_independent():
    """One raw label must mean ONE harmonized unit inside a single cell.

    THE OLDER, STRONGER CLAIM IS NO LONGER TRUE, deliberately. #27 item 8 recorded that
    an (item, raw spelling) pair maps to one harmonized unit everywhere -- harmonization
    item-conditioned but never cell-conditioned. CELL_MIX in nsu_fold_rule.py now breaks
    that on purpose: at ILOILO / TIGBAUAN a `putos' of cabbage or carrot is a mixed
    vegetable bag and folds to putos (mix vegetable), where the same spelling elsewhere
    is correctly a `pack'. The field comments say so outright -- "There is no cabbage
    packs alone this is mixed with carrots" -- and that is a fact about the cell.

    So the invariant is restated rather than dropped. What must hold is the WITHIN-CELL
    part, which is what actually protects the pooling key: inside one cell, one raw label
    means one harmonized unit. Break that and a case holds two units for the same label
    and the pooled median is computed over two different things. The retired post-merge
    override in 03_clean_ms.do did exactly that, on row-level free text.

    Cell-conditioned pairs are reported against CELL_MIX, so a NEW one is a finding
    rather than noise.

    issue #27 item 8; see also #18 A3
    """
    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)

    # (a) the invariant that must hold: one label, one unit, within a cell
    within = xw.groupby([xw.province.map(ng), xw.pull_municipal_city.map(ng),
                         xw.cons_name.map(ni), xw.pull_nsu_unit.map(nz)],
                        dropna=False).harmonized_nsu_unit.nunique()
    split = within[within > 1]
    check("one raw label means one harmonized unit within a cell",
          "issue #27 item 8, restated",
          "0 cell(s) split a raw label across harmonized units",
          f"{len(split)} cell(s) split a raw label across harmonized units",
          f"{len(within):,} cells checked"
          + ("" if split.empty else f"; offenders: {list(split.index[:3])}"))

    # (b) the pairs that ARE cell-conditioned, which must be exactly CELL_MIX
    across = xw.groupby([xw.cons_name.map(ni), xw.pull_nsu_unit.map(nz)],
                        dropna=False).harmonized_nsu_unit.nunique()
    cond = sorted(across[across > 1].index)
    expected = sorted({(ni(i), nz(u)) for _p, _m, i, u in CELL_MIX})
    check("only the declared cells are cell-conditioned",
          "issue #27 item 8, restated",
          f"{len(expected)} pair(s), all declared in CELL_MIX",
          f"{len(cond)} pair(s), all declared in CELL_MIX" if cond == expected
          else f"{len(cond)} pair(s), NOT matching CELL_MIX",
          f"found {cond}; CELL_MIX declares {expected}")


# ============================================================ 4. price coverage
def c_size_cells_have_prices(d):
    """Every cell that reaches Outcome 2 must have a price-file row, or its weights
    cannot be paired with a price point and there is nothing to convert.

    ALL THREE BRANCHES ARE CHECKED, not just size-based. This used to filter to
    `weighing_approach == 3', and that gap hid a real defect: the mixed-bag override
    in 03_clean_ms.do reassigned `harmonized_nsu_unit' post-merge on 4 ILOILO /
    TIGBAUAN rows, all of them approach 2, producing a harmonized unit with no price
    counterpart at that municipality. Four weighings (65/90/85/85 g) went into
    Outcome 2 as orphans and this check could not see them. Widened so the same class
    of defect cannot hide in the other two branches -- see issue #18.

    Reported per branch. A lumped total would let one branch regress while another
    improves and still look clean, and the branches fail for different reasons:
    approach 3 loses a fold target, approach 2 loses a price point.

    docs/conversion_factor_methodology.md, Step A
    """
    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)
    for c, f in [("province", ng), ("pull_municipal_city", ng),
                 ("cons_name", ni), ("harmonized_nsu_unit", nz)]:
        xw[c] = xw[c].map(f)
    priced = set(map(tuple, xw[xw.source.isin(["MS & Price", "Price Only"])]
                     [["province", "pull_municipal_city", "cons_name",
                       "harmonized_nsu_unit"]].dropna().values))

    APPROACH = {1: "conventional", 2: "price-quantity", 3: "size-based"}
    parts, details, missing = [], [], []
    for a in sorted(APPROACH):
        s = d[d.weighing_approach == a].copy()
        s["province"] = s.pull_province.map(ng)
        s["pull_municipal_city"] = s.pull_municipal_city.map(ng)
        s["cons_name"] = s.pull_item.map(ni)
        s["harmonized_nsu_unit"] = s.harmonized_nsu_unit.map(nz)
        cells = set(map(tuple, s[["province", "pull_municipal_city", "cons_name",
                                  "harmonized_nsu_unit"]].drop_duplicates().values))
        miss = sorted(cells - priced)
        missing += [(APPROACH[a], m) for m in miss]
        parts.append(f"{APPROACH[a]} {len(cells) - len(miss):,}/{len(cells):,}")
        details.append(f"{APPROACH[a]}: {len(cells) - len(miss):,} of {len(cells):,} covered")

    # An uncovered cell in ANY branch is a finding, not noise: it means a harmonized
    # unit reaches the deliverable with nothing in the price file that folds to it.
    # The usual cause is an assignment made after the crosswalk merge, which the join
    # never validated. Do not silence this by narrowing the filter again.
    now = ("all cells covered, every branch" if not missing else
           f"{len(missing)} uncovered: "
           + "; ".join(f"[{b}] " + " / ".join(m) for b, m in missing[:5]))
    check("every cell reaching Outcome 2 has a price-file row",
          "conversion_factor_methodology.md / Step A",
          "all cells covered, every branch",
          now,
          "  ".join(details)
          + ("" if not missing else "  UNCOVERED: "
             + "; ".join(f"[{b}] " + " / ".join(m) for b, m in missing[:5])))


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
    # grams 9147 -> 9132 and litres 1615 -> 1614: the 16 MS weighings behind the five
    # non-unit labels dropped in 02_drop_non_nsu_labels.py EXACT. The partition total
    # below is summed from this dict, so it follows automatically.
    recorded = {"grams": 9132, "litres": 1614, "kg < 1": 15,
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
          # Moved by 4 weighings / 1 case when the ILOILO / DUEAS cabbage label
          # "2 kapinutos nga cabbage/20pesos" joined the AMBIGUOUS set in
          # 02_drop_non_nsu_labels.py. That drop is the resolution of issue #22.
          # Harmonized fell 1,949 -> 1,948 when the TIGBAUAN mixed-bag fold moved into
          # CELL_MIX. That cell used to hold TWO harmonized units for cabbage -- `pack'
          # for the uncommented rows and `putos (mix vegetable)' for the commented ones,
          # because the old override ran after the crosswalk merge. It now holds one.
          "1,943 harmonized / 1,957 cleaned / 1,985 raw",
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
          # Moved by 4 weighings / 1 case when the ILOILO / DUEAS cabbage label
          # "2 kapinutos nga cabbage/20pesos" joined the AMBIGUOUS set in
          # 02_drop_non_nsu_labels.py. That drop is the resolution of issue #22.
          "437 of 1,508 size-based cases would be mislabelled by a naive grp->S/M/L map",
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
          # Moved by the STEP 3e adjudication (issue #18, from the manual review of
          # snap_sense_check.xlsx). The rules adopt the block reading on 431 rows where
          # the old plausibility gate moved only 42.
          "87 cases fill fewer groups than the field recorded labels",
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
          # Moved by the STEP 3e adjudication (issue #18, from the manual review of
          # snap_sense_check.xlsx). The rules adopt the block reading on 431 rows where
          # the old plausibility gate moved only 42.
          "29 with one group filled; 44 filled (1,2); 14 filled (1,3)",
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
          # Moved by 4 weighings / 1 case when the ILOILO / DUEAS cabbage label
          # "2 kapinutos nga cabbage/20pesos" joined the AMBIGUOUS set in
          # 02_drop_non_nsu_labels.py. That drop is the resolution of issue #22.
          "698 not-under-filled cases would be caught; 362 field-small, 155 field-large",
          f"{len(ok1):,} not-under-filled cases would be caught;"
          f" {n_s} field-small, {n_l} field-large",
          "these have one label recorded AND one group filled, so they are correctly"
          " labelled today; a rule reading 'n_filled == 1' would overwrite them")


def c_thin_sensitivity():
    """A3's sensitivity table. It had NO CHECK BEHIND IT and went stale unnoticed.

    Every figure in it moved when the fallback ladder landed -- the reference set went
    3,305 rows to 2,557 and the flagged share fell from 38.3% to 20.3% -- and all 28
    checks in this file passed while it was wrong. That is the failure this check exists
    to prevent, and it is the argument for the register's own rule: name a check, do not
    restate a figure.

    The share is what matters rather than the count, because A3's claim is about
    SENSITIVITY: moving the cut by one roughly doubles or halves the flagged share, which
    is why the threshold is called badly placed.

    docs/implicit_assumptions.md / A3
    """
    ref = pd.read_stata(DELIV + r"\nsu_reference_set.dta", convert_categoricals=False)
    n = len(ref)
    got = {t: int((ref.n_g < t).sum()) for t in (2, 3, 4, 5)}
    check("A3 rows flagged at THIN = 2 / 3 / 4 / 5",
          "implicit_assumptions.md / A3",
          "210 / 434 / 967 / 1400 of 2490",
          f"{got[2]} / {got[3]} / {got[4]} / {got[5]} of {n}",
          note="A3's table is a claim about sensitivity; if these move, the argument for "
               "calling THIN = 3 badly placed has to be re-made on the new numbers.")


def c_reclassification_counts():
    """#28's reclassification, and the split it predicted.

    Two things are asserted in the issue and neither was checked anywhere: that 388
    weighings in 99 cases move from conventional to size-based, and that the 123
    field-conventional cases still publish 123 rows because only the LABEL moves.

    The 78 / 21 split is the interesting one. #28 predicted that 21 of the 99 could not be
    finished until the province fallback existed; those 21 are exactly the reclassified
    cases too thin to publish a size rung, which now land on the pooled row. Nothing
    coordinated those two numbers, so a divergence would mean one of the two rules changed
    scope without the other noticing.

    issue #28 / branch, and docs/implicit_assumptions.md A12
    """
    ref = pd.read_stata(DELIV + r"\nsu_reference_set.dta", convert_categoricals=False)
    if "d_reclassified" not in ref.columns:
        skip("#28 reclassification reaches the published set", "issue #28",
             "nsu_reference_set.dta has no d_reclassified -- run 00_shared/08_branch.do")
        return
    conv = ref[ref.weighing_approach == 1]
    rc = conv[conv.d_reclassified == 1]
    check("#28 field-conventional rows: always-conventional vs reclassified",
          "issue #28 / branch",
          "22 always-conventional, 99 reclassified, 121 rows in total",
          f"{int((conv.d_reclassified == 0).sum())} always-conventional, "
          f"{int(len(rc))} reclassified, {len(conv)} rows in total",
          note="WAS 24 / 99 / 123. The two that left are camote tops `2bond' and "
               "`3bugkos' at AKLAN / MALINAO, both published size_ord = conventional_nsu "
               "and both removed from Outcome 1 by A21 as counts rather than units. The "
               "RECLASSIFIED count is untouched at 99, which is the part #28 asserts; "
               "only the always-conventional side moved, and it moved for a reason "
               "outside #28. If the reclassified figure ever changes, that IS #28 drifting.")
    check("#28 reclassified rows: published medium vs pooled across sizes",
          "issue #28 / branch",
          "99 medium, 0 pooled",
          f"{int((rc.size_ord == 2).sum())} medium, {int((rc.size_ord == 4).sum())} pooled",
          note="WAS 78 medium / 21 pooled, and the change is a fix rather than a drift. A "
               "reclassified case has exactly ONE rung by construction -- A12 forbids "
               "terciling it -- so the L1 collapse had nothing to pool, and the 21 thin "
               "ones were being relabelled 'pooled across sizes' anyway. "
               "12_publish_reference_set.do sec 5b now requires >= 2 rungs before it "
               "collapses a cell, so all 99 publish at medium and the 21 carry d_thin = 1 "
               "instead, which says what is actually true of them. If this ever reads "
               "anything but 99/0, the collapse gate has been loosened again.")


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
          # ROSE from 57.5%. The field labels are an INDEPENDENT signal -- the snap never
          # reads them -- so better agreement after the adjudication is corroboration that
          # the rules pick the right candidate, not an artefact of the rules.
          # These three moved AGAIN, by 2-3 groups, when the 12 hand corrections were
          # re-keyed off `id' onto content -- nine had been landing on the wrong
          # weighing. Agreement went UP, which is the direction that says the
          # re-keying put them where the reviewer meant.
          # Rose a THIRD time (64.7% -> 65.3%) when the second review round's 80
          # verdicts were applied. Same direction every time, and the snap never
          # reads the field labels -- so this is corroboration, not overfitting.
          # Rose again (64.0% -> 64.7%) when the referee became hetero-aware. The field
          # labels are a signal the snap never reads, so agreement improving is evidence
          # the rule picks better, not evidence of fitting to them.
          "68.4% (3,871 of 5,657)",
          f"{per_row / len(full) * 100:.1f}% ({per_row:,} of {len(full):,})",
          "this is the number that justifies re-terciling in the first place -- the"
          " field label is wrong about a third of the time at row level")

    g = (full.groupby(["cell", "grp"]).field_sml
              .agg(lambda x: x.mode().iloc[0]).reset_index())
    per_grp = int((g.field_sml == g.grp).sum())
    check("modal field label agrees with the tercile, per group",
          "methodology.md / assumption 7",
          # ROSE from 66.5%, same independence argument as the per-weighing figure above.
          "82.0% (1,215 of 1,482)",
          f"{per_grp / len(g) * 100:.1f}% ({per_grp:,} of {len(g):,})",
          "aggregating recovers signal, which is what the naming criterion needs")

    err = (g.field_sml - g.grp)
    below = int((err < 0).sum())
    above = int((err > 0).sum())
    check("the modal-label criterion is biased low",
          "methodology.md / assumption 7",
          # The low bias SHRANK from -0.176 to -0.141 under the adjudication, consistent
          # with the review's finding that the log-10 snap tends to underestimate: adopting
          # the block reading on 431 rows removes part of that downward pull. Still not
          # symmetric, so the caveat below stands.
          "mean signed error -0.096; 196 groups below their tercile, 71 above",
          f"mean signed error {err.mean():+.3f};"
          f" {below} groups below their tercile, {above} above",
          "NOT symmetric. The modal field label runs systematically low, so a criterion"
          " built on it favours the LOWER of two candidate names -- the same direction as"
          " the status quo it was used to judge. Settling this needs evidence independent"
          " of the field labels (the reference photographs).")


def c_reference_docs_row_totals():
    """The row totals two REFERENCE docs state about files they describe.

    docs/summary_statistics.md and docs/data_dictionary.md / docs/master_rename.md

    WHY THESE TWO ARE HERE NOW. Both sat outside this file's net and both drifted: the
    summary doc quoted a cleaned row count of 11,458 against a build of 11,433 (and the
    CSV nominally backing it said 11,453 -- a third number, because the script had not
    been re-run), and the crosswalk totals said 2,950 rows against 2,927 on disk. Nothing
    noticed, which is the same failure the attrition ledger was rebuilt to prevent, just
    recurring in the docs that this file did not reach.

    These are the cheapest possible checks -- a row count of a file the doc names -- and
    they are the ones that would have caught both.
    """
    cleaned = pd.read_stata(TEMP + r"\nsu_data_master.dta",
                            convert_categoricals=False)
    check("summary_statistics.md: cleaned row count",
          "summary_statistics.md / Sources, Grain, Counts",
          "11,433 rows in nsu_data_master.dta",
          f"{len(cleaned):,} rows in nsu_data_master.dta",
          "quoted in three places in that doc (Sources, Grain, Counts). Re-run"
          " 90_diagnostics/summary_statistics.py, then update the doc from its CSVs")

    xw = pd.read_csv(DC + r"\outputs\tables\master_nsu_rename.csv")
    src = xw.source.value_counts()
    n_merged = int((xw.n_cell_merged > 1).sum())
    check("master_rename.md / data_dictionary.md: crosswalk totals",
          "master_rename.md / source table, data_dictionary.md / master rename sheet",
          "2,927 rows: 1,985 MS & Price + 942 Price Only + 0 MS-only; 766 in-cell merged",
          f"{len(xw):,} rows: {src.get('MS & Price', 0):,} MS & Price"
          f" + {src.get('Price Only', 0):,} Price Only + {src.get('MS', 0)} MS-only;"
          f" {n_merged} in-cell merged",
          "both docs state this total; they disagreed with each other on the merged"
          " count as well as with the file, which is what an unchecked figure does")


def c_d_thin_on_every_deliverable():
    """d_thin ships on all six deliverables, and reads what A3 says it reads.

    Decided 2026-09-16 on #31: a thin value is PUBLISHED and FLAGGED in both outcomes,
    never rerouted to a pooled weight. Before that the flag existed on nsu_reference_set
    alone, so a reader of outcome2_lookup or psps_grams had to derive it themselves with
    nothing saying which count to use.

    The shares are checked, not just the presence, because the figures previously recorded
    on #31 drifted by hundreds of rows across two rebuilds with nothing watching them --
    which is the failure this whole file exists to prevent.
    """
    d = DC + r"\outputs\build\deliverables"
    rd = lambda f: pd.read_stata(f"{d}\\{f}.dta", convert_categoricals=False)

    missing = [f for f in ("nsu_reference_set", "outcome2_lookup",
                           "outcome2_lookup_noinflation", "outcome2_lookup_heteroblind",
                           "psps_grams", "psps_grams_heteroblind")
               if "d_thin" not in rd(f).columns]
    check("d_thin ships on every deliverable",
          "implicit_assumptions.md / A3, data_dictionary.md",
          "present on all 6",
          "present on all 6" if not missing else f"MISSING from {', '.join(missing)}",
          "the flag is the whole apparatus for thinness; a file without it forces a"
          " reader to guess which count to threshold")

    ref, lk = rd("nsu_reference_set"), rd("outcome2_lookup")
    pg = rd("psps_grams")
    check("d_thin counts, by deliverable",
          "implicit_assumptions.md / A3 table",
          "O1 434/2,490 | lookup 1,162/3,172 | psps_grams 7,077/34,893",
          f"O1 {int(ref.d_thin.sum()):,}/{len(ref):,}"
          f" | lookup {int((lk.d_thin == 1).sum()):,}/{int(lk.d_thin.notna().sum()):,}"
          f" | psps_grams {int((pg.d_thin == 1).sum()):,}"
          f"/{int(pg.d_thin.notna().sum()):,}",
          "Outcome 2's lookup reads twice as thin as Outcome 1 because it publishes one"
          " row per price point, not one per cell x size -- a grain difference, not"
          " weaker evidence")

    # The hetero-blind pair is gated at every rung and has no L0, so nothing below THIN
    # can reach it. Stated in A3 as "0 by construction"; if that ever stops holding, the
    # blind variant has quietly become something else.
    hb, gb = rd("outcome2_lookup_heteroblind"), rd("psps_grams_heteroblind")
    check("the hetero-blind pair carries no thin row",
          "implicit_assumptions.md / A3",
          "0 and 0",
          f"{int((hb.d_thin == 1).sum())} and {int((gb.d_thin == 1).sum())}",
          "this is what the blind variant IS: no published value rests on fewer than"
          " THIN weighings, bought by ignoring the price/size match entirely")


def main():
    head("INPUTS")
    prelim = pd.read_stata(PRELIM, convert_categoricals=False)
    corrected = pd.read_stata(TEMP + r"\standard_weight_unit_correction.dta",
                              convert_categoricals=False)
    rest = pd.read_stata(RESTATED, convert_categoricals=False)
    sized = pd.read_stata(SIZED, convert_categoricals=False)
    print(f"  prelim_nsu_data              {len(prelim):>7,} rows")
    print(f"  ref_10_sized              {len(sized):>7,} rows")
    print(f"  standard_weight_unit_corr    {len(corrected):>7,} rows")
    print(f"  nsu_weighings_cpi         {len(rest):>7,} rows")

    head("BUILD HYGIENE")
    c_no_corrupt_source_files()
    c_reference_docs_row_totals()
    c_d_thin_on_every_deliverable()

    head("CLAIMS ABOUT IDENTIFICATION AND VOCABULARY")
    c_harmonization_uniqueness(rest)
    c_case_counts(rest)
    # issue #27 item 8 -- three premises that were measured clean and left
    # unguarded. Asserted here so a future build cannot quietly break one.
    c_ascii_strip_no_collisions(rest)
    c_restaurant_collapse_is_one_item(rest)
    c_harmonization_is_cell_independent()

    # The fold policy is NOT checked here, deliberately. It needs validate_folds.do to
    # have just run against the current weighings, and nothing in this file can
    # guarantee that -- a first attempt guarded it on file mtimes, which a git checkout
    # rewrites, so a merge would have made a stale result look fresh. It lives in
    # dofiles/verify_pipeline.py, which runs validate_folds.do itself first.

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
    c_thin_sensitivity()
    c_reclassification_counts()

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
