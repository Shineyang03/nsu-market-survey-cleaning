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

# snap_rule / snap_referee are labelled in nsu_data_master, not prelim, so their value
# labels come from that file. Numeric codes here would be unreadable in a workbook whose
# whole purpose is a human scanning it.
_vlm = pd.io.stata.StataReader(T / "nsu_data_master.dta").value_labels()

# Nothing should fall outside the declared label set; if it does the codes have moved
# and every hetero_group in this workbook is suspect.
_bad = d.item_nsu_hetero_type.notna() & d.hetero_group.isna()
if _bad.any():
    raise SystemExit(
        f"{int(_bad.sum())} row(s) carry an item_nsu_hetero_type outside the `hetero'"
        " label set: "
        + ", ".join(map(str, sorted(d.loc[_bad, "item_nsu_hetero_type"].unique()))))
# cleaning_notes AND the post-05 weight. `published' below is 04's answer; 05 then
# applies the hand corrections and the .c readings, so on a handful of rows the two
# differ and the sheet used to show only the first. A reviewer looking for remaining
# errors needs the value that actually ships.
d = d.merge(mas[["id","cleaning_notes","corrected_weight","snap_rule","snap_referee"]]
            .rename(columns={"corrected_weight":"final_weight"}),
            on="id", how="left", validate="1:1")
for _c in ("snap_rule", "snap_referee"):
    if _c in d.columns and _c in _vlm:
        d[_c] = d[_c].map(_vlm[_c])
d["final_differs"] = (d.final_weight.round(1) != d.corrected_weight.round(1)) & (
    d.final_weight.notna() | d.corrected_weight.notna())

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
# snap_rule / snap_referee say WHY the published value is what it is -- which rule
# fired and which pool refereed it. final_weight is what ships after
# 05_manual_corrections.do; final_differs marks the rows where 04's answer was
# subsequently overridden by hand or set unusable, so they are not read as errors.
COLS = ["id","cell","hetero_group","approach","unit","weight",
        "block_says","anchor_says","published","final_weight","final_differs",
        "snap_rule","snap_referee",
        "rule_used","cell_median","n_cell_agreeing","x_from_median",
        "review_step1","cleaning_notes"]

# ---- carry the PREVIOUS review forward ---------------------------------------
# A second review pass must not start from a blank sheet. Two things have to survive
# a regeneration:
#
#   1. the verdicts already given, so they are not re-litigated, and
#   2. whether each verdict actually LANDED, because one did not -- ANTIQUE /
#      SAN REMIGIO / preserved meat / bilog, raw 60 g, was adjudicated to the block
#      reading and still publishes 600 g.
#
# MATCHED ON CONTENT, NOT ON `id'. The reviewed workbook predates durable ids, so
# every id in it points somewhere else now. The key is (cell, hetero_group, raw
# weight) -- what the reviewer was actually looking at, and none of it renumbers.
REVIEWED_DIR = Path("reference/reviewed")


def _vkey(frame):
    """cell | hetero_group | raw weight, rendered so float32 cannot break the join.

    `weight' is a Stata float, so the .dta side renders 1265 as "1264.9999" and 3670
    as "3670.0002", while the workbook side comes back from Excel as float64 and
    renders them exactly. A decimal round cannot fix this across a range running from
    0.007 to 7,680 -- float32's error is RELATIVE, so any fixed number of decimals is
    too coarse at one end or too fine at the other. Six significant digits is inside
    float32's ~7 and reproduces every raw reading in the file exactly.

    This is the same trap as the float() wrapper in 05_manual_corrections.do sec 4a,
    and it failed the same way: silently, matching nothing, on 2 of 10 verdicts.
    """
    return (frame.cell.astype(str) + "|" + frame.hetero_group.astype(str)
            + "|" + frame.weight.map(lambda v: "" if pd.isna(v) else f"{v:.6g}"))


prior = {}
_src = sorted(REVIEWED_DIR.glob("snap_sense_check_REVIEWED_*.xlsx"))
if _src:
    _latest = _src[-1]
    for _sheet in ("disagreements", "gate_overrules", "cell_context"):
        try:
            _r = pd.read_excel(_latest, sheet_name=_sheet)
        except Exception:
            continue
        if "Corrected Value" not in _r.columns:
            continue
        _r = _r[_r["Corrected Value"].notna()]
        for _k, _v in zip(_vkey(_r), _r["Corrected Value"]):
            prior.setdefault(_k, _v)
    print(f"carried {len(prior)} prior verdict(s) forward from {_latest.name}")
else:
    print("NO reviewed workbook found under reference/reviewed -- starting clean")

# Verdicts given in an issue COMMENT rather than in the workbook. The second review
# round on #18 adjudicated two rows in prose ("id: 2835, correction in cell_context"),
# and the cell_context sheet has no `Corrected Value' column to have carried them, so
# they cannot be recovered by the loop above. Keyed on content, like everything else:
# the ids cited predate durable ids and no longer resolve.
COMMENT_VERDICTS = {
    # ANTIQUE / SAN REMIGIO / preserved meat / bilog, raw 60 g. Adjudicated to the
    # block reading -- its only neighbour in the cell weighs 65 g, while the province
    # pool for preserved meat `bilog' sits near 600 g (issue #28).
    "ANTIQUE / SAN REMIGIO / preserved or processed meat (tocino, tapa, longaniza, "
    "etc) / bilog|province_median|60": "60",
}
for _k, _v in COMMENT_VERDICTS.items():
    prior.setdefault(_k, _v)

d["prior_verdict"] = _vkey(d).map(prior)

# A verdict that matches no current row is a broken reference, not a silent no-op.
_unmatched = set(prior) - set(_vkey(d))
if _unmatched:
    print(f"WARNING: {len(_unmatched)} prior verdict(s) match no row in this build.")
    print("  The content key moved, or the row was dropped upstream. Reconcile these")
    print("  rather than letting a past decision fall out of the build silently:")
    for _k in sorted(_unmatched):
        print(f"    {_k}")


def _landed(row):
    """Did the published value end up where the reviewer said it should?

    A row set unusable by hand counts as SETTLED, not as a verdict that failed to
    land. The CAPIZ / PANAY mineral water is the case: the workbook says "7000 mL",
    and the later instruction on #18 was to drop it as a non-sensical unit instead.
    05_manual_corrections.do sec 4a does that (corrected_weight = .c), so falling
    back to `published' here would report a wrong number as still standing.
    """
    if pd.isna(row.prior_verdict):
        return ""
    if row.final_differs and pd.isna(row.final_weight):
        return "superseded -- row set unusable by hand"
    m = re.search(r"[-+]?\d*\.?\d+", str(row.prior_verdict).replace(",", ""))
    if not m:                      # a free-text verdict, e.g. "drop it"
        return "check by hand"
    want = float(m.group())
    got = row.final_weight if pd.notna(row.final_weight) else row.published
    if pd.isna(got):
        return "row no longer published"
    return "yes" if abs(got - want) < 0.5 else "NO -- still " + f"{got:g}"


d["verdict_landed"] = d.apply(_landed, axis=1)

# ---- what still needs a human ------------------------------------------------
# Two populations, and they are different problems.
#
#   a) a verdict was given and did not land. A bug, and it publishes a wrong number.
#   b) the anchor published, a PROVINCE pool refereed it, and the block reading sits
#      closer to the row's OWN cell median in decades. "Default to the block" only
#      fires where the referee is undecided; where the province pool has an opinion
#      the anchor still wins, and for units whose local meaning varies that pool is
#      the wrong authority (issue #28).
_anchor_won = d.published.round(6).eq(d.anchor_says.round(6))
_prov = d.snap_referee.astype(str).str.startswith("prov")
_ok = d.cell_median.gt(0) & d.block_says.gt(0) & d.published.gt(0)
_blk_closer = _ok & (
    (np.log10(d.block_says.where(_ok)) - np.log10(d.cell_median.where(_ok))).abs()
    < (np.log10(d.published.where(_ok)) - np.log10(d.cell_median.where(_ok))).abs())

d["needs_review"] = ""
d.loc[_anchor_won & _prov & _blk_closer, "needs_review"] = \
    "province refereed; block sits closer to this cell"
d.loc[d.verdict_landed.astype(str).str.startswith("NO"), "needs_review"] = \
    "PRIOR VERDICT NOT APPLIED"

# Blank column for the reviewer to fill in. Pre-created so annotation happens in
# place and the next run can read it back through the same content key.
d["Corrected Value"] = ""

RCOLS = (COLS[:COLS.index("review_step1")]
         + ["prior_verdict", "verdict_landed", "needs_review", "Corrected Value"]
         + COLS[COLS.index("review_step1"):])

dis = d[(d.anchor_says != d.block_says) & d.published.notna()]
dis = dis.sort_values("x_from_median", ascending=False)
gate = d[d.anchor_implausible]

ref_new = pd.read_stata(T/"nsu_reference_set.dta", convert_categoricals=False)
touched = set(dis.cell)
ctx = d[d.cell.isin(touched)].sort_values(["cell","published"])

# The sheet to open first: only the rows a human still has to decide, worst first.
todo = d[d.needs_review.ne("")].copy()
todo["_order"] = np.where(todo.needs_review.eq("PRIOR VERDICT NOT APPLIED"), 0, 1)
todo = todo.sort_values(["_order", "x_from_median"], ascending=[True, False])

with pd.ExcelWriter(OUT) as w:
    todo[RCOLS].to_excel(w, "to_review", index=False)
    dis[RCOLS].to_excel(w, "disagreements", index=False)
    gate[RCOLS].to_excel(w, "gate_overrules", index=False)
    ref_new.to_excel(w, "reference_set_now", index=False)
    ctx[RCOLS].to_excel(w, "cell_context", index=False)

print(f"\nprior verdicts matched to a current row : {int(d.prior_verdict.notna().sum())}")
print(d.verdict_landed[d.verdict_landed.ne("")].value_counts().to_string())
print(f"\nrows on the to_review sheet            : {len(todo)}")
print(todo.needs_review.value_counts().to_string())

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
