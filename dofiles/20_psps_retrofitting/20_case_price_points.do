********************************************************************************
* 20_case_price_points.do -- how many price points a case gets, and which are usable
*
* WHAT THIS OWNS. Outcome 2 cuts a case's pooled weights into as many groups as the case
* has price points, and matches a household to one of them by price. This file decides
* what those points ARE. It is the only place the price file is read for grouping.
*
* A CASE HERE IS prov x mun x item x harmonized_nsu_unit -- WITHOUT corrected_unit, and
* that is forced rather than chosen. `corrected_unit' (g vs mL) exists only on the market
* survey side; a price row has no dimension to split on. 65 of 1,941 weighed cells span
* both g and mL, so those cells' two sub-cells share one set of points. The branch builds
* join on this coarser key deliberately; see the note in section 6.
*
* ==============================================================================
* THE MERGE RULE (issue #21 sec 2, settled there)
*
*   1  Take the price rows of the spellings that were WEIGHED in this cell. A spelling
*      priced but never weighed contributes no weight moment, so it cannot inform a
*      group -- issue #21 sec 1. Its price level is still computed, in section 7, because
*      the spelling-price gap flag needs it.
*   2  Union on the PESO VALUE. Two spellings both quoting PHP 60 give one point at 60.
*   3  Merge points within PHP 20 of each other, single-linkage, so a chain of near-equal
*      values collapses to one. Merging is on the VALUE, NOT THE RUNG LABEL -- the mp25 of
*      one spelling may merge with the mp50 of another.
*   4  The merged point takes the MEAN of the values in it. PHP 17.50 and PHP 8 give 12.75.
*
* WHY PHP 20. It is the price file's own threshold, not a new one: NSU_Analysis.R does not
* record a municipal price separately when it is within PHP 20 of the province median, and
* collapses quartiles to the median alone when both quartile gaps are within PHP 20.
*
* KNOWN AND ACCEPTED INCONSISTENCY. The merge applies only where harmonization pooled more
* than one weighed spelling. A single-spelling case keeps its points as recorded however
* close they are, and 452 of 959 single-spelling quartile triples have an adjacent gap of
* PHP 20 or less. So identical gaps are merged in one case and kept in another. The rule is
* scoped to what the fold created and leaves the price file's own output alone; extending
* it would touch 452 cases and is a different decision.
*
* ==============================================================================
* THE unique_mun_price ARM -- decided, and it is what unblocked this file
*
* A `unique_mun_price' is a municipal price recorded because the cell had at most two
* distinct PSPS prices. By design it accompanies a province median, and because the price
* file folds away any municipal price within PHP 20 of that median, EVERY SURVIVING unique
* price is far from the central tendency: gap median PHP 55, 75th percentile PHP 130, max
* PHP 1,110. CF_h is linear in 1/p_g, so choosing a unique price over the median rescales
* every conversion factor in the case by up to 6x.
*
* THE RULE. A unique-price point is usable only where a market-survey weighing IN THAT
* CELL was actually recorded against a unique price. Everywhere else the point survives
* for MATCHING but yields no weight -- `.c', reported unconvertible, never imputed.
*
* Stated that way it is one rule, and the data collapses it to something simpler still.
* All 33 weighings recorded against a unique price (item_nsu_hetero_type 10 or 11) are on
* the PRICE-QUANTITY branch, in 12 cases, and every one carries `pull_price'. Outcome 2's
* price-quantity branch never consults the price file -- it uses `pull_price' per weighing
* (#21 sec 2 rows 5-6) -- so on exactly the cells where a unique price is legitimate, it
* arrives as an ordinary point by a different route and needs nothing from this file.
* Asserted in section 5, because the rule and the shortcut only coincide while that holds.
*
* WHAT THAT LEAVES, and why it is refused rather than substituted:
*
*   size-based cell, price file holds a unique price   196 cases  -> point is .c
*   conventional cell, ditto                            20 cases  -> Branch C uses no
*                                                                    price point at all
*   price-only cell (no MS weighing), ditto             97 cases  -> no weight moment
*                                                                    exists anyway (#30)
*
* A CELL IS NEVER EMPTIED BY THIS. Every unique-price cell carries another point: 347 of
* 351 hold a province median beside it and the other 4 hold a full quartile triple. So the
* refusal removes an ARM, not a case.
*
* AND THE HOUSEHOLD STILL MATCHES THE REFUSED POINT. It is not removed from the ladder.
* A household whose own unit price sits nearest a unique price is precisely the household
* whose conversion would be the 6x extrapolation, so it comes back unconvertible instead
* of silently falling through to the province median. Groups are cut on the CONVERTIBLE
* points only (n_points_conv), so the refused arm consumes no group either.
*
* Logged as A16 in docs/implicit_assumptions.md.
*
* ==============================================================================
* INPUTS  ${pricedata}                    NSU_prices_from_Makayla.csv
*         ${btemp}\master_nsu_rename.dta  the crosswalk, normalized by 03_clean_ms.do
*         ${btemp}\nsu_weighings_cpi.dta  the weighings, carrying `branch' from 08
*
* OUTPUTS ${btemp}\case_price_points.dta       one row per case x point
*         ${btemp}\case_spelling_gap.dta       the A11 gap flag, one row per mixed case
*         ${btables}\case_price_points.csv     the same, for inspection
*         ${btables}\price_points_refused.csv  the .c points, with what the case keeps
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\20_case_price_points.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

* PHP 20, the price file's own tolerance. One definition; see the header for provenance.
local PMERGE = 20

* A11's cut. docs/implicit_assumptions.md A11 -- the ratio beyond which a weighed and an
* unweighed spelling in one harmonized case are treated as probably different objects.
local GAP_FLAG = 2.0

confirm file "${pricedata}"


********************************************************************************
**# 1. The price file, on the crosswalk's keys
********************************************************************************

import delimited "${pricedata}", clear varnames(1)
cap drop v1
qui count
di as res _n "price rows in: " r(N)

rename unit_lbl pull_nsu_unit
rename price    p_raw

* p_raw MUST BE NUMERIC, and it is not safe to assume it arrives that way. This is a
* hand-maintained CSV, `import delimited' infers each column's type from its contents, and
* one blank Price cell plus any stray character anywhere in the column is enough to make
* the whole thing a string -- at which point `p_raw <= 0' is an r(109) type mismatch and
* every comparison below would have been silently wrong if it had not been.
*
* AND IT DOES NOT, ON THIS VINTAGE. Exactly one of the 5,412 rows carries the literal
* string "NA" -- R's missing marker, written into the CSV as text. pandas reads "NA" as a
* missing and gets a float column, which is why no Python diagnostic ever noticed; Stata
* reads it as a character and the ENTIRE column becomes a string.
*
* The row is a placeholder, not a lost price: NEGROS OCCIDENTAL / MANAPLA / Loaf Bread /
* Large, with every numeric field NA and only province, municipality, uuid and price_type
* filled. It is the slot where a SECOND unique price would have gone. That case keeps its
* real unique price of PHP 120 and its province median of PHP 90, so dropping the row
* costs the ladder nothing.
*
* "NA" IS TRANSLATED, NOT FORCED. `destring, force' would also make this row missing --
* and would make missing any future value it could not parse, which is the one behaviour
* that must not happen here: a price that cannot be read is a price point this file would
* then silently omit from a case's ladder. Naming the one marker we accept keeps the
* difference between "known missing" and "unreadable" intact.
capture confirm numeric variable p_raw
if _rc {
	qui count if trim(p_raw) == "NA"
	di as txt "Price imported as a string; " r(N) " row(s) hold R's literal NA."
	qui replace p_raw = "" if trim(p_raw) == "NA"
	destring p_raw, replace
	capture confirm numeric variable p_raw
	if _rc {
		di as err "ERROR: Price will not destring after clearing NA."
		di as err "It holds some other non-numeric value. Find it; do NOT add force,"
		di as err "which would silently drop a real price point."
		exit 109
	}
}

* The project's one normalization, called rather than re-implemented. 00b_price_ms_cases.do
* does its own lower/ascii pass on this same file for a different purpose; this file uses
* nsu_normalize so its keys are identical to the crosswalk's by construction.
nsu_normalize, item(cons_name) unit(pull_nsu_unit) ///
	mun(pull_municipal_city) province(province)
rename cons_name pull_item
rename province  pull_province

* price_type is a fixed vocabulary and the whole arm below keys on one of its values, so a
* renamed or re-spelled category has to stop the build rather than silently classify every
* unique price as an ordinary point. This is the `(0 real changes made)' failure mode.
replace price_type = ustrtrim(ustrlower(price_type))

* `tab', not `levelsof' into a macro and `di'. Two of these values contain a space, so
* levelsof returns them compound-quoted -- `"municipality median"' -- and embedding that
* macro inside a double-quoted display string is an r(198) invalid name. The tab prints
* the same information and cannot be broken by the content of the data.
di as txt "price_type values present:"
tab price_type

gen byte _known = inlist(price_type, "mp25_price", "mp50_price", "mp75_price", ///
	"municipality median", "province median", "unique_mun_price")
qui count if _known == 0
if r(N) > 0 {
	di as err "ERROR: " r(N) " price row(s) carry an unrecognised price_type."
	di as err "The unique_mun_price arm keys on this vocabulary -- see section 5."
	tab price_type if _known == 0
	exit 459
}
drop _known

* A point with no value is not a point.
qui count if missing(p_raw) | p_raw <= 0
if r(N) > 0 {
	di as res "dropping " r(N) " price row(s) with no usable value"
	drop if missing(p_raw) | p_raw <= 0
}

keep pull_province pull_municipal_city pull_item pull_nsu_unit price_type p_raw


********************************************************************************
**# 2. The harmonized unit
********************************************************************************
* The price file is keyed on the RAW spelling; both outcomes pool on the harmonized unit.
* The crosswalk is what connects them, and it holds a row for every (cell, raw label) that
* appears in either source -- so an unmatched price row means the crosswalk and the price
* file have diverged, which is #33's failure and must halt rather than warn.

* THE TRIMMED LABELS COME OUT FIRST, and they have to, because the live crosswalk no
* longer holds them. 02_drop_non_nsu_labels.py removed the labels that are not NSUs --
* standard quantity, ambiguous quantity, free text -- from master_nsu_rename.csv and wrote
* what it removed to master_rename_dropped_labels.csv. Several of those labels came from
* the price file, so their price rows have no crosswalk row BY DESIGN. Without this step
* they would be indistinguishable from a genuine crosswalk/price divergence, which is the
* thing the assertion below exists to catch.
*
* Read from that script's own report rather than re-deciding what is not an NSU: one
* definition of the rule, as with 20a.
preserve
	import delimited "${tables}\master_rename_dropped_labels.csv", clear ///
		varname(1) stringcols(_all)
	rename province  pull_province
	rename cons_name pull_item
	nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
		mun(pull_municipal_city) province(pull_province)
	keep pull_province pull_municipal_city pull_item pull_nsu_unit
	duplicates drop
	gen byte d_trimmed = 1
	tempfile trimmed
	save "`trimmed'"
restore

merge m:1 pull_province pull_municipal_city pull_item pull_nsu_unit ///
	using "`trimmed'", keep(1 3) nogen keepusing(d_trimmed)
qui count if d_trimmed == 1
di as res "price rows on a label the non-NSU trim removed: " r(N) " (dropped)"
drop if d_trimmed == 1
drop d_trimmed

merge m:1 pull_province pull_municipal_city pull_item pull_nsu_unit ///
	using "${btemp}\master_nsu_rename", keep(1 3) ///
	keepusing(harmonized_nsu_unit) generate(_m_xw)

qui count if _m_xw == 1
if r(N) > 0 {
	di as err "ERROR: " r(N) " price row(s) have no crosswalk entry and were not trimmed."
	di as err "The crosswalk is built FROM this file, so a non-match means they diverged."
	list pull_province pull_municipal_city pull_item pull_nsu_unit if _m_xw == 1, noobs
	exit 459
}
drop _m_xw

* Belt and braces: a crosswalk row with an empty harmonized unit would pool nothing.
qui count if missing(harmonized_nsu_unit) | harmonized_nsu_unit == ""
if r(N) > 0 {
	di as err "ERROR: " r(N) " price row(s) matched a crosswalk row with no harmonized unit"
	exit 459
}

tempfile priced
save "`priced'"


********************************************************************************
**# 3. Which spellings were weighed, and what branch the cell is
********************************************************************************
* Two facts per cell, both from the weighings:
*
*   which raw spellings have a weight, so section 4 can drop the rest from grouping
*   whether any weighing was recorded against a unique price, for section 5
*
* `branch' NOT `weighing_approach'. This decides how a cell is PROCESSED, which is exactly
* the split 08_branch.do exists to make: a field-conventional cell whose (item, unit) pair
* mixes approaches elsewhere is processed as size-based, so it is not a Branch C cell and
* its points matter. See dofiles/README.md.

use "${btemp}\nsu_weighings_cpi", clear
keep if !missing(corrected_weight) & corrected_weight > 0

* Spelling grain -- which (cell, raw label) pairs carry a weight.
preserve
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit pull_nsu_unit
	duplicates drop
	gen byte d_weighed_spelling = 1
	tempfile weighedspell
	save "`weighedspell'"
restore

* Cell grain -- the branch, and whether a unique price was ever weighed against.
gen byte _uniq_weighed = inlist(item_nsu_hetero_type, 10, 11)

* THE ASSERTION THE ARM RESTS ON. A weighing recorded against a unique price must be
* price-quantity, because that is the only branch on which the enumerator was handed a
* peso amount at all. If a size-based weighing ever carries hetero type 10 or 11, the
* shortcut in section 5 -- that the legitimate unique prices arrive via `pull_price' and
* need nothing from the price file -- stops being true and the arm needs rewriting.
qui count if _uniq_weighed == 1 & weighing_approach != 2
if r(N) > 0 {
	di as err "ERROR: " r(N) " weighing(s) against a unique price are not price-quantity."
	di as err "Section 5's unique_mun_price arm assumes they all are. Re-read it."
	exit 459
}
qui count if _uniq_weighed == 1
di as res "weighings recorded against a unique price: " r(N)

collapse (max) d_uniq_weighed = _uniq_weighed (first) branch, ///
	by(pull_province pull_municipal_city pull_item harmonized_nsu_unit)
qui count if d_uniq_weighed == 1
di as res "  cells holding at least one: " r(N)
tempfile cellinfo
save "`cellinfo'"


********************************************************************************
**# 4. Drop the price rows of spellings that were never weighed here
********************************************************************************
* Issue #21 sec 1. A spelling with no weighing in the cell contributes no weight moment,
* so it cannot inform how the pooled weights are cut. It is not discarded: section 7
* computes its price level, which is the whole input to the A11 gap flag.

use "`priced'", clear
merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit pull_nsu_unit ///
	using "`weighedspell'", keep(1 3) nogen keepusing(d_weighed_spelling)
replace d_weighed_spelling = 0 if missing(d_weighed_spelling)

qui count if d_weighed_spelling == 0
di as res _n "price rows on a spelling never weighed in the cell: " r(N) ///
	" (kept for section 7, excluded from grouping)"

preserve
	keep if d_weighed_spelling == 0
	tempfile unweighed
	save "`unweighed'"
restore

keep if d_weighed_spelling == 1
drop d_weighed_spelling
drop pull_nsu_unit    // the union is on the VALUE; the spelling has done its work


********************************************************************************
**# 5. Union on the value, then merge within PHP 20
********************************************************************************

* Is this value quoted ONLY as a unique price? Computed before the union collapses the
* types, because a value quoted as BOTH a unique price and a median is a median as far as
* the arm is concerned -- there is a central tendency at that peso figure.
gen byte _is_uniq = (price_type == "unique_mun_price")
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit p_raw: ///
	egen byte value_all_uniq = min(_is_uniq)
drop _is_uniq

* WHICH TYPES QUOTED THIS VALUE, as six indicators rather than a concatenated string.
* `egen concat()' does not do this: it joins VARIABLES within an observation, not
* observations within a group, and it has no `unique' option. The alternative idiom -- a
* running string built with `types[_n-1] + ";" + price_type' -- depends on within-group row
* order, which is the sort-seed defect this project already has one instance of
* (dofiles/README.md, Determinism). Six flags depend on no order at all, and they are also
* what a reader would want to filter on.
gen byte has_mp25     = (price_type == "mp25_price")
gen byte has_mp50     = (price_type == "mp50_price")
gen byte has_mp75     = (price_type == "mp75_price")
gen byte has_mun_med  = (price_type == "municipality median")
gen byte has_prov_med = (price_type == "province median")
gen byte has_unique   = (price_type == "unique_mun_price")

foreach f in has_mp25 has_mp50 has_mp75 has_mun_med has_prov_med has_unique {
	bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit p_raw: ///
		egen byte _v_`f' = max(`f')
	drop `f'
	rename _v_`f' `f'
}

* ---- the union: one row per (case, distinct value) ---------------------------
* `keep' takes no `by' prefix, so the first row of each value is tagged and then filtered.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit p_raw: ///
	gen byte _firstval = (_n == 1)
keep if _firstval
drop _firstval price_type

* ---- single-linkage merge within PHP `PMERGE' --------------------------------
* Sorted ascending within the case, a new point starts wherever the gap to the previous
* value EXCEEDS the tolerance. On a sorted one-dimensional set that is exactly
* single-linkage clustering, so a chain of near-equal values collapses to one point even
* where its ends are more than PHP 20 apart -- which is the intended behaviour.
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit p_raw
by pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	gen byte _newpoint = (_n == 1) | (p_raw - p_raw[_n-1] > `PMERGE')
by pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	gen int point_id = sum(_newpoint)
drop _newpoint

* The merged point takes the MEAN of its members. Mapping a size onto a price rung already
* assumes small <-> mp25, which nothing in the data establishes; against that, the choice
* between two prices PHP 20 apart is not material, and the mean privileges no spelling.
collapse (mean) p_g = p_raw (count) n_merged = p_raw (min) point_all_uniq = value_all_uniq ///
         (max) has_mp25 has_mp50 has_mp75 has_mun_med has_prov_med has_unique, ///
         by(pull_province pull_municipal_city pull_item harmonized_nsu_unit point_id)

label var p_g          "price point, PHP per NSU -- mean of the values merged into it"
label var n_merged     "distinct peso values merged into this point"
label var point_all_uniq "1 = every value in this point was quoted only as a unique_mun_price"
label var has_mp25     "an mp25 quote is in this point"
label var has_mp50     "an mp50 quote is in this point"
label var has_mp75     "an mp75 quote is in this point"
label var has_mun_med  "a municipality median is in this point"
label var has_prov_med "a province median is in this point"
label var has_unique   "a unique_mun_price quote is in this point"

* point_all_uniq must agree with the flags, or the two descriptions of one point disagree
* and the arm in section 6 is keyed on the wrong one.
assert point_all_uniq == (has_unique == 1 & has_mp25 == 0 & has_mp50 == 0 & ///
	has_mp75 == 0 & has_mun_med == 0 & has_prov_med == 0)


********************************************************************************
**# 6. Which points are usable
********************************************************************************

merge m:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	using "`cellinfo'", keep(1 3) nogen keepusing(d_uniq_weighed branch)
replace d_uniq_weighed = 0 if missing(d_uniq_weighed)

* THE ARM. A unique-price-only point is usable exactly where the cell weighed against a
* unique price; otherwise it is .c. See the header for why refusal beats substitution.
gen byte d_point_unconvertible = (point_all_uniq == 1 & d_uniq_weighed == 0)
label var d_point_unconvertible ///
	"1 = a unique_mun_price point with no weighing behind it; matched to, then refused"

* Groups are cut on the CONVERTIBLE points. A refused point consumes no group -- cutting
* the pooled weights into a part that can never be paired with a weight would misassign
* every other part as well.
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	gen int n_points = _N
bysort pull_province pull_municipal_city pull_item harmonized_nsu_unit: ///
	egen int n_points_conv = total(d_point_unconvertible == 0)
label var n_points      "price points in this case, refused ones included"
label var n_points_conv "price points the weights are cut on -- 21_branch_size_based.do reads THIS"

* No case may lose every point. By design a unique price accompanies a province median, so
* this cannot fire on the current vintage -- and if it ever does, the case needs a decision
* rather than a silent zero-group cut.
qui count if n_points_conv == 0
if r(N) > 0 {
	di as err "ERROR: " r(N) " point-row(s) sit in a case with NO convertible point."
	di as err "Every unique-price cell is supposed to carry a median beside it."
	list pull_province pull_municipal_city pull_item harmonized_nsu_unit p_g has_unique ///
		if n_points_conv == 0, noobs
	exit 459
}

di as res _n "points by whether they are usable:"
tab d_point_unconvertible, m
di as res _n "refused points, by the branch of the cell they sit in:"
tab branch d_point_unconvertible, m
di as res _n "convertible points per case:"
preserve
	* egen tag, not `bysort: keep if _n == 1' -- `keep' takes no `by' prefix.
	egen byte _t = tag(pull_province pull_municipal_city pull_item harmonized_nsu_unit)
	keep if _t
	tab n_points_conv, m
restore


********************************************************************************
**# 7. The A11 spelling-price gap
********************************************************************************
* Issue #21 sec 5.3, decided there: option (a) for the bulk and option (c) for the tail.
*
* A household reporting a spelling that was priced but never weighed in its cell is
* matched against a ladder built entirely from the OTHER spelling's prices. CF_h is linear
* in p_h/p_g, so any price-level difference between the two spellings is silently
* converted into a size difference nobody measured. Where the two levels are close that is
* harmless and the household behaves like every other household -- option (a). Where they
* differ by `GAP_FLAG' or more, the two are probably not the same object, and the honest
* output is a flag rather than a number -- option (c).
*
* THE DATA CANNOT ADJUDICATE THIS and no sensitivity run will change that: the flagged
* spelling has no weighings, which is the definition of the population. A11 records it as
* a judgement for exactly that reason.
*
* BUILT HERE, IN STATA, rather than read from the Python diagnostic that measured it.
* 90_diagnostics/scope_spelling_price_gap.py keeps the sensitivity table across cuts,
* which is what a diagnostic is for; the flag the build acts on is a price computation and
* belongs in the file that owns prices.
*
* GRAIN: no corrected_unit, for the reason in the file header -- a price-only spelling has
* no dimension to split on.

preserve
	* level of the WEIGHED side: the median of the points the case actually uses
	keep if d_point_unconvertible == 0
	collapse (median) lvl_weighed = p_g, ///
		by(pull_province pull_municipal_city pull_item harmonized_nsu_unit)
	tempfile lvlweighed
	save "`lvlweighed'"
restore

preserve
	use "`unweighed'", clear
	collapse (median) lvl_unweighed = p_raw, ///
		by(pull_province pull_municipal_city pull_item harmonized_nsu_unit)
	merge 1:1 pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		using "`lvlweighed'", keep(3) nogen

	* Both sides present by construction of keep(3): these are the MIXED cases -- at least
	* one weighed spelling and at least one priced-but-unweighed spelling.
	* Guarded. A zero or missing level on either side gives a ratio that is missing or
	* infinite, and `gap_sym >= GAP_FLAG' would read a missing as ABOVE the cut -- Stata's
	* missing sorts high, so an unmeasurable case would be flagged as a divergent one. The
	* two are different findings and only one of them is about prices.
	gen double gap_ratio = .
	replace  gap_ratio = lvl_unweighed / lvl_weighed if lvl_weighed > 0 & lvl_unweighed > 0
	gen double gap_sym = .
	replace  gap_sym = max(gap_ratio, 1 / gap_ratio) if !missing(gap_ratio)
	gen byte d_spelling_gap = (gap_sym >= `GAP_FLAG') & !missing(gap_sym)

	qui count if missing(gap_sym)
	if r(N) > 0 {
		di as res "  " r(N) " mixed case(s) have no usable level on one side -- not flagged"
	}

	label var gap_ratio      "unweighed spelling's price level / weighed spelling's"
	label var gap_sym        "the same, folded so 0.4 and 2.5 read alike"
	label var d_spelling_gap "1 = the two levels differ by GAP_FLAG or more; flag, do not convert (A11)"

	qui count
	di as res _n "mixed cases (a weighed AND an unweighed spelling): " r(N)
	qui count if d_spelling_gap == 1
	di as res "  flagged at `GAP_FLAG'x: " r(N)
	qui su gap_sym, detail
	di as res "  gap distribution -- median " %5.2f r(p50) ", p75 " %5.2f r(p75) ///
		", max " %6.2f r(max)

	* The sensitivity, so a reader can disagree with the cut without rerunning anything.
	di as res "  cases flagged at other cuts:"
	foreach c in 1.25 1.5 2.0 3.0 5.0 {
		qui count if gap_sym >= `c'
		di as res "    " %5.2f `c' "x : " r(N)
	}

	compress
	sort pull_province pull_municipal_city pull_item harmonized_nsu_unit
	save "${btemp}\case_spelling_gap", replace
restore


********************************************************************************
**# 8. Save
********************************************************************************

drop point_all_uniq
label var branch      "how the cell is PROCESSED (08_branch.do), not what the field did"
label var pull_item           "item"
label var pull_province       "province"
label var pull_municipal_city "municipality"

compress
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit point_id
save "${btemp}\case_price_points", replace
export delimited using "${btables}\case_price_points.csv", replace

preserve
	keep if d_point_unconvertible == 1
	keep pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
	     p_g has_unique has_prov_med has_mun_med branch n_points n_points_conv
	export delimited using "${btables}\price_points_refused.csv", replace
	di as txt "wrote ${btables}\price_points_refused.csv (" _N " row(s))"
restore


********************************************************************************
**# 9. Report
********************************************************************************

qui count
di as res _n "{hline 78}"
di as res "20_case_price_points.do done -- " r(N) " point(s)"
di as res "{hline 78}"
preserve
	egen byte _t = tag(pull_province pull_municipal_city pull_item harmonized_nsu_unit)
	keep if _t
	qui count
	di as res "  cases with at least one point : " r(N)
restore
qui count if d_point_unconvertible == 1
di as res "  points refused (unique price, no weighing behind it): " r(N)
di as res ""
di as res "  21_branch_size_based.do cuts the pooled weights into n_points_conv parts."
di as res "  28_match_and_convert.do matches a household to the nearest point INCLUDING"
di as res "  a refused one, and returns .c where it lands on one."
di as res "{hline 78}"
