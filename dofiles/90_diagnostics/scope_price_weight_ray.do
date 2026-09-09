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
* WHAT IT REPORTS, in the order #30 asks for it:
*
*   1  Do the (price, weight) pairs within a province lie on a RAY THROUGH THE ORIGIN?
*      Reported as the coefficient of variation of w/p within province x item x unit,
*      and drawn as a scatter with the median ray overlaid.
*   2  Is w/p TIGHTER THAN w ALONE? This is the entire case for conditioning on price.
*      If CV(w/p) is not below CV(w), the price bought nothing and this reduces to
*      pooling weights directly.
*   3  HOW MANY PAIRS are there per province x item x unit -- and, the binding number,
*      how many DISTINCT PRICE POINTS. A ray needs pairs at different prices; a group
*      whose prices are all equal cannot speak to the slope at all.
*   4  LEAVE-ONE-MUNICIPALITY-OUT. Estimate the schedule from the other municipalities
*      in the province, predict the held-out municipality's grams from its own price,
*      and compare to what was actually weighed. This is the only real test; everything
*      above it is description.
*
* THE ESTIMATOR IS THE MEDIAN OF PER-PAIR RATIOS, w/p -- estimator (a) on #30. It is
* scale-free and does not weight pairs by price level, and it is what was chosen over
* the two regression variants.
*
* WHERE THE PAIRS COME FROM, AND THE LIMIT THAT IMPOSES. `pull_price' is recorded ONLY
* on the price-quantity branch (weighing_approach == 2): 1,109 weighings carry both a
* price and a weight, against 9,753 size-based weighings that carry no market-survey
* price at all. So the schedule can only ever be estimated where the survey asked for a
* price, and the question of whether it EXTENDS to size-based cases is not answerable
* from this file.
*
* PRICES ARE DEFLATED BEFORE POOLING. A household's price is a PSPS-period price and the
* market-survey weights carry `cpi_factor'. Pooling nominal prices across rounds would
* let the schedule absorb inflation as if it were cross-municipality variation.
*
* RUN     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\scope_price_weight_ray.do
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

use "${btemp}\nsu_weighings_cpi", clear

* ---- the pairs ---------------------------------------------------------------
* One pair per weighing: the price the vendor was quoted and the grams delivered.
keep if weighing_approach == 2
keep if !missing(pull_price) & pull_price > 0
keep if !missing(corrected_weight) & corrected_weight > 0
keep if !missing(cpi_factor) & cpi_factor > 0

* Deflate to a common frame. cpi_factor is the multiplier the pipeline already uses.
gen double p_real = pull_price / cpi_factor
gen double gpp    = corrected_weight / p_real
label var p_real "price, deflated to the cpi_factor base frame"
label var gpp    "grams per peso for this weighing"

qui count
di as res _n "pairs (price-quantity weighings with a price and a weight): " r(N)

egen long grp = group(pull_province pull_item harmonized_nsu_unit), label

* ---- 1 & 2. spread of w/p against spread of w -------------------------------
* CV rather than SD because the two quantities are in different units and the whole
* comparison is about RELATIVE spread. A CV is only meaningful on a positive quantity,
* which both are here by construction above.
foreach v in gpp corrected_weight p_real {
	egen double `v'_m  = mean(`v'), by(grp)
	egen double `v'_sd = sd(`v'),   by(grp)
	gen double cv_`v'  = `v'_sd / `v'_m if `v'_m > 0
}
egen long   n_pairs  = count(gpp),         by(grp)
egen long   n_price  = nvals(p_real),      by(grp)
egen long   n_mun    = nvals(pull_municipal_city), by(grp)
egen double gpp_med  = median(gpp),        by(grp)

* nvals is not built in everywhere; if the egen extension is absent the counts above
* are missing and every gate below silently passes. Catch that rather than discover it
* in the output.
count if missing(n_price) | missing(n_mun)
if r(N) > 0 {
	di as err "egen nvals() returned missing -- `egenmore' is not installed."
	di as err "ssc install egenmore, or replace nvals with a tag-and-total."
	exit 199
}

* ---- the report ---------------------------------------------------------------
preserve
	collapse (first) pull_province pull_item harmonized_nsu_unit ///
	         n_pairs n_price n_mun gpp_med ///
	         cv_gpp cv_corrected_weight cv_p_real, by(grp)

	* A group whose prices are all equal cannot speak to a slope, however many
	* weighings it holds. This is the gate #30 step 3 asks about, and it is far more
	* binding than the pair count.
	gen byte estimable = (n_price >= 3)

	* Does conditioning on price tighten anything? Below 1 means yes.
	gen double tighten = cv_gpp / cv_corrected_weight

	label var estimable "1 = at least 3 distinct deflated prices, so a ray is identified"
	label var tighten   "CV(w/p) / CV(w); below 1 means the price bought something"

	di as res _n "groups (province x item x harmonized unit): " _N
	count if estimable
	di as res "  of which estimable (>=3 distinct prices): " r(N)
	count if estimable & tighten < 1
	di as res "  of those, w/p tighter than w alone:       " r(N)
	count if estimable & n_mun >= 2
	di as res "  of those, spanning >=2 municipalities:    " r(N)

	di as res _n "spread of w/p vs w, estimable groups:"
	summ cv_gpp cv_corrected_weight tighten if estimable, sep(0)

	gsort -estimable -n_price
	di as res _n "estimable groups, worst ray fit first:"
	gsort -estimable -cv_gpp
	list pull_province pull_item harmonized_nsu_unit n_pairs n_price n_mun ///
	     gpp_med cv_gpp cv_corrected_weight tighten if estimable, ///
	     noobs abbrev(20) sep(0)

	export delimited using "${btables}\price_weight_ray.csv", replace
	di as txt "wrote ${btables}\price_weight_ray.csv"
restore

* ---- 4. leave-one-municipality-out -------------------------------------------
* For each municipality that DOES have weights, estimate the schedule from the OTHER
* municipalities in the same province x item x unit and predict this one's grams from
* its own prices. Only groups spanning at least two municipalities can be tested.
*
* Computed as a leave-one-out median by hand: Stata has no by-group median that
* excludes the current group, and doing it with a loop over municipalities is both
* clearer and cheap at this size.
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
		gen double w_pred = gpp_loo * p_real
		gen double ratio  = w_pred / corrected_weight
		label var gpp_loo "median w/p from the OTHER municipalities in this group"
		label var w_pred  "grams predicted for this weighing from its own price"
		label var ratio   "predicted / actual"

		di as res _n "leave-one-municipality-out, " _N " weighing(s) in " ///
			as res "groups spanning >=2 municipalities:"
		summ ratio, detail

		* A prediction is only useful if it lands in the right decade. That is the
		* standard the rest of this project holds weights to.
		gen byte within_2x   = inrange(ratio, 0.5, 2)
		gen byte within_dec  = inrange(ratio, 0.1, 10)
		qui summ within_2x
		di as res "  within 2x of the weighed value:  " %5.1f 100*r(mean) "%"
		qui summ within_dec
		di as res "  within a decade:                 " %5.1f 100*r(mean) "%"

		keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		     item_nsu_hetero_type pull_price p_real corrected_weight ///
		     gpp gpp_loo w_pred ratio n_pairs n_price n_mun
		export delimited using "${btables}\price_weight_ray_loo.csv", replace
		di as txt "wrote ${btables}\price_weight_ray_loo.csv"
	}
restore

* ---- the picture -------------------------------------------------------------
* One panel per estimable group, weight against deflated price, with the median ray
* through the origin drawn on. A group whose pairs sit near its ray supports a common
* exchange rate; a cloud, or a flat band, does not.
preserve
	keep if n_price >= 3
	qui count
	if r(N) > 0 {
		gen double ray = gpp_med * p_real
		* Cap the panel count so the graph stays legible; the CSV carries them all.
		egen long _rank = group(grp)
		qui summ _rank
		local nmax = min(r(max), 12)
		keep if _rank <= `nmax'

		twoway (scatter corrected_weight p_real, msize(small) mcolor(navy%60)) ///
		       (line ray p_real, sort lcolor(cranberry) lpattern(dash)) ///
		       , by(grp, note("dashed = ray through the origin at the group's median w/p") ///
		             title("Do (price, weight) pairs lie on a ray through the origin?") ///
		             subtitle("price-quantity weighings, price deflated by cpi_factor") ///
		             legend(off)) ///
		         xtitle("deflated price") ytitle("corrected weight (g/mL)")
		graph export "${bgraphs}\price_weight_ray.png", replace width(2000)
		di as txt "wrote ${bgraphs}\price_weight_ray.png (`nmax' panel(s))"
	}
restore

di as res _n "scope_price_weight_ray.do done"
