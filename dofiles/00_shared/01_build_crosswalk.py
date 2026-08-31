from pathlib import Path
import sys
"""
Price-Only classifier, v5: rename-crosswalk-FIRST architecture.
  step 1: price raw unit -> cleaned_nsu_unit via nsu_rename_crosswalk (the SAME cleaning MS got);
          heuristics (reduce_unit / groups / fuzzy) are a FALLBACK only for strings the rename lacks.
  cells:  MS inventory is built from nsu_data CLEANED units (not the raw .dta), so matching is
          cleaned->cleaned (harmonized->harmonized). A price unit harmonizes to an in-cell unit
          whenever they share a harmonized_nsu_unit.
Everything else (canonical fold rule, fold_verdict, recoverable salvage, overrides) unchanged from v4.
"""
import pandas as pd, re, os, pickle, difflib
from collections import defaultdict
BOX=r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
FOLD=0.85
# The one definition of the project's string normalization. This file used to hold the
# authoritative copy; it now lives in 00_shared/nsu_normalize.py so the diagnostics can
# import the same one instead of each carrying their own.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from nsu_normalize import A, nz, ni, ng
def toks(s): return re.sub(r'[^a-z0-9 ]',' ',nz(s)).split()
def ts(a,b): return difflib.SequenceMatcher(None,' '.join(sorted(toks(a))),' '.join(sorted(toks(b)))).ratio()

cw=pd.read_excel(BOX+r'\Data Cleaning\outputs\tables\price_ms_unit_harmonization_crosswalk.xlsx', dtype=str)
GRP={nz(r.unit_lbl):(nz(r.translation_group) if isinstance(r.translation_group,str) and r.translation_group.strip() else None) for r in cw.itertuples()}
def grp(u): return GRP.get(nz(u))

# ---- rename crosswalk: (item, raw pull_nsu_unit) -> cleaned_nsu_unit  [step 1, authoritative] ----
_rn=pd.read_excel(BOX+r'\Data Cleaning\outputs\tables\nsu_rename_crosswalk.xlsx', dtype=str)
RENAME={(ni(r.pull_item),nz(r.pull_nsu_unit)):nz(r.cleaned_nsu_unit) for r in _rn.itertuples()
        if isinstance(r.cleaned_nsu_unit,str) and r.cleaned_nsu_unit.strip()}
MIX_UNITS={(ni(r.pull_item),nz(r.pull_nsu_unit)) for r in _rn.itertuples() if nz(r.cleaned_nsu_unit)=='putos (mix vegetable)'}
MIX_UNITS|={('cabbage','putos /mix mix'),('carrot','putos /mix mix'),
            ('carrot','pack of mixed vegetables'),('carrot','packs of mix veges')}
MIX_CANON='putos (mix vegetable)'

OLD_RENAME=dict(RENAME)   # snapshot of the untouched old hand-rename, kept for the 'past_rename' reference column

# ---- Option A override: the OLD hand-rename folds putos->pack for these 2 items, but their
# putos is a small sachet (~60g ice cream / ~160g crackers) vs a ~300-525g pack (weight test).
# Keep putos separate for these items only; all other 7 validated putos->pack/other folds stand.
PUTOS_KEEP_SEPARATE_ITEMS={'ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)',
                           'crackers, cookies, buiscuits, chips/curls'}
for _it in PUTOS_KEEP_SEPARATE_ITEMS:
    RENAME[(_it,'putos')]='putos'

# ---- item-specific manual reconciliations ----
RENAME[('beer','1 case')]='case'      # '1 case' == 'case' (as recorded in Panay); drop the redundant count

# ---- item-INDEPENDENT manual reconciliations: same referent regardless of item ----
# Keyed on the exact normalized raw string, applied in to_cleaned() before the heuristic fallback.
#   '1/2'                         a bare half (survey sometimes mangled to a date '2-jan' by Excel) -> half
#   small descriptive packs       ice-wrapper / cellophane / pancit-noodle packs are all a small pack
# Note: only the EXACT strings below are remapped; '1/2 sack of rice', '1/2 of whole' etc. are untouched.
GENERIC_CLEAN={'1/2':'half',
               'pack of ice wrapper':'small packs',
               'packs in cellophane':'small packs',
               'small pack for pancit (noodles)':'small packs'}

# ================= fold rule (unchanged from v4) =================
KEEP_SEPARATE={'bundle','packs'}
def unsafe_pieces(item): return item=='chicken' or item.startswith('preserved')
# Size-stratified weight test (validate_folds.py): camote bilog != binilog (p=0.004, ratio 1.61) but on
# only 3 strata -> LOW CONFIDENCE. Policy: when confidence is low, be conservative and do NOT fold. So the
# whole pieces group is kept unfolded for camote (we cannot confirm any of its variants share a weight).
NOFOLD_PIECES={'camote'}
def canonical(item,u):
    u=nz(u)
    if (item,u) in MIX_UNITS: return MIX_CANON
    g=grp(u)
    if g is None: return u
    if g in KEEP_SEPARATE:
        if g=='packs' and u in ('pack','packs'): return 'pack'
        return u
    if g=='pieces or units':
        if item in NOFOLD_PIECES: return u                        # conservative: don't fold (low-confidence test)
        if unsafe_pieces(item) and u=='bilog': return u
    return g
def fold_verdict(item,u):
    g=grp(u)
    if g is None: return 'identity(ungrouped)'
    if g in KEEP_SEPARATE: return 'keep-separate'
    if g=='pieces or units':
        if item in NOFOLD_PIECES: return 'kept-separate(low-confidence weight test)'
        if unsafe_pieces(item) and u=='bilog': return 'reassigned-separate(item-specific)'
    if g in ('whole (chicken)','small cup','small packs'): return 'fold(untested/minor-flag)'
    return 'safe-fold'

KNOWN_BASE={'tasa','cup','pieces','piece','cone','galon','gallon','glass','bowl','serving','ball','chop','order','stick','sachet'}
def recoverable(u):
    u=nz(u)
    if ' and ' in u or 'jan' in u: return None
    m=re.match(r'^\s*0*([1-9]\d*)\s*',u)
    if not m: return None
    cnt=m.group(1); rest=u[m.end():]; rest=re.sub(r'\bpcs?\.?\b|\bpieces?\b','pieces',rest)
    base=next((w for w in re.findall(r'[a-z]+',rest) if w in KNOWN_BASE), None)
    return (cnt,base) if base else None

SIZE_QUAL={'gagmay','dako','dagko','daragkul','mabahoe','kasarangan','maisot','tama','gamay','large','medium',
           'small','big','whole','manok','tibuok','buong','junior','malaki','maliit','katamtaman','malaking'}
FORCE_JUNK={('fresh fish','pack/ putos'),('carrot','putos or pack'),
            ('carrot','pack of slices')}          # 'pack of ice wrapper' now -> small packs (GENERIC_CLEAN)
REDUCE_TO={('fresh fish','per putos ung binibili na isda'):'putos',('fresh fish','repack'):'pack'}
def reduce_unit(item,U):                         # heuristic FALLBACK (rename-miss only)
    u=nz(U)
    if (item,u) in MIX_UNITS: return u
    if (item,u) in REDUCE_TO: return REDUCE_TO[(item,u)]
    if grp(u) is not None or re.match(r'^\s*\d',u): return u
    if set(re.findall(r'[a-z]+',u)) & SIZE_QUAL: return u
    core=re.sub(r'\([^)]*\)',' ',u); core=re.sub(r'/[a-z ]*',' ',core)
    core=re.sub(r'\s+',' ',re.sub(r'[^a-z ]',' ',core)).strip()
    if grp(core) is not None: return core
    hits={w for w in core.split() if grp(w) is not None}
    if len(hits)==1:
        base=hits.pop(); rest=[w for w in core.split() if w!=base]
        STOP={'per','ung','na','ng','sa','of','and','mix','the','a','in','for','po','nga'}
        if all(w in STOP for w in rest): return base
    return u

RENAME_KEYS=defaultdict(list)
for (I,u) in RENAME: RENAME_KEYS[I].append(u)
def to_cleaned(I,U):                               # raw unit -> cleaned_nsu_unit, via OUR (corrected) rename
    u=nz(U)
    if u in GENERIC_CLEAN: return GENERIC_CLEAN[u],'generic'   # manual reconciliation wins over the crosswalk
    if (I,u) in RENAME: return RENAME[(I,u)],'rename'
    ru=reduce_unit(I,U)                            # strip redundant descriptors, then re-try the rename
    if (I,ru) in RENAME: return RENAME[(I,ru)],'rename+reduce'
    keys=RENAME_KEYS.get(I,[])                     # fuzzy (word-order/typo) against this item's rename keys
    if keys:
        best=max(keys,key=lambda k:ts(u,k))
        if ts(u,best)>=FOLD: return RENAME[(I,best)],'rename-fuzzy'
    return ru,'heuristic'                           # rename doesn't cover it -> heuristic canonical

# ---- MS cell inventory from RAW ${data} units (ms_keys), re-cleaned via OUR (corrected) rename ----
# NOT nsu_data's cleaned_nsu_unit: that bakes in the old rename (e.g. ice cream putos->pack), which
# contaminates the pack weight. Re-cleaning the raw ourselves keeps putos separate with its own weight.
ms_rows=pickle.load(open('ms_keys.pkl','rb'))      # (ng(prov), raw_city, ni(item), nz(raw_unit)) from ${data}
cell_cleaned=defaultdict(set); item_cleaned=defaultdict(set); item_cities=defaultdict(set)
for P,rawc,I,rawU in ms_rows:
    C=ng(rawc); cln=to_cleaned(I,rawU)[0]
    cell_cleaned[(P,C,I)].add(cln); item_cleaned[I].add(cln); item_cities[(P,I)].add(C)
def item_harm(I): return {canonical(I,x) for x in item_cleaned.get(I,set())}

def match_unit(I,cleaned,h,units):                 # exact canonical match, else fuzzy for ungrouped (as in v4)
    exact=[x for x in units if canonical(I,x)==h]
    if exact: return exact[0]
    if grp(cleaned) is None and (I,cleaned) not in MIX_UNITS:
        close=[x for x in units if ts(cleaned,x)>=FOLD]
        if close: return max(close,key=lambda x:ts(cleaned,x))
    return None

# FALLBACK-ONLY group membership: 'tama-tama nga putos' (loaf bread) is a plain-language "medium size"
# descriptor but was never added to the 'medium packs' translation group in the crosswalk, so it is
# ungrouped (grp()==None) and its harmonized_nsu_unit is itself. This override does NOT change that --
# canonical()/grp()/harmonized_nsu_unit are untouched -- it only lets fallback_unit() treat it as a
# 'medium packs' member when searching for an in-cell fallback, in BOTH directions: a price-only
# 'tama-tama nga putos' case can fall back onto an in-cell 'medium packs' sibling, and a price-only
# 'medium nga putos'/'medium'/etc. case can fall back onto an in-cell 'tama-tama nga putos'.
FALLBACK_GROUP_OVERRIDE={('loaf bread','tama-tama nga putos'):'medium packs',
    # chicken 'bilog' (whole bird, ~1,095g, n=233) and 'whole (chicken)' (~1,120g, n=476) are kept as
    # separate harmonized units only because they come from different official translation-group
    # entries -- weights agree to within 2%. Fallback-only, both directions; a synthetic group tag
    # (not a real translation_group name) so this pairing can't accidentally pick up other members.
    ('chicken','bilog'):'FALLBACK:chicken_whole_bird',
    ('chicken','whole (chicken)'):'FALLBACK:chicken_whole_bird'}
def eff_grp(item,u): return FALLBACK_GROUP_OVERRIDE.get((item,nz(u)), grp(u))

def fallback_unit(P,C,I,U):
    """For an 'empty/uncommon' case only: if a translation-group sibling that was kept separate on
    weight grounds is nonetheless PRESENT with data in this exact cell, surface its harmonized unit as
    the best locally-available conversion target -- rather than leaving the case to fall back on the
    (possibly thin) global pool for its own harmonized_nsu_unit. harmonized_nsu_unit itself is untouched
    (stays item-conditioned, cell-independent); this is a separate, cell-specific fallback."""
    cleaned,_=to_cleaned(I,U)
    g=eff_grp(I,cleaned)
    if g is None: return ''
    own_h=canonical(I,cleaned)
    cell=cell_cleaned.get((P,C,I),set())
    cands=sorted({canonical(I,x) for x in cell if eff_grp(I,x)==g} - {own_h})
    return cands[0] if cands else ''

def classify(P,C,I,U):
    u=nz(U)
    if (I,u) in FORCE_JUNK: return 1,'nonsensical','','manual override: ambiguous / mixed-content -> .c',''
    cleaned,src=to_cleaned(I,U)
    h=canonical(I,cleaned)
    cell=cell_cleaned.get((P,C,I),set())
    if not cell:
        scope='item not surveyed anywhere in province' if (P,I) not in item_cities else 'item in province, not this city'
        return 2,'empty/uncommon','',f'item absent from this cell ({scope}); step1={src}',''
    tgt=match_unit(I,cleaned,h,cell)
    if tgt is not None: return 3,'harmonizable',tgt,f"folds ({src}) to MS cleaned unit '{tgt}'",canonical(I,tgt)
    if match_unit(I,cleaned,h,item_cleaned.get(I,set())) is not None:
        return 2,'empty/uncommon','',f"valid for item elsewhere ({src}); cell has {sorted(cell)[:4]}",h
    return 1,'nonsensical','',f"no MS referent for item ({src}); cell has {sorted(cell)[:4]}",''

# ================= fold map (weights) from nsu_data RAW units + OUR rename (de-contaminated) =================
# key on raw pull_nsu_unit re-cleaned via to_cleaned(), NOT nsu_data.cleaned_nsu_unit (old contaminated rename)
d=pd.read_pickle('nsu_all.pkl')
d['I']=d.pull_item.map(ni); d['rawU']=d.pull_nsu_unit.map(nz); d['w']=pd.to_numeric(d.corrected_weight,errors='coerce')
d['clab']=[to_cleaned(i,u)[0] for i,u in zip(d.I,d.rawU)]
DIM={1.0:'mass(g)',2.0:'vol(mL)'}
rows=[]
for (it,cl),g in d.groupby(['I','clab']):
    w=g.w.dropna(); dim=DIM.get(g.corrected_unit.dropna().iloc[0],'?') if g.corrected_unit.notna().any() else '?'
    rows.append([it,cl,canonical(it,cl),fold_verdict(it,cl),dim,len(g),round(w.median(),1) if len(w) else None])
fold_map=pd.DataFrame(rows,columns=['item','label','harmonized_nsu_unit','fold_verdict','dimension','n','median_g']).sort_values(['item','harmonized_nsu_unit','n'],ascending=[True,True,False])
fold_map.to_csv(BOX+r'\Data Cleaning\outputs\tables\unit_fold_map.csv',index=False,encoding='utf-8-sig')

# ================= diagnose price-only cases =================
pr=pd.read_csv(BOX+r'\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv', dtype=str).rename(columns={'Unit_lbl':'unit_lbl'})
pr.province=pr.province.map(ng); pr.pull_municipal_city=pr.pull_municipal_city.map(ng); pr.cons_name=pr.cons_name.map(ni); pr.unit_lbl=pr.unit_lbl.map(nz)
for c in ['mn_item_unit_pairs','pn_item_unit_pairs']: pr[c]=pd.to_numeric(pr[c],errors='coerce')
mn_map=pr.groupby(['province','pull_municipal_city','cons_name','unit_lbl'])['mn_item_unit_pairs'].max().to_dict()
pn_map=pr.groupby(['province','cons_name','unit_lbl'])['pn_item_unit_pairs'].max().to_dict()

cases=pd.read_csv(BOX+r'\Data Cleaning\outputs\temp\cases_in_price_not_in_MS.csv', dtype=str)
# Repair an Excel date-coercion artifact in this input only: the fraction '1/2' was written as '2-Jan'.
# The raw ${data} and price CSV both hold '1/2' correctly, so un-mangling here makes the cases file agree
# with them (beef then collapses to one '1/2' row; chicken price-only likewise). '1/2' -> 'half' downstream.
cases['unit_lbl']=cases.unit_lbl.map(lambda s: '1/2' if nz(s)=='2-jan' else s)
po=cases[cases.source=='Price Only'].copy()
po['P']=po.province.map(ng); po['C']=po.pull_municipal_city.map(ng); po['I']=po.cons_name.map(ni); po['U']=po.unit_lbl.map(nz)
r=[classify(p,c,i,u) for p,c,i,u in zip(po.P,po.C,po.I,po.U)]
po['cause']=[x[0] for x in r]; po['cause_label']=[x[1] for x in r]; po['link_target']=[x[2] for x in r]; po['detail']=[x[3] for x in r]; po['_h']=[x[4] for x in r]
po['harmonizable']=(po.cause==3); po['fold_verdict']=[fold_verdict(i,u) for i,u in zip(po.I,po.U)]
po['fallback_harmonized_nsu_unit']=[fallback_unit(p,c,i,u) if cz==2 else ''
                                     for p,c,i,u,cz in zip(po.P,po.C,po.I,po.U,po.cause)]
new_can=[]; new_lab=[]; new_det=[]
for i,u,cz,h,lab,det in zip(po.I,po.U,po.cause,po._h,po.cause_label,po.detail):
    if cz!=1: new_can.append(h); new_lab.append(lab); new_det.append(det); continue
    rec=recoverable(u)
    if rec: cnt,base=rec; new_can.append(base); new_lab.append('nonsensical (recoverable)'); new_det.append(f'recoverable: {cnt} x {base} (verify); '+det)
    else: new_can.append('.c'); new_lab.append('nonsensical (unmappable)'); new_det.append('unmappable free-text; '+det)
po['canonical_unit']=new_can; po['cause_label']=new_lab; po['detail']=new_det
po['mn_item_unit_pairs']=[mn_map.get((p,c,i,u)) for p,c,i,u in zip(po.P,po.C,po.I,po.U)]
po['pn_item_unit_pairs']=[pn_map.get((p,i,u)) for p,i,u in zip(po.P,po.I,po.U)]
print('=== v5 cause distribution ==='); print(po.cause_label.value_counts().to_string())

out=BOX+r'\Data Cleaning\outputs\temp\cases_in_price_not_in_MS_diagnosed.csv'
po=po.rename(columns={'canonical_unit':'harmonized_nsu_unit','link_target':'in_MS_as'})
cols=['province','pull_municipal_city','cons_name','unit_lbl','harmonized_nsu_unit','fallback_harmonized_nsu_unit',
      'fold_verdict','in_MS_as','freq_price','mn_item_unit_pairs','pn_item_unit_pairs','cause','cause_label',
      'harmonizable','detail']
po[cols].sort_values(['cause','province','cons_name','pull_municipal_city']).to_csv(out,index=False,encoding='utf-8-sig')
print('wrote',out)

# ---- coverage summary: how many price-only cases have NO MS presence in their exact cell at all,
# direct match or fallback (see docs/price_only_coverage.md for the full write-up) ----
direct=(po.cause_label=='harmonizable')
fallback=(~direct)&(po.fallback_harmonized_nsu_unit!='')
none=~direct & ~fallback
cov=pd.DataFrame([
    ['direct in-cell match (harmonizable)',int(direct.sum())],
    ['resolved via in-cell fallback',int(fallback.sum())],
    ['no MS presence in cell at all (no match, no fallback)',int(none.sum())],
    ['  of which: nonsensical (unmappable) -- no weight at all (.c)',int((none&(po.cause_label=='nonsensical (unmappable)')).sum())],
    ['  of which: nonsensical (recoverable) -- heuristic salvage only',int((none&(po.cause_label=='nonsensical (recoverable)')).sum())],
    ['  of which: empty/uncommon, item absent from cell',int((none&(po.cause_label=='empty/uncommon')&po.detail.str.contains('item absent from this cell')).sum())],
    ['  of which: empty/uncommon, valid for item elsewhere (has an item-level pool, just not local)',int((none&(po.cause_label=='empty/uncommon')&po.detail.str.contains('valid for item elsewhere')).sum())],
    ['TOTAL price-only cases',len(po)],
],columns=['category','n'])
cov.to_csv(BOX+r'\Data Cleaning\outputs\temp\price_only_coverage_summary.csv',index=False,encoding='utf-8-sig')
print('=== price-only coverage summary ==='); print(cov.to_string(index=False))

# ================= MASTER rename: prov x mun x item x nsu (MS union Price), with in-cell merges =================
# Universe = every (prov,mun,item,raw_nsu) observed in raw ${data} (MS) OR the price data. For each raw nsu
# shows what it harmonizes to AND which sibling spellings/translations in the SAME cell it pools with --
# the core task: identify same-referent nsus (diff spelling/translation) coexisting in one prov-mun-item cell.
ms_cell_raw=defaultdict(set)
for P,rawc,I,rawU in ms_rows: ms_cell_raw[(P,ng(rawc),I)].add(rawU)
pr_cell_raw=defaultdict(set)
_cN=cases.copy(); _cN['P']=_cN.province.map(ng); _cN['C']=_cN.pull_municipal_city.map(ng); _cN['I']=_cN.cons_name.map(ni); _cN['U']=_cN.unit_lbl.map(nz)
for P,C,I,U in zip(_cN.P,_cN.C,_cN.I,_cN.U): pr_cell_raw[(P,C,I)].add(U)
SRC_MAP={(p,c,i,u):s for p,c,i,u,s in zip(_cN.P,_cN.C,_cN.I,_cN.U,_cN.source)}   # authoritative Stata source
diag={(p,c,i,u):(lab,inms,fb) for p,c,i,u,lab,inms,fb in
      zip(po.P,po.C,po.I,po.U,po.cause_label,po.in_MS_as,po.fallback_harmonized_nsu_unit)}

mrows=[]
for cell in sorted(set(ms_cell_raw)|set(pr_cell_raw)):
    P,C,I=cell
    raws=ms_cell_raw.get(cell,set())|pr_cell_raw.get(cell,set())
    hmap={u:canonical(I,to_cleaned(I,u)[0]) for u in raws}      # each raw nsu -> harmonized
    for u in sorted(raws):
        h=hmap[u]; cl=to_cleaned(I,u)[0]
        sibs=sorted(x for x in raws if hmap[x]==h and x!=u)      # other spellings in THIS cell that pool with u
        src=SRC_MAP.get((P,C,I,u),'MS')                          # authoritative source; 'MS' = raw only in ${data}, not price
        lab,inms,fb=diag.get((P,C,I,u),('','',''))
        mrows.append([P,C,I,u,cl,h,src,'; '.join(sibs),len(sibs)+1,lab,inms,fb])
# No past_rename column: cleaned_nsu_unit already IS the rename-crosswalk output (with the item-specific
# putos separations of docs/master_rename.md sec.6 applied), so a raw copy of the old hand-rename would
# duplicate it. cleaned_nsu_unit is reference-only; harmonized_nsu_unit is the operational pooling key.
master=pd.DataFrame(mrows,columns=['province','pull_municipal_city','cons_name','pull_nsu_unit','cleaned_nsu_unit',
    'harmonized_nsu_unit','source','cell_merge_with','n_cell_merged','cause_label','in_MS_as',
    'fallback_harmonized_nsu_unit'])
out3=BOX+r'\Data Cleaning\outputs\tables\master_nsu_rename.csv'
master.sort_values(['cons_name','province','pull_municipal_city','harmonized_nsu_unit','pull_nsu_unit']).to_csv(out3,index=False,encoding='utf-8-sig')
print('wrote',out3, master.shape)
print('rows in an in-cell merge (n_cell_merged>1):',(master.n_cell_merged>1).sum(),'/',len(master))
print(master.source.value_counts().to_string())

# ---- Excel-safe copy: format the raw-unit columns as Text so Excel won't coerce strings like '1/2'
# into a date on open (the plain .csv has no stored cell format, so Excel guesses the type at open time).
import openpyxl
xout=BOX+r'\Data Cleaning\outputs\tables\master_nsu_rename.xlsx'
with pd.ExcelWriter(xout, engine='openpyxl') as xw:
    master.sort_values(['cons_name','province','pull_municipal_city','harmonized_nsu_unit','pull_nsu_unit']).to_excel(xw, index=False, sheet_name='master_nsu_rename')
    ws=xw.sheets['master_nsu_rename']
    for colname in ['pull_nsu_unit','cleaned_nsu_unit','harmonized_nsu_unit','fallback_harmonized_nsu_unit']:
        ci=list(master.columns).index(colname)+1
        for row in ws.iter_rows(min_row=2, min_col=ci, max_col=ci):
            for cell in row: cell.number_format='@'
print('wrote',xout)
