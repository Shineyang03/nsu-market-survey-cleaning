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
*    cream" says nothing about which. 65 of 1,941 weighed cells hold both, and section 2
*    picks the sub-cell with more weighings behind it. This changes a LABEL and almost
*    never a number: the project treats a millilitre and a gram as the same reading at the
*    precision recorded, because the items measured by volume are near water density.
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
*         ${btemp}\outcome2_lookup.dta          25
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

use "${btemp}\outcome2_lookup", clear
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
use "${btemp}\outcome2_lookup", clear
rename psps_month lk_month
label var lk_month "the month THIS LOOKUP ROW was restated to (Branch P only)"

* `share_uncertain' IS DROPPED, not renamed, and the distinction matters. On the lookup it
* describes the GROUP's weighings. On a household row the question is how questioned the
* weight THIS ROW WAS ACTUALLY GIVEN is -- which for a matched row is the same number, but
* for a fallback row is a different rung's entirely. Carrying the group's share onto a row
* served by a province pool would describe weighings the row never received. Section 7
* recomputes it from nu_used and n_g_used, which are filled per route.
*
* The counts themselves are kept: n_uncertain is what a matched row's nu_used reads from.
drop share_uncertain
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
	keep(1 3) nogen keepusing(fb_grams fb_n_g fb_nu fb_level fb_unconvertible)

gen str28 conv_route = ""
gen double cf_h = .
gen long   n_g_used = .
* nu_used is filled on the SAME line as n_g_used at every route below, so the two can only
* ever describe the same set of weighings. A row's uncertainty must come from wherever its
* weight came from -- the matched group, the cell pool, or a borrowed rung (#35).
gen long   nu_used = .
gen byte   fallback_level = .

* --- 1. the ordinary path -----------------------------------------------------
replace conv_route = "matched price point" if d_point_usable == 1 & d_spelling_gap == 0
replace cf_h = p_h / v_use  if conv_route == "matched price point" & d_no_price == 0 & branch != 1
replace cf_h = w_use        if conv_route == "matched price point" & d_no_price == 1
replace cf_h = w_use        if conv_route == "matched price point" & branch == 1
replace n_g_used = n_g      if conv_route == "matched price point"
replace nu_used  = n_uncertain if conv_route == "matched price point"
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
replace nu_used        = fb_nu    if conv_route == "fallback: empty size part"
replace fallback_level = fb_level if conv_route == "fallback: empty size part"
replace conv_route     = "refused: nothing anywhere" ///
	if conv_route == "fallback: empty size part" & fb_unconvertible == 1

assert conv_route != ""


********************************************************************************
**# 6. The households whose case had no usable group at all
********************************************************************************

append using "`nocase'"
replace conv_route = "" if missing(conv_route)

* THESE ARE #30's POPULATION and they are one row in six. Most of them are not "a case
* whose groups all failed" -- they are a case THE MARKET SURVEY NEVER VISITED, so no
* per-cell table can reach them. #30 counts 419 cells needing a province fallback and 75
* needing any province, 5,741 PSPS observations between them.
*
* THE LADDER IS CLIMBED FROM THE OTHER END for them: the cell's own pooled weight if it
* has one, then the province schedule, then the national one, then refusal. Each schedule
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
	keep `coarse' corrected_unit fb_grams fb_n_g fb_nu fb_level
	rename (corrected_unit fb_grams fb_n_g fb_nu fb_level) (r1_dim r1_g r1_n r1_nu r1_lvl)
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
	keep pull_province pull_item harmonized_nsu_unit corrected_unit fb_grams fb_n_g fb_nu fb_level
	rename (corrected_unit fb_grams fb_n_g fb_nu fb_level) (r2_dim r2_g r2_n r2_nu r2_lvl)
	isid pull_province pull_item harmonized_nsu_unit
	tempfile rung2
	save "`rung2'"
restore

* ---- rung: the national schedule --------------------------------------------
preserve
	use "${btemp}\outcome2_fallback_national", clear
	bysort pull_item harmonized_nsu_unit: egen double _best = max(fb_n_g)
	bysort pull_item harmonized_nsu_unit: ///
		egen byte _pick = min(cond(fb_n_g == _best, corrected_unit, .))
	keep if corrected_unit == _pick
	bysort pull_item harmonized_nsu_unit: gen byte _ndim = _N
	assert _ndim == 1
	keep pull_item harmonized_nsu_unit corrected_unit fb_grams fb_n_g fb_nu fb_level
	rename (corrected_unit fb_grams fb_n_g fb_nu fb_level) (r3_dim r3_g r3_n r3_nu r3_lvl)
	isid pull_item harmonized_nsu_unit
	tempfile rung3
	save "`rung3'"
restore

merge m:1 `coarse' using "`rung1'", keep(1 3) nogen keepusing(r1_dim r1_g r1_n r1_nu r1_lvl)
merge m:1 pull_province pull_item harmonized_nsu_unit using "`rung2'", ///
	keep(1 3) nogen keepusing(r2_dim r2_g r2_n r2_nu r2_lvl)
merge m:1 pull_item harmonized_nsu_unit using "`rung3'", ///
	keep(1 3) nogen keepusing(r3_dim r3_g r3_n r3_nu r3_lvl)

* FINEST RUNG FIRST, and each `if' requires conv_route still empty so an earlier rung
* cannot be overwritten by a coarser one.
replace corrected_unit = r1_dim if conv_route == "" & !missing(r1_g)
replace cf_h           = r1_g   if conv_route == "" & !missing(r1_g)
replace n_g_used       = r1_n   if conv_route == "" & !missing(r1_g)
replace nu_used        = r1_nu  if conv_route == "" & !missing(r1_g)
replace fallback_level = r1_lvl if conv_route == "" & !missing(r1_g)
replace conv_route     = "fallback: cell pooled"     if conv_route == "" & !missing(r1_g)

replace corrected_unit = r2_dim if conv_route == "" & !missing(r2_g)
replace cf_h           = r2_g   if conv_route == "" & !missing(r2_g)
replace n_g_used       = r2_n   if conv_route == "" & !missing(r2_g)
replace nu_used        = r2_nu  if conv_route == "" & !missing(r2_g)
replace fallback_level = r2_lvl if conv_route == "" & !missing(r2_g)
replace conv_route     = "fallback: province pool"   if conv_route == "" & !missing(r2_g)

replace corrected_unit = r3_dim if conv_route == "" & !missing(r3_g)
replace cf_h           = r3_g   if conv_route == "" & !missing(r3_g)
replace n_g_used       = r3_n   if conv_route == "" & !missing(r3_g)
replace nu_used        = r3_nu  if conv_route == "" & !missing(r3_g)
replace fallback_level = r3_lvl if conv_route == "" & !missing(r3_g)
replace conv_route     = "fallback: national pool"   if conv_route == "" & !missing(r3_g)

replace conv_route     = "refused: nothing anywhere" if conv_route == ""
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

gen byte d_converted = !missing(grams_h)
gen byte d_thin = n_g_used < ${THIN} if !missing(n_g_used)
replace  d_thin = 0 if missing(d_thin)

* Every route either produces grams or does not, and which is which is part of the route's
* meaning rather than an outcome of the data. A "matched price point" row with no grams
* would mean the lookup handed over a usable group with no weight.
assert !missing(grams_h) if strpos(conv_route, "refused") == 0
assert missing(grams_h)  if strpos(conv_route, "refused") > 0
assert grams_h > 0 if !missing(grams_h)

* ---- the uncertainty carried onto the household row (#35) --------------------------
* EVERY CONVERTED ROW MUST KNOW how questioned the weight it was given is. A converted row
* with nothing here would be a gram figure whose provenance stops at the number, which is
* the gap this whole change closes -- and it would arrive as a clean build, since a
* missing count reads as "not questioned" in every summary downstream.
assert !missing(nu_used) if d_converted == 1
assert !missing(n_g_used) if d_converted == 1

* A refused row has no weight, so it must carry no count either. Zero would assert
* something about a set of weighings the row never received.
assert missing(nu_used) if d_converted == 0

* Subset of the weighings it counts within, at whichever level supplied them.
assert nu_used <= n_g_used if !missing(nu_used)

gen double share_uncertain = nu_used / n_g_used
format share_uncertain %5.3f

label var cf_h        "grams (or mL) in one unit of the NSU this household reported"
label var grams_h     "q_h * cf_h -- total grams for this household x item x slot"
label var conv_route  "how this row got its grams, or why it did not"
label var n_g_used    "weighings behind cf_h, at the level actually used"
label var nu_used     "of n_g_used, how many were disputed or anchor-flagged (#35)"
label var share_uncertain ///
	"nu_used / n_g_used; 1 = nothing behind this row's weight went unquestioned"
label var d_no_price  "1 = no faced price (own production or gift); converted at the group's own weight"
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
di as res _n "how questioned the weight behind each converted row is (#35):"
table fallback_level if d_converted, statistic(frequency) ///
	statistic(mean share_uncertain) nformat(%9.3f)
qui count if d_converted == 1 & share_uncertain == 1
local n_all_u = r(N)
qui count if d_converted == 1
di as res "  rows whose weight rests ENTIRELY on questioned weighings: " ///
	%8.0fc `n_all_u' "  of " %8.0fc r(N)
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
