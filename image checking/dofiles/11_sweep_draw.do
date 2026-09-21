********************************************************************************
* 11_sweep_draw.do -- the full Check 2 read: every must-tier weighing with a photo
*
* WHAT CHANGES FROM 03. That file drew a SAMPLE, 20 per stratum, to calibrate the
* instrument. This is the sweep: all 2,460 Check 2 must-tier weighings that have a
* photograph, so the override rule has an input for every row it could touch.
*
* NO SAMPLING, SO NO SEED IS NEEDED for selection -- the population is the whole tier.
* A seed still governs the SHEET ORDER downstream, so the sheets reproduce.
*
* ALREADY-READ IMAGES ARE MARKED, NOT RE-READ. 93 of the 2,460 were looked at during
* calibration and 31 of those by a person. Re-reading them would cost a wave of agents
* to produce readings that already exist, and would throw away the human ones, which
* are the best evidence in the project. `needs_reading' is what the sheet builder takes.
*
* THE BLIND SPLIT IS UNCHANGED and is enforced downstream, not here:
* make_contact_sheets.py prints a sequence number on each tile and nothing else, and
* writes the sequence-to-id mapping to a separate manifest. This file carries the typed
* weight because 13_apply_photo_rule.do needs it to compare against; it must never
* reach a sheet.
*
* INPUT   ${imgtables}\photo_targets.csv
*         ${imgqc}\readings_calib_v1.csv, readings_restest.csv, human_verdicts_v1.csv
* OUTPUT  ${imgtables}\sweep_check2_ids.csv        every Check 2 must-tier image
*         ${imgtables}\sweep_check2_toread.csv     the subset still to read
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 11_sweep_draw.do
********************************************************************************

clear all
do "00_photo_globals.do"

local BASE_C2 2460

import delimited "${imgtables}/photo_targets.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id check priority has_photo raw_weight corrected_weight, replace

keep if check == 2 & has_photo == 1
* One row per weighing: photo_targets is long over (id, check, reason).
gsort id priority
by id: keep if _n == 1

qui count
local n_c2 = r(N)
di as txt _n "Check 2 must-tier weighings with a photograph: `n_c2'  (recorded: `BASE_C2')"
if `n_c2' != `BASE_C2' {
	di as error "COUNT HAS MOVED from the recorded baseline -- say so, do not substitute."
}

* ---- what has already been read -------------------------------------------------
tempfile base
save "`base'"

* a model display reading
preserve
	import delimited "${imgqc}/readings_calib_v1.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	keep if strpos(reader, "sonnet") > 0
	keep id
	duplicates drop
	tempfile r1
	save "`r1'"
restore
preserve
	import delimited "${imgqc}/readings_restest.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	keep id
	duplicates drop
	tempfile r2
	save "`r2'"
restore
preserve
	import delimited "${imgqc}/human_verdicts_v1.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	keep id
	duplicates drop
	tempfile r3
	save "`r3'"
restore

use "`base'", clear
gen byte read_model = 0
gen byte read_human = 0
foreach f in r1 r2 {
	merge 1:1 id using "``f''", keep(master match) gen(_m)
	replace read_model = 1 if _m == 3
	drop _m
}
merge 1:1 id using "`r3'", keep(master match) gen(_m)
replace read_human = 1 if _m == 3
drop _m

gen byte needs_reading = (read_model == 0 & read_human == 0)

qui count if read_model | read_human
local n_done = r(N)
qui count if read_human
local n_hum = r(N)
qui count if needs_reading
local n_todo = r(N)

di as txt _n "  already read by a model ... `n_done'   (of which a human too: `n_hum')"
di as txt "  still to read ............. `n_todo'"

di as txt _n "still-to-read, by the rule that set the published value:"
tab snap_rule if needs_reading, m

export delimited using "${imgtables}\sweep_check2_ids.csv", replace

preserve
	keep if needs_reading
	keep id
	export delimited using "${imgtables}\sweep_check2_toread.csv", replace
restore

di as res _n "11_sweep_draw complete: `n_c2' in the tier, `n_todo' to read"
di as txt "  ${imgtables}\sweep_check2_ids.csv"
di as txt "  ${imgtables}\sweep_check2_toread.csv"
