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

global graphs "${output}\graphs"
cap noi mkdir "${graphs}"

global tables "${output}\tables"
cap noi mkdir "${tables}"


use "${data}", clear

********************************************************************************
**# cleaning 
********************************************************************************
rename weighing_approach wa
encode wa, gen(weighing_approach)
order weighing_approach, after(wa)
drop wa

* obs_type = the price point / size the std unit is measured at (to account for non-linearity in conversion factors)
encode obs_type, gen(item_nsu_hetero_type) // heterogeneity within item-nsu pair, by price/size
order item_nsu_hetero_type, after(obs_type)
drop obs_type
drop consent_agree
drop consent_reject_reas
drop key
drop observation_number // problematic


********************************************************************************
**# Data Structure
********************************************************************************

count

* uuid = pull_item + pull_nsu_unit + pull_municipal_city

* mun_market_typ = pull_municipal_city + market_type (public/roadside / talipapa)

isid uuid mun_market_typ obs_seq item_nsu_hetero_type

isid caseid mun_market_typ obs_seq item_nsu_hetero_type

sort pull_province pull_municipal_city pull_item caseid mun_market_typ obs_seq 


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


** Generating new identifiers to replace uuid / caseid which reflects more accurately the data structure 
gen prov_mun = pull_province + "_" + pull_municipal_city

gen nsu_item = pull_item + "_" + pull_nsu_unit

gen prov_mun_nsu_item = prov_mun + "_" + nsu_item



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


drop caseid uuid 

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

graph bar (sum) u_vendor, over(market_type) blabel(bar) // 
	ytitle("Number of Unique Vendors Visited, by market type")
	
preserve 	
contract prov_mun nsu_item, freq(n)
export excel prov_mun nsu_item n using "${tables}\prov_mun_by_nsu_item_cnt.xlsx", replace firstrow(variables)

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
