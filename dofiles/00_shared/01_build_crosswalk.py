"""Build master_nsu_rename.csv -- the harmonization crosswalk the whole project joins on.

WHAT THIS PRODUCES. For every (province, municipality, item, raw NSU label) observed in
EITHER the market survey or the price file, the crosswalk records what that raw label
cleans to, what it harmonizes to, and which sibling spellings in the SAME cell pool with
it. `harmonized_nsu_unit` is the operational pooling key; `cleaned_nsu_unit` is
reference-only. 03_clean_ms.do reads this file, and every price-side diagnostic joins on
it.

It also diagnoses the price-only cases -- those carrying a price but no market-survey
weighing -- into three causes, and tallies how many have any conversion path at all.

THIS RUNS BEFORE THE STATA BUILD AND READS NO BUILD OUTPUT. Its inputs are the raw launch
data, the price file, and two hand-maintained crosswalks. That was not true until issue
#33: this file used to load two pickles, `ms_keys.pkl` and `nsu_all.pkl`, which nothing
in the repo wrote and which no longer existed on disk, so it could not run at all and the
crosswalk sitting in outputs/ was the only copy of itself.

  * `ms_keys` is now derived from the raw launch data inline -- see the block below.
  * `nsu_all` held corrected WEIGHTS, and was only ever needed by the fold map, which
    reported observed medians beside each fold. Weights exist only after the Stata build,
    so that block made this file depend on its own downstream output. It has moved to
    90_diagnostics/fold_map.py, which runs after the build and imports the same rule.

THE FOLD RULE LIVES IN 00_shared/nsu_fold_rule.py and is imported here rather than
defined. The fold map needs the identical rule, and a module whose name starts with a
digit cannot be imported -- which is why the rule could never have stayed in this file.

OUTPUTS
    outputs/tables/master_nsu_rename.csv / .xlsx         the crosswalk
    outputs/temp/cases_in_price_not_in_MS_diagnosed.csv   price-only causes
    outputs/temp/price_only_coverage_summary.csv          coverage tally

RUN, from the project root:
    python dofiles/00_shared/01_build_crosswalk.py
then re-apply the non-NSU label trim, which this file deliberately does not do:
    python dofiles/00_shared/02_drop_non_nsu_labels.py --apply
"""
from pathlib import Path
import sys

import argparse
import pandas as pd, re, os, difflib
from collections import defaultdict

BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"

# ---- --outdir: build the crosswalk somewhere else, and touch nothing live ------------
# The question this exists for is "would the harmonization differ if an upstream input
# changed?", which can only be answered by building it again and diffing. Doing that in
# place destroys the crosswalk you are comparing against, and this build also APPENDS to
# the durable id registry -- a file that must only ever grow deliberately.
#
# With --outdir every output goes to that directory instead, and the registry write is
# refused rather than redirected: a comparison build has no business minting ids.
_ap = argparse.ArgumentParser(add_help=True)
_ap.add_argument("--outdir", default=None,
                 help="write all outputs here instead of outputs/tables and "
                      "outputs/temp; also refuses to append to the id registry")
_ARGS, _ = _ap.parse_known_args()
DRY = _ARGS.outdir is not None
if DRY:
    _OD = Path(_ARGS.outdir)
    (_OD / "tables").mkdir(parents=True, exist_ok=True)
    (_OD / "temp").mkdir(parents=True, exist_ok=True)
    print(f"--outdir given: writing to {_OD}")
    print("  the id registry will NOT be appended to (comparison build)")


def OUTPATH(kind, name):
    """Where an output goes. `kind' is 'tables' or 'temp'."""
    if DRY:
        return str(_OD / kind / name)
    return BOX + rf"\Data Cleaning\outputs\{kind}\{name}"


sys.path.insert(0, str(Path(__file__).resolve().parent))
from nsu_normalize import A, nz, ni, ng
from nsu_fold_rule import (CELL_MIX, FOLD, FORCE_JUNK, GENERIC_CLEAN, GRP, KEEP_SEPARATE,
                           MIX_CANON, MIX_UNITS, NOFOLD_PIECES, OLD_RENAME, RENAME,
                           RENAME_KEYS, canonical, fold_verdict, grp, recoverable,
                           reduce_unit, to_cleaned, toks, ts, unsafe_pieces)

# ---- MS cell inventory, derived from the RAW launch data ----------------------------
# Replaces ms_keys.pkl, which held tuples of
#     (ng(province), RAW municipality, ni(item), nz(raw NSU label))
# and which nothing in the repo wrote. Rebuilt here from ${data}, which is where the
# pickle's own comment said its contents came from.
#
# THE MUNICIPALITY IS DELIBERATELY LEFT RAW and normalized at each point of use, exactly
# as the pickle did: ng() is applied once when the cleaned inventory is built and again
# in the master-rename block. Normalizing it here instead would change the cell keys
# silently.
#
# Verified against the frozen reference crosswalk in reference/: 2,001 distinct tuples,
# matching its 2,001 MS-source rows exactly, with nothing on either side of the
# difference.
_raw = pd.read_stata(BOX + r"\NSU Market Survey Launch\data"
                           r"\PSPS NSU Market Survey Launch.dta",
                     convert_categoricals=False)
ms_rows = sorted(set(zip(_raw.pull_province.map(ng), _raw.pull_municipal_city,
                         _raw.pull_item.map(ni), _raw.pull_nsu_unit.map(nz))))
print(f"MS keys from the raw launch data: {len(ms_rows):,} distinct"
      f" (province, municipality, item, raw label) over {len(_raw):,} weighings")

# ---- re-clean those raw units via OUR (corrected) rename ---------------------------
# NOT nsu_data's cleaned_nsu_unit: that bakes in the old rename (e.g. ice cream putos->pack), which
# contaminates the pack weight. Re-cleaning the raw ourselves keeps putos separate with its own weight.
# This is also why ms_rows carries RAW labels rather than cleaned ones -- the cleaning has to be
# ours, applied here, not inherited from a previous build.
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

out=OUTPATH('temp','cases_in_price_not_in_MS_diagnosed.csv')
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
cov.to_csv(OUTPATH('temp','price_only_coverage_summary.csv'),index=False,encoding='utf-8-sig')
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
    # Cell-level overrides (CELL_MIX) win over the global fold. Applied HERE, before
    # `sibs' is computed, so the in-cell merge grouping and n_cell_merged see the
    # override -- and applied to raws from BOTH sides, so the price file folds with
    # the market survey instead of keeping the old target and orphaning the cell.
    hmap={u: (CELL_MIX.get((P,C,I,nz(u))) or canonical(I,to_cleaned(I,u)[0]))
          for u in raws}                                         # each raw nsu -> harmonized
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

# ---- durable ids for the PRICE-ONLY cases ----------------------------------------
# A price-only case has no market-survey weighing behind it, so it never passes through
# 03_clean_ms.do and never gets a weighing id there. It still needs a durable handle:
# once harmonization folds pull_nsu_unit, the content key stops being reconstructable
# from the working data and the registry id is the only thing that still identifies the
# row. That argument is the same one that motivates the weighing registry.
#
# THEY CONTINUE THE SAME SEQUENCE, in the same registry file, so an id means one thing
# across the project and the two kinds can never collide on a number.
#
# TWO PROGRAMS WRITE THIS FILE -- this one and 03_clean_ms.do -- which is worth being
# careful about. What makes it safe is that they write DISJOINT rows and neither can
# touch the other's:
#   * a weighing key is prov|mun|item|label|vendor|hetero  -- FIVE pipes
#   * a price-case key is prov|mun|item|label              -- THREE pipes
# No value in either key contains a pipe (asserted below), so the shapes cannot be
# confused. Each program appends only; neither renumbers. They run sequentially in the
# documented order (00b, 01, 02, then the master), never concurrently.
REG = Path(BOX) / "Data Cleaning" / "outputs" / "tables" / "weighing_id_registry.csv"

_po = master.source == "Price Only"


def _case_key(r):
    """The registry key for a price-only case. Commas are stripped for the same reason
    they are on the weighing side: the registry is a CSV and several item names contain
    commas."""
    f = lambda x: ("" if pd.isna(x) else str(x)).replace(",", "")
    return "|".join([f(r.province), f(r.pull_municipal_city),
                     f(r.cons_name), f(r.pull_nsu_unit)])


# Built ON master and read back by mapping, NOT by merging on the stripped columns.
# Merging on stripped keys against the crosswalk's unstripped ones silently loses every
# item whose name contains a comma -- 278 of 949 rows, which the assert below caught.
master["_idkey"] = ""
master.loc[_po, "_idkey"] = master.loc[_po].apply(_case_key, axis=1)
assert not master.loc[_po, "_idkey"].duplicated().any(),     "price-only cases are not unique on the 4-part key"

if REG.exists():
    reg = pd.read_csv(REG, dtype={"idkey": str, "id": int})
    fresh = sorted(set(master.loc[_po, "_idkey"]) - set(reg.idkey))
    if fresh:
        nxt = int(reg.id.max()) + 1
        reg = pd.concat([reg, pd.DataFrame({"idkey": fresh,
                                            "id": range(nxt, nxt + len(fresh))})],
                        ignore_index=True).sort_values("id")
        assert reg.id.is_unique and reg.idkey.is_unique
        if DRY:
            print(f"id registry: {len(fresh):,} new price-only case(s) WOULD be"
                  " appended; not written because --outdir was given")
        else:
            reg.to_csv(REG, index=False, encoding="utf-8-sig")
        print(f"id registry: appended {len(fresh):,} price-only case(s), "
              f"ids {nxt:,}-{nxt + len(fresh) - 1:,}; registry now {len(reg):,} rows")
    else:
        print(f"id registry: all {int(_po.sum()):,} price-only cases already have ids")

    # MS & Price rows are left blank on purpose: their id is the WEIGHING id, which
    # lives at weighing grain and cannot sit on a case row without implying one
    # weighing per case.
    # Int64, NOT the default. `.map()' over a key with unmatched rows produces NaN,
    # which upcasts the whole column to float, and the writer then emits `11687.0' --
    # an id with a decimal point, as text. The nullable integer type holds the misses
    # without upcasting, so the CSV carries `11687' and Stata can destring it.
    master["price_case_id"] = (master._idkey.map(reg.set_index("idkey").id)
                               .astype("Int64"))
    master.loc[~_po, "price_case_id"] = pd.NA
    assert master.price_case_id.dtype == "Int64", master.price_case_id.dtype
    n_id = int(master.price_case_id.notna().sum())
    print(f"crosswalk: {n_id:,} of {int(_po.sum()):,} price-only rows carry a price_case_id")
    assert n_id == int(_po.sum()), "a price-only crosswalk row did not receive an id"
else:
    # The weighing registry is seeded by 03_clean_ms.do. Before its first run there is
    # no sequence to continue, so this is skipped rather than started here -- two
    # programs seeding one file would race on the starting number.
    master["price_case_id"] = pd.NA
    print("id registry does not exist yet (03_clean_ms.do seeds it); "
          "price-only cases will get ids on the next crosswalk build")

master = master.drop(columns="_idkey")

out3=OUTPATH('tables','master_nsu_rename.csv')
master.sort_values(['cons_name','province','pull_municipal_city','harmonized_nsu_unit','pull_nsu_unit']).to_csv(out3,index=False,encoding='utf-8-sig')
print('wrote',out3, master.shape)
print('rows in an in-cell merge (n_cell_merged>1):',(master.n_cell_merged>1).sum(),'/',len(master))
print(master.source.value_counts().to_string())

# ---- Excel-safe copy: format the raw-unit columns as Text so Excel won't coerce strings like '1/2'
# into a date on open (the plain .csv has no stored cell format, so Excel guesses the type at open time).
import openpyxl
xout=OUTPATH('tables','master_nsu_rename.xlsx')
with pd.ExcelWriter(xout, engine='openpyxl') as xw:
    master.sort_values(['cons_name','province','pull_municipal_city','harmonized_nsu_unit','pull_nsu_unit']).to_excel(xw, index=False, sheet_name='master_nsu_rename')
    ws=xw.sheets['master_nsu_rename']
    for colname in ['pull_nsu_unit','cleaned_nsu_unit','harmonized_nsu_unit','fallback_harmonized_nsu_unit']:
        ci=list(master.columns).index(colname)+1
        for row in ws.iter_rows(min_row=2, min_col=ci, max_col=ci):
            for cell in row: cell.number_format='@'
print('wrote',xout)
