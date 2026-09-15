********************************************************************************
* 06_cpi_panel.do
*
* Builds the CPI level panel and the item crosswalk specified in
* docs/inflation_adjustment_spec.md. Stata port of dofiles/archive/06_cpi_panel.py,
* written to reproduce that script's three artifacts byte for byte.
*
* WHY THIS IS A DO-FILE
* Project policy (CLAUDE.md, "Build objects in Stata. Python only where Stata
* cannot") reserves Python for fuzzy string matching, .xlsx I/O and unicode
* normalization. This step does none of those: it reads two CSVs, joins them on
* an exact key, takes a moving average, and writes two CSVs plus a text report.
* Every language boundary is a place Stata's data model gets re-interpreted, and
* that re-interpretation fails silently, so the boundary is removed.
*
* DELIVERABLES (levels only -- no ratios, no inflation factors, no aggregation to
* any survey grain, no application to weights; spec section 7)
*
*   cpi_level_panel.csv       province x item_group x month -> cpi, cpi_ma3, cpi_source
*   cpi_item_crosswalk.csv    (province, cons_name) -> item_group, normalized
*   cpi_panel_validation.txt  the spec section 8 validation report
*
* WHERE IT WRITES
* Output goes to ${tables} -- this file owns the published copies that
* 07_cpi_factor.do reads. THE SWITCHOVER IS DONE: 06_cpi_panel.py is retired to
* dofiles/archive/, dofiles/README.md names this do-file in the run order, and
* master_outcome1.do / master_outcome2.do name it in their step listings.
*
* While the port was being validated ${cpiout} pointed at ${output}/temp/_cpi_port/
* instead, so the two implementations could be diffed without overwriting each
* other's output. That comparison and its one residual difference -- a single
* cpi_ma3 value 1 ULP apart from the Python's -- are in dofiles/archive/README.md.
* The _cpi_port folder is that frozen comparison copy; nothing reads it.
*
* CALLED BY   nothing. Run it on its own, from the dofiles/ folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\06_cpi_panel.do
*
* READS   NSU Market Survey Launch\data\fp_cpi_byprov_byitem_psa_2023_26.csv
*         NSU Market Survey Launch\data\cons_name_to_coicop_crosswalk.csv
*
********************************************************************************
* FOUR CONVENTIONS THAT LOOK LIKE FUSS AND ARE NOT
********************************************************************************
*
* 1. THE CPI COLUMN IS IMPORTED AS A STRING AND PARSED WITH real().
*    `import delimited' picks a storage type by inspecting values, and a float
*    holds only ~7 significant digits where the source carries 16. A float cpi
*    would round 100.4923286732160 to 100.4923 and every ratio built from it
*    would inherit that. stringcols(_all) removes the guess: the digits arrive
*    verbatim and real() turns them into a double. MEASURED, not assumed: over
*    all 5,820 values in the pinned vintage, real() returns the same double a
*    correctly rounded C strtod does. StataCorp documents no such guarantee for
*    real(), so treat that as a property of this input, not of the function.
*
* 2. NUMERIC OUTPUT IS FORMATTED BY A SHORTEST-ROUND-TRIP LADDER, NOT BY %f.
*    See `shortest_g' below. A CPI level written with fewer digits than it
*    carries is a silently different number downstream; written with more, it
*    grows noise digits that were never measured.
*
* 3. EVERY DATA-DRIVEN REPORT LINE IS BUILT AS A VARIABLE AND WRITTEN WITH rlx,
*    never assembled in a macro. Two of the report's lines quote strings with
*    single quotes, and a single quote inside a macro expansion terminates the
*    macro early -- the line would come out truncated, in a validation report,
*    which is the one artifact whose job is to be trusted.
*
* 4. THIS FILE DOES NOT CALL nsu_normalize, DELIBERATELY.
*    nsu_normalize lower-cases, strips non-ASCII and collapses whitespace. It is
*    the right rule for the market-survey join keys it was built for, and the
*    prepped-food collapse below is the same rule in INTENT. It is not called
*    here for two reasons:
*
*      - It would change the ARTIFACT. cons_name and item_group are published
*        columns, and item_group has to keep the non-ASCII "cafe" spelling
*        exactly as PSA issued it; nsu_normalize would strip the accent and
*        lower-case both columns. This file's whole purpose is to reproduce
*        cpi_item_crosswalk.csv as it stands.
*      - There is nothing to gain. The only consumer, 07_cpi_factor.do:285-288,
*        re-normalizes both sides itself (lower + itrim + the restaurant rule)
*        before merging, so the case published here is not load-bearing for any
*        join.
*
*    NOTE FOR ANYONE TEMPTED TO CONSOLIDATE: the reference implementation
*    (06_cpi_panel.py:151-156) justifies the same choice by asserting that
*    cons_name's case IS significant because the join is "on the raw-cased
*    string". That is not true of 07_cpi_factor.do as written -- it lower-cases
*    first. The decision is right; that particular reason for it is not.
*
********************************************************************************

version 19
clear all
set more off

do "00_shared/00_globals.do"

* ---- where things live --------------------------------------------------------
global cpifile "${root}\NSU Market Survey Launch\data\fp_cpi_byprov_byitem_psa_2023_26.csv"
global cwfile  "${root}\NSU Market Survey Launch\data\cons_name_to_coicop_crosswalk.csv"

* Spec section 3.1 pins the vintage by hash. Three files with this stem sit in
* that folder and they differ by up to 930 rows, so the hash is the only thing
* that says which one was read.
global cpisha  "62e938ef119b91dd0e9d5b6badff4eeb17108151d921591dcbfabec9cba0a4be"

* A backslash is safe here because neither following character is `$' or a
* backtick. Written "${output}\${build_name}" the separator would VANISH -- `\$'
* is Stata's escape for a literal dollar sign -- and the folder would be created
* one level up with a mangled name. See the same warning in 00_globals.do.
* WIRED IN. This writes the published CPI panel; 06_cpi_panel.py is retired to
* dofiles/archive/. While the port was being validated this pointed at
* ${output}/temp/_cpi_port/ so the two could be diffed without overwriting the
* reference -- see dofiles/archive/README.md for that comparison and its one residual
* difference, a single cpi_ma3 value 1 ULP apart from the Python's.
global cpiout  "${tables}"
mkdir_missing "${cpiout}"

global outpanel "${cpiout}\cpi_level_panel.csv"
global outcw    "${cpiout}\cpi_item_crosswalk.csv"
global outval   "${cpiout}\cpi_panel_validation.txt"


********************************************************************************
* Helper programs
********************************************************************************

* ---- rl / rlx : write one line of the validation report -----------------------
* The report is one artifact, so it is written through one door. rl takes
* literal text; rlx takes an EXPRESSION evaluated against the data in memory,
* for any line whose content comes from the data.
*
* The newline goes BEFORE the line rather than after it: the file must end
* without a trailing newline, and a leading separator is the only way to
* guarantee that without truncating the file afterwards.
capture program drop rl
program define rl
	args s
	if "${rlstarted}" == "1" file write rp _n
	global rlstarted 1
	file write rp `"`s'"'
	di as txt `"`s'"'
end

capture program drop rlx
program define rlx
	args e
	if "${rlstarted}" == "1" file write rp _n
	global rlstarted 1
	file write rp (`e')
	di as txt (`e')
end

* ---- shortest_g : shortest representation that reads back as the same double --
* Writes `varlist' into a new string variable `generate', choosing the fewest
* significant digits that survive a round trip through real().
*
* WHY A LADDER AND NOT A FIXED FORMAT. A double carries between 1 and 17
* significant decimal digits of information. %21.17g always round-trips but
* pads real measurements with noise (100.492328673216 becomes
* 100.49232867321599); %21.15g is exact for every value in the source file but
* not for a computed mean (157.20000000000002 collapses to 157.2, a different
* number). Trying 15, then 16, then 17 and keeping the first that reads back
* identically gives the shortest exact form in every case.
*
* The trailing ".0" is not cosmetic. A whole-numbered index level must still
* read as a floating-point quantity, and %g drops the decimal point entirely
* (151.0000000000000 becomes "151"). 49 values in the published panel are
* affected -- 38 in cpi and 11 in cpi_ma3, falling on 44 of the 2,250 rows.
*
* ONE KNOWN LIMIT, AND IT IS STATA'S, NOT THIS LADDER'S.
* Stata's number-to-text conversion carries at most 18 significant digits:
* %21.19g and %21.22g both return the same 18-digit string. Any format asking
* for 17 or fewer digits is therefore rounded a SECOND time, from that 18-digit
* intermediate rather than from the double, and where the 18th digit is exactly
* 5 the two roundings can disagree. On this vintage that happens on 4 of 2,250
* cpi_ma3 values, which come out one unit high in the 17th significant digit
* (123.91548786386034 where the correctly rounded form is 123.91548786386033).
*
* THE VALUE IS NOT WRONG -- both spellings parse back to the identical IEEE
* double, verified on all four, so nothing that reads this CSV sees a different
* number. Only the spelling differs, and only where 17 digits are needed.
*
* DO NOT "FIX" THIS BY TRUNCATING INSTEAD OF ROUNDING AT THE 17TH DIGIT. That
* looks like it works -- it repairs all four rows here -- and it is wrong. A
* disagreement is only VISIBLE when the true value sits below the 18-digit
* intermediate; when it sits above, Stata's round-half-up is already the correct
* answer. So the four rows that differ are exactly the ones truncation fixes,
* and truncation would break the rows that currently agree. The only correct
* repair is an exact decimal expansion of the mantissa (Mata big-integer
* arithmetic), which is a large amount of delicate machinery to change the
* spelling of four numbers.
capture program drop shortest_g
program define shortest_g
	syntax varname(numeric), GENerate(name)

	* No explicit str width on either variable. A TYPED `gen' truncates a longer
	* result SILENTLY -- only `replace' auto-promotes -- so the width is left to
	* Stata to infer from the expression.
	quietly {
		gen `generate' = ""
		foreach d in 15 16 17 {
			tempvar cand
			gen `cand' = strtrim(strofreal(`varlist', "%21.`d'g"))
			replace `generate' = `cand' ///
				if `generate' == "" & !missing(`varlist') & real(`cand') == `varlist'
			drop `cand'
		}
		* Not reachable on this vintage, and NOT provably unreachable in general:
		* 17 digits round-trip only when correctly rounded, and the block above
		* records that Stata's conversion is not always correctly rounded. So this
		* is a real tripwire, not a formality -- it stops an unrepresentable value
		* from being exported as an empty field, which would read as a missing CPI.
		count if `generate' == "" & !missing(`varlist')
		if r(N) > 0 {
			local nbad = r(N)
			di as err "shortest_g: `nbad' value(s) had no round-trip representation"
			exit 459
		}
		replace `generate' = `generate' + ".0" ///
			if `generate' != "" & strpos(`generate', ".") == 0 ///
			 & strpos(strlower(`generate'), "e") == 0
	}
end

* ---- pquant : the quantile pandas .describe() reports -------------------------
* Linear interpolation between the two order statistics straddling (n-1)*q --
* NOT Stata's `summarize, detail' percentile, which is a plain order statistic
* and can differ from this by up to one whole observation. The published
* report's p25/p50/p75 are pandas figures, so the comparison only means
* something if the same definition is used.
* SORTS THE DATA. Call it on a throwaway copy.
capture program drop pquant
program define pquant, rclass
	syntax varname(numeric), Q(real)
	tempname res
	quietly {
		sort `varlist'
		count if !missing(`varlist')
		local n  = r(N)
		local h  = (`n' - 1) * `q'
		local lo = floor(`h')
		local fr = `h' - `lo'
		local i1 = `lo' + 1
		local i2 = min(`lo' + 2, `n')
		scalar `res' = `varlist'[`i1'] + `fr' * (`varlist'[`i2'] - `varlist'[`i1'])
	}
	return scalar q = `res'
end

* ---- pad60 : 60 spaces, for left-justifying report columns -------------------
* Stata has no blanks() -- that is Mata -- so column padding is
* substr("${pad60}", 1, n). n is clamped at 0 because Python's "{s:<55s}" never
* TRUNCATES an over-long string, and three of the item_group labels exceed 55
* characters (62, 61 and 58). Padding by ustrlen and not strlen: item_group carries a non-ASCII
* character, so its byte length exceeds its character length and byte padding
* would misalign exactly those rows by one space.
global pad60 = "                                                            "

* ---- ym_str : "YYYY-MM" from a Stata monthly date ----------------------------
capture program drop ym_str
program define ym_str, rclass
	args m
	local yy = 1960 + floor(`m' / 12)
	local mm = 1 + mod(`m', 12)
	return local s = strofreal(`yy') + "-" + cond(`mm' < 10, "0", "") + strofreal(`mm')
end


********************************************************************************
* Open the report
********************************************************************************

macro drop rlstarted
capture file close rp
file open rp using "${outval}", write text replace

rl "=============================================================================="
rl "CPI LEVEL PANEL BUILD -- validation report"
rl "Spec: docs/inflation_adjustment_spec.md"
rl "=============================================================================="


********************************************************************************
* 3.1  Pin the vintage and verify its hash
********************************************************************************
* Stata has no sha256, so this shells out to the OS. Get-FileHash rather than
* certutil: certutil's digest sits on the second line of a message whose wording
* is locale-dependent, while Get-FileHash emits the digest and nothing else.
* Reading a hash is a measurement of an input, not a build step, so a shell call
* here does not reintroduce the language boundary this file exists to remove.

tempfile hashout
shell powershell -NoProfile -Command "(Get-FileHash -Algorithm SHA256 '${cpifile}').Hash" > "`hashout'"

local actualsha ""
capture file close hf
file open hf using "`hashout'", read text
file read hf hline
while r(eof) == 0 {
	local cand = strlower(strtrim(`"`hline'"'))
	if ustrregexm("`cand'", "^[0-9a-f]{64}$") local actualsha "`cand'"
	file read hf hline
}
file close hf

if "`actualsha'" == "" {
	di as err "could not read a sha256 for ${cpifile}"
	file close rp
	exit 601
}

rl ""
rl "## Vintage pinning"
rl "CPI file used: ${cpifile}"
rl "sha256 (expected, from spec): ${cpisha}"
rl "sha256 (actual):              `actualsha'"

if "`actualsha'" != "${cpisha}" {
	rl "*** MISMATCH -- vintage does not match the pinned spec value. ABORTING. ***"
	file close rp
	exit 459
}
rl "Hash MATCHES the pinned vintage in spec section 3.1. Proceeding."


********************************************************************************
* 4.1  Import and normalize the CPI file
********************************************************************************

import delimited using "${cpifile}", varnames(1) stringcols(_all) ///
	encoding("utf-8") clear
* import delimited strips the UTF-8 BOM, so the first name is `geolocation' and
* not a BOM-prefixed variant. Confirmed, not assumed. The variable COUNT is
* checked too: `confirm variable' only tests presence and accepts unique
* abbreviations, so on its own it would pass a file that had grown a column.
confirm variable geolocation commodity year month date cpi
assert c(k) == 6

* The order the rows arrived in. Carried through so the tier-2 dedup below can
* state a tie-break that is a property of the FILE rather than of the sort seed;
* the sort at the end of this block would otherwise destroy it.
gen long src_row = _n

* NO EXPLICIT str WIDTHS. A typed `gen str17 province = ...' truncates a longer
* value SILENTLY -- only `replace' auto-promotes -- and the pinned vintage sits
* exactly at the ceiling: the longest geolocation is 17 bytes and the longest
* commodity is 103. A 104-character PSA label would then be truncated on the CPI
* side but NOT on the crosswalk side, the tier-1 merge would miss, and the cell
* would be quietly filled by a constructed fallback mean while a published
* province figure existed. Letting Stata infer the width removes the failure.
rename geolocation province
replace province = ustrupper(province)
rename commodity item_group
gen int mdate = ym(real(year), real(month))
rename cpi cpi_src
gen double cpi = real(cpi_src)

* real() returns missing for anything unparseable, and a silently dropped price
* level is exactly what a `cap' would hide. A BLANK cpi field is a separate
* case and is deliberately NOT an error here -- it is a missing observation, and
* the coverage ladder is what handles those. See the tier-1 assignment below.
count if missing(cpi) & cpi_src != ""
assert r(N) == 0
* ym() returns missing on an out-of-range month, which the reference's
* (year-1960)*12 + (month-1) arithmetic would silently accept as a valid date.
count if missing(mdate)
assert r(N) == 0

* The COICOP code that opens each item_group label. Derived once, here, because
* the tier 2 and tier 4 fallbacks both pool on it and two definitions of "the
* code" that differ slightly would disagree without anything noticing.
* Untyped again, and here it matters more than it looks: a truncated code is how
* two different commodities come to share one code, which is exactly the
* non-unique key the tier-2 dedup would then have to break arbitrarily.
gen code = strtrim(cond(strpos(item_group, " - ") > 0, ///
	substr(item_group, 1, strpos(item_group, " - ") - 1), item_group))

keep province item_group mdate cpi code src_row
order province item_group mdate cpi code src_row

* A DUPLICATE KEY HALTS. The reference implementation prints a warning and
* carries on, and its left merge then fans the target rows out -- silently
* inflating the panel and giving one (province, item_group, month) cell two
* different CPI levels. There is no correct way to continue, so this stops, with
* the report closed properly rather than left truncated mid-write.
quietly duplicates report province item_group mdate
local ndup = r(N) - r(unique_value)
if `ndup' > 0 {
	rl "*** FATAL: `ndup' duplicate (province,item_group,mdate) rows in the raw CPI file. ***"
	rl "*** The panel key would no longer identify a row. ABORTING.                     ***"
	file close rp
	di as err "`ndup' duplicate (province,item_group,mdate) rows in ${cpifile}"
	exit 459
}

tempfile cpiall
sort province item_group mdate
save `cpiall'


********************************************************************************
* 3.2 / 4.2  Import and normalize the item crosswalk
********************************************************************************
* JOIN KEY IS (province, cons_name), NEVER cons_name ALONE. The crosswalk is
* isid cons_name province: 95 rows over 19 names, because exactly one item's
* group varies by province -- Iloilo has no ice-cream series and falls back to
* the parent sweets category. `merge m:1 cons_name' against this file is an
* r(459), which is what archive/analysis.do:535 does. Do not copy it.

import delimited using "${cwfile}", varnames(1) stringcols(_all) ///
	encoding("utf-8") clear
confirm variable province cons_name item_group

gen long row_order = _n
local n_cw_raw = _N

tempvar tg
egen `tg' = tag(cons_name)
count if `tg'
local n_cons_raw = r(N)
drop `tg'

* The prepped-food collapse and the accent fold, in this order -- the same order
* archive/analysis.do applies them. The replacement string already spells "cafe"
* with an ASCII e, so the accent fold is a no-op on the rows the collapse
* touched and reaches only the others.
*
* Detection is case-insensitive. On the current 95-row crosswalk that changes
* nothing (5 hits either way, 0 rows differ); it hardens against a future
* spelling rather than fixing today's output.
replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" ///
	if strpos(ustrlower(cons_name), "restaurant") > 0
replace cons_name = usubinstr(cons_name, ustrunescape("caf\u00e9"), "cafe", .)

tempvar dd
duplicates tag cons_name province, gen(`dd')
count if `dd' > 0
local isid_bad = r(N)
local isid_ok = cond(`isid_bad' == 0, "True", "False")
drop `dd'

egen `tg' = tag(cons_name)
count if `tg'
local n_cons = r(N)
drop `tg'

egen `tg' = tag(province)
count if `tg'
local n_prov_cw = r(N)
drop `tg'

local n_cw = _N

rl ""
rl "## Item crosswalk"
rl "rows: `n_cw' (raw file had `n_cw_raw')"
rl "distinct cons_name: `n_cons' (raw file had `n_cons_raw')"
rl "distinct province: `n_prov_cw'"
rl "isid cons_name province holds: `isid_ok'"
if `isid_bad' > 0 {
	rl "*** WARNING: crosswalk is not unique on (cons_name, province) after normalization ***"
}

tempfile cwclean
sort row_order
save `cwclean'

* ---- which item_group values are not used by every province -------------------
* Confirms the one documented province-varying item empirically rather than
* asserting it.
keep item_group province
duplicates drop
bysort item_group (province): gen int nprov = _N
by item_group: gen plist = "'" + province + "'" if _n == 1
by item_group: replace plist = plist[_n-1] + ", '" + province + "'" if _n > 1
by item_group: keep if _n == _N
keep if nprov < `n_prov_cw'
sort item_group
local n_varying = _N
gen rline = "  - '" + item_group + "': used by [" + plist + "]"

rl "item_group values not used by all `n_prov_cw' provinces: `n_varying'"
forvalues i = 1/`n_varying' {
	rlx "rline[`i']"
}

* ---- the crosswalk artifact ---------------------------------------------------
* Written in the source file's row order, which is what the reference
* implementation's order-preserving to_csv produces.
use `cwclean', clear
sort row_order
drop row_order
order province cons_name item_group
export delimited using "${outcw}", replace


********************************************************************************
* The target grid
********************************************************************************
* The (province, item_group) pairs the crosswalk actually needs, crossed with
* every month in the CPI file. Building the grid FIRST and then filling it is
* what makes a missing cell visible: filling straight from the CPI file would
* report complete coverage of whatever happened to be in it.

use `cpiall', clear
keep mdate
duplicates drop
sort mdate
local n_months = _N
local mo_min = mdate[1]
local mo_max = mdate[_N]
tempfile months
save `months'

use `cwclean', clear
keep province item_group row_order
* FIRST-APPEARANCE ORDER, not sorted order. `duplicates drop' would re-sort and
* lose it. The reference builds its grid from a pandas drop_duplicates(), which
* keeps the crosswalk file's own order, and that order is what its UNRESOLVED
* listing comes out in -- the one report section whose sequence is not otherwise
* pinned. The crosswalk file is NOT sorted by (province, item_group), so the two
* orders genuinely differ.
bysort province item_group (row_order): keep if _n == 1
sort row_order
gen long pair_order = _n
drop row_order
local n_pairs = _N

tempvar tg2
egen `tg2' = tag(item_group)
count if `tg2'
local n_grp_needed = r(N)
drop `tg2'
egen `tg2' = tag(province)
count if `tg2'
local n_prov_needed = r(N)
drop `tg2'

tempfile pairs
save `pairs'

cross using `months'
local n_target = _N

ym_str `mo_min'
local ym_min "`r(s)'"
ym_str `mo_max'
local ym_max "`r(s)'"
local full_cross = `n_prov_needed' * `n_grp_needed'
local ragged = `full_cross' - `n_pairs'

rl ""
rl "## Target panel grid"
rl "needed (province, item_group) pairs from crosswalk: `n_pairs'"
rl "distinct item_group values needed: `n_grp_needed'"
rl "months in CPI file: `n_months' (`ym_min' to `ym_max')"
rl "target rows (pairs x months): `n_target'"
rl "full province x item_group rectangle would be `n_prov_needed' x `n_grp_needed' = `full_cross' pairs; actual pairs = `n_pairs' (ragged by `ragged', expected -- see ice cream exception above)"

tempfile target
sort pair_order mdate
save `target'


********************************************************************************
* 5.  Coverage ladder
********************************************************************************
* Every filled cell records which tier filled it, so a constructed fallback can
* never pass itself off downstream as a published province-level figure.
*
* Tiers 2-4 are written out in full even though the current vintage resolves
* everything at tier 1. Coverage is only *believed* complete (spec section 5),
* and a ladder that exists on paper but not in code would leave the next vintage
* silently dropping cells instead of falling back.

tempfile ladder

* ---- tier 1: province x exact COICOP group ------------------------------------
use `target', clear
merge 1:1 province item_group mdate using `cpiall', keepusing(cpi)
drop if _merge == 2
* A MATCH IS NOT ENOUGH -- the matched cpi must also be non-missing. A blank cpi
* field in the source matches on the key but carries no level, and stamping it
* tier 1 would publish a missing value labelled as a published province figure
* and skip the fallbacks that exist for exactly that case. The reference keys
* tier 1 off cpi.notna() for the same reason.
gen byte tier = 1 if _merge == 3 & !missing(cpi)
drop _merge

gen code = strtrim(cond(strpos(item_group, " - ") > 0, ///
	substr(item_group, 1, strpos(item_group, " - ") - 1), item_group))
gen parent_code = cond(strpos(code, ".") > 0, ///
	substr(code, 1, strrpos(code, ".") - 1), "")
save `ladder'

* ---- tier 2: province x parent COICOP group -----------------------------------
count if missing(tier)
if r(N) > 0 {
	tempfile plook
	use `cpiall', clear
	rename code parent_code
	rename cpi  cpi_t2
	keep province parent_code mdate cpi_t2 src_row
	* THE TIE-BREAK IS src_row, NOT ROW ORDER. On this vintage every commodity
	* has its own code, so the key is already unique and the dedup is a no-op.
	* It stops being a no-op the moment two labels share a code, and then
	* `bysort ...: keep if _n == 1' WITHOUT an explicit sort variable keeps
	* whichever row the sort seed happened to place first -- reproducible,
	* because 00_globals.do pins the seed, but arbitrary, and different from the
	* reference, which keeps the first row in CPI-FILE order. src_row is that
	* order, carried down from the import for this one purpose.
	bysort province parent_code mdate (src_row): keep if _n == 1
	drop src_row
	save `plook'

	use `ladder', clear
	merge m:1 province parent_code mdate using `plook', keep(master match) nogen
	replace cpi  = cpi_t2 if missing(tier) & !missing(cpi_t2)
	replace tier = 2      if missing(tier) & !missing(cpi_t2)
	drop cpi_t2
	save `ladder', replace
}

* ---- tier 3: national x exact group -------------------------------------------
* The extract carries no PSA national row, so a national figure has to be
* CONSTRUCTED -- the unweighted mean across the provinces present. Unweighted
* because the extract carries no population or expenditure weights; a
* province-count mean is not PSA's national index, and the tier label is what
* keeps that distinction visible downstream.
use `ladder', clear
count if missing(tier)
if r(N) > 0 {
	tempfile nat
	use `cpiall', clear
	collapse (mean) cpi_t3 = cpi, by(item_group mdate)
	save `nat'

	use `ladder', clear
	merge m:1 item_group mdate using `nat', keep(master match) nogen
	replace cpi  = cpi_t3 if missing(tier) & !missing(cpi_t3)
	replace tier = 3      if missing(tier) & !missing(cpi_t3)
	drop cpi_t3
	save `ladder', replace
}

* ---- tier 4: all-food ---------------------------------------------------------
* Also constructed: the unweighted mean, per province and month, across every
* food-coded (leading "01") commodity in the extract.
local do_t4 0
use `ladder', clear
count if missing(tier)
if r(N) > 0 {
	tempfile allfood
	use `cpiall', clear
	keep if substr(code, 1, 2) == "01"
	* `collapse' on zero observations is r(2000), not an empty result. Without
	* this guard a vintage carrying no food-coded commodity would ABORT here
	* instead of leaving the cells UNRESOLVED and listing them, which is what
	* the ladder is supposed to do when it runs out of tiers.
	if _N > 0 {
		collapse (mean) cpi_t4 = cpi, by(province mdate)
		save `allfood'
		local do_t4 1
	}
}
if `do_t4' == 1 {
	use `ladder', clear
	merge m:1 province mdate using `allfood', keep(master match) nogen
	replace cpi  = cpi_t4 if missing(tier) & !missing(cpi_t4)
	replace tier = 4      if missing(tier) & !missing(cpi_t4)
	drop cpi_t4
	save `ladder', replace
}

* ---- report the ladder --------------------------------------------------------
use `ladder', clear
drop code parent_code

rl ""
rl "## Coverage ladder results"
local n_tier1 = 0
foreach t in 1 2 3 4 {
	if `t' == 1 local lbl "tier1_province_exact_group"
	if `t' == 2 local lbl "tier2_province_parent_group"
	if `t' == 3 local lbl "tier3_national_group"
	if `t' == 4 local lbl "tier4_all_food"
	count if tier == `t'
	local nt = r(N)
	if `t' == 1 local n_tier1 = `nt'
	rl "  `lbl': `nt' rows"
}
count if missing(tier)
local n_unres = r(N)
rl "  UNRESOLVED (present in no tier): `n_unres' rows"

if `n_unres' > 0 {
	rl "  Full list of unresolved (province, item_group, month) cells:"
	tempfile withtier
	save `withtier'
	keep if missing(tier)
	* pair_order, not (province, item_group): see the grid block above.
	sort pair_order mdate
	gen rline = "    - " + province + " | " + item_group + " | " ///
		+ strofreal(1960 + floor(mdate / 12)) + "-" ///
		+ cond(1 + mod(mdate, 12) < 10, "0", "") + strofreal(1 + mod(mdate, 12))
	forvalues i = 1/`n_unres' {
		rlx "rline[`i']"
	}
	use `withtier', clear
}
else if `n_tier1' == _N {
	rl "  Coverage is empirically COMPLETE at tier 1 for all needed cells."
	rl "  Tiers 2-4 were not exercised on this vintage -- confirmed empty, not merely assumed."
}
else {
	* THE CONDITION ON THIS BRANCH IS THE POINT. The reference implementation
	* printed the "complete at tier 1" claim whenever nothing was UNRESOLVED,
	* which is not the same test: a vintage filled partly by constructed
	* national or all-food means would have been reported as fully covered by
	* published province-level figures. Verified by punching holes in the
	* extract -- tiers 2, 3 and 4 each supplied rows and the report still said
	* they were "not exercised". On the current vintage tier 1 does supply every
	* row, so this branch is silent and the file above is unchanged.
	local n_fallback = _N - `n_tier1'
	rl "  Coverage is COMPLETE, but NOT at tier 1 alone -- `n_tier1' of `=_N' cells came from"
	rl "  tier 1 and `n_fallback' from a fallback tier. Tier 3 and tier 4 figures are CONSTRUCTED"
	rl "  means, not published province-level series; cpi_source says which is which."
}

* The ladder must not have changed the grid's row count. Every merge above is
* 1:1 or m:1 with keep(master match), so an extra row would mean a using file
* was not unique on its key -- the one way this block could silently duplicate
* a cell. Derivation: n_target = n_pairs x n_months, computed in the grid block.
assert _N == `n_target'

* Unmatched cells are listed above and then dropped, not carried as missing --
* a missing cpi in the panel is indistinguishable from a zero-priced item to
* anything that reads it.
drop if missing(tier)

gen cpi_source = ""
replace cpi_source = "tier1_province_exact_group"  if tier == 1
replace cpi_source = "tier2_province_parent_group" if tier == 2
replace cpi_source = "tier3_national_group"        if tier == 3
replace cpi_source = "tier4_all_food"              if tier == 4
assert cpi_source != ""
drop tier


********************************************************************************
* 4.3  cpi_ma3 -- 3-month CENTRED moving average of the LEVEL
********************************************************************************
* ENDPOINT HANDLING IS EXPLICIT, per spec section 4.3: the first and last month
* of each series get MISSING cpi_ma3, not a shrunk 2-point window. A 2-point
* average at an edge is a different statistic from the interior 3-point average,
* and mixing them changes what the column means from month to month without
* saying so.
*
* ADJACENCY IS TESTED ON THE MONTH, NOT THE ROW -- mdate[_n-1] == mdate - 1
* rather than "a row exists before this one". If a series ever loses a month,
* row adjacency would quietly average across the hole and still call the result
* a 3-month average. The current vintage has no holes, which is precisely why
* the guard has to be written rather than observed.
*
* Summed left to right in double precision. The reference writes
* np.mean([prev, cur, next]), which at n = 3 reduces to ((prev + cur) + next)/3
* -- an implementation detail of numpy's add.reduce, not a contract it states.
* Verified bit-for-bit against the published panel on all 2,175 interior rows
* (identical hex mantissas), so the agreement is measured, not assumed.
*
* mdate is deliberately NOT given a %tm display format here, though spec 4.1
* asks for one. `export delimited' can render a numeric through its display
* format, and the published panel carries the bare month integer (767, not
* 2023m12). 07_cpi_factor.do applies its own format after reading.
sort province item_group mdate
by province item_group: gen double cpi_ma3 = (cpi[_n-1] + cpi[_n] + cpi[_n+1]) / 3 ///
	if _n > 1 & _n < _N & mdate[_n-1] == mdate - 1 & mdate[_n+1] == mdate + 1

gen year_month = strofreal(1960 + floor(mdate / 12)) + "-" ///
	+ cond(1 + mod(mdate, 12) < 10, "0", "") + strofreal(1 + mod(mdate, 12))

keep province item_group mdate year_month cpi cpi_ma3 cpi_source
order province item_group mdate year_month cpi cpi_ma3 cpi_source
sort province item_group mdate

tempfile panelnum
save `panelnum'


********************************************************************************
* The panel artifact
********************************************************************************
* cpi and cpi_ma3 are exported as the strings shortest_g produced, not as
* numerics: `export delimited' would otherwise render a double through a display
* format and silently truncate the level. See convention 2 in the header.

use `panelnum', clear
shortest_g cpi,     generate(cpi_s)
shortest_g cpi_ma3, generate(cpi_ma3_s)
drop cpi cpi_ma3
rename cpi_s     cpi
rename cpi_ma3_s cpi_ma3
order province item_group mdate year_month cpi cpi_ma3 cpi_source
sort province item_group mdate
export delimited using "${outpanel}", replace


********************************************************************************
* 8.  Validation
********************************************************************************

use `panelnum', clear

* ---- panel dimensions --------------------------------------------------------
tempvar tg3
egen `tg3' = tag(province)
count if `tg3'
local n_prov = r(N)
drop `tg3'
egen `tg3' = tag(item_group)
count if `tg3'
local n_grp = r(N)
drop `tg3'
egen `tg3' = tag(mdate)
count if `tg3'
local n_mo = r(N)
drop `tg3'

local n_rows = _N
local rect = `n_prov' * `n_grp' * `n_mo'

bysort province item_group (mdate): gen int pairn = _N
by province item_group: gen byte pairtag = (_n == 1)
quietly summarize pairn if pairtag
local pmin = r(min)
local pmax = r(max)
local balanced = cond(`pmin' == `n_mo' & `pmax' == `n_mo', "True", "False")
drop pairn pairtag

rl ""
rl "## Panel dimensions"
rl "provinces: `n_prov'  |  item_groups: `n_grp'  |  months: `n_mo'"
rl "rows: `n_rows'  (would be `rect' if it were a full province x item_group x month rectangle)"
rl "balanced across time within every included (province,item_group) pair: `balanced' (every included pair has exactly `n_mo' months, min=`pmin', max=`pmax')"
rl "NOT a full province x item_group rectangle: `n_pairs' of `full_cross' possible pairs present -- the `ragged' missing pair(s) are the documented ice-cream exception (item_group varies by province for that one cons_name), not a data gap."

* ---- cpi distribution --------------------------------------------------------
quietly summarize cpi
local cmin = r(min)
local cmax = r(max)
count if missing(cpi)
local n_cmiss = r(N)
count if cpi == 0
local n_czero = r(N)
count if cpi < 0
local n_cneg = r(N)

pquant cpi, q(0.25)
local p25 = r(q)
pquant cpi, q(0.50)
local p50 = r(q)
pquant cpi, q(0.75)
local p75 = r(q)

local s_min = strtrim(strofreal(`cmin', "%21.4f"))
local s_p25 = strtrim(strofreal(`p25',  "%21.4f"))
local s_p50 = strtrim(strofreal(`p50',  "%21.4f"))
local s_p75 = strtrim(strofreal(`p75',  "%21.4f"))
local s_max = strtrim(strofreal(`cmax', "%21.4f"))

rl ""
rl "## cpi distribution"
rl "min=`s_min'  p25=`s_p25'  p50=`s_p50'  p75=`s_p75'  max=`s_max'"
rl "missing cpi: `n_cmiss'  |  zero cpi: `n_czero'  |  negative cpi: `n_cneg'"

* Halt, do not warn. A missing, zero or negative index level makes every ratio
* built from this panel either undefined or sign-flipped, and the failure would
* surface a long way downstream as an implausible weight.
assert `n_cmiss' == 0
assert `n_czero' == 0
assert `n_cneg'  == 0
rl "ASSERTIONS PASSED: cpi is never missing, zero, or negative."

* ---- counts per tier, on the final panel -------------------------------------
use `panelnum', clear
rl ""
rl "## Counts per cpi_source tier (repeat, on final panel)"
foreach lbl in tier1_province_exact_group tier2_province_parent_group ///
	tier3_national_group tier4_all_food {
	count if cpi_source == "`lbl'"
	local nl = r(N)
	rl "  `lbl': `nl'"
}

* ---- month-on-month moves ----------------------------------------------------
* True adjacent months only, for the same reason cpi_ma3 tests the month rather
* than the row: a gap would otherwise be reported as a one-month move.
sort province item_group mdate
by province item_group: gen double cpi_lag = cpi[_n-1]
by province item_group: gen int mdate_lag  = mdate[_n-1]
keep if mdate == mdate_lag + 1
gen double pct_change = (cpi - cpi_lag) / cpi_lag * 100
gen double apc = abs(pct_change)

tempfile momfile
save `momfile'

gen rline = "  " ///
	+ province   + substr("${pad60}", 1, max(0, 20 - ustrlen(province)))   + " " ///
	+ item_group + substr("${pad60}", 1, max(0, 55 - ustrlen(item_group))) + " " ///
	+ strofreal(1960 + floor(mdate_lag / 12)) + "-" ///
	  + cond(1 + mod(mdate_lag, 12) < 10, "0", "") + strofreal(1 + mod(mdate_lag, 12)) ///
	+ "->" ///
	+ strofreal(1960 + floor(mdate / 12)) + "-" ///
	  + cond(1 + mod(mdate, 12) < 10, "0", "") + strofreal(1 + mod(mdate, 12)) ///
	+ "  " + cond(pct_change >= 0, "+", "") ///
	+ strtrim(strofreal(pct_change, "%21.1f")) + "%"

gsort -apc
rl ""
rl "## Top 10 largest month-on-month moves (level pct change within a series)"
forvalues i = 1/10 {
	if `i' <= _N {
		rlx "rline[`i']"
	}
}

* ---- index integrity for ratio use -------------------------------------------
local i_min = strtrim(strofreal(`cmin', "%21.1f"))
local i_max = strtrim(strofreal(`cmax', "%21.1f"))

rl ""
rl "## Index integrity for ratio use"
rl "Fixed-base level check: PSA CPI series by construction are fixed-base index levels"
rl "(base period re-referenced to 100), not year-on-year rates -- consistent with the"
rl "observed range here (min=`i_min' .. max=`i_max', centred near 100,"
rl "not near 0 the way a y/y growth rate would be)."
rl ""
rl "Base-break check at the 2026 boundary (2025m12 -> 2026m1):"

local bnd = ym(2026, 1)

use `momfile', clear
keep if mdate == `bnd'
local n_bnd = _N
pquant pct_change, q(0.50)
local med_bnd = r(q)

use `momfile', clear
keep if mdate != `bnd'
local n_oth = _N
pquant pct_change, q(0.50)
local med_oth = r(q)

local s_bnd = strtrim(strofreal(`med_bnd', "%21.2f"))
local s_oth = strtrim(strofreal(`med_oth', "%21.2f"))

rl "  median m/m %% change at 2025m12->2026m1: `s_bnd'%  (n=`n_bnd')"
rl "  median m/m %% change at all other transitions: `s_oth'%  (n=`n_oth')"
if abs(`med_bnd') <= abs(`med_oth') + 2 {
	rl "  Interpretation: no visible base break -- boundary move is in line with (or smaller than) the typical move."
}
else {
	rl "  Interpretation: boundary move is notably larger than typical -- inspect for a base break."
}

* ---- how far cpi_ma3 departs from cpi, by group ------------------------------
use `panelnum', clear
keep if !missing(cpi_ma3)
* A vintage with fewer than three months leaves every cpi_ma3 missing, and
* `collapse' on zero observations is r(2000). Without this guard the file would
* abort here -- AFTER both CSVs are on disk -- where the reference simply prints
* an empty section.
local n_dep = 0
if _N > 0 {
	gen double abs_pct_dev = abs(cpi_ma3 - cpi) / cpi * 100
	collapse (mean) dmean = abs_pct_dev (max) dmax = abs_pct_dev, by(item_group)
	gsort -dmean
	gen rline = "  " ///
		+ item_group + substr("${pad60}", 1, max(0, 55 - ustrlen(item_group))) ///
		+ " mean |cpi_ma3 - cpi| / cpi = " + strtrim(strofreal(dmean, "%21.2f")) ///
		+ "%   max = " + strtrim(strofreal(dmax, "%21.2f")) + "%"
	local n_dep = _N
}

rl ""
rl "## cpi_ma3 departure from cpi, by item_group"
forvalues i = 1/`n_dep' {
	rlx "rline[`i']"
}

use `panelnum', clear
count if missing(cpi_ma3)
local n_ma3_miss = r(N)
local expect_miss = 2 * `n_pairs'
local n_panel = _N

* The PRINTED figure uses the crosswalk's pair count, because that is what the
* reference prints. The ASSERTED figure below must not: if a whole pair's cells
* were all unresolved and dropped, the panel holds fewer pairs than the
* crosswalk asked for, and 2 x n_pairs is then simply the wrong number.
tempvar tgp
egen `tgp' = tag(province item_group)
count if `tgp'
local n_panel_pairs = r(N)
drop `tgp'

rl ""
rl "cpi_ma3 missing at series endpoints (documented, not shrunk): `n_ma3_miss' rows out of `n_panel' (expect 2 per (province,item_group) series x `n_pairs' series = `expect_miss')"

* The endpoint count is derivable from the panel's own shape, so it is asserted
* rather than merely printed -- but only where it IS derivable. "2 per series"
* holds when every series runs a full contiguous span of months; once a month is
* missing from a series the true count is higher, and a bare assert would halt
* on a panel whose gaps the report has already listed in full. Two conditions,
* not one: the panel must be balanced AND must still carry every pair the
* crosswalk asked for. The balance flag alone does not catch a lost pair --
* it compares each SURVIVING pair against the panel's own month count.
if "`balanced'" == "True" & `n_panel_pairs' == `n_pairs' {
	assert `n_ma3_miss' == 2 * `n_panel_pairs'
}

rl ""
rl "## Vintage hash (repeat)"
rl "sha256(fp_cpi_byprov_byitem_psa_2023_26.csv) = `actualsha'"

rl ""
rl "## Files written"
rl "  ${outpanel}"
rl "  ${outcw}"
rl "  ${outval}"

file close rp

di as txt ""
di as txt "Wrote ${outpanel}"
di as txt "Wrote ${outcw}"
di as txt "Wrote ${outval}"
