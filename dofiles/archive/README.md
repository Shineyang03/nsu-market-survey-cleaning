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
