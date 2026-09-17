r"""How many raw {unit, weight} readings did the pipeline change, and how many are uncertain?

Answers two questions that a reader of the reference set has to be able to ask, and
that nothing else in the project answered:

  1. How many weighings were published at a DIFFERENT magnitude from what the
     enumerator typed? "Corrected" here means only that: the published weight is not a
     straight unit conversion of the raw reading. A kg row published in grams is NOT a
     correction -- kg to g is a conversion, and every mass row gets one.

  2. On how many do the two candidate readings DISAGREE, and on how many is there no
     reading at all?
       readings_differ  the typed reading and the pool-anchored reading are not the
                        same number -- which, since the anchor only moves the decimal
                        point, means the typed number sits in a different DECADE from
                        its pool's median
       no_reading       nothing defensible could be read, so the weight is .c

     NEITHER IS PUBLISHED, AND THAT IS DELIBERATE. Both were carried into the
     deliverables until 2026-09-17 as `disputed' / `unusable', aggregated into
     n_uncertain and share_uncertain. They were retired because the pipeline publishes
     the TYPED reading precisely on the grounds that differing from neighbours does not
     impeach a non-standard unit -- so flagging the row as doubtful for differing from
     its neighbours contradicted the rule that produced the number. 08_branch.do carries
     the full reasoning.

     They are still reported HERE, because a difference between two readings is a real
     fact about the row and someone will want the list. A diagnostic may describe it; a
     deliverable should not grade a weight on it.

WHY BOTH NUMBERS MATTER TOGETHER. The corrected count on its own reads as a defect rate.
It is not: most corrections are unit-tick errors the pipeline is meant to repair.

OUTPUT  outputs/build/summary/weight_correction_report.csv
        one row per weighing, with the flags below -- built long so the pipeline
        explorer can filter and group it rather than re-deriving any of it
        outputs/build/summary/weight_correction_summary.csv
        the counts, for citation

Run from the project root:  python dofiles/90_diagnostics/report_weight_corrections.py
"""
import numpy as np, pandas as pd
from pathlib import Path

# ANCHORED ON THE REPO ROOT, not on the working directory. These used to be relative
# (`Path("outputs/...")`), which means running this script from dofiles/ -- the directory
# every do-file must be run from -- silently CREATES dofiles/outputs/build/
# and writes there. An empty three-level tree of exactly that shape was sitting in the
# repo, which is how the defect was found. Deriving the root from this file's own location
# makes the script work from anywhere and makes that failure impossible.
DC = Path(__file__).resolve().parents[2]
T = DC / "outputs" / "build" / "intermediate"
OUT = DC / "outputs" / "build" / "summary"

pre = pd.read_stata(T / "prelim_nsu_data.dta", convert_categoricals=False)
mas = pd.read_stata(T / "nsu_data_master.dta", convert_categoricals=True)
snap = pd.read_stata(T / "standard_weight_unit_correction.dta", convert_categoricals=True)

d = pre[["id", "pull_province", "pull_municipal_city", "pull_item",
         "harmonized_nsu_unit", "unit", "weight"]].merge(
    mas[["id", "corrected_weight", "corrected_unit", "weighing_approach",
         "item_nsu_hetero_type", "snap_rule", "snap_referee", "snap_block",
         "review_step1", "w_block", "cleaning_notes"]],
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
# DERIVED HERE, DELIBERATELY, AND ONLY HERE -- 2026-09-17.
#
# These used to be read off d_unusable / d_disputed / d_any_uncertain in
# nsu_weighings_cpi.dta, because both deliverables published them. Those columns are
# retired (see 00_shared/08_branch.do for why), so this report computes the comparison
# itself from the two readings the build still carries.
#
# THE RENAME IS THE POINT, not cosmetic. `readings_differ' is a FACT about the row: the
# typed reading and the pool-anchored reading are not the same number. The old name
# `disputed' asserted more than that -- it implied a contest in which one answer had to
# be chosen, and the pipeline no longer holds one: the typed reading is published wherever
# it is possible. A diagnostic may report the difference; nothing should publish it as a
# verdict on the weight.
#
# This is not the duplication #32 forced out of the normalizers. There is no second
# definition to drift from any more -- the build has none.
_ref = pd.read_stata(T / "nsu_weighings_cpi.dta", columns=["id"])
d = d.merge(_ref.assign(_in_build=True), on="id", how="left", validate="1:1")

# A weighing missing from nsu_weighings_cpi was dropped at stage 2 and never reached
# either deliverable. Left as NA rather than filled: a False would say "the readings
# agree" about a row nothing ever compared.
_seen = d["_in_build"].fillna(False).astype(bool)
d["no_reading"] = pd.NA
d["readings_differ"] = pd.NA
d.loc[_seen, "no_reading"] = d.loc[_seen, "published"].isna()
d.loc[_seen, "readings_differ"] = (
    d.loc[_seen, "w_step1"].notna() & d.loc[_seen, "w_block"].notna()
    & (d.loc[_seen, "w_step1"] != d.loc[_seen, "w_block"])
) | (d.loc[_seen, "w_step1"].isna() != d.loc[_seen, "w_block"].isna())
for c in ["no_reading", "readings_differ"]:
    d[c] = d[c].astype("boolean")
d = d.drop(columns=["_in_build"])

# `branch' is ADDED, not substituted. The subject of this report is the weight correction,
# which happens upstream of branching and is unaffected by it -- so weighing_approach, the
# field record, stays. But the report describes rows that SHIP, and a reader asking why a
# conventional case appears as medium needs to see it here rather than having to join the
# reference set. #28 lists this file among those that must follow `branch'.
#
# It comes from nsu_weighings_cpi rather than nsu_data_master, because 08_branch.do writes
# into the former. Absent when 08 has not run, and the report is still usable without it,
# so this warns rather than exits -- unlike the two scope_* scripts, whose whole output is
# a partition keyed on it.
_wc = T / "nsu_weighings_cpi.dta"
if _wc.exists():
    # Asked by trying the read, not by inspecting varlist -- StataReader exposes the
    # variable list under different names across pandas versions, and a wrong guess here
    # would silently take the else branch and drop the column with a misleading note.
    try:
        _b = pd.read_stata(_wc, columns=["id", "branch", "d_reclassified"])
    except (ValueError, KeyError):
        _b = None
    if _b is not None:
        d = d.merge(_b, on="id", how="left", validate="1:1")
    else:
        print("note: nsu_weighings_cpi.dta has no `branch' -- run 00_shared/08_branch.do "
              "to have the reclassified conventional cases identified in this report")
else:
    print(f"note: {_wc.name} not found; `branch' omitted from this report")

cols = ["id", "pull_province", "pull_municipal_city", "pull_item",
        "harmonized_nsu_unit", "weighing_approach", "item_nsu_hetero_type",
        "unit", "weight", "raw_canonical", "published", "corrected_unit",
        "magnitude_corrected", "decades_moved", "snap_rule", "snap_referee",
        "snap_block", "readings_differ", "no_reading",
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
    # NOT an error rate, and not published anywhere. The two readings differing means
    # the typed number sits in a different decade from its pool's median -- which for a
    # NON-STANDARD unit is partly the thing being measured. Reported because it is a real
    # feature of the data and someone will want to look at those rows; retired as a
    # published verdict on 2026-09-17 (see 00_shared/08_branch.do).
    ("the two readings differ (typed vs pool-anchored)",
     int(d.readings_differ.fillna(False).sum())),
    ("no defensible reading at all, weight is .c",
     int(d.no_reading.fillna(False).sum())),
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
