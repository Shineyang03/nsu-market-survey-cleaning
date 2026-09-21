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

* The rescue pass. Three photographs failed a streamed read ONCE during sheet
* generation, were painted as UNREADABLE tiles and recorded as such in the manifest,
* and were correctly reported unread. They were never corrupt -- see the retry now in
* cached_photo -- and were re-rendered and read on their own sheet. Loaded as its own
* pass so the recovery stays visible rather than being quietly folded into the sweep.
* The Check 1 sweep. Same instrument, same presentation, different population: its
* tier is flat groups, dual-ticked cases, liquids ticked as a mass and solids ticked as
* Litres, and 93% of those photographs show no scale at all against 83% WITH one in
* Check 2's. Its value is overwhelmingly in package_text rather than display_text.
load_pass, file("${imgqc}/readings_sweep_c1.csv") pass("sweep_c1") suffix("sc1")
tempfile p_sc1
save "`p_sc1'"
qui count
di as txt "  sweep_c1 ........... " r(N)

load_pass, file("${imgqc}/readings_sweep_c2_rescue.csv") pass("sweep rescue") suffix("rsc")
tempfile p_rsc
save "`p_rsc'"
qui count
di as txt "  sweep_c2 rescue .... " r(N)

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
foreach f in p_hai p_hir p_swp p_sc1 p_rsc p_hum {
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
norm_g g_sc1 v_sc1 `KGSPLIT'
norm_g g_rsc v_rsc `KGSPLIT'
norm_g g_hai v_hai `KGSPLIT'

gen double photo_g    = .
gen str16  photo_src  = ""
gen str4   photo_unit = ""

* precedence, best evidence last-applied-wins is avoided: each branch guards on missing
replace photo_g = g_sc1  if missing(photo_g) & !missing(g_sc1)
replace photo_src = "sonnet C1 sweep" if photo_src == "" & !missing(g_sc1)
replace photo_g = g_rsc  if missing(photo_g) & !missing(g_rsc)
replace photo_src = "rescue read"   if photo_src == "" & !missing(g_rsc)
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
foreach s in son swp sc1 rsc hir {
	replace pkg_seen = 1 if !missing(pkg_`s') & trim(pkg_`s') != "" & pkg_`s' != "NA"
}
* mL_rule_pending is defined below, once has_pkg_qty exists.

* ---- A PACKAGE QUANTITY IS A READING TOO ----------------------------------------
* `has_reading' used to mean "a scale display was read", which silently equated "no
* display" with "no evidence". Under the mL rule a printed volume is evidence -- it is
* the PREFERRED evidence where both exist -- so a photograph of a label with a legible
* quantity is a read photograph, not an unread one.
*
* The cost of the old definition was not cosmetic: it reported Check 2 coverage as 75%
* when 89% of the tier has evidence, and it hid 333 usable package labels behind a
* count of 616 "no reading" rows.
*
* Parsed from the FIRST trusted reader that recorded a label, in the same precedence as
* the display reading. Haiku is excluded here for the same reason it is excluded there.
gen str80 pkg_text = ""
foreach s in rsc hir son swp sc1 {
	replace pkg_text = pkg_`s' if pkg_text == "" & !missing(pkg_`s') & trim(pkg_`s') != ""
}

* Volume first, then mass. A label reading "Net Content: 64ml (60g)" is a volume that
* also states its mass, and the mL rule wants the volume.
gen double pkg_qty  = .
gen str4   pkg_unit = ""

* number immediately followed by a volume unit
gen str80 _m = regexs(0) if regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(ml|millilit[a-z]*)")
replace pkg_qty  = real(regexs(1)) if regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(ml|millilit[a-z]*)")
replace pkg_unit = "mL" if !missing(pkg_qty)

* litres -> mL, only where no mL figure was found
replace pkg_qty  = real(regexs(1))*1000 ///
	if missing(pkg_qty) & regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(lit[a-z]*|l)\b")
replace pkg_unit = "mL" if pkg_unit == "" & !missing(pkg_qty)

* mass, only where no volume was found at all
replace pkg_qty  = real(regexs(1)) ///
	if missing(pkg_qty) & regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(g|gram[a-z]*)\b")
replace pkg_unit = "g" if pkg_unit == "" & !missing(pkg_qty)
replace pkg_qty  = real(regexs(1))*1000 ///
	if missing(pkg_qty) & regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(kg|kilo[a-z]*)\b")
replace pkg_unit = "g" if pkg_unit == "" & !missing(pkg_qty)
drop _m

gen byte has_pkg_qty = !missing(pkg_qty)

* THE mL RULE, stated as one condition. A printed volume governs where one exists --
* over a scale display and over the field record. Applied from a MODEL reading here,
* which is a change: it was previously human-only. The owner ruled on 2026-09-21 that
* the printed volume governs whenever it is available, without that qualification.
gen byte ml_rule_applied = 0
replace photo_g    = pkg_qty  if has_pkg_qty & pkg_unit == "mL"
replace photo_unit = "mL"     if has_pkg_qty & pkg_unit == "mL"
replace ml_rule_applied = 1   if has_pkg_qty & pkg_unit == "mL"
replace photo_src = photo_src + " + mL label" if ml_rule_applied & photo_src != ""
replace photo_src = "package label (mL)"      if ml_rule_applied & photo_src == ""

* a printed MASS, only where nothing else gave a value
replace photo_g    = pkg_qty if missing(photo_g) & has_pkg_qty & pkg_unit == "g"
replace photo_unit = "g"     if missing(photo_unit) & has_pkg_qty & pkg_unit == "g"
replace photo_src  = "package label (g)" if photo_src == "" & !missing(photo_g)

gen byte has_reading = !missing(photo_g)
gen byte from_human  = inlist(photo_src, "human", "human (mL rule)")
gen byte evidence_is_label = (strpos(photo_src, "package label") > 0) | ml_rule_applied

* A label was SEEN but no quantity could be parsed from it, so a person must look. It
* no longer covers labels the rule can read, because the rule now reads them.
gen byte mL_rule_pending = pkg_seen & !has_pkg_qty

label var pkg_qty      "Quantity parsed from the printed package label"
label var pkg_unit     "Its dimension: mL where a volume was printed, else g"
label var has_pkg_qty  "A usable quantity was printed on the packaging"
label var ml_rule_applied "The printed volume governed this row"

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
      evidence_is_label ml_rule_applied pkg_text pkg_qty pkg_unit has_pkg_qty ///
      mL_rule_pending pkg_seen raw_tick raw_weight corrected_weight pub_unit pub_rule ///
      pull_item harmonized_nsu_unit pull_province pull_municipal_city ///
      market_name store_stall_name vendor_id ///
      v_hum raw_hum reading_source h_glare_flag h_notes ///
      v_hir v_son v_swp v_sc1 v_rsc v_hai ///
      g_hum g_hir g_son g_swp g_sc1 g_rsc g_hai ///
      type_son type_hir type_swp type_sc1 type_rsc type_hai ///
      leg_son leg_hir leg_swp leg_sc1 leg_rsc leg_hai ///
      pkg_son pkg_hir pkg_swp pkg_sc1 pkg_rsc pkg_hai
gsort id
export delimited using "${imgqc}\photo_readings_master.csv", replace

di as res _n "12_photo_readings_master complete: `n' rows"
di as txt "  ${imgqc}\photo_readings_master.csv"
