********************************************************************************
* 07_cpi_factor.do
*
* Builds cpi_factor: the province x item-group CPI ratio that Outcome 2 uses to move a
* price-quantity weight from its market-survey month to the PSPS interview month.
*
* WHAT THIS FILE NO LONGER DOES
* It used to also restate every price-quantity weight into a common reference month
* (w_ref = corrected_weight * cpi_factor), so weighings from 2026m3 / m4 / m5 could be
* pooled without the pool itself carrying the month's price level. That step is RETIRED
* (issue #29): the market survey visits a municipality across at most a few months and
* the factor is constant within 93% of price-quantity cases, so the restatement moved
* 399 of 1,118 rows and only 84 of them by more than 5%. Weights are now carried as
* measured, in corrected_weight, and the ONLY inflation adjustment performed is the
* MS -> PSPS one, applied at the point of use.
*
* WHY cpi_factor IS EXACTLY 1 ON TWO OF THE THREE BRANCHES
* This is the substantive content of the file, so it is worth stating plainly.
*
*   price-quantity (weighing_approach == 2)   cpi_factor varies
*       The enumerator was handed a FIXED preloaded peso amount and bought whatever it
*       bought. The grams recorded are therefore a function of the price level in the
*       month of that vendor visit: the same PHP 50 buys less cabbage in a dearer
*       month. Comparing such a weight to a PSPS household's purchase in a different
*       month requires adjusting for the price level between the two.
*
*   size-based (== 3) and conventional (== 1)   cpi_factor == 1, exactly
*       No peso amount was involved. The enumerator asked for a small / medium / large
*       unit, or for one conventional unit, and weighed the object handed over. A
*       medium mango's grams are a property of the mango, not of what a fixed sum
*       happened to buy that month. There is no price level in the measurement, so
*       there is nothing for an index to adjust. Setting cpi_factor = 1 on these rows
*       is not a default or a placeholder -- it is the statement that inflation does
*       not enter.
*
* This mirrors assumptions 2 and 3 in docs/conversion_factor_methodology.md, which are
* deliberate mirror images: the price-quantity branch assumes the PRICE schedule moved
* only with the index; the size-based branch assumes the QUANTITY schedule did not move
* at all (no shrinkflation). Neither branch is assumption-free, and they do not lean on
* the same thing.
*
* The reference month used to build the ratio is REF = 2026m4, the modal market-survey
* month. Downstream the pipeline multiplies by CPI(REF)/CPI(m_PSPS), so REF cancels
* algebraically -- it is a bookkeeping anchor, not a modelling choice.
*
* No row is dropped for inflation reasons; every input row survives into the output
* (less the 98 rows excluded in step 1 below -- 95 vendor-priced rows are
* identified there, of which some are kept, and two further rules drop more;
* the net is 98).
*
* INPUTS  (read only)
*   outputs/build/temp/nsu_data_master.dta   11,433 weighings
*   outputs/tables/cpi_level_panel.csv                      2,250 rows
*   outputs/tables/cpi_item_crosswalk.csv                       95 rows
*
* OUTPUT
*   outputs/build/temp/nsu_weighings_cpi.dta
*
* Run as a fresh isolated batch process:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\07_cpi_factor.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

* this file's own alias for the build temp folder
global temp_in "${btemp}"

local ref_month = tm(2026m4)

****************************************************************************************************
* WHY THIS FILE STILL EXISTS, GIVEN w_ref IS RETIRED
*
* It used to restate every weighing into a single reference month (w_ref =
* corrected_weight * cpi_factor). That column is gone (issue #29) and the output is
* no longer called "restated". Two things this file does are still load-bearing:
*
*   1. IT DROPS 98 ROWS. The vendor-priced price-quantity rule (section 1) is the
*      only place that happens, and BOTH outcomes depend on it. Skipping this file
*      does not just cost cpi_factor -- it silently readmits 98 weighings whose
*      recorded price was not the price the enumerator handed over.
*
*   2. IT BUILDS cpi_factor. Outcome 2 needs it for the MS -> PSPS adjustment: a
*      fixed peso amount buys different grams in different months, so price-quantity
*      weighings have to be put in one price frame before they can be compared.
*      cpi_factor == 1 on the conventional and size-based branches BY CONSTRUCTION,
*      because no peso amount entered those measurements -- asserted in section 8.
*
* The output is nsu_weighings_cpi.dta: the weighings both outcomes work from, scoped
* and carrying cpi_factor. Nothing in it is restated.
*
* ROW ORDER WAS NOT DETERMINISTIC -- FIXED, and worth knowing why.
*
* Running this file on its own and running it from master_outcome1.do produced the
* same 11,355 rows with the same values in a DIFFERENT order. Since Stata 13 `sort'
* places tied observations in a random order drawn from the sort seed, and every
* `bysort' and `merge' below sorts on keys that do not uniquely identify a row.
*
* Two changes fixed it: 00_globals.do pins `set sortseed', and this file sorts on
* `id' (unique) immediately before saving, so no ties are left for the seed to break.
* Verified: standalone and from-master now agree byte for byte including order.
*
********************************************************************************

************************************************************
**# 0. Load
********************************************************************************

use "${temp_in}\nsu_data_master.dta", clear
local n_in = _N
di as result "Rows in: `n_in'"

* Tripwire on the input row count. It is NOT a constant of nature -- it is the
* arithmetic below -- so when it fires, check that arithmetic before changing it.
*
*     11,494  raw MS weighings after comment handling
*     -   58  non-NSU labels (standard quantity / ambiguous quantity / not a unit),
*             excluded in 03_clean_ms.do before the crosswalk merge
*     -    3  dropped later in 03_clean_ms.do
*     ------
*     11,433
*
* Was 11,449 until five labels that had reached the published reference set as
* harmonized units were dropped -- a bare "10", "3 for 25 pesos (putos)",
* "pack 25 per pack in the market", "1.3 galon" and "6 bottles of redhorse". They
* carry 16 MS weighings between them: 3 for the bare "10", 4 for
* "3 for 25 pesos (putos)", 5 for "pack 25 per pack in the market", 1 for
* "1.3 galon" and 3 for "6 bottles of redhorse". Found by reading the published
* deliverable, not the label list; see 02_drop_non_nsu_labels.py EXACT.
*
* The "1.3 galon" row is worth knowing about: its RAW spelling carries a non-ASCII
* character, so it is invisible to a plain text search for "galon" in the launch file
* and only matches after nsu_normalize strips the accent. Reconcile this arithmetic
* against the drop_reason tab in the log, never against a text search.
*
* Was 11,453 before that, until the ILOILO / DUEAS cabbage label was excluded. The four are the
* weighings labelled "2 kapinutos nga cabbage/20pesos" -- a label that bundles a
* count, the item name and a price, so what one unit IS cannot be recovered. It is
* an exact-match literal in 02_drop_non_nsu_labels.py's AMBIGUOUS set, and dropping
* it is what resolved the size-based cell with no price row (issue #22).
*
* Was 11,458 before that. The five are the ANTIQUE / HAMTIC mineral-water
* weighings labelled "500" -- an ambiguous quantity. They used to slip through
* because the old substring rule looked for a unit ("ml", "kg", "kilo") and "500"
* has none; the crosswalk now classifies them explicitly.
*
* If this fires: read the attrition figures in dofiles/03_clean_ms.log and find
* which stage moved. Do NOT just update the number -- that is how a silent drop
* becomes permanent.
local n_expected = 11433
if `n_in' != `n_expected' {
	di as error "Input row count moved: expected `n_expected', got `n_in'."
	di as error "Reconcile against 03_clean_ms.log before touching this number."
	assert `n_in' == `n_expected'
}

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
    keep pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit item_nsu_hetero_type
    duplicates drop
    bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: gen n_rungs_before = _N
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

* --- FIRST: rows where the vendor gave NO price at all --------------------------
* approx_price == 1 means the vendor said the item was unavailable at the preloaded
* price and offered no replacement. There is no valid p_r for that weighing and no
* way to recover one -- the grams recorded do not correspond to the preloaded peso
* figure. Drop them.
*
* THIS MUST RUN BEFORE has_preloaded IS COMPUTED. 26 of the 27 carry no
* actual_price, so they would otherwise count as "preloaded" rows and wrongly
* protect their case from the rescue rule below.
count if weighing_approach == 2 & approx_price == 1
di as result "no-price rows dropped (approx_price == 1): " r(N)
drop if weighing_approach == 2 & approx_price == 1

* --- THEN the rescue rule -------------------------------------------------------
* GRAIN: corrected_unit MUST be in the key. Without it the rule runs on a coarser
* grain than the case grain it protects, and a cell can be judged "safe" because its
* SIBLING dimension held a preloaded row. That is not hypothetical: it dropped the
* only price-quantity row of NEGROS OCCIDENTAL / ENRIQUE B. MAGALONA / ice cream /
* putos / mL because the g sub-cell was fine, deleting the mL cell -- exactly the
* loss this rule exists to prevent.
gen byte n_pre = (weighing_approach == 2 & missing(actual_price))
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
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
    keep pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit item_nsu_hetero_type
    duplicates drop
    gen byte rung_after = 1
    tempfile after_rungs
    save "`after_rungs'"
restore

preserve
    use "`before_rungs'", clear
    merge 1:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit item_nsu_hetero_type using "`after_rungs'"
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

* ---- ASCII-SAFE JOIN KEY -------------------------------------------------------
* item_group is a COICOP label, and 189 weighings carry
*     "11.1.1 - Restaurants, cafe and the like (S)"
* where the "e" is an e-acute (UTF-8 C3 A9). It used to be the merge key against the
* CPI panel below. Both sides are written by 06_cpi_panel.do so they matched byte for
* byte, but nothing made that robust: re-encode or hand-edit either CSV and the join
* drops those rows.
*
* Worse, the post-merge assertions covered `weighing_approach == 2' only, and all 189
* of those rows are approach 3 -- so the one guard that would have noticed excluded
* exactly the rows at risk. They would have come out with a missing cpi and no error.
*
* Every one of the 16 item_group values begins with a distinct COICOP code
* (01.1.1.12, 11.1.1, ...) containing nothing but digits and dots. Joining on the code
* removes the exposure at source rather than guarding against it: no non-ASCII
* character is in the key at all. item_group is kept for readability.
gen str24 item_group_code = ""
quietly replace item_group_code = ustrregexs(1) if ustrregexm(item_group, "^([0-9]+(\.[0-9]+)*)")

* If this fires, an item_group arrived without a leading code and the join key cannot
* be built. Fix the label in cpi_item_crosswalk.csv; do not fall back to merging on
* the label, which is what this replaced.
count if mi(item_group_code) & !mi(item_group)
if r(N) > 0 {
	di as error "`r(N)' row(s) have an item_group with no leading COICOP code:"
	levelsof item_group if mi(item_group_code) & !mi(item_group), clean
	exit 459
}

********************************************************************************
**# 4. Join the CPI level at m_ms and at REF
********************************************************************************

preserve
    import delimited "${tables}\cpi_level_panel.csv", clear varnames(1) encoding("utf-8")
    * same ASCII-safe key as the master side -- see the note above
    gen str24 item_group_code = ""
    quietly replace item_group_code = ustrregexs(1) if ustrregexm(item_group, "^([0-9]+(\.[0-9]+)*)")
    assert !mi(item_group_code)
    * the code must identify a panel row as tightly as the label did
    isid province item_group_code mdate
    rename province pull_province
    keep pull_province item_group_code mdate cpi cpi_ma3
    tempfile cpi_panel
    save "`cpi_panel'"
restore

* --- CPI at the weighing's own month ---
gen mdate = m_ms
format mdate %tm
merge m:1 pull_province item_group_code mdate using "`cpi_panel'", keep(1 3) keepusing(cpi cpi_ma3) gen(_merge_ms)
rename cpi     cpi_at_m_ms
rename cpi_ma3 cpi_ma3_at_m_ms

count if weighing_approach == 2 & _merge_ms == 1
di as result "--- Step 4 check: price-quantity rows unmatched at m_ms ---"
di as result "  unmatched: " r(N)
if r(N) > 0 {
    list id pull_province item_group m_ms if weighing_approach == 2 & _merge_ms == 1, noobs
}
* WIDENED past approach 2. It used to read `weighing_approach != 2 | _merge_ms == 3',
* which let approach 1 and 3 rows go unmatched in silence -- and cpi_factor is built for
* all three approaches, so an unmatched row there is a missing factor, not a no-op.
assert _merge_ms == 3
drop mdate _merge_ms

* --- CPI at the reference month ---
gen mdate = `ref_month'
format mdate %tm
merge m:1 pull_province item_group_code mdate using "`cpi_panel'", keep(1 3) keepusing(cpi cpi_ma3) gen(_merge_ref)
rename cpi     cpi_at_ref
rename cpi_ma3 cpi_ma3_at_ref

count if weighing_approach == 2 & _merge_ref == 1
di as result "--- Step 4 check: price-quantity rows unmatched at REF ---"
di as result "  unmatched: " r(N)
if r(N) > 0 {
    list id pull_province item_group if weighing_approach == 2 & _merge_ref == 1, noobs
}
* WIDENED past approach 2, same reason as at m_ms above.
assert _merge_ref == 3
drop mdate _merge_ref

* The code was only ever a join key. item_group itself stays, so nothing a reader
* needs is lost, and dropping it keeps this fix invisible in every saved output.
drop item_group_code

********************************************************************************
**# 5. cpi_factor (level CPI)
********************************************************************************

* cpi_factor is KEPT: Outcome 2 needs it to move a price-quantity weight from its MS
* month to the PSPS interview month.
*
* w_ref -- corrected_weight * cpi_factor -- is RETIRED (issue #29). It restated every
* price-quantity weight into one reference month so the MS was internally comparable.
* That step is withdrawn: weights are now carried as weighed, and the only inflation
* adjustment performed is the MS -> PSPS one, at the point of use. Downstream code
* reads corrected_weight directly.

* Exactly 1 on approach 1 and 3 by construction, and that is a claim, not a default:
* no peso amount entered those measurements, so no index applies. See the header.
gen double cpi_factor = 1
replace cpi_factor = cpi_at_m_ms / cpi_at_ref if weighing_approach == 2

********************************************************************************
**# 6. cpi_factor_ma3 (3-month moving-average CPI, robustness variant)
********************************************************************************

* cpi_ma3 is missing by design at the first/last month of every province x
* item_group series. If that makes either the numerator or denominator missing, the
* ratio is left missing for that row rather than silently falling back to the level
* CPI. Kept alongside cpi_factor as the robustness variant; w_ref_ma3 is retired with
* w_ref (issue #29).
gen double cpi_factor_ma3 = 1
replace cpi_factor_ma3 = cpi_ma3_at_m_ms / cpi_ma3_at_ref if weighing_approach == 2

* Report WHICH months are missing, not just how many rows. A bare count reads like
* scattered edge cases, and cpi_ma3 IS missing at series endpoints by design, so a count
* alone is indistinguishable from that expected trickle. It is not a trickle: every one
* of these rows is in a single interview month, which means the ma3 robustness variant
* is unavailable for that ENTIRE wave rather than thinned at its edges. Anyone reading
* cpi_factor_ma3 as a sensitivity check needs to know that before running it.
count if weighing_approach == 2 & missing(cpi_factor_ma3)
local n_ma3_miss = r(N)
di as result "--- Step 6 check: price-quantity rows with missing cpi_factor_ma3 ---"
di as result "  count: `n_ma3_miss'"
if `n_ma3_miss' > 0 {
	qui levelsof m_ms if weighing_approach == 2 & missing(cpi_factor_ma3), local(ma3_months)
	local n_months : word count `ma3_months'
	di as result "  affected interview months (`n_months'):"
	foreach m of local ma3_months {
		qui count if weighing_approach == 2 & missing(cpi_factor_ma3) & m_ms == `m'
		di as result "    " %tm `m' "   " r(N) " rows"
	}
	qui count if weighing_approach == 2
	di as result "  of `r(N)' price-quantity rows in total"
	if `n_months' == 1 {
		di as result "  ONE month accounts for all of them: the ma3 variant is"
		di as result "  unavailable for that whole wave, not thinned at series endpoints."
	}
}

********************************************************************************
**# 7. Save
********************************************************************************

drop cpi_at_m_ms cpi_ma3_at_m_ms cpi_at_ref cpi_ma3_at_ref

local n_out = _N
di as result "Rows out: `n_out'"
assert `n_out' == `n_in' - `n_dropped'

* Deterministic row order: `id' is unique, so this leaves no ties for the sort
* seed to break. Without it the saved file's ORDER varies between runs.
sort id

save "${temp_in}\nsu_weighings_cpi.dta", replace

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

di as result "--- how far cpi_factor departs from 1, price-quantity only ---"
* Reported so the size of the MS -> PSPS adjustment stays visible even though no
* weight is restated any more.
gen double abs_pct_change = abs(100 * (cpi_factor - 1)) if weighing_approach == 2
summarize abs_pct_change if weighing_approach == 2, detail
di as result "  median abs %% change: " r(p50)
di as result "  max abs %% change: " r(max)

di as result "--- cpi_factor == 1 check, other branches ---"
* ASSERTED, not merely counted (issue #27 item 8). cpi_factor == 1 on the
* conventional and size-based branches is not an observation about this run -- it is
* the definition of those branches. No peso amount entered either measurement, so
* there is no price frame to move a weight between: the enumerator asked for a small
* or handed over nothing at all. A non-1 factor there would mean an inflation
* adjustment had been applied to a weight that was never denominated in money, and
* with w_ref retired this invariant is the only thing left guarding that.
count if inlist(weighing_approach, 1, 3) & cpi_factor != 1
di as result "  rows with cpi_factor != 1 on approach 1/3 (expect 0): " r(N)
if r(N) > 0 {
	di as error "cpi_factor != 1 on a conventional or size-based row."
	di as error "No price entered those measurements, so no adjustment applies."
	assert r(N) == 0
}

di as result "--- missing cpi_factor_ma3, price-quantity only ---"
count if weighing_approach == 2 & missing(cpi_factor_ma3)
di as result "  count: " r(N)
di as result "  (month breakdown printed by the Step 6 check above)"

di as result "===================================================================="
di as result "Saved: ${temp_in}\nsu_weighings_cpi.dta"
di as result "===================================================================="
