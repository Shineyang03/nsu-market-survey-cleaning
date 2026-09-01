# Pipeline layout

Two deliverables are built from the same market-survey weighings:

- **Outcome 1 — the reference set.** Grams by size for each province × municipality ×
  item × harmonized NSU unit, so a future enumerator can look up what a named local
  unit weighs. Built and live.
- **Outcome 2 — PSPS retro-fitting.** Conversion factors that turn PSPS household
  quantities into grams. Skeleton only; see `master_outcome2.do` and issue #7.

They share everything up to a clean, inflation-framed weight per weighing, then
diverge: Outcome 1 slices weighings by the **size** the field recorded, Outcome 2 by
the **price points** the price file holds. Neither output is derivable from the other
— the same case can yield three sizes in one and a single weight in the other.

## Running it

```
cd ".../Data Cleaning/dofiles"
"C:\Program Files\StataNow19\StataSE-64.exe" -e do master_outcome1.do
```

**The working directory must be `dofiles/`.** Each step reaches `00_shared/00_globals.do`
by a relative path, because the globals that would give it an absolute one are what
that file defines.

Any step can also be run on its own once an earlier one has run at least once — each
writes a `.dta` the next one reads.

The Python steps are not run from the masters. They build the crosswalk and the CPI
panel and change rarely; run them from the project root when their inputs change:

```
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\00a_weighing_ids.do
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\00b_price_ms_cases.do
python dofiles/00_shared/01_build_crosswalk.py
python dofiles/00_shared/02_drop_non_nsu_labels.py --apply
python dofiles/00_shared/06_cpi_panel.py
```

**That order matters, and it is a straight line on purpose.** `00a` assigns every raw
weighing its durable id and owns the registry; `01` needs that registry to number the
price-only cases, and `03` needs the crosswalk `01` and `02` produce. Seeding the
registry later — which is where it started — left a fresh clone needing two passes to
converge, the same circularity issue #33 was about.

**That order matters.** `01_build_crosswalk.py` reads the case-coverage CSV that
`00b_price_ms_cases.do` writes, and `02` filters the crosswalk `01` produces.
Re-running `02` without rebuilding in between is a no-op by design, not an error --
it refuses to overwrite the record of what it removed.

**After any change**, run the claim checker from the project root:

```
python dofiles/90_diagnostics/verify_documented_claims.py
```

It re-derives every number recorded in `docs/` that no build file produces and fails
when one has moved. It is what catches a figure going stale in a document.

## Folders

| folder | what it holds |
|---|---|
| `00_shared/` | raw market survey → one clean weight per weighing, with `cpi_factor` |
| `10_reference_set/` | Outcome 1 |
| `20_psps_retrofitting/` | Outcome 2 (skeleton) |
| `90_diagnostics/` | scoping, auditing and reporting. Never on a critical path. |
| `archive/` | superseded. Nothing calls it. `archive/README.md` says why each file is there. |

## The steps

### `00_shared/` — both outcomes

| file | does |
|---|---|
| `00_globals.do` | paths, plus the two shared programs `def_hetero` and `nsu_normalize` |
| `00a_weighing_ids.do` | assigns every raw weighing a durable `id` and owns `weighing_id_registry.csv`. Reads only the raw survey, so nothing downstream can affect an id |
| `00b_price_ms_cases.do` | which cases exist in the price file, the MS, or both. Reads the RAW market survey, so the crosswalk cannot depend on its own downstream output (#33) |
| `01_build_crosswalk.py` | folds raw NSU spellings into `harmonized_nsu_unit`; writes `master_nsu_rename.csv` |
| `02_drop_non_nsu_labels.py` | removes labels that are not NSUs (standard quantity, ambiguous quantity, free text) and reports what it removed |
| `03_clean_ms.do` | load, comments, normalize, **exclude non-NSU labels**, harmonize, identifiers. Calls 04 and 05. |
| `04_unit_snap.do` | magnitude correction — kg→g, L→mL, decimal slips |
| `05_manual_corrections.do` | every hand-made weight/unit fix, each asserting its row count |
| `06_cpi_panel.py` | province × item-group × month CPI panel |
| `07_cpi_factor.do` | drops the 98 vendor-priced rows; builds `cpi_factor`. Output: `nsu_weighings_cpi.dta` |

**Steps 03 → 04 → 05 must stay in that order.** `04`'s anchor is a median over
whatever rows it is given, so the exclusion in `03` has to happen first. Running it
later is what once turned a 10 L gallon into 10 mL.

### `10_reference_set/` — Outcome 1

| file | does |
|---|---|
| `10_size_assignment.do` | assigns each weighing a `size_ord`, re-derived from the pooled weight distribution rather than taken from the field label |
| `11_size_checks.do` | checkpoint: under-filled cases, and the field-label-vs-empirical-size crosstab that is the evidence for re-terciling. Changes no rows. |
| `12_publish_reference_set.do` | collapses to case × size, publishes `nsu_reference_set.dta` / `.xlsx` |

### `20_psps_retrofitting/` — Outcome 2

| file | does |
|---|---|
| `26_psps_extract.do` | pulls the household side from the PSPS consumption module |

Steps 20–25 and 27–30 are not written. `master_outcome2.do` lists them with the issue
that owns each decision.

## Conventions worth keeping

Both of these exist because the pipeline was bitten without them.

**A correction that can match nothing must assert its row count.** One hand-made fix
tested the wrong size code, matched zero rows, logged `(0 real changes made)`, and
shipped a 1 gram whole chicken to the published reference set. `05_manual_corrections.do`
is the pattern: one block per correction, each stating and asserting how many rows it
expects.

**A hardcoded count must carry its derivation, not just its value.** An input tripwire
that only says `assert n == 11458` invites whoever hits it to update the number. The
one in `07_cpi_factor.do` shows the arithmetic that produces it and says to reconcile
against the log instead.

## Determinism

Stata does not sort stably: since version 13, `sort` places **tied** observations in a
random order drawn from the sort seed. Any `bysort` or `merge` on a key that does not
uniquely identify a row therefore produces a different row order from run to run —
which it did here, until it was fixed.

Two things keep it deterministic, and both need to stay:

1. `00_globals.do` pins `set sortseed`. The value is arbitrary; never changing it is
   the point.
2. Every step sorts on a **unique** key immediately before saving, so no ties are left
   for the seed to break.

This is not only about reproducibility. A `bysort key: ... _n` where `key` is not
unique is reading an order the sort seed chose. The pipeline has one such construction
(`10_size_assignment.do`, issue #18) — pinning makes it reproducible, not correct.
