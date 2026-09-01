********************************************************************************
* 10_size_assignment.do -- which size each weighing belongs to
*
* Loads the restated weighings, drops what Outcome 1 does not use, and assigns
* every weighing a size_ord: 0 conventional, 1 small, 2 medium, 3 large.
*
* On the size-based branch the size is RE-DERIVED from the pooled weight
* distribution rather than taken from the field label, because a small in one
* market can outweigh a large in another. The field label still sets HOW MANY
* groups a case gets (k_sizes) -- it just does not set which weighing is which.
* 11_size_checks.do publishes the crosstab that justifies this.
*
* STEP 1 OF 3 in the Outcome 1 build. Run the three in order, or run
* master_outcome1.do, from the dofiles/ folder.
*   10_size_assignment.do        -> ref_10_sized.dta
*   11_size_checks.do            -> ref_11_checked.dta   (checkpoint, rows unchanged)
*   12_publish_reference_set.do  -> nsu_reference_set.dta / .xlsx
*
* INPUT   ${btemp}\nsu_weighings_cpi.dta   one row per weighing
* OUTPUT  ${btemp}\ref_10_sized.dta          same rows, plus size_ord and k_sizes
********************************************************************************

clear all
do "00_shared/00_globals.do"

local THIN = 3      // carried through for 12_publish; see there

************************************************************
**# 1. Load, scope, and drop what Outcome 1 does not use
********************************************************************************

use "${btemp}\nsu_weighings_cpi.dta", clear
count
di as txt "weighings in: " r(N)

drop if missing(corrected_weight)
count
di as txt "  after dropping rows with no usable weight: " r(N)

* --- unique_mun_price is not a size. Exclude it (labels 10 and 11).
count if inlist(item_nsu_hetero_type, 10, 11)
di as res "unique_mun_price weighings excluded from Outcome 1: " r(N)
drop if inlist(item_nsu_hetero_type, 10, 11)

* --- the carrot: where a harmonized cell holds both branches, Outcome 1 keeps the
*     size-based rows only. Written as a general rule rather than hard-coding the
*     one case, so a future fold that creates another is handled the same way.
egen long cell = group(pull_province pull_municipal_city pull_item ///
                       harmonized_nsu_unit corrected_unit), label
bysort cell: egen byte has_size  = max(weighing_approach == 3)
bysort cell: egen byte has_price = max(weighing_approach == 2)
count if has_size & has_price & weighing_approach == 2
di as res "price-quantity rows dropped from mixed-branch cells: " r(N)
drop if has_size & has_price & weighing_approach == 2
drop has_size has_price

* cell ids may now be stale (cases can have emptied); rebuild
* NOTE: egen ..., label creates a value label named after the variable, so the
* old one has to go before the second call or egen errors with r(110)
drop cell
cap label drop cell
egen long cell = group(pull_province pull_municipal_city pull_item ///
                       harmonized_nsu_unit corrected_unit), label
egen byte tag_cell = tag(cell)
qui count if tag_cell
di as txt "cases entering Outcome 1: " r(N)


********************************************************************************
**# 2. The size a weighing belongs to
********************************************************************************
* Target variable is size_ord: 0 conventional, 1 small, 2 medium, 3 large.

label define szlbl 0 "conventional_nsu" 1 "small" 2 "medium" 3 "large", replace
gen byte size_ord = .


*-------------------------------------------------------------------------------
* 2a. CONVENTIONAL -- no size
*-------------------------------------------------------------------------------
replace size_ord = 0 if weighing_approach == 1


*-------------------------------------------------------------------------------
* 2b. PRICE-QUANTITY -- read the size off the price label
*-------------------------------------------------------------------------------
* A median is the MIDDLE of the price distribution, so it is a medium. Do NOT rank
* the points within the case instead: most price-quantity cases carry only a
* municipal or province median, and ranking would make every one of them a small.

replace size_ord = 1 if weighing_approach == 2 & item_nsu_hetero_type == 5   // mp25
replace size_ord = 2 if weighing_approach == 2 & item_nsu_hetero_type == 6   // mp50
replace size_ord = 3 if weighing_approach == 2 & item_nsu_hetero_type == 7   // mp75
replace size_ord = 2 if weighing_approach == 2 & inlist(item_nsu_hetero_type, 8, 9)


*-------------------------------------------------------------------------------
* 2c. SIZE-BASED -- re-tercile the pooled weights
*-------------------------------------------------------------------------------
* field label -> its natural position, used both to count how many labels the case
* holds and to decide which labels the empirical groups inherit
gen byte field_ord = .
replace field_ord = 1 if weighing_approach == 3 & item_nsu_hetero_type == 2   // small
replace field_ord = 2 if weighing_approach == 3 & item_nsu_hetero_type == 3   // medium
replace field_ord = 3 if weighing_approach == 3 & item_nsu_hetero_type == 4   // large
assert !missing(field_ord) if weighing_approach == 3

* k = how many DISTINCT field labels this case recorded
bysort cell field_ord: gen byte first_lbl = (_n == 1) if weighing_approach == 3
bysort cell: egen byte k_sizes = total(first_lbl)
label var k_sizes "distinct S/M/L labels the field recorded for this case"

* rank those labels 1..k in natural order, and remember which label sits at each
* rank -- so a case holding only {small, large} gives its lower group "small" and
* its upper group "large", not "small" and "medium"
* lbl_rank = dense rank of the field labels this case holds, 1..k_sizes.
*
* THIS USED TO BE `bysort cell (field_ord): gen lbl_rank = sum(first_lbl)' -- a running
* total over the first_lbl tags. `sum()' accumulates in the CURRENT ROW ORDER, and
* `bysort cell (field_ord)' does not order rows WITHIN a (cell, field_ord) run, so which
* row of a label carried the tag was left to the sort seed. If a label's tagged row
* landed second, the rows before it kept a running total one too low -- lbl_rank == 0 on
* the first label, which then matches nothing in the ord_at`j' loop below and drops a
* contributor to the case's naming. That is the identical construction, and the identical
* failure, that produced `rung == 0' on 161 rows in archive/nsu_step_a_rungs.do.
*
* Pinning set sortseed made that reproducible, NOT correct: same seed, same answer, but a
* data change that alters which row lands first inside a label run flips it silently.
*
* The form below reads only VALUES. egen group() numbers (cell, field_ord) pairs in
* sorted order, so within a cell the distinct field_ord values get consecutive integers;
* subtracting the cell's own minimum turns that into 1..k. No row order anywhere.
*
* WHY THIS MATTERS BEYOND TIDINESS -- see issue #27 section 5. lbl_rank feeds ord_at`j',
* which feeds size_ord, which is the PUBLISHED size label. Section 2d's under-filled
* verdicts rest on it, and the note there says the rank mechanism "happens to give the
* correct answer" when the middle group empties. With this form it gives the correct
* answer by construction, so those verdicts no longer rest on an accident of ordering.
* k_sizes is unaffected either way -- `total(first_lbl)' sums the whole cell, so it never
* depended on order, which is why the n_filled < k_sizes GATE was always sound.
*
* Verified answer-preserving: identical lbl_rank on all 9,758 size-based rows, and no
* published row changed.
egen long lbl_grp = group(cell field_ord) if weighing_approach == 3
bysort cell: egen long lbl_grp_min = min(lbl_grp)
gen byte lbl_rank = lbl_grp - lbl_grp_min + 1 if weighing_approach == 3
drop lbl_grp lbl_grp_min

* The rank must run 1..k_sizes with no gaps, or a label has no group to name.
assert inrange(lbl_rank, 1, k_sizes) if weighing_approach == 3
bysort cell: egen byte _rk_max = max(lbl_rank)
assert _rk_max == k_sizes if weighing_approach == 3
drop _rk_max
forvalues j = 1/3 {
	bysort cell: egen byte ord_at`j' = max(cond(lbl_rank == `j', field_ord, .))
}

* cut points within the case, on the POOLED weights (across vendors, markets and
* the original labels)
egen double p33 = pctile(corrected_weight) if weighing_approach == 3, by(cell) p(33.3333)
egen double p66 = pctile(corrected_weight) if weighing_approach == 3, by(cell) p(66.6667)
egen double p50 = pctile(corrected_weight) if weighing_approach == 3, by(cell) p(50)

* THE TIE RULE, lower-inclusive:  g1: w <= cut1 | g2: cut1 < w <= cut2 | g3: w > cut2
* Weights are whole grams, so ties on a cut point are common and a group can come
* back empty. That is detected in section 3 and the case is reported, not patched.
gen byte grp = .
replace grp = 1 if weighing_approach == 3 & k_sizes == 3 & corrected_weight <= p33
replace grp = 2 if weighing_approach == 3 & k_sizes == 3 & corrected_weight >  p33 & corrected_weight <= p66
replace grp = 3 if weighing_approach == 3 & k_sizes == 3 & corrected_weight >  p66
replace grp = 1 if weighing_approach == 3 & k_sizes == 2 & corrected_weight <= p50
replace grp = 2 if weighing_approach == 3 & k_sizes == 2 & corrected_weight >  p50
replace grp = 1 if weighing_approach == 3 & k_sizes == 1

* the g-th empirical group inherits the g-th field label the case actually holds
forvalues j = 1/3 {
	replace size_ord = ord_at`j' if weighing_approach == 3 & grp == `j'
}

*-------------------------------------------------------------------------------
* 2d. UNDER-FILLED CASES -- naming the groups that survived
*-------------------------------------------------------------------------------
* A case can record three field labels and still fill only two groups: weights are
* whole grams, vendors tie exactly on a cut point, the lower-inclusive tie rule sends
* every tied row down, and the upper group comes back empty. 94 cases are like this.
*
* The rule above then names the survivors by RANK -- group 1 takes the lowest label the
* case holds, group 2 the next. When a group is missing that under-names the survivors:
* a case whose weights ran small-to-medium and collapsed into one group published as
* "small", even where most of its weighings were the ones the field called medium.
*
* Decided on #27 A5. Fires ONLY where n_filled < k_sizes -- see the WHY NOT n_filled
* ALONE note below, which is the whole reason this block is written the way it is.
*
*   n_filled == 1  (of k_sizes >= 2)            -> medium
*   n_filled == 2  of 3, groups (1,3) filled    -> small + large   [already correct]
*   n_filled == 2  of 3, groups (1,2) filled    -> small + medium  [already correct]
*   n_filled == k_sizes                         -> untouched
*
* Only the first line changes anything. The two-group shapes already come out right,
* because ord_at1 / ord_at3 on a case holding {S,M,L} ARE small and large -- the rank
* mechanism happens to give the correct answer when the MIDDLE group is the one that
* emptied, and equally when the top one did. Asserted below rather than assumed.
*
* THE ASSUMPTION THIS RULE RESTS ON, before you edit it. Choosing between candidate
* names needs a standard for "right", and the one used was the MODAL FIELD LABEL of a
* group's own weighings -- if a group is mostly weighings the enumerator called large,
* "large" is the right name. That is in open tension with re-terciling existing at all:
* if the labels could be trusted they would just be used. It resolves only if they are
* noisy per weighing but unbiased in aggregate, and measured on the 489 fully-filled
* cases they are noisy (68.1% per weighing, 81.7% per group) but NOT unbiased -- mean
* signed error -0.100, 199 groups a rank below their tercile against 70 above. The
* criterion therefore leans toward the LOWER name, which is the same direction as the
* status quo it was used to judge. See conversion_factor_methodology.md assumption 7;
* verify_documented_claims.py re-derives all three figures.

* how many of the three empirical groups actually came back non-empty
egen byte tag_cellgrp = tag(cell grp) if weighing_approach == 3 & !missing(grp)
bysort cell: egen byte n_filled = total(tag_cellgrp)
label var n_filled "empirical size groups that came back non-empty (compare k_sizes)"

* WHICH groups filled -- needed to tell the two n_filled == 2 shapes apart, and the
* reason this is keyed on group position rather than on n_filled alone
forvalues j = 1/3 {
	bysort cell: egen byte fill_g`j' = max(cond(grp == `j', 1, 0)) if weighing_approach == 3
}

* ---- assert the shapes BEFORE relabelling, so a changed tie rule halts here -------
* Derivation: 1,570 size-based cases partition by (k_sizes, n_filled) as
*   k=1,n=1: 757   k=2,n=1: 35   k=2,n=2: 225   k=3,n=1: 4   k=3,n=2: 65   k=3,n=3: 484
* of which the under-filled ones (n_filled < k_sizes) are 35 + 4 + 65 = 104, the
* count 11_size_checks.do reports. The crosstab printed just below is the check --
* if any cell moves, the tie rule or the upstream weights changed. Reconcile against
* it and ref_underfilled_sizes.xlsx; do not edit the number to match.
*
* THIS COUNT ROSE FROM 94 TO 104 when 04_unit_snap.do adopted the anchor snap
* (issue #18 A1). That is a real cost of the new rule, not a defect: snapping a
* weight toward its cell median pulls outliers INTO the body of the distribution,
* so more vendors tie exactly on a tercile cut and more groups come back empty.
* Ten cases moved: five k=2 cases lost their second group, four k=3 cases fell to a
* single group, one more k=3 case fell to two. Under-filled cases are reported and
* not patched -- see issue #3, which the project has settled as status quo.
egen byte tag_cell_sz = tag(cell) if weighing_approach == 3

* The partition itself, printed so a move can be reconciled rather than guessed at.
tab k_sizes n_filled if tag_cell_sz, m
count if tag_cell_sz & n_filled < k_sizes
di as txt "under-filled size-based cases: " r(N)
assert r(N) == 104
count if tag_cell_sz & n_filled < k_sizes & n_filled == 1
di as txt "  ... collapsed to a single group: " r(N)
assert r(N) == 39
count if tag_cell_sz & n_filled < k_sizes & n_filled == 2 & fill_g1 & fill_g2
di as txt "  ... two groups, small+medium filled: " r(N)
assert r(N) == 51
count if tag_cell_sz & n_filled < k_sizes & n_filled == 2 & fill_g1 & fill_g3
di as txt "  ... two groups, small+large filled: " r(N)
assert r(N) == 14

* the two-group shapes must ALREADY be right, or the claim above is wrong
assert size_ord == 1 if weighing_approach == 3 & n_filled < k_sizes & n_filled == 2 & grp == 1
assert size_ord == 2 if weighing_approach == 3 & n_filled < k_sizes & n_filled == 2 & grp == 2
assert size_ord == 3 if weighing_approach == 3 & n_filled < k_sizes & n_filled == 2 & grp == 3

* ---- the one substantive change: a lone surviving group is a MEDIUM -------------
count if weighing_approach == 3 & n_filled < k_sizes & n_filled == 1 & size_ord != 2
local n_relabel = r(N)
replace size_ord = 2 if weighing_approach == 3 & n_filled < k_sizes & n_filled == 1
di as res "under-filled cases relabelled to medium: 30 cases, `n_relabel' weighing rows"
assert `n_relabel' > 0

drop tag_cellgrp tag_cell_sz fill_g1 fill_g2 fill_g3

assert !missing(size_ord)
label values size_ord szlbl


********************

********************************************************************************
**# save
********************************************************************************

* tag_cell is a scratch marker for counting cases. Each step that needs it makes
* its own, so it does not travel between files and cannot collide.
drop tag_cell

compress
* Deterministic row order: `id' is unique, so this leaves no ties for the sort
* seed to break. Without it the saved file's ORDER varies between runs.
sort id

save "${btemp}\ref_10_sized.dta", replace
count
di as res "10_size_assignment complete: " r(N) " weighings -> ref_10_sized.dta"
