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
*    (b) NON-NSU LABELS -- still dropped, but the rule now lives in ONE place.
*        drop_non_nsu_labels.py classifies a raw label as standard quantity
*        ("bottle (500 ml)", "1/2 sack of rice (25kls.)"), ambiguous quantity
*        ("500", "pieces/ kilo"), or not a unit at all, removes it from
*        master_nsu_rename, and reports what it removed. This file reads that
*        report and drops the matching MS weighings, rather than keeping a second
*        copy of the substring rule. Sixteen labels / 58 weighings. None needs a
*        measured conversion factor; the standard-quantity ones are reconciled by
*        hand on the PSPS side at merge time. Every dropped row is exported to
*        tables/excluded_standard_unit_obs.xlsx first, with its drop_reason.
*
*        The drop is placed BEFORE 04_unit_snap.do deliberately, so these
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


****************************************************************************************************
**# Setting Globals
********************************************************************************
* Paths and the shared programs (def_hetero, nsu_normalize) live in one place now.
* Run this file on its own with the dofiles/ folder as the working directory.
do "00_shared/00_globals.do"

************************************************************
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

* ---- side C: labels removed from the crosswalk because they are not NSUs ------
* drop_non_nsu_labels.py owns the definition of "not an NSU" -- standard quantity
* ("bottle (500 ml)"), ambiguous quantity ("500", "pieces/ kilo"), and free text
* that is not a unit at all ("1 sack is 2900/for salary/inkind") -- and applies it
* to master_nsu_rename. The MS weighings carrying those same raw labels have to
* leave too, and they have to leave for the STATED REASON rather than by falling
* out of the crosswalk merge as an unexplained non-match. Reading that script's own
* report keeps ONE definition of the rule instead of a Stata copy that can drift.
preserve
	import delimited "${tables}\master_rename_dropped_labels.csv", ///
		clear varname(1) stringcols(_all)
	rename province pull_province
	rename cons_name pull_item
	nsu_normalize, item(pull_item) unit(pull_nsu_unit) ///
		mun(pull_municipal_city) province(pull_province)
	foreach v in cleaned_nsu_unit harmonized_nsu_unit {
		replace `v' = ustrto(`v', "ascii", 2)
		replace `v' = ustrtrim(ustrlower(`v'))
		replace `v' = ustrregexra(`v', "\s+", " ")
	}
	* prefixed so they cannot collide with the crosswalk merge downstream
	rename cleaned_nsu_unit    xw_cleaned_nsu_unit
	rename harmonized_nsu_unit xw_harmonized_nsu_unit
	keep pull_province pull_municipal_city pull_item pull_nsu_unit ///
	     xw_cleaned_nsu_unit xw_harmonized_nsu_unit drop_reason
	isid pull_province pull_municipal_city pull_item pull_nsu_unit
	count
	di as txt "non-NSU labels removed from the crosswalk: " r(N)
	tab drop_reason, m
	save "${btemp}\master_rename_dropped", replace
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

* ---- DURABLE WEIGHING ID -- attached here, ASSIGNED in 00a_weighing_ids.do --------
* `id' is looked up, never created here. 00a assigns it on the raw file and owns the
* registry; this step only reads. That split is deliberate: 01_build_crosswalk.py also
* needs the registry, and 01 runs BEFORE this file, so seeding here left a fresh clone
* needing two passes to converge. See the header of 00a for the ordering.
*
* THE KEY is the content key: province, municipality, item, RAW label, vendor, hetero
* type. All raw inputs. Deliberately not harmonized_nsu_unit -- keying on a value the
* crosswalk can change would move ids whenever a fold changed, which is the failure the
* registry exists to prevent.
*
* Commas are stripped before joining because the registry is a CSV and several item
* names contain them. The isid proves the strip collides nothing.
tempvar idkey
gen str244 `idkey' = subinstr(pull_province, ",", "", .) ///
    + "|" + subinstr(pull_municipal_city, ",", "", .) ///
    + "|" + subinstr(pull_item, ",", "", .) ///
    + "|" + subinstr(pull_nsu_unit, ",", "", .) ///
    + "|" + subinstr(vendor_id, ",", "", .) ///
    + "|" + subinstr(obs_type, ",", "", .)
isid `idkey'

capture confirm file "${tables}\weighing_id_registry.csv"
if _rc {
	di as error "NO ID REGISTRY at ${tables}\weighing_id_registry.csv"
	di as error "Run 00_shared/00a_weighing_ids.do first -- it assigns the ids from the"
	di as error "raw file. This step reads them and must not create them: 01 needs the"
	di as error "same registry and runs earlier."
	exit 601
}

preserve
	* delimiter(",") is NOT optional. import delimited auto-detects, and the key holds
	* five "|" characters against the header's zero commas, so it picks "|" and splits
	* the key into six variables -- silently, reporting "(6 vars, ... obs)".
	import delimited "${tables}\weighing_id_registry.csv", clear varnames(1) ///
		delimiter(",") stringcols(1) encoding("utf-8")
	isid idkey
	isid id
	tempfile registry
	save "`registry'"
restore

rename `idkey' idkey
merge m:1 idkey using "`registry'", keep(1 3) gen(_m_id)

* Every raw weighing was numbered by 00a, so an unmatched row here means the content
* key moved between the two steps -- most likely a normalization change. That is a
* reconciliation, not something to paper over by minting a new id.
count if _m_id == 1
if r(N) > 0 {
	di as error "`r(N)' weighing(s) are not in the id registry."
	di as error "00a numbers the whole raw file, so this means the content key changed"
	di as error "between 00a and here. Reconcile that; do not assign new ids."
	list pull_province pull_municipal_city pull_item pull_nsu_unit if _m_id == 1, noobs
	exit 459
}
drop _m_id idkey

assert !missing(id)
isid id

label var id "Durable weighing id: assigned in 00a_weighing_ids.do, held in outputs/tables/weighing_id_registry.csv"

* `id' IDENTIFIES A WEIGHING, NOT A CASE. Do not use it as a case key and do not
* "improve" it toward one. The case (the pooling grain) is
*     province x municipality x item x harmonized_nsu_unit x corrected_unit
* built as `cell' in 10_size_assignment.do, with the string form `prov_mun_nsu_item'
* here. The case key SHOULD move when a fold changes -- that is what a fold does. A
* weighing id must NOT, which is why the two are keyed differently and why this one
* uses the raw label.

tempfile rawms
save `rawms'

* ---- the block reading, computed HERE and deliberately not later ---------------
* This is the last point in the build at which no fold decision has been applied: the
* crosswalk merge is below, at "merge master_nsu_rename with raw data". The block
* reading is a pure function of `weight', `unit' and KGMAX, so it COULD be computed
* anywhere -- it used to be STEP 3a-3d of 04_unit_snap.do, which runs after the merge.
*
* Position is the point. The fold test asks whether two raw labels folded into one
* harmonized unit actually weigh the same, and it cannot answer that from a weight the
* snap moved toward a pool keyed on that same harmonized unit. Computing the block
* reading above the merge makes its independence STRUCTURAL rather than something a
* reader has to establish by tracing 04. See 03a_block_reading.do's header and
* dofiles/README.md, "Two different loops".
global block_in  "`rawms'"
global block_out "${btemp}\block_reading"
do "${dofiles}/00_shared/03a_block_reading.do"
global block_in  ""
global block_out ""

import excel "${tables}\add_comments_crosswalk.xlsx", clear firstrow

def_hetero
encode item_nsu_hetero_type, gen(item_nsu_hetero_type_d) label(hetero)
drop item_nsu_hetero_type
rename item_nsu_hetero_type_d item_nsu_hetero_type

merge 1:1 pull_province pull_municipal_city pull_item pull_nsu_unit weighing_approach market_type vendor_id item_nsu_hetero_type using "`rawms'", gen(_m_cmt)

* The crosswalk is master here and the raw MS data is `using', so a master-only row
* is a comment keyed to a weighing that does not exist. It would survive the merge
* as a phantom observation with weight, unit, price and market all missing, and
* nothing downstream would mark it as such. 0 today; assert it stays 0. Note
* item_nsu_hetero_type is `encode'd separately on each side, and encode assigns an
* unseen string a NEW code rather than erroring -- so a typo in the crosswalk shows
* up here and only here.
count if _m_cmt == 1
if r(N) > 0 {
	di as err "ERROR: " r(N) " add_comments row(s) match no MS weighing"
	list pull_province pull_municipal_city pull_item pull_nsu_unit ///
		item_nsu_hetero_type if _m_cmt == 1, noobs abbrev(24)
	exit 459
}
drop _m_cmt

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


* ---- exclude raw labels that are not NSUs -------------------------------------
* Runs BEFORE the crosswalk merge, on the raw label, because these labels no longer
* HAVE a crosswalk row (drop_non_nsu_labels.py removed them). Run afterwards, they
* would disappear as "no master_nsu_rename row" -- dropped for the wrong reason, and
* invisible to the attrition ledger. Placing it here also keeps them out of
* 04_unit_snap.do's item-level anchor pool (step 1c), which matters: mineral
* water's pools run from a 500 mL bottle to a 10 L gallon, and letting both vote on
* one item-level reference is what contaminated that anchor.
*
* These labels name their own quantity or are unrecoverable, so none of them needs a
* MEASURED conversion factor; the standard-quantity ones are reconciled by hand on
* the PSPS side at merge time (issue #14).
merge m:1 pull_province pull_municipal_city pull_item pull_nsu_unit ///
	using "${btemp}\master_rename_dropped", keep(1 3) gen(_m_dropped)

count if _m_dropped == 3
local n_nonnsu = r(N)
di as txt "MS weighings on a non-NSU label: `n_nonnsu'"
if `n_nonnsu' > 0 {
	tab drop_reason if _m_dropped == 3, m

	preserve
		keep if _m_dropped == 3
		rename xw_cleaned_nsu_unit    cleaned_nsu_unit
		rename xw_harmonized_nsu_unit harmonized_nsu_unit
		decode item_nsu_hetero_type, gen(hetero_lbl)
		* `id' rides along so an excluded weighing stays referenceable. It keeps the
		* number it was assigned on the raw file, so a label re-admitted later comes
		* back as the same weighing rather than a new one.
		keep id pull_province pull_municipal_city pull_item pull_nsu_unit ///
		     drop_reason cleaned_nsu_unit harmonized_nsu_unit ///
		     weighing_approach hetero_lbl market_type vendor_id pull_price ///
		     weight unit
		order id pull_province pull_municipal_city pull_item pull_nsu_unit drop_reason
		sort drop_reason pull_item pull_nsu_unit pull_province pull_municipal_city
		list pull_item pull_nsu_unit drop_reason weight unit, ///
			noobs abbrev(30) sepby(drop_reason)
		* ERASED FIRST, and the reason is a real failure rather than caution.
		* `sheet(, replace)' rewrites an EXISTING workbook in place: Stata reads it,
		* swaps the sheet, and writes it back through scratch files it drops in the
		* same folder (STU<hex>_<hex>.tmp). On a sync drive that round trip is where
		* it breaks -- this export failed r(603) "could not be saved" on two
		* consecutive runs against a workbook that was perfectly readable, and
		* succeeded immediately once the file was deleted and rebuilt from nothing.
		* Four orphaned STU*.tmp files had been sitting beside it, which is what a
		* half-finished rewrite leaves behind.
		*
		* This workbook holds ONE sheet, so there is nothing in it worth preserving
		* across a run. Erasing makes the export a plain write, which cannot fail
		* that way. `capture' because the first run of a fresh clone has no file to
		* erase, and that is not an error.
		capture erase "${btables}\excluded_standard_unit_obs.xlsx"
		export excel using "${btables}\excluded_standard_unit_obs.xlsx", ///
			sheet("excluded_from_MS", replace) firstrow(variables)
		di as txt "excluded non-NSU weighings exported: " _N
	restore
}

drop if _m_dropped == 3
drop _m_dropped xw_cleaned_nsu_unit xw_harmonized_nsu_unit drop_reason

merge m:1 pull_province pull_municipal_city pull_item pull_nsu_unit ///
	using "${btemp}\master_rename_ms", keep(1 3) gen(_m_rename)

* master's universe is the union of MS and price at the cell grain, and it has
* source=="MS" (MS-only) = 0 rows. The non-NSU labels that USED to land here as
* non-matches were removed above, for a stated reason. So every MS weighing that
* reaches this line must match, and an unmatched row is a genuine join break --
* a normalization drift between this file and the script that built the crosswalk,
* or a new raw label that belongs on drop_non_nsu_labels.py's list. Either way it
* is a defect, not attrition: STOP rather than drop.
count if _m_rename == 1
if r(N) > 0 {
	di as err "ERROR: " r(N) " MS weighing(s) have no master_nsu_rename row"
	preserve
		keep if _m_rename == 1
		contract pull_province pull_municipal_city pull_item pull_nsu_unit, freq(n_obs)
		export excel using "${btables}\unmatched_ms_cells.xlsx", ///
			sheet("no_master_rename_row", replace) firstrow(variables)
		list, noobs abbrev(24)
	restore
	di as err "Either the normalization drifted from the crosswalk builder, or these"
	di as err "labels are not NSUs and belong in dofiles/00_shared/02_drop_non_nsu_labels.py."
	di as err "Do not silence this by re-adding a drop -- that is what hid the"
	di as err "standard-quantity rows and broke the excluded-obs export."
	exit 459
}
drop _m_rename

assert !mi(harmonized_nsu_unit) & harmonized_nsu_unit != ".c"

* reference-only annotations from the superseded crosswalk (never a rename here)
merge m:1 pull_item pull_nsu_unit using "${btemp}\nsu_name_notes", keep(1 3) nogen

count if notes != ""
di as txt "weighings carrying a cleaning note: " r(N)

* MIXED-BAG REASSIGNMENT -- RETIRED, now declared in the crosswalk.
*
* This used to be:
*     replace harmonized_nsu_unit = "putos (mix vegetable)" if strpos(notes,"halo halo")>0
* which assigned a harmonized unit AFTER the crosswalk merge, on the MS side only.
* Three consequences, all measured before it was moved:
*   1. the join never validated the value it assigned;
*   2. it caught only the 4 rows carrying the comment, leaving 2 uncommented
*      TIGBAUAN cabbage "putos" rows folded to "pack" -- one cell, two harmonized
*      units, which is the cell-independence invariant breaking;
*   3. the price file kept the old fold, so "putos (mix vegetable)" had no price row
*      at TIGBAUAN and 4 weighings (65/90/85/85 g) went into Outcome 2 as orphans.
*      All 4 are weighing_approach == 2, and the price-coverage assertion only
*      inspects approach 3, so nothing caught it.
*
* The fold now lives in CELL_MIX in 00_shared/nsu_fold_rule.py, keyed on
* (province, municipality, item, raw unit), where it moves BOTH sides together.
* The field evidence is recorded there.
*
* Tripwire: if a mixed-bag comment appears in a cell CELL_MIX does not cover, the
* fold is missing and this stops the build rather than publishing the old split.
count if strpos(notes, "halo halo") > 0 & harmonized_nsu_unit != "putos (mix vegetable)"
if r(N) > 0 {
	di as error "`r(N)' row(s) carry a mixed-bag comment but did not fold to putos (mix vegetable)."
	di as error "Add the cell to CELL_MIX in 00_shared/nsu_fold_rule.py -- do NOT re-add a"
	di as error "post-merge replace here; see the note above for why that broke three ways."
	list pull_province pull_municipal_city pull_item pull_nsu_unit harmonized_nsu_unit ///
		if strpos(notes, "halo halo") > 0 & harmonized_nsu_unit != "putos (mix vegetable)", noobs
	exit 459
}

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
* the rest of this file (and 04_unit_snap.do) depends on 3 == size-based
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


* Every price-quantity row should now carry a price. Exactly 3 do not, and they are the
* SAME 3 rows the Tigbauan drop below removes -- measured, not assumed. cleaning.do wrote
* this as `cap noi assert', which swallowed the return code and never checked _rc, so the
* failure was invisible and a FOURTH such row would have passed just as quietly.
*
* Derivation of the 3: after `replace pull_price = . if weighing_approach == 3' above,
* the only rows left with a missing price and an approach other than 1 or 3 are
* ILOILO / TIGBAUAN / fresh fish / bilog, approach 2. Anything else appearing here is a
* new data problem, not this known one -- reconcile it, do not raise the number.
count if pull_price == . & !inlist(weighing_approach, 1, 3)
local n_nopricewa2 = r(N)
di as txt "price-quantity weighings with no price: `n_nopricewa2'"
assert `n_nopricewa2' == 3

count if pull_price == . & !inlist(weighing_approach, 1, 3) ///
	& pull_item == "fresh fish" & pull_nsu_unit == "bilog" ///
	& pull_municipal_city == "TIGBAUAN"
assert r(N) == `n_nopricewa2'

* drop the Tigbauan Fresh Fish Bilog obs that do not have the stated price (seems like a SCTO Glitch)
* re-expressed on the normalized keys: cleaning.do matched the old uuid string
* "Fresh Fish_Bilog_TIGBAUAN", which this build no longer constructs
count if pull_price == . & pull_item == "fresh fish" & pull_nsu_unit == "bilog" & pull_municipal_city == "TIGBAUAN"
di as txt "Tigbauan Fresh Fish Bilog rows with no stated price: " r(N)
assert r(N) == 3
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

* DEFAULT, not an assignment: a caller that has already set ${unitvar} keeps its choice.
* The comment above says this step is parameterized rather than copied, but the parameter
* was hardcoded here, so the only way to try a different anchor pool was to edit the file
* -- which is how you end up with two implementations of one rule. Overridable now, so
* the re-keying question (raw label vs cleaned vs harmonized) can be MEASURED instead of
* argued. See dofiles/README.md, "Which unit the anchor pools on".
if "${unitvar}" == "" global unitvar "harmonized_nsu_unit"
global snap_in     "${btemp}\prelim_nsu_data"
global snap_out    "${btemp}\standard_weight_unit_correction"
global snap_tables "${btables}"

do "${dofiles}/00_shared/04_unit_snap.do"

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
* NOTE: mixed_dimension_items.xlsx is regenerated by 04_unit_snap.do from
* THIS build's prelim data, so its pull_item values are already normalized
* (lowercase) -- the inlist()s below match that, unlike cleaning.do's raw-cased
* versions
import excel "${btables}\mixed_dimension_items.xlsx", firstrow clear

gen diagnostics = ""

replace diagnostics = "g" if inlist(pull_item,"chicken","crackers, cookies, buiscuits, chips/curls","loaf bread","preserved or processed meat (tocino, tapa, longaniza, etc)")

replace diagnostics = "mL" if inlist(pull_item, "liquor (e.g, whisky, coconut wine)","mineral or spring water, all drinking water sold in containers")

* Items left WITHOUT a verdict keep the mass/volume dimension the enumerator
* recorded (04_unit_snap.do STEP 2 deliberately does not harmonize). That is
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


* ------------------------------------------------------------------------------
* Manual weight/unit corrections
* ------------------------------------------------------------------------------
* Moved out to its own file so every hand-made correction lives in one place and
* each one asserts that it actually matched the rows it was written for. The block
* that used to sit here contained a correction that silently matched NOTHING -- the
* ILOILO chicken rescale tested the wrong hetero code, logged "(0 real changes
* made)", and shipped a 1 gram whole chicken to the reference set. The assertions in
* that file turn a silent miss into a halt.
do "${dofiles}/00_shared/05_manual_corrections.do"


drop weight unit diagnostics

sort pull_province pull_municipal_city pull_item harmonized_nsu_unit market_type item_nsu_hetero_type
order id, first

compress
* Deterministic row order: `id' is unique, so this leaves no ties for the sort
* seed to break. Without it the saved file's ORDER varies between runs.
sort id

save "${btemp}\nsu_data_master", replace


********************************************************************************
**# Build report: this build vs the pre-Aug11 nsu_data
********************************************************************************
* One place to see what swapping the crosswalk did, at the grains that matter for
* the conversion-factor pipeline. Written to xlsx so it can be checked without
* re-running anything.

* `open' keeps the workbook in memory; without it putexcel re-saves the whole file
* on EVERY command, and the loop below issues dozens. On a Box-synced folder that
* races the sync client and fails with "could not be saved" (r603) -- reproducibly,
* not occasionally. One write at the end instead.
* ...and `replace' is still not enough on its own. This file is written by BOTH
* masters, because 03 is shared, so running master_outcome2.do after
* master_outcome1.do asks putexcel to overwrite a workbook Box wrote seconds earlier
* and may still be holding. That fails r(603) and takes the whole build with it.
* Erasing first means `replace' writes a new file rather than overwriting a held one
* -- the same fix already used for excluded_standard_unit_obs.xlsx at the top of this
* file. `capture' because the file legitimately does not exist on a clean build.
capture erase "${btables}\build_comparison.xlsx"
putexcel set "${btables}\build_comparison.xlsx", replace sheet("counts") open
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
putexcel A`row' = "MS-only rows are no longer dropped (master has 0 of them); non-NSU labels ARE still dropped -- 16 labels / 58 weighings (standard quantity, ambiguous quantity, not a unit), listed in excluded_standard_unit_obs.xlsx"
local ++row
putexcel A`row' = "see 03_clean_ms.do header note 3 for why those two old filters are separate exclusions"

putexcel save
putexcel close

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
