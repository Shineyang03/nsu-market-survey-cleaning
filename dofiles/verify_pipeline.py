r"""Is the pipeline on disk actually the pipeline the code describes?

WHY THIS EXISTS. Every other check in this project verifies a NUMBER. Nothing verified
that the artifacts on disk were still the ones the current code produces -- and that gap
let a real failure sit undetected for six weeks: validate_folds.py (now retired to archive/) read
outputs/temp/nsu_data.dta, the pre-Aug11 build, so it reproduced its own past answers no
matter what changed upstream. It looked like confirmation. Three other files were archived
for hardcoding that same path.

So this asks a different question from verify_documented_claims.py. That one asks "do the
recorded numbers still hold?". This one asks "were these files built from these inputs, by
this code?".

WHAT IT CHECKS, in order, stopping at nothing -- every check runs and the exit code is set
at the end, so one failure does not hide the others:

  1  THE CROSSWALK REPRODUCES. Rebuilds it from its inputs into a scratch directory and
     compares content, column by column, on every row the live file has. This is the check
     that #33 was opened about: master_nsu_rename.csv is in neither master, so it can drift
     from its inputs with nothing noticing.

  2  THE TRIM IS ACCOUNTED FOR. The rebuild is PRE-trim (2,950 rows) and the live file is
     POST-trim (2,927), because 02_drop_non_nsu_labels.py removes labels that are not NSUs
     and refuses to re-run. So the difference must be exactly the rows recorded in
     master_rename_dropped_labels.csv -- no more, no fewer.

  3  THE FOLD EVIDENCE IS CURRENT. Re-runs validate_folds.do so its output describes the
     live weighings, then reads it back: no folded group may contradict its own weight
     test, per the policy in docs/master_rename.md sec 6.

  4  THE DOCUMENTED NUMBERS HOLD. Runs verify_documented_claims.py and reports its verdict
     counts.

  5  THE INPUT MANIFEST. Hashes every hand-maintained input and every headline output, and
     compares against outputs/tables/build_manifest.json. Says which inputs moved since
     the manifest was written, so "these outputs came from these inputs" is answerable
     rather than assumed.

WHY HASHES AND NOT TIMESTAMPS. A git checkout rewrites the mtime of every file it touches,
so a merge or a branch switch makes a stale artifact look fresh and a fresh one look stale.
Timestamps cannot answer this question in a repo. Content can.

WHAT IT DOES NOT DO. It does not re-run the Stata build. That takes minutes and would
overwrite the artifacts it is checking; the point here is to verify what is on disk, not to
replace it. Check 5 is what tells you the Stata outputs match their inputs.

RUN, from the project root:
    python dofiles/verify_pipeline.py
    python dofiles/verify_pipeline.py --update-manifest   # after a deliberate rebuild

Exit code 0 if every check passes, 1 otherwise.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import pandas as pd

DC = Path(__file__).resolve().parent.parent          # ...\Data Cleaning
BOX = DC.parent                                      # ...\14 NSU Market Survey
SCRATCH = DC / "outputs" / "temp" / "_verify_rebuild"
MANIFEST = DC / "outputs" / "tables" / "build_manifest.json"

# Hand-maintained inputs and headline outputs. Inputs are things a human edits or a
# collaborator supplies; outputs are what the project publishes or the next step consumes.
INPUTS = {
    "raw market survey": BOX / "NSU Market Survey Launch" / "data"
                             / "PSPS NSU Market Survey Launch.dta",
    "price file (from the R script)": BOX / "NSU Market Survey Launch" / "data"
                                          / "NSU_prices_from_Makayla.csv",
    "official translation groups": DC / "outputs" / "tables"
                                      / "price_ms_unit_harmonization_crosswalk.xlsx",
    "hand rename": DC / "outputs" / "tables" / "nsu_rename_crosswalk.xlsx",
    "curated field notes": DC / "outputs" / "tables" / "add_comments_crosswalk.xlsx",
    "snap review ledger": DC / "reference" / "reviewed" / "snap_verdicts.csv",
    "durable id registry": DC / "outputs" / "tables" / "weighing_id_registry.csv",
    "price/MS case coverage": DC / "outputs" / "temp" / "cases_in_price_not_in_MS.csv",
    "CPI panel": DC / "outputs" / "tables" / "cpi_level_panel.csv",
}
OUTPUTS = {
    "crosswalk": DC / "outputs" / "tables" / "master_nsu_rename.csv",
    "weighings + cpi_factor": DC / "outputs" / "master_rename_build" / "temp"
                                 / "nsu_weighings_cpi.dta",
    "reference set (Outcome 1)": DC / "outputs" / "master_rename_build" / "temp"
                                    / "nsu_reference_set.dta",
}

XW_KEY = ["province", "pull_municipal_city", "cons_name", "pull_nsu_unit"]

# ---- folds knowingly kept despite failing their own weight test ---------------------
# A check that is permanently red is a check people learn to ignore. These are folds
# where the weight test says DIFFER but the fold stands anyway, as a recorded decision
# rather than an oversight -- so they report as ACK, not FAIL.
#
# THE RECORDED FIGURES ARE PART OF THE ACKNOWLEDGEMENT. If the verdict stops being
# DIFFER, or the size-controlled ratio moves by more than RATIO_TOL, the decision was
# made about different evidence and the check fails again so it can be re-made. An
# acknowledgement is not a mute button.
#
# Keyed on (item substring, label_ref, label_other) as validate_folds.do reports them.
RATIO_TOL = 0.15
#
# EMPTY, AND THAT IS THE RESULT OF FIXING THE TEST RATHER THAN EXCUSING IT.
#
# The one entry here was crackers `bilog' / `pieces or units', a fold that failed its own
# weight test at p=0.043 with a size-controlled ratio of 0.62. It was acknowledged on the
# grounds that 3 strata is thin evidence on which to flip a harmonization.
#
# It was not thin evidence. It was the WRONG evidence. The test read corrected_weight --
# the published weight, which 04_unit_snap.do snaps toward the median of a pool keyed on
# harmonized_nsu_unit. So the fold under test helped produce the number judging it. On the
# block reading, which is a function of the raw weight, the unit tick and KGMAX alone, the
# same comparison gives p=0.220 on an IDENTICAL ratio of 0.62: the fold passes.
# validate_folds.do now defaults to that reading, and Panel A has no DIFFER rows at all.
#
# Keep this dict for the case it was built for -- a fold genuinely kept against its own
# evidence -- but do not put one here to quiet a red check before establishing that the
# test is measuring the right thing. That is what happened last time.
ACKNOWLEDGED = {}

_fail = []
_warn = []


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def ok(msg):
    print(f"  [OK    ] {msg}")


def bad(msg):
    print(f"  [FAIL  ] {msg}")
    _fail.append(msg)


def warn(msg):
    print(f"  [WARN  ] {msg}")
    _warn.append(msg)


def sha(path):
    d = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            d.update(chunk)
    return d.hexdigest()


# Stata 19. The 17 install on this machine has an expired licence and must not be used.
STATA = r"C:\Program Files\StataNow19\StataSE-64.exe"


def run(cmd, what, cwd=None):
    """Run a step, streaming nothing; return (rc, stdout+stderr).

    `cwd' defaults to the project root, which is what the Python steps expect. A Stata
    step needs dofiles/ instead, because every do-file here opens with a relative
    `do "00_shared/00_globals.do"'.
    """
    print(f"  running {what} ...", flush=True)
    p = subprocess.run(cmd, cwd=cwd or DC, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


# ------------------------------------------------------------------ 1 + 2
def check_crosswalk():
    h("1-2  DOES THE CROSSWALK REPRODUCE FROM ITS INPUTS?")
    live_p = OUTPUTS["crosswalk"]
    if not live_p.exists():
        bad(f"{live_p.name} is absent")
        return
    rc, out = run([sys.executable, "dofiles/00_shared/01_build_crosswalk.py",
                   "--outdir", str(SCRATCH)], "01_build_crosswalk.py --outdir")
    if rc != 0:
        bad("01_build_crosswalk.py failed; last lines:\n" + "\n".join(out.splitlines()[-8:]))
        return
    new_p = SCRATCH / "tables" / "master_nsu_rename.csv"
    if not new_p.exists():
        bad("the rebuild wrote no crosswalk")
        return

    live = pd.read_csv(live_p, encoding="utf-8-sig", dtype=str)
    new = pd.read_csv(new_p, encoding="utf-8-sig", dtype=str)
    print(f"    live {len(live):,} rows (post-trim)   rebuild {len(new):,} rows (pre-trim)")

    # every live row must exist in the rebuild
    live_k = set(map(tuple, live[XW_KEY].values))
    new_k = set(map(tuple, new[XW_KEY].values))
    missing = live_k - new_k
    if missing:
        bad(f"{len(missing)} live crosswalk row(s) the rebuild does not produce; "
            f"e.g. {sorted(missing)[:2]}")
    else:
        ok(f"all {len(live_k):,} live rows are reproduced by the rebuild")

    # ...and agree on every shared column
    cols = [c for c in live.columns if c in new.columns and c not in XW_KEY]
    m = live.merge(new, on=XW_KEY, how="inner", suffixes=("_live", "_new"))
    diffs = {c: int((m[c + "_live"].fillna("~") != m[c + "_new"].fillna("~")).sum())
             for c in cols}
    badcols = {c: n for c, n in diffs.items() if n}
    if badcols:
        bad("the rebuild disagrees with the live crosswalk on: "
            + ", ".join(f"{c} ({n} rows)" for c, n in badcols.items()))
    else:
        ok(f"all {len(cols)} shared columns agree on all {len(m):,} rows "
           "(harmonized_nsu_unit included)")

    # check 2: the pre/post-trim gap must be exactly the recorded drops
    dropped_p = DC / "outputs" / "tables" / "master_rename_dropped_labels.csv"
    extra = new_k - live_k
    if not dropped_p.exists():
        warn(f"{dropped_p.name} absent; cannot account for the {len(extra)} trimmed rows")
        return
    dr = pd.read_csv(dropped_p, encoding="utf-8-sig", dtype=str)
    dr_k = set(map(tuple, dr[XW_KEY].values))
    if extra == dr_k:
        ok(f"the {len(extra)} pre/post-trim rows are exactly those recorded in "
           f"{dropped_p.name}")
    else:
        bad(f"trim mismatch: rebuild-minus-live is {len(extra)} rows, "
            f"{dropped_p.name} records {len(dr_k)}; "
            f"unaccounted {len(extra - dr_k)}, over-recorded {len(dr_k - extra)}")


# ------------------------------------------------------------------ 3
def check_folds():
    h("3  IS THE FOLD EVIDENCE CURRENT?")
    # STATA, not Python. validate_folds.do is the live implementation; the .py it was
    # validated against is retired to dofiles/archive/. It reproduced the Python exactly
    # -- both panels, verdicts and ratios and medians bit-identical, p-values within
    # 6.7e-13 relative, which is Mata-vs-numpy summation order and nowhere near a verdict
    # boundary.
    #
    # TWO THINGS DIFFER FROM RUNNING A PYTHON STEP, and both are traps.
    #
    # It must run from dofiles/, because the do-file opens with
    # `do "00_shared/00_globals.do"' -- a relative path, the convention every step here
    # follows so a single step can be run on its own.
    #
    # AND `stata -e' RETURNS 0 EVEN WHEN THE DO-FILE ERRORS. It logs the failure and
    # carries on to the next command. So the exit code proves nothing and the log has to
    # be read for `r(NNN);'. Trusting rc here would have let a broken fold test report
    # OK, which is the exact failure mode check 3 exists to prevent.
    log = DC / "dofiles" / "validate_folds.log"
    log.unlink(missing_ok=True)
    rc, out = run([STATA, "-e", "do", r"90_diagnostics\validate_folds.do"],
                  "validate_folds.do", cwd=DC / "dofiles")
    if not log.exists():
        bad(f"validate_folds.do produced no log at {log}; Stata may not have started")
        return
    text = log.read_text(encoding="utf-8", errors="replace")
    errs = re.findall(r"^r\(\d+\);", text, re.M)
    if errs:
        tail = [ln for ln in text.splitlines() if ln.strip()][-8:]
        bad(f"validate_folds.do hit {len(errs)} Stata error(s) "
            f"({', '.join(sorted(set(errs)))}); last lines:\n" + "\n".join(tail))
        return
    out = text
    for line in out.splitlines():
        if line.startswith("raw size-weighings"):
            print(f"    {line}")
    A = DC / "outputs" / "temp" / "fold_validation_A.csv"
    if not A.exists():
        bad("validate_folds.do wrote no fold_validation_A.csv")
        return
    a = pd.read_csv(A)
    susp = a[a.verdict.eq("DIFFER")
             & ((a.size_ctrl_ratio > 1.25) | (a.size_ctrl_ratio < 0.80))]
    if not len(susp):
        ok(f"no folded group contradicts its weight test ({len(a)} pairs tested)")
    else:
        print("    docs/master_rename.md sec 6: a group is kept folded only where the")
        print("    test CONFIRMS the members weigh the same. These contradict that.")
    for r in susp.itertuples():
        key = next((k for k in ACKNOWLEDGED
                    if k[0] in r.item and k[1] == r.label_ref and k[2] == r.label_other),
                   None)
        desc = (f"{r.item[:34]} {r.label_ref}/{r.label_other} "
                f"p={r.p:.3g} ratio={r.size_ctrl_ratio} n_strata={r.n_strata}")
        if key is None:
            bad(f"FOLDED BUT DIFFERS: {desc}")
            continue
        rec = ACKNOWLEDGED[key]
        drift = abs(r.size_ctrl_ratio - rec["ratio"])
        if drift > RATIO_TOL:
            bad(f"ACKNOWLEDGED FOLD HAS MOVED: {desc} -- recorded ratio "
                f"{rec['ratio']}, now {r.size_ctrl_ratio} (drift {drift:.2f} > "
                f"{RATIO_TOL}). The decision was made about different evidence; "
                "re-make it and update ACKNOWLEDGED.")
        else:
            print(f"  [ACK   ] {desc}")
            print(f"            accepted: {rec['why']}")

    # An acknowledgement for a fold that no longer fails is stale bookkeeping: it would
    # silently excuse a future regression on that pair.
    still = {(k[0], k[1], k[2]) for k in ACKNOWLEDGED
             if any(k[0] in r.item and k[1] == r.label_ref and k[2] == r.label_other
                    for r in susp.itertuples())}
    for k in ACKNOWLEDGED:
        if k not in still:
            warn(f"ACKNOWLEDGED entry {k} no longer fails its test -- remove it, or it "
                 "will excuse a future regression on that pair")


# ------------------------------------------------------------------ 4
def check_claims():
    h("4  DO THE DOCUMENTED NUMBERS STILL HOLD?")
    rc, out = run([sys.executable, "dofiles/90_diagnostics/verify_documented_claims.py"],
                  "verify_documented_claims.py")
    # rc == 1 is its DESIGNED exit for "a claim moved" -- not a crash. Distinguish the
    # two, or a moved number is reported as a broken script and the actual claim is lost
    # in a stack-trace tail.
    lines = out.splitlines()
    counts = [l.strip() for l in lines
              if l.strip().startswith(("OK", "CHANGED", "SKIPPED"))
              and len(l.strip().split()) == 2]
    if not counts:
        bad("verify_documented_claims.py did not report verdict counts, so it crashed"
            " rather than finding a moved number; last lines:\n"
            + "\n".join(lines[-8:]))
        return
    for c in counts:
        print(f"    {c}")
    if any(c.split()[0] == "CHANGED" and int(c.split()[1]) for c in counts):
        # name them, so the failure is actionable without re-running the other script
        bad("claim(s) moved -- reconcile the doc or fix the code, never the constant. "
            "Run 90_diagnostics/verify_documented_claims.py for the detail.")
    else:
        ok(f"every documented number re-derives ({counts[0].split()[1]} checks)")


# ------------------------------------------------------------------ 5
def check_manifest(update):
    h("5  WERE THESE OUTPUTS BUILT FROM THESE INPUTS?")
    cur = {"inputs": {}, "outputs": {}}
    for kind, group in (("inputs", INPUTS), ("outputs", OUTPUTS)):
        for name, p in group.items():
            if not p.exists():
                bad(f"{kind[:-1]} missing: {name} -> {p}")
                continue
            cur[kind][name] = {"sha256": sha(p), "bytes": p.stat().st_size}

    if update:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(json.dumps(cur, indent=2, sort_keys=True), encoding="utf-8")
        ok(f"manifest written: {MANIFEST.relative_to(DC)} "
           f"({len(cur['inputs'])} inputs, {len(cur['outputs'])} outputs)")
        return

    if not MANIFEST.exists():
        warn(f"no manifest at {MANIFEST.relative_to(DC)}. Run with --update-manifest "
             "after a deliberate rebuild to record what the outputs were built from.")
        return

    old = json.loads(MANIFEST.read_text(encoding="utf-8"))
    for kind in ("inputs", "outputs"):
        moved = [n for n, v in cur[kind].items()
                 if n in old.get(kind, {}) and old[kind][n]["sha256"] != v["sha256"]]
        added = [n for n in cur[kind] if n not in old.get(kind, {})]
        gone = [n for n in old.get(kind, {}) if n not in cur[kind]]
        # A MOVED OUTPUT IS A FAILURE, not a warning, and the first version of this had
        # it backwards. The case that matters is a variant build or a stray run having
        # replaced a published artifact -- exactly what a measurement experiment does if
        # it writes to the live subtree. Downgrading that to a warning means the one
        # scenario this check exists for scrolls past in yellow.
        #
        # A deliberate rebuild is accepted by re-recording: --update-manifest. That
        # makes accepting a change an explicit act rather than the default.
        if moved:
            bad(f"{kind} changed since the manifest: {', '.join(moved)}"
                + (" -- the outputs may no longer follow from them"
                   if kind == "inputs" else
                   " -- a published artifact was overwritten. If the rebuild was"
                   " deliberate, re-record with --update-manifest"))
        if added:
            warn(f"{kind} not in the manifest: {', '.join(added)}")
        if gone:
            bad(f"{kind} in the manifest but now absent: {', '.join(gone)}")
        if not (moved or added or gone):
            ok(f"all {len(cur[kind])} {kind} match the manifest")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--update-manifest", action="store_true",
                    help="record the current input/output hashes as the reference")
    args = ap.parse_args()

    print("verify_pipeline: is the pipeline on disk the one the code describes?")
    print(f"  project root: {DC}")

    check_crosswalk()
    check_folds()
    check_claims()
    check_manifest(args.update_manifest)

    h("VERDICT")
    if _warn:
        print(f"  {len(_warn)} warning(s):")
        for w in _warn:
            print(f"    - {w}")
    if _fail:
        print(f"  {len(_fail)} FAILURE(S):")
        for f in _fail:
            print(f"    - {f}")
        print("\n  The pipeline on disk does NOT match what the code describes.")
        return 1
    print("  every check passed: the artifacts on disk follow from their inputs,")
    print("  the crosswalk reproduces, and no documented number has moved.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
