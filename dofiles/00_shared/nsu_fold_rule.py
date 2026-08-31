"""THE fold rule for this project: which raw NSU spellings mean the same thing.

WHY THIS FILE EXISTS. This is the rule that decides `harmonized_nsu_unit` -- the key
every weighing pools on, and therefore the key behind every published gram figure. It
used to live inside 01_build_crosswalk.py, which cannot be imported: a module name
cannot start with a digit. So anything else needing the rule had to re-implement it,
which is the one thing this project does not allow a decision rule to be.

The immediate consumer is the fold MAP (90_diagnostics/fold_map.py), which attaches
observed median weights to each fold so a human can check whether two labels that got
pooled actually weigh the same. That needs corrected weights, so it runs AFTER the Stata
build -- while the rule itself needs no data at all and runs before it. Keeping both in
one file made the crosswalk build depend on its own downstream output. See issue #33.

THE RULE VS THE MAP VS CLASSIFICATION -- three different things whose names collide:

  the fold RULE (here)    pure functions of (item, raw label). Decides
                          harmonized_nsu_unit.
  CLASSIFICATION (01)     why a price-file case has no market-survey weighing. Needs
                          the MS cell inventory.
  the fold MAP (90_)      a REPORT of the rule with observed weights attached. Needs
                          the built dataset. Diagnostic only; nothing consumes it.

NOTHING HERE READS A BUILD OUTPUT. The only inputs are two hand-maintained crosswalks
under outputs/tables/ -- price_ms_unit_harmonization_crosswalk.xlsx (the official
translation groups) and nsu_rename_crosswalk.xlsx (the hand rename). Both are inputs to
the project rather than products of it. Keep it that way: the moment this file reads a
build output, the circularity issue #33 exists to remove comes straight back.

WHAT THE CALLER GETS.

    to_cleaned(item, raw)    -> (cleaned_nsu_unit, which route resolved it). Hand
                                rename, then reduce-and-retry, then fuzzy at
                                FOLD = 0.85, then a heuristic.
    canonical(item, cleaned) -> harmonized_nsu_unit. Folds onto the translation group,
                                subject to the carve-outs below.
    fold_verdict(item, u)    -> a label saying WHY a fold happened or did not.
                                Reporting only; nothing branches on it.
    grp(u)                   -> the official translation group of a label, or None.
    recoverable(u)           -> salvage a "3 pieces" style count-times-base reading,
                                or None.

THE CARVE-OUTS ARE THE INTERESTING PART, and each is a measured decision rather than a
default:

  * `bundle` and `packs` never fold -- those group names describe a container, not a
    size, so two members need not weigh the same.
  * `pieces or units` does not fold for camote. The size-stratified weight test says
    bilog != binilog (p=0.004, ratio 1.61) but on only 3 strata, so confidence is low
    and the conservative move is not to fold.
  * `pieces or units` does not fold chicken or preserved-meat `bilog`: a whole bird is
    not a piece.
  * `putos` stays separate for ice cream and crackers, where the old hand rename folded
    it into `pack`. A putos there is a ~60 g sachet against a ~300-525 g pack.

String normalization comes from nsu_normalize.py and must not be re-implemented here
either.
"""

from pathlib import Path
import sys

import pandas as pd, re, difflib
from collections import defaultdict

BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"

# The similarity threshold for the fuzzy fallback in to_cleaned(). Only reached for a raw
# label the hand rename does not cover, even after reduce-and-retry.
FOLD = 0.85

# Normalization is imported, never re-implemented -- see nsu_normalize.py.
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

# ---- CELL-LEVEL folds: (province, municipality, item, raw unit) -> harmonized unit ----
#
# MIX_UNITS above is keyed on (item, unit) and therefore applies in EVERY municipality.
# Some folds are true of one cell only, and this is where those go. The key is the
# narrowest one the data has, so an entry cannot leak into a cell it was not measured in.
#
# WHY THIS TIER EXISTS. The alternative was a `replace ... if strpos(notes, ...)' in
# 03_clean_ms.do AFTER the crosswalk merge, which is worse in three specific ways:
# it assigns a harmonized unit the join never validated; it splits one raw label across
# two harmonized units inside a single cell (breaking cell independence); and because
# it runs on the MS side only, the price file keeps the old fold and the cell loses its
# price row. Declaring the fold HERE moves both sides together.
#
# Each entry must record the evidence. Field comments are quoted verbatim.
CELL_MIX={
    # ILOILO / TIGBAUAN, cabbage and carrot, raw label 'putos'.
    #
    # Field-officer comments on these rows, verbatim:
    #   cabbage: "There is no cabbage packs alone this is mixed with carrots"
    #   carrot : "There is no carrots packs alone this is mixed with cabbage"
    #
    # "There is no X packs alone" is a statement about the CELL, not about the four
    # vendors who happened to get the comment recorded -- which is why this is a
    # cell-level fold and not a row-level one. Before this entry existed, the
    # post-merge override caught only the 4 commented rows and left 2 uncommented
    # cabbage 'putos' rows folded to 'pack', so one cell held both harmonized units.
    #
    # The default fold for these is putos -> pack (via grp()), which is right
    # everywhere else and wrong here: at TIGBAUAN the thing weighed is a mixed bag.
    ('ILOILO','TIGBAUAN','cabbage','putos'): MIX_CANON,
    ('ILOILO','TIGBAUAN','carrot', 'putos'): MIX_CANON,
}


def cell_canonical(province, municipality, item, raw_unit):
    """harmonized unit for a raw label, honouring any cell-level override.

    Falls through to canonical() -- defined below -- when the cell has no entry, so
    this is safe to call unconditionally. Province/municipality are matched on the
    same normalized form the crosswalk is keyed on.
    """
    hit = CELL_MIX.get((ng(province), ng(municipality), ni(item), nz(raw_unit)))
    return hit

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
