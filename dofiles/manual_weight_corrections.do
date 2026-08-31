********************************************************************************
* manual_weight_corrections.do
*
* Every hand-made correction to corrected_weight / corrected_unit, in one place,
* with an assertion per block that the block actually matched what it was written
* for.
*
* WHY THIS FILE EXISTS
* These corrections used to sit inline in cleaning_Aug11.do (and before that in
* cleaning.do). They worked, except where they silently did not: the ILOILO
* chicken block below was written to rescale one row and matched ZERO, because it
* tested item_nsu_hetero_type == 2 (small) against a row that is 4 (large). The log
* recorded "(0 real changes made)" and nothing stopped the build. The row shipped as
* a 1 gram whole chicken and reached the published reference set.
*
* A `replace ... if <condition>` that matches nothing is indistinguishable from one
* that was never needed. So every block here states the number of rows it expects
* and asserts it. A correction that stops matching -- because the data changed, a
* code changed, or the condition was wrong to begin with -- now halts the build
* instead of passing silently.
*
* There is a second, orphaned file: dofiles/unit_correction_manual_overrides.do.
* Nothing calls it and the dataset it reads (unit_correction_intermediate) is never
* written, so it has never run. Its Override 1 is documented as a no-op; its
* Override 2 targeted fresh-fish rows the current snap already resolves to 95 g on
* its own. Neither is carried forward here. That file should be deleted once this
* one is confirmed in place.
*
* KEYING
* Blocks that fix a PATTERN (all ILOILO liquor reading exactly 1) stay written as
* the pattern -- enumerating the rows would hide the rule. Blocks that fix ONE
* observation are keyed on the stable combination
*     pull_province x pull_municipal_city x pull_item x harmonized_nsu_unit
*     x market_type x vendor_id x item_nsu_hetero_type
* rather than on `id`, which is a row counter (gen id = _n) and shifts whenever the
* upstream data or sort order changes.
*
* CALLED FROM cleaning_Aug11.do, after the snap is merged in and after
* harmonized_nsu_unit exists. Expects: weight, unit, diagnostics, corrected_weight,
* corrected_unit, cleaning_notes, and the key variables above.
********************************************************************************

di as txt _n "{hline 78}"
di as txt "manual_weight_corrections.do"
di as txt "{hline 78}"

* Helper: assert a block matched what it says it should, and say so out loud.
capture program drop _chk
program define _chk
	args label expected
	local got = r(N)
	di as txt "  `label': matched `got' row(s), expected `expected'"
	if `got' != `expected' {
		di as error "  MANUAL CORRECTION MISMATCH -- `label'"
		di as error "  expected `expected' row(s), matched `got'."
		di as error "  A correction that no longer matches is not a no-op: either the"
		di as error "  data changed, or the condition was wrong. Fix one or the other;"
		di as error "  do not simply update the expected count."
		assert `got' == `expected'
	}
end


********************************************************************************
**# 1. Dimension verdicts -- mass vs volume, one verdict per item
********************************************************************************
* `diagnostics` carries the per-item verdict resolved upstream. This relabels the
* unit; it deliberately does NOT rescale the number, because the items involved are
* near water density (liquor, ice cream) where 375 g and 375 mL are the same reading
* to the precision recorded. See docs/data_oddities.md sec.4.

* Asserted per branch, not as one total: a lumped count would let the g branch
* grow while the mL branch shrinks and still pass.
count if diagnostics == "g" & corrected_unit != 1 & !mi(corrected_unit)
_chk "1a. dimension verdict g  (relabel mL -> g)" 15
count if diagnostics == "mL" & corrected_unit != 2 & !mi(corrected_unit)
_chk "1b. dimension verdict mL (relabel g -> mL)" 251

replace corrected_unit = 1 if diagnostics == "g"  & corrected_unit != 1 & !mi(corrected_unit)
replace corrected_unit = 2 if diagnostics == "mL" & corrected_unit != 2 & !mi(corrected_unit)


********************************************************************************
**# 2. Decimal-point slips: readings that land on 1 when they should be ~1 kg
********************************************************************************
* These share one cause: the field number carries a 1000x decimal-point error AND
* the unit tick is wrong, so the snap resolves them to a value of 1. weight *
* (1000^2) recovers the intended reading. Each block is a separate pattern with its
* own expected count.

* --- 2a. ILOILO liquor recorded in mL, reading exactly 1
count if pull_item == "liquor (e.g, whisky, coconut wine)" & ///
         pull_province == "ILOILO" & corrected_unit == 2 & corrected_weight == 1
_chk "2a. ILOILO liquor, reading 1 mL" 10
replace corrected_weight = weight * (1000^2) if ///
	pull_item == "liquor (e.g, whisky, coconut wine)" & ///
	pull_province == "ILOILO" & corrected_unit == 2 & corrected_weight == 1

* --- 2b. ILOILO / BADIANGAN whole chicken, reading exactly 1 g
* THIS BLOCK IS THE REASON THE FILE EXISTS. cleaning_Aug11.do wrote it as
*     ... & item_nsu_hetero_type == 2 & ...
* which is small_size. The row is large_size (4), so the condition matched nothing
* and the log said "(0 real changes made)". Re-expressed on the stable key, with no
* hetero-type condition at all -- the size label is not part of what identifies the
* error. Raw weight 0.001175 ticked as Litres; 0.001175 * 1000^2 = 1,175 g, which
* sits correctly above the two mediums in the same cell (980 g and 795 g) and near
* the province median for a whole chicken (1,225 g).
count if pull_province == "ILOILO" & pull_municipal_city == "BADIANGAN" & ///
         pull_item == "chicken" & harmonized_nsu_unit == "whole (chicken)" & ///
         corrected_unit == 1 & corrected_weight == 1
_chk "2b. BADIANGAN whole chicken, reading 1 g" 1
replace cleaning_notes = "decimal-point slip: 0.001175 ticked as Litres, rescaled to 1,175 g" ///
	if pull_province == "ILOILO" & pull_municipal_city == "BADIANGAN" & ///
	   pull_item == "chicken" & harmonized_nsu_unit == "whole (chicken)" & ///
	   corrected_unit == 1 & corrected_weight == 1
replace corrected_weight = weight * (1000^2) ///
	if pull_province == "ILOILO" & pull_municipal_city == "BADIANGAN" & ///
	   pull_item == "chicken" & harmonized_nsu_unit == "whole (chicken)" & ///
	   corrected_unit == 1 & corrected_weight == 1

* --- 2c. ice cream in mL reading 1-2  (flagged uncertain by the original author)
count if pull_item == "ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)" & ///
         corrected_unit == 2 & inrange(corrected_weight,1,2)
_chk "2c. ice cream, reading 1-2 mL" 7
replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.001 L)" ///
	if pull_item == "ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)" & ///
	   corrected_unit == 2 & inrange(corrected_weight,1,2)
replace corrected_weight = weight * (1000^2) ///
	if pull_item == "ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)" & ///
	   corrected_unit == 2 & inrange(corrected_weight,1,2)

* --- 2d. preserved meat in g reading 1-2  (flagged uncertain by the original author)
count if pull_item == "preserved or processed meat (tocino, tapa, longaniza, etc)" & ///
         corrected_unit == 1 & inrange(corrected_weight,1,2)
_chk "2d. preserved meat, reading 1-2 g" 1
replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.001x L)" ///
	if pull_item == "preserved or processed meat (tocino, tapa, longaniza, etc)" & ///
	   corrected_unit == 1 & inrange(corrected_weight,1,2)
replace corrected_weight = weight * (1000^2) ///
	if pull_item == "preserved or processed meat (tocino, tapa, longaniza, etc)" & ///
	   corrected_unit == 1 & inrange(corrected_weight,1,2)


********************************************************************************
**# 3. Refilled water containers reading 10
********************************************************************************
* A refill container reading 10 is 0.01 L mis-scaled; the intended reading is 1 L.
count if inlist(harmonized_nsu_unit,"refilled","container") & corrected_weight == 10
_chk "3. refilled/container, reading 10" 5
replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.01 L)" ///
	if inlist(harmonized_nsu_unit,"refilled","container") & corrected_weight == 10
replace corrected_weight = 1000 ///
	if inlist(harmonized_nsu_unit,"refilled","container") & corrected_weight == 10


********************************************************************************
**# 4. Readings no power-of-ten interpretation rescues -- set to .c, not dropped
********************************************************************************
* These survive as rows with an extended-missing weight so the attrition ledger can
* account for them; they are excluded downstream by the usable-weight filter.

* --- 4a. CAPIZ / PANAY mineral water "distilled water", 0.007 L
* NOTE the float() wrapper: weight is a float and 0.007 is not exactly
* representable, so a bare `weight == 0.007` matches NOTHING. cleaning.do targeted
* this as `inlist(id, 4242)`; id is _n and the two saved copies of the old build
* disagree on which row that is, so it is expressed on the reading itself.
count if unit == 3 & weight == float(0.007)
_chk "4a. 0.007 L mineral water (was id 4242)" 1
replace cleaning_notes = "Genuinely unsure about how to interpret original weight-unit values (0.007 L)" ///
	if unit == 3 & weight == float(0.007)
replace corrected_weight = .c if unit == 3 & weight == float(0.007)
replace corrected_unit   = .c if unit == 3 & weight == float(0.007)

* --- 4b. prawns sold by the cup, reading 5 g
count if inlist(harmonized_nsu_unit,"cup") & ///
         pull_item == "prawns, lobster, shrimp" & weight == 5 & unit == 2
_chk "4b. 5 g per cup, prawns" 1
replace cleaning_notes = "Genuinely unsure about how to interpret original weight-unit values (5 g per cup)" ///
	if inlist(harmonized_nsu_unit,"cup") & ///
	   pull_item == "prawns, lobster, shrimp" & weight == 5 & unit == 2
replace corrected_weight = .c if inlist(harmonized_nsu_unit,"cup") & ///
	pull_item == "prawns, lobster, shrimp" & weight == 5 & unit == 2
replace corrected_unit   = .c if inlist(harmonized_nsu_unit,"cup") & ///
	pull_item == "prawns, lobster, shrimp" & weight == 5 & unit == 2

capture program drop _chk
di as txt "manual_weight_corrections.do: all blocks matched their expected counts"
di as txt "{hline 78}" _n
