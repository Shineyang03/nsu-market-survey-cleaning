********************************************************************************
* validate_folds.do -- does the harmonization pool labels that actually weigh the same?
*
* Every published gram figure rests on `harmonized_nsu_unit', the key weighings pool
* on. Two labels pooled into one referent had better be one referent. This file asks
* whether they are, for every fold the market-survey weighings can speak to.
*
* THE STATISTIC LIVES ELSEWHERE. 00_shared/nsu_rank_test.do holds the van Elteren
* stratified rank test, the equivalence (TOST) framing, and the verdict rule, with the
* reasoning for each. Read that file for WHY the test is built the way it is. This file
* decides only WHICH labels get compared, and reports the answers.
*
********************************************************************************
* THREE PANELS, THREE DIFFERENT FOLDS
*
* The harmonization folds labels TWICE, and both layers can be wrong:
*
*     raw pull_nsu_unit  --[spelling / vocabulary]-->  cleaned_nsu_unit
*     cleaned_nsu_unit   --[official translation  ]-->  harmonized_nsu_unit
*
*   (A) TRANSLATION FOLDS. For each (item, harmonized_nsu_unit) pooling two or more
*       cleaned labels, do those labels agree in weight?
*
*   (B) DOCUMENTED SEPARATIONS. For the pairs docs/master_rename.md section 6 keeps
*       deliberately apart, do they in fact differ? A hardcoded policy list, carried
*       as-is; do not re-derive it.
*
*   (C) SPELLING FOLDS. For each (item, cleaned_nsu_unit) pooling two or more raw
*       spellings, do those spellings agree?
*
* PANEL C EXISTS BECAUSE THIS LAYER WAS INVISIBLE. Panels A and B compare CLEANED
* labels, so the spelling fold has already happened before they see anything. That is
* not a harmless omission: these are translations, not typos. Loaf bread `large packs'
* pools `large' with `dalagku nga putos', `mabahoe nga putos' and `daragkul nga putos';
* ice cream `small cup' pools `gamay nga cup', `gmay nga cup', `small cup (translate)'
* and `maisot nga tasa'. Measured on the build this file was written against, 1,830 of
* the 9,750 matched size-weighings -- 18.8% -- sat under a spelling fold that carried
* enough data on two or more of its spellings to be testable, and none of them had ever
* been tested.
*
* WHAT NO PANEL CAN REACH. 16 of the 19 translation folds contain at least one label
* with ZERO market-survey weighings -- the price-side vocabulary (`tibuok na manok',
* `buong (manok)', `malaking packs', `maliit na packs', `gagmay nga pakete',
* `maliit na tasa', `can o lata'). There is no weight for those labels, so no weight
* test can ever run on them; they rest on the official translation alone. That is a
* property of the data, not a gap to be closed, and it is stated here so nobody has to
* infer it from an empty row.
*
********************************************************************************
* POPULATION AND GRAIN
*
* Universe : weighings with obs_type in {small,medium,large}_size -- physical
*            weighings only. Municipality and province medians and the *_price rows
*            are derived aggregates and would double-count.
* Unit     : one weighing. A test compares two label groups of weighings.
* Weight   : `corrected_weight', the PUBLISHED weight.
*
* WHY THE PUBLISHED WEIGHT, when this test once ran on `w_block'. The magnitude snap
* pools its anchor on `harmonized_nsu_unit', so two labels already folded together were
* snapped toward one median -- biasing this exact test toward "they agree", which is
* what justified folding them. That circularity is no longer live: `corrected_weight'
* and `w_block' are the SAME NUMBER on 9,735 of the 9,752 size-weighings this file
* reads. 15 differ and 2 are missing, and the 15 are hand verdicts from the review
* ledger -- a person looking at the row and deciding, which is better evidence than the
* typed number. Reading the published weight also lets the test see
* 05_manual_corrections.do's dimension resolution, which the block reading predates.
*
* RE-CHECK THAT 9,735 IF THE SNAP IS EVER CHANGED TO MOVE WEIGHTS AGAIN. If the two
* columns diverge materially the circularity is back and this decision has to be
* revisited -- switch `w' back to `w_block' and say so here.
*
* STRATA -- province x municipality x size x measurement-unit, falling back to
* province x size x measurement-unit.
*
*   A stratum must hold things comparable APART from the label being tested, so the
*   ideal is the MARKET: it controls for the local price and supply conditions a single
*   municipality shares, which is exactly the vendor-to-vendor variation a non-standard
*   unit carries. Municipality strata are often too thin to run, so the fine
*   stratification is tried first and the coarse one used only where the fine one could
*   not run at all. `strata_level' records which produced each verdict, because a
*   province-level verdict is a weaker claim and the CSV should say so.
*
*   THE FALLBACK FIRES ON r(gated) ONLY -- never on a verdict of `inconclusive'.
*   Gated means the count thresholds blocked the test and no evidence was weighed;
*   retrying on coarser strata is then legitimate. `inconclusive' means the test RAN
*   and could not resolve. Coarser strata have more power, so retrying those would be
*   fishing until a fold passes -- reintroducing, through the back door, the very bias
*   the reversed null exists to remove.
*
*   MEASUREMENT-UNIT is a stratum because a gram cannot be rank-compared with a
*   millilitre. ITEM IS NOT A STRATUM BECAUSE IT IS A CONSTANT: every test compares two
*   labels within one item, fixed by the `keep' at the top of each loop, so item cannot
*   vary inside a stratum and adding it would create no cells.
*
* STRING NORMALIZATION comes from `nsu_normalize' in 00_shared/00_globals.do -- the
* project's one definition, never a new one.
*
* OUTPUT
*     outputs/temp/fold_validation_A.csv    translation folds
*     outputs/temp/fold_validation_B.csv    documented separations
*     outputs/temp/fold_validation_C.csv    spelling folds
*
* A and B are read back by dofiles/verify_pipeline.py check 3.
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\validate_folds.do
********************************************************************************

version 19
clear all
set more off

do "00_shared/00_globals.do"
do "00_shared/nsu_rank_test.do"

* ---- knobs --------------------------------------------------------------------
* MIN_LABEL_N / MIN_STRATA gate the test on counts: below these it does not run at
* all and the pair is reported gated. RATIO_LO / RATIO_HI are the equivalence margin,
* pre-specified in docs/implicit_assumptions.md and NOT to be tuned to make a fold
* pass. ALPHA is per one-sided test, so the equivalent interval is 90%, not 95%.
local MIN_LABEL_N = 10
local MIN_STRATA  = 2
local RATIO_HI    = 1.25
local RATIO_LO    = 1/1.25
local ALPHA       = 0.05
local NPERM       = 10000
local SEED        = 20260917

local LNLO = ln(`RATIO_LO')
local LNHI = ln(`RATIO_HI')

local outdir "${output}/temp"
mkdir_missing "`outdir'"

di as res _n "{hline 78}"
di as res "FOLD VALIDATION"
di as res "  equivalence margin  [`RATIO_LO', `RATIO_HI']   alpha `ALPHA' per side"
di as res "  permutations `NPERM'   seed `SEED'"
di as res "{hline 78}"

********************************************************************************
* A SHARED RUNNER -- every panel tests a pair the same way, so the two-stage
* stratification and the posting live here once rather than three times.
*
* Expects in memory: w (raw weight), x (= ln w), isA, P, C, size, dim.
* Returns via r(): everything nsu_fold_test sets, plus r(strata_level) and
* r(size_ctrl_ratio).
********************************************************************************
capture program drop nsu_run_pair
program define nsu_run_pair, rclass
	syntax , minn(integer) minstr(integer) lnlo(real) lnhi(real) ///
	         alpha(real) nperm(integer) seed(integer)

	capture drop stratum
	egen long stratum = group(P C size dim)
	mata: nsu_fold_test(`minn', `minstr', `lnlo', `lnhi', `alpha', `nperm', `seed')
	local lvl "prov x mun"

	* fall back ONLY when the count gate blocked the test -- see the header
	if scalar(r(gated)) == 1 {
		capture drop stratum
		egen long stratum = group(P size dim)
		mata: nsu_fold_test(`minn', `minstr', `lnlo', `lnhi', `alpha', `nperm', `seed')
		local lvl "prov"
	}

	* p-values MUST move as Stata scalars, never through a local macro: a local's
	* default numeric-to-text conversion silently truncates a double to ~13
	* significant digits, and p is reported at full precision in the CSV.
	return scalar p_nil      = r(p_nil)
	return scalar p_tost_lo  = r(p_tost_lo)
	return scalar p_tost_hi  = r(p_tost_hi)
	return scalar p_nil_norm = r(p_nil_norm)
	return scalar ratio_hl   = r(ratio_hl)
	return scalar ratio_p25  = r(ratio_p25)
	return scalar ratio_p75  = r(ratio_p75)
	return scalar nstr       = r(nstr)
	return scalar nA         = r(nA)
	return scalar nB         = r(nB)
	return scalar gated      = r(gated)
	return local  verdict    = "`r(verdict)'"

	mata: st_numscalar("r_scr", nsu_size_ctrl_ratio())
	return scalar size_ctrl_ratio = scalar(r_scr)
	return local  strata_level    = "`lvl'"
end

********************************************************************************
* 1. the matched size-weighings
********************************************************************************
use "${btemp}/nsu_weighings_cpi.dta", clear
keep pull_province pull_municipal_city pull_item pull_nsu_unit item_nsu_hetero_type ///
     corrected_unit corrected_weight w_block

* item_nsu_hetero_type / corrected_unit are labelled numerics on this build -- decode
* to the plain strings, never compare against the numeric code.
decode item_nsu_hetero_type, gen(size)
decode corrected_unit, gen(dim0)
drop item_nsu_hetero_type corrected_unit

keep if inlist(size,"small_size","medium_size","large_size")

gen double w = corrected_weight
keep if !missing(w) & w>0
gen double x = ln(w)

gen str100 P = pull_province
gen str100 C = pull_municipal_city
gen str100 I = pull_item
gen str100 U = pull_nsu_unit
nsu_normalize, item(I) unit(U) mun(C) province(P)

* dim = nz(corrected_unit). unit() alone gets the generic transform; item() is a
* throwaway copy so the prepped-food substitution has nowhere real to land.
gen str100 dim    = dim0
gen str100 _dummy = dim0
nsu_normalize, item(_dummy) unit(dim)
drop _dummy dim0 pull_province pull_municipal_city pull_item pull_nsu_unit ///
     w_block corrected_weight

order P C I U dim size w x
save "`outdir'/_matched_raw.dta", replace

********************************************************************************
* 2. the crosswalk -- cleaned_nsu_unit / harmonized_nsu_unit from
*    outputs/tables/master_nsu_rename.csv, the single source of truth for the fold rule
********************************************************************************
import delimited using "${tables}/master_nsu_rename.csv", clear varnames(1) ///
	stringcols(_all) encoding("utf-8")
keep province pull_municipal_city cons_name pull_nsu_unit cleaned_nsu_unit harmonized_nsu_unit

gen str100 P = province
gen str100 C = pull_municipal_city
gen str100 I = cons_name
gen str100 U = pull_nsu_unit
nsu_normalize, item(I) unit(U) mun(C) province(P)

gen str100 cleaned  = cleaned_nsu_unit
gen str100 _dummy1  = cleaned_nsu_unit
nsu_normalize, item(_dummy1) unit(cleaned)

gen str100 harm     = harmonized_nsu_unit
gen str100 _dummy2  = harmonized_nsu_unit
nsu_normalize, item(_dummy2) unit(harm)

keep P C I U cleaned harm

* A collision on the normalized key would make the join's payload depend on row order.
* Assert there are none rather than silently picking a winner.
duplicates tag P C I U, gen(_dup)
quietly count if _dup>0
if r(N)>0 {
	di as err "validate_folds.do: `r(N)' rows of master_nsu_rename.csv collide on the"
	di as err "normalized (province, municipality, item, unit) key. Investigate before"
	di as err "trusting any output below."
	exit 459
}
drop _dup
save "`outdir'/_crosswalk.dta", replace

********************************************************************************
* 3. merge
********************************************************************************
use "`outdir'/_matched_raw.dta", clear
quietly count
local nweigh = r(N)

merge m:1 P C I U using "`outdir'/_crosswalk.dta"

* Count against the WEIGHINGS, not against the merged row total. An unrestricted
* m:1 merge also carries in crosswalk rows that matched no weighing -- price-only
* vocabulary, mostly -- and including those in the denominator understates the match
* rate against a population that was never being matched.
quietly count if _merge==3
local nmatch = r(N)
quietly count if _merge==2
local nxwonly = r(N)
di as txt "size-weighings: `nweigh' | matched to master_nsu_rename: `nmatch' (" ///
	%4.1f (100*`nmatch'/`nweigh') "%), " (`nweigh'-`nmatch') " unmatched and dropped"
di as txt "  (plus `nxwonly' crosswalk rows carrying no weighing at all -- price-only"
di as txt "   vocabulary, which no weight test can reach; see the header)"

keep if _merge==3
drop _merge
save "`outdir'/_matched.dta", replace

********************************************************************************
* 4. (A) TRANSLATION FOLDS -- cleaned labels within one (item, harmonized unit)
*
* The reference label is the highest-count one; every other label with at least
* MIN_LABEL_N weighings is compared against it -- NOT all pairwise combinations.
********************************************************************************
use "`outdir'/_matched.dta", clear
contract I harm cleaned, freq(cnt)
keep if cnt>=`MIN_LABEL_N'
bysort I harm: gen long nlabs = _N
keep if nlabs>=2

* count descending, ties broken alphabetically for determinism
gsort I harm -cnt cleaned
by I harm: gen long rk = _n
by I harm: gen str100 reflabel = cleaned[1]
keep if rk>1
rename cleaned otherlabel
keep I harm reflabel otherlabel

local NPAIRS = _N
di as res _n "===== (A) TRANSLATION FOLDS: `NPAIRS' pooled-label pair(s) ====="
forvalues i = 1/`NPAIRS' {
	local Ai_`i' = I[`i']
	local Hi_`i' = harm[`i']
	local Ri_`i' = reflabel[`i']
	local Oi_`i' = otherlabel[`i']
}

tempname postA
postfile `postA' str100 item str100 harmonized str100 label_ref str100 label_other ///
	str40 verdict double p double p_tost_lo double p_tost_hi double p_nil_norm ///
	double size_ctrl_ratio double ratio_hl double ratio_p25 double ratio_p75 ///
	long n_strata long n_ref long n_other double med_ref_med_g double med_other_med_g ///
	str20 strata_level byte gated using "`outdir'/_resultsA.dta", replace

forvalues i = 1/`NPAIRS' {
	use "`outdir'/_matched.dta", clear
	keep if I=="`Ai_`i''" & harm=="`Hi_`i''" & inlist(cleaned, "`Ri_`i''", "`Oi_`i''")
	gen byte isA = (cleaned=="`Ri_`i''")

	nsu_run_pair, minn(`MIN_LABEL_N') minstr(`MIN_STRATA') lnlo(`LNLO') lnhi(`LNHI') ///
		alpha(`ALPHA') nperm(`NPERM') seed(`SEED')

	scalar s_p    = r(p_nil)
	scalar s_plo  = r(p_tost_lo)
	scalar s_phi  = r(p_tost_hi)
	scalar s_pn   = r(p_nil_norm)
	scalar s_hl   = r(ratio_hl)
	scalar s_p25  = r(ratio_p25)
	scalar s_p75  = r(ratio_p75)
	scalar s_scr  = r(size_ctrl_ratio)
	local  nstr_i = r(nstr)
	local  nA_i   = r(nA)
	local  nB_i   = r(nB)
	local  gate_i = r(gated)
	local  verd_i = "`r(verdict)'"
	local  lvl_i  = "`r(strata_level)'"

	gen byte _fref = (cleaned=="`Ri_`i''" & size=="medium_size")
	gen byte _foth = (cleaned=="`Oi_`i''" & size=="medium_size")
	mata: st_numscalar("r(medref)", nsu_median_if("w","_fref"))
	mata: st_numscalar("r(medoth)", nsu_median_if("w","_foth"))
	mata: st_numscalar("r(medref_r)", nsu_round_even(st_numscalar("r(medref)"), 0))
	mata: st_numscalar("r(medoth_r)", nsu_round_even(st_numscalar("r(medoth)"), 0))
	local medref_r = r(medref_r)
	local medoth_r = r(medoth_r)

	di as txt "  `Ai_`i'' | `Hi_`i'' | `Ri_`i'' vs `Oi_`i''"
	di as txt "      -> `verd_i'   p_nil=" s_p "  TOST lo=" s_plo " hi=" s_phi ///
		"  ratio_HL=" s_hl "  nstr=`nstr_i'  `lvl_i'"

	post `postA' (`"`Ai_`i''"') (`"`Hi_`i''"') (`"`Ri_`i''"') (`"`Oi_`i''"') ///
		(`"`verd_i'"') (s_p) (s_plo) (s_phi) (s_pn) (s_scr) (s_hl) (s_p25) (s_p75) ///
		(`nstr_i') (`nA_i') (`nB_i') (`medref_r') (`medoth_r') (`"`lvl_i'"') (`gate_i')
}
postclose `postA'

********************************************************************************
* 5. (B) DOCUMENTED SEPARATIONS -- docs/master_rename.md section 6, carried as-is
*    (item substring filter, harm A, harm B; empty item = any item).
*    This is a hardcoded policy list. Do not re-derive it.
********************************************************************************
local NSPLITS = 8
local itf1 "chicken"
local ha1  "bilog"
local hb1  "pieces or units"
local itf2 "preserved"
local ha2  "bilog"
local hb2  "pieces or units"
local itf3 "camote"
local ha3  "bilog"
local hb3  "binilog"
local itf4 "ice cream"
local ha4  "putos"
local hb4  "pack"
local itf5 "crackers"
local ha5  "putos"
local hb5  "pack"
local itf6 ""
local ha6  "bundle"
local hb6  "bugkos"
local itf7 ""
local ha7  "putos"
local hb7  "pakete"
local itf8 ""
local ha8  "pack"
local hb8  "packs"

di as res _n "===== (B) DOCUMENTED SEPARATIONS: `NSPLITS' pair(s) ====="

tempname postB
postfile `postB' str100 item str100 harm_A str100 harm_B str40 verdict double p ///
	double p_tost_lo double p_tost_hi double p_nil_norm double size_ctrl_ratio ///
	double ratio_hl double ratio_p25 double ratio_p75 long n_strata long n_A long n_B ///
	double med_A_med_g double med_B_med_g str20 strata_level byte gated ///
	using "`outdir'/_resultsB.dta", replace

forvalues i = 1/`NSPLITS' {
	use "`outdir'/_matched.dta", clear
	keep if inlist(harm, "`ha`i''", "`hb`i''")
	if `"`itf`i''"' != "" {
		keep if strpos(I, "`itf`i''") > 0
	}
	quietly count
	local gN = r(N)

	if `gN' == 0 {
		if `"`itf`i''"' == "" local itemlabel "any"
		else                  local itemlabel "`itf`i''"
		di as txt "  spec `i' (`itemlabel', `ha`i'', `hb`i'') -> absent (no matching rows)"
		post `postB' (`"`itemlabel'"') (`"`ha`i''"') (`"`hb`i''"') ("absent") ///
			(.) (.) (.) (.) (.) (.) (.) (.) (0) (0) (0) (.) (.) ("") (0)
		continue
	}

	save "`outdir'/_splitsubset.dta", replace

	* items where BOTH harm values are present
	contract I harm
	bysort I: gen long nharm = _N
	keep if nharm==2
	quietly count
	local nqual = r(N)
	if `nqual' == 0 {
		di as txt "  spec `i' (`ha`i'', `hb`i'') -> no item carries both harm values"
		continue
	}
	duplicates drop I, force
	sort I
	local nqual = _N

	forvalues q = 1/`nqual' {
		local itemq = I[`q']

		use "`outdir'/_splitsubset.dta", clear
		keep if I=="`itemq'"
		gen byte isA = (harm=="`ha`i''")

		nsu_run_pair, minn(`MIN_LABEL_N') minstr(`MIN_STRATA') lnlo(`LNLO') ///
			lnhi(`LNHI') alpha(`ALPHA') nperm(`NPERM') seed(`SEED')

		scalar s_p   = r(p_nil)
		scalar s_plo = r(p_tost_lo)
		scalar s_phi = r(p_tost_hi)
		scalar s_pn  = r(p_nil_norm)
		scalar s_hl  = r(ratio_hl)
		scalar s_p25 = r(ratio_p25)
		scalar s_p75 = r(ratio_p75)
		scalar s_scr = r(size_ctrl_ratio)
		local  nstr_i = r(nstr)
		local  nA_i   = r(nA)
		local  nB_i   = r(nB)
		local  gate_i = r(gated)
		local  verd_i = "`r(verdict)'"
		local  lvl_i  = "`r(strata_level)'"

		gen byte _fA = (harm=="`ha`i''" & size=="medium_size")
		gen byte _fB = (harm=="`hb`i''" & size=="medium_size")
		mata: st_numscalar("r(medA)", nsu_median_if("w","_fA"))
		mata: st_numscalar("r(medB)", nsu_median_if("w","_fB"))
		mata: st_numscalar("r(medA_r)", nsu_round_even(st_numscalar("r(medA)"), 0))
		mata: st_numscalar("r(medB_r)", nsu_round_even(st_numscalar("r(medB)"), 0))
		local medA_r = r(medA_r)
		local medB_r = r(medB_r)

		di as txt "  `itemq' | `ha`i'' vs `hb`i''"
		di as txt "      -> `verd_i'   p_nil=" s_p "  TOST lo=" s_plo " hi=" s_phi ///
			"  ratio_HL=" s_hl "  nstr=`nstr_i'  `lvl_i'"

		post `postB' (`"`itemq'"') (`"`ha`i''"') (`"`hb`i''"') (`"`verd_i'"') ///
			(s_p) (s_plo) (s_phi) (s_pn) (s_scr) (s_hl) (s_p25) (s_p75) ///
			(`nstr_i') (`nA_i') (`nB_i') (`medA_r') (`medB_r') (`"`lvl_i'"') (`gate_i')
	}
}
postclose `postB'

********************************************************************************
* 6. (C) SPELLING FOLDS -- raw pull_nsu_unit spellings within one (item, cleaned label)
*
* Same construction as Panel A one layer up: reference = the highest-count spelling,
* every other spelling with at least MIN_LABEL_N weighings compared against it.
********************************************************************************
use "`outdir'/_matched.dta", clear
contract I cleaned U, freq(cnt)
keep if cnt>=`MIN_LABEL_N'
bysort I cleaned: gen long nspell = _N
keep if nspell>=2

gsort I cleaned -cnt U
by I cleaned: gen long rk = _n
by I cleaned: gen str100 refspell = U[1]
keep if rk>1
rename U otherspell
keep I cleaned refspell otherspell

local NSPELL = _N
di as res _n "===== (C) SPELLING FOLDS: `NSPELL' pooled-spelling pair(s) ====="
forvalues i = 1/`NSPELL' {
	local Ci_`i' = I[`i']
	local Li_`i' = cleaned[`i']
	local Si_`i' = refspell[`i']
	local Ti_`i' = otherspell[`i']
}

tempname postC
postfile `postC' str100 item str100 cleaned_label str100 spell_ref str100 spell_other ///
	str40 verdict double p double p_tost_lo double p_tost_hi double p_nil_norm ///
	double size_ctrl_ratio double ratio_hl double ratio_p25 double ratio_p75 ///
	long n_strata long n_ref long n_other double med_ref_med_g double med_other_med_g ///
	str20 strata_level byte gated using "`outdir'/_resultsC.dta", replace

forvalues i = 1/`NSPELL' {
	use "`outdir'/_matched.dta", clear
	keep if I=="`Ci_`i''" & cleaned=="`Li_`i''" & inlist(U, "`Si_`i''", "`Ti_`i''")
	gen byte isA = (U=="`Si_`i''")

	nsu_run_pair, minn(`MIN_LABEL_N') minstr(`MIN_STRATA') lnlo(`LNLO') lnhi(`LNHI') ///
		alpha(`ALPHA') nperm(`NPERM') seed(`SEED')

	scalar s_p   = r(p_nil)
	scalar s_plo = r(p_tost_lo)
	scalar s_phi = r(p_tost_hi)
	scalar s_pn  = r(p_nil_norm)
	scalar s_hl  = r(ratio_hl)
	scalar s_p25 = r(ratio_p25)
	scalar s_p75 = r(ratio_p75)
	scalar s_scr = r(size_ctrl_ratio)
	local  nstr_i = r(nstr)
	local  nA_i   = r(nA)
	local  nB_i   = r(nB)
	local  gate_i = r(gated)
	local  verd_i = "`r(verdict)'"
	local  lvl_i  = "`r(strata_level)'"

	gen byte _fref = (U=="`Si_`i''" & size=="medium_size")
	gen byte _foth = (U=="`Ti_`i''" & size=="medium_size")
	mata: st_numscalar("r(medref)", nsu_median_if("w","_fref"))
	mata: st_numscalar("r(medoth)", nsu_median_if("w","_foth"))
	mata: st_numscalar("r(medref_r)", nsu_round_even(st_numscalar("r(medref)"), 0))
	mata: st_numscalar("r(medoth_r)", nsu_round_even(st_numscalar("r(medoth)"), 0))
	local medref_r = r(medref_r)
	local medoth_r = r(medoth_r)

	di as txt "  `Ci_`i'' | `Li_`i'' | `Si_`i'' vs `Ti_`i''"
	di as txt "      -> `verd_i'   p_nil=" s_p "  TOST lo=" s_plo " hi=" s_phi ///
		"  ratio_HL=" s_hl "  nstr=`nstr_i'  `lvl_i'"

	post `postC' (`"`Ci_`i''"') (`"`Li_`i''"') (`"`Si_`i''"') (`"`Ti_`i''"') ///
		(`"`verd_i'"') (s_p) (s_plo) (s_phi) (s_pn) (s_scr) (s_hl) (s_p25) (s_p75) ///
		(`nstr_i') (`nA_i') (`nB_i') (`medref_r') (`medoth_r') (`"`lvl_i'"') (`gate_i')
}
postclose `postC'

********************************************************************************
* 7. write the CSVs
*
* Written with `file write', not `export delimited', to keep full double precision on
* the p-values. CSV quoting is applied by hand for the same reason.
********************************************************************************
capture program drop nsu_csvquote
program define nsu_csvquote
	args src dst
	gen str200 `dst' = `src'
	replace `dst' = subinstr(`dst', `"""', `""""', .)
	replace `dst' = `"""' + `dst' + `"""' if strpos(`src', ",") | strpos(`src', `"""')
end

* %30.17g, NOT %21.17g -- a narrower field WIDTH silently caps the digits printed below
* the 17 significant figures the .17g precision asks for. string() is applied to the
* VARIABLE directly, never to a local holding its value: a local's numeric-to-text
* conversion already truncated it to ~13 significant digits on assignment.
capture program drop nsu_fmtnum
program define nsu_fmtnum
	args var i name
	if `var'[`i'] >= .  c_local `name' ""
	else                c_local `name' = string(`var'[`i'], "%30.17g")
end

capture program drop nsu_writecsv
program define nsu_writecsv
	* args: dta-path  csv-path  "4 leading string vars"  panel-letter
	args indta outcsv strvars letter

	use "`indta'", clear
	local k = 1
	foreach v of local strvars {
		nsu_csvquote `v' _q`k'
		local ++k
	}
	local nstr = `k' - 1

	local N = _N
	file open fh using "`outcsv'", write text replace
	if "`letter'" == "A" ///
		file write fh "item,harmonized,label_ref,label_other," _n(0)
	if "`letter'" == "B" ///
		file write fh "item,harm_A,harm_B," _n(0)
	if "`letter'" == "C" ///
		file write fh "item,cleaned_label,spell_ref,spell_other," _n(0)
	file write fh "verdict,p,p_tost_lo,p_tost_hi,p_nil_norm,size_ctrl_ratio," ///
		"ratio_hl,ratio_p25,ratio_p75,n_strata,n_A,n_B,med_A_med_g,med_B_med_g," ///
		"strata_level,gated" _n

	forvalues i = 1/`N' {
		forvalues k = 1/`nstr' {
			local s`k' = _q`k'[`i']
		}
		local vd = verdict[`i']
		local sl = strata_level[`i']
		local ns = n_strata[`i']
		local na = n_A[`i']
		local nb = n_B[`i']
		local gt = gated[`i']

		nsu_fmtnum p              `i' pp_s
		nsu_fmtnum p_tost_lo      `i' plo_s
		nsu_fmtnum p_tost_hi      `i' phi_s
		nsu_fmtnum p_nil_norm     `i' pnn_s
		nsu_fmtnum size_ctrl_ratio `i' scr_s
		nsu_fmtnum ratio_hl       `i' hl_s
		nsu_fmtnum ratio_p25      `i' r25_s
		nsu_fmtnum ratio_p75      `i' r75_s
		nsu_fmtnum med_A_med_g    `i' mA_s
		nsu_fmtnum med_B_med_g    `i' mB_s

		forvalues k = 1/`nstr' {
			file write fh `"`s`k''"' ","
		}
		file write fh "`vd'" "," `"`pp_s'"' "," `"`plo_s'"' "," `"`phi_s'"' "," ///
			`"`pnn_s'"' "," `"`scr_s'"' "," `"`hl_s'"' "," `"`r25_s'"' "," ///
			`"`r75_s'"' "," (`ns') "," (`na') "," (`nb') "," `"`mA_s'"' "," ///
			`"`mB_s'"' "," "`sl'" "," (`gt') _n
	}
	file close fh
	di as res "wrote `outcsv' (`N' rows)"
end

* Panel B's medians are named med_A/med_B; A and C use med_ref/med_other. Rename so
* one writer serves all three rather than three near-identical writers drifting apart.
use "`outdir'/_resultsA.dta", clear
rename (n_ref n_other med_ref_med_g med_other_med_g) (n_A n_B med_A_med_g med_B_med_g)
save "`outdir'/_resultsA.dta", replace
use "`outdir'/_resultsC.dta", clear
rename (n_ref n_other med_ref_med_g med_other_med_g) (n_A n_B med_A_med_g med_B_med_g)
save "`outdir'/_resultsC.dta", replace

nsu_writecsv "`outdir'/_resultsA.dta" "`outdir'/fold_validation_A.csv" ///
	"item harmonized label_ref label_other" "A"
nsu_writecsv "`outdir'/_resultsB.dta" "`outdir'/fold_validation_B.csv" ///
	"item harm_A harm_B" "B"
nsu_writecsv "`outdir'/_resultsC.dta" "`outdir'/fold_validation_C.csv" ///
	"item cleaned_label spell_ref spell_other" "C"

********************************************************************************
* 8. the summary a reader actually needs
********************************************************************************
di as res _n "{hline 78}"
di as res "VERDICT COUNTS"
di as res "{hline 78}"
foreach L in A B C {
	use "`outdir'/_results`L'.dta", clear
	di as txt _n "Panel `L':"
	tab verdict, missing
	quietly count if gated==1
	di as txt "  of which never ran (count gate): " r(N)
}

di as res _n "{hline 78}"
di as res "validate_folds.do complete."
di as res "  outputs/temp/fold_validation_A.csv   translation folds"
di as res "  outputs/temp/fold_validation_B.csv   documented separations"
di as res "  outputs/temp/fold_validation_C.csv   spelling folds"
di as res ""
di as res "  An `inconclusive' verdict KEEPS THE LABELS APART and is a photo-review"
di as res "  candidate, not a pass. See 00_shared/nsu_rank_test.do for why."
di as res "{hline 78}"
