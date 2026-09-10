r"""How much does the magnitude rule (STEP 3) disagree with the log10 snap (STEP 1)?

THE QUESTION THIS ANSWERS. `00_shared/04_unit_snap.do` computes two independent
corrections and keeps only one. STEP 1 snaps each weight to the nearest power of ten
toward a robust item x unit anchor, and flags rows whose anchor is untrustworthy. STEP 3
then applies a flat magnitude threshold -- below 10, multiply by 1,000; above it, believe
the number -- and overwrites STEP 1 on every row that has a weight, which is 11,448 of
11,453. So the anchor snap decides nothing and the threshold decides everything.

That was not a design decision. STEP 3 was written to resolve the rows STEP 1 flagged for
review, and its blocks happen to partition the whole domain, so it swallowed the rest.
Whether the blunt rule is the RIGHT rule is issue #18's open question, and it cannot be
argued without knowing where the two rules actually disagree. This file measures that.

WHAT IT NEEDS. `04_unit_snap.do` carries STEP 1's answer forward as `w_step1` (and its
review flag as `review_step1`) purely so this comparison is possible; STEP 3 would
otherwise destroy it in place. Nothing in the build reads either column.

HOW TO READ THE OUTPUT. The headline is the disagreement rate and, more importantly, WHO
is right where they differ. Neither rule is ground truth, so the report leans on two
things that are closer to it:

  * the ITEM x UNIT median of the other, undisputed rows -- a disputed row whose STEP 3
    value sits far from its own cell's median is the suspicious one;
  * whether STEP 1 had flagged the row for review at all. A row STEP 1 was confident
    about and STEP 3 overruled is a different case from one STEP 1 also could not place.

OUTPUT  outputs/tables/snap_step1_vs_step3.csv   one row per disagreement

RUN, from the project root, after master_outcome1.do has run:
    python dofiles/90_diagnostics/snap_step1_vs_step3.py
"""
import sys
from pathlib import Path

import pandas as pd

DC = Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel"
          r"\14 NSU Market Survey\Data Cleaning")
TEMP = DC / "outputs" / "build" / "temp"
SNAP = TEMP / "standard_weight_unit_correction.dta"
PRELIM = TEMP / "prelim_nsu_data.dta"
OUT = DC / "outputs" / "tables" / "snap_step1_vs_step3.csv"


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def main():
    snap = pd.read_stata(SNAP, convert_categoricals=False)
    if "w_step1" not in snap.columns:
        print("standard_weight_unit_correction.dta has no w_step1 column.")
        print("Re-run the build: 04_unit_snap.do carries it only since issue #18.")
        return 1

    # join on id, never on row position
    prelim = pd.read_stata(PRELIM, convert_categoricals=False)
    keep = ["id", "weight", "unit", "pull_item", "harmonized_nsu_unit",
            "pull_province", "pull_municipal_city", "item_nsu_hetero_type"]
    keep = [c for c in keep if c in prelim.columns]
    d = snap.merge(prelim[keep], on="id", how="left", validate="1:1")
    d["w3"] = pd.to_numeric(d.corrected_weight, errors="coerce")
    d["w1"] = pd.to_numeric(d.w_step1, errors="coerce")

    h("COVERAGE")
    print(f"  rows in the snap output          : {len(d):,}")
    print(f"  with a STEP 3 value              : {int(d.w3.notna().sum()):,}")
    print(f"  with a STEP 1 value              : {int(d.w1.notna().sum()):,}")
    both = d[d.w3.notna() & d.w1.notna()].copy()
    print(f"  comparable (both non-missing)     : {len(both):,}")

    h("DISAGREEMENT")
    both["same"] = (both.w1 - both.w3).abs() <= 0.5     # both rounded to whole units
    agree, dis = int(both.same.sum()), int((~both.same).sum())
    print(f"  agree    : {agree:>6,}  ({agree/len(both)*100:.2f}%)")
    print(f"  DISAGREE : {dis:>6,}  ({dis/len(both)*100:.2f}%)")
    if dis == 0:
        print("\n  The two rules give the same answer on every comparable row. STEP 3"
              "\n  overwriting STEP 1 changes no published weight, and the choice"
              "\n  between them is moot on this data.")
        return 0

    x = both[~both.same].copy()
    x["ratio"] = x.w3 / x.w1
    print(f"\n  ratio STEP 3 / STEP 1, over the {dis:,} disagreements:")
    print("   " + x.ratio.describe(percentiles=[.05, .25, .5, .75, .95])
          .to_string().replace("\n", "\n   "))
    print("\n  disagreements by exact power-of-ten factor:")
    import numpy as np
    x["decades"] = np.log10(x.ratio).round(3)
    print("   " + x.decades.value_counts().sort_index().rename("rows")
          .to_string().replace("\n", "\n   "))

    h("DID STEP 1 KNOW IT WAS UNSURE?")
    # A row STEP 1 flagged for review and STEP 3 overruled is a rule doing its job.
    # A row STEP 1 was CONFIDENT about and STEP 3 overruled is the interesting case.
    if "review_step1" in x.columns:
        fl = x.review_step1.fillna(0).astype(int)
        print(f"  disagreements where STEP 1 had flagged the row : {int((fl==1).sum()):,}")
        print(f"  disagreements where STEP 1 was CONFIDENT       : {int((fl==0).sum()):,}")
        print("\n  The confident ones are the substance of #18: STEP 1 placed the row"
              "\n  against its cell's anchor, raised no flag, and STEP 3 overruled it"
              "\n  anyway on magnitude alone.")

    h("WHICH ANSWER LOOKS RIGHT?")
    # Reference = the median of the rows the two rules AGREE on, within item x unit.
    # It is not ground truth, but it is independent of the disputed rows themselves.
    ref = (both[both.same].groupby(["pull_item", "harmonized_nsu_unit"]).w3
                          .agg(["median", "size"])
                          .rename(columns={"median": "cell_med", "size": "cell_n"}))
    x = x.join(ref, on=["pull_item", "harmonized_nsu_unit"])
    ok = x[x.cell_med.notna() & (x.cell_n >= 3)].copy()
    print(f"  disagreements in a cell with >=3 undisputed rows: {len(ok):,} of {dis:,}")
    if len(ok):
        ok["d1"] = (ok.w1 / ok.cell_med).apply(lambda r: abs(pd.np.log10(r))
                                               if hasattr(pd, "np") else abs(__import__("math").log10(r)))
        ok["d3"] = (ok.w3 / ok.cell_med).apply(lambda r: abs(__import__("math").log10(r)))
        s1_closer = int((ok.d1 < ok.d3).sum())
        s3_closer = int((ok.d3 < ok.d1).sum())
        tie = len(ok) - s1_closer - s3_closer
        print(f"    STEP 1 closer to its cell median : {s1_closer:,}")
        print(f"    STEP 3 closer to its cell median : {s3_closer:,}")
        print(f"    tie                              : {tie:,}")
        print("\n  Read this as a hint, not a verdict: the cell median is built from the"
              "\n  rows the rules agree on, so it inherits whatever they agree to be"
              "\n  wrong about.")

    h("THE DISAGREEMENTS")
    cols = [c for c in ["id", "pull_province", "pull_municipal_city", "pull_item",
                        "harmonized_nsu_unit", "weight", "unit", "w1", "w3", "ratio",
                        "review_step1", "cell_med", "cell_n"] if c in x.columns]
    out = x[cols].sort_values("ratio", ascending=False)
    out.to_csv(OUT, index=False, encoding="utf-8-sig")
    print(f"  wrote {OUT}  ({len(out):,} rows)")
    show = out.head(25)
    for r in show.itertuples():
        fl = "flagged" if getattr(r, "review_step1", 0) == 1 else "confident"
        print(f"    {r.ratio:>9.4g}x  {str(r.pull_item)[:28]:<28}"
              f" {str(r.harmonized_nsu_unit)[:14]:<14} raw={r.weight:g} u={r.unit:g}"
              f"  step1={r.w1:g} step3={r.w3:g}  ({fl})")
    if len(out) > 25:
        print(f"    ... {len(out)-25:,} more in the csv")
    return 0


if __name__ == "__main__":
    sys.exit(main())
