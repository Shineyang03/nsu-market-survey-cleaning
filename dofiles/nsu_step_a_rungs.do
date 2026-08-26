********************************************************************************
********************************************************************************
**                                                                            **
**   SUPERSEDED -- DO NOT RUN, DO NOT BUILD ON, DO NOT COPY FROM              **
**                                                                            **
**   Kept only as a record of an approach that was tried and rejected.        **
**   Its output (nsu_rungs.dta) is stale and nothing downstream reads it.     **
**                                                                            **
********************************************************************************
********************************************************************************
*
* REPLACED BY
*   dofiles/nsu_reference_set.do     Outcome 1, the reference set (built, live)
*   dofiles/<not yet written>        Outcome 2, PSPS conversion factors
*
* WHY IT WAS REJECTED -- three things in this file are now known wrong:
*
* 1. THE GROUP COUNT COMES FROM THE WRONG EVIDENCE. This file sets the number of
*    groups from the WEIGHING COUNT (the MIN3=6 / MIN2=3 ladder below). Neither
*    outcome uses the weighing count. Outcome 1 counts the distinct S/M/L labels
*    the field recorded; Outcome 2 reads the price file's point structure. The
*    ladder here demoted 77 of the 553 cases that genuinely had all three sizes
*    recorded.
*
* 2. THE SHARED-FILE PREMISE IS WRONG. This file assumes one rung resolution can
*    serve both deliverables. It cannot: they slice the same weighings by
*    different evidence and on different grains, so the same case can yield three
*    sizes in Outcome 1 and one weight in Outcome 2. The two outputs are not
*    derivable from one another.
*
* 3. IT DOES NOT EXCLUDE unique_mun_price from Outcome 1, and it predates the
*    decision to drop the 12 cases that weighed only at a unique price.
*
* WHAT IS STILL WORTH READING HERE
*   The tie-rule discussion in section 3a and the empty-group handling in
*   section 4 carried over to nsu_reference_set.do largely intact. The
*   terminology did not: "rung" was replaced project-wide by "hetero-group",
*   matching item_nsu_hetero_type in the data.
*
* See docs/conversion_factor_methodology.md ("Degrading gracefully") for the
* superseded rule recorded in full, and docs/data_oddities.md for the one-off
* cases.
*
********************************************************************************
* ORIGINAL HEADER FOLLOWS -- describes the rejected design, not current practice
********************************************************************************
* nsu_step_a_rungs.do
*
* STEP A -- resolve every case into an ordinal ladder of "rungs", and give each
* rung a representative weight w_r.
*
* This file is SHARED. Both deliverables consume its output:
*   Outcome 1 (reference set)      -> reports w_r directly as grams per unit
*   Outcome 2 (PSPS conversion)    -> pairs w_r with a price to build CF
* If each of those terciled independently they would drift at the cut points and
* the two tables would silently disagree. There is exactly ONE tercile rule and
* it lives here.
*
*-------------------------------------------------------------------------------
* WHAT A "RUNG" IS
*-------------------------------------------------------------------------------
* A rung is an ordinal position on a smallest-to-largest ladder, r in {1,2,3}.
* It is NOT the same observable on every branch -- that is the whole subtlety:
*
*   size-based (wa==3)      a rung is a WEIGHT TERCILE. The survey's own S/M/L
*                           labels are discarded and re-derived from the pooled
*                           weight distribution, because a "small" in one market
*                           can outweigh a "large" in another. This is the only
*                           step in the pipeline that overrides a substantive
*                           field judgement rather than repairing a recording
*                           error. Follows Oseni, Durazo & McGee (2017), "The Use
*                           of Non-Standard Units for the Collection of Food
*                           Quantity", sec 3 step 3 p.16 (docs/WB-NSU-Guide.pdf).
*
*   price-quantity (wa==2)  a rung is a PRICE POINT the enumerator was sent to.
*                           NOT re-terciled -- the ladder is already given by the
*                           preloaded price, so re-deriving it would throw away
*                           the design. Rungs are ranked by pull_price.
*
*   conventional (wa==1)    no size to resolve. One rung per case.
*
*-------------------------------------------------------------------------------
* GRAIN
*-------------------------------------------------------------------------------
* case = pull_province x pull_municipal_city x pull_item x harmonized_nsu_unit
*                       x corrected_unit
*
* Two parts of that are load-bearing:
*   harmonized_nsu_unit, not cleaned or raw -- it is the pooling key. See
*     docs/master_rename.md.
*   corrected_unit MUST be in the grain. Two items (ice cream, drinks at
*     restaurant) are recorded in both grams and millilitres. Pooling mass with
*     volume would produce a meaningless distribution, so they deliberately get
*     one set of conversion factors per dimension. Cost of that split is measured
*     in docs/data_oddities.md sec 4.
*
* We POOL ACROSS vendor_id, market_type and item_nsu_hetero_type (the original
* S/M/L labels). Market type is pooled across for BOTH outcomes -- it is not in
* Outcome 1's key, see conversion_factor_methodology.md.
*
*-------------------------------------------------------------------------------
* INPUT
*-------------------------------------------------------------------------------
* nsu_weights_restated.dta, from dofiles/nsu_restate_weights.do.
*
* We aggregate w_ref, NOT corrected_weight. On the price-quantity branch a fixed
* peso amount buys different grams in different months, so weighings must be put
* in one price frame before a median over vendors is meaningful. On the other two
* branches w_ref == corrected_weight by construction (the restatement is a no-op
* there), so using w_ref everywhere is safe and keeps one weight variable.
*
* The 95 vendor-priced rows are already dropped upstream -- see data_oddities.md
* sec 3.
********************************************************************************

clear all
set more off

global build "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs\master_rename_build"
global btemp   "${build}\temp"
global btables "${build}\tables"

* the degradation ladder: how many rungs a cell's weight distribution can support
local MIN3 = 6    // >= 6 weighings -> three terciles (~2 obs per tercile)
local MIN2 = 3    // 3-5 weighings  -> median split, two sizes
                  // < 3 weighings  -> one case-level scalar
* NOTE: 6 and 3 are judgement, not guidance from the LSMS guidebook. They are
* here as named locals so a sensitivity run is a one-line change.


********************************************************************************
**# 1. Load and scope
********************************************************************************

use "${btemp}\nsu_weights_restated.dta", clear

count
di as txt "weighings in: " r(N)

* A weighing with no usable weight cannot inform a tercile. Keep the row out of
* the pooling but report how many we lost and from where.
count if missing(w_ref)
di as txt "weighings with no w_ref (excluded from pooling): " r(N)
drop if missing(w_ref)

* Guard: w_ref must be strictly positive. Zero weight is the survey's code for
* "item not observed at the requested price/size" and should already be .c --
* see data_oddities.md sec 2. If any survive, halt rather than let a zero drag a
* tercile boundary to the floor.
count if w_ref <= 0
assert r(N) == 0


********************************************************************************
**# 2. Define the case
********************************************************************************

egen long cell = group(pull_province pull_municipal_city pull_item ///
                       harmonized_nsu_unit corrected_unit), label
label var cell "case: prov x mun x item x harmonized NSU x g/mL"

egen byte tag_cell = tag(cell)
qui count if tag_cell
di as txt "cases: " r(N)

* weighings per case, and the branch (verified single-valued per case at the
* cleaned grain; the one harmonized-level exception is the TIGBAUAN carrot, which
* resolves itself here because Outcome 1 only ever sees its size-based rows --
* see data_oddities.md sec 1)
bysort cell: gen int n_cell = _N
label var n_cell "weighings pooled in this case"

* one marker per distinct field label within a case, used below to count how many
* different price points / size labels the case actually contains
egen byte tag_lbl = tag(cell item_nsu_hetero_type)
label var tag_lbl "1 = first weighing of this field label within the case"


********************************************************************************
**# 3. Rung assignment, by branch
********************************************************************************

gen byte rung     = .
gen byte n_target = .        // how many rungs the ladder AIMED at
label var rung     "ordinal rung, 1 = smallest/cheapest"
label var n_target "rungs targeted before checking whether any came back empty"


*-------------------------------------------------------------------------------
* 3a. SIZE-BASED -- re-tercile from the pooled weight distribution
*-------------------------------------------------------------------------------
* egen pctile computes the cut points WITHIN cell, so every cell gets its own
* boundaries. This is the point of the exercise: sizes are local.

egen double p33 = pctile(w_ref) if weighing_approach == 3, by(cell) p(33.3333)
egen double p66 = pctile(w_ref) if weighing_approach == 3, by(cell) p(66.6667)
egen double p50 = pctile(w_ref) if weighing_approach == 3, by(cell) p(50)

replace n_target = 3 if weighing_approach == 3 & n_cell >= `MIN3'
replace n_target = 2 if weighing_approach == 3 & inrange(n_cell, `MIN2', `MIN3'-1)
replace n_target = 1 if weighing_approach == 3 & n_cell <  `MIN2'

* THE TIE RULE, stated explicitly because it is the main failure mode.
* Weights are recorded to the whole gram, so many observations sit exactly ON a
* cut point. The rule is lower-inclusive:
*       rung 1 : w <= p33
*       rung 2 : p33 <  w <= p66
*       rung 3 : w >  p66
* Consequence to watch: if enough observations tie at p66, rung 3 comes back
* EMPTY and the cell has only two populated rungs despite targeting three. That
* is detected in section 4 and the cell is demoted rather than shipped with a
* phantom rung.

replace rung = 1 if weighing_approach == 3 & n_target == 3 & w_ref <= p33
replace rung = 2 if weighing_approach == 3 & n_target == 3 & w_ref >  p33 & w_ref <= p66
replace rung = 3 if weighing_approach == 3 & n_target == 3 & w_ref >  p66

* two-size fallback: median split. The guidebook explicitly authorises this --
* "Some units may only be found in two relatively uniform sizes, in which case
* only small and large size should be assigned" (p.16).
replace rung = 1 if weighing_approach == 3 & n_target == 2 & w_ref <= p50
replace rung = 3 if weighing_approach == 3 & n_target == 2 & w_ref >  p50
* NOTE rung 3, not 2 -- on a two-rung ladder the pair is small/large, so keeping
* the codes at the ends preserves the ordinal meaning of the number.

* one-scalar fallback
replace rung = 1 if weighing_approach == 3 & n_target == 1


*-------------------------------------------------------------------------------
* 3b. PRICE-QUANTITY -- the ladder is the price, already given
*-------------------------------------------------------------------------------
* These cases are NOT re-terciled. The enumerator was sent to a specific price
* point, so the ladder already exists; re-deriving it would throw away the design.
*
* WHAT THE PRICE POINT MEANS AS A SIZE. The label says where in the PSPS price
* distribution the point sits, and that IS the size claim:
*
*       mp25_price          -> rung 1   small
*       mp50_price          -> rung 2   medium
*       mp75_price          -> rung 3   large
*       municipality median -> rung 2   medium   (a median IS the middle)
*       province median     -> rung 2   medium
*
* DO NOT rank the points within the case instead. Ranking looks equivalent but
* is not: 845 weighings sit in cases whose ONLY point is a municipality or
* province median, and ranking would make each of them rung 1 (small) when the
* whole meaning of a median is that it is the middle. That mis-sizes 470
* mun_median + 375 prov_median weighings.
*
* unique_mun_price is the one label with no inherent position -- it means the
* municipality had too few distinct prices to take percentiles, so the observed
* price(s) were recorded as-is. One of them is a middle (rung 2); two of them
* bracket a range, so they take the ends (rungs 1 and 3).
*
* Reality check on how much ladder there is here: only 38 of 315 price-quantity
* cases have more than one point. 277 are a single point, and under the mapping
* above nearly all of those are a MEDIUM, not a small.

replace rung = 1 if weighing_approach == 2 & item_nsu_hetero_type == 5   // mp25
replace rung = 2 if weighing_approach == 2 & item_nsu_hetero_type == 6   // mp50
replace rung = 3 if weighing_approach == 2 & item_nsu_hetero_type == 7   // mp75
replace rung = 2 if weighing_approach == 2 & inlist(item_nsu_hetero_type, 8, 9)

* unique_mun_price (labels 10 and 11): position depends on how many the case has
tempvar nuniq
bysort cell: egen byte `nuniq' = total(inlist(item_nsu_hetero_type,10,11) & ///
                                       weighing_approach == 2 & tag_lbl)
replace rung = 2 if weighing_approach == 2 & inlist(item_nsu_hetero_type,10,11) & `nuniq' == 1
replace rung = 1 if weighing_approach == 2 & item_nsu_hetero_type == 10 & `nuniq' > 1
replace rung = 3 if weighing_approach == 2 & item_nsu_hetero_type == 11 & `nuniq' > 1

assert !missing(rung) & inrange(rung,1,3) if weighing_approach == 2

* how many DISTINCT rungs this case actually has
bysort cell: egen byte np = total(tag_lbl) if weighing_approach == 2
replace n_target = np if weighing_approach == 2
drop np


*-------------------------------------------------------------------------------
* 3c. CONVENTIONAL -- one rung, no size to resolve
*-------------------------------------------------------------------------------
replace rung     = 1 if weighing_approach == 1
replace n_target = 1 if weighing_approach == 1

assert !missing(rung, n_target)


********************************************************************************
**# 4. Cases that ended up with fewer sizes than we tried to give them
********************************************************************************
* We aim for three sizes when a case has enough weighings. Sometimes only two (or
* one) actually come out. That happens because weights are recorded in whole
* grams: if enough vendors report the same number, they all land on the same side
* of a cut point and one size ends up with nobody in it.
*
* When that happens we report the sizes that really exist rather than an empty
* one. An empty size is telling us something true about the case -- the units
* there are more uniform than we assumed -- so it gets exported for inspection
* rather than smoothed over.

bysort cell rung: gen byte tag_rung = (_n == 1)
bysort cell: egen byte n_actual = total(tag_rung)
label var n_actual "rungs actually populated"

count if tag_cell & n_actual < n_target
di as res "cases where a targeted rung came back EMPTY: " r(N)

preserve
	keep if tag_cell & n_actual < n_target
	if _N > 0 {
		gen str8 branch = cond(weighing_approach==1,"conv",cond(weighing_approach==2,"price","size"))
		keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		     corrected_unit branch n_cell n_target n_actual
		export excel using "${btables}\stepA_empty_rungs.xlsx", ///
			replace firstrow(variables)
		di as txt "exported to stepA_empty_rungs.xlsx"
	}
restore


********************************************************************************
**# 5. Diagnostic: do the survey's own S/M/L labels agree with the terciles?
********************************************************************************
* This is the EVIDENCE for the claim that re-terciling is necessary. If the field
* labels lined up with the empirical terciles, Step A would be redundant. Publish
* the crosstab rather than asserting the claim.

preserve
	keep if weighing_approach == 3 & n_target == 3
	decode item_nsu_hetero_type, gen(field_label)
	di as txt _n "field S/M/L label vs empirical weight tercile (3-rung cells only)"
	tab field_label rung, row
	contract field_label rung
	export excel using "${btables}\stepA_label_vs_tercile.xlsx", ///
		replace firstrow(variables)
restore


********************************************************************************
**# 6. Collapse to the deliverable: case x rung -> w_r
********************************************************************************
* MEDIAN, not mean. The guidebook allows either ("The mean or median measurement
* for each container unit can be used") and the median is robust to the single
* mis-keyed vendor that the order-of-magnitude snap did not catch.

preserve
	collapse (median) w_r = w_ref (count) n_r = w_ref (first) weighing_approach ///
	         n_cell n_target n_actual, ///
	         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	            corrected_unit rung)

	label var w_r     "representative grams (or mL) for this rung: median over vendors"
	label var n_r     "weighings behind w_r"
	label var rung    "ordinal rung, 1 = smallest/cheapest"

	* w_r must rise with the rung inside a cell. If it does not, the ladder is not
	* ordinal and something upstream is wrong -- report, do not silently ship.
	bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	       corrected_unit (rung): gen byte nonmono = (w_r < w_r[_n-1]) if _n > 1
	count if nonmono == 1
	di as res "rung pairs where w_r FALLS as the rung rises: " r(N)
	if r(N) > 0 {
		export excel using "${btables}\stepA_nonmonotonic.xlsx" if nonmono == 1, ///
			replace firstrow(variables)
	}
	drop nonmono

	compress
	save "${btemp}\nsu_rungs.dta", replace
	count
	di as txt "case x rung rows out: " r(N)
restore


********************************************************************************
**# 7. How much did re-terciling actually move things?
********************************************************************************
* Compare the tercile medians against the medians of the survey's own labels for
* the same cells. If these barely differ, the re-terciling is cosmetic and worth
* reconsidering; if they differ a lot, it is doing real work.

preserve
	keep if weighing_approach == 3 & n_target == 3
	* empirical: median within cell x tercile
	bysort cell rung: egen double w_emp = median(w_ref)
	* as-labelled: median within cell x the field's own S/M/L
	bysort cell item_nsu_hetero_type: egen double w_lbl = median(w_ref)
	gen double gap_pct = 100 * (w_emp - w_lbl) / w_lbl
	di as txt _n "shift from field label median to tercile median, % (3-rung cells)"
	su gap_pct, detail
restore

di as res _n "STEP A complete."
