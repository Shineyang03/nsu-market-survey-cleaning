********************************************************************************
* 12_publish_reference_set.do -- Outcome 1, the deliverable
*
* Collapses to one row per case x size and publishes it. The MEDIAN is taken
* within each group: the guidebook allows mean or median, and the median is
* robust to a single mis-keyed vendor the magnitude snap did not catch.
*
* d_thin marks a published value resting on fewer than THIN weighings. THIN = 3
* sits almost exactly on the median of n_g, so the flagged share is very
* sensitive to it -- n_g is published alongside so a reader can set their own
* cut. See issue #27 item 3.
*
* STEP 3 OF 3 in the Outcome 1 build. Run the three in order, or run
* master_outcome1.do, from the dofiles/ folder.
*   10_size_assignment.do        -> ref_10_sized.dta
*   11_size_checks.do            -> ref_11_checked.dta   (checkpoint, rows unchanged)
*   12_publish_reference_set.do  -> nsu_reference_set.dta / .xlsx
*
* INPUT   ${btemp}\ref_11_checked.dta
* OUTPUT  ${btemp}\nsu_reference_set.dta
*         ${btables}\nsu_reference_set.xlsx
********************************************************************************

clear all
do "00_shared/00_globals.do"

local THIN = ${THIN}      // ONE definition, in 00_globals.do -- do not retype the value

use "${btemp}\ref_11_checked.dta", clear
count
di as txt "weighings in: " r(N)

label define szlbl 0 "conventional_nsu" 1 "small" 2 "medium" 3 "large", replace
label values size_ord szlbl

************************************************************
**# 5. Collapse to the reference set
********************************************************************************
* MEDIAN within case x size. The guidebook allows mean or median; the median is
* robust to a single mis-keyed vendor the magnitude snap did not catch.

* `branch' and `d_reclassified' ride along so a published row can say WHY it is called
* medium. Without them a reclassified case is indistinguishable from a case the field
* actually recorded as medium, and #28's decision becomes invisible in the deliverable
* it changed. Both are constant within a case by construction -- 08_branch.do asserts no
* case mixes conventional with another approach internally -- so (first) is exact rather
* than a choice among differing values.
collapse (median) grams = corrected_weight (count) n_g = corrected_weight ///
         (first) weighing_approach branch d_reclassified, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
            corrected_unit size_ord)

********************************************************************************
**# 5b. FALLBACK LEVEL 1 -- a cell with any thin rung publishes one pooled weight
********************************************************************************
* THE RULE (issue #30, settled there). A size ladder cut from one or two weighings per
* rung is not a size distribution; it is noise with three labels on it. So where ANY rung
* in a cell is thin, the cell stops publishing per-rung weights and publishes a single
* median pooled across its rungs, at
*
*     province x municipality x item x harmonized_nsu_unit x corrected_unit
*
* WHOLE CELL, NOT THE THIN RUNGS ONLY, and that is the part worth understanding. Replacing
* only the thin rungs would leave one cell publishing `small' at its own median and
* `medium' at the cell-pooled median -- two different estimators inside one ladder, which
* can invert the size ordering. The monotonicity check further down exports exactly that
* as a defect, so a rung-by-rung rule would manufacture the failures it then reports.
*
* OUTCOME 1 STOPS HERE. It does not fall back to province x item, nor to item x unit. The
* reference set is the record of what was weighed in that cell; borrowing another
* municipality's weight into it changes what the table is. A cell with no weighing at all
* is absent from the table rather than imputed. Outcome 2's retrofit is where borrowing
* belongs, and its ladder continues past this point -- see 20_psps_retrofitting/
* 30_fallback.do.
*
* corrected_unit STAYS IN THE KEY. Pooling across rungs must never pool grams with
* millilitres.
*
* This does NOT rescue a thin cell, and must not be read as if it did: a cell whose rungs
* hold one weighing each pools to n_g = 2 and is still thin. It carries fallback_level = 1
* AND d_thin = 1, and both are published.
tempvar anythin
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	egen byte `anythin' = max(n_g < `THIN')

gen byte fallback_level = 0
replace  fallback_level = 1 if `anythin' == 1

qui count if fallback_level == 1
local n_pre = r(N)

* Re-collapse only the affected cells. The weighing-level median cannot be recovered from
* rung medians, so the pooled median is taken over the WEIGHINGS -- which is why this
* re-reads the pre-collapse data rather than averaging the rungs.
preserve
	keep if fallback_level == 1
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit
	duplicates drop
	tempfile thincells
	save "`thincells'"
restore

preserve
	use "${btemp}\ref_11_checked", clear
	merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		corrected_unit using "`thincells'", keep(3) nogen
	collapse (median) grams = corrected_weight (count) n_g = corrected_weight ///
	         (first) weighing_approach branch d_reclassified, ///
	         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	            corrected_unit)
	* NOT 0 -- that code already means "conventional_nsu" in szlbl, and a pooled row is
	* not a conventional unit. 4 is a distinct code, added to the label below.
	*
	* Safe against the monotonicity check further down, which compares grams across
	* consecutive size_ord within a cell: a pooled cell holds exactly ONE row, since its
	* per-rung rows are dropped above, so `_n > 1' is never true for it and no comparison
	* is attempted. If that check is ever rewritten to compare across cells, this needs
	* an explicit exclusion.
	gen byte size_ord = 4
	gen byte fallback_level = 1
	tempfile pooled
	save "`pooled'"
restore

drop if fallback_level == 1
append using "`pooled'"
drop `anythin'

qui count if fallback_level == 1
di as res _n "fallback level 1 (cell pooled across rungs): " r(N) " cell(s), from " ///
	"`n_pre' per-rung row(s)"
qui count if fallback_level == 1 & n_g < `THIN'
di as res "  of those, still thin after pooling: " r(N) ///
	" -- Outcome 1 has no further level, so they publish flagged"

* Code 4 carries the pooled rows created above; see the note there for why not 0.
label define szlbl 0 "conventional_nsu" 1 "small" 2 "medium" 3 "large" ///
	4 "pooled across sizes", replace
label values size_ord szlbl
gen byte d_thin = n_g < `THIN'

* ONE definition, in 00_globals.do, shared with the Outcome 2 ladder. Outcome 1 only ever
* uses codes 0 and 1, but it carries the same label set so the flag reads identically
* across the two deliverables.
def_fallback_level
label values fallback_level fallback_lbl
label var fallback_level "how this weight was arrived at; 0 = the cell's own size rung"

label var grams  "reference weight: median grams (or mL) for one unit of this size"
label var n_g    "weighings behind this estimate"
label var d_thin "1 = fewer than 3 weighings behind the estimate; treat as uncertain"
label var size_ord "size"

* EVERY exported column needs a label, because the export below uses
* firstrow(varlabels): an unlabelled variable falls back to its raw variable name, and a
* variable the collapse labelled keeps whatever the collapse wrote. This is a
* field-facing lookup table, and it was going out with three columns headed pull_item /
* pull_province / pull_municipal_city and a fourth headed "(first) weighing_approach" --
* collapse syntax leaking into a deliverable.
* Both new columns need a label for the same reason as the rest: the export uses
* firstrow(varlabels), so an unlabelled variable ships under its raw variable name.
label values branch branchlbl
label var branch         "how this row was PROCESSED (see weighing_approach for the field record)"
label var d_reclassified "1 = field-conventional, published size-based; its item x unit mixes approaches"
label var pull_item           "item"
label var pull_province       "province"
label var pull_municipal_city "municipality"
label var weighing_approach   "how this weight was measured in the field"

* Decoded, for the same reason size_ord is. These two sit side by side in the exported
* sheet, and size_ord was already exporting as "small"/"medium"/"large" while
* weighing_approach exported as a bare 1/2/3 with nothing in the file to decode it.
* Nothing reads this workbook programmatically -- it is read by people.
label define walbl 1 "conventional" 2 "price-quantity" 3 "size-based", replace
label values weighing_approach walbl

* grams must rise with size within a case, or the table is visibly wrong to a user
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
       corrected_unit (size_ord): gen byte nonmono = (grams < grams[_n-1]) if _n > 1 & size_ord > 0
count if nonmono == 1
di as res "size pairs where grams FALLS as size rises: " r(N)
if r(N) > 0 {
	export excel using "${btables}\ref_nonmonotonic.xlsx" if nonmono == 1, ///
		replace firstrow(variables)
}
drop nonmono

compress
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit size_ord
save "${btemp}\nsu_reference_set.dta", replace
export excel using "${btables}\nsu_reference_set.xlsx", replace firstrow(varlabels)


********************************************************************************
**# 6. Report
********************************************************************************

count
di as res _n "reference-set rows: " r(N)
di as txt _n "rows by size:"
tab size_ord, m
di as txt _n "rows by weighing approach:"
tab weighing_approach, m
di as txt _n "thin estimates (n_g < `THIN'):"
tab d_thin, m
qui su n_g, detail
di as txt "weighings behind an estimate -- min `r(min)', p25 `r(p25)', median `r(p50)', max `r(max)'"

di as res _n "OUTCOME 1 complete."
