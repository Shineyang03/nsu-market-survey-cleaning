r"""How many raw {unit, weight} readings did the pipeline change, and how many are uncertain?

Answers two questions that a reader of the reference set has to be able to ask, and
that nothing else in the project answered:

  1. How many weighings were published at a DIFFERENT magnitude from what the
     enumerator typed? "Corrected" here means only that: the published weight is not a
     straight unit conversion of the raw reading. A kg row published in grams is NOT a
     correction -- kg to g is a conversion, and every mass row gets one.

  2. How many are UNCERTAIN, and in what way? Three different things get conflated if
     they are not separated, and they need different follow-up:
       disputed        the two rules disagreed and one had to be chosen
       step1_flagged   the anchor machinery distrusted its own answer
       unusable        no interpretation was defensible, so the weight is .c

WHY BOTH NUMBERS MATTER TOGETHER. The corrected count on its own reads as a defect rate.
It is not: most corrections are decimal slips the pipeline is meant to repair. The
uncertain count is the part a reader should discount, and it is much smaller.

OUTPUT  outputs/master_rename_build/tables/weight_correction_report.csv
        one row per weighing, with the flags below -- built long so the pipeline
        explorer can filter and group it rather than re-deriving any of it
        outputs/master_rename_build/tables/weight_correction_summary.csv
        the counts, for citation

Run from the project root:  python dofiles/90_diagnostics/report_weight_corrections.py
"""
import numpy as np, pandas as pd
from pathlib import Path

T = Path("outputs/master_rename_build/temp")
OUT = Path("outputs/master_rename_build/tables")

pre = pd.read_stata(T / "prelim_nsu_data.dta", convert_categoricals=False)
mas = pd.read_stata(T / "nsu_data_master.dta", convert_categoricals=True)
snap = pd.read_stata(T / "standard_weight_unit_correction.dta", convert_categoricals=True)

d = pre[["id", "pull_province", "pull_municipal_city", "pull_item",
         "harmonized_nsu_unit", "unit", "weight"]].merge(
    mas[["id", "corrected_weight", "corrected_unit", "weighing_approach",
         "item_nsu_hetero_type", "snap_rule", "snap_referee", "snap_block",
         "review_step1", "cleaning_notes"]],
    on="id", validate="1:1")
d = d.merge(snap[["id", "w_step1"]], on="id", validate="1:1", suffixes=("", "_snap"))

# ---- the raw reading in canonical units, with NO magnitude repair ------------------
# unit 1 = kg, 2 = g, 3 = litres. kg->g and L->mL are conversions, not corrections, so
# they are applied here before anything is compared. Density ~ 1 for these items, which
# is the same assumption the pipeline makes and is recorded in docs/data_oddities.md.
d["raw_canonical"] = np.where(d.unit == 2, d.weight, d.weight * 1000)
d.loc[d.weight.isna(), "raw_canonical"] = np.nan

# ---- 1. was the magnitude changed -------------------------------------------------
d["published"] = d.corrected_weight
d["magnitude_corrected"] = (
    d.published.notna() & d.raw_canonical.notna()
    & (d.published.round(1) != d.raw_canonical.round(1)))

# how far, in decades -- a correction of one decade is a decimal slip, more than that
# is a unit tick read the wrong way
with np.errstate(divide="ignore", invalid="ignore"):
    d["decades_moved"] = np.log10(d.published / d.raw_canonical)
d.loc[~d.magnitude_corrected, "decades_moved"] = 0.0
d["decades_moved"] = d.decades_moved.replace([np.inf, -np.inf], np.nan).round(2)

# ---- 2. the three kinds of uncertainty --------------------------------------------
# `disputed' is read off snap_block against w_step1 rather than recomputed: a row is
# disputed exactly when the published value is not STEP 1's answer, which is what
# snap_block records. Recomputing the block rule here would duplicate it.
d["unusable"] = d.published.isna()
d["disputed"] = d.snap_block.fillna(0).astype(int).eq(1) & ~d.unusable
d["step1_flagged"] = d.review_step1.fillna(0).astype(int).eq(1)
d["any_uncertainty"] = d.unusable | d.disputed | d.step1_flagged

cols = ["id", "pull_province", "pull_municipal_city", "pull_item",
        "harmonized_nsu_unit", "weighing_approach", "item_nsu_hetero_type",
        "unit", "weight", "raw_canonical", "published", "corrected_unit",
        "magnitude_corrected", "decades_moved", "snap_rule", "snap_referee",
        "snap_block", "disputed", "step1_flagged", "unusable", "any_uncertainty",
        "cleaning_notes"]
d[cols].to_csv(OUT / "weight_correction_report.csv", index=False,
               encoding="utf-8-sig")

# ---- the summary, in the form the numbers get quoted in ---------------------------
n = len(d)
rows = [
    ("weighings in the built dataset", n),
    ("  published at the typed magnitude (conversion only)",
     int((~d.magnitude_corrected & d.published.notna()).sum())),
    ("  published at a CORRECTED magnitude", int(d.magnitude_corrected.sum())),
    # The buckets are three decades, one decade, and everything else, because that is
    # how the data actually falls -- see the crosstab this script prints. Three decades
    # is not "a big decimal slip": it is the UNIT TICK contradicting the number. An
    # enumerator who writes 0.275 and ticks grams has written the kilogram number, and
    # x1000 is the repair. That is the single largest category of correction in the
    # file, and calling it a decimal error misdescribes what the field did.
    ("    ... x1000: a kilogram number ticked as grams (or mL as L)",
     int((d.magnitude_corrected & d.decades_moved.between(2.5, 3.5)).sum())),
    ("    ... /1000: a gram number ticked as kilograms (or mL as L)",
     int((d.magnitude_corrected & d.decades_moved.between(-3.5, -2.5)).sum())),
    ("    ... one decade, either way: a decimal slip",
     int((d.magnitude_corrected & d.decades_moved.abs().between(0.5, 1.5)).sum())),
    ("    ... any other distance", int((d.magnitude_corrected
        & ~d.decades_moved.between(2.5, 3.5)
        & ~d.decades_moved.between(-3.5, -2.5)
        & ~d.decades_moved.abs().between(0.5, 1.5)).sum())),
    ("uncertain -- any of the three below", int(d.any_uncertainty.sum())),
    ("  disputed: the two rules disagreed, block published",
     int(d.disputed.sum())),
    ("  step1_flagged: the anchor distrusted its own answer",
     int(d.step1_flagged.sum())),
    ("  unusable: no defensible reading, weight is .c", int(d.unusable.sum())),
]
s = pd.DataFrame(rows, columns=["measure", "weighings"])
s["share_of_all"] = (s.weighings / n * 100).round(1)
s.to_csv(OUT / "weight_correction_summary.csv", index=False, encoding="utf-8-sig")

print(s.to_string(index=False))
print()
print("corrections by the rule that set them:")
print(d[d.magnitude_corrected].snap_rule.value_counts().to_string())
print()
print("corrections by raw unit ticked (1 = kg, 2 = g, 3 = litres) x decades moved.")
print("Read the +3 column against unit 2: that is the kilogram-number-ticked-as-grams")
print("case, and it is most of the corrections in the file.")
print(pd.crosstab(d[d.magnitude_corrected].decades_moved.round(0),
                  d[d.magnitude_corrected].unit).to_string())
print()
print(f"wrote {OUT / 'weight_correction_report.csv'}")
print(f"wrote {OUT / 'weight_correction_summary.csv'}")
