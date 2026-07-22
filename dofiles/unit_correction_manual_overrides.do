********************************************************************************
**# Manual overrides on top of the automatic power-of-ten snap
********************************************************************************
* Operates on the flagged-review queue saved by correct_unit_snap.do. Every
* row in this file IS the flagged queue (there is no flag_review column --
* the file's existence as a subset already means flag_review==1 for all rows).
* This script creates `still_flagged`, starts it at 1 for every row, and each
* override block below clears it to 0 for the rows it resolves.
*
* Each block: (a) targets a specific, understood error pattern, (b) overrides
* corrected_unit/corrected_weight for exactly that slice, (c) derives the new
* corrected_weight from `base_corr` (the untouched algorithm output), never
* from `corrected_weight` itself -- that makes every block idempotent, i.e.
* safe to re-run on a file that may already reflect a prior manual pass,
* rather than silently compounding (e.g. dividing by 10 twice).
*
* CAVEAT: "id" here is a sequential row counter (gen id = _n on the flagged
* subset), not a stable observation key -- correct_unit_snap.do currently
* drops vendor_id/market_type/prov_mun_nsu_item/item_nsu_hetero_type via
* `keep unit weight pull_item cleaned_nsu_unit` before id is ever assigned.
* Any `if inlist(id, ...)` override below is only valid for THIS exact save
* of the queue and will silently mismatch if the upstream data, sort order,
* or algorithm changes. Re-point id at the stable combination
* (prov_mun_nsu_item market_type vendor_id item_nsu_hetero_type) before
* relying on more one-off id-based fixes, or on merging this back to
* prelim_nsu_data at all.

use "${temp}\unit_correction_intermediate", clear

gen byte still_flagged = 1
label var still_flagged "1 = still needs manual review after overrides below"

* ------------------------------------------------------------------------------
* Override 1: literal, plausible kg entries (enumerator's number and unit
* already agree on an ordinary bulk-purchase size) -- trust as-is over the
* anchor algorithm's second-guess.
* Currently a no-op on this save of the queue (no unit==1 row has weight in
* [1,20]) -- kept so it activates automatically if a future re-run produces
* matching rows; the displayed count tells you whether it did anything.
* ------------------------------------------------------------------------------
count if still_flagged==1 & inrange(weight,1,20) & unit==1
di as txt "Override 1 (kg plausibility): " r(N) " row(s) matched"

replace corrected_unit   = "kg"    if still_flagged==1 & inrange(weight,1,20) & unit==1
replace corrected_weight = weight  if still_flagged==1 & inrange(weight,1,20) & unit==1
replace still_flagged    = 0       if still_flagged==1 & inrange(weight,1,20) & unit==1

* ------------------------------------------------------------------------------
* Override 2: Fresh Fish / Binilog, weight==0.095, unit==2 (id 35, 36).
* Algorithm proposed k=4 (-> ~950g, base_corr); judged too large for a single
* Binilog purchase -- true value is one decade down (~95g). Recomputed from
* base_corr (not corrected_weight) so this is safe to re-run even though the
* saved file may already reflect it. NOTE: id-based, see caveat above.
* ------------------------------------------------------------------------------
count if inlist(id,35,36) & still_flagged==1
di as txt "Override 2 (Fresh Fish/Binilog id 35,36): " r(N) " row(s) matched"

replace corrected_weight = base_corr/10 if inlist(id,35,36) & still_flagged==1
replace still_flagged    = 0             if inlist(id,35,36) & still_flagged==1

* ------------------------------------------------------------------------------
* Add further reviewed slices below this line, one block per pattern:
*   count if still_flagged==1 & <slice condition>
*   replace corrected_unit   = "..."          if still_flagged==1 & <slice condition>
*   replace corrected_weight = <from base_corr, not corrected_weight> if still_flagged==1 & <slice condition>
*   replace still_flagged    = 0              if still_flagged==1 & <slice condition>
* ------------------------------------------------------------------------------

tab still_flagged, m
count if still_flagged==1
di as txt "Remaining flagged for review: " r(N)

save "${temp}\unit_correction_intermediate", replace
