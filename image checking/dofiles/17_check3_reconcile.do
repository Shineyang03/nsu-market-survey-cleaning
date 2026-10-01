********************************************************************************
* 17_check3_reconcile.do -- do blind object descriptions separate the label pairs?
*
* THE QUESTION THIS ANSWERS IS ABOUT THE INSTRUMENT, NOT ABOUT THE FOLDS. Readers
* described 167 photographs under PROMPT_OBJECTS.md without being told that any
* grouping existed. This file applies the grouping afterwards and asks whether the
* descriptions separate pairs we already know to be different, and fail to separate
* pairs we already know to agree. Only if BOTH hold does a reading of the 7 unresolved
* pairs mean anything.
*
* THE STATISTIC. For one pair and one categorical field, let p_A and p_B be the field's
* distribution over side A's and side B's photographs. The OVERLAP is
*
*     overlap = sum over categories of min(p_A, p_B)
*
* which is 1 minus the total variation distance. Read it as: the share of one side's
* photographs that could be swapped for the other side's without changing the
* distribution at all.
*
*     overlap near 1   the two labels look alike -- no objection
*     overlap near 0   they look like different kinds of thing -- an objection
*
* It is used rather than a modal match because a modal match throws away everything
* except the winner, and six photographs per label is too few for a winner to be stable.
*
* WHY NOT A TEST. With six photographs a side, any significance test is powerless, and
* a p-value would invite the same mistake the fold test was rebuilt to avoid: reading a
* non-rejection as evidence of sameness. The controls do the work a test cannot. If the
* positive controls separate and the negative ones do not, the instrument discriminates;
* the unresolved pairs are then read against where the controls landed, as a descriptive
* comparison and nothing more.
*
* FREE TEXT IS NOT SCORED HERE. `object', `size_cue' and `distinguishing' carry most of
* what a reader saw, and no mechanical rule should collapse them. They are written out
* side by side, per pair, for a judgement pass.
*
* INPUT   ${imgqc}\readings_c3cal.csv         parse_readings.py --instrument objects
*         ${imgtables}\check3_labels.csv      16_check3_draw.do
* OUTPUT  ${imgqc}\check3_overlap.csv         one row per (pair, field, reader)
*         ${imgqc}\check3_descriptions.csv    the free text, grouped, for judgement
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 17_check3_reconcile.do
********************************************************************************

clear all
set more off
set linesize 220
do "00_photo_globals.do"

capture confirm file "${imgqc}/readings_c3cal.csv"
if _rc {
	di as err "17: no readings_c3cal.csv yet. Run, from image checking/scripts:"
	di as err "    python parse_readings.py --tag c3cal --instrument objects \\"
	di as err "        --prompt-version objects-v2.0 --out ../outputs/qc/readings_c3cal.csv"
	exit 601
}

********************************************************************************
* 1. readings, joined to the pair register
********************************************************************************
import delimited using "${imgtables}/check3_labels.csv", clear varnames(1) ///
	stringcols(_all) encoding("utf-8")
destring id pair_id, replace force
keep id pair_id status layer label side size itemsub laba labb ratio
destring ratio, replace force
rename label lblname
tempfile reg
save `reg'

import delimited using "${imgqc}/readings_c3cal.csv", clear varnames(1) ///
	stringcols(_all) encoding("utf-8")
destring id, replace force
keep id reader visible object form container container_material size_cue colour ///
     distinguishing notes

* parse_readings.py names a reader after the FILE, so one reader checkpointing per
* sheet arrives as 42 readers (`sonnetA_s01' ... `sonnetA_s42'). That is right for its
* own coverage check, which needs to see a sheet skipped whole. Here the unit is the
* person-or-model doing the reading, so strip the sheet suffix.
gen str24 who = regexr(reader, "_s[0-9]+$", "")
drop reader
rename who reader

* one photograph can serve two pairs, so this is m:m by design -- joinby, not merge
joinby id using `reg'

di as res _n "{hline 88}"
di as res "CHECK 3 CALIBRATION -- do blind descriptions separate the pairs?"
di as res "{hline 88}"
quietly count
di as txt "  (reading x pair) rows ......................... " r(N)
* `clean' drops the compound quotes levelsof otherwise returns. Without it the names
* cannot be printed in a display line, and `foreach' still works either way.
quietly levelsof reader, local(RD) clean
di as txt "  readers ....................................... " `: word count `RD'' ///
	"   (`RD')"
quietly levelsof id, local(IDS)
di as txt "  distinct photographs with a reading ........... " `: word count `IDS''

di as res _n "  COVERAGE PER PAIR SIDE -- a side with no usable description cannot be compared"
preserve
	gen byte usable = (visible!="unusable" & form!="" & form!="indeterminate")
	collapse (count) n=id (sum) n_usable=usable, by(pair_id side reader)
	quietly count if n_usable < 3
	di as txt "    (pair x side x reader) cells with <3 usable descriptions: " r(N)
restore

********************************************************************************
* 2. OVERLAP, per (pair, field, reader)
********************************************************************************
tempname O
postfile `O' long pair_id str14 status str40 labelA str40 labelB str20 field ///
	str24 reader double overlap long nA long nB ///
	using "${imgqc}/_check3_overlap.dta", replace

quietly levelsof pair_id, local(PAIRS)
foreach f in form container {
	foreach r of local RD {
		foreach p of local PAIRS {
			preserve
				quietly keep if pair_id==`p' & reader=="`r'"
				quietly drop if visible=="unusable"
				quietly count if side=="A"
				local nA = r(N)
				quietly count if side=="B"
				local nB = r(N)
				if `nA'==0 | `nB'==0 {
					restore
					continue
				}
				local st = status[1]
				local la = laba[1]
				local lb = labb[1]
				* share of each side falling in each category, then sum of minima
				quietly levelsof `f', local(CATS)
				local ov = 0
				foreach c of local CATS {
					quietly count if side=="A" & `f'=="`c'"
					local pa = r(N)/`nA'
					quietly count if side=="B" & `f'=="`c'"
					local pb = r(N)/`nB'
					local ov = `ov' + min(`pa',`pb')
				}
				post `O' (`p') ("`st'") ("`la'") ("`lb'") ("`f'") ("`r'") ///
					(`ov') (`nA') (`nB')
			restore
		}
	}
}
postclose `O'

********************************************************************************
* 3. DID THE CONTROLS BEHAVE?
********************************************************************************
use "${imgqc}/_check3_overlap.dta", clear
gen byte is_form = (field=="form")

di as res _n "{hline 88}"
di as res "THE CONTROLS"
di as res "  positive controls SHOULD separate (low overlap)."
di as res "  negative controls SHOULD NOT (high overlap)."
di as res "{hline 88}"
foreach f in form container {
	di as res _n "  field: `f'"
	di as txt %-14s "status" %10s "pairs" %10s "mean" %10s "min" %10s "max"
	foreach s in control_diff control_same unknown {
		quietly su overlap if field=="`f'" & status=="`s'"
		if r(N) > 0 {
			di as txt %-14s "`s'" %10.0f r(N) %10.2f r(mean) %10.2f r(min) %10.2f r(max)
		}
	}
}

di as res _n "  THE VERDICT ON THE INSTRUMENT"
quietly su overlap if field=="form" & status=="control_diff"
local d_mean = r(mean)
local d_max  = r(max)
quietly su overlap if field=="form" & status=="control_same"
local s_mean = r(mean)
local s_min  = r(min)
di as txt "    positive controls, mean form overlap ........ " %5.2f `d_mean' ///
	"   (worst, i.e. highest: " %4.2f `d_max' ")"
di as txt "    negative controls, mean form overlap ........ " %5.2f `s_mean' ///
	"   (worst, i.e. lowest:  " %4.2f `s_min' ")"
if (`d_max' < `s_min') {
	di as res "    SEPARATES CLEANLY: every known-different pair has lower overlap"
	di as res "    than every known-same pair. The instrument discriminates, and the"
	di as res "    unknown pairs can be read against the gap between " ///
		%4.2f `d_max' " and " %4.2f `s_min' "."
}
else {
	di as err "    DOES NOT SEPARATE CLEANLY. The control ranges touch or cross, so"
	di as err "    `form' alone does not distinguish a real fold error from noise at"
	di as err "    this sample size. Read the free text before concluding anything,"
	di as err "    and consider a side-by-side pass -- PROMPT.md's Blinding section"
	di as err "    permits naming the labels for Check 3."
}

di as res _n "{hline 88}"
di as res "EVERY PAIR, form overlap by reader"
di as res "{hline 88}"
preserve
	keep if field=="form"
	sort status pair_id reader
	di as txt %-14s "status" %-26s "label A" %-26s "label B" %-14s "reader" ///
		%9s "overlap" %5s "nA" %5s "nB"
	forvalues i = 1/`=_N' {
		di as txt %-14s status[`i'] %-26s abbrev(labelA[`i'],26) ///
			%-26s abbrev(labelB[`i'],26) %-14s abbrev(reader[`i'],14) ///
			%9.2f overlap[`i'] %5.0f nA[`i'] %5.0f nB[`i']
	}
restore

export delimited using "${imgqc}/check3_overlap.csv", replace
di as res _n "wrote ${imgqc}/check3_overlap.csv"

********************************************************************************
* 4. THE FREE TEXT, for a judgement pass
********************************************************************************
import delimited using "${imgqc}/readings_c3cal.csv", clear varnames(1) ///
	stringcols(_all) encoding("utf-8")
destring id, replace force
keep id reader visible object form container size_cue colour distinguishing
joinby id using `reg'
keep pair_id status itemsub laba labb side lblname size reader visible object ///
     form container size_cue colour distinguishing id
order pair_id status itemsub laba labb side lblname size reader visible object ///
      form container size_cue colour distinguishing id
sort pair_id side reader id
export delimited using "${imgqc}/check3_descriptions.csv", replace
quietly count
di as res "wrote ${imgqc}/check3_descriptions.csv -- " r(N) " rows"
di as res ""
di as res "  The free text is NOT scored above. Read it per pair before accepting any"
di as res "  overlap figure: two genuinely different objects can both be honestly"
di as res "  described as `a small clear sachet', and the difference lost."
di as res "{hline 88}"
