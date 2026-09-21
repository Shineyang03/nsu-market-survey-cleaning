********************************************************************************
* 09_photo_corrections.do -- corrected weights, read off the photographs
*
* WHAT THIS IS. A verdict ledger keyed on `id': for every photograph that has been
* read, what the image says the value should be, and whether that differs from what the
* build published.
*
* IT IS AN INPUT, NOT A PATCH. Section 9 of the handover brief is explicit: verdicts
* are an input to the pipeline, never an edit to a deliverable. The deliverables rebuild
* from their inputs, so a hand edit is silently overwritten on the next run. Nothing
* here writes to outputs/build. To make a correction take effect, feed the rows flagged
* `correct' into the review ledger that 05_manual_corrections.do reads, then rebuild and
* run dofiles/verify_pipeline.py.
*
* ---- THE mL RULE ---------------------------------------------------------------
* Decided 2026-09-20 by the project owner, and it overrides the enumerator:
*
*   WHERE BOTH A PRINTED VOLUME AND A SCALE READING ARE LEGIBLE, THE PRINTED VOLUME
*   GOVERNS -- even where the field officer recorded the scale reading.
*
* The reasoning is that the printed volume is what the vendor's unit CONTAINS, while
* the scale reading is the container plus its contents. The photographs make the gap
* concrete: a `355 mL' can reads 700 g and 760 g on the scale, which no density
* reconciles because most of that mass is not the drink.
*
* THE RULE IS APPLIED ONLY WHERE A HUMAN READ BOTH. It overrides a field record, so it
* is not applied off a model reading. Tier B rows below carry a flag where a package
* label was seen, and wait for a person.
*
* ---- TWO TIERS OF EVIDENCE, AND THEY MUST NOT BE MIXED --------------------------
*   A  human      a person read the photograph blind. Authoritative.
*   B  model      Sonnet read it; no human has. Sonnet scores 97% against the human on
*                 33 readings, so these are good -- but 97% is not 100%, and a
*                 correction that overwrites a published weight should not rest on it.
*                 Published as `provisional': a proposal for a human to confirm.
*
* ---- WHAT THIS DOES NOT COVER ---------------------------------------------------
* 3,495 of the 3,535 must-tier images have not been read by anyone. This file corrects
* what has been looked at and nothing else. It is not a sweep of Check 2.
*
* INPUT   ${imgqc}\human_scored_v1.csv       human readings, scored
*         ${imgqc}\reconcile_calib_v1.csv    model readings
*         ${btemp}\nsu_weighings_cpi.dta     the published values
* OUTPUT  ${imgqc}\photo_corrections.csv     the ledger
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 09_photo_corrections.do
********************************************************************************

clear all
do "00_photo_globals.do"

local TOL      0.02
local REVIEWER "photo review, human_v1 + calib_v1"
local RDATE    "2026-09-20"

********************************************************************************
* A. TIER A -- human readings
********************************************************************************

import delimited "${imgqc}/human_scored_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id human_g corrected_weight raw_weight h_glare_flag typed_ratio, replace

gen str8 tier = "A human"

* THE VALUE THE PHOTOGRAPH SUPPORTS.
* A package volume is a VOLUME and is published in mL; a scale reading is a MASS in
* grams. They are different dimensions and the unit column says which, rather than
* both being flattened into one number whose meaning depends on a row you have to
* look up.
gen double photo_value = .
gen str4   photo_unit  = ""

* scale rows: human_g is already the display normalised to grams
replace photo_value = human_g   if reading_source == "scale"
replace photo_unit  = "g"       if reading_source == "scale"

* package rows: the mL rule. The number is taken from the parser's own
* `h_display_val' rather than re-extracted from the raw string here -- a second
* implementation of "pull the number out of what the reviewer typed" is a second place
* for it to disagree, and 08's export does not carry the column.
preserve
	import delimited "${imgqc}/human_verdicts_v1.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id h_display_val, replace
	keep id h_display_val
	tempfile hv
	save "`hv'"
restore
merge 1:1 id using "`hv'", keep(master match) nogen

replace photo_value = h_display_val if reading_source == "package"
replace photo_unit  = "mL"          if reading_source == "package"
drop h_display_val

qui count if missing(photo_value)
if r(N) > 0 {
	di as error "`r(N)' human row(s) yield no value -- a reading was unparseable."
	list image_code h_display_raw reading_source if missing(photo_value), noobs
	exit 459
}

keep id image_code tier stratum rawtick raw_weight corrected_weight ///
     photo_value photo_unit reading_source h_display_raw h_glare_flag h_notes
rename h_display_raw photo_read_raw
rename h_notes       reviewer_note
tempfile tierA
save "`tierA'"

********************************************************************************
* B. TIER B -- model readings, where no human has looked
********************************************************************************

import delimited "${imgqc}/reconcile_calib_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id corrected_weight raw_weight, replace
destring display_textsonnet, gen(m_sonnet) force
keep if !missing(m_sonnet)

* Same normalisation as everywhere else in this subsystem: below 30 is kilograms.
gen double photo_value = cond(m_sonnet < 30, m_sonnet*1000, m_sonnet)
gen str4   photo_unit  = "g"
gen str8   tier = "B model"
gen str16  reading_source = "scale"
rename display_textsonnet photo_read_raw

* A package label the model saw. The mL rule is NOT applied here -- it overrides a
* field record and must not run off a model reading -- but the flag tells a reviewer
* which rows the rule would touch.
gen byte pkg_seen = !missing(package_textsonnet) & trim(package_textsonnet) != ""
gen str80 reviewer_note = cond(pkg_seen, ///
	"package label visible: " + package_textsonnet + " -- mL rule NOT applied, needs a human", "")
gen byte h_glare_flag = 0

keep id tier stratum rawtick raw_weight corrected_weight photo_value photo_unit ///
     reading_source photo_read_raw reviewer_note h_glare_flag pkg_seen

* Drop anything Tier A already covers: a human reading supersedes a model one.
merge 1:1 id using "`tierA'", keep(master) nogen

* image_code, so the ledger keys the same way the workbook does.
* DROPPED FIRST. The merge against Tier A above brought `image_code' into this frame as
* an all-missing column, and Stata's merge keeps the MASTER's value for a variable that
* exists on both sides -- so merging the codes in would silently leave every Tier B row
* blank while reporting a clean match.
capture drop image_code
preserve
	import delimited "${imgbridge}/photo_id_bridge.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	gen str32 image_code = subinstr(filename, ".jpg", "", .)
	keep id image_code
	tempfile codes
	save "`codes'"
restore
merge 1:1 id using "`codes'", keep(master match) nogen

append using "`tierA'"
replace pkg_seen = 0 if missing(pkg_seen)

********************************************************************************
* C. The verdict
********************************************************************************

* Compared against the PUBLISHED value, which the pipeline computed. Re-deriving one
* from the raw typed weight re-implements the block rule and does not cover the litre
* branch -- that mistake produced a false positive twice before it was caught.
gen double ratio = photo_value / corrected_weight if !missing(photo_value, corrected_weight) & corrected_weight > 0

gen str10 verdict = ""
replace verdict = "confirm" if !missing(ratio) & abs(ratio - 1) < `TOL'
replace verdict = "correct" if !missing(ratio) & abs(ratio - 1) >= `TOL'

* A reading the reviewer flagged for glare is not firm enough to overturn a published
* weight on. It is surfaced for a second look rather than silently applied or silently
* dropped.
replace verdict = "review"  if verdict == "correct" & h_glare_flag == 1
replace verdict = "review"  if missing(ratio)

* Provisional: a model reading may PROPOSE a change but never carry one on its own.
gen byte provisional = (tier == "B model")
replace verdict = "propose" if provisional & verdict == "correct"

gen str80 evidence = photo_unit + " " + string(photo_value, "%12.0g") + ///
	" read from photograph; published " + string(corrected_weight, "%12.0g")
gen str48 reviewer = "`REVIEWER'"
gen str12 rdate    = "`RDATE'"

di as res _n "{hline 78}"
di as res "PHOTO CORRECTION LEDGER"
di as res "{hline 78}"
tab verdict tier

di as res _n "  TIER A -- HUMAN-CONFIRMED CHANGES (authoritative)"
gsort -ratio
list image_code stratum rawtick raw_weight photo_read_raw photo_value photo_unit ///
     corrected_weight ratio if verdict == "correct" & tier == "A human", noobs abbrev(13)

di as res _n "  TIER A -- FLAGGED FOR A SECOND LOOK (reviewer noted glare)"
list image_code stratum raw_weight photo_read_raw photo_value corrected_weight ///
	if verdict == "review" & tier == "A human", noobs abbrev(13)

di as res _n "  TIER B -- MODEL PROPOSALS (not authoritative; need a human)"
qui count if verdict == "propose"
di as txt "    " r(N) " proposed change(s)"
gsort -ratio
list image_code stratum raw_weight photo_read_raw photo_value corrected_weight ratio ///
	if verdict == "propose" in 1/15, noobs abbrev(13)

qui count if pkg_seen & tier == "B model"
di as txt _n "  Tier B rows where a package label is visible and the mL rule would apply,"
di as txt "  but has not been (needs a human): " r(N)

********************************************************************************
* D. Export
********************************************************************************

order id image_code tier provisional verdict photo_value photo_unit reading_source ///
      photo_read_raw corrected_weight ratio rawtick raw_weight stratum ///
      pkg_seen h_glare_flag evidence reviewer rdate reviewer_note
gsort tier verdict image_code
export delimited using "${imgqc}\photo_corrections.csv", replace

qui count
di as res _n "09_photo_corrections complete: " r(N) " rows"
di as txt "  ${imgqc}\photo_corrections.csv"
di as txt _n "THIS IS AN INPUT, NOT A PATCH. Nothing here has changed a published value."
di as txt "To apply: feed verdict==correct into the ledger 05_manual_corrections.do"
di as txt "reads, rebuild, then run dofiles/verify_pipeline.py."
di as txt _n "3,495 of the 3,535 must-tier images remain unread by anyone."
