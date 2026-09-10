# Archived outputs — produced by code that no longer runs

Nothing in the live pipeline writes these, and nothing reads them. They are kept because
they are the only surviving output of a rejected approach, and a rejected approach is
easier to argue against when you can see what it produced.

**`graphs/` is the one exception, and it is a different case — read the section at the
foot of this file before assuming those figures are dead.**

**These files are frozen. Do not cite a number from them as current.** A full rebuild
with `outputs/build/` cleared does not recreate them — that is how they
were identified (`dofiles/90_diagnostics/verify_reproducibility.py` reported them as
MISSING).

| file | written by | dated |
|---|---|---|
| `nsu_rungs.dta` | `dofiles/archive/nsu_step_a_rungs.do` | 2026-08-25 |
| `stepA_empty_rungs.xlsx` | same | 2026-08-25 |
| `stepA_label_vs_tercile.xlsx` | same | 2026-08-25 |
| `stepA_nonmonotonic.xlsx` | same | 2026-08-25 |

## Why `nsu_step_a_rungs.do` was rejected

It was a shared "Step A" meant to serve both outcomes. `dofiles/archive/README.md` has
the full argument; the short version is two reasons, both still worth knowing:

1. **It set the number of groups from the weighing count** (`MIN3 = 6` / `MIN2 = 3`).
   Neither outcome uses the weighing count — Outcome 1 counts the distinct S/M/L labels
   the field recorded, Outcome 2 reads the price file's point structure. That ladder
   demoted 77 of the 553 cases that genuinely had all three sizes recorded.
2. **The shared-file premise is wrong.** The two deliverables slice the same weighings by
   different evidence and on different grains, so the same case can yield three sizes in
   Outcome 1 and one weight in Outcome 2.

It also still references `w_ref`, a column retired in issue #29, so it errors on its first
substantive line against any current input.

The live equivalents are the three `dofiles/10_reference_set/` steps.

---

## `spotcheck_identified_errors.xlsx` — its `id` column is invalid, do not join on it

A 24 July spot-check listing 41 weighings judged to be errors. No file in the live tree
writes it and none reads it.

**Every id in it is wrong now.** They were assigned by the original `gen id = _n`, which
numbered rows by position. Checked against the current build: of the 41, **40 point at a
different weighing** and 1 no longer exists. The ids still fall inside the valid range,
so nothing looks broken — `id 4513` reads as Loaf Bread here and is prawns in the build;
`id 9418` was Chicken and is cabbage.

The rest of the file is still meaningful: `pull_item`, `weight`, `unit`,
`corrected_weight` and `tier` describe real readings. If the spot-check is ever revisited,
re-key it on those columns and discard the id. Note the content key here is incomplete —
there is no province or municipality — so a few rows may be ambiguous.

Weighing ids are now assigned once and remembered in
`outputs/tables/weighing_id_registry.csv` (`dofiles/00_shared/00a_weighing_ids.do`), so
an id written down today keeps its meaning. That was not true when this file was made.

---

## `price_only_no_weight_anywhere.csv` — an orphan input, removed rather than repaired

586 rows, one per price-only cell, with four informational columns:
`item_weighed_in_this_municipality`, `n_weighings_of_item_here`,
`other_units_weighed_here`, `this_unit_weighed_anywhere`.

**Nothing in the tree ever wrote it**, and `90_diagnostics/build_pipeline_explorer.py`
was its only reader — the orphan-input defect of issue #33, where a frozen CSV is
presented as an intermediate, cannot be regenerated, and drifts silently as the
crosswalk changes.

The obvious fix was to give it a producer. It did not earn one:

* all four columns are derivable from `nsu_weighings_cpi.dta`;
* the explorer **already** derived the same classification freshly, using the CSV only
  as a preferred lookup with the fresh derivation as fallback — two implementations of
  one rule, with the frozen one winning;
* the two agree on **585 of its 586 rows**. The one disagreement is its own drifted row,
  CAPIZ / PANAY / drinking water / `distilled water`, which it records as weighed
  nowhere and which the current weighings place at a province fallback;
* that row keys to a cell that no longer exists, so it was already being filtered out.
  **Bucket totals are identical with and without the file**: 1,943 convertible, 427
  province fallback, 78 other-province-only, 79 weighed nowhere.

So its entire remaining contribution was a warning that it had gone stale. It also
powered a `stale-CSV` badge and a case-detail panel in the explorer, both of which
described the CSV rather than the data and were removed with it.

**One framing difference it embodied, worth knowing if it is ever revived:** it required
a *usable weight* to call a cell weighed, whereas the live derivation counts a cell as
weighed if any row exists. CAPIZ / TAPAZ chicken sits on exactly that line — its rows
exist but carry no `corrected_unit`. Both are defensible; the live one is in force.

To recover the per-cell detail, derive it from `nsu_weighings_cpi.dta`. Do not revive
this file.

---

## `graphs/` — superseded figures, not dead code

17 files moved here from `outputs/graphs/`: six forest plots (`forest_v1` … `forest_v6`),
four heatmaps, a per-province forest dot-plot set, and one size-check panel. All dated
**24 July 2026**, six weeks stale at the time they were moved.

**Unlike everything else in this folder, the code that writes them still runs.**

| figure set | written by | status |
|---|---|---|
| `heatmap_prov_mun_by_nsu_item*.png` | `dofiles/90_diagnostics/heatmaps.do` | **live**, just not run since July |
| `forest_v1` … `forest_v6`, `forest_dotplot/` | `dofiles/archive/build_forests.py`, `build_forest_medians.py` | archived code |
| `sizecheck_Chicken_Bilog.png` | an ad-hoc check | no producer in the tree |

So these are **superseded outputs**, not the residue of a rejected approach. They were
archived because they are stale — they predate the fallback ladder, the `branch`
reclassification (#28), the uncertainty columns (#35) and the A10 reversal, so any figure
here is drawn on a build that no longer exists. Do not read a level off them.

`${graphs}` still points at `outputs/graphs/`, and `00_globals.do` recreates that folder
on every run, so it will reappear (empty) immediately and refill the moment `heatmaps.do`
is run again. That is correct: it is a live output location whose *contents* went stale,
which is a different thing from a dead path. If you want the heatmaps current, re-run
`heatmaps.do` rather than reading these.

The two `build_forest*.py` scripts are in `dofiles/archive/`; `dofiles/archive/README.md`
says why. Regenerating the forest plots would mean reviving them first.
