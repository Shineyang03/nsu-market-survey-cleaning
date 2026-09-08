# Pipeline layout

**This file is the living map of the pipeline** — what exists, what runs in which order,
and which steps are still unwritten. Update it when a step lands, not when a decision is
made; decisions live in the issue that owns them and in `../docs/`.

Two companions, and they do not overlap:

- **`../docs/implicit_assumptions.md`** — every hard-coded threshold, tie rule and
  fallback, and what each one claims about the data. **Read it before changing any
  constant in a do-file.**
- **`../docs/conversion_factor_methodology.md`** — what the method is and why, including
  the assumptions the method itself makes.

Two deliverables are built from the same market-survey weighings:

- **Outcome 1 — the reference set.** Grams by size for each province × municipality ×
  item × harmonized NSU unit, so a future enumerator can look up what a named local
  unit weighs. Built and live.
- **Outcome 2 — PSPS retro-fitting.** Conversion factors that turn PSPS household
  quantities into grams. Skeleton only — the step table under
  *`20_psps_retrofitting/`* below says what each remaining step owes and what blocks it.

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

**That order matters, and it is a straight line on purpose.** Each link:

- `00a` assigns every raw weighing its durable id and owns the registry. It reads only
  the raw survey, so nothing downstream can move an id.
- `01` needs that registry to number the price-only cases, and reads the case-coverage
  CSV that `00b` writes.
- `02` filters the crosswalk `01` produces. Re-running it without rebuilding in between
  is a no-op **by design, not an error** — it refuses to overwrite the record of what it
  removed.
- `03` needs the crosswalk `01` and `02` produce.

Seeding the registry later — which is where it started — left a fresh clone needing two
passes to converge, the same circularity issue #33 was about.

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
| `01_build_crosswalk.py` | folds raw NSU spellings into `harmonized_nsu_unit`; writes `master_nsu_rename.csv`. `--outdir <dir>` builds it somewhere else and refuses to touch the id registry, for comparing a rebuild against the live crosswalk |
| `02_drop_non_nsu_labels.py` | removes labels that are not NSUs (standard quantity, ambiguous quantity, free text) and reports what it removed |
| `03_clean_ms.do` | load, comments, normalize, **exclude non-NSU labels**, harmonize, identifiers. Calls 04 and 05. |
| `04_unit_snap.do` | magnitude correction — kg→g, L→mL, decimal slips |
| `05_manual_corrections.do` | every hand-made weight/unit fix. §1–5 are one block per correction, each asserting its row count; **§6 applies the review ledger**, `reference/reviewed/snap_verdicts.csv`, which is where the bulk of the adjudicated decisions now live. See *Adjudicating a weight* below. |
| `06_cpi_panel.py` | province × item-group × month CPI panel |
| `07_cpi_factor.do` | drops 98 price-quantity rows whose recorded price was not the price handed over — 71 vendor-priced (a further 23 are rescued where they were the case's only rung) and 27 where the vendor gave no price at all. **The only place those rows are dropped, and both outcomes depend on it.** Builds `cpi_factor`. Output: `nsu_weighings_cpi.dta` |
| `08_branch.do` **(not written; decided on #28)** | derives `branch`, the variable the build slices on. Equals `weighing_approach`, except a conventional case whose (item, harmonized unit) pair mixes approaches elsewhere becomes size-based — 99 cases, 388 weighings. Also sets `d_reclassified`. |

**Two shared MODULES live in `00_shared/` alongside the steps.** Nothing runs them; they
are imported, and they are where two decision rules are defined once so no caller can
re-implement them differently.

| module | defines | imported by |
|---|---|---|
| `nsu_fold_rule.py` | **THE fold rule** — which raw spellings mean the same thing, and therefore what `harmonized_nsu_unit` is. Pure functions of (item, raw label), reading no build output, deliberately: the snap's anchor pool is keyed on `harmonized_nsu_unit`, so a fold that read corrected weights would close a loop (#33). Its carve-outs are the item-specific separations in `../docs/master_rename.md` §6. | `01`, plus `90_diagnostics/fold_map.py` and `verify_documented_claims.py` |
| `nsu_normalize.py` | the one definition of the project's string normalization (`nz` / `ni` / `ng`). The Stata counterpart is the `nsu_normalize` program in `00_globals.do` and must agree with it character for character. **Never NFKD-decompose** — `DUEÑAS` becomes `DUEAS`, not `DUENAS`. | `01`, `02`, `nsu_fold_rule.py`, and 16 diagnostics |

There used to be eleven byte-identical copies of the normalizers across `90_diagnostics/`;
a fix to any one of them reached none of the others (#32). Import these, never copy them.

**`branch` vs `weighing_approach`, once `08` exists.** Use **`branch`** wherever the code
decides how a weighing is PROCESSED or PUBLISHED. Keep **`weighing_approach`** wherever it
describes WHAT THE FIELD DID. `weighing_approach` is never overwritten: it is the field
record, and the evidence for #28 is keyed on it — `scope_conventional_units.py` reading
`branch` would report no mixed pairs at all, which is the finding erasing itself. Getting
this backwards is a silent error in either direction. The site-by-site split is on #28.

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

**This folder is currently empty.** `26_psps_extract.do` was archived: it did vocabulary
discovery — which NSU labels PSPS households use — that job is finished and now lives in
the crosswalk, and it dropped `hhid` and `subdate`, so it could not serve either thing
Outcome 2 needs from PSPS. See `../archive/README.md`.

**Nothing reads the PSPS consumption file on a critical path today.** The first Outcome 2
step to write is a **household-grain extract** keeping `hhid`, `subdate`, quantity and
expenditure. Three steps below need it, at two grains: `24` needs only the list of months
occurring in each municipality, which is a by-product; `28` and `29` need the household
rows themselves.

**Steps 20–30 are not written.** This table is the source for what each owes and
what blocks it; `master_outcome2.do` prints an abbreviated version when it stops.

| step | owes | blocked on |
|---|---|---|
| `20a_psps_households.do` | the household side of PSPS — one row per household × item × unit × source, keeping `hhid`, `subdate`, quantity and expenditure, normalized into the crosswalk's vocabulary. Read by `24`, `28` and `29`. The `a` suffix follows `00a`/`00b`: it must run before the numbered chain, since `24` needs its month list. | nothing — write it first |
| `20_case_price_points.do` | how many price points a case gets, after the ₱20 union-merge | the `unique_mun_price` arm — **#23**. The merge rule itself is decided (#21 §2). |
| `21_branch_size_based.do` | cut pooled weights into that many parts | 20, plus how a household reporting an unweighed spelling is routed (**#21 §5.3**, 273 cases) |
| `22_branch_price_quantity.do` | `w_g` per case × `pull_price` | nothing — decided (#21 §2 rows 5–6) |
| `23_branch_conventional.do` | one weight per case, for the **24** cases whose (item, unit) pair is conventional everywhere it appears | **decided on #28**, not yet built. The other **99** conventional cases are reclassified to size-based and publish as medium — see `branch` below, and A1/A12 in `../docs/implicit_assumptions.md`. |
| `24_inflate_to_psps_month.do` | `w_g_m`, `v_g_m` per interview month | nothing — decided (#5) |
| `25_lookup.do` | append the three branches | #11 (the no-inflation variant) |
| `27_standard_units.do` | kg/L answers convert directly | #14 |
| `28_match_and_convert.do` | nearest point, `CF_h`, `grams_h` | nothing — decided (#5) |
| `29_cap.do` | clamp `p_h/p_g`, flag | **#19**, and the threshold `t` is unset. Choosing `t` needs no weights — it needs step 20 and a household-grain extract. |
| `30_fallback.do` | cases with no MS weight of their own | **#30 — the real blocker.** One PSPS observation in six needs a fallback, and borrowing weights across municipalities is unsolved. |

**#30 gates the deliverable** regardless of what order the others land in. Note that #30's
cost argument was written against a 14× cross-municipality spread; the corrected figure is
**6.7×**, so re-read it against that.

**Carry the uncertainty through.** Every weighing carries flags saying whether its weight
was corrected and whether it is disputed, anchor-flagged or unusable —
`weight_correction_report.csv`, written by `90_diagnostics/report_weight_corrections.py`.
Roughly one weighing in seven carries some uncertainty; run that script for the current
count rather than trusting a number written here, because it moves with every review
round. A conversion factor built on a disputed weight should say so, and no step
currently reads that file.

## Adjudicating a weight: the snap review loop

`04_unit_snap.do` decides magnitude by rule, but some readings cannot be settled by rule —
a raw `0.00125` might be 1 mL or 1,250 mL, and only the surrounding cell says which. Those
go to a human, and the loop that does it is:

1. **`python dofiles/90_diagnostics/snap_sense_check.py`** writes
   `outputs/master_rename_build/tables/snap_sense_check.xlsx`. Open the **`to_review`**
   sheet first — it holds only the rows still needing a decision, each with a
   `proposed_value` and the rule behind it. `all_weighings` holds the whole file for an
   overall pass.
2. **Fill in `Corrected Value`** where you disagree. Leave it blank to accept.
3. **Re-run the same script.** It archives your annotated copy into `reference/reviewed/`
   automatically *before* regenerating — no manual copy needed — then rewrites
   `reference/reviewed/snap_verdicts.csv` from the whole archive.
4. **Re-run `master_outcome1.do`.** §6 of `05_manual_corrections.do` applies the ledger.

Two properties worth knowing before you touch it:

- **Verdicts are matched on CONTENT** — cell, hetero group, raw weight at six significant
  digits — not on `id`, because the earliest review workbooks predate the durable id
  registry and their ids now point elsewhere. Six significant digits because `weight` is a
  Stata float: 1265 stores as 1264.9999, and an exact float join drops such rows silently.
- **The ledger is rewritten in full from the archive on every run, never appended.** That
  makes it idempotent. Do not hand-edit `snap_verdicts.csv` — the next run overwrites it.
  Across review rounds a later verdict overrides an earlier one on the same row, which is
  how a decision gets revised; a conflict *within* one round halts the run instead.

`verdict_landed` in the workbook says whether each past verdict actually reached the
published value, so a decision cannot fall out of the build unnoticed.

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

**A threshold must say what it claims about the data.** `KGMAX = 30`, `THIN = 3`,
`FOLD = 0.85` and the rest are each a statement about the world, and several are safe
only by accident. Every one is written up in `../docs/implicit_assumptions.md` with what
rests on it and whether anything checks it. **Add an entry there before adding a
constant here** — the test is whether a reader of the line would know a decision was
made.

**A diagnostic must read the build it claims to validate.** `validate_folds.py` spent six
weeks pointed at `outputs/temp/nsu_data.dta` — the pre-Aug11 build — so it reproduced its
own past answers no matter what changed upstream, which is worse than not running: it
looked like confirmation. Three files were archived for hardcoding that same path
(`archive/README.md`). **The live weighings are
`outputs/master_rename_build/temp/nsu_weighings_cpi.dta`**; anything reading
`outputs/temp/` is reading a build from July. `verify_documented_claims.py` now refuses to
score a fold check whose input CSV is older than the weighings it describes.

**A decision made from data must be re-checked against that data.** The fold rule is a
pure function of (item, raw label) and reads no weights — deliberately, because the snap's
anchor pool is keyed on `harmonized_nsu_unit`, so a fold that depended on corrected
weights would close a genuine loop (#33). But its carve-outs were *decided* from weight
tests and then hardcoded, so new weights cannot change the harmonization while still
invalidating the evidence it rests on. The check "the fold policy still holds" in
`verify_documented_claims.py` is the tripwire for exactly that gap.

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
