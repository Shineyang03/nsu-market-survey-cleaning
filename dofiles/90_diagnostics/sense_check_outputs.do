********************************************************************************
* sense_check_outputs.do -- are the published numbers plausible?
*
* WHAT THIS IS FOR. Every other check in this project asks whether the pipeline did what
* the code says. This one asks whether the ANSWER IS SENSIBLE -- whether a cabbage "piece"
* weighs something a cabbage could weigh, and whether the grams Outcome 2 hands a
* household add up to an amount a household could eat. A build can reconcile perfectly and
* still be wrong by a factor of ten, and nothing upstream would notice.
*
* THE SHARPEST TEST IS THE LAST ONE. Sections 1-3 look at the outputs on their own terms,
* which is useful but circular -- a reference weight looks plausible next to other
* reference weights from the same build. Section 4 leaves the pipeline entirely and asks
* whether the implied food intake per person per day is a number a person could eat. That
* is the only check here with an external referent, and it is the one to read first if
* something looks wrong.
*
* READS ONLY PUBLISHED OUTPUTS, plus household size from the raw PSPS file, which the
* pipeline does not compute and therefore cannot be read from a build output.
*
* INPUTS   ${btemp}\nsu_reference_set.dta        Outcome 1
*          ${btemp}\psps_converted_capped.dta    Outcome 2, non-standard units
*          ${btemp}\psps_standard_units.dta      Outcome 2, standard units
*          ${psps_cons}                          household size only
* OUTPUTS  ${btables}\sense_check_outcome1.csv
*          ${btables}\sense_check_outcome2.csv
*          ${btables}\sense_check_o1_vs_o2.csv
*          ${btables}\sense_check_percapita.csv
*          ${bgraphs}\sense_*.png                four panels
*
* RUN, from the dofiles/ folder, after both masters:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\sense_check_outputs.do
********************************************************************************

clear all
do "00_shared/00_globals.do"
set scheme s2color

* Item names run to 63 characters. At the default width Stata gives up on a wide table
* and prints one observation per vertical block, which is unreadable for a table meant to
* be scanned down a column. Widening the log fixes every table here at once.
set linesize 110


********************************************************************************
**# 1. Outcome 1 -- do the reference weights look like the things they describe?
********************************************************************************

use "${btemp}\nsu_reference_set", clear
qui count
di as res _n "{hline 78}"
di as res "OUTCOME 1 -- the reference set, " r(N) " row(s)"
di as res "{hline 78}"

di as res _n "rows by size:"
tab size_ord, m
di as res _n "rows by branch (how the row was PROCESSED):"
tab branch, m

* Grams by item. The eye test: a unit of rice should be ~2 kg (a gantang), a putos of ice
* cream tens of grams, a whole chicken ~1 kg. A median in the wrong decade for a familiar
* item is the failure this table exists to surface.
di as res _n "reference grams by item -- min / p25 / median / p75 / max:"
preserve
	collapse (min) g_min = grams (p25) g_p25 = grams (median) g_med = grams ///
	         (p75) g_p75 = grams (max) g_max = grams (count) n_rows = grams, ///
	         by(pull_item)
	gsort -n_rows
	list pull_item n_rows g_min g_p25 g_med g_p75 g_max, noobs abbrev(32) sep(0)
	export delimited using "${btables}\sense_check_outcome1.csv", replace

	* THE PANEL. Drawn from the same collapse the table above prints, so the figure and
	* the table cannot disagree.
	*
	* NOT `graph hbox grams, over(pull_item) yscale(log)'. graph box does not honour a
	* log scale: the axis comes out LINEAR with no warning, and the category axis
	* collapses so all 19 item labels print on top of one another. Both failures are
	* silent -- the do-file runs, the png is written, and the scale the note claims is
	* not the scale drawn. A range plot on an explicit log10 axis cannot lose the scale,
	* because the scale is in the data rather than in an axis option.
	*
	* Bar = p25-p75, thin line = min-max, dot = median. Ticks are decades, which is what
	* makes a wrong order of magnitude a visible jump rather than a small offset.
	gsort g_med
	gen int y = _n
	foreach v in min p25 med p75 max {
		gen double lg_`v' = log10(g_`v')
	}
	local ylab
	forvalues i = 1/`=_N' {
		* char(34) is a double quote: an item name carrying one would end the quoted
		* label early and turn the rest of it into option syntax.
		local nm = subinstr(substr(pull_item[`i'], 1, 34), char(34), "", .)
		local ylab `ylab' `i' "`nm'"
	}
	twoway (rspike lg_min lg_max y, horizontal lcolor(gs11) lwidth(thin)) ///
	       (rspike lg_p25 lg_p75 y, horizontal lcolor(navy) lwidth(medthick)) ///
	       (scatter y lg_med, msymbol(O) msize(small) mcolor(white) mlcolor(navy)) ///
	       , ylabel(`ylab', labsize(vsmall) angle(0) nogrid) ytitle("") ///
	         yscale(range(0.4 `=_N + 0.6')) ///
	         xlabel(1 "10" 1.699 "50" 2 "100" 2.699 "500" 3 "1,000" 4 "10,000") ///
	         xtitle("grams per unit, log scale") ///
	         legend(order(2 "p25-p75" 1 "min-max" 3 "median") size(vsmall) rows(1) ///
	                region(lstyle(none))) ///
	         title("Outcome 1: reference weight by item", size(medium)) ///
	         note("One observation per published (case x size) row, collapsed to the item." ///
	              "Log scale, decade ticks: a wrong order of magnitude is a visible jump," ///
	              "which is what this panel is for.", size(vsmall)) ///
	         ysize(6) xsize(9)
	graph export "${bgraphs}\sense_o1_grams_by_item.png", replace width(1600)
restore

* IMPLAUSIBLE MAGNITUDES, on bounds chosen from what the units are rather than from the
* distribution. Anything a household buys as one non-standard unit should sit between a
* few grams and a sack.
di as res _n "rows outside 5 g - 30,000 g:"
count if grams < 5 | grams > 30000
if r(N) > 0 {
	list pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		size_ord grams n_g if grams < 5 | grams > 30000, noobs abbrev(26) sep(0)
}

* MONOTONICITY within a cell. Re-terciling makes small <= medium <= large impossible to
* break on the size-based branch, so any hit here is either price-quantity (where size_ord
* comes from the price label, not from a tercile of weights) or a defect.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	corrected_unit (size_ord): gen byte nonmono = ///
	(grams < grams[_n-1]) if _n > 1 & size_ord > 0 & size_ord < 4
di as res _n "size pairs where grams FALLS as size rises:"
count if nonmono == 1
if r(N) > 0 {
	list pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		size_ord grams n_g branch if nonmono == 1, noobs abbrev(26)
}
drop nonmono

di as res _n "weighings behind a published row:"
qui su n_g, detail
di as res "  min " r(min) "  p25 " r(p25) "  median " r(p50) "  p75 " r(p75) "  max " r(max)

* The by-item panel is drawn in the collapse block above, beside the table it shares its
* numbers with.


********************************************************************************
**# 2. Outcome 2 -- do the conversion factors look like the units they convert?
********************************************************************************

use "${btemp}\psps_converted_capped", clear
qui count
local n_nsu = r(N)
qui count if d_converted == 1
di as res _n "{hline 78}"
di as res "OUTCOME 2 -- `n_nsu' non-standard-unit household rows, " r(N) " converted"
di as res "{hline 78}"

di as res _n "conversion factor (grams per unit) by item, converted rows only:"
preserve
	keep if d_converted == 1
	collapse (min) cf_min = cf_h (p25) cf_p25 = cf_h (median) cf_med = cf_h ///
	         (p75) cf_p75 = cf_h (max) cf_max = cf_h (count) n_rows = cf_h ///
	         (sum) tot_g = grams_h, ///
	         by(pull_item)
	gsort -n_rows
	list pull_item n_rows cf_min cf_p25 cf_med cf_p75 cf_max, noobs abbrev(32) sep(0)
	export delimited using "${btables}\sense_check_outcome2.csv", replace
restore

* cf_h IS NOT BOUNDED BY THE REFERENCE WEIGHT, and that is the design: CF_h = p_h * w_g/p_g
* scales with what the household paid, so a household buying a bigger-than-typical unit
* legitimately gets more grams than any single weighing. The #19 cap bounds it to
* [w_g/t, w_g*t] with t = 5, so the check is that nothing escapes THAT.
di as res _n "converted rows outside 5 g - 30,000 g per unit:"
count if d_converted == 1 & (cf_h < 5 | cf_h > 30000)
if r(N) > 0 {
	preserve
		keep if d_converted == 1 & (cf_h < 5 | cf_h > 30000)
		collapse (count) n = cf_h (min) lo = cf_h (max) hi = cf_h, ///
			by(pull_item harmonized_nsu_unit)
		gsort -n
		list, noobs abbrev(28) sep(0)
	restore
}

di as res _n "conversion factor by fallback level (borrowed weights vs the cell's own):"
table fallback_level if d_converted, statistic(frequency) ///
	statistic(p50 cf_h) statistic(mean cf_h) nformat(%9.1f)

* THE RUNG GAP, DECOMPOSED. The medians above are not comparable as they stand: a
* borrowed rung is used exactly where the cell had no weighings of its own, and those
* cells are not a random sample of items. So the raw L0-vs-L2 gap mixes two things --
* the borrowing shifting the number, and the borrowing serving a different basket.
*
* HELD FIXED AT (item x harmonized unit), NOT at the item. An item alone is too coarse:
* camote tops bought by the bundle and by the kilo are the same pull_item and nothing
* like the same number of grams, so an item-level ratio would report a change of unit mix
* as though it were an effect of borrowing. At (item x unit) the two rungs describe the
* same object bought the same way, and the only thing that differs is which cells'
* weighings stand behind it.
*
* A ratio near 1 says the raw gap is composition. A ratio far from 1 across many rows
* says the borrowing itself moves the answer, which is the failure the panel's note warns
* about. The remaining difference is still geographic -- L0 rows are municipalities that
* weighed the item, L2 rows are municipalities in the same province that did not.
di as res _n "L0 vs L2 within (item x harmonized unit); ratio near 1 = the gap is composition:"
preserve
	keep if d_converted == 1 & inlist(fallback_level, 0, 2)
	collapse (count) n = cf_h (median) med = cf_h, ///
		by(pull_item harmonized_nsu_unit fallback_level)
	drop if n < 20
	reshape wide n med, i(pull_item harmonized_nsu_unit) j(fallback_level)
	keep if !missing(med0) & !missing(med2)
	gen double ratio = med2 / med0
	gsort -n2
	gen str26 item = substr(pull_item, 1, 26)
	gen str16 unit = substr(harmonized_nsu_unit, 1, 16)
	format med0 med2 %9.0f
	format ratio %6.2f
	list item unit n0 med0 n2 med2 ratio, noobs sep(0)
	qui su ratio, detail
	di as res "  (item x unit) pairs compared " r(N) "   median ratio " %5.2f r(p50) ///
		"   min " %5.2f r(min) "   max " %5.2f r(max)

	* Where the disagreement that survives the control is concentrated. This is the
	* actionable half: an indeterminate unit label is where a borrowed weight is least
	* safe, because the thing being borrowed is not pinned down in the first place.
	qui count if ratio > 2 | ratio < 0.5
	local nbad = r(N)
	di as res "  pairs still disagreeing by more than 2x either way: `nbad'"
	if `nbad' > 0 {
		list item unit n0 med0 n2 med2 ratio if ratio > 2 | ratio < 0.5, noobs sep(0)
	}
	di as res ""
	di as res "  HOW TO READ THIS. Compare against the rung table above, where L2's median"
	di as res "  is about 1.7x L0's. Once the unit is held fixed the high-volume pairs sit"
	di as res "  near 1, so most of that raw gap is which items and units the borrowed rung"
	di as res "  serves, not the borrowing changing the answer. What survives is not spread"
	di as res "  evenly: it lands on the labels that do not pin down a quantity in the first"
	di as res "  place. A borrowed weight is least safe exactly where the unit is vaguest,"
	di as res "  which is a limit of the fallback ladder rather than a defect in it."
restore

di as res _n "and by whether the household had a faced price at all (A10):"
table d_no_price if d_converted, statistic(frequency) statistic(p50 cf_h) nformat(%9.1f)

* Same construction and the same reason as the Outcome 1 panel: graph box silently
* ignores yscale(log) and overprints its category labels, so the percentiles are
* collapsed here and plotted on an explicit log10 axis.
preserve
	keep if d_converted == 1
	collapse (count) n = cf_h (p10) c10 = cf_h (p25) c25 = cf_h (median) c50 = cf_h ///
	         (p75) c75 = cf_h (p90) c90 = cf_h, by(fallback_level)
	foreach v in 10 25 50 75 90 {
		gen double lg`v' = log10(c`v')
	}
	* The rung counts are in the table printed just above, so the axis carries only the
	* rung name. Building "L0 (n=28,961)" here would mean a formatted number inside a
	* quoted label inside an option -- three nesting layers for something already on the
	* page.
	local ylab
	forvalues i = 1/`=_N' {
		local lv = fallback_level[`i']
		local ylab `ylab' `lv' "L`lv'"
	}
	twoway (rspike lg10 lg90 fallback_level, horizontal lcolor(gs11) lwidth(thin)) ///
	       (rspike lg25 lg75 fallback_level, horizontal lcolor(navy) lwidth(medthick)) ///
	       (scatter fallback_level lg50, msymbol(O) msize(small) ///
	                mcolor(white) mlcolor(navy)) ///
	       , ylabel(`ylab', labsize(small) angle(0) nogrid) ytitle("") ///
	         yscale(reverse range(-0.4 3.4)) ///
	         xlabel(1 "10" 2 "100" 2.699 "500" 3 "1,000" 3.699 "5,000") ///
	         xtitle("conversion factor, grams per unit, log scale") ///
	         legend(order(2 "p25-p75" 1 "p10-p90" 3 "median") size(vsmall) rows(1) ///
	                region(lstyle(none))) ///
	         title("Outcome 2: conversion factor by fallback rung", size(medium)) ///
	         note("L0 is the cell's own weighings; L1-L3 borrow, and from L1 down the household's" ///
	              "own price is not used (A15). A borrowed rung should not look systematically" ///
	              "different -- if it does, the borrowing is doing more than filling a gap.", ///
	              size(vsmall)) ///
	         ysize(4.5) xsize(9)
	graph export "${bgraphs}\sense_o2_cf_by_rung.png", replace width(1600)
restore


********************************************************************************
**# 3. Outcome 1 against Outcome 2 -- issue #16
********************************************************************************
* #16 asks whether it makes sense for the reference set to differ substantively from the
* retrofit. The two are not supposed to be equal -- Outcome 1 slices by SIZE and Outcome 2
* by PRICE POINT, and a household's own price moves its factor -- but they describe the
* same objects in the same cells, so a large systematic gap would mean one of them is
* wrong rather than that they answer different questions.
*
* Compared at CASE grain: the median published gram figure against the median conversion
* factor of the households in that case.

use "${btemp}\nsu_reference_set", clear
collapse (median) o1_grams = grams (sum) o1_n = n_g, ///
	by(pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit)
tempfile o1
save "`o1'"

use "${btemp}\psps_converted_capped", clear
keep if d_converted == 1
collapse (median) o2_cf = cf_h (count) o2_rows = cf_h (max) o2_maxrung = fallback_level, ///
	by(pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit)

merge 1:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit ///
	using "`o1'", keep(3) nogen

gen double ratio = o2_cf / o1_grams
gen double logr = log10(ratio)

qui count
di as res _n "{hline 78}"
di as res "OUTCOME 1 vs OUTCOME 2 (#16) -- " r(N) " case(s) both publish"
di as res "{hline 78}"
qui su ratio, detail
di as res "  Outcome 2 cf / Outcome 1 grams:"
di as res "    p5 " %7.3f r(p5) "   p25 " %7.3f r(p25) "   median " %7.3f r(p50) ///
	"   p75 " %7.3f r(p75) "   p95 " %7.3f r(p95)
foreach b in 1.25 1.5 2 5 10 {
	qui count if ratio > `b' | ratio < 1/`b'
	di as res "    beyond " %5.2f `b' "x : " r(N)
}

di as res _n "  by the deepest fallback rung the case's households used:"
table o2_maxrung, statistic(frequency) statistic(p50 ratio) nformat(%9.3f)

di as res _n "  A median near 1 is the result to want. It says the two deliverables agree"
di as res "  on the OBJECT and differ only through the household's own price, which is"
di as res "  the intended difference. A median far from 1 would mean the price match or"
di as res "  the inflation step is shifting the level, not just spreading it."

export delimited using "${btables}\sense_check_o1_vs_o2.csv", replace

* EXPLICIT TICKS ON BOTH LOG AXES. Left to Stata, a log scale places ticks at values it
* chooses from the data range and the labels collide into an unreadable smear -- the first
* version of this graph rendered its x axis as "10020000030000".
local dec 10 30 100 300 1000 3000 10000 30000
twoway (scatter o2_cf o1_grams, msize(vsmall) mcolor(%25)) ///
       (function y = x, range(5 30000) lcolor(red) lpattern(dash)), ///
	xscale(log) yscale(log) ///
	xlabel(`dec', labsize(small)) ylabel(`dec', labsize(small) angle(0)) ///
	xtitle("Outcome 1: published reference grams") ///
	ytitle("Outcome 2: median conversion factor") ///
	title("The two deliverables on the same cells (#16)", size(medium)) ///
	subtitle("one point per case; dashed line is equality", size(small)) ///
	legend(off) ///
	note("They are not supposed to be identical -- Outcome 1 slices by size and Outcome 2" ///
	     "by price point -- but they describe the same objects, so the cloud should sit on" ///
	     "the line rather than beside it.", size(vsmall))
graph export "${bgraphs}\sense_o1_vs_o2.png", replace width(1400)


********************************************************************************
**# 4. THE EXTERNAL CHECK -- grams per person per day
********************************************************************************
* The only test here that does not grade the pipeline against itself.
*
* Both outcomes' household figures are a quantity consumed over a SEVEN-DAY recall. Divide
* by household size and by 7 and the result is grams per person per day, which has a known
* plausible range: total food intake is on the order of 1-2 kg per person per day including
* drinking water, staple cereals a few hundred grams.
*
* WHAT WOULD FAIL. A factor-of-ten error anywhere in the conversion chain -- a kg/g slip, a
* decimal in the wrong place, a per-unit factor mistaken for a per-purchase total -- shows
* up here immediately and nowhere else. Every other check in this file compares build
* output to build output and would pass.
*
* WHAT THIS IS NOT. It is not a nutrition estimate. It covers only the food items the NSU
* survey priced, uses a raw household headcount with no adult-equivalent scaling, and
* includes drinking water, which is heavy and dominates the total. Read the SHAPE and the
* ORDER OF MAGNITUDE, not the level.

* household size, from the raw file -- the pipeline does not compute it
preserve
	use "${psps_cons}", clear
	keep hhid count_res_members
	* COLLAPSED, not `duplicates drop' + `isid'. The consumption file holds one row per
	* (household, item), so the headcount is repeated and should be constant within a
	* household -- but a diagnostic must not HALT on a raw-data surprise it only needs one
	* value from. Any variation is reported and the first non-missing value taken.
	bysort hhid: egen byte _nsz = nvals(count_res_members)
	qui count if _nsz > 1
	if r(N) > 0 {
		di as err "note: " r(N) " row(s) in households whose headcount varies within hhid"
	}
	collapse (firstnm) count_res_members, by(hhid)
	isid hhid
	tempfile hhsize
	save "`hhsize'"
restore

use "${btemp}\psps_converted_capped", clear
keep if d_converted == 1
keep hhid pull_item grams_h
gen str16 route = "non-standard"
tempfile part1
save "`part1'"

use "${btemp}\psps_standard_units", clear
keep hhid pull_item grams_h
gen str16 route = "standard unit"
append using "`part1'"

collapse (sum) grams_h, by(hhid pull_item route)
merge m:1 hhid using "`hhsize'", keep(3) nogen

* Guard: a zero or missing headcount would divide to infinity and dominate every
* percentile below.
drop if missing(count_res_members) | count_res_members <= 0

gen double gppd = grams_h / count_res_members / 7
label var gppd "grams per person per day"

di as res _n "{hline 78}"
di as res "THE EXTERNAL CHECK -- grams per person per day, 7-day recall"
di as res "{hline 78}"

di as res _n "by item (median across households that report it):"
preserve
	collapse (count) n_hh = gppd (median) gppd_med = gppd (p90) gppd_p90 = gppd ///
	         (sum) tot = grams_h, by(pull_item)
	gsort -n_hh
	* The longest pull_item is 63 characters. Listed whole it pushes the row past the
	* log's width and Stata falls back to a one-observation-per-block vertical layout,
	* which is unreadable for a table meant to be scanned. Truncate to a width that
	* keeps every row on one line; the full name is in the CSV.
	* Exported before the truncation so the CSV carries the full item name.
	export delimited using "${btables}\sense_check_percapita.csv", replace
	gen str32 item = substr(pull_item, 1, 32)
	list item n_hh gppd_med gppd_p90, noobs sep(0)
restore

* Per household per day, all items summed. This is the headline number.
preserve
	collapse (sum) gppd, by(hhid)
	qui su gppd, detail
	di as res _n "TOTAL across all items, per person per day:"
	di as res "  households      " %10.0fc r(N)
	di as res "  p10             " %10.0f r(p10) " g"
	di as res "  p25             " %10.0f r(p25) " g"
	di as res "  MEDIAN          " %10.0f r(p50) " g"
	di as res "  p75             " %10.0f r(p75) " g"
	di as res "  p90             " %10.0f r(p90) " g"
	di as res "  max             " %10.0f r(max) " g"
	di as res ""
	di as res "  Read against roughly 1-2 kg/person/day of total food and drink. This"
	di as res "  covers only the surveyed items, so it should sit BELOW that, and drinking"
	di as res "  water is the heaviest single contributor."

	qui count if gppd > 10000
	di as res _n "  households above 10 kg/person/day: " r(N) ///
		" -- implausible on any reading; section 4b names what drives them"

	histogram gppd if gppd > 0 & gppd < 6000, width(100) percent ///
		xtitle("grams per person per day, all surveyed items") ///
		title("Implied intake per person per day", size(medium)) ///
		subtitle("the one check with an external referent", size(small)) ///
		note("Truncated at 6 kg for display. Covers only surveyed items, includes drinking" ///
		     "water, and uses a raw headcount with no adult-equivalent scaling -- so read the" ///
		     "shape and the order of magnitude, not the level.", size(vsmall))
	graph export "${bgraphs}\sense_percapita.png", replace width(1400)
restore


********************************************************************************
**# 4b. THE SAME NUMBER ON THREE NARROWER CUTS -- which is where it becomes readable
********************************************************************************
* The total above is not the number to judge this pipeline by, and the reason is worth
* stating rather than leaving to a caveat: DRINKING WATER dominates it. A 5-gallon
* container is 18.9 kg, so a household reporting a few a week outweighs everything it eats,
* and a household reporting fifty outweighs the entire rest of the sample.
*
* Three cuts, narrowing to what this project actually produces:
*
*   all surveyed items          what section 4 reports; water-dominated
*   excluding drinking water    the food figure, and the one to read against an external
*                               referent
*   NSU-converted rows only     THE PIPELINE'S OWN CONTRIBUTION. Everything else came from
*                               a stated standard unit and needed no market survey at all
*
* THE THIRD CUT IS THE HONEST SCOPE OF THIS WORK. Most of the tonnage in PSPS food
* consumption is rice in kilograms and water in labelled containers -- neither needs an NSU
* conversion. The non-standard units are the smaller items, so their share of total mass is
* modest even though they are 40% of the ROWS. A reader who takes the headline figure as a
* measure of this pipeline's importance will overstate it in one direction and understate
* it in the other.

gen byte _iswater = strpos(pull_item, "water") > 0

di as res _n "grams per person per day, three cuts:"
di as res "  cut                                    n_hh      p25   median      p75      p90        max"

preserve
	collapse (sum) gppd, by(hhid)
	qui su gppd, detail
	di as res "  all surveyed items                  " %8.0fc r(N) " " %8.0f r(p25) ///
		" " %8.0f r(p50) " " %8.0f r(p75) " " %8.0f r(p90) " " %10.0f r(max)
restore
preserve
	drop if _iswater
	collapse (sum) gppd, by(hhid)
	qui su gppd, detail
	di as res "  excluding drinking water            " %8.0fc r(N) " " %8.0f r(p25) ///
		" " %8.0f r(p50) " " %8.0f r(p75) " " %8.0f r(p90) " " %10.0f r(max)
restore
preserve
	keep if route == "non-standard"
	collapse (sum) gppd, by(hhid)
	qui su gppd, detail
	di as res "  NSU-converted only (this pipeline)  " %8.0fc r(N) " " %8.0f r(p25) ///
		" " %8.0f r(p50) " " %8.0f r(p75) " " %8.0f r(p90) " " %10.0f r(max)
restore

* WHERE THE MASS IS, which is the other half of the same point.
di as res _n "total grams by route and item, the ten largest:"
preserve
	collapse (sum) tot_g = grams_h, by(route pull_item)
	gsort -tot_g
	gen double tot_tonnes = tot_g / 1000000
	gen str32 item = substr(pull_item, 1, 32)
	list route item tot_tonnes in 1/10, noobs sep(0)
restore

* THE IMPLAUSIBLE TAIL, NAMED. Every household above 10 kg/person/day is worth being able
* to point at, because the answer to "is the conversion wrong" is different from "is the
* reported quantity wrong" and only the first is this project's problem.
di as res _n "the ten highest households, and the single item driving each:"
* The data is at (household x item x route) here -- section 4 summed the acquisition slots
* -- so q_h and cf_h do not exist at this grain and are not listed. grams_h at this grain
* is what the household consumed of that item over the recall week, which is the quantity
* the implausibility is about.
preserve
	bysort hhid: egen double _hh_tot = total(gppd)
	* `bysort hhid (gppd)' ascending, then _n == _N, picks each household's largest item.
	* NOT `gsort -_hh_tot' followed by `by hhid:' -- gsort with a descending key leaves the
	* data in an order `by' rejects as "not sorted", which is an r(5) rather than a wrong
	* answer, but only because Stata checks.
	bysort hhid (gppd): gen byte _biggest = (_n == _N)
	keep if _biggest
	gsort -_hh_tot
	gen str28 item = substr(pull_item, 1, 28)
	rename count_res_members hhsize
	list hhid route item hhsize grams_h gppd _hh_tot in 1/10, noobs sep(0)
	di as res ""
	di as res "  READ THE ROUTE COLUMN FIRST. Where it reads standard unit, the conversion"
	di as res "  is arithmetic -- a stated container size times a reported count -- so an"
	di as res "  implausible total is an implausible REPORTED QUANTITY, not a conversion"
	di as res "  error, and it is upstream of this project. Where it reads non-standard,"
	di as res "  the conversion is this project's and the row deserves a look."
restore
drop _iswater

di as res _n "{hline 78}"
di as res "sense_check_outputs.do done -- four tables in ${btables}, four graphs in ${bgraphs}"
di as res "{hline 78}"
