********************************************************************************
* 19_magnitude_labels.do -- human-confirmed display magnitudes for the Check 2
*                           crops, split into a tuning half and a held-back half
*
* WHAT IT IS FOR. `sevenseg.py --magnitude' does not read a display. It decides only
* where the first non-zero digit sits on a fixed `x.xxx' kg display, which is enough
* to fix the DECADE of a weighing. Saying how often that decision is right needs
* answers no model produced, and this file assembles them from readings a PERSON made.
*
* THE LABEL. The position of the first non-zero digit among the four shown:
*
*     true_pos   display          grams
*        1       1.000 - 9.999    1,000 - 9,999
*        2       0.100 - 0.999      100 -   999
*        3       0.010 - 0.099       10 -    99
*        4       0.001 - 0.009        1 -     9
*
* SOURCES, every one a person:
*
*   human_verdicts_v1.csv        blind readings, 40 photographs
*   human_verdicts_hold_v1.csv   blind readings of the 2x hold set, 37
*        -> scale readings only; a printed package volume is not a display
*   override_verdicts_v2.csv     owner verdicts on proposed overrides
*   override_verdicts_v3.csv
*   hold_verdicts_v2.csv         owner verdicts on the 2x hold set
*        -> grams only, and only where the photograph's evidence was the scale.
*           Where a package label governed, the verdict is about the label.
*
* WHAT THESE LABELS ARE NOT: A RANDOM SAMPLE. Every owner verdict exists because a
* model reading disagreed with the published value, so the set is enriched for decade
* errors and for hard displays. That makes it the right set for measuring how often
* the classifier would apply a WRONG correction, and the wrong set for quoting an
* accuracy rate on the population. Accuracy on unflagged rows needs a blind random
* sample read by a person.
*
* A PHOTOGRAPH WITH TWO LABELS THAT DISAGREE ON THE DECADE is listed and dropped, not
* resolved here. Which reading is right is a question for a person, and a label set
* that silently picked one would score the classifier against that choice.
*
* THE SPLIT. Within each true_pos, half the photographs are `tune' and half `holdout',
* drawn on a pinned seed and then frozen in magnitude_split_ledger.csv (section E). The classifier may be developed against `tune' only;
* `holdout' is opened once, to score it. Thresholds tuned against every label available
* produce a reader that works on those labels (README, "The OCR reader does not work").
*
* INPUT   ${imgqc}\human_verdicts_v1.csv, human_verdicts_hold_v1.csv,
*         override_verdicts_v2.csv, override_verdicts_v3.csv, hold_verdicts_v2.csv,
*         photo_readings_master.csv
*         ${imgtables}\sweep_check2_ids.csv
*         ${imgout}\rect_all_status.csv
* OUTPUT  ..\outputs\decimal_drift\magnitude_labels.csv        every label, with split
*         ..\outputs\decimal_drift\magnitude_labels_tune.csv   the tuning half only
*         ..\outputs\decimal_drift\magnitude_label_conflicts.csv
*         ..\outputs\decimal_drift\magnitude_split_ledger.csv  read, then appended to
*         ..\outputs\decimal_drift\check2_crop_manifest.csv    the run list: every
*                                                             Check 2 photograph with a crop
*
* The outputs go beside THIS do-file's checkout, not into ${imgout}: this is a branch
* experiment, and the main tree's outputs folder is shared by every checkout.
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 19_magnitude_labels.do
********************************************************************************

clear all
do "00_photo_globals.do"

local KGSPLIT 30
local SEED    20261009

global ddout "`c(pwd)'\..\outputs\decimal_drift"
mkdir_missing "${ddout}"

********************************************************************************
* A. Blind human readings of the display
********************************************************************************

import delimited "${imgqc}/human_verdicts_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
gen str24 src = "human_v1"
tempfile hv1
save "`hv1'"

import delimited "${imgqc}/human_verdicts_hold_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
gen str24 src = "hold_v1"
append using "`hv1'"

keep if reading_source == "scale"
* 14_final_corrections.do, owner decision 1: this reviewer's "1.5L" is a printed
* package volume that the parser classified as a scale reading.
drop if image_code == "1773797771519"

destring id h_display_val, replace
gen double label_g = cond(h_display_val < `KGSPLIT', h_display_val*1000, h_display_val)
keep image_code id src label_g
tempfile pool
save "`pool'"

********************************************************************************
* B. Owner verdicts on proposals, grams only
********************************************************************************

foreach f in override_verdicts_v2 override_verdicts_v3 hold_verdicts_v2 {
	import delimited "${imgqc}/`f'.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	gen str24 src = "`f'"
	keep if verdict_unit == "g"
	destring id verdict_value, replace
	rename verdict_value label_g
	keep image_code id src label_g
	append using "`pool'"
	save "`pool'", replace
}

* Where a printed label governed the photograph's reading, the verdict is about the
* label and says nothing about the display.
preserve
	import delimited "${imgqc}/photo_readings_master.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	keep image_code evidence_is_label
	destring evidence_is_label, replace
	tempfile lab
	save "`lab'"
restore
merge m:1 image_code using "`lab'", keep(master match) nogen
qui count if evidence_is_label == 1 & src != "human_v1" & src != "hold_v1"
di as txt "  owner verdicts dropped, label evidence ......... " r(N)
drop if evidence_is_label == 1 & src != "human_v1" & src != "hold_v1"
drop evidence_is_label

********************************************************************************
* C. Restrict to Check 2 photographs that have a rectified crop
********************************************************************************

preserve
	import delimited "${imgtables}/sweep_check2_ids.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	keep id
	destring id, replace
	duplicates drop
	tempfile c2
	save "`c2'"
restore
merge m:1 id using "`c2'", keep(match) nogen

preserve
	import delimited "${imgout}/rect_all_status.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	keep if substr(status, 1, 2) == "ok"
	keep image_code
	duplicates drop
	tempfile cr
	save "`cr'"
restore
merge m:1 image_code using "`cr'", keep(match) nogen

* ---- the population the classifier runs on -------------------------------------
* Every Check 2 photograph with a crop, labelled or not. Built here so the run list and
* the label list are restricted by the same two merges and cannot drift apart.
preserve
	import delimited "${imgout}/bridge/photo_id_bridge.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	gen str32 image_code = subinstr(filename, ".jpg", "", .)
	keep id image_code
	merge 1:1 id using "`c2'", keep(match) nogen
	qui count
	di as txt "  Check 2 photographs ............................ " r(N)
	merge 1:1 image_code using "`cr'", keep(match) nogen
	qui count
	di as txt "  ... with a rectified crop (the run list) ....... " r(N)
	sort image_code
	export delimited using "${ddout}\check2_crop_manifest.csv", replace
restore

********************************************************************************
* D. The label
********************************************************************************

qui count if missing(label_g) | label_g <= 0
di as txt "  dropped, no positive value ..................... " r(N)
drop if missing(label_g) | label_g <= 0

* decade_of is defined in 00_photo_globals.do, shared with 20_decimal_drift.do
decade_of decade label_g
gen byte true_pos = 4 - decade if inrange(decade, 0, 3)
qui count if missing(true_pos)
di as txt "  dropped, outside 1 - 9,999 g ................... " r(N)
drop if missing(true_pos)

* ---- one label per photograph ----------------------------------------------------
sort image_code src
by image_code: egen byte pos_min = min(true_pos)
by image_code: egen byte pos_max = max(true_pos)
gen byte conflict = pos_min != pos_max

preserve
	keep if conflict
	keep image_code id src label_g true_pos
	export delimited using "${ddout}\magnitude_label_conflicts.csv", replace
	qui levelsof image_code
	di as txt "  photographs whose labels disagree on decade .... " r(r)
restore
drop if conflict

by image_code: gen int n_sources = _N
gen str120 sources = src
by image_code: replace sources = sources[_n-1] + ";" + src if _n > 1
by image_code: keep if _n == _N
keep image_code id true_pos label_g n_sources sources

********************************************************************************
* E. Split, and write
********************************************************************************

* THE SPLIT IS A LEDGER, NOT A DRAW. A photograph keeps the half it was first assigned
* to, for good. A fresh stratified draw on every run would move photographs between
* halves whenever a label changed -- and one did: the decade rule once put a 1,000 g
* label in the 100s, its correction re-drew the strata, and a photograph the classifier
* had been tuned on landed in the held-back half. Only photographs not yet in the
* ledger are drawn, and they are appended to it.
gen str8 split = ""
capture confirm file "${ddout}\magnitude_split_ledger.csv"
local have_ledger = (_rc == 0)
if `have_ledger' {
	preserve
		import delimited "${ddout}\magnitude_split_ledger.csv", clear varnames(1) ///
			delimiter(",") encoding("utf-8") stringcols(_all)
		keep image_code split
		rename split split_ledger
		tempfile led
		save "`led'"
	restore
	merge 1:1 image_code using "`led'", keep(master match) nogen
	replace split = split_ledger if !missing(split_ledger)
	drop split_ledger
}
qui count if split == ""
di as txt "  photographs new to the split ledger ............ " r(N)

set seed `SEED'
sort image_code
gen double u = runiform()
bysort true_pos (u): gen long draw_n = sum(split == "")
replace split = cond(mod(draw_n, 2) == 1, "tune", "holdout") if split == ""
drop u draw_n

* append the new assignments; rows already in the ledger are never rewritten
preserve
	keep image_code split
	if `have_ledger' {
		merge 1:1 image_code using "`led'", nogen
		replace split = split_ledger if !missing(split_ledger)
		drop split_ledger
	}
	sort image_code
	export delimited using "${ddout}\magnitude_split_ledger.csv", replace
restore

di as res _n "{hline 78}"
di as res "MAGNITUDE LABELS, Check 2 photographs with a crop"
di as res "{hline 78}"
tab true_pos split, m
tab n_sources split

sort image_code
export delimited using "${ddout}\magnitude_labels.csv", replace
preserve
	keep if split == "tune"
	keep image_code true_pos
	export delimited using "${ddout}\magnitude_labels_tune.csv", replace
restore

qui count
di as res _n "19_magnitude_labels complete: " r(N) " labelled photographs"
di as txt "  ${ddout}\magnitude_labels.csv"
