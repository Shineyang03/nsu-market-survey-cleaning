********************************************************************************
* scope_price_weight_ray.do -- is grams-per-peso common within a province?
*
* THE QUESTION (issue #30, direction 2). A PSPS household buys an item x harmonized
* unit in a municipality where the market survey weighed nothing. One way to give it a
* weight is to estimate a grams-per-peso schedule across the province and apply it to
* the price that household actually faced.
*
* That never claims two municipalities' units are the same size. It claims a peso buys
* the same amount of food in both -- a statement about the local food market rather
* than about the unit. This file measures whether that holds.
*
* ------------------------------------------------------------------------------
* WHERE THE (PRICE, WEIGHT) PAIRS COME FROM -- and this is the part it is easy to get
* wrong. An earlier version of this file paired on `pull_price', the price recorded in
* the MARKET SURVEY. That is recorded only on the price-quantity branch, so it saw 1,109
* weighings and reported that a schedule could only be estimated where the survey had
* asked for a price. That conclusion was an artefact of the pairing, not a property of
* the data, and it understated the estimable base by roughly a factor of three.
*
* Outcome 2 does not pair that way. It puts BOTH branches on one rung ladder --
* `size_ord' in 10_size_assignment.do: for the price-quantity branch mp25/mp50/mp75 map
* to rungs 1/2/3 directly, and for the size-based branch the pooled weights are
* RE-TERCILED into the same three rungs. The reference set then publishes grams at each
* rung of each case. So a price point and a weight meet at (case x rung), and the price
* comes from the price file rather than from the market survey.
*
* Pairing that way:
*     2,877 tercile price rows, all of which resolve to a harmonized unit
*     1,260 (price, grams) pairs on case x rung
*     1,104 of them SIZE-BASED, which the old pairing could not see at all
*
* ------------------------------------------------------------------------------
* WHAT IT REPORTS, in the order #30 asks for it:
*
*   1  Do the (price, weight) pairs within a province lie on a RAY THROUGH THE ORIGIN?
*      Reported as the coefficient of variation of w/p within province x item x unit,
*      and drawn as a scatter with the median ray overlaid.
*   2  Is w/p TIGHTER THAN w ALONE? This is the entire case for conditioning on price.
*      If CV(w/p) is not below CV(w), the price bought nothing and this reduces to
*      pooling weights directly.
*   3  HOW MANY PAIRS per province x item x unit -- and how many DISTINCT PRICE POINTS.
*      A ray needs pairs at different prices; a group whose prices are all equal cannot
*      speak to the slope at all.
*   4  LEAVE-ONE-MUNICIPALITY-OUT. Estimate the schedule from the other municipalities
*      in the province, predict the held-out municipality's grams from its own price,
*      and compare to the grams the reference set publishes. This is the only real test;
*      everything above it is description.
*
* THE ESTIMATOR IS THE MEDIAN OF PER-PAIR RATIOS, w/p -- estimator (a) on #30. It is
* scale-free and does not weight pairs by price level.
*
* A LIMIT THAT REMAINS. The price file carries no date, so these prices cannot be put
* in a common frame the way `cpi_factor' puts market-survey prices in one. If the price
* points were collected across rounds, a schedule estimated from them absorbs inflation
* as if it were cross-municipality variation. That is a real caveat on every number
* below and it is not fixable from this input.
*
* RUN     from dofiles/:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\scope_price_weight_ray.do
*
* OUTPUT  ${btables}\price_weight_ray.csv       one row per province x item x unit
*         ${btables}\price_weight_ray_loo.csv   leave-one-municipality-out predictions
*         ${bgraphs}\price_weight_ray.png       the scatter, estimable groups only
*
* READ-ONLY on the build. Writes nothing the pipeline reads.
********************************************************************************

clear all
set more off
do "00_shared/00_globals.do"

* ---- 1. the tercile prices ----------------------------------------------------
import delimited using "${pricedata}", clear varnames(1) encoding("utf-8") ///
	stringcols(_all)

keep if inlist(price_type, "mp25_price", "mp50_price", "mp75_price")
gen byte rung = 1 if price_type == "mp25_price"
replace  rung = 2 if price_type == "mp50_price"
replace  rung = 3 if price_type == "mp75_price"
assert !missing(rung)

destring price, gen(p) force
rename (cons_name unit_lbl) (pull_item pull_nsu_unit)
rename province pull_province
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

* ---- 2. resolve each price row to a harmonized unit ---------------------------
* The crosswalk is keyed at cell x raw label, which is exactly the price file's grain.
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
di as txt "price rows with no harmonized unit: " r(N)
keep if _m_xw == 3
drop _m_xw

* ---- 3. attach the grams the reference set publishes at that rung -------------
tempfile withprice
save `withprice'

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

qui count
di as res "(price, grams) pairs on case x rung: " r(N)
di as res "  by branch of the reference rung:"
tab weighing_approach

gen double gpp = grams / p
label var gpp "grams per peso at this case x rung"

egen long grp = group(pull_province pull_item harmonized_nsu_unit), label

* ---- steps 1 & 2. spread of w/p against spread of w --------------------------
* CV rather than SD because the two quantities are in different units and the whole
* comparison is about RELATIVE spread. Meaningful only on a positive quantity, which
* both are by construction above.
foreach v in gpp grams p {
	egen double `v'_m  = mean(`v'), by(grp)
	egen double `v'_sd = sd(`v'),   by(grp)
	gen double cv_`v'  = `v'_sd / `v'_m if `v'_m > 0
}
egen long   n_pairs = count(gpp), by(grp)
egen long   n_price = nvals(p),   by(grp)
egen long   n_mun   = nvals(pull_municipal_city), by(grp)
egen double gpp_med = median(gpp), by(grp)

* nvals comes from egenmore. Without it the counts are missing and every gate below
* silently passes, so catch it here rather than in the output.
count if missing(n_price) | missing(n_mun)
if r(N) > 0 {
	di as err "egen nvals() returned missing -- egenmore is not installed."
	di as err "ssc install egenmore, or replace nvals with a tag-and-total."
	exit 199
}

preserve
	collapse (first) pull_province pull_item harmonized_nsu_unit ///
	         n_pairs n_price n_mun gpp_med cv_gpp cv_grams cv_p, by(grp)

	gen byte estimable = (n_price >= 3)
	gen double tighten = cv_gpp / cv_grams
	label var estimable "1 = at least 3 distinct prices, so a ray is identified"
	label var tighten   "CV(w/p) / CV(w); below 1 means the price bought something"

	di as res _n "groups (province x item x harmonized unit): " _N
	count if estimable
	di as res "  estimable (>=3 distinct prices):       " r(N)
	count if estimable & n_mun >= 2
	di as res "  of those, spanning >=2 municipalities: " r(N)
	count if estimable & tighten < 1
	di as res "  of those, w/p tighter than w alone:    " r(N)

	di as res _n "spread of w/p vs w, estimable groups:"
	summ cv_gpp cv_grams tighten if estimable, sep(0)

	gsort -estimable -cv_gpp
	di as res _n "estimable groups, worst ray fit first:"
	list pull_province pull_item harmonized_nsu_unit n_pairs n_price n_mun ///
	     gpp_med cv_gpp cv_grams tighten if estimable, noobs abbrev(20) sep(0)

	export delimited using "${btables}\price_weight_ray.csv", replace
	di as txt "wrote ${btables}\price_weight_ray.csv"
restore

* ---- step 4. leave-one-municipality-out --------------------------------------
* For each municipality with a published rung, estimate the schedule from the OTHER
* municipalities in the same province x item x unit and predict this one's grams from
* its own price. Stata has no by-group median that excludes the current group, so it is
* done with an explicit loop -- clearer than the alternatives and cheap at this size.
preserve
	keep if n_price >= 3 & n_mun >= 2
	qui count
	if r(N) == 0 {
		di as err "no group has >=3 distinct prices AND >=2 municipalities;"
		di as err "the leave-one-out test is not available on this vintage."
	}
	else {
		gen double gpp_loo = .
		levelsof grp, local(gs)
		foreach g of local gs {
			levelsof pull_municipal_city if grp == `g', local(ms) clean
			foreach m of local ms {
				qui summ gpp if grp == `g' & pull_municipal_city != "`m'", detail
				qui replace gpp_loo = r(p50) ///
					if grp == `g' & pull_municipal_city == "`m'"
			}
		}
		gen double w_pred = gpp_loo * p
		gen double ratio  = w_pred / grams
		label var gpp_loo "median w/p from the OTHER municipalities in this group"
		label var w_pred  "grams predicted for this rung from its own price"
		label var ratio   "predicted / published"

		di as res _n "leave-one-municipality-out, " _N " pair(s):"
		summ ratio, detail

		* A prediction is useful only if it lands in the right decade -- the standard
		* the rest of this project holds weights to.
		gen byte within_2x  = inrange(ratio, 0.5, 2)
		gen byte within_dec = inrange(ratio, 0.1, 10)
		qui summ within_2x
		di as res "  within 2x of the published value: " %5.1f 100*r(mean) "%"
		qui summ within_dec
		di as res "  within a decade:                  " %5.1f 100*r(mean) "%"

		* Does the ray fit identify where the schedule works? This is the screen #30
		* proposed. Reported by CV band so a non-monotonic answer is visible.
		di as res _n "accuracy by the group's ray fit (the proposed screen):"
		gen byte cvband = 1 if cv_gpp < 0.2
		replace  cvband = 2 if inrange(cv_gpp, 0.2, 0.4)
		replace  cvband = 3 if cv_gpp > 0.4 & cv_gpp <= 0.6
		replace  cvband = 4 if cv_gpp > 0.6
		label define cvb 1 "CV<0.2" 2 "0.2-0.4" 3 "0.4-0.6" 4 ">0.6", replace
		label values cvband cvb
		table cvband, statistic(frequency) ///
			statistic(mean within_2x) statistic(mean within_dec) ///
			statistic(median ratio) nformat(%6.3f)

		keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		     rung weighing_approach p grams n_g d_thin ///
		     gpp gpp_loo w_pred ratio n_pairs n_price n_mun cv_gpp
		export delimited using "${btables}\price_weight_ray_loo.csv", replace
		di as txt "wrote ${btables}\price_weight_ray_loo.csv"
	}
restore

* ---- the picture -------------------------------------------------------------
* One panel per estimable group, grams against price, with the median ray through the
* origin drawn on. Pairs near the ray support a common exchange rate; a cloud, or a
* flat band, does not.
preserve
	keep if n_price >= 3
	qui count
	if r(N) > 0 {
		gen double ray = gpp_med * p
		egen long _rank = group(grp)
		qui summ _rank
		local nmax = min(r(max), 12)
		keep if _rank <= `nmax'

		twoway (scatter grams p, msize(small) mcolor(navy%60)) ///
		       (line ray p, sort lcolor(cranberry) lpattern(dash)) ///
		       , by(grp, note("dashed = ray through the origin at the group's median w/p") ///
		             title("Do (price, weight) pairs lie on a ray through the origin?") ///
		             subtitle("tercile prices against the grams published at that rung") ///
		             legend(off)) ///
		         xtitle("price at this rung") ytitle("grams published at this rung")
		graph export "${bgraphs}\price_weight_ray.png", replace width(2000)
		di as txt "wrote ${bgraphs}\price_weight_ray.png (`nmax' panel(s))"
	}
restore

di as res _n "scope_price_weight_ray.do done"
