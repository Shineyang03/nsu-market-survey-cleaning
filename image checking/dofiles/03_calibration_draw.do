********************************************************************************
* 03_calibration_draw.do -- the stratified sample the reading instrument is tested on
*
* WHAT IT IS FOR. Before 3,535 photographs are read, the reader has to be calibrated:
* how often do two readers agree, does the decimal survive, and is a cheap model as
* good as an expensive one? This draws the set those questions are answered on.
*
* WHY IT IS NOT A RANDOM SAMPLE OF THE TARGET LIST. A calibration set drawn at random
* is dominated by easy images, and agreement measured on easy images does not transfer
* to the hard ones -- which are the only ones the answer turns on. So it is stratified
* and DELIBERATELY OVER-SAMPLES the awkward cells:
*
*   - `block governs' rows, which photo_review_queue.do records as 12x more likely to
*     be a decade outlier: 35/571 = 6.13% against 54/10,758 = 0.50%. Those 571 are
*     where 03a_block_reading.do's <=10 and >30 thresholds actually decided something.
*   - dimension overrules, a larger claim than moving a decimal since they assert the
*     officer picked the wrong dropdown item.
*   - the three Check 1 dimension grounds, which are small and sharply defined.
*   - flat-group representatives, where the expected answer is a printed label and no
*     scale at all -- the case the reader must not force a number onto.
*
* EXCLUDES WHAT HAS ALREADY BEEN SEEN. Nine photographs were read aloud earlier in the
* session that built this pipeline, so a "blind" re-read of them is not blind. They are
* dropped by id rather than trusted to not recur. ${imgqc}\seen_ids.csv holds them and
* is appended to, never rewritten -- an image once seen is seen permanently.
*
* SEEDED. `SEED' is recorded in the output, so a later session re-drawing the same
* population with the same seed gets the same rows, as the handover brief requires.
*
* NOTE ON `sample'. Stata's sort places tied observations in an order drawn from the
* sort seed, so a draw that sorts on a non-unique key is not reproducible even with
* `set seed'. Every sort below ends in `id', which is unique.
*
* INPUT   ${imgtables}\photo_targets.csv
*         ${imgqc}\seen_ids.csv            (optional; created empty if absent)
* OUTPUT  ${imgtables}\calibration_ids.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 03_calibration_draw.do
********************************************************************************

clear all
do "00_photo_globals.do"

* ---- THE DIALS ------------------------------------------------------------------
* N per stratum, not a total: the strata are of very different sizes and the point is
* to have enough of each to say something, not to mirror the population.
local SEED    20260919
local N_STRAT 20

set seed `SEED'

********************************************************************************
* A. Load the targets, and drop what has been seen
********************************************************************************

import delimited "${imgtables}/photo_targets.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)

destring id check priority has_photo, replace
keep if has_photo == 1

* A weighing wanted by both checks is ONE photograph, so the draw must see each id
* once. The collapse happens AFTER stratification, not here, and that ordering is the
* point: collapsing on `check' first silently destroyed a whole stratum. All 348
* dimension overrules are also Check 1 rows -- overruling a tick is precisely what
* makes a weighing liquid-ticked-as-mass or dual-ticked -- so taking the lowest
* `check' per id absorbed every one of them into Check 1 and left the Check 2
* dimension cell with zero rows, while reporting success.
qui levelsof id, local(_ids)
local n_pool : word count `_ids'

* ---- the seen list --------------------------------------------------------------
capture confirm file "${imgqc}/seen_ids.csv"
if _rc {
	di as txt "no seen-id list yet; creating an empty one at ${imgqc}/seen_ids.csv"
	preserve
		clear
		set obs 0
		gen long id = .
		gen str32 seen_where = ""
		export delimited using "${imgqc}/seen_ids.csv", replace
	restore
}

preserve
	import delimited "${imgqc}/seen_ids.csv", clear varnames(1) delimiter(",")
	capture confirm variable id
	if _rc {
		clear
		set obs 0
		gen long id = .
	}
	qui count
	local n_seen = r(N)
	tempfile seen
	save "`seen'"
restore

* m:1, not 1:1. The collapse to one row per image now happens after stratification,
* so an id appears once per check here and 1:1 fails on exactly the rows that are
* wanted by both checks.
merge m:1 id using "`seen'", keep(master) nogen
qui levelsof id, local(_ids2)
local n_avail : word count `_ids2'

di as txt _n "pool with a photograph: `n_pool'   previously seen: `n_seen'   available: `n_avail'"

********************************************************************************
* B. Strata
********************************************************************************

* One stratum per TARGET ROW first; the collapse to one row per image comes after.
*
* `stratum_ord' ORDERS THE CELLS BY SCARCITY, rarest first, and that is what decides
* which claim an image keeps when two checks want it. A photograph that is both a
* dimension overrule (348 in the build) and a dual-ticked case (649) is worth more to
* the calibration as the former. Ordering by `check' instead -- the obvious version --
* is what emptied the dimension cell.
gen byte stratum_ord = .
gen str32 stratum = ""

* 9 is the non-representative remainder of a flat group and is EXCLUDED below, not
* drawn. Every weighing in a flat group reports the same number, so one photograph
* settles all of them; reading the other 502 would spend the calibration's budget
* re-confirming a group it has already answered. They stay in photo_targets.csv,
* which is the list a reviewer works from -- this exclusion is the calibration's, not
* the target list's.
#delimit ;
local cells `" "1 C1 solid as Litres"      "2 C2 review queue"
               "3 C2 dimension overrule"   "4 C1 flat-group rep"
               "5 C2 block governs"        "6 C1 liquid as mass"
               "7 C1 dual-ticked"          "8 C2 magnitude"
               "9 C1 flat-group non-rep" "' ;
#delimit cr

replace stratum_ord = 1 if stratum_ord==. & strpos(reason,"solid ticked")>0
replace stratum_ord = 2 if stratum_ord==. & strpos(reason,"review queue")>0
replace stratum_ord = 3 if stratum_ord==. & strpos(reason,"dimension")>0
replace stratum_ord = 4 if stratum_ord==. & strpos(reason,"4A")>0 & is_rep=="1"
replace stratum_ord = 5 if stratum_ord==. & check==2 & strpos(lower(snap_rule),"block")>0
replace stratum_ord = 6 if stratum_ord==. & strpos(reason,"liquid ticked")>0
replace stratum_ord = 7 if stratum_ord==. & strpos(reason,"dual-ticked")>0
replace stratum_ord = 8 if stratum_ord==. & check==2
replace stratum_ord = 9 if stratum_ord==. & strpos(reason,"4A")>0 & is_rep=="0"

foreach c of local cells {
	local k : word 1 of `c'
	local nm = subinstr("`c'", "`k' ", "", 1)
	replace stratum = "`nm'" if stratum_ord == `k'
}

* Nothing may fall outside a stratum: an unclassified row would be silently excluded
* from the draw, which is the kind of quiet narrowing this project has been bitten by.
qui count if stratum == ""
if r(N) > 0 {
	di as error "`r(N)' available target row(s) fall in no stratum."
	list id check reason snap_rule is_rep if stratum == "" in 1/20, noobs
	exit 459
}

* ---- now one row per image, keeping its scarcest claim --------------------------
gsort id stratum_ord check priority
by id: keep if _n == 1

di as txt _n "available by stratum (one row per image):"
tab stratum

drop if stratum_ord == 9
qui count
local n_avail2 = r(N)
di as txt _n "after dropping non-representative flat-group members: `n_avail2'"

********************************************************************************
* C. Draw
********************************************************************************

* `runiform()' AFTER `set seed', then sort on (stratum, u, id). The trailing id breaks
* any tie in u deterministically, so the draw does not depend on the sort seed.
gen double u = runiform()
gsort stratum u id
by stratum: gen long pick = _n
keep if pick <= `N_STRAT'

gen int  seed = `SEED'
gen str16 draw_tag = "calib_v1"

di as res _n "drawn by stratum:"
tab stratum

qui count
local n_draw = r(N)

keep id check priority reason stratum seed draw_tag filename photo_path ///
     pull_item pull_nsu_unit snap_rule rawtick raw_weight dim corrected_weight
gsort stratum id

export delimited using "${imgtables}\calibration_ids.csv", replace

di as res _n "03_calibration_draw complete: `n_draw' images across 8 strata"
di as txt "seed `SEED', `N_STRAT' per stratum"
di as txt "draw: ${imgtables}\calibration_ids.csv"
di as txt _n "NOTE the draw carries raw_weight and corrected_weight so the UNBLINDING"
di as txt "step has them. make_contact_sheets.py must be given only the id column."
