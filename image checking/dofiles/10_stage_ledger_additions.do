********************************************************************************
* 10_stage_ledger_additions.do -- turn photograph verdicts into ledger rows
*
* WHAT IT DOES. Writes the rows that would be added to
* reference/reviewed/snap_verdicts.csv to apply the photograph corrections, in that
* file's exact schema, to a STAGING file. It does not touch the ledger itself.
*
* WHY IT STAGES RATHER THAN APPLIES. Three of the seven corrections land on keys that
* ALREADY CARRY AN ADJUDICATED VERDICT -- a person looked at those rows in an earlier
* review round and decided. Overwriting a human decision with a different human
* decision is legitimate here, because a photograph of the scale is better evidence
* than the numbers the earlier reviewer had. It is not something a do-file should do
* quietly. So the conflicts are written out, named, and left for an explicit call.
*
* 05_manual_corrections.do asserts that one content key never carries two different
* verdicts. Appending a conflicting row WITHOUT removing the old one does not produce a
* wrong answer -- it halts the build. That assertion is the reason this is safe to get
* wrong, and the reason the superseded rows must be REMOVED rather than just added to.
*
* ---- WHAT THE CONFLICTS SHOW, WHICH IS A FINDING IN ITS OWN RIGHT ---------------
* On two of the three, the ledger chose the BLOCK reading and the photograph agrees
* with the ANCHOR:
*
*   cabbage   0.600  ledger 600 (chose block)  anchor said 60   photograph reads 60
*   ice cream 0.950  ledger 950 (chose block)  anchor said 95   photograph reads 95
*
* That is direct evidence on issue #38 section 3's "block governs" concern: where the
* two disagreed by a decade, the earlier review preferred the block reading and the
* photographs say the anchor was right. Two rows is not a pattern, but it is the first
* outside evidence on that choice and it points one way.
*
* The third conflict is the glare row: ledger 25, anchor 250, photograph 30. The
* photograph agrees with NEITHER, and the reviewer flagged the reading as uncertain
* before being asked to stand behind it.
*
* ---- WHAT THIS CANNOT EXPRESS --------------------------------------------------
* The ledger sets `corrected_weight' and nothing else. Two corrections change the
* DIMENSION as well -- 760 g and 700 g become 355 mL under the mL rule -- and
* `corrected_unit' stays "g" for those rows whatever this file writes.
*
* Under the build's own 1 g per mL convention the NUMBER is then right and only the
* label is wrong, so applying these still improves the data. But it misrecords a
* declared volume as a measured mass, which is exactly what issue #40 is about. Those
* two rows are marked in the staging file.
*
* INPUT   ${imgqc}\photo_corrections.csv
*         ${btemp}\nsu_weighings_cpi.dta, ${btemp}\prelim_nsu_data.dta
*         ${root}\Data Cleaning\reference\reviewed\snap_verdicts.csv
* OUTPUT  ${imgqc}\ledger_additions_staged.csv
*         ${imgqc}\ledger_conflicts.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 10_stage_ledger_additions.do
********************************************************************************

clear all
do "00_photo_globals.do"

local LEDGER "${root}\Data Cleaning\reference\reviewed\snap_verdicts.csv"

********************************************************************************
* A. The corrections a human stands behind
********************************************************************************

import delimited "${imgqc}/photo_corrections.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id photo_value corrected_weight, replace

* `review' rows are included: the project owner has taken the photograph readings as
* truth on those two, which is a decision recorded here rather than assumed.
keep if tier == "A human" & inlist(verdict, "correct", "review")
keep id image_code photo_value photo_unit verdict
rename verdict photo_verdict
tempfile fixes
save "`fixes'"

********************************************************************************
* B. The ledger's content key, rebuilt exactly as 05_manual_corrections.do builds it
********************************************************************************

use "${btemp}/nsu_weighings_cpi.dta", clear
keep id pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
     item_nsu_hetero_type corrected_unit
decode item_nsu_hetero_type, gen(hetero_group)
decode corrected_unit, gen(pub_dim)
merge 1:1 id using "${btemp}/prelim_nsu_data.dta", ///
	keepusing(weight unit) keep(match) nogen

merge 1:1 id using "`fixes'", keep(match) nogen

* Six significant digits, matching 05 exactly. `weight' is a Stata float, so 1265 holds
* as 1264.9999; an exact join drops such rows silently and has done, on 2 of 10.
gen str244 vk = pull_province + "|" + pull_municipal_city + "|" + pull_item + "|" ///
	+ harmonized_nsu_unit + "|" + hetero_group + "|" + strofreal(weight, "%9.6g")

********************************************************************************
* C. Which keys the ledger already answers
********************************************************************************

preserve
	import delimited using "`LEDGER'", clear varnames(1) encoding("utf-8") ///
		stringcols(1 2 3 4 5)
	gen str244 vk = province + "|" + municipality + "|" + item + "|" ///
		+ harmonized_nsu_unit + "|" + hetero_group + "|" ///
		+ strofreal(raw_weight, "%9.6g")
	keep vk verdict chose block_says anchor_says
	rename (verdict chose block_says anchor_says) ///
	       (existing_verdict existing_chose existing_block existing_anchor)
	duplicates drop vk, force
	tempfile led
	save "`led'"
restore

merge m:1 vk using "`led'", keep(master match) gen(_mled)
gen byte conflicts = (_mled == 3) & (abs(existing_verdict - photo_value) > 1e-6)
gen byte already_agrees = (_mled == 3) & !conflicts

* The mL rule changes a dimension the ledger cannot carry.
gen byte dimension_unexpressed = (photo_unit == "mL") & (pub_dim != "mL")

di as res _n "{hline 78}"
di as res "STAGING PHOTOGRAPH VERDICTS FOR THE REVIEW LEDGER"
di as res "{hline 78}"
qui count
di as txt "  corrections to stage ................ " r(N)
qui count if _mled == 3
di as txt "  keys the ledger already answers ..... " r(N)
qui count if conflicts
di as txt "    of which CONFLICT ................. " r(N)
qui count if already_agrees
di as txt "    of which already agree ............ " r(N)
qui count if dimension_unexpressed
di as txt "  dimension change the ledger cannot carry " r(N)

di as res _n "  CONFLICTS -- an earlier reviewer decided these differently"
list image_code pull_item weight existing_verdict existing_chose ///
     existing_block existing_anchor photo_value if conflicts, noobs abbrev(12)

di as res _n "  DIMENSION NOT EXPRESSIBLE -- number right, label stays grams (#40)"
list image_code pull_item weight pub_dim photo_value photo_unit ///
	if dimension_unexpressed, noobs abbrev(12)

********************************************************************************
* D. Write the staging files, in the ledger's schema
********************************************************************************

preserve
	keep if conflicts
	keep image_code id pull_province pull_municipal_city pull_item ///
	     harmonized_nsu_unit hetero_group weight ///
	     existing_verdict existing_chose existing_block existing_anchor photo_value
	gsort image_code
	export delimited using "${imgqc}\ledger_conflicts.csv", replace
restore

* The ledger's own column order and names. `chose' records WHAT DECIDED the value, and
* "photo" is a new value in that column -- the earlier rounds could only choose between
* block and anchor because that was all the evidence there was.
gen str12 chose = "photo"
rename (pull_province pull_municipal_city pull_item weight unit) ///
       (province municipality item raw_weight raw_unit)
gen double verdict = photo_value
gen block_says  = existing_block
gen anchor_says = existing_anchor
gen id_at_review = id

keep province municipality item harmonized_nsu_unit hetero_group raw_unit ///
     raw_weight verdict chose block_says anchor_says id_at_review ///
     image_code conflicts dimension_unexpressed photo_unit photo_verdict
order province municipality item harmonized_nsu_unit hetero_group raw_unit ///
      raw_weight verdict chose block_says anchor_says id_at_review
gsort image_code
export delimited using "${imgqc}\ledger_additions_staged.csv", replace

di as res _n "10_stage_ledger_additions complete"
di as txt "  staged     ${imgqc}\ledger_additions_staged.csv"
di as txt "  conflicts  ${imgqc}\ledger_conflicts.csv"
di as txt _n "NOTHING HAS BEEN APPLIED. To apply, the conflicting keys must first be"
di as txt "REMOVED from reference/reviewed/snap_verdicts.csv -- appending beside them"
di as txt "trips 05_manual_corrections.do's one-key-one-verdict assertion and halts"
di as txt "the build. That assertion is why getting this wrong is safe."
