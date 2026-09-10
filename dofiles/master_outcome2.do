********************************************************************************
* master_outcome2.do -- PSPS RETRO-FITTING (Outcome 2)
*
* NOT YET BUILT. This file is the skeleton, so that the order of the steps and what
* each one owes is written down in one place rather than rediscovered. Running it
* today gets you the shared stage, then stops -- there is no Outcome 2 code yet.
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
di as res "OUTCOME 2 -- PSPS retro-fitting  (PARTIAL: steps 20-30 not written)"
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

di as res _n "{hline 78}"
di as res "STOPPING HERE. The steps below are not written yet."
di as res "This list is abbreviated; dofiles/README.md is the source for what each step"
di as res "owes and what blocks it, and docs/implicit_assumptions.md for the thresholds."
di as res ""
di as res "  20_case_price_points.do   how many price points a case gets, after the"
di as res "                            PHP20 union-merge on pooled spellings  [#21 sec2; ARM OPEN #23]"
di as res "  21_branch_size_based.do   cut pooled weights into that many parts [#23; #21 sec5.3]"
di as res "  22_branch_price_quantity.do   w_g per case x pull_price           [#21 sec2 rows 5-6]"
di as res "  23_branch_conventional.do     one weight per case -- the 24 cases whose"
di as res "                                (item,unit) pair is conventional everywhere"
di as res "                                [#28 DECIDED, not built]"
di as res "  24_inflate_to_psps_month.do   w_g_m, v_g_m per interview month    [#5 CLOSED]"
di as res "  25_lookup.do                  append the three branches           [#11]"
di as res "  27_standard_units.do          kg/L answers convert directly       [#14]"
di as res "  28_match_and_convert.do       p_h, nearest point, CF_h, grams_h   [#5 CLOSED]"
di as res "  29_cap.do                     clamp p_h/p_g, flag                 [#19, t unset]"
di as res "  30_fallback.do                cases with no MS weight of their own [#30 BLOCKING]"
di as res ""
di as res "  30 is the blocker, not 29: one PSPS observation in six needs a fallback,"
di as res "  and borrowing weights across municipalities is unsolved -- #28 measures the"
di as res "  same unit varying up to 6.7x between municipalities. That figure WAS 14x;"
di as res "  it fell when the snap adjudication removed a contaminated-anchor artefact,"
di as res "  so re-read #30's cost argument against 6.7x before deciding it."
di as res ""
di as res "  CARRY THE UNCERTAINTY THROUGH. Every weighing now has flags saying whether"
di as res "  its weight was corrected and whether it is disputed, anchor-flagged or"
di as res "  unusable -- weight_correction_report.csv, written by"
di as res "  90_diagnostics/report_weight_corrections.py. A conversion factor built on a"
di as res "  disputed weight should say so; 1,742 weighings carry some uncertainty."
di as res "{hline 78}"
