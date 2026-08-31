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
* PARAMETERS (globals; all default to the original cleaning.do behaviour, so
* calling this file with none of them set runs the CURRENT cleaning.do path. It does
* NOT reproduce the pre-Aug11 output byte for byte -- since parameterization the file
* also gained a unit==3 block, a round() and an encode, and lost two saves
*   ${unitvar}     unit variable defining the anchor pool  [cleaned_nsu_unit]
*   ${snap_in}     input dataset                           [${temp}\prelim_nsu_data]
*   ${snap_out}    output dataset                          [${temp}\standard_weight_unit_correction]
*   ${snap_tables} folder for mixed_dimension_items.xlsx    [${tables}]

if "${unitvar}"     == "" global unitvar     "cleaned_nsu_unit"
if "${snap_in}"     == "" global snap_in     "${temp}\prelim_nsu_data"
if "${snap_out}"    == "" global snap_out    "${temp}\standard_weight_unit_correction"
if "${snap_tables}" == "" global snap_tables "${tables}"

di as txt "04_unit_snap: anchor pool = pull_item x ${unitvar}"
di as txt "04_unit_snap: in  = ${snap_in}"
di as txt "04_unit_snap: out = ${snap_out}"

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


********************************************************************************
**# STEP 3 -- Claude's weight-review overrides on flagged rows
********************************************************************************
* Each block fixes corrected_weight for a specific, understood error pattern and
* clears flag_review. Blocks are item-independent (condition-based), so the same
* raw entry always maps to the same corrected value. corrected_unit is NOT set
* here -- Steps 1-2 own the unit.

* --- 3a. unit==2 (grams): decimal / same-input-same-output consistency ---------
*   weight >= 10 : already plausible grams          -> keep
*   weight <  10 : kg-magnitude misentry            -> x1000
*   (subsumes the old id 35/36 fix: 0.095 -> 95 g)
replace corrected_weight = cond(weight>=10, weight, weight*1000) if unit==2 & !missing(weight)
replace flag_review      = 0                                      if unit==2 & !missing(weight)

replace corrected_weight = cond(weight>=10, weight, weight*1000) if unit==3 & !missing(weight)
replace flag_review      = 0                                      if unit==3 & !missing(weight)


* --- 3b. unit==1 (kg) sub-1 entries are true kg -> grams via x1000 -------------
*   fixes the 0.155 vs 0.205 boundary flip (0.155 had snapped to 1550 g -> 155 g)
replace corrected_weight = weight*1000 if unit==1 & weight<1 & !missing(weight)
replace flag_review      = 0           if unit==1 & weight<1 & !missing(weight)

* --- 3c. unit==1 (kg) plausible bulk kg entries: trust the reading (-> grams) ---
*   an ordinary 1-`KGMAX' kg purchase whose number and unit already agree.
*   THE CEILING MATTERS. It used to be 20, which left the band (20,1000) handled by
*   nothing at all: three 25 kg rice sacks (ILOILO/MAASIN, "sack of rice") fell
*   through to the STEP 1 anchor, which pulled them toward the item-level rice
*   anchor -- dominated by gantang ~2,250 g -- and published them as 2,500 g, ten
*   times too small.
count if inrange(weight,1,`KGMAX') & unit==1 & !missing(weight)
di as txt "3c kg-plausibility: " r(N) " row(s) matched"
replace corrected_weight = weight*1000 if inrange(weight,1,`KGMAX') & unit==1 & !missing(weight)
replace flag_review      = 0           if inrange(weight,1,`KGMAX') & unit==1 & !missing(weight)

* --- 3d. unit==1 (kg) but far too big for kg: grams mis-ticked as kg ------------
*   A cabbage does not weigh 1,180 kg. Above `KGMAX' the number is already grams and
*   the UNIT tick is the error, so take the reading as it stands. Subsumes what STEP
*   4 did via a x10 rescale, and states the real invariant -- "the typed number is
*   already grams" -- rather than "the snap overshot by one decade", which held for
*   those 16 rows only because the anchor happened to give k = -4 for every one.
count if weight > `KGMAX' & unit==1 & !missing(weight)
di as txt "3d kg-implausibility (read as grams): " r(N) " row(s) matched"
replace corrected_weight = weight if weight > `KGMAX' & unit==1 & !missing(weight)
replace flag_review      = 0      if weight > `KGMAX' & unit==1 & !missing(weight)


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

sort id

replace corrected_weight = round(corrected_weight,1)
encode corrected_unit, gen(correct_unit)
order correct_unit, after(corrected_unit)
drop corrected_unit
order id, last


keep correct* id

save "${snap_out}", replace

