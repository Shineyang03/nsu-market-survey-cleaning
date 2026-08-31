********************************************************************************
* 00b_price_ms_cases.do -- which cases exist in the price file, the MS, or both
*
* Produces cases_in_price_not_in_MS.csv: one row per
* (province x municipality x item x raw unit label), with how many times the case
* appears on the market-survey side (freq_ms), on the price side (freq_price), and
* which side(s) it came from (source).
*
* WHY THIS FILE EXISTS. The CSV was an INPUT to 01_build_crosswalk.py with no
* producer in the repo -- a frozen artifact of the archived analysis.do, which
* nothing could re-run. Issue #33. The construction below is ported from
* archive/analysis.do (price side lines 221-252, MS side lines 260-324), reduced to
* only what the CSV needs.
*
* WHAT WAS LEFT OUT of the ported block, and why it does not affect the output:
*   - `destring price mn_* pp* pn* iqr' -- touches none of the four key variables
*     nor the frequency count.
*   - the `br' / `unique' inspection lines -- interactive, no data effect.
*   - the commented-out m:1 merge against price_item_list -- never ran.
*
* THIS READS THE RAW MARKET SURVEY, NOT THE CLEANED CHAIN. That is deliberate and
* is what lets the step sit before 01_build_crosswalk.py: the crosswalk cannot
* depend on an output of the cleaning the crosswalk itself feeds. Do not "improve"
* this by pointing it at nsu_data_master.dta -- that reintroduces the circularity
* issue #33 was opened about.
*
* NORMALIZATION IS THE ARCHIVED RULE, DELIBERATELY NOT nsu_normalize. The join
* below is price-side against MS-side, both normalized the SAME way here, and the
* frozen CSV this must reproduce was built with this rule. Note province is NOT
* ascii-folded on either side -- consistent between the two sides, so the join is
* unaffected. Changing any of this changes the crosswalk's input; see #33 and #18.
*
* INPUT   ${pricedata}   NSU_prices_from_Makayla.csv
*         ${data}        PSPS NSU Market Survey Launch.dta   (RAW)
* OUTPUT  ${temp}\cases_in_price_not_in_MS.csv
*         ${temp}\cases_in_price_not_in_MS.dta
*
* RUN, from the dofiles/ folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\00b_price_ms_cases.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

confirm file "${pricedata}"
confirm file "${data}"


********************************************************************************
**# 1. Price side -- one row per case, with its price-row count
********************************************************************************

import delimited "${pricedata}", clear varnames(1)
cap drop v1

replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(cons_name, "restaurant") > 0

foreach v in cons_name unit_lbl {
	replace `v' = ustrtrim(ustrlower(`v'))
}
foreach v in cons_name unit_lbl pull_municipal_city {
	replace `v' = ustrto(`v', "ascii", 2)
}

contract province pull_municipal_city cons_name unit_lbl, freq(freq_price)
count
di as txt "price-side cases: " r(N)

tempfile price_cases
save `price_cases'


********************************************************************************
**# 2. MS side -- one row per case, with its weighing count
********************************************************************************

use "${data}", clear

rename pull_province    province
rename pull_item        cons_name
rename pull_nsu_unit    unit_lbl

replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(cons_name, "restaurant") > 0

foreach v in cons_name unit_lbl {
	replace `v' = ustrtrim(ustrlower(`v'))
}
foreach v in cons_name unit_lbl pull_municipal_city {
	replace `v' = ustrto(`v', "ascii", 2)
}

contract province pull_municipal_city cons_name unit_lbl, freq(freq_ms)
count
di as txt "MS-side cases: " r(N)


********************************************************************************
**# 3. Which side is each case on
********************************************************************************

merge 1:1 province pull_municipal_city cons_name unit_lbl using `price_cases', gen(_m_side)

gen str12 source = ""
replace  source = "MS Only"    if _m_side == 1
replace  source = "Price Only" if _m_side == 2
replace  source = "MS & Price" if _m_side == 3

* Every row must land in exactly one bucket -- a blank source would silently
* propagate into the crosswalk build as an unclassified case.
assert inlist(source, "MS Only", "Price Only", "MS & Price")

tab source, m
drop _m_side

label var freq_ms    "market-survey rows for this case (missing = case absent from MS)"
label var freq_price "price-file rows for this case (missing = case absent from price file)"
label var source     "MS Only / Price Only / MS & Price"

* Deterministic row order: the four key variables uniquely identify a row, so no
* ties are left for the sort seed to break. The archived file exported in whatever
* order `merge' left behind.
sort province pull_municipal_city cons_name unit_lbl

compress
save "${temp}\cases_in_price_not_in_MS", replace
export delimited using "${temp}\cases_in_price_not_in_MS.csv", replace

count
di as res _n "00b_price_ms_cases complete: " r(N) " cases -> ${temp}\cases_in_price_not_in_MS.csv"
