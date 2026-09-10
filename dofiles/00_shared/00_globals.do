********************************************************************************
* 00_globals.do -- paths and shared programs for the whole pipeline
*
* Every numbered do-file in this project starts by running this file. Nothing here
* touches data; it only defines where things live and the two programs that more
* than one step needs.
*
* CALLED BY   both master do-files, and by each numbered step so a single step can
*             still be run on its own without the master.
*
* Run a step on its own like this, from the dofiles/ folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\03_clean_ms.do
********************************************************************************

set more off

* ---- deterministic sorting -----------------------------------------------------
* Since Stata 13, `sort' places TIED observations in a random order, drawn from the
* sort seed. Two runs of the same do-file on the same data therefore produce the same
* rows in a different order unless the seed is pinned -- which is exactly what
* happened here: 07_cpi_factor.do's output stopped reproducing between a standalone
* run and a run from master_outcome1.do, with identical values throughout.
*
* This matters beyond reproducibility. Any `bysort key: ... _n' where `key' does not
* uniquely identify a row is reading an order the sort seed chose, and this pipeline
* has such a construction (the running-sum-over-tags in 10_size_assignment.do, issue
* #18). Pinning makes those reproducible; it does not make them correct, and the
* right fix there is still to sort on something unique.
*
* The value is arbitrary. What matters is that it never changes.
set sortseed 20260831

* No `version' pin. One was added and removed again during the restructure -- it
* looked like pinning changed cpi_factor, but the apparent change was the row-order
* problem above. A pin may still be worth adding; it just has to be a deliberate
* decision rather than a side effect.

* ---- root ---------------------------------------------------------------------
* `c(username)' rather than a hardcoded user, so the same file works on any machine
* with the Box folder mounted in the usual place.
global root    "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
global proj    "${root}\Data Cleaning"
global dofiles "${proj}\dofiles"

* ---- raw inputs ---------------------------------------------------------------
global data      "${root}\NSU Market Survey Launch\data\PSPS NSU Market Survey Launch.dta"
global pricedata "${root}\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv"

* The PSPS household consumption file, for Outcome 2. Note 2_publication_data --
* an earlier version of the extraction do-file read 3_publication_data, which does
* not exist, so the file had never run.
global psps_cons "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\08 Analysis & Data\14 Wave 1_Pub\Household survey\5_outputs\2_publication_data\2_consumption\2_consumption.dta"

* ---- outputs ------------------------------------------------------------------
global output "${proj}\outputs"
global temp   "${output}\temp"
global graphs "${output}\graphs"
global tables "${output}\tables"
* Silent mkdir, not `cap noi mkdir'. On every run after the first these folders all
* exist, so `noi' logged a mkdir failure eight times per build -- noise on a perfectly
* healthy build, which is the fastest way to train a reader to skip real errors. (The
* wording is left out of this comment on purpose: it was worth being able to grep a log
* for that message and get only genuine hits.) The failure that matters is not a
* redundant mkdir; it is a folder that cannot be reached at all, and mkdir_missing
* below halts on exactly that.
capture program drop mkdir_missing
program define mkdir_missing
	args d
	cap mkdir "`d'"
	mata: st_local("ok", strofreal(direxists(st_local("d"))))
	if "`ok'" != "1" {
		di as err "output folder is unreachable and could not be created: `d'"
		exit 693
	}
end

foreach d in "${output}" "${temp}" "${graphs}" "${tables}" {
	mkdir_missing "`d'"
}

* The current build writes to its own subtree so the pre-Aug11 outputs under
* ${temp} stay inspectable. See dofiles/archive/README.md.
*
* ${build_name} IS AN OVERRIDE, and it exists so a variant build cannot clobber the
* published one. A caller that sets it before running this file sends every .dta, every
* table and every graph to its own subtree -- which is what makes an experiment
* (does re-keying the snap anchor change anything?) safe to run without backing up and
* restoring 73 MB of artifacts by hand. Relying on a human to remember that backup is
* the same fragile safeguard this project has been bitten by before.
* FORWARD SLASH, deliberately, and it is not cosmetic. Written as
* "${output}\${build_name}" the backslash is consumed: `\$' is Stata's escape for a
* literal dollar sign, so the separator disappears and the path becomes
* "...\outputsanchor_pull_nsu_unit". It creates the folder, saves into it, reports
* success, and the variant build silently lands outside outputs/. Stata accepts a
* forward slash on Windows, and it cannot be eaten.
if "${build_name}" == "" global build_name "master_rename_build"
global build   "${output}/${build_name}"

* Five subtrees, split by what a reader would need to know before opening one:
*   deliverables  the published objects a reader outside this pipeline consumes --
*                 the reference set, the two lookups, and the household-level PSPS
*                 files -- plus the .xlsx / .csv export that goes with each.
*   intermediate  every other .dta the build writes and a later step reads. Nothing
*                 here is meant to be opened by anyone who is not debugging the
*                 pipeline itself.
*   summary       sense checks, summary statistics, the attrition ledger and the
*                 pipeline explorer -- material that describes the build rather than
*                 being part of it.
*   diagnostics   everything else: issue-specific scoping tables, review workbooks,
*                 one-off exports. Never a dependency of another step.
*   graphs        analytic figures meant to be read on their own.
*
* Kept as ${btemp} / ${btables} / ${bgraphs} even though the folders they point to are
* no longer called temp/ and tables/. Renaming the macros would be 49 edits across the
* do-files that use them for nothing gained; repointing the macro is the one-line change
* that matters, and this comment is what makes the mapping legible.
global btemp    "${build}\intermediate"
global btables  "${build}\diagnostics"
global bgraphs  "${build}\graphs"
global bdeliv   "${build}\deliverables"
global bsummary "${build}\summary"
foreach d in "${build}" "${btemp}" "${btables}" "${bgraphs}" "${bdeliv}" "${bsummary}" {
	mkdir_missing "`d'"
}


* ---- THIN ---------------------------------------------------------------------
* Fewer than this many weighings behind an estimate makes it thin. ONE DEFINITION,
* because it is now read in three places and they must agree:
*
*   12_publish_reference_set.do   sets d_thin, AND decides which cells collapse across
*                                 their size rungs (Outcome 1's fallback level 1)
*   10_size_assignment.do         carries it through for that collapse
*   30_fallback.do                the rung the Outcome 2 ladder must clear before it
*                                 stops climbing
*
* It was a `local THIN = 3' in each of the three, with the third carrying the comment
* "must match 12_publish_reference_set.do" -- a comment is not a mechanism. Three copies
* of one threshold is the same defect that gave the block reading three implementations,
* and the fix is the same: one home, everyone reads it.
*
* THE VALUE IS NOT NEUTRAL and moving it does two things at once. It flags a row as thin,
* and it decides which cells stop publishing a size ladder. docs/implicit_assumptions.md
* A3 has the sensitivity table and the warning against reading the flagged share as a
* coverage measure; verify_documented_claims.py fails if that table goes stale.
global THIN 3


********************************************************************************
* Shared programs
********************************************************************************

* ---- def_hetero ---------------------------------------------------------------
* The obs_type value label. Defined as a program rather than once at the top
* because `use ..., clear' on the raw launch data wipes value labels along with the
* data, so it has to be re-declared after every load.
*
* The ORDER IS SEMANTIC and is relied on downstream: codes 2/3/4 are small/medium/
* large and are compared with < and >, so they must stay in ascending size order.
capture program drop def_hetero
program define def_hetero
	label define hetero 1 "conventional_nsu" 2 "small_size" 3 "medium_size" 4 "large_size" ///
		5 "mp25_price" 6 "mp50_price" 7 "mp75_price" 8 "municipality_median" ///
		9 "province_median" 10 "unique_mun_price6" 11 "unique_mun_price7", replace
end

* ---- def_fallback_level -------------------------------------------------------
* The fallback ladder's rung labels, defined ONCE for both outcomes. Codes 0 and 1 mean
* the same thing in each and must keep meaning the same thing, because a reader comparing
* an Outcome 1 row with an Outcome 2 row is entitled to read the flag the same way.
*
* Outcome 1 stops at 1 -- the reference set records what was weighed in a cell and does
* not borrow across cells, so 2 and 3 never occur there. That is not a reason to give it a
* shorter label set: a value label costs nothing and a divergent one costs a reader's
* confidence. Declared as a program for the same reason def_hetero is -- `use ..., clear'
* wipes value labels with the data, so it has to be re-declarable after any load.
*
* Ordinal on purpose. A reader can keep rung 1 and drop rung 3 rather than facing one
* all-or-nothing switch; docs/implicit_assumptions.md A15 has the reasoning.
*
* CODE 0 IS "THE CELL'S OWN WEIGHINGS", not "own cell x size". The earlier wording named a
* size dimension, and two large populations of rows at level 0 have none: the always-
* conventional cases (size_ord == 0) and #28's reclassified cases, which publish one group
* by decision and are never terciled. On those rows the old label invited a reader to look
* for a size structure that is not there. The current wording is the thing all three
* populations actually have in common -- the weight came from this cell, nothing was
* borrowed -- which is the whole content of level 0 and is what 12_publish_reference_set.do
* section 5c asserts.
capture program drop def_fallback_level
program define def_fallback_level
	label define fallback_lbl ///
		0 "the cell's own weighings" ///
		1 "cell pooled across sizes" ///
		2 "province x item x unit" ///
		3 "item x unit (national)", replace
end

* ---- nsu_normalize ------------------------------------------------------------
* THE authoritative string normalization on the Stata side. Its Python counterpart
* is nz()/ni()/ng() in 00_shared/01_build_crosswalk.py, and the two MUST agree
* character for character -- master_nsu_rename.csv is built by the Python side and
* joined by this one.
*
* mode 2 DROPS non-ASCII rather than transliterating. That is deliberate: a clean
* n-tilde and a mojibaked one must collapse to the SAME string, and they do only if
* both lose the character (DUENAS -> DUEAS either way). Do not "improve" this to
* NFKD-decompose -- that maps a clean DUENAS to DUENAS and a mojibaked one to
* something else, and the join silently loses rows.
capture program drop nsu_normalize
program define nsu_normalize
	syntax , Item(name) Unit(name) [Mun(name) PROVince(name)]

	foreach v in `item' `unit' {
		replace `v' = ustrto(`v', "ascii", 2)
		replace `v' = ustrtrim(ustrlower(`v'))
		replace `v' = ustrregexra(`v', "\s+", " ")
	}

	* prepped food: the item string differs across datasets only in the accent
	replace `item' = "drinks at restaurant, hotel, cafe, or kiosk" if strpos(`item', "restaurant") > 0

	foreach v in `mun' `province' {
		replace `v' = ustrto(`v', "ascii", 2)
		replace `v' = ustrtrim(ustrupper(`v'))
		replace `v' = ustrregexra(`v', "\s+", " ")
	}
end

di as txt "00_globals.do loaded -- build subtree: ${build}"
