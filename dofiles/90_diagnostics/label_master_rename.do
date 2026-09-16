********************************************************************************
* label_master_rename.do -- a documented, self-describing copy of the crosswalk
*
* WHAT THIS IS FOR. `master_nsu_rename` is the harmonization crosswalk: it says, for
* every (province, municipality, item, raw NSU spelling) in the survey, what that
* spelling was cleaned to and what it pools with. The build's own copy is a working
* object -- bare column names, everything a string. This writes the same rows with a
* label on every variable and value labels on the two categorical columns, so it can be
* opened by someone who was not told what the columns mean.
*
* NOTHING IN THE PIPELINE READS THIS. It is a reference copy. The build continues to
* read ${btemp}\master_nsu_rename.dta, and this file must never be substituted for it:
* `source` and `cause_label` are ENCODED here, so a `keep if source == "Price Only"`
* written against the working copy would silently match nothing here.
*
* THE ONE CONFIRMED COPY IS outputs/tables/master_nsu_rename.csv, written by
* 01_build_crosswalk.py and imported by 03_clean_ms.do. The copy under reference/ is a
* FROZEN pre-split baseline (issue #33) and is deliberately older -- see reference/README.md.
*
* INPUT   ${btemp}\master_nsu_rename.dta   as 03_clean_ms.do saved it
* OUTPUT  ${tables}\master_nsu_rename_labelled.dta
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\label_master_rename.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

use "${btemp}\master_nsu_rename", clear
qui count
di as res _n "crosswalk rows: " r(N)

********************************************************************************
**# 1. Value labels -- the two columns that are categorical rather than free text
********************************************************************************
* encode() assigns codes alphabetically. Declaring them explicitly instead, so the
* numbers mean something stable and a re-run cannot silently renumber them when a
* category gains or loses its last row.

* ---- source ------------------------------------------------------------------
gen byte _source = .
replace _source = 1 if source == "MS & Price"
replace _source = 2 if source == "MS"
replace _source = 3 if source == "Price Only"
assert !missing(_source) if !missing(source) & source != ""
label define source_lbl ///
	1 "MS & Price -- weighed in the market survey and present in the price file" ///
	2 "MS -- weighed in the market survey, absent from the price file" ///
	3 "Price Only -- in the price file, never weighed in this cell"
label values _source source_lbl
drop source
rename _source source

* ---- cause_label -------------------------------------------------------------
gen byte _cause = .
replace _cause = 1 if cause_label == "harmonizable"
replace _cause = 2 if cause_label == "empty/uncommon"
replace _cause = 3 if cause_label == "nonsensical (recoverable)"
replace _cause = 4 if cause_label == "nonsensical (unmappable)"
assert !missing(_cause) if !missing(cause_label) & trim(cause_label) != ""
label define cause_lbl ///
	1 "harmonizable -- the same object is already in this cell under another spelling" ///
	2 "empty/uncommon -- a real unit, but this cell has no weighing of it" ///
	3 "nonsensical (recoverable) -- a quantity-prefixed string with a base unit inside" ///
	4 "nonsensical (unmappable) -- not a unit; no base unit can be recovered"
label values _cause cause_lbl
drop cause_label
rename _cause cause_label

********************************************************************************
**# 2. Variable labels -- every column, in the order a reader meets them
********************************************************************************
label var pull_province        "Province, uppercase, as harmonized across the survey"
label var pull_municipal_city  "Municipality or city, uppercase; with province and item this is the CELL"
label var pull_item            "Food item, as the consumption module names it"
label var pull_nsu_unit        "RAW non-standard unit label, lowercased and trimmed, non-ASCII dropped"
label var cleaned_nsu_unit     "Raw label at canonical spelling -- REFERENCE ONLY, nothing pools on this"
label var harmonized_nsu_unit  "THE POOLING KEY: spellings sharing a physical referent collapse here"
label var source               "Which side of the project saw this spelling in this cell"
label var cell_merge_with      "Other raw spellings IN THIS CELL sharing this harmonized unit ('; ' separated)"
label var n_cell_merged        "Raw spellings in this cell collapsing to this harmonized unit (>1 = a merge)"
label var cause_label          "Price Only rows: why the spelling was missing from the market survey"
label var in_ms_as             "Price Only harmonizable rows: the market-survey unit in this same cell it matched"
label var fallback_harmonized_nsu_unit ///
	"Price Only empty/uncommon rows: a local conversion target from a sibling unit, if one exists"
label var price_case_id        "Durable id for a Price Only case; blank on MS & Price rows by design"

********************************************************************************
**# 3. Dataset label, order, and the checks that make the copy trustworthy
********************************************************************************
* One row per raw spelling per cell -- the grain the fold is decided at.
isid pull_province pull_municipal_city pull_item pull_nsu_unit

* The two operational columns are never blank; that is what makes the crosswalk total.
assert !missing(harmonized_nsu_unit) & trim(harmonized_nsu_unit) != ""
assert !missing(cleaned_nsu_unit)    & trim(cleaned_nsu_unit)    != ""

* price_case_id is a Price Only construct; asserting it so a reader can rely on the blank.
assert missing(price_case_id) if source == 1
qui count if source == 3 & !missing(price_case_id)
di as txt "Price Only rows carrying a case id: " r(N)

order pull_province pull_municipal_city pull_item pull_nsu_unit ///
      cleaned_nsu_unit harmonized_nsu_unit source n_cell_merged cell_merge_with ///
      cause_label in_ms_as fallback_harmonized_nsu_unit price_case_id
sort pull_province pull_municipal_city pull_item pull_nsu_unit

label data "NSU harmonization crosswalk -- raw spelling to pooling key, one row per cell x spelling"

di as res _n "source"
tab source, m
di as res _n "cause_label"
tab cause_label, m
di as res _n "cells where more than one raw spelling pools into one harmonized unit"
qui count if n_cell_merged > 1
di as txt "  rows: " r(N)

compress
* Alongside master_nsu_rename.csv/.xlsx in outputs/tables, not in the build tree: this
* is a reference copy of the crosswalk, not a product of a build run.
save "${tables}\master_nsu_rename_labelled", replace
di as res _n "wrote ${tables}\master_nsu_rename_labelled.dta (" _N " rows)"
describe
