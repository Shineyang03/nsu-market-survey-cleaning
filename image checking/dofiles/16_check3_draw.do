********************************************************************************
* 16_check3_draw.do -- the photographs Check 3's instrument is calibrated on
*
* CHECK 3 verifies the HARMONIZATION CROSSWALK: do two labels the fold pools show the
* same physical object? Its unit is a LABEL PAIR, not a weighing, so this draws
* photographs per LABEL and the comparison happens afterwards, in 17.
*
* WHY THERE ARE CONTROLS, AND WHY THEY COME FIRST. Checks 1 and 2 could be calibrated
* against a human because "what does this display read" has one right answer a person
* can supply. "Are these two labels the same kind of object" does not -- a person would
* be guessing from the same photographs. So the ground truth here is the WEIGHT TEST:
*
*   POSITIVE controls  pairs validate_folds.do calls `different' on a large ratio.
*                      Chicken `bilog' (a whole bird, ~1,045 g) against `pieces or
*                      units' (a portion, ~500 g) is 3.74x apart. If the object
*                      instrument cannot separate THESE, it cannot separate anything
*                      and nothing it says about the unresolved pairs is worth reading.
*   NEGATIVE controls  pairs it calls `equivalent' at a ratio near 1.00. If the
*                      instrument reports an objection on these, it is finding
*                      differences that are not there -- the opposite failure, and the
*                      more dangerous one, because an objection is the actionable
*                      verdict.
*   UNKNOWN            the 7 pairs it cannot resolve. These are the question.
*
* The controls are not a formality. They are the only thing that converts "a model said
* these look different" into evidence, and they are cheap -- the same reading pass.
*
* THE DRAW IS STRATIFIED BY HETERO TYPE, which matters more here than anywhere else in
* this subsystem. A fold is a claim about WHAT THE THING IS, not how big it is. If one
* label's sample is mostly smalls and the other's mostly larges, a reader will report a
* size difference and it will be scored as a referent difference. Holding size fixed is
* what makes the comparison about the referent.
*
* THE SHEETS STAY BLIND. make_contact_sheets.py gives each tile a sequence number and
* nothing else, exactly as for Checks 1 and 2. The reader describes one photograph at a
* time and never learns which label it belongs to, or that any grouping exists.
* PROMPT.md's Blinding section allows Check 3 to name the labels -- "it asks whether two
* labels name the same object, which cannot be asked without naming the labels" -- but
* that permission is not needed if the grouping is applied AFTERWARDS, to structured
* descriptions, by 17_check3_reconcile.do. Reading blind costs the same number of
* photographs and buys a stronger inference: a reader told two tiles are supposed to
* match will tend to say they match.
*
* IF BLIND DESCRIPTION TURNS OUT TOO COARSE -- if it cannot separate the positive
* controls -- then a side-by-side pass is the fallback, and the controls are what will
* have told us. Do not start there.
*
* INPUT   ${btemp}\nsu_weighings_cpi.dta
*         ${imgbridge}\photo_id_bridge.csv
*         ${imgqc}\seen_ids.csv                  (optional)
* OUTPUT  ${imgtables}\check3_ids.csv            ids for make_contact_sheets.py
*         ${imgtables}\check3_labels.csv         the label/pair register, for 17
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 16_check3_draw.do
********************************************************************************

clear all
set more off
set linesize 200
do "00_photo_globals.do"

* ---- THE DIALS ------------------------------------------------------------------
local SEED    = 20260930
local PERLBL  = 6        // photographs per label
local PERSIZE = 2        // at most this many from any one hetero band, if spread allows

set seed `SEED'

********************************************************************************
* 1. THE PAIR REGISTER
*
* Hardcoded, like validate_folds.do's SPLITS list, and for the same reason: this is a
* policy list naming which decisions are under test, not something to re-derive. Each
* row is   layer | item substring | label A | label B | status | recorded ratio
*
* layer    harm    = harmonized_nsu_unit  (a translation-group decision)
*          cleaned = cleaned_nsu_unit     (a translation fold, Panel A)
*          raw     = pull_nsu_unit        (a spelling fold, Panel C)
*
* The ratios are validate_folds.do's Hodges-Lehmann estimates, carried here so a reader
* of this file can see WHY each pair is a control. They are not used in the draw.
********************************************************************************
tempname P
postfile `P' str8 layer str24 itemsub str40 labA str40 labB str14 status double ratio ///
	using "${imgtables}/_check3_pairs.dta", replace

* -- POSITIVE controls: the weight test says these are different objects -------------
post `P' ("harm")    ("chicken")   ("bilog")         ("pieces or units") ("control_diff") (3.74)
post `P' ("harm")    ("crackers")  ("putos")         ("pack")            ("control_diff") (0.27)
post `P' ("harm")    ("ice cream") ("putos")         ("pack")            ("control_diff") (0.56)
post `P' ("harm")    ("camote")    ("bilog")         ("binilog")         ("control_diff") (1.33)

* -- NEGATIVE controls: the weight test confirms these agree -------------------------
post `P' ("cleaned") ("cabbage")   ("bilog")         ("binilog")         ("control_same") (0.96)
post `P' ("raw")     ("liquor")    ("lipid / lapad") ("lapad")           ("control_same") (1.00)
post `P' ("raw")     ("loaf")      ("large")         ("dalagku nga putos") ("control_same") (1.00)

* -- UNKNOWN: the 7 the weight test cannot resolve -----------------------------------
post `P' ("cleaned") ("crackers")  ("bilog")  ("binilog")              ("unknown") (.)
post `P' ("cleaned") ("crackers")  ("bilog")  ("pieces or units")      ("unknown") (0.88)
post `P' ("cleaned") ("fresh fish") ("bilog") ("binilog")             ("unknown") (1.00)
post `P' ("raw")     ("ice cream") ("gamay nga cup") ("maisot nga tasa")   ("unknown") (.)
post `P' ("raw")     ("loaf")      ("large")  ("mabahoe nga putos")    ("unknown") (.)
post `P' ("raw")     ("loaf")      ("medium") ("kasarangan nga putos") ("unknown") (.)
post `P' ("raw")     ("loaf")      ("small")  ("maisot nga putos")     ("unknown") (.)
postclose `P'

use "${imgtables}/_check3_pairs.dta", clear
gen long pair_id = _n
quietly count
local NPAIR = r(N)
di as res _n "{hline 78}"
di as res "CHECK 3 CALIBRATION DRAW -- `NPAIR' label pairs"
di as res "{hline 78}"
tab status
forvalues i = 1/`NPAIR' {
	local L_`i'  = layer[`i']
	local IT_`i' = itemsub[`i']
	local A_`i'  = labA[`i']
	local B_`i'  = labB[`i']
	local S_`i'  = status[`i']
}
save "${imgtables}/_check3_pairs.dta", replace

********************************************************************************
* 2. THE WEIGHINGS, with photograph availability
********************************************************************************
preserve
	import delimited using "${imgbridge}/photo_id_bridge.csv", clear varnames(1) ///
		stringcols(_all) encoding("utf-8")
	keep id
	destring id, replace force
	drop if missing(id)
	duplicates drop id, force
	gen byte has_photo = 1
	tempfile ph
	save `ph'
restore

use "${btemp}/nsu_weighings_cpi.dta", clear
keep id pull_item pull_nsu_unit cleaned_nsu_unit harmonized_nsu_unit ///
     item_nsu_hetero_type corrected_weight pull_province pull_municipal_city
merge 1:1 id using `ph', keep(master match) nogen
replace has_photo = 0 if missing(has_photo)
decode item_nsu_hetero_type, gen(size)

* physical weighings only -- municipality and province medians are derived rows and
* have no photograph of their own
keep if inlist(size,"small_size","medium_size","large_size")
keep if has_photo==1

* AN IMAGE ONCE SEEN IS SEEN PERMANENTLY. Same rule as 03_calibration_draw.do.
capture confirm file "${imgqc}/seen_ids.csv"
if !_rc {
	preserve
		import delimited using "${imgqc}/seen_ids.csv", clear varnames(1) ///
			stringcols(_all) encoding("utf-8")
		capture destring id, replace force
		keep id
		drop if missing(id)
		duplicates drop id, force
		gen byte seen = 1
		tempfile sn
		save `sn'
	restore
	merge m:1 id using `sn', keep(master) nogen
}

gen str60 lo_item = lower(pull_item)
gen str60 lo_raw  = lower(strtrim(pull_nsu_unit))
gen str60 lo_cln  = lower(strtrim(cleaned_nsu_unit))
gen str60 lo_harm = lower(strtrim(harmonized_nsu_unit))
tempfile W
save `W'

********************************************************************************
* 3. DRAW, per (pair, label), stratified by hetero band
********************************************************************************
tempname D
postfile `D' long id long pair_id str14 status str8 layer str40 label str8 side ///
	str14 size using "${imgtables}/_check3_draw.dta", replace

forvalues i = 1/`NPAIR' {
	foreach side in A B {
		local lb = "``side'_`i''"
		use `W', clear
		keep if strpos(lo_item, "`=lower("`IT_`i''")'") > 0
		if "`L_`i''" == "harm"    keep if lo_harm == "`=lower("`lb'")'"
		if "`L_`i''" == "cleaned" keep if lo_cln  == "`=lower("`lb'")'"
		if "`L_`i''" == "raw"     keep if lo_raw  == "`=lower("`lb'")'"

		quietly count
		local avail = r(N)
		if `avail' == 0 {
			di as err "  pair `i' side `side' (`IT_`i'' | `lb') -- NO PHOTOGRAPHED WEIGHINGS"
			continue
		}

		* stratify: take up to PERSIZE from each band, then top up at random
		gen double u = runiform()
		bysort size (u id): gen long rk_in_size = _n
		gen byte take = (rk_in_size <= `PERSIZE')
		quietly count if take
		local got = r(N)
		if `got' < `PERLBL' {
			local need = `PERLBL' - `got'
			sort take u id
			quietly replace take = 1 if !take & _n <= `need' + `got'
		}
		sort take u id
		quietly count if take
		if r(N) > `PERLBL' {
			* trim the overflow deterministically
			gen long _o = _n if take
			quietly su _o
			sort take u id
			local k = 0
			forvalues j = 1/`=_N' {
				if take[`j'] {
					local ++k
					if `k' > `PERLBL' quietly replace take = 0 in `j'
				}
			}
		}
		keep if take
		quietly count
		di as txt "  pair `i' `side'  " %-24s "`IT_`i''" " | " %-26s abbrev("`lb'",26) ///
			"  drew " r(N) " of `avail'"
		forvalues j = 1/`=_N' {
			post `D' (id[`j']) (`i') ("`S_`i''") ("`L_`i''") ("`lb'") ("`side'") (size[`j'])
		}
	}
}
postclose `D'

********************************************************************************
* 4. WRITE THE TWO OUTPUTS
********************************************************************************
use "${imgtables}/_check3_draw.dta", clear
di as res _n "{hline 78}"
di as res "THE DRAW"
di as res "{hline 78}"
quietly count
di as txt "  photographs drawn ............................. " r(N)
quietly levelsof id, local(U)
di as txt "  distinct photographs .......................... " `: word count `U''
tab status
tab size

* a photograph can serve two pairs (crackers `bilog' and loaf bread `large' each appear
* twice). The sheet needs each image ONCE; the register keeps every pair membership.
preserve
	keep id
	duplicates drop
	sort id
	export delimited using "${imgtables}/check3_ids.csv", replace
	quietly count
	di as res _n "wrote ${imgtables}/check3_ids.csv -- " r(N) " distinct ids"
restore

merge m:1 pair_id using "${imgtables}/_check3_pairs.dta", keep(match) nogen
sort pair_id side id
export delimited using "${imgtables}/check3_labels.csv", replace
quietly count
di as res "wrote ${imgtables}/check3_labels.csv -- " r(N) " (photograph x pair) rows"

di as res _n "{hline 78}"
di as res "NEXT: build the sheets, from the image checking/scripts folder"
di as res ""
di as res "  python make_contact_sheets.py --out-tag c3cal" ///
          " --ids ../outputs/tables/check3_ids.csv --shuffle --seed `SEED'" ///
          " --cell 700 --cols 2 --per-sheet 4"
di as res ""
di as res "Readers read those under PROMPT_OBJECTS.md. The sheets are BLIND -- no label"
di as res "reaches the reader. 17_check3_reconcile.do applies check3_labels.csv"
di as res "afterwards and asks whether the descriptions separate the pairs."
di as res "{hline 78}"
