********************************************************************************
**# Correct unit-entry errors in weight/unit   (2-step procedure)
********************************************************************************
* STEP 1  Power-of-ten (log10) magnitude snap, staying WITHIN the recorded
*         dimension. Errors are powers of ten (kg<->g, L<->mL, decimal slips)
*         = integer shifts on a log10 scale; we snap each obs to the nearest
*         integer shift toward a robust item_nsu anchor (item-level sibling
*         anchor as fallback/repair), and flag untrusted/ambiguous rows.
*         PRINCIPLE: a power-of-ten fix never crosses mass<->volume. The
*         corrected unit is fixed by the RECORDED dimension:
*             unit 1 (kg) / 2 (g) -> mass   -> corrected_unit "g"
*             unit 3 (L)          -> volume -> corrected_unit "mL"
*         (corrected_weight is the canonical base: grams for mass, mL for volume)
*
* STEP 2  Mass/volume harmonization. A handful of items were recorded in BOTH
*         mass and volume units. Step 1 keeps each row in its recorded dimension;
*         Step 2 relabels every row of such an item to the ONE true dimension
*         (supplied manually below). Numeric value is unchanged (density ~ 1).
*
* STEP 3  Manual weight-review overrides on the flagged rows: item-independent
*         consistency rules + named-NSU ground truth. Clears flag_review as
*         each slice is resolved.
*
* Inputs required in memory : pull_item ${unitvar} weight unit id
* Key outputs               : corrected_unit corrected_weight base_corr k flag_review
*
* PARAMETERS (globals). 03_clean_ms.do sets all four before calling this file, so on
* the pipeline path the defaults below are never used. They exist only so this step
* can be run on its own, and they therefore default to THE CURRENT BUILD.
*
*   ${unitvar}     unit variable defining the anchor pool  [harmonized_nsu_unit]
*   ${snap_in}     input dataset                           [${btemp}\prelim_nsu_data]
*   ${snap_out}    output dataset                          [${btemp}\standard_weight_unit_correction]
*   ${snap_tables} folder for mixed_dimension_items.xlsx    [${btables}]
*
* WHY THESE DEFAULTS CHANGED. They used to point at ${temp} with cleaned_nsu_unit, to
* "default to the original cleaning.do behaviour". ${temp} is the pre-Aug11 subtree,
* where prelim_nsu_data.dta is dated 2026-07-28, so a standalone run of this file read
* July data, pooled its anchors on a retired unit variable, and wrote its output back
* into the July subtree -- silently, because a stale .dta loads exactly as cleanly as a
* current one. The defaults bought nothing in exchange: the header already recorded
* that this file no longer reproduces the pre-Aug11 output byte for byte, having since
* gained a unit==3 block, a round() and an encode, and lost two saves.
*
* A standalone run now does what the pipeline does. `confirm file' below is what makes
* a wrong path halt instead of loading whatever happens to be there.

* Load the paths, exactly as every other numbered step does. This file used not to,
* which made it the one step that could not run on its own at all: standalone, ${temp}
* and ${btemp} were both EMPTY, so its input path resolved to a bare
* "\prelim_nsu_data" and nothing about the failure said why.
*
* NO `clear all' HERE, unlike the top-level steps. 03_clean_ms.do sets ${unitvar},
* ${snap_in}, ${snap_out} and ${snap_tables} immediately before calling this file, and
* `clear all' would drop all four -- silently reverting the pipeline to the standalone
* defaults below. 00_globals.do itself touches no data, so loading it here is safe
* mid-build.
do "00_shared/00_globals.do"

if "${unitvar}"     == "" global unitvar     "harmonized_nsu_unit"
if "${snap_in}"     == "" global snap_in     "${btemp}\prelim_nsu_data"
if "${snap_out}"    == "" global snap_out    "${btemp}\standard_weight_unit_correction"
if "${snap_tables}" == "" global snap_tables "${btables}"

di as txt "04_unit_snap: anchor pool = pull_item x ${unitvar}"
di as txt "04_unit_snap: in  = ${snap_in}"
di as txt "04_unit_snap: out = ${snap_out}"

* Halt on a missing input rather than letting `use' report it. This step is called
* with a parameterized path, so a typo or an unset global is a real possibility, and
* the failure to guard against is reading the WRONG file, not reading none.
confirm file "${snap_in}.dta"

use "${snap_in}", clear

keep unit weight pull_item ${unitvar} id

* ---- tunable parameters -------------------------------------------------------
local MIN   = 10      // min item_nsu cell size before falling back to item level
local FLOOR = 5       // g/mL: an anchor below this is physically implausible
local SIB   = 1.5     // decades: item_nsu anchor this far from item ref => contaminated
local AMB   = 0.35    // decades: post-snap residual above this => ambiguous snap
local KGMAX = 30      // kg: at or below this a "kg" tick is believed; above it the
                      //     number is read as grams mis-ticked as kg. Empirically
                      //     clean -- the only kg rows in (20,30] are three 25 kg
                      //     rice sacks, and (30,50] is empty.


********************************************************************************
**# STEP 1 -- log10 power-of-ten snap, within recorded dimension
********************************************************************************

* ---- 1a. canonical base magnitude (grams for mass, mL for volume; density ~ 1)
gen double base = weight
replace    base = weight*1000 if unit==1          // kg -> g
replace    base = weight*1000 if unit==3          // L  -> mL
replace    base = .           if !(weight>0 & weight<.)   // drop 0 / missing / .c
gen double log_base = log10(base)

* ---- 1b. item_nsu anchor (median log10) + cell sizes --------------------------
* ORDER DEPENDENCE, stated here and not only in the caller. This anchor is a median
* over every row present in the input, so it is only as good as what was excluded
* BEFORE the file was called. 03_clean_ms.do drops the non-NSU labels first, and
* must keep doing so: mineral water's pools otherwise run from a 500 mL bottle to a
* 10 L gallon, and letting both vote on one item-level reference is what turned a
* 0.01 L reading of a 10 L gallon into 10 mL. Moving that exclusion after this file
* reintroduces the bug with no error.
egen double anchor_in = median(log_base), by(pull_item ${unitvar})
egen long   n_in      = count(log_base),  by(pull_item ${unitvar})
egen long   n_item    = count(log_base),  by(pull_item)

* ---- 1c. item-level sibling reference = median of the per-nsu anchors ----------
egen byte   tag_nsu      = tag(pull_item ${unitvar}) if !missing(log_base)
egen double anchor_item0 = median(anchor_in) if tag_nsu==1, by(pull_item)
egen double anchor_item  = mean(anchor_item0), by(pull_item)   // broadcast to all rows
drop anchor_item0 tag_nsu

* ---- 1d. guards ---------------------------------------------------------------
gen byte flag_small     = (n_in < `MIN')                                   // fell back to item level
gen byte flag_lowanchor = (anchor_in < log10(`FLOOR'))                     // anchor physically implausible
gen byte flag_sibling   = (abs(anchor_in - anchor_item) > `SIB') & !missing(anchor_item)

* ---- 1e. effective anchor: item_nsu normally; item ref if small / contaminated
gen double eff_anchor = anchor_in
replace    eff_anchor = anchor_item if flag_small | flag_lowanchor | flag_sibling

* ---- 1f. snap to nearest integer power of ten ---------------------------------
gen int    k         = round(eff_anchor - log_base)     // 0 => unchanged
gen double base_corr = base * (10^k)
gen double resid     = abs(eff_anchor - log_base - k)   // distance to chosen decade
gen byte   flag_ambiguous = (resid > `AMB') & !missing(resid)

* ---- 1g. review flag (fallback alone is acceptable unless item is also tiny) ---
gen byte flag_review = flag_lowanchor | flag_sibling | flag_ambiguous
replace  flag_review = 1 if flag_small & n_item < `MIN'
replace  flag_review = 1 if missing(base)

* ---- 1h. corrected weight + unit -- unit fixed by RECORDED dimension -----------
gen double corrected_weight = base_corr                 // canonical: grams (mass) / mL (volume)
gen str3 corrected_unit = ""
replace  corrected_unit = "g"  if inlist(unit,1,2) & !missing(base_corr)   // mass   -> grams
replace  corrected_unit = "mL" if unit==3          & !missing(base_corr)   // volume -> millilitres

label var base             "Recorded weight in canonical base (g mass / mL volume)"
label var log_base         "log10(base)"
label var anchor_in        "log10 anchor: median within item_nsu"
label var anchor_item      "log10 anchor: item-level sibling reference"
label var eff_anchor       "log10 anchor actually used for snapping"
label var k                "Applied power-of-ten shift (log10); 0 = unchanged"
label var base_corr        "Corrected weight in canonical base (g/mL) after snap"
label var corrected_unit   "Corrected unit within recorded dimension (mass->g, volume->mL)"
label var corrected_weight "Corrected weight expressed in corrected_unit"
label var flag_review      "1 = anchor untrusted or snap ambiguous -> manual review"

tab k, m
tab corrected_unit, m
tab flag_review, m


********************************************************************************
**# STEP 2 -- mass/volume harmonization for items recorded in BOTH dimensions: READ ONLY, no change to data
********************************************************************************

* items recorded with BOTH a mass unit (kg/g) and a volume unit (L)
gen byte rec_mass = inlist(unit,1,2)
gen byte rec_vol  = (unit==3)
egen byte item_has_mass = max(rec_mass), by(pull_item)
egen byte item_has_vol  = max(rec_vol),  by(pull_item)
gen byte item_mixed = item_has_mass & item_has_vol

* export the mixed-dimension list (mass vs volume row counts) for manual review
preserve
    keep if item_mixed
    collapse (sum) n_mass=rec_mass n_vol=rec_vol, by(pull_item)
    list, noobs sep(0)
    export excel using "${snap_tables}\mixed_dimension_items.xlsx", replace firstrow(variables)
restore

* NOTE: dimension harmonization is intentionally NOT applied. Step 2 only
* records which items were logged in both dimensions (list + xlsx above); each
* row keeps the mass/volume dimension the enumerator recorded (set in Step 1).
* To harmonize later, add one line per mixed item, e.g.:
*   replace corrected_unit = "mL" if pull_item == "Liquor (e.g, whisky, coconut wine)"

drop rec_mass rec_vol item_has_mass item_has_vol item_mixed


* ---- KEEP STEP 1's ANSWER, so STEP 3 can be compared against it ---------------
* STEP 3 below overwrites corrected_weight on every row that has a weight, so without
* this the log10 snap's answer is computed and then destroyed with nothing recording
* what it would have said. The whole open question on issue #18 -- whether the blunt
* magnitude rule is the RIGHT rule -- is unanswerable unless both answers survive to
* the same dataset. These two columns change no result; they are carried through to
* the output and read by 90_diagnostics/snap_step1_vs_step3.py.
gen double w_step1 = corrected_weight
gen byte   review_step1 = flag_review
label var w_step1      "STEP 1 (log10 anchor snap) corrected weight, before STEP 3 overwrote it"
label var review_step1 "STEP 1 flag_review, before STEP 3 cleared it"


********************************************************************************
**# STEP 3 -- magnitude blocks decide the READING; the anchor decides the DECADE
********************************************************************************
* Each block identifies a specific, understood recording error and states what the
* typed number literally means -- "this is kg", "this is already grams", "the unit
* tick is wrong". That reading is `w_block'. Blocks are item-independent
* (condition-based), so the same raw entry always maps to the same reading, and
* corrected_unit is NOT set here -- Steps 1-2 own the unit.
*
* WHAT THE BLOCK READING CANNOT DO, and why this step is no longer the whole rule
* (issue #18 A1). Read the blocks in the CANONICAL BASE that STEP 1 builds -- grams
* for mass, mL for volume, so base = weight*1000 for kg and L, and base = weight for
* g. In those terms every block publishes base, base*1000, or base/1000: it shifts
* the reading by at most three decades, and usually by none.
*
* For the kg and litres blocks the x1000 IS the dimension conversion, so those
* blocks repair nothing whatsoever -- they convert and stop. A liquor long-neck
* typed as `0.001495' L is a three-decade decimal slip: the true reading is 1.495 L
* = 1,495 mL, and the enumerator dropped three places. The litres block converts to
* 1.495 mL and publishes 1 mL. Twenty-one restaurant drinks reached 2 mL the same
* way, and the hand corrections in 05_manual_corrections.do existed only to finish
* the repair the block never started (they used weight * 1000^2, which is the
* conversion and the three-decade repair bundled into one multiplier).
*
* So the block no longer sets the answer on its own. STEP 1's anchor snap -- which
* moves HOWEVER MANY decades the row's own item x unit median implies, not a fixed
* number -- sets the decade, and the block reading is the fallback for when the
* anchor is itself untrustworthy. See the plausibility gate below.

* --- 3a. unit==2 (grams): decimal / same-input-same-output consistency ---------
*   weight >= 10 : already plausible grams          -> read as typed
*   weight <  10 : kg-magnitude misentry            -> read as kg
gen double w_block = .
replace w_block = cond(weight>=10, weight, weight*1000) if unit==2 & !missing(weight)

* --- 3a (litres). Same premise in the volume dimension. A genuine 20 L reading
*   would become 20 mL here; safe only because the one cell with real litre
*   readings (mineral water) is removed upstream by the non-NSU exclusion.
replace w_block = cond(weight>=10, weight, weight*1000) if unit==3 & !missing(weight)

* --- 3b. unit==1 (kg) sub-1 entries are true kg -> grams via x1000 -------------
replace w_block = weight*1000 if unit==1 & weight<1 & !missing(weight)

* --- 3c. unit==1 (kg) plausible bulk kg entries: trust the reading (-> grams) ---
*   THE CEILING MATTERS. It used to be 20, which left (20,1000) handled by nothing:
*   three 25 kg rice sacks fell through to the anchor and published at 2,500 g.
count if inrange(weight,1,`KGMAX') & unit==1 & !missing(weight)
di as txt "3c kg-plausibility: " r(N) " row(s) matched"
replace w_block = weight*1000 if inrange(weight,1,`KGMAX') & unit==1 & !missing(weight)

* --- 3d. unit==1 (kg) but far too big for kg: grams mis-ticked as kg ------------
*   A cabbage does not weigh 1,180 kg. Above `KGMAX' the typed number is already
*   grams and the UNIT tick is the error, so take the reading as it stands.
count if weight > `KGMAX' & unit==1 & !missing(weight)
di as txt "3d kg-implausibility (read as grams): " r(N) " row(s) matched"
replace w_block = weight if weight > `KGMAX' & unit==1 & !missing(weight)


* --- 3e. THE PLAUSIBILITY GATE: which of the two answers is published -----------
* The anchor snap (STEP 1, `base_corr') wins by default, because it is the only one
* of the two that can move more than three decades.
*
* It loses when it returns a physically impossible weight, which happens when the
* ANCHOR ITSELF is contaminated -- a whole cell sharing one recording error makes
* the cell median encode that error, and the snap then faithfully reproduces it.
* Both directions occur in this data and both are caught here:
*
*   too big  2 beer "case" rows -> 1,200,000 g and 7,680,000 g. The cell is almost
*            entirely mis-ticked litres, so the median says a case of beer weighs a
*            tonne. Block reading (1,200 / 7,680 mL) is right.
*   too small 38 fresh-fish rows -> 4-9 g, and 1 cracker row -> 9 g. Same mechanism
*            in the other direction. Block reading (~620 g) is right.
*
* The bounds are set from the data, not from taste: the largest defensible NSU
* purchase in the file is a 25 kg sack of rice, and NOTHING legitimate falls below
* 10 g -- every sub-10 g anchor result is one of the 39 contaminated rows above.
* Widening either bound re-admits a known-wrong value, so they are asserted below.
local WFLOOR = 10       // g/mL: below this an anchor result is contaminated, not small
local WCEIL  = 50000    // g/mL: 2x the largest real purchase (a 25 kg rice sack)

* Compare on the ROUNDED value. corrected_weight is rounded to whole g/mL below,
* and float arithmetic puts 0.01 L * 1000 at 9.9999998 -- which is 10 mL, not a
* sub-floor value. Testing the raw product makes the gate fire on precision noise.
gen byte anchor_implausible = !missing(base_corr) & ///
    (round(base_corr,1) < `WFLOOR' | round(base_corr,1) > `WCEIL')
gen byte block_implausible = !missing(w_block) & ///
    (round(w_block,1) < `WFLOOR' | round(w_block,1) > `WCEIL')

count if anchor_implausible & !missing(w_block)
di as txt "3e anchor overruled by the block reading: " r(N) " row(s)"

replace corrected_weight = base_corr if !missing(base_corr) & !anchor_implausible
replace corrected_weight = w_block   if  anchor_implausible & !missing(w_block)
replace corrected_weight = w_block   if  missing(base_corr) & !missing(w_block)

replace flag_review = 0 if !missing(corrected_weight) & !missing(weight)

* The gate must leave nothing implausible behind. If this fires, a cell has become
* contaminated in a way the bounds do not cover -- widen nothing until you know why.
* WHERE BOTH ANSWERS ARE IMPLAUSIBLE the row is a data problem, not a rule problem,
* and the gate has nothing to choose between. Those rows stay in the review queue
* instead of stopping the build -- they were equally wrong before this change, so
* crashing here would block the pipeline on a defect it did not introduce.
* Today: 6 mineral-water rows typed as 0.007-0.01 L, i.e. 7-10 mL of drinking water.
* This is the same contaminated cell STEP 1's header warns about; the non-NSU
* exclusion removes most of it but not these.
replace flag_review = 1 if anchor_implausible & block_implausible
count if anchor_implausible & block_implausible
di as txt "3e both answers implausible -> left in review queue: " r(N) " row(s)"
if r(N) > 0 {
	list id pull_item ${unitvar} unit weight base_corr w_block ///
		if anchor_implausible & block_implausible, noobs sep(0)
}

* The gate must never PICK an implausible answer when a plausible one was on offer.
* That would be a defect in the gate itself, so it hard-stops.
count if !missing(corrected_weight) & !(anchor_implausible & block_implausible) & ///
    (round(corrected_weight,1) < `WFLOOR' | round(corrected_weight,1) > `WCEIL')
assert r(N) == 0

drop anchor_implausible block_implausible


tab flag_review, m
count if flag_review==1

		 
********************************************************************************
**# STEP 4 -- manual weight-review overrides on flagged rows
********************************************************************************

* RETIRED. This rescaled kg rows with weight >= 1000 by x10; 3d now covers every kg
* row above `KGMAX' and states the invariant directly. The old pair also carried a
* latent bug -- its second line tested corrected_weight, which the first line had
* just mutated, so the guard could never fire and the log read "(0 real changes
* made)".

* --- THE REVIEW QUEUE ---------------------------------------------------------
* Anything still carrying flag_review is a row the rules above could not resolve, and
* it must leave the pipeline as an artefact a human can open. This previously called
* `br', which is interactive-only and silently does nothing in batch ("request
* ignored because of batch mode" in the log); the next line then cleared every flag,
* so 22 rows were accepted unseen and three of them were wrong.
count if flag_review == 1
di as res "UNRESOLVED rows sent to the review queue: " r(N)
if r(N) > 0 {
	preserve
		keep if flag_review == 1
		keep id pull_item ${unitvar} weight unit base base_corr k corrected_weight ///
		     corrected_unit flag_small flag_lowanchor flag_sibling flag_ambiguous
		export excel using "${snap_tables}/unit_correction_review_queue.xlsx", ///
			replace firstrow(variables)
		di as txt "  exported to unit_correction_review_queue.xlsx"
	restore
}
		
replace flag_review = 0 if flag_review == 1 

drop flag_review flag*
drop base log_base base_corr 
drop k
* w_step1 and review_step1 deliberately survive the drops above -- neither name
* starts with `flag', so `drop flag*' does not reach review_step1.

sort id

replace corrected_weight = round(corrected_weight,1)
* Fix g=1 / mL=2 EXPLICITLY. `encode' would assign these codes from the alphabetical
* order of whatever strings happen to be present, so a build containing only volume
* rows would silently number mL as 1 -- inverting the eight conditions in
* 05_manual_corrections.do and five in 03_clean_ms.do that hard-code these values.
* The codes are part of the pipeline's contract, so they are declared, not inferred.
label define correct_unit_lbl 1 "g" 2 "mL", replace
gen byte correct_unit = .
replace  correct_unit = 1 if corrected_unit == "g"
replace  correct_unit = 2 if corrected_unit == "mL"
label values correct_unit correct_unit_lbl
label var correct_unit "Corrected unit: 1 = g (mass), 2 = mL (volume)"

* An unmapped non-empty string means a third unit appeared and every downstream
* condition keyed on 1/2 is now silently incomplete.
count if missing(correct_unit) & !missing(corrected_unit) & corrected_unit != ""
assert r(N) == 0
order correct_unit, after(corrected_unit)
drop corrected_unit
order id, last


* w_step1 / review_step1 ride along so the STEP 1 vs STEP 3 comparison is available
* downstream without re-running the snap. They are diagnostics: nothing in the build
* reads them, and 03_clean_ms.do renames only correct_* -> corrected_*.
replace w_step1 = round(w_step1, 1)
keep correct* w_step1 review_step1 id

* Deterministic row order: `id' is unique, so this leaves no ties for the sort
* seed to break. Without it the saved file's ORDER varies between runs.
sort id

save "${snap_out}", replace

