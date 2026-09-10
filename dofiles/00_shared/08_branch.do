********************************************************************************
* 08_branch.do -- `branch': how a weighing is PROCESSED, as against what the field did
*
* WHY THIS EXISTS. The conventional branch publishes one weight per case, with no size
* and no price dimension. That is defensible only if "conventional" is a property of the
* UNIT. It is not: `weighing_approach' is preloaded per (municipality, item, unit) cell,
* and 13 of the 21 labels that appear as conventional somewhere also appear under
* size-based or price-quantity elsewhere -- always on the SAME item. So for those,
* "conventional" records what a cell was assigned, not what the unit is.
*
* The instrument makes it worse rather than better. `weighing_approach' is a `calculate'
* field pulled from the case file, and where two approaches were preloaded the enumerator
* picks between them from a choice list that contains only price-quantity and size-based.
* **Conventional is not an option a field officer can select.** It is never a field
* judgement; it is an assignment made when the case list was built, with no way to correct
* it. See issue #28 Q1-Q3.
*
* THE RULE (decided on #28):
*
*     branch = weighing_approach, except
*              conventional AND its (item, harmonized unit) pair appears under another
*              approach somewhere else in the data  ->  size-based
*
* `weighing_approach' IS NOT OVERWRITTEN, and that is not tidiness. It is the field record,
* and the evidence for this very decision is keyed on it -- "13 of 21 labels appear under
* more than one approach" is a statement about what the field did. Overwriting it would
* erase the finding that motivated the change. Both variables ship.
*
* ------------------------------------------------------------------------------
* WHICH VARIABLE TO USE, AND WHY GETTING IT BACKWARDS IS A REAL ERROR
*
*   Use `branch'            wherever the code decides how a weighing is PROCESSED or
*                           PUBLISHED -- size assignment, the reference set, the retrofit,
*                           and any diagnostic describing shipped rows.
*   Use `weighing_approach' wherever the code describes WHAT THE FIELD DID -- the
*                           conventional-units audit, the dispersion measurements, the raw
*                           file summaries, the attrition ledger.
*
* Every site falls into one or the other. `branch' in an audit hides the finding that
* motivated it: `scope_conventional_units.py' run on `branch' returns "no mixed pairs",
* the finding erasing itself. `weighing_approach' in the build silently keeps the old
* behaviour. dofiles/README.md carries the site-by-site split.
*
* VERIFIED SAFE, no change needed: `07_cpi_factor.do'. Its vendor-price rule tests
* `weighing_approach == 2' and no row moves into or out of price-quantity. Its invariant is
* `inlist(weighing_approach, 1, 3) & cpi_factor != 1', and the reclassification moves rows
* from 1 to 3 -- both inside that list -- so it holds whichever variable it reads. Checked
* rather than assumed, because a silent break there would apply an inflation adjustment to
* a weight never denominated in money.
*
* WHAT THIS DOES NOT DECIDE. Where a reclassified case lands in the size ladder is
* `10_size_assignment.do''s business, not this file's. Those cases were weighed AS
* conventional, so they carry no S/M/L labels to tercile and no price point per weighing;
* they publish as a single "medium" group. `docs/implicit_assumptions.md' A12 records that
* medium is the better of two defensible choices rather than a measured result -- the
* conventional median sits at the size-based medium with a ratio median of 1.00
* (IQR 0.93-1.25), but is equally close to the small tercile on average log-distance.
*
* CALLED BY   master_outcome1.do and master_outcome2.do, after 07_cpi_factor.do and before
*             anything that assigns sizes.
*
* IN / OUT    ${btemp}\nsu_weighings_cpi.dta, augmented in place with `branch',
*             `d_reclassified' and the four uncertainty flags below.
*
* IT ALSO OWNS THE UNCERTAINTY FLAGS, for the same reason it owns `branch': this is the
* last step both masters share, so a variable defined here reaches both deliverables with
* one definition. See the block at the foot of this file and #35.
********************************************************************************

clear all
set more off
do "00_shared/00_globals.do"

use "${btemp}\nsu_weighings_cpi", clear

* ---- which (item, harmonized unit) pairs mix conventional with another approach -------
* Keyed on the HARMONIZED unit, and on the item, with no geography. The claim being made
* is about the unit's nature: if the same item x unit is treated as size- or price-varying
* anywhere in the sample, then it is not a standard measure and the conventional
* assignment in this cell describes the cell rather than the unit.
*
* Measured on `weighing_approach', necessarily -- this is a statement about the field
* record, and it is the one place in the build that must read it rather than `branch'.
egen byte _conv_here  = max(weighing_approach == 1), by(pull_item harmonized_nsu_unit)
egen byte _other_here = max(inlist(weighing_approach, 2, 3)), by(pull_item harmonized_nsu_unit)

gen byte _mixed_pair = (_conv_here == 1 & _other_here == 1)

* ---- branch -------------------------------------------------------------------
gen byte branch = weighing_approach
replace  branch = 3 if weighing_approach == 1 & _mixed_pair == 1

gen byte d_reclassified = (branch != weighing_approach)

* The value label on weighing_approach is itself named `weighing_approach'. Copied rather
* than shared, so a future edit to one variable's labelling cannot silently relabel the
* other -- the two variables mean different things and are meant to be read side by side.
capture label drop branchlbl
label copy  weighing_approach branchlbl
label values branch branchlbl
label var branch "how this weighing is PROCESSED; = weighing_approach unless reclassified"
label var d_reclassified ///
	"1 = field-conventional, processed size-based: its item x unit mixes approaches"

* ---- what the rule did, and the invariant it rests on -------------------------
qui count if d_reclassified
local n_w = r(N)

* Counted by tagging one row per case, not with `tab', whose r(r) is capped by matsize and
* would fail on a wave with more reclassified cases than this one has.
egen long _case = group(pull_province pull_municipal_city pull_item harmonized_nsu_unit)
egen byte _tag_rc = tag(_case) if d_reclassified
qui count if _tag_rc == 1
local n_c = r(N)
drop _tag_rc

di as res _n "08_branch.do -- reclassified: `n_w' weighing(s) in `n_c' case(s)"
di as res "branch vs weighing_approach:"
tab weighing_approach branch, m

* NO CASE MAY MIX conventional with another approach INTERNALLY. The whole rule assumes
* the mixing is across municipalities, so that a case moves as a unit and none has to be
* split. #28 verified this on the raw data; asserting it here means a future wave that
* breaks the assumption fails loudly instead of silently splitting a case.
egen byte _conv_in_case  = max(weighing_approach == 1), by(_case)
egen byte _other_in_case = max(inlist(weighing_approach, 2, 3)), by(_case)
count if _conv_in_case == 1 & _other_in_case == 1
if r(N) > 0 {
	di as err "08_branch.do: " r(N) " weighing(s) sit in a case that mixes conventional"
	di as err "with another approach INTERNALLY. The reclassification assumes cases move"
	di as err "whole; such a case would have to be split, which no downstream step handles."
	exit 459
}

* A reclassified weighing must be conventional in the field record and size-based in the
* branch. Anything else means the replace above caught a row it should not have.
assert weighing_approach == 1 & branch == 3 if d_reclassified
assert branch == weighing_approach if !d_reclassified

drop _conv_here _other_here _mixed_pair _case _conv_in_case _other_in_case

********************************************************************************
* THE UNCERTAINTY FLAGS -- defined here, once, because both outcomes read this file
*
* WHY HERE. A published conversion factor should say whether the weight behind it was
* questioned. Three different things get conflated if they are not separated, and they
* need different follow-up:
*
*   d_unusable        no interpretation of the reading was defensible, so the weight is .c
*   d_disputed        the two snap rules disagreed and one had to be chosen
*   d_step1_flagged   the anchor machinery distrusted its own answer
*
* NOTHING IS DERIVED HERE. Each flag is read off a column the build already carries --
* `corrected_weight', `snap_block' and `review_step1' -- so this block records a decision
* made upstream rather than re-deciding it. `snap_block == 1' means the published value is
* not STEP 1's answer, which is exactly what "the rules disagreed" means; recomputing the
* block rule here would put a second copy of it in the pipeline.
*
* WHY NOT READ THE DIAGNOSTIC'S CSV. `weight_correction_report.csv' publishes these same
* three flags, and reading it would be shorter. It is forbidden: a build step that reads a
* diagnostic output is the orphan-input defect of #33, and it would make the build
* unreproducible from the raw files alone. The direction is the other way round -- the
* diagnostic reads these columns.
*
* THIS IS THE ONLY DEFINITION. 08 is the last step both masters share, so both deliverables
* inherit the same four variables and neither can re-implement them differently. That is
* the consolidation #32 forced on the string normalizers, applied before the duplication
* has a chance to appear.
*
* WHAT THE FLAGS DO NOT SAY. That a weight was questioned, not by how much it could be
* wrong. There is no interval here and none is implied. See #35 and A20.
********************************************************************************

gen byte d_unusable      = missing(corrected_weight)
gen byte d_disputed      = (snap_block == 1) & !d_unusable
gen byte d_step1_flagged = (review_step1 == 1)
gen byte d_any_uncertain = d_unusable | d_disputed | d_step1_flagged

label var d_unusable      "1 = no defensible reading; weight is .c"
label var d_disputed      "1 = the two snap rules disagreed and one had to be chosen"
label var d_step1_flagged "1 = the anchor machinery distrusted its own answer"
label var d_any_uncertain "1 = disputed, anchor-flagged or unusable; see #35"

* The source columns must exist and must be the ones these flags claim to read. A missing
* column would make `snap_block == 1' silently false for every row and publish a table
* saying nothing was ever disputed -- which is the failure this whole block exists to
* prevent, arriving as a clean build.
confirm numeric variable corrected_weight snap_block review_step1

* d_any_uncertain is an OR, so it must be at least as large as each part and no larger
* than their sum. Cheap, and it catches a future edit that turns the OR into an AND.
assert d_any_uncertain >= d_unusable
assert d_any_uncertain >= d_disputed
assert d_any_uncertain >= d_step1_flagged
assert d_any_uncertain <= d_unusable + d_disputed + d_step1_flagged

* An unusable weighing cannot also be disputed: there was no published value to dispute.
assert !(d_unusable == 1 & d_disputed == 1)

qui count
local n_all = r(N)
di as res _n "08_branch.do -- uncertainty flags on `n_all' priced weighings:"
foreach v in d_unusable d_disputed d_step1_flagged d_any_uncertain {
	qui count if `v' == 1
	di as res "  " %-18s "`v'" %8.0fc r(N) "   " %5.1f 100 * r(N) / `n_all' "%"
}

* Read against branch, because a branch carrying disproportionate uncertainty would change
* how the three Outcome 2 branch builds should be read.
di as res _n "share uncertain by branch:"
table branch, statistic(frequency) statistic(mean d_any_uncertain) nformat(%9.3f)

save "${btemp}\nsu_weighings_cpi", replace
di as txt "08_branch.do: wrote branch, d_reclassified and the four uncertainty flags"
