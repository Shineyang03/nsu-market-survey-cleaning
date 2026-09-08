********************************************************************************
* measure_anchor_keying.do -- what does the snap's anchor pool cost us?
*
* 04_unit_snap.do pools its anchor and all four referee rungs on
* pull_item x ${unitvar}. Today ${unitvar} is harmonized_nsu_unit, which creates a
* dependency worth naming: the harmonized unit comes from the crosswalk, the snap
* uses it to correct weights, and the fold decisions behind the crosswalk were
* themselves taken from corrected weights. That is a loop, and it is why the fold
* rule is forbidden from reading a build output (issue #33).
*
* Pointing the anchor at pull_nsu_unit -- the RAW label -- breaks the loop: the snap
* would then depend on nothing the crosswalk produces, so the fold could legitimately
* read corrected weights and the harmonization could respond to new evidence.
*
* THIS FILE MEASURES THE COST OF THAT, and changes nothing permanently. It runs the
* normal Outcome 1 chain with the anchor re-keyed, writes the reference set to a
* SEPARATE folder, and leaves the live build for the caller to restore.
*
* NOT A REPLACEMENT for the restructure. Re-keying the anchor is necessary but not
* sufficient: 05_manual_corrections.do references harmonized_nsu_unit 25 times, so a
* pipeline that truly ran the snap before harmonization would need those re-keyed too.
* What this answers is the prior question -- does the re-key move published weights
* enough to matter?
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\measure_anchor_keying.do
*
* Pass a different pool by setting the global first; the three candidates are
* pull_nsu_unit (raw), cleaned_nsu_unit (what the pre-Aug11 build used), and
* harmonized_nsu_unit (current).
*
* AFTER RUNNING, the live build artifacts have been overwritten. Restore them from a
* backup or re-run master_outcome1.do.
********************************************************************************

clear all
set more off

if "${keying}" == "" global keying "pull_nsu_unit"

di as res _n "{hline 78}"
di as res "ANCHOR KEYING MEASUREMENT: pooling on pull_item x ${keying}"
di as res "{hline 78}"

* This is the whole intervention: preset ${unitvar} so 03_clean_ms.do's default does
* not fire. Everything downstream is the unmodified chain.
global unitvar "${keying}"

do "00_shared/03_clean_ms.do"
do "00_shared/07_cpi_factor.do"
do "10_reference_set/10_size_assignment.do"
do "10_reference_set/11_size_checks.do"
do "10_reference_set/12_publish_reference_set.do"

di as res _n "{hline 78}"
di as res "done -- reference set built with anchor pool = pull_item x ${keying}"
di as res "The live build artifacts are now this variant, NOT the published build."
di as res "{hline 78}"
