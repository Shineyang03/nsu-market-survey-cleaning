********************************************************************************
* 04_photo_reconcile.do -- what the photographs say, against what the build says
*
* THE UNBLINDING STEP. Readers saw a tile and a sequence number. This is the first
* file that puts a reading next to the typed weight and the published one, and it
* answers three separate questions that must not be run together:
*
*   RELIABILITY   do two readers of the same photograph agree?
*   CHECK 1       was a measurement taken at all -- is there a scale in the picture?
*   CHECK 2       does the scale display match the number that was typed?
*
* RELIABILITY IS REPORTED FIRST AND SEPARATELY, because the other two are worthless
* without it. An agreement rate is not an accuracy rate: two readers of the same model
* family share failure modes and will misread the same dim display the same way. What
* agreement bounds is CONSISTENCY. Only a human check is ground truth, and none has
* been done -- say so wherever a number from this file is quoted.
*
* DECIMAL RECOVERY IS SCORED ON ITS OWN, never folded into the headline agreement
* rate. Check 2 turns on `0.800' against `800', and the decimal is a few pixels. If
* readers systematically drop it, agreement stays HIGH while accuracy collapses --
* the failure that looks most like success. A separate metric is the only way to see
* it.
*
* TWO DIFFERENT CHECK 2 QUESTIONS, and conflating them is the easy mistake:
*
*   (a) TRANSCRIPTION -- does the typed `weight' equal what the display shows?
*       Needs no interpretation at all: compare the two numbers. This is the clean
*       test and it is reported first.
*   (b) INTERPRETATION -- given the display, is the published gram value right?
*       Needs an inference about whether the scale was in kilogram or gram mode,
*       because these displays mostly print no unit. The inference is stated below
*       and flagged in the output; it is THIS FILE'S yardstick, not a pipeline
*       quantity, in the same way photo_review_queue.do's pool median is its own.
*
* INPUT   ${imgqc}\readings_<tag>.csv        parse_readings.py
*         ${imgtables}\calibration_ids.csv   03_calibration_draw.do
*         ${btemp}\nsu_weighings_cpi.dta     the published build
* OUTPUT  ${imgqc}\reconcile_<tag>.csv       one row per image, both readers side by side
*         ${imgqc}\agreement_<tag>.csv       the reliability table
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 04_photo_reconcile.do
********************************************************************************

clear all
do "00_photo_globals.do"

local TAG "calib_v1"

********************************************************************************
* A. Readings, one row per image per reader model
********************************************************************************

import delimited "${imgqc}/readings_`TAG'.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id, replace

* The three haiku workers read disjoint sheets, so they are ONE reader between them;
* likewise the two sonnet workers. Collapsing to the model is what makes the
* comparison a cross-MODEL one rather than a comparison of arbitrary work splits.
gen str12 rmodel = ""
replace rmodel = "haiku"  if strpos(reader, "haiku")  > 0
replace rmodel = "sonnet" if strpos(reader, "sonnet") > 0
qui count if rmodel == ""
if r(N) > 0 {
	di as error "`r(N)' reading(s) from a reader whose model cannot be identified."
	levelsof reader if rmodel == "", clean
	exit 459
}

* A model must not read one image twice. If it does, the work split overlapped and
* the agreement denominator would be wrong.
qui duplicates report id rmodel
qui duplicates tag id rmodel, gen(_dup)
qui count if _dup > 0
if r(N) > 0 {
	di as error "`r(N)' reading(s) duplicate an (image, model) pair -- sheets overlapped."
	exit 459
}
drop _dup

keep id rmodel photo_type display_text display_legible display_unit_shown ///
     package_text package_qty package_unit item_on_scale notes
reshape wide photo_type display_text display_legible display_unit_shown ///
     package_text package_qty package_unit item_on_scale notes, i(id) j(rmodel) string

qui count
local n_img = r(N)
di as txt _n "images with at least one reading: `n_img'"

********************************************************************************
* B. Reliability -- and nothing downstream is worth reading until this is seen
********************************************************************************

gen byte both_read = !missing(photo_typehaiku) & !missing(photo_typesonnet)
qui count if both_read
local n_both = r(N)

* ---- photo_type ----------------------------------------------------------------
gen byte ag_type = (photo_typehaiku == photo_typesonnet) if both_read

* ---- scale present: the coarser, more robust version of the same question -------
* Check 1 needs "is there a scale", not the full seven-way classification. Two readers
* can disagree between label_closeup and item_no_scale while agreeing completely on
* the thing the check turns on.
gen byte scale_h = inlist(photo_typehaiku,  "scale_with_item", "scale_no_item") if !missing(photo_typehaiku)
gen byte scale_s = inlist(photo_typesonnet, "scale_with_item", "scale_no_item") if !missing(photo_typesonnet)
gen byte ag_scale = (scale_h == scale_s) if both_read

* ---- display text, exact string -------------------------------------------------
gen byte has_disp_h = !missing(display_texthaiku)  & display_texthaiku  != "NA"
gen byte has_disp_s = !missing(display_textsonnet) & display_textsonnet != "NA"
gen byte both_disp  = has_disp_h & has_disp_s
gen byte ag_disp    = (display_texthaiku == display_textsonnet) if both_disp

* ---- DECIMAL RECOVERY, scored alone ---------------------------------------------
gen byte dec_h = strpos(display_texthaiku,  ".") > 0 if has_disp_h
gen byte dec_s = strpos(display_textsonnet, ".") > 0 if has_disp_s
gen byte ag_dec = (dec_h == dec_s) if both_disp

* ---- abstention ------------------------------------------------------------------
* A reader that never abstains is not being careful; one that always abstains is
* useless. Both rates belong in the report.
gen byte abst_h = (display_legiblehaiku  == "ambiguous" | display_legiblehaiku  == "not_visible")
gen byte abst_s = (display_legiblesonnet == "ambiguous" | display_legiblesonnet == "not_visible")

di as res _n "{hline 78}"
di as res "RELIABILITY -- consistency between two models, NOT accuracy"
di as res "{hline 78}"
di as txt "  images read by both models .................. `n_both' of `n_img'"
foreach m in ag_type ag_scale {
	qui summarize `m', meanonly
	di as txt "  `m' ....... " %6.1f (100*r(mean)) "%  (n=" r(N) ")"
}
qui count if both_disp
di as txt "  both gave a display reading ................. " r(N)
foreach m in ag_disp ag_dec {
	qui summarize `m', meanonly
	di as txt "  `m' ........ " %6.1f (100*r(mean)) "%  (n=" r(N) ")"
}
qui summarize abst_h, meanonly
di as txt "  haiku abstained on .......................... " %5.1f (100*r(mean)) "%"
qui summarize abst_s, meanonly
di as txt "  sonnet abstained on ......................... " %5.1f (100*r(mean)) "%"

********************************************************************************
* C. Join the build. Everything below is unblinded.
********************************************************************************

preserve
	import delimited "${imgtables}/calibration_ids.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	keep id stratum check reason
	tempfile calib
	save "`calib'"
restore
merge 1:1 id using "`calib'", keep(master match) nogen

preserve
	use "${btemp}/nsu_weighings_cpi.dta", clear
	keep id pull_item corrected_weight corrected_unit snap_rule item_nsu_hetero_type
	decode corrected_unit, gen(pub_dim)
	decode snap_rule,      gen(rule)
	drop corrected_unit snap_rule
	tempfile pub
	save "`pub'"
restore
merge 1:1 id using "`pub'", keep(master match) nogen

preserve
	use "${btemp}/prelim_nsu_data.dta", clear
	keep id weight unit
	decode unit, gen(rawtick)
	rename weight raw_weight
	drop unit
	tempfile raw
	save "`raw'"
restore
merge 1:1 id using "`raw'", keep(master match) nogen

********************************************************************************
* D. CHECK 1 -- was a measurement taken?
********************************************************************************

* Agreed readings only. Where the two models disagree about whether a scale is
* present, the image is counted as unresolved rather than assigned to a side.
gen byte scale_present = scale_h if both_read & ag_scale == 1
label var scale_present "Both readers agree a scale is in the photograph"

di as res _n "{hline 78}"
di as res "CHECK 1 -- IS THERE A SCALE IN THE PHOTOGRAPH?"
di as res "Agreed readings only; disagreements are excluded, not assigned."
di as res "{hline 78}"
tab stratum scale_present, row missing

di as res _n "  by item (agreed readings)"
tab pull_item scale_present, row

********************************************************************************
* E. CHECK 2 -- does the display match what was typed?
********************************************************************************

* (a) TRANSCRIPTION. No interpretation: is the typed number the number on the
*     display? Uses the sonnet reading where the two agree, which is the only
*     population where a reading can be relied on at all.
gen str24 disp = display_textsonnet if both_disp & ag_disp == 1
destring disp, gen(disp_num) force
gen byte typed_matches_display = (abs(raw_weight - disp_num) < 1e-6) if !missing(disp_num, raw_weight)
label var typed_matches_display "Typed weight equals the characters on the display"

di as res _n "{hline 78}"
di as res "CHECK 2(a) -- TRANSCRIPTION: does the typed weight equal the display?"
di as res "Only images where both readers gave the SAME display text."
di as res "{hline 78}"
tab typed_matches_display, missing
di as txt _n "  by stratum:"
tab stratum typed_matches_display, row

* (b) INTERPRETATION. THIS RESTS ON AN INFERENCE and the column is named so that a
*     reader of the CSV cannot miss it.
*
*     These displays mostly print no unit. A reading with a decimal point and a value
*     below 30 is taken to be KILOGRAMS -- the mode the photographs show, where a
*     cabbage reads 0.800 and a chicken 1.085 -- and an integer reading is taken to be
*     GRAMS. The cut at 30 is borrowed from KGMAX in 03a_block_reading.do so that this
*     yardstick and the rule it is checking do not disagree for an unrelated reason.
*
*     Where display_unit_shown says kg or g, that is used instead and the inference is
*     not invoked.
gen byte mode_inferred = 1
gen str4 disp_mode = ""
replace disp_mode = "kg" if display_unit_shownsonnet == "kg"
replace disp_mode = "g"  if display_unit_shownsonnet == "g"
replace mode_inferred = 0 if inlist(disp_mode, "kg", "g")
replace disp_mode = cond(strpos(disp,".")>0 & disp_num < 30, "kg", "g") if disp_mode == ""

gen double photo_grams = cond(disp_mode=="kg", disp_num*1000, disp_num) if !missing(disp_num)
label var photo_grams   "Grams implied by the display, under the mode inference"
label var mode_inferred "1 = kg/g mode inferred, not printed on the display"

gen double pub_ratio = corrected_weight / photo_grams if !missing(photo_grams, corrected_weight) & photo_grams > 0
gen byte pub_matches_photo = (abs(pub_ratio - 1) < 0.02) if !missing(pub_ratio)
label var pub_matches_photo "Published grams within 2% of the display, under the inference"

di as res _n "{hline 78}"
di as res "CHECK 2(b) -- INTERPRETATION: is the published gram value right?"
di as res "RESTS ON A kg/g MODE INFERENCE where the display prints no unit."
di as res "{hline 78}"
qui count if mode_inferred == 1 & !missing(photo_grams)
di as txt "  readings where the mode was inferred ........ " r(N)
tab pub_matches_photo, missing
di as txt _n "  by the rule that set the published value:"
tab rule pub_matches_photo, row

di as res _n "  WHERE PUBLISHED AND PHOTOGRAPH DISAGREE (worst first)"
gsort -pub_ratio
list id pull_item rawtick raw_weight disp disp_mode photo_grams corrected_weight rule ///
	if pub_matches_photo == 0 in 1/25, noobs abbrev(14)

********************************************************************************
* F. Export
********************************************************************************

preserve
	keep id stratum check both_read ag_type ag_scale ag_disp ag_dec abst_h abst_s
	export delimited using "${imgqc}\agreement_`TAG'.csv", replace
restore

order id stratum check pull_item rawtick raw_weight corrected_weight rule ///
      photo_typehaiku photo_typesonnet ag_scale scale_present ///
      display_texthaiku display_textsonnet ag_disp ag_dec ///
      disp disp_mode mode_inferred photo_grams pub_ratio ///
      typed_matches_display pub_matches_photo
sort id
export delimited using "${imgqc}\reconcile_`TAG'.csv", replace

di as res _n "04_photo_reconcile complete"
di as txt "  ${imgqc}\reconcile_`TAG'.csv"
di as txt "  ${imgqc}\agreement_`TAG'.csv"
di as txt _n "NO HUMAN CHECK HAS BEEN DONE. Agreement above is consistency between two"
di as txt "model readers, not accuracy. Quote it as such."
