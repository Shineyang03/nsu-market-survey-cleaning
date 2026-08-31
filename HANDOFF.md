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
Branch: `fix/snap-kg-band-and-price-drops`. HEAD: `6464f7d`. Working tree clean apart
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

11 checks; it re-derives every number in `docs/` that no build file produces and fails
when one moves. It has caught three wrong figures already. Treat a CHANGED verdict as
"reconcile", never as "update the constant".

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
| #27 | Implicit assumptions. User dispositioned each: A1→#28, A4→#21, A8→"change to assert", rest→take as given. **A5 has an unanswered question from them: "what is under-filled cases"** |
| #28 | Is "conventional" a unit property or a cell assignment? Data says cell assignment for 13 of 21 labels |
| #30 | Province fallback. **The blocker for Outcome 2** — 1 PSPS observation in 6 needs it, and borrowing weights across municipalities is unsolved (#28 measured 14× variation). Full write-up incl. the combining-step options is on the issue |
| #3 | Tercile tie rule; 94 under-filled cases |
| #31 | 778 singleton hetero-groups. The 1 g chicken is fixed; **8 other outliers are not**, and 5 of them are `putos` — possibly a reclassification question (#28), not a value question |
| #22 | Root cause found and posted: a post-merge override manufactures a harmonized unit outside the crosswalk. Three options on the issue, none chosen |

**Waiting on the Outcome 2 build — nothing to do until it exists:** #11, #16, #19
(cap threshold `t` unset), #20, #23, #25.

**Actionable now:**

| # | what |
|---|---|
| #18 | **The consolidated code-defect issue** (#9 and #32 folded in). Has a high-stakes table with file:line. Start here for code work. |
| #7 | Restructure DONE. Outcome 2 steps 20–30 remain unwritten |
| #8 | Attrition ledger exists but its numbers are stale again; needs a regeneration. Current figures are in the latest comment |
| #14 | PSPS standard-unit answers convert directly, no MS data. One of the last pipeline steps |
| #24 | Publish the harmonized NSU list as a deliverable in its own right |

**#15 is the user's own** (write up lessons) — leave it.

## The single most important open code question

**#18, top row.** `00_shared/04_unit_snap.do` STEP 3 (lines 160–206) exhaustively
partitions every row that has a weight — 11,448 of 11,453 — and overwrites STEP 1 on
all of them. Measured: the log10 anchor snap decides **0** rows, `MIN`/`FLOOR`/`SIB`/`AMB`
govern nothing, and the review queue receives only the 5 rows with no weight.

So a bare magnitude threshold is the *only* rule deciding every corrected weight, and
it became the only rule by covering the whole domain rather than by being chosen. That
is worth a deliberate decision.

## Things I got wrong this session — don't rebuild these

- Claimed `version 17` changed `cpi_factor` values and committed it as fact. It was
  row order, not values. Both notes corrected.
- Claimed `26_psps_extract.do` was repaired before running it; normalization was after
  the case key was built. Fixed in `bd16ac7`.
- Recorded the row-order non-determinism as a "finding" when it was a defect. Fixed in
  `6464f7d`.

The pattern: verify by running before asserting.
