********************************************************************************
* 21_branch_size_based.do -- Branch S: cut the pooled weights onto the price points
*
* WHAT THIS OWNS. The size-based branch is 78% of cases and it is the one where the price
* and the weight were NEVER observed together: the enumerator asked for a small, a medium
* and a large, and no money changed hands. So the weights have to be cut into groups and
* PAIRED with price points that came from somewhere else -- the price file, computed from
* PSPS responses in a different round by different respondents.
*
* THIS IS THE PROJECT'S OWN INVENTION, not the guidebook's method, and issue #34 is the
* record of establishing that. The LSMS guide's design has the household report the size
* directly (the size is baked into the unit code), its conversion library has no price
* column, and its only discussion of price-based conversion is section 1.2, which REJECTS
* it -- citing quality differences and quantity discounts, the two mechanisms that make
* this pairing unsafe. PSPS has no size variable, so that route is closed; this is what is
* left. The support it has is one test, on 29 price-quantity cases where both sides WERE
* observed together: within-case Spearman correlation between price and weight, median
* 0.878, positive in 28 of 29. That is the assumption surviving its first real test rather
* than being established. Methodology assumption 4; A9.
*
* ==============================================================================
* HOW MANY GROUPS: n_points_conv, from 20_case_price_points.do
*
* NOT the number of field size labels -- that is Outcome 1's rule, and using it here is
* the single easiest way to get this file wrong. A size is only useful if there is a price
* to pair it with, so a cell with one median price supports ONE group however often it was
* weighed. The same case can therefore yield three sizes in Outcome 1 and one weight here,
* and that is the design (methodology, Decision tree).
*
* CONVERTIBLE points only. A refused unique-price point consumes no group -- see
* 20_case_price_points.do, the unique_mun_price arm.
*
* ==============================================================================
* THE PRICE POINTS ARE AT A COARSER GRAIN THAN THE WEIGHTS, and it is forced
*
* Weights pool at province x municipality x item x harmonized unit x CORRECTED_UNIT.
* Price points have no dimension -- a price row cannot say whether it bought grams or
* millilitres -- so they exist at that key WITHOUT corrected_unit. 65 of 1,941 weighed
* cells span both g and mL, and in those the two sub-cells are cut against the SAME price
* points. Each sub-cell is cut on its own weights, so no gram is ever pooled with a
* millilitre; what is shared is the ladder they are cut into.
*
* ==============================================================================
* THE RECLASSIFIED CASES ARE NEVER CUT. A12, decided on #28.
*
* 99 cases arrive here from the conventional branch because their (item, unit) pair mixes
* approaches elsewhere. Their weighings carry NO size information to re-derive: they are
* not small, medium and large readings that lost their labels, they are readings taken
* without a size being asked for. Terciling them would manufacture a structure the field
* never observed. So they get ONE group whatever the point count, matched to the case's
* mp50 / municipality median -- section 4 picks it explicitly rather than by rank.
*
* ==============================================================================
* INPUTS  ${btemp}\nsu_weighings_cpi.dta     the weighings, with `branch' from 08
*         ${btemp}\case_price_points.dta     the ladder, from 20
* OUTPUT  ${btemp}\branch_size_based.dta     one row per case x group
*         ${btables}\branch_s_no_price.csv   weighed cells with no price point
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\21_branch_size_based.do
********************************************************************************

clear all
do "00_shared/00_globals.do"


********************************************************************************
**# 1. The convertible points, ranked, and which one a reclassified case takes
********************************************************************************

use "${btemp}\case_price_points", clear
keep if d_point_unconvertible == 0

* Rank ascending by price. Group j is paired with the j-th point, lowest weights to the
* lowest price -- which is the rank-alignment assumption, stated as assumption 4 and NOT
* established by anything in the data. It is the reason issue #34 exists.
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit p_g
by pull_province pull_municipal_city pull_item harmonized_nsu_unit: gen int conv_rank = _n

* ---- which point a reclassified case is matched to ---------------------------
* A12 says mp50 / municipality median. Preference order, most specific first, because a
* case can hold more than one of these after the PHP 20 merge:
*
*   1  a point containing an mp50 quote          -- the literal middle rung
*   2  a point containing a municipality median  -- A12's stated equivalent
*   3  a point containing a province median      -- the same statistic, one geography out
*   4  the lower-middle point by rank            -- nothing above exists; see below
*
* Rung 4 exists because the preference list is not exhaustive: a case can hold only
* quartile points other than mp50 (an mp25/mp75 pair whose mp50 merged away). Taking the
* lower-middle rather than the middle is a choice on an even count -- it gives the smaller
* p_g, hence the LARGER grams for a given household price, so it is not the conservative
* direction. It is chosen for determinism rather than caution, and section 4 counts how
* many cases reach it so the choice is visible rather than buried.
gen byte _pref = 4
replace  _pref = 3 if has_prov_med == 1
replace  _pref = 2 if has_mun_med  == 1
replace  _pref = 1 if has_mp50     == 1

bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	egen byte _bestpref = min(_pref)
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	egen int _midrank = max(ceil(n_points_conv / 2))

gen byte _is_pick = .
replace  _is_pick = (_pref == _bestpref) if _bestpref < 4
replace  _is_pick = (conv_rank == _midrank) if _bestpref == 4

* Where several points share the best preference, take the cheapest, so the pick is a
* function of the data and not of row order.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	egen int _pickrank = min(cond(_is_pick == 1, conv_rank, .))
gen byte d_recl_point = (conv_rank == _pickrank)

* Exactly one point per case is the reclassified pick.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	egen byte _npick = total(d_recl_point)
assert _npick == 1
drop _pref _bestpref _midrank _is_pick _pickrank _npick

qui count if d_recl_point == 1 & has_mp50 == 0 & has_mun_med == 0 & has_prov_med == 0
di as res "reclassified-pick points that are neither mp50 nor a median: " r(N) ///
	" (preference rung 4)"

keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
     conv_rank p_g n_points_conv d_recl_point
tempfile points
save "`points'"

* Case-grain point count, for the cut.
preserve
	egen byte _t = tag(pull_province pull_municipal_city pull_item harmonized_nsu_unit)
	keep if _t
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit n_points_conv
	tempfile kfile
	save "`kfile'"
restore


********************************************************************************
**# 2. The weighings, and how many groups each case supports
********************************************************************************

use "${btemp}\nsu_weighings_cpi", clear
keep if branch == 3
qui count
di as res _n "size-based weighings (branch == 3, so including the 99 reclassified): " r(N)

drop if missing(corrected_weight) | corrected_weight <= 0
drop if missing(corrected_unit)
qui count
di as res "  with a usable weight and dimension: " r(N)

* unique_mun_price WEIGHINGS. Outcome 1 excludes these outright -- a unique price is not a
* size -- and section 5 of 20_case_price_points.do establishes that every such weighing is
* price-quantity, so none should be here at all. Asserted because if one ever were, it
* would enter a tercile as though it were a size reading.
qui count if inlist(item_nsu_hetero_type, 10, 11)
if r(N) > 0 {
	di as err "ERROR: " r(N) " size-based weighing(s) recorded against a unique price."
	exit 459
}

* cpi_factor is 1 on this branch by construction: no peso amount entered the measurement,
* so w_g is a property of the object and carries no price round. This is the mirror image
* of Branch P, and it is methodology assumption 3 -- unit size stable between rounds --
* which is load-bearing and untested (shrinkflation would break it).
assert cpi_factor == 1

merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	using "`kfile'", keep(1 3) keepusing(n_points_conv) generate(_m_k)

* A WEIGHED CELL WITH NO PRICE POINT cannot be converted on this branch: there is nothing
* to pair a weight with. Reported rather than asserted, because the honest outcome for such
* a cell is that no household can be converted through it, not a halt.
*
* ON THE CURRENT VINTAGE IT IS 144 WEIGHINGS IN 41 CELLS AND ALL OF THEM ARE ONE ITEM:
* `drinks at restaurant, hotel, cafe, or kiosk' under harmonized unit `pieces'. The cause
* is on the PSPS side, not here. The consumption module records prepped food in a
* different slot -- fd_cons_5a, "number of times consumed", with fd_cons_6a/6b for value
* -- and that slot carries NO unit and NO quantity in the NSU sense. So no NSU price
* pairing was ever computed for it, hence no price point, hence no group.
*
* THE EXPOSURE IS ZERO, which is what makes this reportable rather than blocking:
* 20a_psps_households.do finds NO household rows for that item at all, because those rows
* are in a slot 20a does not stack (correctly -- there is no quantity to convert). The
* market survey weighed something PSPS never reports in a non-standard unit. Those 144
* weighings still publish in Outcome 1, where a reference weight for a restaurant drink is
* a perfectly good thing to have.
*
* Note #31 already flagged this item family from another direction: ILOILO / BINGAWAN
* drinks / `pieces' is on its outlier list at 1,000 g against a province median of 2, and
* #31 observes that a province median of 2 g is not a plausible weight either. So the cells
* are odd as well as unconvertible; the oddity belongs to Outcome 1.
qui count if _m_k == 1
local n_noprice = r(N)
di as res _n "size-based weighings in a cell with no usable price point: `n_noprice'"
if `n_noprice' > 0 {
	preserve
		keep if _m_k == 1
		collapse (count) n_weighings = corrected_weight, ///
			by(pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit)
		export delimited using "${btables}\branch_s_no_price.csv", replace
		di as txt "  wrote ${btables}\branch_s_no_price.csv (" _N " cell(s))"
	restore
	drop if _m_k == 1
}
drop _m_k


********************************************************************************
**# 3. Cut the pooled weights
********************************************************************************
* The cut is on the POOLED weights of the full case -- across vendors, market types AND
* the field's own S/M/L labels. Those labels are what Outcome 1 re-derives; here they are
* not used at all, because the number of groups comes from the price side.
*
* THE TIE RULE IS LOWER-INCLUSIVE, matching 10_size_assignment.do:
*     g1: w <= cut1 | g2: cut1 < w <= cut2 | g3: w > cut2
* Weights are whole grams, so vendors tie exactly on a cut and a group can come back
* EMPTY. Section 5 reports those; the point they would have been paired with then has no
* weight, and is published as unconvertible rather than given a neighbouring group's.
* A5 has the direction, which is still untested.

* Named `_scell', not `cell'. 10_size_assignment.do creates a variable called `cell' on
* the Outcome 1 side and it is not obvious from here whether the weighings file carries one
* already -- an egen onto an existing name is an error, and a rename of someone else's
* column would be worse.
egen int _scell = group(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	corrected_unit)

* k_use: the number of parts THIS case is cut into. One for a reclassified case whatever
* the point count -- A12, and the whole reason d_reclassified rides this far.
gen int k_use = n_points_conv
replace  k_use = 1 if d_reclassified == 1

qui count if k_use > 3
if r(N) > 0 {
	di as err "ERROR: " r(N) " weighing(s) in a case with more than 3 convertible points."
	di as err "The S/M/L ladder has three rungs; a 4-point case needs a decision."
	di as err "#21 sec 5.4 (ILOILO / CARLES chicken) is the case that used to do this;"
	di as err "the PHP 20 merge now brings it to 3 or fewer."
	exit 459
}

egen double _p33 = pctile(corrected_weight), by(_scell) p(33.3333)
egen double _p66 = pctile(corrected_weight), by(_scell) p(66.6667)
egen double _p50 = pctile(corrected_weight), by(_scell) p(50)

gen int grp = .
replace grp = 1 if k_use == 3 & corrected_weight <= _p33
replace grp = 2 if k_use == 3 & corrected_weight >  _p33 & corrected_weight <= _p66
replace grp = 3 if k_use == 3 & corrected_weight >  _p66
replace grp = 1 if k_use == 2 & corrected_weight <= _p50
replace grp = 2 if k_use == 2 & corrected_weight >  _p50
replace grp = 1 if k_use == 1
assert !missing(grp)
drop _p33 _p66 _p50 _scell

di as res _n "weighings by the number of parts their case is cut into:"
tab k_use, m


********************************************************************************
**# 4. Collapse, and pair each group with its point
********************************************************************************

collapse (median) w_g = corrected_weight (count) n_g = corrected_weight ///
         (first) branch d_reclassified k_use n_points_conv, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
            corrected_unit grp)

* A NON-RECLASSIFIED group takes the point of its own rank. A RECLASSIFIED case has one
* group and takes the mp50/median point chosen in section 1, whose rank is generally NOT 1.
gen int conv_rank = grp
merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit conv_rank ///
	using "`points'", keep(1 3) keepusing(p_g d_recl_point) generate(_m_p)

* Overwrite the pairing for the reclassified cases.
preserve
	use "`points'", clear
	keep if d_recl_point == 1
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit p_g conv_rank
	rename p_g       p_g_recl
	rename conv_rank conv_rank_recl
	tempfile reclpoint
	save "`reclpoint'"
restore

merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	using "`reclpoint'", keep(1 3) nogen keepusing(p_g_recl conv_rank_recl)

replace p_g       = p_g_recl       if d_reclassified == 1
replace conv_rank = conv_rank_recl if d_reclassified == 1
drop p_g_recl conv_rank_recl

* Every group must have found a price. A non-match means the rank arithmetic and the point
* file disagree, which would publish a weight with no price to convert it at.
qui count if missing(p_g)
if r(N) > 0 {
	di as err "ERROR: " r(N) " group(s) found no price point."
	list pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		grp conv_rank k_use n_points_conv if missing(p_g), noobs
	exit 459
}
drop _m_p

gen double v_g = p_g / w_g
gen double cpi_factor_g = 1
rename grp group_id
rename n_points_conv n_points


********************************************************************************
**# 5. Empty groups
********************************************************************************
* A case cut into 3 that comes back with 2 filled groups has a price point with no weight
* behind it. Outcome 1 handles the same event by renaming the survivors (A5, #27); Outcome
* 2 cannot, because the point the empty group would have taken is a real price a household
* can match to. Reported here; 28_match_and_convert.do returns .c for a household whose
* nearest point has no group.

bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	gen int n_filled = _N
gen int n_empty = k_use - n_filled

qui count if n_empty > 0
di as res _n "groups in a case that came back under-filled: " r(N)
preserve
	egen byte _t = tag(pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit)
	keep if _t
	di as res "cases by parts cut vs groups filled:"
	tab k_use n_filled, m
restore

label var w_g      "median grams (or mL) in this group, pooled across vendors and field labels"
label var n_g      "weighings behind w_g"
label var p_g      "the price point this group is paired with, PHP per NSU"
label var v_g      "PHP per gram at this group"
label var group_id "1..k_use, lowest weights to the lowest price"
label var k_use    "parts this case was cut into -- n_points, or 1 if reclassified"
label var n_points "convertible price points in this case"
label var n_filled "groups that came back non-empty"
label var n_empty  "parts cut that came back empty -- their price point has no weight"
label var conv_rank "rank of the paired point within the case, by price ascending"
label var cpi_factor_g "1 by construction: no peso amount entered a size-based measurement"

compress
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit group_id
save "${btemp}\branch_size_based", replace

qui count
di as res _n "{hline 78}"
di as res "21_branch_size_based.do done -- " r(N) " group(s)"
qui count if d_reclassified == 1
di as res "  of which reclassified (one group, mp50/median point): " r(N)
di as res "{hline 78}"
