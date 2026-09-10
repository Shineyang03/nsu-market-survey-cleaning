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

     THESE ARE THE BUILD'S FLAGS, read from nsu_weighings_cpi.dta. `08_branch.do' owns
     their definition, because both deliverables now publish them (#35): the reference
     set carries n_disputed / n_flagged / n_uncertain / share_uncertain per published
     row, and every converted PSPS household row carries nu_used at the rung that
     supplied its weight. This script no longer derives them, so it cannot disagree
     with what shipped.

WHY BOTH NUMBERS MATTER TOGETHER. The corrected count on its own reads as a defect rate.
It is not: most corrections are decimal slips the pipeline is meant to repair. The
uncertain count is the part a reader should discount, and it is much smaller.

OUTPUT  outputs/master_rename_build/summary/weight_correction_report.csv
        one row per weighing, with the flags below -- built long so the pipeline
        explorer can filter and group it rather than re-deriving any of it
        outputs/master_rename_build/summary/weight_correction_summary.csv
        the counts, for citation

Run from the project root:  python dofiles/90_diagnostics/report_weight_corrections.py
"""
import numpy as np, pandas as pd
from pathlib import Path

T = Path("outputs/master_rename_build/intermediate")
OUT = Path("outputs/master_rename_build/summary")

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
# READ FROM THE BUILD, NOT DERIVED HERE. `08_branch.do' defines these four flags and
# writes them into nsu_weighings_cpi.dta, because both deliverables now publish them
# (#35). This script used to derive its own copy from snap_block and review_step1 --
# correct at the time and free to drift the moment either definition moved, which is the
# duplication #32 forced out of the string normalizers.
#
# So the direction is: the build decides, this report describes. A diagnostic reads the
# quantity the pipeline computed; it never recomputes it.
_flags = ["d_unusable", "d_disputed", "d_step1_flagged", "d_any_uncertain"]
fl = pd.read_stata(T / "nsu_weighings_cpi.dta", columns=["id"] + _flags)
d = d.merge(fl, on="id", how="left", validate="1:1")

# A weighing missing from nsu_weighings_cpi was dropped at stage 2 and never reached
# either deliverable, so it has no published flag to report. Left as NA rather than
# filled: a False here would say "not questioned" about a row nothing ever judged.
d = d.rename(columns={"d_unusable": "unusable", "d_disputed": "disputed",
                      "d_step1_flagged": "step1_flagged",
                      "d_any_uncertain": "any_uncertainty"})
for c in ["unusable", "disputed", "step1_flagged", "any_uncertainty"]:
    d[c] = d[c].astype("boolean")

# The one cross-check worth keeping, and it is a check rather than a second definition:
# `unusable' means the published weight is missing, which this script can see directly
# from the column it already read. If the build's flag and the published value disagree,
# one of them is wrong and the report must not paper over it.
_seen = d.unusable.notna()
_mismatch = int((d.loc[_seen, "unusable"].astype(bool) != d.loc[_seen, "published"].isna()).sum())
if _mismatch:
    raise SystemExit(
        f"{_mismatch} row(s) where the build's d_unusable disagrees with whether "
        "corrected_weight is missing. 08_branch.do and this report cannot both be right; "
        "fix the build before quoting either number.")

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
