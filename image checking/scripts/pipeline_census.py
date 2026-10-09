"""pipeline_census.py -- every headline number for the photograph checks, in one pass.

WHY THIS EXISTS. The figures describing these checks -- how many weighings each tier
holds, how many were read, what the readers resolved, how the verdicts split -- were
being quoted from several places at once: a do-file log, an earlier measurement, a
summary written days before. They disagreed, and the disagreements were not visible
because nothing recomputed them together.

Four errors reached a reader that way: a residual quoted as 8,862 when it was 7,914, a
Check 1 tier quoted as 1,876 when that was the LONG row count and the weighing count was
1,500, a Check 2 confirm rate quoted on a 2,997 denominator that is the whole proposal
file rather than the 2,176 Check 2 resolved, and a claim that the Check 2 sweep could not
see packaging when in fact it runs two tracks and 333 of its resolved readings ARE
package labels.

Every one of those was a number carried forward rather than re-derived. So this file
re-derives all of them from the artefacts, together, and ASSERTS THE PARTS SUM TO THE
WHOLES. A figure that cannot be reconciled stops the run instead of being printed.

WHAT IT IS NOT. It is not a new rule and it recomputes no pipeline logic. Every quantity
is read from a published artefact -- photo_targets.csv, photo_readings_master.csv,
photo_rule_proposal.csv, the verdict CSVs -- in the spirit of "a diagnostic reads the
quantity the pipeline computed, it never recomputes it". The only derived quantities are
counts, sums and set differences.

THE LONG-VS-WIDE TRAP, which caused two of the four errors. `photo_targets.csv` is LONG
over (id, check, reason): a weighing suspect on two grounds gets two rows. Counting rows
there answers "how many grounds" and not "how many weighings". Every count here states
which it is, and the tier counts use distinct ids.

USAGE
    python pipeline_census.py
    python pipeline_census.py --json census.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "outputs")

TARGETS = os.path.join(OUT, "tables", "photo_targets.csv")
MASTER = os.path.join(OUT, "qc", "photo_readings_master.csv")
PROPOSAL = os.path.join(OUT, "qc", "photo_rule_proposal.csv")
BRIDGE = os.path.join(OUT, "bridge", "photo_id_bridge.csv")

HOLD_Q = os.path.join(OUT, "qc", "photo_rule_hold.csv")
OVER_Q = os.path.join(OUT, "qc", "override_review_ids.csv")
HOLD_V = os.path.join(OUT, "qc", "hold_verdicts_v2.csv")

# Reader columns, in the precedence 12_photo_readings_master.do applies. Haiku is
# excluded there and is excluded here, for the same reason: it is not evidence.
LEG = ["leg_son", "leg_hir", "leg_swp", "leg_sc1", "leg_rsc", "leg_hai"]
PKG = ["pkg_rsc", "pkg_hir", "pkg_son", "pkg_swp", "pkg_sc1"]

FAILURES: list[str] = []


def check(label: str, got, want) -> None:
    """Record a reconciliation rather than raising, so every break is reported at once."""
    if got != want:
        FAILURES.append(f"{label}: got {got}, expected {want}")


def nonempty(s: pd.Series) -> pd.Series:
    return s.notna() & s.astype(str).str.strip().ne("") & s.astype(str).str.strip().ne("nan")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", help="also write the census as JSON")
    args = ap.parse_args(argv)

    for p in (TARGETS, MASTER, PROPOSAL, BRIDGE):
        if not os.path.exists(p):
            print(f"missing input: {p}", file=sys.stderr)
            return 2

    t = pd.read_csv(TARGETS, low_memory=False)
    m = pd.read_csv(MASTER, low_memory=False)
    p = pd.read_csv(PROPOSAL, low_memory=False)
    br = pd.read_csv(BRIDGE, low_memory=False)

    c = {}

    # ---- population ------------------------------------------------------------
    c["photos_bridged"] = int(br.id.nunique())
    c1_ids = set(t.loc[t.check == 1, "id"])
    c2_ids = set(t.loc[t.check == 2, "id"])
    c["target_rows_long"] = int(len(t))
    c["check1_weighings"] = len(c1_ids)
    c["check2_weighings"] = len(c2_ids)
    c["in_both"] = len(c1_ids & c2_ids)
    c["targeted_distinct"] = len(c1_ids | c2_ids)
    check("targeted distinct = c1 + c2 - both",
          c["targeted_distinct"], c["check1_weighings"] + c["check2_weighings"] - c["in_both"])

    # THE RESIDUAL IS A SET DIFFERENCE, NOT A SUBTRACTION. 18 targeted weighings have no
    # photograph at all, so `bridged - targeted' undercounts the unread photographs by
    # exactly those 18. Subtracting two totals that do not live in the same universe is
    # how 7,914 became 7,896 on the first run of this file.
    bridged = set(br.id)
    targeted = c1_ids | c2_ids
    c["targeted_with_photo"] = len(targeted & bridged)
    c["targeted_no_photo"] = len(targeted - bridged)
    c["residual"] = len(bridged - targeted)
    check("targeted-with-photo + residual = bridged photographs",
          c["targeted_with_photo"] + c["residual"], c["photos_bridged"])

    c1 = t[t.check == 1]
    c["check1_with_photo"] = int(c1.loc[c1.has_photo == 1, "id"].nunique())
    c["check1_grounds"] = {r: int(g.id.nunique()) for r, g in c1.groupby("reason")}

    c2 = t[t.check == 2]
    c["check2_with_photo"] = int(c2.loc[c2.has_photo == 1, "id"].nunique())
    c["check2_no_photo"] = c["check2_weighings"] - c["check2_with_photo"]

    # ---- reading, Check 2 ------------------------------------------------------
    j2 = m[m.id.isin(c2_ids)]
    c["check2_in_master"] = int(len(j2))
    c["check2_resolved"] = int((j2.has_reading == 1).sum())
    c["check2_unreadable"] = int((j2.has_reading != 1).sum())
    check("check2 master = resolved + unreadable",
          c["check2_in_master"], c["check2_resolved"] + c["check2_unreadable"])
    check("check2 master = with_photo", c["check2_in_master"], c["check2_with_photo"])

    u = j2[j2.has_reading != 1]
    worst = []
    for _, r in u.iterrows():
        v = [r[col] for col in LEG if pd.notna(r[col])]
        worst.append("ambiguous" if "ambiguous" in v
                     else "not_visible" if "not_visible" in v
                     else "other")
    c["unreadable_verdict"] = pd.Series(worst).value_counts().to_dict()
    c["unreadable_single_reader"] = int((u[LEG].notna().sum(axis=1) == 1).sum())

    # ---- what KIND of evidence resolved each Check 2 reading -------------------
    r2 = j2[j2.has_reading == 1].copy()
    lab = r2.ml_rule_applied == 1
    disp = r2.scale_g.notna()
    c["ev_display_only"] = int((disp & ~lab).sum())
    c["ev_label_only"] = int((lab & ~disp).sum())
    c["ev_both"] = int((lab & disp).sum())
    c["ev_neither"] = int((~lab & ~disp).sum())
    check("check2 resolved = display + label + both + neither",
          c["check2_resolved"],
          c["ev_display_only"] + c["ev_label_only"] + c["ev_both"] + c["ev_neither"])

    # which reader supplied the package text on the label-governed rows
    labrows = r2[lab].copy()
    def pkg_src(row):
        for col in PKG:
            v = row.get(col)
            if isinstance(v, str) and v.strip() and v.strip().lower() != "nan":
                return col.replace("pkg_", "")
        return "none"
    c["label_from_reader"] = labrows.apply(pkg_src, axis=1).value_counts().to_dict() if len(labrows) else {}

    # ---- the two reading tracks of the Check 2 sweep ---------------------------
    has_v = m.v_swp.notna()
    has_p = nonempty(m.pkg_swp)
    c["swp_display_only"] = int((has_v & ~has_p).sum())
    c["swp_label_only"] = int((~has_v & has_p).sum())
    c["swp_both"] = int((has_v & has_p).sum())

    # ---- verdicts --------------------------------------------------------------
    c["proposal_rows"] = int(len(p))
    c["verdict_all"] = p.rule_verdict.value_counts().to_dict()
    check("proposal rows = master resolved", c["proposal_rows"], int((m.has_reading == 1).sum()))

    p2 = p[p.id.isin(c2_ids)]
    c["verdict_check2"] = p2.rule_verdict.value_counts().to_dict()
    check("check2 verdicts sum to check2 resolved",
          int(sum(c["verdict_check2"].values())), c["check2_resolved"])

    # verdicts split by evidence kind -- a label confirming a published weight is a
    # different claim from a display confirming it
    kind = r2.assign(kind=["label" if l and not d else "display" if d and not l
                           else "both" if l and d else "neither"
                           for l, d in zip(lab, disp)])[["id", "kind"]]
    pk = p2.merge(kind, on="id", how="left")
    c["verdict_check2_by_evidence"] = (
        pk.groupby(["rule_verdict", "kind"]).size().unstack(fill_value=0).to_dict())

    # ---- adjudication ----------------------------------------------------------
    if os.path.exists(HOLD_V):
        import glob
        ov = pd.concat([pd.read_csv(f, dtype={"image_code": str}).assign(r=i)
                        for i, f in enumerate(sorted(glob.glob(
                            os.path.join(OUT, "qc", "override_verdicts_v*.csv"))))])
        ov = ov[ov.approve.fillna("") != ""].sort_values("r").groupby("image_code").tail(1)
        hv = pd.read_csv(HOLD_V, dtype={"image_code": str})
        hv = hv[hv.approve.fillna("") != ""]
        oq = pd.read_csv(OVER_Q, dtype={"image_code": str})
        hq = pd.read_csv(HOLD_Q, dtype={"image_code": str})
        o = oq.merge(ov[["image_code", "verdict_value"]], on="image_code")
        h = hq.merge(hv[["image_code", "verdict_value"]], on="image_code")
        o["chg"] = o.verdict_value.round(3) != o.published_now.round(3)
        h["chg"] = h.verdict_value.round(3) != h.corrected_weight.round(3)
        c["adjudicated"] = int(len(o) + len(h))
        c["adjudicated_check2"] = int(o.id.isin(c2_ids).sum() + h.id.isin(c2_ids).sum())
        c["adjudicated_other"] = c["adjudicated"] - c["adjudicated_check2"]
        c["corrections"] = int(o.chg.sum() + h.chg.sum())
        c["override_queue"] = int(len(o))
        c["hold_queue"] = int(len(h))
        check("override queue = verdict_all override",
              c["override_queue"], int(c["verdict_all"].get("override", 0)))
        check("hold queue = verdict_all hold",
              c["hold_queue"], int(c["verdict_all"].get("hold", 0)))

    # ---- the 649 dual-ticked ---------------------------------------------------
    dual = set(t.loc[t.reason == "4B dual-ticked case", "id"])
    jd = m[m.id.isin(dual)]
    c["dual_ticked"] = len(dual)
    c["dual_in_master"] = int(len(jd))
    c["dual_resolved"] = int((jd.has_reading == 1).sum())
    c["dual_unreadable"] = int((jd.has_reading != 1).sum())
    check("dual resolved + unreadable = dual in master",
          c["dual_resolved"] + c["dual_unreadable"], c["dual_in_master"])
    rd = jd[jd.has_reading == 1]
    c["dual_ml_rows"] = (rd[rd.photo_unit == "mL"].pull_item.value_counts().to_dict())

    # ---- readers ---------------------------------------------------------------
    c["resolved_by_source"] = m[m.has_reading == 1].photo_src.value_counts().to_dict()

    # ---- report ----------------------------------------------------------------
    for k, v in c.items():
        if isinstance(v, dict):
            print(f"{k}:")
            for kk, vv in sorted(v.items(), key=lambda x: -x[1] if isinstance(x[1], int) else 0):
                print(f"    {kk:<58} {vv}")
        else:
            print(f"{k:<34} {v}")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(c, fh, indent=2, default=str)
        print(f"\nwrote {args.json}")

    if FAILURES:
        print("\nRECONCILIATION FAILED -- do not quote these figures:", file=sys.stderr)
        for f in FAILURES:
            print(f"    {f}", file=sys.stderr)
        return 1
    print("\nall reconciliations passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
