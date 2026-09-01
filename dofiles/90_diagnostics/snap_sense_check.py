r"""Every weight the anchor snap moved, laid out for a human to eyeball.

Issue #18 A1 replaced a fixed-factor magnitude rule with a snap toward each row's own
item x unit cell anchor. That changes published weights, so this writes the changed
rows out with enough context to judge them one by one -- what was typed, what each rule
says, what the rest of the cell says, and whether the row reaches the deliverable.

Sheets, in the order worth reading:

  disagreements   every row where the anchor and the block reading differ. Sorted by
                  how far the published value sits from its cell median, so the rows
                  most likely to be wrong are at the top whichever rule produced them.
  gate_overrules  rows where the anchor was REJECTED as implausible and the block
                  reading published instead. These are the contaminated cells.
  published_diff  case x size rows of the deliverable whose value moved, old vs new.
  cell_context    every weighing in any cell touched above, so a disputed row can be
                  read against its neighbours rather than in isolation.

Run from the project root:  python dofiles/90_diagnostics/snap_sense_check.py
"""
import io, re
import numpy as np, pandas as pd
from pathlib import Path

T = Path("outputs/master_rename_build/temp")
OUT = Path("outputs/master_rename_build/tables/snap_sense_check.xlsx")
SNAP_DO = Path("dofiles/00_shared/04_unit_snap.do")

# ---------------------------------------------------------------- constant tripwire
# This script RE-IMPLEMENTS the block reading (see `block_says' below), because the
# block rule is a plain threshold and the .dta does not carry its answer separately.
# That leaves three constants duplicated from 04_unit_snap.do. They agree today, and
# nothing would tell you if they stopped: this file would keep scoring the two rules
# against a threshold the pipeline no longer uses, on the very workbook the rule is
# being judged from. Silent, and wrong in the direction of looking fine.
#
# So: read them out of the do-file and fail if they have moved. The do-file is the
# source of truth; EXPECTED is only what this script last agreed with.
#
# The anchor snap is NOT re-implemented -- `anchor_says' is read from `w_step1', which
# 04_unit_snap.do carries forward for exactly this comparison. Only the block reading
# is duplicated, and only because it is three lines of threshold.
EXPECTED = {"KGMAX": 30, "WFLOOR": 10, "WCEIL": 50000}


def _locals_from_do(path, names):
    """Pull `local NAME = VALUE' out of a do-file. Returns {name: int}."""
    txt = io.open(path, encoding="utf-8", errors="replace").read()
    found = {}
    for n in names:
        m = re.search(r"^\s*local\s+" + n + r"\s*=\s*(-?\d+)", txt, re.M)
        if m:
            found[n] = int(m.group(1))
    return found


_have = _locals_from_do(SNAP_DO, EXPECTED)
_missing = sorted(set(EXPECTED) - set(_have))
if _missing:
    raise SystemExit(
        f"could not find local(s) {chr(44).join(_missing)} in {SNAP_DO}." + "\n"
        "They were renamed or removed. Do not delete this check to get past it --"
        " the block reading below is built from those values and would diverge.")
_moved = {k: (EXPECTED[k], _have[k]) for k in EXPECTED if EXPECTED[k] != _have[k]}
if _moved:
    raise SystemExit(
        "04_unit_snap.do thresholds moved; this diagnostic still uses the old ones:"
        + "\n"
        + "\n".join(f"  {k}: this script has {a}, the do-file says {b}"
                     for k, (a, b) in sorted(_moved.items()))
        + "\nUpdate EXPECTED and the block-reading lines together, then re-run."
          " Any comparison produced before that is scored against a rule the"
          " pipeline no longer applies.")

KGMAX = _have["KGMAX"]
WFLOOR, WCEIL = _have["WFLOOR"], _have["WCEIL"]

pre = pd.read_stata(T/"prelim_nsu_data.dta", convert_categoricals=False)
snap = pd.read_stata(T/"standard_weight_unit_correction.dta", convert_categoricals=False)
mas = pd.read_stata(T/"nsu_data_master.dta", convert_categoricals=False)

d = pre[["id","pull_province","pull_municipal_city","pull_item","harmonized_nsu_unit",
         "unit","weight","weighing_approach","item_nsu_hetero_type"]].merge(
    snap[["id","corrected_weight","w_step1","review_step1"]], on="id", validate="1:1")

# hetero_group and approach are labelled numerics; the codes alone are unreadable in a
# workbook a human is scanning. Decode from the value labels IN THE FILE rather than a
# dict in this script -- that mapping is already duplicated in several places and a
# hardcoded copy here would be one more thing to keep in step with
# `label define hetero' in 00_shared/00_globals.do.
_vl = pd.io.stata.StataReader(T/"prelim_nsu_data.dta").value_labels()
d["hetero_group"] = d.item_nsu_hetero_type.map(_vl["hetero"])
d["approach"] = d.weighing_approach.map(_vl["weighing_approach"])

# Nothing should fall outside the declared label set; if it does the codes have moved
# and every hetero_group in this workbook is suspect.
_bad = d.item_nsu_hetero_type.notna() & d.hetero_group.isna()
if _bad.any():
    raise SystemExit(
        f"{int(_bad.sum())} row(s) carry an item_nsu_hetero_type outside the `hetero'"
        " label set: "
        + ", ".join(map(str, sorted(d.loc[_bad, "item_nsu_hetero_type"].unique()))))
d = d.merge(mas[["id","cleaning_notes"]], on="id", how="left", validate="1:1")

d["base"] = d.weight.where(d.unit == 2, d.weight*1000)
d["cell"] = (d.pull_province+" / "+d.pull_municipal_city+" / "+d.pull_item
             +" / "+d.harmonized_nsu_unit)
d["published"] = d.corrected_weight.round()
d["anchor_says"] = d.w_step1.round()

# the block reading, recomputed exactly as 04_unit_snap.do states it
blk = pd.Series(np.nan, index=d.index)
m2, m3 = d.unit.eq(2), d.unit.eq(3)
blk[m2] = np.where(d.weight[m2] >= 10, d.weight[m2], d.weight[m2]*1000)
blk[m3] = np.where(d.weight[m3] >= 10, d.weight[m3], d.weight[m3]*1000)
m1 = d.unit.eq(1)
blk[m1] = np.where(d.weight[m1] > KGMAX, d.weight[m1], d.weight[m1]*1000)
d["block_says"] = blk.round()

# cell median of the rows the two rules AGREE on -- an independent-ish yardstick
agree = d[(d.anchor_says == d.block_says) & d.published.notna()]
med = agree.groupby("cell").published.median().rename("cell_median")
n_cell = agree.groupby("cell").size().rename("n_cell_agreeing")
d = d.join(med, on="cell").join(n_cell, on="cell")
d["x_from_median"] = (d.published / d.cell_median).where(d.cell_median > 0)
d["x_from_median"] = d.x_from_median.where(d.x_from_median >= 1, 1/d.x_from_median)

d["anchor_implausible"] = d.anchor_says.notna() & (
    (d.anchor_says < WFLOOR) | (d.anchor_says > WCEIL))
d["rule_used"] = np.where(d.anchor_implausible, "block (anchor rejected)", "anchor")

# hetero_group sits beside `cell' because it is what splits a cell into rows: on the
# size-based branch it is the field's small/medium/large label, on the price-quantity
# branch it is which price point the vendor was quoted (mp25/mp50/mp75, or a
# municipality/province median where the ladder is incomplete). Two rows in one cell
# with different hetero_groups are meant to differ in weight; two with the SAME
# hetero_group differing by a decade are the interesting case.
COLS = ["id","cell","hetero_group","approach","unit","weight",
        "block_says","anchor_says","published",
        "rule_used","cell_median","n_cell_agreeing","x_from_median",
        "review_step1","cleaning_notes"]

dis = d[(d.anchor_says != d.block_says) & d.published.notna()]
dis = dis.sort_values("x_from_median", ascending=False)
gate = d[d.anchor_implausible]

ref_new = pd.read_stata(T/"nsu_reference_set.dta", convert_categoricals=False)
touched = set(dis.cell)
ctx = d[d.cell.isin(touched)].sort_values(["cell","published"])

with pd.ExcelWriter(OUT) as w:
    dis[COLS].to_excel(w, "disagreements", index=False)
    gate[COLS].to_excel(w, "gate_overrules", index=False)
    ref_new.to_excel(w, "reference_set_now", index=False)
    ctx[COLS].to_excel(w, "cell_context", index=False)

# ---- score the two rules against an INDEPENDENT referee -----------------------
# The referee must not be the pool the anchor snaps toward, or the comparison is
# circular. STEP 1 anchors on pull_item x harmonized_nsu_unit pooled NATIONALLY, so
# scoring against that same median simply asks whether the snap snapped -- it did.
# The referee here is the LOCAL cell (province x municipality x item x unit), taken
# over the rows both rules agree on, and restricted to cells with >= 3 such rows.
sc = dis[dis.n_cell_agreeing.ge(3) & dis.cell_median.gt(0)].copy()
da = (np.log10(sc.anchor_says / sc.cell_median)).abs()
db = (np.log10(sc.block_says / sc.cell_median)).abs()
print("scored against the LOCAL cell median, "
      f"{len(sc):,} disputed rows in cells with >=3 agreeing rows:")
print(f"  anchor closer : {int((da < db).sum()):,}")
print(f"  block  closer : {int((db < da).sum()):,}")
print("  (a national anchor cannot see local variation -- see issue #28)")
print()
print(f"rows where the two rules disagree : {len(dis):,}")
print(f"  anchor published                : {(dis.rule_used=='anchor').sum():,}")
print(f"  block published (anchor rejected): {(dis.rule_used!='anchor').sum():,}")
print(f"cells touched                     : {len(touched):,}")
print(f"published rows now                : {len(ref_new):,}")
print(f"\nfurthest from the cell median (check these first):")
top = dis.head(12)[["cell","weight","block_says","anchor_says","published","cell_median"]]
print(top.to_string(index=False))
print(f"\nwrote {OUT}")
