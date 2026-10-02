********************************************************************************
* 18_check3_overlap.do -- can a label pair be compared at all?
*
* THE QUESTION THIS SETTLES. A fold asserts that two vendor labels name the same
* object. validate_folds.do tests that WITHIN province x municipality x size x
* dimension, because a market is the only place the claim is meaningful: one
* municipality's vendors of one unit are selling one kind of thing, and comparing an
* Iloilo object with an Aklan object confounds the label with the place.
*
* So before any comparison -- statistical or photographic -- the pair has to co-occur.
* This counts where each label appears and how much the two overlap.
*
* WHY IT EXISTS: A FINDING THAT INVALIDATED A PHOTOGRAPHIC RESULT. 16_check3_draw.do
* stratified its sample by hetero band and left province free. On fresh fish that
* produced a 1.46x size difference between `bilog' and `binilog' -- an apparent
* objection to the fold, corroborated by band-level median weights (large 610 g against
* 1,042 g). Both were artefacts. `bilog' is an ILOILO/CAPIZ word (456 of 545 weighings)
* and `binilog' an AKLAN one (62 of 99); they share ONE province and NO municipality.
* The photographs compared Iloilo fish with Aklan fish, and the band medians did the
* same. The difference is geography, not vocabulary.
*
* A PHOTOGRAPHIC DRAW FOR CHECK 3 MUST THEREFORE BE RESTRICTED TO SHARED
* MUNICIPALITIES, exactly as the weight test is. Where none exist, no draw helps.
*
* INPUT   ${imgtables}\_check3_pairs.dta     the pair register, from 16
*         ${btemp}\nsu_weighings_cpi.dta
* OUTPUT  ${imgqc}\check3_overlap_geo.csv    one row per pair
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 18_check3_overlap.do
********************************************************************************

clear all
set more off
set linesize 200
do "00_photo_globals.do"

use "${imgtables}/_check3_pairs.dta", clear
capture gen long pair_id = _n
quietly count
local NP = r(N)
forvalues i = 1/`NP' {
	local L_`i'  = layer[`i']
	local IT_`i' = itemsub[`i']
	local A_`i'  = labA[`i']
	local B_`i'  = labB[`i']
	local S_`i'  = status[`i']
}

use "${btemp}/nsu_weighings_cpi.dta", clear
keep pull_province pull_municipal_city pull_item pull_nsu_unit cleaned_nsu_unit ///
     harmonized_nsu_unit item_nsu_hetero_type corrected_weight
decode item_nsu_hetero_type, gen(size)
keep if inlist(size,"small_size","medium_size","large_size")
keep if !missing(corrected_weight)
gen str60 lo_item = lower(pull_item)
gen str60 lo_raw  = lower(strtrim(pull_nsu_unit))
gen str60 lo_cln  = lower(strtrim(cleaned_nsu_unit))
gen str60 lo_harm = lower(strtrim(harmonized_nsu_unit))
tempfile W
save `W'

tempname G
postfile `G' long pair_id str14 status str24 item str40 labelA str40 labelB ///
	long provA long provB long prov_shared long munA long munB long mun_shared ///
	using "${imgqc}/_check3_geo.dta", replace

di as res _n "{hline 104}"
di as res "GEOGRAPHIC OVERLAP OF EACH LABEL PAIR"
di as res "A fold is a claim about one market. Two labels that never share one cannot be"
di as res "compared there -- by any method."
di as res "{hline 104}"
di as txt %-14s "status" %-12s "item" %-22s "label A" %-22s "label B" ///
	%6s "provA" %6s "provB" %7s "shared" %6s "munA" %6s "munB" %8s "shrMun"

forvalues i = 1/`NP' {
	use `W', clear
	keep if strpos(lo_item, "`=lower("`IT_`i''")'") > 0
	gen byte isA = 0
	gen byte isB = 0
	if "`L_`i''" == "harm" {
		replace isA = lo_harm == "`=lower("`A_`i''")'"
		replace isB = lo_harm == "`=lower("`B_`i''")'"
	}
	if "`L_`i''" == "cleaned" {
		replace isA = lo_cln == "`=lower("`A_`i''")'"
		replace isB = lo_cln == "`=lower("`B_`i''")'"
	}
	if "`L_`i''" == "raw" {
		replace isA = lo_raw == "`=lower("`A_`i''")'"
		replace isB = lo_raw == "`=lower("`B_`i''")'"
	}
	keep if isA | isB
	quietly count
	if r(N)==0 continue

	egen byte pA = max(isA), by(pull_province)
	egen byte pB = max(isB), by(pull_province)
	egen long mun = group(pull_province pull_municipal_city)
	egen byte mA = max(isA), by(mun)
	egen byte mB = max(isB), by(mun)

	preserve
		duplicates drop pull_province, force
		quietly count if pA
		local npA = r(N)
		quietly count if pB
		local npB = r(N)
		quietly count if pA & pB
		local nps = r(N)
	restore
	preserve
		duplicates drop mun, force
		quietly count if mA
		local nmA = r(N)
		quietly count if mB
		local nmB = r(N)
		quietly count if mA & mB
		local nms = r(N)
	restore

	di as txt %-14s "`S_`i''" %-12s abbrev("`IT_`i''",12) %-22s abbrev("`A_`i''",22) ///
		%-22s abbrev("`B_`i''",22) %6.0f `npA' %6.0f `npB' %7.0f `nps' ///
		%6.0f `nmA' %6.0f `nmB' %8.0f `nms'
	post `G' (`i') ("`S_`i''") ("`IT_`i''") ("`A_`i''") ("`B_`i''") ///
		(`npA') (`npB') (`nps') (`nmA') (`nmB') (`nms')
}
postclose `G'

use "${imgqc}/_check3_geo.dta", clear
di as res _n "{hline 104}"
di as res "WHAT THIS MEANS FOR EACH CLASS OF PAIR"
di as res "{hline 104}"
foreach s in control_diff control_same unknown {
	quietly count if status=="`s'"
	local n = r(N)
	quietly count if status=="`s'" & mun_shared==0
	local z = r(N)
	quietly su mun_shared if status=="`s'"
	di as txt %-14s "`s'" "  pairs " %3.0f `n' "   with NO shared municipality " ///
		%3.0f `z' "   median shared " %4.0f r(p50)
}

quietly count if status=="unknown" & mun_shared==0
local zu = r(N)
quietly count if status=="unknown"
local nu = r(N)
di as res _n "  `zu' OF THE `nu' UNRESOLVED FOLDS HAVE NO SHARED MUNICIPALITY AT ALL."
di as res ""
di as res "  That is why the weight test could not resolve them, and it is not a"
di as res "  shortage of data in the ordinary sense. These label pairs are REGIONAL"
di as res "  VOCABULARY: `binilog', `mabahoe nga putos', `kasarangan nga putos',"
di as res "  `maisot nga tasa' are words used in one province and not the others. The"
di as res "  crosswalk asserts that a word from one place and a word from another name"
di as res "  the same object, and no within-market comparison can check that, because"
di as res "  no market contains both."
di as res ""
di as res "  A PHOTOGRAPH DOES NOT RESCUE THIS. A draw spanning provinces compares"
di as res "  different places, and whatever it finds is confounded. Restricting the draw"
di as res "  to shared municipalities is correct and, for these pairs, leaves nothing."
di as res ""
di as res "  These folds rest on the official translation, and the evidence that would"
di as res "  settle them is linguistic rather than photographic -- a speaker of both"
di as res "  dialects, or issue #37's field-staff questions."
export delimited using "${imgqc}/check3_overlap_geo.csv", replace
di as res _n "wrote ${imgqc}/check3_overlap_geo.csv"
di as res "{hline 104}"
