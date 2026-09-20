********************************************************************************
* 07_human_validation_draw.do -- the set a person reads, to establish ground truth
*
* WHY THIS EXISTS, AND WHY IT REPLACES THE EARLIER YARDSTICK.
*
* 06_resolution_compare.do scored readings against the TYPED weight. That is backwards.
* The photographs are the ground truth against which the typed data is being checked;
* scoring a photograph against the typed value makes the evidence answerable to the
* thing it is meant to judge, and it cannot produce an accuracy figure -- a perfect
* reader would score 100% minus the officer mis-typing rate, which is the unknown being
* sought. Those scores are agreement-with-the-officer and nothing more.
*
* THE ONLY NON-CIRCULAR GROUND TRUTH IS A PERSON READING THE SAME DISPLAY. This file
* draws the set they read.
*
* NOTHING FROM THE TYPED DATA REACHES THE HUMAN, and nothing from the model readings
* does either. The workbook carries an image and a sequence number. A human shown
* "the model read 0.095, confirm?" is being asked to agree, not to read, and their
* answer would inherit exactly the error it exists to detect.
*
* THIS IS A DELIBERATE DEPARTURE FROM docs/adjudication_playbook.md, which says to
* pre-fill every verdict because confirm/override is cheap and decide-from-scratch is
* not. That rule is right when a reviewer is ADJUDICATING a judgement call. It is wrong
* here, because the human is not adjudicating -- they are the measuring instrument, and
* pre-filling an instrument with the answer destroys it. The playbook's efficiency
* argument is real, and the cost is accepted: 40 reads from scratch.
*
* POPULATION. Images where BOTH calib_v1 readers agreed a scale is present -- there has
* to be a display for a person to read. Stratified, so the awkward cells are
* represented rather than swamped by the easy ones.
*
* THE MODEL READINGS ARE CARRIED IN THIS FILE but must NOT be written into the
* workbook. 08_score_against_human.do joins them back afterwards. They are here so the
* scoring step has one input rather than three.
*
* INPUT   ${imgqc}\reconcile_calib_v1.csv
* OUTPUT  ${imgtables}\human_validation_ids.csv
*
* RUN, from the "image checking/dofiles" folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 07_human_validation_draw.do
********************************************************************************

clear all
do "00_photo_globals.do"

local SEED    20260920
local N_TOTAL 40

set seed `SEED'

import delimited "${imgqc}/reconcile_calib_v1.csv", clear varnames(1) ///
	delimiter(",") encoding("utf-8") stringcols(_all)
destring id scale_present ag_scale, replace

* A display must be present for a person to read one. Both readers agreeing it is
* there is the weakest claim that still guarantees that.
keep if scale_present == 1

qui count
local n_pool = r(N)
di as txt _n "images where both readers agree a scale is present: `n_pool'"

di as txt _n "available by stratum:"
tab stratum

* Proportional-ish but floored: every stratum that has any images contributes at least
* two, so a cell cannot vanish from the validation set just for being small. The
* remainder is filled at random across the pool.
gen double u = runiform()
gsort stratum u id
by stratum: gen long k = _n

gen byte pick = (k <= 2)
qui count if pick
local n_floor = r(N)
local n_rest = `N_TOTAL' - `n_floor'

if `n_rest' > 0 {
	gsort pick u id
	qui replace pick = 1 if !pick & sum(!pick) <= `n_rest'
}

keep if pick
qui count
local n_draw = r(N)

di as res _n "drawn by stratum:"
tab stratum

* Carried for the scoring step, NOT for the workbook. make_validation_workbook.py
* writes only the image and a sequence number; see this file's header.
keep id stratum display_texthaiku display_textsonnet photo_typesonnet ///
     raw_weight rawtick corrected_weight
gen int  seed = `SEED'
gen str16 draw_tag = "human_v1"
gsort id

export delimited using "${imgtables}\human_validation_ids.csv", replace

di as res _n "07_human_validation_draw complete: `n_draw' images"
di as txt "draw: ${imgtables}\human_validation_ids.csv"
di as txt _n "NEXT: python scripts/make_validation_workbook.py"
di as txt "The workbook must carry NO typed weight and NO model reading."
