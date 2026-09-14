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

local THIN = ${THIN}      // ONE definition, in 00_globals.do -- do not retype the value

************************************************************
**# 1. Load, scope, and drop what Outcome 1 does not use
********************************************************************************

use "${btemp}\nsu_weighings_cpi.dta", clear

* `branch' and `d_reclassified' come from 00_shared/08_branch.do, which must run first.
* Without them 2a below would fall back to no-size treatment for all 468 field-conventional
* weighings and #28's reclassification would silently not happen -- the exact failure mode
* worth an explicit stop rather than a wrong number.
foreach v in branch d_reclassified {
	capture confirm variable `v'
	if _rc {
		di as err "10_size_assignment.do: `v' not found. Run 00_shared/08_branch.do first;"
		di as err "master_outcome1.do and master_outcome2.do both call it after 07."
		exit 111
	}
}
count
di as txt "weighings in: " r(N)

drop if missing(corrected_weight)
count
di as txt "  after dropping rows with no usable weight: " r(N)

* --- unique_mun_price is not a size. Exclude it (labels 10 and 11).
count if inlist(item_nsu_hetero_type, 10, 11)
di as res "unique_mun_price weighings excluded from Outcome 1: " r(N)
drop if inlist(item_nsu_hetero_type, 10, 11)

* --- NOT A REUSABLE LOCAL UNIT. Outcome 1 is a reference book: an enumerator meets a
*     vendor, hears a unit name, and looks up what it weighs. That only works for a
*     label that NAMES A UNIT someone else will hear again. These nine do not.
*
*     Three reasons, and they are different:
*       a count, not a unit   `1 order', `1 serve', `2 slice', `2bond', `3bugkos' --
*                             the number is part of the label, so the row answers
*                             "what do two slices weigh", which no enumerator asks
*       an item, not a unit   `papaya, mango, banana' -- a list of what was bought
*       a one-off phrasing    `pinutos / plastic', `role', `stick' -- one vendor's
*                             wording, recorded once, in one municipality
*
*     THIS IS THE FIRST TIME THE PIPELINE ASKS WHETHER A LABEL IS A UNIT AT ALL. Every
*     other exclusion here is structural -- no weight, not a size, wrong branch. A3 in
*     docs/implicit_assumptions.md is explicit that thinness NEVER drops a row (`the
*     flag is a convenience, not a filter'), and that stands: these are excluded for
*     what they are, not for how thin they are. Several are not thin -- `3bugkos' and
*     `pinutos / plastic' rest on 4 weighings each.
*
*     OUTCOME 2 IS UNAFFECTED, deliberately. A household that reported "2 slice" still
*     needs its grams, and the weighings behind these labels are real. This file feeds
*     Outcome 1 only; master_outcome2.do never calls it.
*
*     Excluded rows are written out rather than vanishing, to
*     ${btables}\refbook_excluded_not_a_unit.csv.
local notaunit `" "1 order" "1 serve" "2 slice" "2bond" "3bugkos" "papaya, mango, banana" "pinutos / plastic" "role" "stick" "'
gen byte _notaunit = 0
foreach u of local notaunit {
	replace _notaunit = 1 if harmonized_nsu_unit == "`u'"
}
count if _notaunit
di as res "not-a-unit weighings excluded from Outcome 1: " r(N)
* A label that stops matching is a silent scope change, so fail rather than drift.
foreach u of local notaunit {
	count if harmonized_nsu_unit == "`u'"
	if r(N) == 0 {
		di as err "not-a-unit exclusion list names `u', which matches no weighing."
		di as err "The label was respelled or folded upstream. Reconcile the list;"
		di as err "do not delete the entry -- see the fold tables in nsu_fold_rule.py."
		exit 459
	}
}
* The record of what left, at the grain it left at -- one row per weighing, with the
* weight it carried, so a reader can see exactly what the reference book gave up and
* recover it if a label is later judged a real unit after all.
preserve
	keep if _notaunit
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	     pull_nsu_unit corrected_weight corrected_unit weighing_approach id
	gsort pull_item harmonized_nsu_unit pull_province pull_municipal_city
	export delimited using "${btables}\refbook_excluded_not_a_unit.csv", replace
	di as txt "  wrote ${btables}\refbook_excluded_not_a_unit.csv (" _N " weighing(s))"
restore

drop if _notaunit
drop _notaunit

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
* READS `branch', NOT `weighing_approach', and that is the whole of #28's change here.
* Only the cases whose (item, harmonized unit) pair is conventional EVERYWHERE it appears
* keep the no-size treatment -- 80 weighings in 24 cases. The other 388 weighings in 99
* cases are field-conventional but processed size-based, because the same item x unit is
* treated as size- or price-varying in other municipalities, so "conventional" there
* described the cell assignment rather than the unit. They are handled in 2a-ii.
*
* On `weighing_approach' this line would send all 468 to size_ord = 0 and the
* reclassification would have no effect on published output.
replace size_ord = 0 if branch == 1


*-------------------------------------------------------------------------------
* 2a-ii. RECLASSIFIED CONVENTIONAL -- one group, published as medium
*-------------------------------------------------------------------------------
* These were weighed AS conventional, so there are no S/M/L labels to tercile and no
* price point recorded per weighing. There is nothing to cut, and re-cutting the pooled
* distribution against price points the enumerator never spent would be Outcome 2's
* Branch S rather than a size-based case. So: one group, no tercile, published medium.
*
* MEDIUM IS THE BETTER OF TWO DEFENSIBLE CHOICES, not a measured result, and
* docs/implicit_assumptions.md A12 says so. The conventional median sits at the
* size-based medium with a ratio median of 1.00 (IQR 0.93-1.25) and far from the large
* tercile -- but it is equally close to the small tercile on average log-distance.
*
* k_sizes = 1 is set explicitly. Left to 2c's `total(first_lbl)' it would come out 0,
* because first_lbl is only tagged on field-labelled size-based rows, and a zero would
* make the under-filled gate in 2d read these cases as having filled 0 of 0 groups.
replace size_ord = 2 if d_reclassified == 1

count if d_reclassified == 1
di as res "2a-ii reclassified conventional -> one medium group: " r(N) " weighing(s)"


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

* --- TWO MEDIANS IN ONE CASE ARE TWO PRICE POINTS, so they are two rungs -------------
* A municipality median and a province median are separate hetero groups: each records a
* price point a vendor was actually quoted, and what that vendor handed over at it. The
* label mapping above sends both to `medium', so a case holding both published ONE row
* averaging them -- at NEGROS OCCIDENTAL / VALLADOLID a 325 g group and a 780 g group
* became a single 425 g "medium", with nothing on the row to say so. Issue #21 §5.1.
*
* THE COLLISION IS CREATED BY THE FOLD, not by the field. No raw `pull_nsu_unit' ever
* carries both price types -- measured, 0 of them. It appears only after harmonization
* pools two spellings whose prices were derived differently, which is this issue's whole
* subject.
*
* ORDERED BY PRICE, because the price ladder is what orders sizes on this branch --
* mp25 < mp50 < mp75 is a price ordering, not a size measurement. Nothing is invented:
* the ordering comes from `pull_price', and in both live cases it agrees with the weights.
*
*     cabbage   mun median  P25.00 -> 325 g      prov median  P60.00 -> 780 g
*     carrot    prov median  P8.00 ->  95 g      mun median   P17.50 -> 150 g
*
* Note the two run in OPPOSITE directions by geography -- the province median is the
* dearer point for cabbage and the cheaper one for carrot -- so no rule keyed on
* "municipality beats province" could have got both right. Only the price can.
*
* SMALL AND LARGE rather than small and medium, following the same convention 2d uses for
* a size-based case with two filled groups (#27 A5, the (1,3) shape): two observed points
* with nothing identifying a middle are the ladder's ends. A reader sees two rungs whose
* order is real and whose spacing is not claimed.
egen byte _n_med = nvals(item_nsu_hetero_type) if weighing_approach == 2 & ///
	inlist(item_nsu_hetero_type, 8, 9), by(cell)
egen double _med_price_min = min(pull_price) if weighing_approach == 2 & ///
	inlist(item_nsu_hetero_type, 8, 9), by(cell)

count if _n_med > 1 & !missing(_n_med)
di as res "2b two-median cases split by price rank: " r(N) " weighing(s)"

replace size_ord = 1 if _n_med > 1 & !missing(_n_med) & pull_price == _med_price_min
replace size_ord = 3 if _n_med > 1 & !missing(_n_med) & pull_price >  _med_price_min

* Both points must differ in price, or the rank is arbitrary and the two rows would
* collide again at size_ord = 1. If this fires, the case needs a decision rather than a
* rule -- two different price POINTS quoted at the same price is not something the
* ordering can resolve.
count if _n_med > 1 & !missing(_n_med) & missing(pull_price)
assert r(N) == 0
* Counts DISTINCT HETERO GROUPS per rung, not weighings. Several weighings sharing a rung
* is the normal case -- three vendors quoted the same price point -- and an earlier version
* of this guard tested `_N > 1' and so fired on every split case it was meant to pass.
egen byte _dup_med = nvals(item_nsu_hetero_type) if _n_med > 1 & !missing(_n_med), ///
	by(cell size_ord)
count if _dup_med > 1 & !missing(_dup_med)
if r(N) > 0 {
	di as err "10_size_assignment.do: " r(N) " weighing(s) in two-median cases still"
	di as err "share a size_ord -- the two price points are quoted at the same price."
	exit 459
}
drop _n_med _med_price_min _dup_med


* --- 2b-ii. ONE LABEL, TWO PRICES: the collision 2b does NOT cover -------------------
* 2b above fixes a cell holding two DIFFERENT price-point labels that both map to the same
* size -- a municipality median and a province median, both `medium'. It does nothing about
* the other shape: two weighings carrying the SAME label at DIFFERENT peso prices.
*
* That can arise from exactly the same cause. `item_nsu_hetero_type' on this branch records
* which price point a vendor was quoted, and the fold can pool two spellings that each have
* their own municipality median. Both weighings would then read `municipality_median', both
* would take size_ord = 2, and 12_publish_reference_set.do would collapse them into ONE
* `medium' row averaging two genuinely different price levels -- with nothing on the row
* saying so. That is the VALLADOLID defect one step over, and the size_ord mapping cannot
* see it, because the mapping reads the LABEL and the difference is in the PRICE.
*
* MEASURED: 0 of 361 (cell x label) groups on this branch carry more than one distinct
* price. It does not arise here, and the reason is thin -- only 3 price-quantity cells pool
* more than one spelling at all, and those 3 happen to carry different labels. Nothing
* about the pipeline prevents a fourth.
*
* So this halts rather than guesses. There is no ordering to apply: 2b could split by price
* rank because the two labels were genuinely different points, but two weighings quoted the
* SAME point at different prices are either a price-file disagreement between spellings or
* a fold that should not have happened, and which it is decides what the right answer is.
egen byte _onelbl_np = nvals(pull_price) if weighing_approach == 2, ///
	by(cell item_nsu_hetero_type)
count if _onelbl_np > 1 & !missing(_onelbl_np)
if r(N) > 0 {
	di as err "10_size_assignment.do 2b-ii: " r(N) " price-quantity weighing(s) share a"
	di as err "price-point LABEL within a cell but carry different peso prices."
	di as err "They would collapse into one size_ord row averaging two price levels."
	di as err "This is #21's collision in the shape sec 2b does not cover. Decide whether"
	di as err "the fold should have pooled these spellings, or whether the two prices are"
	di as err "a price-file disagreement; do not extend 2b's price-rank rule blindly."
	list pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		pull_nsu_unit item_nsu_hetero_type pull_price corrected_weight ///
		if _onelbl_np > 1 & !missing(_onelbl_np), noobs abbrev(24)
	exit 459
}
drop _onelbl_np


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

* A RECLASSIFIED CASE HAS ONE GROUP, and it has to be said rather than counted. `total()'
* reads missing as zero and first_lbl is tagged only on field-labelled size-based rows, so
* these cases would otherwise carry k_sizes = 0 -- which 2d's under-filled gate would read
* as "filled 0 of 0 groups" and 2c's rank assert would reject.
replace k_sizes = 1 if d_reclassified == 1
label var k_sizes "distinct S/M/L labels the field recorded for this case (1 if reclassified)"

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

* A RECLASSIFIED CASE FILLED ITS ONE GROUP. `tag_cellgrp' is only set inside the tercile,
* which these cases never enter, so they arrive here with n_filled = 0 against the
* k_sizes = 1 set in 2a-ii -- reading as "the field labelled one group and none filled",
* which is false: the single pooled group is exactly what they publish.
*
* THIS IS NOT COSMETIC. `n_filled < k_sizes' is the under-filled gate, and on all 388 of
* these rows the inconsistent pair makes it TRUE. 11_size_checks.do counts under-filled
* cases and would report 99 spurious ones the moment it reads `branch' instead of
* `weighing_approach' -- which #28 asks it to do. Fixing the data rather than the
* condition means either variable gives the right answer, so the check does not depend on
* which one it happens to read.
replace n_filled = 1 if d_reclassified == 1
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
* THIS COUNT HAS MOVED TWICE, and both moves are the same mechanism running in
* opposite directions. Reconcile against the crosstab, do not edit the number.
*
*   94 -> 104  when 04_unit_snap.do adopted the anchor snap (#18 A1). Snapping a
*              weight toward its cell median pulls outliers INTO the body of the
*              distribution, so more vendors tie exactly on a tercile cut and more
*              groups come back empty.
*  104 -> 100  when STEP 3e began adjudicating by rule rather than by the
*              plausibility bounds alone (#18, from the manual review). The rules
*              adopt the BLOCK reading on 196 more rows -- 68 on a shared sub-1
*              decimal structure, 128 on a whole-number reading -- and the block
*              reading restates the typed number instead of pulling it toward the
*              median. Fewer weights land on a cut, so four cases regained a group.
*  100 ->  97  when the 80 adjudicated verdicts from the second review round were
*              applied (05_manual_corrections.do sec 6). Same mechanism a third
*              time and in the same direction: 65 of the 80 adopt the block
*              reading, which restates the typed number rather than pulling it
*              toward a median, so three more cases regained a group.
*   97 ->  97  when the third review round took the ledger to 227 verdicts. The
*              TOTAL held, but the shape moved: one case stopped collapsing to a
*              single group and became small+medium instead. So the count being
*              stable is not the same as nothing having changed, which is why all
*              four numbers below are asserted and not just the total.
*   97 ->  96  when STEP 3e's referee ladder was reordered to exhaust every
*              hetero-CORRECT pool before any hetero-BLIND one, adding the
*              region_hetero rung. 74 weighings moved, 68 of them UP a decade: the
*              pooled cell had been refereeing them against a median that mixes
*              small, medium and large, which sits below the larges and hands the
*              row to the anchor. Four cases stopped collapsing to a single group.
*
*   96 ->  94  when the block reading became the published weight everywhere it is a
*              possible reading (04 STEP 3e-v-b), and 03a gained the misplaced-decimal
*              repair for sub-0.01 litre entries. The block reading restates the typed
*              number instead of pulling it toward a median, so this is the same
*              mechanism as the three moves above, running once more in the same
*              direction and now over 352 rows at once.
*
* The four counts below must reconcile against each other and against the crosstab:
*     31 collapsed to one group  +  48 small+medium  +  15 small+large  =  94
* and in the crosstab (k=2, filled=1) + (k=3, filled=1) = 31, while
* 48 + 15 = 63 (k=3, filled=2). If one moves and the others do not, the tie rule
* changed rather than the weights.
*
* SMALL+LARGE NOW MOVES, 14 -> 17 -> 15, and it held at 14 for the whole history
* above. It was unmoved by the anchor snap, the 3e rules and all three review rounds,
* because each of those alters a weight without altering WHICH pool the row is judged
* against -- and a case whose MIDDLE group empties is not one a shifted weight tends
* to reach. The two changes that moved it are the two that changed the pool itself:
* the ladder reorder (a row is refereed against its own size group's median, so a
* medium can land on a different side of a tercile cut) and then STEP 3e-v-b (a row is
* not refereed at all unless its block reading is impossible). The shape nothing had
* tested is now tested, and it responds to pool changes and not to weight changes --
* which is what its stability through the first three moves was already saying.
*
* Under-filled cases are reported and not patched -- see issue #3, settled as status
* quo.
egen byte tag_cell_sz = tag(cell) if weighing_approach == 3

* The partition itself, printed so a move can be reconciled rather than guessed at.
tab k_sizes n_filled if tag_cell_sz, m
count if tag_cell_sz & n_filled < k_sizes
di as txt "under-filled size-based cases: " r(N)
assert r(N) == 94
count if tag_cell_sz & n_filled < k_sizes & n_filled == 1
di as txt "  ... collapsed to a single group: " r(N)
assert r(N) == 31
count if tag_cell_sz & n_filled < k_sizes & n_filled == 2 & fill_g1 & fill_g2
di as txt "  ... two groups, small+medium filled: " r(N)
assert r(N) == 48
count if tag_cell_sz & n_filled < k_sizes & n_filled == 2 & fill_g1 & fill_g3
di as txt "  ... two groups, small+large filled: " r(N)
assert r(N) == 15

* the two-group shapes must ALREADY be right, or the claim above is wrong
assert size_ord == 1 if weighing_approach == 3 & n_filled < k_sizes & n_filled == 2 & grp == 1
assert size_ord == 2 if weighing_approach == 3 & n_filled < k_sizes & n_filled == 2 & grp == 2
assert size_ord == 3 if weighing_approach == 3 & n_filled < k_sizes & n_filled == 2 & grp == 3

* ---- the one substantive change: a lone surviving group is a MEDIUM -------------
count if weighing_approach == 3 & n_filled < k_sizes & n_filled == 1 & size_ord != 2
local n_relabel = r(N)

* The CASE count, counted rather than typed. It used to read "30 cases" as a literal,
* beside an assertion seventeen lines above putting the same population at 34 -- two
* numbers for one set, one of them unchecked. A count that cannot be re-derived on the
* run that prints it is how this project's stale figures start.
egen byte _tag_uf = tag(pull_province pull_municipal_city pull_item harmonized_nsu_unit) ///
	if weighing_approach == 3 & n_filled < k_sizes & n_filled == 1
count if _tag_uf == 1
local n_uf_cases = r(N)
drop _tag_uf

replace size_ord = 2 if weighing_approach == 3 & n_filled < k_sizes & n_filled == 1
di as res "under-filled cases relabelled to medium: `n_uf_cases' cases, " ///
	"`n_relabel' weighing rows"
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
