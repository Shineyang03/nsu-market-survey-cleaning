
* extract a list of municipality x item x unit (by purchase method) for food items from PSPS consumption module


use "C:\Users\uzj5150\Box\Philippines Panel\01 Panel\08 Analysis & Data\14 Wave 1_Pub\Household survey\5_outputs\3_publication_data\2_consumption\2_consumption.dta", clear

keep if item_type == 1

missings dropvars, force

drop nfd*

drop fd_cons_5a fd_cons_6a fd_cons_6b

drop ppi* item_type item *unit

drop fourp_status fo_id sfo_id fc_id subdate random_select nonrandom_select fd_cons_6c

drop brgy_code hhid count_res_members

gsort -fd_cons_4b

gen fd_cons_2_unit_price = fd_cons_2b / fd_cons_2a

gen fd_cons_3_unit_price = fd_cons_3b / fd_cons_3a

gen fd_cons_4_unit_price = fd_cons_4b / fd_cons_4a

drop fd_cons_2a fd_cons_2b fd_cons_3a fd_cons_3b fd_cons_4a fd_cons_4b



preserve 

keep if cons_purchased == 1

drop cons_purchased cons_own_production cons_gift

keep *2* municipal_code province cons_name

rename *price unit_price 
rename *lbl unit_lbl 

gen source = "purchased"

tempfile purchased 
save `purchased'

restore 

preserve 

keep if cons_own_production == 1

drop cons_purchased cons_own_production cons_gift

keep *3* municipal_code province cons_name

rename *price unit_price 
rename *lbl unit_lbl 

gen source = "own_production"

br if unit_lbl == "Whole Chicken"



tempfile own_production
save `own_production'

restore 


preserve 

keep if cons_gift == 1

drop cons_purchased cons_own_production cons_gift

keep *4* municipal_code province cons_name

rename *price unit_price 
rename *lbl unit_lbl 

gen source = "gift"


tempfile gift 
save `gift'

restore 


use `purchased', clear

append using `own_production'

append using `gift'


drop if unit_lbl == "" & unit_price == .


bysort province municipal_code cons_name unit_lbl: gen obs_per_case = _N


duplicates drop


merge m:1 municipal_code using "C:\Users\uzj5150\Box\Philippines Panel\01 Panel\08 Analysis & Data\14 Wave 1_Pub\Household survey\3_input_data\municipal_mapping.dta", keep(1 3) 

drop _merge pull_province 

order pull_municipal_city, after(province)

order municipal_code, last

bysort province municipal_code cons_name unit_lbl: gen unique_prices_per_case = _N

gsort -unique_prices_per_case

gen case = province + "_" + pull_municipal_city + "_" + cons_name + "_" + unit_lbl

unique case // 5358 cases


egen tag = tag(province municipal_code cons_name unit_lbl)
bysort province municipal_code cons_name: egen unique_lbls_per_item_mun = total(tag)


encode unit_lbl, gen(unit_lbl_n)

drop tag 

order obs_per_case unique_prices_per_case unique_lbls_per_item_mun, after(unit_price)



* common names with NSU market survey 

rename cons_name pull_item 
rename unit_lbl pull_nsu_unit


save "${temp}\psps_cases", replace


br 
tab unit_lbl_n,m

contract unit_lbl_n

gsort _freq
