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

**# Generating new identifiers to replace uuid / caseid which reflects more accurately the data structure 
gen prov_mun = pull_province + "_" + pull_municipal_city

gen nsu_item = pull_item + "_" + pull_nsu_unit

gen prov_mun_nsu_item = prov_mun + "_" + nsu_item

tostring market_type, gen(market_type_str)
gen nsu_item_market_type = nsu_item + "_" + market_type_str


br if inlist(pull_nsu_unit, "Slice", "Sliced")

br if inlist(pull_nsu_unit, "Cone", "Cone of an ice cream")
sort pull_municipal_city




* convert all weights to standard unit (g --> kilo)
tab unit,m

tab pull_item if unit == 3

br if pull_item == "Chicken" & unit == 3 // ???


br if prov_mun_nsu_item == "ANTIQUE_HAMTIC_Ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)_Bilog" 

tab weighing_approach if nsu_item == "Chicken_Pieces or units",m 
* both price and size 



** ignore original caseid / uuid: use newly generated groups
drop caseid uuid



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


