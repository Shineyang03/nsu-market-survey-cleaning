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
# GROUP_FILL is applied to GRP further down, once it is defined -- see _apply_group_fill.

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
    #
    # WHY TIGBAUAN IS THE ONLY ENTRY -- the obvious worry is that this is scoped too
    # narrowly, so: 15 cells fold to putos (mix vegetable), and in 13 of them the
    # VENDOR'S OWN LABEL says so -- `mixmix', `putos (halo - halo)', `pack of mixed
    # vegetables', `mix-mix cabbage and carrots', `packs of mix vegies', `mix slice of
    # cabbage'. MIX_UNITS catches all of those on the label alone, with no comment
    # needed. TIGBAUAN wrote plain `putos', so the label under-describes the product
    # and the field comment is the only signal. That is what makes it the exception,
    # and what a future entry here would have to look like: a bare label plus a
    # comment contradicting it.
    #
    # 03_clean_ms.do carries the matching tripwire, and it is not vacuous: 4 rows
    # currently carry the mixed-bag comment and all 4 fold correctly. Delete either
    # entry below and those 4 revert to `pack' and the build stops.
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

# ================= issue #36: the no-group review, applied =================
#
# The official translation crosswalk assigns a group to only 54 of its 210 labels. The
# other 156 carry `resolved_by = no-group', `action = keep', note "not in translation
# crosswalk" -- they were never adjudicated, because the crosswalk was built by matching
# observed labels INTO a pre-existing translation vocabulary and whatever missed it fell
# through. 91 of them turned out to govern something.
#
# The decisions from that review live HERE rather than in the workbook, for the same
# reason `GENERIC_CLEAN' and the putos carve-out do: the workbook is what the field team
# wrote, and this file is what the project decided. Keeping them apart means a future
# reader can see which is which, and every entry below is revertible on its own line.
#
# The reasoning for each entry, with its weight evidence and what it rests on, is in
# 90_diagnostics/harmonization_verdicts.py. That module is a REPORT of these tables and
# imports them; this file must never import it.

# label -> official translation group. Applied by patching GRP after it is read, so the
# label behaves exactly as if the crosswalk had carried the group all along.
GROUP_FILL={
    # The English piece vocabulary, absent from the crosswalk entirely. `piece',
    # `pieces', `per piece' and `pcs' sit there with a BLANK translation_group, so
    # grp() returned None and they passed through as themselves -- 60 crosswalk rows on
    # an English spelling against 60 on the canonical one. Weight-checked per item:
    # pork 215 g vs pieces or units 260 g (x1.21), 272 g vs 260 g (x1.05); prawns
    # already folded; drinks-at-restaurant has 189 weighings and no other vocabulary,
    # so nothing is pooled there.
    'piece':'pieces or units', 'pieces':'pieces or units',
    'per piece':'pieces or units', 'pcs':'pieces or units',
    'pc':'pieces or units', 'pc.':'pieces or units', 'pcs.':'pieces or units',
    'unit':'pieces or units', 'units':'pieces or units',
    'per pc':'pieces or units', 'per pcs':'pieces or units',
    'per piraso':'pieces or units', '1 pc. prawn':'pieces or units',

    # NOT HERE, DELIBERATELY: 'tama-tama nga putos' -> 'medium packs'.
    #
    # `tama-tama' is `just right / moderate'. Loaf bread, 23 weighings at median 450 g,
    # which is EXACTLY the medium packs median (n=352); large is 640 g, small 370 g. The
    # case for folding was coverage rather than the median: its 424 household rows span
    # 57 cells and its 23 weighings cover 8 of them, so 375 rows were converting off a
    # borrowed rung -- 116 pooling all 23 region-wide. Folding raised same-cell coverage
    # to 348 of 424 and moved 385 rows onto local weighings (n_g_used 4, 2, 3, 6 instead
    # of 16 and 23).
    #
    # IT WAS APPLIED, MEASURED AND REVERTED. The fold cost 39 households their gram
    # figure entirely -- SARA 15, SAN ENRIQUE 9, BUGASONG 6, and five more municipalities.
    # Not a missing weighing and not a fallback refusal: they fail at the PRICE-POINT
    # match, because the household's price does not align with the price structure
    # `medium packs' has in that municipality, where the retired `tama-tama' case had
    # points that did. The trade was a better conversion factor for 385 rows against no
    # conversion factor for 39, and the project's call is that no figure is worse than a
    # borrowed one. See outputs/archive/pre_issue36_harmonization/README.md.
    #
    # A middle path exists and has not been built: fold, and extend the price-point
    # match so a household price outside the target's local structure falls back to the
    # target's provincial points rather than failing. That is a change to 28/30, not to
    # this table.

    # `o' is `or': the label gives the English and Visayan name of one thing, and `lata'
    # is the canonical member of the cans group.
    'can o lata':'cans',
}

# label -> the spelling it harmonizes onto, item-independent. Same mechanism as
# GENERIC_CLEAN and applied alongside it: an exact normalized string, remapped before
# the heuristic. Every entry here is ONE WORD differently spelled, spaced or
# prepositioned, or a translation confirmed against weights in the same item.
SPELLING_FOLD={
    # --- one word, differently written. Identity is settled by the string; a weight
    # --- divergence between two spellings of one word is variation within a unit.
    'sliced':'slice',
    'per pack':'pack', 'putos (pack)':'pack', 'pack/ putos':'pack',
    'putos /supot':'pack',
    'tupper ware':'tupperware',
    '1order':'1 order',
    'rice cooker cup (small)':'small rice cooker cup',
    'rice cooker cup, small':'small rice cooker cup',
    'tumpok / plastic':'tumpok', 'tumpok(pile)':'tumpok',
    'cone ( dirty ice cream ) 10 pesos per cone':'cone',
    'glass/shots':'glass',
    # misspellings that no similarity threshold reaches: patupa/patupong 0.714,
    # patopung/patupong 0.750, boll/bul 0.571, tumbok/tumpok 0.947, bugkos/buskos 0.833
    # -- against bilog/binilog at 0.833, which is a REAL distinction (p=0.004). The
    # ordering is why these are listed by hand rather than folded by a cutoff.
    'patupong':'patupa', 'patopung':'patupa',
    'boll':'ball (tuba)', 'bul':'ball (tuba)',
    'buskos':'bugkos',
    'mix vegetables (per tumbok)':'mix vegetables (per tumpok)',
    'jr':'junior lapad',

    # --- different words, same referent, checked where a check was possible
    'balde':'bucket',            # Spanish-derived Tagalog/Visayan for bucket; same item
                                 # (crackers) 1500 g (n=5) vs 1065 g (n=2), x1.41
    'baso':'glass',              # Tagalog/Visayan for drinking glass; no co-occurring
                                 # weighings, rests on the translation
    'apa':'cone',                # the wafer cone in Visayan; `cone' has 39 weighings in
                                 # the same item, `apa' none
    '1 k caltex(kabo)':'caltex',  # `kabo' is a dipper; both unweighed
    'mix slice of carrot':'putos (mix vegetable)',   # MIX_UNITS covers the siblings
}

# Fill the blank translation groups. Done by assignment and not setdefault: these labels
# are PRESENT in the crosswalk with an empty translation_group, so the key already
# exists and setdefault would silently do nothing. That exact mistake made the first
# measurement of this change report "0 rows affected".
_GF_BEFORE={u: GRP.get(nz(u)) for u in GROUP_FILL}
for _u,_g in GROUP_FILL.items():
    GRP[nz(_u)]=_g
    assert grp(_u)==_g, 'GROUP_FILL did not take for %r' % _u
# An entry that was already grouped would be overriding the field team, not filling a
# blank, and that needs to be a deliberate decision rather than a side effect.
_GF_CLASH={u:(b,GROUP_FILL[u]) for u,b in _GF_BEFORE.items() if b is not None and b!=GROUP_FILL[u]}
assert not _GF_CLASH, 'GROUP_FILL overrides a group the crosswalk already set: %r' % _GF_CLASH

# ================= fold rule (unchanged from v4) =================
KEEP_SEPARATE={'bundle','packs'}
def unsafe_pieces(item): return item=='chicken' or item.startswith('preserved')
# Size-stratified weight test (validate_folds.do): camote bilog != binilog (p=0.004, ratio 1.61) but on
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

# ================= the comparison key: normalize, then match exactly =================
#
# WHY A KEY AND NOT A HIGHER THRESHOLD. to_cleaned()'s fuzzy step compares a raw label to
# the KEYS OF THE HAND RENAME, so two labels that are identical to each other but absent
# from the rename are never compared at all. Raising FOLD cannot fix that -- there is no
# comparison to make more permissive. And similarity is the wrong instrument regardless:
# ts('3bugkos','bugkos') = 0.923, which must NOT fold (three bundles), while
# ts('per piece','piece') = 0.714, which must. Both are decided by structure, not degree.
#
# So the rule is: normalize each label down to a key, and fold labels whose keys are
# EQUAL. Nothing is folded by degree of resemblance. What the key throws away is exactly
# what carries no meaning for a unit label -- punctuation, word order, a redundant
# leading count of 1, English pluralization, prepositions, and a restatement of the item
# name. What it keeps is everything that changes the referent: any count other than a
# leading 1, and every content word including size qualifiers. `rice cooker cup (small)'
# and `small rice cooker cup' share a key; `rice cooker cup (small)' and
# `rice cooker cup (large)' do not, and neither do `3bugkos' and `bugkos'.

# Pluralization and abbreviation are WHITELISTED, never rule-based. A blanket English
# plural rule would mangle the Visayan units this survey is full of -- putos -> puto,
# bugkos -> bugko, kilos -> kilo -- so every member below is written out by hand.
ABBREV={'pc':'piece','pcs':'piece','pce':'piece','pces':'piece','pieces':'piece',
        'pck':'pack','pks':'pack','pkt':'pack','packs':'pack',
        'kg':'kilo','kgs':'kilo','kls':'kilo','kilos':'kilo','kilogram':'kilo',
        'kilograms':'kilo','gms':'gram','grams':'gram',
        'btl':'bottle','bottles':'bottle','cups':'cup','glasses':'glass','bowls':'bowl',
        'slices':'slice','sliced':'slice','sacks':'sack','bundles':'bundle',
        'tasas':'tasa','cans':'can','boxes':'box','ties':'tie','heads':'head',
        'stalks':'stalk','sticks':'stick','orders':'order','servings':'serving',
        'sachets':'sachet','balls':'ball','cones':'cone','gallons':'gallon',
        'galon':'gallon','galons':'gallon','trays':'tray','loaves':'loaf',
        'units':'unit','bars':'bar'}

# Function words, English and Visayan. `mix' is deliberately ABSENT: a mixed bag is a
# different product and MIX_CANON exists to keep it that way.
KEY_STOP={'per','ung','na','ng','sa','of','and','the','a','in','for','po','nga','or',
          'with','w'}

def foldkey(item,u):
    """(counts, token bag) for a label. Equal keys mean the same referent.

    Returned as a tuple so the counts can never be compared away by a similarity
    measure: a label carrying `3' and one carrying nothing differ in the first element.
    """
    s=nz(u)
    s=re.sub(r'(\d)([a-z])',r'\1 \2',s); s=re.sub(r'([a-z])(\d)',r'\1 \2',s)  # 3bugkos
    parts=re.sub(r'[^a-z0-9]+',' ',s).split()
    nums=[p for p in parts if p.isdigit()]; toks=[p for p in parts if not p.isdigit()]
    if nums and parts[0]=='1': nums=nums[1:]      # a leading 1 is redundant; 3 is not
    nums=sorted(n.lstrip('0') or '0' for n in nums)
    toks=[t for t in (ABBREV.get(x,x) for x in toks) if t not in KEY_STOP]
    itoks={ABBREV.get(t,t) for t in re.findall(r'[a-z]+',ni(item))}
    kept=[t for t in toks if t not in itoks]       # the unit need not restate the item
    if kept: toks=kept                             # ...but only if something survives
    return ('#'.join(nums),''.join(sorted(toks)))  # spaces dropped: tupper ware==tupperware

def fold_blocked(item,a,b):
    """Why two key-equal labels must still not be pooled, or None.

    The carve-outs of canonical() are decisions about what does not share a weight, and
    they outrank the key: two labels can denote the same thing and still be kept apart
    because the weight evidence says the members differ.
    """
    ga,gb=grp(a),grp(b)
    if ga is not None and gb is not None and ga!=gb:
        return 'different official translation groups'
    g=ga or gb
    if g in KEEP_SEPARATE: return 'keep-separate group (%s)' % g
    if g=='pieces or units':
        if item in NOFOLD_PIECES: return 'camote pieces kept separate (low-confidence weight test)'
        if unsafe_pieces(item) and 'bilog' in (a,b): return 'bilog kept separate for this item'
    ma,mb=(item,a) in MIX_UNITS,(item,b) in MIX_UNITS
    if ma!=mb: return 'mixed-vegetable bag vs single-item'
    return None

def cluster_map(item,values,weight=None):
    """{label -> representative} for the labels of one item that share a fold key.

    Only ever MERGES: every value either maps to itself or to another value already in
    `values'. The representative is chosen deterministically -- official crosswalk
    vocabulary first, then the spelling carrying the most rows, then the shortest, then
    alphabetical -- so the result cannot depend on the order the labels arrive in.
    """
    weight=weight or {}
    byk=defaultdict(list)
    for v in sorted(set(values)): byk[foldkey(item,v)].append(v)
    out={}
    for _,members in sorted(byk.items()):
        if len(members)<2: continue
        if any(fold_blocked(item,members[i],members[j])
               for i in range(len(members)) for j in range(i+1,len(members))): continue
        rep=sorted(members,key=lambda h:(grp(h) is None,-weight.get(h,0),len(h),h))[0]
        for v in members:
            if v!=rep: out[v]=rep
    return out

RENAME_KEYS=defaultdict(list)
for (I,u) in RENAME: RENAME_KEYS[I].append(u)
def to_cleaned(I,U):                               # raw unit -> cleaned_nsu_unit, via OUR (corrected) rename
    u=nz(U)
    if u in GENERIC_CLEAN: return GENERIC_CLEAN[u],'generic'   # manual reconciliation wins over the crosswalk
    # The #36 spelling folds sit HERE, ahead of the hand rename, because several of the
    # labels they cover already have a rename entry mapping them to THEMSELVES -- an
    # identity row the crosswalk carries for every observed label. Placed after the
    # rename they would never fire.
    if u in SPELLING_FOLD: return SPELLING_FOLD[u],'spelling-fold'
    if (I,u) in RENAME: return RENAME[(I,u)],'rename'
    ru=reduce_unit(I,U)                            # strip redundant descriptors, then re-try the rename
    if (I,ru) in RENAME: return RENAME[(I,ru)],'rename+reduce'
    keys=RENAME_KEYS.get(I,[])                     # fuzzy (word-order/typo) against this item's rename keys
    if keys:
        best=max(keys,key=lambda k:ts(u,k))
        if ts(u,best)>=FOLD: return RENAME[(I,best)],'rename-fuzzy'
    return ru,'heuristic'                           # rename doesn't cover it -> heuristic canonical
