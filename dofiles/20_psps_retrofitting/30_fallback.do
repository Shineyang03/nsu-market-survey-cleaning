********************************************************************************
* 30_fallback.do -- the province grams-per-peso schedule, and who is refused a weight
*
* WHAT THIS OWNS. 494 price-file cases have no market-survey weighing of their own --
* 5,741 PSPS observations, roughly one in six of all non-standard-unit answers. This file
* builds the object that gives them a weight where one can honestly be given, and the
* list of those it cannot.
*
* THE RULE (issue #30, settled there):
*
*   1  A fallback is offered wherever a province schedule is ESTIMABLE: the province x
*      item x harmonized-unit group has >=3 distinct prices and spans >=2 municipalities.
*   2  The estimator is the MEDIAN OF PER-PAIR w/p, applied to the price the household
*      actually faced. Scale-free, and it does not weight pairs by price level.
*   3  There is NO ACCURACY THRESHOLD. Every fallback weight ships with cv_gpp, n_pairs,
*      n_price and n_mun so a reader can set their own cut -- the same convention
*      12_publish_reference_set.do uses for n_g and d_thin.
*   4  Where the schedule is not estimable the case is REFUSED and reported unconvertible.
*
* WHY NO THRESHOLD, since a gate looks safer. Measured in PSPS observations rather than
* groups, a gate buys almost nothing and costs almost everything:
*
*     gate                          fallback obs answered    share of 5,741
*     CV(w/p) < 0.2                              317               5.5%
*     CV(w/p) < 0.4                            1,726              30.1%
*     estimable only, no gate                  3,403              59.3%
*     not estimable at all                     2,338              40.7%
*
* The binding constraint is ESTIMABILITY, not fit: 41% of the fallback need has a province
* group with fewer than three distinct prices, so no threshold reaches it either way.
* Gating at 0.2 answers one PSPS observation in eighteen -- not a conservative fallback,
* but declining to have one. The ray statistic is published instead of enforced.
*
* WHAT cv_gpp MEANS AND WHY IT IS WORTH PUBLISHING. w/p is grams per peso. If a peso buys
* the same amount of food across a province then w/p is constant within province x item x
* unit, and the (price, weight) pairs lie on a ray through the origin. cv_gpp is how much
* it wobbles, and it predicts accuracy sharply -- validated by holding out one
* municipality at a time and predicting it from the others:
*
*     cv_gpp        pairs   within 2x of the weighed value
*     < 0.2           109              92.7%
*     0.2-0.4         549              79.1%
*     0.4-0.6         350              69.7%
*     > 0.6           184              51.6%
*
* AN ASSUMPTION, recorded rather than measured: those figures come from cells that DO
* have their own weighings, because only there is the answer known. The 494 fallback cells
* are by construction ones nobody weighed locally -- plausibly rarer units in thinner
* markets -- so the figures are optimistic for them. See docs/implicit_assumptions.md.
*
* ------------------------------------------------------------------------------
* WHAT THIS FILE DOES NOT DO. It does not attach a weight to a PSPS household. That needs
* the retrofit, which is not written: 20_psps_retrofitting/ is otherwise empty and
* `branch' comes from 08_branch.do (#28), also unwritten. This file builds the SCHEDULE
* and the REFUSAL LIST; the step that joins them to household rows consumes both.
*
* IT ALSO OWNS THE PAIR CONSTRUCTION, and that is deliberate. 90_diagnostics/
* scope_price_weight_ray.do measures the same pairs and must not build them a second time
* -- see CLAUDE.md, "A diagnostic reads the quantity the pipeline computed."
*
* CALLED BY   master_outcome2.do. Runs after the Outcome 1 reference set exists, because
*             the weight half of every pair is a published reference-set row.
*
* OUTPUT  ${btemp}\price_weight_pairs.dta     one row per (case x rung) pair
*         ${btemp}\province_schedule.dta      one row per province x item x harmonized unit
*         ${btables}\province_schedule.csv    the same, for inspection
*         ${btables}\fallback_refused.csv     cases with no estimable schedule
********************************************************************************

clear all
set more off
do "00_shared/00_globals.do"

local MINPRICE = 3    // distinct prices a group needs before a ray is identified
local MINMUN   = 2    // municipalities it must span, so the schedule is not one place's

********************************************************************************
**# 1. the (price, weight) pairs, at case x rung
********************************************************************************
* Both branches meet on one rung ladder. 10_size_assignment.do maps mp25/mp50/mp75 to
* rungs 1/2/3 on the price-quantity branch and RE-TERCILES the size-based branch's pooled
* weights into the same three, so `size_ord' is comparable across branches. The reference
* set publishes grams at each rung; the price file carries a price at each rung. They meet
* at (province x municipality x item x harmonized unit x rung).
*
* NOT on pull_price. The market survey records a price only on the price-quantity branch,
* so pairing there sees 1,109 weighings, misses all 1,046 size-based pairs, and cuts the
* estimable base from 79 groups to 29. That mistake reversed two conclusions on #30.

import delimited using "${pricedata}", clear varnames(1) encoding("utf-8") stringcols(_all)

keep if inlist(price_type, "mp25_price", "mp50_price", "mp75_price")
gen byte rung = 1 if price_type == "mp25_price"
replace  rung = 2 if price_type == "mp50_price"
replace  rung = 3 if price_type == "mp75_price"
assert !missing(rung)

destring price, gen(p) force
rename (cons_name unit_lbl province) (pull_item pull_nsu_unit pull_province)
keep pull_province pull_municipal_city pull_item pull_nsu_unit rung p
drop if missing(p) | p <= 0

* THE authoritative normalization, from 00_globals.do. Its Python counterpart is
* nz()/ni()/ng() in nsu_normalize.py and the two must agree character for character --
* the crosswalk joined below is built by the Python side.
nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
	mun(pull_municipal_city) province(pull_province)
tempfile prices
save `prices'
qui count
di as res _n "tercile price rows: " r(N)

* ---- resolve each priced spelling to its harmonized unit ---------------------
import delimited using "${tables}\master_nsu_rename.csv", clear varnames(1) ///
	encoding("utf-8") stringcols(_all)
rename (province cons_name) (pull_province pull_item)
keep pull_province pull_municipal_city pull_item pull_nsu_unit harmonized_nsu_unit
drop if missing(harmonized_nsu_unit)
nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
	mun(pull_municipal_city) province(pull_province)
replace harmonized_nsu_unit = ustrtrim(ustrlower(ustrto(harmonized_nsu_unit,"ascii",2)))
duplicates drop pull_province pull_municipal_city pull_item pull_nsu_unit, force
tempfile xw
save `xw'

use `prices', clear
merge m:1 pull_province pull_municipal_city pull_item pull_nsu_unit using `xw', ///
	keep(1 3) gen(_m_xw)
count if _m_xw == 1
di as txt "  price rows with no harmonized unit: " r(N)
keep if _m_xw == 3
drop _m_xw
tempfile withprice
save `withprice'

* ---- attach the grams published at that rung --------------------------------
use "${btemp}\nsu_reference_set", clear
keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	size_ord grams n_g d_thin weighing_approach
nsu_normalize, item(pull_item) unit(harmonized_nsu_unit) ///
	mun(pull_municipal_city) province(pull_province)
rename size_ord rung
duplicates drop pull_province pull_municipal_city pull_item harmonized_nsu_unit rung, force
tempfile ref
save `ref'

use `withprice', clear
merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit rung ///
	using `ref', keep(3) gen(_m_ref)
drop _m_ref
drop if missing(grams) | grams <= 0

gen double gpp = grams / p
label var gpp   "grams per peso at this case x rung"
label var p     "price at this rung, from the price file"
label var grams "grams the reference set publishes at this rung"
label var rung  "size_ord: 1 small / mp25, 2 medium / mp50, 3 large / mp75"

qui count
di as res "(price, grams) pairs on case x rung: " r(N)
di as res "  by branch of the reference rung:"
tab weighing_approach

sort pull_province pull_municipal_city pull_item harmonized_nsu_unit rung
save "${btemp}\price_weight_pairs", replace
di as txt "wrote ${btemp}\price_weight_pairs.dta"

********************************************************************************
**# 2. the province schedule
********************************************************************************
egen long grp = group(pull_province pull_item harmonized_nsu_unit), label

egen double gpp_med  = median(gpp), by(grp)
egen double _gpp_m   = mean(gpp),   by(grp)
egen double _gpp_sd  = sd(gpp),     by(grp)
gen  double cv_gpp   = _gpp_sd / _gpp_m if _gpp_m > 0
egen long   n_pairs  = count(gpp), by(grp)
egen long   n_price  = nvals(p),   by(grp)
egen long   n_mun    = nvals(pull_municipal_city), by(grp)

* nvals is from egenmore. Without it these come back missing and the estimable gate below
* silently passes everything, which is the worst possible failure for this file.
count if missing(n_price) | missing(n_mun)
if r(N) > 0 {
	di as err "egen nvals() returned missing -- egenmore is not installed."
	di as err "ssc install egenmore, or replace nvals with a tag-and-total."
	exit 199
}

collapse (first) pull_province pull_item harmonized_nsu_unit ///
         gpp_med cv_gpp n_pairs n_price n_mun, by(grp)

gen byte estimable = (n_price >= `MINPRICE' & n_mun >= `MINMUN')

label var gpp_med   "median grams per peso across the province -- the estimator"
label var cv_gpp    "ray fit: CV of w/p in this group. Lower predicts better accuracy"
label var n_pairs   "case x rung pairs behind the estimate"
label var n_price   "DISTINCT prices behind it -- the binding constraint"
label var n_mun     "municipalities it spans"
label var estimable "1 = >=3 distinct prices and >=2 municipalities; 0 = refuse a fallback"

di as res _n "province x item x harmonized-unit groups: " _N
count if estimable
di as res "  estimable (offer a fallback):     " r(N)
count if !estimable
di as res "  not estimable (refuse):           " r(N)

di as res _n "ray fit among estimable groups -- published, NOT enforced:"
summ cv_gpp if estimable, detail

sort pull_province pull_item harmonized_nsu_unit
save "${btemp}\province_schedule", replace
export delimited using "${btables}\province_schedule.csv", replace
di as txt "wrote ${btemp}\province_schedule.dta and ${btables}\province_schedule.csv"

********************************************************************************
**# 3. who is refused, and why
********************************************************************************
* A case is refused for one of two reasons, and they are not the same finding:
*   no schedule   -- its province group is not estimable (too few distinct prices)
*   no group      -- the item x harmonized unit was never weighed in this province
* Reported separately so the 41% is attributable rather than a single bucket.
tempfile sched
save `sched'

use "${btemp}\nsu_reference_set", clear
keep pull_province pull_item harmonized_nsu_unit
nsu_normalize, item(pull_item) unit(harmonized_nsu_unit) ///
	mun(pull_province) province(pull_province)
duplicates drop
merge 1:1 pull_province pull_item harmonized_nsu_unit using `sched', ///
	keepusing(estimable cv_gpp n_price n_mun) gen(_m_s)

gen str24 fallback_status = ""
replace  fallback_status = "offered"          if _m_s == 3 & estimable == 1
replace  fallback_status = "refused: no ray"  if _m_s == 3 & estimable == 0
replace  fallback_status = "refused: no group" if _m_s == 1
assert fallback_status != ""
drop _m_s

di as res _n "reference-set (province x item x unit) combinations by fallback status:"
tab fallback_status

preserve
	keep if fallback_status != "offered"
	keep pull_province pull_item harmonized_nsu_unit fallback_status n_price n_mun
	export delimited using "${btables}\fallback_refused.csv", replace
	di as txt "wrote ${btables}\fallback_refused.csv (" _N " combination(s))"
restore

di as res _n "30_fallback.do done -- schedule built; ATTACHING it to PSPS households"
di as res "needs the retrofit, which is not written (see dofiles/README.md)."
