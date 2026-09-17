********************************************************************************
* 30_fallback.do -- the Outcome 2 weight ladder, and who is refused a weight
*
* WHAT THIS OWNS. A PSPS household reports an item and a non-standard unit. Where its
* province x municipality x item x harmonized unit cell has a thick market-survey
* weighing of its own, Outcome 2 uses it. Where the cell is thin or absent, this file
* decides what weight the household gets instead -- or that it gets none.
*
* THE LADDER (issue #30, settled there). From L1 down, each rung is tried in turn and the
* first that clears THIN wins:
*
*   L0  prov x mun x item x nsu x unit x hetero    the price selects the rung; NO THIN test
*   L1  prov x mun x item x nsu x unit            pool across hetero -- NO price match
*   L2  prov x item x nsu x unit                  no usable weighing in the cell
*   L3  item x nsu x unit                         still nothing
*   --  unconvertible                             nothing anywhere; reported, never imputed
*
* L0 IS NOT GATED ON THIN, and this header said it was until 2026-09-16. A household whose
* matched rung rests on one or two weighings is converted AT THAT RUNG and marked d_thin --
* it is not sent up the ladder. The ladder is for weights that are ABSENT, not for weights
* that are FEW (#31, decided there; A3 has the comparison and what the alternative cost).
* 28_match_and_convert.do sets fallback_level = 0 for any usable matched point, and 7,077
* of the 28,889 rows at L0 carry n_g_used < 3.
*
* THE ONE PLACE A THIN TEST DOES GATE L0 is the (cell x size) record written in section 4,
* which answers "what would each rung resolve to" for inspection. Nothing consumes it. The
* table that 28 DOES consume is outcome2_cell_fallback, built in section 5, and that one is
* L1-down by construction because L0 is precisely the thing that failed.
*
* RE-TESTED AT EVERY RUNG FROM L1 DOWN. Reaching L1 does not end the climb: a cell whose
* two rungs hold one weighing each pools to n_g = 2, is still thin, and continues to L2.
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
* WHAT THIS FILE DOES NOT DO. It does not attach a weight to a PSPS household row. This
* builds the LADDER as a lookup keyed at every level, plus the refusal list;
* 28_match_and_convert.do consumes both and does the attaching, and it runs immediately
* after this file in master_outcome2.do. `branch' comes from 08_branch.do, which runs
* earlier still.
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
* `n_lN' IS COMPUTED AT EVERY RUNG, alongside that rung's own median, and for a reason:
* a household served by a borrowed weight must be told how much evidence THE WEIGHINGS IT
* ACTUALLY GOT rest on, not how much its own cell held. Carrying a single cell-level count
* and reporting it beside a province median would attach a number to a row it does not
* describe -- the mislabel class closed in 12_publish_reference_set.do section 5c.
* Section 3 picks n_g_used with the same selector it uses for grams_used, so the two
* columns cannot come from different rungs.
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
* 2x INSIDE one municipality. A regional median for such a unit describes nowhere in
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

* n_g_used moves in the SAME replace as grams_used and under the same condition, which is
* the whole point: the two columns describe one rung or they describe nothing. Filling the
* count afterwards from the level code is how a count from L0 ends up printed beside a
* weight from L2.
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

* Cells no rung can serve: even the regional item x unit pool is under THIN.
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
* stale value as if it were an estimate. n_g_used included: a 0 there would read as a real
* count of no weighings, about an estimate that does not exist.
assert missing(grams_used) & missing(n_g_used) if unconvertible

di as res _n "weighings behind the weight, by the rung that supplied it:"
table fallback_level if !unconvertible, statistic(frequency) ///
	statistic(mean n_g_used) nformat(%9.2f)

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


********************************************************************************
**# 5. The CELL-level answer, for the households the price match cannot serve
********************************************************************************
* The table above is keyed (cell x size), because at L0 the household's price selects the
* rung. A household reaching the fallback has no usable rung to select: either its cell
* built no group at all, or the point it matched has no weight behind it. For those, the
* question is not "which rung" but "what does this cell resolve to at all", and the answer
* is the first rung from L1 down that clears THIN -- the SAME climb, with L0 skipped
* because L0 is precisely the thing that failed.
*
* L0 IS NOT AVAILABLE HERE, and that is the whole content of this table. Skipping it means
* from L1 down every household in the cell receives the SAME grams whatever it paid, which
* is the substantive cost recorded as A15: a household that bought the cheap version and
* one that bought the expensive version of the same unit are given one number. That cost
* is accepted in exchange for not depending on a price-weight relationship holding across
* municipalities.
*
* Built here rather than in 28_match_and_convert.do so the ladder has ONE definition. A
* second climb written next to the household join would be free to drift from this one,
* which is the defect that gave the block reading three implementations.

preserve
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	     corrected_unit w_l1 n_l1 w_l2 n_l2 w_l3 n_l3
	duplicates drop

	* One row per cell. w_l1/n_l1 and below are constant within a cell by construction --
	* they are collapses at or above the cell grain -- so `duplicates drop' must leave
	* exactly one row per cell. If it does not, one of those collapses has a finer key than
	* its name claims.
	isid pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit

	gen double fb_grams  = .
	gen long   fb_n_g    = .
	gen byte   fb_level  = .
	foreach L in 1 2 3 {
		replace fb_level = `L' if missing(fb_level) & n_l`L' >= `THIN'
		replace fb_grams = w_l`L'  if fb_level == `L' & missing(fb_grams)
		replace fb_n_g   = n_l`L'  if fb_level == `L' & missing(fb_n_g)
	}
	gen byte fb_unconvertible = missing(fb_level)

	def_fallback_level
	label values fb_level fallback_lbl
	label var fb_level  "coarsest-first rung serving this cell when the price match fails"
	label var fb_grams  "grams (or mL) that rung resolves to"
	label var fb_n_g    "weighings behind fb_grams, AT THE RUNG USED"
	label var fb_unconvertible "1 = no rung from L1 down clears THIN; report, do not impute"

	assert missing(fb_grams) & missing(fb_n_g) if fb_unconvertible
	assert fb_n_g >= `THIN' if !fb_unconvertible
	forvalues L = 1/3 {
		assert fb_n_g == n_l`L' if fb_level == `L'
	}

	di as res _n "cell-level fallback rung:"
	tab fb_level, m
	qui count if fb_unconvertible
	di as res "  cells no rung from L1 down can serve: " r(N)

	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit ///
	     fb_grams fb_n_g fb_level fb_unconvertible
	compress
	sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit
	save "${btemp}\outcome2_cell_fallback", replace
	di as txt "wrote ${btemp}\outcome2_cell_fallback.dta (" _N " cell(s))"
restore


********************************************************************************
**# 6. L2 and L3 AS STANDALONE SCHEDULES -- the cells with no weighing of their own
********************************************************************************
* THIS IS THE POPULATION ISSUE #30 IS ABOUT, and everything above misses it.
*
* Sections 1-5 are keyed on cells that HAVE weighings: they read ref_11_checked, so a cell
* the market survey never visited has no row anywhere in them. But #30's exposure is
* exactly the other case -- 419 cells needing a province fallback and 75 needing any
* province, 5,741 PSPS observations between them, one observation in six. A household
* there cannot be served by a table keyed on cells, because its cell is not in the table.
*
* So the L2 and L3 pools are also written out on THEIR OWN KEYS:
*
*   province schedule   province x item x harmonized unit x corrected unit
*   regional schedule   item x harmonized unit x corrected unit
*
* 28_match_and_convert.do climbs cell -> province -> regional, which is the same ladder
* read from the other end. The medians are the identical collapses computed in section 2 --
* not recomputed -- so the two readings of L2 cannot disagree.
*
* A HOUSEHOLD IN AN UNWEIGHED CELL HAS NO DIMENSION EITHER, and neither pool can tell it
* which. Each schedule therefore also names the dimension the pool is dominated by, on the
* same more-weighings-wins rule 28 uses elsewhere. Since a gram and a millilitre are the
* same reading at this precision, that choice moves a label and not a number.

foreach L in 2 3 {
	preserve
		if `L' == 2 {
			local lkey pull_province pull_item harmonized_nsu_unit corrected_unit
			local lnm  "province"
		}
		else {
			local lkey pull_item harmonized_nsu_unit corrected_unit
			local lnm  "regional"
		}
		keep `lkey' w_l`L' n_l`L'
		duplicates drop
		isid `lkey'

		rename w_l`L'  fb_grams
		rename n_l`L'  fb_n_g
		gen byte fb_level = `L'

		* Only a pool clearing THIN is offered. Below that the honest answer is nothing;
		* the household climbs to the next rung or is reported unconvertible.
		qui count
		local n_all = r(N)
		keep if fb_n_g >= `THIN'
		qui count
		di as res _n "`lnm' schedule: " r(N) " of `n_all' pool(s) clear THIN"

		def_fallback_level
		label values fb_level fallback_lbl
		label var fb_grams "median grams (or mL) in this pool"
		label var fb_n_g   "weighings behind it"
		label var fb_level "the rung this schedule is"
		assert fb_n_g >= `THIN'

		compress
		sort `lkey'
		save "${btemp}\outcome2_fallback_`lnm'", replace
		di as txt "  wrote ${btemp}\outcome2_fallback_`lnm'.dta"
	restore
}

* L3 IS THE WEAKEST RUNG BY A WIDE MARGIN and the schedule is where that stops being
* visible, so it is worth restating here as well as at the collapse. It drops province
* entirely, and A1 measures conventional units varying up to 6.7x between municipalities
* -- camote tops `bundle' 95 g to 635 g over 28 of them -- with 41 of 106 conventional
* cases dispersing beyond 2x INSIDE one municipality. A regional median for such a unit
* describes nowhere in particular. It is offered because the alternative is no number, and
* `fallback_level' is what lets a reader refuse it.
*
* REGIONAL, NOT NATIONAL. The survey covers five provinces -- AKLAN, ANTIQUE, CAPIZ,
* ILOILO and NEGROS OCCIDENTAL -- all Western Visayas (Region VI), with Guimaras the one
* Region VI province absent. L3 is therefore the widest pool the data contains and still
* says nothing about the Philippines outside this region. The label read "national" until
* it was corrected, which invited exactly the generalization the data cannot support.

********************************************************************************
**# The hetero-blind lookup, published
********************************************************************************
* ONE CONVERSION FACTOR PER CELL, with no within-NSU heterogeneity in it at all. This is
* the cell-grain ladder above, promoted from an intermediate to a deliverable because it
* answers a question on its own: what does a household get if the price/size matching is
* removed entirely?
*
* THE KEY IS FIVE COLUMNS, NOT FOUR. `corrected_unit' has to stay in it. No CELL spans
* both dimensions any more -- 05_manual_corrections.do section 1c resolves those -- but
* the rungs above the cell still do: 20 of 212 province groups and 8 of 84 national ones
* mix grams and millilitres, because they pool municipalities that resolved differently.
* Dropping the column would add grams to millilitres at exactly those rungs.
*
* THE LADDER STILL CLIMBS. `fb_level' says how far: 1 means the cell's own weighings
* pooled across hetero-groups, 2 the province, 3 the region. A cell too thin to serve
* itself borrows, exactly as the headline ladder does, so this table and the published
* one cover the same cells and a difference between them is the hetero matching alone.
*
* THIS IS A ROBUSTNESS OBJECT, NOT A BETTER ANSWER. It is A15's cost applied universally:
* a household that bought the cheap version and one that bought the expensive version of
* the same unit receive identical grams. Nothing downstream should prefer it without
* saying why. Its household-level counterpart is psps_grams_heteroblind, written by
* 31_psps_grams.do from the same rungs.
preserve
	use "${btemp}\outcome2_cell_fallback", clear

	rename (fb_grams fb_n_g fb_level fb_unconvertible) ///
	       (cf_blind n_g_used fallback_level d_unconvertible)

	label var cf_blind       "grams (or mL) in one unit of this NSU, pooled across hetero-groups"
	label var n_g_used       "weighings behind cf_blind, at the rung actually used"
	label var fallback_level "rung: 1 cell pooled, 2 province, 3 regional (never 0 -- L0 IS the hetero match)"
	label var d_unconvertible "1 = no rung from L1 down clears THIN; reported, never imputed"
	label var corrected_unit "dimension of cf_blind: 1 = g, 2 = mL -- part of the key, never pooled over"

	* d_thin ships here for schema parity with the headline pair, and it is ZERO on every
	* row BY CONSTRUCTION: this ladder is gated at every rung and has no L0, so nothing
	* below THIN can reach it. Asserted rather than assumed -- that is the cleanest
	* statement of what the blind variant is, and a future change letting a thin value in
	* should fail here rather than pass quietly. (#31, 2026-09-16.)
	gen_d_thin n_g_used
	assert d_thin == 0 if !missing(d_thin)

	isid pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit
	assert inlist(fallback_level, 1, 2, 3) if !d_unconvertible
	assert missing(cf_blind) == (d_unconvertible == 1)

	order pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit ///
	      cf_blind fallback_level n_g_used d_thin d_unconvertible
	compress
	sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit
	save "${bdeliv}\outcome2_lookup_heteroblind", replace
	di as txt "wrote ${bdeliv}\outcome2_lookup_heteroblind.dta (" _N " cell x dimension row(s))"
	qui export delimited using "${bdeliv}\outcome2_lookup_heteroblind.csv", replace
	di as txt "wrote ${bdeliv}\outcome2_lookup_heteroblind.csv"

	di as res _n "hetero-blind lookup, rung serving each cell:"
	tab fallback_level, m
restore


di as res _n "30_fallback.do done -- ladder built, with nu_lN beside every rung's count."
di as res "28_match_and_convert.do runs next and attaches it to PSPS household rows."
