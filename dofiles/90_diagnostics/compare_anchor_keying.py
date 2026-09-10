"""Every weighing the snap's anchor keying moves, with what you need to judge it.

04_unit_snap.do pools its anchor and all four referee rungs on pull_item x ${unitvar}.
Today that is harmonized_nsu_unit, which is what creates the dependency loop the
restructure is about: the crosswalk sets the harmonized unit, the snap uses it to correct
weights, and the fold decisions behind the crosswalk came from corrected weights.

Re-keying to the RAW label breaks the loop. This file answers the separate question of
whether it also changes the ANSWERS, and if so which way.

READS TWO BUILDS and diffs them:
    outputs/build/     the published build, anchor on harmonized_nsu_unit
    outputs/anchor_pull_nsu_unit/    the variant, anchor on pull_nsu_unit

Build the variant first, which touches nothing live:
    "C:\\Program Files\\StataNow19\\StataSE-64.exe" -e do 90_diagnostics\\measure_anchor_keying.do

THE YARDSTICK IS THE BLOCK READING -- the typed number in canonical units, with the
kg/g/L tick not taken literally. Three rounds of manual review established that as the
thing to trust: of 227 adjudicated verdicts, 200 adopted it. So for each moved weighing
this reports which keying returns it, which is the closest thing to a right answer
available without going back to the reviewer.

RUN
    python dofiles/90_diagnostics/compare_anchor_keying.py

OUTPUT
    outputs/tables/anchor_keying_diff.csv   one row per moved weighing
    a printed table
"""
import sys
from pathlib import Path

import numpy as np
import pandas as pd

DC = Path(__file__).resolve().parent.parent.parent
LIVE = DC / "outputs" / "build" / "intermediate"
VAR = DC / "outputs" / "anchor_pull_nsu_unit" / "intermediate"
OUT = DC / "outputs" / "tables" / "anchor_keying_diff.csv"

# THE BLOCK READING IS READ FROM THE BUILD, not recomputed here. 04_unit_snap.do keeps
# it as `w_block', so there is one definition of the rule and this file cannot drift from
# it. It used to re-derive the reading from weight, unit and a KGMAX scraped out of the
# do-file -- which guarded the constant but not the branch structure, so a change to
# STEP 3a's `weight>=10' would have left this file scoring against a rule the pipeline
# no longer used, with nothing to catch it.


def main():
    for p, what in ((LIVE, "published build"), (VAR, "variant build")):
        if not (p / "nsu_weighings_cpi.dta").exists():
            sys.exit(f"{what} not found at {p}\n"
                     "Build the variant with 90_diagnostics/measure_anchor_keying.do "
                     "(it writes to its own subtree and touches nothing live).")

    keep = ["id", "pull_province", "pull_municipal_city", "pull_item",
            "pull_nsu_unit", "harmonized_nsu_unit", "item_nsu_hetero_type",
            "corrected_weight", "corrected_unit", "w_block"]
    h = pd.read_stata(LIVE / "nsu_weighings_cpi.dta", convert_categoricals=False)[keep]
    r = pd.read_stata(VAR / "nsu_weighings_cpi.dta",
                      convert_categoricals=False)[["id", "corrected_weight"]]
    # convert_categoricals=False, and it is not optional. `unit' is a LABELLED numeric,
    # so the default read returns the label strings ("Kilograms (Kgs)"), every `unit == 1'
    # test below is silently False, and the kg rows quietly take the grams branch. That
    # is wrong only in the 10..30 window -- which is why it survived a first run -- but
    # it is wrong, and it fails without an error.
    pre = pd.read_stata(LIVE / "prelim_nsu_data.dta",
                        columns=["id", "weight", "unit"], convert_categoricals=False)
    seen = set(pre.unit.dropna().unique())
    if not seen <= {1, 2, 3}:
        sys.exit(f"unexpected unit code(s) {sorted(seen - {1, 2, 3})}; block_reading only "
                 "knows 1=kg, 2=g, 3=litres")
    lab = pd.io.stata.StataReader(LIVE / "prelim_nsu_data.dta").value_labels()["hetero"]

    d = h.merge(r, on="id", suffixes=("_harm", "_raw")).merge(pre, on="id")
    d["hetero"] = d.item_nsu_hetero_type.map(lab)
    moved = d[d.corrected_weight_harm.round(1) != d.corrected_weight_raw.round(1)].copy()
    real = moved[moved.corrected_weight_harm.notna()
                 & moved.corrected_weight_raw.notna()].copy()

    print(f"weighings in both builds        : {len(d):,}")
    print(f"flagged as differing            : {len(moved)}")
    print(f"  of which BOTH missing (.c hand-drops, not a change): "
          f"{len(moved) - len(real)}")
    print(f"REAL weight changes             : {len(real)}")

    real["block"] = real.w_block
    real["harm_is_block"] = real.corrected_weight_harm.round(0) == real.block.round(0)
    real["raw_is_block"] = real.corrected_weight_raw.round(0) == real.block.round(0)
    real["closer_to_typed"] = np.where(real.harm_is_block, "harmonized",
                                np.where(real.raw_is_block, "raw", "neither"))
    real["ratio"] = real.corrected_weight_raw / real.corrected_weight_harm

    # How thin was the pool each keying used? This is the mechanism: a raw-label pool is
    # smaller, so its median is drawn from fewer readings and can sit a decade away.
    for lbl, col in (("n_pool_harm", "harmonized_nsu_unit"),
                     ("n_pool_raw", "pull_nsu_unit")):
        n = d.groupby(["pull_item", col]).size().rename(lbl)
        real = real.join(n, on=["pull_item", col])

    real["unit_tick"] = real.unit.map({1: "kg", 2: "g", 3: "L"})

    # WHICH RUNG REFEREED, in each build. This is what the pool sizes above only hint at,
    # and it is the difference between "the raw pool was noisier" and a named mechanism:
    # the ladder is cell_hetero > cell > prov_hetero > prov, so a rung MOVING DOWN means
    # the pool the re-keying produced was too thin to referee itself and the row was
    # judged against a wider one. Falling off a *_hetero rung is the case 04's own STEP 3e
    # comment warns about -- a median pooled across small/medium/large sits below the
    # larges, so a large's block reading looks a decade too big and the anchor wins.
    #
    # Note the pools count AGREEING rows, and _agree compares the block against the
    # ANCHOR, which is itself keyed on ${unitvar}. So the re-keying changes which rows
    # are eligible to referee, not just how many there are -- a raw sub-pool can hold
    # MORE agreeing rows than the harmonized pool that contains it.
    LADDER = {"cell_hetero": 1, "cell": 2, "prov_hetero": 3, "prov": 4}
    for tag, root in (("H", LIVE), ("R", VAR)):
        s = pd.read_stata(root / "standard_weight_unit_correction.dta")[
            ["id", "snap_rule", "snap_referee"]]
        s = s.rename(columns={"snap_rule": f"rule_{tag}",
                              "snap_referee": f"referee_{tag}"}).set_index("id")
        real = real.join(s, on="id")
    # astype(str) first, then float after. snap_referee reads back as a Categorical, and
    # .map() on one returns another Categorical -- whose `>' compares CATEGORY ORDER, not
    # the depth numbers, which silently inverted these labels on the first run.
    depth_h = real.referee_H.astype(str).map(LADDER).astype(float)
    depth_r = real.referee_R.astype(str).map(LADDER).astype(float)
    real["rung"] = np.select(
        [depth_h.isna() | depth_r.isna(), depth_r > depth_h, depth_r < depth_h],
        ["n/a", "wider", "narrower"], default="same")
    cols = ["id", "pull_province", "pull_municipal_city", "pull_item", "pull_nsu_unit",
            "harmonized_nsu_unit", "hetero", "unit_tick", "weight", "block",
            "corrected_weight_harm", "corrected_weight_raw", "ratio",
            "closer_to_typed", "n_pool_harm", "n_pool_raw",
            "rule_H", "referee_H", "rule_R", "referee_R", "rung"]
    real = real[cols].sort_values(["rung", "ratio"])

    print("\nwhich keying returns the typed number in canonical units:")
    print(real.closer_to_typed.value_counts().to_string())
    print("\nanchor pool size behind each answer (medians):")
    print(f"  harmonized keying: {real.n_pool_harm.median():.0f} weighings")
    print(f"  raw-label keying : {real.n_pool_raw.median():.0f} weighings")
    print("\nreferee rung the re-keying landed on, vs which reading won:")
    print(pd.crosstab(real.rung, real.closer_to_typed).to_string())
    print("\n  'wider'    = the raw pool could not referee itself, judged against a "
          "broader one")
    print("  'narrower' = the raw keying reached a TIGHTER pool than the harmonized one")

    show = real.copy()
    show["pull_item"] = show.pull_item.str.slice(0, 22)
    for c in ("rule_H", "rule_R"):
        show[c] = show[c].astype(str).str.slice(0, 12)
    pd.set_option("display.width", 250)
    pd.set_option("display.max_colwidth", 22)
    print("\n" + "=" * 78)
    print("EVERY WEIGHING THE RE-KEYING MOVES")
    print("=" * 78)
    print(show.to_string(index=False))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    real.to_csv(OUT, index=False, encoding="utf-8-sig")
    print(f"\nwrote {OUT.relative_to(DC)}")


if __name__ == "__main__":
    main()
