********************************************************************************
* 05_manual_corrections.do
*
* Every hand-made correction to corrected_weight / corrected_unit, in one place,
* with an assertion per block that the block actually matched what it was written
* for.
*
* WHY THIS FILE EXISTS
* These corrections used to sit inline in 03_clean_ms.do (and before that in
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
* There is a second, orphaned file: dofiles/archive/unit_correction_manual_overrides.do.
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
* CALLED FROM 00_shared/03_clean_ms.do, after the snap is merged in and after
* harmonized_nsu_unit exists. Expects: weight, unit, diagnostics, corrected_weight,
* corrected_unit, cleaning_notes, and the key variables above.
********************************************************************************

di as txt _n "{hline 78}"
di as txt "05_manual_corrections.do"
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
**# 2. Decimal-point slips -- RETIRED, now handled by the snap
********************************************************************************
* This section used to hold four blocks (ILOILO liquor, BADIANGAN whole chicken,
* ice cream, preserved meat), each multiplying a raw reading by 1000^2. All 18 rows
* were ticked as Litres and carry a THREE-decade decimal slip: 0.001495 L was meant
* to be 1.495 L. The multiplier looks like six decades only because it bundles two
* different things -- x1000 to convert L to mL, and x1000 to undo the slip.
*
* They existed because the old STEP 3 litres block did the conversion and nothing
* else, leaving the slip untouched and publishing 1 mL. A human then had to supply
* the missing three decades by hand, item by item.
*
* 04_unit_snap.do now snaps toward the row's own item x unit cell anchor and moves
* however many decades that implies, so these rows arrive already corrected and the
* blocks matched 0 rows. Under this file's own convention a correction that matches
* nothing is deleted, not silently zeroed -- see the header.
*
* WHAT CHANGED, on the 18 rows the four blocks covered:
*   12 rows  the snap lands on exactly the value the hand correction produced,
*            including the BADIANGAN chicken at 1,175 g and every long-neck liquor.
*    6 rows  the snap lands one decade LOWER, because the cell anchor disagrees
*            with the blanket x1000^2: ice cream "pieces or units" 150 not 1,500 mL,
*            "container" 125 not 1,250, "1.3 gallon" 130 not 1,300; preserved meat
*            "pack" 120 not 1,200 g; liquor "lipid/lapad" 120 and 121 not 1,200.
*            A blanket rescale could not tell a tub from a single piece; the anchor
*            can. The 1.3 gallon row is not right either way -- its cell is too thin
*            to anchor on, and it is on issue #31 with the other singletons.
*
* Do not re-add a rescale here without first checking whether the snap already did
* it. Two corrections applied to one row is a 1000x error with no error message.

* The rows those blocks used to catch must not come back as sub-plausible readings.
* If this fires, the snap stopped handling a case this file no longer covers.
count if inlist(pull_item, ///
		"liquor (e.g, whisky, coconut wine)", ///
		"ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)", ///
		"preserved or processed meat (tocino, tapa, longaniza, etc)") ///
	& !missing(corrected_weight) & corrected_weight < 10
assert r(N) == 0


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

* --- 4c. readings a FIELD REVIEWER flagged as ambiguous, from the curated `notes'
*         column of add_comments_crosswalk.xlsx
*
* Set to .c on the same grounds as 4a/4b: the reading cannot be interpreted, and a
* weight whose meaning is unknown is worse than no weight. Both were surfaced by
* auditing all 15 curated notes rather than by a weight test -- neither row looks
* wrong on its magnitude, which is exactly why the reviewer's note is the only
* evidence there is.
*
* NOT dropped as a LABEL in 02_drop_non_nsu_labels.py, deliberately. These are
* row-level recording problems, not bad labels: `bundle' for camote tops is a good
* NSU in 28 municipalities and `putos' for preserved meat in 12. Removing either
* label would delete a large, valid pool to fix 5 rows. The notes merge 1:1 on
* (province, municipality, item, raw label, approach, market type, vendor, hetero),
* so they land on individual weighings and are corrected at that grain.
*
* 4c-i. TIGBAUAN camote tops "bundle", reviewer note:
*   "not clear if the enumerator recorded weight for 15 php (2 bundles) or weight
*    for 1 bundle"
* A factor-of-two ambiguity with no way to settle it: 340 g is either one bundle or
* two. Its 8 cell siblings run 160-650 g, so both readings are plausible and the
* cell cannot adjudicate. NOTE this is not the driver of the camote tops / bundle
* dispersion on issue #28 -- that is 6.74x with or without this row.
count if pull_item == "camote tops" & harmonized_nsu_unit == "bundle" ///
	& pull_municipal_city == "TIGBAUAN" & strpos(cleaning_notes, "2 bundles") > 0
_chk "4c-i. TIGBAUAN camote tops, 1-vs-2 bundle ambiguity" 1
replace corrected_weight = .c if pull_item == "camote tops" & harmonized_nsu_unit == "bundle" ///
	& pull_municipal_city == "TIGBAUAN" & strpos(cleaning_notes, "2 bundles") > 0

* 4c-ii. PANITAN preserved meat "putos", reviewer note: "not sure" on 4 rows.
* The reviewer looked at these and did not reach a verdict. Kept as .c rather than
* guessed at. The cell keeps its other 2 weighings (225 and 260 g), so the case
* still publishes. Overlaps issue #31 (preserved meat / putos outliers).
count if pull_item == "preserved or processed meat (tocino, tapa, longaniza, etc)" ///
	& harmonized_nsu_unit == "putos" & pull_municipal_city == "PANITAN" ///
	& strpos(cleaning_notes, "not sure") > 0
_chk "4c-ii. PANITAN preserved meat, reviewer unresolved" 4
replace corrected_weight = .c ///
	if pull_item == "preserved or processed meat (tocino, tapa, longaniza, etc)" ///
	& harmonized_nsu_unit == "putos" & pull_municipal_city == "PANITAN" ///
	& strpos(cleaning_notes, "not sure") > 0


capture program drop _chk
di as txt "05_manual_corrections.do: all blocks matched their expected counts"
di as txt "{hline 78}" _n
