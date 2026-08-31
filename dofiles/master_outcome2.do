********************************************************************************
* master_outcome2.do -- PSPS RETRO-FITTING (Outcome 2)
*
* NOT YET BUILT. This file is the skeleton, so that the order of the steps and what
* each one owes is written down in one place rather than rediscovered. Running it
* today gets you the shared stage and the household extract, then stops.
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
* Issue #7 carries the full skeleton with what each step owes and what blocks it.
********************************************************************************

clear all
set more off

di as res _n "{hline 78}"
di as res "OUTCOME 2 -- PSPS retro-fitting  (PARTIAL: steps 20-30 not written)"
di as res "{hline 78}"

* ---- shared stage, identical to Outcome 1 --------------------------------------
di as res _n ">>> 03_clean_ms.do  (also runs 04_unit_snap and 05_manual_corrections)"
do "00_shared/03_clean_ms.do"

di as res _n ">>> 07_cpi_factor.do"
do "00_shared/07_cpi_factor.do"

* ---- the household side --------------------------------------------------------
di as res _n ">>> 26_psps_extract.do"
do "20_psps_retrofitting/26_psps_extract.do"

di as res _n "{hline 78}"
di as res "STOPPING HERE. The steps below are not written yet:"
di as res ""
di as res "  20_case_price_points.do   how many price points a case gets, after the"
di as res "                            PHP20 union-merge on pooled spellings   [#21 DECIDED]"
di as res "  21_branch_size_based.do   cut pooled weights into that many parts  [#23]"
di as res "  22_branch_price_quantity.do   w_g per case x pull_price            [#21 DECIDED]"
di as res "  23_branch_conventional.do     one weight per case                  [#28 OPEN]"
di as res "  24_inflate_to_psps_month.do   w_g_m, v_g_m per interview month     [#5]"
di as res "  25_lookup.do                  append the three branches            [#11]"
di as res "  27_standard_units.do          kg/L answers convert directly        [#14]"
di as res "  28_match_and_convert.do       p_h, nearest point, CF_h, grams_h    [#5]"
di as res "  29_cap.do                     clamp p_h/p_g, flag                  [#19, t unset]"
di as res "  30_fallback.do                cases with no MS weight of their own [#30 BLOCKING]"
di as res ""
di as res "  30 is the blocker, not 29: one PSPS observation in six needs a fallback,"
di as res "  and borrowing weights across municipalities is unsolved -- #28 measured the"
di as res "  same unit varying 14x between municipalities in one province."
di as res "{hline 78}"
