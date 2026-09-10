********************************************************************************
* 22_branch_price_quantity.do -- Branch P: the groups the field already built
*
* WHAT THIS OWNS. On the price-quantity branch the enumerator was handed a fixed peso
* amount, spent it, and weighed what came back. So a price and a weight were observed on
* the SAME PHYSICAL OBJECT, and the hetero-groups exist already: one per peso amount. This
* file collapses the weighings onto them.
*
* IT IS THE ONLY BRANCH WITH BOTH SIDES MEASURED TOGETHER, which is why it needs none of
* the machinery the other two do -- no price file, no rank assumption, no tercile cut.
* Issue #34 makes the same point from the other direction: this branch is the validation
* set for the assumption Branch S has to make blind.
*
* THE PRICE FILE IS NOT READ HERE. Decided on #21 sec 2 rows 5 and 6: p_g is `pull_price',
* the amount actually handed over, and every distinct `pull_price' in a case is its own
* group with NO merging -- even where two folded spellings sit PHP 20 apart. Merging them
* would destroy the measurement: at NEGROS OCCIDENTAL / VALLADOLID, PHP 60 bought 2.4x
* what PHP 25 bought under one harmonized unit, and that ratio is the thing this branch
* exists to record. The PHP 20 merge in 20_case_price_points.do is scoped to Branch S,
* where no money changed hands.
*
* ------------------------------------------------------------------------------
* WHY cpi_factor RIDES ALONG, and what it costs
*
* w_g here is "what a fixed peso amount bought AT THE PRICE LEVEL OF THE MONTH IT WAS
* SPENT". It is the one weight in this project that is not a property of an object, so it
* is the one that has to be restated before it can be compared with a PSPS household in a
* different month. 24_inflate_to_psps_month.do does that; this file supplies the factor.
*
* THE FACTOR IS A GROUP MEDIAN, and that is an approximation with a measured cost. A group
* can hold weighings from more than one market-survey month, each with its own
* CPI(m_ms)/CPI(REF). Restating each weighing before taking the median is exactly the
* retired `w_ref' (issue #29), withdrawn because the market survey visits a municipality
* across at most a few months and the factor is constant within 93% of price-quantity
* cases. Taking the median factor is therefore exact on those and an approximation on the
* rest, and section 3 counts which is which rather than leaving it implicit.
*
* ------------------------------------------------------------------------------
* INPUT   ${btemp}\nsu_weighings_cpi.dta   the weighings, carrying `branch' from 08
* OUTPUT  ${btemp}\branch_price_quantity.dta   one row per case x price point
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\22_branch_price_quantity.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

use "${btemp}\nsu_weighings_cpi", clear

* `branch' NOT `weighing_approach'. No row moves into or out of price-quantity under
* #28's reclassification -- it moves cells from conventional to size-based -- so the two
* select the same rows here. Reading `branch' anyway is the rule from dofiles/README.md:
* this decides how a weighing is PROCESSED. Asserted below rather than trusted.
qui count if (branch == 2) != (weighing_approach == 2)
if r(N) > 0 {
	di as err "ERROR: " r(N) " row(s) where branch and weighing_approach disagree about"
	di as err "price-quantity. #28's reclassification is not supposed to touch this branch."
	exit 459
}

keep if branch == 2
qui count
di as res _n "price-quantity weighings: " r(N)

drop if missing(corrected_weight) | corrected_weight <= 0
drop if missing(corrected_unit)
qui count
di as res "  with a usable weight and dimension: " r(N)

* p_g IS pull_price AND IT MUST EXIST. 07_cpi_factor.do drops the 27 rows where the vendor
* gave no price at all and the 71 vendor-priced rows whose case kept a preloaded rung, so
* every survivor has one. A missing price here would make v_g missing and the group
* unmatchable, silently.
qui count if missing(pull_price) | pull_price <= 0
if r(N) > 0 {
	di as err "ERROR: " r(N) " price-quantity weighing(s) with no usable pull_price."
	di as err "07_cpi_factor.do is supposed to have removed all of them."
	list id pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		item_nsu_hetero_type pull_price if missing(pull_price) | pull_price <= 0, noobs
	exit 459
}


********************************************************************************
**# 2. One group per distinct price handed over
********************************************************************************
* The group key is the case PLUS the peso amount. `item_nsu_hetero_type' is NOT in it,
* deliberately: two hetero codes quoting the same peso figure bought the same thing, and
* the code is a label for the price rather than a second dimension. It rides along as a
* description via (min), so a reader can see which rung the amount was.
*
* corrected_unit IS in the key. Grams are never pooled with millilitres.

* How many months does each group span? Computed before the collapse, because after it the
* per-weighing months are gone and the approximation in section 3 cannot be measured.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
       corrected_unit pull_price: egen byte n_ms_months = nvals(m_ms)
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
       corrected_unit pull_price: egen byte n_cpi_vals = nvals(cpi_factor)

collapse (median) w_g = corrected_weight (count) n_g = corrected_weight ///
         (median) cpi_factor_g = cpi_factor ///
         (min) hetero_code = item_nsu_hetero_type ///
         (max) n_ms_months n_cpi_vals ///
         (first) branch d_reclassified item_group, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
            corrected_unit pull_price)

rename pull_price p_g

* v_g = PHP per gram. This is the rate a household is converted at: it receives
* p_h / v_g grams per NSU. Stated on v rather than on w because the tie rule in
* 28_match_and_convert.do is stated on v -- see the methodology, Step B2.
gen double v_g = p_g / w_g

bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	gen int n_points = _N
gen int group_id = .
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit ///
	(p_g): replace group_id = _n

qui count
di as res _n "Branch P groups (case x price point): " r(N)
di as res _n "groups per case:"
preserve
	egen byte _t = tag(pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit)
	keep if _t
	tab n_points, m
restore


********************************************************************************
**# 3. What the median factor costs
********************************************************************************
* Reported, not asserted, because a group spanning two months is not an error -- it is the
* market survey revisiting a municipality. What would be an error is applying one factor to
* it without saying so.

qui count if n_ms_months > 1
local n_multi = r(N)
qui count
di as res _n "groups spanning more than one market-survey month: `n_multi' of " r(N)
qui count if n_cpi_vals > 1
di as res "  ...and holding more than one distinct cpi_factor: " r(N)
di as res "  (the second number is the one that matters: two months with a flat CPI"
di as res "   series between them give one factor and no approximation at all)"

* On the other two branches the factor is exactly 1 by construction -- no peso amount
* entered the measurement, so no index applies. 07_cpi_factor.do asserts that at source;
* this asserts the consequence, that nothing on THIS branch has been left at 1 by accident
* where it should vary.
qui count if cpi_factor_g == 1
di as res "  groups whose factor is exactly 1 (weighed in REF, or a flat series): " r(N)

label var p_g          "price handed over, PHP per NSU -- pull_price, not the price file"
label var w_g          "median grams that amount bought, AS WEIGHED (not restated)"
label var n_g          "weighings behind w_g"
label var v_g          "PHP per gram at this point, as weighed"
label var cpi_factor_g "CPI(m_ms)/CPI(REF) for this group -- 24 uses it to reach the PSPS month"
label var hetero_code  "which preloaded rung this peso amount was (see label hetero)"
label var n_ms_months  "market-survey months the weighings in this group span"
label var n_cpi_vals   "distinct cpi_factor values in this group; >1 means the median is an approximation"
label var n_points     "price points in this case"
label var group_id     "1..n_points, ordered by price ascending"

* item_group RIDES ALONG for 24_inflate_to_psps_month.do, which needs it to look up the
* CPI at the household's month. It is a function of (province, item), so 24 could rejoin
* it from cpi_item_crosswalk.csv -- but that would put a second copy of 07_cpi_factor.do's
* restaurant-collapse normalization in the tree, and that normalization is the one this
* project has already had thirteen copies of (#32). Carrying the column is one definition.
label var item_group   "COICOP group, for the CPI join in 24"
assert !missing(item_group)
def_hetero
label values hetero_code hetero

compress
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit group_id
save "${btemp}\branch_price_quantity", replace

di as res _n "{hline 78}"
di as res "22_branch_price_quantity.do done -- ${btemp}\branch_price_quantity.dta"
di as res "  w_g is AS WEIGHED. 24_inflate_to_psps_month.do restates it."
di as res "{hline 78}"
