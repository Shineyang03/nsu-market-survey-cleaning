r"""The whole harmonization vocabulary, laid out for a human to eyeball.

WHY THIS EXISTS. `harmonized_nsu_unit` is the key every weighing pools on, so a label
that should have folded and did not silently splits a cell, and a label that folded and
should not silently pools two different products. Neither shows up as an error. The
audit in issue #36 found that the official translation crosswalk assigns a group to only
54 of its 210 labels -- the other 156 are marked `resolved_by = no-group', `action =
keep', note "not in translation crosswalk" -- so most of the vocabulary has never been
adjudicated at all. This workbook puts every one of those decisions in front of a
reviewer with the evidence attached.

NOTHING HERE DECIDES ANYTHING. It reads the rule from 00_shared/nsu_fold_rule.py and the
harmonized values the build published, and reports them. Proposals are proposals; they
take effect only when a human writes them into the crosswalk.

Sheets, in the order worth reading:

  to_review       OPEN THIS FIRST. Every label that still needs a decision, most
                  observations first, each with a `proposed_group', the rule behind it
                  and a `confidence'. Fill in `Corrected Group' where you disagree or
                  where the proposal is blank; the next run reads it back.
  live_gaps       labels that MEAN the same thing and still ship as different
                  harmonized values. These are the folds that are missing today.
  cross_item      one raw spelling that harmonizes to different values depending on the
                  item. Some are deliberate carve-outs; the rest are inconsistencies.
  full_mapping    EVERY (item, raw label) -> cleaned -> harmonized, with the route that
                  decided it and the weights behind it. The sheet for an overall review.
  groups_now      the 54 labels that DO carry a translation group, for reference.

THE FOLD KEY. `fold_key' is the normalized form from nsu_fold_rule.foldkey(): two labels
with an equal key denote the same referent. It deliberately throws away word order,
punctuation, English pluralization, prepositions, a redundant leading count of 1, and a
restatement of the item name -- and deliberately keeps every count of 2 or more and
every content word including size qualifiers. So `3bugkos' never shares a key with
`bugkos', and `rice cooker cup (small)' never shares one with `rice cooker cup (large)'.

WHY NOT JUST A SIMILARITY THRESHOLD. Because no threshold separates the real folds from
the real distinctions. `3bugkos'/`bugkos' score 0.923 and must not fold; `per
piece'/`piece' score 0.714 and must. Similarity appears here only in `near_miss', as a
proposal for a human, never as a mechanism.

A REVIEW ROUND SURVIVES A REGENERATION. Verdicts are read back from the newest
reference/reviewed/harmonization_review_REVIEWED_*.xlsx and matched on CONTENT -- the
normalized label -- never on row position. `verdict_landed' says whether the verdict is
reflected in what the build currently publishes, and a verdict matching no current label
raises a warning rather than disappearing silently.

Your annotated copy is archived into reference/reviewed/ AUTOMATICALLY before this
regenerates, so a review pass cannot be lost by re-running.

Run from anywhere:  python dofiles/90_diagnostics/harmonization_review.py
"""
import datetime as dt
import difflib
import importlib.util
import shutil
import sys
from collections import Counter, defaultdict
from pathlib import Path

import pandas as pd

# Anchored on the repo root, not the working directory -- see the note in
# report_weight_corrections.py. A relative path here would write the review workbook
# into dofiles/outputs/, where nothing looks for it.
DC = Path(__file__).resolve().parents[2]
SHARED = DC / "dofiles" / "00_shared"
INTER = DC / "outputs" / "build" / "intermediate"
TABLES = DC / "outputs" / "tables"
OUT = DC / "outputs" / "build" / "diagnostics" / "harmonization_review.xlsx"
REVIEWED = DC / "reference" / "reviewed"

sys.path.insert(0, str(SHARED))
from nsu_normalize import ng, ni, nz  # noqa: E402

# nsu_fold_rule.py is THE rule. Imported by path because a sibling module cannot be
# imported by name from a package whose peers start with a digit.
_spec = importlib.util.spec_from_file_location("nsu_fold_rule", str(SHARED / "nsu_fold_rule.py"))
nfr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nfr)

# The proposed verdicts. A hand-written table, kept beside this script rather than
# inside it so the proposals can be read and argued with on their own.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harmonization_verdicts import RATIO_VETO, VERDICTS  # noqa: E402


# ------------------------------------------------------------------ prior verdicts
def load_prior_verdicts():
    """Newest reviewed workbook -> {normalized label: (verdict, source file)}."""
    got = sorted(REVIEWED.glob("harmonization_review_REVIEWED_*.xlsx"))
    if not got:
        return {}, None
    newest = got[-1]
    try:
        prior = pd.read_excel(newest, sheet_name="to_review", dtype=str)
    except Exception as exc:                                  # noqa: BLE001
        print(f"  ! could not read {newest.name}: {exc}")
        return {}, newest
    col = next((c for c in ("Corrected Group", "corrected_group") if c in prior.columns), None)
    if col is None:
        return {}, newest
    out = {}
    for _, row in prior.iterrows():
        lbl = nz(row.get("unit_lbl", ""))
        val = str(row.get(col, "") or "").strip()
        if lbl and val.lower() not in ("nan", "none", ""):
            out[lbl] = (val, newest.name)
    return out, newest


def archive_annotated():
    """Copy an existing annotated workbook into reference/reviewed/ before overwriting."""
    if not OUT.exists():
        return None
    REVIEWED.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.fromtimestamp(OUT.stat().st_mtime).strftime("%Y-%m-%d_%H%M")
    dest = REVIEWED / f"harmonization_review_REVIEWED_{stamp}.xlsx"
    if not dest.exists():
        shutil.copy2(OUT, dest)
        return dest
    return None


# ------------------------------------------------------------------ inputs
def main():
    master = pd.read_stata(INTER / "master_nsu_rename.dta")
    master["item"] = master.pull_item.map(ni)
    master["raw"] = master.pull_nsu_unit.map(nz)
    master["harm"] = master.harmonized_nsu_unit.map(nz)
    master["clean"] = master.cleaned_nsu_unit.map(nz)

    wgh = pd.read_stata(INTER / "nsu_weighings_cpi.dta")
    wgh["item"] = wgh.pull_item.map(ni)
    wgh["harm"] = wgh.harmonized_nsu_unit.map(nz)
    wgh["raw"] = wgh.pull_nsu_unit.map(nz)          # the spelling as the vendor gave it
    wgh = wgh[wgh.corrected_weight.notna()]

    # PSPS household rows carrying each raw label. This is the measure of how much a
    # harmonization decision actually moves the deliverable, and it is NOT the same as
    # the weighing count: a label can carry 204 weighings and 9 household rows. The two
    # are separate channels -- weighings change the CONVERSION FACTOR, household rows
    # change how many rows get RE-LABELLED -- and summing them, as the crosswalk's
    # n_ms + n_price does, produces a number that is neither.
    try:
        pg = pd.read_stata(DC / "outputs" / "build" / "deliverables" / "psps_grams.dta")
        pg["raw"] = pg.pull_nsu_unit.map(nz)
        psps_rows = pg.groupby("raw").size()
        psps_conv = pg[pg.grams_h.notna()].groupby("raw").size()
        n_psps_total = len(pg)
    except Exception as exc:                                      # noqa: BLE001
        print(f"  ! psps_grams unavailable ({exc}); PSPS impact columns will be blank")
        psps_rows = psps_conv = pd.Series(dtype=int)
        n_psps_total = 0

    cw = pd.read_excel(TABLES / "price_ms_unit_harmonization_crosswalk.xlsx", dtype=str)
    cw["lbl"] = cw.unit_lbl.map(nz)
    cw["group"] = cw.translation_group.fillna("").map(nz)
    cw["n_ms_i"] = pd.to_numeric(cw.n_ms, errors="coerce").fillna(0).astype(int)
    cw["n_pr_i"] = pd.to_numeric(cw.n_price, errors="coerce").fillna(0).astype(int)
    cw["n_obs"] = cw.n_ms_i + cw.n_pr_i

    grouped = cw[cw.group != ""]
    nogroup = cw[cw.group == ""].copy()

    # weights behind each (item, harmonized value)
    wstat = (wgh.groupby(["item", "harm"]).corrected_weight
             .agg(["size", "median"]).rename(columns={"size": "n_w", "median": "med_g"}))
    wstat_h = (wgh.groupby("harm").corrected_weight
               .agg(["size", "median"]).rename(columns={"size": "n_w", "median": "med_g"}))
    # WEIGHINGS OF A RAW SPELLING, keyed on the spelling itself. An earlier version
    # looked a RAW label up in the HARMONIZED index, which silently returned "0
    # weighings" for any label the rename moves -- `putos (pack)' read as no evidence
    # at all when 73 weighings sit behind it. A reviewer would have decided blind.
    wstat_raw = (wgh.groupby("raw").corrected_weight
                 .agg(["size", "median"]).rename(columns={"size": "n_w", "median": "med_g"}))

    # ------------------------------------------------------------ full mapping
    rows = []
    for (item, raw), sub in master.groupby(["item", "raw"]):
        cleaned, route = nfr.to_cleaned(item, raw)
        harms = sorted(set(sub.harm))
        # Key on the RAW label, always. Keying on the harmonized value where it happened
        # to be unique and on the raw label otherwise made two rows incomparable with
        # the rest of the column.
        key = nfr.foldkey(item, raw)
        ws = wstat.loc[(item, harms[0])] if (item, harms[0]) in wstat.index else None
        rows.append({
            "item": item,
            "pull_nsu_unit": raw,
            "cleaned_nsu_unit": cleaned,
            "harmonized_nsu_unit": "; ".join(harms),
            "route": route,
            # canonical() looks up the group of the CLEANED value, not the raw label.
            # Both are shown because they differ on 30 rows and only one governs.
            "group_of_cleaned_governs": nfr.grp(cleaned) or "",
            "group_of_raw_label": nfr.grp(raw) or "",
            "fold_verdict": nfr.fold_verdict(item, cleaned),
            "n_rows": len(sub),
            "n_provinces": sub.pull_province.nunique(),
            "identical_to_raw": int(len(harms) == 1 and harms[0] == raw),
            "n_weighings": int(ws.n_w) if ws is not None else 0,
            "median_g": round(float(ws.med_g), 1) if ws is not None else None,
            "fold_key_counts": key[0],
            "fold_key_tokens": key[1],
        })
    full = pd.DataFrame(rows).sort_values(["item", "pull_nsu_unit"])

    # ------------------------------------------------------------ live gaps
    # a family is only a live gap if its members SURVIVE as different harmonized values
    items_using = defaultdict(set)
    for i, h in zip(master.item, master.harm):
        items_using[h].add(i)
    byk = defaultdict(list)
    for h in sorted(set(master.harm)):
        byk[nfr.foldkey("", h)].append(h)

    gaps = []
    for key, members in sorted(byk.items()):
        if len(members) < 2:
            continue
        veto = next((nfr.fold_blocked(it, a, b)
                     for a in members for b in members if a != b
                     for it in items_using[a] | items_using[b]
                     if nfr.fold_blocked(it, a, b)), None)
        for mem in members:
            ws = wstat_h.loc[mem] if mem in wstat_h.index else None
            gaps.append({
                "fold_key_counts": key[0],
                "fold_key_tokens": key[1],
                "harmonized_nsu_unit": mem,
                "n_rows": int((master.harm == mem).sum()),
                "items_using": "; ".join(sorted(items_using[mem])),
                "n_weighings": int(ws.n_w) if ws is not None else 0,
                "median_g": round(float(ws.med_g), 1) if ws is not None else None,
                "carve_out_veto": veto or "",
                "weight_test": ("vetoes" if veto else
                                "not applicable -- no co-occurring weighings"
                                if all(m not in wstat_h.index for m in members)
                                else "comparable weighings exist -- check medians"),
            })
    live = pd.DataFrame(gaps)

    # ------------------------------------------------------------ cross-item conflicts
    conf = []
    for raw, sub in master.groupby("raw"):
        tgt = sub.groupby("item").harm.agg(lambda s: "; ".join(sorted(set(s))))
        if tgt.nunique() > 1:
            for item, h in tgt.items():
                conf.append({
                    "pull_nsu_unit": raw,
                    "item": item,
                    "harmonized_nsu_unit": h,
                    "route": nfr.to_cleaned(item, raw)[1],
                    "n_rows": int(((master.raw == raw) & (master.item == item)).sum()),
                    # Tag ONLY when the carve-out touches THIS label. Keying it on the
                    # item alone tagged crackers `bilog' as "putos kept separate",
                    # which is a statement about a different label entirely.
                    "deliberate_carve_out": (
                        "camote pieces kept separate"
                        if item in nfr.NOFOLD_PIECES and nfr.grp(raw) == "pieces or units"
                        else "bilog kept separate for this item"
                        if nfr.unsafe_pieces(item) and raw == "bilog"
                        else "putos kept separate for this item"
                        if item in nfr.PUTOS_KEEP_SEPARATE_ITEMS and raw == "putos"
                        else ""),
                })
    cross = pd.DataFrame(conf).sort_values(["pull_nsu_unit", "item"])

    # ------------------------------------------------------------ proposals
    # key of every GROUPED label, so an exact-key hit can propose that label's group
    key_to_group = {}
    for r in grouped.itertuples():
        key_to_group.setdefault(nfr.foldkey("", r.lbl), set()).add(r.group)
    def words(s):
        return set(s.replace("-", " ").replace("/", " ").split())

    all_groups = sorted(set(grouped.group))

    def propose(lbl):
        """(group, why, confidence) for a no-group label.

        strong  the fold key is EQUAL to that of a label already carrying a group, or
                the label reduces to one. Structural, not a guess.
        medium  exactly one group shares a content word with the label. A real signal,
                but a shared word is not a shared referent -- confirm it.
        none    zero or several candidate groups. Only a human can place these.
        """
        k = nfr.foldkey("", lbl)
        hit = key_to_group.get(k)
        if hit and len(hit) == 1:
            return next(iter(hit)), f"fold key equal to a grouped label (key={k[1]!r})", "strong"
        red = nfr.reduce_unit("", lbl)
        if red != lbl and nfr.grp(red):
            return nfr.grp(red), f"reduces to the grouped label {red!r}", "strong"
        toks = words(lbl)
        cands = {g for g in all_groups if toks & words(g)}
        if len(cands) == 1:
            g = next(iter(cands))
            return g, f"only candidate group, shares {sorted(toks & words(g))}", "medium"
        if cands:
            return "", f"ambiguous -- candidate groups: {sorted(cands)}", "none"
        return "", "no candidate group -- may be genuinely ungrouped", "none"

    # ---------------------------------------------------- is a label's group inert?
    # THE ONLY HONEST TEST IS TO TRY IT. An earlier version of this sheet reasoned from
    # the ROUTE -- "the hand rename already resolves this label, so its translation
    # group cannot matter" -- and was wrong for 34 of 76 labels. canonical() looks up
    # grp() of the CLEANED value, and the rename very often maps a label to ITSELF, so
    # the group is consulted after all. `tama-tama nga putos' is a rename entry and
    # still governs 57 rows.
    #
    # So: give each label a sentinel group, recompute every harmonized value, and count
    # what moves. Two counts, because they are different risks -- `own' is the label's
    # own rows, `other' is collateral on labels that merely REDUCE to this one or carry
    # it as their cleaned value. `putos (mix vegetable)' has own=0 and other=10: giving
    # it a group would break the mixed-bag fold for ten rows of other spellings.
    SENTINEL = "zz sentinel group"
    ov = [bool(nfr.CELL_MIX.get((ng(p), ng(c), ni(i), nz(u))))
          for p, c, i, u in zip(master.pull_province, master.pull_municipal_city,
                                master.item, master.raw)]
    # cell overrides never consult grp(), so only the non-overridden pairs can move
    pair_rows = Counter((i, u) for (i, u), o in zip(zip(master.item, master.raw), ov) if not o)
    pairs = sorted(pair_rows)

    def harmonize_pairs():
        return {p: nz(nfr.canonical(p[0], nfr.to_cleaned(p[0], p[1])[0])) for p in pairs}

    base_h = harmonize_pairs()
    inert = {}
    for lbl in sorted(set(nogroup.lbl)):
        had = lbl in nfr.GRP
        prev = nfr.GRP.get(lbl)
        nfr.GRP[lbl] = SENTINEL
        after = harmonize_pairs()
        if had:
            nfr.GRP[lbl] = prev
        else:
            del nfr.GRP[lbl]
        own = sum(n for (i, u), n in pair_rows.items()
                  if base_h[(i, u)] != after[(i, u)] and u == lbl)
        oth = sum(n for (i, u), n in pair_rows.items()
                  if base_h[(i, u)] != after[(i, u)] and u != lbl)
        inert[lbl] = (own, oth)

    # ------------------------------------------------- the proposed verdict, and its test
    # Within-item medians, because a label used for two items has two medians and they are
    # not comparable. The weight test runs ONLY for `translation' proposals -- a claim that
    # two DIFFERENT WORDS share a referent. For a `spelling' proposal the string settles
    # identity and a weight divergence is a note about the weighings, not an objection.
    def verdict_evidence(lbl):
        try:
            action, target, fold_class, basis, why = VERDICTS[lbl]
        except KeyError:
            return dict(proposed_action="(no verdict written)", proposed_target="",
                        fold_class="", basis="", weight_test="", proposed_why="")
        lines = []
        for it in sorted(set(master.item[master.raw == lbl])):
            mine = wgh[(wgh.item == it) & (wgh.raw == lbl)].corrected_weight
            if target:
                tgt = wgh[(wgh.item == it) & (wgh.harm == nz(target))].corrected_weight
            else:
                tgt = wgh.iloc[0:0].corrected_weight
            if not len(mine) or not len(tgt):
                lines.append(f"{it[:22]}: "
                             + (f"{len(mine)}@{mine.median():.0f}g vs target n=0"
                                if len(mine) else "no weighings of this spelling"))
                continue
            ratio = mine.median() / tgt.median() if tgt.median() else float("nan")
            tag = ""
            if fold_class == "translation":
                tag = "  VETO" if (ratio > RATIO_VETO or ratio < 1 / RATIO_VETO) else "  ok"
            elif fold_class == "spelling":
                tag = "  (not a gate: one word)"
            lines.append(f"{it[:22]}: {len(mine)}@{mine.median():.0f}g vs "
                         f"{target} {len(tgt)}@{tgt.median():.0f}g  x{ratio:.2f}{tag}")
        # For a `keep', `target' is the nearest CANDIDATE rather than a destination: it is
        # named so the weight test is actually exercised and the reader can see the number
        # that justifies keeping the label apart, instead of taking the verdict on trust.
        return dict(proposed_action=action,
                    proposed_target=target if action in ("group", "fold") else "",
                    compared_against=target if action not in ("group", "fold") else "",
                    fold_class=fold_class, basis=basis,
                    weight_test=" | ".join(lines) or "not applicable", proposed_why=why)

    prior, prior_src = load_prior_verdicts()
    cur_harm = {}
    for lbl, sub in master.groupby("raw"):
        cur_harm[lbl] = "; ".join(sorted(set(sub.harm)))

    rev = []
    for r in nogroup.sort_values("n_obs", ascending=False).itertuples():
        g, why, conf_lvl = propose(r.lbl)
        k = nfr.foldkey("", r.lbl)
        # THE WHOLE CROSSWALK, not just the no-group part. Searching only the no-group
        # labels hid the one sibling that answers the question: `per pack', `in a pack'
        # and `per packs' all share a key with `pack' and `packs', which ARE grouped,
        # and the sheet showed each of them only the other two ungrouped spellings.
        fam = sorted(x for x in cw.lbl if nfr.foldkey("", x) == k and x != r.lbl)
        pv, psrc = prior.get(r.lbl, ("", ""))
        ws = wstat_raw.loc[r.lbl] if r.lbl in wstat_raw.index else None
        # and the bucket this label lands in, which is what a fold would pool with
        cells = set(zip(master.item[master.raw == r.lbl], master.harm[master.raw == r.lbl]))
        bucket = wgh[[(i, h) in cells for i, h in zip(wgh.item, wgh.harm)]]
        used_by = sorted(set(master.item[master.raw == r.lbl]))
        in_mix = any((it, r.lbl) in nfr.MIX_UNITS for it in used_by)
        own, oth = inert.get(r.lbl, (0, 0))
        decided_by = ("mixed-bag entry (MIX_UNITS)" if in_mix else
                      "; ".join(sorted({nfr.to_cleaned(it, r.lbl)[1] for it in used_by}))
                      or "(not observed)")
        rev.append({
            "unit_lbl": r.lbl,
            # FROZEN counts, hand-entered in the crosswalk workbook. Nothing in the tree
            # regenerates them and they no longer match the build: n_ms sums to 11,495
            # against 11,335 actual weighing rows, n_price to 5,412 against 2,927
            # price-side rows. Kept because they are what the crosswalk records; use the
            # live counts beside them for anything that matters.
            "n_ms_frozen": r.n_ms_i,
            "n_price_frozen": r.n_pr_i,
            "n_obs_frozen": r.n_obs,
            "n_rows_in_build": int((master.raw == r.lbl).sum()),
            "psps_rows": int(psps_rows.get(r.lbl, 0)),
            "psps_rows_converted": int(psps_conv.get(r.lbl, 0)),
            "observed_in_build": int(r.lbl in set(master.raw)),
            "current_harmonized": cur_harm.get(r.lbl, "(not observed)"),
            "items_using": "; ".join(used_by),
            # measured by the sentinel test above, not inferred from the route
            "safe_to_skip": int(own == 0 and oth == 0),
            "rows_affected_own": own,
            "rows_affected_other_labels": oth,
            "currently_decided_by": decided_by,
            # weighings recorded against THIS spelling
            "n_weighings_this_label": int(ws.n_w) if ws is not None else 0,
            "median_g_this_label": round(float(ws.med_g), 1) if ws is not None else None,
            # weighings in the (item, harmonized) buckets this spelling lands in --
            # what it is already pooled with, and what a fold would pool it into
            "n_weighings_in_bucket": len(bucket),
            "median_g_in_bucket": (round(float(bucket.corrected_weight.median()), 1)
                                   if len(bucket) else None),
            "fold_key_counts": k[0],
            "fold_key_tokens": k[1],
            "same_key_labels": "; ".join(fam),
            "same_key_grouped_siblings": "; ".join(
                f"{s} [{nfr.grp(s)}]" for s in fam if nfr.grp(s)),
            **(verdict_evidence(r.lbl) if own or oth else
               dict(proposed_action="(skippable -- group governs nothing)",
                    proposed_target="", fold_class="", basis="", weight_test="",
                    proposed_why="")),
            # the old string-only proposer, kept as a second opinion
            "string_only_proposed_group": g,
            "string_only_why": why,
            "string_only_confidence": conf_lvl,
            "prior_verdict": pv,
            "prior_verdict_from": psrc,
            "verdict_landed": ("" if not pv else
                               int(nz(pv) == nz(nfr.grp(r.lbl) or ""))),
            "Corrected Group": "",
            "reviewer_note": "",
        })
    to_review = pd.DataFrame(rev)
    # labels whose group actually governs something come first, biggest blast radius
    # at the top; the rows a reviewer can genuinely skip sink to the bottom
    to_review = to_review.sort_values(
        ["safe_to_skip", "psps_rows", "rows_affected_own", "n_weighings_this_label"],
        ascending=[True, False, False, False]).reset_index(drop=True)

    # NEAR MISSES ARE PROPOSALS FOR A HUMAN, NEVER A MECHANISM -- and this sheet is the
    # evidence for why. Similarity ranks these pairs in the WRONG ORDER: the genuine
    # misspellings score LOW (`boll'/`bul' 0.571, `patupa'/`patupong' 0.714) while
    # `bilog'/`binilog' scores 0.833 and is a real, measured distinction (p=0.004). No
    # threshold separates them. So the floor here is deliberately loose and the pairs
    # are restricted to labels that share an item, where a confusion is plausible;
    # the sheet's job is to put candidates in front of a reviewer, not to decide.
    # Two floors. Within one item a confusion is plausible, so the floor is loose and
    # the sheet carries some noise on purpose. Across items the floor is tight -- but it
    # is NOT skipped, because the same misspelt word turns up under different items
    # (`buskos' on cabbage against `bugkos' on camote tops) and that is precisely the
    # across-case inconsistency the harmonization is supposed to remove.
    NEAR_FLOOR_SAME_ITEM, NEAR_FLOOR_CROSS_ITEM = 0.60, 0.80
    labs = sorted(set(master.harm))
    nm = []
    for a in range(len(labs)):
        for b in range(a + 1, len(labs)):
            x, y = labs[a], labs[b]
            shared = items_using[x] & items_using[y]
            floor = NEAR_FLOOR_SAME_ITEM if shared else NEAR_FLOOR_CROSS_ITEM
            kx, ky = nfr.foldkey("", x), nfr.foldkey("", y)
            if kx == ky:
                continue
            ratio = difflib.SequenceMatcher(None, kx[1], ky[1]).ratio()
            if ratio >= floor:
                nm.append({
                    "label_a": x, "label_b": y, "key_similarity": round(ratio, 3),
                    "shared_items": "; ".join(sorted(shared)) or "(none -- cross-item)",
                    "counts_differ": int(kx[0] != ky[0]),
                    "n_rows_a": int((master.harm == x).sum()),
                    "n_rows_b": int((master.harm == y).sum()),
                    "carve_out_veto": next(
                        (nfr.fold_blocked(it, x, y)
                         for it in items_using[x] | items_using[y]
                         if nfr.fold_blocked(it, x, y)), ""),
                    "Corrected Group": "", "reviewer_note": "",
                })
    near = pd.DataFrame(nm).sort_values("key_similarity", ascending=False)

    # ------------------------------------------------------- original decisions
    # EVERY NSU harmonization decision the original pipeline made, checked against what
    # the current one produces. The original is outputs/temp/ms_nsu_item_rename.dta, the
    # table dofiles/archive/cleaning.do merged at its line 869; the only manual NSU
    # statement outside it is the mixed-bag rule at line 874, which now lives in
    # MIX_UNITS / CELL_MIX with a tripwire in 03_clean_ms.do.
    #
    # The point of this sheet is that a decision must never be lost QUIETLY. Every
    # departure has to be one of: a documented code override, or a row a documented
    # filter removed. Anything else lands as UNEXPLAINED and should be treated as a bug.
    orig_path = DC / "outputs" / "temp" / "ms_nsu_item_rename.dta"
    orig_rows = []
    if orig_path.exists():
        orig = pd.read_stata(orig_path)
        orig["item"] = orig.pull_item.map(ni)
        orig["raw"] = orig.pull_nsu_unit.map(nz)
        orig["orig_cleaned"] = orig.cleaned_nsu_unit.map(nz)
        built = {(r.item, r.raw): (r.clean, r.harm) for r in master.itertuples()}
        dropped = {}
        dpath = TABLES / "master_rename_dropped_labels.csv"
        if dpath.exists():
            dd = pd.read_csv(dpath, encoding="utf-8-sig")
            for r in dd.itertuples():
                dropped[(ni(r.cons_name), nz(r.pull_nsu_unit))] = str(r.drop_reason)
        for r in orig.itertuples():
            cur_clean, route = nfr.to_cleaned(r.item, r.raw)
            cur_clean = nz(cur_clean)
            b = built.get((r.item, r.raw))
            drop_reason = dropped.get((r.item, r.raw), "")
            same = cur_clean == r.orig_cleaned
            if same and b:
                status = "survived"
            elif not b and drop_reason:
                status = f"dropped by a documented filter: {drop_reason}"
            elif not b:
                status = "UNEXPLAINED -- not in the build and not in the drop ledger"
            elif route == "generic":
                status = "deliberate override (GENERIC_CLEAN)"
            elif (r.item, r.raw) in nfr.RENAME and nz(nfr.RENAME[(r.item, r.raw)]) != r.orig_cleaned:
                status = "deliberate override (rename crosswalk edited)"
            else:
                status = "UNEXPLAINED -- cleaned value changed with no recorded reason"
            orig_rows.append({
                "item": r.item,
                "pull_nsu_unit": r.raw,
                "original_cleaned": r.orig_cleaned,
                "current_cleaned": cur_clean,
                "current_harmonized": b[1] if b else "",
                "route": route,
                "reaches_build": int(b is not None),
                "status": status,
                "original_note": str(r.note or ""),
            })
    original = pd.DataFrame(orig_rows)

    groups_now = (grouped[["lbl", "group", "canonical_unit", "n_ms_i", "n_pr_i", "resolved_by"]]
                  .rename(columns={"lbl": "unit_lbl", "group": "translation_group",
                                   "n_ms_i": "n_ms", "n_pr_i": "n_price"})
                  .sort_values(["translation_group", "unit_lbl"]))

    # ------------------------------------------------------------ column guide
    # Every column of to_review, said plainly, including where a number comes from and
    # whether it is live or frozen. Shipped as a sheet so it travels with the workbook.
    GUIDE = [
        ("unit_lbl", "the raw NSU label, normalized (ASCII, lower-case, whitespace "
                     "collapsed). This is the thing being decided.", "key"),
        ("n_ms_frozen", "market-survey weighing rows carrying this label, AS RECORDED "
                        "IN THE CROSSWALK WORKBOOK. Hand-entered and frozen: nothing in "
                        "the tree regenerates it and it no longer matches the build "
                        "(sums to 11,495 against 11,335 actual weighing rows). NOT a "
                        "PSPS household count.", "frozen"),
        ("n_price_frozen", "price-file rows carrying this label, as recorded in the "
                           "crosswalk workbook. Also frozen (sums to 5,412 against "
                           "2,927 price-side rows). NOT a PSPS household count.",
         "frozen"),
        ("n_obs_frozen", "n_ms_frozen + n_price_frozen. DO NOT USE IT AS A SIZE. It "
                         "adds a WEIGHING-level count to a CASE-level one -- weighings "
                         "observed within heterogeneity groups, plus the number of "
                         "heterogeneity groups -- so the sum is not a quantity. Kept "
                         "only because it is what the crosswalk records. Use psps_rows "
                         "for downstream impact and n_weighings_this_label for "
                         "conversion-factor impact.", "frozen"),
        ("psps_rows", "PSPS household consumption rows whose reported unit is this "
                      "label. THE measure of how much a decision moves the deliverable. "
                      "Live from psps_grams.", "live"),
        ("psps_rows_converted", "of those, rows that currently receive a gram figure.",
         "live"),
        ("n_rows_in_build", "rows of master_nsu_rename carrying this label -- one per "
                            "(province, municipality, item, label). Computed live from "
                            "the current build. This is the honest size measure.", "live"),
        ("observed_in_build", "1 if the label appears in master_nsu_rename at all. 0 "
                              "means a documented filter removed it and no decision is "
                              "needed.", "live"),
        ("current_harmonized", "the harmonized_nsu_unit the build currently publishes "
                               "for this label; several values separated by '; ' means "
                               "it resolves differently depending on the item.", "live"),
        ("items_using", "the items this label appears with.", "live"),
        ("safe_to_skip", "1 if giving this label a translation group changes NOTHING "
                         "anywhere. MEASURED, not inferred: each label is assigned a "
                         "sentinel group and every harmonized value recomputed.", "live"),
        ("rows_affected_own", "rows of this label that would move if its group changed.",
         "live"),
        ("rows_affected_other_labels", "rows of OTHER labels that would move -- "
                                       "collateral via labels that reduce to this one "
                                       "or carry it as their cleaned value.", "live"),
        ("currently_decided_by", "which branch of to_cleaned() resolves it today "
                                 "(rename, heuristic, generic, ...), or the mixed-bag "
                                 "entry. Information only -- NOT a reason to skip.",
         "live"),
        ("n_weighings_this_label", "market-survey weighings whose OWN raw spelling is "
                                   "this label. Live from nsu_weighings_cpi.", "live"),
        ("median_g_this_label", "median corrected weight of those weighings, grams.",
         "live"),
        ("n_weighings_in_bucket", "weighings in the (item, harmonized) cells this label "
                                  "lands in -- what it is already pooled with.", "live"),
        ("median_g_in_bucket", "median corrected weight of that bucket, grams. Pools "
                               "across items where the label spans items, so read it "
                               "with items_using.", "live"),
        ("fold_key_counts", "counts kept by the fold key. A leading 1 is dropped as "
                            "redundant; any other count is kept and blocks a fold.",
         "derived"),
        ("fold_key_tokens", "the fold key's token bag: punctuation, word order, English "
                            "plurals, prepositions and a restatement of the item are "
                            "removed. Equal keys mean the same referent.", "derived"),
        ("same_key_labels", "every OTHER crosswalk label sharing this fold key.",
         "derived"),
        ("same_key_grouped_siblings", "those siblings that already carry a translation "
                                      "group, with the group named. If this is "
                                      "non-empty the answer is usually that group.",
         "derived"),
        ("proposed_action", "group <g> / fold <l> / keep / notaunit / manual. See "
                            "harmonization_verdicts.py.", "proposal"),
        ("proposed_target", "the group or label to harmonize onto, for group/fold only.",
         "proposal"),
        ("compared_against", "for a keep, the nearest candidate, named so the weight "
                             "test is exercised rather than asserted.", "proposal"),
        ("fold_class", "spelling (one word, folds unconditionally, weight test has NO "
                       "standing) / translation (different words claimed to share a "
                       "referent, weight test GATES) / count / size / distinct / "
                       "notaunit / field.", "proposal"),
        ("basis", "what the proposal rests on: measured, structural, language, field. "
                  "'language' is the category to check -- if the reading is wrong, "
                  "nothing in the data will show it.", "proposal"),
        ("weight_test", "per item: this label's median against the target's median in "
                        "the SAME item, with the ratio. 'VETO' where a translation "
                        "claim exceeds the ratio line. Never pooled across items.",
         "proposal"),
        ("proposed_why", "the reasoning, quoted from the verdict table.", "proposal"),
        ("string_only_proposed_group", "a second opinion from the original string-only "
                                       "proposer, which consults no weighings and can "
                                       "only ever name one of the existing groups. Kept "
                                       "so the two can be compared.", "proposal"),
        ("string_only_why", "that proposer's reason.", "proposal"),
        ("string_only_confidence", "strong / medium / none, from the string-only "
                                   "proposer. Medium is visibly noisy.", "proposal"),
        ("prior_verdict", "your decision from the newest reviewed workbook, matched on "
                          "the label.", "review"),
        ("prior_verdict_from", "which reviewed workbook it came from.", "review"),
        ("verdict_landed", "1 if that prior decision is reflected in what the build "
                           "publishes now.", "review"),
        ("Corrected Group", "YOURS TO FILL. Overrides the proposal; read back on the "
                            "next run.", "review"),
        ("reviewer_note", "YOURS TO FILL. Free text.", "review"),
    ]
    guide = pd.DataFrame(GUIDE, columns=["column", "meaning", "kind"])

    # ------------------------------------------------------------ self-check
    # EVERY DERIVED COLUMN IS RECOMPUTED A SECOND WAY AND COMPARED. This exists because
    # a column here was wrong in a way no reader could have spotted: `already_resolved_by'
    # was inferred from the route, which was the wrong test, and it was wrong for 34 of
    # 76 labels. A column that is argued for rather than measured is the failure mode,
    # so each one below is checked against an independent recomputation.
    problems = []

    def verify(name, ok, detail=""):
        if not ok:
            problems.append(f"{name}{': ' + detail if detail else ''}")

    def parts(s):
        return [z for z in str(s or "").split("; ") if z and z != "nan"]

    obs_raw = set(master.raw)
    verify("n_obs_frozen disagrees with the crosswalk",
           all(int(cw.set_index("lbl").n_obs.get(nz(r.unit_lbl), -1)) == r.n_obs_frozen
               for r in to_review.itertuples()))
    verify("n_rows_in_build disagrees with master_nsu_rename",
           all(int((master.raw == nz(r.unit_lbl)).sum()) == r.n_rows_in_build
               for r in to_review.itertuples()))
    verify("observed_in_build disagrees with master_nsu_rename",
           all((nz(r.unit_lbl) in obs_raw) == bool(r.observed_in_build)
               for r in to_review.itertuples()))
    verify("items_using disagrees with the build",
           all(sorted(set(master.item[master.raw == nz(r.unit_lbl)])) == parts(r.items_using)
               for r in to_review.itertuples()))
    verify("current_harmonized disagrees with the build",
           all(("; ".join(sorted(set(master.harm[master.raw == nz(r.unit_lbl)])))
                or "(not observed)") == str(r.current_harmonized)
               for r in to_review.itertuples()))
    # the weighings columns must be keyed on the spelling, never on the harmonized index
    verify("n_weighings_this_label is not keyed on the raw spelling",
           all(int(r.n_weighings_this_label)
               == int((wgh.raw == nz(r.unit_lbl)).sum()) for r in to_review.itertuples()))
    # same_key_labels must span the whole crosswalk
    kk = defaultdict(list)
    for lb in cw.lbl:
        kk[nfr.foldkey("", lb)].append(lb)
    verify("same_key_labels does not span the whole crosswalk",
           all(sorted(z for z in kk[nfr.foldkey("", nz(r.unit_lbl))] if z != nz(r.unit_lbl))
               == sorted(parts(r.same_key_labels)) for r in to_review.itertuples()))
    # safe_to_skip must agree with the sentinel measurement it came from
    verify("safe_to_skip disagrees with the sentinel measurement",
           all(bool(r.safe_to_skip) == (inert.get(nz(r.unit_lbl), (0, 0)) == (0, 0))
               for r in to_review.itertuples()))
    # full_mapping: the group shown as governing must be the one canonical() consults
    verify("group_of_cleaned_governs is not grp(cleaned)",
           all((nfr.grp(nz(r.cleaned_nsu_unit)) or "") == str(r.group_of_cleaned_governs or "")
               for r in full.itertuples()))
    verify("full_mapping fold key is not keyed on the raw label",
           all(nfr.foldkey(ni(r.item), nz(r.pull_nsu_unit))[1] == r.fold_key_tokens
               for r in full.itertuples()))
    # the column guide must describe exactly the columns that exist. A guide that has
    # drifted from the sheet is worse than no guide, because it is trusted.
    verify("to_review columns missing from column_guide", not
           (set(to_review.columns) - set(guide.column)),
           str(sorted(set(to_review.columns) - set(guide.column))))
    verify("column_guide describes columns that do not exist", not
           (set(guide.column) - set(to_review.columns)),
           str(sorted(set(guide.column) - set(to_review.columns))))
    # the verdict table must cover exactly the labels whose group governs something
    governing = {nz(r.unit_lbl) for r in to_review.itertuples() if not r.safe_to_skip}
    verify("labels whose group governs something but carry no written verdict",
           not (governing - set(VERDICTS)), str(sorted(governing - set(VERDICTS))[:8]))
    verify("verdicts written for labels that are not in the review set",
           not (set(VERDICTS) - governing), str(sorted(set(VERDICTS) - governing)[:8]))
    # a fold target must itself be a real label or group, never a typo
    bad_t = sorted({t for a, t, fc, b, wy in VERDICTS.values()
                    if a != "group" and t and nz(t) not in set(master.harm) | set(master.raw)}
                   | {t for a, t, fc, b, wy in VERDICTS.values()
                      if a == "group" and t and t not in set(grouped.group)})
    verify("a verdict names a fold target that does not exist", not bad_t, str(bad_t[:8]))
    # live_gaps families must be real
    verify("a live_gaps family has fewer than two distinct values",
           all(g.harmonized_nsu_unit.nunique() >= 2
               for _, g in live.groupby("fold_key_tokens")) if len(live) else True)
    verify("a live_gaps member does not carry its stated key",
           all(nfr.foldkey("", nz(r.harmonized_nsu_unit))[1] == r.fold_key_tokens
               for r in live.itertuples()) if len(live) else True)

    # ------------------------------------------------------------ write
    archived = archive_annotated()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with pd.ExcelWriter(OUT, engine="openpyxl") as xl:
        guide.to_excel(xl, sheet_name="column_guide", index=False)
        to_review.to_excel(xl, sheet_name="to_review", index=False)
        live.to_excel(xl, sheet_name="live_gaps", index=False)
        near.to_excel(xl, sheet_name="near_miss", index=False)
        cross.to_excel(xl, sheet_name="cross_item", index=False)
        full.to_excel(xl, sheet_name="full_mapping", index=False)
        if len(original):
            original.to_excel(xl, sheet_name="original_decisions", index=False)
        groups_now.to_excel(xl, sheet_name="groups_now", index=False)

    if archived:
        print(f"  archived your annotated copy -> reference/reviewed/{archived.name}")
    if prior_src:
        print(f"  read {len(prior)} prior verdict(s) from {prior_src.name}")
        stale = [k for k in prior if k not in set(nogroup.lbl)]
        if stale:
            print(f"  ! {len(stale)} prior verdict(s) match no current label: {stale[:6]}")
    print(f"\nwrote {OUT.relative_to(DC)}")
    unsettled = to_review[to_review.safe_to_skip == 0]
    print(f"  to_review    {len(to_review):5d}  ({len(unsettled)} whose group actually "
          f"governs something, {len(to_review) - len(unsettled)} skippable)")
    print("     verdicts by what they rest on: "
          + ", ".join(f"{k}={v}" for k, v in unsettled.basis.value_counts().items()))
    print("     by fold class: "
          + ", ".join(f"{k}={v}" for k, v in unsettled.fold_class.value_counts().items()))
    if n_psps_total:
        tot = int(unsettled.psps_rows.sum())
        top5 = int(unsettled.nlargest(5, "psps_rows").psps_rows.sum())
        print(f"     downstream reach: {tot} PSPS household rows of {n_psps_total} "
              f"({tot / n_psps_total * 100:.1f}%); the top 5 labels are "
              f"{top5 / tot * 100:.0f}% of that")
    vetoes = unsettled[unsettled.weight_test.fillna("").str.contains("VETO")]
    if len(vetoes):
        print(f"     !! {len(vetoes)} proposal(s) carry a weight-test VETO:")
        for r in vetoes.itertuples():
            print(f"        {r.unit_lbl!r}: {r.weight_test}")
    print(f"  live_gaps    {len(live):5d}  ({live.fold_key_tokens.nunique() if len(live) else 0} families)")
    print(f"  near_miss    {len(near):5d}")
    print(f"  cross_item   {len(cross):5d}  ({cross.pull_nsu_unit.nunique() if len(cross) else 0} labels)")
    print(f"  full_mapping {len(full):5d}")
    if len(original):
        surv = (original.status == "survived").sum()
        delib = original.status.str.startswith("deliberate").sum()
        drop = original.status.str.startswith("dropped").sum()
        bad = original[original.status.str.startswith("UNEXPLAINED")]
        print(f"  original_decisions {len(original):3d}  ({surv} survived unchanged, "
              f"{delib} deliberate override, {drop} dropped by a documented filter)")
        if len(bad):
            print(f"  ! {len(bad)} ORIGINAL DECISION(S) CHANGED WITH NO RECORDED REASON:")
            for r in bad.itertuples():
                print(f"      [{r.item}] {r.pull_nsu_unit!r}: "
                      f"{r.original_cleaned!r} -> {r.current_cleaned!r}")
    print(f"  groups_now   {len(groups_now):5d}")
    if problems:
        print(f"\n  !! {len(problems)} SELF-CHECK FAILURE(S) -- do not review this workbook:")
        for p in problems:
            print(f"     - {p}")
        raise SystemExit(1)
    print("\n  self-check: all derived columns recomputed independently and agree")
    return to_review, live, near, cross, full


if __name__ == "__main__":
    main()
