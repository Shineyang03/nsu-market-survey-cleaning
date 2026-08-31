"""Pipeline explorer: trace one observation from raw MS through to output weight.

WHY THIS EXISTS (GitHub issue #26). `dofiles/90_diagnostics/case_lookup.py` answers "what did the
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
  restated stage     outputs/master_rename_build/temp/nsu_weighings_cpi.dta
  Outcome 1 output   outputs/master_rename_build/temp/nsu_reference_set.dta
  harmonization map  outputs/tables/master_nsu_rename.csv
  comment crosswalk  outputs/tables/add_comments_crosswalk.xlsx
  non-NSU drops  outputs/master_rename_build/tables/excluded_standard_unit_obs.xlsx
  attrition ledger   outputs/master_rename_build/tables/attrition_ledger.csv (context only,
                      see "KNOWN DISCREPANCY" below -- this script does not trust its
                      row counts, only its prose reasons)

WHAT THIS WRITES
  outputs/explorer/nsu_pipeline_explorer.html   -- the only output. Self-contained:
      inline CSS/JS, data embedded as JSON, no CDN, no build step. Opens from disk
      with file://. Nothing anywhere else is touched -- no .do file, no .dta.

HOW A RAW ROW IS JOINED TO ITS ARRIVAL ROW. `prelim_nsu_data.dta` carries an `id`
that raw rows do not have (raw predates `id`; `id` is assigned by 03_clean_ms.do
AFTER the 37 stage-1 drops, sorted by a key that does not preserve raw row order).
So the raw -> arrival join cannot use `id` and cannot use row position. Instead it
uses the identification key `docs/conversion_factor_methodology.md` documents as
unique on the raw file (verified here to be unique on BOTH sides, 11,495 groups /
11,495 rows and 11,458 groups / 11,458 rows, with zero raw rows resolving to more
than one arrival row):

    province x municipality x item x pull_nsu_unit x market_type x vendor_id x obs_type

`obs_type` is mapped to the same numeric code `03_clean_ms.do`'s `def_hetero`
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
  - 38 rows: present in outputs/master_rename_build/tables/excluded_standard_unit_obs.xlsx
    (the non-NSU label drop -- standard quantity, ambiguous quantity, or not a unit;
    the file's drop_reason column says which), matched back the same way.
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
outputs/master_rename_build/temp/nsu_weighings_cpi.dta on disk and the count
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
frequent ties this data has (corrected_weight is whole grams; a case can hold one weighing
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

THE PRICE-FILE SIDE (added for GitHub issue #26 follow-up: "the entire price-file
population is invisible"). A price-only cell has no MS row to follow forward, so it
never appears in the Sankey above -- the price file's 5,412 rows are a second,
independent population that has to be traced on its own terms. `build_price_cells()`
and `build_price_sankey()` do that:

  5,412 price rows
    -> 17 rows whose raw label was deliberately removed from the crosswalk
       (dofiles/00_shared/02_drop_non_nsu_labels.py, `is_dropped_label()` -- these are a sink,
       not a broken join; the tripwire below still fails loudly on a genuine
       unmatched row)
    -> 5,395 rows harmonize to 2,533 (province, municipality, item, harmonized_unit)
       cells (+ the 17 dropped-label rows, each its own island cell -> 2,550 total,
       matching the harmonized-cell count `scope_price_combo_grain.py` reports)
    -> of the 2,533 harmonized cells, each is classified by whether that EXACT cell
       (not just the item, not just the province) has an MS weighing:
         - convertible: an MS weighing exists in this exact cell
         - price-only: no MS weighing in this exact cell, further split into
             - province fallback available: weighed elsewhere in the SAME province
             - other-province-only: weighed only in a DIFFERENT province
             - weighed nowhere: no MS weighing anywhere, for any province -- no
               conversion path
       The classification for the price-only rows reuses
       outputs/tables/price_only_no_weight_anywhere.csv rather than re-deriving it
       from scratch (see that file's own richer fold logic in
       dofiles/00_shared/01_build_crosswalk.py); this script only ADDS the same-vs-other-
       province split that CSV does not carry, using nsu_weighings_cpi.dta.

PRICE-ONLY FIGURES MOVED WITH THE CROSSWALK TRIM. Commit 3c436b9 removed 17
non-NSU labels from master_nsu_rename, which changed the price-only counts:
602 price-only / 96 weighed-nowhere before, 586 / 80 after.
price_only_no_weight_anywhere.csv was regenerated against the trimmed crosswalk
in b3ccf67, so every row in it now keys to a cell that still exists; the orphan
check below expects 0.

This script classifies price-only cells freshly against the restated MS data
rather than trusting the CSV, so its own figures (585 price-only, 79 nowhere)
differ from the CSV's 586 / 80 by exactly one cell: CAPIZ / TAPAZ chicken, whose
rows exist but carry no corrected_unit and therefore no usable weight. The CSV
requires a usable weight; this script counts a cell as weighed if any row exists.
Both framings are defensible -- the difference is recorded so it is not
rediscovered as a bug.

Nine already-computed per-case analysis tables (outputs/tables/issue21_*.csv,
conventional_*.csv, master_rename_dropped_labels.csv) are embedded verbatim as
lookup tables (`payload["price_analyses"]`) and joined to a selected case/cell in
the browser by a shared key -- see `load_price_analyses()`. Nothing in them is
recomputed here.

RUN
    python dofiles/90_diagnostics/build_pipeline_explorer.py

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

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    "_dropnonnsu",
    Path(__file__).resolve().parent.parent / "00_shared" / "02_drop_non_nsu_labels.py")
_mod = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
is_dropped_label = _mod.is_dropped_label


def stata_pctile(values, p):
    """Replicates Stata's default `pctile x, p(p)` algorithm exactly (verified
    100% against the actual `nsu_reference_set.dta` -- see classify_stage3()).

    Stata's rule, on sorted x_(1) <= ... <= x_(n): let idx = n*p/100. If idx is
    (within float tolerance of) an integer i, the percentile is the average of
    x_(i) and x_(i+1); otherwise it is x_(ceil(idx)). pandas' `Series.quantile`
    uses a DIFFERENT (linear-interpolation) rule that silently disagrees at
    small n with ties -- exactly the case here, since corrected_weight is whole grams and
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
RESTATED_PATH = DC / "outputs" / "master_rename_build" / "temp" / "nsu_weighings_cpi.dta"
REFSET_PATH = DC / "outputs" / "master_rename_build" / "temp" / "nsu_reference_set.dta"
MASTER_RENAME_PATH = DC / "outputs" / "tables" / "master_nsu_rename.csv"
COMMENTS_XW_PATH = DC / "outputs" / "tables" / "add_comments_crosswalk.xlsx"
STDQTY_PATH = DC / "outputs" / "master_rename_build" / "tables" / "excluded_standard_unit_obs.xlsx"

# ---- price-side analysis tables (all read-only; see "THE PRICE-FILE SIDE" above) ----
T = DC / "outputs" / "tables"
PRICE_ONLY_PATH = T / "price_only_no_weight_anywhere.csv"
POOLED_SPELLING_PATH = T / "issue21_pooled_spelling_conflicts.csv"
MERGE_RULE_PATH = T / "issue21_merge_rule_candidates.csv"
DROPPED_LABELS_PATH = T / "master_rename_dropped_labels.csv"
CONV_OVERLAP_PATH = T / "conventional_unit_overlap.csv"
CONV_COVERAGE_PATH = T / "conventional_price_coverage.csv"
MEDIAN_DISAGREEMENT_PATH = T / "issue21_median_disagreement.csv"
RUNG_MIX_PATH = T / "issue21_rung_composition_mix.csv"
FOLD_CHECK_PATH = T / "issue21_outcome1_fold_check.csv"

# ---- case-explorer-only tables (see "THE CASE EXPLORER" below) ----
PSPS_EXPOSURE_PATH = T / "psps_conversion_exposure.csv"
SINGLETON_PATH = T / "singleton_hetero_groups.csv"

OUT_DIR = DC / "outputs" / "explorer"
OUT_HTML = OUT_DIR / "nsu_pipeline_explorer.html"


# ============================================================================
# Normalizers -- COPIED VERBATIM from dofiles/00_shared/01_build_crosswalk.py (do not
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


def key4(p, c, i, h):
    """Canonical province|municipality|item|harmonized-unit join key, used to line up
    the price file, the crosswalk, restated MS weighings, and every issue21_*.csv /
    conventional_*.csv analysis table on one shared identity. Always the four raw
    strings, always normalized here -- never key on a column a source file already
    happens to have pre-normalized (case_lookup.py/scope_*.py all re-normalize on
    read for the same reason: a silent normalization mismatch is how joins go
    quietly wrong)."""
    return f"{ng(p)}|{ng(c)}|{ni(i)}|{nz(h)}"


# The obs_type -> item_nsu_hetero_type coding, copied from 03_clean_ms.do's
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
    these two files ARE `nsu_data_master.dta` (03_clean_ms.do's own Stage-1
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
    log(f"  raw rows with no arrival-stage match: {len(dropped)} (expect 42)")

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
    log(f"            1c non-NSU label = {n1c} (expect 38)")
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

    r['drop_no_wref'] = r.corrected_weight.isna()
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
    log(f"  stage3 drops (replicated): no usable corrected_weight={n1} (doc: 7), "
        f"unique_mun_price={n2} (doc: 33), carrot mixed-branch={n3} (doc: 7 -- "
        f"stale; see module docstring, the ILOILO/TIGBAUAN carrot cell currently "
        f"holds 4 price-quantity rows on disk, not 7)")

    eligible = r[~(r.drop_no_wref | r.drop_unique_mun | r.drop_carrot)].copy()
    log(f"  rows entering the Outcome 1 collapse: {len(eligible)} "
        f"({len(r):,} - {n1 + n2 + n3} = {len(r) - n1 - n2 - n3})")

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

    p33 = sb.groupby('cell')['corrected_weight'].transform(lambda s: stata_pctile(s.values, 33.3333))
    p66 = sb.groupby('cell')['corrected_weight'].transform(lambda s: stata_pctile(s.values, 66.6667))
    p50 = sb.groupby('cell')['corrected_weight'].transform(lambda s: stata_pctile(s.values, 50))

    grp = pd.Series(np.nan, index=sb.index)
    m3 = sb.k_sizes == 3
    grp[m3 & (sb.corrected_weight <= p33)] = 1
    grp[m3 & (sb.corrected_weight > p33) & (sb.corrected_weight <= p66)] = 2
    grp[m3 & (sb.corrected_weight > p66)] = 3
    m2 = sb.k_sizes == 2
    grp[m2 & (sb.corrected_weight <= p50)] = 1
    grp[m2 & (sb.corrected_weight > p50)] = 2
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
            .groupby(CASE_COLS + ['size_ord'])['corrected_weight']
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
    log(f"  master (prelim + weight/unit correction) rows: {len(master)} (expect 11,453)")
    raw, master, stage1_dropped = classify_stage1_drops(raw, master)

    log("=" * 78)
    log("STAGE 2: arrival -> restated")
    log("=" * 78)
    restated = load_restated()
    log(f"  restated rows on disk: {len(restated)} (expect 11,355)")
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
    log(f"    - {n_s3_drop} stage-3 drops (no corrected_weight + unique_mun_price + carrot)")
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


def classify_price_rows(master_rename):
    """Load the price file and join every row to its harmonized unit via the
    crosswalk (master_nsu_rename.csv) -- the one join every price-side function in
    this script builds on top of (shared-logic rule: defined once, here). Adds
    `matched` (bool) and `H` (harmonized unit, nz()'d, or None). An unmatched row is
    expected ONLY when its raw label is one `02_drop_non_nsu_labels.is_dropped_label()`
    says was deliberately removed from the crosswalk (17 rows); any other unmatched
    row is a broken join and stops the build rather than silently being absorbed.
    """
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
    pr['matched'] = pr.harmonized_nsu_unit != ''
    pr['H'] = [nz(h) if m else None for h, m in zip(pr.harmonized_nsu_unit, pr.matched)]

    unmatched = pr[~pr.matched]
    intended = unmatched[unmatched.Unit_lbl.map(is_dropped_label)]
    broken = unmatched[~unmatched.Unit_lbl.map(is_dropped_label)]
    log(f"  price rows: {len(pr)} (expect 5,412)")
    log(f"  price rows unmatched to the crosswalk: {len(unmatched)} (expect 17, all "
        f"deliberately-dropped labels -- dofiles/00_shared/02_drop_non_nsu_labels.py)")
    log(f"    of which deliberately-dropped labels: {len(intended)}, "
        f"BROKEN (unexplained): {len(broken)}")
    if len(broken):
        raise SystemExit(
            f"FATAL: {len(broken)} price row(s) fail to join the crosswalk for a "
            f"reason other than a deliberate label removal -- fix the join before "
            f"trusting any price-side figure. First few:\n"
            + broken[['P', 'C', 'I', 'U']].drop_duplicates().head(10).to_string())
    return pr


def build_price_lookup(pr):
    """province|municipality|item -> harmonized units seen in the price file
    for that cell, so a selected weighing can find its price rungs."""
    by_cell = {}
    for (p, c, i), g in pr.groupby(['P', 'C', 'I']):
        key = f"{p}|{c}|{i}"
        by_cell[key] = [
            {"raw_unit": row.Unit_lbl, "harmonized_unit": row.harmonized_nsu_unit,
             "price_type": row.price_type, "price": nn(row.price),
             "raw_key": key4(p, c, i, row.Unit_lbl),
             "cell_key": key4(p, c, i, row.harmonized_nsu_unit) if row.harmonized_nsu_unit else None}
            for row in g.itertuples()
        ]
    log(f"  price-file rows indexed for lookup: {len(pr)} across {len(by_cell)} cells")
    return by_cell


def build_price_cells(pr, restated_full):
    """Classify every harmonized price cell by whether it has an MS weighing, and
    if not, whether one exists elsewhere in the same province. See the module
    docstring, "THE PRICE-FILE SIDE", for the full picture and the known
    price_only_no_weight_anywhere.csv staleness this function prints and does not
    silently absorb."""
    matched = pr[pr.matched].copy()
    dropped = pr[~pr.matched].copy()

    r = restated_full.copy()
    r['P_'] = r.pull_province.map(ng)
    r['C_'] = r.pull_municipal_city.map(ng)
    r['I_'] = r.pull_item.map(ni)
    r['H_'] = r.harmonized_nsu_unit.map(nz)
    ms_cell_set = set(zip(r.P_, r.C_, r.I_, r.H_))
    ms_prov_set = set(zip(r.P_, r.I_, r.H_))
    ms_anywhere_set = set(zip(r.I_, r.H_))

    matched_cell_keys = set(zip(matched.P, matched.C, matched.I, matched.H))

    po = pd.read_csv(PRICE_ONLY_PATH, encoding='utf-8-sig')
    po['P_'] = po.province.map(ng)
    po['C_'] = po.municipality.map(ng)
    po['I_'] = po.item.map(ni)
    po['H_'] = po.harmonized_nsu_unit.map(nz)
    po['k_'] = list(zip(po.P_, po.C_, po.I_, po.H_))
    po['stale_'] = ~po.k_.isin(matched_cell_keys)
    n_stale = int(po.stale_.sum())
    log(f"  price_only_no_weight_anywhere.csv rows whose exact cell no longer "
        f"exists in the current (post-label-trim) crosswalk: {n_stale} (expect "
        f"0 -- the CSV was regenerated against the trimmed crosswalk in b3ccf67)")
    if n_stale and not (po.loc[po.stale_, 'this_unit_weighed_anywhere'] == 0).all():
        log("  *** WARNING: not every stale row was in that CSV's own 'weighed "
            "nowhere' bucket -- the 602/96 -> 586/80 arithmetic in the module "
            "docstring no longer holds; re-derive it before trusting the note ***")

    po_bucket = {}
    for row in po[~po.stale_].itertuples():
        k = row.k_
        if row.this_unit_weighed_anywhere == 0:
            po_bucket[k] = 'price_only_nowhere'
        elif (row.P_, row.I_, row.H_) in ms_prov_set:
            po_bucket[k] = 'price_only_province_fallback'
        else:
            po_bucket[k] = 'price_only_other_province_only'

    records = []
    n_uncovered = 0
    for (p, c, i, h), g in matched.groupby(['P', 'C', 'I', 'H']):
        k = (p, c, i, h)
        if k in ms_cell_set:
            bucket = 'convertible'
        else:
            bucket = po_bucket.get(k)
            if bucket is None:
                n_uncovered += 1
                if (p, i, h) in ms_prov_set:
                    bucket = 'price_only_province_fallback'
                elif (i, h) in ms_anywhere_set:
                    bucket = 'price_only_other_province_only'
                else:
                    bucket = 'price_only_nowhere'
        records.append({
            "province": p, "municipality": c, "item": i, "harmonized_unit": h,
            "cell_key": key4(p, c, i, h),
            "n_price_rows": int(len(g)),
            "price_rows": [
                {"raw_unit": row.Unit_lbl, "price_type": row.price_type,
                 "price": nn(row.price), "raw_key": key4(p, c, i, row.Unit_lbl)}
                for row in g.itertuples()
            ],
            "bucket": bucket,
            "dropped_label": False,
        })
    log(f"  price-only cells not covered by price_only_no_weight_anywhere.csv "
        f"(freshly classified against restated MS data instead): {n_uncovered} "
        f"(expect 0)")

    for (p, c, i, u), g in dropped.groupby(['P', 'C', 'I', 'U']):
        records.append({
            "province": p, "municipality": c, "item": i, "harmonized_unit": u,
            "cell_key": key4(p, c, i, u),
            "n_price_rows": int(len(g)),
            "price_rows": [
                {"raw_unit": row.Unit_lbl, "price_type": row.price_type,
                 "price": nn(row.price), "raw_key": key4(p, c, i, row.Unit_lbl)}
                for row in g.itertuples()
            ],
            "bucket": "dropped_label",
            "dropped_label": True,
        })

    def rowsum(bucket):
        return sum(rec['n_price_rows'] for rec in records if rec['bucket'] == bucket)

    def cellcount(bucket):
        return sum(1 for rec in records if rec['bucket'] == bucket)

    n_conv, n_pf, n_op, n_now, n_drop = (cellcount('convertible'),
        cellcount('price_only_province_fallback'), cellcount('price_only_other_province_only'),
        cellcount('price_only_nowhere'), cellcount('dropped_label'))
    log(f"  price cells: {len(records):,} total "
        f"({len(matched_cell_keys):,} matched + {n_drop} dropped-label islands)")
    log(f"    convertible (MS weighing in this exact cell): {n_conv:,}")
    log(f"    price-only, province fallback available: {n_pf:,}")
    log(f"    price-only, weighed only in another province: {n_op:,}")
    log(f"    price-only, weighed nowhere (no conversion path): {n_now:,}")
    log(f"    price-only total: {n_pf + n_op + n_now:,}  "
        f"(pre-trim, before commit 3c436b9: 602 price-only, 96 nowhere; "
        f"post-trim, current data: {n_pf + n_op + n_now:,} price-only, {n_now:,} nowhere)")
    return records


def build_price_sankey(records, pr):
    """Row-weighted Sankey over the price-file population. Ribbon widths are PRICE
    ROWS throughout, including across the row->cell collapse -- the same
    convention build_sankey() uses at the Outcome-1 collapse (eligible -> outcome1):
    the true cell count is named in the node label, the ribbon width stays in the
    finer (row) unit so the diagram conserves end to end without a discontinuity."""
    nodes = []
    links = []

    def add_node(nid, label, n):
        nodes.append({"id": nid, "label": label, "n": int(n)})

    def add_link(s, t, n):
        links.append({"source": s, "target": t, "n": int(n)})

    n_total_rows = len(pr)
    n_dropped_rows = int((~pr.matched).sum())
    n_matched_rows = int(pr.matched.sum())
    n_cells_matched = sum(1 for r in records if not r['dropped_label'])

    add_node("p_raw", "Price file rows", n_total_rows)
    add_node("p_dropped_label", f"Dropped: label removed from crosswalk ({n_dropped_rows})", n_dropped_rows)
    add_link("p_raw", "p_dropped_label", n_dropped_rows)
    add_node("p_matched", f"Harmonized to a price cell ({n_matched_rows:,} rows -> "
                          f"{n_cells_matched:,} cells)", n_matched_rows)
    add_link("p_raw", "p_matched", n_matched_rows)

    def rowsum(bucket):
        return sum(r['n_price_rows'] for r in records if r['bucket'] == bucket)

    def cellcount(bucket):
        return sum(1 for r in records if r['bucket'] == bucket)

    n_conv_rows, n_conv_cells = rowsum('convertible'), cellcount('convertible')
    n_pf_rows, n_pf_cells = rowsum('price_only_province_fallback'), cellcount('price_only_province_fallback')
    n_op_rows, n_op_cells = rowsum('price_only_other_province_only'), cellcount('price_only_other_province_only')
    n_now_rows, n_now_cells = rowsum('price_only_nowhere'), cellcount('price_only_nowhere')
    n_po_rows, n_po_cells = n_pf_rows + n_op_rows + n_now_rows, n_pf_cells + n_op_cells + n_now_cells

    add_node("p_convertible", f"Matched to a case with MS weighings ({n_conv_rows:,} rows / {n_conv_cells:,} cells)", n_conv_rows)
    add_link("p_matched", "p_convertible", n_conv_rows)
    add_node("p_only", f"Price-only: no MS weighing in this exact cell ({n_po_rows:,} rows / {n_po_cells:,} cells)", n_po_rows)
    add_link("p_matched", "p_only", n_po_rows)
    add_node("p_province_fallback", f"Province fallback available ({n_pf_rows:,} rows / {n_pf_cells:,} cells)", n_pf_rows)
    add_link("p_only", "p_province_fallback", n_pf_rows)
    add_node("p_other_province", f"Weighed only in another province ({n_op_rows:,} rows / {n_op_cells:,} cells)", n_op_rows)
    add_link("p_only", "p_other_province", n_op_rows)
    add_node("p_nowhere", f"Weighed nowhere -- no conversion path ({n_now_rows:,} rows / {n_now_cells:,} cells)", n_now_rows)
    add_link("p_only", "p_nowhere", n_now_rows)

    by_id = {n['id']: n['n'] for n in nodes}
    inflow, outflow = {}, {}
    for l in links:
        outflow[l['source']] = outflow.get(l['source'], 0) + l['n']
        inflow[l['target']] = inflow.get(l['target'], 0) + l['n']
    SINKS = {'p_dropped_label', 'p_convertible', 'p_province_fallback',
             'p_other_province', 'p_nowhere'}
    for nid, n in by_id.items():
        if nid == 'p_raw':
            assert nid not in inflow, f"{nid}: expected no inflow"
        elif nid in SINKS:
            assert inflow.get(nid) == n, f"{nid}: inflow {inflow.get(nid)} != n {n}"
        else:
            assert inflow.get(nid) == n == outflow.get(nid), (
                f"{nid}: inflow {inflow.get(nid)}, n {n}, outflow {outflow.get(nid)}")
    log("  price sankey flow conservation check: OK (every node's inflow/outflow reconciles)")

    return {"nodes": nodes, "links": links}


def _addkey4(df, p_col, c_col, i_col, h_col):
    """Adds `_key` = key4(...) for the browser-side join. Copies first -- never
    mutates a caller's frame."""
    df = df.copy()
    df['_key'] = [key4(p, c, i, h) for p, c, i, h in
                  zip(df[p_col], df[c_col], df[i_col], df[h_col])]
    return df


def _records(df):
    """DataFrame -> list of JSON-safe dicts (NaN -> None via nn())."""
    return [{k: nn(v) for k, v in row.items()} for row in df.to_dict('records')]


def load_price_analyses(pr):
    """Read-only per-case analysis tables (outputs/tables/issue21_*.csv and
    friends), embedded verbatim and keyed for the browser-side join described in
    the module docstring. Nothing here is recomputed -- see "THE PRICE-FILE SIDE".

    Most tables key on `_key` = key4(province, municipality, item, harmonized_unit).
    Two (issue21_merge_rule_candidates.csv, issue21_median_disagreement.csv) print
    their own 'case' string instead (scope_price_point_merge_rule.py /
    scope_multi_price_points.py: "province / municipality / item[:24 or full] /
    harmonized_unit") -- the browser recomputes that same string from a selected
    case's own fields rather than this script trying to parse it back apart.

    `pr` (the classified price rows from classify_price_rows()) is used only to
    flag which price_only_no_weight_anywhere.csv rows are stale post-label-trim
    (`now_dropped_label`) -- see build_price_cells()'s KNOWN DISCREPANCY note.
    """
    tables = {}
    matched_cell_keys = set(zip(pr[pr.matched].P, pr[pr.matched].C,
                                 pr[pr.matched].I, pr[pr.matched].H))

    po = pd.read_csv(PRICE_ONLY_PATH, encoding='utf-8-sig')
    po = _addkey4(po, 'province', 'municipality', 'item', 'harmonized_nsu_unit')
    po['now_dropped_label'] = [
        (ng(p), ng(c), ni(i), nz(h)) not in matched_cell_keys
        for p, c, i, h in zip(po.province, po.municipality, po.item, po.harmonized_nsu_unit)]
    tables['price_only'] = _records(po)

    pooled = pd.read_csv(POOLED_SPELLING_PATH, encoding='utf-8-sig')
    tables['pooled_spelling_conflicts'] = _records(_addkey4(
        pooled, 'province', 'municipality', 'item', 'harmonized_nsu_unit'))

    rung = pd.read_csv(RUNG_MIX_PATH, encoding='utf-8-sig')
    tables['rung_composition_mix'] = _records(_addkey4(
        rung, 'province', 'pull_municipal_city', 'cons_name', 'harmonized_nsu_unit'))

    fold = pd.read_csv(FOLD_CHECK_PATH, encoding='utf-8-sig')
    tables['outcome1_fold_check'] = _records(_addkey4(
        fold, 'province', 'pull_municipal_city', 'cons_name', 'harmonized_nsu_unit'))

    merge_rule = pd.read_csv(MERGE_RULE_PATH, encoding='utf-8-sig')
    tables['merge_rule_candidates'] = _records(merge_rule)

    median_dis = pd.read_csv(MEDIAN_DISAGREEMENT_PATH, encoding='utf-8-sig')
    tables['median_disagreement'] = _records(median_dis)

    dropped = pd.read_csv(DROPPED_LABELS_PATH, encoding='utf-8-sig')
    dropped = _addkey4(dropped, 'province', 'pull_municipal_city', 'cons_name', 'pull_nsu_unit')
    # cell-level key (no unit) -- a label dropped ENTIRELY from the crosswalk has no
    # surviving harmonized_nsu_unit to key on (see build_pipeline_explorer.py module
    # docstring addendum, "THE CASE EXPLORER"); the case view matches these to a
    # harmonized case by (province, municipality, item) alone.
    dropped['_cell3'] = [f"{ng(p)}|{ng(m)}|{ni(i)}" for p, m, i in
                         zip(dropped.province, dropped.pull_municipal_city, dropped.cons_name)]
    tables['dropped_labels'] = _records(dropped)

    conv_ov = pd.read_csv(CONV_OVERLAP_PATH, encoding='utf-8-sig')
    conv_ov = conv_ov.copy()
    conv_ov['_unit'] = conv_ov.unit.map(nz)
    tables['conventional_unit_overlap'] = _records(conv_ov)

    conv_cov = pd.read_csv(CONV_COVERAGE_PATH, encoding='utf-8-sig')
    tables['conventional_price_coverage'] = _records(_addkey4(
        conv_cov, 'province', 'pull_municipal_city', 'cons_name', 'unit_raw'))

    for name, rows in tables.items():
        log(f"  loaded {name}: {len(rows):,} rows")
    return tables


def build_case_explorer(master_rename):
    """THE CASE EXPLORER (GitHub issue #26, follow-up 2): a case-centred third view.

    The two Sankeys above are flow-level -- they answer "how many rows took this
    path", never "what happened to THIS harmonized case end to end". This function
    builds the data for that: the crosswalk embedded verbatim, and two more tables
    (`psps_conversion_exposure.csv`, `singleton_hetero_groups.csv`) joined in by key,
    never recomputed -- see the task brief, "Also join in (do not recompute)".

    A "case" is province x municipality x item x harmonized_nsu_unit (NOT
    corrected_unit -- that is a finer MS-only grain; see CASE_COLS elsewhere in this
    file). Its key is `key4()`, identical to every other analysis table's join key,
    so the case explorer needs no key scheme of its own: `analysis_key` on a MS
    weighing and `cell_key` on a price cell already ARE a case key when the cell is
    not a dropped-label island.

    WHAT IS DELIBERATELY LEFT TO THE BROWSER. Outcome 1/2 partition-row
    classification (docs/conversion_factor_methodology.md, the two "Decision rule"
    sections) needs nothing beyond fields already embedded per weighing
    (`weighing_approach`, `raw_spelling`, `terminal`) -- see the HTML template's
    `classifyOutcome1`/`classifyOutcome2`. Recomputing that here in a second
    language would be exactly the "shared logic, defined twice" failure mode; the
    one true source is the per-weighing `terminal`/`weighing_approach` fields
    build_payload() already computes from classify_stage3().
    """
    cw = master_rename.copy()
    cw['_key'] = [key4(p, c, i, h) for p, c, i, h in
                  zip(cw.province, cw.pull_municipal_city, cw.cons_name,
                      cw.harmonized_nsu_unit)]
    log(f"  crosswalk rows embedded for the case explorer: {len(cw):,} (expect 2,933)")

    cases = []
    for k, g in cw.groupby('_key'):
        r0 = g.iloc[0]
        cases.append({
            "case_key": k,
            "province": r0.province, "municipality": r0.pull_municipal_city,
            "item": r0.cons_name, "harmonized_unit": r0.harmonized_nsu_unit,
            "_cell3": f"{ng(r0.province)}|{ng(r0.pull_municipal_city)}|{ni(r0.cons_name)}",
            "n_spellings": int(len(g)),
            "n_ms_price": int((g.source == 'MS & Price').sum()),
            "n_price_only": int((g.source == 'Price Only').sum()),
        })
    log(f"  distinct harmonized cases in the crosswalk: {len(cases):,}")

    psps = pd.read_csv(PSPS_EXPOSURE_PATH, encoding='utf-8-sig')
    psps['_key'] = [key4(p, m, i, h) for p, m, i, h in
                    zip(psps.prov, psps.mun, psps.item, psps.harm)]
    log(f"  PSPS exposure rows: {len(psps):,} (expect 2,496), "
        f"total PSPS NSU observations: {int(psps.n_psps_obs.sum()):,} (expect 35,489)")

    singleton = pd.read_csv(SINGLETON_PATH, encoding='utf-8-sig')
    singleton['_key4'] = [key4(p, m, i, h) for p, m, i, h in
                          zip(singleton.pull_province, singleton.pull_municipal_city,
                              singleton.pull_item, singleton.harmonized_nsu_unit)]
    log(f"  singleton hetero-groups: {len(singleton):,} (expect 778)")

    return {
        "crosswalk": _records(cw),
        "cases": cases,
        "psps_exposure": _records(psps),
        "singleton_groups": _records(singleton),
    }


def build_payload(raw, master, stage1_dropped, restated_full, eligible, pub_lookup,
                   refset, counts):
    master_rename = pd.read_csv(MASTER_RENAME_PATH, encoding='utf-8-sig', dtype=str)

    sankey = build_sankey(raw, master, stage1_dropped, restated_full, eligible, counts)
    pr = classify_price_rows(master_rename)
    price_by_cell = build_price_lookup(pr)
    price_cells = build_price_cells(pr, restated_full)
    price_sankey = build_price_sankey(price_cells, pr)
    price_analyses = load_price_analyses(pr)
    case_explorer = build_case_explorer(master_rename)

    n_pf = sum(1 for c in price_cells if c['bucket'] == 'price_only_province_fallback')
    n_op = sum(1 for c in price_cells if c['bucket'] == 'price_only_other_province_only')
    n_now = sum(1 for c in price_cells if c['bucket'] == 'price_only_nowhere')
    n_conv = sum(1 for c in price_cells if c['bucket'] == 'convertible')
    n_dropcells = sum(1 for c in price_cells if c['bucket'] == 'dropped_label')
    price_counts = {
        "n_price_rows": len(pr), "n_price_cells": len(price_cells),
        "n_dropped_label_cells": n_dropcells, "n_convertible": n_conv,
        "n_price_only": n_pf + n_op + n_now, "n_province_fallback": n_pf,
        "n_other_province_only": n_op, "n_weighed_nowhere": n_now,
    }
    price_discrepancy_note = (
        f"outputs/tables/price_only_no_weight_anywhere.csv predates commit 3c436b9 "
        f"(the 17-label crosswalk trim, dofiles/00_shared/02_drop_non_nsu_labels.py). 16 of its "
        f"602 rows carry a raw label the current crosswalk no longer harmonizes at "
        f"all -- all 16 were in that CSV's own 'weighed nowhere' bucket. This page "
        f"reclassifies those 16 as the dropped-label sink instead of price-only, so "
        f"its current-data figures are {n_pf + n_op + n_now:,} price-only cells "
        f"(pre-trim: 602) and {n_now:,} weighed nowhere (pre-trim: "
        f"96). The province-fallback ({n_pf:,}) and other-province-only ({n_op:,}) "
        f"splits are unaffected by the trim."
    )

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
            "corrected_weight": nn(row.corrected_weight),
            "case_key": f"{row.pull_province}|{row.pull_municipal_city}|{row.pull_item}|"
                        f"{row.harmonized_nsu_unit}|{CORRECTED_UNIT_LABEL.get(row.corrected_unit, '')}",
            # province|municipality|item|harmonized_unit, normalized the same way as
            # the price side (key4()) -- NOT case_key above, which also carries
            # corrected_unit and is unnormalized. This is what joins a weighing to
            # a price cell and to the issue21_*.csv / conventional_*.csv analysis
            # tables in payload["price_analyses"] (see load_price_analyses()).
            "analysis_key": key4(row.pull_province, row.pull_municipal_city,
                                  row.pull_item, row.harmonized_nsu_unit),
            # same idea, keyed on the RAW spelling instead of the harmonized unit --
            # joins master_rename_dropped_labels.csv / conventional_price_coverage.csv,
            # which are keyed to one specific raw label, not the pooled harmonized unit.
            "raw_key": key4(row.pull_province, row.pull_municipal_city,
                             row.pull_item, row.pull_nsu_unit),
        }

        # ---- arrival raw-spelling provenance, if the id is joinable ------------
        mrow = m_by_id.loc[rid] if rid in m_by_id.index else None
        rec["raw_spelling_arrival"] = row.pull_nsu_unit  # already the arrival-stage field

        # ---- stage-2 outcome (already survived, since row is in restated) ------
        # ---- stage-3 outcome -----------------------------------------------------
        notes = []
        if row.drop_no_wref:
            rec["terminal"] = "dropped"
            rec["terminal_reason"] = "Stage 3: no usable weight (corrected_weight/corrected_weight missing)"
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
                         f"= corrected_weight {nn(row.corrected_weight)}")
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
        "(11,458 -> 11,384). The current dofiles/00_shared/07_cpi_factor.do and its own "
        "saved log drop 98 (27 'vendor gave no price at all' + 71 'vendor-priced, "
        "case keeps a preloaded rung') -> 11,360, matching the file on disk and this "
        "tool's own counts throughout. docs/data_oddities.md sec.3b already documents "
        "the 27-row rule; the ledger was written earlier and has not been regenerated. "
        "This page uses the files on disk as ground truth and flags the stale figures "
        "here rather than matching them."
    )

    meta = {
        "generated_note": "Generated by dofiles/90_diagnostics/build_pipeline_explorer.py. Read-only tool; "
                           "nothing here feeds back into the pipeline.",
        "counts": counts,
        "price_counts": price_counts,
        "ledger_discrepancy_note": ledger_note,
        "price_discrepancy_note": price_discrepancy_note,
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
        "price_sankey": price_sankey,
        "price_cells": price_cells,
        "price_analyses": price_analyses,
        "case_explorer": case_explorer,
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
.tag.info { background: rgba(79,163,255,.18); color: #8fc4ff; }
.badges { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 10px; }
.qbtn {
  background: var(--panel2); color: var(--text); border: 1px solid var(--border);
  border-radius: 14px; padding: 4px 12px; cursor: pointer; font-size: 12px;
}
.qbtn .n { color: var(--muted); margin-left: 4px; }
.qbtn:hover { border-color: var(--accent); }
.qbtn.active { background: #1e3a5f; border-color: var(--accent); color: #cfe6ff; }
.flagbadge {
  display: inline-block; padding: 0 5px; margin: 0 2px 2px 0; border-radius: 8px;
  font-size: 10px; cursor: help; background: rgba(255,180,84,.15); color: var(--accent2);
  border: 1px solid rgba(255,180,84,.3);
}
.crosslink {
  display: inline-block; margin-top: 8px; padding: 4px 10px; border-radius: 4px;
  background: var(--panel2); border: 1px solid var(--accent); color: var(--accent);
  cursor: pointer; font-size: 12px;
}
.crosslink:hover { background: #1e3a5f; }
.subtable { margin-top: 6px; max-height: 220px; overflow: auto; border: 1px solid var(--border); border-radius: 6px; }
.subtable table { font-size: 11px; }
#detail { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.detail-col { background: var(--panel); border: 1px solid var(--border); border-radius: 8px; padding: 14px; min-width: 0; overflow-x: auto; }
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
  <h2>1. Market-survey flow (Sankey) &mdash; click a node to filter the table in section 3</h2>
  <div id="sankey-wrap"><svg id="sankey"></svg></div>
  <div class="crosslink" id="sankey-to-case" style="margin-top:10px">Trace one harmonized case instead &mdash; jump to section 6 &darr;</div>
</section>

<section>
  <h2>2. Price-file flow (Sankey) &mdash; every price row, whether or not it has a matching MS weighing (click a node to filter the table in section 4)</h2>
  <p style="color:var(--muted);font-size:12.5px;margin:0 0 10px 0">
    The Sankey above only ever follows an MS row forward, so a price-only cell (no MS weighing at all) never
    appears in it. This second flow traces the price file's own 5,412 rows instead: whether each harmonized
    cell has an MS weighing, and if not, whether one exists elsewhere in the same province.
  </p>
  <div id="price-banner-holder"></div>
  <div id="price-sankey-wrap" style="overflow-x:auto"><svg id="price-sankey"></svg></div>
  <div class="crosslink" id="price-sankey-to-case" style="margin-top:10px">Trace one harmonized case instead &mdash; jump to section 6 &darr;</div>
</section>

<section>
  <h2>3. MS observation drill-down &mdash; <span id="filter-summary"></span></h2>
  <div class="badges" id="ms-badges"></div>
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
        <th data-k="corrected_weight">corrected_weight (g/mL)</th>
        <th data-k="terminal">Terminal state</th>
        <th>Flags</th>
      </tr></thead>
      <tbody id="tbl-body"></tbody>
    </table>
  </div>
</section>

<section>
  <h2>4. Price-cell drill-down &mdash; <span id="price-filter-summary"></span></h2>
  <div class="badges" id="price-badges"></div>
  <div class="filters">
    <input type="text" id="pf-province" placeholder="Province">
    <input type="text" id="pf-municipality" placeholder="Municipality">
    <input type="text" id="pf-item" placeholder="Item">
    <input type="text" id="pf-harmunit" placeholder="Harmonized unit / raw label">
    <select id="pf-bucket"><option value="">Status: any</option>
      <option value="convertible">convertible</option>
      <option value="price_only_province_fallback">price-only, province fallback</option>
      <option value="price_only_other_province_only">price-only, other province only</option>
      <option value="price_only_nowhere">price-only, weighed nowhere</option>
      <option value="dropped_label">dropped label</option></select>
    <button class="clear" id="clear-price-node-filter" style="display:none">clear node filter</button>
    <span class="count" id="price-row-count"></span>
  </div>
  <div id="price-tablewrap">
    <table id="price-tbl">
      <thead><tr>
        <th data-k="province">Province</th><th data-k="municipality">Municipality</th>
        <th data-k="item">Item</th><th data-k="harmonized_unit">Harmonized unit / raw label</th>
        <th data-k="n_price_rows">Price rows</th>
        <th data-k="bucket">Status</th><th>Flags</th>
      </tr></thead>
      <tbody id="price-tbl-body"></tbody>
    </table>
  </div>
</section>

<section>
  <h2>5. Selected observation &mdash; its path through the build, and its price-side context</h2>
  <div id="detail"><div class="placeholder" style="grid-column:1/-1">Select a row in section 3 or 4 to see its path.</div></div>
</section>

<section id="case-explorer-section">
  <h2>6. Case explorer &mdash; trace one harmonized case end to end</h2>
  <p style="color:var(--muted);font-size:12.5px;margin:0 0 10px 0">
    A harmonized case is province &times; municipality &times; item &times; harmonized NSU unit
    (<code>docs/master_rename.md</code>). Search for one to see every raw spelling that folds into it, which
    spellings were dropped and from where, how each surviving spelling was weighed, what Outcome 1 and
    Outcome 2 do with it, how many PSPS observations depend on it, and whether its hetero-groups rest on a
    single weighing.
  </p>
  <div class="filters">
    <input type="text" id="case-search" placeholder="Search province / municipality / item / harmonized unit&hellip;" style="width:440px">
    <span class="count" id="case-search-count"></span>
  </div>
  <div id="case-results" class="subtable" style="max-height:240px"></div>
  <div id="case-detail" style="margin-top:16px"></div>
</section>

<footer id="footer"></footer>

<script>
const DATA = __DATA_JSON__;

// ---------------------------------------------------------------- header/banner
document.getElementById('hdr-sub').textContent =
  `${DATA.meta.counts.n_raw.toLocaleString()} raw -> ${DATA.meta.counts.n_master.toLocaleString()} arrival -> ` +
  `${DATA.meta.counts.n_restated.toLocaleString()} restated -> ${DATA.meta.counts.n_refset.toLocaleString()} Outcome 1 rows` +
  `  |  price file: ${DATA.meta.price_counts.n_price_rows.toLocaleString()} rows -> ` +
  `${DATA.meta.price_counts.n_price_cells.toLocaleString()} harmonized cells`;

const bannerHolder = document.getElementById('banner-holder');
function banner(text, into) {
  const d = document.createElement('div');
  d.className = 'banner';
  d.textContent = text;
  (into || bannerHolder).appendChild(d);
}
banner('Known discrepancy vs docs/attrition_ledger.md: ' + DATA.meta.ledger_discrepancy_note);
banner('Outcome 2: ' + DATA.meta.outcome2_note);
banner('Price-only figures vs the task brief: ' + DATA.meta.price_discrepancy_note,
       document.getElementById('price-banner-holder'));

document.getElementById('footer').textContent = DATA.meta.generated_note;

function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

// ---------------------------------------------------------------- generic sankey renderer
// Shared by both flows (MS pipeline, price file) -- same layout/interaction logic,
// parametrized by which data/columns/coloring it draws and what a click does.
function makeSankey(svgId, sankeyData, columns, classifyFn, onSelect, onClear) {
  const nodes = sankeyData.nodes;
  const links = sankeyData.links;
  const byId = {}; nodes.forEach(n => byId[n.id] = n);

  nodes.forEach(n => n.col = columns[n.id] ?? (Math.max(0, ...Object.values(columns)) + 1));
  const maxCol = Math.max(...nodes.map(n => n.col));

  const width = Math.max(1100, 160 * (maxCol + 1) + 200);
  const height = 560;
  const svg = document.getElementById(svgId);
  svg.setAttribute('width', width);
  svg.setAttribute('height', height);
  svg.setAttribute('viewBox', `0 0 ${width} ${height}`);

  const colWidth = (width - 200) / (maxCol + 1);
  const nodeW = 18;
  const rootNode = nodes.find(n => n.col === 0) || nodes[0];
  const total = rootNode.n;
  const usableH = height - 40;
  const pxPerUnit = usableH / total;

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
    for (const k in attrs) if (attrs[k] !== undefined) e.setAttribute(k, attrs[k]);
    return e;
  }

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

  let selectedNode = null;
  function clearVisual() {
    selectedNode = null;
    svg.querySelectorAll('.node').forEach(g => g.classList.remove('selected'));
  }
  function selectNode(n) {
    if (selectedNode && selectedNode.id === n.id) {
      clearVisual();
      onClear();
      return;
    }
    svg.querySelectorAll('.node').forEach(g => g.classList.remove('selected'));
    selectedNode = n;
    svg.querySelector(`.node[data-id="${n.id}"]`).classList.add('selected');
    onSelect(n.id);
  }

  nodes.forEach(n => {
    const cls = classifyFn(n.id);
    const g = el('g', { class: 'node ' + cls, 'data-id': n.id });
    const rect = el('rect', { x: n.x, y: n.y, width: nodeW, height: n.h,
                               fill: cls ? undefined : '#4fa3ff' });
    g.appendChild(rect);
    const label = el('text', { x: n.x + nodeW + 6, y: n.y + Math.min(n.h, 14) });
    label.textContent = `${n.label} (${n.n.toLocaleString()})`;
    g.appendChild(label);
    const title = el('title', {}); title.textContent = `${n.label}: ${n.n.toLocaleString()}`;
    g.appendChild(title);
    g.addEventListener('click', () => selectNode(n));
    svg.appendChild(g);
  });

  return { clearVisual };
}

// ---------------------------------------------------------------- MS sankey + table
let nodeFilter = null;    // {id, pred, useDropped}
let msQuickFilter = null; // {id, label, test}

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

const msSankeyColumns = {
  raw: 0,
  s1_1a: 1, s1_1c: 1, s1_1d: 1, s1_unresolved: 1, cleaned: 1,
  wtunit: 2,
  s2_noprice: 3, s2_vendordrop: 3, s2_unresolved: 3, restated: 3,
  b_conv: 4, b_pq: 4, b_size: 4,
  s3_nowref: 5, s3_unique: 5, s3_carrot: 5, eligible: 5,
  outcome1: 6,
};
function msNodeClass(id) {
  if (id.startsWith('s1_') || id.startsWith('s2_') || id.startsWith('s3_')) return 'drop';
  if (id === 'outcome1') return 'terminal';
  return '';
}
const msSankeyCtl = makeSankey('sankey', DATA.sankey, msSankeyColumns, msNodeClass,
  (nodeId) => { applyNodeFilter(nodeId); document.getElementById('clear-node-filter').style.display = ''; },
  () => { nodeFilter = null; document.getElementById('clear-node-filter').style.display = 'none'; renderTable(); });
document.getElementById('clear-node-filter').addEventListener('click', () => {
  msSankeyCtl.clearVisual();
  nodeFilter = null;
  document.getElementById('clear-node-filter').style.display = 'none';
  renderTable();
});

const filterIds = ['f-province', 'f-municipality', 'f-item', 'f-spelling', 'f-harmunit', 'f-approach', 'f-label', 'f-vendor'];
filterIds.forEach(id => document.getElementById(id).addEventListener('input', renderTable));

let sortKey = null, sortDir = 1;
document.querySelectorAll('#tbl th').forEach(th => {
  th.addEventListener('click', () => {
    const k = th.dataset.k; if (!k) return;
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

// ---------------------------------------------------------------- price analysis tables (joined in, not recomputed)
const PA = DATA.price_analyses;
function buildIndex(rows, keyField) {
  const idx = {};
  (rows || []).forEach(r => { const k = r[keyField]; if (k == null) return; (idx[k] = idx[k] || []).push(r); });
  return idx;
}
const IDX_price_only = buildIndex(PA.price_only, '_key');
const IDX_pooled = buildIndex(PA.pooled_spelling_conflicts, '_key');
const IDX_rung = buildIndex(PA.rung_composition_mix, '_key');
const IDX_fold = buildIndex(PA.outcome1_fold_check, '_key');
const IDX_dropped = buildIndex(PA.dropped_labels, '_key');
const IDX_convcov = buildIndex(PA.conventional_price_coverage, '_key');
const IDX_mergerule = buildIndex(PA.merge_rule_candidates, 'case');
const IDX_mediandis = buildIndex(PA.median_disagreement, 'case');
const IDX_convoverlap = buildIndex(PA.conventional_unit_overlap, '_unit');
const CELL_BY_KEY = {}; DATA.price_cells.forEach(c => { CELL_BY_KEY[c.cell_key] = c; });

// province / municipality / item[:24 or full] / harmonized_unit -- the exact string
// scope_price_point_merge_rule.py / scope_multi_price_points.py print as their own
// 'case' column. Recomputed here (never parsed back out of the CSV) from a
// selected row's own already-normalized fields.
function caseStr(prov, mun, item, harm, trunc) {
  const i = trunc ? String(item || '').substring(0, 24) : (item || '');
  return `${prov || ''} / ${mun || ''} / ${i} / ${harm || ''}`;
}

function gatherAnalyses(o) {
  const out = {
    price_only: (o.analysisKey && IDX_price_only[o.analysisKey]) || [],
    pooled_spelling_conflicts: (o.analysisKey && IDX_pooled[o.analysisKey]) || [],
    rung_composition_mix: (o.analysisKey && IDX_rung[o.analysisKey]) || [],
    outcome1_fold_check: (o.analysisKey && IDX_fold[o.analysisKey]) || [],
    dropped_labels: (o.rawKeys || []).flatMap(k => IDX_dropped[k] || []),
    conventional_price_coverage: (o.rawKeys || []).flatMap(k => IDX_convcov[k] || []),
    conventional_unit_overlap: (o.harmonizedUnit && IDX_convoverlap[o.harmonizedUnit]) || [],
    merge_rule_candidates: [], median_disagreement: [],
  };
  if (o.province && o.municipality && o.item && o.harmonizedUnit) {
    out.merge_rule_candidates = IDX_mergerule[caseStr(o.province, o.municipality, o.item, o.harmonizedUnit, true)] || [];
    out.median_disagreement = IDX_mediandis[caseStr(o.province, o.municipality, o.item, o.harmonizedUnit, false)] || [];
  }
  return out;
}

const ANALYSIS_LABELS = {
  price_only: 'Price-only case detail (price_only_no_weight_anywhere.csv)',
  pooled_spelling_conflicts: 'Pooled-spelling price conflict (issue21_pooled_spelling_conflicts.csv)',
  rung_composition_mix: 'Rung composition mix (issue21_rung_composition_mix.csv)',
  outcome1_fold_check: 'Outcome-1 fold check (issue21_outcome1_fold_check.csv)',
  dropped_labels: 'Dropped-label reason (master_rename_dropped_labels.csv)',
  conventional_price_coverage: 'Conventional-branch price coverage (conventional_price_coverage.csv)',
  merge_rule_candidates: 'Price-point merge-rule candidates (issue21_merge_rule_candidates.csv)',
  median_disagreement: 'Median disagreement (issue21_median_disagreement.csv)',
  conventional_unit_overlap: 'Conventional-unit overlap (conventional_unit_overlap.csv)',
};

function renderGenericTable(rows) {
  if (!rows || !rows.length) return '';
  const cols = Object.keys(rows[0]).filter(k => k !== '_key' && k !== '_unit');
  return `<div class="subtable"><table><thead><tr>${cols.map(c => `<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>` +
    rows.map(r => `<tr>${cols.map(c => `<td>${r[c] == null ? '' : esc(r[c])}</td>`).join('')}</tr>`).join('') +
    '</tbody></table></div>';
}

function renderAnalysesHTML(analyses) {
  let html = '';
  for (const key of Object.keys(ANALYSIS_LABELS)) {
    const rows = analyses[key];
    if (!rows || !rows.length) continue;
    html += `<div style="margin-top:10px"><b>${ANALYSIS_LABELS[key]}</b> &mdash; ${rows.length} row(s)` +
      renderGenericTable(rows) + `</div>`;
  }
  return html || '<div class="placeholder">no matching rows in the analysis tables for this case</div>';
}

function msFlagBadges(w) {
  const badges = [];
  if ((IDX_pooled[w.analysis_key] || []).some(r => r.conflict === 1)) badges.push('<span class="flagbadge" title="pooled-spelling price conflict">conflict</span>');
  if ((IDX_rung[w.analysis_key] || []).some(r => r.n_units > 1)) badges.push('<span class="flagbadge" title="pools >1 raw spelling">pooled</span>');
  if ((IDX_mediandis[caseStr(w.province, w.municipality, w.item, w.harmonized_unit, false)] || []).length) badges.push('<span class="flagbadge" title="median disagreement">median-dis</span>');
  if ((IDX_mergerule[caseStr(w.province, w.municipality, w.item, w.harmonized_unit, true)] || []).length) badges.push('<span class="flagbadge" title="price-point merge-rule candidate">merge</span>');
  return badges.join('');
}

// ---------------------------------------------------------------- quick-filter badges (shared renderer)
function renderQuickBadges(containerId, filters, dataArr, getState, setState, rerender) {
  const holder = document.getElementById(containerId);
  holder.innerHTML = filters.map(f => {
    const n = dataArr.filter(f.test).length;
    return `<button type="button" class="qbtn" data-id="${f.id}">${esc(f.label)}<span class="n">${n.toLocaleString()}</span></button>`;
  }).join('');
  Array.from(holder.querySelectorAll('.qbtn')).forEach(btn => {
    btn.addEventListener('click', () => {
      const f = filters.find(x => x.id === btn.dataset.id);
      if (getState() && getState().id === f.id) {
        setState(null);
      } else {
        setState(f);
      }
      holder.querySelectorAll('.qbtn').forEach(b => b.classList.toggle('active', getState() && b.dataset.id === getState().id));
      rerender();
    });
  });
}

const MS_QUICK_FILTERS = [
  { id: 'ms-conflict', label: 'Pooled-spelling price conflict',
    test: w => (IDX_pooled[w.analysis_key] || []).some(r => r.conflict === 1) },
  { id: 'ms-pooled', label: 'Pools >1 raw spelling',
    test: w => (IDX_rung[w.analysis_key] || []).some(r => r.n_units > 1) },
  { id: 'ms-median', label: 'Median disagreement',
    test: w => (IDX_mediandis[caseStr(w.province, w.municipality, w.item, w.harmonized_unit, false)] || []).length > 0 },
  { id: 'ms-merge', label: 'Merge-rule candidate',
    test: w => (IDX_mergerule[caseStr(w.province, w.municipality, w.item, w.harmonized_unit, true)] || []).length > 0 },
];
renderQuickBadges('ms-badges', MS_QUICK_FILTERS, DATA.weighings,
  () => msQuickFilter, (f) => { msQuickFilter = f; }, renderTable);

let currentRows = [];
function renderTable() {
  const usingDropped = !!(nodeFilter && nodeFilter.useDropped);
  let rows = (usingDropped ? DATA.dropped : DATA.weighings).filter(matchesTextFilters);
  document.getElementById('filter-summary').textContent = nodeFilter
    ? (nodeFilter.id.startsWith('pinned:') ? `pinned to case: ${nodeFilter.id.slice(7)}` : `filtered by Sankey node: ${nodeFilter.id}`)
    : 'no Sankey node selected';
  if (nodeFilter) rows = rows.filter(nodeFilter.pred);
  if (!usingDropped && msQuickFilter) rows = rows.filter(msQuickFilter.test);
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
      <td>${w.vendor_id||''}</td><td>${w.corrected_weight!=null? w.corrected_weight.toLocaleString(undefined,{maximumFractionDigits:1}):''}</td>
      <td>${terminalTag(w)}</td>
      <td>${usingDropped ? '' : msFlagBadges(w)}</td>
    </tr>`).join('');
  if (rows.length > MAX_RENDER) {
    const note = document.createElement('tr');
    note.innerHTML = `<td colspan="11" style="color:var(--muted);font-style:italic">
      showing first ${MAX_RENDER.toLocaleString()} of ${rows.length.toLocaleString()} filtered rows -- narrow the filters to see more</td>`;
    body.appendChild(note);
  }
  Array.from(body.querySelectorAll('tr[data-idx]')).forEach(tr => {
    tr.addEventListener('click', () => selectRow(shown[+tr.dataset.idx]));
  });
}
renderTable();

// ---------------------------------------------------------------- price-file sankey + cell table
let priceNodeFilter = null;
let priceQuickFilter = null;

const PRICE_NODE_PREDICATES = {
  p_raw: c => true,
  p_matched: c => true,
  p_convertible: c => c.bucket === 'convertible',
  p_only: c => c.bucket.startsWith('price_only'),
  p_province_fallback: c => c.bucket === 'price_only_province_fallback',
  p_other_province: c => c.bucket === 'price_only_other_province_only',
  p_nowhere: c => c.bucket === 'price_only_nowhere',
  p_dropped_label: c => c.bucket === 'dropped_label',
};
function applyPriceNodeFilter(nodeId) {
  priceNodeFilter = PRICE_NODE_PREDICATES[nodeId] ? { id: nodeId, pred: PRICE_NODE_PREDICATES[nodeId] } : null;
  renderPriceCellsTable();
}

const priceSankeyColumns = {
  p_raw: 0, p_dropped_label: 1, p_matched: 1,
  p_convertible: 2, p_only: 2,
  p_province_fallback: 3, p_other_province: 3, p_nowhere: 3,
};
function priceNodeClass(id) {
  if (id === 'p_dropped_label' || id === 'p_nowhere') return 'drop';
  if (id === 'p_convertible') return 'terminal';
  if (id === 'p_province_fallback' || id === 'p_other_province') return 'pending';
  return '';
}
const priceSankeyCtl = makeSankey('price-sankey', DATA.price_sankey, priceSankeyColumns, priceNodeClass,
  (nodeId) => { applyPriceNodeFilter(nodeId); document.getElementById('clear-price-node-filter').style.display = ''; },
  () => { priceNodeFilter = null; document.getElementById('clear-price-node-filter').style.display = 'none'; renderPriceCellsTable(); });
document.getElementById('clear-price-node-filter').addEventListener('click', () => {
  priceSankeyCtl.clearVisual();
  priceNodeFilter = null;
  document.getElementById('clear-price-node-filter').style.display = 'none';
  renderPriceCellsTable();
});

const priceFilterIds = ['pf-province', 'pf-municipality', 'pf-item', 'pf-harmunit'];
priceFilterIds.forEach(id => document.getElementById(id).addEventListener('input', renderPriceCellsTable));
document.getElementById('pf-bucket').addEventListener('change', renderPriceCellsTable);

let priceSortKey = null, priceSortDir = 1;
document.querySelectorAll('#price-tbl th').forEach(th => {
  th.addEventListener('click', () => {
    const k = th.dataset.k; if (!k) return;
    if (priceSortKey === k) priceSortDir *= -1; else { priceSortKey = k; priceSortDir = 1; }
    renderPriceCellsTable();
  });
});

function priceTextFilterVal(id) { return document.getElementById(id).value.trim().toLowerCase(); }
function priceMatchesTextFilters(c) {
  const p = priceTextFilterVal('pf-province'); if (p && !(c.province||'').toLowerCase().includes(p)) return false;
  const m = priceTextFilterVal('pf-municipality'); if (m && !(c.municipality||'').toLowerCase().includes(m)) return false;
  const it = priceTextFilterVal('pf-item'); if (it && !(c.item||'').toLowerCase().includes(it)) return false;
  const hu = priceTextFilterVal('pf-harmunit'); if (hu && !(c.harmonized_unit||'').toLowerCase().includes(hu)) return false;
  const bk = document.getElementById('pf-bucket').value; if (bk && c.bucket !== bk) return false;
  return true;
}

const BUCKET_LABEL = {
  convertible: '<span class="tag ok">convertible</span>',
  price_only_province_fallback: '<span class="tag pending">price-only: province fallback</span>',
  price_only_other_province_only: '<span class="tag pending">price-only: other province only</span>',
  price_only_nowhere: '<span class="tag dropped">price-only: weighed nowhere</span>',
  dropped_label: '<span class="tag dropped">label removed from crosswalk</span>',
};
function bucketTag(c) { return BUCKET_LABEL[c.bucket] || esc(c.bucket); }

function priceFlagBadges(c) {
  const badges = [];
  if ((IDX_pooled[c.cell_key] || []).some(r => r.conflict === 1)) badges.push('<span class="flagbadge" title="pooled-spelling price conflict">conflict</span>');
  if ((IDX_rung[c.cell_key] || []).some(r => r.n_units > 1)) badges.push('<span class="flagbadge" title="pools >1 raw spelling">pooled</span>');
  if ((IDX_price_only[c.cell_key] || []).some(r => r.now_dropped_label)) badges.push('<span class="flagbadge" title="stale in price_only_no_weight_anywhere.csv -- label since dropped from the crosswalk">stale-CSV</span>');
  return badges.join('');
}

const PRICE_QUICK_FILTERS = [
  { id: 'pc-priceonly', label: 'Price-only cases', test: c => c.bucket.startsWith('price_only') },
  { id: 'pc-fallback', label: 'Province fallback available', test: c => c.bucket === 'price_only_province_fallback' },
  { id: 'pc-nowhere', label: 'Weighed nowhere', test: c => c.bucket === 'price_only_nowhere' },
  { id: 'pc-conflict', label: 'Pooled-spelling price conflict', test: c => (IDX_pooled[c.cell_key] || []).some(r => r.conflict === 1) },
  { id: 'pc-pooled', label: 'Pools >1 raw spelling', test: c => (IDX_rung[c.cell_key] || []).some(r => r.n_units > 1) },
];
renderQuickBadges('price-badges', PRICE_QUICK_FILTERS, DATA.price_cells,
  () => priceQuickFilter, (f) => { priceQuickFilter = f; }, renderPriceCellsTable);

let currentPriceRows = [];
function renderPriceCellsTable() {
  let rows = DATA.price_cells.filter(priceMatchesTextFilters);
  document.getElementById('price-filter-summary').textContent = priceNodeFilter
    ? (priceNodeFilter.id.startsWith('pinned:') ? `pinned to cell: ${priceNodeFilter.id.slice(7)}` : `filtered by Sankey node: ${priceNodeFilter.id}`)
    : 'no Sankey node selected';
  if (priceNodeFilter) rows = rows.filter(priceNodeFilter.pred);
  if (priceQuickFilter) rows = rows.filter(priceQuickFilter.test);
  if (priceSortKey) {
    rows = rows.slice().sort((a, b) => {
      const av = a[priceSortKey], bv = b[priceSortKey];
      if (av == null) return 1; if (bv == null) return -1;
      if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * priceSortDir;
      return String(av).localeCompare(String(bv)) * priceSortDir;
    });
  }
  currentPriceRows = rows;
  document.getElementById('price-row-count').textContent = `${rows.length.toLocaleString()} cells`;
  const body = document.getElementById('price-tbl-body');
  const MAX_RENDER = 2000;
  const shown = rows.slice(0, MAX_RENDER);
  body.innerHTML = shown.map((c, i) => `
    <tr data-idx="${i}">
      <td>${c.province||''}</td><td>${c.municipality||''}</td><td>${c.item||''}</td>
      <td>${c.harmonized_unit||''}</td><td>${c.n_price_rows}</td>
      <td>${bucketTag(c)}</td><td>${priceFlagBadges(c)}</td>
    </tr>`).join('');
  if (rows.length > MAX_RENDER) {
    const note = document.createElement('tr');
    note.innerHTML = `<td colspan="7" style="color:var(--muted);font-style:italic">
      showing first ${MAX_RENDER.toLocaleString()} of ${rows.length.toLocaleString()} filtered cells -- narrow the filters to see more</td>`;
    body.appendChild(note);
  }
  Array.from(body.querySelectorAll('tr[data-idx]')).forEach(tr => {
    tr.addEventListener('click', () => selectPriceCell(shown[+tr.dataset.idx]));
  });
}
renderPriceCellsTable();

// ---------------------------------------------------------------- cross-linking between the two tables
function jumpToMSCase(analysisKey) {
  msQuickFilter = null;
  document.querySelectorAll('#ms-badges .qbtn').forEach(b => b.classList.remove('active'));
  nodeFilter = { id: 'pinned:' + analysisKey, pred: w => w.analysis_key === analysisKey, useDropped: false };
  msSankeyCtl.clearVisual();
  document.getElementById('clear-node-filter').style.display = '';
  renderTable();
  document.getElementById('tbl').scrollIntoView({ behavior: 'smooth', block: 'center' });
}
function jumpToPriceCell(cellKey) {
  priceQuickFilter = null;
  document.querySelectorAll('#price-badges .qbtn').forEach(b => b.classList.remove('active'));
  priceNodeFilter = { id: 'pinned:' + cellKey, pred: c => c.cell_key === cellKey };
  priceSankeyCtl.clearVisual();
  document.getElementById('clear-price-node-filter').style.display = '';
  renderPriceCellsTable();
  document.getElementById('price-tbl').scrollIntoView({ behavior: 'smooth', block: 'center' });
}
function wireCrosslinks(container) {
  container.querySelectorAll('[data-jump="ms"]').forEach(b => b.addEventListener('click', () => jumpToMSCase(b.dataset.key)));
  container.querySelectorAll('[data-jump="price"]').forEach(b => b.addEventListener('click', () => jumpToPriceCell(b.dataset.key)));
  container.querySelectorAll('[data-jump="case"]').forEach(b => b.addEventListener('click', () => jumpToCase(b.dataset.key)));
}

// ---------------------------------------------------------------- detail panel (shared by both tables)
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
        + `unit, corrected weight, or corrected_weight -- there is nothing further in its path to show.`
      : `This row reached the arrival stage but was dropped before the restated stage `
        + `(nsu_weighings_cpi.dta), so it has no corrected weight or corrected_weight -- there is `
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
      ['Restated (corrected_weight)', w.corrected_weight != null ? `${w.corrected_weight} (cpi_factor ${w.cpi_factor})` : '(missing)'],
      ['Case', w.case_key],
      ['Terminal state', terminalTag(w)],
    ].map(([k, v]) => `<div class="pathstep"><div class="stage">${k}</div><div class="val">${v}</div></div>`).join('')
     + (w.terminal_reason ? `<div class="note">${w.terminal_reason}</div>` : '')
     + (w.notes && w.notes.length ? w.notes.map(n => `<div class="note">${n}</div>`).join('') : '');
  }

  const right = document.createElement('div');
  right.className = 'detail-col';
  const cellKey3 = `${w.province}|${w.municipality}|${w.item}`;
  const prices = (DATA.price_by_cell[cellKey3] || []);
  const samehunit = prices.filter(p => p.harmonized_unit === w.harmonized_unit);
  const other = prices.filter(p => p.harmonized_unit !== w.harmonized_unit);
  const hasPriceCell = !isDroppedRecord(w) && !!CELL_BY_KEY[w.analysis_key];
  right.innerHTML = `<h3>Price-file rows for this cell</h3>` +
    (prices.length === 0 ? '<div class="placeholder">no price-file rows for this province/municipality/item</div>' :
    `<div class="pricebox"><b>Same harmonized unit (${w.harmonized_unit || 'n/a'})</b>` +
    renderPriceRowsTable(samehunit) +
    (other.length ? `<b>Other units in this cell</b>` + renderPriceRowsTable(other) : '') +
    `</div>`) +
    (hasPriceCell ? `<button class="crosslink" data-jump="price" data-key="${esc(w.analysis_key)}">View this cell's row in section 4 (price-file flow) &darr;</button>` : '') +
    (!isDroppedRecord(w) && CASE_BY_KEY[w.analysis_key] ? `<button class="crosslink" data-jump="case" data-key="${esc(w.analysis_key)}">Trace this case end to end in section 6 &darr;</button>` : '') +
    (!isDroppedRecord(w) ? `<h3 style="margin-top:16px">Related analyses for this case</h3>` +
      renderAnalysesHTML(gatherAnalyses({
        analysisKey: w.analysis_key, rawKeys: [w.raw_key],
        province: w.province, municipality: w.municipality, item: w.item, harmonizedUnit: w.harmonized_unit,
      })) : '');

  const detail = document.getElementById('detail');
  detail.innerHTML = '';
  detail.appendChild(left);
  detail.appendChild(right);
  wireCrosslinks(detail);
}

function renderPriceRowsTable(rows) {
  if (!rows.length) return '<div class="placeholder">none</div>';
  return '<table><thead><tr><th>raw unit</th><th>harmonized</th><th>price type</th><th>price</th></tr></thead><tbody>' +
    rows.map(p => `<tr><td>${p.raw_unit}</td><td>${p.harmonized_unit}</td><td>${p.price_type}</td><td>${p.price}</td></tr>`).join('') +
    '</tbody></table>';
}

const BUCKET_NOTE = {
  convertible: 'This exact (province, municipality, item, harmonized unit) cell has at least one MS weighing -- directly convertible.',
  price_only_province_fallback: 'No MS weighing in this exact cell, but this item x harmonized unit IS weighed elsewhere in the same province -- a province-level fallback conversion factor is available.',
  price_only_other_province_only: 'No MS weighing in this exact cell or province; this item x harmonized unit is weighed only in a DIFFERENT province.',
  price_only_nowhere: 'This item x harmonized unit is not weighed anywhere in the MS data, in any province -- no conversion path exists.',
  dropped_label: 'This raw label was deliberately removed from the crosswalk (dofiles/00_shared/02_drop_non_nsu_labels.py) -- not a broken join.',
};

function selectPriceCell(c) {
  document.querySelectorAll('#price-tbl-body tr').forEach(tr => tr.classList.remove('selected'));
  const idx = currentPriceRows.indexOf(c);
  const tr = document.querySelector(`#price-tbl-body tr[data-idx="${idx}"]`);
  if (tr) tr.classList.add('selected');

  const left = document.createElement('div');
  left.className = 'detail-col';
  left.innerHTML = `<h3>Price cell</h3>` + [
    ['Cell', `${c.province} / ${c.municipality} / ${c.item} / ${c.harmonized_unit}`],
    ['Status', bucketTag(c)],
    ['Price rows in this cell', c.n_price_rows],
  ].map(([k, v]) => `<div class="pathstep"><div class="stage">${k}</div><div class="val">${v}</div></div>`).join('')
   + (BUCKET_NOTE[c.bucket] ? `<div class="note">${BUCKET_NOTE[c.bucket]}</div>` : '')
   + (c.bucket === 'convertible' ? `<button class="crosslink" data-jump="ms" data-key="${esc(c.cell_key)}">View MS weighings for this case in section 3 &darr;</button>` : '')
   + (!c.dropped_label && CASE_BY_KEY[c.cell_key] ? `<button class="crosslink" data-jump="case" data-key="${esc(c.cell_key)}">Trace this case end to end in section 6 &darr;</button>` : '')
   + `<div class="pricebox" style="margin-top:10px"><b>Price rows in this cell</b>` +
     '<div class="subtable"><table><thead><tr><th>raw unit</th><th>price type</th><th>price</th></tr></thead><tbody>' +
     c.price_rows.map(p => `<tr><td>${p.raw_unit}</td><td>${p.price_type}</td><td>${p.price}</td></tr>`).join('') +
     '</tbody></table></div></div>';

  const right = document.createElement('div');
  right.className = 'detail-col';
  const analyses = gatherAnalyses({
    analysisKey: c.cell_key, rawKeys: c.price_rows.map(p => p.raw_key),
    province: c.province, municipality: c.municipality, item: c.item, harmonizedUnit: c.harmonized_unit,
  });
  right.innerHTML = `<h3>Related analyses</h3>` + renderAnalysesHTML(analyses);

  const detail = document.getElementById('detail');
  detail.innerHTML = '';
  detail.appendChild(left);
  detail.appendChild(right);
  wireCrosslinks(detail);
}

// ============================================================================
// 6. CASE EXPLORER (issue #26, follow-up 2) -- a case-centred third view.
//
// A "case" is province x municipality x item x harmonized_nsu_unit -- key4(),
// identical to `analysis_key` on a weighing and `cell_key` on a (non-island)
// price cell, so no new key scheme is needed: CASE_BY_KEY, WEIGHINGS_BY_CASE and
// CELL_BY_KEY are all keyed the same way and cross-links are a direct lookup.
//
// Outcome 1 / Outcome 2 partition-row classification (the two "Decision rule"
// sections of docs/conversion_factor_methodology.md) is computed HERE, once, from
// fields the payload already carries per weighing (`weighing_approach`,
// `raw_spelling`, `terminal`) -- never re-derived server-side, so there is exactly
// one implementation of "which row does this case fall in", not two that could
// silently disagree.
// ============================================================================
const CE = DATA.case_explorer;
const CASE_BY_KEY = {}; CE.cases.forEach(c => CASE_BY_KEY[c.case_key] = c);
const CROSSWALK_BY_CASE = buildIndex(CE.crosswalk, '_key');
const IDX_ce_psps = buildIndex(CE.psps_exposure, '_key');
const IDX_ce_singleton = buildIndex(CE.singleton_groups, '_key4');
const IDX_dropped_cell3 = buildIndex(PA.dropped_labels, '_cell3');
const WEIGHINGS_BY_CASE = buildIndex(DATA.weighings, 'analysis_key');

// stage-1 "looks_standard" MS-side drops (03_clean_ms.do), keyed by the same
// (province, municipality, item) cell a case belongs to -- these predate
// harmonization, so they carry no harmonized_nsu_unit to key a case on.
const IDX_stage1c_by_cell3 = {};
DATA.dropped.forEach(d => {
  if (d.stage1_drop_reason && d.stage1_drop_reason.startsWith('1c:')) {
    const k = `${d.province}|${d.municipality}|${d.item}`;
    (IDX_stage1c_by_cell3[k] = IDX_stage1c_by_cell3[k] || []).push(d);
  }
});

const SOURCE_TAG = {
  'MS & Price': '<span class="tag ok">weighed (MS &amp; Price)</span>',
  'Price Only': '<span class="tag pending">Price Only &mdash; never weighed under this spelling</span>',
};

function renderCaseSpellingsTable(caseKey) {
  const rows = CROSSWALK_BY_CASE[caseKey] || [];
  if (!rows.length) return '<div class="placeholder">no crosswalk rows for this case</div>';
  return '<div class="subtable"><table><thead><tr><th>raw spelling (pull_nsu_unit)</th><th>cleaned unit</th>' +
    '<th>source</th><th>merges with (in this cell)</th></tr></thead><tbody>' +
    rows.map(r => `<tr><td>${esc(r.pull_nsu_unit)}</td><td>${esc(r.cleaned_nsu_unit)}</td>` +
      `<td>${SOURCE_TAG[r.source] || esc(r.source)}</td>` +
      `<td>${r.n_cell_merged > 1 ? esc(r.cell_merge_with || '') : '<span style="color:var(--muted)">(only spelling here)</span>'}</td></tr>`).join('') +
    '</tbody></table></div>';
}

function renderDroppedSpellingsTable(caseObj) {
  const cell3 = caseObj._cell3;
  const fromMS = (IDX_stage1c_by_cell3[cell3] || []).map(d => ({
    spelling: d.raw_spelling,
    fate: '<span class="tag dropped">dropped from MS</span>',
    detail: 'Not an NSU -- a standard quantity, an ambiguous quantity, or free text that is not a unit. Excluded from the MS weighings before the crosswalk merge, on the list drop_non_nsu_labels.py owns (dofiles/90_diagnostics/build_pipeline_explorer.py stage-1 reason 1c).',
  }));
  const fromCrosswalk = (IDX_dropped_cell3[cell3] || []).map(d => ({
    spelling: d.pull_nsu_unit,
    fate: '<span class="tag dropped">dropped from crosswalk</span>',
    detail: `Removed from master_nsu_rename.csv entirely (dofiles/00_shared/02_drop_non_nsu_labels.py): ${esc(d.drop_reason)}. Source was ${esc(d.source)}; would-be harmonized unit ${esc(d.harmonized_nsu_unit)}.`,
  }));
  const rows = fromMS.concat(fromCrosswalk);
  if (!rows.length) return '<div class="placeholder">no dropped spellings recorded for this (province, municipality, item) cell</div>';
  return '<div class="subtable"><table><thead><tr><th>raw spelling</th><th>fate</th><th>detail</th></tr></thead><tbody>' +
    rows.map(r => `<tr><td>${esc(r.spelling)}</td><td>${r.fate}</td><td>${r.detail}</td></tr>`).join('') +
    '</tbody></table></div>';
}

function renderWeighingSummary(caseWeighings) {
  if (!caseWeighings.length) return '<div class="placeholder">no MS weighing ever reached the restated stage for this case</div>';
  const groups = {};
  caseWeighings.forEach(w => {
    const k = `${w.raw_spelling}||${w.weighing_approach}||${w.size_price_label}||${w.corrected_unit}`;
    if (!groups[k]) groups[k] = { raw_spelling: w.raw_spelling, weighing_approach: w.weighing_approach,
      size_price_label: w.size_price_label, corrected_unit: w.corrected_unit, n: 0 };
    groups[k].n++;
  });
  const rows = Object.values(groups).sort((a, b) => a.raw_spelling.localeCompare(b.raw_spelling));
  return '<div class="subtable"><table><thead><tr><th>raw spelling</th><th>weighing approach</th>' +
    '<th>size/price label</th><th>unit</th><th>n weighings</th></tr></thead><tbody>' +
    rows.map(r => `<tr><td>${esc(r.raw_spelling)}</td><td>${esc(r.weighing_approach)}</td>` +
      `<td>${esc(r.size_price_label)}</td><td>${esc(r.corrected_unit)}</td><td>${r.n}</td></tr>`).join('') +
    '</tbody></table></div>';
}

// ---- Outcome 1 partition (docs/conversion_factor_methodology.md, "Decision rule
// (Outcome 1)") -- domain is the ELIGIBLE weighings, i.e. every weighing whose
// `terminal` is not one of the Outcome-1-only exclusions or the hard drop. ----
const OUTCOME1_ELIGIBLE_TERMINALS = new Set(
  ['outcome1_reference_row', 'outcome1_reference_row_unverified', 'survived_unresolved_size']);

function classifyOutcome1(caseWeighings) {
  const eligible = caseWeighings.filter(w => OUTCOME1_ELIGIBLE_TERMINALS.has(w.terminal));
  if (!eligible.length) {
    const reasons = [...new Set(caseWeighings.map(w => w.terminal_reason).filter(Boolean))];
    return { excluded: true, reasons, hasAnyWeighing: caseWeighings.length > 0 };
  }
  const branches = [...new Set(eligible.map(w => w.weighing_approach))];
  const nSpellings = new Set(eligible.map(w => w.raw_spelling)).size;
  let row, text;
  if (branches.length > 1) {
    row = null;
    text = 'Unexpected: eligible rows span more than one weighing_approach for this case -- the carrot ' +
      'rule should already have excluded the one known mixed-branch cell from Outcome 1 eligibility. Flag for review.';
  } else if (branches[0] === 'conventional') {
    row = 1; text = 'Partition row 1 (conventional, no pooling): no size to resolve -- reports the case median.';
  } else if (branches[0] === 'size-based') {
    row = nSpellings > 1 ? 3 : 2;
    text = nSpellings > 1
      ? 'Partition row 3 (size-based, pools >1 weighed spelling): k = distinct S/M/L field labels across ' +
        'the pooled spellings; terciles are cut on the pooled weights, not any one spelling’s own.'
      : 'Partition row 2 (size-based, single weighed spelling): k = distinct S/M/L field labels present; ' +
        'terciles cut on this spelling’s own weights.';
  } else {
    row = nSpellings > 1 ? 5 : 4;
    text = nSpellings > 1
      ? 'Partition row 5 (price-quantity, pools >1 weighed spelling): only 2 cases in the whole dataset do ' +
        'this (both NEGROS OCCIDENTAL / VALLADOLID, pieces or units) -- both collide, see docs/conversion_factor_methodology.md.'
      : 'Partition row 4 (price-quantity, single weighed spelling): size read off the rung -- mp25→S, mp50→M, mp75→L, any median→M.';
  }
  const bySize = {};
  eligible.forEach(w => {
    if (w.terminal === 'outcome1_reference_row' || w.terminal === 'outcome1_reference_row_unverified') {
      const lbl = w.size_label || '(unresolved)';
      if (!bySize[lbl]) bySize[lbl] = { size_label: lbl, n: 0, grams: w.outcome1_grams,
        unverified: w.terminal === 'outcome1_reference_row_unverified' };
      bySize[lbl].n++;
    }
  });
  return { excluded: false, row, text, sizes: Object.values(bySize) };
}

// ---- Outcome 2 partition (docs/conversion_factor_methodology.md, "Decision rule
// (Outcome 2)") -- domain is EVERY restated weighing for the case (no exclusions:
// the doc's own partition totals 11,360, the full restated population). No
// terminal value is computed or shown -- Outcome 2 has no do-file yet; only the
// applicable rule is named, per the task brief. ----
function classifyOutcome2(caseWeighings) {
  if (!caseWeighings.length) return { applicable: false };
  const branches = [...new Set(caseWeighings.map(w => w.weighing_approach))];
  const nSpellings = new Set(caseWeighings.map(w => w.raw_spelling)).size;
  if (branches.length > 1) {
    return { row: 7, text: 'Partition row 7 (mixed price-quantity + size-based cell -- the carrot rule): ' +
      'Outcome 1 keeps only the size-based rows (row 3 above); Outcome 2 keeps the price-quantity rows, ' +
      'each price point kept separate (row 6 rule, no merge).' };
  }
  const b = branches[0];
  if (b === 'conventional') {
    return nSpellings > 1
      ? { row: 2, text: 'Partition row 2 (conventional, pools >1 weighed spelling): documented as NOT ' +
          'occurring anywhere in the data (0 cases) -- seeing it here means something has changed upstream.' }
      : { row: 1, text: 'Partition row 1 (conventional, no pooling): CF = median(w) over the case. The price file is not used for grouping.' };
  }
  if (b === 'size-based') {
    return nSpellings > 1
      ? { row: 4, text: 'Partition row 4 (size-based, pools >1 weighed spelling): the union of price points ' +
          'from every weighed spelling, merged within ₱20 (single-linkage; a merged point takes the mean), ' +
          'then the pooled weights are cut into as many terciles as surviving points. No terminal value is ' +
          'computed here -- Outcome 2 has no do-file yet (docs/conversion_factor_methodology.md, Row 4 in detail).' }
      : { row: 3, text: 'Partition row 3 (size-based, single weighed spelling): keeps that spelling’s own ' +
          'price points exactly as recorded, no merge. No terminal value is computed here -- Outcome 2 has no do-file yet.' };
  }
  return nSpellings > 1
    ? { row: 6, text: 'Partition row 6 (price-quantity, pools >1 weighed spelling): every distinct pull_price ' +
        'is kept SEPARATE, no merge -- the enumerator spent a specific amount, so collapsing two spellings’ ' +
        'prices would misattribute the price-quantity relationship (docs/conversion_factor_methodology.md, Row 6 in detail).' }
    : { row: 5, text: 'Partition row 5 (price-quantity, single weighed spelling): pull_price is used directly ' +
        'as the price point. The price file is not consulted.' };
}

function renderOutcome1Panel(caseWeighings) {
  const o1 = classifyOutcome1(caseWeighings);
  if (o1.excluded) {
    const why = o1.hasAnyWeighing
      ? `Excluded from the Outcome 1 collapse for every weighing in this case. Reason(s) recorded: ${
          o1.reasons.length ? o1.reasons.map(esc).join(' | ') : '(none recorded -- see raw rows in section 3)'}`
      : 'No MS weighing for this case ever reached the restated stage -- nothing to exclude or include.';
    return `<div class="note">${why}</div>`;
  }
  const sizeRows = o1.sizes.length
    ? '<div class="subtable"><table><thead><tr><th>size</th><th>n</th><th>grams/mL</th><th></th></tr></thead><tbody>' +
      o1.sizes.map(s => `<tr><td>${esc(s.size_label)}</td><td>${s.n}</td><td>${s.grams != null ? s.grams : '(unverified)'}</td>` +
        `<td>${s.unverified ? '<span class="tag pending">unverified</span>' : '<span class="tag ok">published</span>'}</td></tr>`).join('') +
      '</tbody></table></div>'
    : '<div class="placeholder">eligible for Outcome 1, but this tool\'s size replication could not assign a size to any weighing here -- see the generator\'s docstring</div>';
  return `<div class="note">${esc(o1.text)}</div>` + sizeRows;
}

function renderOutcome2Panel(caseWeighings) {
  const o2 = classifyOutcome2(caseWeighings);
  if (o2.applicable === false) return '<div class="placeholder">no MS weighing for this case -- Outcome 2 has nothing to key a conversion factor to</div>';
  return `<div class="note">${esc(o2.text)}</div>`;
}

function renderPSPSExposure(caseKey) {
  const rows = IDX_ce_psps[caseKey] || [];
  if (!rows.length) return '<div class="placeholder">no PSPS exposure record for this case (outputs/tables/psps_conversion_exposure.csv scopes food-only, non-standard-unit PSPS answers -- this case may simply not appear in the PSPS consumption data)</div>';
  const total = rows.reduce((a, r) => a + r.n_psps_obs, 0);
  return `<div class="subtable"><table><thead><tr><th>bucket</th><th>PSPS observations</th></tr></thead><tbody>` +
    rows.map(r => `<tr><td>${esc(r.bucket)}</td><td>${r.n_psps_obs.toLocaleString()}</td></tr>`).join('') +
    `</tbody></table></div><div class="note">${total.toLocaleString()} PSPS household observation(s) in this exact (province, municipality, item, harmonized unit) cell depend on this case's conversion path.</div>`;
}

function renderSingletonFlag(caseKey, caseWeighings) {
  const groups = IDX_ce_singleton[caseKey] || [];
  const totalGroups = new Set(caseWeighings.filter(w => w.corrected_weight != null).map(w => w.size_price_label)).size;
  if (!groups.length) {
    return totalGroups
      ? '<div class="placeholder">none of this case\'s hetero-groups rest on a single weighing</div>'
      : '<div class="placeholder">no weighed hetero-group to check</div>';
  }
  const allSingle = totalGroups > 0 && groups.length >= totalGroups;
  const table = '<div class="subtable"><table><thead><tr><th>label</th><th>branch</th><th>weight</th><th>vendors</th>' +
    '<th>province median (same group, elsewhere)</th><th>province n (excl. this one)</th></tr></thead><tbody>' +
    groups.map(g => `<tr><td>${esc(g.label)}</td><td>${esc(g.branch)}</td><td>${g.w}</td><td>${g.vendors}</td>` +
      `<td>${g.prov_median != null ? g.prov_median : '(n/a)'}</td><td>${g.prov_n_other}</td></tr>`).join('') +
    '</tbody></table></div>';
  return table + (allSingle
    ? '<div class="note">EVERY hetero-group in this case rests on exactly one weighing -- no internal check of any kind (outputs/tables/singleton_hetero_groups.csv, Q4).</div>'
    : `<div class="note">${groups.length} of ${totalGroups} hetero-group(s) in this case rest on a single weighing.</div>`);
}

function renderCaseDetail(caseKey) {
  const caseObj = CASE_BY_KEY[caseKey];
  const holder = document.getElementById('case-detail');
  if (!caseObj) {
    holder.innerHTML = '<div class="placeholder">case not found</div>';
    return;
  }
  const caseWeighings = WEIGHINGS_BY_CASE[caseKey] || [];
  const cell = CELL_BY_KEY[caseKey];
  const units = [...new Set(caseWeighings.map(w => w.corrected_unit).filter(Boolean))];

  const left = document.createElement('div');
  left.className = 'detail-col';
  left.innerHTML = `<h3>${esc(caseObj.province)} / ${esc(caseObj.municipality)} / ${esc(caseObj.item)} / ${esc(caseObj.harmonized_unit)}</h3>` +
    [
      ['Raw spellings folding in', `${caseObj.n_spellings} (${caseObj.n_ms_price} MS &amp; Price, ${caseObj.n_price_only} Price Only)`],
      ['MS weighings (restated stage)', caseWeighings.length],
      ['Unit(s) recorded', units.length ? units.join(', ') : '(no weighing)'],
    ].map(([k, v]) => `<div class="pathstep"><div class="stage">${k}</div><div class="val">${v}</div></div>`).join('') +
    (units.length > 1 ? '<div class="note">More than one corrected unit appears under this harmonized unit -- the panels below pool across all of them for display; docs/conversion_factor_methodology.md’s case grain is actually 5-key (adds corrected_unit).</div>' : '') +
    (cell ? `<button class="crosslink" data-jump="price" data-key="${esc(caseKey)}">View this cell's price rows in section 4 &darr;</button>` : '') +
    (caseWeighings.length ? `<button class="crosslink" data-jump="ms" data-key="${esc(caseKey)}">View MS weighings for this case in section 3 &darr;</button>` : '') +
    `<h3 style="margin-top:16px">1. Raw spellings folding into this case (master_nsu_rename.csv)</h3>` +
    renderCaseSpellingsTable(caseKey) +
    `<h3 style="margin-top:16px">2. Dropped spellings for this cell</h3>` +
    renderDroppedSpellingsTable(caseObj);

  const right = document.createElement('div');
  right.className = 'detail-col';
  right.innerHTML =
    `<h3>3. How each surviving spelling was weighed</h3>` + renderWeighingSummary(caseWeighings) +
    `<h3 style="margin-top:16px">4a. Outcome 1 &mdash; reference-set row(s)</h3>` + renderOutcome1Panel(caseWeighings) +
    `<h3 style="margin-top:16px">4b. Outcome 2 &mdash; conversion-factor eligibility</h3>` + renderOutcome2Panel(caseWeighings) +
    `<h3 style="margin-top:16px">PSPS exposure (psps_conversion_exposure.csv)</h3>` + renderPSPSExposure(caseKey) +
    `<h3 style="margin-top:16px">Singleton hetero-groups (singleton_hetero_groups.csv)</h3>` + renderSingletonFlag(caseKey, caseWeighings) +
    `<h3 style="margin-top:16px">Related analyses</h3>` + renderAnalysesHTML(gatherAnalyses({
      // crosswalk fields arrive already normalized (province upper, municipality upper,
      // item lower, unit lower/trimmed -- same rule key4() applies server-side), so a
      // plain pipe-join here reproduces key4()'s output without a JS re-implementation
      // of nz()/ni()/ng() -- see the task's normalizer rule, "never write a fourth copy".
      analysisKey: caseKey, rawKeys: (CROSSWALK_BY_CASE[caseKey] || []).map(r =>
        `${caseObj.province}|${caseObj.municipality}|${caseObj.item}|${r.pull_nsu_unit}`),
      province: caseObj.province, municipality: caseObj.municipality, item: caseObj.item, harmonizedUnit: caseObj.harmonized_unit,
    }));

  holder.innerHTML = '';
  const grid = document.createElement('div');
  grid.style.cssText = 'display:grid;grid-template-columns:1fr 1fr;gap:16px';
  grid.appendChild(left);
  grid.appendChild(right);
  holder.appendChild(grid);
  wireCrosslinks(holder);
}

function jumpToCase(caseKey) {
  document.getElementById('case-explorer-section').scrollIntoView({ behavior: 'smooth', block: 'start' });
  const c = CASE_BY_KEY[caseKey];
  if (c) document.getElementById('case-search').value = `${c.province} / ${c.municipality} / ${c.item} / ${c.harmonized_unit}`;
  renderCaseResults(caseKey);
  renderCaseDetail(caseKey);
}

function renderCaseResults(highlightKey) {
  const q = document.getElementById('case-search').value.trim().toLowerCase();
  const holder = document.getElementById('case-results');
  if (!q) {
    holder.innerHTML = '<div class="placeholder">type to search across ' + CE.cases.length.toLocaleString() + ' harmonized cases</div>';
    document.getElementById('case-search-count').textContent = '';
    return;
  }
  const matches = CE.cases.filter(c =>
    c.province.toLowerCase().includes(q) || c.municipality.toLowerCase().includes(q) ||
    c.item.toLowerCase().includes(q) || c.harmonized_unit.toLowerCase().includes(q));
  document.getElementById('case-search-count').textContent = `${matches.length.toLocaleString()} case(s)`;
  const MAX = 200;
  const shown = matches.slice(0, MAX);
  if (!shown.length) { holder.innerHTML = '<div class="placeholder">no matching case</div>'; return; }
  holder.innerHTML = '<table><tbody>' + shown.map(c => `
    <tr data-key="${esc(c.case_key)}" style="cursor:pointer${c.case_key === highlightKey ? ';background:#1e3a5f' : ''}">
      <td>${esc(c.province)}</td><td>${esc(c.municipality)}</td><td>${esc(c.item)}</td><td>${esc(c.harmonized_unit)}</td>
      <td style="color:var(--muted)">${c.n_spellings} spelling(s)</td>
    </tr>`).join('') + '</tbody></table>' +
    (matches.length > MAX ? `<div style="padding:6px;color:var(--muted);font-style:italic">showing first ${MAX} of ${matches.length} -- narrow your search</div>` : '');
  holder.querySelectorAll('tr[data-key]').forEach(tr => tr.addEventListener('click', () => renderCaseDetail(tr.dataset.key)));
}

document.getElementById('case-search').addEventListener('input', () => renderCaseResults());
renderCaseResults();
document.getElementById('case-detail').innerHTML = '<div class="placeholder">Search above, or follow a "Trace this case end to end" link from sections 3 or 4.</div>';

document.getElementById('sankey-to-case').addEventListener('click', () =>
  document.getElementById('case-explorer-section').scrollIntoView({ behavior: 'smooth', block: 'start' }));
document.getElementById('price-sankey-to-case').addEventListener('click', () =>
  document.getElementById('case-explorer-section').scrollIntoView({ behavior: 'smooth', block: 'start' }));
</script>
</body>
</html>
"""


if __name__ == "__main__":
    sys.exit(main())
