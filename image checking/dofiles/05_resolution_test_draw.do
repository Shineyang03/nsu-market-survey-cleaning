********************************************************************************
* 05_resolution_test_draw.do -- the A/B test set for reading resolution
*
* THE QUESTION. Display-text agreement on calib_v1 was 54.3%, and the disagreements
* are one-sided: measured against the typed value, Sonnet reads 83% of displays
* correctly and Haiku 55%. Dropping Haiku is the obvious first fix. What it does NOT
* answer is whether Sonnet's remaining 17% is the model's ceiling or an artefact of
* how the images were presented.
*
* calib_v1 tiled four photographs per sheet at 700 px each, so an 8 megapixel
* photograph was shown at roughly a fifth of its linear resolution, and the scale
* display occupies a small part of the frame. That is a plausible cause of a misread
* digit and it has never been tested.
*
* THE TEST. Re-read the SAME images, same model, same instrument, one per sheet at
* 1500 px. Everything varies except presentation, so a difference in accuracy is
* attributable to resolution.
*
* THE POPULATION is the 46 images where BOTH calib_v1 readers produced a display
* reading -- the only images where a tiled reading exists to compare against. It mixes
* the 25 the readers agreed on with the 21 they did not, so the test measures a change
* in accuracy rather than only a change in agreement.
*
* WHY THIS IS A DO-FILE AND NOT A FILTER ON THE COMMAND LINE. "Images where both
* readers produced a display reading" is a selection rule, and a selection rule that
* lives in a shell invocation cannot be re-run, reviewed or cited.
*
* BLINDING IS PRESERVED. This writes ids only. make_contact_sheets.py assigns fresh
* sequence numbers for the new tag, so a reader cannot carry a label across from
* calib_v1 even in principle; the two reading sets are joined afterwards on `id'.
*
* INPUT   ${imgqc}\reconcile_calib_v1.csv
* OUTPUT  ${imgtables}\restest_ids.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 05_resolution_test_draw.do
********************************************************************************

clear all
do "00_photo_globals.do"

import delimited "${imgqc}/reconcile_calib_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id, replace

* Stata's import writes an empty cell as "" for a string column; a reading that was
* never given is missing, not the text "NA".
gen byte got_h = !missing(display_texthaiku)  & trim(display_texthaiku)  != ""
gen byte got_s = !missing(display_textsonnet) & trim(display_textsonnet) != ""
keep if got_h & got_s

qui count
local n = r(N)
if `n' == 0 {
	di as error "no images have a reading from both readers -- nothing to test."
	exit 459
}

gen byte tiled_agreed = (display_texthaiku == display_textsonnet)
qui count if tiled_agreed
local n_ag = r(N)

di as txt _n "resolution-test population: `n' images"
di as txt "  tiled readers agreed on ...... `n_ag'"
di as txt "  tiled readers disagreed on ... " `n' - `n_ag'
di as txt _n "by stratum:"
tab stratum

keep id stratum display_texthaiku display_textsonnet tiled_agreed raw_weight rawtick
gsort id
export delimited using "${imgtables}\restest_ids.csv", replace

di as res _n "05_resolution_test_draw complete: `n' images"
di as txt "draw: ${imgtables}\restest_ids.csv"
