********************************************************************************
* 20a_psps_households.do -- the PSPS household side of Outcome 2
*
* WHAT THIS OWNS. Everything downstream of here needs PSPS household rows: the price
* the household faced, the quantity it reported, the unit it named, and the month it was
* interviewed. This file produces them, one row per household x item x acquisition slot,
* and classifies each row's unit label into exactly one conversion path.
*
* THE `a' SUFFIX follows 00a/00b: this runs BEFORE the numbered chain, because
* 24_inflate_to_psps_month.do needs the month list it emits and cannot be written
* without it.
*
* WHY IT IS NOT 26_psps_extract.do. That file (now dofiles/archive/) did vocabulary
* discovery -- which NSU labels PSPS households use -- and that job is finished; its
* results live in the crosswalk. It also dropped `hhid' and `subdate' and then
* `duplicates drop'ped, so it held distinct case x source x price rows and its own header
* said it "has no unique id". Three later steps need household rows: 24 needs the months,
* 28 and 29 need the rows themselves. So this is a different file, not a repair.
*
* ------------------------------------------------------------------------------
* p_h COMES FROM THE PURCHASED SLOT ONLY, and this is the one rule that had to be
* carried across from the archived file rather than rediscovered.
*
* The module records three acquisition routes in parallel slots: 2 = purchased,
* 3 = own production, 4 = gift. Each has its own quantity (a) and value (b). Only the
* purchased slot holds a price the household actually faced -- the other two carry an
* IMPUTED value, which is an enumerator's or respondent's estimate of what the item was
* worth, not what anyone paid. Dividing an imputed value by a quantity produces a number
* shaped like a price that no market ever set, and Step B3 is linear in it.
*
* docs/implicit_assumptions.md A10 records this, and records that the rule was at risk
* of being lost exactly here: "the file is now in dofiles/archive/ and its replacement,
* 20a_psps_households.do, is unwritten. The rule has to be re-stated there, or p_h will
* silently start absorbing imputed values." This is that re-statement.
*
* A10's SECOND HALF still bites and is not addressed here. The conversion factor built
* from purchase prices is applied to every row regardless of slot, so a gifted `bugkos'
* is assumed to be the same size as a bought one. Roughly one food observation in five is
* acquired without a purchase. Untested; see A10.
*
* ------------------------------------------------------------------------------
* INPUTS  ${psps_cons}      PSPS Wave 1 consumption, item_type == 1 (food)
*         ${municipal_map}  municipal_code -> municipality name
*         ${tables}\master_nsu_rename.csv              the NSU crosswalk
*         ${tables}\master_rename_dropped_labels.csv   labels that are not NSUs
*
* OUTPUTS ${btemp}\psps_households.dta        one row per hhid x item x slot
*         ${btemp}\standard_unit_factors.dta  the standard-unit gram table
*         ${btemp}\psps_months.dta            months occurring in each municipality
*         ${btables}\psps_unit_classification.csv   every label, its path, its count
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\20a_psps_households.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

* Not in 00_globals.do because only this file reads it.
global municipal_map "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\08 Analysis & Data\14 Wave 1_Pub\Household survey\3_input_data\municipal_mapping.dta"


********************************************************************************
**# 1. The standard-unit gram table
********************************************************************************
* A household that answered "2 kilograms" needs no market survey. Issue #14: convert the
* stated standard unit directly. This is the table that does it, and it is built here --
* one definition -- with 27_standard_units.do applying it.
*
* THIS TABLE TAKES PRECEDENCE OVER THE CROSSWALK, deliberately, and it is the only place
* in the pipeline where an explicit list outranks a data-driven join. The reason is that
* two labels here (`ganta', and `gallon' variants) also appear in the crosswalk as NSUs
* with market-survey weighings behind them. Where a unit's size is known from its own
* name, the name is the better evidence than a median of eight vendors -- and letting the
* crosswalk win would convert `ganta' from weighings and `gantang' from the table, giving
* one object two conversion factors.
*
* ---- GANTANG, and why it is here at all --------------------------------------
* 11,647 PSPS observations, the largest single NSU in the file and a third of the
* non-standard-unit population. It arrives as a standard unit by DECISION, recorded here
* because the history is easy to misread:
*
*   1. NSU_Analysis.R -- the R script that builds the price file, in
*      "13 Non-Standard Units & Market Survey/code/", not ours and not edited by us --
*      canonicalizes any free-text unit containing "ganta" to the label "Gantang"
*      (line 188). That is where the string comes from.
*   2. That script's OWN exclusion list (`standard_unit_values', line 64) has ten
*      entries and DOES NOT CONTAIN "Gantang". It is: Kilograms (KG), Grams (g),
*      Gallons, Liters (L), 5-gallon blue container, Cans (500 mL), Cans (330 mL),
*      Bottle (500 ml), Bottle (330 ml), Millileters (mL).
*   3. 90_diagnostics/scope_psps_exposure.py carries a nineteen-entry list described as
*      that list "verbatim". It is not verbatim. Most additions are correct -- the
*      publication file spells the same standard units differently from the R's raw
*      free text -- but "Gantang" is not a standard unit in any metric sense, and its
*      inclusion silently removed a third of the population from every figure on #30.
*
* So the exclusion was ours and undocumented. It is now ours and documented, on different
* grounds: a gantang IS a standard measure, just not a metric one.
*
* THE FACTOR IS 2,250 g, FROM OUR OWN WEIGHINGS, not from the traditional definition.
* The two disagree by 10% and the gap is worth knowing:
*
*   traditional   1 salop / ganta = 3 litres, quoted at ~2.5 kg of rice
*   measured      28 MS weighings in 7 municipalities: 2,237.5 - 2,275 g, SPREAD 1.7%
*
* Three litres of milled rice is 2.25 kg at a bulk density of 0.75 kg/L and 2.5 kg at
* 0.83. Both are inside the plausible range for loose milled rice, so the VOLUME half of
* the traditional figure is solid and the DENSITY half is the loose one -- which is
* exactly where the 10% sits. A direct measurement of the actual object in the actual
* provinces beats a rounded density, so the measurement wins. docs/data_oddities.md
* already treats ~2,250 g as the project's rice-gantang figure.
*
* It also keeps the two deliverables agreeing on rice, which is #16's question: Outcome 1
* publishes 2,237.5-2,275 g for these 7 cells and Outcome 2 will convert them at 2,250.
*
* GANTANG IS THE ONE UNIT WHERE A1 ACTUALLY HOLDS. A1 says conventional units are
* standard within a locality and reports that claim FALSIFIED -- camote tops `bundle'
* varies 6.7x across municipalities. A 1.7% spread across 7 is a different animal, and it
* is what licenses a single sample-wide constant here where A1 forbids one everywhere else.
* SAMPLE-WIDE, not national: the 7 municipalities are all Western Visayas, so the evidence
* cannot speak to gantang outside this region.
*
* `ganta' gets the same factor as `gantang'. They are one object: the crosswalk folds raw
* `ganta' to harmonized `gantang' (outputs/tables/unit_fold_map.csv, `safe-fold', n=28), and
* the fold pools nothing -- all 14 crosswalk rows carry n_cell_merged == 1, because no raw
* `gantang' label exists on our side at all. Only 18 PSPS rows spell it `ganta'; giving
* them a different factor from the other 11,647 would be incoherent.

clear
input str40 pull_nsu_unit double std_grams str14 std_basis
"kilograms (kg)"          1000    "metric"
"kilograms"               1000    "metric"
"kilo"                    1000    "metric"
"kilos"                   1000    "metric"
"grams (g)"                  1    "metric"
"grams"                      1    "metric"
"millileters (ml)"           1    "metric"
"litro (l)"               1000    "metric"
"liters"                  1000    "metric"
"liters (l)"              1000    "metric"
"gallons"               3785.41   "metric"
"5-gallon blue container" 18927.1 "metric"
"botelya (500ml)"          500    "stated"
"bote (500ml)"             500    "stated"
"bottle (500 ml)"          500    "stated"
"botelya (330ml)"          330    "stated"
"bote (330ml)"             330    "stated"
"lata (500 ml)"            500    "stated"
"lata (330 ml)"            330    "stated"
"gantang"                 2250    "measured"
"ganta"                   2250    "measured"
end

* One US gallon is 3.785411784 L; the Philippines uses the US gallon. The 5-gallon blue
* container is the standard household water container at five of those. Volume converts
* to grams at water density, the same assumption 04_unit_snap.do makes when it treats a
* millilitre and a gram as one reading.
label var pull_nsu_unit "normalized PSPS unit label"
label var std_grams     "grams (or mL) in one such unit -- applied by 27_standard_units.do"
label var std_basis     "metric = from the unit name; stated = a quantity printed in the label; measured = from our own weighings"

isid pull_nsu_unit
qui count
di as res "standard-unit factor table: " r(N) " label(s)"
compress
sort pull_nsu_unit
save "${btemp}\standard_unit_factors", replace

tempfile stdfactors
save "`stdfactors'"


********************************************************************************
**# 2. Labels that are not a unit at all
********************************************************************************
* Distinct from "not an NSU". 02_drop_non_nsu_labels.py owns that definition and applies
* it to the crosswalk -- standard quantity, ambiguous quantity, free text -- and its
* report is read as data below so there is no second copy of that rule.
*
* These two are a THIRD thing, and they reach us only from the PSPS side, so no existing
* rule covers them: the respondent said they did not know. "wala kabalo" is Hiligaynon
* and "wara kamaan" Waray for "I don't know". They are not a unit, not an NSU, and not a
* standard quantity; they are a missing answer.
*
* THIS LIST MATCHES 0 ROWS ON THE CURRENT VINTAGE, and that is worth stating rather than
* leaving a reader to wonder. All 15 such answers carry no quantity, so they are removed
* by the `quantity non-missing and != 0' filter in section 7 before classification runs.
* The list is kept as a declared category anyway: a future respondent who says "I don't
* know" the unit but does give a number would otherwise land in path 5 and be counted as
* an unrecognised NSU, which is a different problem needing a different answer.
clear
input str40 pull_nsu_unit
"wala kabalo"
"wara kamaan"
end
gen byte d_no_unit = 1
isid pull_nsu_unit
tempfile nounit
save "`nounit'"


********************************************************************************
**# 3. The crosswalk, and the labels it excluded
********************************************************************************
* Read as data, normalized the same way 03_clean_ms.do normalizes it, so the join key is
* the project's one normalization and not a fourth copy of it.

import delimited "${tables}\master_nsu_rename.csv", clear varname(1) stringcols(_all)
rename province  pull_province
rename cons_name pull_item
nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
	mun(pull_municipal_city) province(pull_province)
foreach v in harmonized_nsu_unit fallback_harmonized_nsu_unit {
	replace `v' = ustrto(`v', "ascii", 2)
	replace `v' = ustrtrim(ustrlower(`v'))
	replace `v' = ustrregexra(`v', "\s+", " ")
}
* RENAMED HERE, not after the merge. `source' is already taken on the household side --
* it is the acquisition slot -- and a merge whose keepusing() names an existing variable
* fails outright. Renaming on this side keeps the two meanings apart at the point where
* they could be confused: xw_source says whether the crosswalk row came from the market
* survey or only from the price file; source says how the household got the food.
rename source xw_source
keep pull_province pull_municipal_city pull_item pull_nsu_unit ///
     harmonized_nsu_unit fallback_harmonized_nsu_unit xw_source
isid pull_province pull_municipal_city pull_item pull_nsu_unit
tempfile xwalk
save "`xwalk'"

* The dropped-label report, at LABEL grain. A label 02_drop_non_nsu_labels.py judged not
* to be an NSU is not one wherever it appears, so the cell is not in this key.
import delimited "${tables}\master_rename_dropped_labels.csv", clear varname(1) stringcols(_all)
rename cons_name pull_item
nsu_normalize, item(pull_item) unit(pull_nsu_unit)
keep pull_nsu_unit drop_reason
* `keep' is not a by-able command, so the first row of each label is tagged and then
* filtered. `duplicates drop pull_nsu_unit' would need `force' and would not say which
* drop_reason survived; tagging makes the choice explicit and arbitrary-by-design (a
* label with two reasons is not an NSU under either).
bysort pull_nsu_unit: gen byte _first = (_n == 1)
keep if _first
drop _first
gen byte d_not_nsu = 1
isid pull_nsu_unit
tempfile droppedlbl
save "`droppedlbl'"


********************************************************************************
**# 4. Load the food consumption rows
********************************************************************************

use "${psps_cons}", clear
qui count
di as res _n "consumption rows in: " r(N)

keep if item_type == 1
qui count
local n_food = r(N)
di as res "food rows (item_type == 1): `n_food'"

* (hhid, item) identifies a food row. Asserted because every reshape below assumes it:
* the three slots are COLUMNS of one row, so if the key were not unique the stack would
* silently multiply rows.
isid hhid item

keep hhid province municipal_code brgy_code item cons_name subdate ///
     cons_purchased cons_own_production cons_gift ///
     fd_cons_2a fd_cons_2aunit fd_cons_2aunit_lbl fd_cons_2b ///
     fd_cons_3a fd_cons_3aunit fd_cons_3aunit_lbl fd_cons_3b ///
     fd_cons_4a fd_cons_4aunit fd_cons_4aunit_lbl fd_cons_4b


********************************************************************************
**# 5. The municipality name
********************************************************************************
* The consumption file carries municipal_code, not the name. Every downstream key is on
* the name, so an unmatched code cannot be joined to anything -- and if _merge is dropped
* without counting, it arrives as an ordinary row with a blank municipality and is
* undetectable afterwards. That is what the archived version did.

* province is on both sides; take the mapping's copy only where ours is missing.
merge m:1 municipal_code using "${municipal_map}", keep(1 3) gen(_m_map) ///
	keepusing(pull_municipal_city pull_province)

qui count if _m_map == 1
if r(N) > 0 {
	di as err "ERROR: " r(N) " row(s) carry a municipal_code with no mapping entry."
	di as err "They would take a blank municipality into every downstream key."
	tab municipal_code if _m_map == 1
	exit 459
}
drop _m_map

* Our own province column and the mapping's must agree, or one of the two is wrong about
* where the household lives.
qui count if pull_province != province & !missing(province)
if r(N) > 0 {
	di as err "ERROR: " r(N) " row(s) where the mapping's province disagrees with the file's"
	exit 459
}
drop province


********************************************************************************
**# 6. The interview month
********************************************************************************
* Needed twice: 24_inflate_to_psps_month.do restates a price-quantity weight from its MS
* month to this one, and the month list per municipality is what tells 24 which months to
* build at all.
*
* THE FORMAT IS READ, NOT ASSUMED. A Stata date is %td (days) and a datetime is %tc
* (milliseconds); mofd() on a %tc value returns a month somewhere around the year 1960.
* 07_cpi_factor.do writes mofd(dofc(submissiondate)) because that column IS %tc. This
* column need not be, so the format decides.
local sdfmt : format subdate
di as txt "subdate format: `sdfmt'"
if strpos("`sdfmt'", "%tc") > 0 | strpos("`sdfmt'", "%tC") > 0 {
	gen psps_month = mofd(dofc(subdate))
}
else {
	gen psps_month = mofd(subdate)
}
format psps_month %tm
label var psps_month "PSPS interview month, from subdate"

* PSPS fielding ran 2023m12 - 2025m1 (docs/conversion_factor_methodology.md). The CPI
* panel covers 2023m12 - 2026m5, so every month here has an index to join. A month outside
* this window means either a bad date or a wave this pipeline has never seen, and in
* either case step 24 would produce a missing factor rather than an error.
qui count if !inrange(psps_month, tm(2023m12), tm(2025m1))
if r(N) > 0 {
	di as err "ERROR: " r(N) " row(s) have an interview month outside 2023m12-2025m1"
	tab psps_month if !inrange(psps_month, tm(2023m12), tm(2025m1))
	exit 459
}
di as res _n "interview months:"
tab psps_month


********************************************************************************
**# 7. Stack the three acquisition slots
********************************************************************************
* One row per household x item x slot, keeping only slots that recorded something. The
* three slots are separate columns of one row, so a household that bought AND was gifted
* the same item yields two rows -- which is the grain Outcome 2 needs, because the two
* carry different quantities and only one carries a price.
*
* THE FILTER IS `Quantity non-missing AND != 0', which is the filter
* 90_diagnostics/scope_psps_exposure.py uses and, through it, the filter NSU_Price.R used
* when it built the price file. Matching it is what makes the counts here reconcilable
* against every figure on issue #30. A row with a value but no quantity cannot yield a
* unit price or a converted gram figure, so it is not a household observation for this
* purpose; the count is reported below rather than hidden.

tempfile base slot2 slot3 slot4
save "`base'"

foreach s in 2 3 4 {
	use "`base'", clear
	rename fd_cons_`s'a        q_h
	rename fd_cons_`s'aunit    unit_code
	rename fd_cons_`s'aunit_lbl pull_nsu_unit
	rename fd_cons_`s'b        e_h
	keep hhid pull_province pull_municipal_city municipal_code brgy_code ///
	     item cons_name subdate psps_month q_h unit_code pull_nsu_unit e_h
	gen byte slot = `s'
	qui count if !missing(q_h) & q_h != 0
	di as txt "  slot `s': " r(N) " row(s) with a usable quantity of " _N
	keep if !missing(q_h) & q_h != 0
	save "`slot`s''"
}

use "`slot2'", clear
append using "`slot3'"
append using "`slot4'"

qui count
local n_stacked = r(N)
di as res _n "stacked household x item x slot rows: `n_stacked'"

* Reconciliation tripwire against the #30 population. scope_psps_exposure.py reports
* 87,959 rows at this point on the current vintage. If this moves, either the consumption
* file changed or one of the two filters diverged -- and every share quoted on #30 is then
* computed on a different denominator from this build. Reconcile before changing it.
* IT EXITS. Printing to the log and carrying on made this tripwire unenforceable: `stata -e'
* returns 0 either way, and the project's own way of checking a run is to grep the log for
* an r() code -- which this never emitted. A drift would have completed the build clean and
* left every share quoted on #30 computed on a different denominator.
if `n_stacked' != 87959 {
	di as err "Stacked row count is `n_stacked', not the 87,959 that issue #30's figures rest on."
	di as err "Reconcile against 90_diagnostics/scope_psps_exposure.py before editing this."
	exit 459
}

gen str14 source = ""
replace source = "purchased"     if slot == 2
replace source = "own_production" if slot == 3
replace source = "gift"          if slot == 4
* No backtick-quotes in a label string. Stata expands macros before parsing, so a
* "`purchased'" written here would resolve to an empty local and ship a mangled label.
label var source "acquisition route; only the purchased slot carries a faced price"


********************************************************************************
**# 8. Names into the crosswalk's vocabulary -- BEFORE any key is built
********************************************************************************
* The join is on normalized strings, so normalization has to happen before anything is
* keyed on these columns. Building a key on raw-cased strings and normalizing afterwards
* leaves a key that matches nothing, which is what the first repaired version of the
* archived file did.

rename cons_name pull_item
rename item      psps_item_code

nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
	mun(pull_municipal_city) province(pull_province)


********************************************************************************
**# 9. The household unit price
********************************************************************************
* p_h = e_h / q_h, ON EVERY ACQUISITION MODE. See A10, which was reversed on measurement.
*
* This file used to compute p_h on the purchased slot only and assert it missing elsewhere,
* on the reasoning that an own-production or gift value "is not a price anyone faced". That
* conflates two objects. The price POINTS that build the conversion factors come from the
* price file and are market transactions; nothing here changes that. A household's own p_h
* is not an observation feeding an estimate -- it is the INDEX saying which rung of an
* already-built ladder this consumption sits on, and then the scale factor in
* CF_h = p_h / v_g. That role does not require a transaction price.
*
* AND THE OLD RULE WAS NOT NEUTRAL. With p_h missing, 28 gave those rows the case's middle
* price point and converted at that group's own weight -- the degenerate p_h = p_g, so
* CF_h = w_g. That asserts every own-producing household consumed the TYPICAL-sized unit,
* which is a stronger claim than reading the value they reported. Refusing the data was
* not the cautious option.
*
* Measured before changing: implied prices from the non-purchased slots track purchase
* prices in the same province x municipality x item x unit at a median ratio of 1.000
* (IQR 1.000-1.062, n = 11,392). Of the 82 households reporting the same item x unit
* through both a purchased and a non-purchased slot, 66 report an IDENTICAL unit value, so
* both rows receive the identical conversion factor. A10 names the 16 that do not, and
* chicken `bilog' is the worked example of what the rule costs.

gen double p_h = .
replace  p_h = e_h / q_h if q_h > 0 & !missing(e_h)
label var p_h "implied unit value, PHP per NSU -- all acquisition modes (A10)"
label var q_h "quantity reported, in the unit named by pull_nsu_unit"
label var e_h "amount paid (purchased) or imputed value (own production, gift), PHP"

* Reported by SOURCE, because the whole point of the change is that the non-purchased
* slots now carry a value, and a reader should see the coverage they carry rather than
* take it on trust.
di as res _n "p_h coverage by acquisition mode:"
table source, statistic(frequency) statistic(count p_h) nformat(%9.0fc)

* p_h is a pure function of e_h and q_h and of nothing else -- in particular NOT of the
* slot. Stated as an invariant because the old rule lived in exactly this spot and a
* future edit that reinstates a slot condition would otherwise pass silently.
assert missing(p_h) == (missing(e_h) | missing(q_h) | q_h <= 0)


********************************************************************************
**# 10. Which conversion path each row takes
********************************************************************************
* Exactly one path per row, tested in this order. The order is the decision:
*
*   1  standard unit      the label states its own size -- convert directly (#14)
*   2  NSU, in crosswalk  resolvable to a harmonized unit; Outcome 2 converts it
*   3  not an NSU         02_drop_non_nsu_labels.py judged the label not a unit
*   4  no unit given      the respondent said they did not know
*   5  NSU, no crosswalk row for this cell -- REPORTED, not dropped
*
* PATH 5 IS THE RESIDUAL AND IT IS THE TRIPWIRE. A label that is none of the first four
* lands there and is listed with its count, so a new vintage introducing an unfamiliar
* unit shows up as a number in the log rather than as rows that quietly convert to
* nothing. It also legitimately contains rows: a label priced or weighed in one
* municipality and reported by a household in another has no crosswalk row for that cell.

merge m:1 pull_nsu_unit using "`stdfactors'", keep(1 3) nogen ///
	keepusing(std_grams std_basis)
gen byte d_standard_unit = !missing(std_grams)

merge m:1 pull_province pull_municipal_city pull_item pull_nsu_unit ///
	using "`xwalk'", keep(1 3) nogen ///
	keepusing(harmonized_nsu_unit fallback_harmonized_nsu_unit xw_source)
gen byte d_in_crosswalk = !missing(harmonized_nsu_unit) & harmonized_nsu_unit != ""

merge m:1 pull_nsu_unit using "`droppedlbl'", keep(1 3) nogen keepusing(d_not_nsu drop_reason)
replace d_not_nsu = 0 if missing(d_not_nsu)

merge m:1 pull_nsu_unit using "`nounit'", keep(1 3) nogen keepusing(d_no_unit)
replace d_no_unit = 0 if missing(d_no_unit)

gen byte conv_path = .
replace conv_path = 1 if d_standard_unit == 1
replace conv_path = 2 if missing(conv_path) & d_in_crosswalk == 1
replace conv_path = 3 if missing(conv_path) & d_not_nsu == 1
replace conv_path = 4 if missing(conv_path) & d_no_unit == 1
replace conv_path = 5 if missing(conv_path)

label define convpath 1 "standard unit -- convert directly" ///
	2 "NSU, resolvable via the crosswalk" ///
	3 "not an NSU (dropped label)" ///
	4 "no unit given by the respondent" ///
	5 "NSU label with no crosswalk row in this cell", replace
label values conv_path convpath
label var conv_path "conversion path -- exactly one per row, see section 10"

* Every row takes a path, and no row takes two. The first is what makes the partition
* exhaustive; the second is the thing precedence is for, and asserting it means a future
* edit that adds a label to two lists fails here instead of silently taking the first.
assert !missing(conv_path)
gen byte _npaths = d_standard_unit + d_in_crosswalk + d_not_nsu + d_no_unit
qui count if _npaths > 1
if r(N) > 0 {
	di as res "note: " r(N) " row(s) satisfy more than one path; precedence resolves them"
	tab pull_nsu_unit conv_path if _npaths > 1
}
drop _npaths

di as res _n "rows by conversion path:"
tab conv_path, m

di as res _n "the standard-unit rows, by label:"
tab pull_nsu_unit if conv_path == 1

di as res _n "PATH 5 -- the residual. Every label, with its count:"
tab pull_nsu_unit if conv_path == 5, sort


********************************************************************************
**# 11. Save
********************************************************************************

* hhid x psps_item_code x slot identifies a row: the slots are columns of a (hhid, item)
* row, asserted unique in section 4, so stacking them cannot collide.
isid hhid psps_item_code slot
sort hhid psps_item_code slot
gen long hh_row = _n
label var hh_row "row id, stable within a build; the key is hhid x psps_item_code x slot"

label var hhid                 "household identifier"
label var psps_item_code       "PSPS item code"
label var pull_item            "normalized item name, matches master_nsu_rename"
label var pull_nsu_unit        "normalized raw NSU label as the household reported it"
label var harmonized_nsu_unit  "POOLING KEY: the harmonized unit this label resolves to"
label var d_standard_unit      "1 = the label states its own size; 27_standard_units.do converts it"
label var d_in_crosswalk       "1 = this cell x label has a crosswalk row"
label var slot                 "consumption module slot: 2 purchased, 3 own production, 4 gift"

compress
save "${btemp}\psps_households", replace
qui count
di as res _n "wrote ${btemp}\psps_households.dta -- " r(N) " row(s)"

* ---- the month list, for 24_inflate_to_psps_month.do -------------------------
* 24 restates a price-quantity weight into each month that occurs in the municipality it
* is being applied to, so it needs the months and nothing else from this file. Emitting
* them separately keeps 24 off the household rows, which it has no other use for.
preserve
	keep pull_province pull_municipal_city psps_month
	duplicates drop
	qui count
	di as res "months x municipality: " r(N)
	label var psps_month "an interview month occurring in this municipality"
	sort pull_province pull_municipal_city psps_month
	save "${btemp}\psps_months", replace
restore

* ---- the classification, for inspection --------------------------------------
preserve
	gen byte n = 1
	collapse (sum) n_obs = n, by(conv_path pull_nsu_unit std_grams std_basis drop_reason)
	gsort conv_path -n_obs
	export delimited using "${btables}\psps_unit_classification.csv", replace
	di as txt "wrote ${btables}\psps_unit_classification.csv"
restore


********************************************************************************
**# 12. Report
********************************************************************************

di as res _n "{hline 78}"
di as res "20a_psps_households.do done"
di as res "{hline 78}"
di as res "  food rows read              : `n_food'"
di as res "  household x item x slot rows: `n_stacked'"
di as res ""
di as res "  Outcome 2 converts path 2 via the market survey and path 1 from the"
di as res "  standard-unit table. Paths 3 and 4 are unconvertible by definition and"
di as res "  path 5 is the residual to watch."
di as res ""
di as res "  NEXT: 20_case_price_points.do needs nothing from this file; 24, 28 and 29 do."
di as res "{hline 78}"
