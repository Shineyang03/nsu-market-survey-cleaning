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
* Inputs required in memory : pull_item cleaned_nsu_unit weight unit id
* Key outputs               : corrected_unit corrected_weight base_corr k flag_review

use "${temp}\prelim_nsu_data", clear

keep unit weight pull_item cleaned_nsu_unit id


* ---- tunable parameters -------------------------------------------------------
local MIN   = 10      // min item_nsu cell size before falling back to item level
local FLOOR = 5       // g/mL: an anchor below this is physically implausible
local SIB   = 1.5     // decades: item_nsu anchor this far from item ref => contaminated
local AMB   = 0.35    // decades: post-snap residual above this => ambiguous snap


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
egen double anchor_in = median(log_base), by(pull_item cleaned_nsu_unit)
egen long   n_in      = count(log_base),  by(pull_item cleaned_nsu_unit)
egen long   n_item    = count(log_base),  by(pull_item)

* ---- 1c. item-level sibling reference = median of the per-nsu anchors ----------
egen byte   tag_nsu      = tag(pull_item cleaned_nsu_unit) if !missing(log_base)
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
**# STEP 2 -- mass/volume harmonization for items recorded in BOTH dimensions
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
    export excel using "${tables}\mixed_dimension_items.xlsx", replace firstrow(variables)
restore

* NOTE: dimension harmonization is intentionally NOT applied. Step 2 only
* records which items were logged in both dimensions (list + xlsx above); each
* row keeps the mass/volume dimension the enumerator recorded (set in Step 1).
* To harmonize later, add one line per mixed item, e.g.:
*   replace corrected_unit = "mL" if pull_item == "Liquor (e.g, whisky, coconut wine)"

drop rec_mass rec_vol item_has_mass item_has_vol item_mixed


********************************************************************************
**# STEP 3 -- manual weight-review overrides on flagged rows
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

* --- 3b. unit==1 (kg) sub-1 entries are true kg -> grams via x1000 -------------
*   fixes the 0.155 vs 0.205 boundary flip (0.155 had snapped to 1550 g -> 155 g)
replace corrected_weight = weight*1000 if unit==1 & weight<1 & !missing(weight)
replace flag_review      = 0           if unit==1 & weight<1 & !missing(weight)

* --- 3c. unit==1 (kg) plausible bulk kg entries: trust the reading (-> grams) ---
*   an ordinary 1-20 kg purchase whose number+unit already agree; no-op if none
count if inrange(weight,1,20) & unit==1 & !missing(weight)
di as txt "3c kg-plausibility: " r(N) " row(s) matched"
replace corrected_weight = weight*1000 if inrange(weight,1,20) & unit==1 & !missing(weight)
replace flag_review      = 0           if inrange(weight,1,20) & unit==1 & !missing(weight)

* --- 3d. water "Bottle (500 ml)" -- the NSU name IS the answer = 500 mL --------
*   (0.5 L had snapped to 5 mL against a contaminated water anchor)
replace corrected_weight = 500 if unit==3 & cleaned_nsu_unit=="Bottle (500 ml)" ///
    & pull_item=="Mineral or spring water, all drinking water sold in containers"
replace flag_review      = 0   if unit==3 & cleaned_nsu_unit=="Bottle (500 ml)" ///
    & pull_item=="Mineral or spring water, all drinking water sold in containers"

* --- add further reviewed slices below, one block per pattern ------------------
*   count if flag_review==1 & <slice>
*   replace corrected_weight = <fixed value / rule> if flag_review==1 & <slice>
*   replace flag_review      = 0                    if flag_review==1 & <slice>


********************************************************************************
**# outputs
********************************************************************************
tab flag_review, m
count if flag_review==1
di as txt "Remaining rows still flagged for manual review: " r(N)

* full corrected dataset
save "${temp}\nsu_data_unit_corrected", replace

* the remaining review queue (for inspection)
preserve
    keep if flag_review==1
    keep pull_item cleaned_nsu_unit weight unit base base_corr k ///
         corrected_weight corrected_unit flag_small flag_lowanchor flag_sibling flag_ambiguous id
    save "${temp}\unit_correction_intermediate", replace
restore

* browse the remaining queue:
* br pull_item cleaned_nsu_unit weight unit base base_corr k corrected_weight ///
*    corrected_unit flag_small flag_lowanchor flag_sibling flag_ambiguous id if flag_review==1

* intermediates you can drop once satisfied:
* drop base log_base anchor_in n_in n_item anchor_item eff_anchor resid ///
*      flag_small flag_lowanchor flag_sibling flag_ambiguous
