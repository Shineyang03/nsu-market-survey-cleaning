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
* KGMAX IS NOT DEFINED HERE ANY MORE. It belongs to the block reading, which moved to
* 00_shared/03a_block_reading.do so it is computed before the harmonization merge; the
* threshold moved with the computation so the rule has one home. Nothing in this file
* reads it -- STEP 3a-3d now merges w_block in. Do not re-add it as a convenience:
* two files disagreeing about where a threshold lives is how the block reading came to
* have three implementations in the first place.


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

* --- 3a-3d. THE BLOCK READING IS MERGED IN, NOT COMPUTED HERE ------------------
* The five branches that build it (grams, litres, and the three kg bands around
* KGMAX) moved to 00_shared/03a_block_reading.do, which 03_clean_ms.do runs BEFORE it
* merges the harmonization crosswalk.
*
* Nothing about the computation changed and nothing about it depended on this file. What
* changed is its POSITION, and that is the entire point. The fold test
* (90_diagnostics/validate_folds.do --weight=block) asks whether two raw labels folded
* into one harmonized_nsu_unit actually weigh the same. It cannot answer that from the
* published weight, because STEP 1 below snaps that weight toward the median of a pool
* keyed on ${unitvar} -- harmonized_nsu_unit -- so the grouping under test helped produce
* the evidence for it. Computing the block reading upstream of the merge makes its
* independence structural: everything the fold test reads is complete before a single
* fold has been applied.
*
* KGMAX moved with it. There is one definition of the rule and one definition of the
* threshold, in the same file.
* NOT assert(3). block_reading is built from the raw MS BEFORE the crosswalk merge and
* before the non-NSU trim, so it legitimately holds rows this file no longer has -- that
* asymmetry is the whole point of computing it upstream. What must hold is the other
* direction: every row the snap is about to adjudicate has to carry a reading.
merge 1:1 id using "${btemp}\block_reading", keepusing(w_block) gen(_m_block)
count if _m_block == 1
if r(N) > 0 {
	di as err "04_unit_snap.do: " r(N) " row(s) have no block reading."
	di as err "block_reading is built from the raw MS in 03a; a row here that is not"
	di as err "there means an id was created after 03a ran."
	exit 459
}
qui count if _m_block == 2
di as txt "3a-3d: " r(N) " block reading(s) belong to rows dropped upstream of the snap"
drop if _m_block == 2
drop _m_block

* The merge is asserted match-only above, so a missing w_block here means the reading
* itself came out missing -- which STEP 3e cannot adjudicate against. Every row with a
* usable weight must carry one.
count if !missing(weight) & weight > 0 & missing(w_block)
if r(N) > 0 {
	di as err "04_unit_snap.do: " r(N) " row(s) have a weight but no block reading."
	di as err "03a_block_reading.do covers unit codes 1/2/3 only -- check its exit 459."
	exit 459
}


********************************************************************************
**# STEP 3e -- ADJUDICATION: which of the two answers is published
********************************************************************************
* Two candidate weights exist for every row: `base_corr' from STEP 1's anchor snap,
* and `w_block' from the STEP 3 blocks. This decides between them.
*
* THE WHOLE OF THIS SECTION IS A FALLBACK NOW. 3e-v-b publishes the block reading on
* every row where it is a possible reading, so what follows decides a row only when the
* block reading is IMPOSSIBLE -- which, since 03a_block_reading.do gained the
* misplaced-decimal repair, is no rows at all on this vintage. Read it as the path a
* future vintage takes, not as the path this build took.
*
*   1. referee median exists  -> publish whichever candidate is closer in log10 terms
*   2. THE BLOCK READING GOVERNS, unless it is outside the plausibility bounds  (3e-v-b)
*   3. plausibility floor/ceiling, applied LAST to whatever survives
*
* WHAT USED TO BE HERE, and why it is gone. Three corroborating rules -- a shared sub-1
* decimal structure, a whole number typed as-is, a final default -- plus a narrow
* override letting a row's own cell overrule a province referee. All four could only set
* the choice TO the block reading, which 3e-v-b now does unconditionally, so none of them
* could change a published weight. See the note where they used to sit.
*
* THE ONE SURVIVING FINDING from the #18 review, because it still governs rule 1:
* proximity to a local median is judged in ORDERS OF MAGNITUDE, not in absolute grams.
* A 255 g reading against a 152.5 g cell median is the same decade; a 25 g reading is a
* decade out, and the decade is what the snap gets wrong. Absolute distance can prefer
* the value that is 10x too small.

* ---- 3e-i. the referee pools, built only from rows where the two rules AGREE ------
* Rows where anchor and block already agree carry no information about which rule is
* better, which is exactly what makes their median a usable yardstick for the rows
* that disagree. Compared on the ROUNDED values, as the published weight is.
gen byte _agree = (round(base_corr,1) == round(w_block,1)) ///
                  & !missing(base_corr) & !missing(w_block)
gen double _agreed = base_corr if _agree

* THE REFEREE IS HETERO-AWARE, and that ordering is the whole point of the ladder.
*
* A cell median pooled ACROSS hetero-groups is biased DOWN for the larger groups: a
* case holding smalls, mediums and larges has a median near its middle, so a large's
* block reading looks a decade too big against it and the anchor -- which is the block
* reading divided by ten -- wins by being closer to a number that describes smaller
* units. Measured before changing anything: of the 338 disputed rows with a usable cell
* median, a hetero-specific median differs on 316 and FLIPS the chosen rule on 92, of
* which 88 flip toward the block reading. That asymmetry is the bias, not noise.
*
* So the primary referee is the cell WITHIN a hetero-group, and the pooled cell is the
* first fallback for groups too thin to referee themselves. Raised on the second manual
* review of snap_sense_check.xlsx; see issue #18.
egen double _ch_med = median(_agreed), by(pull_province pull_municipal_city pull_item ${unitvar} item_nsu_hetero_type)
egen long   _ch_n   = count(_agreed),  by(pull_province pull_municipal_city pull_item ${unitvar} item_nsu_hetero_type)

* the cell pooled across hetero-groups
egen double _cell_med    = median(_agreed), by(pull_province pull_municipal_city pull_item ${unitvar})
egen long   _cell_nagree = count(_agreed),  by(pull_province pull_municipal_city pull_item ${unitvar})

* THE REGIONAL HETERO POOL -- item x unit x hetero-group across all five provinces.
* It exists because the rung below it, the pooled cell, is HETERO-BLIND, and being
* hetero-blind is a worse defect than being geographically broad.
*
* The pooled cell mixes smalls, mediums and larges, so its median sits near the middle
* of the case and a large's block reading looks a decade too big against it. The anchor
* -- the block reading divided by ten -- then wins by being closer to a number that
* describes smaller units. That bias is already documented for the cell_hetero rung
* above; what was missed is that it does not stop applying when the hetero pool is too
* thin to referee. It just stops being visible, because the fallback silently drops the
* hetero grain instead of widening the geography.
*
* Measured on the build this rung was added to fix. Of the rows where the block reading
* sits a decade above the published weight, the pooled cell refereed 88 and an
* independent item x unit x hetero median over undisputed rows contradicts the
* published value on 70 of them -- consistently in one direction, the anchor winning
* when it should not have. The hetero-AWARE cell rung refereed 54 of the same class and
* the same independent median backs the published value on 51. The rung that keeps the
* hetero grain is right; the rung that drops it is wrong, and wrong the same way each
* time.
*
* So: exhaust the hetero-correct pools before falling back to any hetero-blind one.
* Geography is the weaker confounder. A medium puto in the next province is a closer
* referent for a medium puto than a large puto in the same market.
*
* THIS POOL IS REGIONAL, NOT NATIONAL. All five surveyed provinces are Western Visayas
* (Region VI). See def_fallback_level in 00_globals.do.
egen double _rh_med = median(_agreed), by(pull_item ${unitvar} item_nsu_hetero_type)
egen long   _rh_n   = count(_agreed),  by(pull_item ${unitvar} item_nsu_hetero_type)

* the province-level fallbacks for thin cells, hetero-group first then without it
egen double _ph_med = median(_agreed), by(pull_province pull_item ${unitvar} item_nsu_hetero_type)
egen long   _ph_n   = count(_agreed),  by(pull_province pull_item ${unitvar} item_nsu_hetero_type)
egen double _p_med  = median(_agreed), by(pull_province pull_item ${unitvar})
egen long   _p_n    = count(_agreed),  by(pull_province pull_item ${unitvar})

* NAGREE = how many agreeing rows a pool needs before it can referee. Below this the
* median is one or two readings and cannot adjudicate a decade.
local NAGREE = 5

* THE HETERO POOL NEEDS A LOWER BAR, and it is not arbitrary. A cell's agreeing rows
* split three ways across small/medium/large, so a hetero pool is roughly a third the
* size of the pooled cell -- at `NAGREE' it referees only 28 disputed rows and is not
* the main reference at all, which is the point of having it. Measured across
* thresholds, the flips are lopsided toward the block reading at every one, which is
* the downward bias itself and not noise:
*
*     bar    rows refereed    flip to block    flip to anchor
*     > 5              28                5                 0
*     > 3             123               21                 1
*     > 2             209               37                 1
*     > 1             350               59                 3
*
* Set at 2, so a hetero median rests on at least THREE agreeing readings. Two is a
* midpoint, not a median. Moving this to 3 is defensible and costs 16 of the 37 flips;
* moving it to 1 is not -- a two-row "median" adjudicating a decade is worse than the
* pooled cell it replaces.
local NAGREE_HET = 2

* THE LADDER, and the one sentence that generates its order:
*
*     exhaust every HETERO-CORRECT pool, most local first,
*     before falling back to any HETERO-BLIND pool, most local first.
*
*         cell_hetero  -> prov_hetero -> region_hetero  | cell -> prov
*         \___________ hetero grain kept ____________/  \_ grain dropped _/
*
* The order used to be cell_hetero -> cell -> prov_hetero -> prov, which crosses the
* line in the middle of the ladder: a thin hetero pool fell straight to a pooled cell
* that mixes smalls, mediums and larges. See the comment on _rh_med above for what that
* cost -- 70 of 88 contested rows refereed the wrong way, one direction every time.
*
* `_ref_src' IS str14 AND MUST STAY AT LEAST THAT WIDE. "region_hetero" is 13
* characters; at the old str12 Stata truncates it to "region_heter" silently, and every
* downstream tab, label and diagnostic inherits the typo with nothing failing.
gen double _ref_med = .
gen str14  _ref_src = ""
replace _ref_med = _ch_med   if _ch_n > `NAGREE_HET' & !missing(_ch_med)
replace _ref_src = "cell_hetero" if _ch_n > `NAGREE_HET' & !missing(_ch_med)
replace _ref_med = _ph_med   if missing(_ref_med) & _ph_n > `NAGREE' & !missing(_ph_med)
replace _ref_src = "prov_hetero" if missing(_ref_src) & !missing(_ref_med)
replace _ref_med = _rh_med   if missing(_ref_med) & _rh_n > `NAGREE' & !missing(_rh_med)
replace _ref_src = "region_hetero" if missing(_ref_src) & !missing(_ref_med)
replace _ref_med = _cell_med if missing(_ref_med) & _cell_nagree > `NAGREE' & !missing(_cell_med)
replace _ref_src = "cell"    if missing(_ref_src) & !missing(_ref_med)
replace _ref_med = _p_med    if missing(_ref_med) & _p_n  > `NAGREE' & !missing(_p_med)
replace _ref_src = "prov"    if missing(_ref_src) & !missing(_ref_med)

* The truncation guard the comment above warns about, made mechanical.
assert _ref_src != "region_heter"
assert inlist(_ref_src, "", "cell_hetero", "prov_hetero", "region_hetero", "cell", "prov")

* ---- 3e-ii. rule 1: closer in log10 terms wins -----------------------------------
gen byte _pick_block = .
replace _pick_block = (abs(log10(w_block/_ref_med)) < abs(log10(base_corr/_ref_med))) ///
    if !missing(_ref_med) & _ref_med > 0 ///
     & !missing(w_block) & w_block > 0 & !missing(base_corr) & base_corr > 0
gen str16 _rule = "log10 median" if !missing(_pick_block)

* ---- 3e-ii-b to 3e-v: DELETED, and here is the proof they could not decide anything ---
* Three corroborating rules used to sit here -- a shared sub-1 decimal structure in the
* cell, a whole number typed as-is, and a final default. Each could only ever set
* `_pick_block' to 1, never to 0: all three said "publish the block reading".
*
* 3e-v-b below now sets `_pick_block = 1' on every row where the block reading is
* possible. So on those rows the three rules were choosing an outcome that was about to
* be chosen anyway, and on the rows where the block reading is IMPOSSIBLE they were
* choosing a value the plausibility gate then rejects. Neither branch can reach the
* published weight. They survived only in the `snap_rule' label, which recorded a rule
* that agreed with the decision rather than one that made it -- 159 rows labelled
* "whole number", "cell decimals" or "block default" whose weight came from block-governs.
*
* WHAT HAPPENS NOW WHERE NO REFEREE EXISTS. `_pick_block' stays missing, 3e-v-b sets it
* to 1 if the block reading is possible, and where it is not the row falls to the anchor
* -- which is strictly better than the old default of publishing an impossible block
* reading and relying on the gate to catch it.
*
* THE 34 ROWS BEHIND THE DELETED "own cell" RULE ARE NOT LOST. That rule was adjudicated
* by hand on issue #18 and every one of its rows was decided to the block reading; they
* still publish the block reading, now because block-governs says so rather than because
* a narrow override caught them. The review's conclusion survives; its machinery does not
* need to.

local WFLOOR = 10       // g/mL: below this a result is contaminated, not small
local WCEIL  = 50000    // g/mL: 2x the largest real purchase (a 25 kg rice sack)

* ---- 3e-v-b. THE BLOCK READING GOVERNS UNLESS IT CANNOT BE A READING --------------
* Everything above computes which candidate a pool of neighbours prefers. THAT ANSWER
* IS NOW CONSULTED ONLY WHERE THE BLOCK READING IS IMPOSSIBLE. Where the block reading
* is a number the item could have weighed, it is published, whatever the pool says.
*
* WHY. The block reading restates what the enumerator typed, in canonical units. The
* anchor is that number moved a decade -- a value nobody observed. Overruling an
* observation requires evidence that it is not an observation, and "it differs from its
* neighbours" is not that evidence for a NON-STANDARD unit, whose defining property is
* that it varies from vendor to vendor. Dispersion is partly the thing being measured.
*
* THE EVIDENCE THAT SETTLED IT. On the 197 rows where the pool overruled a plausible
* block reading, the override was split 104 up a decade against 93 down -- not a
* correction of a systematic error but a regression toward the local centre in both
* directions. Tested against each row's own item x unit x size range, built from rows
* where the two rules already agreed, the override landed the row inside that range on
* 101 and left it outside on 71; the remaining 25 had no comparable rows at all. And
* where a person adjudicated a disputed row -- 227 of them, in the review ledger -- they
* chose the block reading 200 times against 21 for the anchor. The rule was overruling
* the field far more often than a reviewer looking at the same rows ever did.
*
* WHAT STILL OVERRULES IT. Two things, and only two:
*   1. the plausibility bounds below -- a block reading outside them is not a reading,
*      and the pool's answer is then the only candidate left;
*   2. a hand verdict in reference/reviewed/snap_verdicts.csv, applied by
*      05_manual_corrections.do, which runs after this file and wins outright.
*
* As of the vintage this was written against, 03a_block_reading.do's misplaced-decimal
* repair means NO block reading falls outside the bounds, so the ladder above currently
* decides nothing. It is kept, not deleted, because it is the fallback the moment a new
* vintage produces a block reading that cannot be a reading. `snap_referee' still
* records which pool WOULD have refereed, which is what makes that reachable-but-unused
* claim checkable rather than asserted.
gen byte _block_ok = !missing(w_block) ///
    & round(w_block,1) >= `WFLOOR' & round(w_block,1) <= `WCEIL'

* COUNT ONLY WHERE IT CHANGES THE ANSWER. On the rows where the anchor and the block
* reading already agree -- the large majority -- `_pick_block' is 0 but publishing
* either one gives the same weight, so counting those would report about 10,700
* "reinstatements" that move nothing and bury the number that matters.
count if _block_ok & _pick_block == 0 & !missing(base_corr) ///
       & round(w_block,1) != round(base_corr,1)
di as result "3e-v-b: block reading reinstated over the pool's answer on " r(N) " row(s)"
replace _rule = "block governs" if _block_ok & _pick_block == 0 & !missing(base_corr) ///
       & round(w_block,1) != round(base_corr,1)
replace _pick_block = 1         if _block_ok

* EVERY ROW MUST CARRY A RULE LABEL. With the corroborating rules deleted, a row with no
* usable referee reaches here with `_rule' still empty -- it was those rules that used to
* fill it. `encode' turns an empty string into a MISSING category, so snap_rule would
* silently go blank on exactly the rows with the least evidence behind them.
replace _rule = "block governs"            if _rule == "" & _block_ok
replace _rule = "anchor (block impossible)" if _rule == "" & !_block_ok
assert _rule != ""

count if !_block_ok
di as result "3e-v-b: block reading impossible, ladder decides on " r(N) " row(s)"

* ---- 3e-vi. publish, then the plausibility floor/ceiling LAST ---------------------
* The bounds are the last word regardless of which rule won: an answer outside them is
* physically impossible, and where the OTHER candidate is inside them it is published
* instead. This is what catches a contaminated anchor pool -- 2 beer "case" rows
* reaching 1.2M g, and fresh-fish rows falling to 4-9 g.

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

* NO TYPED WEIGHT MEANS NO PUBLISHED WEIGHT -- 2026-09-17.
*
* A row whose raw `weight' is missing, zero or negative has no reading to correct. It
* gets no block reading in 03a, so every branch above falls through to the anchor, and
* the anchor would hand it the median of its pool's decade -- a number invented for a
* row where the enumerator recorded nothing. That is imputation, and this pipeline does
* not impute a weight anywhere else: a cell with no weighing is absent from Outcome 1
* and reported unconvertible in Outcome 2.
*
* So these rows stay MISSING and are accounted for as attrition instead. The count is
* printed rather than asserted, because a vintage with more of them is a fieldwork fact,
* not a build failure.
count if !(weight > 0 & weight < .) & !missing(corrected_weight)
di as result "3e-vii: clearing " r(N) " weight(s) the anchor would have invented (no typed reading)"
replace corrected_weight = . if !(weight > 0 & weight < .)

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
     _rh_med _rh_n _block_ok ///
     _ref_med _ref_src _pick_block _rule _chosen _other ///
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

* w_block RIDES ALONG FOR THE SAME REASON, and keeping it retires three hand-written
* copies of the rule above. It used to be computed here, used, and dropped -- so every
* consumer that needed the block reading re-derived it: snap_sense_check.py and the
* since-deleted compare_anchor_keying.py each carried their own version, scraping
* `KGMAX' out of this file to do it. Those copies guarded the CONSTANT and not the
* branch structure, so
* changing `weight>=10' in STEP 3a would have left both of them silently computing a
* rule the pipeline no longer used -- and snap_sense_check.py is what builds the review
* workbook whose verdicts get frozen into the ledger.
*
* It is also the weight a fold test must use to be non-circular: it is a function of
* the typed weight, the unit tick and `KGMAX' alone, and reads no harmonized unit.
replace w_block = round(w_block, 1)
label var w_block "STEP 3 block reading: typed weight in g/mL, kg-tick not taken literally"
keep correct* w_step1 w_block review_step1 snap_rule snap_referee snap_block id

* Deterministic row order: `id' is unique, so this leaves no ties for the sort
* seed to break. Without it the saved file's ORDER varies between runs.
sort id

save "${snap_out}", replace

