********************************************************************************
* 02_photo_targets.do -- which photographs to pull, for Checks 1 and 2
*
* WHAT IT PRODUCES. One row per (id, check): the weighing, which check wants it, why,
* and where to find the photograph. Keyed on `id', as the handover brief requires,
* and carrying enough locator columns that a reviewer can find the row in the field.
*
* IT DEFINES NO POPULATIONS OF ITS OWN. Every flag it reads was computed somewhere
* else and is read here as data:
*
*   Check 1, 4A  flat groups          outputs/tables/photo_check_packaging.csv
*                                     (90_diagnostics/photo_check_packaging.do)
*   Check 1, 4B  dimension grounds    outputs/build/diagnostics/photo_check1_flags.csv
*                                     (90_diagnostics/photo_check_scope.do)
*   Check 2      judgement applied    outputs/build/diagnostics/photo_check2_flags.csv
*                                     (the same file)
*   Check 2      priority ordering    outputs/tables/photo_review_queue.csv
*                                     (90_diagnostics/photo_review_queue.do)
*   photograph   id -> filename       outputs/bridge/photo_id_bridge.csv (01 here)
*
* That is deliberate and it is the project's rule: a decision rule defined in two
* places disagrees silently. "Was a judgement applied" is decided once, in
* photo_check_scope.do, which prints the counts the brief quotes and writes the rows
* behind them. If a figure here disagrees with that file, this file is wrong.
*
* MUST TIERS ONLY. The spot tiers -- packaged items outside a flat group, ice cream
* across both ticks, fresh controls, and a light sample of plain conversions -- are
* NOT built here. They need the packaged/fresh item classification, which currently
* lives inside photo_check_packaging.do and is not published at the row level. Adding
* them means publishing that classification the same way Check 1's and Check 2's
* grounds are now published, rather than restating the item list here.
*
* CHECK 3 IS NOT HERE EITHER. Its natural unit is a label pair, not a weighing, so it
* needs its own file; validate_folds.do owns the verdicts.
*
* THE PHOTOGRAPH COLUMN IS THE POINT OF THE JOIN. A target with no photograph cannot
* be checked, and the count of those is a finding in itself -- if a large share of
* Check 2's population turns out to have no scale photograph behind it, the reading
* job is much smaller than 2,472 and the brief's sizing needs revisiting.
*
* INPUT   the five files above
* OUTPUT  ${imgtables}\photo_targets.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 02_photo_targets.do
********************************************************************************

clear all
do "00_photo_globals.do"

* Recorded 2026-09-19 from photo_check_scope.do. Reported, not asserted -- see
* 01_photo_bridge.do on why a move is information rather than a failure.
local BASE_C1_DUAL    649
local BASE_C1_LIQMASS 273
local BASE_C1_SOLVOL   17
local BASE_C1_FLAT    937
local BASE_C2_MUST   2472

********************************************************************************
* A. Check 1 -- the raw data
********************************************************************************

* ---- 4B: the three dimension grounds -------------------------------------------
import delimited "${btables}/photo_check1_flags.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8")
keep id m_dualcase m_liqmass m_solvol

qui count if m_dualcase
local n_dual = r(N)
qui count if m_liqmass
local n_liq = r(N)
qui count if m_solvol
local n_sol = r(N)

* Long: a weighing on two grounds earns two rows, so a reviewer sees both reasons
* rather than one arbitrarily chosen.
gen byte check = 1
expand 3
bysort id: gen byte _g = _n
gen str48 reason = ""
replace reason = "4B dual-ticked case"        if _g == 1 & m_dualcase
replace reason = "4B liquid ticked as a mass" if _g == 2 & m_liqmass
replace reason = "4B solid ticked as Litres"  if _g == 3 & m_solvol
drop if reason == ""
drop _g m_dualcase m_liqmass m_solvol

gen str8 tier = "must"
gen byte priority = 2
* The 17 solid-as-Litre rows are small enough to do exhaustively, and the brief names
* the dual-ticked cases as the sharpest target: a contradiction inside one cell.
replace priority = 1 if reason == "4B solid ticked as Litres"
replace priority = 1 if reason == "4B dual-ticked case"

tempfile c1b
save "`c1b'"

* ---- 4A: the flat groups --------------------------------------------------------
import delimited "${tables}/photo_check_packaging.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8")
keep id flat_group nobs nven

qui count
local n_flat = r(N)
qui levelsof flat_group, local(fg)
local n_groups : word count `fg'

* ONE PHOTOGRAPH SETTLES A GROUP. Every weighing in a flat group reports the same
* number, so a single photograph showing a printed label rather than a scale answers
* for all of them. The representative is the lowest id in the group -- deterministic,
* and it does not depend on sort order the way `_n' after a plain sort would.
bysort flat_group (id): gen byte is_rep = (_n == 1)

gen byte check = 1
gen str48 reason = "4A flat group: 3+ vendors, one value"
gen str8 tier = "must"
* The representative is what a reviewer actually pulls; the rest of the group is
* carried so the group can be closed out once the representative is read.
gen byte priority = cond(is_rep, 1, 3)

append using "`c1b'"
tempfile c1
save "`c1'"

********************************************************************************
* B. Check 2 -- the decimal-drift correction
********************************************************************************

import delimited "${btables}/photo_check2_flags.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8")
keep id judgement magchg dimchg nopub snap_rule raw_weight corrected_weight rawtick dim

qui count if judgement
local n_c2 = r(N)

keep if judgement
drop judgement

* The brief's priority ordering WITHIN the must tier. It is an ordering, not a
* narrowing: all 2,472 are must-check.
*   1  in photo_review_queue.csv -- also wrong relative to its neighbours
*   2  a dimension overrule -- a larger claim than moving a decimal, since it asserts
*      the officer picked the wrong dropdown item
*   3  magnitude only -- where the thresholds worked in bulk
gen byte check = 1
replace check = 2
gen str8 tier = "must"
gen byte priority = 3
replace priority = 2 if dimchg

gen str48 reason = ""
replace reason = "C2 magnitude only -- decimal moved"   if magchg & !dimchg
replace reason = "C2 dimension only -- tick overruled"  if dimchg & !magchg
replace reason = "C2 both magnitude and dimension"      if dimchg & magchg

* The review queue's own flags, merged in rather than recomputed. `photo_review_queue'
* holds 97 rows, of which 89 are decade outliers, 5 anchor-set and 3 unpublished; the
* 3 unpublished are NOT in this population (judgement requires something published),
* so a partial match here is expected.
preserve
	import delimited "${tables}/photo_review_queue.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8")
	keep id flag_reason queue_tier
	rename flag_reason queue_flag
	tempfile q
	save "`q'"
restore
merge 1:1 id using "`q'", keep(master match) gen(_mq)
qui count if _mq == 3
local n_queue = r(N)
replace priority = 1 if _mq == 3
replace reason = reason + " [review queue]" if _mq == 3
drop _mq magchg dimchg nopub

append using "`c1'"

********************************************************************************
* C. Attach the photograph and the locators
********************************************************************************

preserve
	import delimited "${imgbridge}/photo_id_bridge.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	keep id filename photo_path obs_type pull_province pull_municipal_city ///
	     pull_item pull_nsu_unit vendor_id market_name store_stall_name
	tempfile br
	save "`br'"
restore

merge m:1 id using "`br'", keep(master match) gen(_mb)
gen byte has_photo = (_mb == 3)
drop _mb

label var has_photo "A usable photograph exists for this weighing"

********************************************************************************
* D. Report
********************************************************************************

di as txt _n "{hline 78}"
di as txt "                             recorded   this run"
di as txt "C1 4A flat-group weighings   `BASE_C1_FLAT'        `n_flat'"
di as txt "C1 4B dual-ticked            `BASE_C1_DUAL'        `n_dual'"
di as txt "C1 4B liquid as a mass       `BASE_C1_LIQMASS'        `n_liq'"
di as txt "C1 4B solid as Litres        `BASE_C1_SOLVOL'         `n_sol'"
di as txt "C2 judgement applied         `BASE_C2_MUST'       `n_c2'"
di as txt "{hline 78}"
di as txt "flat groups: `n_groups'   |   C2 rows also in the review queue: `n_queue'"

local drift = 0
foreach p in "`n_flat' `BASE_C1_FLAT'" "`n_dual' `BASE_C1_DUAL'" ///
             "`n_liq' `BASE_C1_LIQMASS'" "`n_sol' `BASE_C1_SOLVOL'" ///
             "`n_c2' `BASE_C2_MUST'" {
	local a : word 1 of `p'
	local b : word 2 of `p'
	if `a' != `b' local drift = 1
}
if `drift' {
	di as error _n "COUNTS HAVE MOVED from the recorded baseline."
	di as error "Re-derive from 90_diagnostics/photo_check_scope.do and say so explicitly"
	di as error "rather than substituting the new number."
}

* ---- THE NUMBER THIS FILE EXISTS TO PRODUCE ------------------------------------
* How much of each must tier can actually be checked. A target with no photograph is
* not a target.
di as res _n "{hline 78}"
di as res "PHOTOGRAPH COVERAGE OF THE MUST TIERS"
di as res "{hline 78}"
foreach c in 1 2 {
	qui count if check == `c'
	local t = r(N)
	qui count if check == `c' & has_photo
	local h = r(N)
	di as txt "  check `c':  `h' of `t' target rows have a photograph"
}
qui levelsof id if has_photo, local(ids)
local n_unique : word count `ids'
di as txt _n "  distinct weighings to photograph, across both checks: `n_unique'"

di as res _n "  CHECK 2 MUST TIER BY PRIORITY"
tab priority if check == 2 & has_photo

di as res _n "  CHECK 1 MUST TIER BY REASON"
tab reason if check == 1 & has_photo

********************************************************************************
* E. Export
********************************************************************************

order id check tier priority reason has_photo filename photo_path obs_type ///
      pull_province pull_municipal_city market_name store_stall_name vendor_id ///
      pull_item pull_nsu_unit rawtick raw_weight dim corrected_weight snap_rule ///
      flat_group nobs nven is_rep queue_flag queue_tier
gsort check priority -has_photo id

export delimited using "${imgtables}\photo_targets.csv", replace

qui count
di as res _n "02_photo_targets complete: " r(N) " target rows"
di as txt "targets: ${imgtables}\photo_targets.csv"
