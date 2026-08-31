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

local THIN = 3      // fewer than this many weighings behind an estimate -> d_thin

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

collapse (median) grams = corrected_weight (count) n_g = corrected_weight (first) weighing_approach, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
            corrected_unit size_ord)

label values size_ord szlbl
gen byte d_thin = n_g < `THIN'

label var grams  "reference weight: median grams (or mL) for one unit of this size"
label var n_g    "weighings behind this estimate"
label var d_thin "1 = fewer than 3 weighings behind the estimate; treat as uncertain"
label var size_ord "size"

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
