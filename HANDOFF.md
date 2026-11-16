# Session handoff — NSU Market Survey → PSPS gram conversion

Paste this whole file as your first message in the new session.

---

## Status update, 2026-11-16

Source: git history to 2026-10-09, project documents and project memory. The state of the
GitHub issues was **not** re-checked; read them before acting. The sections below this one
date from 2026-09-16 and are superseded where they differ.

**Where the repo is.** Branch `main`, last commit `3bd7cf1` (2026-10-09), in sync with
`origin/main`. 70 commits since 2026-09-16. The branch named further down
(`fix/snap-kg-band-and-price-drops`) is no longer current.

### What changed since 2026-09-16

1. **Photograph verification (Check 1 and Check 2), 19 Sept to 5 Oct.** Every field
   photograph was linked to its weighing. Check 1 reads package labels; Check 2 reads the
   scale display. A human-scored validation set came first, then the readers were run in
   batches with checkpointing. Per the commit messages: the cropping step produced 6,939
   displays from 11,449 photographs; batch 3 finished 680 of 680 after six reader failures;
   209 of 209 override verdicts were recorded in round 3 (`3a68be2`). Earlier, the model read
   at 97% against the human and four published weights were found to be 10 times too high
   (`a52d177`); 16 weight corrections, 3 dimension changes and 9 supersedes were finalised
   (`4096bd9`).
2. **Four owner rulings on which number a photograph yields** (2 Oct, assumption A25 in
   `docs/implicit_assumptions.md`; summary in `CLAUDE.md`).
3. **Folding rule.** Folding two spellings now needs positive evidence (`56fa2f7`); the
   weight-uncertainty flags were retired and no weight is invented where none was typed
   (`783588e`).
4. **Inputs moved into the repo and the methodology rewritten** (`589c5d0`).
5. **Reproducibility.** A generator for the price schedule the field used (`5563c37`); one
   script that recomputes every headline figure and asserts they reconcile (`fe31da6`); the
   outstanding-reading count is derived from the master, not from the log that scheduled
   the run (`3bd7cf1`).
6. **Process.** Two hooks (see `CLAUDE.md`); the reader dispatch brief is versioned at
   `image checking/READER_BRIEF.md`; `docs/working_across_devices.md` explains how to work
   from more than one computer.

### Hangups and concerns on the record

* **The readers do not all work.** The digit reading failed in the first calibration
  (Check 2); `not_visible` was not reliable in the human comparison; one reader was isolated
  as the failing one (`de1e061`). The object instrument works as a method but its scored
  field does not (`e7826e8`). The unresolved folds turned out to be unresolvable by size
  (`4987291`). The reader scores are not accuracy figures (`3f26e2d`).
* **Being interrupted is normal**, so every reader checkpoints per sheet.
* **Agents overwrote each other's helper scripts** and rebuilt a decoder that already
  existed. Both are now rules in `CLAUDE.md`.
* **Three staged photograph verdicts overwrote an earlier human decision** (`04a9dbd`); the
  staging stopped there.
* **The ice cream density of 0.9 g/mL leans heavy** and reaches 127 rows (A25).
* **Box sync** can lock files during Stata runs; `putexcel` races it.

### Loose ends found on 2026-11-16

* **Path fix committed, not yet run (`56fddac`).** The PSPS publication folder
  `2_consumption` was renamed `02_consumption` in the Wave 1 Pub project. The old name no
  longer exists in Box; the new one does. The one-line fix in
  `dofiles/00_shared/00_globals.do`, `dofiles/90_diagnostics/scope_psps_exposure.py` and
  `dofiles/price/NSU_Price.R` was checked only for the new path's existence. Run the
  pipeline step that reads the PSPS consumption file to confirm.
* **Stale documents:** this file (the sections below); `docs/attrition_ledger.md` (16 Sept,
  already known stale in #8); `dofiles/README.md` (17 Sept, before the photograph work;
  the photograph work is described in `image checking/README.md`); the "23 checks, all OK
  at `8033446`" line below, which must be re-run.

### Next steps

Open as of the 2026-09-16 triage and not shown as closed in the git history (confirm each
against its issue):

1. Decisions for the owner: #27 (implicit assumptions), #28 (is "conventional" a unit
   property or a cell assignment), #30 (province fallback, the blocker for Outcome 2), #31
   (778 singleton groups and 8 unfixed outliers).
2. Code: #18, three items left (`item_group` merge key in `07_cpi_factor.do`; the last
   divergent normalizer in `tally_price_points.py`; the running sum in
   `10_size_assignment.do`). Regenerate the attrition ledger (#8).
3. Outcome 2 steps 20 to 30 are still unwritten (#7). #14 and #24 are actionable.
4. New since then: run the path fix above, re-run
   `verify_documented_claims.py` and `verify_reproducibility.py`, update
   `dofiles/README.md` for the photograph checks, then confirm with the owner what remains of
   the override review after round 3.
5. #15 is the owner's.

---

## What the project is

Philippine market survey (MS) weighings of non-standard units (NSUs) — a *putos*, a
*bilog*, a *tumpok* — turned into grams. Two deliverables:

- **Outcome 1, the reference set.** Grams by size (small/medium/large, or one weight
  for conventional units) per province × municipality × item × harmonized NSU unit.
  **Built and live.** 3,303 rows.
- **Outcome 2, PSPS retro-fitting.** Conversion factors mapping PSPS household
  quantities to grams, via price points. **Skeleton only** — see `master_outcome2.do`
  and issue #7.

Repo: `Shineyang03/nsu-market-survey-cleaning` (user's own repo).
Working dir: `C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning`
Branch: `fix/snap-kg-band-and-price-drops`. HEAD: (see git log). Working tree clean apart
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

23 checks (all OK at `8033446`); it re-derives every number in `docs/` that no build file produces and fails
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
and reads as reproduced. There was a second mode, `--reference`, byte-comparing the
crosswalk against frozen pre-split copies in `reference/`; it is retired and those copies
are gone — the baseline had drifted behind the live build on intended changes and reported
a failure on every run. `reference/README.md` has the reasoning. The single confirmed
crosswalk is `outputs/tables/master_nsu_rename.csv`.

**The Stata chain is verified reproducible** as of `a0868d1`: cleared `temp/*.dta`, `tables/*.xlsx` and the ported step's own output, rebuilt from raw (`00b_price_ms_cases.do` then `master_outcome1.do`), and all 25 watched outputs matched value-for-value. `snap_sense_check.xlsx` reports MISSING until you re-run its Python producer -- it is a diagnostic, not a chain output.

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
- Current counts: 11,494 raw MS weighings → 42 non-NSU excluded → 11,449 →
  98 dropped in `07` → 11,351 → Outcome 1 publishes 3,303 rows.
  The reference set moved 3,321 → 3,305 (cabbage label dropped) → 3,304
  (CELL_MIX closed an intra-cell split) → 3,303 (5 reviewer-flagged ambiguous
  readings set to .c). The 5 stay in the weighings files as .c so the attrition
  ledger can account for them; `missing()` is true for .c, so 10_size_assignment
  drops them.

## Issue triage — 16 open

**The issues are the source of truth. This table is a map, not a substitute.**

**Blocked on a decision from you. Scope and present options; do not implement.**

| # | what needs deciding |
|---|---|
| #27 | Implicit assumptions. Each dispositioned; A8's dispersion figure is now re-measured (see #28) |
| #28 | Is "conventional" a unit property or a cell assignment? Data says cell assignment for 13 of 21 labels. **Dispersion re-measured after #18 A1: max is 6.68x, not the 14x reported before.** camote tops/bundle and prawns/tumpok are genuinely dispersed and not artefacts |
| #30 | Province fallback. **The blocker for Outcome 2.** Re-read it against #28's corrected numbers — the fallback was argued against partly on the contaminated 14x figure |
| #31 | 778 singleton hetero-groups. The 1 g chicken is fixed; **8 other outliers are not**, and 5 are `putos` — possibly a reclassification question (#28) |

**Waiting on the Outcome 2 build:** #11, #16, #19, #20, #23, #25.

**Actionable now:**

| # | what |
|---|---|
| #18 | **The consolidated code-defect issue.** One comment holds the whole status; 4 items open, each re-verified by grep at `a0868d1`. Start here for code work. |
| #8 | **Attrition ledger is stale** — says 11,337 into publish against 11,307 actual. Only 4 of that gap is the cabbage drop; the rest moved in `3b77d85`. Needs regeneration |
| #7 | Restructure DONE. Outcome 2 steps 20-30 remain unwritten |
| #14 | PSPS standard-unit answers convert directly, no MS data |
| #24 | Publish the harmonized NSU list as a deliverable |

**#15 is yours** (write up lessons) — leave it.

**Closed this session:** #21 (medium kept + documented), #22 (cabbage label dropped),
#33 (crosswalk CSV has a producer), #3 (tercile tie, status quo accepted).

### The 4 open #18 items, verified at `a0868d1`

- ~~mixed-vegetable post-merge override~~ **CLOSED**. Moved into `CELL_MIX` in
  `nsu_fold_rule.py`, keyed on (province, municipality, item, raw unit). It WAS the cause
  of #22 -- I briefly claimed otherwise after measuring the post-drop state, which could
  not see the rows in question; the pre-drop build at `b37d2f5` settles it.
- `item_group` unnormalized merge key — `07_cpi_factor.do:306, 322`
- `tally_price_points.py:48-49` — the last divergent normalizer copy. Fixing it moves counts
  cited on #27 A4 and #6, so those must be re-derived in the same commit
- running sum over tags — `10_size_assignment.do:109-116`. Reproducible (seed pinned) but
  not correct; fix is `egen ... group(field_ord), by(cell)`

`04_unit_snap.do:174` (the litres block) was **reviewed and accepted by you** — do not
re-raise it.

## For manual sense-checking: the snap output

`outputs/build/tables/snap_sense_check.xlsx`, regenerated by
`python dofiles/90_diagnostics/snap_sense_check.py`. Four sheets:

| sheet | rows | what |
|---|---|---|
| `disagreements` | 985 | every row where the anchor and the block reading differ, sorted by distance from the cell median so the likeliest errors are on top |
| `gate_overrules` | 42 | rows where the anchor was rejected as implausible and the block reading published — the contaminated cells |
| `reference_set_now` | 3,305 | the deliverable as published |
| `cell_context` | 3,469 | every weighing in any cell touched above, so a disputed row reads against its neighbours |

## What landed since the last handoff (`c93186e` … `a0868d1`)

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
