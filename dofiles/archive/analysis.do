
** Do file to construct CF from cleaned Market Survey Data **
* Created by: Shine Yang 
* Date Created: 29th July, 2026

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
**# loading inflation data
********************************************************************************

import delimited "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\NSU Market Survey Launch\data\fp_cpi_byprov_byitem_psa_2023_26.csv", clear

rename geolocation province 
replace province = strupper(province)

// bysort pull_province commodity year: gen month_cnt = _N

rename commodity item_group

gen mdate = ym(year, month)
format mdate %tm 

drop date year month

save "${temp}\psa_cpi_fp", replace




********************************************************************************
**# Extract submission date from PSPS and MS 
********************************************************************************

* MS submission date: 
use "${data}", clear

keep submissiondate pull_province pull_item pull_nsu_unit

gen mdate = mofd(dofc(submissiondate))
format mdate %tm
drop submissiondate

// duplicates drop

sort pull_province pull_item pull_nsu_unit

replace pull_item = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(pull_item, "restaurant") > 0


rename pull_province province
rename pull_item cons_name
rename pull_nsu_unit unit_lbl
rename mdate mdate_ms

save "${temp}\ms_subdate_prov_item_nsu", replace


* PSPS submission date:
** group_by: prov mun cons_name unit_lbl 
use "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\08 Analysis & Data\14 Wave 1_Pub\Household survey\5_outputs\3_publication_data\2_consumption\2_consumption.dta", clear

// tab fd_cons_2aunit fd_cons_2aunit_lbl if !inrange(fd_cons_2aunit,1,27) & !mi(fd_cons_2aunit) // need to clean: 0.5 --> kg; 30 --> putos 

* municipality names:
merge m:1 municipal_code using "C:/Users//`c(username)'/Box/Philippines Panel/01 Panel/08 Analysis & Data/14 Wave 1_Pub/Household survey/3_input_data/municipal_mapping.dta", assert(3) nogen

replace cons_name = subinstr(cons_name, "café", "cafe", .)

keep province municipal_code pull_municipal_city cons_name *unit_lbl subdate hhid

gen mdate = mofd(subdate)
format mdate %tm
drop subdate


foreach var in fd_cons_2aunit_lbl fd_cons_3aunit_lbl fd_cons_4aunit_lbl{
	
replace `var' = "" if ///
	strpos(`var',"(Kg)") > 0 | ///
	strpos(`var',"(g)") > 0 | ///
	strpos(`var',"(L)") > 0 | ///
	strpos(`var',"(mL)") > 0 | ///
	strpos(`var',"ml") > 0 | ///
	strpos(`var', "kg") > 0 | ///
	strpos(`var', "kilo") > 0 | ///
	strpos(`var', "(25kls.)") > 0 | ///
	strpos(`var', "ml") > 0 | ///
	strpos(`var', "litres")	> 0	| ///
	strpos(`var', "liters")	> 0	// 51 obs
	
}

* prepped food actually have no unit in PSPS, but in MS we assigned "Pieces"
replace fd_cons_2aunit_lbl = "Pieces" if cons_name == "Drinks at restaurant, hotel, cafe, or kiosk"

drop if fd_cons_2aunit_lbl == "" & fd_cons_3aunit_lbl == "" & fd_cons_4aunit_lbl == ""


preserve 
keep fd_cons_2aunit_lbl province municipal_code pull_municipal_city cons_name mdate hhid
duplicates drop

rename fd_cons_2aunit_lbl unit_lbl

tempfile 2a 
save `2a'

restore 

preserve 
keep fd_cons_3aunit_lbl province municipal_code pull_municipal_city cons_name mdate hhid
duplicates drop

rename fd_cons_3aunit_lbl unit_lbl

tempfile 3a 
save `3a'

restore 


keep fd_cons_4aunit_lbl province municipal_code pull_municipal_city cons_name mdate hhid
duplicates drop

rename fd_cons_4aunit_lbl unit_lbl

append using `2a' 

append using `3a'

drop if unit_lbl == ""

br if cons_name == "Camote tops" & unit_lbl == "Bugkos" & pull_municipal_city == "LEMERY"

sort pull_municipal_city

br if cons_name == "Camote" & pull_municipal_city == "SIGMA"  // small N 



// * diagnostics: 
// bysort municipal_code cons_name unit_lbl: egen mn = min(mdate_psps)
// bysort municipal_code cons_name unit_lbl: egen mx = max(mdate_psps)
// gen span = mx - mn
// tab span

sort province cons_name unit_lbl mdate


save "${temp}\psps_subdate_prov_item_nsu", replace



********************************************************************************
**# loading cons_name to COICOP group crosswalk 
********************************************************************************

import delimited "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\NSU Market Survey Launch\data\cons_name_to_coicop_crosswalk.csv", clear varnames(1)

replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(cons_name, "restaurant") > 0

isid cons_name province

* NO CPI data for Iloilo ice cream, hence used parent category (sweets / confectionary)

save "${temp}\coicop_item_crosswalk", replace


********************************************************************************
**# merging CPI rates to price data 
********************************************************************************

use "${temp}\psps_subdate_prov_item_nsu", clear // hhid unique ID

merge m:1 province cons_name using "${temp}\coicop_item_crosswalk", assert(2 3) keep(1 3) nogen


merge m:1 province item_group mdate using "${temp}\psa_cpi_fp", assert(2 3) keep(3) nogen //_merge == 2: prov_item not present in PSPS (among NSU users)


**# HERE --> side quest to compare price list against raw MS data

** collapse to cell level to match price data:
collapse (mean) mean_cpi = cpi (median) med_cpi = cpi (sd) sd_cpi = cpi, ///
	by(province municipal_code pull_municipal_city cons_name unit_lbl)




* price points used in MS, obtained from PSPS

**# Price data may need to be cleaned first
	* NA municipal_code (non-missing municipal_city)

import delimited "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv", clear varnames(1) 

drop v1

destring price mn_* pp* pn* iqr , replace force

replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(cons_name, "restaurant") > 0

tab pull_m


** municipal_code has NAs - not uniquely identifying pull_municipal_city: occurred due to various merging operations 

** pre-cleaning merge keys :
foreach v in cons_name unit_lbl {
    replace `v' = ustrtrim(ustrlower(`v'))     // trim + lowercase
}

foreach v in cons_name unit_lbl pull_municipal_city {

    replace `v' = ustrto(`v', "ascii", 2) // rid of accents

}

	
** some of these do look like nonsensical units; pull list and compare against the list of units included in the cleaned NSU file

preserve
contract province pull_municipal_city cons_name unit_lbl, freq(freq_price)      // one row per case with count

tempfile price_nomatch 
save `price_nomatch'

restore


save "${temp}\ms_full_prices_from_Makayla", replace



use "${data}", clear // raw data, not cleaned


rename pull_province province 
rename pull_item cons_name 
rename pull_nsu_unit unit_lbl


replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(cons_name, "restaurant") > 0


** pre-cleaning merge keys :
foreach v in cons_name unit_lbl {
    replace `v' = ustrtrim(ustrlower(`v'))     // trim + lowercase
}

foreach v in cons_name unit_lbl pull_municipal_city {

    replace `v' = ustrto(`v', "ascii", 2) // rid of accents

}

br if cons_name == "beer"

unique province cons_name unit_lbl pull_municipal_city

// merge m:1 province cons_name unit_lbl pull_municipal_city using "${temp}\price_item_list"

/*

    Result                      Number of obs
    -----------------------------------------
    Not matched                           949
        from master                         0  (_merge==1)
        from using                        949  (_merge==2) // in price data but not in MS 
		** 100% of PSPS municipalities are covered - so should just be from units
		** in theory all cases in price data should be present in MS, except for:  
		** 1) item-nsu pairs deemed non-sensical during pilot: thrown out after price dataset created
		** or 2) empty cases (could not be found during MS)?

    Matched                            11,495  (_merge==3)
    -----------------------------------------


*/




contract province pull_municipal_city cons_name unit_lbl, freq(freq_ms)      


merge 1:1 province pull_municipal_city cons_name unit_lbl using `price_nomatch' // all no match 

gen source = ""
replace source = "Price Only" if _merge == 2 
replace source = "MS Only" if _merge == 1 
replace source = "MS & Price" if _merge == 3

drop _merge 

** raw data ver
save "${temp}\cases_in_price_not_in_MS", replace
export delimited using "${temp}\cases_in_price_not_in_MS.csv", replace




use "${temp}\cases_in_price_not_in_MS", clear 

rename cons_name item

tempfile price 
save `price'

** full case data (pre field)
use "C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\NSU Market Survey Launch\cases\nsu_cases_final.dta", clear

br if strpos(item, "restaurant") > 0 // only ever drinks, no food

replace item = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(item, "restaurant") > 0


** pre-cleaning merge keys :
foreach v in item unit_lbl {
    replace `v' = ustrtrim(ustrlower(`v'))     // trim + lowercase
}

foreach v in item unit_lbl pull_municipal_city {

    replace `v' = ustrto(`v', "ascii", 2) // rid of accents

}


keep item unit_lbl province pull_municipal_city 

duplicates list, table // after pre-processing there are 40 duplicate cases (prov-mun-item-nsu): likely due to string formatting

duplicates drop

merge 1:1 item unit_lbl province pull_municipal_city using `price'

//    Result                      Number of obs
//     -----------------------------------------
//     Not matched                             3
//         from master                         2  (_merge==1)
//			** case but not in price
//         from using                          1  (_merge==2)
// 			** price but not in case 
//
//     Matched                             2,949  (_merge==3)
//     -----------------------------------------


tab _merge source

/*

 Matching result from |        source
                merge | MS & Pr..  Price O.. |     Total
----------------------+----------------------+----------
       Using only (2) |         0          1 |         1 
          Matched (3) |     2,001        948 |     2,949 
----------------------+----------------------+----------
                Total |     2,001        949 |     2,950 
				
*/
* price only & matched: intended to be collected but empty cell 
* price only & using only: Aubrey decided that it would not be a case

br if _merge == 1 // "1-feb": to be rightly dropped 

br if _merge == 2 // pieces of "drinks at restaurant": dropped from case

br if _merge == 3 & source == "Price Only" // dropped after going to field

** i.e., almost all PSPS NSUs appear in final cases (Mar): case not really helpful 



keep if source == "Price Only"

drop if inlist(unit_lbl, "bilog", "binilog") // already know how to deal with these

keep province pull_municipal_city cons_name unit_lbl 

// tempfile 

use "${temp}\nsu_data", clear

list prov_mun nsu_item if pull_nsu_unit == "maisot nga tasa", noobs table


* ---- TEST: within province x municipal_city x item, are "bilog" and "binilog" ever BOTH present? (raw ${data}) ----
preserve
    use "${temp}\ms_full_prices_from_Makayla", clear
    gen _u = ustrlower(ustrtrim(unit_lbl))          // case/space-robust match
    keep if inlist(_u, "bilog", "binilog")
    egen _tag     = tag(province pull_municipal_city cons_name _u)   // one row per distinct variant in a cell
    bysort province pull_municipal_city cons_name: egen _nvar = total(_tag)
    egen _celltag = tag(province pull_municipal_city cons_name)
    count if _nvar > 1 & _celltag
    di as txt "province x city x item cells containing BOTH bilog & binilog: " as result r(N)
    list province pull_municipal_city cons_name if _nvar > 1 & _celltag, noobs table 
    assert _nvar == 1        // errors if any cell holds both variants; list above shows offenders
	

	br if _nvar != 1
	

	
restore

use "${data}", clear


foreach v in pull_nsu_unit {
    replace `v' = ustrtrim(ustrlower(`v'))     // trim + lowercase
}

foreach v in pull_nsu_unit pull_municipal_city {

    replace `v' = ustrto(`v', "ascii", 2) // rid of accents

}

br if pull_municipal_city == "DUEAS" 

br if strpos(pull_nsu_unit, "shredded cabbage") > 0

tab pull_item if pull_province == "AKLAN" & pull_municipal_city == "ALTAVAS"

 & pull_item == "Rice"

rename pull_item cons_name 
rename pull_nsu_unit unit_lbl
rename pull_province province 

br i


// preserve 

/*
keep if _merge == 2 // prov x mun x item x unit cases present in price list but not present in Market Survey data

unique province cons_name unit_lbl pull_municipal_city // unique 949 cases

keep province cons_name unit_lbl pull_municipal_city 

merge 1:m province cons_name unit_lbl pull_municipal_city using "${temp}\ms_full_prices_from_Makayla", keep(3) nogen

unique province cons_name unit_lbl pull_municipal_city // unique 949 cases 

drop uuid iqr low_variance municipal_code 

tab mn_item_unit_pairs price_type

tab mn_item_unit_pairs
*/

/*

use "${temp}\nsu_data", clear

rename pull_item cons_name 
rename pull_nsu_unit unit_lbl
rename pull_province province 


replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(cons_name, "restaurant") > 0


** pre-cleaning merge keys :
foreach v in cons_name unit_lbl {
    replace `v' = ustrtrim(ustrlower(`v'))     // trim + lowercase
}

foreach v in cons_name unit_lbl pull_municipal_city {

    replace `v' = ustrto(`v', "ascii", 2) // rid of accents

}



contract province pull_municipal_city cons_name unit_lbl, freq(freq_ms)      


merge 1:1 province pull_municipal_city cons_name unit_lbl using `price_nomatch' // all no match 

gen source = ""
replace source = "Price Only" if _merge == 2 
replace source = "MS Only" if _merge == 1 
replace source = "MS & Price" if _merge == 3

drop _merge 


** cleaned data ver
export delimited using "${temp}\cases_in_price_not_in_MS.csv", replace

** a lot of the missing from MS cases are due to e.g. diff spelling / capitalisation / trimming etc.
* now the Q is e.g., cabbage bilog vs cabbage Bilog - only removed one of the 2 nsu-item IFF in the same prov-mun 



save "${temp}\cases_in_price_not_in_MS", replace
export delimited "${temp}\cases_in_price_not_in_MS.csv", replace

*/



merge m:1 cons_name using "${temp}\coicop_item_crosswalk", assert(3) nogen


merge 





use "${data}", clear

keep if strpos(obs_type, "unique") > 0

br if pull_price == .

keep pull_municipal_city pull_item pull_nsu_unit pull_province pull_price 


br if pull_province == "ILOILO" & pull_item == "Fresh Fish" & pull_nsu_unit == "Bilog" & pull_municipal_city == "SAN ENRIQUE"

// province	cons_name	unit_lbl	municipal_code	pull_municipal_city	price_type	price	tag
// ILOILO	Fresh Fish	Bilog	NA	SAN ENRIQUE	unique_mun_price	150	0
//




use "${temp}\psps_subdate_prov_item_nsu", clear

merge 1:




merge m:

// gsort -municipal_code // where did the NA mun_code come from

** pull province & item to extract inflation rates, ignore prices for now


** outcome: inflation rate collapsed to prov-item level
* each prov is associated with PSPS month & MS month --> duration: calcs inflation rate


import delimited "${tables}\master_nsu_rename.csv", clear varnames(1)

tab cause_label

// preserve 

label var cons_name "trimmed & lower case pull_item"
label var pull_nsu_unit "Raw NSU Units from PSPS, trimmed & lower case"
label var cause_label "Deducted reason for case's absence in Market Survey"
label var in_ms_as "if harmonizable: diff spelling/translation of the NSU in prov-mun-item"
label var fallback_harmonized_nsu_unit "if empty: fallback case when translated nsu r available"
label var harmonized_nsu_unit "item-nsu level harmonization of NSU across spelling/translations"
notes harmonized_nsu_unit: only when weights (within item-size across municipality) do not differ significantly across translations/spellings of pull_nsu_unit values
label var cleaned_nsu_unit "ref only: pull_nsu_unit cleaned for spelling"


replace cause_label = "empty" if strpos(cause_label, "empty") > 0
replace cause_label = "nonsensical" if strpos(cause_label, "nonsensical") > 0 
replace cause_label = "harmonizable: pull_nsu_unit found in data under diff spelling/translation etc" if strpos(cause_label, "harmonizable") > 0 

tab harmonized_nsu_unit if cons_name == "loaf bread" & cause_label == ""


gen temp = 1 if cons_name == "loaf bread" & harmonized_nsu_unit == "medium packs" & (cause_label == "" | strpos(cause_label, "harmonizable") > 0)

br if temp == 1

bysort province pull_municipal_city: ereplace temp = min(temp)

tab temp,m

** manual filling in of fallback: 
replace fallback_harmonized_nsu_unit = "medium packs" if cause_label == "empty" & pull_nsu_unit == "tama-tama nga putos" & cons_name == "loaf bread"



br if cons_name == "camote tops" & pull_municipal_city == "LEMERY"

tab cause_label if fallback_harmonized_nsu_unit != "" // 92 cases, mainly translations w sig weight differences across pull_nsu_unit 

br if fallback_harmonized_nsu_unit == "" & cause_label == "empty"

// br if cons_name == "chicken" 
// br if cons_name == "chicken" & pull_nsu_unit == "bilog"
//
// keep if cons_name == "chicken" & pull_nsu_unit == "bilog"
//
// rename cons_name pull_item 
// rename province pull_province
//
// tempfile bilog_chicken 
// save `bilog_chicken'

// restore 

preserve 


// egen tag = tag(cons_name pull_nsu_unit)
//
// list province pull_municipal_city cons_name pull_nsu_unit if cause_label == "empty" & tag == 1, noobs table

br if pull_nsu_unit == "putos /supot"

br if cons_name == "camote" & cause_label == "empty"
br if cons_name == "camote" & pull_municipal_city == "SIGMA"

tab pull_nsu_unit if cons_name == "camote" & cause_label == ""


keep province pull_municipal_city cons_name pull_nsu_unit cause_label in_ms_as fallback_harmonized_nsu_unit
keep if cause_label != ""


save "${temp}\price_only_cases_from_master_rename", replace 

restore 


use "${temp}\psps_subdate_prov_item_nsu", clear

replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(cons_name, "restaurant") > 0


** pre-cleaning merge keys :
foreach v in cons_name unit_lbl {
    replace `v' = ustrtrim(ustrlower(`v'))     // trim + lowercase
}

foreach v in cons_name unit_lbl pull_municipal_city {

    replace `v' = ustrto(`v', "ascii", 2) // rid of accents

}

contract province pull_municipal_city cons_name unit_lbl, freq(psps_freq)

rename unit_lbl pull_nsu_unit

merge 1:1 province pull_municipal_city cons_name pull_nsu_unit using "${temp}\price_only_cases_from_master_rename"

/*
    Result                      Number of obs
    -----------------------------------------
    Not matched                         2,341
        from master                     2,336  (_merge==1)
		** PSPS and in MS: good ones
        from using                          5  (_merge==2) 
		** price data only

    Matched                               944  (_merge==3)
		** PSPS and not in MS but in Price 
    -----------------------------------------
*/

br if _merge == 2 // not sure how come? but small scale 

br if _merge == 3 & psps_freq >=3 & fallback_harmonized_nsu_unit == "" & cause_label == "empty" // cases with multiple obs in PSPS but no obs in MS
order pull_municipal_city, after(province)
gsort -psps_freq



list province pull_municipal_city cons_name pull_nsu_unit psps_freq if _merge == 3 & psps_freq >=3 & fallback_harmonized_nsu_unit == "" & cause_label == "empty", noobs table


br if pull_nsu_unit == "tama-tama nga putos"



use "${data}", clear

foreach v in pull_item pull_nsu_unit {
    replace `v' = ustrtrim(ustrlower(`v'))     // trim + lowercase
}

foreach v in pull_item pull_nsu_unit pull_municipal_city {

    replace `v' = ustrto(`v', "ascii", 2) // rid of accents

}

br if pull_municipal_city == "AJUY" & pull_item == "loaf bread"

br if pull_item == "pork"

br if pull_municipal_city == "SIGMA" 

order unit, after(weight)

merge m:1 pull_province pull_municipal_city pull_item using `bilog_chicken'

** among cases in MS with binilog data: how many of them also have bilog chicken?
tab _merge if pull_item == "chicken" & pull_nsu_unit == "binilog"

/*
   Matching result from |
                  merge |      Freq.     Percent        Cum.
------------------------+-----------------------------------
        Master only (1) |         64       72.73       72.73 // 12 unique prov-mun
            Matched (3) |         24       27.27      100.00 // 8 unique prov-mun
------------------------+-----------------------------------
                  Total |         88      100.00
				  
	** majority only has binilog no bilog (although bilog is observed in psps)
	** although from psps prices we understand that binilog should be interpreted as whole chicken too, empricially vendors interpret binilog as pieces (rather than whole chicken / bilog); this means that empirically we should not have substituted bilog with binilog 
	
*/

tab _merge if pull_item == "chicken" & strpos(pull_nsu_unit, "whole") > 0 |strpos(pull_nsu_unit, "Whole") > 0

unique pull_province pull_municipal_city if pull_item == "chicken" & strpos(pull_nsu_unit, "whole") > 0 |strpos(pull_nsu_unit, "Whole") > 0 & _merge == 3

/*

   Matching result from |
                  merge |      Freq.     Percent        Cum.
------------------------+-----------------------------------
        Master only (1) |        178       37.55       37.55 // 78 unique prov-mun
            Matched (3) |        296       62.45      100.00 // 78 unique prov-mun
------------------------+-----------------------------------
                  Total |        474      100.00
				  
	** half of prov-mun only has whole chicken and not bilog - in this case it's kind of fine bc bilog measures to whole chicken anyway 
	
*/




count if pull_item == "Chicken" & pull_nsu_unit == "Binilog" & strpos(weighing_approach, "Size") > 0 // 86

count if pull_item == "Chicken" & pull_nsu_unit == "Binilog" & strpos(weighing_approach, "Price") > 0 // 2 --> when price based, the price for binilog chicken is indicative that binilog is meant as the whole chicken in PSPS; however, when left to their own, vendors give pieces (not whole) of chicken when asked "binilog"


br if pull_item == "Chicken" & pull_nsu_unit == "Bilog" // regardless of size / price based, vendors understand "bilog" of chicken as whole chicken

count if pull_item == "Chicken" & pull_nsu_unit == "Bilog" & strpos(weighing_approach, "Size") > 0 // 181

count if pull_item == "Chicken" & pull_nsu_unit == "Bilog" & strpos(weighing_approach, "Price") > 0 // 53


sort pull_province obs_type weight pull_municipal_city
