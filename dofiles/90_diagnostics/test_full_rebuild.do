********************************************************************************
* test_full_rebuild.do -- run the whole pipeline into an isolated tree, from raw
*
* WHAT THIS IS FOR. Every other run of this pipeline overwrites the published build, so
* "does it still reproduce from raw?" cannot be asked without risking the artifacts the
* answer is about. This file asks it safely: it sets ${build_name}, so every .dta, table
* and graph the two masters write goes to outputs/test_full_rebuild/ and
* outputs/master_rename_build/ is never touched.
*
* WHAT "FROM RAW" MEANS HERE, precisely, because it is not everything.
*
* This runs the two masters, which read three raw sources -- the market survey launch
* file, the price file, and the PSPS consumption file -- and derive everything else. It
* does NOT re-run the four prerequisites:
*
*   00a_weighing_ids.do    owns the DURABLE id registry. Re-running it is the one thing
*                          that must not be done casually: an id written down in an issue
*                          comment has to keep its meaning, and ids have already moved
*                          once (see #18, "The id numbers in my earlier comments no longer
*                          resolve"). It reads only the raw survey, so nothing downstream
*                          can affect it.
*   00b + 01 + 02          build the crosswalk, which lives in outputs/tables/ and is
*                          SHARED. verify_pipeline.py check 1 already rebuilds it from the
*                          raw inputs into a scratch directory and compares it column by
*                          column -- zero differing cells across 2,927 rows x 9 columns --
*                          so its reproducibility is established there rather than here,
*                          and without a second copy in the tree.
*   06_cpi_panel.do        the CPI panel, also in outputs/tables/ and also shared.
*
* So: run "python dofiles/verify_pipeline.py" for the upstream half and this file for the
* downstream half. Between them every step from raw to household grams is covered.
*
* NO MARKDOWN-STYLE BACKTICK PAIRS ANYWHERE IN THIS FILE, comments included.
*
* Stata expands macros BEFORE parsing and does not exempt comments. Its quoting is
* backtick-then-APOSTROPHE, so a markdown pair -- backtick, text, backtick -- is two macro
* OPENS and no close. Stata then reads the whole rest of the file looking for the closing
* apostrophe and executes none of it.
*
* THE SYMPTOM IS SILENT: exit code 0, no error, no output, no tree, and a log containing
* only the echoed source. The first version of this file had one such pair; the fix
* explaining the trap introduced a second one on the line describing it. Both cost a
* full rebuild each.
*
* To check a do-file before running it, count per line: number of backticks must not
* exceed number of apostrophes.
*
* Use "double quotes" for prose in a comment.
*
* ------------------------------------------------------------------------------
* THE TREE IS CLEARED FIRST, and that is the point. A rebuild into a directory holding a
* previous run's output proves nothing: a step that silently stopped writing its .dta
* would leave the old one in place and the comparison would pass. So section 1 removes
* the subtree and lets 00_globals.do recreate it.
*
* The whole outputs/test_ prefix is gitignored -- this tree is a ~70 MB second copy of the
* published build, produced to be diffed and discarded. The diff REPORT is small and goes
* to outputs/tables/test_full_rebuild_diff.csv, which is committed.
*
* ------------------------------------------------------------------------------
* OUTPUT  the whole build, isolated, under outputs/test_full_rebuild/
*         outputs/tables/test_full_rebuild_diff.csv   one row per compared file
*
* KEEP A SLASH IMMEDIATELY FOLLOWED BY AN ASTERISK OUT OF THIS FILE ENTIRELY, comments
* included, and even on a line that already begins with an asterisk. Stata reads that
* two-character sequence as the start of a BLOCK comment, which then runs until the
* matching close -- and if there is no close, to the end of the file.
*
* This file hit it twice. The OUTPUT line above was first written as a glob: the tree path
* followed by two asterisks, which put that sequence mid-comment and made every command
* below it inert. A path glob is the natural way to write "everything under this folder",
* which is exactly why it is worth a warning.
*
* THE SYMPTOM IS SILENT AND EXPENSIVE. Exit code 0, no error, no output, no tree, and a
* log holding nothing but the echoed source -- indistinguishable from a file that ran and
* did nothing. Each occurrence cost a full rebuild to diagnose.
*
* A misdiagnosis worth recording too: the first hypothesis was a markdown-style backtick
* pair, on the grounds that Stata expands macros before parsing. That was WRONG -- several
* live do-files in this project contain such pairs in comments and run correctly. Check the
* slash-asterisk sequence first.
*
* RUN, from the dofiles/ folder. Takes several minutes; the PSPS consumption file is large
* and on a synced drive:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\test_full_rebuild.do
********************************************************************************

clear all
set more off

* ---- the override, set BEFORE the globals load -------------------------------
* 00_globals.do reads ${build_name} and points ${btemp} / ${btables} / ${bgraphs} /
* ${bdeliv} / ${bsummary} at outputs/<build_name>/. Setting it after the globals load
* would be a no-op and the run would quietly overwrite the published build, which is
* the one failure this file must not have. So it is set here, first, and asserted below.
global build_name "test_full_rebuild"

do "00_shared/00_globals.do"

* THE GUARD. If ${btemp} still points at the published subtree the override did not take,
* and continuing would destroy the thing being verified.
if strpos("${btemp}", "test_full_rebuild") == 0 {
	di as err "ERROR: the build_name override did not take -- btemp is ${btemp}"
	di as err "Refusing to run: this would overwrite the published build."
	exit 459
}
di as res "isolated build tree: ${build}"


********************************************************************************
**# 1. Clear the tree
********************************************************************************
* Windows `rmdir /s /q' via shell, then let 00_globals.do's mkdir_missing recreate the
* five subtrees on the next `do'. Guarded on the path containing the build name, so a
* mistyped global cannot delete anything else.

foreach d in "${btemp}" "${btables}" "${bgraphs}" "${bdeliv}" "${bsummary}" {
	if strpos("`d'", "test_full_rebuild") == 0 {
		di as err "ERROR: refusing to clear `d' -- it is not inside the test tree"
		exit 459
	}
	cap noi shell rmdir /s /q "`d'"
}
* Recreate them; the masters' own `do 00_globals.do' would too, but this makes the state
* explicit rather than incidental.
foreach d in "${build}" "${btemp}" "${btables}" "${bgraphs}" "${bdeliv}" "${bsummary}" {
	mkdir_missing "`d'"
}
di as res "tree cleared and recreated"


********************************************************************************
**# 2. Outcome 1, from the raw market survey
********************************************************************************
* Not `do master_outcome1.do': that file runs `clear all' and then `do 00_globals.do'
* WITHOUT build_name set, which would reset the override back to the published subtree.
* The steps are listed here instead, in the master's own order, and each one re-reads the
* globals with build_name still in memory.
*
* If a step is ever added to master_outcome1.do it has to be added here too. That
* duplication is the cost of the override mechanism; section 5 catches it by comparing
* the FILE LIST as well as the contents, so a step missing from this file shows up as a
* file present in the published build and absent from the test one.

di as res _n ">>> 03_clean_ms.do  (calls 03a, 04, 05)"
do "00_shared/03_clean_ms.do"
di as res _n ">>> 07_cpi_factor.do"
do "00_shared/07_cpi_factor.do"
di as res _n ">>> 08_branch.do"
do "00_shared/08_branch.do"
di as res _n ">>> 10_size_assignment.do"
do "10_reference_set/10_size_assignment.do"
di as res _n ">>> 11_size_checks.do"
do "10_reference_set/11_size_checks.do"
di as res _n ">>> 12_publish_reference_set.do"
do "10_reference_set/12_publish_reference_set.do"


********************************************************************************
**# 3. Outcome 2, from the price file and the PSPS consumption file
********************************************************************************
* Same order as master_outcome2.do. 20a before 24 (it writes the month list); 30 before 28
* (it writes the three fallback schedules 28 climbs).

di as res _n ">>> 20a_psps_households.do"
do "20_psps_retrofitting/20a_psps_households.do"
di as res _n ">>> 20_case_price_points.do"
do "20_psps_retrofitting/20_case_price_points.do"
di as res _n ">>> 21_branch_size_based.do"
do "20_psps_retrofitting/21_branch_size_based.do"
di as res _n ">>> 22_branch_price_quantity.do"
do "20_psps_retrofitting/22_branch_price_quantity.do"
di as res _n ">>> 23_branch_conventional.do"
do "20_psps_retrofitting/23_branch_conventional.do"
di as res _n ">>> 24_inflate_to_psps_month.do"
do "20_psps_retrofitting/24_inflate_to_psps_month.do"
di as res _n ">>> 25_lookup.do"
do "20_psps_retrofitting/25_lookup.do"
di as res _n ">>> 30_fallback.do"
do "20_psps_retrofitting/30_fallback.do"
di as res _n ">>> 27_standard_units.do"
do "20_psps_retrofitting/27_standard_units.do"
di as res _n ">>> 28_match_and_convert.do"
do "20_psps_retrofitting/28_match_and_convert.do"
di as res _n ">>> 29_cap.do"
do "20_psps_retrofitting/29_cap.do"

di as res _n ">>> attrition_ledger.do"
do "90_diagnostics/attrition_ledger.do"


********************************************************************************
**# 4. Compare against the published build
********************************************************************************
* Every .dta both trees hold, compared on ROW COUNT and on the sum of each numeric
* variable. Not `cf' -- that halts on the first difference and says nothing about the
* rest, and what a sense check needs is the whole picture at once.
*
* SUMS, NOT A HASH. A hash answers "identical or not" and nothing else; a sum that differs
* tells you which column moved and by how much, which is the difference between a finding
* and a mystery. Row counts catch a step that dropped rows; column sums catch a step that
* changed values without changing the shape.

* THE 23 DATASETS SPLIT ACROSS TWO SUBTREES, not one, since the restructure that gave
* the published objects their own `deliverables/' folder. Five of the 23 moved there --
* the reference set, both lookups, and the two household files this file's own list
* predates (psps_grams.dta is not compared here at all: 31_psps_grams.do is not yet
* wired into this file's own step list either -- see the header's note on keeping that
* list in sync with the masters). Everything else still lives under `intermediate/'
* (the renamed `temp/'). Two root pairs, one per subtree, rather than one dataset list
* searched in two places -- so a dataset that moved and one that stayed can never be
* confused about which folder it is compared in.
clear all
do "00_shared/00_globals.do"
local pub_temp  "${output}/master_rename_build/intermediate"
local pub_deliv "${output}/master_rename_build/deliverables"
global build_name "test_full_rebuild"
do "00_shared/00_globals.do"
local tst_temp  "${btemp}"
local tst_deliv "${bdeliv}"

tempfile report
postfile CMP str48 dataset double n_pub double n_tst str8 rows ///
	double n_vars_pub double n_vars_tst double n_diff_cols str1200 diff_detail ///
	using "`report'", replace

local files_temp nsu_data_master nsu_weighings_cpi ref_10_sized ref_11_checked ///
	psps_households case_price_points case_spelling_gap ///
	branch_size_based branch_price_quantity branch_price_quantity_m ///
	branch_conventional outcome2_weight_ladder outcome2_cell_fallback ///
	outcome2_fallback_province outcome2_fallback_national psps_converted ///
	standard_unit_factors psps_months

local files_deliv nsu_reference_set outcome2_lookup outcome2_lookup_noinflation ///
	psps_standard_units psps_converted_capped

foreach grp in temp deliv {
	if "`grp'" == "temp" {
		local pub "`pub_temp'"
		local tst "`tst_temp'"
		local flist "`files_temp'"
	}
	else {
		local pub "`pub_deliv'"
		local tst "`tst_deliv'"
		local flist "`files_deliv'"
	}

	foreach f of local flist {
		local okp = 0
		local okt = 0
		cap confirm file "`pub'/`f'.dta"
		if !_rc local okp = 1
		cap confirm file "`tst'/`f'.dta"
		if !_rc local okt = 1

		if `okp' == 0 | `okt' == 0 {
			local miss = cond(`okp' == 0, "missing in published", "missing in test")
			post CMP ("`f'") (.) (.) ("MISSING") (.) (.) (.) ("`miss'")
			di as err "  `f': `miss'"
			continue
		}

		* ---- the published side, once ------------------------------------------------
		* TWO LOADS PER DATASET, not one per variable. The obvious way to write this is a
		* preserve/restore inside the variable loop that re-reads the published file each
		* time; on 23 datasets and a few hundred columns, across a synced drive, that is
		* hundreds of reads of files up to 70 MB.
		use "`pub'/`f'.dta", clear
		local np = _N
		qui ds
		local varsp `r(varlist)'
		local nvp : word count `varsp'

		* SUMS ARE STORED AS HEX FLOATS. `local s = r(sum)' writes the macro through Stata's
		* number-to-text conversion, which keeps about 13 significant digits of a double --
		* a trap this project has already been bitten by in 07_cpi_factor.do and in the snap
		* verdict join. At 13 digits a genuinely identical sum can differ in the macro, so a
		* tight tolerance would report false differences on the largest columns.
		* `%21x' is Stata's hex-float format: exact, round-trips, and usable directly as a
		* numeric literal in the comparison below.
		local pnum ""
		local psums ""
		foreach v of local varsp {
			cap confirm numeric variable `v'
			if _rc continue
			qui su `v', meanonly
			local hx : display %21x r(sum)
			local pnum  "`pnum' `v'"
			local psums "`psums' `hx'"
		}

		* ---- the test side, once -----------------------------------------------------
		use "`tst'/`f'.dta", clear
		local nt = _N
		qui ds
		local varst `r(varlist)'
		local nvt : word count `varst'

		* Compare the sum of every numeric variable present in BOTH files. A variable in one
		* and not the other is reported as a column difference rather than compared.
		local ndiff = 0
		local detail ""
		local i = 0
		foreach v of local pnum {
			local ++i
			local sp : word `i' of `psums'
			local inboth : list posof "`v'" in varst
			if `inboth' == 0 {
				local ++ndiff
				local detail "`detail'`v': absent in test; "
				continue
			}
			qui su `v', meanonly
			local hx : display %21x r(sum)
			* reldif handles both-zero, which a plain ratio does not. Exact equality is the
			* right test here BECAUSE the values are hex floats -- there is no formatting
			* noise left to tolerate -- but reldif is kept so a rebuild that differs only in
			* the last bit of a float reports the size of the difference rather than just its
			* existence.
			if reldif(`sp', `hx') > 0 {
				local ++ndiff
				* Shown in decimal, not hex: the hex form is what makes the COMPARISON exact,
				* but it is unreadable in a report a person has to act on.
				local dp : display %14.0g `sp'
				local dt : display %14.0g `hx'
				local detail "`detail'`v': `=trim("`dp'")' vs `=trim("`dt'")'; "
			}
		}
		* postfile truncates a string that overflows its width, so the detail is cut here,
		* visibly, rather than silently losing its tail.
		if length("`detail'") > 1150 {
			local detail = substr("`detail'", 1, 1140) + " [...]"
		}

		local rowtag = cond(`np' == `nt', "SAME", "DIFFER")
		post CMP ("`f'") (`np') (`nt') ("`rowtag'") (`nvp') (`nvt') (`ndiff') ("`detail'")

		if "`rowtag'" == "SAME" & `ndiff' == 0 & `nvp' == `nvt' {
			di as res "  `f': identical (" `np' " rows, " `nvp' " vars)"
		}
		else {
			di as err "  `f': rows `np' vs `nt', vars `nvp' vs `nvt', `ndiff' differing column(s)"
			if "`detail'" != "" di as err "     `detail'"
		}
	}
}
postclose CMP


********************************************************************************
**# 5. The verdict, including files one tree has and the other does not
********************************************************************************

use "`report'", clear
gen byte identical = (rows == "SAME" & n_diff_cols == 0 & n_vars_pub == n_vars_tst)
label var identical "1 = same rows, same variables, every numeric column sums the same"

qui count
local n_all = r(N)
qui count if identical
local n_ok = r(N)

di as res _n "{hline 78}"
di as res "FROM-RAW REBUILD vs THE PUBLISHED BUILD"
di as res "{hline 78}"
di as res "  datasets compared : `n_all'"
di as res "  identical         : `n_ok'"
di as res "  differing         : " `n_all' - `n_ok'

if `n_ok' < `n_all' {
	di as err _n "  NOT IDENTICAL -- the pipeline does not reproduce from raw."
	di as err "  Each differing dataset is listed above with the columns that moved."
	list dataset n_pub n_tst rows n_diff_cols if !identical, noobs abbrev(24)
}
else {
	di as res _n "  The pipeline reproduces from raw: every dataset has the same rows,"
	di as res "  the same variables, and the same sum on every numeric column."
}

order dataset rows identical n_pub n_tst n_vars_pub n_vars_tst n_diff_cols diff_detail
export delimited using "${tables}\test_full_rebuild_diff.csv", replace
di as txt _n "wrote ${tables}\test_full_rebuild_diff.csv"

di as res _n "{hline 78}"
di as res "This covers the two masters. For the crosswalk and the CPI panel -- both shared,"
di as res "both prerequisites -- run: python dofiles/verify_pipeline.py"
di as res "{hline 78}"
