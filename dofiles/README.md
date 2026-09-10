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
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\06_cpi_panel.do
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

### Where the fold evidence is produced, and why it is produced there

Inside `03_clean_ms.do` there is one ordering constraint that is not about which file
needs which `.dta`. It is about what a piece of evidence is allowed to have seen.

```
03    raw MS prep — comments, obs_type → item_nsu_hetero_type      no folds applied yet
03a   00_shared/03a_block_reading.do → w_block                     reads weight, unit only
───── everything the fold test reads is complete at this line ─────────────────────────
03    merge master_nsu_rename → harmonized_nsu_unit
04    00_shared/04_unit_snap.do → published corrected_weight        pools on ${unitvar}
05    00_shared/05_manual_corrections.do
```

The **block reading** is the typed weight in canonical units, with the kg/g/L tick not
taken literally — a pure function of `weight`, `unit` and `KGMAX`. It used to be STEP
3a–3d of `04_unit_snap.do`, which runs *after* the crosswalk merge. Nothing about it
depended on that merge, but its position meant a reader had to trace `04` to establish
as much.

That matters because of what reads it. `validate_folds.do` asks whether two raw labels
folded into one `harmonized_nsu_unit` actually weigh the same. **The published weight
cannot answer that**: `04` snaps it toward the median of a pool keyed on
`harmonized_nsu_unit`, so two labels folded together are snapped toward one median,
nudging the test toward "they weigh the same" — which is what justified folding them.

Measured on the current build, all three candidate inputs:

| test input | crackers `bilog`/`pieces or units` | fresh fish `bilog`/`binilog` |
| :-- | :-- | :-- |
| published weight (pool keyed on harmonized unit) | **DIFFER** p=0.043 | agree p=0.469 |
| **block reading** | agree p=0.220 | agree p=0.944 |
| published weight (pool keyed on raw label) | **DIFFER** p=0.043 | **DIFFER** p=0.041 |

The crackers fold contradicts the documented fold policy only on the published weight;
on block readings it passes, with an identical size-controlled ratio of 0.62. Keying the
snap on the raw label does not fix it and breaks a different fold instead — each label
snapped toward its own median, pushing folded labels apart. The block reading is the only
input with no grouping bias in either direction. The carve-outs themselves (`camote`
pieces, `putos` for ice cream and crackers) hold identically under all three, so nothing
rests on the choice except which folds look suspect.

So: run the fold test with `--weight=block`, and keep `03a` above the merge. `04` merges
`w_block` in rather than recomputing it, and `KGMAX` lives in `03a` with the computation
it belongs to.

Seeding the registry later — which is where it started — left a fresh clone needing two
passes to converge, the same circularity issue #33 was about.

**After any change**, run the verification master from the project root:

```
python dofiles/verify_pipeline.py
```

**This is the one command that says whether the pipeline on disk is the pipeline the code
describes.** Exit 0 means it is. It does five things:

1. **Rebuilds the crosswalk** into a scratch directory and compares content column by
   column — `master_nsu_rename.csv` is in neither master, so it can otherwise drift from
   its inputs with nothing noticing (#33).
2. **Accounts for the trim**: the rebuild is pre-trim and the live file post-trim, so the
   difference must be exactly the rows in `master_rename_dropped_labels.csv`.
3. **Re-runs `validate_folds.do`** and checks that no folded group contradicts its own
   weight test, per `../docs/master_rename.md` §6. Folds knowingly kept despite failing
   are listed in `ACKNOWLEDGED` with their recorded figures and the reason — and they
   fail again if those figures move, so an acknowledgement is not a mute button.
4. **Runs `verify_documented_claims.py`**, which re-derives every number recorded in
   `docs/` that no build file produces.
5. **Checks the input manifest** — `outputs/tables/build_manifest.json` holds a SHA-256
   of every hand-maintained input and headline output, so "these outputs came from these
   inputs" is answerable rather than assumed. After a deliberate rebuild, re-record it
   with `--update-manifest`.

**Hashes, not timestamps, and that is not fussiness.** A git checkout rewrites the mtime
of every file it touches, so a merge or a branch switch makes a stale artifact look fresh
and a fresh one look stale. An earlier version of check 3 was guarded on mtime and would
have passed over exactly the failure it exists to catch.

`verify_documented_claims.py` can still be run alone for the per-claim detail; the
verification master reports only its verdict counts.

**What it does not do:** re-run the Stata build. That would overwrite the artifacts it is
checking. Check 5 is what tells you those outputs still match their inputs.

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
| `03_clean_ms.do` | load, comments, normalize, **exclude non-NSU labels**, harmonize, identifiers. Calls 03a, 04 and 05. |
| `03a_block_reading.do` | the **block reading** `w_block` — typed weight in g/mL, kg tick not taken literally. Called from `03` *before* the crosswalk merge, deliberately: it reads only `weight`, `unit` and `KGMAX`, so everything the fold test needs is complete before any fold is applied. Owns `KGMAX`. Output: `block_reading.dta`, merged into `04`. See "Where the fold evidence is produced" above. |
| `04_unit_snap.do` | magnitude correction — kg→g, L→mL, decimal slips. Merges `w_block` in rather than recomputing it |
| `05_manual_corrections.do` | every hand-made weight/unit fix. §1–5 are one block per correction, each asserting its row count; **§6 applies the review ledger**, `reference/reviewed/snap_verdicts.csv`, which is where the bulk of the adjudicated decisions now live. See *Adjudicating a weight* below. |
| `06_cpi_panel.do` | province × item-group × month CPI panel, plus the item crosswalk and the spec's validation report. Stata port of a retired Python step (`archive/06_cpi_panel.py`), verified against its output before the switch |
| `07_cpi_factor.do` | drops 98 price-quantity rows whose recorded price was not the price handed over — 71 vendor-priced (a further 23 are rescued where they were the case's only rung) and 27 where the vendor gave no price at all. **The only place those rows are dropped, and both outcomes depend on it.** Builds `cpi_factor`. Output: `nsu_weighings_cpi.dta` |
| `08_branch.do` | derives `branch`, the variable the build slices on. Equals `weighing_approach`, except a conventional case whose (item, harmonized unit) pair mixes approaches elsewhere becomes size-based — 99 cases, 388 weighings. Also sets `d_reclassified`. Wired into both masters. |

**Two shared MODULES live in `00_shared/` alongside the steps.** Nothing runs them; they
are imported, and they are where two decision rules are defined once so no caller can
re-implement them differently.

| module | defines | imported by |
|---|---|---|
| `nsu_fold_rule.py` | **THE fold rule** — which raw spellings mean the same thing, and therefore what `harmonized_nsu_unit` is. Pure functions of (item, raw label), reading no build output, deliberately: the snap's anchor pool is keyed on `harmonized_nsu_unit`, so a fold that read corrected weights would close a loop (#33). Its carve-outs are the item-specific separations in `../docs/master_rename.md` §6, and **their provenance is not uniform** — see "Two different loops" below. | `01`, plus `90_diagnostics/fold_map.py` and `verify_documented_claims.py` |
| `nsu_normalize.py` | the one definition of the project's string normalization (`nz` / `ni` / `ng`). The Stata counterpart is the `nsu_normalize` program in `00_globals.do` and must agree with it character for character. **Never NFKD-decompose** — `DUEÑAS` becomes `DUEAS`, not `DUENAS`. | `01`, `02`, `nsu_fold_rule.py`, and 16 diagnostics |

There used to be eleven byte-identical copies of the normalizers across `90_diagnostics/`;
a fix to any one of them reached none of the others (#32). Import these, never copy them.

### Two different loops, and only one of them is real

"The snap depends on the harmonization and the harmonization depends on the snap" is
half true, and which half matters for what you can rely on.

**The runtime edge is forward-only, and is not a cycle.** Within one build the order is
fixed: `00a` assigns durable ids from the raw data, `01` builds the crosswalk from the
raw survey plus the price file plus that registry, `03` merges the harmonized unit at
§339, and the snap runs afterwards at §659. `03_clean_ms.do:370` is the *only* write to
`harmonized_nsu_unit` anywhere in the pipeline — every reference in
`05_manual_corrections.do` is a read-only lookup key. So the build is a DAG and it
reproduces: `verify_pipeline.py` check 1 rebuilds the crosswalk from raw inputs and gets
zero differing cells across 2,927 rows × 9 columns. Re-keying the snap's anchor would
remove this edge, and remove nothing that was a defect.

**The evidence edge is a real loop, and it is latched through a person.** Some carve-outs
were *decided* by looking at corrected weights — the snap's own output — and then frozen
by hand into `nsu_fold_rule.py` and the crosswalk workbooks:

```
a carve-out        (frozen in nsu_fold_rule.py / the crosswalks)
  ← a weight test  (90_diagnostics/validate_folds.do, van Elteren)
    ← corrected_weight
      ← 04_unit_snap.do
        ← harmonized_nsu_unit   (the snap pools its anchor on this)
          ← the carve-out
```

Nothing re-runs by itself, so a snap change cannot silently move a fold. What it can do
is leave a frozen carve-out contradicting the evidence that justified it — which has
already happened once, to the crackers `bilog` fold. **Re-keying the anchor does not
close this loop**, because the test still reads corrected weights. Testing folds on the
*block reading* instead — the typed number in canonical units, a function of the raw
weight, the unit tick and `KGMAX` alone — would. `04_unit_snap.do` keeps that reading as
**`w_block`** for exactly this purpose; it reads no harmonized unit, so a fold test built
on it is not circular.

`w_block` is also the single definition of the block reading. It used to be computed in
`04`, used, and dropped, so `snap_sense_check.py` and `compare_anchor_keying.py` each
carried a hand-written copy of the rule, scraping `KGMAX` out of the do-file. Both copies
checked that the *constant* still matched and neither checked the *branches*, so a change
to STEP 3a's `weight>=10` would have left them computing a rule the pipeline no longer
used — and `snap_sense_check.py` builds the workbook whose verdicts are frozen into the
ledger. Read `w_block`; never re-derive it.

`90_diagnostics/audit_weight_derived_folds.py` is the register of which decisions are
exposed. It reports provenance and how many weighings each governs; it does not re-run
the tests, because `validate_folds.do` owns those and a second copy would diverge.
Currently **1,277 weighings (11.3%)** have their final `harmonized_nsu_unit` set by a
weight-derived decision, plus 712 more where only `fallback_harmonized_nsu_unit` does.
The rest of the carve-outs rest on a stated referent difference, a quoted field comment,
or string normalization, and no snap change can touch them.

**`branch` vs `weighing_approach`, once `08` exists.** Use **`branch`** wherever the code
decides how a weighing is PROCESSED or PUBLISHED. Keep **`weighing_approach`** wherever it
describes WHAT THE FIELD DID. `weighing_approach` is never overwritten: it is the field
record, and the evidence for #28 is keyed on it — `scope_conventional_units.py` reading
`branch` would report no mixed pairs at all, which is the finding erasing itself. Getting
this backwards is a silent error in either direction. The site-by-site split is on #28.

## Running a variant build without touching the published one

`00_globals.do` takes a `${build_name}` override. Set it before the globals load and the
whole build — every `.dta`, table and graph — goes to `outputs/<build_name>/` instead of
`outputs/master_rename_build/`:

```stata
global build_name "anchor_pull_nsu_unit"
global unitvar    "pull_nsu_unit"
do "00_shared/03_clean_ms.do"
```

`90_diagnostics/measure_anchor_keying.do` is the worked example: it answers "would the
snap give different weights if its anchor pooled on the raw label instead of the
harmonized one?" by building the variant and leaving the published build alone, so the
two can be diffed with no backup-and-restore step. `outputs/anchor_*/` is gitignored.

**Which unit the anchor pools on.** `04_unit_snap.do` pools its anchor and all four
referee rungs on `pull_item × ${unitvar}`, defaulting to `harmonized_nsu_unit`. Three
candidates exist: the raw `pull_nsu_unit`, `cleaned_nsu_unit` (what the pre-Aug11 build
used), and the current harmonized unit. The choice matters beyond accuracy, because
`harmonized_nsu_unit` comes from the crosswalk while the fold decisions behind the
crosswalk came from corrected weights — a loop, and the reason `nsu_fold_rule.py` is
forbidden from reading a build output. Measured: re-keying to the raw label moves **17 of
11,335** corrected weights and 34 of 3,305 published rows, and scored against the typed
number the two keyings split 9–7. So it breaks the loop without improving the weights.

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

**Built.** `master_outcome2.do` runs end to end and converts PSPS household rows.

| | |
|---|---|
| household × item × slot rows | 87,959 |
| already in a standard unit (`27`, #14) | 52,489 |
| needing an NSU conversion | 35,448 |
| **converted** | **34,916 (98.5%)** |
| …at the matched price point | 28,961 |
| …on a fallback rung | 5,955 (L1 110, L2 5,484, L3 361) |
| refused | 532 — A11 spelling gap 304, unique price 117, nothing anywhere 111 |

`26_psps_extract.do` was archived: it did vocabulary discovery — which NSU labels PSPS
households use — that job is finished and now lives in the crosswalk, and it dropped
`hhid` and `subdate`, so it could not serve either thing Outcome 2 needs from PSPS. See
`../archive/README.md`.

**Run order matters in two places and nowhere else.** `20a` must precede `24` (it writes the
month list) and `30` must precede `28` (it writes the three fallback schedules `28` climbs).
Everything else is independent.

**`26` is deliberately missing from the numbering.** `26_psps_extract.do` is archived — it did
vocabulary discovery, that job is finished and lives in the crosswalk, and it dropped `hhid` and
`subdate`. `20a` replaces it. The gap is kept so the step numbers cited on #19, #21 and #23 still
resolve.

| step | does |
|---|---|
| `20a_psps_households.do` | the household side of PSPS — one row per household × item × acquisition slot, keeping `hhid`, `subdate`, quantity and expenditure, normalized into the crosswalk's vocabulary. Classifies every unit label into exactly one of five conversion paths, asserted exhaustive and mutually exclusive. Also owns the **standard-unit gram table** (#14) and the month list `24` needs. `p_h` comes from the **purchased slot only** (A10) |
| `20_case_price_points.do` | which price points a case gets: union on the peso value across weighed spellings, single-linkage merge within ₱20, merged point takes the mean (#21 §2). Owns the **`unique_mun_price` refusal** (A16) and builds A11's spelling-price gap flag |
| `21_branch_size_based.do` | cuts each case's pooled weights into `n_points_conv` parts, lowest weights to the lowest price. The 99 reclassified cases are **never cut** (A12). Also emits the points that no group can serve, so a household can match one and be refused |
| `22_branch_price_quantity.do` | `w_g` per case × `pull_price`. The price file is not read: every distinct peso amount is its own group, no merge (#21 §2 rows 5–6) |
| `23_branch_conventional.do` | one weight per case, for the **24** cases whose (item, unit) pair is conventional everywhere it appears (#28). The other 99 join Branch S |
| `24_inflate_to_psps_month.do` | `w_g_m`, `v_g_m` per interview month — **Branch P only**, crossed with the months of its own municipality |
| `25_lookup.do` | appends the three branches, and builds #11's no-inflation variant as a second file |
| `27_standard_units.do` | kg / L / stated-quantity answers convert from the unit's own name, with no market-survey input (#14) |
| `28_match_and_convert.do` | the household join: nearest point, tie on `v`, `CF_h`, `grams_h`. Climbs cell → province → national for the households the price match cannot serve |
| `29_cap.do` | clamps `p_h/p_g` to `[1/t, t]` and flags, `t = 5` (A18) |
| `30_fallback.do` | the **weight ladder**, three ways. Per (cell × size): **L0** the cell's own rung → **L1** the cell pooled across sizes → **L2** province × item × unit → **L3** item × unit nationally → unconvertible. Per cell, for when the price match fails. And **L2 and L3 on their own keys**, which is the only reading that can serve a cell the market survey never visited — #30's actual population, one PSPS observation in six |

**#30 was the gate and it is now built.** Note that its cost argument was written against a 14×
cross-municipality spread; the corrected figure is **6.7×**, so read it against that.

**Not build steps, and still open:** #20 (approach A vs B, needs `psps_converted_capped.dta`),
#11 (compare the two lookups' household grams — both are built), #16 (Outcome 1 against Outcome 2,
answerable for the first time).

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
unique is reading an order the sort seed chose. **The pipeline had one such construction and
no longer does:** `10_size_assignment.do`'s running total over label tags (#18 A7) is now
`egen lbl_grp = group(field_ord), by(cell)`, which does not depend on within-group order.
Verified answer-preserving on all 9,758 size-based rows.

Two places still read a within-group order deliberately, and both sort on something unique
first so there is nothing for the seed to break: the price-point clustering in
`20_case_price_points.do` (sorted on `p_g`, which the ₱20 merge makes distinct within a case)
and the match in `28_match_and_convert.do` (`gsort hh_row _rankkey -v_use group_id`).
