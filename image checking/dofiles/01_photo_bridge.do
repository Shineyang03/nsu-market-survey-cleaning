********************************************************************************
* 01_photo_bridge.do -- link every field photograph to the weighing it depicts
*
* THE FIRST STEP OF THE PHOTOGRAPH CHECKS, and the only place the join is made.
* Everything downstream -- target lists, contact sheets, the verdict ledger, the
* reconciliation -- reads the one file this writes and never re-derives the join.
*
* WHAT THE JOIN IS. The photo crosswalk keys a JPEG filename on a submission KEY and
* a photo slot (item_photo_ss / _ms / _ls / _conv_nsu / _mun_median / _prov_median /
* _mp25 / _mp50 / _mp75). The raw market survey keys a weighing on `key' and
* `obs_type'. The slot names and the obs_type values are the same nine categories
* under two spellings, so:
*
*     crosswalk KEY + photo_variable  ==  raw key + obs_type  ->  one weighing
*
* and `key' + `obs_type' is unique in the raw file, which the isid below proves.
*
* WHY THE ID COMES FROM THE REGISTRY AND IS NOT RECOMPUTED. The pipeline's durable
* `id' is assigned by 00_shared/00a_weighing_ids.do against a content key, and that
* file owns it: "reads the registry, never writes it" is the rule for every later
* step. This one rebuilds the same content key ONLY to look the id up, merges
* keep(1 3), and halts if any raw row fails to find one. It never mints an id and
* never writes the registry. If a row here has no id, the fix is upstream in 00a, not
* a new number invented in a diagnostic.
*
* The key is copied from 00a deliberately and must stay identical to it: raw-cased,
* commas stripped, six components, obs_type as the STRING rather than the encoded
* value. 00a's header explains why each of those matters; the short version is that
* every component is raw input text, so nothing this project computes can move an id.
*
* NEITHER prelim_nsu_data.dta NOR nsu_weighings_cpi.dta CARRIES `key', which is why
* the join has to start from the raw survey rather than from an intermediate. That is
* also why this file exists as a build step rather than as a line inside a later one.
*
* RAW WEIGHT AND UNIT ARE CARRIED, PUBLISHED ONES ARE NOT. Check 1 must read the raw
* tick -- scoring it against corrected_unit compares a decision with itself. The
* published columns are joined later, in the reconciliation, where that comparison is
* the point. A consumer of this file that wants corrected_weight should merge
* nsu_weighings_cpi.dta on id.
*
* NOTE FOR THE CONTACT SHEETS. This file carries the typed weight so a reviewer can
* find a row in the field. The sheets built for blind reading must NOT print it --
* that is the sheet builder's job, and the reason the blind split is enforced there
* rather than by withholding the column here.
*
* INPUT   ${data}                             raw market survey
*         ${tables}\weighing_id_registry.csv  the durable id registry (read only)
*         ${photocw}                          the photo crosswalk workbook
* OUTPUT  ${imgbridge}\photo_id_bridge.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 01_photo_bridge.do
********************************************************************************

clear all
do "00_photo_globals.do"

* ---- RECORDED BASELINE ---------------------------------------------------------
* Measured 2026-09-19 against the crosswalk as delivered. These are NOT pass/fail
* gates. docs and the handover brief both say the same thing about figures in this
* project: expect them to move, and treat a move as information. A changed count here
* means the survey was re-exported or the crosswalk was rebuilt, which is a real event
* a reader needs told about -- not a reason a diagnostic should refuse to run.
* Structural violations below DO halt, because those mean the join itself is wrong.
local BASE_CW      11480   // crosswalk rows
local BASE_MATCH   11459   // crosswalk rows matching a raw weighing
local BASE_NOPHOTO    36   // raw weighings with no photo slot (unique_mun_price6/7)
local BASE_ORPHAN     21   // crosswalk rows matching no raw weighing
local BASE_USABLE  11449   // matched AND the file is present on disk

********************************************************************************
* A. The raw survey, and its durable id
********************************************************************************

confirm file "${data}"
use "${data}", clear

def_hetero

* The content key, character for character as 00a_weighing_ids.do builds it. Do not
* "tidy" this: lower-casing it, or swapping obs_type for its encoded value, orphans
* every id in the registry. 00a's header is the argument.
tempvar idkey
gen str244 `idkey' = subinstr(pull_province, ",", "", .) ///
    + "|" + subinstr(pull_municipal_city, ",", "", .) ///
    + "|" + subinstr(pull_item, ",", "", .) ///
    + "|" + subinstr(pull_nsu_unit, ",", "", .) ///
    + "|" + subinstr(vendor_id, ",", "", .) ///
    + "|" + subinstr(obs_type, ",", "", .)
isid `idkey'

* The registry, read exactly as 00a reads it. delimiter(",") is not optional -- the
* key holds five "|" characters against the header's zero commas, so auto-detection
* picks "|" and splits the key into six variables while reporting success.
preserve
	import delimited "${tables}\weighing_id_registry.csv", clear varnames(1) ///
		delimiter(",") stringcols(1) encoding("utf-8")
	isid idkey
	isid id
	tempfile registry
	save "`registry'"
restore

rename `idkey' idkey
merge m:1 idkey using "`registry'", keep(1 3) gen(_m_id)

qui count if _m_id == 1
if r(N) > 0 {
	di as error "`r(N)' raw weighing(s) have no id in the registry."
	di as error "This file does not mint ids. Run 00_shared\00a_weighing_ids.do from"
	di as error "dofiles/ first, and reconcile why the content key moved."
	exit 459
}
drop _m_id idkey

assert !missing(id)
isid id

* `unit' is a LABELLED NUMERIC. Exported as-is it writes the code, and a consumer
* reading the CSV in pandas gets the label string instead -- the two disagree, which
* is the documented trap behind a past bug where `unit == 1' matched nothing. Decode
* once, here, and let every downstream reader use the string.
decode unit, gen(raw_unit)
label var raw_unit "Unit tick as the field officer selected it (RAW, pre-repair)"

rename weight raw_weight
label var raw_weight "Weight as typed in the field (RAW, pre-repair)"

keep id key caseid obs_type pull_province pull_municipal_city pull_item ///
     pull_nsu_unit vendor_id market_name store_stall_name raw_weight raw_unit

tempfile weighings
save "`weighings'"

qui count
local n_raw = r(N)

********************************************************************************
* B. The photo crosswalk
********************************************************************************

import excel using "${photocw}", sheet("Photo Crosswalk") firstrow clear

* photo_exists arrives from Excel as a boolean, and Stata may read it as a string
* ("TRUE"/"FALSE") or as numeric depending on how the workbook was written. Normalise
* to a byte so the rest of the file can rely on it either way.
capture confirm string variable photo_exists
if _rc == 0 {
	gen byte _px = (upper(trim(photo_exists)) == "TRUE")
}
else {
	gen byte _px = (photo_exists != 0 & !missing(photo_exists))
}
drop photo_exists
rename _px photo_exists
label var photo_exists "Crosswalk's own claim that the JPEG is present on disk"

qui count
local n_cw = r(N)

* ---- THE SLOT-TO-OBS_TYPE MAP --------------------------------------------------
* The one place the two spellings are reconciled. Nine slots, nine obs_type values,
* one-to-one. The two obs_type values with NO slot -- unique_mun_price6 and
* unique_mun_price7 -- are extra municipal price points the instrument never
* photographed; they are why 36 raw weighings legitimately have no image, and they are
* reported below rather than treated as a failure.
gen str24 obs_type = ""
replace obs_type = "small_size"          if photo_variable == "item_photo_ss"
replace obs_type = "medium_size"         if photo_variable == "item_photo_ms"
replace obs_type = "large_size"          if photo_variable == "item_photo_ls"
replace obs_type = "conventional_nsu"    if photo_variable == "item_photo_conv_nsu"
replace obs_type = "municipality_median" if photo_variable == "item_photo_mun_median"
replace obs_type = "province_median"     if photo_variable == "item_photo_prov_median"
replace obs_type = "mp25_price"          if photo_variable == "item_photo_mp25"
replace obs_type = "mp50_price"          if photo_variable == "item_photo_mp50"
replace obs_type = "mp75_price"          if photo_variable == "item_photo_mp75"

* An unmapped slot is a new photo variable the instrument gained, and silently
* dropping it would quietly shrink the population every later check runs on.
qui count if obs_type == ""
if r(N) > 0 {
	di as error "`r(N)' crosswalk row(s) carry a photo_variable this file does not map."
	levelsof photo_variable if obs_type == "", clean
	exit 459
}

* One filename per row, and no filename reused. If a JPEG were listed twice the join
* would attach one image to two weighings and every later count would double-book it.
isid filename
rename KEY key

* RENAMED BEFORE THE MERGE, on purpose. caseid arrives from both sides, and Stata's
* merge does not suffix a clash -- it keeps the master's value silently, so a
* disagreement between the crosswalk's vintage of the survey and this one would be
* absorbed rather than shown. Renaming is what makes the comparison in C possible.
rename caseid caseid_cw

keep key obs_type caseid_cw filename photo_exists photo_variable
isid key obs_type

********************************************************************************
* C. The join
********************************************************************************

merge 1:1 key obs_type using "`weighings'", gen(_m)

* caseid reaches this file from both sides. They must agree -- if they do not, the
* crosswalk was built against a different vintage of the survey, and the join is not
* trustworthy even on the rows where key + obs_type happened to match. This halts.
qui count if _m == 3 & caseid != caseid_cw
if r(N) > 0 {
	di as error "`r(N)' matched row(s) disagree on caseid between the survey and the crosswalk."
	di as error "The crosswalk was built against a different vintage of the survey."
	list key obs_type caseid caseid_cw if _m == 3 & caseid != caseid_cw in 1/20, noobs
	exit 459
}
drop caseid_cw

qui count if _m == 3
local n_match = r(N)
qui count if _m == 1
local n_orphan = r(N)
qui count if _m == 2
local n_nophoto = r(N)

* ---- what has no photograph ----------------------------------------------------
di as txt _n "{hline 78}"
di as txt "Raw weighings with no photograph, by obs_type:"
tab obs_type if _m == 2

* ---- what has no weighing ------------------------------------------------------
di as txt _n "Crosswalk rows matching no raw weighing, by obs_type:"
tab obs_type if _m == 1

********************************************************************************
* D. Checks
********************************************************************************

* STRUCTURAL -- these halt. A failure means the join is wrong, not that the data moved.
assert !missing(id) if _m == 3
assert !missing(filename) if inlist(_m, 1, 3)

* DRIFT -- these report. A move is information; see the header on the baseline block.
local drift = 0
if `n_cw'      != `BASE_CW'      local drift = 1
if `n_match'   != `BASE_MATCH'   local drift = 1
if `n_nophoto' != `BASE_NOPHOTO' local drift = 1
if `n_orphan'  != `BASE_ORPHAN'  local drift = 1

di as txt _n "{hline 78}"
di as txt "                          recorded    this run"
di as txt "crosswalk rows            `BASE_CW'       `n_cw'"
di as txt "matched to a weighing     `BASE_MATCH'       `n_match'"
di as txt "weighings with no photo   `BASE_NOPHOTO'          `n_nophoto'"
di as txt "photos with no weighing   `BASE_ORPHAN'          `n_orphan'"
di as txt "{hline 78}"

if `drift' {
	di as error _n "COUNTS HAVE MOVED from the recorded baseline."
	di as error "That is not necessarily an error -- it means the survey was re-exported"
	di as error "or the crosswalk rebuilt. It IS a finding: say so explicitly rather than"
	di as error "substituting the new number. Update the baseline block once the move is"
	di as error "understood and recorded."
}

********************************************************************************
* E. Export
********************************************************************************

* Only rows that have BOTH a weighing and an image file are usable for a check. The
* other two groups are kept in the log above, not in the file -- a target list built
* off this must never contain a row with no photograph to look at.
keep if _m == 3 & photo_exists == 1
drop _m

* FORWARD SLASH, and it is not cosmetic -- the same reasoning 00_globals.do gives for
* ${build}. A backslash immediately before a macro reference is Stata's escape for a
* literal dollar sign and gets consumed, so a path built with one can silently lose its
* separator. Windows accepts a forward slash, and the Python that reads this CSV
* prefers it.
gen str260 photo_path = "${photodir}/" + filename
label var photo_path "Absolute path to the JPEG"

qui count
local n_usable = r(N)

di as txt _n "usable photograph-weighing pairs: `n_usable'  (recorded: `BASE_USABLE')"

order id filename photo_variable obs_type caseid key ///
      pull_province pull_municipal_city pull_item pull_nsu_unit ///
      vendor_id market_name store_stall_name raw_weight raw_unit photo_path
sort id

isid id
isid filename

export delimited using "${imgbridge}\photo_id_bridge.csv", replace

di as res _n "01_photo_bridge complete: `n_usable' photographs linked to a weighing"
di as txt "bridge: ${imgbridge}\photo_id_bridge.csv"
