********************************************************************************
* nsu_restate_weights.do
*
* Restates price-quantity market-survey weighings to a common reference month so
* that weighings collected in 2026m3 / 2026m4 / 2026m5 can be pooled without the
* pool itself being contaminated by which month's price level happened to apply.
*
* WHY THIS STEP EXISTS
* On the price-quantity branch (weighing_approach == 2) the enumerator was handed a
* FIXED preloaded peso amount and bought whatever it bought; the grams recorded
* therefore depend on the price level in the month of that particular vendor visit.
* Restate every such weighing to a common reference month BEFORE any aggregation:
*
*     w_ref(i) = corrected_weight(i) * CPI(province, item_group, m_MS(i))
*                                     / CPI(province, item_group, REF)
*
* Downstream the pipeline multiplies by CPI(REF)/CPI(m_PSPS(household)), so REF
* cancels out algebraically -- it is a pure bookkeeping anchor, not a modeling
* choice. REF = 2026m4 is used because it is the modal market-survey month
* (5,970 of 11,458 weighings); any other in-sample month would give the same
* final answer once the cancellation happens downstream, so this is not agonized
* over further.
*
* SCOPE: this restatement applies ONLY to weighing_approach == 2 (price-quantity).
* Size-based (== 3) and conventional (== 1) weights are properties of the object
* weighed -- a medium mango's grams are not a price-round quantity -- so those rows
* are carried through unchanged: cpi_factor = 1 exactly, w_ref = corrected_weight.
* They are NOT dropped; every input row is expected to survive into the output
* (less the 95 rows excluded in step 1 below).
*
* INPUTS  (read only)
*   outputs/master_rename_build/temp/nsu_data_master.dta   11,458 weighings
*   outputs/tables/cpi_level_panel.csv                      2,250 rows
*   outputs/tables/cpi_item_crosswalk.csv                       95 rows
*
* OUTPUT
*   outputs/master_rename_build/temp/nsu_weights_restated.dta
*
* Run as a fresh isolated batch process:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do nsu_restate_weights.do
********************************************************************************

clear all
set more off

global root "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning"
global temp_in  "${root}\outputs\master_rename_build\temp"
global tables   "${root}\outputs\tables"

local ref_month = tm(2026m4)

********************************************************************************
**# 0. Load
********************************************************************************

use "${temp_in}\nsu_data_master.dta", clear
local n_in = _N
di as result "Rows in: `n_in'"
assert `n_in' == 11458

********************************************************************************
**# 1. Drop the 95 vendor-priced price-quantity rows
********************************************************************************

* On weighing_approach == 2, a non-missing actual_price means a field-officer
* comment recorded that the VENDOR'S OWN price governed the transaction, not the
* preloaded fixed amount. The "fixed peso amount" premise the restatement formula
* relies on fails for those rows, so they cannot be restated and are dropped
* entirely (not carried through with cpi_factor = 1).

* --- capture the rung structure BEFORE the drop, for the "lost its only rung" check
preserve
    keep pull_province pull_municipal_city pull_item harmonized_nsu_unit item_nsu_hetero_type
    duplicates drop
    bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit: gen n_rungs_before = _N
    tempfile before_rungs
    save "`before_rungs'"
restore

count if weighing_approach == 2 & !missing(actual_price)
di as result "Vendor-priced price-quantity rows: " r(N)
assert r(N) == 95

* --- RESCUE RULE ---------------------------------------------------------------
* Dropping all 95 would delete 6 cases outright, because the vendor-priced rows
* were the case's ONLY rung. Losing a case entirely is worse than the problem the
* drop is meant to solve.
*
* The objection to using actual_price was that it puts two different prices inside
* one rung's median. That objection only bites where a preloaded-price rung
* SURVIVES to be mixed with. Where nothing survives there is nothing to mix, so
* the vendor's own price is simply the best available p_r for that case.
*
* So: drop where the case keeps at least one preloaded rung; keep and re-flag
* where it would otherwise vanish. price_source records which is which so no
* downstream step can confuse a vendor-quoted price for a preloaded one.

gen byte n_pre = (weighing_approach == 2 & missing(actual_price))
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	egen byte has_preloaded = max(n_pre)
drop n_pre

gen str14 price_source = ""
replace price_source = "preloaded"     if weighing_approach == 2 & missing(actual_price)
replace price_source = "vendor_actual" if weighing_approach == 2 & !missing(actual_price) & has_preloaded == 0
label var price_source "which peso figure is p_r for this row (price-quantity only)"

count if weighing_approach == 2 & !missing(actual_price) & has_preloaded == 0
di as result "  rescued (case would otherwise vanish): " r(N)
count if weighing_approach == 2 & !missing(actual_price) & has_preloaded == 1
di as result "  dropped (case keeps a preloaded rung): " r(N)

drop if weighing_approach == 2 & !missing(actual_price) & has_preloaded == 1
drop has_preloaded

local n_dropped = `n_in' - _N
di as result "Rows dropped: `n_dropped'"

* --- capture the rung structure AFTER the drop and compare
preserve
    keep pull_province pull_municipal_city pull_item harmonized_nsu_unit item_nsu_hetero_type
    duplicates drop
    gen byte rung_after = 1
    tempfile after_rungs
    save "`after_rungs'"
restore

preserve
    use "`before_rungs'", clear
    merge 1:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit item_nsu_hetero_type using "`after_rungs'"
    gen byte rung_lost = (_merge == 1)
    di as result "--- Step 1 check: rungs lost from the vendor-price drop ---"
    count if rung_lost == 1
    di as result "  (case, rung) pairs that lost a rung: " r(N)
    if r(N) > 0 {
        list pull_province pull_municipal_city pull_item harmonized_nsu_unit item_nsu_hetero_type n_rungs_before if rung_lost == 1, sepby(pull_province) noobs
    }
    count if rung_lost == 1 & n_rungs_before == 1
    di as result "  of which the case's ONLY rung (case now has zero rungs of any type): " r(N)
    if r(N) > 0 {
        list pull_province pull_municipal_city pull_item harmonized_nsu_unit item_nsu_hetero_type if rung_lost == 1 & n_rungs_before == 1, sepby(pull_province) noobs
    }
restore

********************************************************************************
**# 2. Derive the market-survey month
********************************************************************************

gen m_ms = mofd(dofc(submissiondate))
format m_ms %tm

di as result "--- m_ms distribution ---"
tab m_ms, m
assert inlist(m_ms, tm(2026m3), tm(2026m4), tm(2026m5))

********************************************************************************
**# 3. Join item_group via the (province, cons_name) crosswalk
********************************************************************************

* Normalize the join key on the master side: pull_item is already lowercased and
* whitespace-collapsed, but apply the restaurant rule used elsewhere in the project.
gen item_norm = trim(itrim(lower(pull_item)))
replace item_norm = "drinks at restaurant, hotel, cafe, or kiosk" if strpos(item_norm, "restaurant") > 0

* Verify (not assume) that pull_province is already uppercase.
assert pull_province == strupper(pull_province)

preserve
    import delimited "${tables}\cpi_item_crosswalk.csv", clear varnames(1) encoding("utf-8")
    assert province == strupper(province)
    gen item_norm = trim(itrim(lower(cons_name)))
    replace item_norm = "drinks at restaurant, hotel, cafe, or kiosk" if strpos(item_norm, "restaurant") > 0
    * confirm the (province, normalized-name) key is unique before it becomes a
    * merge key -- this is the trap the brief warns about: never merge on
    * cons_name alone, because ice cream maps to a different item_group in Iloilo.
    isid province item_norm
    rename province pull_province
    keep pull_province item_norm item_group
    tempfile crosswalk_norm
    save "`crosswalk_norm'"
restore

merge m:1 pull_province item_norm using "`crosswalk_norm'", keep(1 3) keepusing(item_group) gen(_merge_cw)

count if _merge_cw == 1
di as result "--- Step 3 check: weighings with no item_group match ---"
di as result "  unmatched: " r(N)
if r(N) > 0 {
    list id pull_province pull_item if _merge_cw == 1, noobs
}
drop _merge_cw item_norm

********************************************************************************
**# 4. Join the CPI level at m_ms and at REF
********************************************************************************

preserve
    import delimited "${tables}\cpi_level_panel.csv", clear varnames(1) encoding("utf-8")
    isid province item_group mdate
    rename province pull_province
    keep pull_province item_group mdate cpi cpi_ma3
    tempfile cpi_panel
    save "`cpi_panel'"
restore

* --- CPI at the weighing's own month ---
gen mdate = m_ms
format mdate %tm
merge m:1 pull_province item_group mdate using "`cpi_panel'", keep(1 3) keepusing(cpi cpi_ma3) gen(_merge_ms)
rename cpi     cpi_at_m_ms
rename cpi_ma3 cpi_ma3_at_m_ms

count if weighing_approach == 2 & _merge_ms == 1
di as result "--- Step 4 check: price-quantity rows unmatched at m_ms ---"
di as result "  unmatched: " r(N)
if r(N) > 0 {
    list id pull_province item_group m_ms if weighing_approach == 2 & _merge_ms == 1, noobs
}
assert weighing_approach != 2 | _merge_ms == 3
drop mdate _merge_ms

* --- CPI at the reference month ---
gen mdate = `ref_month'
format mdate %tm
merge m:1 pull_province item_group mdate using "`cpi_panel'", keep(1 3) keepusing(cpi cpi_ma3) gen(_merge_ref)
rename cpi     cpi_at_ref
rename cpi_ma3 cpi_ma3_at_ref

count if weighing_approach == 2 & _merge_ref == 1
di as result "--- Step 4 check: price-quantity rows unmatched at REF ---"
di as result "  unmatched: " r(N)
if r(N) > 0 {
    list id pull_province item_group if weighing_approach == 2 & _merge_ref == 1, noobs
}
assert weighing_approach != 2 | _merge_ref == 3
drop mdate _merge_ref

********************************************************************************
**# 5. cpi_factor and w_ref (level CPI)
********************************************************************************

gen double cpi_factor = 1
replace cpi_factor = cpi_at_m_ms / cpi_at_ref if weighing_approach == 2
gen double w_ref = corrected_weight * cpi_factor

********************************************************************************
**# 6. cpi_factor_ma3 and w_ref_ma3 (3-month moving-average CPI, robustness variant)
********************************************************************************

* cpi_ma3 is missing by design at the first/last month of every province x
* item_group series. If that makes either the numerator or denominator missing,
* the ratio (and therefore w_ref_ma3) is left missing for that row rather than
* silently falling back to the level CPI.
gen double cpi_factor_ma3 = 1
replace cpi_factor_ma3 = cpi_ma3_at_m_ms / cpi_ma3_at_ref if weighing_approach == 2
gen double w_ref_ma3 = corrected_weight * cpi_factor_ma3

count if weighing_approach == 2 & missing(cpi_factor_ma3)
di as result "--- Step 6 check: price-quantity rows with missing cpi_factor_ma3 ---"
di as result "  count: " r(N)

********************************************************************************
**# 7. Save
********************************************************************************

drop cpi_at_m_ms cpi_ma3_at_m_ms cpi_at_ref cpi_ma3_at_ref

local n_out = _N
di as result "Rows out: `n_out'"
assert `n_out' == `n_in' - `n_dropped'

save "${temp_in}\nsu_weights_restated.dta", replace

********************************************************************************
**# 8. Validation report
********************************************************************************

di as result "===================================================================="
di as result "VALIDATION SUMMARY"
di as result "===================================================================="
di as result "Rows in: `n_in'   Rows dropped: `n_dropped'   Rows out: `n_out'"

di as result "--- cpi_factor distribution, weighing_approach == 2 ---"
summarize cpi_factor if weighing_approach == 2, detail

count if weighing_approach == 2 & cpi_factor == 1
di as result "  cpi_factor exactly 1: " r(N)
count if weighing_approach == 2 & m_ms == tm(2026m4)
di as result "  rows weighed in 2026m4: " r(N)
* NOTE: these two counts need not match. cpi_factor == 1 whenever
* CPI(m_ms) == CPI(REF), which is guaranteed for m_ms == REF but can also occur
* when a province x item_group series happens to be flat between two months.
count if weighing_approach == 2 & cpi_factor == 1 & m_ms != tm(2026m4)
di as result "  of which cpi_factor == 1 despite m_ms != 2026m4 (flat CPI series between the two months, not an error): " r(N)
if r(N) > 0 {
    preserve
        keep if weighing_approach == 2 & cpi_factor == 1 & m_ms != tm(2026m4)
        contract pull_province item_group m_ms
        list pull_province item_group m_ms _freq, noobs
    restore
}

di as result "--- w_ref vs corrected_weight departure, price-quantity only ---"
gen double abs_pct_change = abs(100 * (w_ref - corrected_weight) / corrected_weight) if weighing_approach == 2
summarize abs_pct_change if weighing_approach == 2, detail
di as result "  median abs %% change: " r(p50)
di as result "  max abs %% change: " r(max)

di as result "--- cpi_factor == 1 check, other branches ---"
count if inlist(weighing_approach, 1, 3) & cpi_factor != 1
di as result "  rows with cpi_factor != 1 on approach 1/3 (expect 0): " r(N)
* Compare on non-missing values directly, and compare missingness separately --
* corrected_weight carries the extended missing code .c for a handful of rows;
* any arithmetic on it collapses to plain system-missing (.) in w_ref, so a raw
* w_ref != corrected_weight test would flag those rows as "different" even
* though both are, substantively, missing.
count if inlist(weighing_approach, 1, 3) & !missing(corrected_weight) & w_ref != corrected_weight
di as result "  rows with a genuine (non-missing) w_ref != corrected_weight mismatch on approach 1/3 (expect 0): " r(N)
count if inlist(weighing_approach, 1, 3) & missing(corrected_weight) != missing(w_ref)
di as result "  rows where missingness of w_ref disagrees with missingness of corrected_weight on approach 1/3 (expect 0): " r(N)

di as result "--- missing cpi_factor_ma3, price-quantity only ---"
count if weighing_approach == 2 & missing(cpi_factor_ma3)
di as result "  count: " r(N)

di as result "===================================================================="
di as result "Saved: ${temp_in}\nsu_weights_restated.dta"
di as result "===================================================================="
