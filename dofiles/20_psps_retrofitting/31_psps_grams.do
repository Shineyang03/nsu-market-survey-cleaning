********************************************************************************
* 31_psps_grams.do -- the single household-level PSPS grams deliverable
*
* WHAT THIS OWNS. The thing this project exists to produce -- grams for a PSPS
* household consumption row -- has had no single artefact and no non-Stata export.
* It has been split across two files with NO OVERLAP:
*
*   ${bdeliv}\psps_converted_capped.dta   35,448 rows, 74 vars   29 -- NSU rows,
*                                        grams via the market survey, capped
*   ${bdeliv}\psps_standard_units.dta     52,489 rows, 23 vars   27 -- grams from
*                                        the unit's own name, no market-survey input
*
* This file appends the two into one household x item x slot table and adds the
* THIRD population that belongs beside them and has shipped in neither: the 22 rows
* at conv_path == 3 (20a_psps_households.do sec. 10) -- labels that reach the
* crosswalk join but that 02_drop_non_nsu_labels.py judged not to be an NSU at all
* (a bundled count-and-price, a stated standard quantity written as free text, or
* plain non-unit text). They have no grams and never will; carrying them WITH that
* stated, rather than dropping them again, is what makes 87,959 -- the row count
* 20a's own tripwire and the attrition ledger both use -- the total this file
* reconciles to, not 87,937.
*
* ==============================================================================
* THE GRAIN. hhid x psps_item_code x slot, asserted with `isid'. It is the same
* grain as psps_households.dta, and hh_row -- assigned once there, before any
* branching -- is carried through unchanged as a stable single-column key into the
* same id space.
*
* ==============================================================================
* THE APPEND-FILLS-MISSING HAZARD, audited column by column
*
* `append' fills an absent source column with system missing, SILENTLY. A missing
* flag then reads as "false" in most summaries, which is indistinguishable from a
* considered "no". Every column below that does not exist on all three sources was
* checked against that failure mode, not just d_converted:
*
*   d_converted    DOES NOT EXIST on psps_standard_units.dta -- every row there has
*                  grams by construction (27_standard_units.do converts the whole
*                  file with no refusal branch). Set to 1 explicitly, and to 0 for
*                  the conv_path==3 rows, which never reach a conversion attempt at
*                  all. Cross-checked below against grams_h.
*   conv_path      DOES NOT EXIST on psps_standard_units.dta either --
*                  27_standard_units.do's own first line is `keep if conv_path==1',
*                  so every row already IS path 1; restated here as a column.
*   fallback_level and d_cap  exist on psps_standard_units.dta already, written as
*                  constants for the same reason (27's own header explains it): 0 and
*                  0, "nothing to borrow, nothing to cap". Restated explicitly for
*                  the conv_path==3 rows too, matching how 28_match_and_convert.do
*                  itself treats an unconverted row -- d_cap is 0 (never capped) on
*                  every refusal route including there, so 0 here is not a guess,
*                  it is the pipeline's own convention; fallback_level stays MISSING,
*                  matching how 28 leaves it missing on "refused: A11 spelling gap"
*                  and "refused: unique price" -- no rung ever fired, so there is no
*                  rung to name. Verified against the live build in section 2.
*   n_g_used, nu_used, share_uncertain   DO NOT EXIST on psps_standard_units.dta at
*                  all, and per docs/implicit_assumptions.md A20 and the task this
*                  file was written against, THEY MUST STAY MISSING THERE, NOT ZERO:
*                  a standard-unit row's grams come from a stated container size, not
*                  a market-survey weighing, so there is no weighing to have
*                  questioned. A zero would assert something about an empty set.
*                  Left absent through section 2 and asserted missing in section 5.
*   d_no_price     EXISTS on psps_converted_capped.dta already, but it is NOT carried
*                  from there -- see the note in section 1. It is recomputed once,
*                  after the append, from p_h alone, which every source carries.
*   share_uncertain likewise is recomputed once after the append from nu_used and
*                  n_g_used, rather than carried from psps_converted_capped.dta,
*                  so ONE formula produces it regardless of which source a row
*                  came from.
*
* ==============================================================================
* A HAZARD FOUND IN THE UPSTREAM BUILD, NOT INTRODUCED HERE, AND WORKED AROUND
*
* psps_converted_capped.dta's OWN `d_no_price' column already carries exactly this
* failure mode, inherited from 28_match_and_convert.do's internal structure rather
* than from anything this file does: `d_no_price' is computed on the joinby'd rows
* in section 4, BEFORE the households whose case had no usable group at all are
* appended back in section 6 (the `nocase' population, 30_fallback.do's territory).
* Those appended rows never get `d_no_price' set, so it arrives as missing rather
* than as 1 -- even though most of them genuinely have no faced price. Measured
* directly against the live build: of the 11,809 rows with `p_h' missing (own
* production 10,187, gift 1,606, purchased-but-unpriced 16 -- A10's own figures,
* reproduced exactly), 2,135 carry `d_no_price' missing rather than 1.
*
* THIS FILE DOES NOT CARRY THAT COLUMN FORWARD. `d_no_price' is recomputed here,
* once, as `missing(p_h)' -- the same formula 28 uses, applied uniformly to every
* row regardless of source -- so this deliverable does not re-ship a gap that
* already exists one file upstream. 28_match_and_convert.do is not modified: it is
* out of this file's scope, and out of this task's.
*
* ==============================================================================
* INPUTS  ${bdeliv}\psps_converted_capped.dta   29 -- NSU rows (conv_path 2)
*         ${bdeliv}\psps_standard_units.dta     27 -- standard-unit rows (conv_path 1)
*         ${btemp}\psps_households.dta         20a -- conv_path == 3 rows only
* OUTPUTS ${bdeliv}\psps_grams.dta
*         ${bdeliv}\psps_grams.csv            header row is VARIABLE LABELS, not
*                                               names -- see section 6
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\31_psps_grams.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

local keyvars hhid psps_item_code slot


********************************************************************************
**# 1. NSU rows -- converted (or refused) via the market survey (28, 29)
********************************************************************************
* d_no_price is NOT kept from this file -- see the header note above. Recomputed
* uniformly in section 4 instead.

use "${bdeliv}\psps_converted_capped", clear
qui count
local n_nsu = r(N)
di as res _n "NSU rows (market-survey branch, conv_path 2): `n_nsu'"

* THE _blind COLUMNS RIDE ALONG on the NSU rows only, and are missing everywhere else by
* construction: a standard-unit row never used an NSU conversion, so there is no
* hetero-blind counterfactual for it to have. 28_match_and_convert.do section 6b builds
* them; the standalone deliverable at the end of this file is written from them.
keep hh_row hhid psps_item_code slot source ///
     pull_province pull_municipal_city pull_item pull_nsu_unit harmonized_nsu_unit ///
     q_h p_h cf_h grams_h conv_path conv_route d_converted fallback_level d_cap ///
     n_g_used nu_used ///
     cf_h_blind grams_h_blind dim_blind fallback_level_blind conv_route_blind ///
     n_g_used_blind nu_used_blind d_converted_blind

isid `keyvars'
tempfile nsu
save "`nsu'"


********************************************************************************
**# 2. Standard-unit rows -- grams from the unit's own name (27)
********************************************************************************
* See the header note: d_converted and conv_path do not exist on this file and are
* stated explicitly rather than left for the append to fill in.

use "${bdeliv}\psps_standard_units", clear
qui count
local n_std = r(N)
di as res _n "standard-unit rows (conv_path 1, no market-survey input): `n_std'"

* NOT labeled here. `append' keeps the MASTER's (section 1's) variable label where
* one already exists, so a `label var' written on this tempfile would be silently
* discarded the moment it is appended under psps_converted_capped.dta's rows --
* verified directly against this Stata install before relying on it. The single
* authoritative label for every appended column is set once, in section 4, after
* the append -- which is the only point at which a `label var' call is guaranteed
* to stick regardless of which source a row came from.
gen byte d_converted = 1
gen byte conv_path = 1

* fallback_level and d_cap already exist on this file, already 0/0 -- 27_standard_
* units.do sets them itself, "written as constants so the columns line up with 28's
* output on append" (its own words). Verified, not re-set:
assert fallback_level == 0
assert d_cap == 0

* n_g_used, nu_used and share_uncertain are left ABSENT here -- not generated and
* not zeroed. See the header note and A20: no weighing stands behind a stated
* container size, so there is nothing for these three to count.

keep hh_row hhid psps_item_code slot source ///
     pull_province pull_municipal_city pull_item pull_nsu_unit harmonized_nsu_unit ///
     q_h p_h cf_h grams_h conv_path conv_route d_converted fallback_level d_cap

isid `keyvars'
tempfile std
save "`std'"


********************************************************************************
**# 3. conv_path == 3 -- reaches the crosswalk join, but is not an NSU at all
********************************************************************************
* 02_drop_non_nsu_labels.py's own three reasons (`drop_reason') say why: a bundled
* count-and-price ("2 kapinutos nga cabbage/20pesos"), a stated standard quantity
* written as free text ("1/2 sack of rice (25kls.)"), or plain non-unit text ("he
* buy cooked food for his meals"). None of the three names a recoverable unit size,
* so none of the three deliverables above can give these rows grams -- not now, not
* with a different fallback rung, not ever. Carrying them here WITH THAT STATED is
* the alternative to the thing that would otherwise happen: they simply disappear
* from every count downstream of the household file, indistinguishable from a
* build that dropped 22 rows by accident.

use "${btemp}\psps_households", clear
keep if conv_path == 3
qui count
local n_path3 = r(N)
di as res _n "conv_path == 3 rows (not an NSU; no grams possible): `n_path3'"

assert `n_path3' == 22
assert conv_path == 3
assert missing(harmonized_nsu_unit)

gen double cf_h    = .
gen double grams_h = .
gen byte   d_converted = 0

* Neither branch's convention fits perfectly, so the closer precedent is chosen
* explicitly rather than left to an accident of append order:
*   d_cap = 0            -- matches 28/29's own convention that d_cap is 0 (never
*                           capped) on EVERY row, including every refusal route.
*   fallback_level = .   -- matches 28's OWN treatment of a refusal that never
*                           reached the fallback ladder ("refused: A11 spelling
*                           gap", "refused: unique price"): missing, not 0, because
*                           no rung ever fired. These rows never even reach the
*                           market-survey lookup, so the same logic applies harder.
* Not labeled here -- see the note in section 2: a `label var' on this tempfile
* would not survive the append. Section 4 sets the authoritative label.
gen byte d_cap = 0
gen byte fallback_level = .

gen str48 conv_route = "refused: not an NSU (" + drop_reason + ")"

* n_g_used / nu_used are left ABSENT, same reasoning as section 2: nothing was ever
* weighed for a label that is not an NSU.

keep hh_row hhid psps_item_code slot source ///
     pull_province pull_municipal_city pull_item pull_nsu_unit harmonized_nsu_unit ///
     q_h p_h cf_h grams_h conv_path conv_route d_converted fallback_level d_cap

isid `keyvars'
tempfile path3
save "`path3'"


********************************************************************************
**# 4. Append, and the two columns given ONE definition each across all sources
********************************************************************************

use "`nsu'", clear
append using "`std'"
append using "`path3'"

qui count
local n_all = r(N)
di as res _n "appended rows: `n_all'"

* THE RECONCILIATION. 20a_psps_households.do's own tripwire, and the attrition
* ledger (#8), both rest on 87,959 household x item x slot rows. 35,448 + 52,489
* is 87,937 -- the two files this build already shipped -- and it is 22 SHORT of
* that, not equal to it. The 22 are conv_path == 3, carried in section 3.
if `n_all' != 87959 {
	di as err "Appended row count is `n_all', not 87,959."
	di as err "Reconcile against 20a_psps_households.do's own tripwire and the"
	di as err "attrition ledger (90_diagnostics/attrition_ledger.do) before editing this."
	exit 459
}

isid `keyvars'
isid hh_row

* ---- d_no_price: ONE formula, applied uniformly ------------------------------
* Not carried from psps_converted_capped.dta -- see the header note on why that
* column cannot be trusted as-is. p_h exists on every source and means the same
* thing on all three (20a section 9): the purchased-slot price, missing on every
* other acquisition route and on the 16 purchased rows with no usable price.
gen byte d_no_price = missing(p_h)
label var d_no_price "1 = no computable unit value on this row (e_h or q_h absent)"

* ---- share_uncertain: ONE formula, applied uniformly --------------------------
* Missing wherever either input is missing -- which is every conv_path 1 and 3 row,
* and every refused conv_path 2 row -- by ordinary division, with no `if' needed.
gen double share_uncertain = nu_used / n_g_used
format share_uncertain %5.3f
label var share_uncertain "nu_used / n_g_used; missing where no weighing stands behind cf_h"

label var hh_row               "row id; same id space as hh_row in psps_households.dta"
label var hhid                 "household identifier"
label var psps_item_code       "PSPS item code"
label var slot                 "acquisition slot: 2 purchased, 3 own production, 4 gift"
label var source               "acquisition route: purchased, own_production, or gift"
label var pull_province        "province"
label var pull_municipal_city  "municipality"
label var pull_item            "food item"
label var pull_nsu_unit        "unit as the household reported it"
label var harmonized_nsu_unit  "harmonized market-survey unit; blank where none applies"
label var q_h                  "quantity reported, in the unit named by pull_nsu_unit"
label var p_h                  "implied unit value, PHP per unit; all acquisition modes (A10)"
label var cf_h                 "grams (or mL) per unit for this household's row"
label var grams_h              "q_h * cf_h; total grams for this row; missing if not converted"
label var conv_path            "20a conversion path: 1 standard unit, 2 NSU, 3 not an NSU"
label var conv_route           "how this row got its grams, or why it did not"
label var d_converted          "1 = this row has a gram figure"
label var fallback_level       "0 matched or standard-unit; 1-3 a borrowed rung; missing if unconverted"
label var d_cap                "1 = the household price ratio was clamped to t=5 (conv_path 2 only)"
label var n_g_used             "weighings behind cf_h, at the level used; missing off conv_path 2"
label var nu_used              "of n_g_used, disputed or anchor-flagged (#35); missing off conv_path 2"

* ---- value labels: RESET, not inherited ---------------------------------------
* conv_path and fallback_level each arrive from a different source per row, and the
* three sources do not attach the same value label to them (psps_standard_units.dta
* never runs `label values fallback_level fallback_lbl' at all, and this file's own
* section 2/3 generate conv_path from scratch with none). Rather than let the
* decoded text a reader sees depend on which source happened to save first, both
* are set explicitly, once, here.
label values conv_path .
label define grams_convpath 1 "standard unit" 2 "NSU via market survey" ///
	3 "not an NSU (dropped label)", replace
label values conv_path grams_convpath

* fallback_lbl is Outcome 2's own shared definition (00_globals.do's
* def_fallback_level, the same one 12_publish_reference_set.do and
* 28_match_and_convert.do both call) -- reused rather than restated, so a reader
* comparing this column against either deliverable's own reads it identically.
def_fallback_level
label values fallback_level fallback_lbl


********************************************************************************
**# 5. Assertions -- each states a claim this file makes about itself
********************************************************************************

* --- the grain -------------------------------------------------------------
isid `keyvars'
isid hh_row

* --- the three conversion paths partition the rows, and sum to 87,959 -------
* Paths 4 and 5 are the residual categories in 20a (no unit given; NSU with no
* crosswalk row) and carry ZERO rows on the current vintage -- a fact, not an
* assumption, checked directly rather than just absent from this file's inputs.
qui count if !inlist(conv_path, 1, 2, 3)
if r(N) > 0 {
	di as err "ERROR: " r(N) " row(s) carry conv_path 4 or 5."
	di as err "This file only reads paths 1-3 from psps_households.dta; a new"
	di as err "vintage with path 4/5 rows would silently vanish from this table."
	exit 459
}
qui count if conv_path == 1
assert r(N) == 52489
qui count if conv_path == 2
assert r(N) == 35448
qui count if conv_path == 3
assert r(N) == 22

* --- grams_h is non-missing exactly where d_converted == 1 ------------------
assert !missing(grams_h) if d_converted == 1
assert  missing(grams_h) if d_converted == 0

* --- grams_h == q_h * cf_h wherever both exist -------------------------------
assert reldif(grams_h, q_h * cf_h) < 1e-9 if !missing(grams_h) & !missing(cf_h)

* --- nu_used <= n_g_used wherever both exist ---------------------------------
assert nu_used <= n_g_used if !missing(nu_used) & !missing(n_g_used)

* --- the uncertainty columns are missing on every standard-unit row ----------
* conv_path == 1 is exactly the standard-unit population (section 2's own filter),
* so this is the direct restatement of the header note and A20: a stated container
* size has no weighing behind it to have questioned.
assert missing(n_g_used)        if conv_path == 1
assert missing(nu_used)         if conv_path == 1
assert missing(share_uncertain) if conv_path == 1

* --- the same holds for conv_path == 3: nothing was ever weighed -------------
assert missing(n_g_used)        if conv_path == 3
assert missing(nu_used)         if conv_path == 3
assert missing(share_uncertain) if conv_path == 3
assert missing(fallback_level)  if conv_path == 3
assert d_cap == 0               if conv_path == 3

* --- no column silently arrived missing where a decision was required -------
assert !missing(conv_path)
assert !missing(d_converted)
assert !missing(d_cap)
assert conv_route != ""

di as res _n "5. assertions: all pass"


********************************************************************************
**# 6. Save, and export a CSV a non-Stata user can read unaided
********************************************************************************
* NOTHING TEMPORARY MAY SHIP. A `tempvar' is dropped when the do-file ENDS, which
* is after this save -- so a tempvar still in memory here would ship as a junk
* `__000004' column, exactly as happened today in 12_publish_reference_set.do.
* Same guard, copied from there: `ds' exits 111 when nothing matches, which is the
* clean case, so success is the failure to test for.
capture ds __*
if _rc == 0 {
	di as err "temporary variable(s) still in memory at save: `r(varlist)'"
	di as err "Name and drop them -- a tempvar survives to here and ships."
	exit 459
}

* d_converted_blind must be 0 rather than missing on rows the blind ladder refused, so
* `tab d_converted_blind' counts the same population as d_converted. It arrives missing
* only on the standard-unit and conv_path 3 rows, which the append leaves empty and which
* have no NSU conversion to have a counterfactual for -- those stay missing on purpose.
replace d_converted_blind = 0 if conv_path == 2 & missing(d_converted_blind)
assert !missing(d_converted_blind) if conv_path == 2
assert missing(d_converted_blind)  if conv_path != 2

order hh_row hhid psps_item_code slot source ///
      pull_province pull_municipal_city pull_item pull_nsu_unit harmonized_nsu_unit ///
      q_h p_h cf_h grams_h conv_path conv_route d_converted fallback_level d_cap ///
      d_no_price n_g_used nu_used share_uncertain ///
      cf_h_blind grams_h_blind dim_blind fallback_level_blind conv_route_blind ///
      n_g_used_blind nu_used_blind d_converted_blind

compress
sort hh_row
save "${bdeliv}\psps_grams", replace
di as txt "wrote ${bdeliv}\psps_grams.dta -- `n_all' row(s)"

* ---- the CSV: header is variable LABELS, not names ---------------------------
* `export delimited' has no `firstrow(varlabels)' -- that option exists only for
* `export excel' (tested directly against this Stata install: `varnames(varlabel)'
* is refused with "option varnames() not allowed"). This is the artefact a
* non-Stata user opens, so the header is built by hand instead of shipping raw
* variable names -- the exact defect 12_publish_reference_set.do's own note warns
* against, just on a format where the built-in option does not exist to prevent it.
* DEFINED AS A PROGRAM because this file now publishes TWO csv deliverables -- the
* headline file and the hetero-blind variant in section 6b -- and a second hand-copy of
* thirty lines of file-handle work is exactly the silent divergence the project keeps
* being bitten by. One definition, called twice, on whatever is in memory.
capture program drop _labeled_csv
program define _labeled_csv
	syntax , OUTfile(string)

	qui ds
	local allvars `r(varlist)'
	foreach v of local allvars {
		local lbl : variable label `v'
		if `"`lbl'"' == "" {
			di as err "ERROR: `v' has no variable label -- every published column needs one."
			exit 459
		}
	}

	tempfile csvbody csvhead
	qui export delimited using "`csvbody'.csv", novarnames replace

	tempname fh
	file open `fh' using "`csvhead'.csv", write replace
	local line ""
	foreach v of local allvars {
		local lbl : variable label `v'
		local line `"`line'"`lbl'","'
	}
	local line = substr(`"`line'"', 1, length(`"`line'"') - 1)
	file write `fh' `"`line'"' _n
	file close `fh'

	cap erase "`outfile'"
	! copy /b "`csvhead'.csv"+"`csvbody'.csv" "`outfile'"
	cap confirm file "`outfile'"
	if _rc != 0 {
		di as err "ERROR: labeled CSV concatenation failed; `outfile' not written."
		exit 459
	}
	qui count
	di as txt "wrote `outfile' (header = variable labels, " r(N) " data row(s))"
end

_labeled_csv, outfile("${bdeliv}\psps_grams.csv")


********************************************************************************
**# 6b. The hetero-blind deliverable -- a drop-in file, not extra columns
********************************************************************************
* WHY A SEPARATE FILE and not just the _blind columns above. An analyst running the
* counterfactual should not have to rename six columns and remember which ones, because
* the one they forget is the one that silently keeps the published answer. So this ships
* the variant with the SAME COLUMN NAMES as the headline file: `grams_h' here IS the
* hetero-blind number. Same precedent as outcome2_lookup_noinflation.
*
* Built from the file already in memory, so the two cannot drift.
*
* WHAT IS NOT IN IT. `d_cap' and `p_h' are dropped: the cap bounds r_h = p_h / p_g, which
* exists only where a household price was divided by a group price, and no blind row has
* one. Keeping a cap flag that can never be 1 would invite a reader to conclude the cap
* was tested here and found to bind on nothing.
*
* ROWS OUTSIDE conv_path 2 ARE UNCHANGED, and that is the point of the comparison: a
* standard-unit row's grams come from the unit's own name, never from an NSU conversion,
* so there is nothing hetero-blind about it. A difference between this file and the
* headline one is the price/size matching and nothing else.
preserve

	replace cf_h            = cf_h_blind            if conv_path == 2
	replace grams_h         = grams_h_blind         if conv_path == 2
	replace conv_route      = conv_route_blind      if conv_path == 2
	replace fallback_level  = fallback_level_blind  if conv_path == 2
	replace d_converted     = d_converted_blind     if conv_path == 2
	replace n_g_used        = n_g_used_blind        if conv_path == 2
	replace nu_used         = nu_used_blind         if conv_path == 2
	replace share_uncertain = nu_used / n_g_used    if conv_path == 2

	drop cf_h_blind grams_h_blind dim_blind fallback_level_blind ///
	     conv_route_blind n_g_used_blind nu_used_blind d_converted_blind ///
	     d_cap p_h

	label var cf_h    "grams (or mL) in one unit of this NSU -- CELL POOLED across hetero-groups"
	label var grams_h "q_h * cf_h -- HETERO-BLIND grams for this household x item x slot"
	label var conv_route "how this row got its hetero-blind grams, or why it did not"
	label var fallback_level "hetero-blind rung: 1 cell pooled, 2 province, 3 regional (never 0)"

	* The blind ladder starts at L1, so a converted NSU row can never read 0 here. If this
	* fires, a headline-file column survived the swap above.
	assert fallback_level != 0 if conv_path == 2 & d_converted == 1
	assert !missing(grams_h) == (d_converted == 1) if conv_path == 2

	compress
	sort hh_row
	save "${bdeliv}\psps_grams_heteroblind", replace
	qui count
	di as txt "wrote ${bdeliv}\psps_grams_heteroblind.dta -- " r(N) " row(s)"

	_labeled_csv, outfile("${bdeliv}\psps_grams_heteroblind.csv")

	* ---- what the counterfactual costs, printed rather than left to be derived ------
	qui count if conv_path == 2 & d_converted == 1
	di as res _n "hetero-blind: converted NSU rows " r(N)
	qui su grams_h if conv_path == 2 & d_converted == 1
	di as res "hetero-blind: total grams over converted NSU rows " %18.0fc r(sum)

restore


********************************************************************************
**# 7. Report
********************************************************************************

di as res _n "{hline 78}"
di as res "31_psps_grams.do done"
di as res "{hline 78}"

di as res _n "rows by conversion path:"
tab conv_path, m

di as res _n "rows by conversion route:"
tab conv_route, m

di as res _n "converted vs refused:"
tab d_converted, m

qui su grams_h if d_converted == 1
di as res _n "total grams over converted rows: " %18.0fc r(sum)

* Reported for conv_path == 2 only -- the market-survey branch is the only
* population where n_g_used/nu_used are ever populated (A20's own aggregation
* rule: state which population a share is computed over, do not mix them). Both
* readings are printed, as A20 itself insists on: "resting on at least one" and
* "resting entirely on" are different claims and neither should be quoted alone.
qui count if conv_path == 2 & d_converted == 1
local n_nsu_conv = r(N)
qui count if conv_path == 2 & d_converted == 1 & share_uncertain > 0
local n_nsu_some = r(N)
qui count if conv_path == 2 & d_converted == 1 & share_uncertain == 1
local n_nsu_allu = r(N)
di as res _n "of the `n_nsu_conv' converted market-survey rows (conv_path 2):"
di as res "  resting on AT LEAST ONE questioned weighing: " %8.0fc `n_nsu_some' ///
	"  (" %5.1f 100 * `n_nsu_some' / `n_nsu_conv' "%)"
di as res "  resting ENTIRELY on questioned weighings:     " %8.0fc `n_nsu_allu' ///
	"  (" %5.1f 100 * `n_nsu_allu' / `n_nsu_conv' "%)"

di as res _n "{hline 78}"
di as res "  This is now the single household-level PSPS grams artefact."
di as res "  ${bdeliv}\psps_grams.dta and ${bdeliv}\psps_grams.csv"
di as res "{hline 78}"
