********************************************************************************
* attrition_ledger.do -- account for every market-survey weighing and every PSPS
*                        household row, at every stage, for BOTH outcomes
*
* WHAT THIS OWNS (issue #8). One table that answers "where did this row go". It covers
* the shared market-survey stages, Outcome 1, Outcome 2's supply side (the lookup) and
* Outcome 2's demand side (the household rows), plus the price-file side, which is #8's
* "equivalently, each case from the price data".
*
* IT COMPUTES EVERY COUNT FROM THE FILES ON DISK. The previous ledger was a frozen CSV
* written by hand against `cleaning_Aug11.do', an archived file, and it went stale in
* three places without anything noticing -- which is the whole reason #8 stayed open. A
* ledger whose numbers are typed is a ledger that will disagree with the build. Nothing
* here re-derives a pipeline decision; it only counts rows in the outputs the pipeline
* wrote.
*
* ==============================================================================
* AGGREGATION IS NOT ATTRITION, and it has its own section
*
* The old ledger put `11,290 weighings -> 2,559 reference-set rows' in the same column as
* the drops, and a reader who subtracts gets an 8,731-row loss that never happened. That
* step discards nothing: it changes the UNIT OF OBSERVATION from a weighing to a
* (case x size) group, and each group publishes one row holding its median. The weighings
* sum back exactly.
*
* So `record_type' separates them:
*
*   stage        rows in -> rows out, with a drop count and a reason
*   aggregation  the unit of observation changes; rows_dropped is deliberately MISSING
*   detail       a named case worth following, with its current status
*
* Every real drop in the market-survey chain is in the `stage' rows and they sum to 205.
*
* ==============================================================================
* GRAIN. Stated on every row, because the previous ledger's own reconciliation section
* showed how easily a coarse-grain input count gets differenced against a fine-grain
* output count and produces a phantom gap. The pooling grain in this project is
*
*     province x municipality x item x harmonized_nsu_unit x corrected_unit
*
* and a count at any other grain says so in the `grain' column.
*
* ------------------------------------------------------------------------------
* INPUTS   every .dta and .csv the two masters write, plus the raw launch file
* OUTPUTS  ${btables}\attrition_ledger.csv
*
* RUN, from the dofiles/ folder, AFTER both masters:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\attrition_ledger.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

* FIXED-WIDTH STRINGS, NOT strL. postfile refuses a strL outright, and the widths below
* are deliberately generous: `post' TRUNCATES a string that overflows its declared width
* rather than complaining, so a tight width would quietly cut the end off the longest
* note. Section 7 asserts nothing came out at its declared maximum, which is what a
* truncation would look like.
tempfile ledger
postfile LG str12 record_type str10 outcome str30 stage str6 step str34 dofile ///
	str240 description double rows_in double rows_dropped double rows_out ///
	str64 grain str400 reason str1200 notes using "`ledger'", replace

* A tiny helper so a count is never typed twice: `n' is set by the caller from a live
* count, and the post below is the only place it is written down.
capture program drop lgpost
program define lgpost
	syntax anything(name=handle), TYPE(string) OUTcome(string) STAGE(string) ///
		DESC(string) [STEP(string) DOFILE(string) IN(real -1) DROPPED(real -1) ///
		OUT(real -1) GRAIN(string) REASON(string) NOTES(string)]
	local i = cond(`in' == -1, ., `in')
	local d = cond(`dropped' == -1, ., `dropped')
	local o = cond(`out' == -1, ., `out')
	post `handle' ("`type'") ("`outcome'") ("`stage'") ("`step'") ("`dofile'") ///
		("`desc'") (`i') (`d') (`o') ("`grain'") ("`reason'") ("`notes'")
end


********************************************************************************
**# 1. The shared market-survey chain
********************************************************************************

use "${data}", clear
local n_raw = _N
lgpost LG, type(stage) outcome(shared) stage(0 raw) dofile((raw survey)) ///
	desc(Raw market-survey weighings as collected) out(`n_raw') grain(weighing) ///
	notes(PSPS NSU Market Survey Launch.dta)

* ---- stage 1: 03_clean_ms.do -------------------------------------------------
* Three drops, and they are separable because 03 exports the middle one with its own
* reason column. Reading that workbook is what keeps ONE definition of "not an NSU":
* 02_drop_non_nsu_labels.py owns the rule and 03 reports what it removed.
use "${btemp}\prelim_nsu_data", clear
local n_arrival = _N

import excel "${btables}\excluded_standard_unit_obs.xlsx", ///
	sheet("excluded_from_MS") firstrow clear
local n_nonnsu = _N
qui levelsof drop_reason, local(reasons) clean
local rsum ""
foreach rr of local reasons {
	qui count if drop_reason == "`rr'"
	local rsum "`rsum'`rr' `r(N)'; "
}

local n_s1 = `n_raw' - `n_arrival'
local n_other = `n_s1' - `n_nonnsu'

lgpost LG, type(stage) outcome(shared) stage(1 arrival) step(1a) ///
	dofile(00_shared/03_clean_ms.do) ///
	desc(Comment-flagged data-entry errors and other hand-identified drops) ///
	in(`n_raw') dropped(`n_other') out(`=`n_raw' - `n_other'') grain(weighing) ///
	reason(a field comment identifies the row as mis-entered) ///
	notes(the residual of stage 1 once the non-NSU labels are accounted for)

lgpost LG, type(stage) outcome(shared) stage(1 arrival) step(1b) ///
	dofile(00_shared/03_clean_ms.do) ///
	desc(Labels that are not non-standard units) ///
	in(`=`n_raw' - `n_other'') dropped(`n_nonnsu') out(`n_arrival') grain(weighing) ///
	reason(`rsum') ///
	notes(rule owned by 02_drop_non_nsu_labels.py; rows listed with their reason in excluded_standard_unit_obs.xlsx. Dropped BEFORE the magnitude snap so they never pollute an anchor pool)

* ---- stage 2: 07_cpi_factor.do -----------------------------------------------
* THE ONLY PLACE THESE ROWS ARE DROPPED, and both outcomes depend on it. Skipping 07
* does not merely cost cpi_factor; it silently readmits weighings whose recorded price
* was not the price the enumerator handed over.
use "${btemp}\nsu_weighings_cpi", clear
local n_restated = _N
local n_s2 = `n_arrival' - `n_restated'
qui count if price_source == "vendor_actual"
local n_rescued = r(N)

lgpost LG, type(stage) outcome(shared) stage(2 priced) step(2) ///
	dofile(00_shared/07_cpi_factor.do) ///
	desc(Price-quantity weighings whose recorded price was not the amount handed over) ///
	in(`n_arrival') dropped(`n_s2') out(`n_restated') grain(weighing) ///
	reason(vendor gave no price at all (approx_price == 1); or vendor-priced where the case keeps a preloaded rung) ///
	notes(`n_rescued' vendor-priced rows are RESCUED rather than dropped, where they were the case's only rung -- losing a case entirely is worse than the problem the drop solves. price_source records which is which)

lgpost LG, type(stage) outcome(shared) stage(2 priced) step(2x) ///
	dofile(00_shared/07_cpi_factor.do) ///
	desc(SHARED CHAIN ENDS HERE -- nsu_weighings_cpi.dta is what both outcomes read) ///
	out(`n_restated') grain(weighing) ///
	notes(carries cpi_factor, and branch/d_reclassified from 08_branch.do)


********************************************************************************
**# 2. Outcome 1
********************************************************************************

use "${btemp}\ref_11_checked", clear
local n_o1_in = _N
local n_s3 = `n_restated' - `n_o1_in'

* Decompose the stage-3 drops from the two files rather than from a remembered split.
use "${btemp}\nsu_weighings_cpi", clear
merge 1:1 id using "${btemp}\ref_11_checked", keepusing(id) generate(_m_o1)
qui count if _m_o1 == 1 & missing(corrected_weight)
local d_nowt = r(N)
qui count if _m_o1 == 1 & inlist(item_nsu_hetero_type, 10, 11)
local d_uniq = r(N)
qui count if _m_o1 == 1 & !missing(corrected_weight) & !inlist(item_nsu_hetero_type, 10, 11)
local d_rest = r(N)

lgpost LG, type(stage) outcome(outcome 1) stage(3 eligible) step(3a) ///
	dofile(10_reference_set/10_size_assignment.do) ///
	desc(Weighings with no defensible weight) ///
	in(`n_restated') dropped(`d_nowt') out(`=`n_restated' - `d_nowt'') grain(weighing) ///
	reason(corrected_weight is .c -- no interpretation rescues the reading) ///
	notes(set by hand in 05_manual_corrections.do rather than deleted, so this ledger can still account for them)

lgpost LG, type(stage) outcome(outcome 1) stage(3 eligible) step(3b) ///
	dofile(10_reference_set/10_size_assignment.do) ///
	desc(unique_mun_price weighings) ///
	in(`=`n_restated' - `d_nowt'') dropped(`d_uniq') ///
	out(`=`n_restated' - `d_nowt' - `d_uniq'') grain(weighing) ///
	reason(a unique municipal price is not a size, and Outcome 1 publishes grams BY SIZE) ///
	notes(Outcome 2 keeps these rows -- they are price-quantity weighings with a real pull_price. See A16 and issue #23)

lgpost LG, type(stage) outcome(outcome 1) stage(3 eligible) step(3c) ///
	dofile(10_reference_set/10_size_assignment.do) ///
	desc(The price-quantity rows of the one mixed-branch cell) ///
	in(`=`n_restated' - `d_nowt' - `d_uniq'') dropped(`d_rest') out(`n_o1_in') grain(weighing) ///
	reason(ILOILO / TIGBAUAN carrot -- bilog (size-based) and pieces or units (price-quantity) fold to one harmonized unit) ///
	notes(Outcome 1 takes the size-based rows of that cell and Outcome 2 takes the price-quantity ones, so neither outcome mixes branches inside a case)

* ---- the collapse, in its own record type -----------------------------------
use "${btemp}\nsu_reference_set", clear
local n_o1_out = _N
qui su n_g
local n_g_sum = r(sum)
qui count if d_thin == 1
local n_thin = r(N)
qui count if fallback_level == 1
local n_fb1 = r(N)

lgpost LG, type(aggregation) outcome(outcome 1) stage(4 published) step(4) ///
	dofile(10_reference_set/12_publish_reference_set.do) ///
	desc(Collapse to one row per case x size -- NOTHING IS DISCARDED) ///
	in(`n_o1_in') out(`n_o1_out') grain(case x size) ///
	notes(rows_dropped is deliberately missing: the unit of observation changes from a weighing to a group. The weighings sum back exactly -- n_g totals `n_g_sum')

lgpost LG, type(detail) outcome(outcome 1) stage(4 published) ///
	dofile(10_reference_set/12_publish_reference_set.do) ///
	desc(Published rows resting on fewer than ${THIN} weighings) ///
	out(`n_thin') grain(case x size) ///
	notes(d_thin. Not attrition -- these rows ship, flagged, and n_g is published so a reader can set their own cut)

lgpost LG, type(detail) outcome(outcome 1) stage(4 published) ///
	dofile(10_reference_set/12_publish_reference_set.do) ///
	desc(Cells that lost their size ladder to the L1 collapse) ///
	out(`n_fb1') grain(case) ///
	notes(fallback_level == 1. Any thin rung collapses a cell of TWO OR MORE rungs to one pooled median; a one-rung cell keeps its own size label because nothing would be pooled)


********************************************************************************
**# 3. Outcome 2 -- the supply side, from weighings to the lookup
********************************************************************************
* Outcome 2 does NOT apply Outcome 1's stage 3. It keeps the unique_mun_price weighings
* (they are real price-quantity measurements) and it slices on `branch' rather than on
* the field's size labels. So its chain forks from stage 2, not from stage 3.

use "${btemp}\nsu_weighings_cpi", clear
forvalues b = 1/3 {
	qui count if branch == `b'
	local nb`b' = r(N)
}
local bnm1 conventional
local bnm2 price-quantity
local bnm3 size-based
forvalues b = 1/3 {
	lgpost LG, type(stage) outcome(outcome 2) stage(3 branch) step(3.`b') ///
		dofile(00_shared/08_branch.do) ///
		desc(Weighings routed to the `bnm`b'' branch) ///
		in(`n_restated') out(`nb`b'') grain(weighing) ///
		notes(branch == `b'. NOT weighing_approach: 99 field-conventional cases whose (item, unit) pair mixes approaches elsewhere are processed as size-based -- issue #28, A12)
}

foreach f in size_based price_quantity conventional {
	use "${btemp}\branch_`f'", clear
	local ng_`f' = _N
}
use "${btemp}\branch_size_based", clear
qui count if d_point_usable == 0
local n_unusable = r(N)
qui count if d_point_usable == 1
local n_s_usable = r(N)

lgpost LG, type(aggregation) outcome(outcome 2) stage(4 branch groups) step(4.3) ///
	dofile(20_psps_retrofitting/21_branch_size_based.do) ///
	desc(Branch S -- pooled weights cut onto the case's convertible price points) ///
	in(`nb3') out(`ng_size_based') grain(case x group) ///
	notes(`n_s_usable' groups carry a weight; `n_unusable' rows are price points a household can MATCH but that yield no weight -- an emptied part of the cut, or a refused unique price. They are in the table on purpose: removing them would push the household onto the next point along)

lgpost LG, type(aggregation) outcome(outcome 2) stage(4 branch groups) step(4.2) ///
	dofile(20_psps_retrofitting/22_branch_price_quantity.do) ///
	desc(Branch P -- one group per distinct peso amount handed over) ///
	in(`nb2') out(`ng_price_quantity') grain(case x price point) ///
	notes(the price file is not read here: p_g is pull_price, and every distinct amount is its own group with no merge. Issue #21 sec 2 rows 5-6)

lgpost LG, type(aggregation) outcome(outcome 2) stage(4 branch groups) step(4.1) ///
	dofile(20_psps_retrofitting/23_branch_conventional.do) ///
	desc(Branch C -- one weight per case, no price and no month) ///
	in(`nb1') out(`ng_conventional') grain(case) ///
	notes(built from the 24 cases whose (item, unit) pair is conventional EVERYWHERE it appears, not from the 123 the field labelled conventional)

use "${btemp}\branch_price_quantity_m", clear
local n_pm = _N
lgpost LG, type(aggregation) outcome(outcome 2) stage(5 month frame) step(5) ///
	dofile(20_psps_retrofitting/24_inflate_to_psps_month.do) ///
	desc(Branch P crossed with the PSPS interview months of its own municipality) ///
	in(`ng_price_quantity') out(`n_pm') grain(case x price point x month) ///
	notes(Branch P only. Its grams are what a fixed peso amount bought, so they move with the price level; a size-based or conventional weight is a property of an object and is the same in every month)

use "${btemp}\outcome2_lookup", clear
local n_lookup = _N
use "${btemp}\outcome2_lookup_noinflation", clear
local n_lookup_ni = _N
lgpost LG, type(aggregation) outcome(outcome 2) stage(6 lookup) step(6) ///
	dofile(20_psps_retrofitting/25_lookup.do) ///
	desc(The three branches appended into the conversion lookup) ///
	out(`n_lookup') grain(case x group, plus month on Branch P) ///
	notes(issue #11's no-inflation variant is a second file of `n_lookup_ni' rows -- it drops the month dimension rather than setting the factor to 1, because without a restatement nothing month-specific is left on any branch)


********************************************************************************
**# 4. Outcome 2 -- the demand side, from consumption rows to grams
********************************************************************************
* THIS IS THE HALF #8 SAID HAD TO WAIT. It could not be written before, because nothing
* read the PSPS consumption file on a critical path.

use "${psps_cons}", clear
local n_cons = _N
qui count if item_type == 1
local n_food = r(N)

lgpost LG, type(stage) outcome(outcome 2) stage(H0 consumption) step(H0) ///
	dofile((raw PSPS)) desc(PSPS Wave 1 consumption rows) out(`n_cons') ///
	grain(household x item) notes(2_consumption.dta)

lgpost LG, type(stage) outcome(outcome 2) stage(H1 food) step(H1) ///
	dofile(20_psps_retrofitting/20a_psps_households.do) ///
	desc(Food rows) in(`n_cons') dropped(`=`n_cons' - `n_food'') out(`n_food') ///
	grain(household x item) reason(item_type != 1 -- non-food and prepped-food rows) ///
	notes(prepped food is recorded in fd_cons_5a as a NUMBER OF TIMES CONSUMED, with no unit and no quantity, so it cannot be converted from an NSU at all)

use "${btemp}\psps_households", clear
local n_slots = _N
lgpost LG, type(aggregation) outcome(outcome 2) stage(H2 slots) step(H2) ///
	dofile(20_psps_retrofitting/20a_psps_households.do) ///
	desc(Reshaped to one row per household x item x acquisition slot) ///
	in(`n_food') out(`n_slots') grain(household x item x slot) ///
	notes(three parallel slots -- 2 purchased, 3 own production, 4 gift -- so one food row can yield up to three rows. Only slots with a non-missing non-zero quantity are kept, which is the filter NSU_Price.R used and therefore the denominator every figure on issue #30 rests on)

forvalues c = 1/5 {
	qui count if conv_path == `c'
	local np`c' = r(N)
}
local pnm1 standard unit -- converted from the unit's own name
local pnm2 non-standard unit -- needs the market survey
local pnm3 not an NSU at all
local pnm4 no unit given by the respondent
local pnm5 NSU label with no crosswalk row in this cell
forvalues c = 1/5 {
	lgpost LG, type(stage) outcome(outcome 2) stage(H3 path) step(H3.`c') ///
		dofile(20_psps_retrofitting/20a_psps_households.do) ///
		desc(`pnm`c'') in(`n_slots') out(`np`c'') grain(household x item x slot) ///
		notes(conv_path == `c'. The five paths are asserted exhaustive and mutually exclusive, so no row is unaccounted for)
}

use "${btemp}\psps_standard_units", clear
local n_std_out = _N
lgpost LG, type(stage) outcome(outcome 2) stage(H4 standard) step(H4) ///
	dofile(20_psps_retrofitting/27_standard_units.do) ///
	desc(Standard-unit rows converted) in(`np1') dropped(0) out(`n_std_out') ///
	grain(household x item x slot) ///
	notes(no market-survey input, no fallback and no cap -- the unit states its own size. Issue #14, and A17 for rice gantang)

use "${btemp}\psps_converted_capped", clear
local n_nsu_in = _N
qui count if d_converted == 1
local n_conv = r(N)
qui count if d_converted == 0
local n_ref = r(N)

lgpost LG, type(stage) outcome(outcome 2) stage(H5 converted) step(H5) ///
	dofile(20_psps_retrofitting/28_match_and_convert.do) ///
	desc(Non-standard-unit rows given grams) in(`n_nsu_in') dropped(`n_ref') ///
	out(`n_conv') grain(household x item x slot) ///
	reason(see the route detail rows below) ///
	notes(a refused row is REPORTED, never imputed and never silently redirected to another price point)

qui levelsof conv_route, local(routes)
foreach rt of local routes {
	qui count if conv_route == `"`rt'"'
	lgpost LG, type(detail) outcome(outcome 2) stage(H5 converted) ///
		dofile(20_psps_retrofitting/28_match_and_convert.do) ///
		desc(route: `rt') out(`r(N)') grain(household x item x slot) ///
		notes(conv_route)
}

forvalues L = 0/3 {
	qui count if d_converted == 1 & fallback_level == `L'
	lgpost LG, type(detail) outcome(outcome 2) stage(H5 converted) ///
		dofile(20_psps_retrofitting/30_fallback.do) ///
		desc(converted at fallback level `L') out(`r(N)') grain(household x item x slot) ///
		notes(from L1 down the household's own price is not used at all -- A15)
}

qui count if d_cap == 1
lgpost LG, type(detail) outcome(outcome 2) stage(H6 capped) ///
	dofile(20_psps_retrofitting/29_cap.do) ///
	desc(Rows whose price ratio hit the cap) out(`r(N)') grain(household x item x slot) ///
	notes(clamped and KEPT, never dropped. d_cap marks them and r_h_raw keeps the uncapped ratio. A18)


********************************************************************************
**# 5. The price-file side
********************************************************************************
* #8 asks for the price data accounted for as well as the market survey: "equivalently,
* each case from the price data". The counts come from 20_case_price_points.do's inputs
* and output rather than being recomputed.

import delimited "${pricedata}", clear varnames(1)
cap drop v1
local n_price = _N

use "${btemp}\case_price_points", clear
local n_points = _N
qui count if d_point_unconvertible == 1
local n_pt_ref = r(N)

lgpost LG, type(stage) outcome(price file) stage(P0 raw) dofile((price file)) ///
	desc(Price rows as delivered) out(`n_price') grain(raw cell x price type) ///
	notes(NSU_prices_from_Makayla.csv. One row carries R's literal string NA and is a placeholder, not a lost price -- see 20_case_price_points.do section 1)

lgpost LG, type(aggregation) outcome(price file) stage(P1 points) ///
	dofile(20_psps_retrofitting/20_case_price_points.do) ///
	desc(Price points after the union on value and the PHP 20 single-linkage merge) ///
	in(`n_price') out(`n_points') grain(case x point) ///
	notes(rows on a label the non-NSU trim removed are dropped; rows on a spelling never WEIGHED in the cell are excluded from grouping but retained for the A11 gap flag. `n_pt_ref' of the surviving points are refused -- a unique price with no weighing behind it)

use "${btemp}\case_spelling_gap", clear
local n_gap = _N
qui count if d_spelling_gap == 1
lgpost LG, type(detail) outcome(price file) stage(P2 gap) ///
	dofile(20_psps_retrofitting/20_case_price_points.do) ///
	desc(Priced-but-unweighed spellings, and how many diverge in price level) ///
	in(`n_gap') out(`r(N)') grain(case x spelling) ///
	notes(A11. Flagged at 2x and refused at conversion: the household faced that spelling's price level but would be scored against a ladder built from the other spelling's prices, and CF_h is linear in p_h/p_g)


********************************************************************************
**# 6. Named cases worth following
********************************************************************************
* #8 asked that four specific cases be carried forward. Each is CHECKED against the
* current build rather than restated from the old ledger's prose, because two of the four
* have since been resolved and carrying them as live losses would be wrong.

use "${btemp}\ref_11_checked", clear
qui count if pull_municipal_city == "ENRIQUE B. MAGALONA (SARAVIA)" & ///
	strpos(pull_item, "ice cream") > 0 & harmonized_nsu_unit == "putos" & corrected_unit == 2
local n_ice = r(N)
lgpost LG, type(detail) outcome(shared) stage(2 priced) ///
	dofile(00_shared/07_cpi_factor.do) ///
	desc(NEGROS OCCIDENTAL / ENRIQUE B. MAGALONA / ice cream / putos / mL) ///
	out(`n_ice') grain(case) ///
	notes(RESOLVED. This cell used to be lost in stage 2 to a rescue-rule grain mismatch -- the rule decided "does this case keep a preloaded rung" WITHOUT corrected_unit, so the g side's preloaded row shielded the mL side, whose only price-quantity row was then dropped. corrected_unit is now in the rescue key and the cell survives with `n_ice' weighing(s))

use "${btemp}\nsu_weighings_cpi", clear
qui count if pull_municipal_city == "TAPAZ" & pull_item == "chicken"
local n_tapaz_in = r(N)
qui count if pull_municipal_city == "TAPAZ" & pull_item == "chicken" & missing(corrected_unit)
local n_tapaz_nodim = r(N)
use "${btemp}\ref_11_checked", clear
qui count if pull_municipal_city == "TAPAZ" & pull_item == "chicken"
lgpost LG, type(detail) outcome(outcome 1) stage(3 eligible) ///
	dofile(10_reference_set/10_size_assignment.do) ///
	desc(CAPIZ / TAPAZ / chicken / whole (chicken)) ///
	in(`n_tapaz_in') dropped(`n_tapaz_nodim') out(`r(N)') grain(case) ///
	notes(STILL LIVE. `n_tapaz_nodim' of `n_tapaz_in' rows have a blank field weight and so no corrected_unit, which puts them in their own (case x corrected_unit = missing) group. The case is lost at the fine grain while its g split survives -- so a count of CASES differs between the two grains here, which is exactly why every row of this ledger states its grain)

qui count if harmonized_nsu_unit == "putos (mix vegetable)"
local n_pmv = r(N)
preserve
	keep if harmonized_nsu_unit == "putos (mix vegetable)"
	qui levelsof pull_item, local(pmv_items) clean
	egen byte _t = tag(pull_province pull_municipal_city pull_item)
	qui count if _t
	local n_pmv_cells = r(N)
restore
lgpost LG, type(detail) outcome(shared) stage(1 arrival) ///
	dofile(00_shared/nsu_fold_rule.py) ///
	desc(Harmonized unit putos (mix vegetable)) ///
	out(`n_pmv') grain(weighing) ///
	notes(ITS OWN CASE, not part of the carrot narrative. It is a fold target collecting rows from MORE THAN ONE ITEM -- `pmv_items' -- across `n_pmv_cells' cells. The ILOILO / DUENAS cabbage cell that had no price-file row was a different problem and was resolved by dropping an ambiguous label at source; see issue #22)

lgpost LG, type(detail) outcome(shared) stage(1 arrival) ///
	dofile(00_shared/03_clean_ms.do) ///
	desc(The crosswalk merge itself) out(0) grain(weighing) ///
	notes(0 unmatched, and 03 hard-stops if that ever changes. So "no crosswalk row" is a DEFECT category rather than an attrition category, and every stage-1 drop leaves against a stated reason)


********************************************************************************
**# 7. Write it, and reconcile
********************************************************************************

postclose LG
use "`ledger'", clear

* TRUNCATION CHECK. `post' silently cuts a string that overflows its declared width, so a
* value sitting exactly at the maximum is the signature of a note whose end was lost.
foreach v in description reason notes {
	local w : type `v'
	local w = real(subinstr("`w'", "str", "", .))
	qui count if strlen(`v') >= `w'
	if r(N) > 0 {
		di as err "ERROR: " r(N) " `v' value(s) are at the full str`w' width -- truncated."
		di as err "Widen the postfile declaration; do not shorten the text to fit."
		exit 459
	}
}

label var record_type  "stage = a real drop; aggregation = the unit of observation changes; detail = a named figure"
label var outcome      "shared, outcome 1, outcome 2, or price file"
label var grain        "what one row is counted at -- differencing across grains is how phantom gaps appear"
label var rows_dropped "MISSING on an aggregation row, deliberately: nothing was discarded"

order record_type outcome stage step dofile description rows_in rows_dropped rows_out grain reason notes
export delimited using "${btables}\attrition_ledger.csv", replace
di as txt "wrote ${btables}\attrition_ledger.csv (" _N " row(s))"

* ---- the reconciliation, printed -------------------------------------------
di as res _n "{hline 78}"
di as res "MARKET-SURVEY CHAIN"
di as res "{hline 78}"
di as res %10.0fc `n_raw'      "  raw weighings"
di as res %10.0fc -`n_s1'      "  stage 1  (03_clean_ms.do)"
di as res %10.0fc `n_arrival'  "  = arrival"
di as res %10.0fc -`n_s2'      "  stage 2  (07_cpi_factor.do)  -- BOTH outcomes read this file"
di as res %10.0fc `n_restated' "  = priced weighings"
di as res %10.0fc -`n_s3'      "  stage 3  (Outcome 1 only)"
di as res %10.0fc `n_o1_in'    "  = entering the Outcome 1 collapse"
di as res "        ->" %8.0fc `n_o1_out' "  published reference-set rows  (AGGREGATION, not attrition)"
di as res ""
di as res "  every real drop: " %6.0fc `=`n_s1' + `n_s2' + `n_s3''

di as res _n "{hline 78}"
di as res "OUTCOME 2, HOUSEHOLD SIDE"
di as res "{hline 78}"
di as res %10.0fc `n_cons'    "  consumption rows"
di as res %10.0fc `n_food'    "  = food rows"
di as res %10.0fc `n_slots'   "  = household x item x slot rows with a usable quantity"
di as res %10.0fc `np1'       "     of which already in a standard unit  -> `n_std_out' converted"
di as res %10.0fc `np2'       "     of which needing an NSU conversion"
di as res %10.0fc `n_conv'    "        converted"
di as res %10.0fc `n_ref'     "        refused and reported"
di as res %10.0fc `np3'       "     not an NSU"
di as res %10.0fc `=`np4' + `np5'' "     no unit given, or a label with no crosswalk row"

local n_paths = `np1' + `np2' + `np3' + `np4' + `np5'
if `n_paths' != `n_slots' {
	di as err "ERROR: the five conversion paths sum to `n_paths', not `n_slots'."
	exit 459
}
if `n_conv' + `n_ref' != `np2' {
	di as err "ERROR: converted + refused does not equal the NSU population."
	exit 459
}
di as res _n "  the five paths sum to the slot rows, and converted + refused sums to the"
di as res "  NSU population. Both asserted, so no household row is unaccounted for."

di as res _n "{hline 78}"
di as res "attrition_ledger.do done. Regenerate docs/attrition_ledger.md from this CSV,"
di as res "never the other way round."
di as res "{hline 78}"
