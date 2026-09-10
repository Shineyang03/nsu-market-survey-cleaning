********************************************************************************
* 30_fallback.do -- the Outcome 2 weight ladder, and who is refused a weight
*
* WHAT THIS OWNS. A PSPS household reports an item and a non-standard unit. Where its
* province x municipality x item x harmonized unit cell has a thick market-survey
* weighing of its own, Outcome 2 uses it. Where the cell is thin or absent, this file
* decides what weight the household gets instead -- or that it gets none.
*
* THE LADDER (issue #30, settled there). Each rung is tried in turn and the first that
* clears THIN wins:
*
*   L0  prov x mun x item x nsu x unit x hetero    n_g >= 3; the price selects the rung
*   L1  prov x mun x item x nsu x unit            pool across hetero -- NO price match
*   L2  prov x item x nsu x unit                  no usable weighing in the cell
*   L3  item x nsu x unit                         still nothing
*   --  unconvertible                             nothing anywhere; reported, never imputed
*
* RE-TESTED AT EVERY RUNG. Reaching L1 does not end the climb: a cell whose two rungs
* hold one weighing each pools to n_g = 2, is still thin, and continues to L2. The ladder
* stops at the first rung with n_g >= 3, or falls off the bottom.
*
* IGNORING WITHIN-NSU HETEROGENEITY IS THE COST, and it is accepted rather than
* incidental. From L1 down a household that bought the cheap version and one that bought
* the expensive version of the same unit RECEIVE THE SAME GRAMS. In exchange the estimate
* does not depend on a price-weight relationship holding across municipalities. See
* docs/implicit_assumptions.md A15.
*
* WHY NO RAY-FIT STATISTIC. An earlier design borrowed the price-weight SLOPE across
* municipalities and needed a ray-fit statistic (cv_gpp) to say where that was safe. This
* ladder borrows a MEDIAN WEIGHT at a coarser grain, so there is no slope to qualify and
* the statistic has nothing to say. It survives only in 90_diagnostics/
* scope_price_weight_ray.do, as a measurement of the road not taken.
*
* HOW THIS DIFFERS FROM OUTCOME 1, and why the same evidence gives opposite answers.
* 12_publish_reference_set.do stops at L1: the reference set records what was weighed in
* a cell, so borrowing another municipality's weight would change what the table is, and
* a cell with no weighing is simply absent. Outcome 2's job is to produce a usable number
* for a household that exists, so it climbs. A singleton is kept and flagged in Outcome 1;
* in Outcome 2 the ladder may carry it past its own cell.
*
* ------------------------------------------------------------------------------
* WHAT THIS FILE DOES NOT DO. It does not attach a weight to a PSPS household row. That
* needs the retrofit, which is not written -- 20_psps_retrofitting/ holds only this file --
* and `branch' from 08_branch.do (#28), also unwritten. This builds the LADDER as a lookup
* keyed at every level, plus the refusal list; the step that joins it to household rows
* consumes both.
*
* CALLED BY   master_outcome2.do, after the Outcome 1 reference set exists.
*
* OUTPUT  ${btemp}\outcome2_weight_ladder.dta   every (cell x hetero) with its resolved
*                                              weight, fallback_level and n_g_used
*         ${btables}\outcome2_weight_ladder.csv the same, for inspection
*         ${btables}\fallback_refused.csv       cells the ladder cannot serve
********************************************************************************

clear all
set more off
do "00_shared/00_globals.do"

local THIN = ${THIN}    // ONE definition, in 00_globals.do -- do not retype the value

********************************************************************************
**# 1. the weighing-level base
********************************************************************************
* Read the weighings, not the reference set. The reference set has ALREADY applied
* Outcome 1's L1 collapse, so its rows are a mixture of per-rung and pooled medians and
* its n_g is the count at whichever grain survived. Reconstructing a ladder from that
* would inherit Outcome 1's stopping rule, which is not Outcome 2's.
use "${btemp}\ref_11_checked", clear

keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	corrected_unit size_ord corrected_weight weighing_approach
drop if missing(corrected_weight) | corrected_weight <= 0
drop if missing(corrected_unit)

qui count
di as res _n "weighings available to the ladder: " r(N)

* corrected_unit STAYS IN EVERY KEY below. Grams must never be pooled with millilitres,
* and the ladder's coarser rungs are exactly where that could happen unnoticed.

********************************************************************************
**# 2. one median per rung of the ladder
********************************************************************************
* Each level gets a median and a count computed over the WEIGHINGS at that grain -- not
* an average of the finer level's medians, which would weight cells rather than
* observations.
tempfile base
save "`base'"

* ---- L0: the cell's own hetero rung -----------------------------------------
collapse (median) w_l0 = corrected_weight (count) n_l0 = corrected_weight ///
         (first) weighing_approach, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
            corrected_unit size_ord)
tempfile l0
save "`l0'"

* ---- L1: the cell, pooled across hetero -------------------------------------
use "`base'", clear
collapse (median) w_l1 = corrected_weight (count) n_l1 = corrected_weight, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit)
tempfile l1
save "`l1'"

* ---- L2: the province, dropping municipality --------------------------------
use "`base'", clear
collapse (median) w_l2 = corrected_weight (count) n_l2 = corrected_weight, ///
         by(pull_province pull_item harmonized_nsu_unit corrected_unit)
tempfile l2
save "`l2'"

* ---- L3: the whole sample, dropping province --------------------------------
* THE WEAKEST RUNG BY A WIDE MARGIN, and flagged distinctly for it. Conventional units
* vary up to 6.7x across municipalities (implicit_assumptions.md A1: camote tops `bundle'
* 95 g to 635 g over 28 municipalities), and 41 of 106 conventional cases disperse beyond
* 2x INSIDE one municipality. A national median for such a unit describes nowhere in
* particular. It is offered because the alternative is no number at all, and the flag is
* what lets a reader refuse it.
use "`base'", clear
collapse (median) w_l3 = corrected_weight (count) n_l3 = corrected_weight, ///
         by(pull_item harmonized_nsu_unit corrected_unit)
tempfile l3
save "`l3'"

********************************************************************************
**# 3. climb
********************************************************************************
use "`l0'", clear
merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	corrected_unit using "`l1'", keep(1 3) nogen
merge m:1 pull_province pull_item harmonized_nsu_unit corrected_unit ///
	using "`l2'", keep(1 3) nogen
merge m:1 pull_item harmonized_nsu_unit corrected_unit using "`l3'", keep(1 3) nogen

* ANY THIN RUNG DISQUALIFIES THE WHOLE CELL FROM L0, exactly as Outcome 1's L1 rule works.
* Without this the ladder mixes estimators inside one cell -- `small' at its own median,
* `medium' at the cell-pooled one -- and the mixture is what breaks the ordering rather
* than either estimator being wrong.
*
* MEASURED, not assumed. Resolving rung by rung leaves 165 rows where the price rung rises
* and the resolved grams FALL, and 164 of those 165 sit in the 294 cells that hold both a
* thick and a thin rung. A household paying a mid price would be told it received less food
* than one paying a low price, for no reason other than which rung happened to be thin.
*
* The cost is real and accepted: 440 rows at 294 cells hold a thick rung of their own and
* still lose it to the cell median. That is the same trade Outcome 1 makes, and it is why
* the flag is published.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	egen byte _cell_has_thin = max(n_l0 < `THIN')

* First rung clearing THIN wins, ordered finest to coarsest so the earliest assignment
* sticks and no later replace can overwrite a better one. L0 is available only to cells
* with no thin rung anywhere.
gen double grams_used   = .
gen long   n_g_used     = .
gen byte   fallback_level = .

replace fallback_level = 0 if n_l0 >= `THIN' & _cell_has_thin == 0
replace grams_used     = w_l0 if fallback_level == 0
replace n_g_used       = n_l0 if fallback_level == 0

foreach L in 1 2 3 {
	replace fallback_level = `L' if missing(fallback_level) & n_l`L' >= `THIN'
	replace grams_used     = w_l`L'  if fallback_level == `L' & missing(grams_used)
	replace n_g_used       = n_l`L'  if fallback_level == `L' & missing(n_g_used)
}
drop _cell_has_thin

* THE CONVENTIONAL BRANCH HAS NO HETERO LEVELS to pool (size_ord == 0), so L1 is a no-op
* there and those cells go straight to L2 if their own count is thin. Not a special case
* in the code -- L1's key simply drops a variable that was already constant -- but worth
* naming, because it means the conventional branch reaches coarser rungs sooner than the
* others. #28's reclassification is shrinking this population.

* Cells no rung can serve: even the national item x unit pool is under THIN.
gen byte unconvertible = missing(fallback_level)

* ONE definition, in 00_globals.do, shared with the Outcome 1 reference set. It had a
* second copy here under a different label name, with codes 0 and 1 spelled identically --
* correct today and free to drift, which is the whole argument against two copies.
def_fallback_level
label values fallback_level fallback_lbl
label var fallback_level "rung of the ladder that supplied the weight; 0 = the cell's own"
label var grams_used     "weight this cell x size resolves to, in g or mL"
label var n_g_used       "weighings behind grams_used, AT THE RUNG USED"
label var unconvertible  "1 = no rung reached THIN; report as unconvertible, do not impute"

********************************************************************************
**# 3b. LABEL INVARIANTS -- every rung label must be true of the row carrying it
********************************************************************************
* Same instrument as 12_publish_reference_set.do section 5c, and here for the same reason.
* Three labels in the Outcome 1 publish step were wrong on real rows because THE LABEL WAS
* WRITTEN BY THE CODE PATH THE ROW TRAVELLED THROUGH rather than derived from what happened
* to the row -- 474 rows announced a pooling across sizes that never occurred. The ladder
* below is the same shape of code, so it gets the same assertions.
*
* This ladder turns out NOT to have that defect, and the reason is worth recording rather
* than rediscovering: a cell holding one rung has n_l1 == n_l0 identically, so a cell that
* fails L0's thin test fails L1's too and climbs straight past it. L1 is therefore
* unreachable for a single-rung cell by arithmetic. The assertion states that, so a future
* change to either count breaks the build instead of quietly labelling a non-pooling as a
* pooling.

* Level 1 claims a pooling across hetero rungs. That requires the cell to hold at least
* two, which shows up as L1's count strictly exceeding L0's.
count if fallback_level == 1 & n_l1 <= n_l0
if r(N) > 0 {
	di as err r(N) " row(s) at `cell pooled across sizes' whose L1 pool is no larger than L0"
	di as err "The label claims a pooling that did not happen -- see the note above."
	exit 459
}

* Each rung's own count must be the one published, and must clear THIN. A row whose
* n_g_used came from a different rung than fallback_level names is mislabelled even when
* the weight is right.
forvalues L = 0/3 {
	assert n_g_used == n_l`L' & grams_used == w_l`L' if fallback_level == `L'
	assert n_g_used >= `THIN'                        if fallback_level == `L'
}

* The ladder is ordered finest to coarsest, so a row at level L must have FAILED every
* finer rung. Without this, a bug in the `foreach' order could publish a coarse rung while
* a finer one was available -- the weight would be defensible and the flag would overstate
* how far the estimate travelled.
*
* L0 IS NOT "n_l0 >= THIN". It is that AND no thin rung anywhere in the cell -- the
* whole-cell rule from section 3. So the L0 assertion has to recompute the cell condition
* rather than read n_l0 alone; a row can hold a thick rung of its own and still be denied
* L0 because a SIBLING rung is thin. 440 rows at 294 cells are in exactly that position,
* and reading n_l0 by itself would flag every one of them as a defect.
tempvar cellthin
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	egen byte `cellthin' = max(n_l0 < `THIN')
assert (fallback_level == 0) == (n_l0 >= `THIN' & `cellthin' == 0)
assert n_l1 <  `THIN' | inlist(fallback_level, 0, 1) if !unconvertible
assert n_l2 <  `THIN' | inlist(fallback_level, 0, 1, 2) if !unconvertible
drop `cellthin'

di as res _n "3b label invariants: all pass"

di as res _n "rung that supplied the weight:"
tab fallback_level, m
di as res _n "still thin at the rung used (should be none by construction):"
count if !unconvertible & n_g_used < `THIN'
assert r(N) == 0

di as res _n "cells x sizes no rung can serve: "
count if unconvertible
di as res "  " r(N)

* A weight that fell off the bottom must carry nothing, or a downstream join will read a
* stale value as if it were an estimate.
assert missing(grams_used) & missing(n_g_used) if unconvertible

sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit size_ord
save "${btemp}\outcome2_weight_ladder", replace
export delimited using "${btables}\outcome2_weight_ladder.csv", replace
di as txt "wrote ${btemp}\outcome2_weight_ladder.dta and the .csv"

preserve
	keep if unconvertible
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	     corrected_unit size_ord n_l0 n_l1 n_l2 n_l3
	export delimited using "${btables}\fallback_refused.csv", replace
	di as txt "wrote ${btables}\fallback_refused.csv (" _N " row(s))"
restore

di as res _n "30_fallback.do done -- ladder built. ATTACHING it to PSPS households"
di as res "needs the retrofit and 08_branch.do, neither written."
