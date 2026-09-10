"""Which harmonization decisions rest on snapped weights -- the circularity register.

WHY THIS EXISTS. `harmonized_nsu_unit' is produced entirely before the snap runs, from
raw inputs, and nothing downstream writes it back (the only write in the pipeline is the
crosswalk merge in 03_clean_ms.do; every reference in 05_manual_corrections.do is a
read-only key). So the BUILD is acyclic and reproduces -- verify_pipeline.py check 1
rebuilds the crosswalk from raw inputs and gets zero differing cells.

That is not the whole story, and reporting only that understates the problem.

Several carve-outs and fallbacks inside the fold rule were DECIDED by looking at
corrected weights -- the snap's output. Those decisions are then frozen by hand into
nsu_fold_rule.py and the two crosswalk workbooks. The loop is therefore real, but it is
latched through a person and a spreadsheet rather than through code:

    a carve-out          (frozen in nsu_fold_rule.py / the crosswalks)
      <- a weight test   (90_diagnostics/validate_folds.do, van Elteren)
        <- corrected_weight
          <- 04_unit_snap.do
            <- harmonized_nsu_unit    (the snap pools its anchor on this)
              <- the carve-out

Nothing re-runs on its own, so a snap change cannot silently move a fold. What it CAN do
is leave a frozen carve-out contradicting the evidence that justified it -- which has
already happened once, to the crackers `bilog' fold. That is a staleness problem, and it
needs a register of WHICH decisions are exposed, which is this file.

WHAT THIS DOES AND DOES NOT DO. It reports provenance and how many weighings each
decision governs. It does NOT re-run the weight tests -- validate_folds.do owns those,
and verify_pipeline.py check 3 is what fails the build when a folded group contradicts
its own test. Duplicating the test here is exactly the divergence this project keeps
getting bitten by.

Membership is asked of nsu_fold_rule.py rather than re-derived, for the same reason.

RUN
    python dofiles/90_diagnostics/audit_weight_derived_folds.py

OUTPUT
    outputs/tables/weight_derived_folds.csv   one row per decision
    a printed register
"""
import sys
from pathlib import Path

import pandas as pd

DC = Path(__file__).resolve().parent.parent.parent
SHARED = DC / "dofiles" / "00_shared"
BUILD = DC / "outputs" / "master_rename_build" / "intermediate"
OUT = DC / "outputs" / "tables" / "weight_derived_folds.csv"

sys.path.insert(0, str(SHARED))
import nsu_fold_rule as FR  # noqa: E402  the fold rule itself, never a second copy

# Provenance classes. The distinction that matters is the first one against the rest:
# only WEIGHT decisions can go stale when the snap changes.
WEIGHT = "weight test (snap output)"
FIELD = "field-officer comment"
CONCEPT = "conceptual (referent differs)"
STRING = "string / semantic"


def decisions():
    """Every decision that shapes the final harmonized_nsu_unit or its fallback.

    Each entry carries the predicate that selects the weighings it governs, taking the
    row's (item, cleaned_nsu_unit, harmonized_nsu_unit).
    """
    pieces = "pieces or units"
    return [
        dict(
            name="camote pieces-group kept unfolded",
            lives="nsu_fold_rule.py NOFOLD_PIECES",
            provenance=WEIGHT,
            sets="harmonized_nsu_unit",
            evidence="validate_folds.do: camote bilog != binilog, p=0.004, ratio 1.61, "
                     "but on only 3 strata -> low confidence, so do not fold",
            pick=lambda it, cl, h: it in FR.NOFOLD_PIECES and FR.grp(cl) == pieces,
        ),
        dict(
            name="putos kept separate from pack (ice cream, crackers)",
            lives="nsu_fold_rule.py PUTOS_KEEP_SEPARATE_ITEMS",
            provenance=WEIGHT,
            sets="harmonized_nsu_unit",
            evidence="weight test: a putos is a ~60 g (ice cream) / ~160 g (crackers) "
                     "sachet against a ~300-525 g pack",
            pick=lambda it, cl, h: it in FR.PUTOS_KEEP_SEPARATE_ITEMS and cl == "putos",
        ),
        dict(
            name="chicken bilog <-> whole (chicken) fallback pairing",
            lives="01_build_crosswalk.py FALLBACK_GROUP_OVERRIDE",
            provenance=WEIGHT,
            sets="fallback_harmonized_nsu_unit only",
            evidence="weight test: bilog ~1,095 g (n=233) vs whole (chicken) ~1,120 g "
                     "(n=476), agreeing to within 2%",
            pick=lambda it, cl, h: it == "chicken" and h in ("bilog", "whole (chicken)"),
        ),
        dict(
            name="bundle / packs groups never fold",
            lives="nsu_fold_rule.py KEEP_SEPARATE",
            provenance=CONCEPT,
            sets="harmonized_nsu_unit",
            evidence="the group name describes a container, not a size, so two members "
                     "need not weigh the same",
            pick=lambda it, cl, h: FR.grp(cl) in FR.KEEP_SEPARATE,
        ),
        dict(
            name="chicken / preserved-meat bilog is not a piece",
            lives="nsu_fold_rule.py unsafe_pieces()",
            provenance=CONCEPT,
            sets="harmonized_nsu_unit",
            evidence="a whole bird is not a piece; stated as a referent difference, "
                     "not measured",
            pick=lambda it, cl, h: FR.unsafe_pieces(it) and cl == "bilog",
        ),
        dict(
            name="mixed-vegetable putos folds (incl. cell-level)",
            lives="nsu_fold_rule.py MIX_UNITS / CELL_MIX",
            provenance=FIELD,
            sets="harmonized_nsu_unit",
            evidence='field comments quoted verbatim, e.g. "There is no cabbage packs '
                     'alone this is mixed with carrots"',
            pick=lambda it, cl, h: h == FR.MIX_CANON,
        ),
        dict(
            name="hand rename, reduce-and-retry, fuzzy at 0.85, heuristic",
            lives="nsu_fold_rule.py to_cleaned()",
            provenance=STRING,
            sets="cleaned_nsu_unit -> harmonized_nsu_unit",
            evidence="spelling and word-order reconciliation; no weight is consulted",
            pick=lambda it, cl, h: True,  # the route every row travels
        ),
    ]


def main():
    f = BUILD / "nsu_weighings_cpi.dta"
    if not f.exists():
        sys.exit(f"build not found at {f}; run master_outcome1.do first")
    w = pd.read_stata(f, convert_categoricals=False)

    # ASK THE RULE, do not read the build's record of it. cleaned_nsu_unit does ride
    # along on the built weighings, and today it agrees with to_cleaned() on all 11,335
    # rows -- but it is labelled "ref only" in 03_clean_ms.do for a reason, and a
    # register whose whole job is to catch staleness must not itself depend on a column
    # that can go stale. validate_folds.py read a build column for six weeks and
    # reproduced its own past answers; this is that shape.
    #
    # The build column is still read, as a TRIPWIRE: a disagreement means the crosswalk
    # on disk was built by a different version of the fold rule than the one imported
    # here, and the counts below would describe neither.
    cleaned = [FR.to_cleaned(i, u)[0] for i, u in
               zip(w.pull_item.fillna(""), w.pull_nsu_unit.fillna(""))]
    if "cleaned_nsu_unit" in w.columns:
        off = sum(1 for a, b in zip(cleaned, w.cleaned_nsu_unit.fillna("")) if a != b)
        if off:
            sys.exit(f"{off} weighing(s) where the built cleaned_nsu_unit disagrees with "
                     "nsu_fold_rule.to_cleaned(). The crosswalk on disk was not built by "
                     "this fold rule -- re-run 01_build_crosswalk.py before trusting any "
                     "count below.")

    trip = list(zip(w.pull_item.fillna(""), cleaned, w.harmonized_nsu_unit.fillna("")))

    rows = []
    for d in decisions():
        n = sum(1 for it, cl, h in trip if d["pick"](it, cl, h))
        rows.append({k: d[k] for k in ("name", "lives", "provenance", "sets",
                                       "evidence")} | {"weighings": n})
    reg = pd.DataFrame(rows)

    wd = reg[(reg.provenance == WEIGHT) & (reg.sets == "harmonized_nsu_unit")]
    fb = reg[(reg.provenance == WEIGHT) & (reg.sets != "harmonized_nsu_unit")]

    print(f"weighings in build: {len(w):,}\n")
    print("=" * 78)
    print("HARMONIZATION DECISIONS BY PROVENANCE")
    print("=" * 78)
    for prov in (WEIGHT, CONCEPT, FIELD, STRING):
        sub = reg[reg.provenance == prov]
        if sub.empty:
            continue
        print(f"\n{prov.upper()}")
        for _, r in sub.iterrows():
            print(f"  {r.weighings:6,d}  {r['name']}")
            print(f"          sets {r.sets}; {r.lives}")
    print("\n" + "=" * 78)
    print("EXPOSURE TO A SNAP CHANGE")
    print("=" * 78)
    print(f"  {wd.weighings.sum():6,d}  weighings whose FINAL harmonized_nsu_unit rests "
          f"on a weight test")
    print(f"          = {wd.weighings.sum() / len(w):.1%} of the build")
    print(f"  {fb.weighings.sum():6,d}  further weighings where only the FALLBACK column "
          f"does")
    print("\n  These are frozen by hand, so a snap change cannot move them on its own.")
    print("  It can leave them contradicting the evidence that justified them.")
    print("  validate_folds.do re-runs the tests; verify_pipeline.py check 3 fails the")
    print("  build when a folded group contradicts its own test.")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    reg.to_csv(OUT, index=False, encoding="utf-8-sig")
    print(f"\nwrote {OUT.relative_to(DC)}")


if __name__ == "__main__":
    main()
