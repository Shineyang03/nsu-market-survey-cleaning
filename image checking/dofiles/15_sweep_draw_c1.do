********************************************************************************
* 15_sweep_draw_c1.do -- the Check 1 sweep population
*
* Check 1 asks whether a measurement was taken at all and whether the ticked dimension
* is right, so it is answered by what the photograph SHOWS -- a scale, a package label,
* a measuring jug -- rather than by a number. That makes its sweep cheaper per image
* than Check 2's: a classification, not a digit read.
*
* ALREADY-READ IMAGES ARE MARKED, NOT RE-READ. A large share of Check 1's tier was
* already photographed during the Check 2 sweep, because 419 weighings are wanted by
* both checks and the calibration drew across both. Re-reading them would spend agents
* reproducing readings that exist.
*
* INPUT   ${imgtables}\photo_targets.csv
*         ${imgqc}\photo_readings_master.csv
* OUTPUT  ${imgtables}\sweep_check1_ids.csv      the whole tier
*         ${imgtables}\sweep_check1_toread.csv   the subset still to read
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 15_sweep_draw_c1.do
********************************************************************************

clear all
do "00_photo_globals.do"

import delimited "${imgtables}/photo_targets.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id check has_photo priority, replace
keep if check == 1 & has_photo == 1

* photo_targets is long over (id, check, reason); one row per weighing here.
gsort id priority
by id: keep if _n == 1

qui count
local n_tier = r(N)
di as txt _n "Check 1 must-tier weighings with a photograph: `n_tier'"

di as txt _n "by reason:"
tab reason

* ---- what already has a reading -------------------------------------------------
preserve
	import delimited "${imgqc}/photo_readings_master.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	keep id
	duplicates drop
	gen byte already = 1
	tempfile seen
	save "`seen'"
restore
merge 1:1 id using "`seen'", keep(master match) nogen
replace already = 0 if missing(already)

qui count if already
local n_done = r(N)
qui count if !already
local n_todo = r(N)
di as txt _n "  already looked at ... `n_done'"
di as txt "  still to read ....... `n_todo'"

export delimited using "${imgtables}\sweep_check1_ids.csv", replace

preserve
	keep if !already
	keep id
	export delimited using "${imgtables}\sweep_check1_toread.csv", replace
restore

di as res _n "15_sweep_draw_c1 complete: `n_tier' in the tier, `n_todo' to read"
