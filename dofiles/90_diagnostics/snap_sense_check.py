r"""Every weight the anchor snap moved, laid out for a human to eyeball.

Issue #18 A1 replaced a fixed-factor magnitude rule with a snap toward each row's own
item x unit cell anchor. That changes published weights, so this writes the changed
rows out with enough context to judge them one by one -- what was typed, what each rule
says, what the rest of the cell says, and whether the row reaches the deliverable.

Sheets, in the order worth reading:

  to_review        OPEN THIS FIRST. Only the rows still needing a decision, worst
                   first, each with a `proposed_value' and the rule behind it. Fill in
                   `Corrected Value' where you disagree; the next run reads it back.
  disagreements    every row where the anchor and the block reading differ, sorted by
                   how far the published value sits from its cell median.
  gate_overrules   rows where the anchor was REJECTED as implausible and the block
                   reading published instead. These are the contaminated cells.
  reference_set_now  the published deliverable as it currently stands.
  all_weighings    EVERY weighing, sorted so a cell reads as one block, showing the
                   value that actually ships (`final_says') and what moved it
                   (`adjusted_by'). This is the sheet for an overall review.

A REVIEW ROUND SURVIVES A REGENERATION. Verdicts are read back from the newest
reference/reviewed/snap_sense_check_REVIEWED_*.xlsx and matched on CONTENT -- cell,
hetero_group, raw weight -- because ids in older workbooks predate the durable id
registry. `verdict_landed' says whether each one actually reached the published value,
and a verdict matching no current row raises a warning rather than disappearing.

Your annotated copy is archived into reference/reviewed/ AUTOMATICALLY before this
regenerates, so a review pass cannot be lost by re-running. No manual copy needed.

Run from the project root:  python dofiles/90_diagnostics/snap_sense_check.py
"""
import datetime as dt
import io, re, shutil, sys
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

# the value that actually ships: 04's answer unless 05 overrode it. Defined HERE,
# before the triage below, because the triage must judge what ships rather than
# what 04 proposed -- otherwise every row the review already settled comes back.
d["final_says"] = d.final_weight.where(d.final_weight.notna(), d.published)

# THE BLOCK READING IS READ, NOT RECOMPUTED. 04_unit_snap.do keeps `w_block', so this
# is now the same single definition the pipeline published -- as `anchor_says' already
# was via w_step1.
#
# It used to be re-derived here from weight, unit and a scraped KGMAX. The EXPECTED
# guard above catches a moved CONSTANT but not a moved BRANCH: changing STEP 3a's
# `weight>=10' would have left this file proposing values from a rule the pipeline no
# longer used, and this file builds the workbook whose verdicts are frozen into the
# ledger. A stale block reading here becomes a permanent hand-adjudicated weight.
if "w_block" not in d.columns:
    sys.exit("the build has no w_block column -- rebuild with a 04_unit_snap.do that "
             "keeps it, rather than reintroducing a second copy of the block rule here")
d["block_says"] = d.w_block.round()

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


# ---- never overwrite a review pass ---------------------------------------------
# This script regenerates OUT in place. If a reviewer has annotated that workbook and
# not copied it anywhere, re-running destroys the pass -- and asking a human to
# remember a manual copy before every run is a bad safeguard, because the one time
# they forget is the time it matters.
#
# So the copy happens HERE, automatically, before anything is written: an annotated
# live workbook is filed into reference/reviewed/ under its own last-modified date.
# The carry-forward below then picks it up as the newest reviewed file, which is why
# this must run first.
REVIEWED_DIR.mkdir(parents=True, exist_ok=True)


def _annotations(frame):
    """Rows carrying a REAL verdict.

    `Corrected Value' is written out as an empty string, not a null, so a bare
    .notna() is True on every row and would report a freshly generated workbook as
    fully annotated. That is not hypothetical -- it fired on the first run and
    archived an un-annotated file over the top of a real review pass.
    """
    if "Corrected Value" not in frame.columns:
        return frame.iloc[0:0]
    v = frame["Corrected Value"]
    return frame[v.notna() & v.astype(str).str.strip().ne("")]


if OUT.exists():
    try:
        _x = pd.ExcelFile(OUT)
        _n_notes = sum(len(_annotations(_x.parse(_s))) for _s in _x.sheet_names)
    except Exception as _e:                     # unreadable or mid-save: assume yes
        print(f"could not scan {OUT.name} for annotations ({_e}); archiving anyway")
        _n_notes = -1
    if _n_notes != 0:
        # Timestamped to the MINUTE, not the day. Two passes on one day are two
        # passes, and a date-only name made the second collide with the first --
        # which the first attempt "resolved" by writing a _2 file that then sorted
        # last and shadowed the fuller review.
        _stamp = dt.datetime.fromtimestamp(OUT.stat().st_mtime).strftime("%Y-%m-%d_%H%M")
        _dest = REVIEWED_DIR / f"snap_sense_check_REVIEWED_{_stamp}.xlsx"
        if not _dest.exists():
            shutil.copy2(OUT, _dest)
            print(f"archived {_n_notes} annotation(s) to {_dest.name} before regenerating")
    else:
        print("no annotations in the current workbook -- nothing to archive")

# EVERY reviewed workbook, oldest first, so a later verdict overrides an earlier one
# on the same row and nothing is lost. Reading only the newest file was wrong: a review
# pass that covers 4 rows would have shadowed the pass before it that covered 34.
#
# Sheets: all of them. Reading only the three that existed in round one silently lost
# every round-two verdict, which is the exact failure this carry-forward exists to
# prevent, reintroduced by an out-of-date list.
def _norm_verdict(v):
    """Canonical form of a Corrected Value, for COMPARING entries only.

    Excel gives back a different dtype per sheet depending on what else is in the
    column -- disagreements read 3670 as float64, gate_overrules read "7000 mL (7 L)"
    as object, a later to_review read the same number as int64. 3670, 3670.0 and
    "3670" must compare equal or every one of those dtype seams reads as a fabricated
    conflict. Free text (a real verdict, e.g. "drop it") is compared as its stripped
    string since it has no numeric form.
    """
    s = str(v).strip()
    try:
        return f"{float(s):.6g}"
    except ValueError:
        return s


prior = {}
_src = sorted(REVIEWED_DIR.glob("snap_sense_check_REVIEWED_*.xlsx"))
if _src:
    _per_file = []
    for _f in _src:
        _n_f = 0
        # Collected for this ONE file before anything folds into `prior`, so a
        # same-round conflict can be checked on the raw annotations -- see below.
        _file_rows = []           # (key, value, sheet)
        try:
            _sheets = pd.ExcelFile(_f).sheet_names
        except Exception as _e:
            print(f"  could not open {_f.name} ({_e}) -- skipped")
            continue
        for _sheet in _sheets:
            try:
                _r = _annotations(pd.read_excel(_f, sheet_name=_sheet))
            except Exception:
                continue
            # `reference_set_now' is case-level and carries none of the key columns.
            # Reading every sheet is right; assuming every sheet has the key is not.
            if not {"cell", "hetero_group", "weight",
                    "Corrected Value"} <= set(_r.columns):
                continue
            for _k, _v in zip(_vkey(_r), _r["Corrected Value"]):
                _file_rows.append((_k, _v, _sheet))

        # A SAME-ROUND CONFLICT: one content key given two DIFFERENT Corrected Value
        # entries inside this one workbook -- whether typed twice on one sheet (a
        # fill-down smear) or once each on two sheets that both surfaced the same row
        # (e.g. disagreements and gate_overrules can overlap). This has to be caught
        # HERE, on every row this file contributed, before the `prior[_k] = _v` fold
        # below -- that fold keeps whichever write it sees last and would hide exactly
        # this, which is the gap #18's round-3 review turned up nobody had checked.
        #
        # A later FILE giving a key a different value than an earlier file is NOT this
        # bug -- it is a reviewer revising a past decision, and folding forward with
        # "later file wins" is what makes that possible. Only compare WITHIN one file.
        if _file_rows:
            _fdf = pd.DataFrame(_file_rows, columns=["key", "value", "sheet"])
            _fdf["_norm"] = _fdf.value.map(_norm_verdict)
            _nun = _fdf.groupby("key")._norm.nunique()
            _bad = _nun[_nun > 1]
            if len(_bad):
                _lines = [f"{_f.name}: {len(_bad)} content key(s) received "
                          "conflicting Corrected Value entries within this one "
                          "review round (not across files -- that part is fine):"]
                for _k in _bad.index:
                    _sub = _fdf[_fdf.key == _k]
                    _pairs = ", ".join(f"{_row.value!r} ({_row.sheet})"
                                        for _row in _sub.itertuples())
                    _lines.append(f"  {_k}\n    {_pairs}")
                raise SystemExit(
                    "\n".join(_lines) + "\n"
                    "Reconcile these in the workbook by hand before re-running --"
                    " otherwise whichever entry happens to be read last is applied"
                    " silently, and the conflict-check downstream never sees it"
                    " because it runs on the deduplicated ledger.")

        for _k, _v, _sheet in _file_rows:
            prior[_k] = _v          # later FILE wins -- an intentional revision
            _n_f += 1
        _per_file.append(f"{_f.name}: {_n_f}")
    print(f"carried {len(prior)} prior verdict(s) forward from {len(_src)} file(s)")
    for _line in _per_file:
        print(f"  {_line}")
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

# ---- write the ledger that 05_manual_corrections.do applies --------------------
# The verdicts are collected here, so the ledger is written here. Building it by hand
# once was fine for 80 rows; doing that every round is how a review pass and the build
# drift apart.
#
# REWRITTEN IN FULL, not appended. Every verdict is derived from the reviewed archive,
# so a full rewrite is idempotent -- re-running reproduces the same file -- while an
# append duplicates on every run. The archive is the source of truth; the ledger is a
# projection of it.
#
# THE THIRD CASE. A verdict equal to neither candidate cannot be applied as given and
# is resolved to the BLOCK reading -- the raw weight read as canonical units, with its
# decimals honoured and the kg/g/mL tick not taken literally. That is the standing
# instruction for rows the rules do not settle, and it is what every neighbouring row
# in the same review round chose.
#
# It is also what a spreadsheet fill-down produces. Round 3 carried six entries all
# reading 650 across sheet rows 83-89, where row 86 (raw 0.650) legitimately IS 650 and
# the value had been smeared over its neighbours -- whose raw weights were 0.645, 0.450,
# 0.500, 0.600, 0.500 and 395. Resolving to the block reading recovers exactly those.
# Recorded in `chose' so the substitution is visible rather than silent.
LEDGER = Path("reference/reviewed/snap_verdicts.csv")

_led = d[d.prior_verdict.notna()].copy()
_led["verdict_raw"] = pd.to_numeric(_led.prior_verdict, errors="coerce")
_ok_b = _led.verdict_raw.round(1).eq(_led.block_says.round(1))
_ok_a = _led.verdict_raw.round(1).eq(_led.anchor_says.round(1))
_led["chose"] = np.where(_ok_b, "block", np.where(_ok_a, "anchor", ""))
_sub = _led.chose.eq("") & _led.block_says.notna()
_led.loc[_sub, "chose"] = ("raw-weight default (entry was "
                           + _led.loc[_sub, "verdict_raw"].map(lambda v: f"{v:g}") + ")")
_led["verdict"] = np.where(_sub, _led.block_says, _led.verdict_raw)

# A row set unusable by hand is settled by 05 sec 4 and must not be re-asserted here.
_led = _led[~(_led.final_differs & _led.final_weight.isna())]

_parts = _led.cell.str.split(" / ", n=3, expand=True)
_out = pd.DataFrame({
    "province": _parts[0], "municipality": _parts[1],
    "item": _parts[2], "harmonized_nsu_unit": _parts[3],
    "hetero_group": _led.hetero_group, "raw_unit": _led.unit.astype("Int64"),
    "raw_weight": _led.weight, "verdict": _led.verdict, "chose": _led.chose,
    "block_says": _led.block_says, "anchor_says": _led.anchor_says,
    "id_at_review": _led.id.astype("Int64")})

# One content key may carry several rows -- a cell can hold two identical readings from
# different vendors -- but it may NOT carry two answers. 05 asserts the same thing.
_ck = ["province", "municipality", "item", "harmonized_nsu_unit",
       "hetero_group", "raw_weight"]
_conf = _out.groupby(_ck).verdict.nunique()
if (_conf > 1).any():
    raise SystemExit(
        f"{int((_conf > 1).sum())} content key(s) carry conflicting verdicts across "
        "review rounds. Reconcile the reviewed workbooks before writing the ledger:\n"
        + _conf[_conf > 1].to_string())

_out.sort_values(_ck).to_csv(LEDGER, index=False, encoding="utf-8")
print(f"\nwrote {LEDGER}: {len(_out)} verdict(s) on {_conf.size} content key(s)")
print(_out.chose.str.replace(r"raw-weight default.*", "raw-weight default",
                             regex=True).value_counts().to_string())


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
    if abs(got - want) < 0.5:
        return "yes"
    # An entry matching NEITHER candidate is resolved to the block reading when the
    # ledger is written, and that substitution is deliberate. Compare against what was
    # APPLIED, or the six fill-down rows report as unapplied forever while the build
    # already holds the right number.
    _cand = [row.block_says, row.anchor_says]
    if all(pd.isna(c) or abs(c - want) >= 0.5 for c in _cand) \
            and pd.notna(row.block_says) and abs(got - row.block_says) < 0.5:
        return "yes (raw-weight default applied)"
    return "NO -- still " + f"{got:g}"


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
# Against the value that SHIPS, not 04's answer. `published' is pre-05, so a row the
# review already adjudicated to the block reading still looks anchor-published there
# and would be handed back for review a second time. final_says is post-05.
_anchor_won = d.final_says.round(6).eq(d.anchor_says.round(6))
_prov = d.snap_referee.astype(str).str.startswith("prov")
_disagree = d.anchor_says.round(6).ne(d.block_says.round(6))

# ROUND 2 SETTLED THE OTHER HALF OF THIS. Every row where a province pool published
# the anchor while the block reading sat closer to the row's OWN cell was reviewed,
# and all 34 were adjudicated to the block. That is now STEP 3e-ii-b in
# 04_unit_snap.do, so those rows no longer reach this flag.
#
# What is left is the mirror image: a province pool published the anchor and the row's
# own cell AGREES with it. The local evidence does not contradict the province here,
# so the round-2 argument does not reach these -- but they were never looked at, and
# they are the largest remaining block of anchor-published rows. Round 3.
d["needs_review"] = ""
d.loc[_anchor_won & _prov & _disagree, "needs_review"] = \
    "province refereed, anchor published -- own cell does not contradict it"

# A ROW THE REVIEW HAS ALREADY SETTLED MUST NOT COME BACK. Switching the triage to
# `final_says' stopped that for verdicts adopting the BLOCK reading, but not for
# verdicts adopting the ANCHOR: there `final_says == anchor_says` is exactly what the
# flag tests, so the condition stays true however many times a human confirms it. All
# 15 anchor verdicts from round 2 were handed back in round 3 for that reason.
#
# The flag cannot distinguish "the anchor won because the algorithm chose it" from
# "because the reviewer chose it" -- so the verdict, not the flag, decides.
d.loc[d.verdict_landed.astype(str).str.strip().eq("yes"), "needs_review"] = ""

d.loc[d.verdict_landed.astype(str).str.startswith("NO"), "needs_review"] = \
    "PRIOR VERDICT NOT APPLIED"

# The shape of the raw number is the evidence the round-1 rules turn on ("a whole
# number should follow block_says"; "a shared 0.xxx structure is the market's
# convention"). Surfaced as a column so a reviewer can sort on it rather than reading
# it off `weight' one row at a time.
d["raw_shape"] = np.where(d.weight.isna(), "",
    np.where(d.weight < 1, "sub-1 decimal (0.xxx)",
             np.where(d.weight.eq(d.weight.round()), "whole number", "decimal")))

# ---- a proposed verdict, so the reviewer edits rather than starts blank ---------
# This applies the reviewer's OWN round-1 rules to the rows still outstanding. Those
# rules exist in 04_unit_snap.do as 3e-iii and 3e-iv, but only as FALLBACKS: they are
# guarded by `if missing(_pick_block)', so they never fire on a row that rule 1 has
# already decided. On these rows rule 1 always decides, using a province pool.
#
# The proposal is therefore: where the ONLY referee available is a province pool, let
# the shape of the raw number outrank it. A whole number typed as-is, or a sub-1
# decimal repeated within the cell, is evidence about THIS reading; a province median
# is evidence about other municipalities.
#
# NOT IMPLEMENTED, and deliberately so -- it would flip published weights on rows
# nobody has looked at. It is a column in a workbook, for a human to agree with or not.
_sub1_in_cell = (d.weight.lt(1) & d.weight.notna()).groupby(d.cell).transform("sum")

d["proposed_value"] = np.nan
d["proposed_why"] = ""

# Every row still needing a decision gets a proposal -- including the ones flagged
# PRIOR VERDICT NOT APPLIED, which previously got none. A row showing an unapplied
# verdict and no proposal reads as emptier than it is; the reviewer has to reconstruct
# what the candidates were.
_out = d.needs_review.ne("")

# A row carrying a LANDED verdict is not proposed against. The proposal machinery does
# not consult prior_verdict, so on a settled row it can contradict a decision already
# made -- it did, on 3 of the 15 anchor verdicts, proposing 350 g for an ice-cream
# small cup the reviewer had put at 35 g.
_settled = d.verdict_landed.astype(str).str.strip().eq("yes")
_out = _out & ~_settled

_whole = _out & d.raw_shape.eq("whole number")
d.loc[_whole, "proposed_value"] = d.loc[_whole, "block_says"]
d.loc[_whole, "proposed_why"] = "round-1: a whole number was typed as-is"

_dec = _out & d.raw_shape.eq("sub-1 decimal (0.xxx)") & _sub1_in_cell.ge(2)
d.loc[_dec, "proposed_value"] = d.loc[_dec, "block_says"]
d.loc[_dec, "proposed_why"] = "round-1: 0.xxx repeated in this cell, a convention"

_keep = _out & d.proposed_value.isna()
d.loc[_keep, "proposed_value"] = d.loc[_keep, "published"]
d.loc[_keep, "proposed_why"] = "no round-1 rule reaches it -- province referee stands"

# THE PLAUSIBILITY GATE APPLIES TO A PROPOSAL TOO, and leaving it off was a real bug
# rather than a tidiness point. The "0.xxx repeated in the cell is a convention"
# argument assumes multiplying by 1,000 lands somewhere sensible. It does for 0.275 ->
# 275 g. It does NOT for 0.001175, which is a six-decade slip, not a three-decade
# convention: the block reading there is 1 g.
#
# Ten of the 185 proposals were outside [WFLOOR, WCEIL], and one of them was ILOILO /
# BADIANGAN chicken `whole (chicken)' -- the ONE GRAM WHOLE CHICKEN that was the
# headline defect on issue #31. A proposal that reinstates a fixed bug is worse than
# no proposal, because it arrives carrying a rule's authority.
#
# 04_unit_snap.do already applies these bounds last (3e-vi), so the pipeline would
# have rejected these anyway. The failure was showing a reviewer a number the pipeline
# would never publish.
_prop_bad = _out & d.proposed_value.notna() & (
    d.proposed_value.lt(WFLOOR) | d.proposed_value.gt(WCEIL))
_alt_ok = d.published.between(WFLOOR, WCEIL)
_revert = _prop_bad & _alt_ok
# Guarded: an empty slice makes the string concat below fail on dtype rather than
# no-op, and the slice IS empty once every implausible row has been settled by review.
if int(_revert.sum()):
    d.loc[_revert, "proposed_value"] = d.loc[_revert, "published"]
    d.loc[_revert, "proposed_why"] = (
        "round-1 rule REJECTED: block reading is implausible ("
        + d.loc[_revert, "block_says"].map(lambda v: f"{v:g}")
        + f" outside [{WFLOOR}, {WCEIL}]) -- keeping the anchor")
    print(f"\n{int(_revert.sum())} proposal(s) reverted by the plausibility gate")

# Blank column for the reviewer to fill in. Pre-created so annotation happens in
# place and the next run can read it back through the same content key.
d["Corrected Value"] = ""

RCOLS = (COLS[:COLS.index("final_weight")]
         + ["final_says", "adjusted_by", "raw_shape"]
         + COLS[COLS.index("final_weight"):COLS.index("review_step1")]
         + ["prior_verdict", "verdict_landed", "needs_review",
            "proposed_value", "proposed_why", "Corrected Value"]
         + COLS[COLS.index("review_step1"):])

# ---- the value that actually ships, and what moved it -------------------------
# `published' is 04's answer. 05_manual_corrections.do then overrides some rows by
# hand and sets others unusable, so a review that reads `published' is reviewing an
# intermediate. These two columns put the FINAL value in front of the reviewer and
# say what moved it, so an adjustment is visible rather than implied.
d["adjusted_by"] = np.where(
    d.final_differs & d.final_weight.isna(), "05 -- set unusable",
    np.where(d.final_differs, "05 -- hand correction",
             np.where(d.published.round(1) != d.base.round(1), "04 -- snap", "")))

dis = d[(d.anchor_says != d.block_says) & d.published.notna()]
dis = dis.sort_values("x_from_median", ascending=False)
gate = d[d.anchor_implausible]

ref_new = pd.read_stata(T/"nsu_reference_set.dta", convert_categoricals=False)

# ---- EVERY weighing, at its FINAL value ---------------------------------------
# This sheet used to be `cell_context' and held only the cells a disagreement had
# touched -- 3,450 of 11,335 rows. That made an overall review impossible: a cell
# where both rules agreed, or where a hand correction had already settled it, was
# simply not in the workbook to be looked at.
#
# It now holds the whole file, sorted so a cell reads as one block.
allw = d.sort_values(["cell", "hetero_group", "weight"])

# The sheet to open first: only the rows a human still has to decide, worst first.
todo = d[d.needs_review.ne("")].copy()
todo["_order"] = np.where(todo.needs_review.eq("PRIOR VERDICT NOT APPLIED"), 0, 1)
todo = todo.sort_values(["_order", "x_from_median"], ascending=[True, False])

with pd.ExcelWriter(OUT) as w:
    todo[RCOLS].to_excel(w, sheet_name="to_review", index=False)
    dis[RCOLS].to_excel(w, sheet_name="disagreements", index=False)
    gate[RCOLS].to_excel(w, sheet_name="gate_overrules", index=False)
    ref_new.to_excel(w, sheet_name="reference_set_now", index=False)
    allw[RCOLS].to_excel(w, sheet_name="all_weighings", index=False)

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
print(f"cells with a disagreement         : {dis.cell.nunique():,}")
print(f"all_weighings sheet               : {len(allw):,} rows, "
      f"{allw.cell.nunique():,} cells")
print("  (that is every weighing reaching 04_unit_snap, BEFORE 07_cpi_factor drops")
print("   the 98 vendor-priced rows -- the snap runs first, so the review sees them)")
print(allw.adjusted_by.replace("", "not adjusted").value_counts().to_string())
print(f"published rows now                : {len(ref_new):,}")
print(f"\nfurthest from the cell median (check these first):")
top = dis.head(12)[["cell","weight","block_says","anchor_says","published","cell_median"]]
print(top.to_string(index=False))
print(f"\nwrote {OUT}")
