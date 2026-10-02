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
* ---- WHICH NUMBER GOVERNS, IN ORDER ----------------------------------------------
* Four owner rulings, each narrowing the one before it. Taken together they say: use
* the most direct statement of the contents, and never take a number whose use would
* oblige an assumption that a better number avoids.
*
*   1. A printed package quantity beats a scale display (2026-09-20, widened
*      2026-09-28). A scale weighs the packaging too; a label states net contents.
*
*   2. On a label printing BOTH a mass and a volume, the grams win (2026-10-02).
*      Both describe the same contents, and the grams need no density.
*
*   3. On a label printing a volume ALONE, beside a legible scale reading, the
*      weighed grams win -- but only where the packaging is visibly light, which in
*      practice means ice cream bars (2026-10-02). See A25 in the body: applied
*      generally this would adopt a liquor bottle's glass as its contents.
*
*   4. No reading may be negative or zero (2026-10-02). A non-positive value is
*      withdrawn, not corrected; see the block above the precedence cascade.
*
* Ruling 1 is applied on model rows as well as human ones. The rest of the mL rule --
* the `reading_source == "package"' branch -- stays confined to human-read rows,
* because it overrides a field record and a model reading is not strong enough to do
* that. Model rows that saw a package label carry `pkg_seen' so the reach is visible.
*
* Where a printed volume survives all of this and must still become a mass, the factor
* is ${DENS_ICECREAM} and it is defined once in 00_shared/00_globals.do. It is NOT
* applied in this file; this file resolves what the photograph says.
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

* ---- A READING MUST BE STRICTLY POSITIVE ----------------------------------------
* A mass and a volume are both non-negative quantities; nothing a scale or a label can
* legitimately say makes one negative, and a weighing of exactly zero is the absence of
* a reading rather than a reading of nothing. Owner ruling, 2026-10-02.
*
* WHAT IS ACTUALLY IN THE DATA. Eight non-positive readings, all from the C1 sweep: six
* negative (-0.040, -0.045, -0.050, -0.160, -0.175, -0.990 kg) and two exactly zero.
* The negatives are a leading minus that is almost certainly a ghost segment -- an
* unlit bar on a display that glows dark red -- and not a scale left untared.
*
* THEY ARE SET MISSING, NOT MADE ABSOLUTE, and the distinction is the whole point.
* Five of the six match the field record exactly once the sign is dropped, which looks
* like permission to take the magnitude. It is not: whether a reading matches the field
* record is the question Check 2 asks, so using that agreement to repair the reading
* would decide the check with the check's own answer. A reading whose sign its reader
* got wrong is a reading that cannot be trusted to the digit, so it is withdrawn and
* the row falls through to the next reader in the precedence below, or becomes unread.
*
* Nothing is lost: the withdrawn value stays in v_* and the count prints every run.
gen byte nonpositive_withdrawn = 0
foreach s in hum hir son swp sc1 rsc hai {
	qui count if !missing(g_`s') & g_`s' <= 0
	if r(N) > 0 {
		di as txt "  withdrew `r(N)' non-positive reading(s) from g_`s'"
		replace nonpositive_withdrawn = 1 if !missing(g_`s') & g_`s' <= 0
		replace g_`s' = . if g_`s' <= 0
	}
}
label var nonpositive_withdrawn "A reader returned a non-positive value; it was withdrawn"

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

* THE SCALE DISPLAY, KEPT SEPARATELY. At this exact point photo_g is the resolved
* reading of the scale and nothing else: the label rules below have not run. A25 needs
* to compare a label against a display after the label has already overwritten
* photo_g, so the display is captured here rather than reconstructed later -- the same
* reason the build keeps w_block instead of letting a diagnostic re-derive it.
gen double scale_g = photo_g
label var scale_g "The resolved SCALE reading in grams, before any label rule"

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

* MASS FIRST, THEN VOLUME. A label reading "Net Content: 64ml (56g)" states the same
* contents twice, and the grams are the better of the two: they are the quantity this
* project publishes, and taking them costs no density assumption. Taking the volume
* instead would oblige a conversion whose factor is not measured per pack.
*
* IT USED TO RUN THE OTHER WAY -- volume first, "the mL rule wants the volume". That
* ordering was set when the only question was volume-against-scale; it was never a
* judgement that a printed volume beats a printed mass on the SAME label. Owner
* ruling, 2026-10-02: where a package states both, the grams always win.
*
* It moves seven rows, every one of them ice cream, and it removes the only rows where
* a printed mass sat in the data unused beside the volume that displaced it. Those
* seven are what DENS_ICECREAM is calibrated on; see 00_globals.do and A25.
gen double pkg_qty  = .
gen str4   pkg_unit = ""

* number immediately followed by a mass unit
replace pkg_qty  = real(regexs(1)) ///
	if regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(g|gram[a-z]*)\b")
replace pkg_unit = "g" if !missing(pkg_qty)

* kilograms -> g, only where no gram figure was found
replace pkg_qty  = real(regexs(1))*1000 ///
	if missing(pkg_qty) & regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(kg|kilo[a-z]*)\b")
replace pkg_unit = "g" if pkg_unit == "" & !missing(pkg_qty)

* volume, only where no mass was found at all
replace pkg_qty  = real(regexs(1)) ///
	if missing(pkg_qty) & regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(ml|millilit[a-z]*)")
replace pkg_unit = "mL" if pkg_unit == "" & !missing(pkg_qty)

* litres -> mL, only where no mL figure was found
replace pkg_qty  = real(regexs(1))*1000 ///
	if missing(pkg_qty) & regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(lit[a-z]*|l)\b")
replace pkg_unit = "mL" if pkg_unit == "" & !missing(pkg_qty)

* Does the label ALSO state the dimension it did not win on? Kept because it is the
* only in-data observation of a pack's own density, and because the count is the
* tripwire on the ordering above: if the mass-first branch ever stops matching, this
* goes to zero and the assert below halts the build.
gen byte pkg_states_both = ///
	(regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(g|gram[a-z]*)\b") | ///
	 regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(kg|kilo[a-z]*)\b")) & ///
	(regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(ml|millilit[a-z]*)") | ///
	 regexm(lower(pkg_text), "([0-9]+\.?[0-9]*) *(lit[a-z]*|l)\b"))
label var pkg_states_both "The printed label gave BOTH a mass and a volume"

* A label stating both must now resolve to grams. This is the ordering, asserted.
qui count if pkg_states_both & pkg_unit != "g"
assert r(N) == 0

gen byte has_pkg_qty = !missing(pkg_qty)

* THE LABEL RULE. A legible printed quantity governs wherever one exists -- over a
* scale display and over the field record -- whether it states a VOLUME or a MASS.
*
* IT USED TO BE VOLUME-ONLY, and the reason for widening it is a measurement rather
* than a preference. A scale reading is whatever sat on the pan, which for a packaged
* good is GROSS: contents plus cup, ice, stick or wrapper. A printed label states NET
* contents. So where both are legible the label is the better measure of the thing the
* project publishes -- what a vendor's unit contains -- and the scale reading carries a
* packaging component that nothing in the data can subtract.
*
* MEASURED, on the 23 rows carrying both a printed mass and a scale reading: the scale
* exceeds the label on 18 of 20 inspected, by a median of about 5% and up to 38%. That
* systematic excess IS the packaging, and its sign is the prediction the rule makes.
* The gap is item-dependent and not always small: a drink photographed beside its cup
* read 355 mL printed against 0.700 kg weighed, because the cup and the ice weigh as
* much again as the drink.
*
* TWO ROWS RUN THE OTHER WAY (ratios 0.74 and 0.77 -- the scale LIGHTER than the
* label). A part-pack sold loose, a misread label, or a label belonging to something
* else in frame would each do that. They are not explained here and are worth a look.
*
* Owner rulings: printed volume governs, 2026-09-21; widened to any legible printed
* quantity, 2026-09-28.
gen byte ml_rule_applied = 0
foreach U in mL g {
	replace photo_g    = pkg_qty  if has_pkg_qty & pkg_unit == "`U'"
	replace photo_unit = "`U'"    if has_pkg_qty & pkg_unit == "`U'"
	replace ml_rule_applied = 1   if has_pkg_qty & pkg_unit == "`U'"
	replace photo_src = photo_src + " + `U' label" ///
		if has_pkg_qty & pkg_unit == "`U'" & photo_src != "" & ///
		   strpos(photo_src, "label") == 0
	replace photo_src = "package label (`U')" ///
		if has_pkg_qty & pkg_unit == "`U'" & photo_src == ""
}

* ---- A25: A WEIGHED GRAM BEATS A PRINTED MILLILITRE, ON LIGHT PACKAGING ONLY -----
* The label rule above prefers a printed quantity to a scale reading, because a scale
* weighs the packaging too. Where the label prints a MASS that reasoning is complete
* and this block does not fire.
*
* Where the label prints only a VOLUME it is incomplete, because taking the volume
* does not end the problem -- it defers it to a density conversion, and that
* conversion has an error of its own. On a wrapped ice cream bar the choice is
* between two errors with very different sizes:
*
*     take the printed mL  ->  multiply by an ASSUMED 0.9 g/mL, when the packs that
*                              state both run 0.47 to 0.94 (00_globals.do)
*     take the weighed g   ->  carry the mass of a plastic wrapper and a wooden stick
*
* The wrapper is grams at most. The density assumption is tens of percent. So the
* scale wins. Owner ruling, 2026-10-02.
*
* IT IS CONFINED TO ICE CREAM, AND THE DATA SAYS WHY. Seven rows have an mL-only label
* beside a scale reading. Four are ice cream, where the two figures agree to within 2%
* on three of them. One is liquor: 375 mL printed, 870 g weighed -- a ratio of 2.3,
* which is the glass bottle. Two are restaurant drinks at 355 mL printed against 700
* and 760 g recorded, where the cup and the ice weigh as much as the drink.
*
* Applied generally this rule would therefore adopt a bottle's tare as its contents on
* the very rows the label rule exists to protect. The discriminator the owner named is
* that the packaging is VISIBLY LIGHT -- plastic wrap and a stick -- which is a
* property of the photograph, not a column. `${ICECREAM_ITEM}' is the available proxy,
* and it is a gate on item, not a measurement of wrapper mass. Widening it to another
* item needs the same two things this had: a reason the packaging is negligible, and a
* look at the rows that would move.
*
* THE ITEM GATE ALONE IS TOO WIDE, and the owner's own adjudications caught it. Of the
* four ice cream rows it selects, one prints 800 mL and one prints 1.5 L. Those are
* TUBS. A moulded tub and lid are not a plastic wrapper, the premise fails, and on the
* 1.5 L row the owner had already approved the printed 1500 mL against a weighed 1048 g
* -- a ratio of 0.70, which is the product's own aeration and not an error to repair.
*
* So the carve-out is additionally capped at `${ICECREAM_SINGLE_ML}' mL of printed
* volume, which is what "single-serve, in a wrapper" means in a column. It fires on one
* row. That is a small return for a rule this long, and the length is the point: the
* rows it must NOT fire on are the expensive ones.
capture confirm string variable pull_item
if _rc {
	di as err "pull_item is not a string -- A25 cannot match on it; decode it first"
	exit 459
}

gen byte scale_beats_volume = has_pkg_qty & pkg_unit == "mL" & ///
	!missing(scale_g) & scale_g > 0 & ///
	strpos(lower(pull_item), lower("${ICECREAM_ITEM}")) > 0 & ///
	pkg_qty <= ${ICECREAM_SINGLE_ML}

qui count if scale_beats_volume
di as txt "  A25 scale-beats-volume (light packaging) ......... " r(N)

replace photo_g         = scale_g if scale_beats_volume
replace photo_unit      = "g"     if scale_beats_volume
replace photo_src       = photo_src + " + scale over mL (A25)" if scale_beats_volume
replace ml_rule_applied = 0       if scale_beats_volume
label var scale_beats_volume "A25: mL-only label overridden by the weighed grams"

* The carve-out must never touch a row whose label stated a mass -- that row is
* already in grams and A25 has nothing to add. Asserted rather than assumed.
assert pkg_states_both == 0 if scale_beats_volume

gen byte has_reading = !missing(photo_g)
gen byte from_human  = inlist(photo_src, "human", "human (mL rule)")
gen byte evidence_is_label = (strpos(photo_src, "package label") > 0) | ml_rule_applied

* A label was SEEN but no quantity could be parsed from it, so a person must look. It
* no longer covers labels the rule can read, because the rule now reads them.
gen byte mL_rule_pending = pkg_seen & !has_pkg_qty

label var pkg_qty      "Quantity parsed from the printed package label"
label var pkg_unit     "Its dimension: mL where a volume was printed, else g"
label var has_pkg_qty  "A usable quantity was printed on the packaging"
* THE NAME IS NOW A MISNOMER and is kept deliberately. It flags the LABEL rule, which
* since 2026-09-28 covers a printed mass as well as a printed volume. Renaming it would
* change a column of photo_readings_master.csv while 109 overrides and 94 holds are
* sitting in front of the owner for approval, keyed off that file. Rename it once those
* are resolved, not before -- a column that disappears under a pending decision is worse
* than a column that is badly named.
label var ml_rule_applied "A printed label quantity governed this row (volume OR mass)"

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

* ---- the 2026-10-02 rulings, counted every run -----------------------------------
qui count if nonpositive_withdrawn
di as txt "  non-positive readings withdrawn .................. " r(N)
qui count if pkg_states_both
di as txt "  labels printing BOTH mass and volume (grams win) . " r(N)
qui count if scale_beats_volume
di as txt "  A25 weighed grams taken over a printed mL ........ " r(N)
qui count if has_pkg_qty & pkg_unit == "mL" & ///
	strpos(lower(pull_item), lower("${ICECREAM_ITEM}")) > 0 & !scale_beats_volume
di as txt "  ice cream rows still owed a density conversion ... " r(N)
di as txt "    (at ${DENS_ICECREAM} g per mL -- 00_globals.do, A23, A25)"

di as txt _n "  resolved reading by source:"
tab photo_src if has_reading

di as txt _n "  by the rule that set the published value:"
tab pub_rule has_reading, row

order id image_code filename photo_g photo_unit photo_src from_human has_reading ///
      evidence_is_label ml_rule_applied pkg_text pkg_qty pkg_unit has_pkg_qty ///
      pkg_states_both scale_g scale_beats_volume nonpositive_withdrawn ///
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
