********************************************************************************
* 12_publish_reference_set.do -- Outcome 1, the deliverable
*
* Collapses to one row per case x size and publishes it. The MEDIAN is taken
* within each group: the guidebook allows mean or median, and the median is
* robust to a single mis-keyed vendor the magnitude snap did not catch.
*
* d_thin marks a published value resting on fewer than THIN weighings. THIN = 3
* sits almost exactly on the median of n_g, so the flagged share is very
* sensitive to it -- n_g is published alongside so a reader can set their own
* cut. See issue #27 item 3.
*
* STEP 3 OF 3 in the Outcome 1 build. Run the three in order, or run
* master_outcome1.do, from the dofiles/ folder.
*   10_size_assignment.do        -> ref_10_sized.dta
*   11_size_checks.do            -> ref_11_checked.dta   (checkpoint, rows unchanged)
*   12_publish_reference_set.do  -> nsu_reference_set.dta / .xlsx
*
* INPUT   ${btemp}\ref_11_checked.dta
* OUTPUT  ${bdeliv}\nsu_reference_set.dta
*         ${bdeliv}\nsu_reference_set.xlsx
********************************************************************************

clear all
do "00_shared/00_globals.do"

local THIN = ${THIN}      // ONE definition, in 00_globals.do -- do not retype the value

use "${btemp}\ref_11_checked.dta", clear
count
di as txt "weighings in: " r(N)

label define szlbl 0 "conventional_nsu" 1 "small" 2 "medium" 3 "large", replace
label values size_ord szlbl

************************************************************
**# 5. Collapse to the reference set
********************************************************************************
* MEDIAN within case x size. The guidebook allows mean or median; the median is
* robust to a single mis-keyed vendor the magnitude snap did not catch.

* `branch' and `d_reclassified' ride along so a published row can say WHY it is called
* medium. Without them a reclassified case is indistinguishable from a case the field
* actually recorded as medium, and #28's decision becomes invisible in the deliverable
* it changed. Both are constant within a case by construction -- 08_branch.do asserts no
* case mixes conventional with another approach internally -- so (first) is exact rather
* than a choice among differing values.
* THE UNCERTAINTY COUNTS ride along too, as counts rather than as a dummy. 27.7% of
* published rows rest on at least one questioned weighing but only 7.6% rest ENTIRELY on
* them, and the median row sits on 4 weighings -- so "this row touches an uncertain
* weight" would condemn more than a quarter of the table while saying nothing about degree.
* (Section 6 prints all three figures on every run; the numbers here are the current ones
* and are not asserted, so read the log rather than this comment.) Counts
* plus `share_uncertain' let a reader set the tolerance; `share_uncertain == 1' is the
* sharp signal, meaning nothing behind the estimate went unquestioned. See #35.
*
* `d_unusable' is deliberately NOT summed here. An unusable weighing has no weight, so it
* was dropped upstream and cannot reach this collapse -- asserted immediately below rather
* than assumed, because a future change that let one through would make every count on
* this row understate its denominator.
assert !missing(corrected_weight)

********************************************************************************
**# 4b. The raw spellings behind each published unit
********************************************************************************
* A reference book names a unit; a field officer hears a WORD. `harmonized_nsu_unit'
* is the pooling key and is often not anything a vendor said -- `pieces or units' is a
* group name, not a phrase. So each published row also carries the raw labels that
* actually fed it.
*
* TWO COLUMNS, BECAUSE THEY ANSWER DIFFERENT QUESTIONS.
*
*   source_nsu_units_here   the spellings observed in THIS municipality for this item
*                           and unit. Exact provenance for the row: it never claims a
*                           spelling that was not heard in this cell.
*   source_nsu_units_item   every spelling that folds to this unit for this item,
*                           anywhere. The vocabulary an enumerator arriving in a new
*                           municipality needs.
*
* THE TWO ARE NOT REDUNDANT, AND ONE PAIR PROVES IT. Harmonization is a function of
* (item, spelling) for 264 of the 266 observed pairs, so for those the item-wide list is
* just the union of the local ones. The exceptions are cabbage `putos' and carrot
* `putos', which fold to `putos (mix vegetable)' at ILOILO / TIGBAUAN and to `pack'
* everywhere else -- a deliberate cell-level entry (CELL_MIX in nsu_fold_rule.py),
* recorded because the field officer wrote "There is no cabbage packs alone this is
* mixed with carrots". An item-wide column alone would show `putos' under BOTH units and
* imply a contradiction; the local column is what disambiguates it.
tempfile refbody
save "`refbody'"

* --- local: province x municipality x item x harmonized unit
preserve
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit pull_nsu_unit
	duplicates drop
	sort pull_province pull_municipal_city pull_item harmonized_nsu_unit pull_nsu_unit
	by pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
		gen str244 source_nsu_units_here = pull_nsu_unit if _n == 1
	by pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
		replace source_nsu_units_here = source_nsu_units_here[_n-1] + "; " + pull_nsu_unit if _n > 1
	by pull_province pull_municipal_city pull_item harmonized_nsu_unit: keep if _n == _N
	drop pull_nsu_unit
	tempfile srclocal
	save "`srclocal'"
restore

* --- item-wide: item x harmonized unit
preserve
	keep pull_item harmonized_nsu_unit pull_nsu_unit
	duplicates drop
	sort pull_item harmonized_nsu_unit pull_nsu_unit
	by pull_item harmonized_nsu_unit: gen str244 source_nsu_units_item = pull_nsu_unit if _n == 1
	by pull_item harmonized_nsu_unit: ///
		replace source_nsu_units_item = source_nsu_units_item[_n-1] + "; " + pull_nsu_unit if _n > 1
	by pull_item harmonized_nsu_unit: keep if _n == _N
	drop pull_nsu_unit
	tempfile srcitem
	save "`srcitem'"
restore

use "`refbody'", clear

collapse (median) grams = corrected_weight (count) n_g = corrected_weight ///
         (sum) n_disputed = d_disputed n_flagged = d_step1_flagged ///
               n_uncertain = d_any_uncertain ///
         (first) weighing_approach branch d_reclassified, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
            corrected_unit size_ord)

* Attach the spellings. assert(3) on both: every published row came from weighings, so
* every row must find its source list, and a list with no row means the collapse key
* and the source key have drifted apart.
merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	using "`srclocal'", assert(3) nogen
merge m:1 pull_item harmonized_nsu_unit using "`srcitem'", assert(3) nogen
label var source_nsu_units_here "raw NSU spellings observed in this municipality for this unit"
label var source_nsu_units_item "every raw NSU spelling folding to this unit for this item, anywhere"

********************************************************************************
**# 5b. FALLBACK LEVEL 1 -- a cell with any thin rung publishes one pooled weight
********************************************************************************
* THE RULE (issue #30, settled there). A size ladder cut from one or two weighings per
* rung is not a size distribution; it is noise with three labels on it. So where ANY rung
* in a cell is thin, the cell stops publishing per-rung weights and publishes a single
* median pooled across its rungs, at
*
*     province x municipality x item x harmonized_nsu_unit x corrected_unit
*
* WHOLE CELL, NOT THE THIN RUNGS ONLY, and that is the part worth understanding. Replacing
* only the thin rungs would leave one cell publishing `small' at its own median and
* `medium' at the cell-pooled median -- two different estimators inside one ladder, which
* can invert the size ordering. The monotonicity check further down exports exactly that
* as a defect, so a rung-by-rung rule would manufacture the failures it then reports.
*
* OUTCOME 1 STOPS HERE. It does not fall back to province x item, nor to item x unit. The
* reference set is the record of what was weighed in that cell; borrowing another
* municipality's weight into it changes what the table is. A cell with no weighing at all
* is absent from the table rather than imputed. Outcome 2's retrofit is where borrowing
* belongs, and its ladder continues past this point -- see 20_psps_retrofitting/
* 30_fallback.do.
*
* corrected_unit STAYS IN THE KEY. Pooling across rungs must never pool grams with
* millilitres.
*
* This does NOT rescue a thin cell, and must not be read as if it did: a cell whose rungs
* hold one weighing each pools to n_g = 2 and is still thin. It carries fallback_level = 1
* AND d_thin = 1, and both are published.
*
* ---- IT TAKES TWO RUNGS TO POOL --------------------------------------------------
* A CELL HOLDING ONE RUNG IS EXCLUDED, and the reason is that both justifications above
* are statements about a LADDER. There is no size distribution to be noise with three
* labels on it, and no second estimator to mix with, when the cell has exactly one rung.
* Collapsing it pools nothing: the median is taken over the same weighings either way and
* the published gram value is identical to the digit.
*
* What the collapse DID do to those rows was rename them. `size_ord' was overwritten with
* 4, "pooled across sizes", and `fallback_level' with 1, "cell pooled across sizes" -- so
* a row whose cell recorded exactly one size announced a pooling that never happened AND
* LOST THE SIZE IT MEASURED. 474 of the 962 collapsing cells were single-rung: 209 of them
* had published `small', 97 `medium', 53 `large', 108 were a price-quantity median and 7
* were conventional. The reference table could not tell a reader that 209 of its rows are
* the small the field went out and weighed.
*
* So the gate is `k_rungs >= 2'. Effects, all of them label-only: no gram value moves, no
* row is added or removed (a single-rung cell publishes one row either way), `n_g' and
* `d_thin' are untouched, and A3's sensitivity table does not shift. What changes is that
* fallback_level == 1 and size_ord == 4 now mean what they say -- asserted in section 5c.
tempvar anythin krungs
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	egen byte `anythin' = max(n_g < `THIN')

* One row per rung at this point -- the collapse in section 5 has already run -- so _N
* within the cell IS the rung count.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	gen byte `krungs' = _N

gen byte fallback_level = 0
replace  fallback_level = 1 if `anythin' == 1 & `krungs' >= 2

qui count if `anythin' == 1 & `krungs' == 1
di as res "5b single-rung thin cells left at their own size label: " r(N) ///
	" (nothing to pool; d_thin still flags them)"

qui count if fallback_level == 1
local n_pre = r(N)

* Re-collapse only the affected cells. The weighing-level median cannot be recovered from
* rung medians, so the pooled median is taken over the WEIGHINGS -- which is why this
* re-reads the pre-collapse data rather than averaging the rungs.
preserve
	keep if fallback_level == 1
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit
	duplicates drop
	tempfile thincells
	save "`thincells'"
restore

preserve
	use "${btemp}\ref_11_checked", clear
	merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		corrected_unit using "`thincells'", keep(3) nogen
	* Same counts, re-summed over the WEIGHINGS for the same reason the median is: a
	* pooled row's count of questioned weighings is not the sum of its rungs' counts once
	* a weighing can sit in more than one rung, and re-reading is the only reading that
	* cannot drift from the gram value beside it.
	collapse (median) grams = corrected_weight (count) n_g = corrected_weight ///
	         (sum) n_disputed = d_disputed n_flagged = d_step1_flagged ///
	               n_uncertain = d_any_uncertain ///
	         (first) weighing_approach branch d_reclassified, ///
	         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	            corrected_unit)
	* NOT 0 -- that code already means "conventional_nsu" in szlbl, and a pooled row is
	* not a conventional unit. 4 is a distinct code, added to the label below.
	*
	* Safe against the monotonicity check further down, which compares grams across
	* consecutive size_ord within a cell: a pooled cell holds exactly ONE row, since its
	* per-rung rows are dropped above, so `_n > 1' is never true for it and no comparison
	* is attempted. If that check is ever rewritten to compare across cells, this needs
	* an explicit exclusion.
	gen byte size_ord = 4
	gen byte fallback_level = 1

	* The source-spelling columns must be attached HERE TOO. This collapse re-reads
	* ref_11_checked and builds brand-new rows, so it does not inherit the merge in
	* section 5 -- and because these rows are appended, the missing values would be
	* silent: the column exists, the row is there, the cell is just blank. That is
	* exactly what happened on the first run, on all 486 pooled rows.
	* assert(2 3), not assert(3): this collapse holds ONLY the thin cells, so most rows
	* of the source lists have no pooled row to match and are legitimately unmatched.
	* What must never happen is a pooled row with no source list -- _merge == 1 -- which
	* is what assert(2 3) forbids. keep(3) then drops the unmatched using rows.
	merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		using "`srclocal'", assert(2 3) keep(3) nogen
	merge m:1 pull_item harmonized_nsu_unit using "`srcitem'", assert(2 3) keep(3) nogen

	* EVERY POOLED ROW MUST HAVE POOLED SOMETHING. The gate in 5b is on the rung count,
	* which is computed on the collapsed rows; this asserts the same fact from the other
	* side, on the WEIGHINGS -- a cell reaching here had at least two distinct size rungs
	* among its weighings. Two independent statements of one invariant, so a future edit to
	* either side cannot quietly reintroduce a one-rung "pooled" row.
	tempfile pooled
	save "`pooled'"
restore

* Same check at the weighing grain, before the append.
preserve
	use "${btemp}\ref_11_checked", clear
	merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		corrected_unit using "`thincells'", keep(3) nogen
	bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		corrected_unit: egen byte _nrung = nvals(size_ord)
	count if _nrung < 2
	if r(N) > 0 {
		di as err "a cell about to publish `pooled across sizes' holds only one size rung"
		exit 459
	}
restore

drop if fallback_level == 1
append using "`pooled'"
drop `anythin' `krungs'

qui count if fallback_level == 1
di as res _n "fallback level 1 (cell pooled across rungs): " r(N) " cell(s), from " ///
	"`n_pre' per-rung row(s)"
qui count if fallback_level == 1 & n_g < `THIN'
di as res "  of those, still thin after pooling: " r(N) ///
	" -- Outcome 1 has no further level, so they publish flagged"

* Code 4 carries the pooled rows created above; see the note there for why not 0.
label define szlbl 0 "conventional_nsu" 1 "small" 2 "medium" 3 "large" ///
	4 "pooled across sizes", replace
label values size_ord szlbl
gen byte d_thin = n_g < `THIN'

* ONE definition, in 00_globals.do, shared with the Outcome 2 ladder. Outcome 1 only ever
* uses codes 0 and 1, but it carries the same label set so the flag reads identically
* across the two deliverables.
def_fallback_level
label values fallback_level fallback_lbl
label var fallback_level "how this weight was arrived at; 0 = the cell's own weighings"

label var grams  "reference weight: median grams (or mL) for one unit of this size"
label var n_g    "weighings behind this estimate"
* THE THRESHOLD IS INTERPOLATED, not typed. This label used to read "fewer than 3", which
* is a second copy of ${THIN} living in a string -- and a string cannot be asserted, so
* moving the global would have left the deliverable's own column header stating the old
* cut to every reader of the .xlsx. Writing it from the global is the only version that
* cannot go stale.
label var d_thin "1 = fewer than ${THIN} weighings behind the estimate; treat as uncertain"
label var size_ord "size"

* ---- how much of this estimate was questioned (#35) --------------------------------
* A SHARE, not a dummy, and the denominator is n_g so the two columns are read together:
* 1 of 5 questioned is a different claim from 1 of 1, and a dummy cannot say which.
gen double share_uncertain = n_uncertain / n_g

label var n_disputed      "weighings behind this estimate where the two snap rules disagreed"
label var n_flagged       "weighings behind this estimate the anchor machinery distrusted"
label var n_uncertain     "weighings behind this estimate that are disputed or anchor-flagged"
label var share_uncertain "n_uncertain / n_g; 1 = nothing behind this estimate went unquestioned"

format share_uncertain %5.3f

qui count if share_uncertain > 0
local n_touch = r(N)
qui count if share_uncertain == 1
local n_all_u = r(N)
qui count
local n_pub = r(N)
di as res _n "uncertainty at the published grain (of `n_pub' rows):"
di as res "  resting on at least one questioned weighing  " %6.0fc `n_touch' ///
	"   " %5.1f 100 * `n_touch' / `n_pub' "%"
di as res "  resting ENTIRELY on questioned weighings     " %6.0fc `n_all_u' ///
	"   " %5.1f 100 * `n_all_u' / `n_pub' "%"
di as res "  Nothing is dropped or down-weighted here. The columns let a reader discount"
di as res "  what they judge should be discounted; that judgement is not the table's."

* EVERY exported column needs a label, because the export below uses
* firstrow(varlabels): an unlabelled variable falls back to its raw variable name, and a
* variable the collapse labelled keeps whatever the collapse wrote. This is a
* field-facing lookup table, and it was going out with three columns headed pull_item /
* pull_province / pull_municipal_city and a fourth headed "(first) weighing_approach" --
* collapse syntax leaking into a deliverable.
* Both new columns need a label for the same reason as the rest: the export uses
* firstrow(varlabels), so an unlabelled variable ships under its raw variable name.
label values branch branchlbl
label var branch         "how this row was PROCESSED (see weighing_approach for the field record)"
label var d_reclassified "1 = field-conventional, published size-based; its item x unit mixes approaches"
label var pull_item           "item"
label var pull_province       "province"
label var pull_municipal_city "municipality"
label var weighing_approach   "how this weight was measured in the field"

* Decoded, for the same reason size_ord is. These two sit side by side in the exported
* sheet, and size_ord was already exporting as "small"/"medium"/"large" while
* weighing_approach exported as a bare 1/2/3 with nothing in the file to decode it.
* Nothing reads this workbook programmatically -- it is read by people.
label define walbl 1 "conventional" 2 "price-quantity" 3 "size-based", replace
label values weighing_approach walbl

********************************************************************************
**# 5c. LABEL INVARIANTS -- every label must be true of every row carrying it
********************************************************************************
* WHY THIS BLOCK EXISTS. Three labels in this file were wrong on real published rows, and
* all three failed the same way: THE LABEL WAS WRITTEN BY THE CODE PATH THE ROW TRAVELLED
* THROUGH RATHER THAN DERIVED FROM WHAT HAPPENED TO THE ROW. A path is named for its
* typical effect -- "pooled across sizes" -- and then every row entering it inherits that
* name, including the rows the effect never touched. 474 rows announced a pooling that did
* not happen and lost the size they had measured; up to 123 more carried "own cell x size"
* with no size dimension to speak of.
*
* A row-count assertion is what this project already uses to stop a hand correction
* matching nothing (05_manual_corrections.do). This is the same instrument pointed at
* labels: each assertion states a label's own claim and fails the build where a row cannot
* support it. Adding a label to the published file means adding its claim here.
*
* These are cheap. They are also the only thing standing between a label and a reader who
* has no way to check it.

* --- size_ord ------------------------------------------------------------------
* 0 "conventional_nsu": exactly the always-conventional branch, no more and no fewer.
assert (size_ord == 0) == (branch == 1)

* 4 "pooled across sizes": the cell pooled >= 2 rungs, so it publishes ONE row, and that
* row must be the cell's only row. If a size_ord 4 row ever sits beside a sized row, the
* collapse ran on part of a cell and the monotonicity check below cannot see it.
tempvar n_in_cell n_pooled
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	gen int `n_in_cell' = _N
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	egen byte `n_pooled' = total(size_ord == 4)
assert `n_in_cell' == 1 if size_ord == 4
assert `n_pooled' == 0 | `n_pooled' == `n_in_cell'
drop `n_in_cell' `n_pooled'

* --- fallback_level ------------------------------------------------------------
* Outcome 1 stops at L1, so 2 and 3 cannot occur here. Asserted rather than assumed: the
* label set is shared with the Outcome 2 ladder, where they do occur.
assert inlist(fallback_level, 0, 1)

* 1 "cell pooled across sizes" and size_ord 4 are the same event seen twice. Neither may
* appear without the other.
assert (fallback_level == 1) == (size_ord == 4)

* 0 "the cell's own weighings" -- true of every remaining row by construction, since
* nothing in Outcome 1 borrows. The claim worth asserting is the negative one: no row at
* level 0 may be a pooled row.
assert size_ord != 4 if fallback_level == 0

* --- d_thin --------------------------------------------------------------------
* d_thin is a reading of n_g and nothing else. If these ever diverge, the flag has
* acquired a second meaning and the .xlsx column header is no longer accurate.
assert d_thin == (n_g < `THIN')
assert n_g >= 1

* --- d_reclassified ------------------------------------------------------------
* 08_branch.do owns this; re-asserted at the point of publication because the label makes
* a claim about `weighing_approach' that only holds if the two columns still disagree
* exactly where the flag says they do.
assert d_reclassified == (branch != weighing_approach)
assert weighing_approach == 1 & branch == 3 if d_reclassified == 1

* A reclassified row is never terciled -- A12, and it is why the row publishes as medium
* or as its cell's pooled value and nothing else.
assert inlist(size_ord, 2, 4) if d_reclassified == 1

* --- the uncertainty counts (#35) ----------------------------------------------
* Each count is bounded by the number of weighings it counts within. A count above n_g
* would mean the collapse summed a different set of rows from the one it counted -- the
* exact failure that makes a share meaningless while still printing a plausible number.
assert n_disputed  <= n_g
assert n_flagged   <= n_g
assert n_uncertain <= n_g

* n_uncertain is the OR of the parts, so it is at least as large as each and no larger
* than their sum. Stated at the published grain as well as at the weighing grain in
* 08_branch.do, because the collapse is what could break the relationship.
assert n_uncertain >= n_disputed
assert n_uncertain >= n_flagged
assert n_uncertain <= n_disputed + n_flagged

* The share is a reading of the two columns beside it and nothing else, and it is the
* column a reader will actually filter on.
assert reldif(share_uncertain, n_uncertain / n_g) < 1e-12
assert inrange(share_uncertain, 0, 1)

di as res _n "5c label invariants: all pass"

* grams must rise with size within a case, or the table is visibly wrong to a user
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
       corrected_unit (size_ord): gen byte nonmono = (grams < grams[_n-1]) if _n > 1 & size_ord > 0
count if nonmono == 1
di as res "size pairs where grams FALLS as size rises: " r(N)
if r(N) > 0 {
	export excel using "${btables}\ref_nonmonotonic.xlsx" if nonmono == 1, ///
		replace firstrow(variables)
}

********************************************************************************
* THE VIOLATION IS PUBLISHED, NOT JUST EXPORTED
********************************************************************************
* This check used to write a side file and say nothing in the deliverable. That left the
* table's most basic promise -- that "large" outweighs "small" -- unenforced AND
* unannounced: a reader pulling one row, which is exactly what this table is for, had no
* way to learn that its size label might be backwards. The side file only helps someone
* who already suspected.
*
* IT IS A FLAG RATHER THAN AN `assert', deliberately. The violation is real and it is not
* a coding error: on the price-quantity branch `size_ord' comes from the PRICE rank
* (mp25 -> small, mp50 -> medium, mp75 -> large), so "medium" there names a price point
* and carries no claim about weight. Where a mid-priced unit genuinely weighs less than a
* cheap one, the ladder inverts and the data is right. Halting the build would force the
* row to be deleted or the label to be falsified; flagging it keeps the number and tells
* the truth about it.
*
* THE FLAG IS ON EVERY ROW OF THE CELL, not only the row that falls. The comparison is
* between two rows, so a reader filtering on the lower one alone would still take the
* other at face value, and the size ordering is a property of the ladder rather than of
* one rung.
* NOT a `tempvar'. Stata drops a tempvar when the DO-FILE ends, and the save is before
* that -- so a tempvar still in memory here ships as a junk `__000004' column in both
* nsu_reference_set.dta and the .xlsx a field team opens. Named and dropped explicitly.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	egen byte _cellmono = max(nonmono == 1)
gen byte d_size_nonmono = (_cellmono == 1)
drop _cellmono
label var d_size_nonmono ///
	"1 = grams do not rise with size_ord in this cell; the size label is a price rank"

qui count if d_size_nonmono
di as res "  rows carrying d_size_nonmono (the whole cell, not just the falling rung): " r(N)
if r(N) > 0 {
	di as res "  These publish their measured grams. On the price-quantity branch size_ord"
	di as res "  is a price rank, so an inverted ladder can be the data rather than a bug."
	list pull_province pull_municipal_city pull_item harmonized_nsu_unit size_ord ///
		grams n_g n_uncertain branch if d_size_nonmono, noobs abbrev(24) sep(0)
}

* The flag must be true of the cell it marks, and of every row in it -- the same standard
* section 5c holds every other label to.
assert d_size_nonmono == 1 if nonmono == 1
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit: ///
	assert d_size_nonmono == d_size_nonmono[1]

drop nonmono

* NOTHING TEMPORARY MAY SHIP. A `tempvar' is dropped when the do-file ENDS, which is
* after this save, so any tempvar still in memory here lands in the deliverable and in
* the .xlsx a field team opens -- once as a column literally headed `__000004'. Every
* label in this file is asserted true of its row; a column with no name at all deserves
* the same treatment, and it is one line.
* `ds' EXITS 111 WHEN NOTHING MATCHES, which is the clean case -- so the test is on the
* return code and success is the failure. Written the other way round it halted every
* build that had nothing wrong with it.
capture ds __*
if _rc == 0 {
	di as err "temporary variable(s) still in memory at save: `r(varlist)'"
	di as err "Name and drop them -- a tempvar survives to here and ships."
	exit 459
}

* EVERY ROW NAMES THE SPELLINGS BEHIND IT. A merge with assert(3) cannot catch this:
* the pooled rows of section 5b are built by a separate collapse and APPENDED, so a
* missing source list arrives as a blank cell in a column that exists, on a row that is
* present, and nothing complains. That is how all 486 pooled rows shipped empty the
* first time. The count is asserted, not just the presence of the column.
qui count if missing(source_nsu_units_here) | source_nsu_units_here == ""
if r(N) > 0 {
	di as err "`r(N)' published row(s) carry no source_nsu_units_here."
	di as err "A step that CREATES rows after section 5 must attach the source lists"
	di as err "itself -- see the merges in 5b. Appended rows inherit nothing."
	list pull_province pull_municipal_city pull_item harmonized_nsu_unit size_ord ///
		if missing(source_nsu_units_here) | source_nsu_units_here == "", noobs
	exit 459
}
qui count if missing(source_nsu_units_item) | source_nsu_units_item == ""
assert r(N) == 0

compress
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit size_ord
save "${bdeliv}\nsu_reference_set.dta", replace
export excel using "${bdeliv}\nsu_reference_set.xlsx", replace firstrow(varlabels)


********************************************************************************
**# 6. Report
********************************************************************************

count
di as res _n "reference-set rows: " r(N)
di as txt _n "rows by size:"
tab size_ord, m
di as txt _n "rows by weighing approach:"
tab weighing_approach, m
di as txt _n "thin estimates (n_g < `THIN'):"
tab d_thin, m
qui su n_g, detail
di as txt "weighings behind an estimate -- min `r(min)', p25 `r(p25)', median `r(p50)', max `r(max)'"

di as txt _n "how much of each estimate was questioned (#35):"
tab share_uncertain, m

di as res _n "OUTCOME 1 complete."
