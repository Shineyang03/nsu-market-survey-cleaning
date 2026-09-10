from pathlib import Path
import sys
"""
Validate NSU fold decisions on the RAW survey weighings, controlling for size.

Why: weight varies ~3x across obs_type size classes (small~80g / medium~152g / large~230g), so a raw
median gap between two labels can be pure size-mix, not a true referent difference. And only the
small/medium/large_size rows are physical weighings -- municipality/province_median and *_price rows are
derived aggregates and must be excluded.

Design (user choice): keep obs_type in {small,medium,large}_size only; compare labels WITHIN
(province x size x measurement-unit) strata via a van Elteren stratified rank test (stratified Wilcoxon,
design-free weights 1/(n_h+1)). Labels/harmonized units are attached by joining raw weighings to
master_nsu_rename.csv, so the fold rule stays single-sourced in 00_shared/01_build_crosswalk.py.

Two questions:
  (A) FOLD validation   : for each (item, harmonized_unit) that pools >=2 cleaned labels, do those labels
                          actually agree in weight? (significant difference => the pool is suspect)
  (B) SPLIT validation  : for documented keep-separate pairs, do they actually differ? (no difference =>
                          the split may be unnecessary)
"""
import pandas as pd, numpy as np, re
from collections import defaultdict
from scipy.stats import norm
BOX=r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
# The one definition of the project's string normalization, imported rather than
# copied. There used to be eleven byte-identical copies of these four functions across
# 90_diagnostics/; a fix to any one of them reached none of the others. The Stata
# counterpart is nsu_normalize in 00_shared/00_globals.do and must agree with it
# character for character -- see the module docstring.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import A, nz, ni, ng

SIZES={'small_size','medium_size','large_size'}
MIN_LABEL_N=10      # a label needs >=this many informative (in-stratum) obs to be testable
MIN_STRATA=2        # need >=this many strata where BOTH labels appear

# ---- weighings: RAW names/sizes + CLEANED weights ----
# Source = nsu_data, which keeps the raw pull_nsu_unit AND the pipeline-corrected weight/unit (mass->g,
# vol->mL, order-of-magnitude entry errors fixed). Size = item_nsu_hetero_type (== the raw obs_type:
# small/medium/large_size). This avoids the raw 'weight' column's mixed units (g/kg/L) and magnitude
# errors, while still keying on the RAW unit name (not cleaned_nsu_unit).
# THIS READ WAS STALE, and silently so for six weeks. It pointed at
# outputs/temp/nsu_data.dta -- written by archive/cleaning.do, the PRE-AUG11 build,
# last touched 27 July and holding 11,259 rows against the live 11,335. So every run
# since then scored the fold rule against weights that predate the anchor snap (#18 A1),
# the snap adjudication, and all 227 adjudicated review verdicts.
#
# That matters beyond tidiness. nsu_fold_rule.py cites this script for the ONE carve-out
# justified by a statistic -- "camote bilog != binilog (p=0.004, ratio 1.61)". Re-running
# after three rounds of weight corrections reproduced that figure exactly, which looked
# like the carve-out surviving the corrections. It was not: the INPUT had not changed.
# A diagnostic that cannot see the build it is meant to validate reproduces its own past
# answer no matter what happens upstream, which is worse than not running at all.
#
# Same defect that archived summarize_corrected_weight_by_cell.do, build_forests.py and
# build_forest_medians.py -- all three hardcoded this same path. See archive/README.md.
#
# ---- WHICH WEIGHT, AND WHY IT IS A PARAMETER --------------------------------------
# `--weight' selects what the test measures. This is not a convenience: the default is
# CIRCULAR and the alternative is the point.
#
#   corrected  the published weight. 04_unit_snap.do snapped it toward the median of a
#              pool keyed on harmonized_nsu_unit -- so two labels FOLDED TOGETHER were
#              snapped toward one median, which nudges this test toward "they weigh the
#              same", which is what justified folding them. The fold decision and the
#              evidence for it are not independent.
#   block      the block reading, w_block, kept by 04_unit_snap.do. The typed number in
#              canonical units: a function of the raw weight, the unit tick and KGMAX
#              alone. NO POOL IS INVOLVED, so it carries no grouping bias in either
#              direction. Noisier -- the decade entry errors the snap exists to fix are
#              still in it -- but the noise is not correlated with the fold under test.
#
# `--build' points at a variant subtree (see 00_globals.do's ${build_name}). Combined with
# a variant built on ${unitvar}="pull_nsu_unit", it gives a third reading: snapped weights
# whose pool was keyed on the RAW label, so the pool boundary does not depend on the fold.
# That one is decade-corrected AND independent of the carve-out -- but it biases the other
# way, pooling each label separately and so nudging toward "they differ".
#
# Run all three and compare. Agreement means the circularity was harmless in practice.
# THE DEFAULT IS `block', and that is the decision this file exists to encode. The
# published weight is available with --weight=corrected for comparison, but it must not
# be what the fold policy is judged on: the grouping under test helped produce it.
_ARGS=dict(weight='block', build='master_rename_build')
for _a in sys.argv[1:]:
    if _a.startswith('--weight='): _ARGS['weight']=_a.split('=',1)[1]
    elif _a.startswith('--build='): _ARGS['build']=_a.split('=',1)[1]
    elif _a in ('-h','--help'):
        sys.exit(__doc__+"\nusage: validate_folds.py [--weight=corrected|block] "
                 "[--build=<subtree under outputs/>]")
    else: sys.exit(f"unknown argument {_a!r}; try --help")
if _ARGS['weight'] not in ('corrected','block'):
    sys.exit("--weight must be 'corrected' or 'block'")
_WCOL={'corrected':'corrected_weight','block':'w_block'}[_ARGS['weight']]
_DTA=(Path(BOX)/'Data Cleaning'/'outputs'/_ARGS['build']/'temp'/'nsu_weighings_cpi.dta')
if not _DTA.exists():
    sys.exit(f"no build at {_DTA}\nBuild a variant with 90_diagnostics/"
             "measure_anchor_keying.do, which writes to its own subtree.")
print(f"[validate_folds] weight={_ARGS['weight']} ({_WCOL})  build={_ARGS['build']}")

# ONLY THE DEFAULT RUN MAY WRITE THE CANONICAL FILENAMES. fold_validation_A.csv and
# fold_validation_B.csv are what verify_pipeline.py check 3 reads back to decide whether a
# folded group contradicts its own weight test. A variant run landing on those names would
# leave the build verified against a test it never agreed to -- the same class of failure
# as this script's own six-week stale read, but pointing forward instead of backward.
_TAG=('' if (_ARGS['weight']=='block' and _ARGS['build']=='master_rename_build')
      else f"_{_ARGS['weight']}"
           + ('' if _ARGS['build']=='master_rename_build' else f"_{_ARGS['build']}"))
def _OUT(p):
    return Path(BOX)/'Data Cleaning'/'outputs'/'temp'/f'fold_validation_{p}{_TAG}.csv'

raw=pd.read_stata(_DTA,
                  columns=['pull_province','pull_municipal_city','pull_item','pull_nsu_unit',
                           'item_nsu_hetero_type','corrected_unit',_WCOL])
# ---- the block reading must be the one computed UPSTREAM of the harmonization ------
# w_block is read off the built weighings for convenience -- that file also carries the
# labels, sizes and dimension this test strata on. But its VALUE has to be the one
#00_shared/03a_block_reading.do produced before 03_clean_ms.do merged the crosswalk,
# because that is the entire basis for calling this test non-circular.
#
# 04_unit_snap.do merges block_reading.dta in and rounds it at save, so the two should
# agree to the rounding and nothing else. If they ever diverge, someone has reintroduced
# a computation of the block reading downstream of the fold decisions, and this test is
# quietly circular again. That is not a difference worth tolerating silently: it is the
# exact failure the restructure removed.
if _ARGS['weight']=='block':
    _bp=Path(BOX)/'Data Cleaning'/'outputs'/_ARGS['build']/'temp'/'block_reading.dta'
    if not _bp.exists():
        sys.exit(f"no block_reading.dta at {_bp}\n"
                 "It is written by 00_shared/03a_block_reading.do, called from "
                 "03_clean_ms.do before the crosswalk merge. Rebuild.")
    _up=pd.read_stata(_bp).set_index('id').w_block
    _tmp=pd.read_stata(_DTA,columns=['id','w_block']).set_index('id').w_block
    _both=pd.concat([_tmp.rename('build'),_up.rename('upstream')],axis=1,join='inner')
    # Tested as "the build holds a valid rounding of the upstream value", NOT by rounding
    # both sides and comparing. Stata's round() breaks a .5 tie away from zero and
    # numpy's breaks it to even, so id 5189 -- weight 20.5 g, block reading 20.5 --
    # is stored as 21 by the build and rounds to 20 in pandas. That is a disagreement
    # between two rounding conventions, not evidence of a recomputation, and reporting it
    # as one sent me looking for a pipeline defect that was not there.
    _gap=(_both.build-_both.upstream).abs()
    _off=(_gap>0.5+1e-9) & _both.build.notna() & _both.upstream.notna()
    _off|=_both.build.isna()!=_both.upstream.isna()
    if _off.any():
        sys.exit(f"{int(_off.sum())} of {len(_both)} block readings on the build are not "
                 "a rounding of 03a_block_reading.do's output.\nThe build's w_block is "
                 "supposed to BE that output, merged in and rounded to the unit. A "
                 "downstream recomputation would make this test circular again -- find "
                 "it before trusting any verdict below.\n"
                 f"worst gap: {_gap[_off].max():.4g} at id {_gap[_off].idxmax()}")
    print(f"[validate_folds] w_block matches 03a's upstream output on all "
          f"{len(_both):,} shared ids")

raw['size']=raw.item_nsu_hetero_type.astype(str)
raw=raw[raw['size'].isin(SIZES)].copy()
raw['w']=pd.to_numeric(raw[_WCOL],errors='coerce')
raw=raw[raw.w.notna() & (raw.w>0)]
raw['P']=raw.pull_province.map(ng); raw['C']=raw.pull_municipal_city.map(ng)
raw['I']=raw.pull_item.map(ni);     raw['U']=raw.pull_nsu_unit.map(nz)
raw['dim']=raw.corrected_unit.map(nz)

# ---- attach cleaned/harmonized from the master (single source of truth for the fold rule) ----
m=pd.read_csv(BOX+r'\Data Cleaning\outputs\tables\master_nsu_rename.csv',dtype=str).fillna('')
for c in ['province','pull_municipal_city','cons_name','pull_nsu_unit']: m[c]=m[c].map(nz)
key=m.set_index(['province','pull_municipal_city','cons_name','pull_nsu_unit'])[['cleaned_nsu_unit','harmonized_nsu_unit']]
# master province/mun are UPPER (ng); rejoin with matching case
mk={}
mm=pd.read_csv(BOX+r'\Data Cleaning\outputs\tables\master_nsu_rename.csv',dtype=str).fillna('')
for r in mm.itertuples():
    mk[(ng(r.province),ng(r.pull_municipal_city),ni(r.cons_name),nz(r.pull_nsu_unit))]=(nz(r.cleaned_nsu_unit),nz(r.harmonized_nsu_unit))
raw['cleaned']=[mk.get((p,c,i,u),(None,None))[0] for p,c,i,u in zip(raw.P,raw.C,raw.I,raw.U)]
raw['harm']  =[mk.get((p,c,i,u),(None,None))[1] for p,c,i,u in zip(raw.P,raw.C,raw.I,raw.U)]
matched=raw.harm.notna().mean()
print(f'raw size-weighings: {len(raw)} rows | matched to master: {matched:.1%} '
      f'({(~raw.harm.notna()).sum()} unmatched dropped)')
raw=raw[raw.harm.notna()].copy()

RATIO_HI=1.25; RATIO_LO=1/RATIO_HI     # "sufficiently different" band on the size-controlled weight ratio

def van_elteren(df,ga,gb,gcol):
    """stratified Wilcoxon (van Elteren, weights 1/(n_h+1)) comparing gcol==ga vs ==gb across 'stratum'.
    Also returns a SIZE-CONTROLLED effect size: median over strata of (median_A_h / median_B_h)."""
    T=0.0; V=0.0; nstr=0; nA=0; nB=0; ratios=[]
    for _,h in df.groupby('stratum'):
        a=h[h[gcol]==ga].w.values; b=h[h[gcol]==gb].w.values
        na,nb=len(a),len(b); n=na+nb
        if na<1 or nb<1: continue
        nstr+=1; nA+=na; nB+=nb
        if np.median(b)>0: ratios.append(np.median(a)/np.median(b))
        r=pd.Series(np.concatenate([a,b])).rank().values          # avg ranks, tie-corrected
        Wa=r[:na].sum(); E=na*(n+1)/2.0
        _,cnt=np.unique(np.concatenate([a,b]),return_counts=True)
        tie=(cnt**3-cnt).sum()
        var=na*nb/12.0*((n+1)-tie/(n*(n-1))) if n>1 else 0.0
        wgt=1.0/(n+1)
        T+=wgt*(Wa-E); V+=wgt**2*var
    ratio=float(np.median(ratios)) if ratios else None
    if nstr<MIN_STRATA or nA<MIN_LABEL_N or nB<MIN_LABEL_N or V<=0:
        return dict(p=None,nstr=nstr,nA=nA,nB=nB,ratio=ratio,verdict='insufficient')
    z=T/np.sqrt(V); p=2*norm.sf(abs(z))
    big = ratio is not None and (ratio>=RATIO_HI or ratio<=RATIO_LO)
    # decision: keep separate only if BOTH statistically different AND materially different in size
    verdict='DIFFER' if (p<0.05 and big) else ('sig-but-small' if p<0.05 else 'agree')
    return dict(p=p,z=z,nstr=nstr,nA=nA,nB=nB,ratio=ratio,verdict=verdict)

def med_med(df,g,val):
    """interpretable absolute scale: median weight restricted to medium_size (one size, not size-confounded)."""
    s=df[(df[g]==val)&(df['size']=='medium_size')]
    return (round(s.w.median(),0) if len(s) else None), len(s)

raw['stratum']=list(zip(raw.P,raw['size'],raw.dim))

# ================= (A) FOLD validation: labels pooled into one harmonized unit =================
print('\n===== (A) FOLD VALIDATION: do pooled cleaned labels agree within (prov x size x unit)? =====')
foldrows=[]
for (it,h),g in raw.groupby(['I','harm']):
    labs=[l for l,c in g.cleaned.value_counts().items() if c>=MIN_LABEL_N]
    if len(labs)<2: continue
    ref=labs[0]
    for other in labs[1:]:
        res=van_elteren(g,ref,other,'cleaned')
        mr,_=med_med(g,'cleaned',ref); mo,_=med_med(g,'cleaned',other)
        rt=round(res['ratio'],2) if res.get('ratio') else None
        foldrows.append([it,h,ref,other,res['verdict'],res.get('p'),rt,res['nstr'],mr,mo])
fold=pd.DataFrame(foldrows,columns=['item','harmonized','label_ref','label_other','verdict','p','size_ctrl_ratio','n_strata','med_ref_med_g','med_other_med_g'])
susp=fold[fold.verdict=='DIFFER']
print(f'pooled-label pairs tested: {len(fold)} | ratio band for "sufficiently different": outside [{RATIO_LO:.2f}, {RATIO_HI:.2f}]')
print('SUSPECT folds (DIFFER = sig AND size-ctrl ratio outside band):',len(susp))
print(fold.to_string(index=False))
fold.to_csv(_OUT('A'),index=False,encoding='utf-8-sig')

# ================= (B) SPLIT validation: documented keep-separate pairs =================
# (item substring filter, harmonized A, harmonized B); '' item = any item
SPLITS=[('chicken','bilog','pieces or units'),
        ('preserved','bilog','pieces or units'),
        # The camote split is the ONLY carve-out whose justification is a number:
        # nsu_fold_rule.py cites "camote bilog != binilog (p=0.004, ratio 1.61) but on
        # only 3 strata -> LOW CONFIDENCE" as the reason NOFOLD_PIECES exists. That
        # number came from this script and was then not re-derived by it -- the pair was
        # never in this list, so every later run silently stopped checking the one
        # carve-out that rests on evidence rather than on meaning. Added so it is.
        ('camote','bilog','binilog'),
        ('ice cream','putos','pack'),
        ('crackers','putos','pack'),
        ('','bundle','bugkos'),
        ('','putos','pakete'),
        ('','pack','packs')]
print('\n===== (B) SPLIT VALIDATION: do kept-separate harmonized units actually differ? =====')
splitrows=[]
for itf,ha,hb in SPLITS:
    g=raw[raw.I.str.contains(itf,na=False)] if itf else raw
    g=g[g.harm.isin([ha,hb])]
    if g.empty: splitrows.append([itf or 'any',ha,hb,'absent',None,None,0,None,None]); continue
    # test per item so we don't mix items when itf is broad
    for it,gi in g.groupby('I'):
        if set(gi.harm.unique())!={ha,hb}: continue
        res=van_elteren(gi,ha,hb,'harm')
        ma,_=med_med(gi,'harm',ha); mb,_=med_med(gi,'harm',hb)
        rt=round(res['ratio'],2) if res.get('ratio') else None
        splitrows.append([it,ha,hb,res['verdict'],res.get('p'),rt,res['nstr'],ma,mb])
split=pd.DataFrame(splitrows,columns=['item','harm_A','harm_B','verdict','p','size_ctrl_ratio','n_strata','med_A_med_g','med_B_med_g'])
print(split.to_string(index=False))
split.to_csv(_OUT('B'),index=False,encoding='utf-8-sig')
print(f"\nwrote {_OUT('A').name} and {_OUT('B').name}")
