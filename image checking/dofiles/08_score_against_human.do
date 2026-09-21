********************************************************************************
* 08_score_against_human.do -- the first non-circular numbers in this pipeline
*
* WHAT CHANGES HERE. Every earlier score compared a reading with the TYPED weight,
* which is the thing under test; those were agreement-with-the-officer, not accuracy.
* The human read the same photographs blind, with no typed value, no published value
* and no model reading in front of them. That makes two genuinely different questions
* answerable for the first time, and they must be kept apart:
*
*   READER ACCURACY      model reading vs human reading.
*                        Ground truth is the human. This is the real accuracy figure.
*   THE OFFICER'S ERROR  typed weight vs human reading.
*                        Ground truth is the photograph. THIS IS CHECK 2's ANSWER --
*                        how often the number in the data is not what the scale said.
*
* The second is the deliverable. The first only says whether a model may stand in for
* a person on the remaining 3,495 images.
*
* ---- WHAT THE RETURNED WORKBOOK CONSTRAINS ------------------------------------
* EXCEL COERCED 37 OF 40 ANSWERS TO NUMBERS, so a display read as `0.300` is stored as
* `0.3`. Comparison is therefore NUMERIC, never string. The distinction Check 2 turns
* on -- 0.3 against 3 against 300 -- survives a numeric comparison intact; what is lost
* is literal character fidelity, and no exact-string claim is made anywhere below.
*
* THREE ROWS RECORD A PACKAGE VOLUME rather than the scale display, on the reviewer's
* stated rule that a printed volume is preferred where both are visible. They are
* EXCLUDED from scale-reading accuracy -- the question there is what the DISPLAY said,
* and these rows do not answer it -- and reported separately. Excluding them from one
* score is not ignoring them: for Check 1 and A23 the package volume may be the better
* datum, and one of them carries a finding in its own right (see the log).
*
* THE UNIT NORMALISATION is the same one 06 uses and is stated there: a value below
* KGSPLIT is kilograms and is multiplied by 1,000; at or above it, grams. It is applied
* identically to the human reading, the model readings and the typed weight, so no
* comparison is ever between different units.
*
* TOL IS 2%, not the 5% used in 06. Against a human ground truth the question is
* whether the same number was read, not whether two estimates are close, and the
* readings are three-decimal displays where a genuine agreement is exact.
*
* INPUT   ${imgqc}\human_verdicts_v1.csv          parse_validation_workbook.py
*         ${imgqc}\reconcile_calib_v1.csv         model readings, tiled
*         ${imgqc}\readings_restest.csv           model readings, hi-res
*         ${imgtables}\human_validation_ids.csv   the draw, with the typed weight
* OUTPUT  ${imgqc}\human_scored_v1.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 08_score_against_human.do
********************************************************************************

clear all
do "00_photo_globals.do"

local KGSPLIT 30
local TOL     0.02

capture program drop norm_g
program define norm_g
	args newvar src split
	gen double `newvar' = cond(`src' < `split', `src'*1000, `src') if !missing(`src')
end

********************************************************************************
* A. Assemble
********************************************************************************

import delimited "${imgqc}/human_verdicts_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id h_display_val h_scale_present h_glare_flag h_legible_yes, replace
keep id image_code h_display_raw h_display_val reading_source h_glare_flag ///
     h_legible_yes h_notes
tempfile human
save "`human'"

import delimited "${imgtables}/human_validation_ids.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id raw_weight corrected_weight, replace
keep id stratum raw_weight rawtick corrected_weight
merge 1:1 id using "`human'", keep(match) nogen

* model readings -- tiled, both models
preserve
	import delimited "${imgqc}/reconcile_calib_v1.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	destring display_texthaiku,  gen(m_haiku)  force
	destring display_textsonnet, gen(m_sonnet) force
	keep id m_haiku m_sonnet
	tempfile mt
	save "`mt'"
restore
merge 1:1 id using "`mt'", keep(master match) nogen

* model readings -- hi-res sonnet, where the image was in that test
preserve
	import delimited "${imgqc}/readings_restest.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	destring display_text, gen(m_hires) force
	keep id m_hires
	duplicates drop id, force
	tempfile mh
	save "`mh'"
restore
merge 1:1 id using "`mh'", keep(master match) nogen

norm_g human_g  h_display_val   `KGSPLIT'
norm_g haiku_g  m_haiku         `KGSPLIT'
norm_g sonnet_g m_sonnet        `KGSPLIT'
norm_g hires_g  m_hires         `KGSPLIT'
norm_g typed_g  raw_weight      `KGSPLIT'

* The scale-reading population: rows where the human read a DISPLAY.
gen byte scale_row = (reading_source == "scale") & !missing(human_g)
qui count
local n_all = r(N)
qui count if scale_row
local n_scale = r(N)

di as txt _n "rows returned ................. `n_all'"
di as txt "human read a scale display .... `n_scale'"
di as txt "human recorded a package volume " `n_all' - `n_scale'

********************************************************************************
* B. READER ACCURACY -- model against the human. Ground truth is the human.
********************************************************************************

foreach m in haiku sonnet hires {
	gen byte ok_`m' = (abs(`m'_g - human_g)/human_g < `TOL') if scale_row & !missing(`m'_g) & human_g > 0
}

di as res _n "{hline 78}"
di as res "READER ACCURACY -- against a human reading of the same photograph"
di as res "Ground truth is the human. This IS an accuracy figure."
di as res "{hline 78}"
di as txt "                        gave a reading    correct"
foreach m in haiku sonnet hires {
	qui count if scale_row & !missing(`m'_g)
	local n = r(N)
	qui summarize ok_`m' if scale_row, meanonly
	local k = round(r(N)*r(mean))
	local p = 100*r(mean)
	local lbl = cond("`m'"=="hires","sonnet, hi-res",cond("`m'"=="haiku","haiku, tiled","sonnet, tiled"))
	di as txt %-24s "`lbl'" %8.0f `n' "      " %5.0f `k' "  (" %4.1f `p' "%)"
}

di as res _n "  ON ROWS THE HUMAN FLAGGED FOR GLARE OR DOUBT"
qui count if scale_row & h_glare_flag
di as txt "    such rows ......... " r(N)
foreach m in haiku sonnet {
	qui summarize ok_`m' if scale_row & h_glare_flag, meanonly
	di as txt "    `m' ......... " %5.1f (100*r(mean)) "%  (n=" r(N) ")"
}

********************************************************************************
* C. THE OFFICER'S ERROR -- typed against the human. THIS IS CHECK 2's ANSWER.
********************************************************************************

* COMPARE THE PUBLISHED VALUE, NOT A RE-NORMALISED TYPED ONE, and the difference is
* not cosmetic -- it removed a false positive that had been reported twice.
*
* `corrected_weight' is already in grams or mL, computed by the pipeline. Re-scaling
* the RAW typed value here means re-implementing the block rule, and the version above
* (below KGSPLIT, multiply by 1,000) does not cover the litre branch, where
* 03a_block_reading.do multiplies a sub-0.01 litre entry by 1,000,000. On
* `0.001175 L' that produced 1.175 against a display of 1.175 kg and scored a MISMATCH,
* when the pipeline had in fact published 1175 -- exactly right. Twice.
*
* Reading what the pipeline computed rather than recomputing it is the project's rule,
* and this is what it is for. `typed_g' is kept for the transcription question below,
* where the litre branch does not arise.
gen byte typed_ok = (abs(corrected_weight - human_g)/human_g < `TOL') if scale_row & !missing(corrected_weight) & human_g > 0
gen double typed_ratio = corrected_weight / human_g if scale_row & !missing(corrected_weight) & human_g > 0

* A decade slip is the failure 03a_block_reading.do's thresholds exist to catch, so it
* is counted as its own category rather than folded into "wrong".
gen byte typed_decade = (abs(log10(typed_ratio)) > 0.7) if !missing(typed_ratio)

di as res _n "{hline 78}"
di as res "THE PUBLISHED VALUE against the photograph"
di as res "Ground truth is the photograph. This is what Check 2 was built to measure."
di as res "{hline 78}"
tab typed_ok, missing
qui summarize typed_ok, meanonly
di as txt _n "  typed weight matches the display on " %4.1f (100*r(mean)) "% of `=r(N)' readable rows"
qui count if typed_decade == 1
di as txt "  of which a DECADE slip (10x or more) .... " r(N)

di as txt _n "  by stratum:"
tab stratum typed_ok, row

di as res _n "  EVERY ROW WHERE THE TYPED VALUE IS NOT WHAT THE SCALE SHOWED"
gsort -typed_decade -typed_ratio
list image_code stratum rawtick raw_weight h_display_raw human_g typed_g ///
     corrected_weight typed_ratio if typed_ok == 0, noobs abbrev(12)

********************************************************************************
* D. The package-volume rows, reported separately
********************************************************************************

di as res _n "{hline 78}"
di as res "ROWS WHERE THE HUMAN RECORDED A PACKAGE VOLUME, NOT THE DISPLAY"
di as res "Excluded from the scores above: they do not answer what the display said."
di as res "{hline 78}"
list image_code stratum rawtick raw_weight h_display_raw corrected_weight ///
	if reading_source == "package", noobs abbrev(14)
di as txt _n "  reviewer's note on these rows:"
list h_notes if reading_source == "package", noobs abbrev(100)

********************************************************************************
* E. Export
********************************************************************************

keep id image_code stratum rawtick raw_weight corrected_weight ///
     h_display_raw human_g reading_source h_glare_flag h_notes ///
     m_haiku m_sonnet m_hires haiku_g sonnet_g hires_g typed_g ///
     ok_haiku ok_sonnet ok_hires typed_ok typed_ratio typed_decade scale_row
gsort image_code
export delimited using "${imgqc}\human_scored_v1.csv", replace

di as res _n "08_score_against_human complete"
di as txt "  ${imgqc}\human_scored_v1.csv"
di as txt _n "n = `n_scale' scale readings. Small, and drawn from strata that"
di as txt "over-sample the awkward cells -- these are not population rates."
