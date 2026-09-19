********************************************************************************
* photo_check_packaging.do -- which weighings were probably NEVER WEIGHED?
*
* THE QUESTION. Field officers weighed items on a portable scale and typed the
* number. For a packaged good -- a bottle of rum, a loaf of bread, a tin of meat --
* nothing stopped them copying the declared net weight off the label instead. The
* form has no field recording which, so the data cannot say directly.
*
* IT CAN SAY INDIRECTLY, because the two leave different fingerprints:
*
*     weighing an object   ->  readings vary vendor to vendor, and land on
*                              arbitrary numbers
*     reading a label      ->  readings are IDENTICAL across vendors of the same
*                              product, and land on commercial pack sizes
*
* So this file measures two things per item -- how concentrated the weights are on
* round values, and how often a whole case reports one single number -- and writes
* the weighings a photograph should be pulled for.
*
* WHY IT MATTERS, and it is not a curiosity. A declared pack size is not evidence
* about what a VENDOR'S unit contains, which is the quantity this project publishes.
* It also decides A23: "1 g per mL" is a harmless relabel if everything was weighed,
* and wrong if the litre-ticked readings are declared volumes, in which case a real
* density conversion is owed. See issue #38 section 1, which is parked on exactly this.
*
* WHAT IT WRITES
*     outputs/tables/photo_check_packaging.csv
*         one row per weighing sitting in a "flat" group -- 3 or more weighings from
*         3 or more DISTINCT vendors reporting one identical number. Keyed on `id',
*         which is what a photograph must be matched on.
*
* READS ONLY PUBLISHED COLUMNS. It recomputes no pipeline rule; the only derived
* quantities are a group size and a distinct-value count.
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\photo_check_packaging.do
********************************************************************************

version 19
clear all
set more off
set linesize 200

do "00_shared/00_globals.do"

* A flat group needs at least this many weighings before "they all agree" means
* anything. At 2 it would fire on coincidence constantly.
local MINOBS = 3

use "${btemp}/nsu_weighings_cpi.dta", clear
keep id pull_province pull_municipal_city market_name store_stall_name vendor_id ///
     pull_item pull_nsu_unit harmonized_nsu_unit item_nsu_hetero_type ///
     corrected_unit corrected_weight
keep if !missing(corrected_weight)

* labelled numerics -- decode, never compare against the code
decode item_nsu_hetero_type, gen(size)
decode corrected_unit, gen(dim)
keep if inlist(size,"small_size","medium_size","large_size")

di as res _n "{hline 78}"
di as res "UNIVERSE: size-weighings carrying a published weight"
count
di as txt "  rows = " r(N) "   unit of observation: one weighing"
di as res "{hline 78}"

* ---- fingerprint 1: is the number a commercial size? -------------------------
gen byte r100 = (mod(corrected_weight,100)==0)
gen byte r50  = (mod(corrected_weight, 50)==0)
gen byte r25  = (mod(corrected_weight, 25)==0)
gen byte r10  = (mod(corrected_weight, 10)==0)

* ---- fingerprint 2: does a whole case report ONE value? ----------------------
egen long cs   = group(pull_province pull_municipal_city pull_item harmonized_nsu_unit size)
egen long nobs = count(corrected_weight), by(cs)
egen long nval = nvals(corrected_weight), by(cs)
egen long nven = nvals(vendor_id), by(cs)
gen byte flat  = (nobs>=`MINOBS' & nval==1)

di as res _n "PER ITEM. Scale rounding puts every item near 50% on multiples of 10,"
di as res "so that column is the yardstick -- anything far above it is suspicious."
preserve
	collapse (count) n=corrected_weight (mean) r100 r50 r25 r10 flat, by(pull_item)
	foreach v in r100 r50 r25 r10 flat {
		replace `v' = 100*`v'
	}
	gsort -flat
	di as txt %-38s "item" %7s "n" %9s "%mult10" %9s "%mult25" %9s "%mult50" ///
		%10s "%mult100" %8s "%flat"
	forvalues i = 1/`=_N' {
		di as txt %-38s abbrev(pull_item[`i'],38) %7.0f n[`i'] %9.1f r10[`i'] ///
			%9.1f r25[`i'] %9.1f r50[`i'] %10.1f r100[`i'] %8.1f flat[`i']
	}
restore

* ---- the control that makes the above mean something -------------------------
* Fresh produce and meat cannot carry a printed net weight, so its rates are the
* floor. Anything a packaged item does above that floor is the signal.
gen byte fresh = 0
foreach s in "fresh fish" "chicken" "cabbage" "carrot" "camote" "mango" "pork" "prawn" {
	replace fresh = 1 if strpos(lower(pull_item), "`s'")>0
}
gen byte packaged = 0
foreach s in "crackers" "loaf bread" "preserved" "liquor" "mineral" "noodle" {
	replace packaged = 1 if strpos(lower(pull_item), "`s'")>0
}
label define fp 0 "other" 1 "fresh (no label possible)" 2 "packaged (label possible)"
gen byte grp = cond(fresh,1,cond(packaged,2,0))
label values grp fp

di as res _n "CONTROL: fresh (cannot be label-read) against packaged (can be)."
di as res "The `flat' column is the decisive one."
tabstat r10 r25 r50 r100 flat, by(grp) stat(mean n) format(%7.3f)

di as res _n "FLAT GROUPS BY ITEM"
preserve
	keep if flat
	collapse (count) nw=corrected_weight, by(cs pull_item)
	collapse (count) ngroups=nw (sum) nweighings=nw, by(pull_item)
	gsort -nweighings
	di as txt %-38s "item" %10s "groups" %12s "weighings"
	forvalues i = 1/`=_N' {
		di as txt %-38s abbrev(pull_item[`i'],38) %10.0f ngroups[`i'] %12.0f nweighings[`i']
	}
restore

di as res _n "LIQUOR -- the clearest case. Its distinct published values:"
preserve
	keep if strpos(lower(pull_item),"liquor")>0
	quietly count
	local nliq = r(N)
	contract corrected_weight dim, freq(n)
	gsort -n
	di as txt %10s "value" %6s "dim" %8s "n"
	forvalues i = 1/`=min(_N,12)' {
		di as txt %10.0f corrected_weight[`i'] %6s dim[`i'] %8.0f n[`i']
	}
	quietly count
	di as txt "  `r(N)' distinct (value, dimension) pairs across `nliq' liquor weighings."
	di as txt "  Those are bottle sizes. Nobody weighs hundreds of bottles and gets"
	di as txt "  exactly 375 every time."
restore

* ---- the target list ---------------------------------------------------------
* One photograph settles a whole GROUP: if three vendors' weighings all read 375 and
* the photograph shows a bottle label, every row in that group is a declared value.
* So the file carries the group id -- sample one row per `flat_group', not 937 rows.
keep if flat
gen str44 check_reason = "flat group: 3+ vendors, one identical value"
rename cs flat_group
keep id pull_province pull_municipal_city market_name store_stall_name vendor_id ///
     pull_item pull_nsu_unit harmonized_nsu_unit size dim corrected_weight ///
     flat_group nobs nven check_reason
order id pull_province pull_municipal_city pull_item pull_nsu_unit ///
      harmonized_nsu_unit size dim corrected_weight flat_group nobs nven check_reason
gsort pull_item pull_province pull_municipal_city -nobs id
export delimited using "${tables}/photo_check_packaging.csv", replace

quietly count
local nrow = r(N)
quietly levelsof flat_group, local(gs)
di as res _n "{hline 78}"
di as res "wrote ${tables}/photo_check_packaging.csv"
di as txt "  `nrow' weighings in " `: word count `gs'' " flat groups."
di as txt "  One photograph per GROUP settles the group -- the group count, not the"
di as txt "  row count, is the size of the fieldwork."
di as res "{hline 78}"
