********************************************************************************
**# Correct order-of-magnitude unit-entry errors  (log10 power-of-ten snapping)
********************************************************************************
* Idea: within pull_item x cleaned_nsu_unit the true physical size is roughly
* constant. Recorded (weight,unit) errors are powers of ten (kg<->g, L<->mL,
* decimal slips), which on a log10 scale are integer shifts. We snap each obs to
* the nearest integer shift toward a robust group anchor (median log10), using an
* item-level sibling anchor as fallback (small cells) and as repair (contaminated
* anchors), and flag rows where the anchor can't be trusted / the snap is ambiguous.
* Raw unit codes: 1 = kg , 2 = g , 3 = L .
*
* Inputs required in memory : pull_item cleaned_nsu_unit weight unit
* Key outputs               : corrected_unit corrected_weight base_corr k flag_review

* ---- tunable parameters -------------------------------------------------------
local MIN   = 10      // min item_nsu cell size before falling back to item level
local FLOOR = 5       // g/mL: an anchor below this is physically implausible
local SIB   = 1.5     // decades: item_nsu anchor this far from item ref => contaminated
local AMB   = 0.35    // decades: post-snap residual above this => ambiguous snap

* ---- 1. canonical base magnitude (grams for mass, mL for volume; density ~ 1) -
gen double base = weight
replace    base = weight*1000 if unit==1          // kg -> g
replace    base = weight*1000 if unit==3          // L  -> mL
replace    base = .           if !(weight>0 & weight<.)   // drop 0 / missing / .c
gen double log_base = log10(base)

* ---- 2. item mass/volume class (majority of recorded unit==3 within item) -----
gen byte    is_vol_obs = (unit==3) if !missing(unit)
egen double share_vol  = mean(is_vol_obs), by(pull_item)
gen byte    vol_item   = (share_vol > 0.5)

* ---- 3. item_nsu anchor (median log10) + cell sizes ---------------------------
egen double anchor_in = median(log_base), by(pull_item cleaned_nsu_unit)
egen long   n_in      = count(log_base),  by(pull_item cleaned_nsu_unit)
egen long   n_item    = count(log_base),  by(pull_item)

* ---- 4. item-level sibling reference = median of the per-nsu anchors ----------
egen byte   tag_nsu      = tag(pull_item cleaned_nsu_unit) if !missing(log_base)
egen double anchor_item0 = median(anchor_in) if tag_nsu==1, by(pull_item)
egen double anchor_item  = mean(anchor_item0), by(pull_item)   // broadcast to all rows
drop anchor_item0 tag_nsu

* ---- 5. guards ----------------------------------------------------------------
gen byte flag_small     = (n_in < `MIN')                                   // fell back to item level
gen byte flag_lowanchor = (anchor_in < log10(`FLOOR'))                     // anchor physically implausible
gen byte flag_sibling   = (abs(anchor_in - anchor_item) > `SIB') & !missing(anchor_item)  // contaminated vs siblings

* ---- 6. effective anchor: item_nsu normally; item ref if small / contaminated -
gen double eff_anchor = anchor_in
replace    eff_anchor = anchor_item if flag_small | flag_lowanchor | flag_sibling

* ---- 7. snap to nearest integer power of ten ----------------------------------
gen int    k         = round(eff_anchor - log_base)     // 0 => unchanged
gen double base_corr = base * (10^k)
gen double resid     = abs(eff_anchor - log_base - k)   // distance to chosen decade
gen byte   flag_ambiguous = (resid > `AMB') & !missing(resid)

* ---- 8. review flag (fallback alone is acceptable unless item is also tiny) ----
gen byte flag_review = flag_lowanchor | flag_sibling | flag_ambiguous
replace  flag_review = 1 if flag_small & n_item < `MIN'
replace  flag_review = 1 if missing(base)

* ---- 9. corrected unit (group standard, from anchor) + corrected weight --------
gen double anchor_base = 10^eff_anchor
gen str6 corrected_unit = ""
replace  corrected_unit = cond(anchor_base>=1000, "L",  "mL") if vol_item==1
replace  corrected_unit = cond(anchor_base>=1000, "kg", "g")  if vol_item==0
replace  corrected_unit = "" if missing(base_corr)

gen double corrected_weight = base_corr
replace    corrected_weight = base_corr/1000 if inlist(corrected_unit,"kg","L")

* ---- labels -------------------------------------------------------------------
label var base             "Recorded weight in canonical base (g mass / mL volume)"
label var log_base         "log10(base)"
label var anchor_in        "log10 anchor: median within item_nsu"
label var anchor_item      "log10 anchor: item-level sibling reference"
label var eff_anchor       "log10 anchor actually used for snapping"
label var k                "Applied power-of-ten shift (log10); 0 = unchanged"
label var base_corr        "Corrected weight in canonical base (g/mL) after snap"
label var corrected_unit   "Corrected unit (group standard): kg/g or L/mL"
label var corrected_weight "Corrected weight expressed in corrected_unit"
label var flag_review      "1 = anchor untrusted or snap ambiguous -> manual review"

* ---- diagnostics --------------------------------------------------------------
tab k, m
tab corrected_unit, m
tab flag_review, m
* browse the review queue:
* br pull_item cleaned_nsu_unit weight unit base base_corr k corrected_weight corrected_unit ///
*    flag_small flag_lowanchor flag_sibling flag_ambiguous if flag_review

* intermediates you can drop once satisfied:
* drop is_vol_obs share_vol anchor_in n_in n_item anchor_item eff_anchor anchor_base ///
*      log_base resid flag_small flag_lowanchor flag_sibling flag_ambiguous
