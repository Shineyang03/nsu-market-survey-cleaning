********************************************************************************
* nsu_rank_test.do -- THE stratified rank test for this project, defined once.
*
* WHY THIS FILE EXISTS. Three panels of 90_diagnostics/validate_folds.do ask the same
* question of different label pairs -- do these two labels weigh the same? -- and the
* answer decides whether the labels are pooled, which decides every published gram
* figure downstream. A decision rule that important gets ONE definition. It used to
* live inside validate_folds.do; a second caller was enough reason to lift it out.
*
* Nothing here reads a dataset off disk or knows what a fold is. It takes three
* variables already in memory and returns numbers. Everything about WHICH labels are
* being compared lives in the caller.
*
* WHAT THE CALLER MUST HAVE IN MEMORY
*     x        double   the measurement, ALREADY LOGGED   (see "why logs" below)
*     isA      0/1      1 for label A's rows, 0 for label B's
*     stratum  numeric  group id; rows are only ever compared within one
*
* ENTRY POINT
*     mata: nsu_fold_test(MIN_LABEL_N, MIN_STRATA, LNLO, LNHI, ALPHA, NPERM, SEED)
*
* returning, in r():
*     verdict        equivalent | equivalent-though-distinguishable | different |
*                    inconclusive
*     p_tost_lo      one-sided p against "the ratio is at or below the lower bound"
*     p_tost_hi      one-sided p against "the ratio is at or above the upper bound"
*     p_nil          two-sided p against "the labels do not differ at all"
*     p_nil_norm     the same, from the normal approximation, for comparison only
*     ratio_hl       Hodges-Lehmann point estimate of the ratio A/B
*     nstr nA nB     strata used, and each label's in-stratum count
*     ratio_p25/p75  spread of the per-stratum median ratios -- the heterogeneity read
*
********************************************************************************
* THE TEST
*
* The statistic is a van Elteren stratified rank test: a stratified Wilcoxon rank-sum
* with design-free weights 1/(n_h+1), on tie-corrected ranks.
*
*   per stratum h:  W_a   = sum of average ranks of A's obs in the pooled a+b ranks
*                   E     = n_a*(n+1)/2
*                   tie   = sum(cnt_v^3 - cnt_v) over distinct pooled values v
*                   var_h = n_a*n_b/12 * [(n+1) - tie/(n*(n-1))]      (n>1, else 0)
*   combined:       T = sum_h [ (W_a,h - E_h) / (n_h+1) ]
*                   V = sum_h [ var_h / (n_h+1)^2 ]
*
* WHY THE NULL IS REVERSED. The obvious test -- "is there a difference?" -- cannot
* answer the question the pipeline actually asks, which is "may these two labels be
* pooled?". A large p-value from that test is FAILURE TO REJECT, not evidence of
* agreement, so treating it as a licence to pool makes the worst-measured pairs the
* most likely to be pooled. The incentive points exactly the wrong way, and not only
* in theory: in a thin stratum the attainable p-values are a finite set, and a
* configuration can exist where p cannot fall below 0.05 under any data whatsoever.
* Such a pair would be pooled automatically, forever, no matter what was weighed.
*
* So the null is inverted, in the standard two-one-sided-tests (TOST) form:
*
*     H0 : the labels differ by MORE than the tolerance band
*     H1 : they differ by less
*
* and folding requires REJECTING H0. Thin data now fails to reject and the labels stay
* separate, which is the conservative direction. Two one-sided tests are run, one
* against each edge of the band, and equivalence is declared only if BOTH reject.
*
* There is no confidence interval in the decision path: TOST needs two one-sided
* tests, not an interval. (An interval is the equivalent presentation. If one is ever
* reported alongside these p-values it must be a 90% interval, not 95% -- alpha=0.05
* per side corresponds to 100(1-2*alpha)% = 90%. Pairing a 95% interval with an
* alpha=0.05 TOST claim is a common and over-conservative error.)
*
* Crossing TOST with the ordinary "do they differ at all" test gives a THREE-WAY
* verdict. The third outcome is the one the old two-way rule could not express:
*
*     TOST rejects, nil does not     equivalent                          -> fold
*     TOST rejects, nil rejects      equivalent-though-distinguishable   -> fold
*     TOST fails,   nil rejects      different                           -> keep apart
*     TOST fails,   nil fails        inconclusive                        -> keep apart,
*                                                                           and go and
*                                                                           look at the
*                                                                           photograph
*
* WHY LOGS. The band is a RATIO band, and [0.80, 1.25] is symmetric only on the log
* scale: ln(0.80) = -0.22314, ln(1.25) = +0.22314. Testing an untransformed ratio
* against those two numbers would give a lopsided test, strict on one side and slack
* on the other. The caller passes x already logged; the band is passed as its logs.
*
* WHY PERMUTATION p-VALUES. The normal approximation to z = T/sqrt(V) is unreliable in
* exactly the thin strata this test spends its time in, and it errs anti-conservatively
* -- which, under the reversed null, means it would declare equivalence too readily.
* Permuting the label assignment WITHIN each stratum (never across -- that is what the
* stratified design licenses) gives an exact test instead. p is computed as
*
*     (1 + #{as extreme as observed}) / (1 + NPERM)
*
* The +1 on both sides is required for validity when the permutation distribution is
* sampled rather than enumerated; without it the p-value is anti-conservative. The
* normal-approximation p is still reported, as p_nil_norm, so the two can be compared:
* a large divergence is a fact about that pair's strata and belongs in the output, not
* in a silent override.
*
* Permuting labels does not change the pooled ranks within a stratum -- only which
* ranks belong to A -- so the ranks are computed once per stratum and reused across
* all NPERM draws. That is what makes an exact test affordable here.
*
* TWO ASSUMPTIONS THIS TEST MAKES, NEITHER OF THEM FREE
*
*  1. LOCATION SHIFT. A rank statistic is a statement about location only if the two
*     distributions differ by a shift. Two labels can share a centre and differ in
*     SPREAD -- one of them used loosely by vendors, the other precisely -- and this
*     test cannot tell that apart from agreement. For a non-standard unit, whose
*     defining property is that it varies from vendor to vendor, that is a live
*     possibility rather than a formality.
*
*  2. A COMMON EFFECT ACROSS STRATA. The van Elteren statistic pools strata on the
*     presumption that the difference between the labels is the same in each. Under
*     real heterogeneity a pooled verdict can be narrow around an average that
*     describes no single market. ratio_p25 and ratio_p75 are returned so a caller can
*     see the per-stratum spread and refuse to trust a verdict that straddles the band.
*
* Neither assumption is testable at these sample sizes. Both are reasons the
* photograph review exists.
*
* THE MARGIN. [0.80, 1.25] is the FDA/EMA bioequivalence acceptance range. That is
* respectable precedent but it arrived here by coincidence of numbers, not by
* derivation from this survey. docs/implicit_assumptions.md records what a 25% weight
* error does to a published conversion factor, which is the justification that
* actually applies. The margin is pre-specified there and must not be tuned to make a
* particular fold pass.
********************************************************************************

version 19

mata:
mata clear

// ---------------------------------------------------------------------------
// numpy-consistent median: exact middle for odd n, average of the two middle
// order statistics for even n. Matches what the retired Python reference did, so
// figures recorded against that vintage stay comparable.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// average-rank ranking; ties take the mean of the ranks they span.
// ---------------------------------------------------------------------------
real colvector nsu_rank_avg(real colvector x)
{
	real scalar n, i, j, k, avgr
	real colvector o, xs, ranks
	n = rows(x)
	o = order(x, 1)
	xs = x[o]
	ranks = J(n,1,.)
	// Mata's `&' does not short-circuit, so "j<n & xs[j+1]==xs[i]" would evaluate
	// xs[j+1] even when j==n and throw a subscript error. Nest the checks instead.
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

// ---------------------------------------------------------------------------
// round(x,d) with ties to even, matching numpy/Python round() on floats -- NOT
// Stata's round(), which breaks ties away from zero.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// THE STATISTIC, at a candidate shift.
//
// Tests A - B = delta by comparing A against B+delta. Returns, as a row vector:
//   1 T          2 V          3 nstr       4 nA         5 nB
//   6 p_perm_two 7 p_perm_up  8 p_perm_lo  9 p_norm_two
//  10 ratio_p25 11 ratio_p50 12 ratio_p75   (per-stratum median ratios, exp'd)
//
// p_perm_up is the evidence that A exceeds B+delta; p_perm_lo that it falls short.
// NPERM<=0 skips the permutation and leaves 6-8 missing.
//
// Strata where either label is absent contribute nothing and are not counted.
// ---------------------------------------------------------------------------
real rowvector nsu_ve(real colvector x0, real colvector isA, real colvector strat,
                      real scalar delta, real scalar NPERM)
{
	real colvector x, ustr, idx, a, b, comb, r, uv, ratios, lr, seg, o
	real colvector nas, Es, wgts, allr, starts, lens
	real scalar i, k, h, na, nb, n, nstr, nA, nB, T, V, Wa, E, tie, cnt, varh, wgt
	real scalar z, pn, H, Tb, nge, nle, nab, ma, mb

	x = x0
	// shift B up by delta: under H0 the shifted samples are exchangeable within stratum
	if (delta != 0) x = x + (isA:==0):*delta

	ustr = uniqrows(strat)
	H = rows(ustr)
	nas  = J(H,1,.)
	Es   = J(H,1,.)
	wgts = J(H,1,.)
	// Each stratum's pooled ranks are kept for the permutation, STACKED into one
	// column with an offset and a length per stratum.
	//
	// They are deliberately NOT held as a vector of pointers. `&r' inside the loop
	// below would take the address of the loop VARIABLE, which the next iteration
	// overwrites -- so every pointer would end up aliasing the last stratum's ranks.
	// That bug is close to invisible in testing: if every stratum happens to hold the
	// same number of observations with no ties, all their rank vectors are 1..n and
	// identical, so the aliased version returns correct answers on regular synthetic
	// data and wrong ones on real data. Stacking has no such failure mode.
	allr   = J(0,1,.)
	starts = J(H,1,.)
	lens   = J(H,1,.)

	T = 0; V = 0; nstr = 0; nA = 0; nB = 0
	ratios = J(0,1,.)

	for (i=1; i<=H; i++) {
		idx = selectindex(strat:==ustr[i])
		a = select(x[idx], isA[idx]:==1)
		b = select(x[idx], isA[idx]:==0)
		na = rows(a); nb = rows(b)
		if (na<1 | nb<1) continue
		n = na + nb
		nstr = nstr + 1
		nA = nA + na
		nB = nB + nb

		// per-stratum ratio, back on the ratio scale. Built from the UNSHIFTED
		// values so it describes the data, not the hypothesis being tested.
		ma = nsu_median(select(x0[idx], isA[idx]:==1))
		mb = nsu_median(select(x0[idx], isA[idx]:==0))
		ratios = ratios \ (ma - mb)

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

		// keep for the permutation: the pooled ranks do not change when labels
		// are permuted, only which of them are counted into W_a
		allr         = allr \ r
		starts[nstr] = rows(allr) - rows(r) + 1
		lens[nstr]   = rows(r)
		nas[nstr]    = na
		Es[nstr]     = E
		wgts[nstr]   = wgt
	}

	// normal-approximation two-sided p. normal(-|z|), not 1-normal(|z|): the latter
	// cancels two numbers close to 1 and loses precision exactly where p is smallest.
	if (V>0) {
		z  = T/sqrt(V)
		pn = 2*normal(-abs(z))
	}
	else pn = .

	// permutation
	nge = .; nle = .; nab = .
	if (NPERM>0 & nstr>0 & V>0) {
		nge = 0; nle = 0; nab = 0
		for (i=1; i<=NPERM; i++) {
			Tb = 0
			for (h=1; h<=nstr; h++) {
				// draw n_a of this stratum's ranks at random, without
				// replacement -- that IS the within-stratum relabelling.
				// order(runiform(...)) rather than jumble() so the code does
				// not depend on whether jumble copies or permutes in place.
				seg = allr[|starts[h] \ starts[h]+lens[h]-1|]
				o   = order(runiform(lens[h],1), 1)
				Tb  = Tb + wgts[h]*(sum(seg[o[1::nas[h]]]) - Es[h])
			}
			if (Tb >=  T)      nge = nge + 1
			if (Tb <=  T)      nle = nle + 1
			if (abs(Tb)>=abs(T)) nab = nab + 1
		}
		// (1 + count)/(1 + NPERM) -- the +1 is what keeps a sampled permutation
		// distribution valid rather than anti-conservative
		nab = (1+nab)/(1+NPERM)
		nge = (1+nge)/(1+NPERM)
		nle = (1+nle)/(1+NPERM)
	}

	if (rows(ratios)>0) {
		lr = sort(ratios,1)
		return((T, V, nstr, nA, nB, nab, nge, nle, pn,
		        exp(lr[max((1,ceil(0.25*rows(lr))))]),
		        exp(nsu_median(ratios)),
		        exp(lr[max((1,ceil(0.75*rows(lr))))])))
	}
	return((T, V, nstr, nA, nB, nab, nge, nle, pn, ., ., .))
}

// ---------------------------------------------------------------------------
// The size-controlled ratio, on the RAW scale: the median, over strata where both
// labels appear, of (median of A) / (median of B).
//
// This duplicates nothing -- it is a different quantity from the ratio_p50 that
// nsu_ve returns, which is built from logged values. The two agree exactly on
// odd-sized strata and differ slightly on even ones, where a median of logs is a
// geometric mean of the two central values and a median of levels is an arithmetic
// one. This function exists so the `size_ctrl_ratio' column keeps the definition it
// had before the test was rewritten, and stays comparable with the figures already
// recorded in docs/master_rename.md and verify_pipeline.py's ACKNOWLEDGED list.
//
// Expects `w' (raw weight), `isA' and `stratum' in memory.
// ---------------------------------------------------------------------------
real scalar nsu_size_ctrl_ratio()
{
	real colvector w, isA, strat, ustr, idx, a, b, ratios
	real scalar i, mb
	st_view(w=.,     ., "w")
	st_view(isA=.,   ., "isA")
	st_view(strat=., ., "stratum")
	ustr = uniqrows(strat)
	ratios = J(0,1,.)
	for (i=1; i<=rows(ustr); i++) {
		idx = selectindex(strat:==ustr[i])
		a = select(w[idx], isA[idx]:==1)
		b = select(w[idx], isA[idx]:==0)
		if (rows(a)<1 | rows(b)<1) continue
		mb = nsu_median(b)
		if (mb>0) ratios = ratios \ (nsu_median(a)/mb)
	}
	if (rows(ratios)>0) return(nsu_median(ratios))
	return(.)
}

// ---------------------------------------------------------------------------
// Hodges-Lehmann point estimate: the shift at which the statistic is zero.
// T is monotone decreasing in delta -- raising B lowers A's ranks -- so bisection
// is safe. Returned on the LOG scale; the caller exponentiates.
// ---------------------------------------------------------------------------
real scalar nsu_hl(real colvector x, real colvector isA, real colvector strat)
{
	real scalar lo, hi, mid, i, Tlo, Thi, Tmid
	lo = -10; hi = 10
	Tlo = nsu_ve(x, isA, strat, lo, 0)[1]
	Thi = nsu_ve(x, isA, strat, hi, 0)[1]
	if (Tlo < 0 | Thi > 0) return(.)      // not bracketed; nothing sensible to return
	for (i=1; i<=60; i++) {
		mid  = (lo+hi)/2
		Tmid = nsu_ve(x, isA, strat, mid, 0)[1]
		if (Tmid > 0) lo = mid
		else          hi = mid
	}
	return((lo+hi)/2)
}

// ---------------------------------------------------------------------------
// THE ENTRY POINT. Runs the three tests, applies the verdict rule, posts to r().
// ---------------------------------------------------------------------------
void nsu_fold_test(real scalar MIN_LABEL_N, real scalar MIN_STRATA,
                   real scalar LNLO, real scalar LNHI,
                   real scalar ALPHA, real scalar NPERM, real scalar SEED)
{
	real colvector x, isA, strat
	real rowvector nil, tlo, thi
	real scalar p_nil, p_lo, p_hi, hl, tost, nilrej
	string scalar verdict

	st_view(x=.,     ., "x")
	st_view(isA=.,   ., "isA")
	st_view(strat=., ., "stratum")

	rseed(SEED)

	// the ordinary "do they differ at all" test, at no shift
	nil = nsu_ve(x, isA, strat, 0, NPERM)

	// the count gate. Unchanged from the two-way rule: too few strata, too few
	// observations on a label, or a degenerate variance means the test has nothing
	// to say -- which under the reversed null is `inconclusive', the same decision
	// the old `insufficient' produced. It is now named for what it means.
	if (nil[3]<MIN_STRATA | nil[4]<MIN_LABEL_N | nil[5]<MIN_LABEL_N | nil[2]<=0) {
		// r(gated)=1 says the test NEVER RAN -- the data were not there to run it.
		// That is different from running and returning `inconclusive', even though
		// both keep the labels apart, and the caller must be able to tell them
		// apart. A caller may legitimately retry a GATED pair on coarser strata,
		// because the obstacle was data availability. It must NOT retry a pair that
		// ran and came back inconclusive: coarser strata have more power, so
		// retrying until one resolves is fishing for a fold, and would reintroduce
		// through the back door exactly the bias the reversed null removes.
		st_numscalar("r(gated)", 1)
		st_global("r(verdict)", "inconclusive")
		st_numscalar("r(p_nil)",      .)
		st_numscalar("r(p_tost_lo)",  .)
		st_numscalar("r(p_tost_hi)",  .)
		st_numscalar("r(p_nil_norm)", nil[9])
		st_numscalar("r(ratio_hl)",   .)
		st_numscalar("r(nstr)", nil[3])
		st_numscalar("r(nA)",   nil[4])
		st_numscalar("r(nB)",   nil[5])
		st_numscalar("r(ratio_p25)", nil[10])
		st_numscalar("r(ratio_p50)", nil[11])
		st_numscalar("r(ratio_p75)", nil[12])
		return
	}

	// TOST lower: H0 says the ratio is at or below exp(LNLO). Reject it with
	// evidence that A sits ABOVE B+LNLO -- the upper tail.
	tlo = nsu_ve(x, isA, strat, LNLO, NPERM)
	p_lo = tlo[7]

	// TOST upper: H0 says the ratio is at or above exp(LNHI). Reject it with
	// evidence that A sits BELOW B+LNHI -- the lower tail.
	thi = nsu_ve(x, isA, strat, LNHI, NPERM)
	p_hi = thi[8]

	p_nil = nil[6]
	hl    = nsu_hl(x, isA, strat)

	tost   = (max((p_lo, p_hi)) < ALPHA)   // BOTH one-sided tests must reject
	nilrej = (p_nil < ALPHA)

	if      ( tost &  nilrej) verdict = "equivalent-though-distinguishable"
	else if ( tost & !nilrej) verdict = "equivalent"
	else if (!tost &  nilrej) verdict = "different"
	else                      verdict = "inconclusive"

	st_numscalar("r(gated)", 0)          // the test ran; see the note above
	st_global("r(verdict)", verdict)
	st_numscalar("r(p_nil)",      p_nil)
	st_numscalar("r(p_tost_lo)",  p_lo)
	st_numscalar("r(p_tost_hi)",  p_hi)
	st_numscalar("r(p_nil_norm)", nil[9])
	st_numscalar("r(ratio_hl)",   hl<. ? exp(hl) : .)
	st_numscalar("r(nstr)", nil[3])
	st_numscalar("r(nA)",   nil[4])
	st_numscalar("r(nB)",   nil[5])
	st_numscalar("r(ratio_p25)", nil[10])
	st_numscalar("r(ratio_p50)", nil[11])
	st_numscalar("r(ratio_p75)", nil[12])
}
end

di as txt "nsu_rank_test.do loaded -- nsu_fold_test() available"
