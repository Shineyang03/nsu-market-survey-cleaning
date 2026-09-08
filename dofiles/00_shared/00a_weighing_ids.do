********************************************************************************
* 00a_weighing_ids.do -- assign every raw weighing its durable id
*
* THE FIRST STEP IN THE PIPELINE, and it reads nothing but the raw market survey.
* That is the whole point: it is what breaks the dependency loop.
*
* WHY IT IS ITS OWN FILE. The registry used to be seeded inside 03_clean_ms.do, which
* runs LAST. But 01_build_crosswalk.py needs the registry (to number the price-only
* cases) and 03 needs the crosswalk. On a fresh clone that never converged in one
* pass: 01 ran with no registry and wrote a crosswalk without price ids, 03 then
* seeded the registry, and 01 had to run a second time. That is the same circularity
* issue #33 was opened about, reintroduced by the registry, and the fix is the same
* one that worked there -- move the half that needs only raw inputs to the front.
*
* The order is now a straight line, with no step depending on a later one:
*     00a  raw            -> weighing_id_registry.csv     (ids 1..N)
*     00b  raw + prices   -> cases_in_price_not_in_MS.csv
*     01   the above      -> master_nsu_rename.csv, and APPENDS price-case ids
*     02   crosswalk      -> filtered crosswalk
*     03+  everything     -> reads the registry, never writes it
*
* INPUT   ${data}    PSPS NSU Market Survey Launch.dta  (RAW)
* OUTPUT  ${tables}\weighing_id_registry.csv
*
* RUN, from the dofiles/ folder:
*     "C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\00a_weighing_ids.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

confirm file "${data}"
use "${data}", clear

def_hetero
encode obs_type, gen(item_nsu_hetero_type) label(hetero)

* ---- DURABLE WEIGHING ID ---------------------------------------------------------
* `id' is assigned ONCE per weighing and then remembered, so it means the same thing
* in every future build. It is NOT recomputed from row position.
*
* WHY, because the obvious version is wrong and was shipped. `id' used to be
* `gen id = _n' after a sort. Sorting on a content key makes that DETERMINISTIC -- the
* same rows always number the same way -- but `_n' is a POSITION, so a given weighing
* does not keep its number when the row set changes. Dropping five non-unit labels
* removed 16 weighings and shifted every id after them. Nine hand corrections keyed on
* `id' then landed on the wrong weighings, one of them setting a chicken bilog to the
* weight of a camote bilog. See section 5 of 05_manual_corrections.do.
*
* THE REGISTRY IS A REGISTRY, NOT A STALE INTERMEDIATE. Issue #33 was about a frozen
* CSV that COULD have been recomputed and wasn't. This file is the opposite case: it
* cannot be recomputed, because remembering a past assignment is the whole point. It is
* committed, and it only ever grows -- an id is never reused and never reassigned.
*
* IT COVERS THE FULL RAW MARKET SURVEY, deliberately, and is assigned HERE -- before
* the comment merge and before every exclusion. Attrition must not touch an id: a
* weighing dropped as a non-NSU label still owns its number, so if that label is ever
* re-admitted it comes back as the same weighing rather than as a new one at the end of
* the sequence. Assigning after the exclusions, which is what the first version did,
* left 62 raw weighings with no id at all.
*
* EVERY COMPONENT OF THE KEY IS RAW INPUT TEXT. Nothing in it is computed by this
* project, and that is the property that makes an id durable.
*
* Two parts of it are easy to get wrong:
*
*   RAW-CASED, not normalized -- "Cabbage|Bilog", not "cabbage|bilog". This step runs
*   before nsu_normalize on purpose. Normalization is CODE and code changes: the rule
*   was edited twice in one session. Keying ids on normalized text would let every
*   normalization edit silently re-key the registry and orphan every id.
*
*   obs_type, the STRING, not item_nsu_hetero_type, the code. They carry the same
*   information, but the code comes from `label define hetero' in 00_globals.do -- code
*   again. Inserting one type into that label would shift every code above it and
*   orphan every id in the registry. The key used the code until the flaw was noticed;
*   the registry was migrated in place (same ids, last component rewritten from the code
*   to its label) so nothing renumbered.
*
* So an id can now only break if the SOURCE DATA is respelled, which is a real event and
* one the orphan check at the bottom of this file reports rather than absorbing.
*
* THE KEY is the same content key asserted just above: province, municipality, item,
* RAW label, vendor, hetero type. All raw inputs. Deliberately not harmonized_nsu_unit
* -- keying on a value the crosswalk can change would move ids whenever a fold changed,
* which is the failure this replaces.

* COMMAS ARE STRIPPED from the components before joining. The registry is a CSV so it
* stays diffable in git, and several item names contain commas
* ("crackers, cookies, buiscuits, chips/curls"). Stata quotes those correctly on export
* but does not honour the quotes on import, which silently splits the key across six
* variables. Stripping is the robust fix: the key needs to be unique and stable, not
* readable, and the isid below proves the strip collides nothing.
tempvar idkey
gen str244 `idkey' = subinstr(pull_province, ",", "", .) ///
    + "|" + subinstr(pull_municipal_city, ",", "", .) ///
    + "|" + subinstr(pull_item, ",", "", .) ///
    + "|" + subinstr(pull_nsu_unit, ",", "", .) ///
    + "|" + subinstr(vendor_id, ",", "", .) ///
    + "|" + subinstr(obs_type, ",", "", .)
isid `idkey'

* First build ever, or the registry was lost: seed it from the current data. After this
* the branch below runs instead and the seeding never happens again.
capture confirm file "${tables}\weighing_id_registry.csv"
if _rc {
	di as error "NO ID REGISTRY at ${tables}\weighing_id_registry.csv -- seeding one."
	di as error "This should happen exactly once in the life of the project. If you are"
	di as error "seeing it on an established build, the registry was deleted: restore it"
	di as error "from git rather than reseeding, or every id in every output changes."
	preserve
		keep `idkey'
		sort `idkey'
		gen long id = _n
		rename `idkey' idkey
		export delimited using "${tables}\weighing_id_registry.csv", replace
	restore
}

* Read it back, so the assertions below check what a later step will actually get.
preserve
	* delimiter(",") is NOT optional. import delimited auto-detects, and the key holds
	* five "|" characters against the header's zero commas, so it picks "|" and splits
	* the key into six variables -- silently, reporting "(6 vars, 11,433 obs)".
	import delimited "${tables}\weighing_id_registry.csv", clear varnames(1) ///
		delimiter(",") stringcols(1) encoding("utf-8")
	isid idkey
	isid id
	qui count
	local n_reg = r(N)
	qui summarize id, meanonly
	local id_max = r(max)
	tempfile registry
	save "`registry'"
restore

rename `idkey' idkey
merge m:1 idkey using "`registry'", keep(1 3) gen(_m_id)

* A weighing the registry has never seen gets the next free id, and the registry grows.
* This is the ONLY way an id is created after seeding. If it fires on a build you did
* not expect it to, the content key moved -- most likely because normalization changed
* upstream -- and the right response is to reconcile that, not to accept new ids for
* rows that already had them.
qui count if _m_id == 1
local n_new = r(N)
if `n_new' > 0 {
	di as error "`n_new' weighing(s) are not in the id registry and will be assigned new ids."
	di as error "Expected only when the market survey genuinely gained rows. If the raw"
	di as error "data did not change, the content key moved -- reconcile that first."
	sort idkey
	qui gen long _newseq = sum(_m_id == 1) if _m_id == 1
	qui replace id = `id_max' + _newseq if _m_id == 1
	drop _newseq

	preserve
		keep if _m_id == 1
		keep idkey id
		append using "`registry'"
		sort id
		isid id
		isid idkey
		export delimited using "${tables}\weighing_id_registry.csv", replace
		qui count
		di as error "registry grew from `n_reg' to " r(N) " rows"
	restore
}

* keep a copy for the orphan check at the bottom, which needs the key after the merge
gen str244 idkey_check = idkey
drop _m_id idkey

* Nothing may reach the rest of the pipeline without an id, and no id may be shared.
assert !missing(id)
isid id

label var id "Durable weighing id: assigned once, remembered in outputs/tables/weighing_id_registry.csv"

* `id' IDENTIFIES A WEIGHING, NOT A CASE. Do not use it as a case key and do not
* "improve" it toward one. The case (the pooling grain) is
*     province x municipality x item x harmonized_nsu_unit x corrected_unit
* built as `cell' in 10_size_assignment.do, with the string form `prov_mun_nsu_item'
* here. The case key SHOULD move when a fold changes -- that is what a fold does. A
* weighing id must NOT, which is why the two are keyed differently and why this one
* uses the raw label.

* ---- INDEPENDENT CHECK: the registry describes the rows it claims to -----------
* The merge above proves every RAW row found a key in the registry. It does not prove
* the reverse -- that every key in the registry still describes a raw row. A key can be
* orphaned by an upstream re-export that respells a component, and the symptom would be
* silent: the orphaned id simply stops being used while a NEW id is minted for what is
* really the same weighing.
*
* Done here, in Stata, deliberately. Reconstructing these keys in Python needs
* `encode obs_type, label(hetero)' reproduced exactly, and two attempts at that got the
* code mapping wrong -- once alphabetically, once against the wrong label set -- each
* time producing a confident, wrong mismatch count. The build already holds the right
* answer; the check belongs where the keys are made.
preserve
	import delimited "${tables}\weighing_id_registry.csv", clear varnames(1) ///
		delimiter(",") stringcols(1) encoding("utf-8")
	* price-only case keys (three pipes) belong to 01_build_crosswalk.py and have no
	* raw weighing behind them -- they are not orphans and must not be counted as such.
	gen byte _pipes = length(idkey) - length(subinstr(idkey, "|", "", .))
	keep if _pipes == 5
	drop _pipes
	tempfile regw
	save "`regw'"
restore

preserve
	keep idkey_check
	rename idkey_check idkey
	merge 1:1 idkey using "`regw'", gen(_m_orph)
	count if _m_orph == 2
	if r(N) > 0 {
		di as error "`r(N)' weighing key(s) in the registry match no row in the raw file."
		di as error "An upstream respelling orphans an id and mints a new one for the same"
		di as error "weighing. Reconcile the spelling; do not delete registry rows."
		list idkey if _m_orph == 2, noobs abbrev(60)
		exit 459
	}
	count if _m_orph == 1
	assert r(N) == 0
restore

count
di as res _n "00a_weighing_ids complete: " r(N) " weighings carry a durable id"
di as txt "registry: ${tables}\weighing_id_registry.csv"
