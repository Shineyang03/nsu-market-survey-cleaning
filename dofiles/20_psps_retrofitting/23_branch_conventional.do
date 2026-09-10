********************************************************************************
* 23_branch_conventional.do -- Branch C: one weight per case, no price, no month
*
* WHAT THIS OWNS. A conventional NSU is treated as a standard measure -- a gantang, a
* salop -- so there is no size to resolve and no price to match against. The case gets one
* weight and every household in it gets that weight.
*
* IT IS BUILT FROM THE 24 CASES WHOSE (item, harmonized unit) PAIR IS CONVENTIONAL
* EVERYWHERE IT APPEARS, not from the 123 the field labelled conventional. That is #28's
* decision and it is the whole reason this file waited on `08_branch.do'. The other 99
* cases -- 388 weighings, four fifths of the branch -- are processed as size-based and
* publish one group as medium; they reach Outcome 2 through 21_branch_size_based.do.
*
* Why: `weighing_approach' is preloaded per (municipality, item, unit) CELL, and 13 of the
* 21 labels appearing as conventional somewhere also appear under size-based or
* price-quantity elsewhere, always on the same item. For those, "conventional" records
* what a cell was assigned rather than what the unit is -- and the instrument gives the
* enumerator no way to correct it, because the one choice list that could contains only
* price-quantity and size-based. See #28 Q1-Q3 and A12.
*
* ------------------------------------------------------------------------------
* A1 IS FALSIFIED AND THIS BRANCH RESTS ON IT, so the constraint has to be stated where
* the code is rather than only in the register.
*
* Conventional (item, unit) combinations vary up to 6.7x ACROSS municipalities -- camote
* tops `bundle' runs 95 g to 635 g over 28 of them -- and, worse, 41 of 106 conventional
* cases with two or more weighings disperse beyond 2x INSIDE a single municipality.
*
* THE ONLY THING PROTECTING THIS FILE IS ITS GRAIN. It publishes a CASE median, and a case
* is municipality-specific, so the between-municipality spread is never pooled here. That
* is a side effect of the grain and not a safety property: any step that aggregates these
* rows above the municipality averages a 6.7x spread. The Outcome 2 fallback ladder does
* exactly that at L2 and L3, which is why `fallback_level' is published beside every
* weight. Within-municipality dispersion is not protected against at all.
*
* GANTANG IS THE EXCEPTION AND IT IS INSTRUCTIVE. Rice `gantang' is the one conventional
* unit where A1's claim holds -- 2,237.5 to 2,275 g over 7 municipalities, a 1.7% spread.
* It is now converted from the standard-unit table in 20a_psps_households.do rather than
* from here, because a unit that genuinely IS standard is better served by a stated factor
* than by a fallback ladder. Its weighings still publish in Outcome 1, where they are the
* evidence for that factor.
*
* ------------------------------------------------------------------------------
* NO PRICE POINT, AND THAT IS NOT A GAP. Every one of the 124 raw conventional cases has a
* price-file row and a non-missing price (#28 Q5), and 29% carry a full quartile ladder --
* enough to support three groups. This branch uses none of it, because a conventional unit
* is one object: there is nothing for three price points to be three OF. A household is
* converted at this weight whatever it paid.
*
* INPUT   ${btemp}\nsu_weighings_cpi.dta   the weighings, carrying `branch' from 08
* OUTPUT  ${btemp}\branch_conventional.dta   one row per case
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\23_branch_conventional.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

use "${btemp}\nsu_weighings_cpi", clear

* branch == 1 is the always-conventional set. weighing_approach == 1 is the 123 the field
* called conventional. The gap between them IS this file's scope decision, so it is
* measured in the log rather than assumed.
qui count if weighing_approach == 1
local n_field = r(N)
qui count if branch == 1
local n_branch = r(N)
qui count if weighing_approach == 1 & branch == 3
di as res _n "field-conventional weighings: `n_field'"
di as res "  staying conventional (branch == 1): `n_branch'"
di as res "  reclassified to size-based (#28)  : " r(N) " -- these go to Branch S"

* A reclassified row must be exactly a field-conventional row that moved. If anything else
* is flagged, `d_reclassified' has drifted from the rule that sets it.
assert weighing_approach == 1 & branch == 3 if d_reclassified == 1
assert d_reclassified == 0 if branch == 1

keep if branch == 1

drop if missing(corrected_weight) | corrected_weight <= 0
drop if missing(corrected_unit)
qui count
di as res "  with a usable weight and dimension: " r(N)

* cpi_factor is exactly 1 on this branch by construction: no peso amount entered the
* measurement, so no index applies. 07_cpi_factor.do asserts it there; re-asserted here
* because this file is where a conventional weight would be restated if anything ever
* wrongly tried to.
assert cpi_factor == 1


********************************************************************************
**# 2. One weight per case
********************************************************************************
* MEDIAN, matching Outcome 1 and for the same reason: it is robust to a single mis-keyed
* vendor the magnitude snap did not catch. The guidebook allows mean or median.
*
* corrected_unit IS in the key even though nothing on this branch is being compared across
* dimensions -- because a case CAN span g and mL, and one median over both would be a
* number in neither.

* The uncertainty counts ride with n_g through to the lookup and on to the household (#35).
collapse (median) w_g = corrected_weight (count) n_g = corrected_weight ///
         (sum) n_disputed = d_disputed n_flagged = d_step1_flagged ///
               n_uncertain = d_any_uncertain ///
         (first) branch d_reclassified, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit)

* No price, no month, one group. Written explicitly rather than left missing, so that
* 25_lookup.do's append produces a table where a reader can see this branch HAS no price
* dimension rather than wondering whether one went missing.
gen double p_g = .
gen double v_g = .
gen double cpi_factor_g = 1
gen int    group_id = 1
gen int    n_points = 1

qui count
di as res _n "Branch C groups (one per case): " r(N)
di as res _n "weighings behind each:"
tab n_g, m
qui su n_g, detail
di as res "  min " r(min) "  median " r(p50) "  max " r(max)

* THE ROW COUNT IS #28's PREDICTION. 24 cases was derived on the issue before the code
* existed and both splits (24/99 and 78/21) matched when 08_branch.do landed. If this
* moves, either the mixed-pair set changed or `branch' did, and #28's arithmetic has to be
* re-derived rather than the number here updated.
* IT EXITS, for the same reason as the stacked-row tripwire in 20a: a check that only
* prints cannot be caught by grepping the log for an r() code, which is how a run here is
* verified, so it was not a tripwire at all.
qui count
if r(N) != 24 {
	di as err "Branch C has " r(N) " case(s), not the 24 #28 predicted."
	di as err "Re-derive #28's mixed-pair count before changing this."
	exit 459
}

label var w_g   "reference weight for one unit of this conventional NSU, g or mL"
label var n_g   "weighings behind w_g"
label var p_g   "not applicable on this branch -- a conventional unit has no price dimension"
label var v_g   "not applicable on this branch"
label var cpi_factor_g "1 by construction: no peso amount entered the measurement"
label var group_id "always 1 -- one group per case"

compress
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit
save "${btemp}\branch_conventional", replace

di as res _n "{hline 78}"
di as res "23_branch_conventional.do done -- ${btemp}\branch_conventional.dta"
di as res "  Any aggregation of these rows ABOVE the municipality averages a 6.7x"
di as res "  spread (A1). The ladder does that at L2 and L3 and flags it."
di as res "{hline 78}"
