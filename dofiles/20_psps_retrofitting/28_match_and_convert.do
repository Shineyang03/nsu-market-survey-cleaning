********************************************************************************
* 28_match_and_convert.do -- attach a weight to a PSPS household row
*
* WHAT THIS OWNS. This is the step the whole of Outcome 2 exists for and the one that has
* never existed: it takes a household's reported quantity in a non-standard unit and
* returns grams. Everything before it built the lookup; nothing before it touched a
* household row.
*
* ==============================================================================
* THE ARITHMETIC
*
*   CF_h = p_h * w_g / p_g  =  p_h / v_g          grams in the HOUSEHOLD's unit
*   grams_h = q_h * CF_h
*
* Read it through v: the group contributes a RATE (its pesos per gram) rather than a level,
* and the household's own spend converts that rate into a quantity. If p_h equals the
* group's own price the household receives exactly the group's weight, which is the
* consistency check worth keeping in mind while reading the rest of this file.
*
* MATCH ON PRICE, TIE ON v, and the second half is not pedantry. A household equidistant
* between two points takes the one with the HIGHER v -- more pesos per gram, so fewer
* grams. Stating the tie on v rather than "take the lower price point" matters because the
* two coincide only if v falls monotonically across the ladder, and nothing guarantees it:
* v = p_g/w_g is a ratio of two independently measured quantities, so a large unit that
* was cheap per gram inverts the order. The methodology's worked example is exactly that
* case -- 150/200/260 g at PHP 50/80/100 gives v of 0.33/0.40/0.38.
*
* ==============================================================================
* FOUR THINGS THAT ARE NOT THE ARITHMETIC, and they decide more rows than it does
*
* 1. A HOUSEHOLD HAS NO DIMENSION. The lookup is keyed with `corrected_unit' because a
*    gram must never be pooled with a millilitre. A household reporting "2 pieces of ice
*    cream" says nothing about which, so section 1 picks one dimension per case.
*
*    AT CELL GRAIN THAT PICK IS NOW VACUOUS. 05_manual_corrections.do section 1c gives
*    every case a single dimension, so section 1 finds one sub-cell and selects it. The
*    code stays as the guard that it is -- its `assert _n_dim == 1' is what would catch a
*    mixed cell reappearing. The pick still BINDS at the fallback rungs in section 6,
*    where 20 of 212 province groups and 8 of 84 national groups do span both dimensions,
*    because pooling across municipalities mixes cells that resolved differently.
*
* 2. A THIRD OF THE ROWS HAVE NO PRICE. 11,809 of 35,448 -- own production (10,187) and
*    gifts (1,606) carry an imputed VALUE, not a price the household faced, so 20a leaves
*    p_h missing on them by design (A10). They still reported a quantity in an NSU and
*    still need grams. Section 4 gives them the case's middle point and converts at that
*    group's own weight -- CF_h = w_g, the degenerate p_h = p_g case -- and flags it. The
*    alternative, dividing an imputed value by a quantity, would manufacture a price no
*    market set and feed it into an expression that is linear in it.
*
*    A10's substantive claim rides on this and is untested: that a gifted `bugkos' is the
*    same size as a bought one. Nothing here tests it; the flag is so a reader can.
*
* 3. SOME POINTS HAVE NO WEIGHT, and they are in the lookup on purpose. 495 of them --
*    301 where the cut's upper part came back empty, 194 refused unique prices. A
*    household matches the NEAREST point, so removing them would push the household onto
*    the next point along and convert it at a weight belonging to a different rung, which
*    is worse than refusing. The two kinds are then treated DIFFERENTLY, in section 5, and
*    that difference is a decision rather than a mechanism.
*
* 4. A SPELLING THAT WAS NEVER WEIGHED. A household can report a spelling that was priced
*    but never weighed in its cell; harmonization still lands it in a case that has
*    weights, so nothing fails. But it is then scored against a ladder built entirely from
*    the OTHER spelling's prices, and CF_h is linear in p_h/p_g, so a price-level gap
*    between two spellings becomes a size difference nobody measured. #21 sec 5.3 settled
*    it: convert normally where the levels are close, refuse where they differ by 2x or
*    more (A11). 60 spellings are flagged.
*
* ==============================================================================
* INPUTS  ${btemp}\psps_households.dta          20a -- conv_path == 2 rows
*         ${bdeliv}\outcome2_lookup.dta         25
*         ${btemp}\case_spelling_gap.dta        20 -- A11's flag, per spelling
*         ${btemp}\outcome2_cell_fallback.dta   30 -- the ladder at cell grain
* OUTPUT  ${btemp}\psps_converted.dta
*         ${btables}\psps_unconvertible.csv
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\28_match_and_convert.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

local coarse pull_province pull_municipal_city pull_item harmonized_nsu_unit


********************************************************************************
**# 1. Which dimension a case answers in
********************************************************************************
* Built from the LOOKUP rather than from the weighings, so that the sub-cell chosen is
* guaranteed to be one that actually produced groups. Choosing from the weighings could
* pick a sub-cell whose every part came back empty.
*
* MORE WEIGHINGS WINS; a tie goes to grams. Both halves are arbitrary in the sense that no
* evidence favours either -- and both are nearly weightless in effect, because g and mL are
* the same number here. What matters is that the rule is deterministic: picking by row
* order would make the answer depend on the sort seed.

use "${bdeliv}\outcome2_lookup", clear
keep if d_point_usable == 1
collapse (sum) _wsum = n_g, by(`coarse' corrected_unit)
bysort `coarse': egen double _best = max(_wsum)
* corrected_unit is 1 = g, 2 = mL (04_unit_snap.do declares these explicitly), so the
* minimum code is grams and `min' implements the tie rule.
bysort `coarse': egen byte _pick = min(cond(_wsum == _best, corrected_unit, .))
keep if corrected_unit == _pick
bysort `coarse': gen byte _n_dim = _N
assert _n_dim == 1
keep `coarse' corrected_unit
rename corrected_unit dim_used
isid `coarse'
tempfile dims
save "`dims'"

qui count
di as res _n "cases with at least one usable group: " r(N)

* ---- the lookup, with its month column renamed --------------------------------
* `psps_month' EXISTS ON BOTH SIDES of the joinby in section 3 -- the household's
* interview month, and the month a Branch P row was restated to. joinby keeps the
* MASTER's copy of a colliding variable and discards the using's, so without this rename
* the lookup's month would vanish and the month filter would compare the household's month
* with itself: always true, and every household would be matched against Branch P rows
* from every month at once. Silent, and it would have inflated the table twelvefold.
use "${bdeliv}\outcome2_lookup", clear
rename psps_month lk_month
label var lk_month "the month THIS LOOKUP ROW was restated to (Branch P only)"

* `d_thin' IS DROPPED, not carried. On the lookup it reads the matched POINT's n_g; on a
* household row the question is whether the weight the row was actually given is thin,
* which for a fallback row is a different rung's count. 31_psps_grams.do regenerates it
* from n_g_used, once, after every route has filled that column.
drop d_thin
tempfile lkj
save "`lkj'"


********************************************************************************
**# 2. The household rows
********************************************************************************

use "${btemp}\psps_households", clear
keep if conv_path == 2
qui count
local n_in = r(N)
di as res _n "household rows needing an NSU conversion: `n_in'"

merge m:1 `coarse' using "`dims'", keep(1 3) keepusing(dim_used) generate(_m_dim)
qui count if _m_dim == 1
di as res "  in a case with NO usable group at all: " r(N) " -- these go to the fallback"
drop _m_dim

* A11: does this household's own reported spelling diverge in price from the weighed one?
merge m:1 `coarse' pull_nsu_unit using "${btemp}\case_spelling_gap", ///
	keep(1 3) nogen keepusing(d_spelling_gap gap_sym)
replace d_spelling_gap = 0 if missing(d_spelling_gap)
qui count if d_spelling_gap == 1
di as res "  reporting a spelling flagged under A11 (gap >= 2x): " r(N)


********************************************************************************
**# 3. Join every candidate group, then keep the matched one
********************************************************************************
* joinby, then filter, rather than a clever single merge. A household has to be compared
* against every point in its case before one can be called nearest, so the fan-out is the
* computation and not an accident of it.

gen byte _has_dim = !missing(dim_used)
preserve
	keep if _has_dim == 0
	tempfile nocase
	save "`nocase'"
restore
keep if _has_dim == 1

rename dim_used corrected_unit
joinby `coarse' corrected_unit using "`lkj'", unmatched(none)

* Branch P is the only branch carrying a month, so it is the only one filtered. Keeping a
* month-mismatched Branch P row would convert a household at another month's price level.
* On branches 1 and 3 lk_month is missing and every candidate survives, which is correct:
* a size-based or conventional weight is the same in every month.
qui count if branch == 2
di as res "  Branch P candidate rows before the month filter: " r(N)
drop if branch == 2 & lk_month != psps_month
qui count if branch == 2
di as res "  ...after: " r(N)

* A household on Branch P must keep at least one candidate, or its own interview month was
* never built for that case -- which 24 cannot produce, since it crosses each group with
* the months of its own municipality and 20a is where both month lists come from.
bysort hh_row: gen byte _ncand = _N
qui count if _ncand == 0
assert r(N) == 0


********************************************************************************
**# 4. The match
********************************************************************************

gen double _absdiff = abs(p_h - p_g)

* NO PRICE: the middle point by rank, and convert at its own weight. See point 2 in the
* header. `group_id' is the rank, so the middle is ceil(k/2) over the USABLE groups.
bysort hh_row: egen int _ngrp = total(d_point_usable == 1)
gen byte d_no_price = missing(p_h)

* Rank the candidates. Where a price exists: nearest point, tie to the higher v_use, and a
* final tie broken on group_id so the choice cannot depend on row order. Where none does:
* the middle usable group.
gen double _rankkey = .
replace _rankkey = _absdiff       if d_no_price == 0
replace _rankkey = abs(group_id - ceil(_ngrp / 2)) if d_no_price == 1

* gsort, then `by hh_row:' -- which requires the data SORTED by hh_row, and gsort leaves
* it so because hh_row is its first key and ascending. `by' checks only its own by-variable,
* so the descending key later in the list is not the r(5) hazard it looks like.
*
* The remaining keys break every tie deterministically: nearest price, then the higher
* v_use (fewer grams -- the conservative direction), then the lowest group_id.
*
* `p_g' IS THE FINAL KEY, and without it the chain does not actually terminate. An
* UNUSABLE point carries group_id missing (25_lookup.do explains why: two refused points
* in one sub-cell both have it) and v_use missing (there is no w_g to divide by), so for a
* household exactly equidistant between two refused points every key up to group_id
* compares missing against missing and the winner falls to row order. 95 cells in the
* current lookup hold two unusable points at distinct prices, and in at least one the two
* carry DIFFERENT reasons -- one "unique price", one "empty part" -- which resolve to a
* permanent refusal and a fallback gram figure respectively. No household in this build
* sits on such a midpoint, so nothing moves today; new price data could put one there, and
* the failure would be a household's outcome flipping between runs with no error.
*
* p_g is distinct within a case by construction -- the PHP 20 merge collapsed equal
* values -- so it terminates the chain.
gsort hh_row _rankkey -v_use group_id p_g
by hh_row: gen byte _chosen = (_n == 1)
keep if _chosen
drop _chosen _rankkey _absdiff _ngrp _has_dim _ncand

isid hh_row


********************************************************************************
**# 5. Convert, or refuse
********************************************************************************
* FOUR OUTCOMES, and the difference between the two refusals is the substantive decision
* in this file.
*
*   convert                       the matched group has a weight
*   .c  unique-price refusal      the matched point is a unique price with no weighing
*   fallback                      the matched point's part of the cut came back empty
*   .c  A11 spelling gap          the household's own spelling diverges 2x in price
*
* WHY THE TWO REFUSALS DIFFER. A unique-price point is refused because the PRICE is not
* trustworthy for this cell -- the price file folds away any municipal price within PHP 20
* of the province median, so a surviving unique price is by construction far from central
* tendency, and CF_h is linear in 1/p_g. Substituting the cell's pooled weight would not
* repair that; it would answer a question nobody asked, at a price still known to be
* atypical. Reported unconvertible, per the decision on #23.
*
* An EMPTY PART is the opposite situation: the price is a perfectly ordinary point and the
* only thing missing is a weight in that particular third of the distribution, because
* vendors tied on a cut. The cell's own pooled weight is exactly what the fallback ladder
* is for, and using it is strictly better than nothing. It carries fallback_level so a
* reader can drop it.

merge m:1 `coarse' corrected_unit using "${btemp}\outcome2_cell_fallback", ///
	keep(1 3) nogen keepusing(fb_grams fb_n_g fb_level fb_unconvertible)

gen str28 conv_route = ""
gen double cf_h = .
* n_g_used is filled on the SAME line as cf_h at every route below, so the two can only
* ever describe the same set of weighings. A row's evidence count must come from wherever
* its weight came from -- the matched group, the cell pool, or a borrowed rung.
gen long   n_g_used = .
gen byte   fallback_level = .

* --- 1. the ordinary path -----------------------------------------------------
replace conv_route = "matched price point" if d_point_usable == 1 & d_spelling_gap == 0
replace cf_h = p_h / v_use  if conv_route == "matched price point" & d_no_price == 0 & branch != 1
replace cf_h = w_use        if conv_route == "matched price point" & d_no_price == 1
replace cf_h = w_use        if conv_route == "matched price point" & branch == 1
replace n_g_used = n_g      if conv_route == "matched price point"
replace fallback_level = 0  if conv_route == "matched price point"

* --- 2. A11 refusal -----------------------------------------------------------
replace conv_route = "refused: A11 spelling gap" if d_spelling_gap == 1

* --- 3. unique-price refusal --------------------------------------------------
replace conv_route = "refused: unique price" ///
	if conv_route == "" & unusable_why == "unique price, no weighing behind it"

* --- 4. empty part -> the ladder ----------------------------------------------
replace conv_route = "fallback: empty size part" ///
	if conv_route == "" & unusable_why == "this part of the cut came back empty"
replace cf_h           = fb_grams if conv_route == "fallback: empty size part"
replace n_g_used       = fb_n_g   if conv_route == "fallback: empty size part"
replace fallback_level = fb_level if conv_route == "fallback: empty size part"
replace conv_route     = "refused: nothing anywhere" ///
	if conv_route == "fallback: empty size part" & fb_unconvertible == 1

assert conv_route != ""


********************************************************************************
**# 6. The households whose case had no usable group at all
********************************************************************************

append using "`nocase'"
replace conv_route = "" if missing(conv_route)

* `d_no_price' IS FILLED HERE, and it is a fix rather than a tidy-up. It is generated in
* section 4, which runs on the `_has_dim == 1' stream only -- the rows set aside at
* section 3 were already out of memory by then, so all 5,882 of them came back with it
* MISSING. 2,135 of those genuinely have no faced price, so `tab d_no_price if
* d_converted' understated A10's population by 18% and the label read as though those
* households had paid something.
*
* Recomputed rather than carried, because it is a pure function of p_h -- `missing(p_h)'
* and nothing else -- so this restates the same rule on the rows that missed it rather
* than making a second decision about them.
replace d_no_price = missing(p_h) if missing(d_no_price)

* And the invariant, so the column cannot drift from its own definition again. It says
* what the label claims: 1 exactly where the household faced no price.
assert d_no_price == missing(p_h)

* THESE ARE #30's POPULATION and they are one row in six. Most of them are not "a case
* whose groups all failed" -- they are a case THE MARKET SURVEY NEVER VISITED, so no
* per-cell table can reach them. #30 counts 419 cells needing a province fallback and 75
* needing any province, 5,741 PSPS observations between them.
*
* THE LADDER IS CLIMBED FROM THE OTHER END for them: the cell's own pooled weight if it
* has one, then the province schedule, then the regional one, then refusal. Each schedule
* is written by 30_fallback.do from the same collapses that built w_l2 and w_l3, so no
* median is recomputed here and the two readings of L2 cannot drift apart.
*
* A DIMENSION HAS TO BE CHOSEN AT EACH RUNG, because a household reports no dimension and
* an unweighed cell offers no hint. Same rule as section 1 -- more weighings wins, grams
* break the tie -- applied to whichever pool is serving.

* ---- rung: the cell's own pooled weight (only where the cell has weighings) ----
preserve
	use "${btemp}\outcome2_cell_fallback", clear
	drop if fb_unconvertible == 1
	bysort `coarse': egen double _best = max(fb_n_g)
	bysort `coarse': egen byte _pick = min(cond(fb_n_g == _best, corrected_unit, .))
	keep if corrected_unit == _pick
	* Not `_n' -- that is Stata's observation-number system variable and an invalid varname.
	bysort `coarse': gen byte _ndim = _N
	assert _ndim == 1
	keep `coarse' corrected_unit fb_grams fb_n_g fb_level
	rename (corrected_unit fb_grams fb_n_g fb_level) (r1_dim r1_g r1_n r1_lvl)
	isid `coarse'
	tempfile rung1
	save "`rung1'"
restore

* ---- rung: the province schedule --------------------------------------------
preserve
	use "${btemp}\outcome2_fallback_province", clear
	bysort pull_province pull_item harmonized_nsu_unit: egen double _best = max(fb_n_g)
	bysort pull_province pull_item harmonized_nsu_unit: ///
		egen byte _pick = min(cond(fb_n_g == _best, corrected_unit, .))
	keep if corrected_unit == _pick
	bysort pull_province pull_item harmonized_nsu_unit: gen byte _ndim = _N
	assert _ndim == 1
	keep pull_province pull_item harmonized_nsu_unit corrected_unit fb_grams fb_n_g fb_level
	rename (corrected_unit fb_grams fb_n_g fb_level) (r2_dim r2_g r2_n r2_lvl)
	isid pull_province pull_item harmonized_nsu_unit
	tempfile rung2
	save "`rung2'"
restore

* ---- rung: the regional schedule --------------------------------------------
preserve
	use "${btemp}\outcome2_fallback_regional", clear
	bysort pull_item harmonized_nsu_unit: egen double _best = max(fb_n_g)
	bysort pull_item harmonized_nsu_unit: ///
		egen byte _pick = min(cond(fb_n_g == _best, corrected_unit, .))
	keep if corrected_unit == _pick
	bysort pull_item harmonized_nsu_unit: gen byte _ndim = _N
	assert _ndim == 1
	keep pull_item harmonized_nsu_unit corrected_unit fb_grams fb_n_g fb_level
	rename (corrected_unit fb_grams fb_n_g fb_level) (r3_dim r3_g r3_n r3_lvl)
	isid pull_item harmonized_nsu_unit
	tempfile rung3
	save "`rung3'"
restore

merge m:1 `coarse' using "`rung1'", keep(1 3) nogen keepusing(r1_dim r1_g r1_n r1_lvl)
merge m:1 pull_province pull_item harmonized_nsu_unit using "`rung2'", ///
	keep(1 3) nogen keepusing(r2_dim r2_g r2_n r2_lvl)
merge m:1 pull_item harmonized_nsu_unit using "`rung3'", ///
	keep(1 3) nogen keepusing(r3_dim r3_g r3_n r3_lvl)

* FINEST RUNG FIRST, and each `if' requires conv_route still empty so an earlier rung
* cannot be overwritten by a coarser one.
replace corrected_unit = r1_dim if conv_route == "" & !missing(r1_g)
replace cf_h           = r1_g   if conv_route == "" & !missing(r1_g)
replace n_g_used       = r1_n   if conv_route == "" & !missing(r1_g)
replace fallback_level = r1_lvl if conv_route == "" & !missing(r1_g)
replace conv_route     = "fallback: cell pooled"     if conv_route == "" & !missing(r1_g)

replace corrected_unit = r2_dim if conv_route == "" & !missing(r2_g)
replace cf_h           = r2_g   if conv_route == "" & !missing(r2_g)
replace n_g_used       = r2_n   if conv_route == "" & !missing(r2_g)
replace fallback_level = r2_lvl if conv_route == "" & !missing(r2_g)
replace conv_route     = "fallback: province pool"   if conv_route == "" & !missing(r2_g)

replace corrected_unit = r3_dim if conv_route == "" & !missing(r3_g)
replace cf_h           = r3_g   if conv_route == "" & !missing(r3_g)
replace n_g_used       = r3_n   if conv_route == "" & !missing(r3_g)
replace fallback_level = r3_lvl if conv_route == "" & !missing(r3_g)
replace conv_route     = "fallback: regional pool"   if conv_route == "" & !missing(r3_g)

replace conv_route     = "refused: nothing anywhere" if conv_route == ""


********************************************************************************
**# 6b. THE HETERO-BLIND VARIANT -- the same ladder, started one rung lower
********************************************************************************
* WHAT IT IS. One conversion factor per province x municipality x item x harmonized unit
* x corrected_unit, with no within-NSU heterogeneity at all. Every household in a cell
* gets that cell's pooled weight whatever it paid and whatever size it bought.
*
* WHY IT EXISTS. The published file resolves 81,377 household rows at L0 -- the household's
* own hetero rung, selected by the price it faced. That matching is the most consequential
* thing Outcome 2 does and the build has no way to say how much it moves. This variant is
* the counterfactual: identical in every other respect, so a difference between the two
* files is the price/size matching and nothing else.
*
* IT IS A15 APPLIED TO EVERY ROW. Section 6's note states the cost for fallback rows --
* a household that bought the cheap version and one that bought the expensive version of
* the same unit receive the same grams. Here that holds universally. This file is
* therefore a ROBUSTNESS OBJECT, not a better answer, and nothing downstream should
* prefer it without saying why.
*
* THE LADDER STILL CLIMBS. Starting at L1 does not mean stopping there: a cell too thin
* to serve itself falls to its province and then to the region, exactly as section 6
* does. Refusing to climb would strand the 499 cells that borrow, and the comparison
* against the published file would stop being like-for-like.
*
* BUILT FROM THE SAME `rung1'/`rung2'/`rung3' TEMPFILES the section above merged in, so
* there is one definition of each rung and no median is recomputed. THE CAP DOES NOT
* APPLY: 29_cap.do bounds r_h = p_h / p_g, which exists only where a household price was
* divided by a group price. No blind row has one.
gen double cf_h_blind          = .
gen byte   dim_blind           = .
gen byte   fallback_level_blind = .
gen long   n_g_used_blind      = .
gen str28  conv_route_blind    = ""

* ---- A11 SURVIVES GOING BLIND, and this guard must come first ---------------------
* A spelling-gap refusal is a statement that the household's NSU LABEL cannot be trusted
* to name the same object the market survey weighed. That has nothing to do with matching
* on price, so removing the price match does not remove the objection -- and a blind file
* that converted these 304 rows would differ from the published one on two counts at
* once, which destroys the only thing this variant is for.
*
* CONTRAST WITH "unique price". That refusal says a price point had no weighing behind
* it, which IS an obstacle only the price match faces; with no point to match, 148 rows
* are legitimately served here that the headline file refuses. That difference is the
* counterfactual working, not leaking.
replace conv_route_blind = "refused: A11 spelling gap" if d_spelling_gap == 1

* FINEST RUNG FIRST, each guarded on the blind route still being empty so a coarser rung
* cannot overwrite a finer one -- the same shape as section 6, on its own columns.
replace dim_blind            = r1_dim if conv_route_blind == "" & !missing(r1_g)
replace cf_h_blind           = r1_g   if conv_route_blind == "" & !missing(r1_g)
replace n_g_used_blind       = r1_n   if conv_route_blind == "" & !missing(r1_g)
replace fallback_level_blind = r1_lvl if conv_route_blind == "" & !missing(r1_g)
replace conv_route_blind     = "blind: cell pooled"     if conv_route_blind == "" & !missing(r1_g)

replace dim_blind            = r2_dim if conv_route_blind == "" & !missing(r2_g)
replace cf_h_blind           = r2_g   if conv_route_blind == "" & !missing(r2_g)
replace n_g_used_blind       = r2_n   if conv_route_blind == "" & !missing(r2_g)
replace fallback_level_blind = r2_lvl if conv_route_blind == "" & !missing(r2_g)
replace conv_route_blind     = "blind: province pool"   if conv_route_blind == "" & !missing(r2_g)

replace dim_blind            = r3_dim if conv_route_blind == "" & !missing(r3_g)
replace cf_h_blind           = r3_g   if conv_route_blind == "" & !missing(r3_g)
replace n_g_used_blind       = r3_n   if conv_route_blind == "" & !missing(r3_g)
replace fallback_level_blind = r3_lvl if conv_route_blind == "" & !missing(r3_g)
replace conv_route_blind     = "blind: regional pool"   if conv_route_blind == "" & !missing(r3_g)

replace conv_route_blind     = "refused: nothing anywhere" if conv_route_blind == ""

* The blind ladder never reaches L0 by construction -- that rung IS the hetero match.
assert fallback_level_blind != 0 if !missing(fallback_level_blind)
assert inlist(fallback_level_blind, 1, 2, 3) if !missing(cf_h_blind)
assert missing(cf_h_blind) == (strpos(conv_route_blind, "refused") > 0)

* Every A11 row is refused here exactly as it is in the headline file, so the two agree
* on that population by construction rather than by coincidence.
assert conv_route_blind == "refused: A11 spelling gap" if d_spelling_gap == 1
assert conv_route == conv_route_blind if d_spelling_gap == 1

drop r1_* r2_* r3_*

* A FALLBACK ROW IGNORES THE HOUSEHOLD'S PRICE ENTIRELY, and that is A15's cost stated as
* code: from L1 down, a household that bought the cheap version and one that bought the
* expensive version of the same unit receive the SAME grams. In exchange the estimate does
* not depend on a price-weight relationship holding across municipalities, which the ray
* test showed holds unevenly and could not be checked at all for 41% of this population.
* fallback_level is published on every row so a reader can keep L1 and drop L3.


********************************************************************************
**# 7. Grams, and the report
********************************************************************************

gen double grams_h = q_h * cf_h

* ---- the hetero-blind counterfactual, same arithmetic on the blind factor ----------
* No CF_h = p_h / v_g here: the blind factor IS the grams in one unit, so this is the
* degenerate p_h = p_g case applied to every row. See section 6b.
gen double grams_h_blind = q_h * cf_h_blind
gen byte   d_converted_blind = !missing(grams_h_blind)
assert grams_h_blind > 0 if !missing(grams_h_blind)

label var cf_h_blind           "hetero-blind: grams in one unit of this NSU, cell pooled across hetero-groups"
label var grams_h_blind        "hetero-blind: q_h * cf_h_blind -- the no-price-matching counterfactual"
label var dim_blind            "hetero-blind: dimension of cf_h_blind (1 = g, 2 = mL)"
label var fallback_level_blind "hetero-blind rung: 1 cell pooled, 2 province, 3 regional (never 0)"
label var conv_route_blind     "hetero-blind: how this row got its grams, or why it did not"
label var n_g_used_blind       "hetero-blind: weighings behind cf_h_blind"
label var d_converted_blind    "1 = the hetero-blind ladder produced grams for this row"

gen byte d_converted = !missing(grams_h)
gen byte d_thin = n_g_used < ${THIN} if !missing(n_g_used)
replace  d_thin = 0 if missing(d_thin)

* Every route either produces grams or does not, and which is which is part of the route's
* meaning rather than an outcome of the data. A "matched price point" row with no grams
* would mean the lookup handed over a usable group with no weight.
assert !missing(grams_h) if strpos(conv_route, "refused") == 0
assert missing(grams_h)  if strpos(conv_route, "refused") > 0
assert grams_h > 0 if !missing(grams_h)

* ---- the evidence count carried onto the household row -----------------------------
* EVERY CONVERTED ROW MUST KNOW how much evidence the weight it was given rests on. A
* converted row with nothing here would be a gram figure whose provenance stops at the
* number -- and it would arrive as a clean build, since a missing count reads as "no
* value published" in every summary downstream.
assert !missing(n_g_used) if d_converted == 1

* A refused row has no weight, so it must carry no count either. Zero would assert
* something about a set of weighings the row never received.
assert missing(n_g_used) if d_converted == 0

label var cf_h        "grams (or mL) in one unit of the NSU this household reported"
label var grams_h     "q_h * cf_h -- total grams for this household x item x slot"
label var conv_route  "how this row got its grams, or why it did not"
label var n_g_used    "weighings behind cf_h, at the level actually used"
label var d_no_price  "1 = no computable unit value (e_h or q_h absent); converted at the group's own weight"
label var d_converted "1 = this row has a gram figure"
label var fallback_level "0 = the matched group; 1-3 = a borrowed rung (see fallback_lbl)"
def_fallback_level
label values fallback_level fallback_lbl

di as res _n "{hline 78}"
di as res "rows by conversion route:"
tab conv_route, m
di as res _n "converted:"
tab d_converted, m
di as res _n "by fallback level, converted rows only:"
tab fallback_level if d_converted, m
di as res _n "weighings behind the weight each converted row was given:"
table fallback_level if d_converted, statistic(frequency) ///
	statistic(mean n_g_used) nformat(%9.2f)
di as res _n "rows converted with no faced price (A10):"
tab d_no_price if d_converted, m
qui su grams_h if d_converted
di as res _n "total grams over converted rows: " %16.0fc r(sum)

compress
sort hh_row
save "${btemp}\psps_converted", replace

preserve
	keep if !d_converted
	keep hhid pull_province pull_municipal_city pull_item pull_nsu_unit ///
	     harmonized_nsu_unit source q_h p_h conv_route gap_sym
	export delimited using "${btables}\psps_unconvertible.csv", replace
	di as txt "wrote ${btables}\psps_unconvertible.csv (" _N " row(s))"
restore

di as res _n "{hline 78}"
di as res "28_match_and_convert.do done. 29_cap.do bounds p_h/p_g on the converted rows."
di as res "{hline 78}"
