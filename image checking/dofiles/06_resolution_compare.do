********************************************************************************
* 06_resolution_compare.do -- does presenting the photograph larger fix the digits?
*
* THE A/B. The same 46 images, the same model, the same instrument. Only the
* presentation differs:
*
*   calib_v1   four photographs per sheet, 700 px each   (an 8 MP image at ~1/5 linear)
*   restest    one photograph per sheet, 1500 px         (~1/2 linear)
*
* So a difference in accuracy is attributable to resolution rather than to the reader.
*
* IT ALSO RE-DERIVES THE PER-MODEL ACCURACY FIGURES. Haiku 55% and Sonnet 83% were
* first computed in an ad-hoc Python one-liner, which is exactly the unreproducible
* number this project has been bitten by. They are computed here, from committed
* inputs, and this file is where they should be quoted from.
*
* ---- THE YARDSTICK, AND ITS CIRCULARITY --------------------------------------
* Accuracy is scored as "is the reading within TOL of the typed weight". The typed
* weight is NOT ground truth -- checking it is the entire point of Check 2 -- so this
* is a proxy, and it is only legitimate for COMPARING READERS. Both readers face the
* same yardstick, so whichever agrees with it more often is reading the display more
* accurately, whatever the typed value's own status.
*
* What it must NOT be used for: concluding that the typed values are right. A reader
* that agreed with the typed value 100% of the time would prove nothing about the
* data, only that it reads displays the way the officer did.
*
* THE UNIT NORMALISATION. These displays mostly print no unit, and the photographs
* show the scale in kilogram mode (a cabbage reads 0.800) and occasionally in gram
* mode (a chicken reads 1085). A value below KGSPLIT is read as kilograms and
* multiplied by 1,000; at or above it, as grams. The same rule is applied to BOTH the
* reading and the typed weight, so a comparison is never between different units.
* KGSPLIT matches KGMAX in 03a_block_reading.do so this yardstick and the rule it
* helps check cannot disagree for an unrelated reason.
*
* INPUT   ${imgqc}\readings_calib_v1.csv   tiled readings   (parse_readings.py)
*         ${imgqc}\readings_restest.csv    high-res readings
*         ${imgtables}\restest_ids.csv     the 46, with the typed weight
* OUTPUT  ${imgqc}\resolution_compare.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 06_resolution_compare.do
********************************************************************************

clear all
do "00_photo_globals.do"

local KGSPLIT 30
local TOL     0.05

capture program drop norm_g
program define norm_g
	* value -> grams, under the kg/g mode rule in the header.
	args newvar src split
	gen double `newvar' = cond(`src' < `split', `src'*1000, `src') if !missing(`src')
end

********************************************************************************
* A. The tiled readings, per model
********************************************************************************

import delimited "${imgqc}/readings_calib_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id, replace
gen str12 rmodel = cond(strpos(reader,"haiku")>0, "haiku", "sonnet")
destring display_text, gen(dt) force
keep if !missing(dt)
keep id rmodel dt
rename dt tiled_val
reshape wide tiled_val, i(id) j(rmodel) string
tempfile tiled
save "`tiled'"

********************************************************************************
* B. The high-resolution readings
********************************************************************************

capture confirm file "${imgqc}/readings_restest.csv"
if _rc {
	di as error "no high-res readings at ${imgqc}/readings_restest.csv"
	di as error "Run: python parse_readings.py --tag restest --out ../outputs/qc/readings_restest.csv"
	exit 601
}
import delimited "${imgqc}/readings_restest.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id, replace
destring display_text, gen(hires_val) force
gen byte hires_gave = !missing(hires_val)
gen byte hires_abst = inlist(display_legible, "ambiguous", "not_visible")
keep id hires_val hires_gave hires_abst display_legible photo_type
rename display_legible hires_legible
rename photo_type      hires_type
duplicates drop id, force
tempfile hires
save "`hires'"

********************************************************************************
* C. The typed weight
********************************************************************************

import delimited "${imgtables}/restest_ids.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id raw_weight tiled_agreed, replace
keep id stratum raw_weight rawtick tiled_agreed

merge 1:1 id using "`tiled'", keep(master match) nogen
merge 1:1 id using "`hires'", keep(master match) nogen

********************************************************************************
* D. Score
********************************************************************************

norm_g typed_g     raw_weight      `KGSPLIT'
norm_g haiku_g     tiled_valhaiku  `KGSPLIT'
norm_g sonnet_g    tiled_valsonnet `KGSPLIT'
norm_g hires_g     hires_val       `KGSPLIT'

foreach v in haiku sonnet hires {
	gen byte ok_`v' = (abs(`v'_g - typed_g)/typed_g < `TOL') if !missing(`v'_g, typed_g) & typed_g > 0
}

di as res _n "{hline 78}"
di as res "READER ACCURACY against the typed weight"
di as res "A PROXY, valid for comparing readers only -- see the header."
di as res "{hline 78}"
di as txt "                        gave a reading   within `=100*`TOL''% of typed"
foreach v in haiku sonnet hires {
	qui count if !missing(`v'_g)
	local n = r(N)
	qui summarize ok_`v', meanonly
	local pct = 100*r(mean)
	local k = r(N)*r(mean)
	local lbl = cond("`v'"=="hires", "hi-res, 1 per sheet", cond("`v'"=="haiku","tiled, haiku","tiled, sonnet"))
	di as txt %-24s "`lbl'" %8.0f `n' "        " %5.0f `k' "  (" %4.1f `pct' "%)"
}

* ---- the like-for-like comparison ----------------------------------------------
* Sonnet tiled against Sonnet hi-res, on images where BOTH produced a reading. This
* is the actual A/B: the rows above differ in denominator as well as presentation.
gen byte pair = !missing(sonnet_g) & !missing(hires_g)
qui count if pair
local n_pair = r(N)
di as res _n "  LIKE FOR LIKE -- Sonnet, both presentations, same `n_pair' images"
qui summarize ok_sonnet if pair, meanonly
di as txt "    tiled  700px 4-up ..... " %5.1f (100*r(mean)) "%"
qui summarize ok_hires if pair, meanonly
di as txt "    hi-res 1500px 1-up .... " %5.1f (100*r(mean)) "%"

gen byte fixed  = (ok_sonnet==0 & ok_hires==1) if pair
gen byte broke  = (ok_sonnet==1 & ok_hires==0) if pair
qui count if fixed
local nf = r(N)
qui count if broke
local nb = r(N)
di as txt "    resolution FIXED ...... `nf'"
di as txt "    resolution BROKE ...... `nb'"

* ---- abstention -----------------------------------------------------------------
qui summarize hires_abst, meanonly
di as txt _n "  hi-res abstention rate .. " %5.1f (100*r(mean)) "%"
qui count if missing(hires_val)
di as txt "  hi-res gave no reading on " r(N) " of 46"

di as res _n "  WHERE THE TWO PRESENTATIONS DISAGREE"
list id stratum raw_weight tiled_valsonnet hires_val ok_sonnet ok_hires ///
	if pair & ok_sonnet != ok_hires, noobs abbrev(12)

********************************************************************************
* E. Export
********************************************************************************

keep id stratum rawtick raw_weight typed_g tiled_valhaiku tiled_valsonnet hires_val ///
     haiku_g sonnet_g hires_g ok_haiku ok_sonnet ok_hires fixed broke ///
     hires_legible hires_type tiled_agreed
gsort id
export delimited using "${imgqc}\resolution_compare.csv", replace

di as res _n "06_resolution_compare complete"
di as txt "  ${imgqc}\resolution_compare.csv"
