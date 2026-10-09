********************************************************************************
* 20_decimal_drift.do -- correct a published weight by a power of ten where the
*                        scale display fixes its decade, and measure the result
*
* THE IDEA. A Check 2 weighing is suspect because its decimal point may have moved:
* the display read 0.045 kg and 450 g was published. The display fixes the DECADE of
* the true weight; the published value supplies the significant digits. So:
*
*     m_image     = decade the display shows    3 for 1.xxx, 2 for 0.xxx, 1 for 0.0xx,
*                                               0 for 0.00x  (= 4 - first non-zero position)
*     m_original  = floor(log10(published grams))
*     k           = m_image - m_original
*     corrected   = published x 10^k
*
* The decade comes from `sevenseg.py --magnitude', a deterministic classifier that
* decides only which of the four `x.xxx' positions holds the first non-zero digit. It
* never reads the digits themselves, and it never sees a recorded or published weight.
*
* WHAT IS COMPARED. The published value, `corrected_weight', is what this checks --
* the same yardstick 13_apply_photo_rule.do uses. Re-scaling the raw typed value would
* re-implement the block rule and miss its litre branch (README, "Things that went
* wrong"). `raw_weight' and `raw_tick' are carried for audit only.
*
* NOTHING HERE IS APPLIED. `weight_corrected_g' is a proposal beside the published
* value, never a replacement for it. A correction reaches the build only through
* reference/reviewed/snap_verdicts.csv.
*
* STATUS, one per Check 2 weighing, and exclusive:
*
*   invalid_input   published value missing, non-positive, or in mL. A scale display is
*                   a mass and says nothing about the decade of a printed volume.
*   uncertain       could not be checked: no photograph, no display located in it, or
*                   the classifier would not commit (reason in status_reason)
*   no_change       checked: the display's decade equals the published decade
*   corrected       checked: they differ, and weight_corrected_g holds the shifted value
*
* "no_change" and "uncertain" are deliberately different statuses. The first is a
* weighing that was checked and passed; the second is one nobody has checked.
*
* VALIDATION, sections D and E. Against Sonnet's readings (agreement, not accuracy --
* README rule 2) and against human-confirmed labels from 19_magnitude_labels.do, which
* is the only accuracy figure this file can give. The `tune' half of those labels was
* used to build the classifier; only `holdout' is an honest score.
*
* INPUT   ${imgtables}\photo_targets.csv              the 2,472 Check 2 weighings
*         ${imgbridge}\photo_id_bridge.csv
*         ${imgout}\rect_all_status.csv                 which photographs have a crop
*         ..\outputs\decimal_drift\magnitude_check2.csv  sevenseg.py --magnitude, run on
*                                                       check2_crop_manifest.csv
*         ..\outputs\decimal_drift\magnitude_labels.csv  19_magnitude_labels.do
*         ${imgqc}\photo_readings_master.csv            Sonnet readings
*         ${btemp}\nsu_weighings_cpi.dta, prelim_nsu_data.dta
* OUTPUT  ..\outputs\decimal_drift\decimal_drift_check2.csv     one row per weighing
*         ..\outputs\decimal_drift\compare_sonnet_disagree.csv  decade disagreements
*         ..\outputs\decimal_drift\label_errors.csv             classifier vs a person
*
* RUN, from the "image checking/dofiles" folder, after 19 and the classifier:
*     py -3.14 ..\scripts\sevenseg.py --magnitude ^
*         --manifest ..\outputs\decimal_drift\check2_crop_manifest.csv ^
*         --crops "<main tree>\image checking\outputs\rect_all" ^
*         --out ..\outputs\decimal_drift\magnitude_check2.csv
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_decimal_drift.do
********************************************************************************

clear all
do "00_photo_globals.do"

global ddout "`c(pwd)'\..\outputs\decimal_drift"
mkdir_missing "${ddout}"

* Recorded from 02_photo_targets.do: every Check 2 flag is must-check. Reported, not
* asserted -- a moved count is a finding to explain, not a constant to bump.
local BASE_C2 2472
local KGSPLIT 30

********************************************************************************
* A. The correction rule, defined once and tested before it touches data
********************************************************************************

* decade_of, the decade of a positive weight, is defined in 00_photo_globals.do and
* shared with 19_magnitude_labels.do, so the labels and the correction cannot disagree.

capture program drop decimal_shift
program define decimal_shift
	syntax , Weight(varname numeric) Pos(varname numeric) SHift(name) CORrected(name)
	tempvar m_orig m_img
	decade_of `m_orig' `weight'
	gen int `m_img' = 4 - `pos' if inrange(`pos', 1, 4)
	gen int `shift' = `m_img' - `m_orig'
	* divide for a negative shift: 450 / 10 is exactly 45, 450 * 0.1 is not
	gen double `corrected' = cond(`shift' >= 0, `weight' * 10^`shift', ///
		`weight' / 10^(-`shift')) if !missing(`shift')
end

* ---- synthetic cases with known answers -----------------------------------------
clear
input double w byte pos double want_k double want_w
  450  3  -1    45
   52  2   1   520
  123  1   1  1230
   87  3   0    87
  0.8  2   3   800
 1000  1   0  1000
    5  4   0     5
   50  4  -1     5
 1085  1   0  1085
  4.5  3   1    45
    0  2   .     .
   -5  2   .     .
    .  2   .     .
  450  .   .     .
  450  5   .     .
end
* a value one ulp-scale below a power of ten belongs to that power
local N = _N + 1
set obs `N'
replace w = 1000 - 1e-10 in `N'
replace pos = 1 in `N'
replace want_k = 0 in `N'
replace want_w = 1000 - 1e-10 in `N'

decimal_shift, weight(w) pos(pos) shift(k) corrected(wc)
assert k == want_k               if !missing(want_k)
assert missing(k)                if  missing(want_k)
assert reldif(wc, want_w) < 1e-12 if !missing(want_w)
assert missing(wc)               if  missing(want_w)
di as res "  decimal_shift: " _N " synthetic cases pass"

********************************************************************************
* B. The Check 2 population, and everything known about each weighing
********************************************************************************

import delimited "${imgtables}/photo_targets.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id check has_photo, replace
keep if check == 2
* photo_targets is long over (id, check, reason)
gsort id -has_photo
by id: keep if _n == 1
keep id has_photo
qui count
di as txt _n "Check 2 weighings: " r(N) "  (recorded: `BASE_C2')"
if r(N) != `BASE_C2' di as error "COUNT HAS MOVED from the recorded baseline -- say so, do not substitute."

preserve
	import delimited "${imgbridge}/photo_id_bridge.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	gen str32 image_code = subinstr(filename, ".jpg", "", .)
	keep id image_code
	tempfile br
	save "`br'"
restore
merge 1:1 id using "`br'", keep(master match) nogen

preserve
	import delimited "${imgout}/rect_all_status.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	gen byte has_crop = substr(status, 1, 2) == "ok"
	keep image_code has_crop
	duplicates drop image_code, force
	tempfile cr
	save "`cr'"
restore
merge m:1 image_code using "`cr'", keep(master match) nogen
replace has_crop = 0 if missing(has_crop)

* ---- the classifier ---------------------------------------------------------------
preserve
	import delimited "${ddout}/magnitude_check2.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring first_nonzero_position image_magnitude_g confidence, replace
	keep image_code mag_status uncertain_reason first_nonzero_position ///
	     image_magnitude_g confidence p1_state p2_state p3_state p4_state
	rename confidence recognition_confidence
	tempfile cv
	save "`cv'"
	qui count
	local n_cv = r(N)
restore
merge m:1 image_code using "`cv'", keep(master match)
qui count if has_crop & _merge != 3
if r(N) > 0 {
	di as error r(N) " photographs with a crop have no classifier row -- re-run sevenseg.py on the manifest"
	exit 459
}
drop _merge

* ---- the published value ----------------------------------------------------------
merge 1:1 id using "${btemp}/nsu_weighings_cpi.dta", ///
	keepusing(pull_item corrected_weight corrected_unit snap_rule) ///
	keep(master match) nogen
decode corrected_unit, gen(pub_unit)
decode snap_rule, gen(pub_rule)
drop corrected_unit snap_rule

merge 1:1 id using "${btemp}/prelim_nsu_data.dta", ///
	keepusing(weight unit) keep(master match) nogen
decode unit, gen(raw_tick)
rename weight raw_weight
drop unit

* ---- Sonnet, and the human labels --------------------------------------------------
preserve
	import delimited "${imgqc}/photo_readings_master.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8")
	keep id g_hir g_swp g_rsc g_son g_sc1 g_hum
	tempfile son
	save "`son'"
restore
merge 1:1 id using "`son'", keep(master match) nogen

* Sonnet passes only, best presentation first (12_photo_readings_master.do). A human
* reading is NOT folded in: this is the comparison with the model.
gen double sonnet_g = .
foreach s in hir swp rsc son sc1 {
	replace sonnet_g = g_`s' if missing(sonnet_g) & !missing(g_`s') & g_`s' > 0
}

preserve
	import delimited "${ddout}/magnitude_labels.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring true_pos, replace
	keep image_code true_pos split
	tempfile lab
	save "`lab'"
restore
merge m:1 image_code using "`lab'", keep(master match) nogen

********************************************************************************
* C. Status and proposal
********************************************************************************

gen double weight_original_g = corrected_weight if pub_unit == "g"
gen byte   pos_ok = first_nonzero_position if mag_status == "ok"

decimal_shift, weight(weight_original_g) pos(pos_ok) shift(decimal_shift) ///
	corrected(w_shifted)
decade_of m_original weight_original_g

gen str16 correction_status = ""
gen str80 status_reason     = ""

replace correction_status = "invalid_input" if pub_unit == "mL"
replace status_reason     = "published in mL; a display fixes the decade of a mass" ///
	if pub_unit == "mL"
replace correction_status = "invalid_input" if correction_status == "" & ///
	(missing(corrected_weight) | corrected_weight <= 0)
replace status_reason     = "published value missing or non-positive" ///
	if correction_status == "invalid_input" & status_reason == ""

replace correction_status = "uncertain" if correction_status == "" & has_photo != 1
replace status_reason     = "no photograph" if correction_status == "uncertain" & status_reason == ""
replace correction_status = "uncertain" if correction_status == "" & !has_crop
replace status_reason     = "no display located in the photograph" ///
	if correction_status == "uncertain" & status_reason == ""
replace correction_status = "uncertain" if correction_status == "" & mag_status != "ok"
replace status_reason     = "classifier: " + mag_status + ///
	cond(trim(uncertain_reason) != "", " -- " + uncertain_reason, "") ///
	if correction_status == "uncertain" & status_reason == ""

replace correction_status = "no_change" if correction_status == "" & decimal_shift == 0
replace correction_status = "corrected" if correction_status == "" & decimal_shift != 0 & !missing(decimal_shift)
assert correction_status != ""

gen double weight_corrected_g = w_shifted if inlist(correction_status, "corrected", "no_change")
drop w_shifted
replace decimal_shift = . if !inlist(correction_status, "corrected", "no_change")

gen double image_magnitude = 10^(4 - pos_ok) if inlist(correction_status, "corrected", "no_change")
label var image_magnitude "Lower bound of the decade the display shows, grams"

di as res _n "{hline 78}"
di as res "DECIMAL DRIFT, Check 2"
di as res "{hline 78}"
tab correction_status, m
tab status_reason if correction_status == "uncertain"
tab decimal_shift if correction_status == "corrected"

qui count if has_crop
local n_crop = r(N)
qui count if has_crop & mag_status == "ok"
di as txt _n "  classifier committed on " r(N) " of `n_crop' crops (" ///
	%4.1f 100*r(N)/`n_crop' "%)"

********************************************************************************
* D. Against Sonnet -- agreement, not accuracy
********************************************************************************

decade_of sonnet_dec sonnet_g
gen byte sonnet_pos = 4 - sonnet_dec if inrange(sonnet_dec, 0, 3)
gen int  sonnet_shift = sonnet_dec - m_original if !missing(sonnet_pos) & !missing(weight_original_g)

gen str24 vs_sonnet = ""
replace vs_sonnet = "agree"                 if pos_ok == sonnet_pos & !missing(pos_ok) & !missing(sonnet_pos)
replace vs_sonnet = "DISAGREE"              if pos_ok != sonnet_pos & !missing(pos_ok) & !missing(sonnet_pos)
replace vs_sonnet = "classifier only"       if !missing(pos_ok) & missing(sonnet_pos)
replace vs_sonnet = "Sonnet only"           if  missing(pos_ok) & !missing(sonnet_pos) & has_crop
replace vs_sonnet = "neither"               if  missing(pos_ok) &  missing(sonnet_pos) & has_crop
replace vs_sonnet = "no crop"               if !has_crop

di as res _n "Decade of the display: classifier vs Sonnet (rows with a crop)"
tab vs_sonnet if has_crop
di as txt _n "  and as a decision, among rows both read and published in grams:"
gen str12 sonnet_decision = cond(sonnet_shift == 0, "no_change", "corrected") if !missing(sonnet_shift)
tab correction_status sonnet_decision if inlist(correction_status, "corrected", "no_change") & ///
	!missing(sonnet_decision), m

preserve
	keep if vs_sonnet == "DISAGREE"
	keep id image_code pull_item corrected_weight pub_rule first_nonzero_position ///
	     recognition_confidence p1_state p2_state p3_state p4_state ///
	     sonnet_g sonnet_pos true_pos split
	sort image_code
	export delimited using "${ddout}\compare_sonnet_disagree.csv", replace
restore

********************************************************************************
* E. Against a person -- the only accuracy figure
********************************************************************************

gen int  true_shift = (4 - true_pos) - m_original if !missing(true_pos) & !missing(weight_original_g)
gen byte cv_right   = pos_ok == true_pos if !missing(pos_ok) & !missing(true_pos)
gen byte son_right  = sonnet_pos == true_pos if !missing(sonnet_pos) & !missing(true_pos)
gen byte wrong_correction = correction_status == "corrected" & decimal_shift != true_shift ///
	if !missing(true_shift)
gen byte missed_correction = correction_status == "no_change" & true_shift != 0 ///
	if !missing(true_shift)

foreach sp in tune holdout {
	di as res _n "Labelled by a person, split = `sp'"
	qui count if split == "`sp'"
	local n = r(N)
	qui count if split == "`sp'" & !missing(pos_ok)
	local nok = r(N)
	qui count if split == "`sp'" & cv_right == 1
	local nright = r(N)
	di as txt "  labelled ............................... `n'"
	di as txt "  classifier committed ................... `nok'"
	di as txt "  ... right .............................. `nright'"
	di as txt "  ... WRONG .............................. " `nok' - `nright'
	qui count if split == "`sp'" & wrong_correction == 1
	di as txt "  wrong automatic corrections ............ " r(N)
	qui count if split == "`sp'" & missed_correction == 1
	di as txt "  decade errors passed as no_change ...... " r(N)
	qui count if split == "`sp'" & !missing(son_right)
	local ns = r(N)
	qui count if split == "`sp'" & son_right == 1
	di as txt "  Sonnet: read " `ns' ", decade right " r(N)
	tab true_pos correction_status if split == "`sp'", m
}

preserve
	keep if !missing(true_pos) & (cv_right == 0 | wrong_correction == 1 | missed_correction == 1)
	keep id image_code split true_pos first_nonzero_position recognition_confidence ///
	     p1_state p2_state p3_state p4_state corrected_weight decimal_shift true_shift ///
	     sonnet_g sonnet_pos correction_status
	sort split image_code
	export delimited using "${ddout}\label_errors.csv", replace
restore

********************************************************************************
* F. Write
********************************************************************************

rename first_nonzero_position first_nonzero_position_raw
gen byte first_nonzero_position = pos_ok

order id image_code weight_original_g image_magnitude first_nonzero_position ///
      decimal_shift weight_corrected_g correction_status status_reason ///
      recognition_confidence mag_status uncertain_reason p1_state p2_state p3_state ///
      p4_state m_original has_photo has_crop pub_unit pub_rule raw_weight raw_tick ///
      corrected_weight pull_item sonnet_g sonnet_pos vs_sonnet true_pos split
keep  id image_code weight_original_g image_magnitude first_nonzero_position ///
      decimal_shift weight_corrected_g correction_status status_reason ///
      recognition_confidence mag_status uncertain_reason p1_state p2_state p3_state ///
      p4_state m_original has_photo has_crop pub_unit pub_rule raw_weight raw_tick ///
      corrected_weight pull_item sonnet_g sonnet_pos vs_sonnet true_pos split
sort id
export delimited using "${ddout}\decimal_drift_check2.csv", replace

qui count
di as res _n "20_decimal_drift complete: " r(N) " Check 2 weighings"
di as txt "  ${ddout}\decimal_drift_check2.csv"
