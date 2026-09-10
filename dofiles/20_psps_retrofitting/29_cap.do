********************************************************************************
* 29_cap.do -- bound the linear extrapolation in B3, and flag what was bounded
*
* WHAT THIS OWNS. Step B3 is linear in the household's price with no upper limit:
*
*     CF_h = p_h * w_g / p_g  =  r_h * w_g,   where r_h = p_h / p_g
*
* so a household whose implied unit price is ten times the matched group's is handed ten
* times the grams of a unit anyone actually weighed. Nothing in the arithmetic stops that.
* The cap is a statement about HOW FAR a household's price may stray from the matched point
* before linear extrapolation stops being credible.
*
* APPROACH A, decided on #19: clamp the RATIO, not the output.
*
*     r~_h = min(max(r_h, 1/t), t)      CF_h = r~_h * w_g
*
* Clamping the input is what makes the bound legible -- it puts CF_h inside
* [w_g/t, w_g*t], a multiplicative window around the weight that was actually measured.
* Two alternatives were considered and are not used. Bounding CF_h against the case's own
* observed weight range is more physical but rests on 3-9 vendors, so its band WIDENS with
* vendor count and is loosest where the evidence is thickest -- the wrong direction; it
* survives as #20's sensitivity. Winsorizing p_h to the case's price span silently
* discards households that really did buy a larger unit.
*
* ROWS ARE CLAMPED AND KEPT, NEVER DROPPED. `d_cap' marks them and `r_h_raw' keeps the
* uncapped ratio, so an analyst can drop the affected households instead of using a
* clamped number, or recompute at their own t.
*
* ==============================================================================
* WHY THIS BITES HARDEST WHERE THE EVIDENCE IS THINNEST
*
* Roughly two thirds of cases carry a SINGLE price point -- 1,221 of 1,907, measured in
* 20_case_price_points.do. There is no ladder to bracket a household there: every
* household matches the one point however far its spend lies from it. So the report below
* is split by point count, and the tail is expected to be worst at one point. That is not
* a property of the cap; it is a property of the price file.
*
* ==============================================================================
* THE CAP DOES NOT APPLY TO EVERY ROW, and the exclusions are structural
*
*   fallback rows        no price entered the estimate -- from L1 down the household's
*                        price is ignored by design (A15), so there is no ratio to clamp
*   conventional rows    the branch has no price point at all
*   no-faced-price rows  own production and gifts have no p_h (A10); 28 converts them at
*                        the group's own weight, which is r_h = 1 by construction
*   standard-unit rows   27 converts them from the unit's own name; no market survey, no
*                        ratio. They are not in this file's input at all.
*
* So the cap reaches only the rows where a household price was actually divided by a
* group price, and section 1 counts them.
*
* ==============================================================================
* INPUT   ${btemp}\psps_converted.dta   28
* OUTPUT  ${btemp}\psps_converted_capped.dta
*         ${btables}\cap_ratio_distribution.csv
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\29_cap.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

* ---- t --------------------------------------------------------------------------
* SET FROM THE DISTRIBUTION IN SECTION 2, NOT CHOSEN IN ADVANCE. #19 is explicit that
* picking 2 or 3 up front would be a number with no evidence behind it, and the figures in
* section 2 are what this value answers to. Change it only against a re-read of them.
*
* THE VALUE IS 5. Read off the reported percentiles: the ratio distribution is tight
* through the 95th percentile and the extreme tail is where it stops describing a purchase
* at all. A cut at 5 leaves ordinary variation -- a household buying a genuinely larger
* unit, a vendor charging more -- untouched, and bounds the rows where CF_h would otherwise
* exceed the heaviest unit ever weighed in the cell by a wide multiple.
*
* IT IS A JUDGEMENT ON A CONTINUOUS DISTRIBUTION, not a break in it. There is no gap in
* the data that selects 5 over 4 or 6; what the percentiles establish is the ORDER OF
* MAGNITUDE at which extrapolation stops being about size. The sensitivity table in
* section 3 is published for exactly that reason -- so a reader can take 3 or 10 instead --
* and `r_h_raw' ships on every row so they can.
local T = 5


********************************************************************************
**# 1. The rows a ratio applies to
********************************************************************************

use "${btemp}\psps_converted", clear
qui count
local n_in = r(N)
di as res _n "converted-and-refused rows in: `n_in'"

gen double r_h_raw = .
replace  r_h_raw = p_h / p_g if d_converted == 1 & fallback_level == 0 & ///
	d_no_price == 0 & !missing(p_g) & p_g > 0

label var r_h_raw "p_h / p_g, UNCAPPED -- missing where no ratio entered the estimate"

qui count if !missing(r_h_raw)
local n_ratio = r(N)
di as res "rows where a household price was divided by a group price: `n_ratio'"
di as res "  (the rest are fallback, conventional, no-faced-price or refused)"

di as res _n "why a row carries no ratio:"
gen str28 _noratio = ""
replace _noratio = "refused, no grams"        if d_converted == 0
replace _noratio = "fallback rung, no price"  if _noratio == "" & fallback_level > 0
replace _noratio = "no faced price (A10)"     if _noratio == "" & d_no_price == 1
replace _noratio = "conventional, no p_g"     if _noratio == "" & missing(p_g)
replace _noratio = "has a ratio"              if _noratio == ""
tab _noratio, m
drop _noratio


********************************************************************************
**# 2. The distribution, which is what sets t
********************************************************************************

di as res _n "{hline 78}"
di as res "DISTRIBUTION OF r_h = p_h / p_g   (uncapped)"
di as res "{hline 78}"
qui su r_h_raw, detail
di as res "  n        " %12.0fc r(N)
di as res "  min      " %12.4f r(min)
di as res "  p1       " %12.4f r(p1)
di as res "  p5       " %12.4f r(p5)
di as res "  p25      " %12.4f r(p25)
di as res "  median   " %12.4f r(p50)
di as res "  p75      " %12.4f r(p75)
di as res "  p95      " %12.4f r(p95)
di as res "  p99      " %12.4f r(p99)
di as res "  max      " %12.4f r(max)

* THE MEDIAN IS THE FIRST THING TO READ. If it is far from 1 the price points and the
* household prices are not on the same frame, and no cap can repair that -- it would be a
* bug in the match or in the inflation step, not a tail to bound.
if abs(r(p50) - 1) > 0.5 {
	di as err "WARNING: the median ratio is far from 1."
	di as err "Households and price points may not be on a common price frame."
}

di as res _n "by the number of price points in the case:"
di as res "  points        n       p50       p95       p99       max"
forvalues k = 1/3 {
	qui su r_h_raw if n_points == `k', detail
	di as res "  " %6.0f `k' "  " %7.0fc r(N) "  " %8.3f r(p50) "  " %8.3f r(p95) ///
		"  " %8.3f r(p99) "  " %8.2f r(max)
}
di as res "  Expect the tail to be worst at ONE point: there is no ladder to bracket a"
di as res "  household, so it matches that point however far its spend lies from it."


********************************************************************************
**# 3. What each candidate t would cost
********************************************************************************
* Published so a reader can disagree with the choice without rerunning anything, which is
* this project's standing convention for a threshold that cannot be measured (A3, A11).

di as res _n "share of ratio-carrying rows clamped at each candidate t:"
di as res "       t      rows       share"
foreach t in 1.5 2 3 5 10 {
	qui count if !missing(r_h_raw) & (r_h_raw > `t' | r_h_raw < 1/`t')
	local n_hit = r(N)
	di as res "  " %6.1f `t' "  " %8.0fc `n_hit' "  " %9.2f 100 * `n_hit' / `n_ratio' "%"
}


********************************************************************************
**# 4. Is an extreme ratio a bulk purchase or a misreport?
********************************************************************************
* #19 asks this before the cap is treated as a fix rather than a symptom, and it is the
* part that decides whether the CLAMP or the FLAG is the useful output. A household
* "spending ten times the top price point" on a quantity of 1, at a round-number
* expenditure, is more likely to have misreported the quantity than to have bought ten
* units' worth of one unit. Where that is the pattern the clamp is cosmetic and the flag is
* the finding.

gen byte _top1 = 0
qui su r_h_raw, detail
replace _top1 = 1 if !missing(r_h_raw) & r_h_raw >= r(p99)
gen byte _q1 = (q_h == 1) if !missing(r_h_raw)
* Round-number expenditure: a multiple of 50 pesos, the scale households actually name.
gen byte _round = (mod(e_h, 50) == 0) if !missing(r_h_raw) & !missing(e_h)

di as res _n "the top 1% of ratios against quantity == 1:"
tab _top1 _q1, row
di as res _n "the top 1% of ratios against a round-number expenditure (multiple of 50):"
tab _top1 _round, row
drop _top1 _q1 _round


********************************************************************************
**# 5. Clamp
********************************************************************************

gen double r_h = r_h_raw
gen byte   d_cap = 0
replace d_cap = 1 if !missing(r_h_raw) & (r_h_raw > `T' | r_h_raw < 1 / `T')
replace r_h   = `T'     if !missing(r_h_raw) & r_h_raw > `T'
replace r_h   = 1 / `T' if !missing(r_h_raw) & r_h_raw < 1 / `T'

* Recompute the conversion on the clamped ratio. CF_h = r~_h * w_g, which is the same
* expression 28 used with r_h in place of p_h/p_g -- written this way rather than as
* p_h*w_g/p_g so the clamp is visibly the only thing that changed.
gen double cf_h_uncapped = cf_h
replace cf_h    = r_h * w_use if d_cap == 1
replace grams_h = q_h * cf_h  if d_cap == 1

label var r_h            "p_h / p_g after clamping to [1/`T', `T']"
label var d_cap          "1 = the ratio hit the cap and cf_h was bounded"
label var cf_h_uncapped  "cf_h before the clamp, kept so the effect is auditable"

qui count if d_cap == 1
di as res _n "rows clamped at t = `T': " r(N) " of `n_ratio' carrying a ratio"

* The clamp must bound and nothing else. A clamped row's factor moves toward the group's
* own weight; an unclamped row's must not move at all.
assert reldif(cf_h, cf_h_uncapped) < 1e-9 if d_cap == 0
assert cf_h != cf_h_uncapped if d_cap == 1
assert inrange(r_h, 1 / `T', `T') if !missing(r_h)

* And the bound it claims: CF_h inside [w_g/t, w_g*t] on every ratio-carrying row.
qui count if !missing(r_h) & !inrange(cf_h, w_use / `T' - 1e-6, w_use * `T' + 1e-6)
if r(N) > 0 {
	di as err "ERROR: " r(N) " row(s) fall outside [w_g/t, w_g*t] after clamping."
	exit 459
}

* WHAT THE CAP COSTS IN GRAMS, computed against the counterfactual total rather than
* against cf_h, which is a per-unit factor and does not sum to anything meaningful.
gen double _g_uncapped = q_h * cf_h_uncapped
qui su grams_h if d_converted
local after = r(sum)
qui su _g_uncapped if d_converted
local before = r(sum)
di as res _n "total grams, uncapped: " %16.0fc `before'
di as res "total grams, capped  : " %16.0fc `after'
di as res "  net effect of the cap: " %14.0fc `after' - `before' " g, " ///
	%6.2f 100 * (`after' - `before') / `before' "% of the total"
di as res ""
di as res "  IT RAISES THE TOTAL, and that is the substantive finding in this file."
di as res "  #19 was written about the HIGH tail -- a household paying ten times the"
di as res "  matched point being handed ten times the grams. In this data that tail"
di as res "  barely exists: p99 of the ratio is 2.0 and only the one-price-point cases"
di as res "  reach as far as 16. The side that actually binds is the LOW one, where a"
di as res "  household is assigned a small fraction of any unit ever weighed -- the"
di as res "  minimum ratio is 0.0017, which on a 200 g unit is a third of a gram. The"
di as res "  cap is symmetric, so it repairs those, and the total rises."
drop _g_uncapped

compress
sort hh_row
save "${btemp}\psps_converted_capped", replace

preserve
	keep if !missing(r_h_raw)
	keep hhid pull_province pull_municipal_city pull_item pull_nsu_unit ///
	     n_points q_h e_h p_h p_g r_h_raw r_h d_cap cf_h cf_h_uncapped grams_h
	export delimited using "${btables}\cap_ratio_distribution.csv", replace
	di as txt "wrote ${btables}\cap_ratio_distribution.csv (" _N " row(s))"
restore

di as res _n "{hline 78}"
di as res "29_cap.do done -- t = `T'"
di as res "  #20 is the sensitivity against approach B and needs this file's output."
di as res "{hline 78}"
