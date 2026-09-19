********************************************************************************
* photo_check_scope.do -- how much of the build rests on a decision a photograph
* could overturn?
*
* MEASUREMENT ONLY. Prints counts; writes nothing. It exists so the figures quoted
* in the photograph-review brief and in issue #38 can be re-derived rather than
* trusted, and so they fail visibly when the build moves.
*
* THREE CHECKS, THREE DIFFERENT THINGS BEING VERIFIED. Keeping them apart is the
* whole point, because two of them are measured on opposite sides of the pipeline:
*
*   CHECK 1  verifies THE RAW DATA. Was a measurement taken at all, and is the
*            ticked dimension right? Measured on the RAW `weight' and `unit'.
*   CHECK 2  verifies THE DECIMAL-DRIFT CORRECTION. Where the published value is
*            not a plain unit conversion of the typed one, a judgement was applied.
*            Measured by joining raw to published.
*   CHECK 3  verifies THE HARMONIZATION CROSSWALK. Not here -- validate_folds.do
*            owns it, and its verdicts are in outputs/temp/fold_validation_*.csv.
*
* WHY CHECK 1 MUST NOT READ `corrected_unit'. The published dimension is the OUTPUT
* of A23's item-level verdicts and its case-majority resolution. Scoring the raw
* tick against it compares a decision with itself and can only agree. Measured on
* the published column, "liquids recorded in grams" is 25 rows; measured on the raw
* tick it is 273, because 240 gram-ticked liquor weighings were overruled to mL by
* the very decision being checked. That gap IS the finding.
*
* SOURCES
*   ${btemp}/prelim_nsu_data.dta    raw `weight' and `unit', pre-repair, keyed on id
*   ${btemp}/nsu_weighings_cpi.dta  the published weight and dimension, same id
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\photo_check_scope.do
********************************************************************************

version 19
clear all
set more off
set linesize 200

do "00_shared/00_globals.do"

********************************************************************************
* CHECK 1 -- the raw data. Raw columns only.
********************************************************************************
use "${btemp}/prelim_nsu_data.dta", clear
keep id pull_province pull_municipal_city pull_item pull_nsu_unit ///
     harmonized_nsu_unit item_nsu_hetero_type weight unit

* `unit' is a labelled numeric -- decode, never compare against the code
decode unit, gen(tick)
gen byte mass = inlist(unit,1,2)          // Kilograms or grams
gen byte vol  = (unit==3)                 // Litres

di as res _n "{hline 78}"
di as res "CHECK 1 -- THE RAW DATA"
di as res "Universe: prelim_nsu_data.dta, the typed values before any repair."
di as res "Unit of observation: one weighing."
di as res "{hline 78}"
count
di as txt "  rows = " r(N)
di as txt "  The instrument offered Kilograms / grams / Litres. NO millilitre option:"
tab tick, m

* ---- 1a: the same ITEM ticked both as a mass and as a volume -----------------
di as res _n "1a  ITEMS TICKED BOTH AS A MASS AND AS A VOLUME"
di as res "    The same item measured two different ways in the field. One reading"
di as res "    is likely wrong and only a photograph says which."
egen byte i_mass = max(mass), by(pull_item)
egen byte i_vol  = max(vol),  by(pull_item)
gen byte dual_item = i_mass & i_vol

preserve
	keep if dual_item
	contract pull_item tick, freq(n)
	di as txt %-44s "item" %18s "raw tick" %8s "n"
	forvalues i = 1/`=_N' {
		di as txt %-44s abbrev(pull_item[`i'],44) %18s tick[`i'] %8.0f n[`i']
	}
restore
count if dual_item
di as txt "    weighings of a dual-ticked ITEM ............. " r(N)

* The sharper grain: one CASE ticked both ways is a contradiction inside a single
* cell rather than a pattern across markets.
egen long cs = group(pull_province pull_municipal_city pull_item harmonized_nsu_unit)
egen byte c_mass = max(mass), by(cs)
egen byte c_vol  = max(vol),  by(cs)
gen byte dual_case = c_mass & c_vol
count if dual_case
di as txt "    weighings in a CASE ticked both ways ........ " r(N)
preserve
	keep if dual_case
	quietly count
	if r(N) > 0 {
		contract cs
		quietly count
	}
	di as txt "    such cases .................................. " r(N)
restore

* ---- 1b: dimension mis-ticks, both directions --------------------------------
di as res _n "1b  LIQUIDS TICKED AS A MASS, AND SOLIDS TICKED AS LITRES"
gen byte liquid = 0
foreach s in "liquor" "mineral" "drinks at restaurant" {
	replace liquid = 1 if strpos(lower(pull_item), "`s'")>0
}
* Ice cream is NOT classified. A23 gives it no item-level verdict because it is
* genuinely sold both ways, so neither tick can be assumed wrong. Reported below.
gen byte icecream = (strpos(lower(pull_item),"ice cream")>0)

preserve
	keep if liquid
	contract pull_item tick, freq(n)
	di as txt %-44s "liquid item" %18s "raw tick" %8s "n"
	forvalues i = 1/`=_N' {
		di as txt %-44s abbrev(pull_item[`i'],44) %18s tick[`i'] %8.0f n[`i']
	}
restore
count if liquid
di as txt "    liquid weighings ............................ " r(N)
count if liquid & mass
di as txt "    OF WHICH TICKED AS A MASS (kg or g) ........ " r(N)
di as txt "    A liquid ticked in grams may simply have been WEIGHED, which is the"
di as txt "    answer rather than a problem -- but nothing in the data distinguishes"
di as txt "    that from a dropdown slip, and A23 overrules these to mL regardless."

count if vol & !liquid & !icecream
di as txt "    solids ticked as Litres (the opposite slip) . " r(N)
preserve
	keep if vol & !liquid & !icecream
	contract pull_item, freq(n)
	gsort -n
	forvalues i = 1/`=_N' {
		di as txt "      " %-42s abbrev(pull_item[`i'],42) %6.0f n[`i']
	}
restore

di as res _n "    ICE CREAM -- reported, not classified (no item-level verdict):"
preserve
	keep if icecream
	contract tick, freq(n)
	forvalues i = 1/`=_N' {
		di as txt "      " %18s tick[`i'] %8.0f n[`i']
	}
restore

* ---- what Check 1 must look at ------------------------------------------------
di as res _n "CHECK 1 MUST-CHECK POPULATIONS (raw-data grounds)"
gen byte m_dualcase = dual_case
gen byte m_liqmass  = liquid & mass
gen byte m_solvol   = vol & !liquid & !icecream
foreach v in m_dualcase m_liqmass m_solvol {
	count if `v'
	di as txt "    `v' ... " r(N)
}
count if m_dualcase | m_liqmass | m_solvol
di as txt "    union .......... " r(N)
di as txt "    (the flat groups -- 'was it measured at all' -- are counted separately,"
di as txt "     by 90_diagnostics/photo_check_packaging.do)"

keep id weight unit
rename (weight unit) (raw_weight raw_unit)
tempfile raw
save `raw'

********************************************************************************
* CHECK 2 -- the decimal-drift correction. Raw joined to published.
********************************************************************************
use "${btemp}/nsu_weighings_cpi.dta", clear
keep id pull_item corrected_unit corrected_weight snap_rule
merge 1:1 id using `raw', keep(master match) nogen
decode corrected_unit, gen(dim)
decode raw_unit, gen(rawtick)

di as res _n "{hline 78}"
di as res "CHECK 2 -- THE DECIMAL-DRIFT CORRECTION"
di as res "Universe: all restated weighings. Unit of observation: one weighing."
di as res "{hline 78}"
quietly count
local N = r(N)
di as txt "  rows = `N'"

* A PLAIN CONVERSION applies no judgement: the tick is taken at face value and the
* number is only restated in canonical units. There is nothing in our step to
* verify on those rows. Everything else had the decimal moved, the tick overruled,
* the dimension changed, or a value set by hand -- and that is what a photograph tests.
gen byte trivial = 0
replace trivial = 1 if raw_unit==1 & dim=="g"  & reldif(corrected_weight, raw_weight*1000)<1e-6
replace trivial = 1 if raw_unit==2 & dim=="g"  & reldif(corrected_weight, raw_weight)     <1e-6
replace trivial = 1 if raw_unit==3 & dim=="mL" & reldif(corrected_weight, raw_weight*1000)<1e-6
gen byte nopub = missing(corrected_weight)
replace trivial = 0 if nopub

gen str8  natural = cond(raw_unit==3, "mL", "g")
gen byte  dimchg  = (dim != natural) & !nopub
gen double implied = cond(raw_unit==2, raw_weight, raw_weight*1000)
gen byte  magchg  = !nopub & reldif(corrected_weight, implied) > 1e-6

di as txt "  plain conversion (kg->g x1000, g->g x1, L->mL x1000): nothing to verify"
count if trivial
di as txt "    ............................................. " r(N) ///
	"  (" %5.1f (100*r(N)/`N') "%)"
count if !trivial & !nopub
di as txt "  JUDGEMENT APPLIED -- THE MUST-CHECK POPULATION  " r(N) ///
	"  (" %5.1f (100*r(N)/`N') "%)"
count if nopub
di as txt "  nothing published ............................. " r(N)

di as res _n "  WHAT THE JUDGEMENT DID"
count if !trivial & !nopub & magchg & !dimchg
di as txt "    magnitude only -- the decimal moved ......... " r(N)
count if !trivial & !nopub & dimchg & !magchg
di as txt "    dimension only -- the tick was overruled .... " r(N)
count if !trivial & !nopub & dimchg & magchg
di as txt "    both ........................................ " r(N)

di as res _n "  BY RAW TICK"
tab rawtick if !trivial & !nopub, m
di as res "  BY THE RULE THAT SET THE PUBLISHED VALUE"
tab snap_rule if !trivial & !nopub, m

di as res _n "  BY ITEM (top 12)"
preserve
	keep if !trivial & !nopub
	contract pull_item, freq(n)
	gsort -n
	di as txt %-46s "item" %8s "n"
	forvalues i = 1/`=min(_N,12)' {
		di as txt %-46s abbrev(pull_item[`i'],46) %8.0f n[`i']
	}
restore

di as res _n "{hline 78}"
di as res "Check 3 is not measured here. validate_folds.do owns the fold verdicts;"
di as res "read outputs/temp/fold_validation_A.csv and _C.csv, verdict `inconclusive'."
di as res "{hline 78}"
