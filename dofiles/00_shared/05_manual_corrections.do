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
* 251 -> 248 when `6 bottles of redhorse' was dropped as a non-unit label. Its 3 MS
* weighings are all liquor, and liquor carries the mL verdict, so those 3 rows left
* this branch. The g branch is unaffected -- none of the five dropped labels belongs
* to a g-verdict item.
_chk "1b. dimension verdict mL (relabel g -> mL)" 248

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


********************************************************************************
**# 5. Reviewer-adjudicated snap decisions
********************************************************************************
* 04_unit_snap.do STEP 3e chooses between the anchor snap and the block reading by
* rule. These 12 weighings were adjudicated BY HAND during the review recorded on
* issue #18, because a reviewer read the cell and the rule did not reach the same
* answer. All 12 adopt the block reading -- the typed number in canonical units.
*
* KEYED ON CONTENT, NOT ON `id', and that matters. The first version of this block
* used `if id == 6115' and similar. Nine of the twelve then landed on the WRONG
* WEIGHING, because `id' is `_n' assigned after a sort: it is stable against
* REORDERING but not against ROW REMOVAL, and dropping five non-unit labels
* (16 weighings) renumbered every id after them. One correction meant for a 0.275 kg
* camote bilog was applied to a chicken bilog whose raw reading was 740 g.
*
* The assertions did not catch it, which is the part worth remembering: they counted
* whether the ids EXISTED, not whether they pointed at the intended rows. A count
* assertion on a positional key proves nothing about identity.
*
* So each block below keys on (municipality, item, harmonized unit, RAW WEIGHT). The
* raw weight is what the reviewer was actually looking at, it cannot renumber, and it
* makes the correction readable without the workbook to hand.
*
* NOTE THE float() WRAPPER on every decimal. weight is a float, so a bare
* `weight == 0.275' matches NOTHING -- the same trap section 4a documents.

* --- 5a. ANTIQUE / SAN REMIGIO / fresh fish / pieces or units --------------------
* Cell median 190 g on 5 agreeing rows. The anchor read these as 92 / 367 / 127 g,
* a decade below the vendor's own number.
count if pull_municipal_city == "SAN REMIGIO" & pull_item == "fresh fish" ///
       & harmonized_nsu_unit == "pieces or units" & inlist(weight, 920, 3670, 1265)
_chk "5a. SAN REMIGIO fresh fish, block reading" 3
replace corrected_weight = weight if pull_municipal_city == "SAN REMIGIO" ///
       & pull_item == "fresh fish" & harmonized_nsu_unit == "pieces or units" ///
       & inlist(weight, 920, 3670, 1265)

* --- 5b. ILOILO / SAN MIGUEL / crackers / pieces or units -----------------------
* Cell median 30 g on 5 agreeing rows; the anchor read 10 / 12 / 12 g. Two rows share
* the 120 g reading and take the same answer, so this is 3 rows on two readings.
count if pull_municipal_city == "SAN MIGUEL" ///
       & pull_item == "crackers, cookies, buiscuits, chips/curls" ///
       & harmonized_nsu_unit == "pieces or units" & inlist(weight, 98, 120)
_chk "5b. SAN MIGUEL crackers, block reading" 3
replace corrected_weight = weight if pull_municipal_city == "SAN MIGUEL" ///
       & pull_item == "crackers, cookies, buiscuits, chips/curls" ///
       & harmonized_nsu_unit == "pieces or units" & inlist(weight, 98, 120)

* --- 5c. NEGROS OCCIDENTAL / PONTEVEDRA / camote / bilog ------------------------
* Raw 0.275 / 0.390 / 0.475 -- a shared sub-1 decimal structure across the cell, so
* the readings are the market's convention rather than three separate slips.
count if pull_municipal_city == "PONTEVEDRA" & pull_item == "camote" ///
       & harmonized_nsu_unit == "bilog" ///
       & inlist(float(weight), float(0.275), float(0.390), float(0.475))
_chk "5c. PONTEVEDRA camote bilog, block reading" 3
replace corrected_weight = round(weight * 1000) ///
       if pull_municipal_city == "PONTEVEDRA" & pull_item == "camote" ///
       & harmonized_nsu_unit == "bilog" ///
       & inlist(float(weight), float(0.275), float(0.390), float(0.475))

* --- 5d. ILOILO / CABATUAN / camote / bilog -------------------------------------
* Same shared 0.xxx structure; annotated during the review.
count if pull_municipal_city == "CABATUAN" & pull_item == "camote" ///
       & harmonized_nsu_unit == "bilog" ///
       & inlist(float(weight), float(0.270), float(0.335), float(0.445))
_chk "5d. CABATUAN camote bilog, block reading" 3
replace corrected_weight = round(weight * 1000) ///
       if pull_municipal_city == "CABATUAN" & pull_item == "camote" ///
       & harmonized_nsu_unit == "bilog" ///
       & inlist(float(weight), float(0.270), float(0.335), float(0.445))


********************************************************************************
**# 6. Adjudicated snap verdicts, applied from the review ledger
********************************************************************************
* Section 5 is four hand-written blocks for twelve weighings. That pattern does not
* scale: the review of snap_sense_check.xlsx now carries 80 verdicts and will carry
* more, and eighty hand-written blocks would be unreadable and unmaintainable.
*
* So the verdicts live in a LEDGER -- reference/reviewed/snap_verdicts.csv, one row
* per adjudicated weighing, written from the annotated workbook by
* 90_diagnostics/snap_sense_check.py. It is committed, diffable, and grows by review
* round rather than by editing code.
*
* KEYED ON CONTENT, for the same reason section 5 is: `id' is durable now, but the
* workbook a reviewer annotates may predate the registry, and content is what the
* reviewer was actually looking at.
*
* THE KEY IS BUILT AS A STRING AT SIX SIGNIFICANT DIGITS. `weight' is a Stata float,
* so 1265 holds as 1264.9999 and 3670 as 3670.0002, while the CSV carries the exact
* decimal. An exact float join drops those rows SILENTLY -- it did, on 2 of 10, in the
* Python that reads this ledger back. Six digits is inside float's ~7 and reproduces
* every raw reading in the file.
*
* Duplicate content keys are expected and fine: 80 verdicts sit on 73 keys, because a
* cell can hold two identical readings from different vendors. Both rows take the same
* verdict, which is why the ledger is checked for CONFLICTING verdicts on one key
* rather than for uniqueness.

capture confirm file "${root}\Data Cleaning\reference\reviewed\snap_verdicts.csv"
if _rc {
	di as error "NO VERDICT LEDGER at reference/reviewed/snap_verdicts.csv."
	di as error "Every adjudicated snap decision lives there. Running without it"
	di as error "publishes the algorithm's answer on rows a human has overruled."
	exit 601
}

preserve
	import delimited using ///
		"${root}\Data Cleaning\reference\reviewed\snap_verdicts.csv", ///
		clear varnames(1) encoding("utf-8") stringcols(1 2 3 4 5)
	* one key may legitimately carry several rows; it may NOT carry two answers
	bysort province municipality item harmonized_nsu_unit hetero_group raw_weight: ///
		egen double _vmin = min(verdict)
	bysort province municipality item harmonized_nsu_unit hetero_group raw_weight: ///
		egen double _vmax = max(verdict)
	assert _vmin == _vmax
	gen str244 _vk = province + "|" + municipality + "|" + item + "|" ///
		+ harmonized_nsu_unit + "|" + hetero_group + "|" ///
		+ strofreal(raw_weight, "%9.6g")
	keep _vk verdict
	duplicates drop
	isid _vk
	qui count
	local n_led = r(N)
	tempfile ledger
	save "`ledger'"
restore

decode item_nsu_hetero_type, gen(_hg)
gen str244 _vk = pull_province + "|" + pull_municipal_city + "|" + pull_item + "|" ///
	+ harmonized_nsu_unit + "|" + _hg + "|" + strofreal(weight, "%9.6g")

merge m:1 _vk using "`ledger'", keep(1 2 3) gen(_m_verdict)

* A verdict that matches no weighing is a decision falling out of the build. Loudly.
count if _m_verdict == 2
if r(N) > 0 {
	di as error "`r(N)' verdict(s) in the ledger match no weighing in this build."
	di as error "The content key moved -- an upstream respelling, a changed fold, or"
	di as error "a row dropped. Reconcile it; do not delete the ledger row."
	list _vk if _m_verdict == 2, noobs abbrev(90)
	exit 459
}

count if _m_verdict == 3
di as result "6. review ledger: `n_led' key(s) -> " r(N) " weighing(s) adjudicated"
replace corrected_weight = verdict if _m_verdict == 3
drop _vk _hg verdict _m_verdict


capture program drop _chk
di as txt "05_manual_corrections.do: all blocks matched their expected counts"
di as txt "{hline 78}" _n
