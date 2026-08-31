# Session handoff — NSU Market Survey → PSPS gram conversion

Paste this whole file as your first message in the new session.

---

## What the project is

Philippine market survey (MS) weighings of non-standard units (NSUs) — a *putos*, a
*bilog*, a *tumpok* — turned into grams. Two deliverables:

- **Outcome 1, the reference set.** Grams by size (small/medium/large, or one weight
  for conventional units) per province × municipality × item × harmonized NSU unit.
  **Built and live.** 3,321 rows.
- **Outcome 2, PSPS retro-fitting.** Conversion factors mapping PSPS household
  quantities to grams, via price points. **Skeleton only** — see `master_outcome2.do`
  and issue #7.

Repo: `Shineyang03/nsu-market-survey-cleaning` (user's own repo).
Working dir: `C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning`
Branch: `fix/snap-kg-band-and-price-drops`. HEAD: `c93186e`. Working tree clean apart
from an untracked `WB_2025_PH_Food_Prices.csv` that is not mine and should be left alone.

## Read these first

1. `dofiles/README.md` — pipeline layout, how to run it, the conventions.
2. `dofiles/archive/README.md` — what is dead and why.
3. `docs/conversion_factor_methodology.md` — the method.
4. GitHub issues. **The issues are the source of truth for open decisions**, not this
   file. Every non-trivial finding this session went onto one.

## How to run it

From the `dofiles/` folder — the working directory matters, each step reaches
`00_shared/00_globals.do` by a relative path:

```
"C:\Program Files\StataNow19\StataSE-64.exe" -e do master_outcome1.do
```

Stata 19 only; the Stata 17 install has an expired licence. Always a fresh batch
process — never touch the user's interactive sessions, and never kill Stata by image
name (their own session is usually running).

After ANY change, from the project root:

```
python dofiles/90_diagnostics/verify_documented_claims.py
```

23 checks; it re-derives every number in `docs/` that no build file produces and fails
when one moves. It has caught three wrong figures already. Treat a CHANGED verdict as
"reconcile", never as "update the constant".

And, to prove a change moved no answer:

```
python dofiles/90_diagnostics/verify_reproducibility.py --snapshot   # before
python dofiles/90_diagnostics/verify_reproducibility.py             # after
```

It compares `.dta`/`.xlsx`/`.csv` outputs on **values**, not bytes — those formats embed
a creation timestamp, so byte comparison always reports a difference. Clear `tables/` as
well as `temp/` before a rebuild: a stale output that nothing overwrites compares SAME
and reads as reproduced. `--reference` byte-compares the frozen crosswalk set in
`reference/` (plain CSV, no timestamp) — see `reference/README.md`.

**The Stata chain is verified reproducible** as of `c93186e`: cleared `temp/*.dta` and
`tables/*.xlsx`, rebuilt from raw, all 24 live outputs matched value-for-value.

## Ground rules for this codebase

**Be conservative. Everything must be rollback-able.**

- One logical change per commit, with a message saying *why*, not just what.
- Never rewrite history, never force-push, never commit half-finished work.
- Before editing a working file, know how to undo it (`git diff`, and the file is
  committed).
- Do NOT restructure, rename, or "tidy" anything that was not asked for. The layout
  was just settled (#7) and churning it again destroys the diff.
- Verify by running, not by reasoning. Several claims this session were confidently
  wrong until measured.
- Ask before anything hard to reverse.

**Two conventions that exist because the pipeline was bitten without them:**

1. **A correction that can match nothing must assert its row count.** One hand-made
   fix tested the wrong size code, matched zero rows, logged `(0 real changes made)`,
   and shipped a 1 gram whole chicken into the published reference set.
   `00_shared/05_manual_corrections.do` is the pattern.
2. **A hardcoded count must carry its derivation.** A bare `assert n == 11458` invites
   whoever hits it to bump the number rather than reconcile.

**Stata gotchas that have already caused defects here:** no nested `preserve` (r621);
`cap` silences failure — verify after; `sort` is not stable, so the seed is pinned in
`00_globals.do` and every step sorts on a unique key before saving (don't remove
either); `putexcel` re-saves the whole workbook per command, which races Box sync —
use `open`/`save`/`close`.

**Box Drive:** the repo lives on a synced drive. Expect occasional locked-file errors;
re-run before diagnosing. Pin folders offline before long Stata runs.

## User's working preferences

- Plain, concise writing. Lead with the bottom line. No preamble.
- **Anything for review goes in a GitHub issue, not chat** — chat scrolls away.
- Non-trivial task → 2–3 bullets up front on difficulty, risks, blockers.
- State the plan and wait; don't chain unrequested changes.
- No throwaway scripts — code that produces a number must live in `dofiles/`.
- Commit and push directly on this repo when a task completes; no permission dance.
- If they push back on a claim, re-measure before conceding or defending.

## Key domain facts

- Three-layer vocabulary: `pull_nsu_unit` (raw) → `cleaned_nsu_unit` (reference only)
  → `harmonized_nsu_unit` (**the pooling key**).
- Case grain: `province × municipality × item × harmonized_nsu_unit × corrected_unit`.
- `weighing_approach`: 1 conventional, 2 price-quantity, 3 size-based. **Preloaded in
  the SurveyCTO case file**, not enumerator-chosen (#28).
- `corrected_unit`: 1 = g, 2 = mL. Raw `unit`: 1 = kg, 2 = g, 3 = litres.
- **Price points were spent.** The mp25/50/75 amounts were printed on the form and
  handed to vendors. They are a field treatment, not a statistic to re-derive.
- Spelling is a vendor-level attribute — 0 of 7,744 vendors ever used two spellings —
  so no weight comparison can adjudicate a fold.
- Normalization: drop non-ASCII, case-fold, trim, collapse whitespace. **Never
  NFKD-decompose** (`DUEÑAS` → `DUEAS`, not `DUENAS`). Authoritative: `nz()`/`ni()`/`ng()`
  in `00_shared/01_build_crosswalk.py`, and `nsu_normalize` in `00_shared/00_globals.do`.
  These two must agree character for character.
- `price_type` values in the price CSV use **spaces** (`"province median"`); the case
  files use underscores. Mixing them silently matches nothing — this has already
  produced one wrong finding.
- Current counts: 11,494 raw MS weighings → 38 non-NSU excluded → 11,453 →
  98 dropped in `07` → 11,355 → Outcome 1 publishes 3,321 rows.

## Issue triage — 19 open

**Blocked on a decision from the user. Do not implement these; scope and present options.**

| # | what needs deciding |
|---|---|
| #21 | Outcome 2 rule is DECIDED (§2). **Outcome 1 (§3) is open** — 861 rows published as "medium" are a municipality/province median relabelled, and 2 VALLADOLID cases collapse a 2.4× spread |
| #27 | Implicit assumptions. User dispositioned each: A1→#28, A4→#21, A8→"change to assert", rest→take as given. **A5 answered and implemented** this session |
| #28 | Is "conventional" a unit property or a cell assignment? Data says cell assignment for 13 of 21 labels. **Its dispersion numbers are contaminated — re-measure after #18 §A1 lands** |
| #30 | Province fallback. **The blocker for Outcome 2** — 1 PSPS observation in 6 needs it, and borrowing weights across municipalities is unsolved (#28 measured 14× variation). Full write-up incl. the combining-step options is on the issue |
| #31 | 778 singleton hetero-groups. The 1 g chicken is fixed; **8 other outliers are not**, and 5 of them are `putos` — possibly a reclassification question (#28), not a value question |
| #22 | Root cause found and posted: a post-merge override manufactures a harmonized unit outside the crosswalk. Three options on the issue, none chosen |

**Waiting on the Outcome 2 build — nothing to do until it exists:** #11, #16, #19
(cap threshold `t` unset), #20, #23, #25.

**Actionable now:**

| # | what |
|---|---|
| #18 | **The consolidated code-defect issue** (#9 and #32 folded in). Start here for code work. §A is down to 6 rows; a **Cleared** table records how each of 13 resolved items was resolved. §A1 is the blocking decision above. Line numbers were refreshed at `c93186e` — several had drifted 20–40 lines. |
| #33 | `01_build_crosswalk.py` is runnable again and the split is proved answer-preserving. Open remainder: `cases_in_price_not_in_MS.csv` is still a frozen input masquerading as an intermediate |
| #7 | Restructure DONE. Outcome 2 steps 20–30 remain unwritten |
| #8 | Attrition ledger exists but its numbers are stale again; needs a regeneration. Current figures are in the latest comment |
| #14 | PSPS standard-unit answers convert directly, no MS data. One of the last pipeline steps |
| #24 | Publish the harmonized NSU list as a deliverable in its own right |

**#15 is the user's own** (write up lessons) — leave it.

### Remaining open #18 §A items, all re-verified against current code

- halo-halo post-merge override (same root cause as #22)
- `item_group` used as an unnormalized merge key — `07_cpi_factor.do:306, 322`
- `encode corrected_unit` — `04_unit_snap.do:293`
- `tally_price_points.py:48` — the last divergent copy of the string normalizer. Fixing it
  will move counts cited on #27 A4 and #6, so it is not a free fix.
- running sum over tags — `10_size_assignment.do:116`

`04_unit_snap.do:174` was reviewed and **accepted** by the user, not fixed — it is in the
Cleared table as such, so don't re-raise it.

### Proposed but NOT authorized — do not implement

A `d_spread` dispersion column beside `d_thin`; rewording #27 item 1; shortening the
sentence-length headers in `nsu_reference_set.xlsx`.

## START HERE: the one decision blocking everything else

**#18 §A1 — which snap rule wins in `00_shared/04_unit_snap.do`.** Measured, written up
on the issue, and waiting on the user to pick one of three options. Nothing should be
implemented here unprompted; the choice materially changes 78 published weights.

The file computes two independent corrections and keeps one. **STEP 1** snaps each weight
to the nearest power of ten toward a robust item × unit anchor and flags rows whose anchor
is untrustworthy. **STEP 3** then applies a flat magnitude threshold — below 10, multiply
by 1,000; above it, believe the number — and overwrites STEP 1 on every row that has a
weight (11,448 of 11,453). STEP 3 was written to resolve the rows STEP 1 *flagged*; its
blocks happen to partition the whole domain, so it swallowed the rest. It became the only
rule by covering everything, not by being chosen.

**985 of 11,448 comparable rows disagree (8.60%).** Using the item × unit median of the
undisputed rows as a (non-authoritative) referee:

| family | rows | STEP 1 closer to cell median | STEP 3 closer |
|---|---|---|---|
| STEP 3 **larger** | 702 | 411 | 196 |
| STEP 3 **smaller** | 283 | **270** | **0** |

- **485 of the 985** are rows STEP 1 raised no flag on and STEP 3 overruled on magnitude
  alone.
- **Neither rule dominates.** STEP 3 yields 41 values at ≤2 g/mL; STEP 1 puts 2 rows above
  100,000 g and 12 at ≤5 g. Opposite failure modes — hence a choice, not a bug fix.
- **78 published rows rest entirely on the rule choice**; 1,002 of 3,321 contain a
  disputed weighing.
- Mechanism: STEP 3's repair is a fixed `× 1000`, which fixes a three-decade error and
  nothing else. A liquor long-neck recorded as `0.001495` L is six decades out — STEP 1
  reads 1,495 mL against a cell median of 750 mL (n=478); STEP 3 publishes **1 mL**.

**The recommendation already on the issue** is option 1: keep STEP 3's plain block
structure, replace the fixed `× 1000` with a snap to the nearest power of ten toward the
cell anchor. It is the only option where neither rule's known failure mode survives. If
the user says go, implement it *with the 985-row disagreement set asserted* so the count
cannot drift unnoticed.

**How the measurement works — don't rebuild it.** `04_unit_snap.do` carries STEP 1's
answer forward as `w_step1` (and its flag as `review_step1`) purely so the comparison is
possible; STEP 3 would otherwise destroy it in place. Nothing in the build reads either
column, and `nsu_reference_set.dta` is byte-unchanged by their presence. The report is
`dofiles/90_diagnostics/snap_step1_vs_step3.py`. The snap rule is **not** re-implemented
in Python — that would duplicate it, which this codebase has been bitten by before.

**#28 is downstream of this and must be re-measured once it lands.** Its
conventional-unit dispersion numbers are contaminated by the STEP 3 artifact. The user
spotted this themselves and sequenced #18 first; the diagnostic confirmed it. CAPIZ / DAO
preserved meat, reported to #28 as a 15.7× within-municipality spread: `raw = 1.02 kg` →
STEP 3 gives 1,020 g (block 3c, "1–30 kg is a plausible bulk purchase"), STEP 1 gives
102 g against a cell median of 250 g. Under STEP 1 the case spans 65–250 g — **3.8×, not
15.7×**.

## What landed since the last handoff (`9df6946` … `c93186e`)

Read the commit messages for the why; this is the map.

- **Three stale-input / silent-failure defects fixed.** `04_unit_snap.do`'s standalone
  defaults pointed at the pre-Aug11 July subtree, and it was the only numbered step that
  never loaded `00_globals.do` — so it could never run standalone at all, the path
  collapsing to a bare `\prelim_nsu_data`. Separately,
  `02_drop_non_nsu_labels.py` destroyed its own removal report on any re-run; it now
  refuses to overwrite the record of what it removed.
- **`01_build_crosswalk.py` made runnable** (#33). It loaded two pickles nothing in the
  repo wrote and that no longer existed on disk, so the crosswalk in `outputs/` was the
  only copy of itself. `ms_keys` was recovered by deriving the tuples inline — 2,001
  distinct, matching the reference crosswalk exactly. `nsu_all` held corrected *weights*,
  which exist only after the Stata build, making the crosswalk depend on its own
  downstream output; that block moved to `90_diagnostics/fold_map.py`. The frozen
  pre-split outputs are in `reference/` — **read `reference/README.md` before trusting
  `unit_fold_map.csv`, which is deliberately not a comparison target.**
- **Four orphan outputs archived** to `outputs/archive/` (`nsu_rungs.dta`, three
  `stepA_*.xlsx`), written only by the archived `nsu_step_a_rungs.do`. The README there
  says what wrote them and why the approach was rejected.
- **The string normalizer was collapsed from thirteen definitions to one** (`dc3ecbb`).
  One copy remains divergent — see the §A list above.
- **#18 B2's conventional-branch bullet is now FALSIFIED, not merely undocumented.** It
  claimed protection because the branch publishes a municipality-specific case median;
  #28 Q4 showed the spread is inside the municipality too, so a case median cannot
  protect against it. The bullet was rewritten rather than deleted, with a note that its
  own numbers are partly contaminated by the snap issue.
- **The modal-field-label assumption is flagged loudly** in both the documentation and the
  issue body, at the user's request. Don't quietly soften it.

## Traps that have already produced wrong findings here

Each of these was reported as a result before being caught. Verify by running.

- **`weighing_approach` is a STRING in the raw launch file** and numeric in the built
  data. Comparing it against `1` there matches zero rows and reports 0/0 — exactly the
  silent-failure mode the project's own Stata notes warn about.
- **`price_type` uses spaces in the price CSV** (`"province median"`) and underscores in
  the case files. Mixing them matches nothing.
- **A stale output nothing overwrites compares SAME** and reads as reproduced. Clear
  `tables/` as well as `temp/`.
- Claimed `version 17` changed `cpi_factor` values and committed it as fact. It was row
  order, not values.
- Claimed `26_psps_extract.do` was repaired before running it; the normalization ran
  after the case key was built. Fixed in `bd16ac7`.
- Recorded the row-order non-determinism as a "finding" when it was a defect. Fixed in
  `6464f7d`.
- Stata's **exit code is unreliable** on Windows: `-e do` returns 0 with `r(601)` in the
  log. Grep the log for `^r([0-9]*);`.
