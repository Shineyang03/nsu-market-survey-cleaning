"""Pipeline explorer: trace one observation from raw MS through to output weight.

WHY THIS EXISTS (GitHub issue #26). `dofiles/case_lookup.py` answers "what did the
field record for this cell" -- useful once a case is already shortlisted, useless
for two other questions that come up constantly while auditing the build:

  - what happened to ONE raw weighing as it moved through the pipeline -- which
    spelling it arrived with, what it was cleaned/harmonized to, whether its
    weight or unit was snapped, whether it was restated for inflation, which case
    it landed in, and whether it survived to an output at all;
  - where the ATTRITION went -- 11,495 raw rows become 11,458, then 11,360, and
    the ledger (docs/attrition_ledger.md) names every drop reason, but a table of
    reasons is not the same as watching the flow.

A spreadsheet is the wrong shape for either question -- both are about a PATH
through stages, which is what a Sankey diagram plus a per-row drill-down are for.

WHAT THIS READS (build outputs only -- nothing here is written by this script)
  raw MS            NSU Market Survey Launch/data/PSPS NSU Market Survey Launch.dta
  price file        NSU Market Survey Launch/data/NSU_prices_from_Makayla.csv
  arrival stage      outputs/master_rename_build/temp/prelim_nsu_data.dta
  weight/unit stage   outputs/master_rename_build/temp/standard_weight_unit_correction.dta
  restated stage     outputs/master_rename_build/temp/nsu_weights_restated.dta
  Outcome 1 output   outputs/master_rename_build/temp/nsu_reference_set.dta
  harmonization map  outputs/tables/master_nsu_rename.csv
  comment crosswalk  outputs/tables/add_comments_crosswalk.xlsx
  standard-qty drops outputs/master_rename_build/tables/excluded_standard_unit_obs.xlsx
  attrition ledger   outputs/master_rename_build/tables/attrition_ledger.csv (context only,
                      see "KNOWN DISCREPANCY" below -- this script does not trust its
                      row counts, only its prose reasons)

WHAT THIS WRITES
  outputs/explorer/nsu_pipeline_explorer.html   -- the only output. Self-contained:
      inline CSS/JS, data embedded as JSON, no CDN, no build step. Opens from disk
      with file://. Nothing anywhere else is touched -- no .do file, no .dta.

HOW A RAW ROW IS JOINED TO ITS ARRIVAL ROW. `prelim_nsu_data.dta` carries an `id`
that raw rows do not have (raw predates `id`; `id` is assigned by cleaning_Aug11.do
AFTER the 37 stage-1 drops, sorted by a key that does not preserve raw row order).
So the raw -> arrival join cannot use `id` and cannot use row position. Instead it
uses the identification key `docs/conversion_factor_methodology.md` documents as
unique on the raw file (verified here to be unique on BOTH sides, 11,495 groups /
11,495 rows and 11,458 groups / 11,458 rows, with zero raw rows resolving to more
than one arrival row):

    province x municipality x item x pull_nsu_unit x market_type x vendor_id x obs_type

`obs_type` is mapped to the same numeric code `cleaning_Aug11.do`'s `def_hetero`
program assigns it (conventional_nsu=1 ... unique_mun_price7=11) so it lines up
with the arrival file's `item_nsu_hetero_type`. `weight` and `pull_price` are
DELIBERATELY EXCLUDED from this key: `pull_price` is blanked for size-based rows
somewhere between raw and arrival (a size-based interview records no price, so
whatever value a preload left in the raw column is discarded), and a `weight` of
literal 0 in raw becomes a true missing value in the arrival file for a handful of
rows (docs/data_oddities.md sec.2, "zero means not available"). Requiring exact
equality on either field turned real matches into false negatives during
development; dropping them from the key does not cost uniqueness on either side.

Every one of the 37 raw rows that fails to join is independently explained:
  - 1 row: the "notes" flag in add_comments_crosswalk.xlsx reading "To drop
    (enumerator re-entered 225 weight for the 187.5 price mark)" -- matched back
    to its raw row by the same 7-field key with obs_type read off the crosswalk's
    own hetero label.
  - 33 rows: present in outputs/master_rename_build/tables/excluded_standard_unit_obs.xlsx
    (the standard-quantity label drop), matched back the same way.
  - 3 rows: pull_price missing & item=="fresh fish" & pull_nsu_unit=="bilog" &
    municipality=="TIGBAUAN" (the documented SurveyCTO glitch), on normalized
    fields.
  If any row is EVER left unexplained by these three reasons, this script prints
  the count and refuses to silently absorb it into one of the three -- see
  `classify_stage1_drops()`.

WHAT IS PRE-AGGREGATED, AND WHY. The weighings (restated-stage rows, 11,360) are
embedded IN FULL, one JSON object per row -- nothing is sampled. The Sankey,
however, only ever needs node-to-node COUNTS, so its flows are pre-aggregated
band totals, never a per-row list. No row is dropped from the embedded table
without being counted in a printed total that reconciles to the raw 11,495 (see
the RECONCILIATION printout at the end of a run) -- if it does not reconcile, this
script says so rather than adjusting a number to make it look like it does.

KNOWN DISCREPANCY WITH docs/attrition_ledger.md -- READ BEFORE TRUSTING A NUMBER.
The saved ledger (both attrition_ledger.md and its .csv) documents Stage 2
(nsu_restate_weights.do) as dropping 74 rows (11,458 -> 11,384). The do-file and
its own saved log (dofiles/nsu_restate_weights.log) currently show 98 dropped
(27 "vendor gave no price at all" + 71 "vendor-priced, case keeps a preloaded
rung") -> 11,360, which matches the actual row count of
outputs/master_rename_build/temp/nsu_weights_restated.dta on disk and the count
this task's own brief names as ground truth. docs/data_oddities.md sec.3b already
describes the 27-row approx_price rule as implemented; the ledger was written
before that rule landed and was never regenerated. This script uses the files on
disk (98 dropped, 11,360 restated) as ground truth throughout and flags the stale
74/11,384 figures in the generated page rather than silently matching them or
silently overwriting the ledger (out of scope: no .do or ledger edits here).

OUTCOME 1 SIZE ASSIGNMENT -- REPLICATED, VALIDATED 100%. To label which size a
size-based weighing became (small / medium / large), this script replicates
nsu_reference_set.do sec.2 (re-tercile the pooled case weights, rank the field
labels present, assign by rank) in pandas. The one nontrivial part is the
tercile CUT ITSELF: pandas' `Series.quantile()` uses linear interpolation, which
silently disagrees with Stata's default `pctile` at the small case sizes and
frequent ties this data has (w_ref is whole grams; a case can hold one weighing
per size label). `stata_pctile()` in this file reimplements Stata's actual rule
(nearest-rank on a non-integer index, average-of-two on an exact one) and is
validated by re-collapsing every replicated (case x size) group to n / median
and comparing against the published nsu_reference_set.dta n_g / grams directly:
100% of case x size groups match exactly (2,843 of 2,843, checked in
development; the generator re-runs and prints this check every time). If a
future data change ever drops that match rate below 100%, the printed
reconciliation will show it, and the page marks any unreconciled row's size as
"unverified" and shows the published grams figure rather than inventing one.

WHAT IS NOT COVERED. Outcome 2 (PSPS conversion factors) has no do-file yet
(docs/conversion_factor_methodology.md, "Which files are live") -- this explorer
can only mark a weighing "eligible for Outcome 2" (i.e. its branch/case survives
the row-level attrition Outcome 2 would also apply -- unique_mun_price exclusion
does NOT apply, since Outcome 2 keeps it) and cannot show a terminal Outcome 2
value, because none exists yet. SurveyCTO case preloads (`nsu_cases_*.csv`) were
read for context (they back the pull_price-preload check in
`verify_documented_claims.py`) but are not embedded here -- nothing in the issue's
"Done when" criteria needs them, and embedding a fourth per-row join for a
low-priority convenience tool was judged not worth the added join-fragility.

RUN
    python dofiles/build_pipeline_explorer.py

Requires PYTHONIOENCODING=utf-8 on Windows (province/item strings are pre-ASCII-
dropped by the time they reach this script, but source file paths and printed
diagnostics can still include non-ASCII bytes on some consoles).
"""
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def stata_pctile(values, p):
    """Replicates Stata's default `pctile x, p(p)` algorithm exactly (verified
    100% against the actual `nsu_reference_set.dta` -- see classify_stage3()).

    Stata's rule, on sorted x_(1) <= ... <= x_(n): let idx = n*p/100. If idx is
    (within float tolerance of) an integer i, the percentile is the average of
    x_(i) and x_(i+1); otherwise it is x_(ceil(idx)). pandas' `Series.quantile`
    uses a DIFFERENT (linear-interpolation) rule that silently disagrees at
    small n with ties -- exactly the case here, since w_ref is whole grams and
    a case can hold as few as 1 weighing per size label. Do not swap this for
    `.quantile()`: it reproduces the published reference-set case x size
    grouping exactly; `.quantile()` misclassified ~28% of case x size groups
    across a size boundary during development.
    """
    v = sorted(values)
    n = len(v)
    if n == 0:
        return float('nan')
    idx = n * p / 100.0
    if abs(idx - round(idx)) < 1e-7:
        i = int(round(idx))
        if i <= 0:
            return v[0]
        if i >= n:
            return v[-1]
        return (v[i - 1] + v[i]) / 2.0
    i = math.ceil(idx)
    i = min(max(i, 1), n)
    return v[i - 1]

BOX = Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey")
DC = BOX / "Data Cleaning"
LAUNCH = BOX / "NSU Market Survey Launch"

RAW_PATH = LAUNCH / "data" / "PSPS NSU Market Survey Launch.dta"
PRICE_PATH = LAUNCH / "data" / "NSU_prices_from_Makayla.csv"
PRELIM_PATH = DC / "outputs" / "master_rename_build" / "temp" / "prelim_nsu_data.dta"
WTUNIT_PATH = DC / "outputs" / "master_rename_build" / "temp" / "standard_weight_unit_correction.dta"
RESTATED_PATH = DC / "outputs" / "master_rename_build" / "temp" / "nsu_weights_restated.dta"
REFSET_PATH = DC / "outputs" / "master_rename_build" / "temp" / "nsu_reference_set.dta"
MASTER_RENAME_PATH = DC / "outputs" / "tables" / "master_nsu_rename.csv"
COMMENTS_XW_PATH = DC / "outputs" / "tables" / "add_comments_crosswalk.xlsx"
STDQTY_PATH = DC / "outputs" / "master_rename_build" / "tables" / "excluded_standard_unit_obs.xlsx"

OUT_DIR = DC / "outputs" / "explorer"
OUT_HTML = OUT_DIR / "nsu_pipeline_explorer.html"


# ============================================================================
# Normalizers -- COPIED VERBATIM from dofiles/diagnose_price_only.py (do not
# reimplement; see docs/conversion_factor_methodology.md, "String normalization").
# Order: drop non-ASCII outright, case-fold, trim, collapse whitespace. Never
# NFKD-decompose -- DUENAS, not DUENAS-with-tilde-stripped-differently.
# ============================================================================
def A(s):
    return str(s).encode('ascii', 'ignore').decode('ascii')


def nz(s):
    return re.sub(r'\s+', ' ', A(s).lower().strip())


def ni(s):
    s = nz(s)
    return 'drinks at restaurant, hotel, cafe, or kiosk' if 'restaurant' in s else s


def ng(s):
    return re.sub(r'\s+', ' ', A(s).strip().upper())


# The obs_type -> item_nsu_hetero_type coding, copied from cleaning_Aug11.do's
# `def_hetero` program (line ~127) so the raw-side key lines up with the coded
# item_nsu_hetero_type every downstream file carries.
HETERO_CODE = {
    'conventional_nsu': 1, 'small_size': 2, 'medium_size': 3, 'large_size': 4,
    'mp25_price': 5, 'mp50_price': 6, 'mp75_price': 7, 'municipality_median': 8,
    'province_median': 9, 'unique_mun_price6': 10, 'unique_mun_price7': 11,
}
HETERO_LABEL = {v: k for k, v in HETERO_CODE.items()}
WA_CODE = {
    'Conventional NSU (eg. ganta, salmon, salop)': 1,
    'Price-quantity based (lower, median, higher price)': 2,
    'Size-based (small, medium, large)': 3,
}
WA_LABEL = {1: 'conventional', 2: 'price-quantity', 3: 'size-based'}
UNIT_LABEL = {1: 'kg (as recorded)', 2: 'g (as recorded)', 3: 'L (as recorded)'}
CORRECTED_UNIT_LABEL = {1.0: 'g', 2.0: 'mL'}
SIZE_LABEL = {0: 'conventional', 1: 'small', 2: 'medium', 3: 'large'}

CASE_COLS = ['pull_province', 'pull_municipal_city', 'pull_item',
             'harmonized_nsu_unit', 'corrected_unit']
RAW_KEY_COLS = ['pull_province', 'pull_municipal_city', 'pull_item',
                'pull_nsu_unit', 'weighing_approach', 'market_type',
                'vendor_id', 'item_nsu_hetero_type']


def log(msg):
    print(msg, flush=True)


# ============================================================================
# Loaders
# ============================================================================
def load_raw():
    raw = pd.read_stata(RAW_PATH, convert_categoricals=False)
    raw['P'] = raw.pull_province.map(ng)
    raw['C'] = raw.pull_municipal_city.map(ng)
    raw['I'] = raw.pull_item.map(ni)
    raw['U_norm'] = raw.pull_nsu_unit.map(nz)
    raw['wa_num'] = raw.weighing_approach.map(WA_CODE)
    if raw.wa_num.isna().any():
        bad = raw.weighing_approach[raw.wa_num.isna()].unique()
        raise SystemExit(f"FATAL: unrecognized weighing_approach values in raw: {bad}")
    raw['het'] = raw.obs_type.map(HETERO_CODE)
    if raw.het.isna().any():
        bad = raw.obs_type[raw.het.isna()].unique()
        raise SystemExit(f"FATAL: unrecognized obs_type values in raw: {bad}")
    return raw


def raw_join_key(df, province='P', mun='C', item='I', unit='U_norm',
                  wa='wa_num', het='het'):
    return list(zip(df[province], df[mun], df[item], df[unit],
                    df[wa], df.market_type, df.vendor_id, df[het]))


def load_prelim_master():
    """Arrival stage (prelim) merged with the weight/unit-correction stage on
    `id` -- never on row position, per the task's hard constraint. Together
    these two files ARE `nsu_data_master.dta` (cleaning_Aug11.do's own Stage-1
    output); reproducing the merge here avoids depending on a temp file that
    may or may not still be on disk, and the merge itself is exactly what
    verify_documented_claims.py already does."""
    prelim = pd.read_stata(PRELIM_PATH, convert_categoricals=False)
    wtunit = pd.read_stata(WTUNIT_PATH, convert_categoricals=False)
    wtunit = wtunit.rename(columns={'correct_unit': 'corrected_unit'})
    master = prelim.merge(wtunit, on='id', how='inner', validate='1:1')
    if len(master) != len(prelim):
        raise SystemExit(
            f"FATAL: prelim ({len(prelim)}) x wtunit ({len(wtunit)}) join on id "
            f"lost rows -> {len(master)}. This must be 1:1 and total.")
    return master


def load_restated():
    return pd.read_stata(RESTATED_PATH, convert_categoricals=False)


def load_refset():
    return pd.read_stata(REFSET_PATH, convert_categoricals=False)


# ============================================================================
# Stage 1: raw arrival -> the 37 documented drops
# ============================================================================
def classify_stage1_drops(raw, master):
    """Every raw row that never reaches `master` (=prelim+wtunit), with a
    reason. See the module docstring, "Every one of the 37 raw rows...".
    """
    raw_key = raw_join_key(raw)
    master_key = raw_join_key(master, province='pull_province',
                               mun='pull_municipal_city', item='pull_item',
                               unit='pull_nsu_unit', wa='weighing_approach',
                               het='item_nsu_hetero_type')
    dup_raw = pd.Series(raw_key).duplicated().sum()
    dup_master = pd.Series(master_key).duplicated().sum()
    log(f"  raw join-key duplicate groups: {dup_raw} (expect 0)")
    log(f"  master join-key duplicate groups: {dup_master} (expect 0)")

    raw = raw.copy()
    raw['_key'] = raw_key
    master_key_set = set(master_key)
    raw['in_master'] = raw._key.isin(master_key_set)

    master = master.copy()
    master['_key'] = master_key

    dropped = raw[~raw.in_master].copy()
    log(f"  raw rows with no arrival-stage match: {len(dropped)} (expect 37)")

    # ---- reason 1a: the one comment-flagged data-entry error -----------------
    cw = pd.read_excel(COMMENTS_XW_PATH, dtype=str)
    flagged = cw[cw.notes.astype(str).str.contains('To drop', na=False)]
    flagged_keys = set()
    for r in flagged.itertuples():
        het = HETERO_CODE.get(str(r.item_nsu_hetero_type).strip())
        wa = WA_CODE.get(str(r.weighing_approach).strip())
        if het is None or wa is None:
            continue
        flagged_keys.add((ng(r.pull_province), ng(r.pull_municipal_city),
                           ni(r.pull_item), nz(r.pull_nsu_unit), wa,
                           int(r.market_type), r.vendor_id, het))
    dropped['reason_1a'] = dropped._key.isin(flagged_keys)

    # ---- reason 1c: the 33 standard-quantity label weighings ------------------
    sq = pd.read_excel(STDQTY_PATH, dtype=str)
    sq_keys = set()
    for r in sq.itertuples():
        wa_label = str(r.weighing_approach).strip()
        wa = WA_CODE.get(wa_label)
        het = HETERO_CODE.get(str(r.hetero_lbl).strip())
        if wa is None or het is None:
            continue
        sq_keys.add((ng(r.pull_province), ng(r.pull_municipal_city),
                     ni(r.pull_item), nz(r.pull_nsu_unit), wa,
                     int(r.market_type), r.vendor_id, het))
    dropped['reason_1c'] = dropped._key.isin(sq_keys)

    # ---- reason 1d: TIGBAUAN fresh fish bilog, no stated price -----------------
    dropped['reason_1d'] = (
        dropped.pull_price.isna() & (dropped.I == 'fresh fish')
        & (dropped.U_norm == 'bilog') & (dropped.C == 'TIGBAUAN'))

    n1a, n1c, n1d = dropped.reason_1a.sum(), dropped.reason_1c.sum(), dropped.reason_1d.sum()
    log(f"  of which: 1a data-entry error = {n1a} (expect 1)")
    log(f"            1c standard-quantity label = {n1c} (expect 33)")
    log(f"            1d TIGBAUAN glitch = {n1d} (expect 3)")

    unexplained = dropped[~(dropped.reason_1a | dropped.reason_1c | dropped.reason_1d)]
    if len(unexplained):
        log(f"  *** {len(unexplained)} dropped raw rows have NO matched reason "
            f"-- reporting as 'unresolved', not guessing ***")
    else:
        log("  every dropped raw row has a matched reason -- 0 unresolved")

    def reason_text(r):
        if r.reason_1a:
            return ("1a: comment-flagged data-entry error (enumerator re-entered "
                    "225 weight for the 187.5 price mark)")
        if r.reason_1c:
            return "1c: standard-quantity label (states its own quantity, not an NSU)"
        if r.reason_1d:
            return "1d: TIGBAUAN fresh fish 'bilog', no stated price (SurveyCTO glitch)"
        return "unresolved -- dropped between raw and arrival stage, reason not matched"

    dropped['stage1_drop_reason'] = dropped.apply(reason_text, axis=1)
    return raw, master, dropped


# ============================================================================
# Stage 2: master -> restated (the vendor-price / no-price drops)
# ============================================================================
def classify_stage2(master, restated):
    """Ground truth is `id` membership in `restated`. The reason string is a
    replication of nsu_restate_weights.do's own logic, printed and cross-
    checked against the actual drop count (98) before being trusted."""
    restated_ids = set(restated.id)
    m = master.copy()
    m['in_restated'] = m.id.isin(restated_ids)
    n_dropped_actual = (~m.in_restated).sum()
    log(f"  master rows absent from restated (actual, by id): {n_dropped_actual} "
        f"(current build: 98 = 27 no-price + 71 vendor-priced-not-rescued)")

    no_price = (m.weighing_approach == 2) & (m.approx_price == 1)
    m['reason_2_noprice'] = no_price

    pre = (m.weighing_approach == 2) & no_price.__invert__() & m.actual_price.isna()
    m['_n_pre'] = pre.astype(int)
    has_preloaded = (m[~no_price].groupby(CASE_COLS)['_n_pre']
                     .transform('max').reindex(m.index[~no_price]))
    m['has_preloaded'] = False
    m.loc[~no_price, 'has_preloaded'] = has_preloaded.astype(bool)

    vendor_priced_dropped = ((m.weighing_approach == 2) & ~no_price
                              & m.actual_price.notna() & m.has_preloaded)
    m['reason_2_vendor_dropped'] = vendor_priced_dropped
    m['reason_2_vendor_rescued'] = ((m.weighing_approach == 2) & ~no_price
                                     & m.actual_price.notna() & ~m.has_preloaded)

    my_dropped = no_price | vendor_priced_dropped
    n_np, n_vd, n_vr = no_price.sum(), vendor_priced_dropped.sum(), m.reason_2_vendor_rescued.sum()
    log(f"  replicated: no-price drops={n_np}, vendor-priced dropped={n_vd}, "
        f"vendor-priced rescued={n_vr}")

    n_mismatch = int((my_dropped != ~m.in_restated).sum())
    agree = 1 - n_mismatch / len(m)
    log(f"  replicated-drop vs actual-membership agreement: {agree:.4%} "
        f"({n_mismatch} row(s) disagree)")
    if n_mismatch:
        mismatch = m[my_dropped != ~m.in_restated]
        log(f"  *** {len(mismatch)} row(s) dropped/kept for a reason this "
            f"replication does not match (id(s): {list(mismatch.id)}) -- ACTUAL "
            f"membership (in_restated) is used as ground truth for the Sankey/"
            f"table regardless; these rows get the generic 'reason not matched "
            f"by replication' text instead of a specific one ***")

    def reason_text(r):
        if r.in_restated:
            return ""
        if r.reason_2_noprice:
            return ("2: vendor gave no price at all (approx_price=1) -- no valid "
                    "price to pair with the recorded grams")
        if r.reason_2_vendor_dropped:
            return ("2: vendor-priced row dropped -- this case retains at least "
                    "one preloaded-price rung, so the vendor's own price is not "
                    "needed and would mix two different prices into one median")
        return "2: dropped between arrival and restated stage; reason not matched by replication"

    m['stage2_drop_reason'] = m.apply(reason_text, axis=1)
    return m


# ============================================================================
# Stage 3: restated -> Outcome 1 (size assignment + attrition), replicating
# nsu_reference_set.do sections 1-2.
# ============================================================================
def classify_stage3(restated, refset):
    r = restated.copy()
    r['cell'] = list(zip(*[r[c] for c in CASE_COLS]))

    r['drop_no_wref'] = r.w_ref.isna()
    r['drop_unique_mun'] = r.item_nsu_hetero_type.isin([10, 11]) & ~r.drop_no_wref

    active = r[~(r.drop_no_wref | r.drop_unique_mun)].copy()
    has_size = active.groupby('cell')['weighing_approach'].transform(lambda s: (s == 3).any())
    has_price = active.groupby('cell')['weighing_approach'].transform(lambda s: (s == 2).any())
    carrot_mask = has_size & has_price & (active.weighing_approach == 2)
    r['drop_carrot'] = False
    r.loc[active.index[carrot_mask], 'drop_carrot'] = True

    n1 = r.drop_no_wref.sum()
    n2 = r.drop_unique_mun.sum()
    n3 = r.drop_carrot.sum()
    log(f"  stage3 drops (replicated): no usable w_ref={n1} (doc: 7), "
        f"unique_mun_price={n2} (doc: 33), carrot mixed-branch={n3} (doc: 7 -- "
        f"stale; see module docstring, the ILOILO/TIGBAUAN carrot cell currently "
        f"holds 4 price-quantity rows on disk, not 7)")

    eligible = r[~(r.drop_no_wref | r.drop_unique_mun | r.drop_carrot)].copy()
    log(f"  rows entering the Outcome 1 collapse: {len(eligible)} "
        f"(11,360 - {n1 + n2 + n3} = {11360 - n1 - n2 - n3})")

    # ---- size_ord assignment --------------------------------------------------
    size_ord = pd.Series(np.nan, index=eligible.index)
    size_ord[eligible.weighing_approach == 1] = 0
    wa2 = eligible.weighing_approach == 2
    het_to_size = {5: 1, 6: 2, 7: 3, 8: 2, 9: 2}
    size_ord[wa2] = eligible.loc[wa2, 'item_nsu_hetero_type'].map(het_to_size)

    wa3 = eligible.weighing_approach == 3
    field_ord = eligible.loc[wa3, 'item_nsu_hetero_type'].map({2: 1, 3: 2, 4: 3})
    sb = eligible.loc[wa3].copy()
    sb['field_ord'] = field_ord
    if sb.field_ord.isna().any():
        raise SystemExit("FATAL: a size-based row carries a hetero_type outside 2/3/4")

    k_sizes = sb.groupby('cell')['field_ord'].transform(lambda s: s.nunique())
    sb['k_sizes'] = k_sizes
    # rank_map[(cell, rank)] = the field_ord (1=S,2=M,3=L) that sits at empirical
    # rank `rank` (1..k) within this cell -- i.e. the g-th empirical weight group
    # inherits the g-th field label the case actually holds (nsu_reference_set.do
    # sec 2c: "ord_at`j'").
    rank_map = {}
    for cell, g in sb.groupby('cell')['field_ord']:
        for rank, fo in enumerate(sorted(g.unique()), start=1):
            rank_map[(cell, rank)] = fo

    p33 = sb.groupby('cell')['w_ref'].transform(lambda s: stata_pctile(s.values, 33.3333))
    p66 = sb.groupby('cell')['w_ref'].transform(lambda s: stata_pctile(s.values, 66.6667))
    p50 = sb.groupby('cell')['w_ref'].transform(lambda s: stata_pctile(s.values, 50))

    grp = pd.Series(np.nan, index=sb.index)
    m3 = sb.k_sizes == 3
    grp[m3 & (sb.w_ref <= p33)] = 1
    grp[m3 & (sb.w_ref > p33) & (sb.w_ref <= p66)] = 2
    grp[m3 & (sb.w_ref > p66)] = 3
    m2 = sb.k_sizes == 2
    grp[m2 & (sb.w_ref <= p50)] = 1
    grp[m2 & (sb.w_ref > p50)] = 2
    grp[sb.k_sizes == 1] = 1
    sb['grp'] = grp

    sb['size_ord_assigned'] = [
        rank_map.get((c, g), np.nan) for c, g in zip(sb.cell, sb.grp)]
    size_ord.loc[sb.index] = sb.size_ord_assigned

    eligible['size_ord'] = size_ord
    if eligible.size_ord.isna().any():
        n_missing = eligible.size_ord.isna().sum()
        log(f"  *** {n_missing} eligible rows could not be assigned a size_ord "
            f"(replication gap) -- marked 'size unresolved', not guessed ***")

    # ---- validate against the actual published reference set -----------------
    mine = (eligible.dropna(subset=['size_ord'])
            .groupby(CASE_COLS + ['size_ord'])['w_ref']
            .agg(n_mine='size', grams_mine='median').reset_index())
    refset_key = refset.rename(columns={'pull_item': 'pull_item'})
    pub = refset_key[CASE_COLS + ['size_ord', 'n_g', 'grams']]
    check = mine.merge(pub, on=CASE_COLS + ['size_ord'], how='left',
                        indicator=True)
    matched = check._merge == 'both'
    n_match = (matched & (check.n_mine == check.n_g)
               & (check.grams_mine.round(3) == check.grams.round(3))).sum()
    log(f"  case x size groups reconciled against published nsu_reference_set.dta: "
        f"{n_match} of {len(check)} exact n & median match "
        f"({n_match / max(len(check), 1):.1%})")

    pub_lookup = pub.set_index(CASE_COLS + ['size_ord'])[['grams', 'n_g']]
    return r, eligible, pub_lookup


# ============================================================================
# Main
# ============================================================================
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    log("=" * 78)
    log("STAGE 0-1: raw MS -> arrival stage")
    log("=" * 78)
    raw = load_raw()
    log(f"  raw rows: {len(raw)} (expect 11,495)")
    master = load_prelim_master()
    log(f"  master (prelim + weight/unit correction) rows: {len(master)} (expect 11,458)")
    raw, master, stage1_dropped = classify_stage1_drops(raw, master)

    log("=" * 78)
    log("STAGE 2: arrival -> restated")
    log("=" * 78)
    restated = load_restated()
    log(f"  restated rows on disk: {len(restated)} (expect 11,360)")
    master = classify_stage2(master, restated)

    log("=" * 78)
    log("STAGE 3: restated -> Outcome 1")
    log("=" * 78)
    refset = load_refset()
    log(f"  Outcome 1 reference-set rows on disk: {len(refset)}")
    restated_full, eligible, pub_lookup = classify_stage3(restated, refset)

    log("=" * 78)
    log("RECONCILIATION")
    log("=" * 78)
    n_raw = len(raw)
    n_s1_drop = len(stage1_dropped)
    n_master = len(master)
    n_s2_drop = int((~master.in_restated).sum())
    n_restated = len(restated_full)
    n_s3_drop = int(restated_full.drop_no_wref.sum() + restated_full.drop_carrot.sum()
                     + restated_full.drop_unique_mun.sum())
    n_eligible = len(eligible)
    log(f"  {n_raw:,} raw")
    log(f"    - {n_s1_drop} stage-1 drops (1a+1c+1d)")
    log(f"  = {n_master:,} arrival/master")
    log(f"    - {n_s2_drop} stage-2 drops (no-price + vendor-priced-not-rescued)")
    log(f"  = {n_restated:,} restated")
    log(f"    - {n_s3_drop} stage-3 drops (no w_ref + unique_mun_price + carrot)")
    log(f"  = {n_eligible:,} rows entering the Outcome 1 collapse")
    log(f"  -> {len(refset):,} Outcome 1 reference-set rows (aggregation, not attrition)")
    ok = (n_raw - n_s1_drop == n_master) and (n_master - n_s2_drop == n_restated)
    log(f"  reconciles end to end: {ok}")
    if n_raw != 11495 or n_master != 11458 or n_restated != 11360:
        log("  *** WARNING: stage counts do not match the brief's stated "
            "11,495 / 11,458 / 11,360 -- printed above, not silently adjusted ***")

    log("=" * 78)
    log("Building JSON payload and writing HTML")
    log("=" * 78)
    payload = build_payload(raw, master, stage1_dropped, restated_full, eligible,
                             pub_lookup, refset,
                             counts=dict(n_raw=n_raw, n_s1_drop=n_s1_drop,
                                         n_master=n_master, n_s2_drop=n_s2_drop,
                                         n_restated=n_restated, n_s3_drop=n_s3_drop,
                                         n_eligible=n_eligible, n_refset=len(refset)))
    write_html(payload)
    log(f"wrote {OUT_HTML}")


# ----------------------------------------------------------------------------
# Payload assembly
# ----------------------------------------------------------------------------
def nn(x):
    """None for NaN/NaT, otherwise a JSON-safe scalar."""
    if x is None:
        return None
    if isinstance(x, float) and np.isnan(x):
        return None
    if isinstance(x, (np.floating,)):
        if np.isnan(x):
            return None
        return float(x)
    if isinstance(x, (np.integer,)):
        return int(x)
    if isinstance(x, pd.Timestamp):
        if pd.isna(x):
            return None
        return x.isoformat()
    return x


def build_sankey(raw, master, stage1_dropped, restated_full, eligible, counts):
    """Pre-aggregated node/link counts -- never a per-row list here.

    Every non-sink node's inflow is asserted to equal its outflow (a true flow
    partition, not just plausible-looking numbers) -- see the `assert` calls
    below. Outcome 2 is deliberately NOT drawn as a competing branch out of
    "eligible": a row can be counted toward Outcome 1's collapse AND be
    Outcome-2-eligible at the same time (they are different downstream USES of
    the same surviving row, not alternatives), so drawing both as sinks off one
    node would double the outgoing width. Outcome 2 eligibility is reported as
    a separate figure in the page text instead.
    """
    nodes = []
    links = []

    def add_node(nid, label, n):
        nodes.append({"id": nid, "label": label, "n": int(n)})

    def add_link(s, t, n):
        links.append({"source": s, "target": t, "n": int(n)})

    add_node("raw", "Raw MS arrival", counts['n_raw'])
    n_1a = int(stage1_dropped.reason_1a.sum())
    n_1c = int(stage1_dropped.reason_1c.sum())
    n_1d = int(stage1_dropped.reason_1d.sum())
    n_1_unresolved = int((~(stage1_dropped.reason_1a | stage1_dropped.reason_1c
                            | stage1_dropped.reason_1d)).sum())
    add_node("s1_1a", f"Dropped: data-entry error ({n_1a})", n_1a)
    add_node("s1_1c", f"Dropped: standard-quantity label ({n_1c})", n_1c)
    add_node("s1_1d", f"Dropped: TIGBAUAN glitch ({n_1d})", n_1d)
    add_link("raw", "s1_1a", n_1a)
    add_link("raw", "s1_1c", n_1c)
    add_link("raw", "s1_1d", n_1d)
    if n_1_unresolved:
        add_node("s1_unresolved", f"Dropped: reason unresolved ({n_1_unresolved})", n_1_unresolved)
        add_link("raw", "s1_unresolved", n_1_unresolved)

    add_node("cleaned", "Name cleaning + harmonization fold", counts['n_master'])
    add_node("wtunit", "Weight/unit correction", counts['n_master'])
    add_link("raw", "cleaned", counts['n_master'])
    add_link("cleaned", "wtunit", counts['n_master'])

    n_noprice = int(master.reason_2_noprice.sum())
    n_vd = int(master.reason_2_vendor_dropped.sum())
    n_unresolved2 = int((~master.in_restated & ~master.reason_2_noprice
                         & ~master.reason_2_vendor_dropped).sum())
    add_node("s2_noprice", f"Dropped: vendor gave no price ({n_noprice})", n_noprice)
    add_node("s2_vendordrop", f"Dropped: vendor-priced, case keeps preload ({n_vd})", n_vd)
    add_link("wtunit", "s2_noprice", n_noprice)
    add_link("wtunit", "s2_vendordrop", n_vd)
    if n_unresolved2:
        add_node("s2_unresolved", f"Dropped: reason unresolved ({n_unresolved2})", n_unresolved2)
        add_link("wtunit", "s2_unresolved", n_unresolved2)
    add_link("wtunit", "restated", counts['n_restated'])
    add_node("restated", "Restated for inflation", counts['n_restated'])
    assert n_noprice + n_vd + n_unresolved2 + counts['n_restated'] == counts['n_master']

    add_node("s3_nowref", f"Dropped: no usable weight ({int(restated_full.drop_no_wref.sum())})",
              int(restated_full.drop_no_wref.sum()))
    add_node("s3_unique", f"Dropped: unique_mun_price, not a size ({int(restated_full.drop_unique_mun.sum())})",
              int(restated_full.drop_unique_mun.sum()))
    add_node("s3_carrot", f"Dropped: mixed-branch cell, carrot rule ({int(restated_full.drop_carrot.sum())})",
              int(restated_full.drop_carrot.sum()))

    for code, label, nid in [(1, "Conventional branch", "b_conv"),
                              (2, "Price-quantity branch", "b_pq"),
                              (3, "Size-based branch", "b_size")]:
        branch = restated_full[restated_full.weighing_approach == code]
        n_branch = len(branch)
        add_node(nid, label, n_branch)
        add_link("restated", nid, n_branch)

        n_nw = int(branch.drop_no_wref.sum())
        n_uniq = int(branch.drop_unique_mun.sum())
        n_car = int(branch.drop_carrot.sum())
        n_ok = n_branch - n_nw - n_uniq - n_car
        if n_nw:
            add_link(nid, "s3_nowref", n_nw)
        if n_uniq:
            add_link(nid, "s3_unique", n_uniq)
        if n_car:
            add_link(nid, "s3_carrot", n_car)
        add_link(nid, "eligible", n_ok)

    add_node("eligible", "Enters Outcome 1 collapse", counts['n_eligible'])
    add_node("outcome1", f"Outcome 1: {counts['n_refset']:,} reference-set rows "
                          f"(collapsed from {counts['n_eligible']:,})", counts['n_eligible'])
    add_link("eligible", "outcome1", counts['n_eligible'])

    # ---- conservation checks -- fail loudly rather than draw a wrong diagram ----
    by_id = {n['id']: n['n'] for n in nodes}
    inflow = {}
    outflow = {}
    for l in links:
        outflow[l['source']] = outflow.get(l['source'], 0) + l['n']
        inflow[l['target']] = inflow.get(l['target'], 0) + l['n']
    for nid, n in by_id.items():
        if nid == 'raw':
            assert inflow.get(nid, n) == n, f"{nid}: expected no inflow"
        elif nid in ('outcome1',) or nid.startswith('s1_') or nid.startswith('s2_') or nid.startswith('s3_'):
            assert inflow.get(nid) == n, f"{nid}: inflow {inflow.get(nid)} != n {n}"
        else:
            assert inflow.get(nid) == n == outflow.get(nid), (
                f"{nid}: inflow {inflow.get(nid)}, n {n}, outflow {outflow.get(nid)}")
    log("  sankey flow conservation check: OK (every node's inflow/outflow reconciles)")

    return {"nodes": nodes, "links": links}


def build_price_lookup(master_rename):
    """province|municipality|item -> harmonized units seen in the price file
    for that cell, so a selected weighing can find its price rungs."""
    pr = pd.read_csv(PRICE_PATH, encoding='utf-8-sig', dtype=str)
    pr['price'] = pd.to_numeric(pr.Price, errors='coerce')
    pr['P'] = pr.province.map(ng)
    pr['C'] = pr.pull_municipal_city.map(ng)
    pr['I'] = pr.cons_name.map(ni)
    pr['U'] = pr.Unit_lbl.map(nz)

    mr = master_rename.copy()
    mr['P'] = mr.province.map(ng)
    mr['C'] = mr.pull_municipal_city.map(ng)
    mr['I'] = mr.cons_name.map(ni)
    mr['U'] = mr.pull_nsu_unit.map(nz)
    harm_map = {(p, c, i, u): h for p, c, i, u, h in
                zip(mr.P, mr.C, mr.I, mr.U, mr.harmonized_nsu_unit)}
    pr['harmonized_nsu_unit'] = [harm_map.get((p, c, i, u), '')
                                  for p, c, i, u in zip(pr.P, pr.C, pr.I, pr.U)]

    by_cell = {}
    for (p, c, i), g in pr.groupby(['P', 'C', 'I']):
        key = f"{p}|{c}|{i}"
        by_cell[key] = [
            {"raw_unit": row.Unit_lbl, "harmonized_unit": row.harmonized_nsu_unit,
             "price_type": row.price_type, "price": nn(row.price)}
            for row in g.itertuples()
        ]
    log(f"  price-file rows indexed for lookup: {len(pr)} across {len(by_cell)} cells")
    return by_cell


def build_payload(raw, master, stage1_dropped, restated_full, eligible, pub_lookup,
                   refset, counts):
    master_rename = pd.read_csv(MASTER_RENAME_PATH, encoding='utf-8-sig', dtype=str)

    sankey = build_sankey(raw, master, stage1_dropped, restated_full, eligible, counts)
    price_by_cell = build_price_lookup(master_rename)

    # ---- raw-side lookup for arrival provenance (raw spelling, market/vendor) --
    raw_by_key = {k: idx for idx, k in zip(raw.index, raw._key)}

    weighings = []
    eligible_by_id = eligible.set_index('id') if 'id' in eligible.columns else None
    m_by_id = master.set_index('id')

    for row in restated_full.itertuples():
        rid = row.id
        rec = {
            "id": int(rid),
            "province": row.pull_province,
            "municipality": row.pull_municipal_city,
            "item": row.pull_item,
            "raw_spelling": row.pull_nsu_unit,
            "cleaned_unit": row.cleaned_nsu_unit,
            "harmonized_unit": row.harmonized_nsu_unit,
            "weighing_approach": WA_LABEL.get(row.weighing_approach, row.weighing_approach),
            "size_price_label": HETERO_LABEL.get(row.item_nsu_hetero_type, ""),
            "market_type": nn(row.market_type),
            "vendor_id": row.vendor_id,
            "weight_raw": nn(getattr(row, 'weight', None)),
            "corrected_weight": nn(row.corrected_weight),
            "corrected_unit": CORRECTED_UNIT_LABEL.get(row.corrected_unit, ""),
            "pull_price": nn(row.pull_price),
            "actual_price": nn(row.actual_price),
            "price_source": getattr(row, 'price_source', ''),
            "cpi_factor": nn(row.cpi_factor),
            "w_ref": nn(row.w_ref),
            "case_key": f"{row.pull_province}|{row.pull_municipal_city}|{row.pull_item}|"
                        f"{row.harmonized_nsu_unit}|{CORRECTED_UNIT_LABEL.get(row.corrected_unit, '')}",
        }

        # ---- arrival raw-spelling provenance, if the id is joinable ------------
        mrow = m_by_id.loc[rid] if rid in m_by_id.index else None
        rec["raw_spelling_arrival"] = row.pull_nsu_unit  # already the arrival-stage field

        # ---- stage-2 outcome (already survived, since row is in restated) ------
        # ---- stage-3 outcome -----------------------------------------------------
        notes = []
        if row.drop_no_wref:
            rec["terminal"] = "dropped"
            rec["terminal_reason"] = "Stage 3: no usable weight (corrected_weight/w_ref missing)"
        elif row.drop_unique_mun:
            rec["terminal"] = "dropped_outcome1_only"
            rec["terminal_reason"] = ("Stage 3: unique_mun_price is a raw observed price, not a "
                                       "size -- excluded from Outcome 1 only; still eligible for "
                                       "Outcome 2 once it exists")
        elif row.drop_carrot:
            rec["terminal"] = "dropped_outcome1_only"
            rec["terminal_reason"] = ("Stage 3: this cell folds both a size-based and a "
                                       "price-quantity raw label together (the ILOILO/TIGBAUAN "
                                       "carrot rule) -- Outcome 1 keeps only the size-based rows")
        else:
            size_ord = None
            if eligible_by_id is not None and rid in eligible_by_id.index:
                erow = eligible_by_id.loc[rid]
                size_ord = erow.size_ord if not isinstance(erow, pd.DataFrame) else erow.size_ord.iloc[0]
            if size_ord is None or (isinstance(size_ord, float) and np.isnan(size_ord)):
                rec["terminal"] = "survived_unresolved_size"
                rec["terminal_reason"] = ("Enters the Outcome 1 collapse, but this tool's size "
                                           "replication could not assign it a size -- see the "
                                           "generator's docstring")
            else:
                size_ord = int(size_ord)
                rec["size_label"] = SIZE_LABEL.get(size_ord, str(size_ord))
                pub_key = (row.pull_province, row.pull_municipal_city, row.pull_item,
                           row.harmonized_nsu_unit, row.corrected_unit, float(size_ord))
                pub_row = pub_lookup.loc[pub_key] if pub_key in pub_lookup.index else None
                if pub_row is not None:
                    if isinstance(pub_row, pd.DataFrame):
                        pub_row = pub_row.iloc[0]
                    rec["terminal"] = "outcome1_reference_row"
                    rec["outcome1_grams"] = nn(pub_row.grams)
                    rec["outcome1_n"] = nn(pub_row.n_g)
                else:
                    rec["terminal"] = "outcome1_reference_row_unverified"
                    rec["terminal_reason"] = ("Assigned a size by this tool's replication of "
                                               "nsu_reference_set.do, but no matching case x size "
                                               "row was found in the published output -- treat "
                                               "the size label as unverified")

        if row.weighing_approach == 1:
            notes.append("Conventional NSU: no size to resolve, published as the case median.")
        if pd.notna(row.corrected_weight) and pd.notna(getattr(row, 'weight', np.nan)):
            raw_w = getattr(row, 'weight', np.nan)
            unit_lbl = UNIT_LABEL.get(row.unit, str(row.unit))
            if row.corrected_weight != raw_w:
                notes.append(f"Weight/unit snap: {raw_w:g} {unit_lbl} -> "
                             f"{row.corrected_weight:g} {CORRECTED_UNIT_LABEL.get(row.corrected_unit, '')}")
        if row.weighing_approach == 2 and pd.notna(row.cpi_factor) and row.cpi_factor != 1:
            notes.append(f"Restated for inflation: corrected_weight x {row.cpi_factor:.4f} "
                         f"= w_ref {nn(row.w_ref)}")
        if getattr(row, 'price_source', '') == 'vendor_actual':
            notes.append("Price-quantity row rescued: this case had no other price-quantity "
                         "rung, so the vendor's own quoted price was kept instead of dropped.")
        rec["notes"] = notes
        weighings.append(rec)

    # ---- stage-1 dropped raw rows, as their own light records -------------------
    dropped_records = []
    for row in stage1_dropped.itertuples():
        dropped_records.append({
            "province": row.P, "municipality": row.C, "item": row.I,
            "raw_spelling": row.pull_nsu_unit,
            "weighing_approach": WA_LABEL.get(row.wa_num, row.wa_num),
            "size_price_label": HETERO_LABEL.get(row.het, ""),
            "vendor_id": row.vendor_id,
            "stage1_drop_reason": row.stage1_drop_reason,
        })

    # ---- stage-2 dropped rows (in master, never reached restated) --------------
    s2_dropped = master[~master.in_restated]
    for row in s2_dropped.itertuples():
        dropped_records.append({
            "province": row.pull_province, "municipality": row.pull_municipal_city,
            "item": row.pull_item, "raw_spelling": row.pull_nsu_unit,
            "weighing_approach": WA_LABEL.get(row.weighing_approach, row.weighing_approach),
            "size_price_label": HETERO_LABEL.get(row.item_nsu_hetero_type, ""),
            "vendor_id": row.vendor_id,
            "stage1_drop_reason": row.stage2_drop_reason,
        })

    log(f"  weighings embedded (restated rows, in full): {len(weighings)}")
    log(f"  additionally-embedded dropped rows (stage 1 + stage 2, light records): "
        f"{len(dropped_records)}")

    # Outcome 2 has no do-file yet (see module docstring). Rows still "in scope"
    # for it are the eligible rows PLUS the unique_mun_price rows Outcome 1
    # excludes but Outcome 2 would keep (nsu_reference_set.do header) -- i.e.
    # everything except the no-usable-weight and carrot-rule drops.
    n_o2_eligible = int(counts['n_eligible']
                         + restated_full.drop_unique_mun.sum())

    ledger_note = (
        "docs/attrition_ledger.md and its .csv record Stage 2 as dropping 74 rows "
        "(11,458 -> 11,384). The current dofiles/nsu_restate_weights.do and its own "
        "saved log drop 98 (27 'vendor gave no price at all' + 71 'vendor-priced, "
        "case keeps a preloaded rung') -> 11,360, matching the file on disk and this "
        "tool's own counts throughout. docs/data_oddities.md sec.3b already documents "
        "the 27-row rule; the ledger was written earlier and has not been regenerated. "
        "This page uses the files on disk as ground truth and flags the stale figures "
        "here rather than matching them."
    )

    meta = {
        "generated_note": "Generated by dofiles/build_pipeline_explorer.py. Read-only tool; "
                           "nothing here feeds back into the pipeline.",
        "counts": counts,
        "ledger_discrepancy_note": ledger_note,
        "outcome2_note": (f"Outcome 2 (PSPS conversion factors) has no do-file yet -- "
                           f"{n_o2_eligible:,} restated weighings would still be in scope for it "
                           f"(everything except the {int(restated_full.drop_no_wref.sum())} rows "
                           f"with no usable weight and the "
                           f"{int(restated_full.drop_carrot.sum())} carrot-rule rows Outcome 1 and "
                           f"Outcome 2 split between them), but this tool cannot show a terminal "
                           f"Outcome 2 value because none has been built. This is not drawn as a "
                           f"Sankey branch because a row is eligible for Outcome 2 independently "
                           f"of whether it also feeds the Outcome 1 collapse -- drawing both as "
                           f"sinks off one node would double-count the flow."),
    }

    return {
        "meta": meta,
        "sankey": sankey,
        "weighings": weighings,
        "dropped": dropped_records,
        "price_by_cell": price_by_cell,
    }


# ----------------------------------------------------------------------------
# HTML assembly
# ----------------------------------------------------------------------------
def write_html(payload):
    data_json = json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
    html = HTML_TEMPLATE.replace("__DATA_JSON__", data_json)
    OUT_HTML.write_text(html, encoding='utf-8')
    log(f"  HTML size: {len(html) / 1e6:.2f} MB")


HTML_TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>NSU pipeline explorer</title>
<style>
:root {
  --bg: #0f1216; --panel: #161b22; --panel2: #1c232c; --border: #2a323d;
  --text: #e6edf3; --muted: #8b96a5; --accent: #4fa3ff; --accent2: #ffb454;
  --drop: #e5534b; --ok: #3fb950; --warn: #d29922;
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--text);
  font: 14px/1.4 -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif;
}
header {
  padding: 14px 20px; border-bottom: 1px solid var(--border);
  display: flex; align-items: baseline; gap: 16px; flex-wrap: wrap;
}
header h1 { font-size: 17px; margin: 0; }
header .sub { color: var(--muted); font-size: 12.5px; }
.banner {
  margin: 10px 20px; padding: 10px 14px; border: 1px solid var(--warn);
  background: #2a2410; border-radius: 6px; font-size: 12.5px; color: #f0d78c;
}
.layout { display: flex; flex-direction: column; gap: 0; }
section { padding: 16px 20px; border-bottom: 1px solid var(--border); }
h2 { font-size: 14px; margin: 0 0 10px 0; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; }
#sankey-wrap { overflow-x: auto; }
#sankey { display: block; }
.node rect { stroke: var(--border); stroke-width: 1; cursor: pointer; }
.node text { fill: var(--text); font-size: 11px; pointer-events: none; }
.node.selected rect { stroke: var(--accent); stroke-width: 2; }
.link { fill: none; opacity: .35; }
.link:hover { opacity: .6; }
.node.drop rect { fill: var(--drop) !important; }
.node.terminal rect { fill: var(--ok) !important; }
.node.pending rect { fill: var(--warn) !important; }
.filters { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 10px; align-items: center; }
.filters input, .filters select {
  background: var(--panel2); color: var(--text); border: 1px solid var(--border);
  border-radius: 4px; padding: 5px 8px; font-size: 12.5px;
}
.filters input[type=text] { width: 160px; }
.filters .count { color: var(--muted); font-size: 12px; margin-left: auto; }
button.clear { background: var(--panel2); color: var(--muted); border: 1px solid var(--border); border-radius: 4px; padding: 5px 10px; cursor: pointer; font-size: 12px; }
button.clear:hover { color: var(--text); }
#tablewrap { max-height: 420px; overflow: auto; border: 1px solid var(--border); border-radius: 6px; }
table { border-collapse: collapse; width: 100%; font-size: 12.5px; }
th, td { padding: 5px 8px; text-align: left; border-bottom: 1px solid var(--border); white-space: nowrap; }
th { position: sticky; top: 0; background: var(--panel2); cursor: pointer; user-select: none; }
tbody tr:hover { background: var(--panel2); cursor: pointer; }
tbody tr.selected { background: #1e3a5f; }
.tag { display: inline-block; padding: 1px 6px; border-radius: 10px; font-size: 10.5px; }
.tag.dropped { background: rgba(229,83,75,.2); color: #ff9891; }
.tag.ok { background: rgba(63,185,80,.2); color: #7ee787; }
.tag.pending { background: rgba(210,153,34,.2); color: #e3b341; }
#detail { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.detail-col { background: var(--panel); border: 1px solid var(--border); border-radius: 8px; padding: 14px; }
.detail-col h3 { margin: 0 0 10px 0; font-size: 13px; color: var(--accent2); }
.pathstep { display: flex; gap: 10px; padding: 6px 0; border-bottom: 1px dashed var(--border); font-size: 12.5px; }
.pathstep:last-child { border-bottom: none; }
.pathstep .stage { width: 130px; flex-shrink: 0; color: var(--muted); }
.pathstep .val { flex: 1; }
.note { font-size: 12px; color: var(--accent2); background: rgba(255,180,84,.08); border-left: 2px solid var(--accent2); padding: 4px 8px; margin-top: 4px; }
.placeholder { color: var(--muted); font-style: italic; padding: 20px; text-align: center; }
.pricebox { margin-top: 6px; font-size: 12px; }
.pricebox table { font-size: 11.5px; }
footer { padding: 14px 20px; color: var(--muted); font-size: 11.5px; }
a { color: var(--accent); }
</style>
</head>
<body>
<header>
  <h1>NSU pipeline explorer</h1>
  <span class="sub" id="hdr-sub"></span>
</header>
<div id="banner-holder"></div>

<section>
  <h2>1. Flow (Sankey) &mdash; click a node to filter the table below</h2>
  <div id="sankey-wrap"><svg id="sankey"></svg></div>
</section>

<section>
  <h2>2. Observation drill-down &mdash; <span id="filter-summary"></span></h2>
  <div class="filters">
    <input type="text" id="f-province" placeholder="Province">
    <input type="text" id="f-municipality" placeholder="Municipality">
    <input type="text" id="f-item" placeholder="Item">
    <input type="text" id="f-spelling" placeholder="Raw spelling">
    <input type="text" id="f-harmunit" placeholder="Harmonized unit">
    <select id="f-approach"><option value="">Weighing approach: any</option>
      <option value="conventional">conventional</option>
      <option value="price-quantity">price-quantity</option>
      <option value="size-based">size-based</option></select>
    <input type="text" id="f-label" placeholder="Size/price label">
    <input type="text" id="f-vendor" placeholder="Vendor id">
    <button class="clear" id="clear-node-filter" style="display:none">clear node filter</button>
    <span class="count" id="row-count"></span>
  </div>
  <div id="tablewrap">
    <table id="tbl">
      <thead><tr>
        <th data-k="province">Province</th><th data-k="municipality">Municipality</th>
        <th data-k="item">Item</th><th data-k="raw_spelling">Raw spelling</th>
        <th data-k="harmonized_unit">Harmonized unit</th>
        <th data-k="weighing_approach">Approach</th>
        <th data-k="size_price_label">Size/price label</th>
        <th data-k="vendor_id">Vendor</th>
        <th data-k="w_ref">w_ref (g/mL)</th>
        <th data-k="terminal">Terminal state</th>
      </tr></thead>
      <tbody id="tbl-body"></tbody>
    </table>
  </div>
</section>

<section>
  <h2>3. Selected observation &mdash; its path through the build</h2>
  <div id="detail"><div class="placeholder" style="grid-column:1/-1">Select a row above to see its path.</div></div>
</section>

<footer id="footer"></footer>

<script>
const DATA = __DATA_JSON__;

// ---------------------------------------------------------------- header/banner
document.getElementById('hdr-sub').textContent =
  `${DATA.meta.counts.n_raw.toLocaleString()} raw -> ${DATA.meta.counts.n_master.toLocaleString()} arrival -> ` +
  `${DATA.meta.counts.n_restated.toLocaleString()} restated -> ${DATA.meta.counts.n_refset.toLocaleString()} Outcome 1 rows`;

const bannerHolder = document.getElementById('banner-holder');
function banner(text) {
  const d = document.createElement('div');
  d.className = 'banner';
  d.textContent = text;
  bannerHolder.appendChild(d);
}
banner('Known discrepancy vs docs/attrition_ledger.md: ' + DATA.meta.ledger_discrepancy_note);
banner('Outcome 2: ' + DATA.meta.outcome2_note);

document.getElementById('footer').textContent = DATA.meta.generated_note;

// ---------------------------------------------------------------- sankey
(function renderSankey() {
  const nodes = DATA.sankey.nodes;
  const links = DATA.sankey.links;
  const byId = {}; nodes.forEach(n => byId[n.id] = n);

  // simple manual column assignment (topological, by known stage order)
  const columns = {
    raw: 0,
    s1_1a: 1, s1_1c: 1, s1_1d: 1, s1_unresolved: 1, cleaned: 1,
    wtunit: 2,
    s2_noprice: 3, s2_vendordrop: 3, s2_unresolved: 3, restated: 3,
    b_conv: 4, b_pq: 4, b_size: 4,
    s3_nowref: 5, s3_unique: 5, s3_carrot: 5, eligible: 5,
    outcome1: 6,
  };
  nodes.forEach(n => n.col = columns[n.id] ?? 7);
  const maxCol = Math.max(...nodes.map(n => n.col));

  const width = Math.max(1100, 160 * (maxCol + 1) + 200);
  const height = 620;
  const svg = document.getElementById('sankey');
  svg.setAttribute('width', width);
  svg.setAttribute('height', height);
  svg.setAttribute('viewBox', `0 0 ${width} ${height}`);

  const colWidth = (width - 200) / (maxCol + 1);
  const nodeW = 18;
  const total = byId['raw'].n;
  const usableH = height - 40;
  const pxPerUnit = usableH / total;

  // stack nodes within each column, ordered by n desc, then compute y
  const byCol = {};
  nodes.forEach(n => { (byCol[n.col] = byCol[n.col] || []).push(n); });
  Object.values(byCol).forEach(list => {
    list.sort((a, b) => b.n - a.n);
    let y = 20;
    list.forEach(n => {
      n.x = 100 + n.col * colWidth;
      n.y = y;
      n.h = Math.max(4, n.n * pxPerUnit);
      y += n.h + 10;
    });
  });

  const svgns = 'http://www.w3.org/2000/svg';
  function el(tag, attrs) {
    const e = document.createElementNS(svgns, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    return e;
  }

  function nodeClass(n) {
    if (n.id.startsWith('s1_') || n.id.startsWith('s2_') || n.id.startsWith('s3_')) return 'drop';
    if (n.id === 'outcome1') return 'terminal';
    return '';
  }

  // links as simple curved paths between node edges, width proportional to n
  links.forEach(l => {
    const s = byId[l.source], t = byId[l.target];
    if (!s || !t) return;
    const sOffsets = s._outUsed || 0; s._outUsed = sOffsets + l.n;
    const tOffsets = t._inUsed || 0; t._inUsed = tOffsets + l.n;
    const sy0 = s.y + sOffsets * pxPerUnit, sy1 = s.y + (sOffsets + l.n) * pxPerUnit;
    const ty0 = t.y + tOffsets * pxPerUnit, ty1 = t.y + (tOffsets + l.n) * pxPerUnit;
    const x0 = s.x + nodeW, x1 = t.x;
    const xm = (x0 + x1) / 2;
    const d = `M${x0},${sy0} C${xm},${sy0} ${xm},${ty0} ${x1},${ty0} ` +
              `L${x1},${ty1} C${xm},${ty1} ${xm},${sy1} ${x0},${sy1} Z`;
    const path = el('path', { d, class: 'link', fill: '#4fa3ff' });
    path.dataset.n = l.n; path.dataset.source = l.source; path.dataset.target = l.target;
    const title = el('title', {});
    title.textContent = `${byId[l.source].label} -> ${byId[l.target].label}: ${l.n.toLocaleString()}`;
    path.appendChild(title);
    svg.appendChild(path);
  });

  nodes.forEach(n => {
    const g = el('g', { class: 'node ' + nodeClass(n), 'data-id': n.id });
    const rect = el('rect', { x: n.x, y: n.y, width: nodeW, height: n.h,
                               fill: nodeClass(n) ? undefined : '#4fa3ff' });
    g.appendChild(rect);
    const label = el('text', { x: n.x + nodeW + 6, y: n.y + Math.min(n.h, 14) });
    label.textContent = `${n.label} (${n.n.toLocaleString()})`;
    g.appendChild(label);
    const title = el('title', {}); title.textContent = `${n.label}: ${n.n.toLocaleString()}`;
    g.appendChild(title);
    g.addEventListener('click', () => selectNode(n));
    svg.appendChild(g);
  });

  let selectedNode = null;
  function selectNode(n) {
    document.querySelectorAll('.node').forEach(el => el.classList.remove('selected'));
    if (selectedNode && selectedNode.id === n.id) {
      selectedNode = null;
      clearNodeFilter();
      return;
    }
    selectedNode = n;
    document.querySelector(`.node[data-id="${n.id}"]`).classList.add('selected');
    document.getElementById('clear-node-filter').style.display = '';
    applyNodeFilter(n.id);
  }
  window.clearNodeFilter = function () {
    selectedNode = null;
    document.querySelectorAll('.node').forEach(el => el.classList.remove('selected'));
    document.getElementById('clear-node-filter').style.display = 'none';
    nodeFilter = null;
    renderTable();
  };
  document.getElementById('clear-node-filter').addEventListener('click', clearNodeFilter);

  window._sankeyApplyNodeFilter = applyNodeFilter;
})();

// ---------------------------------------------------------------- table + filters
let nodeFilter = null;  // {predicate}

const NODE_PREDICATES = {
  raw: w => true,
  cleaned: w => true,
  wtunit: w => true,
  restated: w => true,
  b_conv: w => w.weighing_approach === 'conventional',
  b_pq: w => w.weighing_approach === 'price-quantity',
  b_size: w => w.weighing_approach === 'size-based',
  eligible: w => !w.terminal.startsWith('dropped'),
  outcome1: w => w.terminal === 'outcome1_reference_row' || w.terminal === 'outcome1_reference_row_unverified',
  s3_nowref: w => w.terminal === 'dropped',
  s3_unique: w => w.terminal_reason && w.terminal_reason.includes('unique_mun_price'),
  s3_carrot: w => w.terminal_reason && w.terminal_reason.includes('carrot'),
};

// stage-1/stage-2 drop sinks live in DATA.dropped (raw rows that never reached
// the restated table this NODE_PREDICATES set filters), matched by a substring
// of their own reason text rather than by a `terminal` field they don't have.
const DROPPED_NODE_MATCH = {
  s1_1a: d => d.stage1_drop_reason.startsWith('1a:'),
  s1_1c: d => d.stage1_drop_reason.startsWith('1c:'),
  s1_1d: d => d.stage1_drop_reason.startsWith('1d:'),
  s1_unresolved: d => d.stage1_drop_reason.startsWith('unresolved'),
  s2_noprice: d => d.stage1_drop_reason.includes('no price at all'),
  s2_vendordrop: d => d.stage1_drop_reason.includes('case retains'),
  s2_unresolved: d => d.stage1_drop_reason.includes('not matched by replication'),
};

function applyNodeFilter(nodeId) {
  if (NODE_PREDICATES[nodeId]) {
    nodeFilter = { id: nodeId, pred: NODE_PREDICATES[nodeId], useDropped: false };
  } else if (DROPPED_NODE_MATCH[nodeId]) {
    nodeFilter = { id: nodeId, pred: DROPPED_NODE_MATCH[nodeId], useDropped: true };
  } else {
    nodeFilter = null;
  }
  renderTable();
}
function clearNodeFilter() { window.clearNodeFilter(); }

const filterIds = ['f-province', 'f-municipality', 'f-item', 'f-spelling', 'f-harmunit', 'f-approach', 'f-label', 'f-vendor'];
filterIds.forEach(id => document.getElementById(id).addEventListener('input', renderTable));

let sortKey = null, sortDir = 1;
document.querySelectorAll('#tbl th').forEach(th => {
  th.addEventListener('click', () => {
    const k = th.dataset.k;
    if (sortKey === k) sortDir *= -1; else { sortKey = k; sortDir = 1; }
    renderTable();
  });
});

function textFilterVal(id) { return document.getElementById(id).value.trim().toLowerCase(); }

function matchesTextFilters(w) {
  const p = textFilterVal('f-province'); if (p && !(w.province||'').toLowerCase().includes(p)) return false;
  const m = textFilterVal('f-municipality'); if (m && !(w.municipality||'').toLowerCase().includes(m)) return false;
  const it = textFilterVal('f-item'); if (it && !(w.item||'').toLowerCase().includes(it)) return false;
  const sp = textFilterVal('f-spelling'); if (sp && !(w.raw_spelling||'').toLowerCase().includes(sp)) return false;
  const hu = textFilterVal('f-harmunit'); if (hu && !(w.harmonized_unit||'').toLowerCase().includes(hu)) return false;
  const ap = document.getElementById('f-approach').value; if (ap && w.weighing_approach !== ap) return false;
  const lb = textFilterVal('f-label'); if (lb && !(w.size_price_label||'').toLowerCase().includes(lb)) return false;
  const ve = textFilterVal('f-vendor'); if (ve && !(w.vendor_id||'').toLowerCase().includes(ve)) return false;
  return true;
}

function isDroppedRecord(w) { return w.stage1_drop_reason !== undefined; }

function terminalTag(w) {
  if (isDroppedRecord(w)) {
    const stage = /^(1a|1c|1d|unresolved)/.test(w.stage1_drop_reason) ? 'before arrival stage' : 'before restated stage';
    return `<span class="tag dropped">dropped ${stage}</span>`;
  }
  if (w.terminal === 'dropped') return '<span class="tag dropped">dropped</span>';
  if (w.terminal === 'dropped_outcome1_only') return '<span class="tag pending">excluded (Outcome 1 only)</span>';
  if (w.terminal === 'outcome1_reference_row') return `<span class="tag ok">Outcome 1: ${w.size_label||''}, ${w.outcome1_grams} g/mL</span>`;
  if (w.terminal === 'outcome1_reference_row_unverified') return `<span class="tag pending">Outcome 1 (unverified size)</span>`;
  return '<span class="tag pending">survived, size unresolved</span>';
}

let currentRows = [];
function renderTable() {
  const usingDropped = !!(nodeFilter && nodeFilter.useDropped);
  let rows = (usingDropped ? DATA.dropped : DATA.weighings).filter(matchesTextFilters);
  document.getElementById('filter-summary').textContent =
    nodeFilter ? `filtered by Sankey node: ${nodeFilter.id}` : 'no Sankey node selected';
  if (nodeFilter) {
    rows = rows.filter(nodeFilter.pred);
  }
  if (sortKey) {
    rows = rows.slice().sort((a, b) => {
      const av = a[sortKey], bv = b[sortKey];
      if (av == null) return 1; if (bv == null) return -1;
      if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * sortDir;
      return String(av).localeCompare(String(bv)) * sortDir;
    });
  }
  currentRows = rows;
  document.getElementById('row-count').textContent =
    `${rows.length.toLocaleString()} rows` + (usingDropped ? ' (dropped rows, not weighings)' : '');
  const body = document.getElementById('tbl-body');
  const MAX_RENDER = 2000;
  const shown = rows.slice(0, MAX_RENDER);
  body.innerHTML = shown.map((w, i) => `
    <tr data-idx="${i}">
      <td>${w.province||''}</td><td>${w.municipality||''}</td><td>${w.item||''}</td>
      <td>${w.raw_spelling||''}</td><td>${w.harmonized_unit||''}</td>
      <td>${w.weighing_approach||''}</td><td>${w.size_price_label||''}</td>
      <td>${w.vendor_id||''}</td><td>${w.w_ref!=null? w.w_ref.toLocaleString(undefined,{maximumFractionDigits:1}):''}</td>
      <td>${terminalTag(w)}</td>
    </tr>`).join('');
  if (rows.length > MAX_RENDER) {
    const note = document.createElement('tr');
    note.innerHTML = `<td colspan="10" style="color:var(--muted);font-style:italic">
      showing first ${MAX_RENDER.toLocaleString()} of ${rows.length.toLocaleString()} filtered rows -- narrow the filters to see more</td>`;
    body.appendChild(note);
  }
  Array.from(body.querySelectorAll('tr[data-idx]')).forEach(tr => {
    tr.addEventListener('click', () => selectRow(shown[+tr.dataset.idx]));
  });
}
renderTable();

// ---------------------------------------------------------------- detail panel
function selectRow(w) {
  document.querySelectorAll('#tbl-body tr').forEach(tr => tr.classList.remove('selected'));
  const idx = currentRows.indexOf(w);
  const tr = document.querySelector(`#tbl-body tr[data-idx="${idx}"]`);
  if (tr) tr.classList.add('selected');

  const left = document.createElement('div');
  left.className = 'detail-col';
  if (isDroppedRecord(w)) {
    const isStage1 = /^(1a|1c|1d|unresolved)/.test(w.stage1_drop_reason);
    const gapNote = isStage1
      ? `This row never reached the arrival stage (prelim_nsu_data.dta), so it has no cleaned `
        + `unit, corrected weight, or w_ref -- there is nothing further in its path to show.`
      : `This row reached the arrival stage but was dropped before the restated stage `
        + `(nsu_weights_restated.dta), so it has no corrected weight or w_ref -- there is `
        + `nothing further in its path to show.`;
    left.innerHTML = `<h3>Path through the build</h3>` + [
      ['Raw arrival', `${w.province} / ${w.municipality} / ${w.item} / "${w.raw_spelling}"`],
      ['Weighing approach', `${w.weighing_approach} (${w.size_price_label})`],
      ['Vendor', w.vendor_id],
      ['Terminal state', terminalTag(w)],
    ].map(([k, v]) => `<div class="pathstep"><div class="stage">${k}</div><div class="val">${v}</div></div>`).join('')
     + `<div class="note">${w.stage1_drop_reason}</div>`
     + `<div class="note">${gapNote}</div>`;
  } else {
    left.innerHTML = `<h3>Path through the build (id ${w.id})</h3>` + [
      ['Raw arrival', `${w.province} / ${w.municipality} / ${w.item} / "${w.raw_spelling}"`],
      ['Name cleaning', w.cleaned_unit],
      ['Harmonization fold', w.harmonized_unit],
      ['Weighing approach', `${w.weighing_approach} (${w.size_price_label})`],
      ['Weight, as recorded', w.weight_raw != null ? w.weight_raw : '(missing)'],
      ['Weight/unit correction', w.corrected_weight != null ? `${w.corrected_weight} ${w.corrected_unit}` : '(missing)'],
      ['Price', w.pull_price != null ? w.pull_price : (w.actual_price != null ? w.actual_price + ' (vendor actual)' : 'n/a (size-based)')],
      ['Restated (w_ref)', w.w_ref != null ? `${w.w_ref} (cpi_factor ${w.cpi_factor})` : '(missing)'],
      ['Case', w.case_key],
      ['Terminal state', terminalTag(w)],
    ].map(([k, v]) => `<div class="pathstep"><div class="stage">${k}</div><div class="val">${v}</div></div>`).join('')
     + (w.terminal_reason ? `<div class="note">${w.terminal_reason}</div>` : '')
     + (w.notes && w.notes.length ? w.notes.map(n => `<div class="note">${n}</div>`).join('') : '');
  }

  const right = document.createElement('div');
  right.className = 'detail-col';
  const cellKey = `${w.province}|${w.municipality}|${w.item}`;
  const prices = (DATA.price_by_cell[cellKey] || []);
  const samehunit = prices.filter(p => p.harmonized_unit === w.harmonized_unit);
  const other = prices.filter(p => p.harmonized_unit !== w.harmonized_unit);
  right.innerHTML = `<h3>Price-file rows for this cell</h3>` +
    (prices.length === 0 ? '<div class="placeholder">no price-file rows for this province/municipality/item</div>' :
    `<div class="pricebox"><b>Same harmonized unit (${w.harmonized_unit || 'n/a'})</b>` +
    renderPriceTable(samehunit) +
    (other.length ? `<b>Other units in this cell</b>` + renderPriceTable(other) : '') +
    `</div>`);

  const detail = document.getElementById('detail');
  detail.innerHTML = '';
  detail.appendChild(left);
  detail.appendChild(right);
}

function renderPriceTable(rows) {
  if (!rows.length) return '<div class="placeholder">none</div>';
  return '<table><thead><tr><th>raw unit</th><th>harmonized</th><th>price type</th><th>price</th></tr></thead><tbody>' +
    rows.map(p => `<tr><td>${p.raw_unit}</td><td>${p.harmonized_unit}</td><td>${p.price_type}</td><td>${p.price}</td></tr>`).join('') +
    '</tbody></table>';
}
</script>
</body>
</html>
"""


if __name__ == "__main__":
    sys.exit(main())
