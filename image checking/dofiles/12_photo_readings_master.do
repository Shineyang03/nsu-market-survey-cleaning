********************************************************************************
* 12_photo_readings_master.do -- every photograph reading, in one dataset
*
* THE SINGLE PLACE TO LOOK. Readings have been made in four passes, by three kinds of
* reader, at two presentations. Leaving them in four files invites a later analysis to
* pick one and quietly answer a different question than it thinks. This is one row per
* photographed weighing, keyed on `id', carrying every reading made of it and a single
* RESOLVED value with its provenance beside it.
*
*   pass          reader            presentation      what it covers
*   calib_v1      haiku, sonnet     4-up, 700px       148 stratified, both checks
*   restest       sonnet            1-up, 1500px      46, the resolution A/B
*   human_v1      a person          embedded, 820px   40, ground truth
*   sweep_c2      sonnet            4-up, 700px       the Check 2 must tier
*
* ---- THE PRECEDENCE RULE, DEFINED ONCE -----------------------------------------
* Where a photograph has been read more than once, the resolved reading is taken from
* the best available evidence:
*
*   1  human          a person read it blind. Scores by definition; it IS the yardstick.
*   2  sonnet hi-res  100% against the human on 24 readings.
*   3  sonnet tiled   97% against the human on 33 readings.
*   4  (sweep)        the same instrument and presentation as sonnet tiled.
*
* HAIKU IS NEVER THE RESOLVED READING. It scores 55.6% against the human -- barely
* better than a coin flip on a four-way digit -- and is retained as a column only so
* the disagreement that established this stays visible in the data rather than only in
* a commit message. It is not evidence.
*
* ---- THE mL RULE ---------------------------------------------------------------
* Where a printed volume and a scale reading are both legible, the printed volume
* governs (project owner, 2026-09-20). Applied ONLY on human-read rows: it overrides a
* field record, and a model reading is not strong enough to do that. Model rows that
* saw a package label carry `pkg_seen' so the rule's reach is visible.
*
* ---- BLINDING -----------------------------------------------------------------
* Nothing here reaches a reader. Every reading in this file was made against a tile
* carrying a sequence number and nothing else -- no id, no typed weight, no published
* value, no item name. This is the first place readings and published values meet, and
* it is downstream of all of them.
*
* INPUT   ${imgqc}\readings_calib_v1.csv, readings_restest.csv,
*         human_verdicts_v1.csv, readings_sweep_c2.csv (if present)
*         ${imgbridge}\photo_id_bridge.csv
* OUTPUT  ${imgqc}\photo_readings_master.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 12_photo_readings_master.do
********************************************************************************

clear all
do "00_photo_globals.do"

local KGSPLIT 30

capture program drop norm_g
program define norm_g
	* Display value -> grams. Below KGSPLIT the scale was in kilogram mode, which is
	* what the photographs show (a cabbage reads 0.800, a chicken 1085). KGSPLIT
	* matches KGMAX in 03a_block_reading.do so this and the rule it checks cannot
	* disagree for an unrelated reason.
	args newvar src split
	gen double `newvar' = cond(`src' < `split', `src'*1000, `src') if !missing(`src')
end

* ---- a reusable loader for one parse_readings.py output -------------------------
capture program drop load_pass
program define load_pass
	syntax , FILE(string) PASS(string) SUFFIX(string) [MODEL(string)]
	capture confirm file "`file'"
	if _rc {
		di as txt "  (no `pass' readings at `file' -- skipped)"
		clear
		set obs 0
		gen long id = .
		exit
	}
	import delimited "`file'", clear varnames(1) delimiter(",") ///
		encoding("utf-8") stringcols(_all)
	destring id, replace
	if "`model'" != "" keep if strpos(reader, "`model'") > 0
	destring display_text, gen(v_`suffix') force
	gen str16 type_`suffix' = photo_type
	gen str16 leg_`suffix'  = display_legible
	gen str80 pkg_`suffix'  = package_text
	keep id v_`suffix' type_`suffix' leg_`suffix' pkg_`suffix'
	duplicates drop id, force
end

********************************************************************************
* A. Every pass
********************************************************************************

di as txt _n "loading passes:"

load_pass, file("${imgqc}/readings_calib_v1.csv") pass("calib sonnet") suffix("son") model("sonnet")
tempfile p_son
save "`p_son'"
qui count
di as txt "  calib_v1 sonnet .... " r(N)

load_pass, file("${imgqc}/readings_calib_v1.csv") pass("calib haiku") suffix("hai") model("haiku")
tempfile p_hai
save "`p_hai'"
qui count
di as txt "  calib_v1 haiku ..... " r(N)

load_pass, file("${imgqc}/readings_restest.csv") pass("restest") suffix("hir")
tempfile p_hir
save "`p_hir'"
qui count
di as txt "  restest hi-res ..... " r(N)

load_pass, file("${imgqc}/readings_sweep_c2.csv") pass("sweep_c2") suffix("swp")
tempfile p_swp
save "`p_swp'"
qui count
di as txt "  sweep_c2 ........... " r(N)

* human -- a different schema, from the workbook rather than a reader
capture confirm file "${imgqc}/human_verdicts_v1.csv"
if _rc == 0 {
	import delimited "${imgqc}/human_verdicts_v1.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id h_display_val h_glare_flag h_scale_present, replace
	keep id h_display_val h_display_raw reading_source h_glare_flag h_notes
	rename (h_display_val h_display_raw) (v_hum raw_hum)
	duplicates drop id, force
}
else {
	clear
	set obs 0
	gen long id = .
}
tempfile p_hum
save "`p_hum'"
qui count
di as txt "  human_v1 ........... " r(N)

********************************************************************************
* B. The spine: every photographed weighing that anyone has read
********************************************************************************

use "`p_son'", clear
foreach f in p_hai p_hir p_swp p_hum {
	merge 1:1 id using "``f''", nogen
}

merge 1:1 id using "${btemp}/nsu_weighings_cpi.dta", ///
	keepusing(pull_item harmonized_nsu_unit item_nsu_hetero_type ///
	          corrected_weight corrected_unit snap_rule) keep(master match) nogen
decode corrected_unit, gen(pub_unit)
decode snap_rule, gen(pub_rule)
drop corrected_unit snap_rule

merge 1:1 id using "${btemp}/prelim_nsu_data.dta", ///
	keepusing(weight unit) keep(master match) nogen
decode unit, gen(raw_tick)
rename weight raw_weight
drop unit

preserve
	import delimited "${imgbridge}/photo_id_bridge.csv", clear varnames(1) ///
		delimiter(",") encoding("utf-8") stringcols(_all)
	destring id, replace
	gen str32 image_code = subinstr(filename, ".jpg", "", .)
	keep id image_code filename pull_province pull_municipal_city ///
	     market_name store_stall_name vendor_id
	tempfile br
	save "`br'"
restore
merge 1:1 id using "`br'", keep(master match) nogen

********************************************************************************
* C. Resolve
********************************************************************************

norm_g g_hum v_hum `KGSPLIT'
norm_g g_hir v_hir `KGSPLIT'
norm_g g_son v_son `KGSPLIT'
norm_g g_swp v_swp `KGSPLIT'
norm_g g_hai v_hai `KGSPLIT'

gen double photo_g    = .
gen str16  photo_src  = ""
gen str4   photo_unit = ""

* precedence, best evidence last-applied-wins is avoided: each branch guards on missing
replace photo_g = g_swp  if missing(photo_g) & !missing(g_swp)
replace photo_src = "sonnet sweep"  if photo_src == "" & !missing(g_swp)
replace photo_g = g_son  if missing(photo_g) & !missing(g_son)
replace photo_src = "sonnet tiled"  if photo_src == "" & !missing(g_son)
replace photo_g = g_hir  if !missing(g_hir)
replace photo_src = "sonnet hi-res" if !missing(g_hir)
replace photo_g = g_hum  if !missing(g_hum)
replace photo_src = "human"         if !missing(g_hum)

replace photo_unit = "g" if !missing(photo_g)

* THE mL RULE -- human rows only.
replace photo_g    = v_hum  if reading_source == "package" & !missing(v_hum)
replace photo_unit = "mL"   if reading_source == "package" & !missing(v_hum)
replace photo_src  = "human (mL rule)" if reading_source == "package" & !missing(v_hum)

* A model row that saw a package label: the rule is NOT applied, and the flag says so.
gen byte pkg_seen = 0
foreach s in son swp hir {
	replace pkg_seen = 1 if !missing(pkg_`s') & trim(pkg_`s') != "" & pkg_`s' != "NA"
}
gen byte mL_rule_pending = pkg_seen & photo_src != "human (mL rule)" & photo_src != "human"

gen byte has_reading = !missing(photo_g)
gen byte from_human  = inlist(photo_src, "human", "human (mL rule)")

label var photo_g    "Resolved reading from the photograph, grams (or mL under the mL rule)"
label var photo_src  "Which reader the resolved value came from"
label var from_human "1 = a person read this photograph"
label var mL_rule_pending "A package label is visible; the mL rule needs a human"

********************************************************************************
* D. Report
********************************************************************************

qui count
local n = r(N)
di as res _n "{hline 78}"
di as res "PHOTO READINGS MASTER"
di as res "{hline 78}"
di as txt "  photographed weighings with any reading attempt ... `n'"
qui count if has_reading
di as txt "  with a resolved display reading .................. " r(N)
qui count if from_human
di as txt "  resolved from a human ............................ " r(N)
qui count if mL_rule_pending
di as txt "  package label seen, mL rule pending a human ...... " r(N)

di as txt _n "  resolved reading by source:"
tab photo_src if has_reading

di as txt _n "  by the rule that set the published value:"
tab pub_rule has_reading, row

order id image_code filename photo_g photo_unit photo_src from_human has_reading ///
      mL_rule_pending pkg_seen raw_tick raw_weight corrected_weight pub_unit pub_rule ///
      pull_item harmonized_nsu_unit pull_province pull_municipal_city ///
      market_name store_stall_name vendor_id ///
      v_hum raw_hum reading_source h_glare_flag h_notes ///
      v_hir v_son v_swp v_hai g_hum g_hir g_son g_swp g_hai ///
      type_son type_hir type_swp type_hai leg_son leg_hir leg_swp leg_hai ///
      pkg_son pkg_hir pkg_swp pkg_hai
gsort id
export delimited using "${imgqc}\photo_readings_master.csv", replace

di as res _n "12_photo_readings_master complete: `n' rows"
di as txt "  ${imgqc}\photo_readings_master.csv"
