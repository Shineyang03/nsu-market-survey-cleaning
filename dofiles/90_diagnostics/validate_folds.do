********************************************************************************
* validate_folds.do -- Stata port of the STATISTICAL CORE of
*                      90_diagnostics/validate_folds.py (--weight=block, the default)
*
* WHY THIS PORT EXISTS. Project policy (CLAUDE.md): "Build objects in Stata. Python
* only where Stata cannot." validate_folds.py needs no fuzzy string matching and no
* .xlsx -- it reads one .dta and one .csv, joins them on normalized strings, and runs
* a stratified rank test. None of that requires Python, and Stata does stratified
* rank tests natively. This file is that port. validate_folds.py stays the reference
* until the port is accepted; this file does not replace it and is not wired into
* master_outcome1.do, verify_pipeline.py, or the README.
*
* WHAT IT DOES. Two questions, both restricted to obs_type in
* {small,medium,large}_size (physical weighings only -- municipality/province medians
* and *_price rows are derived aggregates, excluded exactly as in the Python):
*
*   (A) FOLD validation   : for each (item, harmonized_nsu_unit) that pools >=2 cleaned
*                           labels, do those labels actually agree in weight?
*   (B) SPLIT validation  : for the documented keep-separate pairs (docs/master_rename.md
*                           section 6, hardcoded SPLITS list below, carried over as-is),
*                           do they actually differ?
*
* METHOD -- a van Elteren stratified rank test (stratified Wilcoxon, design-free
* weights 1/(n_h+1)) comparing two labels WITHIN (province x size x measurement-unit)
* strata, on the tie-corrected rank-sum statistic:
*
*   per stratum h:  W_a = sum of average ranks of group A's obs in the pooled a+b ranks
*                   E   = n_a*(n+1)/2
*                   tie correction on the variance: sum(cnt_v^3 - cnt_v) over distinct
*                   values v in the pooled a+b sample of that stratum
*                   var_h = n_a*n_b/12 * [(n+1) - tie/(n*(n-1))]      (n>1, else 0)
*   combined:       T = sum_h [ (W_a,h - E_h) / (n_h+1) ]
*                   V = sum_h [ var_h / (n_h+1)^2 ]
*                   z = T / sqrt(V),  p = 2 * P(Z > |z|)   -- plain normal approximation,
*                   NO continuity correction (matches scipy.stats.norm.sf(abs(z))*2)
*
* Strata where either label is entirely absent do not enter T/V/nstr/nA/nB at all
* (matches the Python's `if na<1 or nb<1: continue`), but medians (see below) are
* NOT restricted to those strata -- they are a plain medium_size-only median per label,
* independent of the stratified test.
*
* PLUS a size-controlled effect size: the median, over included strata, of
* (median_A_h / median_B_h). Verdict is DIFFER only when p<0.05 AND that ratio falls
* outside [0.80, 1.25]; otherwise sig-but-small (p<0.05, ratio inside the band) or
* agree (p>=0.05). insufficient overrides both when n_strata<2, or either label's
* total in-stratum n is <10, or the combined variance is 0 -- exactly MIN_STRATA,
* MIN_LABEL_N and the V<=0 guard in validate_folds.py.
*
* WHY THE BLOCK READING, NOT THE PUBLISHED WEIGHT. See dofiles/README.md, "Where the
* fold evidence is produced, and why it is produced there". 04_unit_snap.do snaps the
* published weight toward the median of a pool keyed on harmonized_nsu_unit -- so two
* labels folded together are snapped toward one median, which biases this exact test
* toward "they weigh the same" (the crackers bilog/pieces-or-units fold: DIFFER on the
* published weight, agree on the block reading, same ratio). w_block
* (00_shared/03a_block_reading.do) is a pure function of the raw weight, unit tick and
* KGMAX alone, computed BEFORE any fold is applied, so it carries no such bias. THIS
* IS THE DEFAULT AND ONLY READING THIS FILE TESTS -- it does not implement the Python's
* --weight=corrected or --build=<variant> options; those exist there only for the
* side-by-side comparison written up in the README, not as part of the statistical
* core this file ports.
*
* NOT PORTED, DELIBERATELY: validate_folds.py also re-derives w_block from
* block_reading.dta and asserts the build's copy is a valid ROUNDING of it, guarding
* against a downstream recomputation reopening the circularity the block reading
* exists to avoid. That is a BUILD INTEGRITY check on the pipeline, not part of the
* statistical core, and this file does not duplicate it. If that guard is wanted in
* Stata too, it belongs in its own diagnostic, not folded into this one.
*
* STRING NORMALIZATION. Uses the project's ONE definition, `nsu_normalize` in
* 00_shared/00_globals.do -- never a new one. It must agree character-for-character
* with nsu_normalize.py's nz()/ni()/ng(), which the Python side of this test imports;
* see that program's header comment and docs/master_rename.md footnote on non-ASCII
* handling (dropped, not transliterated -- deliberate).
*
* OUTPUT -- deliberately NOT outputs/temp/. Those two filenames
* (fold_validation_A.csv, fold_validation_B.csv) are read back by
* verify_pipeline.py check 3, and this port is not wired into that check, so writing
* there would leave the build "verified" against a test it never agreed to run.
* Writes instead to its own subtree:
*     outputs/temp/_folds_port/fold_validation_A.csv
*     outputs/temp/_folds_port/fold_validation_B.csv
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\validate_folds.do
********************************************************************************

version 19
clear all
set more off

do "00_shared/00_globals.do"

* ---- knobs -- must match validate_folds.py's module-level constants exactly ----
local MIN_LABEL_N = 10
local MIN_STRATA  = 2
local RATIO_HI    = 1.25
local RATIO_LO    = 1/1.25

local outdir "${output}/temp/_folds_port"
mkdir_missing "`outdir'"

********************************************************************************
* MATA -- the van Elteren stratified rank test, a numpy-consistent median, and a
* round-half-to-even helper (numpy's/Python's round() convention, NOT Stata's
* round-half-away-from-zero -- see the note on this exact issue in
* validate_folds.py's block-reading comparison and in ~/.claude/CLAUDE.md).
********************************************************************************
mata:
mata clear

// numpy-consistent median: exact middle for odd n, average of the two middle
// order statistics for even n (no interpolation beyond that average).
real scalar nsu_median(real colvector x)
{
	real colvector xs
	real scalar n
	xs = sort(x, 1)
	n  = rows(xs)
	if (n == 0) return(.)
	if (mod(n,2)==1) return(xs[(n+1)/2])
	return((xs[n/2] + xs[n/2+1]) / 2)
}

real scalar nsu_median_if(string scalar wvarname, string scalar flagname)
{
	real colvector w, flag
	st_view(w=., ., wvarname)
	st_view(flag=., ., flagname)
	return(nsu_median(select(w, flag:==1)))
}

// average-rank ranking, ties get the mean of the ranks they span -- matches
// pandas.Series.rank() default, which is what validate_folds.py calls.
real colvector nsu_rank_avg(real colvector x)
{
	real scalar n, i, j, k
	real colvector o, xs, ranks
	real scalar avgr
	n = rows(x)
	o = order(x, 1)
	xs = x[o]
	ranks = J(n,1,.)
	// Mata's `&` does not short-circuit, so "j<n & xs[j+1]==xs[i]" evaluates
	// xs[j+1] even when j==n and throws a subscript-out-of-range error. Nest the
	// checks instead so xs[j+1] is only touched once j<n is already known true.
	i = 1
	while (i<=n) {
		j = i
		while (j<n) {
			if (xs[j+1]==xs[i]) j++
			else break
		}
		avgr = (i+j)/2
		for (k=i; k<=j; k++) ranks[o[k]] = avgr
		i = j+1
	}
	return(ranks)
}

// round(x,d) with ties broken to even, matching numpy.round()/Python's round() on
// floats -- NOT Stata's round(), which breaks ties away from zero.
real scalar nsu_round_even(real scalar x, real scalar d)
{
	real scalar scale, y, fl, f
	if (x>=.) return(.)
	scale = 10^d
	y  = x*scale
	fl = floor(y)
	f  = y - fl
	if (abs(f-0.5) < 1e-7) {
		if (mod(fl,2)==0) return(fl/scale)
		return((fl+1)/scale)
	}
	return(round(y)/scale)
}

// The test itself. Expects the CURRENT Stata dataset in memory to already be
// restricted to exactly the two labels under comparison, with:
//   w        double   the weight (w_block)
//   isA      0/1      1 for label A's rows, 0 for label B's
//   stratum  numeric  group id for (province x size x measurement-unit)
// Returns via r(): p, ratio, nstr, nA, nB, and r(verdict) as a string.
void nsu_van_elteren(real scalar MIN_LABEL_N, real scalar MIN_STRATA,
                      real scalar RATIO_HI, real scalar RATIO_LO)
{
	real colvector w, isA, strat, ustr, ratios, idx, a, b, comb, r, uv
	real scalar i, k, na, nb, n, nstr, nA, nB, T, V, ma, mb, Wa, E, tie, cnt, varh, wgt
	real scalar z, p, ratio
	string scalar verdict

	st_view(w=.,    ., "w")
	st_view(isA=.,  ., "isA")
	st_view(strat=., ., "stratum")

	ustr = uniqrows(strat)
	T = 0; V = 0; nstr = 0; nA = 0; nB = 0
	ratios = J(0,1,.)

	for (i=1; i<=rows(ustr); i++) {
		idx = selectindex(strat:==ustr[i])
		a = select(w[idx], isA[idx]:==1)
		b = select(w[idx], isA[idx]:==0)
		na = rows(a); nb = rows(b)
		if (na<1 | nb<1) continue
		n = na + nb
		nstr = nstr + 1
		nA = nA + na
		nB = nB + nb

		ma = nsu_median(a)
		mb = nsu_median(b)
		if (mb>0) ratios = ratios \ (ma/mb)

		comb = a \ b
		r  = nsu_rank_avg(comb)
		Wa = sum(r[1::na])
		E  = na*(n+1)/2

		uv  = uniqrows(comb)
		tie = 0
		for (k=1; k<=rows(uv); k++) {
			cnt = sum(comb:==uv[k])
			tie = tie + (cnt^3 - cnt)
		}
		if (n>1) varh = na*nb/12*((n+1) - tie/(n*(n-1)))
		else     varh = 0

		wgt = 1/(n+1)
		T = T + wgt*(Wa - E)
		V = V + wgt^2*varh
	}

	if (rows(ratios)>0) ratio = nsu_median(ratios)
	else                ratio = .

	if (nstr<MIN_STRATA | nA<MIN_LABEL_N | nB<MIN_LABEL_N | V<=0) {
		verdict = "insufficient"
		p = .
	}
	else {
		z = T/sqrt(V)
		// 2*normal(-|z|), NOT 2*(1-normal(|z|)) -- the latter cancels two numbers
		// close to 1 and loses precision exactly where p is smallest and most in
		// need of it. normal(-|z|) computes the small tail directly.
		p = 2*normal(-abs(z))
		if (p<0.05 & ratio<. & (ratio>=RATIO_HI | ratio<=RATIO_LO)) verdict = "DIFFER"
		else if (p<0.05)                                            verdict = "sig-but-small"
		else                                                        verdict = "agree"
	}

	st_numscalar("r(p)",     p)
	st_numscalar("r(ratio)", ratio)
	st_numscalar("r(nstr)",  nstr)
	st_numscalar("r(nA)",    nA)
	st_numscalar("r(nB)",    nB)
	st_global("r(verdict)", verdict)
}
end

********************************************************************************
* 1. build the matched size-weighings dataset -- mirrors the top of
*    validate_folds.py through `raw=raw[raw.harm.notna()]`
********************************************************************************
use "${btemp}/nsu_weighings_cpi.dta", clear
keep pull_province pull_municipal_city pull_item pull_nsu_unit item_nsu_hetero_type corrected_unit w_block

* item_nsu_hetero_type / corrected_unit are Stata-labelled numerics on this build
* (pandas reads them back as category dtype) -- decode to the plain strings the
* Python side compares against (raw.item_nsu_hetero_type.astype(str), raw.corrected_unit).
decode item_nsu_hetero_type, gen(size)
decode corrected_unit, gen(dim0)
drop item_nsu_hetero_type corrected_unit

* SIZES filter: obs_type in {small,medium,large}_size -- physical weighings only.
keep if inlist(size,"small_size","medium_size","large_size")

* w = w_block, keep w>0 & not missing
gen double w = w_block
keep if !missing(w) & w>0

* ---- normalize the join/strata keys with THE program, not a new one -----------
gen str100 P = pull_province
gen str100 C = pull_municipal_city
gen str100 I = pull_item
gen str100 U = pull_nsu_unit
nsu_normalize, item(I) unit(U) mun(C) province(P)

* dim = nz(corrected_unit). unit() alone gets the generic nz() transform (no
* prepped-food substitution); item() is a throwaway copy so that substitution has
* nowhere real to land.
gen str100 dim    = dim0
gen str100 _dummy = dim0
nsu_normalize, item(_dummy) unit(dim)
drop _dummy dim0 pull_province pull_municipal_city pull_item pull_nsu_unit w_block

order P C I U dim size w
save "`outdir'/_matched_raw.dta", replace

********************************************************************************
* 2. crosswalk -- attach cleaned_nsu_unit / harmonized_nsu_unit from
*    outputs/tables/master_nsu_rename.csv, single source of truth for the fold rule
********************************************************************************
import delimited using "${tables}/master_nsu_rename.csv", clear varnames(1) ///
	stringcols(_all) encoding("utf-8")
keep province pull_municipal_city cons_name pull_nsu_unit cleaned_nsu_unit harmonized_nsu_unit

gen str100 P = province
gen str100 C = pull_municipal_city
gen str100 I = cons_name
gen str100 U = pull_nsu_unit
nsu_normalize, item(I) unit(U) mun(C) province(P)

* cleaned_nsu_unit / harmonized_nsu_unit are ALSO nz()'d on the Python side before
* being stored as the join's payload (see the mk dict comprehension) -- match that.
gen str100 cleaned  = cleaned_nsu_unit
gen str100 _dummy1  = cleaned_nsu_unit
nsu_normalize, item(_dummy1) unit(cleaned)

gen str100 harm     = harmonized_nsu_unit
gen str100 _dummy2  = harmonized_nsu_unit
nsu_normalize, item(_dummy2) unit(harm)

keep P C I U cleaned harm

* The Python builds a dict keyed on (P,C,I,U), which silently keeps the LAST row on
* a collision. Assert there are none post-normalization instead of replicating that
* arbitrary tie-break -- a future collision here means this port and the Python
* reference would pick different winners without either erroring.
duplicates tag P C I U, gen(_dup)
quietly count if _dup>0
if r(N)>0 {
	di as err "validate_folds.do: `r(N)' rows of master_nsu_rename.csv collide on"
	di as err "the normalized (province,mun,item,unit) key. The Python reference"
	di as err "silently keeps the last row in file order on a collision; this port"
	di as err "does not replicate that. Investigate before trusting any output below."
	exit 459
}
drop _dup
save "`outdir'/_crosswalk.dta", replace

********************************************************************************
* 3. merge -- matches raw[raw.harm.notna()]
********************************************************************************
use "`outdir'/_matched_raw.dta", clear
merge m:1 P C I U using "`outdir'/_crosswalk.dta"

quietly count
local ntot = r(N)
quietly count if _merge==3
local nmatch = r(N)
di as txt "raw size-weighings: `ntot' rows | matched to master: " ///
	%4.1f (100*`nmatch'/`ntot') "% (" (`ntot'-`nmatch') " unmatched dropped)"

keep if _merge==3
drop _merge
save "`outdir'/_matched.dta", replace

********************************************************************************
* 4. (A) FOLD VALIDATION -- pairs to test
*
* For each (item, harmonized_nsu_unit) pooling >=2 cleaned labels with >=MIN_LABEL_N
* obs, the reference label is the highest-count one (matches Python's
* value_counts() descending-count order -- ties are not present in the current
* build; see the comment at the sort below if that ever changes), and every other
* qualifying label is compared against it -- NOT all pairwise combinations.
********************************************************************************
use "`outdir'/_matched.dta", clear
contract I harm cleaned, freq(cnt)
keep if cnt>=`MIN_LABEL_N'
bysort I harm: gen long nlabs = _N
keep if nlabs>=2

* Sort each (I,harm) group by count descending -- ties broken alphabetically by
* label for determinism; the current build has no ties at this step (verified
* against the Python reference), so this tie-break is untested territory, not a
* silent behavior change.
gsort I harm -cnt cleaned
by I harm: gen long rk = _n
by I harm: gen str100 reflabel = cleaned[1]
keep if rk>1
rename cleaned otherlabel
keep I harm reflabel otherlabel
save "`outdir'/_pairs_A.dta", replace

use "`outdir'/_pairs_A.dta", clear
local NPAIRS = _N
di as res _n "===== (A) FOLD VALIDATION: `NPAIRS' pooled-label pair(s) to test ====="
forvalues i = 1/`NPAIRS' {
	local Ai_`i' = I[`i']
	local Hi_`i' = harm[`i']
	local Ri_`i' = reflabel[`i']
	local Oi_`i' = otherlabel[`i']
}

tempname postA
postfile `postA' str100 item str100 harmonized str100 label_ref str100 label_other ///
	str100 verdict double p double size_ctrl_ratio long n_strata ///
	double med_ref_med_g double med_other_med_g using "`outdir'/_resultsA.dta", replace

forvalues i = 1/`NPAIRS' {
	use "`outdir'/_matched.dta", clear
	keep if I=="`Ai_`i''" & harm=="`Hi_`i''" & inlist(cleaned, "`Ri_`i''", "`Oi_`i''")

	gen byte isA = (cleaned=="`Ri_`i''")
	egen long stratum = group(P size dim)

	mata: nsu_van_elteren(`MIN_LABEL_N', `MIN_STRATA', `RATIO_HI', `RATIO_LO')
	* p MUST be a Stata SCALAR, not a local macro. `local x = r(p)' converts the
	* double to text using a default ~13-significant-digit format on assignment --
	* verified directly: a double holding 4.292190504903875e-15 round-trips through
	* a local as 4.29219050490e-15, silently dropping the last 5+ significant
	* digits, while `scalar x = r(p)' keeps the full double. p is reported at full
	* precision in the CSV, so it cannot go through a local anywhere in this chain.
	scalar p_i      = r(p)
	local ratio_i   = r(ratio)
	local nstr_i    = r(nstr)
	local verdict_i = "`r(verdict)'"

	gen byte _fref = (cleaned=="`Ri_`i''" & size=="medium_size")
	gen byte _foth = (cleaned=="`Oi_`i''" & size=="medium_size")
	mata: st_numscalar("r(medref)", nsu_median_if("w","_fref"))
	mata: st_numscalar("r(medoth)", nsu_median_if("w","_foth"))
	mata: st_numscalar("r(medref_r)", nsu_round_even(st_numscalar("r(medref)"), 0))
	mata: st_numscalar("r(medoth_r)", nsu_round_even(st_numscalar("r(medoth)"), 0))
	mata: st_numscalar("r(ratio_r)", nsu_round_even(`ratio_i', 2))
	local medref_r = r(medref_r)
	local medoth_r = r(medoth_r)
	local ratio_r  = r(ratio_r)

	di as txt "  `Ai_`i'' | `Hi_`i'' | `Ri_`i'' vs `Oi_`i'' -> `verdict_i'  p=" p_i "  ratio=`ratio_r'  nstr=`nstr_i'"

	post `postA' (`"`Ai_`i''"') (`"`Hi_`i''"') (`"`Ri_`i''"') (`"`Oi_`i''"') ///
		(`"`verdict_i'"') (p_i) (`ratio_r') (`nstr_i') (`medref_r') (`medoth_r')
}
postclose `postA'

********************************************************************************
* 5. (B) SPLIT VALIDATION -- documented keep-separate pairs, carried over as-is
*    from validate_folds.py's SPLITS list (item substring filter, harm A, harm B;
*    '' item = any item). Do not re-derive; this is a hardcoded policy list.
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

di as res _n "===== (B) SPLIT VALIDATION: `NSPLITS' documented keep-separate pair(s) ====="

tempname postB
postfile `postB' str100 item str100 harm_A str100 harm_B str100 verdict double p ///
	double size_ctrl_ratio long n_strata double med_A_med_g double med_B_med_g ///
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
		di as txt "  spec `i' (`itemlabel', `ha`i'', `hb`i'') -> absent (no matching rows at all)"
		post `postB' (`"`itemlabel'"') (`"`ha`i''"') (`"`hb`i''"') ("absent") (.) (.) (0) (.) (.)
	}
	else {
		save "`outdir'/_splitsubset.dta", replace

		* items where BOTH harm values are present (already restricted harm to
		* {ha,hb} above, so "both present" <=> exactly 2 distinct harm values for
		* that item) -- matches set(gi.harm.unique())=={ha,hb}. Sorted ascending
		* on I to match pandas groupby's default sorted iteration order.
		contract I harm
		bysort I: gen long nharm = _N
		keep if nharm==2
		quietly count
		local nqual = r(N)

		if `nqual' == 0 {
			di as txt "  spec `i' (`ha`i'', `hb`i'') -> no item has both harm values present; 0 rows (matches Python: no 'absent' row is written here either)"
		}
		else {
			duplicates drop I, force
			sort I
			local nqual = _N
		}

		forvalues q = 1/`nqual' {
			local itemq = I[`q']

			use "`outdir'/_splitsubset.dta", clear
			keep if I=="`itemq'"

			gen byte isA = (harm=="`ha`i''")
			egen long stratum = group(P size dim)

			mata: nsu_van_elteren(`MIN_LABEL_N', `MIN_STRATA', `RATIO_HI', `RATIO_LO')
			* p as a SCALAR, not a local -- see the comment at the Panel A loop:
			* a local macro's default numeric-to-text conversion silently drops
			* p down to ~13 significant digits, and p is reported at full
			* double precision in the CSV.
			scalar p_i      = r(p)
			local ratio_i   = r(ratio)
			local nstr_i    = r(nstr)
			local verdict_i = "`r(verdict)'"

			gen byte _fA = (harm=="`ha`i''" & size=="medium_size")
			gen byte _fB = (harm=="`hb`i''" & size=="medium_size")
			mata: st_numscalar("r(medA)", nsu_median_if("w","_fA"))
			mata: st_numscalar("r(medB)", nsu_median_if("w","_fB"))
			mata: st_numscalar("r(medA_r)", nsu_round_even(st_numscalar("r(medA)"), 0))
			mata: st_numscalar("r(medB_r)", nsu_round_even(st_numscalar("r(medB)"), 0))
			mata: st_numscalar("r(ratio_r)", nsu_round_even(`ratio_i', 2))
			local medA_r = r(medA_r)
			local medB_r = r(medB_r)
			local ratio_r = r(ratio_r)

			di as txt "  `itemq' | `ha`i'' vs `hb`i'' -> `verdict_i'  p=" p_i "  ratio=`ratio_r'  nstr=`nstr_i'"

			post `postB' (`"`itemq'"') (`"`ha`i''"') (`"`hb`i''"') (`"`verdict_i'"') ///
				(p_i) (`ratio_r') (`nstr_i') (`medA_r') (`medB_r')
		}
	}
}
postclose `postB'

********************************************************************************
* 6. write the CSVs -- same header/column order as validate_folds.py, and CSV
*    quoting (double quotes around any field containing a comma) applied by hand
*    since this is written with `file write`, not `export delimited`, to keep
*    full double precision on the p-values (see the .do header).
********************************************************************************
capture program drop nsu_csvquote
program define nsu_csvquote
	* args: source-strvar  new-strvar (quoted-for-csv)
	args src dst
	gen str200 `dst' = `src'
	replace `dst' = subinstr(`dst', `"""', `""""', .)
	replace `dst' = `"""' + `dst' + `"""' if strpos(`src', ",") | strpos(`src', `"""')
end

* ---- Panel A -------------------------------------------------------------------
use "`outdir'/_resultsA.dta", clear
nsu_csvquote item       item_q
nsu_csvquote harmonized harmonized_q
nsu_csvquote label_ref  label_ref_q
nsu_csvquote label_other label_other_q

local N = _N
file open fhA using "`outdir'/fold_validation_A.csv", write text replace
file write fhA "item,harmonized,label_ref,label_other,verdict,p,size_ctrl_ratio,n_strata,med_ref_med_g,med_other_med_g" _n
forvalues i = 1/`N' {
	local it = item_q[`i']
	local hm = harmonized_q[`i']
	local lr = label_ref_q[`i']
	local lo = label_other_q[`i']
	local vd = verdict[`i']

	local pp = p[`i']
	local rr = size_ctrl_ratio[`i']
	local ns = n_strata[`i']
	local mr = med_ref_med_g[`i']
	local mo = med_other_med_g[`i']

	* %30.17g, NOT %21.17g -- a narrower field WIDTH silently caps the digits Stata
	* will print below the 17 significant figures requested by the .17g precision
	* (verified: %21.17g on 4.292190504903875e-15 prints only "4.29219050490387e-15",
	* 15 sig figs, while %30.17g on the same double prints the full
	* "4.2921905049038749e-15"). The field width has to be generous, not exact.
	*
	* CRITICAL: string() is applied to p[`i'] DIRECTLY, not to the `pp' local.
	* `local pp = p[`i']' already truncated p to ~13 significant digits on
	* assignment (a local macro's default numeric-to-text conversion) -- verified
	* directly: a double holding 4.292190504903875e-15 round-trips through a local
	* as 4.29219050490e-15. `pp' is kept ONLY for the missing-value test, which
	* does not need precision.
	if `pp'>=.  local pp_s ""
	else        local pp_s = string(p[`i'], "%30.17g")
	if `rr'>=.  local rr_s ""
	else        local rr_s = string(`rr', "%30.17g")
	if `mr'>=.  local mr_s ""
	else        local mr_s = string(`mr', "%30.17g")
	if `mo'>=.  local mo_s ""
	else        local mo_s = string(`mo', "%30.17g")

	file write fhA `"`it'"' "," `"`hm'"' "," `"`lr'"' "," `"`lo'"' "," ///
		"`vd'" "," `"`pp_s'"' "," `"`rr_s'"' "," (`ns') "," `"`mr_s'"' "," `"`mo_s'"' _n
}
file close fhA
di as res _n "wrote `outdir'/fold_validation_A.csv (`N' rows)"

* ---- Panel B -------------------------------------------------------------------
use "`outdir'/_resultsB.dta", clear
nsu_csvquote item   item_q
nsu_csvquote harm_A harm_A_q
nsu_csvquote harm_B harm_B_q

local N = _N
file open fhB using "`outdir'/fold_validation_B.csv", write text replace
file write fhB "item,harm_A,harm_B,verdict,p,size_ctrl_ratio,n_strata,med_A_med_g,med_B_med_g" _n
forvalues i = 1/`N' {
	local it = item_q[`i']
	local ha = harm_A_q[`i']
	local hb = harm_B_q[`i']
	local vd = verdict[`i']

	local pp = p[`i']
	local rr = size_ctrl_ratio[`i']
	local ns = n_strata[`i']
	local ma = med_A_med_g[`i']
	local mb = med_B_med_g[`i']

	* p read directly from p[`i'] -- see the identical note in the Panel A writer:
	* `pp' already lost precision on assignment and is kept only for the missing test.
	if `pp'>=.  local pp_s ""
	else        local pp_s = string(p[`i'], "%30.17g")
	if `rr'>=.  local rr_s ""
	else        local rr_s = string(`rr', "%30.17g")
	if `ma'>=.  local ma_s ""
	else        local ma_s = string(`ma', "%30.17g")
	if `mb'>=.  local mb_s ""
	else        local mb_s = string(`mb', "%30.17g")

	file write fhB `"`it'"' "," `"`ha'"' "," `"`hb'"' "," ///
		"`vd'" "," `"`pp_s'"' "," `"`rr_s'"' "," (`ns') "," `"`ma_s'"' "," `"`mb_s'"' _n
}
file close fhB
di as res "wrote `outdir'/fold_validation_B.csv (`N' rows)"

di as res _n "{hline 78}"
di as res "validate_folds.do complete."
di as res "outputs/temp/_folds_port/fold_validation_A.csv and _B.csv are ready to diff"
di as res "against outputs/temp/fold_validation_A.csv and _B.csv (the Python reference)."
di as res "{hline 78}"
