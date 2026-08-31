********************************************************************************
* 26_psps_extract.do -- pull the PSPS household side of Outcome 2
*
* One row per (province x municipality x item x unit label x source), with the
* household unit price, from the PSPS Wave 1 consumption module. This is the file
* Outcome 2 joins the conversion-factor lookup onto.
*
* THIS FILE HAD NEVER RUN before it was repaired. Four things stopped it, all fixed
* here and recorded because each is a pattern worth not repeating:
*   1. it read 5_outputs\3_publication_data\...  -- the folder is 2_publication_data
*   2. it set no globals, so `save "${temp}\psps_cases"' wrote to a malformed path
*      whenever the file was run as its own batch process, which is the project's
*      convention
*   3. it called `br' twice. browse is interactive-only; under -e do it logs
*      "request ignored because of batch mode" and execution carries on, so the
*      two inspection points silently did nothing
*   4. the municipal_mapping merge dropped _merge without ever counting the
*      unmatched, so a municipality with no mapping row would carry a blank
*      pull_municipal_city into the `case' key and be undetectable afterwards
*
* INPUT   ${psps_cons}      PSPS Wave 1 consumption (item_type == 1 = food)
*         ${municipal_map}  municipal_code -> municipality name
* OUTPUT  ${btemp}\psps_cases.dta
*
* NOTE ON THE OUTPUT FOLDER. This writes to ${btemp} (the current build subtree),
* not ${temp} (which holds the pre-Aug11 build). The original line wrote to ${temp}
* and would have mixed a new output into the old build's folder.
*
* RUN, from the dofiles/ folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\26_psps_extract.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

global municipal_map "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\08 Analysis & Data\14 Wave 1_Pub\Household survey\3_input_data\municipal_mapping.dta"

* `missings' is a user-written command (ssc install missings). Fail with a useful
* message rather than an unexplained r(199).
capture which missings
if _rc {
	di as error "the `missings' package is not installed. Run: ssc install missings"
	exit 199
}


********************************************************************************
**# 1. Load the food consumption rows
********************************************************************************

use "${psps_cons}", clear
count
di as txt "consumption rows in: " r(N)

keep if item_type == 1
count
di as txt "food rows (item_type == 1): " r(N)

missings dropvars, force

drop nfd*
drop fd_cons_5a fd_cons_6a fd_cons_6b
drop ppi* item_type item *unit
drop fourp_status fo_id sfo_id fc_id subdate random_select nonrandom_select fd_cons_6c
drop brgy_code hhid count_res_members

gsort -fd_cons_4b


********************************************************************************
**# 2. Unit price per source slot
********************************************************************************
* The module records three acquisition routes in parallel slots: 2 = purchased,
* 3 = own production, 4 = gift. Each carries its own quantity (a) and expenditure
* (b), so the unit price is b/a within a slot.
*
* p_h for Outcome 2 comes from the PURCHASED slot -- own production and gifts carry
* an imputed value, not a price the household faced. The other two are kept so the
* coverage question ("how many NSU observations are there at all") can be answered,
* but they must not be treated as prices. See #5.

gen fd_cons_2_unit_price = fd_cons_2b / fd_cons_2a
gen fd_cons_3_unit_price = fd_cons_3b / fd_cons_3a
gen fd_cons_4_unit_price = fd_cons_4b / fd_cons_4a

drop fd_cons_2a fd_cons_2b fd_cons_3a fd_cons_3b fd_cons_4a fd_cons_4b


********************************************************************************
**# 3. Stack the three slots
********************************************************************************

tempfile purchased own_production gift

preserve
	keep if cons_purchased == 1
	drop cons_purchased cons_own_production cons_gift
	keep *2* municipal_code province cons_name
	rename *price unit_price
	rename *lbl unit_lbl
	gen source = "purchased"
	di as txt "purchased rows: " _N
	save `purchased'
restore

preserve
	keep if cons_own_production == 1
	drop cons_purchased cons_own_production cons_gift
	keep *3* municipal_code province cons_name
	rename *price unit_price
	rename *lbl unit_lbl
	gen source = "own_production"
	di as txt "own-production rows: " _N
	save `own_production'
restore

preserve
	keep if cons_gift == 1
	drop cons_purchased cons_own_production cons_gift
	keep *4* municipal_code province cons_name
	rename *price unit_price
	rename *lbl unit_lbl
	gen source = "gift"
	di as txt "gift rows: " _N
	save `gift'
restore

use `purchased', clear
append using `own_production'
append using `gift'

drop if unit_lbl == "" & unit_price == .
count
di as txt "stacked rows with a unit label or a price: " r(N)


********************************************************************************
**# 4. Attach the municipality name
********************************************************************************
* The mapping is what turns municipal_code into the name the crosswalk is keyed on,
* so an unmatched row cannot be joined to anything downstream -- and with _merge
* dropped it would look like an ordinary row with a blank municipality. Count it.

bysort province municipal_code cons_name unit_lbl: gen obs_per_case = _N
duplicates drop

merge m:1 municipal_code using "${municipal_map}", keep(1 3) gen(_m_map)

count if _m_map == 1
if r(N) > 0 {
	di as error "ERROR: " r(N) " row(s) have a municipal_code with no mapping entry"
	di as error "They would carry a blank municipality into the case key."
	tab municipal_code if _m_map == 1
	exit 459
}
drop _m_map pull_province

order pull_municipal_city, after(province)
order municipal_code, last


********************************************************************************
**# 5. Case keys and counts
********************************************************************************

bysort province municipal_code cons_name unit_lbl: gen unique_prices_per_case = _N
gsort -unique_prices_per_case

gen case = province + "_" + pull_municipal_city + "_" + cons_name + "_" + unit_lbl

egen byte tag_case = tag(case)
count if tag_case == 1
di as res "distinct PSPS cases: " r(N)
drop tag_case

egen byte tag = tag(province municipal_code cons_name unit_lbl)
bysort province municipal_code cons_name: egen unique_lbls_per_item_mun = total(tag)
drop tag

encode unit_lbl, gen(unit_lbl_n)
order obs_per_case unique_prices_per_case unique_lbls_per_item_mun, after(unit_price)


********************************************************************************
**# 6. Put the names in the crosswalk's vocabulary
********************************************************************************
* The join to master_nsu_rename is on normalized strings. Applying nsu_normalize
* here rather than at the join keeps ONE definition of the rule, and means the
* saved file is already in the vocabulary every other step speaks.
*
* This step is NEW. The original file renamed the columns and stopped, which would
* have joined raw-cased PSPS strings against normalized crosswalk keys and matched
* almost nothing.

rename cons_name pull_item
rename unit_lbl  pull_nsu_unit

nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
	mun(pull_municipal_city) province(province)

label var pull_item     "normalized item name, matches master_nsu_rename"
label var pull_nsu_unit "normalized raw NSU label, matches master_nsu_rename"
label var unit_price    "household unit value = expenditure / quantity, per source slot"
label var source        "purchased / own_production / gift -- only purchased is a faced price"

compress
save "${btemp}\psps_cases", replace

count
di as res _n "26_psps_extract complete: " r(N) " rows -> ${btemp}\psps_cases.dta"

tab source, m
