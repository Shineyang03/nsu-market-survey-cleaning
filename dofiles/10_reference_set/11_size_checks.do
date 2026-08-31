********************************************************************************
* 11_size_checks.do -- does the size assignment hold up?
*
* Two checks on what 10 produced. Neither changes a row; this step is a
* CHECKPOINT, and it saves its input unchanged so the chain stays uniform.
*
*   1. Cases that filled fewer sizes than the field recorded. Weights are whole
*      grams, so vendors tie exactly on a cut point and a group comes back
*      empty. Reported, not patched -- see issue #3.
*   2. Field label against empirical size, for 3-label cases. This is the
*      EVIDENCE for re-terciling: if the two agreed, step 10 would be
*      redundant. Published as a crosstab rather than asserted.
*
* STEP 2 OF 3 in the Outcome 1 build. Run the three in order, or run
* master_outcome1.do, from the dofiles/ folder.
*   10_size_assignment.do        -> ref_10_sized.dta
*   11_size_checks.do            -> ref_11_checked.dta   (checkpoint, rows unchanged)
*   12_publish_reference_set.do  -> nsu_reference_set.dta / .xlsx
*
* INPUT   ${btemp}\ref_10_sized.dta
* OUTPUT  ${btemp}\ref_11_checked.dta        rows unchanged
*         ${btables}\ref_underfilled_sizes.xlsx
********************************************************************************

clear all
do "00_shared/00_globals.do"

use "${btemp}\ref_10_sized.dta", clear
count
di as txt "weighings in: " r(N)

label define szlbl 0 "conventional_nsu" 1 "small" 2 "medium" 3 "large", replace
label values size_ord szlbl
egen byte tag_cell = tag(cell)

************************************************************
**# 3. Cases that filled fewer sizes than the field recorded
********************************************************************************
* A case can hold three labels and still populate only two groups, when enough
* vendors report the same whole-gram weight and they all land on one side of a cut
* point. Report the sizes that really exist rather than an empty one.

bysort cell size_ord: gen byte tag_sz = (_n == 1)
bysort cell: egen byte n_filled = total(tag_sz)
count if tag_cell & weighing_approach == 3 & n_filled < k_sizes
di as res "size-based cases filling fewer sizes than the field recorded: " r(N)

preserve
	keep if tag_cell & weighing_approach == 3 & n_filled < k_sizes
	if _N > 0 {
		keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		     corrected_unit k_sizes n_filled
		export excel using "${btables}\ref_underfilled_sizes.xlsx", ///
			replace firstrow(variables)
	}
restore


********************************************************************************
**# 4. Diagnostic: do the field labels agree with the empirical sizes?
********************************************************************************
* The evidence for re-terciling. If the labels lined up with the pooled terciles
* this step would be redundant -- publish the crosstab rather than assert it.

preserve
	keep if weighing_approach == 3 & k_sizes == 3
	label values field_ord szlbl
	di as txt _n "field label (rows) vs empirical size (cols), 3-label cases"
	tab field_ord size_ord, row
restore


********************

********************************************************************************
**# save -- unchanged, this step only inspects
********************************************************************************

drop tag_sz n_filled tag_cell
compress
save "${btemp}\ref_11_checked.dta", replace
count
di as res "11_size_checks complete: " r(N) " weighings -> ref_11_checked.dta"
