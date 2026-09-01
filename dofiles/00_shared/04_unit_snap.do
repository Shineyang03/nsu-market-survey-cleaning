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

* pull_province / pull_municipal_city / item_nsu_hetero_type are needed by the
* adjudication in STEP 3e (the cell and the province-level referee pools). They are
* dropped again by the `keep' just before the save, so they do not reach any output.
keep unit weight pull_item ${unitvar} id pull_province pull_municipal_city item_nsu_hetero_type

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

* NOTE: dimension harmonization is not applied HERE, but it IS applied -- later,
* and somewhere else. Do not add it in this file.
*
* WHERE IT HAPPENS, and why the ordering looks odd. 03_clean_ms.do calls this file
* (its line 555), THEN builds the per-item g/mL verdicts in `diagnostics' (its
* ~line 592), THEN calls 05_manual_corrections.do (its line 629), whose section 1
* applies them. So at the moment the xlsx above is written the verdicts do not yet
* exist, and this list is a snapshot of the RAW recording rather than of the
* corrected state. That is why it is longer than
* mixed_dimension_no_verdict.xlsx: 7 items are recorded in both dimensions, 5 of
* them are now verdicted, and only 2 -- drinks at restaurant and ice cream -- are
* genuinely left keeping whatever dimension the enumerator ticked.
*
* AN EARLIER VERSION OF THIS NOTE SAID to harmonize by adding
* `replace corrected_unit = "mL" if pull_item == "Liquor..."' here. Liquor is one of
* the 5 items 05 section 1 ALREADY relabels, so following that would apply the
* correction twice. 05's own header states the general form of this hazard: two
* corrections on one row is a 1000x error with no error message.
*
* To change a verdict, edit `diagnostics' in 03_clean_ms.do. Section 1 of 05 asserts
* its row counts per branch (15 g, 251 mL), so a verdict that stops matching fails
* the build instead of passing silently.

drop rec_mass rec_vol item_has_mass item_has_vol item_mixed


* ---- KEEP STEP 1's ANSWER, so the adjudication can be audited -------------------
* STEP 3e picks between this and the block reading, so without carrying STEP 1's answer
* forward the rejected candidate is computed and then destroyed, and no one can see what
* the other rule would have said. These two columns change no result.
*
* Read by 90_diagnostics/snap_sense_check.py, which is what a reviewer opens to judge
* the rule. (An earlier snap_step1_vs_step3.py did the same comparison and is archived:
* it predates the adjudication and could not report which rule decided a row.)
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


********************************************************************************
**# STEP 3e -- ADJUDICATION: which of the two answers is published
********************************************************************************
* Two candidate weights exist for every row: `base_corr' from STEP 1's anchor snap,
* and `w_block' from the STEP 3 blocks. This decides between them.
*
* THE RULES BELOW COME FROM A MANUAL REVIEW of every disputed row, recorded on issue
* #18. They are not a guess at what looks right -- read that comment before changing
* any threshold here. The governing findings were:
*
*   - proximity to a local median should be judged in ORDERS OF MAGNITUDE, not in
*     absolute grams. A 255 g reading against a 152.5 g cell median is the same
*     decade; a 25 g reading is a decade out, and the decade is what the snap gets
*     wrong. Absolute distance can prefer the value that is 10x too small.
*   - a raw weight recorded as 0.xxx repeatedly WITHIN one cell is what enumerators
*     in that market wrote on purpose, not a one-off slip, so the block reading (which
*     just restates the typed number in canonical units) is the better reading there.
*   - the log-10 snap tends to UNDERESTIMATE, so more rows should move off STEP 1 than
*     the plausibility bounds alone would move.
*
* PRECEDENCE, decided on review: the median comparison governs wherever a usable
* median exists. The decimal-structure and whole-number readings fill the gaps -- they
* are corroborating patterns, not overrides, and firing them against an explicit local
* median would be substituting a heuristic for a measurement.
*
*   1. referee median exists  -> publish whichever candidate is closer in log10 terms
*   2. no median, cell shows a shared sub-1 decimal structure  -> block
*   3. no median, raw weight is a whole number                 -> block
*   4. nothing fires                                           -> anchor
*   5. plausibility floor/ceiling, applied LAST to all of the above

* ---- 3e-i. the referee pools, built only from rows where the two rules AGREE ------
* Rows where anchor and block already agree carry no information about which rule is
* better, which is exactly what makes their median a usable yardstick for the rows
* that disagree. Compared on the ROUNDED values, as the published weight is.
gen byte _agree = (round(base_corr,1) == round(w_block,1)) ///
                  & !missing(base_corr) & !missing(w_block)
gen double _agreed = base_corr if _agree

* the cell: province x municipality x item x harmonized unit
egen double _cell_med    = median(_agreed), by(pull_province pull_municipal_city pull_item ${unitvar})
egen long   _cell_nagree = count(_agreed),  by(pull_province pull_municipal_city pull_item ${unitvar})

* the province-level fallbacks for thin cells, hetero-group first then without it
egen double _ph_med = median(_agreed), by(pull_province pull_item ${unitvar} item_nsu_hetero_type)
egen long   _ph_n   = count(_agreed),  by(pull_province pull_item ${unitvar} item_nsu_hetero_type)
egen double _p_med  = median(_agreed), by(pull_province pull_item ${unitvar})
egen long   _p_n    = count(_agreed),  by(pull_province pull_item ${unitvar})

* NAGREE = how many agreeing rows a pool needs before it can referee. Below this the
* median is one or two readings and cannot adjudicate a decade.
local NAGREE = 5

gen double _ref_med = .
gen str12  _ref_src = ""
replace _ref_med = _cell_med if _cell_nagree > `NAGREE' & !missing(_cell_med)
replace _ref_src = "cell"    if _cell_nagree > `NAGREE' & !missing(_cell_med)
replace _ref_med = _ph_med   if missing(_ref_med) & _ph_n > `NAGREE' & !missing(_ph_med)
replace _ref_src = "prov_hetero" if missing(_ref_src) & !missing(_ref_med)
replace _ref_med = _p_med    if missing(_ref_med) & _p_n  > `NAGREE' & !missing(_p_med)
replace _ref_src = "prov"    if missing(_ref_src) & !missing(_ref_med)

* ---- 3e-ii. rule 1: closer in log10 terms wins -----------------------------------
gen byte _pick_block = .
replace _pick_block = (abs(log10(w_block/_ref_med)) < abs(log10(base_corr/_ref_med))) ///
    if !missing(_ref_med) & _ref_med > 0 ///
     & !missing(w_block) & w_block > 0 & !missing(base_corr) & base_corr > 0
gen str16 _rule = "log10 median" if !missing(_pick_block)

* ---- 3e-iii. rule 2: a shared sub-1 decimal structure inside the cell -------------
* Sub-1 decimals repeated within one cell are a market's recording convention, not a
* slip. Requires at least two such rows in the cell -- a single 0.xxx reading is the
* one-off this does NOT cover.
gen byte _sub1 = (weight > 0 & weight < 1) & !missing(weight)
egen long _cell_sub1 = total(_sub1), by(pull_province pull_municipal_city pull_item ${unitvar})
replace _pick_block = 1 if missing(_pick_block) & _sub1 & _cell_sub1 >= 2
replace _rule = "cell decimals" if missing(_rule) & !missing(_pick_block)

* ---- 3e-iv. rule 3: a whole number was typed as-is --------------------------------
replace _pick_block = 1 if missing(_pick_block) & !missing(weight) & weight == round(weight)
replace _rule = "whole number" if missing(_rule) & !missing(_pick_block)

* ---- 3e-v. default: the anchor ----------------------------------------------------
replace _pick_block = 0 if missing(_pick_block)
replace _rule = "anchor default" if missing(_rule)

* ---- 3e-vi. publish, then the plausibility floor/ceiling LAST ---------------------
* The bounds are the last word regardless of which rule won: an answer outside them is
* physically impossible, and where the OTHER candidate is inside them it is published
* instead. This is what catches a contaminated anchor pool -- 2 beer "case" rows
* reaching 1.2M g, and fresh-fish rows falling to 4-9 g -- and it now equally catches a
* block reading the rules above would otherwise have adopted.
local WFLOOR = 10       // g/mL: below this a result is contaminated, not small
local WCEIL  = 50000    // g/mL: 2x the largest real purchase (a 25 kg rice sack)

gen double _chosen = cond(_pick_block == 1, w_block, base_corr)
gen double _other  = cond(_pick_block == 1, base_corr, w_block)

gen byte _chosen_bad = !missing(_chosen) & (round(_chosen,1) < `WFLOOR' | round(_chosen,1) > `WCEIL')
gen byte _other_ok   = !missing(_other)  & (round(_other,1) >= `WFLOOR' & round(_other,1) <= `WCEIL')

count if _chosen_bad & _other_ok
di as txt "3e plausibility gate overruled the chosen rule on " r(N) " row(s)"
replace _rule   = "gate override" if _chosen_bad & _other_ok
replace _chosen = _other          if _chosen_bad & _other_ok

replace corrected_weight = _chosen if !missing(_chosen)
replace corrected_weight = _other  if missing(_chosen) & !missing(_other)
replace flag_review = 0 if !missing(corrected_weight) & !missing(weight)

* what each rule decided, for the log and for the report on issue #18
di as res _n "3e adjudication -- rule that decided each row:"
tab _rule, m
di as res "3e adjudication -- referee pool used:"
tab _ref_src, m
di as res "3e adjudication -- block adopted vs anchor kept:"
tab _pick_block, m

* Nothing implausible may survive where a plausible alternative existed. If this
* fires the bounds no longer cover a case they used to -- widen nothing until you
* know which.
count if !missing(corrected_weight) ///
       & (round(corrected_weight,1) < `WFLOOR' | round(corrected_weight,1) > `WCEIL') ///
       & _other_ok
assert r(N) == 0

* KEEP the deciding rule and the referee pool. Which rule set a weight is the first
* thing anyone asks of a corrected value, and reconstructing it afterwards means
* re-implementing STEP 3e outside the pipeline -- the duplication this project keeps
* getting bitten by. 90_diagnostics/report_weight_corrections.py reads these, and they
* are what makes a corrected weight explainable in the pipeline explorer.
encode _rule, gen(snap_rule)
label var snap_rule "STEP 3e rule that set corrected_weight"
encode _ref_src, gen(snap_referee)
label var snap_referee "pool whose median refereed the choice (blank = no usable pool)"
gen byte snap_block = (_pick_block == 1)
label var snap_block "1 = published the block reading, 0 = published the anchor snap"

drop _agree _agreed _cell_med _cell_nagree _ph_med _ph_n _p_med _p_n ///
     _ref_med _ref_src _pick_block _sub1 _cell_sub1 _rule _chosen _other ///
     _chosen_bad _other_ok

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
keep correct* w_step1 review_step1 snap_rule snap_referee snap_block id

* Deterministic row order: `id' is unique, so this leaves no ties for the sort
* seed to break. Without it the saved file's ORDER varies between runs.
sort id

save "${snap_out}", replace

