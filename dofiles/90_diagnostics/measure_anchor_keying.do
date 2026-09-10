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
* THIS FILE MEASURES THE COST OF THAT AND TOUCHES NOTHING LIVE. It sets ${build_name}
* so the whole variant build -- every .dta, every table -- goes to its own subtree under
* outputs/, and the published build is never opened for writing. The first version of
* this measurement did overwrite the live artifacts and relied on a hand-made backup to
* put them back; that worked, but a safeguard a human has to remember is not one.
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
* Pass a different pool by setting ${keying} first; the three candidates are
* pull_nsu_unit (raw), cleaned_nsu_unit (what the pre-Aug11 build used), and
* harmonized_nsu_unit (current).
*
* OUTPUT  ${output}\anchor_<keying>\deliverables\nsu_reference_set.dta   and the rest of
*         the variant build. The published build under build is untouched,
*         so the two can be diffed afterwards with no restore step.
********************************************************************************

clear all
set more off

if "${keying}" == "" global keying "pull_nsu_unit"

* Set BEFORE 00_globals.do runs, so every derived path points at the variant subtree.
* This has to happen here rather than after the first `do' of the globals, because that
* is where ${build}, ${btemp} and ${btables} are computed.
global build_name "anchor_${keying}"

di as res _n "{hline 78}"
di as res "ANCHOR KEYING MEASUREMENT: pooling on pull_item x ${keying}"
di as res "  variant build subtree : ${build_name}"
di as res "  the published build under build is NOT written to"
di as res "{hline 78}"

* The whole intervention: preset ${unitvar} so 03_clean_ms.do's default does not fire.
* Everything downstream is the unmodified chain.
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
