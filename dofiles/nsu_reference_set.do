********************************************************************************
* nsu_reference_set.do        OUTCOME 1 -- the reference set
*
* Builds the lookup a future enumerator uses in the field: a respondent says
* "1 mango", the enumerator asks what size, and this table turns that into grams.
*
*   province x municipality x item x harmonized_nsu_unit x corrected_unit x size
*        ->  grams, n_g, d_thin
*
* NOTE THIS FILE IS OUTCOME 1 ONLY. Outcome 2 (retro-fitting PSPS) slices the same
* weighings differently and on a different grain, so it gets its own file. The two
* outputs are NOT derivable from one another -- a case with all three field labels
* but only a municipal median in the price file yields THREE sizes here and ONE
* weight in Outcome 2. That is the design, not an inconsistency.
*
*-------------------------------------------------------------------------------
* HOW MANY SIZES A CASE GETS
*-------------------------------------------------------------------------------
* Count the distinct S/M/L labels the FIELD actually recorded for the case. Three
* labels -> three sizes, two -> two, one -> one. The number of weighings does NOT
* enter. (An earlier version used a weighing-count ladder; it demoted 77 of the 553
* three-label cases that genuinely had all three sizes recorded.)
*
* Then pool across vendors, market types and the original labels, and re-cut the
* pooled weights into that many empirical groups. Re-terciling always runs, even
* where a case holds exactly one weighing per label: in 31 of those 33 cases the
* empirical order matches the field order so nothing changes, and in 2 it corrects
* a real inversion where a vendor's "medium" outweighed their "large". Publishing
* the field label unchanged would put M > L in the reference table.
*
* Per Oseni, Durazo & McGee (2017), sec 3 step 3 p.16 (docs/WB-NSU-Guide.pdf): a
* small in one market can outweigh a large in another, so sizes must be re-derived
* from the pooled distribution rather than taken from the labels.
*
*-------------------------------------------------------------------------------
* THE THREE WEIGHING APPROACHES
*-------------------------------------------------------------------------------
*   size-based       re-tercile as above; the k groups inherit the k field labels
*                    that were present, in order
*   price-quantity   the size is read off the price label, no re-terciling:
*                       mp25 -> small, mp50 -> medium, mp75 -> large
*                       municipality median / province median -> medium
*                    UNIQUE_MUN_PRICE IS EXCLUDED -- see below
*   conventional     no size to resolve; one row, the case median
*
* WHY unique_mun_price IS EXCLUDED. It is not a percentile of anything -- it is the
* raw observed price, recorded because the municipality had too few distinct prices
* to take quartiles. It has no position on a size ladder. In the price file it never
* appears alone (always alongside a province median), but 12 MS cases weighed ONLY
* at the unique price, so excluding it drops those 12 cases from this table
* entirely. That is intended. See docs/data_oddities.md.
*
* THE CARROT CASE. ILOILO/TIGBAUAN carrot is the one case whose harmonized cell
* contains both size-based and price-quantity weighings. Outcome 1 takes only its
* 9 size-based rows (this file), Outcome 2 takes only its 7 price-quantity rows.
* Its reference weight and its conversion weight therefore come from different
* observations and will not agree. Documented, deliberate.
*
*-------------------------------------------------------------------------------
* INPUT
*-------------------------------------------------------------------------------
* nsu_weights_restated.dta -- one row per weighing. Weights are read from
* corrected_weight, the weight as measured. The former w_ref -- a restatement of
* price-quantity weights into a single reference month -- is retired (issue #29), so
* there is one weight variable and no branch-specific handling of it.
********************************************************************************

clear all
set more off

global build "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs\master_rename_build"
global btemp   "${build}\temp"
global btables "${build}\tables"

local THIN = 3      // fewer than this many weighings behind an estimate -> d_thin


********************************************************************************
**# 1. Load, scope, and drop what Outcome 1 does not use
********************************************************************************

use "${btemp}\nsu_weights_restated.dta", clear
count
di as txt "weighings in: " r(N)

drop if missing(corrected_weight)
count
di as txt "  after dropping rows with no usable weight: " r(N)

* --- unique_mun_price is not a size. Exclude it (labels 10 and 11).
count if inlist(item_nsu_hetero_type, 10, 11)
di as res "unique_mun_price weighings excluded from Outcome 1: " r(N)
drop if inlist(item_nsu_hetero_type, 10, 11)

* --- the carrot: where a harmonized cell holds both branches, Outcome 1 keeps the
*     size-based rows only. Written as a general rule rather than hard-coding the
*     one case, so a future fold that creates another is handled the same way.
egen long cell = group(pull_province pull_municipal_city pull_item ///
                       harmonized_nsu_unit corrected_unit), label
bysort cell: egen byte has_size  = max(weighing_approach == 3)
bysort cell: egen byte has_price = max(weighing_approach == 2)
count if has_size & has_price & weighing_approach == 2
di as res "price-quantity rows dropped from mixed-branch cells: " r(N)
drop if has_size & has_price & weighing_approach == 2
drop has_size has_price

* cell ids may now be stale (cases can have emptied); rebuild
* NOTE: egen ..., label creates a value label named after the variable, so the
* old one has to go before the second call or egen errors with r(110)
drop cell
cap label drop cell
egen long cell = group(pull_province pull_municipal_city pull_item ///
                       harmonized_nsu_unit corrected_unit), label
egen byte tag_cell = tag(cell)
qui count if tag_cell
di as txt "cases entering Outcome 1: " r(N)


********************************************************************************
**# 2. The size a weighing belongs to
********************************************************************************
* Target variable is size_ord: 0 conventional, 1 small, 2 medium, 3 large.

label define szlbl 0 "conventional_nsu" 1 "small" 2 "medium" 3 "large", replace
gen byte size_ord = .


*-------------------------------------------------------------------------------
* 2a. CONVENTIONAL -- no size
*-------------------------------------------------------------------------------
replace size_ord = 0 if weighing_approach == 1


*-------------------------------------------------------------------------------
* 2b. PRICE-QUANTITY -- read the size off the price label
*-------------------------------------------------------------------------------
* A median is the MIDDLE of the price distribution, so it is a medium. Do NOT rank
* the points within the case instead: most price-quantity cases carry only a
* municipal or province median, and ranking would make every one of them a small.

replace size_ord = 1 if weighing_approach == 2 & item_nsu_hetero_type == 5   // mp25
replace size_ord = 2 if weighing_approach == 2 & item_nsu_hetero_type == 6   // mp50
replace size_ord = 3 if weighing_approach == 2 & item_nsu_hetero_type == 7   // mp75
replace size_ord = 2 if weighing_approach == 2 & inlist(item_nsu_hetero_type, 8, 9)


*-------------------------------------------------------------------------------
* 2c. SIZE-BASED -- re-tercile the pooled weights
*-------------------------------------------------------------------------------
* field label -> its natural position, used both to count how many labels the case
* holds and to decide which labels the empirical groups inherit
gen byte field_ord = .
replace field_ord = 1 if weighing_approach == 3 & item_nsu_hetero_type == 2   // small
replace field_ord = 2 if weighing_approach == 3 & item_nsu_hetero_type == 3   // medium
replace field_ord = 3 if weighing_approach == 3 & item_nsu_hetero_type == 4   // large
assert !missing(field_ord) if weighing_approach == 3

* k = how many DISTINCT field labels this case recorded
bysort cell field_ord: gen byte first_lbl = (_n == 1) if weighing_approach == 3
bysort cell: egen byte k_sizes = total(first_lbl)
label var k_sizes "distinct S/M/L labels the field recorded for this case"

* rank those labels 1..k in natural order, and remember which label sits at each
* rank -- so a case holding only {small, large} gives its lower group "small" and
* its upper group "large", not "small" and "medium"
bysort cell (field_ord): gen byte lbl_rank = sum(first_lbl) if weighing_approach == 3
forvalues j = 1/3 {
	bysort cell: egen byte ord_at`j' = max(cond(lbl_rank == `j', field_ord, .))
}

* cut points within the case, on the POOLED weights (across vendors, markets and
* the original labels)
egen double p33 = pctile(corrected_weight) if weighing_approach == 3, by(cell) p(33.3333)
egen double p66 = pctile(corrected_weight) if weighing_approach == 3, by(cell) p(66.6667)
egen double p50 = pctile(corrected_weight) if weighing_approach == 3, by(cell) p(50)

* THE TIE RULE, lower-inclusive:  g1: w <= cut1 | g2: cut1 < w <= cut2 | g3: w > cut2
* Weights are whole grams, so ties on a cut point are common and a group can come
* back empty. That is detected in section 3 and the case is reported, not patched.
gen byte grp = .
replace grp = 1 if weighing_approach == 3 & k_sizes == 3 & corrected_weight <= p33
replace grp = 2 if weighing_approach == 3 & k_sizes == 3 & corrected_weight >  p33 & corrected_weight <= p66
replace grp = 3 if weighing_approach == 3 & k_sizes == 3 & corrected_weight >  p66
replace grp = 1 if weighing_approach == 3 & k_sizes == 2 & corrected_weight <= p50
replace grp = 2 if weighing_approach == 3 & k_sizes == 2 & corrected_weight >  p50
replace grp = 1 if weighing_approach == 3 & k_sizes == 1

* the g-th empirical group inherits the g-th field label the case actually holds
forvalues j = 1/3 {
	replace size_ord = ord_at`j' if weighing_approach == 3 & grp == `j'
}

assert !missing(size_ord)
label values size_ord szlbl


********************************************************************************
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


********************************************************************************
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
