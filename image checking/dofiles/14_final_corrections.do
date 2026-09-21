********************************************************************************
* 14_final_corrections.do -- every photograph verdict a person stands behind,
*                            in the two ledger schemas the build reads
*
* WHAT IT PRODUCES
*   ledger_snap_additions.csv   rows for reference/reviewed/snap_verdicts.csv (weight)
*   ledger_unit_additions.csv   rows for reference/reviewed/unit_verdicts.csv (dimension)
*   ledger_snap_supersede.csv   keys whose EXISTING verdict must be removed first
*
* It still writes nothing into the build. Section 9 of the handover brief: verdicts are
* an input, never an edit to a deliverable.
*
* ---- THE EVIDENCE IT USES --------------------------------------------------------
* Only readings a PERSON made: human_verdicts_v1.csv (40) and human_verdicts_hold_v1.csv
* (37). Model readings propose; they do not carry a correction. That distinction earned
* itself on the hold set -- the model disagreed with the human on 29 of those 37, and
* the PUBLISHED value was right on 27. Auto-applying model readings there would have
* corrupted 29 rows. The 2x gate is the only reason they were seen by a person at all.
*
* Why the model looks so much worse there than its 97% overall: the hold set is DEFINED
* by model-vs-published disagreement, so it is enriched for model error by construction.
* A 97% reader's mistakes are exactly what a disagreement filter selects.
*
* ---- TWO DECISIONS TAKEN BY THE PROJECT OWNER, 2026-09-21 ------------------------
* Encoded here rather than applied by hand, so they are reviewable and reproducible.
*
*   1774320998883  cabbage. The reviewer read 0.705; the officer typed 0.885. A 7/8
*                  confusion is as likely in the reading as in the typing, and the
*                  owner ruled for the officer. NO CORRECTION -- and it is listed
*                  below rather than silently absent, because a decision not to act
*                  is still a decision.
*
*   1773797771519  ice cream. The reviewer wrote "1.5L", which is a printed package
*                  volume, not a scale display. Under the mL rule the printed volume
*                  governs even against the enumerator's record, so this publishes as
*                  1500 mL. It needs BOTH ledgers: the weight and the dimension.
*
* ---- THE SUPERSEDES ---------------------------------------------------------------
* Three corrections land on content keys that snap_verdicts.csv already answers. The
* owner ruled that the photographs win, on the grounds that those earlier verdicts were
* never checked against an image. On two of them the earlier round chose the BLOCK
* reading and the photograph agrees with the ANCHOR, which is evidence in its own right
* on issue #38 section 3.
*
* THE OLD ROWS MUST BE DELETED, NOT APPENDED BESIDE. 05_manual_corrections.do section 6
* asserts that one content key never carries two verdicts, so appending halts the build
* rather than corrupting it. ledger_snap_supersede.csv lists exactly what to remove.
*
* INPUT   ${imgqc}\human_verdicts_v1.csv, human_verdicts_hold_v1.csv
*         ${btemp}\nsu_weighings_cpi.dta, prelim_nsu_data.dta
*         ${root}\Data Cleaning\reference\reviewed\snap_verdicts.csv
* OUTPUT  the three CSVs above, in ${imgqc}
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 14_final_corrections.do
********************************************************************************

clear all
do "00_photo_globals.do"

local TOL 0.02
local KGSPLIT 30

********************************************************************************
* A. Every human reading
********************************************************************************

import delimited "${imgqc}/human_verdicts_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
gen str16 pass = "human_v1"
tempfile hv1
save "`hv1'"

import delimited "${imgqc}/human_verdicts_hold_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
gen str16 pass = "hold_v1"
append using "`hv1'"

destring id h_display_val h_glare_flag, replace
keep id image_code pass h_display_raw h_display_val reading_source h_glare_flag h_notes

* A photograph read twice keeps the later pass. The hold set re-read rows the first
* pass had already covered, and a second look by the same person supersedes the first.
gsort id pass
by id: keep if _n == _N

qui count
di as txt _n "human readings, distinct photographs: " r(N)

* ---- the value the photograph supports -----------------------------------------
gen double photo_value = cond(h_display_val < `KGSPLIT', h_display_val*1000, h_display_val)
gen str4   photo_unit  = "g"

* the mL rule, where the reviewer recorded a printed volume
replace photo_value = h_display_val if reading_source == "package"
replace photo_unit  = "mL"          if reading_source == "package"

* ---- OWNER DECISION 1: the reviewer's "1.5L" is a package volume ----------------
* The parser could not see it: its unit regex needs a word boundary, and "1.5L" has
* none between the digit and the L, so the row was classified as a scale reading.
* 1.5 L is 1500 mL.
gen byte owner_ruled = 0
replace photo_value = 1500 if image_code == "1773797771519"
replace photo_unit  = "mL" if image_code == "1773797771519"
replace reading_source = "package" if image_code == "1773797771519"
replace owner_ruled = 1 if image_code == "1773797771519"

* ---- OWNER DECISION 2: the officer's typed value stands -------------------------
gen byte no_correction = 0
replace no_correction = 1 if image_code == "1774320998883"
replace owner_ruled   = 1 if image_code == "1774320998883"

********************************************************************************
* B. Against the published build
********************************************************************************

merge 1:1 id using "${btemp}/nsu_weighings_cpi.dta", ///
	keepusing(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	          item_nsu_hetero_type corrected_weight corrected_unit) ///
	keep(master match) nogen
decode item_nsu_hetero_type, gen(hetero_group)
decode corrected_unit, gen(pub_unit)

merge 1:1 id using "${btemp}/prelim_nsu_data.dta", ///
	keepusing(weight unit) keep(master match) nogen
decode unit, gen(raw_tick)
rename weight raw_weight

gen double ratio = photo_value / corrected_weight if corrected_weight > 0

gen str12 verdict = "confirm"
replace verdict = "correct" if abs(ratio - 1) >= `TOL'
replace verdict = "owner: officer stands" if no_correction

di as res _n "{hline 78}"
di as res "FINAL PHOTOGRAPH VERDICTS"
di as res "{hline 78}"
tab verdict

* A dimension change is a separate ledger, and only where it actually differs.
gen byte needs_unit = (photo_unit == "mL") & (pub_unit != "mL") & verdict != "owner: officer stands"
qui count if needs_unit
di as txt _n "dimension changes needed (unit_verdicts): " r(N)

********************************************************************************
* C. Which keys the existing snap ledger already answers
********************************************************************************

gen str244 vk = pull_province + "|" + pull_municipal_city + "|" + pull_item + "|" ///
	+ harmonized_nsu_unit + "|" + hetero_group + "|" + strofreal(raw_weight, "%9.6g")

preserve
	import delimited using "${root}\Data Cleaning\reference\reviewed\snap_verdicts.csv", ///
		clear varnames(1) encoding("utf-8") stringcols(1 2 3 4 5)
	gen str244 vk = province + "|" + municipality + "|" + item + "|" ///
		+ harmonized_nsu_unit + "|" + hetero_group + "|" + strofreal(raw_weight, "%9.6g")
	keep vk verdict chose
	rename (verdict chose) (existing_verdict existing_chose)
	duplicates drop vk, force
	tempfile led
	save "`led'"
restore
merge m:1 vk using "`led'", keep(master match) gen(_mled)
gen byte supersedes = (_mled == 3) & verdict == "correct" & ///
	abs(existing_verdict - photo_value) > 1e-6

qui count if supersedes
di as txt _n "corrections that SUPERSEDE an existing snap verdict: " r(N)
list image_code pull_item raw_weight existing_verdict existing_chose photo_value ///
	if supersedes, noobs abbrev(12)

********************************************************************************
* D. Write the three files
********************************************************************************

di as res _n "  CORRECTIONS TO APPLY"
gsort ratio
list image_code pull_item raw_tick raw_weight h_display_raw photo_value photo_unit ///
	corrected_weight ratio if verdict == "correct", noobs abbrev(12)

preserve
	keep if verdict == "correct"
	gen str12 chose = "photo"
	rename (pull_province pull_municipal_city pull_item) (province municipality item)
	gen double verdict_val = photo_value
	gen id_at_review = id
	keep province municipality item harmonized_nsu_unit hetero_group raw_tick ///
	     raw_weight verdict_val chose id_at_review image_code photo_unit supersedes
	order province municipality item harmonized_nsu_unit hetero_group raw_tick ///
	      raw_weight verdict_val chose id_at_review
	gsort image_code
	export delimited using "${imgqc}\ledger_snap_additions.csv", replace
	qui count
	di as res _n "  snap additions: " r(N)
restore

preserve
	keep if needs_unit
	gen str4 unit_verdict = photo_unit
	gen str80 evidence = "printed package volume read from photograph " + image_code
	gen str48 reviewer = "project owner, photo review 2026-09-21"
	gen str12 verdict_date = "2026-09-21"
	keep id unit_verdict evidence reviewer verdict_date
	gsort id
	export delimited using "${imgqc}\ledger_unit_additions.csv", replace
	qui count
	di as res "  unit additions: " r(N)
restore

preserve
	keep if supersedes
	keep image_code vk existing_verdict existing_chose photo_value pull_item raw_weight
	gsort image_code
	export delimited using "${imgqc}\ledger_snap_supersede.csv", replace
	qui count
	di as res "  snap rows to REMOVE first: " r(N)
restore

di as res _n "14_final_corrections complete"
di as txt _n "NOTHING APPLIED. To apply: delete the rows listed in"
di as txt "ledger_snap_supersede.csv from snap_verdicts.csv, append"
di as txt "ledger_snap_additions.csv to it, append ledger_unit_additions.csv to"
di as txt "unit_verdicts.csv, rebuild, then run dofiles/verify_pipeline.py."
