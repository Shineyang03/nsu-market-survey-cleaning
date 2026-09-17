********************************************************************************
* master_outcome2.do -- PSPS RETRO-FITTING (Outcome 2)
*
* Outcome 2 converts PSPS household quantities into grams. It shares stage 00 with
* Outcome 1 and then diverges: Outcome 1 slices weighings by the SIZE the field
* recorded, Outcome 2 slices them by the PRICE POINTS the price file holds. The two
* are not derivable from one another -- the same case can yield three sizes in one
* and a single weight in the other.
*
* HOW TO RUN, from the dofiles/ folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do master_outcome2.do
*
* dofiles/README.md is the source for what each step owes and what blocks it; the
* list printed at the bottom of this file is an abbreviation of it.
********************************************************************************

clear all
set more off

di as res _n "{hline 78}"
di as res "OUTCOME 2 -- PSPS retro-fitting"
di as res "{hline 78}"

* ---- PREREQUISITES not run from here -------------------------------------------
* These build inputs the shared stage reads. They change rarely and are deliberately
* not in either master, so a routine rebuild does not regenerate the crosswalk. Run
* them from the PROJECT ROOT when their inputs change, in this order:
*
*     "...StataSE-64.exe" -e do 00_shared\00a_weighing_ids.do     (from dofiles/)
*     "...StataSE-64.exe" -e do 00_shared\00b_price_ms_cases.do   (from dofiles/)
*     python dofiles/00_shared/01_build_crosswalk.py
*     python dofiles/00_shared/02_drop_non_nsu_labels.py --apply
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\06_cpi_panel.do
*
* 00b must precede 01: 01_build_crosswalk.py reads the case-coverage CSV that 00b
* writes. That ordering used to be undocumented because the CSV had no producer at
* all -- see issue #33.

* ---- shared stage, identical to Outcome 1 --------------------------------------
di as res _n ">>> 03_clean_ms.do  (also runs 04_unit_snap and 05_manual_corrections)"
do "00_shared/03_clean_ms.do"

di as res _n ">>> 07_cpi_factor.do"
do "00_shared/07_cpi_factor.do"

* ---- the household side --------------------------------------------------------
* NOTHING YET. 26_psps_extract.do used to run here and is now in archive/: it did
* vocabulary discovery (which NSU labels PSPS households use), that job is finished
* and lives in the crosswalk, and it dropped `hhid' and `subdate' -- so it could serve
* neither the price-level adjustment nor the lookup join. archive/README.md has the
* full account.
*
* 20a_psps_households.do replaces it. It runs BEFORE the numbered chain, for the same
* reason 00a and 00b do: 24_inflate_to_psps_month.do needs the month list it emits.
di as res _n ">>> 20a_psps_households.do"
do "20_psps_retrofitting/20a_psps_households.do"

* `branch' is written now, so it runs rather than being listed as owed. Outcome 2 needs it
* for the same reason Outcome 1 does: 23_branch_conventional.do is built from the 24 cases
* whose (item, unit) pair is conventional everywhere, not from all 123, and the other 99
* join the size-based branch.
di as res _n ">>> 08_branch.do"
do "00_shared/08_branch.do"

* ---- the price ladder ----------------------------------------------------------
* Runs before the branch builds: 21 cuts each case's weights into as many parts as this
* step says the case has convertible price points.
di as res _n ">>> 20_case_price_points.do"
do "20_psps_retrofitting/20_case_price_points.do"

* ---- the three branches --------------------------------------------------------
* Independent of each other. 25 appends them.
di as res _n ">>> 21_branch_size_based.do"
do "20_psps_retrofitting/21_branch_size_based.do"
di as res _n ">>> 22_branch_price_quantity.do"
do "20_psps_retrofitting/22_branch_price_quantity.do"
di as res _n ">>> 23_branch_conventional.do"
do "20_psps_retrofitting/23_branch_conventional.do"

* ---- the price frame -----------------------------------------------------------
* Branch P only. Its grams are what a fixed peso amount bought, so they move with the
* price level; the other two branches measure objects and are left alone.
di as res _n ">>> 24_inflate_to_psps_month.do"
do "20_psps_retrofitting/24_inflate_to_psps_month.do"

* ---- the lookup ----------------------------------------------------------------
di as res _n ">>> 25_lookup.do"
do "20_psps_retrofitting/25_lookup.do"

* ---- the fallback ladder -------------------------------------------------------
* MUST PRECEDE 28. 28 climbs cell -> province -> regional for the households the price
* match cannot serve, and this is what writes those three schedules.
di as res _n ">>> 30_fallback.do"
do "20_psps_retrofitting/30_fallback.do"

* ---- the household answers -----------------------------------------------------
di as res _n ">>> 27_standard_units.do"
do "20_psps_retrofitting/27_standard_units.do"
di as res _n ">>> 28_match_and_convert.do"
do "20_psps_retrofitting/28_match_and_convert.do"
di as res _n ">>> 29_cap.do"
do "20_psps_retrofitting/29_cap.do"

* ---- the single household-level deliverable -------------------------------------
* Appends psps_converted_capped.dta and psps_standard_units.dta -- the two files
* above, which share 23 columns and do not overlap -- and adds the 22 conv_path==3
* rows (not an NSU at all) that ship in neither, so the row count reconciles to
* 20a's own 87,959, not to 87,937. See the do-file's header for the full account.
di as res _n ">>> 31_psps_grams.do"
do "20_psps_retrofitting/31_psps_grams.do"

di as res _n "{hline 78}"
di as res "OUTCOME 2 complete."
di as res "  the lookup     : ${bdeliv}\outcome2_lookup.dta"
di as res "                   ${bdeliv}\outcome2_lookup_noinflation.dta   (#11's variant)"
di as res "  the households : ${bdeliv}\psps_converted_capped.dta   (non-standard units)"
di as res "                   ${bdeliv}\psps_standard_units.dta      (kg / L / stated, #14)"
di as res "  THE SINGLE DELIVERABLE : ${bdeliv}\psps_grams.dta"
di as res "                           ${bdeliv}\psps_grams.csv"
di as res "  refused        : ${btables}\psps_unconvertible.csv"
di as res ""
di as res "  26 IS DELIBERATELY ABSENT. 26_psps_extract.do is archived: it did vocabulary"
di as res "  discovery, that job is finished and lives in the crosswalk, and it dropped"
di as res "  hhid and subdate. 20a replaces it. The gap in the numbering is kept so the"
di as res "  step numbers in issues #19, #21 and #23 still resolve."
di as res ""
di as res "  STILL OPEN, and neither is a build step:"
di as res "    #20  approach A vs B sensitivity -- needs psps_converted_capped.dta"
di as res "    #11  compare the two lookups' household grams; both are now built"
di as res ""
di as res "  THE UNCERTAINTY IS CARRIED THROUGH (#35). Roughly one weighing in seven is"
di as res "  disputed, anchor-flagged or unusable. 08_branch.do defines the four flags"
di as res "  RETIRED 2026-09-17. The lookup and the household rows carry n_g / n_g_used"
di as res "  and d_thin -- how much evidence stands behind a value, not a verdict on it."
di as res "  rung that actually supplied its weight. Nothing is dropped or down-weighted"
di as res "  -- read share_uncertain against n_g and set your own tolerance. A20."
di as res "{hline 78}"
