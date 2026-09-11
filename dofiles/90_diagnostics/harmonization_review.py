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
from collections import defaultdict
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
from nsu_normalize import nz, ni  # noqa: E402

# nsu_fold_rule.py is THE rule. Imported by path because a sibling module cannot be
# imported by name from a package whose peers start with a digit.
_spec = importlib.util.spec_from_file_location("nsu_fold_rule", str(SHARED / "nsu_fold_rule.py"))
nfr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nfr)


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
    wgh = wgh[wgh.corrected_weight.notna()]

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

    # ------------------------------------------------------------ full mapping
    rows = []
    for (item, raw), sub in master.groupby(["item", "raw"]):
        cleaned, route = nfr.to_cleaned(item, raw)
        harms = sorted(set(sub.harm))
        key = nfr.foldkey(item, harms[0] if len(harms) == 1 else raw)
        ws = wstat.loc[(item, harms[0])] if (item, harms[0]) in wstat.index else None
        rows.append({
            "item": item,
            "pull_nsu_unit": raw,
            "cleaned_nsu_unit": cleaned,
            "harmonized_nsu_unit": "; ".join(harms),
            "route": route,
            "translation_group": nfr.grp(raw) or "",
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
                    "deliberate_carve_out": (
                        "camote pieces" if item in nfr.NOFOLD_PIECES else
                        "chicken/preserved bilog" if nfr.unsafe_pieces(item) else
                        "putos kept separate" if item in nfr.PUTOS_KEEP_SEPARATE_ITEMS else ""),
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

    prior, prior_src = load_prior_verdicts()
    cur_harm = {}
    for lbl, sub in master.groupby("raw"):
        cur_harm[lbl] = "; ".join(sorted(set(sub.harm)))

    rev = []
    for r in nogroup.sort_values("n_obs", ascending=False).itertuples():
        g, why, conf_lvl = propose(r.lbl)
        k = nfr.foldkey("", r.lbl)
        fam = sorted(x for x in nogroup.lbl if nfr.foldkey("", x) == k and x != r.lbl)
        pv, psrc = prior.get(r.lbl, ("", ""))
        ws = wstat_h.loc[r.lbl] if r.lbl in wstat_h.index else None
        # A blank translation group only BITES where nothing else already decides the
        # label. Where the hand rename or a mixed-bag entry already resolves it, filling
        # the group changes nothing -- and accepting a proposal there would re-litigate
        # a decision that was made on evidence the string does not carry.
        used_by = sorted(set(master.item[master.raw == r.lbl]))
        routes = {nfr.to_cleaned(it, r.lbl)[1] for it in used_by}
        in_mix = any((it, r.lbl) in nfr.MIX_UNITS for it in used_by)
        settled = ("mixed-bag entry (MIX_UNITS)" if in_mix else
                   "hand rename" if routes and routes <= {"rename", "rename+reduce",
                                                          "rename-fuzzy", "generic"}
                   else "")
        rev.append({
            "unit_lbl": r.lbl,
            "n_ms": r.n_ms_i,
            "n_price": r.n_pr_i,
            "n_obs": r.n_obs,
            "observed_in_build": int(r.lbl in set(master.raw)),
            "current_harmonized": cur_harm.get(r.lbl, "(not observed)"),
            "items_using": "; ".join(used_by),
            "already_resolved_by": settled,
            "n_weighings": int(ws.n_w) if ws is not None else 0,
            "median_g": round(float(ws.med_g), 1) if ws is not None else None,
            "fold_key_counts": k[0],
            "fold_key_tokens": k[1],
            "same_key_labels": "; ".join(fam),
            "proposed_group": g,
            "proposed_why": why,
            "confidence": conf_lvl,
            "prior_verdict": pv,
            "prior_verdict_from": psrc,
            "verdict_landed": ("" if not pv else
                               int(nz(pv) == nz(nfr.grp(r.lbl) or ""))),
            "Corrected Group": "",
            "reviewer_note": "",
        })
    to_review = pd.DataFrame(rev)
    # unsettled labels first -- those are the ones where a blank group actually bites
    to_review = to_review.sort_values(
        ["already_resolved_by", "n_obs"], ascending=[True, False]).reset_index(drop=True)

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

    groups_now = (grouped[["lbl", "group", "canonical_unit", "n_ms_i", "n_pr_i", "resolved_by"]]
                  .rename(columns={"lbl": "unit_lbl", "group": "translation_group",
                                   "n_ms_i": "n_ms", "n_pr_i": "n_price"})
                  .sort_values(["translation_group", "unit_lbl"]))

    # ------------------------------------------------------------ write
    archived = archive_annotated()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with pd.ExcelWriter(OUT, engine="openpyxl") as xl:
        to_review.to_excel(xl, sheet_name="to_review", index=False)
        live.to_excel(xl, sheet_name="live_gaps", index=False)
        near.to_excel(xl, sheet_name="near_miss", index=False)
        cross.to_excel(xl, sheet_name="cross_item", index=False)
        full.to_excel(xl, sheet_name="full_mapping", index=False)
        groups_now.to_excel(xl, sheet_name="groups_now", index=False)

    if archived:
        print(f"  archived your annotated copy -> reference/reviewed/{archived.name}")
    if prior_src:
        print(f"  read {len(prior)} prior verdict(s) from {prior_src.name}")
        stale = [k for k in prior if k not in set(nogroup.lbl)]
        if stale:
            print(f"  ! {len(stale)} prior verdict(s) match no current label: {stale[:6]}")
    print(f"\nwrote {OUT.relative_to(DC)}")
    unsettled = to_review[to_review.already_resolved_by == ""]
    print(f"  to_review    {len(to_review):5d}  ({(to_review.confidence == 'strong').sum()} strong, "
          f"{(to_review.confidence == 'medium').sum()} medium, "
          f"{(to_review.confidence == 'none').sum()} need a human)")
    print(f"     of which NOT already settled upstream: {len(unsettled)}  "
          f"({(unsettled.confidence == 'strong').sum()} strong, "
          f"{(unsettled.confidence == 'medium').sum()} medium, "
          f"{(unsettled.confidence == 'none').sum()} need a human)")
    print(f"  live_gaps    {len(live):5d}  ({live.fold_key_tokens.nunique() if len(live) else 0} families)")
    print(f"  near_miss    {len(near):5d}")
    print(f"  cross_item   {len(cross):5d}  ({cross.pull_nsu_unit.nunique() if len(cross) else 0} labels)")
    print(f"  full_mapping {len(full):5d}")
    print(f"  groups_now   {len(groups_now):5d}")
    return to_review, live, near, cross, full


if __name__ == "__main__":
    main()
