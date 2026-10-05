********************************************************************************
* 13_apply_photo_rule.do -- the override rule, and what it would change
*
* THE RULE, set by the project owner 2026-09-20:
*
*   Where a photograph reading differs from the published value, the photograph
*   governs -- EXCEPT that anything 2x or more away from the published value is held
*   for a human to confirm before it is applied.
*
* WHY THE 2x GATE IS THE RIGHT SHAPE. Sonnet reads at 97% against a human. On roughly
* 2,400 overrides that is about 74 rows changed wrongly, which is a poor trade if the
* wrong changes are large and a fine one if they are small. The gate spends human
* attention exactly where a model error would do damage: a decade slip moves a weight
* by 1,000%, and those are rare enough to look at individually. A 5% disagreement is
* within the noise of reading a glary display and costs little either way.
*
* A HUMAN READING IS NEVER HELD. If a person read the photograph, the confirmation the
* gate exists to obtain has already happened; holding it would ask for it twice.
*
* HAIKU CANNOT TRIGGER AN OVERRIDE. 12_photo_readings_master.do never resolves to it.
*
* ---- THIS FILE STILL CHANGES NOTHING -------------------------------------------
* It writes a proposal. Section 9 of the handover brief: verdicts are an INPUT to the
* pipeline, never an edit to a deliverable, because deliverables rebuild from their
* inputs and a hand edit is silently overwritten. Applying means adding the `override'
* rows to reference/reviewed/snap_verdicts.csv -- and REMOVING any superseded row
* first, because 05_manual_corrections.do asserts one key never carries two verdicts.
*
* ---- WHAT IT CANNOT EXPRESS ----------------------------------------------------
* The ledger sets corrected_weight only. A row whose photo_unit is mL but whose
* published dimension is g changes the NUMBER correctly and leaves the LABEL wrong.
* Under the build's 1 g per mL convention that is numerically harmless today and still
* misrecords a declared volume as a measured mass -- issue #40. Flagged, not hidden.
*
* INPUT   ${imgqc}\photo_readings_master.csv
* OUTPUT  ${imgqc}\photo_rule_proposal.csv    every row, with its verdict
*         ${imgqc}\photo_rule_hold.csv        the rows needing a human
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 13_apply_photo_rule.do
********************************************************************************

clear all
do "00_photo_globals.do"

* ---- THE DIALS ------------------------------------------------------------------
local TOL  0.02   // within this of the published value counts as agreement
local GATE 2      // this far off, or further, waits for a person

import delimited "${imgqc}/photo_readings_master.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
* `import delimited' LOWERCASES every variable name, so the column written as
* mL_rule_pending arrives as ml_rule_pending. Renamed once here rather than spelled
* the lowercase way throughout, so this file and 12 keep using the same name for the
* same thing.
capture confirm variable ml_rule_pending
if _rc == 0 rename ml_rule_pending mL_rule_pending

destring id photo_g corrected_weight raw_weight has_reading from_human ///
	mL_rule_pending pkg_seen h_glare_flag, replace

qui count
local n_all = r(N)
keep if has_reading == 1
qui count
local n_read = r(N)

gen double ratio = photo_g / corrected_weight if !missing(photo_g, corrected_weight) & corrected_weight > 0

* A published value of zero or missing cannot be ratioed against; those rows are
* surfaced rather than dropped, because "nothing was published" is itself a finding
* the photograph can now speak to.
gen byte no_published = missing(corrected_weight) | corrected_weight <= 0

gen str16 rule_verdict = ""
replace rule_verdict = "no_published" if no_published
replace rule_verdict = "confirm"      if rule_verdict == "" & abs(ratio - 1) < `TOL'
replace rule_verdict = "override"     if rule_verdict == "" & ratio < `GATE' & ratio > 1/`GATE'
replace rule_verdict = "hold"         if rule_verdict == ""

* A person already looked at these: the gate's confirmation has happened.
replace rule_verdict = "override" if rule_verdict == "hold" & from_human == 1

gen byte dimension_unexpressed = (photo_unit == "mL") & (pub_unit != "mL")

di as res _n "{hline 78}"
di as res "PHOTO OVERRIDE RULE -- photograph governs, 2x or more waits for a human"
di as res "{hline 78}"
di as txt "  photographed weighings in the master ...... `n_all'"
di as txt "  with a resolved reading .................. `n_read'"
di as txt ""
tab rule_verdict

di as res _n "  OVERRIDES, by how far they move the published value"
gen str12 band = ""
replace band = "under 1.2x"  if rule_verdict=="override" & max(ratio,1/ratio) < 1.2
replace band = "1.2 - 1.5x"  if rule_verdict=="override" & max(ratio,1/ratio) >= 1.2 & max(ratio,1/ratio) < 1.5
replace band = "1.5 - 2x"    if rule_verdict=="override" & max(ratio,1/ratio) >= 1.5 & max(ratio,1/ratio) < 2
replace band = "2x+ (human)" if rule_verdict=="override" & max(ratio,1/ratio) >= 2
tab band if rule_verdict == "override"

di as res _n "  HELD FOR A HUMAN, by magnitude"
gen str12 hband = ""
replace hband = "2 - 5x"    if rule_verdict=="hold" & max(ratio,1/ratio) < 5
replace hband = "5 - 20x"   if rule_verdict=="hold" & max(ratio,1/ratio) >= 5 & max(ratio,1/ratio) < 20
replace hband = "20x+"      if rule_verdict=="hold" & max(ratio,1/ratio) >= 20
tab hband if rule_verdict == "hold"

di as res _n "  by the rule that set the published value:"
tab pub_rule rule_verdict, row

qui count if dimension_unexpressed & inlist(rule_verdict,"override","hold")
di as txt _n "  changes the dimension, which the ledger cannot carry (#40): " r(N)

di as res _n "  THE LARGEST PROPOSED CHANGES (held rows, worst first)"
gen double offby = max(ratio, 1/ratio)
gsort -offby
list image_code pull_item raw_tick raw_weight corrected_weight photo_g photo_unit ///
	photo_src offby if rule_verdict == "hold" in 1/20, noobs abbrev(12)

********************************************************************************
* Export
********************************************************************************

order id image_code rule_verdict photo_g photo_unit photo_src from_human ///
      corrected_weight ratio offby raw_tick raw_weight pub_unit pub_rule ///
      dimension_unexpressed mL_rule_pending pull_item harmonized_nsu_unit ///
      pull_province pull_municipal_city market_name store_stall_name vendor_id
gsort rule_verdict -offby
export delimited using "${imgqc}\photo_rule_proposal.csv", replace

* ---- the override rows, laid out for an APPROVE/REJECT review -------------------
* The rule applies these automatically. They are exported for a person anyway, because
* the hold set showed what model-vs-published disagreement actually selects for: of 37
* held rows a person read, the model was wrong on 29 and the PUBLISHED value was right
* on 27. These 87 are the same signal at smaller magnitude, and none has been read by a
* person. Applying them unreviewed would very likely inject more error than it removes.
preserve
	keep if rule_verdict == "override"
	gen double published_now  = corrected_weight
	gen double proposed_value = round(photo_g, 0.1)
	gen double times_off      = round(offby, 0.01)
	keep id image_code pull_item raw_tick raw_weight published_now proposed_value ///
	     photo_unit times_off photo_src pub_rule
	gsort -times_off
	export delimited using "${imgqc}\override_review_ids.csv", replace
	qui count
	di as res _n "  override rows exported for review: " r(N)
	di as txt "  ${imgqc}\override_review_ids.csv"

	* ---- WHAT IS ACTUALLY STILL OUTSTANDING ------------------------------------
	* The queue above is the full population, and it is regenerated whenever a rule
	* upstream changes. Handing a reviewer the full file after each such change asks
	* them to re-answer everything they have already answered, and a second answer to
	* the same photograph is not new evidence -- it is an invitation to disagree with
	* oneself and then have to adjudicate the adjudication.
	*
	* So the rows carrying a recorded verdict are subtracted here, and the remainder
	* is exported separately. The verdict files are written by
	* parse_validation_workbook.py --mode adjudicate.
	*
	* EVERY `override_verdicts_v*.csv' IS READ, not a named one. A review happens in
	* rounds -- v2 answered 108 rows, a rule change surfaced 19 more, v3 answered
	* those plus the one v2 left blank -- and a block naming a single round goes stale
	* on the day the next round lands, silently, by re-asking questions that have
	* already been answered. The file glob is the mechanism; a comment saying
	* "remember to add v4" is not.
	*
	* A row answered in two rounds takes the LATEST round, because that is the order a
	* reviewer revises in: v2 left `1774421610417' blank and v3 ruled on it.
	*
	* NO NESTED PRESERVE. This block runs inside the override preserve above, so it
	* parks the queue in a tempfile and reads it back rather than preserving again,
	* which is r(621).
	local vfiles : dir "${imgqc}" files "override_verdicts_v*.csv"
	local vfiles : list sort vfiles
	if `:word count `vfiles'' > 0 {
		tempfile queue adjudicated
		qui save "`queue'"

		local round = 0
		foreach f of local vfiles {
			local ++round
			import delimited using "${imgqc}/`f'", clear stringcols(_all) varnames(1)
			keep if trim(approve) != ""
			keep image_code
			gen int vround = `round'
			if `round' > 1 append using "`adjudicated'"
			qui save "`adjudicated'", replace
		}
		* latest round wins, one row per photograph
		bysort image_code (vround): keep if _n == _N
		qui count
		local n_adj = r(N)
		qui save "`adjudicated'", replace

		use "`queue'", clear
		merge 1:1 image_code using "`adjudicated'", keep(master) nogen
		gsort -times_off
		export delimited using "${imgqc}\override_review_new.csv", replace
		qui count
		di as res "  of which NOT yet adjudicated: " r(N)
		di as txt "  (`n_adj' verdicts recorded across " ///
			`:word count `vfiles'' " round(s))"
		* The `dir' macro returns each name ALREADY QUOTED, so it cannot be dropped
		* into a display string -- "a.csv" "b.csv" inside quotes is an invalid name.
		foreach f of local vfiles {
			di as txt "     `f'"
		}
		di as txt "  ${imgqc}\override_review_new.csv"
	}
	else {
		di as txt "  (no verdict file yet -- the whole queue is outstanding)"
	}
restore

preserve
	keep if rule_verdict == "hold"
	gsort -offby
	export delimited using "${imgqc}\photo_rule_hold.csv", replace
	qui count
	di as res _n "  held for human confirmation: " r(N) " row(s)"
	di as txt "  ${imgqc}\photo_rule_hold.csv"
	di as txt "  -> make_validation_workbook.py builds a blind workbook from these"
restore

di as res _n "13_apply_photo_rule complete"
di as txt "  ${imgqc}\photo_rule_proposal.csv"
di as txt _n "NOTHING APPLIED. Overrides go to reference/reviewed/snap_verdicts.csv,"
di as txt "superseded rows removed first, then rebuild and run verify_pipeline.py."
