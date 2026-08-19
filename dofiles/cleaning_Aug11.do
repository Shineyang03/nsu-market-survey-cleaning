** NSU Cleaning & Construction **
** Created by: Shine Yang, 11th Aug, 2026

** recleaning the raw data using master_nsu_rename instead of nsu_rename_crosswalk (used previously)
** master_nsu_rename accounts for both 1) merging and substitution of NSUs observed in PSPS (from price data) at the data collection stage (i.e., retrospectively retracing the decisions taken in the field); 2) merging and substitution of NSUs observed in the collected market survey data which are deemed nonsensical at the time of post-data collection cleaning (i.e., actively applying cleaning decisions)

*-------------------------------------------------------------------------------
* WHAT IS DIFFERENT FROM cleaning.do (read this before comparing outputs)
*-------------------------------------------------------------------------------
* 1. GRAIN OF THE RENAME. nsu_rename_crosswalk.xlsx was keyed on (pull_item,
*    pull_nsu_unit) -- item x NSU, identical in every municipality -- and was
*    merged on the RAW-CASED strings. master_nsu_rename.csv is keyed on
*    (province, municipality, item, raw NSU) with all keys already normalized
*    (item/NSU lowercased+trimmed+ASCII-dropped, prov/mun UPPER+ASCII-dropped).
*
*    THE MERGE KEY IS THE RAW, UNCLEANED NSU: pull_province x
*    pull_municipal_city x pull_item x pull_nsu_unit. cleaned_nsu_unit and
*    harmonized_nsu_unit are what the merge RETURNS, never what it matches on --
*    master's whole job is (cell, raw label) -> pooling key.
*
*    Two independent consequences, easy to conflate:
*      (a) casing -- master's key columns arrive already normalized, whereas the
*          old crosswalk carried raw-cased strings and joined to the launch data
*          as recorded. THIS is why the rename merge now has to run AFTER
*          nsu_normalize rather than before. Nothing to do with the grain.
*      (b) grain  -- the join is m:1 on four keys instead of two, and the
*          harmonization is resolved per cell, so one raw label can pool with
*          different siblings in different municipalities (see note 4).
*
* 2. OPERATIONAL UNIT. cleaned_nsu_unit -> harmonized_nsu_unit. cleaned_nsu_unit
*    is carried through for reference only (canonical spelling); every pool,
*    identifier and anchor is built on harmonized_nsu_unit. See
*    docs/master_rename.md section 2-3 for why the harmonized key is
*    item-conditioned but cell-independent.
*
* 3. WHAT GETS DROPPED, AND WHY THE TWO OLD FILTERS ARE NOT THE SAME THING.
*    cleaning.do built its crosswalk by merging the MS and PSPS item x NSU lists,
*    applied a standard-unit label filter, then kept only _merge==3. Those are two
*    separate exclusions and this build treats them differently:
*
*    (a) "MS only" -- NOT dropped any more. master carries the authoritative
*        MS-vs-price source flag per cell and has source=="MS" (MS-only) = 0 rows,
*        so there is nothing to drop on that basis. The old keep(_merge==3) was
*        working at item x NSU grain and discarded MS weighings as collateral.
*
*    (b) STANDARD-QUANTITY LABELS -- still dropped, same substring rule
*        ((Kg)/(g)/(L)/ml/kilo/litres/...), now applied at the weighing level.
*        Ten raw labels / 33 weighings: "bottle (500 ml)", "1.5kg per balde",
*        "1/2 sack of rice (25kls.)", "each 10 litres of gallon", etc. Each names
*        its own quantity, so it needs no measured conversion factor; these are
*        reconciled by hand on the PSPS side at merge time. Every dropped row is
*        exported to tables/excluded_standard_unit_obs.xlsx first.
*
*        The drop is placed BEFORE correct_unit_snap.do deliberately, so these
*        labels also stay out of the item-level anchor pool (step 1c). Mineral
*        water's pools span a 500 mL bottle to a 10 L gallon; letting both vote on
*        one item-level reference is what contaminated that anchor and turned a
*        0.01 L reading of a 10 L gallon into 10 mL.
*
*    Do not confuse (b) with PSPS-side standard-unit RESPONSES -- households that
*    answered in kg/g/L/mL need no conversion factor at all and are excluded on
*    the PSPS side, not here. "The household answered in kg" and "this NSU's name
*    mentions kg" are different conditions.
*
* 4. TWO ASSERTS BECOME DIAGNOSTICS. 757 master rows are in-cell merges
*    (n_cell_merged>1): two or more raw NSU spellings in one prov-mun-item cell
*    collapse to one harmonized unit. Consequences:
*      - "never a municipality that uses both weighing approaches for one
*        item-NSU" (assert sum_wa==1) can now be violated, because the two folded
*        spellings may have been measured under different weighing approaches;
*      - isid prov_mun_nsu_item market_type vendor_id item_nsu_hetero_type can now
*        be violated, because one vendor may have weighed both spellings at the
*        same size/price point.
*    Both are computed, tabulated and EXPORTED (section 5) instead of halting the
*    run. They are properties of the fold, not data errors -- decide on them from
*    the exported lists.
*
* 5. NO id-BASED MANUAL FIXES. cleaning.do resolved one case with
*    `if inlist(id, 4242)`, but id = _n over a sort order that this rename
*    changes. Every manual correction in section 7 is re-expressed as a content
*    condition so it targets the same observation regardless of row order.
*
* 6. nsu_name_notes. master has no counterpart to nsu_rename_crosswalk's `note`
*    column (the "unsure of this NSU" annotations). It is merged back on
*    (item, raw NSU) as REFERENCE ONLY -- it never drives a rename here.
*-------------------------------------------------------------------------------


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


** this attempt writes to its own subtree so the pre-Aug11 build stays intact
global build "${output}\master_rename_build"
cap noi mkdir "${build}"

global btemp "${build}\temp"
cap noi mkdir "${btemp}"

global btables "${build}\tables"
cap noi mkdir "${btables}"

global bgraphs "${build}\graphs"
cap noi mkdir "${bgraphs}"


** the hetero (obs_type) value label is defined in several places below because
** `use ..., clear` on the raw launch data wipes value labels along with the data
capture program drop def_hetero
program define def_hetero
	label define hetero 1 "conventional_nsu" 2 "small_size" 3 "medium_size" 4 "large_size" ///
		5 "mp25_price" 6 "mp50_price" 7 "mp75_price" 8 "municipality_median" ///
		9 "province_median" 10 "unique_mun_price6" 11 "unique_mun_price7", replace
end


********************************************************************************
**# normalization for matching
********************************************************************************

* basically across diff datasets cons_name / nsu / municipal often take diff names.
* ONE definition of the rule, used by every dataset in this file (raw MS data,
* master_nsu_rename, and anything joined to them later) -- so a divergence
* between two copies of the normalization can never be the cause of a no-match.

* This is the Stata twin of nz() / ni() / ng() in dofiles/diagnose_price_only.py,
* which built master_nsu_rename.csv. The two MUST agree character for character
* or rows silently fail to merge. Python:
*     nz(s) = collapse_ws( ascii_drop(s).lower().strip() )      # item, NSU
*     ni(s) = nz(s), then the "restaurant" override
*     ng(s) = collapse_ws( ascii_drop(s).strip().upper() )      # province, mun
* so the operation ORDER is: ASCII-drop -> case-fold -> trim -> collapse runs of
* whitespace. The whitespace collapse is the step Stata's ustrtrim() does NOT do
* on its own -- omitting it strands raw labels with double spaces
* ("fish  sold per pack 90 each  pack") with no rename row.

capture program drop nsu_normalize
program define nsu_normalize
	syntax , Item(name) Unit(name) [Mun(name) PROVince(name)]

	foreach v in `item' `unit' {
		* mode 2 DROPS non-ASCII rather than transliterating, so a clean "n-tilde"
		* and a mojibaked one collapse identically (DUENAS -> DUEAS both ways)
		replace `v' = ustrto(`v', "ascii", 2)
		replace `v' = ustrtrim(ustrlower(`v'))
		replace `v' = ustrregexra(`v', "\s+", " ")
	}

	* prepped food: the item string differs across datasets only in the accent
	replace `item' = "drinks at restaurant, hotel, cafe, or kiosk" if strpos(`item', "restaurant") > 0

	foreach v in `mun' `province' {
		replace `v' = ustrto(`v', "ascii", 2)
		replace `v' = ustrtrim(ustrupper(`v'))
		replace `v' = ustrregexra(`v', "\s+", " ")
	}
end


********************************************************************************
**# use as crosswalk
********************************************************************************

import delimited "${tables}\master_nsu_rename.csv", clear varname(1) stringcols(_all)

* basically each observation (prov x mun x item x nsu) is a PSPS case either found in MS AND price or in price data only

rename province pull_province
rename cons_name pull_item

nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
	mun(pull_municipal_city) province(pull_province)

foreach v in cleaned_nsu_unit harmonized_nsu_unit fallback_harmonized_nsu_unit {
	replace `v' = ustrto(`v', "ascii", 2)
	replace `v' = ustrtrim(ustrlower(`v'))
	replace `v' = ustrregexra(`v', "\s+", " ")
}

destring n_cell_merged, replace

label var pull_item                    "trimmed & lower case pull_item (cons_name in master)"
label var pull_nsu_unit                "Raw NSU unit, trimmed & lower case, ASCII-dropped"
label var cleaned_nsu_unit             "ref only: pull_nsu_unit cleaned for spelling"
label var harmonized_nsu_unit          "POOLING KEY: item-conditioned, cell-independent NSU referent"
label var fallback_harmonized_nsu_unit "if empty/uncommon: last-resort in-cell conversion target"
label var cause_label                  "Price Only: deduced reason for absence from Market Survey"
label var in_ms_as                     "if harmonizable: the concrete in-cell MS sibling matched"
label var cell_merge_with              "other raw NSUs in this cell sharing harmonized_nsu_unit"
label var n_cell_merged                "count of raw spellings in this cell folding together (>1 = merged)"

notes harmonized_nsu_unit: pool and convert on THIS column, never on cleaned_nsu_unit
notes harmonized_nsu_unit: labels stay separate where MS weighings (within item x size x province) showed the spellings/translations are different referents -- see docs/master_rename.md sec 6

isid pull_province pull_municipal_city pull_item pull_nsu_unit

tab source, m
tab cause_label, m

save "${btemp}\master_nsu_rename", replace

* ---- side A: the MS-side rename, used in section 3 ----------------------------
preserve
	keep if source != "Price Only"
	keep pull_province pull_municipal_city pull_item pull_nsu_unit ///
	     cleaned_nsu_unit harmonized_nsu_unit source cell_merge_with n_cell_merged
	isid pull_province pull_municipal_city pull_item pull_nsu_unit
	count
	di as txt "MS-side rename rows: " r(N)
	save "${btemp}\master_rename_ms", replace
restore

* ---- side B: the price-only cases, for the PSPS conversion step (not used here)
preserve
	keep if source == "Price Only"
	keep pull_province pull_municipal_city pull_item pull_nsu_unit ///
	     cleaned_nsu_unit harmonized_nsu_unit cause_label in_ms_as ///
	     fallback_harmonized_nsu_unit
	count
	di as txt "Price-only rename rows: " r(N)
	save "${btemp}\master_rename_price_only", replace
restore


* ---- reference only: the old crosswalk's free-text `note` flags ---------------
import excel "${tables}\nsu_rename_crosswalk.xlsx", clear firstrow

keep pull_item pull_nsu_unit note
drop if mi(note)

nsu_normalize, item(pull_item) unit(pull_nsu_unit)

* the old crosswalk was item x NSU; after normalization a couple of raw labels
* collapse, so reduce to one note per normalized (item, NSU)
bysort pull_item pull_nsu_unit (note): keep if _n == 1

rename note nsu_name_notes
label var nsu_name_notes "REFERENCE ONLY: free-text flag from the superseded nsu_rename_crosswalk"

save "${btemp}\nsu_name_notes", replace


********************************************************************************
**# deal with comments
********************************************************************************
* Unchanged from cleaning.do, and it must run BEFORE normalization: the
* add_comments crosswalk carries the RAW-CASED item / NSU strings ("Chicken",
* "Whole (chicken)"), so it only joins to the raw launch data as recorded.

use "${data}", clear

def_hetero
encode obs_type, gen(item_nsu_hetero_type) label(hetero)

tempfile rawms
save `rawms'

import excel "${tables}\add_comments_crosswalk.xlsx", clear firstrow

def_hetero
encode item_nsu_hetero_type, gen(item_nsu_hetero_type_d) label(hetero)
drop item_nsu_hetero_type
rename item_nsu_hetero_type_d item_nsu_hetero_type

merge 1:1 pull_province pull_municipal_city pull_item pull_nsu_unit weighing_approach market_type vendor_id item_nsu_hetero_type using "`rawms'", nogen

drop is_uncertain

drop add_comments

** dropping errors + ones that are hard to interpret
drop if notes == "To drop (enumerator re-entered 225 weight for the 187.5 price mark)"

count
di as txt "raw MS weighings after comment handling: " r(N)


********************************************************************************
**#  merge master_nsu_rename with raw data to consolidate nsu units
********************************************************************************

nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
	mun(pull_municipal_city) province(pull_province)

merge m:1 pull_province pull_municipal_city pull_item pull_nsu_unit ///
	using "${btemp}\master_rename_ms", keep(1 3) gen(_m_rename)

* master's universe is the union of MS and price at the cell grain, and it has
* source=="MS" (MS-only) = 0 rows, so every MS weighing is expected to match.
* Anything unmatched has no harmonized unit and cannot be pooled -- list it
* loudly rather than carrying a blank pooling key downstream.
count if _m_rename == 1
if r(N) > 0 {
	di as err "WARNING: " r(N) " MS weighing(s) have no master_nsu_rename row"
	preserve
		keep if _m_rename == 1
		contract pull_province pull_municipal_city pull_item pull_nsu_unit, freq(n_obs)
		export excel using "${btables}\unmatched_ms_cells.xlsx", ///
			sheet("no_master_rename_row", replace) firstrow(variables)
		list, noobs abbrev(24)
	restore
}
drop if _m_rename == 1
drop _m_rename

assert !mi(harmonized_nsu_unit) & harmonized_nsu_unit != ".c"

* reference-only annotations from the superseded crosswalk (never a rename here)
merge m:1 pull_item pull_nsu_unit using "${btemp}\nsu_name_notes", keep(1 3) nogen

* ---- exclude raw labels that state a standard quantity ------------------------
* Same substring rule the pre-Aug11 crosswalk used, applied here at the weighing
* level. These labels name their own quantity ("bottle (500 ml)", "1.5kg per
* balde", "each 10 litres of gallon"), so they do not need a measured conversion
* factor -- they are handled by hand on the PSPS side at merge time. Dropping
* them HERE, before correct_unit_snap.do, also keeps them out of the item-level
* anchor pool (step 1c), which matters: mineral water's pools run from a 500 mL
* bottle to a 10 L gallon, and letting both vote on one item-level reference is
* what contaminated that anchor. Every dropped row is exported first.
gen byte looks_standard = ///
	strpos(pull_nsu_unit,"(kg)") > 0 | ///
	strpos(pull_nsu_unit,"(g)")  > 0 | ///
	strpos(pull_nsu_unit,"(l)")  > 0 | ///
	strpos(pull_nsu_unit,"(ml)") > 0 | ///
	strpos(pull_nsu_unit,"ml")   > 0 | ///
	strpos(pull_nsu_unit,"kg")   > 0 | ///
	strpos(pull_nsu_unit,"kilo") > 0 | ///
	strpos(pull_nsu_unit,"(25kls.)") > 0 | ///
	strpos(pull_nsu_unit,"litres") > 0 | ///
	strpos(pull_nsu_unit,"liters") > 0

label var looks_standard "1 = raw label states a standard quantity -> excluded from MS data"
tab looks_standard, m

* the excluded set, for the manual PSPS-side treatment later
preserve
	keep if looks_standard == 1
	decode item_nsu_hetero_type, gen(hetero_lbl)
	keep pull_province pull_municipal_city pull_item pull_nsu_unit ///
	     cleaned_nsu_unit harmonized_nsu_unit weighing_approach hetero_lbl ///
	     market_type vendor_id pull_price weight unit
	order pull_province pull_municipal_city pull_item pull_nsu_unit
	sort pull_item pull_nsu_unit pull_province pull_municipal_city
	list pull_item pull_nsu_unit harmonized_nsu_unit weight unit, ///
		noobs abbrev(30) sepby(pull_item)
	export excel using "${btables}\excluded_standard_unit_obs.xlsx", ///
		sheet("excluded_from_MS", replace) firstrow(variables)
	di as txt "excluded standard-quantity weighings exported: " _N
restore

drop if looks_standard == 1
drop looks_standard

count if notes != ""
di as txt "weighings carrying a cleaning note: " r(N)

* some carrots / cabbages are actually measuring weight of mixed bags
replace harmonized_nsu_unit = "putos (mix vegetable)" if strpos(notes, "halo halo") > 0
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

* encode alphabetizes, so 1=Conventional / 2=Price-quantity / 3=Size-based.
* the rest of this file (and correct_unit_snap.do) depends on 3 == size-based
local wa3 : label (weighing_approach) 3
assert strpos(ustrlower("`wa3'"), "size") > 0

* obs_type = the price point / size the std unit is measured at (to account for non-linearity in conversion factors)
order item_nsu_hetero_type, after(obs_type)
drop obs_type
drop consent_agree
drop consent_reject_reas
drop key
drop observation_number // inconsistent with obs_seq & not according to data correction

order unit, after(weight)
order cleaned_nsu_unit harmonized_nsu_unit, after(pull_nsu_unit)
order item_nsu_hetero_type weight unit, after(pull_price)
order fo_comments_cleaned nsu_name_notes cleaning_notes, last
order actual_price approx_price, after(pull_price)
order market_day, before(market_name)
order source cell_merge_with n_cell_merged, last


* enumerators sometimes enter 0 weight when they don' t observe the item at the specified price / size (5 obs)
replace weight = .c if weight == 0

* drop pull_price fields for size based items
tab pull_price if weighing_approach == 3,m // errors (sized based items with a pull-price), ~900 obs
replace pull_price = . if weighing_approach == 3


cap noi assert inlist(weighing_approach,1,3) if pull_price == . // 3 obs, dropped below (price based item-nsu, but no pull-price recorded)

* drop the Tigbauan Fresh Fish Bilog obs that do not have the stated price (seems like a SCTO Glitch)
* re-expressed on the normalized keys: cleaning.do matched the old uuid string
* "Fresh Fish_Bilog_TIGBAUAN", which this build no longer constructs
count if pull_price == . & pull_item == "fresh fish" & pull_nsu_unit == "bilog" & pull_municipal_city == "TIGBAUAN"
di as txt "Tigbauan Fresh Fish Bilog rows with no stated price: " r(N)
drop if pull_price == . & pull_item == "fresh fish" & pull_nsu_unit == "bilog" & pull_municipal_city == "TIGBAUAN"


count if fo_comments_cleaned != ""
di as txt "weighings carrying a field-officer comment: " r(N)


**# Generating new identifiers to replace uuid / caseid which reflects more accurately the data structure
gen prov_mun = pull_province + "_" + pull_municipal_city

gen nsu_item = pull_item + "_" + harmonized_nsu_unit

gen prov_mun_nsu_item = prov_mun + "_" + nsu_item

order prov_mun nsu_item prov_mun_nsu_item, first

label var nsu_item          "Pull_item x Harmonized_NSU_Unit"
label var prov_mun_nsu_item "Prov x Mun x Pull_item x Harmonized_NSU_Unit"


********************************************************************************
**# Data Structure
********************************************************************************

* ---- (a) raw NSUs: one weighing approach per municipality x item x NSU --------
egen tag = tag(weighing_approach pull_item pull_nsu_unit pull_municipal_city pull_province)

bysort pull_item pull_nsu_unit pull_municipal_city pull_province: egen sum_wa = total(tag) // never a municipality that uses both weighing approaches

tab sum_wa,m
assert sum_wa == 1

drop tag sum_wa

* ---- (b) harmonized NSUs: the same check, now DIAGNOSTIC not asserted --------
* a cell-level fold can bring two raw NSUs measured under different weighing
* approaches into one harmonized unit; that is a property of the fold, so the
* offenders are exported for a decision instead of halting the run
egen tag = tag(weighing_approach pull_item harmonized_nsu_unit pull_municipal_city pull_province)

bysort pull_item harmonized_nsu_unit pull_municipal_city pull_province: egen sum_wa = total(tag)

tab sum_wa,m
cap noi assert sum_wa == 1

preserve
	keep if sum_wa > 1
	if _N > 0 {
		contract pull_province pull_municipal_city pull_item harmonized_nsu_unit ///
		         pull_nsu_unit weighing_approach, freq(n_obs)
		export excel using "${btables}\fold_multi_weighing_approach.xlsx", ///
			sheet("cells_with_mixed_wa", replace) firstrow(variables)
		di as err "cells whose harmonized unit spans >1 weighing approach: " _N " rows exported"
	}
restore

drop tag sum_wa


* ---- (c) in-cell fold intensity ----------------------------------------------
tab n_cell_merged, m

egen byte tag_case = tag(prov_mun_nsu_item)
count if tag_case == 1
di as txt "unique prov x mun x item x harmonized NSU cases: " r(N)
drop tag_case

* how many raw NSU labels sit under each harmonized case
egen tag = tag(prov_mun_nsu_item pull_nsu_unit)
bysort prov_mun_nsu_item: egen n_raw_labels = total(tag)
label var n_raw_labels "distinct raw pull_nsu_unit labels folded into this case"
tab n_raw_labels, m
drop tag


count

** ignore original caseid / uuid: use newly generated groups
drop caseid uuid

drop mun_market_typ // no longer necessary after we depart from the original NSUs

drop obs_seq // no longer necessary after we depart from the original NSUs


** new identifiers to work with harmonized_nsu_unit
* NOT isid-able any more: an in-cell fold can put one vendor's two spellings at
* the same size/price point onto one key. Quantify and export before deciding
* whether to collapse them (they are separate physical weighings of the same
* referent, so pooling in section A of the CF pipeline handles them naturally).
duplicates tag prov_mun_nsu_item market_type vendor_id item_nsu_hetero_type, gen(dup_key)
tab dup_key, m
cap noi isid prov_mun_nsu_item market_type vendor_id item_nsu_hetero_type

preserve
	keep if dup_key > 0
	if _N > 0 {
		keep prov_mun_nsu_item pull_nsu_unit harmonized_nsu_unit market_type ///
		     vendor_id item_nsu_hetero_type weight unit
		sort prov_mun_nsu_item market_type vendor_id item_nsu_hetero_type pull_nsu_unit
		export excel using "${btables}\fold_duplicate_keys.xlsx", ///
			sheet("dup_on_new_identifier", replace) firstrow(variables)
		di as err "weighings sharing a (case x market x vendor x hetero) key: " _N
	}
restore

label var dup_key "n other weighings sharing this case x market x vendor x hetero key (0 = unique)"

gen id = _n

label var id "Unique identifier for each weighing instance"

sort pull_province pull_municipal_city pull_item harmonized_nsu_unit market_type item_nsu_hetero_type

save "${btemp}\prelim_nsu_data", replace


********************************************************************************
**# Correct order-of-magnitude unit-entry errors
********************************************************************************
* Same procedure as the pre-Aug11 build, run through the SAME do-file -- it is
* parameterized rather than copied, so there is exactly one implementation of the
* log10 snap. The only substantive change is the anchor pool: item x
* harmonized_nsu_unit instead of item x cleaned_nsu_unit, which pools the folded
* spellings and so gives each anchor more observations.

global unitvar     "harmonized_nsu_unit"
global snap_in     "${btemp}\prelim_nsu_data"
global snap_out    "${btemp}\standard_weight_unit_correction"
global snap_tables "${btables}"

do "${dofiles}\correct_unit_snap.do"

** release the parameters so a later `do cleaning.do` in the same session gets
** its own defaults back
global unitvar     ""
global snap_in     ""
global snap_out    ""
global snap_tables ""


use "${btemp}\prelim_nsu_data", clear


merge 1:1 id using "${btemp}\standard_weight_unit_correction", assert(3) nogen


order correct*, after(unit)
rename correct_* corrected_*


** propagate missings
replace corrected_weight = .c if weight == .c
replace corrected_unit = .c if weight == .c


tempfile snapped
save `snapped'

* mixup between ml & g
* NOTE: mixed_dimension_items.xlsx is regenerated by correct_unit_snap.do from
* THIS build's prelim data, so its pull_item values are already normalized
* (lowercase) -- the inlist()s below match that, unlike cleaning.do's raw-cased
* versions
import excel "${btables}\mixed_dimension_items.xlsx", firstrow clear

gen diagnostics = ""

replace diagnostics = "g" if inlist(pull_item,"chicken","crackers, cookies, buiscuits, chips/curls","loaf bread","preserved or processed meat (tocino, tapa, longaniza, etc)")

replace diagnostics = "mL" if inlist(pull_item, "liquor (e.g, whisky, coconut wine)","mineral or spring water, all drinking water sold in containers")

* Items left WITHOUT a verdict keep the mass/volume dimension the enumerator
* recorded (correct_unit_snap.do STEP 2 deliberately does not harmonize). That is
* the pre-Aug11 behaviour for ice cream, which is genuinely sold both by weight
* and by volume. This build's mixed list is longer than the old one because it no
* longer drops the ~190 MS weighings the old crosswalk discarded, so BEER and
* DRINKS AT RESTAURANT now appear as mixed too. They are left unverdicted --
* forcing a dimension on them would be a new methodological decision, not a
* port of the old pipeline. Listed here so the choice is visible, not implicit.
count if diagnostics == ""
if r(N) > 0 {
	di as err "mixed-dimension items with NO dimension verdict (recorded dimension kept): " r(N)
	list pull_item n_mass n_vol if diagnostics == "", noobs abbrev(60)
	preserve
		keep if diagnostics == ""
		export excel using "${btables}\mixed_dimension_no_verdict.xlsx", ///
			sheet("needs_a_decision", replace) firstrow(variables)
	restore
}

keep pull_item diagnostics

merge 1:m pull_item using `snapped', assert(2 3) nogen


* manual correction - rescale weights

replace corrected_unit = 1 if diagnostics == "g" & corrected_unit != 1 & !mi(corrected_unit)
replace corrected_unit = 2 if diagnostics == "mL" & corrected_unit != 2 & !mi(corrected_unit)


* some of these are due to incorrect DP in original weight

replace corrected_weight = weight * (1000^2)  if pull_item == "liquor (e.g, whisky, coconut wine)" & pull_province == "ILOILO" & corrected_unit == 2 & corrected_weight == 1


replace corrected_weight = weight * (1000^2) if pull_province == "ILOILO" & nsu_item == "chicken_whole (chicken)" & item_nsu_hetero_type == 2  & corrected_unit == 1 & corrected_weight == 1

replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.001 L)" if pull_item == "ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)" & corrected_unit == 2 & inrange(corrected_weight,1,2) // unsure
replace corrected_weight = weight * (1000^2) if pull_item == "ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)" & corrected_unit == 2 & inrange(corrected_weight,1,2) // unsure


replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.001x L)" if pull_item == "preserved or processed meat (tocino, tapa, longaniza, etc)" & corrected_unit == 1 & inrange(corrected_weight,1,2) // unsure
replace corrected_weight = weight * (1000^2) if pull_item == "preserved or processed meat (tocino, tapa, longaniza, etc)" & corrected_unit == 1 & inrange(corrected_weight,1,2) // unsure


replace cleaning_notes = "uncertain cleaning interpretation of original weight-unit values (0.01 L)" if inlist(harmonized_nsu_unit,"refilled", "container") & corrected_weight == 10
replace corrected_weight = 1000 if inlist(harmonized_nsu_unit,"refilled", "container") & corrected_weight == 10


** drop clearly erroneous entries & genuinely unsure instances

* cleaning.do targeted this row as `inlist(id, 4242)`. id is _n, and the two
* saved copies of the old build disagree on which observation id 4242 is, so it
* is re-expressed on the recorded entry itself. The row is CAPIZ / PANAY /
* mineral water / "distilled water" / medium_size / vendor KXHXIWAI: 0.007 L,
* which no power-of-ten reading makes sense of.
*
* NOTE the float() wrapper. `weight` is stored as a float and 0.007 is not
* exactly representable, so a bare `weight == 0.007` silently matches NOTHING.
* The assert below turns any future silent miss into a hard stop.
gen byte is_0007L = unit == 3 & weight == float(0.007)
count if is_0007L
di as txt "0.007 L rows (was id 4242): " r(N)
assert r(N) == 1

replace cleaning_notes = "Genuinely unsure about how to interpret original weight-unit values (0.007 L)" if is_0007L
replace corrected_weight = .c if is_0007L
replace corrected_unit = .c if is_0007L
drop is_0007L

gen byte is_5g_cup = inlist(harmonized_nsu_unit,"cup") & pull_item == "prawns, lobster, shrimp" & weight == 5 & unit == 2
count if is_5g_cup
di as txt "5 g per cup prawn rows: " r(N)
assert r(N) > 0

replace cleaning_notes = "Genuinely unsure about how to interpret original weight-unit values  (5 g per cup)" if is_5g_cup
replace corrected_weight = .c if is_5g_cup
replace corrected_unit = .c if is_5g_cup
drop is_5g_cup


* NOTE: the standard-quantity labels that used to produce implausible volumes here
* ("each 10 litres of gallon" reading 0.01 L -> 10 mL) are excluded upstream now,
* so there is no residual label-vs-reading conflict left to flag at this point.


drop weight unit diagnostics

sort pull_province pull_municipal_city pull_item harmonized_nsu_unit market_type item_nsu_hetero_type
order id, first

compress
save "${btemp}\nsu_data_master", replace


********************************************************************************
**# Build report: this build vs the pre-Aug11 nsu_data
********************************************************************************
* One place to see what swapping the crosswalk did, at the grains that matter for
* the conversion-factor pipeline. Written to xlsx so it can be checked without
* re-running anything.

putexcel set "${btables}\build_comparison.xlsx", replace sheet("counts")
putexcel A1 = "Metric"  B1 = "master_nsu_rename (this build)"  C1 = "nsu_rename_crosswalk (pre-Aug11)", bold

local metrics "weighings items unit_labels item_x_unit cases prov_item_unit"

foreach src in new old {

	if "`src'" == "new" {
		use "${btemp}\nsu_data_master", clear
		local unitv harmonized_nsu_unit
		local col B
	}
	else {
		capture use "${temp}\nsu_data", clear
		if _rc {
			di as err "pre-Aug11 nsu_data.dta not found -- comparison column left blank"
			continue
		}
		local unitv cleaned_nsu_unit
		local col C
	}

	qui count
	local v_weighings = r(N)
	qui unique pull_item
	local v_items = r(unique)
	qui unique `unitv'
	local v_unit_labels = r(unique)
	qui unique pull_item `unitv'
	local v_item_x_unit = r(unique)
	qui unique pull_province pull_municipal_city pull_item `unitv'
	local v_cases = r(unique)
	qui unique pull_province pull_item `unitv'
	local v_prov_item_unit = r(unique)

	local row = 2
	foreach m of local metrics {
		putexcel A`row' = "`m'"
		putexcel `col'`row' = (`v_`m'')
		local ++row
	}
}

local row = `row' + 1
putexcel A`row' = "Notes", bold
local ++row
putexcel A`row' = "unit variable: harmonized_nsu_unit (new) vs cleaned_nsu_unit (pre-Aug11)"
local ++row
putexcel A`row' = "MS-only rows are no longer dropped (master has 0 of them); standard-quantity labels ARE still dropped -- 10 labels / 33 weighings, listed in excluded_standard_unit_obs.xlsx"
local ++row
putexcel A`row' = "see cleaning_Aug11.do header note 3 for why those two old filters are separate exclusions"

use "${btemp}\nsu_data_master", clear

di as res _n "=== build complete ==="
di as txt "dataset : ${btemp}\nsu_data_master.dta"
di as txt "report  : ${btables}\build_comparison.xlsx"
count
di as txt "weighings: " r(N)
qui unique prov_mun_nsu_item
di as txt "prov x mun x item x harmonized-NSU cases: " r(unique)
qui unique nsu_item
di as txt "item x harmonized-NSU pairs: " r(unique)
