# Archive — superseded code

Nothing in this folder runs, and nothing in the live pipeline calls it. It is kept
because two of these files are still the **methodology reference** for how the current
pipeline is supposed to behave, and because a rejected approach is easier to argue
against when you can read it.

**Do not build on anything here.** If you need behaviour from one of these files, port it
into the live pipeline and delete the copy you ported from, so there is exactly one place
that produces each result.

The live pipeline is the numbered chain under `../00_shared/`, `../10_reference_set/`
and `../20_psps_retrofitting/`, run from `../master_outcome1.do`. See `../README.md` for
the step-by-step layout.

The three names this section used to give — `cleaning_Aug11.do`,
`nsu_restate_weights.do`, `nsu_reference_set.do` — no longer exist. They were renamed in
the restructure and became, respectively, `../00_shared/03_clean_ms.do`,
`../00_shared/07_cpi_factor.do`, and the three `../10_reference_set/` steps. Older notes
elsewhere may still use the retired names; that is the mapping.

---

## `cleaning.do`

The original cleaning pipeline, superseded by `../00_shared/03_clean_ms.do`.

**Still the ground truth for methodology questions.** When the current pipeline and a
reference output disagree, read this file before constructing an explanation — several
"known gaps" turned out to be misreadings of what the original actually did. The header
of `../00_shared/03_clean_ms.do` lists every behaviour that deliberately differs from it.

Writes `outputs/temp/nsu_data.dta`. The current pipeline writes to
`outputs/master_rename_build/temp/` instead, so the two builds do not overwrite each
other and the pre-Aug11 outputs remain inspectable.

## `analysis.do`

The original conversion-factor construction, and the reference implementation of the
CPI join. `docs/inflation_adjustment_spec.md` cites it by line number throughout —
lines 35–60 and 182–205 for the import, line 535 for the COICOP merge.

**It does not run to completion**, and did not before it was archived: line 537 is a bare
`merge`. Read it, do not run it.

## `nsu_step_a_rungs.do`

A shared "Step A" that was meant to serve both outcomes. Rejected for two reasons, both
still worth knowing:

1. **It set the number of groups from the weighing count** (`MIN3 = 6` / `MIN2 = 3`).
   Neither outcome uses the weighing count — Outcome 1 counts the distinct S/M/L labels
   the field recorded, Outcome 2 reads the price file's point structure. The ladder here
   demoted 77 of the 553 cases that genuinely had all three sizes recorded.
2. **The shared-file premise is wrong.** The two deliverables slice the same weighings by
   different evidence and on different grains, so the same case can yield three sizes in
   Outcome 1 and one weight in Outcome 2. Neither output is derivable from the other.

It also still references `w_ref`, a column retired in issue #29, so it errors out on its
first substantive line (`w_ref not found`, r(111)) against any current input.

Replaced by the three live `../10_reference_set/` steps (Outcome 1) and the
not-yet-written Outcome 2 build.

## `unit_correction_manual_overrides.do`

Never ran. Its input, `unit_correction_intermediate.dta`, is written by no pipeline step —
only by this file itself. The copy on disk dates from a standalone run in July.

Both of its overrides are dead: Override 1 is documented as a no-op, and Override 2's
target already resolves to 95 g under the current snap. Replaced by
`../00_shared/05_manual_corrections.do`, which asserts a row count per block so a
correction that stops matching halts the build instead of passing silently.

## `summarize_corrected_weight_by_cell.do`

Reads `outputs/temp/nsu_data.dta` — written by `cleaning.do`, not by the current chain.
It ran without error while silently summarising a month-old dataset disconnected from the
live `corrected_weight` / `cpi_factor` pipeline.

Reviving it means re-pointing line 31 at
`outputs/master_rename_build/temp/nsu_weighings_cpi.dta` and checking that the
variables it collapses on still carry those names. Its per-cell summary layout is
otherwise sound and is the closest thing the project has to a cell-level summary sheet.

## `build_forests.py` and `build_forest_medians.py`

Both hardcode `outputs/temp/nsu_data.dta` — written only by `cleaning.do`, dated
27 July. They ran without error against data predating both the `w_ref` retirement
and the non-NSU label trim, so their plots described a build that no longer exists.
Same defect that archived `summarize_corrected_weight_by_cell.do`.

Reviving either means pointing it at
`outputs/master_rename_build/temp/nsu_weighings_cpi.dta` and checking the columns it
groups on still carry those names. The forest-plot layout itself is fine; only the
input was stale.

---

## `26_psps_extract.do` — its job is done, and its output fed nothing

Formerly `psps_nsu_extraction.do`, renamed and repaired in the restructure. **It was never
a designed pipeline step.** It arrived in commit `646877f`, whose message is about the
price-point-to-size mapping and does not mention it; the restructure gave it a number and
a folder, which made it look like part of the Outcome 2 build.

**What it was actually for.** Its own first line said so: *"extract a list of municipality
x item x unit (by purchase method) for food items from PSPS consumption module."* It ended
with a frequency table of PSPS unit labels. **Vocabulary discovery** — finding out which
NSU labels PSPS households use.

Its consumer was `cleaning.do` (line 718), which merged those labels against the market
survey's and recorded the result inline:

```
Matched            170
MS only              3   (spelling: "Whole" vs "Whole (chicken)", "Pieces", "1.3 galĺon")
PSPS only          188   - incl standard units which are not present in MS
```

then dropped the `(Kg)` / `(L)` / `kilo` / `litres` labels. **That block is the ancestor of
issue #14 and of `../00_shared/02_drop_non_nsu_labels.py`.** The reconciliation it existed
to perform is now baked into the crosswalk, so the job is finished.

**Nothing live read its output.** `psps_cases.dta` was referenced only by `cleaning.do`,
also archived. `01_build_crosswalk.py` reads the raw MS and `NSU_prices_from_Makayla.csv`,
never PSPS; `90_diagnostics/scope_psps_exposure.py` reads the consumption file directly,
bypassing this file entirely.

**It cannot serve the two things Outcome 2 needs from PSPS**, which is the reason it is
archived rather than repointed:

```stata
drop fourp_status fo_id sfo_id fc_id subdate random_select nonrandom_select fd_cons_6c
drop brgy_code hhid count_res_members
```

`subdate` is the submission date — populated on all 129,094 food rows, spanning
2023-12-07 to 2025-01-22 — and it is what the PSPS price-level adjustment keys on.
`hhid` is what the final lookup join needs. Both are dropped on those two lines, and the
`duplicates drop` further collapses 87,972 household observations to 32,313 distinct
(case × source × price) rows.

**What replaces it** is a household-grain extract that keeps `hhid`, `subdate`, quantity
and expenditure, serving `24_inflate_to_psps_month.do` (which needs only the month list,
a by-product), `28_match_and_convert.do` and `29_cap.do`. Not written yet; see
`../README.md`.

**Worth reading before writing that replacement.** Four defects were repaired here and each
is a pattern to avoid: it read `3_publication_data` where the folder is `2_publication_data`;
it set no globals, so its `save` wrote to a malformed path under the fresh-batch convention;
it called `br` twice, which is interactive-only and silently does nothing in batch; and it
dropped `_merge` on the municipality join without counting the unmatched, so a municipality
with no mapping row would have carried a blank name into the case key undetected. It also
gained an `nsu_normalize` call it never had — without it, raw-cased PSPS strings would have
been joined against normalized crosswalk keys and matched nothing.

---

## `snap_step1_vs_step3.py` — superseded, and its output was going stale

Measured where the log10 anchor snap and the block reading disagree, to settle whether
the blunt magnitude rule was the right one (issue #18 A1).

**That question is now answered and implemented.** `04_unit_snap.do` STEP 3e adjudicates
between the two rules per row, and `90_diagnostics/snap_sense_check.py` reports the same
comparison plus what this file could not: which rule decided each row (`snap_rule`) and
which pool refereed it (`snap_referee`). Keeping both would leave two diagnostics
answering one question and drifting apart — the duplication this project keeps getting
bitten by.

Its committed output, `outputs/tables/snap_step1_vs_step3.csv`, was **already stale** when
this was archived: 985 rows against the live 971, carrying `id` values from the retired
positional scheme. Anyone joining on those ids would have mis-keyed. Moved to
`outputs/archive/` alongside the script.

The whole docstring describes the pre-adjudication pipeline — STEP 3 "overwrites STEP 1
on every row", the anchor "decides nothing". True when written, wrong now. Read it as a
record of why the adjudication exists, not as a description of the build.
