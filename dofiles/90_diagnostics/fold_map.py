r"""Report every fold the rule made, with the observed weights beside it.

WHAT THIS IS FOR. `00_shared/nsu_fold_rule.py` decides which raw NSU spellings mean the
same thing, and therefore which weighings pool together. It decides that from the
official translation groups and a hand rename -- from *names*, never from weights. This
file is the audit: one row per (item, cleaned label), showing what it harmonized to, why,
how many weighings sit behind it, and their median weight. If two labels were pooled and
their medians are far apart, the fold is worth a second look.

So the rule decides; this reports. It changes nothing and nothing downstream reads it.

WHY IT IS A SEPARATE FILE, AND IN 90_diagnostics/. This block used to live inside
01_build_crosswalk.py, reading a pickle called `nsu_all.pkl`. It needs corrected weights,
which exist only after the Stata build -- so it made the crosswalk build depend on its own
downstream output, and the crosswalk is what 03_clean_ms.do reads. Issue #33. It now runs
after the build and imports the identical rule rather than re-implementing it.

IT USED TO BE STALE, WHICH IS WORTH KNOWING BEFORE COMPARING TO AN OLD COPY. The `n`
column of the committed unit_fold_map.csv summed to 11,259, which is the row count of
outputs/temp/nsu_data.dta dated 27 July -- the pre-Aug11 build. So `nsu_all.pkl` had been
made from data predating both the non-NSU label trim and the w_ref retirement, and the
fold map described a build that no longer existed. Reading nsu_data_master.dta (11,453
rows) changes the numbers, and that is a correction, not a regression. Do not "restore"
the old figures.

INPUT   outputs/build/intermediate/nsu_data_master.dta
OUTPUT  outputs/tables/unit_fold_map.csv

RUN, from the project root, after master_outcome1.do has run at least once:
    python dofiles/90_diagnostics/fold_map.py
"""
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import ni, nz
from nsu_fold_rule import canonical, fold_verdict, to_cleaned

DC = Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel"
          r"\14 NSU Market Survey\Data Cleaning")
IN_DTA = DC / "outputs" / "build" / "intermediate" / "nsu_data_master.dta"
OUT_CSV = DC / "outputs" / "tables" / "unit_fold_map.csv"

# corrected_unit is 1 = grams, 2 = millilitres. Set by an encode() in 04_unit_snap.do, so
# the mapping is alphabetical-by-accident rather than declared -- see issue #18. Anything
# outside those two codes surfaces as '?' rather than being guessed at.
DIM = {1.0: "mass(g)", 2.0: "vol(mL)"}


def main():
    d = pd.read_stata(IN_DTA, convert_categoricals=False)
    print(f"read {IN_DTA.name}: {len(d):,} weighings")

    # Key on the RAW pull_nsu_unit re-cleaned through our own rule, NOT on the dataset's
    # cleaned_nsu_unit. The stored column can carry an older rename -- the ice cream
    # putos->pack fold, for one -- and keying on it would contaminate the pack weight
    # with sachet weighings, hiding exactly the kind of bad fold this report exists to
    # surface.
    d["I"] = d.pull_item.map(ni)
    d["rawU"] = d.pull_nsu_unit.map(nz)
    d["w"] = pd.to_numeric(d.corrected_weight, errors="coerce")
    d["clab"] = [to_cleaned(i, u)[0] for i, u in zip(d.I, d.rawU)]

    rows = []
    for (it, cl), g in d.groupby(["I", "clab"]):
        w = g.w.dropna()
        dim = (DIM.get(g.corrected_unit.dropna().iloc[0], "?")
               if g.corrected_unit.notna().any() else "?")
        rows.append([it, cl, canonical(it, cl), fold_verdict(it, cl), dim, len(g),
                     round(w.median(), 1) if len(w) else None])

    fold_map = pd.DataFrame(rows, columns=["item", "label", "harmonized_nsu_unit",
                                          "fold_verdict", "dimension", "n", "median_g"])
    fold_map = fold_map.sort_values(["item", "harmonized_nsu_unit", "n"],
                                    ascending=[True, True, False])
    fold_map.to_csv(OUT_CSV, index=False, encoding="utf-8-sig")
    print(f"wrote {OUT_CSV}  ({len(fold_map)} rows, n sums to {fold_map.n.sum():,})")

    # A fold that pooled labels whose medians disagree is the thing worth eyeballing, so
    # name them here instead of leaving them to be found by scrolling the csv.
    print("\nfolds pooling >1 label, ranked by how far their medians disagree:")
    pooled = fold_map[fold_map.median_g.notna()].groupby(
        ["item", "harmonized_nsu_unit"]).filter(lambda g: len(g) > 1)
    if pooled.empty:
        print("  none")
        return
    spread = (pooled.groupby(["item", "harmonized_nsu_unit"])
                    .agg(labels=("label", "count"),
                         lo=("median_g", "min"), hi=("median_g", "max"),
                         n=("n", "sum")).reset_index())
    spread["ratio"] = (spread.hi / spread.lo).round(2)
    spread = spread.sort_values("ratio", ascending=False)
    for r in spread.head(12).itertuples():
        print(f"  {r.ratio:>6.2f}x  {r.item[:34]:<34} {r.harmonized_nsu_unit[:20]:<20}"
              f" {r.labels} labels, n={r.n}, {r.lo:g}-{r.hi:g}")
    print(f"\n  {len(spread)} pooled folds in total;"
          f" {int((spread.ratio >= 2).sum())} disagree by 2x or more.")


if __name__ == "__main__":
    main()
