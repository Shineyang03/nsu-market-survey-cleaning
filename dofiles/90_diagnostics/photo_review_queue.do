********************************************************************************
* photo_review_queue.do -- which weighings are worth checking against the field
*                           photographs, and in what order
*
* WHAT THIS IS FOR. Issue #38 is a review of the field photographs against the
* published weights. Nothing in the build says which rows to pull first. This file
* is that list: it reads what the pipeline already decided and flags the weighings
* where that decision is least supported, so a reviewer holding the photographs
* knows where to start.
*
* WHAT IT READS, AND WHY IT RECOMPUTES NOTHING. Every quantity this file flags on
* was already computed by the pipeline: `corrected_weight' (04_unit_snap.do STEP 3e),
* `snap_rule' and `snap_block' (the same step, recording WHICH rule set the weight),
* `corrected_unit' and `item_nsu_hetero_type' (03_clean_ms.do / 04_unit_snap.do).
* Project policy (CLAUDE.md) is that a diagnostic reads the quantity the pipeline
* computed and never re-derives it -- this file does not touch `weight', `unit' or
* `KGMAX', and it does not re-implement any part of the block-reading rule in
* 00_shared/03a_block_reading.do or the adjudication ladder in 04_unit_snap.do. The
* only thing computed HERE is a pool median and a ratio to it, which is not a
* pipeline decision -- it is the diagnostic's own yardstick for how far a published
* weight sits from its neighbours.
*
* THREE FLAG COMPONENTS, UNIONED. A weighing is queued if ANY of these hold:
*
*   1. DECADE OUTLIER    -- corrected_weight is >= `K' times, or <= 1/`K' times, the
*                            median of its pool (pull_item x corrected_unit x
*                            item_nsu_hetero_type), among pools with >=10 published
*                            weighings. This is the direct test of the block-reading
*                            thresholds in 03a_block_reading.do (KGMAX=30, the litre
*                            band): a "block governs" row that is still a decade off
*                            its neighbours is exactly the case those thresholds are
*                            supposed to prevent.
*   2. ANCHOR-SET         -- snap_block == 0: the anchor (log10 median snap) set the
*                            published weight rather than the block reading. Rare on
*                            this vintage (04_unit_snap.do's STEP 3e-v-b publishes the
*                            block reading wherever it is a possible reading), so this
*                            component flags exactly the rows where the block reading
*                            was NOT usable at all.
*   3. NOTHING PUBLISHED  -- corrected_weight is missing: no typed weight survived to
*                            be corrected. All 8 such rows on this build carry Stata's
*                            extended missing code `.c', inherited unchanged from
*                            `weight' in 03_clean_ms.do ("enumerators sometimes enter 0
*                            weight when they don't observe the item at the specified
*                            price/size"). The CSV shows that literal `.c', not a blank
*                            cell -- it is the pipeline's own record of WHY nothing was
*                            typed, not a formatting artefact of this file.
*
* THE K DIAL. `K' (a named local, set once below) controls how extreme a ratio has to
* be to count as a decade outlier. It is a sensitivity dial, not a fixed fact about
* the data -- raising or lowering it trades queue size against how confident each
* flagged row is. Measured on this build: K=10 -> 89 rows, K=5 -> 469, K=3 -> 845.
* The default is 10 because that is the decade-scale test the block-reading rule
* itself is pitched at (a kg/g slip or an L/mL slip is a factor of 1,000 or 1,000,000;
* a factor of 10 is the smallest slip that rule is built to catch).
*
* WHY THE CROSS-TAB WITH snap_rule MATTERS. Rows where "block governs" are 12x more
* likely to be a decade outlier than rows where the log10 median snap governs
* (measured below). That is not a property of this diagnostic; it is the finding that
* motivates running it -- the block reading is exactly what 03a_block_reading.do's
* KGMAX=30 and litre-band thresholds decide, so a concentration of outliers there is
* the concrete test of whether those thresholds are right. If the photographs confirm
* the flagged "block governs" rows, the thresholds hold; if they do not, the
* concentration says where to look first.
*
* OUTPUT. outputs/tables/photo_review_queue.csv, one row per flagged weighing, with
* enough identifying columns (province, municipality, market, store/stall, vendor,
* item and raw NSU label) that a reviewer holding the photographs can find the row.
* Sorted most-suspect first: largest absolute log10 ratio first (the decade outliers,
* worst first), then the anchor-set rows, then the rows with nothing published at all
* -- see the sort block near the end for how the three tiers are built.
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\photo_review_queue.do
********************************************************************************

version 19
clear all
set more off

do "00_shared/00_globals.do"

* ---- THE DIAL. Change this, not a number buried in the ratio expression below. ----
local K = 10

********************************************************************************
* 1. load the published build and decode the labelled numerics this file reports.
*    encode/decode round-trips are the whole reason for this step: item_nsu_hetero_
*    type, corrected_unit and snap_rule are Stata value-labelled numerics on the
*    build, and a reviewer's CSV needs the strings, not the codes.
********************************************************************************
use "${btemp}/nsu_weighings_cpi.dta", clear

decode item_nsu_hetero_type, gen(hetero_type_str)
decode corrected_unit,       gen(corrected_unit_str)
decode snap_rule,            gen(snap_rule_str)

di as res _n "{hline 78}"
di as res "photo_review_queue.do -- universe counts"
di as res "{hline 78}"

quietly count
local n_all = r(N)
di as txt "restated weighings (one row per weighing), universe of this file: `n_all'"

quietly count if !missing(corrected_weight)
di as txt "  of which carry a published corrected_weight: " r(N)

quietly count if missing(corrected_weight)
di as txt "  of which have nothing published (no typed weight survived): " r(N)

quietly count if inlist(hetero_type_str, "small_size", "medium_size", "large_size")
di as txt "  of which are size weighings (small/medium/large_size): " r(N)

********************************************************************************
* 2. the pool median and the ratio to it -- THE ONLY THING THIS FILE COMPUTES.
*    Pool = pull_item x corrected_unit x item_nsu_hetero_type. Grouping on the
*    labelled numerics (not the decoded strings) is the same partition and avoids
*    any string-collation surprise; only pools with >=10 published weighings are
*    judged, per the brief.
********************************************************************************
egen double pool_median = median(corrected_weight), by(pull_item corrected_unit item_nsu_hetero_type)
egen long   pool_n       = count(corrected_weight),  by(pull_item corrected_unit item_nsu_hetero_type)

gen double ratio_to_pool_median = corrected_weight / pool_median ///
	if pool_n >= 10 & !missing(corrected_weight) & pool_median > 0
label var pool_median         "Median corrected_weight in this weighing's pool (pull_item x corrected_unit x item_nsu_hetero_type), among pools with >=10 published weighings"
label var ratio_to_pool_median "corrected_weight / pool_median, judged only where the pool has >=10 published weighings"

di as res _n "{hline 78}"
di as res "photo_review_queue.do -- decade-outlier sensitivity (component 1 alone)"
di as res "{hline 78}"
di as txt "universe for this count: weighings in a pool with >=10 published weighings"
foreach kk in 10 5 3 {
	quietly count if !missing(ratio_to_pool_median) & (ratio_to_pool_median >= `kk' | ratio_to_pool_median <= 1/`kk')
	di as txt "  K=`kk': " r(N) " row(s) at least `kk'x (or <=1/`kk'x) their pool median"
}

********************************************************************************
* 3. the three flag components, unioned
********************************************************************************
gen byte flag_decade_outlier = !missing(ratio_to_pool_median) ///
	& (ratio_to_pool_median >= `K' | ratio_to_pool_median <= 1/`K')
label var flag_decade_outlier "1 = corrected_weight is >=`K'x or <=1/`K'x its pool median (pool n>=10)"

gen byte flag_anchor_set = (snap_block == 0)
label var flag_anchor_set "1 = the anchor (log10 median) snap set corrected_weight, not the block reading"

gen byte flag_missing_weight = missing(corrected_weight)
label var flag_missing_weight "1 = no corrected_weight was published at all"

gen byte flag_any = flag_decade_outlier | flag_anchor_set | flag_missing_weight

di as res _n "{hline 78}"
di as res "photo_review_queue.do -- component counts (universe: `n_all' restated weighings)"
di as res "{hline 78}"
quietly count if flag_decade_outlier
di as txt "component 1, decade outlier (K=`K'): " r(N)
quietly count if flag_anchor_set
di as txt "component 2, anchor-set (snap_block==0): " r(N)
quietly count if flag_missing_weight
di as txt "component 3, nothing published: " r(N)
quietly count if flag_any
local n_union = r(N)
di as res "UNION (any component fires): `n_union'"
quietly count if flag_any & inlist(hetero_type_str, "small_size", "medium_size", "large_size")
di as res "  of which are size weighings: " r(N)

********************************************************************************
* 4. the snap_rule x decade-outlier cross-tab -- the headline finding that sets the
*    review priority. snap_rule is read off the build, not recomputed; see the
*    header. Printed as counts and shares so the concentration is visible in the log
*    without opening the CSV.
********************************************************************************
di as res _n "{hline 78}"
di as res "photo_review_queue.do -- snap_rule x decade-outlier cross-tab"
di as res "unit of observation: one restated weighing; universe: `n_all'"
di as res "{hline 78}"
tab snap_rule_str flag_decade_outlier, m

levelsof snap_rule_str, local(rules)
foreach r of local rules {
	quietly count if snap_rule_str == "`r'"
	local rn = r(N)
	quietly count if snap_rule_str == "`r'" & flag_decade_outlier
	local ro = r(N)
	local shr = 100*`ro'/`rn'
	di as txt "  `r': `rn' row(s), `ro' decade outlier(s) (" %4.2f `shr' "%)"
}

********************************************************************************
* 5. flag_reason -- which component(s) fired, for the rows in the queue
********************************************************************************
gen str60 flag_reason = ""
replace flag_reason = flag_reason + cond(flag_reason=="","","; ") + "decade_outlier" if flag_decade_outlier
replace flag_reason = flag_reason + cond(flag_reason=="","","; ") + "anchor_set"     if flag_anchor_set
replace flag_reason = flag_reason + cond(flag_reason=="","","; ") + "missing_weight" if flag_missing_weight
label var flag_reason "which component(s) queued this row: decade_outlier, anchor_set, missing_weight"

********************************************************************************
* 6. sort order -- most-suspect first. Three tiers: decade outliers ordered by the
*    size of their own log10 ratio (worst first), then anchor-set rows, then rows
*    with nothing published at all. `id' breaks ties within a tier deterministically,
*    per the project's sort-seed convention (dofiles/README.md, "Determinism").
********************************************************************************
gen double abs_log10_ratio = abs(log10(ratio_to_pool_median)) if !missing(ratio_to_pool_median)
label var abs_log10_ratio "abs(log10(ratio_to_pool_median)); larger = further from the pool median"

gen byte queue_tier = .
replace  queue_tier = 1 if flag_decade_outlier
replace  queue_tier = 2 if missing(queue_tier) & flag_anchor_set
replace  queue_tier = 3 if missing(queue_tier) & flag_missing_weight
label define queue_tier_lbl 1 "1: decade outlier" 2 "2: anchor-set" 3 "3: nothing published", replace
label values queue_tier queue_tier_lbl

gen double _sortkey = -abs_log10_ratio if queue_tier == 1

keep if flag_any
sort queue_tier _sortkey id
drop _sortkey

di as res _n "{hline 78}"
di as res "photo_review_queue.do -- final queue"
di as res "{hline 78}"
di as res "rows written: " _N " (of `n_all' restated weighings, `n_union' flagged)"
tab queue_tier, m

********************************************************************************
* 7. write the CSV. Rounded to whole grams/mL for pool_median (matching
*    corrected_weight's own precision) and 2 decimals for the ratio -- this is a
*    reviewer-facing table, not an input to a statistical test, so plain round() is
*    fine here (contrast validate_folds.do, where p-values must survive at full
*    double precision).
********************************************************************************
replace pool_median         = round(pool_median, 1)
replace ratio_to_pool_median = round(ratio_to_pool_median, 0.01)
replace abs_log10_ratio      = round(abs_log10_ratio, 0.001)

keep id pull_province pull_municipal_city market_name store_stall_name vendor_id ///
	pull_item pull_nsu_unit hetero_type_str corrected_weight corrected_unit_str ///
	pool_median ratio_to_pool_median snap_rule_str flag_reason queue_tier abs_log10_ratio

rename hetero_type_str      hetero_type
rename corrected_unit_str   corrected_unit
rename snap_rule_str        snap_rule

order id pull_province pull_municipal_city market_name store_stall_name vendor_id ///
	pull_item pull_nsu_unit hetero_type corrected_weight corrected_unit ///
	pool_median ratio_to_pool_median snap_rule flag_reason queue_tier abs_log10_ratio

export delimited using "${tables}/photo_review_queue.csv", replace

di as res _n "{hline 78}"
di as res "wrote ${tables}/photo_review_queue.csv (" _N " row(s))"
di as res "{hline 78}"
