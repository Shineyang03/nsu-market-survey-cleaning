********************************************************************************
* master_outcome1.do -- builds the REFERENCE SET (Outcome 1)
*
* Outcome 1 publishes grams by size (small / medium / large, or a single weight for
* conventional units) for each province x municipality x item x harmonized NSU unit,
* so that a future enumerator can look up what a named local unit weighs.
*
* HOW TO RUN. From the dofiles/ folder, as a fresh isolated batch process:
*
*     cd "...\Data Cleaning\dofiles"
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do master_outcome1.do
*
* The working directory MUST be dofiles/ -- each step reaches 00_shared/00_globals.do
* by a relative path, because the globals that would give it an absolute one are
* what that file defines.
*
* Each step writes a .dta and the next one reads it, so a step can also be run on
* its own after an earlier one has been run at least once.
*
* THE PYTHON STEPS ARE NOT RUN FROM HERE. 01, 02 and 06 build the crosswalk and the
* CPI panel and change rarely; run them by hand from the project root when their
* inputs change:
*     python dofiles/00_shared/01_build_crosswalk.py
*     python dofiles/00_shared/02_drop_non_nsu_labels.py --apply
*     python dofiles/00_shared/06_cpi_panel.py
*
* AFTER ANY CHANGE, run the claim checker from the project root:
*     python dofiles/90_diagnostics/verify_documented_claims.py
* It re-derives every number recorded in docs/ that no build file produces and
* fails when one has moved.
********************************************************************************

clear all
set more off

di as res _n "{hline 78}"
di as res "OUTCOME 1 -- reference set"
di as res "{hline 78}"

* ---- shared: raw market survey -> one clean, inflation-framed weight per weighing
di as res _n ">>> 03_clean_ms.do  (also runs 04_unit_snap and 05_manual_corrections)"
do "00_shared/03_clean_ms.do"

di as res _n ">>> 07_cpi_factor.do"
do "00_shared/07_cpi_factor.do"

* ---- Outcome 1 ----------------------------------------------------------------
di as res _n ">>> 10_size_assignment.do"
do "10_reference_set/10_size_assignment.do"
di as res _n ">>> 11_size_checks.do"
do "10_reference_set/11_size_checks.do"
di as res _n ">>> 12_publish_reference_set.do"
do "10_reference_set/12_publish_reference_set.do"

di as res _n "{hline 78}"
di as res "OUTCOME 1 complete."
di as res "  reference set : ${btemp}\nsu_reference_set.dta"
di as res "                  ${btables}\nsu_reference_set.xlsx"
di as res "{hline 78}"
