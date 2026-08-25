** Do file to clean NSU Market Survey Data **
* Created by: Shine Yang 
* Date Created: 15th July, 2026
* Date Last Edited:
* Cf_xns = conversion factor between NSU n and standard unit s for item x, i.e., how much is 1 n of x in terms of s
* e.g., 1 gantang = 500 g of rice (hypothetical) - cf_{rice}{gantang}{gram} = 500
* 
***********************************************

********************************************************************************
**# Setting Globals
********************************************************************************


global data "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\NSU Market Survey Launch\data\PSPS NSU Market Survey Launch.dta"

global dofiles "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\dofiles"

global output "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs"

global temp "${output}\temp"
cap noi mkdir "${temp}"

global graphs "${output}\graphs"
cap noi mkdir "${graphs}"

global tables "${output}\tables"
cap noi mkdir "${tables}"




********************************************************************************
**# standardizing NSU names 
********************************************************************************



/*
import excel  "${tables}\nsu_rename_crosswalk.xlsx", clear firstrow

* nsu_item level


preserve 

use "${data}", clear

keep pull_*

drop pull_price 

bysort pull_*: gen n_obs_nsu_by_mun = _N

duplicates drop

* nsu_item_prov_mun level

tempfile data 
save `data'

restore 


merge 1:m pull_item pull_nsu_unit using "`data'", assert(3) nogen

label var n_obs_NSU "N across vendor x market type x municipality"

order n_obs_nsu_by_mun, after(n_obs_NSU)

order pull*, first

order pull_nsu_unit, before(cleaned_nsu_unit)

isid pull_*

preserve 
use "${temp}\psps_cases", clear

keep province pull_municipal_city pull_item pull_nsu_unit obs_per_case
duplicates drop


rename obs_per_case n_obs_per_case_psps
rename province pull_province 

* nsu_item_prov_mun level

tempfile psps 
save `psps'

restore 

merge 1:1 pull_province pull_municipal_city pull_item pull_nsu_unit using `psps'

//     Result                      Number of obs
//     -----------------------------------------
//     Not matched                         3,839
//         from master                        69  (_merge==1)
//         from using                      3,770  (_merge==2)
//
//     Matched                             1,932  (_merge==3)
//     -----------------------------------------

*/





********************************************************************************
**# Summ stats from raw data
********************************************************************************


putexcel set "${tables}\summary_corrected_weight_by_cell.xlsx", sheet("raw data counts", replace) modify

* Stata quirk: when putexcel creates a brand-new sheet inside an existing multi-
* sheet workbook, its FIRST cell write is silently dropped (confirmed by testing
* in isolation) -- this throwaway write absorbs that loss so every real write below lands.
putexcel Z100 = "x"

use "${data}", clear

label define hetero 1 "conventional_nsu" 2 "small_size" 3 "medium_size" 4 "large_size" ///
	5 "mp25_price" 6 "mp50_price" 7 "mp75_price" 8 "municipality_median" ///
	9 "province_median" 10 "unique_mun_price6" 11 "unique_mun_price7", replace
	
encode obs_type, gen(item_nsu_hetero_type) label(hetero)
drop obs_type
rename item_nsu_hetero_type obs_type

local xlrow = 1

* ================================================================================
* Section 1: top-line unique counts (joint combinations, not marginal)
* ================================================================================
qui unique pull_item
local n_item = r(unique)
qui unique pull_nsu_unit
local n_nsu = r(unique)
qui unique pull_item pull_nsu_unit
local n_itemnsu = r(unique)
qui unique pull_province pull_municipal_city pull_item pull_nsu_unit
local n_uuid = r(unique)

putexcel A`xlrow' = "Section 1: Unique Counts", bold
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Unique Items"                                                                  B`xlrow' = `n_item'
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Unique NSU Units"                                                              B`xlrow' = `n_nsu'
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Unique Item x NSU pairs"                                                  B`xlrow' = `n_itemnsu'
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Unique province x municipality x item x NSU values"            B`xlrow' = `n_uuid'
local xlrow = `xlrow' + 2

* ================================================================================
* Section 2: uuid-groups with >=1 obs under each weighing_approach category
*            (+ how many have obs spanning MORE THAN ONE category)
* ================================================================================

use "${data}", clear

egen long uuidgrp = group(pull_province pull_municipal_city pull_item pull_nsu_unit)

tempfile wa_full
contract uuidgrp weighing_approach, freq(n_wa)
fillin uuidgrp weighing_approach
replace n_wa = 0 if _fillin==1
drop _fillin
gen byte has_wa = n_wa > 0
save `wa_full', replace

* -- per-category "at least 1 obs" counts --
collapse (sum) n_groups = has_wa, by(weighing_approach)

putexcel A`xlrow' = "Section 2: Number of province x municipality x item x NSU cases, by Weighing Approach", bold
local xlrow = `xlrow' + 1
qui count
local nrows = r(N)
forvalues i = 1/`nrows' {
    local lbl  = weighing_approach[`i']
    local cnt  = n_groups[`i']
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `cnt'
    local xlrow = `xlrow' + 1
}



* -- how many uuid-groups have obs in MORE THAN ONE weighing_approach category --
use `wa_full', clear
collapse (sum) n_cats_present = has_wa, by(uuidgrp)
qui count if n_cats_present > 1
local n_multi = r(N)
putexcel A`xlrow' = "Obs. in more than 1 weighing_approach category"  B`xlrow' = `n_multi'
local xlrow = `xlrow' + 2

* ================================================================================
* Section 3: uuid-groups with >=1 obs under each obs_type category
* ================================================================================
use "${data}", clear
egen long uuidgrp = group(pull_province pull_municipal_city pull_item pull_nsu_unit)

* re-encode obs_type here: "use ..., clear" wipes value labels along with the
* data, so the encode from the top of this section doesn't survive this reload
label define hetero 1 "conventional_nsu" 2 "small_size" 3 "medium_size" 4 "large_size" ///
	5 "mp25_price" 6 "mp50_price" 7 "mp75_price" 8 "municipality_median" ///
	9 "province_median" 10 "unique_mun_price6" 11 "unique_mun_price7", replace
encode obs_type, gen(item_nsu_hetero_type) label(hetero)
drop obs_type
rename item_nsu_hetero_type obs_type

tempfile ot_full
contract uuidgrp obs_type, freq(n_ot)
fillin uuidgrp obs_type
replace n_ot = 0 if _fillin==1
drop _fillin
gen byte has_ot = n_ot > 0
save `ot_full', replace

collapse (sum) n_groups = has_ot, by(obs_type)

putexcel A`xlrow' = "Section 3: Number of province x municipality x item x NSU cases, by obs_type", bold
local xlrow = `xlrow' + 1
qui count
local nrows = r(N)
forvalues i = 1/`nrows' {
    local code = obs_type[`i']
    local lbl : label (obs_type) `code'
    local cnt  = n_groups[`i']
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `cnt'
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 1

* ================================================================================
* Section 4: uuid-groups by # obs WITHIN each obs_type -- full range 0..max (no top bucket)
* ================================================================================
use `ot_full', clear

tab obs_type n_ot, matcell(freqM) matrow(rowM) matcol(colM)

putexcel A`xlrow' = "Section 4: Number of province x municipality x item x NSU cases, by number of observations within each obs_type", bold
local xlrow = `xlrow' + 1

local ncols = colsof(freqM)
local alphabet B C D E F G H I J K L M N O P Q R S T U V W X Y Z
local hdrrow = `xlrow'
forvalues j = 1/`ncols' {
    local colval : di %3.0f colM[1,`j']
    local colval = trim("`colval'")
    local colletter : word `j' of `alphabet'
    putexcel `colletter'`hdrrow' = "`colval'"
}
local xlrow = `xlrow' + 1

local nrows = rowsof(freqM)
forvalues i = 1/`nrows' {
    local code : di %2.0f rowM[`i',1]
    local lbl : label (obs_type) `code'
    putexcel A`xlrow' = "`lbl'"
    forvalues j = 1/`ncols' {
        local colletter : word `j' of `alphabet'
        putexcel `colletter'`xlrow' = (freqM[`i',`j'])
    }
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 1

* -- average number of observations per case, by obs_type -- EXCLUDING cases with 0 obs --
keep if n_ot > 0
collapse (mean) avg_n_ot = n_ot, by(obs_type)

putexcel A`xlrow' = "Average number of observations per province x municipality x item x NSU case, by obs_type (excl. 0-obs cases)", bold
local xlrow = `xlrow' + 1
qui count
local nrows = r(N)
forvalues i = 1/`nrows' {
    local code = obs_type[`i']
    local lbl : label (obs_type) `code'
    local avgval = avg_n_ot[`i']
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `avgval'
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 2

* ================================================================================
* Section 5: uuid-groups found in exactly 1 / 2 / 3 market_type(s)
* ================================================================================
use "${data}", clear
egen long uuidgrp = group(pull_province pull_municipal_city pull_item pull_nsu_unit)
decode market_type, gen(market_type_lbl)

contract uuidgrp market_type_lbl
egen byte n_cats_present = count(market_type_lbl), by(uuidgrp)
egen byte tag_grp = tag(uuidgrp)

putexcel A`xlrow' = "Section 5: Number of province x municipality x item x NSU cases, by number of distinct market_types present", bold
local xlrow = `xlrow' + 1

forvalues k = 1/3 {
    qui count if tag_grp==1 & n_cats_present==`k'
    local cnt = r(N)
    if `k'==1  local lbl "Found in 1 market_type"
    if `k'==2  local lbl "Found in 2 market_types"
    if `k'==3  local lbl "Found in all 3 market_types"
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `cnt'
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 1

* ================================================================================
* Section 6: unique province x municipality x item x NSU x obs_type values,
*            by count of unique vendor_id, split by market_type
* ================================================================================
use "${data}", clear
egen long uuidgrp = group(pull_province pull_municipal_city pull_item pull_nsu_unit)
decode market_type, gen(market_type_lbl)

egen byte tagv = tag(uuidgrp obs_type market_type_lbl vendor_id)
bysort uuidgrp obs_type market_type_lbl: egen n_vendor = total(tagv)
egen byte tag_cell = tag(uuidgrp obs_type market_type_lbl)

qui su n_vendor if tag_cell==1, meanonly
local max_vendor = r(max)

gen byte n_bucket = n_vendor
recode n_bucket (4/max = 4)
label define vbucketlbl 1 "1" 2 "2" 3 "3" 4 "3+", replace
label values n_bucket vbucketlbl

putexcel A`xlrow' = "Section 6: Number of unique province x municipality x item x NSU x obs_type values, by count of unique vendor_id, split by market_type", bold
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Note: max # unique vendor_id observed in any (case x obs_type x market_type) cell = `max_vendor'"
local xlrow = `xlrow' + 2

levelsof market_type_lbl, local(mtlevels)
foreach mt of local mtlevels {
    putexcel A`xlrow' = "Panel: `mt'", bold
    local xlrow = `xlrow' + 1
    putexcel A`xlrow' = "n unique vendor_id"  B`xlrow' = "n case x obs_type values"
    local xlrow = `xlrow' + 1

    forvalues b = 1/4 {
        qui count if tag_cell==1 & market_type_lbl=="`mt'" & n_bucket==`b'
        local cnt = r(N)
        local blabel : label (n_bucket) `b'
        putexcel A`xlrow' = "`blabel'"  B`xlrow' = `cnt'
        local xlrow = `xlrow' + 1
    }
    local xlrow = `xlrow' + 1
}

putexcel Z100 = ""   // clear the throwaway cell now that real writes have landed


********************************************************************************
**# Summ stats from cleaned data (nsu_data.dta) -- mirrors the raw data counts tab
********************************************************************************
* Depends on nsu_data.dta already being built by the full pipeline (this file +
* correct_unit_snap.do). Same 6 sections + average table as the raw-data
* version above, sourced from the cleaned dataset instead of "${data}".
*
* Key differences from the raw-data version:
*  - item_nsu_hetero_type is already a labeled numeric var here (no re-encode
*    needed -- unlike obs_type in the raw launch data, this label is saved
*    IN the .dta file, so it survives every "use ..., clear").
*  - weighing_approach is ALSO already a labeled numeric var here (unlike the
*    raw data's string version), so its label is decoded via label() lookup.
*  - market_type has no stored value label in nsu_data.dta. Its 3 codes'
*    frequencies (55.6%/16.6%/27.9%) closely match the raw data's labeled
*    Public Market/Talipapa/Roadside Vendors split (55.2%/16.6%/28.2%), so
*    the label below assumes the SAME 1/2/3 coding carried through cleaning
*    -- flagging this as an assumption, not a verified fact.

putexcel set "${tables}\summary_corrected_weight_by_cell.xlsx", sheet("cleaned data count", replace) modify
putexcel Z100 = "x"

use "${temp}\nsu_data", clear

local xlrow = 1

* ================================================================================
* Section 1: top-line unique counts (joint combinations, not marginal)
* ================================================================================
qui unique pull_item
local n_item = r(unique)
qui unique pull_nsu_unit
local n_nsu = r(unique)
qui unique pull_item pull_nsu_unit
local n_itemnsu = r(unique)
qui unique pull_province pull_municipal_city pull_item pull_nsu_unit
local n_uuid = r(unique)

putexcel A`xlrow' = "Section 1: Unique Counts", bold
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Unique Items"                                                                  B`xlrow' = `n_item'
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Unique NSU Units"                                                              B`xlrow' = `n_nsu'
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Unique Item x NSU pairs"                                                  B`xlrow' = `n_itemnsu'
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Unique province x municipality x item x NSU values"            B`xlrow' = `n_uuid'
local xlrow = `xlrow' + 2

* ================================================================================
* Section 2: uuid-groups with >=1 obs under each weighing_approach category
*            (+ how many have obs spanning MORE THAN ONE category)
* ================================================================================
use "${temp}\nsu_data", clear
egen long uuidgrp = group(pull_province pull_municipal_city pull_item pull_nsu_unit)

tempfile wa_full
contract uuidgrp weighing_approach, freq(n_wa)
fillin uuidgrp weighing_approach
replace n_wa = 0 if _fillin==1
drop _fillin
gen byte has_wa = n_wa > 0
save `wa_full', replace

collapse (sum) n_groups = has_wa, by(weighing_approach)

putexcel A`xlrow' = "Section 2: Number of province x municipality x item x NSU cases, by Weighing Approach", bold
local xlrow = `xlrow' + 1
qui count
local nrows = r(N)
forvalues i = 1/`nrows' {
    local code = weighing_approach[`i']
    local lbl : label (weighing_approach) `code'
    local cnt  = n_groups[`i']
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `cnt'
    local xlrow = `xlrow' + 1
}

use `wa_full', clear
collapse (sum) n_cats_present = has_wa, by(uuidgrp)
qui count if n_cats_present > 1
local n_multi = r(N)
putexcel A`xlrow' = "Obs. in more than 1 weighing_approach category"  B`xlrow' = `n_multi'
local xlrow = `xlrow' + 2

* ================================================================================
* Section 3: uuid-groups with >=1 obs under each item_nsu_hetero_type category
* ================================================================================
use "${temp}\nsu_data", clear
egen long uuidgrp = group(pull_province pull_municipal_city pull_item pull_nsu_unit)

tempfile ot_full
contract uuidgrp item_nsu_hetero_type, freq(n_ot)
fillin uuidgrp item_nsu_hetero_type
replace n_ot = 0 if _fillin==1
drop _fillin
gen byte has_ot = n_ot > 0
save `ot_full', replace

collapse (sum) n_groups = has_ot, by(item_nsu_hetero_type)

putexcel A`xlrow' = "Section 3: Number of province x municipality x item x NSU cases, by item_nsu_hetero_type", bold
local xlrow = `xlrow' + 1
qui count
local nrows = r(N)
forvalues i = 1/`nrows' {
    local code = item_nsu_hetero_type[`i']
    local lbl : label (item_nsu_hetero_type) `code'
    local cnt  = n_groups[`i']
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `cnt'
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 1

* ================================================================================
* Section 4: uuid-groups by # obs WITHIN each item_nsu_hetero_type -- full range 0..max
* ================================================================================
use `ot_full', clear

tab item_nsu_hetero_type n_ot, matcell(freqM) matrow(rowM) matcol(colM)

putexcel A`xlrow' = "Section 4: Number of province x municipality x item x NSU cases, by number of observations within each item_nsu_hetero_type", bold
local xlrow = `xlrow' + 1

local ncols = colsof(freqM)
local alphabet B C D E F G H I J K L M N O P Q R S T U V W X Y Z
local hdrrow = `xlrow'
forvalues j = 1/`ncols' {
    local colval : di %3.0f colM[1,`j']
    local colval = trim("`colval'")
    local colletter : word `j' of `alphabet'
    putexcel `colletter'`hdrrow' = "`colval'"
}
local xlrow = `xlrow' + 1

local nrows = rowsof(freqM)
forvalues i = 1/`nrows' {
    local code : di %2.0f rowM[`i',1]
    local lbl : label (item_nsu_hetero_type) `code'
    putexcel A`xlrow' = "`lbl'"
    forvalues j = 1/`ncols' {
        local colletter : word `j' of `alphabet'
        putexcel `colletter'`xlrow' = (freqM[`i',`j'])
    }
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 1

* -- average number of observations per case, by item_nsu_hetero_type -- EXCLUDING cases with 0 obs --
keep if n_ot > 0
collapse (mean) avg_n_ot = n_ot, by(item_nsu_hetero_type)

putexcel A`xlrow' = "Average number of observations per province x municipality x item x NSU case, by item_nsu_hetero_type (excl. 0-obs cases)", bold
local xlrow = `xlrow' + 1
qui count
local nrows = r(N)
forvalues i = 1/`nrows' {
    local code = item_nsu_hetero_type[`i']
    local lbl : label (item_nsu_hetero_type) `code'
    local avgval = avg_n_ot[`i']
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `avgval'
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 2

* ================================================================================
* Section 4b: SAME as Section 4, aggregated across municipalities
*             (grain = province x item x NSU). Obs counts here run much higher
*             than Section 4 (max 201 vs 9) since municipalities are pooled, so
*             bucketed into 0 / 1-4 / 5-9 / 10-14 / 15+ -- both because Stata's
*             two-way tabulate errors past a certain number of distinct column
*             values (confirmed: 88 distinct values fails, ~22 works), and
*             because a 200-column table wouldn't be readable anyway.
* ================================================================================
use "${temp}\nsu_data", clear
egen long provgrp = group(pull_province pull_item pull_nsu_unit)

contract provgrp item_nsu_hetero_type, freq(n_ot)
fillin provgrp item_nsu_hetero_type
replace n_ot = 0 if _fillin==1
drop _fillin

gen byte n_ot_bucket = .
replace n_ot_bucket = 0 if n_ot==0
replace n_ot_bucket = 1 if inrange(n_ot,1,4)
replace n_ot_bucket = 2 if inrange(n_ot,5,9)
replace n_ot_bucket = 3 if inrange(n_ot,10,14)
replace n_ot_bucket = 4 if n_ot>=15 & !missing(n_ot)
label define n_ot_bucket_lbl 0 "0" 1 "1-4" 2 "5-9" 3 "10-14" 4 "15+", replace
label values n_ot_bucket n_ot_bucket_lbl

tab item_nsu_hetero_type n_ot_bucket, matcell(freqM) matrow(rowM) matcol(colM)

putexcel A`xlrow' = "Section 4b: Number of province x item x NSU cases (aggregated across municipalities), by number of observations within each item_nsu_hetero_type", bold
local xlrow = `xlrow' + 1

local ncols = colsof(freqM)
local alphabet B C D E F
local hdrrow = `xlrow'
forvalues j = 1/`ncols' {
    local ccode : di %2.0f colM[1,`j']
    local colval : label (n_ot_bucket) `ccode'
    local colletter : word `j' of `alphabet'
    putexcel `colletter'`hdrrow' = "`colval'"
}
local xlrow = `xlrow' + 1

local nrows = rowsof(freqM)
forvalues i = 1/`nrows' {
    local code : di %2.0f rowM[`i',1]
    local lbl : label (item_nsu_hetero_type) `code'
    putexcel A`xlrow' = "`lbl'"
    forvalues j = 1/`ncols' {
        local colletter : word `j' of `alphabet'
        putexcel `colletter'`xlrow' = (freqM[`i',`j'])
    }
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 1

* -- average number of observations per case, by item_nsu_hetero_type -- EXCLUDING cases with 0 obs (uses UNCAPPED n_ot for a true average) --
keep if n_ot > 0
collapse (mean) avg_n_ot = n_ot, by(item_nsu_hetero_type)

putexcel A`xlrow' = "Average number of observations per province x item x NSU case (aggregated across municipalities), by item_nsu_hetero_type (excl. 0-obs cases)", bold
local xlrow = `xlrow' + 1
qui count
local nrows = r(N)
forvalues i = 1/`nrows' {
    local code = item_nsu_hetero_type[`i']
    local lbl : label (item_nsu_hetero_type) `code'
    local avgval = avg_n_ot[`i']
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `avgval'
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 2

* ================================================================================
* Section 5: uuid-groups found in exactly 1 / 2 / 3 market_type(s)
* ================================================================================
use "${temp}\nsu_data", clear
egen long uuidgrp = group(pull_province pull_municipal_city pull_item pull_nsu_unit)

contract uuidgrp market_type
egen byte n_cats_present = count(market_type), by(uuidgrp)
egen byte tag_grp = tag(uuidgrp)

putexcel A`xlrow' = "Section 5: Number of province x municipality x item x NSU cases, by number of distinct market_types present", bold
local xlrow = `xlrow' + 1

forvalues k = 1/3 {
    qui count if tag_grp==1 & n_cats_present==`k'
    local cnt = r(N)
    if `k'==1  local lbl "Found in 1 market_type"
    if `k'==2  local lbl "Found in 2 market_types"
    if `k'==3  local lbl "Found in all 3 market_types"
    putexcel A`xlrow' = "`lbl'"  B`xlrow' = `cnt'
    local xlrow = `xlrow' + 1
}
local xlrow = `xlrow' + 1

* ================================================================================
* Section 6: unique province x municipality x item x NSU x item_nsu_hetero_type
*            values, by count of unique vendor_id, split by market_type
* NOTE: market_type has no stored value label in nsu_data.dta. The label below
* ASSUMES the same 1/2/3 coding as the raw launch data (Public Market/Talipapa/
* Roadside Vendors) based on closely matching frequency proportions -- this is
* an assumption, not a verified fact.
* ================================================================================
use "${temp}\nsu_data", clear
label define market_type_assumed 1 "Public Market" 2 "Talipapa" 3 "Roadside Vendors", replace
label values market_type market_type_assumed
egen long uuidgrp = group(pull_province pull_municipal_city pull_item pull_nsu_unit)
decode market_type, gen(market_type_lbl)

egen byte tagv = tag(uuidgrp item_nsu_hetero_type market_type_lbl vendor_id)
bysort uuidgrp item_nsu_hetero_type market_type_lbl: egen n_vendor = total(tagv)
egen byte tag_cell = tag(uuidgrp item_nsu_hetero_type market_type_lbl)

qui su n_vendor if tag_cell==1, meanonly
local max_vendor = r(max)

gen byte n_bucket = n_vendor
recode n_bucket (4/max = 4)
label define vbucketlbl 1 "1" 2 "2" 3 "3" 4 "3+", replace
label values n_bucket vbucketlbl

putexcel A`xlrow' = "Section 6: Number of unique province x municipality x item x NSU x item_nsu_hetero_type values, by count of unique vendor_id, split by market_type", bold
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Note: market_type labels ASSUMED to match raw data coding (not a stored value label in nsu_data.dta)"
local xlrow = `xlrow' + 1
putexcel A`xlrow' = "Note: max # unique vendor_id observed in any (case x item_nsu_hetero_type x market_type) cell = `max_vendor'"
local xlrow = `xlrow' + 2

levelsof market_type_lbl, local(mtlevels)
foreach mt of local mtlevels {
    putexcel A`xlrow' = "Panel: `mt'", bold
    local xlrow = `xlrow' + 1
    putexcel A`xlrow' = "n unique vendor_id"  B`xlrow' = "n case x item_nsu_hetero_type values"
    local xlrow = `xlrow' + 1

    forvalues b = 1/4 {
        qui count if tag_cell==1 & market_type_lbl=="`mt'" & n_bucket==`b'
        local cnt = r(N)
        local blabel : label (n_bucket) `b'
        putexcel A`xlrow' = "`blabel'"  B`xlrow' = `cnt'
        local xlrow = `xlrow' + 1
    }
    local xlrow = `xlrow' + 1
}

putexcel Z100 = ""



**# cleaning raw data



**# item_nsu level (ie. across municipality)


import excel  "${tables}\nsu_rename_crosswalk.xlsx", clear firstrow

* nsu_item level

preserve 

use "${data}", clear

keep pull_*

drop pull_price pull_province pull_municipal_city

bysort pull_*: gen n_obs_item_nsu = _N

duplicates drop

* nsu_item level

tempfile data 
save `data'

 restore 

merge 1:m pull_item pull_nsu_unit using "`data'", assert(3) nogen

label var n_obs_item_nsu "N across vendor x market type x municipality"

drop n_obs_NSU


order pull*, first

order pull_nsu_unit, before(cleaned_nsu_unit)

isid pull_*

preserve 

use "${temp}\psps_cases", clear

// br if pull_nsu_unit == "500" // 1 obs


keep pull_item pull_nsu_unit 

bysort pull*: gen n_obs_item_nsu_psps = _N

duplicates drop

* nsu_item level

tempfile psps 
save `psps'

restore 

merge 1:1 pull_item pull_nsu_unit using `psps'

//     Result                      Number of obs
//     -----------------------------------------
//     Not matched                           191
//         from master                         3  (_merge==1)
//         from using                        188  (_merge==2) - incl standard units which are not present in MS 
//
//     Matched                               170  (_merge==3)
//     -----------------------------------------

* PSPS only is expected (checked that not all NSUs in PSPS are present in MS)
* what are the MS only?

br *nsu* pull_item if _merge == 1 // spelling / padding issues, rare instances

// pull_nsu_unit	cleaned_nsu_unit	n_obs_item_nsu_psps	pull_item
// Whole	Whole (chicken)		Chicken
// Pieces	Pieces		Drinks at restaurant, hotel, cafÃ©, or kiosk
// 1.3 galÄºon	1.3 gallon		Ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)

drop if _merge == 1 // Market Survey only

br if _merge ==2  // PSPS only

tab n_obs_item_nsu_psps if _merge == 2

gsort -n_obs_item_nsu_psps 


**# basically we we manually impute a standard weight (as per the package) for these items whose NSU are in fact standard

* preparing for MS: excl standard units; but these are still in crosswalk so we can continue using them for editing PSPS NSUs 


drop if ///
	strpos(pull_nsu_unit,"(Kg)") > 0 | ///
	strpos(pull_nsu_unit,"(g)") > 0 | ///
	strpos(pull_nsu_unit,"(L)") > 0 | ///
	strpos(pull_nsu_unit,"(mL)") > 0 | ///
	strpos(pull_nsu_unit,"ml") > 0 | ///
	strpos(pull_nsu_unit, "kg") > 0 | ///
	strpos(pull_nsu_unit, "kilo") > 0 | ///
	strpos(pull_nsu_unit, "(25kls.)") > 0 | ///
	strpos(cleaned_nsu_unit, "ml") > 0 | ///
	strpos(pull_nsu_unit, "litres")	> 0	| ///
	strpos(pull_nsu_unit, "liters")	> 0	// 51 obs

		
* some we just have to clean in PSPS 
keep if _merge == 3
drop _merge 

tab cleaned_nsu_unit,m


rename n_obs_item_nsu n_obs_item_nsu_ms

bysort pull_item cleaned_nsu_unit: egen n_obs_item_nsu_ms_NEW = total(n_obs_item_nsu_ms)

bysort pull_item cleaned_nsu_unit: egen n_obs_item_nsu_psps_NEW = total(n_obs_item_nsu_psps)

br if n_obs_item_nsu_ms != n_obs_item_nsu_ms_NEW

unique pull_item pull_nsu_unit if n_obs_item_nsu_ms != n_obs_item_nsu_ms_NEW // 81 pairs 
unique pull_item pull_nsu_unit  // out of 170 total



preserve 

keep if note != ""

* some of these may involve just .c the PSPS entries - some free text NSUs do not have clear interpretations

save "${temp}\flagged_NSU", replace // NSU unsure of 



restore

save "${temp}\psps_ms_nsu_item_rename", replace // log incl counts


drop n_obs* status

save "${temp}\ms_nsu_item_rename", replace // nsus only 


********************************************************************************
**# deal with comments 
********************************************************************************

use "${data}", clear

label define hetero 1 "conventional_nsu" 2 "small_size" 3 "medium_size" 4 "large_size" ///
	5 "mp25_price" 6 "mp50_price" 7 "mp75_price" 8 "municipality_median" ///
	9 "province_median" 10 "unique_mun_price6" 11 "unique_mun_price7", replace
	
encode obs_type, gen(item_nsu_hetero_type) label(hetero)
	

tempfile data
save `data'

import excel "${tables}\add_comments_crosswalk.xlsx", clear firstrow


label define hetero 1 "conventional_nsu" 2 "small_size" 3 "medium_size" 4 "large_size" ///
	5 "mp25_price" 6 "mp50_price" 7 "mp75_price" 8 "municipality_median" ///
	9 "province_median" 10 "unique_mun_price6" 11 "unique_mun_price7", replace

encode item_nsu_hetero_type, gen(item_nsu_hetero_type_d) label(hetero)
drop item_nsu_hetero_type
rename item_nsu_hetero_type_d item_nsu_hetero_type

merge 1:1 pull_province pull_municipal_city pull_item pull_nsu_unit weighing_approach market_type vendor_id item_nsu_hetero_type using "`data'", nogen

drop is_uncertain 

drop add_comments


br if notes != ""

** dropping errors + ones that are hard to interpret
drop if notes == "To drop (enumerator re-entered 225 weight for the 187.5 price mark)"


********************************************************************************
**#  merge rename xlsx with raw data to clean up nsu units
********************************************************************************

merge m:1 pull_item pull_nsu_unit using "${temp}\ms_nsu_item_rename", keep(3) nogen // aware that there are ~190 cases of no merges: these are the singletons that we decided to discard 

br if notes != ""

* some carrots / cabbages are actually measuring weight of mixed bags
replace cleaned_nsu_unit = "Putos (mix vegetable)" if strpos(notes, "halo halo") > 0
replace notes = "replaced NSU from putos to putos (mix vegetable) based on comments" if strpos(notes, "halo halo") > 0

rename notes cleaning_notes
rename cleaned_comments fo_comments_cleaned


********************************************************************************
**# cleaning 
********************************************************************************
rename weighing_approach wa
encode wa, gen(weighing_approach)
order weighing_approach, after(wa)
drop wa

//
// label define hetero 1 "conventional_nsu" 2 "small_size" 3 "medium_size" 4 "large_size" ///
// 	5 "mp25_price" 6 "mp50_price" 7 "mp75_price" 8 "municipality_median" ///
// 	9 "province_median" 10 "unique_mun_price6" 11 "unique_mun_price7", replace
//	
//	
// drop item_nsu_hetero_type 
// encode obs_type, gen(item_nsu_hetero_type) label(hetero)
	

* obs_type = the price point / size the std unit is measured at (to account for non-linearity in conversion factors)
order item_nsu_hetero_type, after(obs_type)
drop obs_type
drop consent_agree
drop consent_reject_reas
drop key
drop observation_number // inconsistent with obs_seq & not according to data correction

rename note nsu_name_notes 

order unit, after(weight)
order cleaned_nsu_unit, after(pull_nsu_unit)
order item_nsu_hetero_type weight unit, after(pull_price)
order fo_comments_cleaned nsu_name_notes cleaning_notes, last
order actual_price approx_price, after(pull_price)
order market_day, before(market_name)


* enumerators sometimes enter 0 weight when they don' t observe the item at the specified price / size (5 obs)
replace weight = .c if weight == 0

* drop pull_price fields for size based items
tab pull_price if weighing_approach == 3,m // errors (sized based items with a pull-price), ~900 obs 
replace pull_price = . if weighing_approach == 3 


cap noi assert inlist(weighing_approach,1,3) if pull_price == . // 3 obs, dropped below (price based item-nsu, but no pull-price recorded)

* drop the Tigbauan Fresh Fish Bilog obs that do not have the stated price (seems like a SCTO Glitch)
drop if pull_price == . & uuid == "Fresh Fish_Bilog_TIGBAUAN" 


br if fo_comments_cleaned != ""


* gantang vs ganta (noted)
br if pull_nsu_unit == "ganta"




** pre-processing to match strings with price data (also pre-processed): 
replace pull_item = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(pull_item, "restaurant") > 0

** pre-cleaning merge keys - align with price data:
foreach v in  pull_nsu_unit pull_item {
    replace `v' = ustrtrim(ustrlower(`v'))     // trim + lowercase
}

foreach v in pull_nsu_unit pull_item pull_municipal_city {

    replace `v' = ustrto(`v', "ascii", 2) // rid of accents

}




**# Generating new identifiers to replace uuid / caseid which reflects more accurately the data structure 
gen prov_mun = pull_province + "_" + pull_municipal_city

gen nsu_item = pull_item + "_" + cleaned_nsu_unit 

gen prov_mun_nsu_item = prov_mun + "_" + nsu_item

order prov_mun nsu_item prov_mun_nsu_item, first

label var nsu_item "Pull_item x Cleaned_NSU_Unit"
label var prov_mun_nsu_item "Prov x Mun x Pull_item x Cleaned_NSU_Unit"



// tostring market_type, gen(market_type_str)
// gen nsu_item_market_type = nsu_item + "_" + market_type_str
//


********************************************************************************
**# Data Structure
********************************************************************************

* checking 
egen tag = tag(weighing_approach pull_item pull_nsu_unit pull_municipal_city pull_province)

bysort pull_item pull_nsu_unit pull_municipal_city pull_province: egen sum_wa = total(tag) // never a municipality that uses both weighing approaches

tab sum_wa,m
assert sum_wa == 1

drop tag sum_wa

* based on new NSUs
egen tag = tag(weighing_approach pull_item cleaned_nsu_unit pull_municipal_city pull_province)

bysort pull_item cleaned_nsu_unit pull_municipal_city pull_province: egen sum_wa = total(tag) // never a municipality that uses both weighing approaches (still holds true under cleaned_NSUs)

tab sum_wa,m
assert sum_wa == 1

drop tag sum_wa



count

* uuid = pull_item + pull_nsu_unit + pull_municipal_city

* mun_market_typ = pull_municipal_city + market_type (public/roadside / talipapa)

// isid uuid mun_market_typ obs_seq item_nsu_hetero_type
//
// isid caseid mun_market_typ obs_seq item_nsu_hetero_type 
//
// sort pull_province pull_municipal_city pull_item caseid mun_market_typ obs_seq 


** ignore original caseid / uuid: use newly generated groups
drop caseid uuid

drop mun_market_typ // no longer necessary after we depart from the original NSUs

drop obs_seq // no longer necessary after we depart from the original NSUs


** new identifiers to work with cleaned_nsu_unit
isid prov_mun_nsu_item market_type vendor_id item_nsu_hetero_type 

gen id = _n

label var id "Unique identifier for each weighing instance"

sort pull_province pull_municipal_city pull_item cleaned_nsu_unit market_type item_nsu_hetero_type 

br

save "${temp}\prelim_nsu_data", replace


********************************************************************************
**# Correct order-of-magnitude unit-entry errors
********************************************************************************

do "${dofiles}\correct_unit_snap.do"

use "${temp}\prelim_nsu_data", clear


merge 1:1 id using "${temp}\standard_weight_unit_correction", assert(3) nogen


order correct*, after(unit)
rename correct_* corrected_*


** propagate missings
replace corrected_weight = .c if weight == .c 
replace corrected_unit = .c if weight == .c


tempfile data
save `data'

* mixup between ml & g 
import excel "${tables}\mixed_dimension_items.xlsx", firstrow clear

gen diagnostics = ""

replace diagnostics = "g" if inlist(pull_item,"Chicken","Crackers, Cookies, Buiscuits, Chips/Curls","Loaf Bread","Preserved or Processed Meat (Tocino, Tapa, Longaniza, etc)")

replace diagnostics = "mL" if inlist(pull_item, "Liquor (e.g, whisky, coconut wine)","Mineral or spring water, all drinking water sold in containers")



keep pull_item diagnostics

merge 1:m pull_item using `data', assert(2 3) nogen 


* manual correction - rescale weights

replace corrected_unit = 1 if diagnostics == "g" & corrected_unit != 1 & !mi(corrected_unit)
replace corrected_unit = 2 if diagnostics == "mL" & corrected_unit != 2 & !mi(corrected_unit)



* some of these are due to incorrect DP in original weight 
replace corrected_weight = weight * (1000^2)  if pull_item == "Liquor (e.g, whisky, coconut wine)" & pull_province == "ILOILO" & corrected_unit == 2 & corrected_weight == 1 


replace corrected_weight = weight * (1000^2) if pull_province == "ILOILO" & nsu_item == "Chicken_Whole (chicken)" & item_nsu_hetero_type == 2  & corrected_unit == 1 & corrected_weight == 1 

replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.001 L)" if pull_item == "Ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)" & corrected_unit == 2 & inrange(corrected_weight,1,2) // unsure 
replace corrected_weight = weight * (1000^2) if pull_item == "Ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)" & corrected_unit == 2 & inrange(corrected_weight,1,2) // unsure 


replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.001x L)" if pull_item == "Preserved or Processed Meat (Tocino, Tapa, Longaniza, etc)" & corrected_unit == 1 & inrange(corrected_weight,1,2) // unsure 
replace corrected_weight = weight * (1000^2) if pull_item == "Preserved or Processed Meat (Tocino, Tapa, Longaniza, etc)" & corrected_unit == 1 & inrange(corrected_weight,1,2) // unsure 


replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.01 L)" if inlist(cleaned_nsu_unit,"Refilled", "Container") & corrected_weight == 10 
replace corrected_weight = 1000 if inlist(cleaned_nsu_unit,"Refilled", "Container") & corrected_weight == 10 


** drop clearly erroneous entries & genuinely unsure instances 
replace cleaning_notes = "Genuinely unsure about how to interpret original weight-unit values (0.007 L)" if inlist(id, 4242)
replace corrected_weight = .c if inlist(id, 4242)
replace corrected_unit = .c if inlist(id, 4242)

replace cleaning_notes = "Genuinely unsure about how to interpret original weight-unit values  (5 g per cup)" if inlist(cleaned_nsu_unit,"Cup") & pull_item == "Prawns, Lobster, shrimp" & weight == 5 & unit == 2
replace corrected_weight = .c if inlist(cleaned_nsu_unit,"Cup") & pull_item == "Prawns, Lobster, shrimp" & weight == 5 & unit == 2
replace corrected_unit = .c if inlist(cleaned_nsu_unit,"Cup") & pull_item == "Prawns, Lobster, shrimp" & weight == 5 & unit == 2


drop weight unit diagnostics


save "${temp}\nsu_data", replace 


/*

********************************************************************************
**# Correct for outliers 
********************************************************************************
use "${temp}\nsu_data", replace 

keep id prov_mun nsu_item prov_mun_nsu_item pull* cleaned_nsu_unit weighing_approach market_type vendor_id item_nsu_hetero_type corrected_weight corrected_unit // trimmed ver for easy manipulation


** attempt diff methods of outlier detection due to thin sample size




** then produce summ stats for each method



********************************************************************************
**# Summ Stats 
********************************************************************************
use "${temp}\nsu_data", replace 


    collapse (first) pull_province (first) pull_municipal_city ///
			 (first) pull_item (first) cleaned_nsu_unit ///
			 (mean)   mean_weight   = corrected_weight ///
             (median) median_weight = corrected_weight ///
             (sd)     sd_weight     = corrected_weight ///
             (min)    min_weight    = corrected_weight ///
             (max)    max_weight    = corrected_weight ///
             (count)  n_weight      = corrected_weight ///
             , by(prov_mun_nsu_item weighing_approach item_nsu_hetero_type corrected_unit)

			 			 

forvalues i = 1/3{
	
preserve 
keep if weighing_approach == `i'

save "${temp}\prov_mun_nsu_item_hetero_wa`i'", replace
restore 

}


* size based: 
use "${temp}\prov_mun_nsu_item_hetero_wa3", clear

drop weighing_approach


* ---- flag each row against its PREDECESSOR (so the last row is checked too) --
bysort pull_item cleaned_nsu_unit pull_province pull_municipal_city corrected_unit (item_nsu_hetero_type): ///
    gen byte mean_monotonic = mean_weight > mean_weight[_n-1] if _n > 1
    // mono_ok==1 : this row's mean_weight increased vs. the previous row
    // mono_ok==0 : violation -- did not increase vs. the previous row
    // missing    : first row in the group (nothing before it to compare)

	
unique prov_mun_nsu_item if mean_monotonic == 0  // 93 out of 1478

unique prov_mun_nsu_item if mean_monotonic != . // 812 cells with multiple hetero levels 


* ---- flag every group that contains at least one violation -----------------
bysort pull_item cleaned_nsu_unit pull_province pull_municipal_city corrected_unit: ///
    egen byte flag_mean_cell = max(mean_monotonic==0)

br if flag_mean_cell == 1
	
	

* ---- flag each row against its PREDECESSOR (so the last row is checked too) --
bysort pull_item cleaned_nsu_unit pull_province pull_municipal_city corrected_unit (item_nsu_hetero_type): ///
    gen byte median_monotonic = median_weight > median_weight[_n-1] if _n > 1
    // mono_ok==1 : this row's mean_weight increased vs. the previous row
    // mono_ok==0 : violation -- did not increase vs. the previous row
    // missing    : first row in the group (nothing before it to compare)

	
unique prov_mun_nsu_item if median_monotonic == 0  // 89 out of 1478



* ---- flag every group that contains at least one violation -----------------
bysort pull_item cleaned_nsu_unit pull_province pull_municipal_city corrected_unit: ///
    egen byte flag_median_cell = max(median_monotonic==0)

br if flag_median_cell == 1


br if flag_median_cell != flag_mean_cell

unique prov_mun_nsu_item if flag_median_cell != flag_mean_cell // 29 cells

	
keep if flag_median_cell == 1

keep item_nsu_hetero_type prov_mun_nsu_item flag_median_cell corrected_unit


merge 1:m prov_mun_nsu_item item_nsu_hetero_type corrected_unit using "${temp}\nsu_data", assert(2 3) nogen
	
	
	
br if flag_median_cell == 1	
	

* ---- inspect the offending groups before asserting --------------------------
list pull_item cleaned_nsu_unit pull_province pull_municipal_city sizes mean_weight mono_ok ///
    if group_violation==1, sepby(pull_item cleaned_nsu_unit pull_province pull_municipal_city) noobs

* ---- hard check: halts here (r(9)) if any violation remains -----------------
assert mono_ok==1 if !missing(mono_ok)



** check for monotonicity of SML / price labels:










* ============================================================
* Size separation vs pooled tertile cutoffs — box + tertile lines
* Example: Chicken_Bilog (change the two locals to reuse)
* ============================================================
local item  "Chicken"
local unit  "Bilog"

preserve

    * --- keep the one item-NSU, size-based rows only ---
    decode item_nsu_hetero_type, gen(hetero_str)
    keep if pull_item == "`item'" & cleaned_nsu_unit == "`unit'"
    keep if inlist(hetero_str, "small_size", "medium_size", "large_size")

    * --- ordered S < M < L size variable (robust to numeric codes) ---
    gen byte size_ord = .
    replace size_ord = 1 if hetero_str == "small_size"
    replace size_ord = 2 if hetero_str == "medium_size"
    replace size_ord = 3 if hetero_str == "large_size"
    label define sz 1 "Small" 2 "Medium" 3 "Large", replace
    label values size_ord sz

    * --- pooled tertile cutoffs across ALL sizes for this item-NSU ---
    _pctile corrected_weight, percentiles(33.33 66.67)
    local c1 = r(r1)
    local c2 = r(r2)

    * --- box plot with the two cutoffs as horizontal lines ---
    graph box corrected_weight, over(size_ord) ///
        yline(`c1' `c2', lpattern(dash) lcolor(red)) ///
        ytitle("Corrected weight") ///
        title("`item'_`unit': weight by size vs pooled tertile cutoffs") ///
        note("Dashed red = pooled 33rd/67th pctiles of weight (all sizes)." ///
             "A box straddling a line = observations that pooled-tertile cutting would misclassify.")

    graph export "${graphs}/sizecheck_`item'_`unit'.png", replace width(2000)

restore   


tab pull_nsu_unit if nsu_item == "Chicken_Bilog" & corrected_weight <= 200

br  if nsu_item == "Chicken_Bilog" & corrected_weight <= 200
   
   
 * ssc install vioplot, replace   // one-time
vioplot corrected_weight, over(size_ord) ///
    yline(`c1' `c2', lpattern(dash) lcolor(red)) ///
    ytitle("Corrected weight") ///
    title("`item'_`unit': weight density by size vs pooled tertiles")


/*

* at different levels: 

* groups in decreasing levels of granularity
local groups `""prov_mun_nsu_item item_nsu_hetero_type" "pull_province nsu_item item_nsu_hetero_type" "prov_mun_nsu_item" "pull_province nsu_item""'

local n: word count `groups'
di "`n'"

local i = 1 
gen group = .
foreach group of local groups{
di "`i' `group'"
replace group = `i' if group == . 

bysort `group' corrected_unit: gen N_`i' = _N

bysort `group'  corrected_unit: egen iqr_`i' = iqr(corrected_weight)
bysort `group'  corrected_unit: egen q1_`i' = pctile(corrected_weight), p(25)
bysort `group'  corrected_unit: egen q3_`i' = pctile(corrected_weight), p(75)

gen l_t_`i' = q1_`i' - 1.5*iqr_`i'
gen h_t_`i' = q3_`i' + 1.5*iqr_`i'

bysort `group'  corrected_unit: egen min_`i' = min(corrected_weight)
bysort `group'  corrected_unit: egen p2_`i' = pctile(corrected_weight), p(2)

bysort `group'  corrected_unit: egen max_`i' = max(corrected_weight)
bysort `group'  corrected_unit: egen p98_`i' = pctile(corrected_weight), p(98)


* intermediate vars
drop iqr* q1* q3*

replace l_t_`i' = . if l_t_`i' < min_`i'
replace h_t_`i' = . if h_t_`i' > max_`i'

replace p2_`i' = . if p2_`i' == min_`i'
replace p98_`i' = . if p98_`i' == max_`i'



replace group = . if N_`i' < 6

local ++ i
}

tab group,m

forvalues i = 1/4{
	di "low"
	count if l_t_`i' != . 
	
	di "high"
	count if h_t_`i' != .
	
}

*/









* with obvious data entry errors - we should drop them?
* winsorization would mean assuming they are actually meant to be "Large" (hence replacing with P99) but just not THAT LARGE 
* this assumption may not hold - and can be quite substantive given small sample size wtihin mun-nsu-item-hetero groups? - would increase mean / even median (across vendors / market types) by a lot?






















** Duplicate municipalities across provinces
preserve
    keep pull_municipal_city pull_province
    duplicates drop
    duplicates list pull_municipal_city
	
br if pull_municipal_city == "PONTEVEDRA"
* Capiz & Negros

br if pull_municipal_city == "SAN ENRIQUE"
* Iloilo & Negros 
	
restore

//   +---------------------------+
//   | Group   Obs   pull_muni~y |
//   |---------------------------|
//   |     1    76    PONTEVEDRA |
//   |     1    77    PONTEVEDRA |
//   |     2    83   SAN ENRIQUE |
//   |     2    84   SAN ENRIQUE |
//   +---------------------------+

** adopt cleaned NSUs





preserve

** Panel table (panels = weighing_approach x province): obs counts by item x NSU x municipality x market type
decode weighing_approach, gen(wa_str)
decode market_type, gen(mkt_str)
contract wa_str pull_province pull_item pull_nsu_unit pull_municipal_city mkt_str, freq(n_obs)
rename (pull_item pull_nsu_unit pull_municipal_city mkt_str) (item nsu municipality market_type)
gen panel_key = wa_str + " - " + pull_province
sort panel_key item nsu municipality market_type

* one header row above each panel; data rows leave the panel column blank
gen seq = _n
bysort panel_key (seq): gen byte first = _n == 1
expand 2 if first, gen(hdr)
gsort seq -hdr
gen panel = "Panel: " + panel_key if hdr
foreach v of varlist item nsu municipality market_type {
    replace `v' = "" if hdr
}
replace n_obs = . if hdr
drop seq first hdr wa_str pull_province panel_key

order panel item nsu municipality market_type n_obs
export excel panel item nsu municipality market_type n_obs using ///
    "${tables}\prov_mun_by_nsu_item_cnt.xlsx", sheet("cnt_by_weighing_approach", replace) firstrow(variables)



restore 



** Duplicate uuid across caseid  --> as we are redefining uuid, we can also ignore caseid 
preserve
    keep caseid uuid

    duplicates drop
    duplicates list uuid
	
// Cabbage_Bilog_PANITAN 
// N11112597
// N11111195

// br if uuid == "Liquor (e.g, whisky, coconut wine)_Lipid / Lapad_IVISAN"
// caseid
// N11113442
// N11112399

restore

br if inlist(caseid, "N11112597","N11111195","N11113442","N11112399")

br if uuid == "Cabbage_Bilog_PANITAN" & inlist(caseid, "N11112597","N11111195")

sort market_type obs_seq


//   +------------------------------------------------------------------------+
//   | Group    Obs                                                      uuid |
//   |------------------------------------------------------------------------|
//   |     1   1395                                     Cabbage_Bilog_PANITAN |
//   |     1   1400                                     Cabbage_Bilog_PANITAN |
//   |     2    842   Liquor (e.g, whisky, coconut wine)_Lipid / Lapad_IVISAN |
//   |     2    860   Liquor (e.g, whisky, coconut wine)_Lipid / Lapad_IVISAN |
//   +------------------------------------------------------------------------+



//
// bysort pull_province uuid market_type obs_type: gen n_weight_per_type = _N
//
// tab n_weight_per_type
//
// unique uuid if inrange(n_weight_per_type,4,5)



********************************************************************************
**# prelim summ stats
********************************************************************************




unique vendor_id // 7857 unique vendors

egen u_vendor = tag(vendor_id)

// graph bar (sum) u_vendor, over(market_type) blabel(bar) ///
// 	ytitle("Number of Unique Vendors Visited, by market type")
	
egen u_nsu_item_market_type = tag(nsu_item_market_type prov_mun)

// graph hbar (sum) u_nsu_item_market_type if pull_province == "AKLAN", over(pull_municipal_city) 

	
preserve 	
putexcel set "${tables}\prov_mun_by_nsu_item_cnt.xlsx", replace sheet("obs_by_prov_mun_by_nsu_item") 

table (prov_mun) (nsu_item), stat(frequency) stat(percent,across(prov_mun))

putexcel A4 = collect

restore

** All unique pull_item x pull_nsu_unit combinations (with obs count per pair)
preserve
    contract pull_item pull_nsu_unit, freq(n_obs)
	* if an item-nsu pair has few obs, it essentially means any PSPS respondent who uses that nsu for that item the std_u amount for her would be subject to a lot of noise
	
    gsort -n_obs
    export excel using "${tables}\prov_mun_by_nsu_item_cnt.xlsx", ///
        sheet("item_nsu_pairs", replace) firstrow(variables)
restore




egen tag_vendor_by_market_type = tag(vendor_id market_type)
* distinct vendor_id x market type groups
bysort market_type: egen tot_vendor_wi_market_typ = total(tag_vendor_by_market_type)

tab tot_vendor_wi_market_typ market_type,m

// tot_vendor |  market_type: Please select the
// _wi_market |        type of the market
//       _typ | Public Ma   Talipapa  Roadside  |     Total
// -----------+---------------------------------+----------
//       1327 |         0      1,913          0 |     1,913 
//       2511 |         0          0      3,239 |     3,239 
//       4019 |     6,343          0          0 |     6,343 
// -----------+---------------------------------+----------
//      Total |     6,343      1,913      3,239 |    11,495 




egen tag_vendor_by_case = tag(vendor_id market_type prov_mun nsu_item)




tab weighing_approach, gen(d_weigh_)

graph bar (sum) d_weigh_*, over(nsu_item) 


putexcel set "${tables}\prov_mun_by_nsu_item_cnt.xlsx", modify sheet("by_weighing_approach", replace)

table(nsu_item)  (weighing_approach), stat(frequency)

putexcel A4 = collect


** Check: each nsu_item without any conventional_nsu obs (weighing_approach==1)
** must have >=1 obs in BOTH price-quantity based (==2) and size-based (==3)
preserve
    gen byte wa1 = weighing_approach == 1
    gen byte wa2 = weighing_approach == 2
    gen byte wa3 = weighing_approach == 3
    collapse (max) wa1 wa2 wa3, by(nsu_item)

    gen byte violation = wa1 == 0 & (wa2 == 0 | wa3 == 0)
    count if violation
    list nsu_item wa1 wa2 wa3 if violation, abbrev(20) noobs

    cap noi assert violation == 0
restore



**# Summ stats of data errors

use "${temp}\nsu_data", clear

egen tag = tag(pull_province nsu_item weighing_approach)
bysort pull_province nsu_item: egen cnt_wa = sum(tag)

tab cnt_wa

tab nsu_item if cnt_wa != 1

unique prov_mun_nsu_item if cnt_wa != 1



* ---- new tab: rows=province, cols=# distinct weighing_approach, cell=count of nsu_item ----
egen byte tag_pi = tag(pull_province nsu_item)

preserve
    keep if tag_pi == 1
    keep pull_province nsu_item cnt_wa

    contract pull_province cnt_wa, freq(n_nsu_item)

    qui su cnt_wa
    local max_wa = r(max)

    reshape wide n_nsu_item, i(pull_province) j(cnt_wa)

    local wa_vars ""
    forvalues w = 1/`max_wa' {
        capture confirm variable n_nsu_item`w'
        if _rc {
            gen long n_nsu_item`w' = 0
        }
        else {
            replace n_nsu_item`w' = 0 if missing(n_nsu_item`w')
        }
        rename n_nsu_item`w' wa_`w'
        local wa_vars "`wa_vars' wa_`w'"
    }

    order pull_province `wa_vars'
	
	rename wa_1 one_weighing_approach 
	rename wa_2 two_weighing_approach 
	rename wa_3 three_weighing_approach 

    export excel using "${tables}\summary_corrected_weight_by_cell.xlsx", ///
        sheet("nsu_item_wa_count_by_prov") sheetreplace firstrow(variables)
restore


use "${temp}\prelim_nsu_data", clear


egen tag = tag(prov_mun pull_item pull_nsu_unit cleaned_nsu_unit)
bysort prov_mun pull_item cleaned_nsu_unit: egen cnt_pull_nsu_unit = total(tag)

tab cnt_pull_nsu_unit // multiple original NSU unit under 1 cleaned nsu unit


// br if cnt_pull_nsu_unit == 2 & prov_mun_nsu_item == "AKLAN_BURUANGA_Crackers, Cookies, Buiscuits, Chips/Curls_Pack"

sort prov_mun_nsu_item item_nsu_hetero_type

br prov_mun_nsu_item item_nsu_hetero_type pull_price if cnt_pull_nsu_unit > 1 & weighing_approach == 2

keep if cnt_pull_nsu_unit > 1 

tab prov_mun_nsu_item item_nsu_hetero_type if weighing_approach == 2





import excel "${tables}\summary_corrected_weight_by_cell.xlsx", sheet("cleaned nsu mean weights") firstrow clear

keep if level == "Province"

gsort -n_weight -sd_weight

preserve 

keep if level == "Province"

foreach var in pull_province nsu_item item_nsu_hetero_type{
	
	encode `var', gen(`var'_n)
	
	drop `var'
	
	rename `var'_n `var'

}

sort pull_province nsu_item item_nsu_hetero_type

* fan median_weight into one var per hetero type, so each becomes its own connected line
separate median_weight, by(item_nsu_hetero_type) gen(mw)

twoway connected mw* pull_province if inrange(nsu_item, 1,6), sort ///
    by(nsu_item,  legend(off) note("") ///
	title(,size(2.2))) ///
    xlabel(1 (1) 5, valuelabel angle(45) labsize(vsmall)) xtitle("")

restore 



preserve 

keep if p_size_inversion <= 0.05 | p_price_inversion <= 0.05

keep pull_province pull_municipal_city nsu_item corrected_unit

tempfile names 
save `names'

restore

import excel "${tables}\summary_corrected_weight_by_cell.xlsx", sheet("cleaned nsu mean weights") firstrow clear

merge m:1 pull_province pull_municipal_city nsu_item corrected_unit using `names', assert(1 3) gen(size_inversion)

br if size_inversion == 3
sort pull_province pull_municipal_city nsu_item corrected_unit item_nsu_hetero_type

*/
