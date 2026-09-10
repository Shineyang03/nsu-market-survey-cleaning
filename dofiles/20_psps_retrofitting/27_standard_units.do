********************************************************************************
* 27_standard_units.do -- households that already answered in a standard unit
*
* WHAT THIS OWNS. Issue #14: where a PSPS household reported a quantity in a unit that
* states its own size -- "2 kilograms", "1 litro", "3 bottles (500 ml)" -- the market
* survey is not needed and must not be used. The unit name IS the conversion factor.
*
* IT IS 52,489 OF 87,959 HOUSEHOLD x ITEM x SLOT ROWS, 59.7%. The non-standard-unit
* problem this whole project exists for is the other 40%.
*
* THE FACTOR TABLE IS NOT DEFINED HERE. 20a_psps_households.do builds it, classifies every
* label against it, and carries `std_grams' onto the row -- so the definition and the
* classification live together and this file only multiplies. #14 asks for this to be one
* of the last steps in the pipeline, which it is in run order; that is about where the
* answer is assembled, not about where the table is declared.
*
* WHY NOT JUST CONVERT THESE UPSTREAM. Because they must stay countable. A reader asking
* "how much of PSPS food consumption rests on an NSU conversion at all" needs the standard
* rows present and labelled, not silently resolved in 20a and absent from every later
* count. The attrition question (#8) needs the same thing.
*
* ------------------------------------------------------------------------------
* THE ONE JUDGEMENT IN HERE IS RICE `gantang', AND IT IS RECORDED IN 20a
*
* A gantang is not metric, so calling it a standard unit is a decision rather than a
* reading of the label. It is made because the unit genuinely is standard -- our own 28
* weighings across 7 municipalities span 2,237.5 to 2,275 g, a 1.7% spread, against the
* 6.7x that A1 measures for camote tops `bundle'. It is the one conventional unit where
* A1's claim holds. 11,665 rows convert at 2,250 g on that basis. See 20a section 1 for
* the full history, including why the factor is our measurement and not the traditional
* 3 L / ~2.5 kg.
*
* ------------------------------------------------------------------------------
* INPUT   ${btemp}\psps_households.dta   20a, carrying conv_path and std_grams
* OUTPUT  ${bdeliv}\psps_standard_units.dta   one row per converted household row
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\27_standard_units.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

use "${btemp}\psps_households", clear

qui count
di as res _n "household x item x slot rows in: " r(N)

keep if conv_path == 1
qui count
di as res "  answering in a standard unit: " r(N)

* 20a asserts that conv_path 1 and a non-missing std_grams are the same set. Re-asserted
* here because this file multiplies by it: a missing factor would produce a missing gram
* figure that looks like an unconvertible row rather than a broken join.
assert !missing(std_grams) & std_grams > 0

* THE CONVERSION. cf_h is grams per unit and does not vary by household -- that is what
* makes these rows standard. It is named cf_h anyway so the column means the same thing
* here as in 28_match_and_convert.do and the two can be appended.
gen double cf_h    = std_grams
gen double grams_h = q_h * cf_h

label var cf_h    "grams (or mL) per unit -- from the unit's own name, not from the market survey"
label var grams_h "q_h * cf_h; total grams this row represents"

* A quantity of zero was already removed in 20a, so every row must produce a positive
* figure. A non-positive result here means a negative quantity reached this far.
qui count if !(grams_h > 0 & !missing(grams_h))
if r(N) > 0 {
	di as err "ERROR: " r(N) " row(s) convert to a non-positive or missing gram figure"
	list hhid pull_item pull_nsu_unit q_h std_grams if !(grams_h > 0 & !missing(grams_h)), noobs
	exit 459
}

* No fallback and no cap on this branch, and both absences are the point of #14. There is
* nothing to borrow -- the unit states its own size everywhere -- and there is no price
* ratio to extrapolate along, so #19's cap has no purchase here. Written as constants so
* the columns line up with 28's output on append.
gen byte   fallback_level = 0
gen byte   d_cap  = 0
gen byte   d_thin = 0
gen long   n_g    = .
gen str24  conv_route = "standard unit"
label var conv_route "how this row got its grams"
label var fallback_level "0 -- nothing is borrowed for a standard unit"
label var n_g "not applicable: no weighing stands behind a stated standard unit"

* Reported with tab + summarize rather than `table', whose column headers pick up the full
* variable LABELS and wrap the output past readability in a log file.
di as res _n "rows by how the factor was arrived at:"
tab std_basis
foreach b in metric stated measured {
	qui su grams_h if std_basis == "`b'"
	di as res "  `b': " %14.0fc r(sum) " g over " r(N) " row(s)"
}

di as res _n "the five biggest contributors, by total grams:"
preserve
	collapse (sum) tot_g = grams_h (count) n_rows = grams_h, by(pull_nsu_unit std_grams)
	gsort -tot_g
	list pull_nsu_unit std_grams n_rows tot_g in 1/5, noobs
restore

keep hhid psps_item_code pull_province pull_municipal_city pull_item pull_nsu_unit ///
     harmonized_nsu_unit source slot psps_month q_h e_h p_h ///
     cf_h grams_h conv_route std_basis std_grams fallback_level d_cap d_thin n_g hh_row

compress
sort hh_row
save "${bdeliv}\psps_standard_units", replace

qui count
di as res _n "{hline 78}"
di as res "27_standard_units.do done -- " r(N) " row(s) converted with no market-survey input"
di as res "{hline 78}"
