# Pipeline layout

**This file is the living map of the pipeline** — what exists, what runs in which order,
and which steps are still unwritten. Update it when a step lands, not when a decision is
made; decisions live in the issue that owns them and in `../docs/`.

Three companions, and they do not overlap:

- **`../docs/implicit_assumptions.md`** — every hard-coded threshold, tie rule and
  fallback, and what each one claims about the data. **Read it before changing any
  constant in a do-file.**
- **`../docs/conversion_factor_methodology.md`** — what the method is and why, including
  the assumptions the method itself makes.
- **`../docs/adjudication_playbook.md`** — how to put judgement calls in front of a
  reviewer. **Read it before building any review artifact.** Two efforts in this project
  — the harmonization review and the unit-snap review — consumed a large share of the
  total time, mostly by being re-done; that file is why a third one need not be.

Two deliverables are built from the same market-survey weighings:

- **Outcome 1 — the reference set.** Grams by size for each province × municipality ×
  item × harmonized NSU unit, so a future enumerator can look up what a named local
  unit weighs. Built and live.
- **Outcome 2 — PSPS retro-fitting.** Conversion factors that turn PSPS household
  quantities into grams, and the household answers themselves. Built and live; the step
  table under *`20_psps_retrofitting/`* below says what each step does.

They share everything up to a clean, inflation-framed weight per weighing, then
diverge: Outcome 1 slices weighings by the **size** the field recorded, Outcome 2 by
the **price points** the price file holds. Neither output is derivable from the other
— the same case can yield three sizes in one and a single weight in the other.

## Running it

```
cd ".../Data Cleaning/dofiles"
"C:\Program Files\StataNow19\StataSE-64.exe" -e do master_outcome1.do
"C:\Program Files\StataNow19\StataSE-64.exe" -e do master_outcome2.do
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics\sense_check_outputs.do
```

The third line is not part of the build. It reads what the first two published and asks
whether the numbers are plausible — see *Checking the two deliverables* below.

**`stata -e` exits 0 even when a do-file errors.** Check the log for `r(` followed by a
number and a semicolon; an exit status of 0 is not evidence the build ran.

**The working directory must be `dofiles/`.** Each step reaches `00_shared/00_globals.do`
by a relative path, because the globals that would give it an absolute one are what
that file defines.

Any step can also be run on its own once an earlier one has run at least once — each
writes a `.dta` the next one reads.

Five prerequisite steps are not run from the masters. They build the id registry, the
crosswalk and the CPI panel, and they change rarely. Run them when their inputs change.

**They do not all run from the same directory, and the commands below are written for
where each one actually works.** The three Stata steps reach `00_shared/00_globals.do` by
a relative path, so like every other do-file here they need the working directory to be
`dofiles/`. The two Python steps take a path *from the project root*.

From `dofiles/`:

```
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\00a_weighing_ids.do
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\00b_price_ms_cases.do
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 00_shared\06_cpi_panel.do
```

From the project root, between `00b` and `06`:

```
python dofiles/00_shared/01_build_crosswalk.py
python dofiles/00_shared/02_drop_non_nsu_labels.py --apply
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
| `20_psps_retrofitting/` | Outcome 2 |
| `90_diagnostics/` | scoping, auditing and reporting. Never on a critical path. |
| `archive/` | superseded. Nothing calls it. `archive/README.md` says why each file is there. |

## Where a build's output lands

Every do-file writes under `outputs/<build_name>/` — `outputs/build/` for
the published build, some other subtree for a variant (see *Running a variant build*
below). Five folders, split by what a reader needs to know before opening a file:

| folder | macro | what it holds |
|---|---|---|
| `deliverables/` | `${bdeliv}` | the published objects — the reference set, the two Outcome 2 lookups, and the household-level PSPS files — each with the `.xlsx` or `.csv` export that ships beside it |
| `intermediate/` | `${btemp}` | every other `.dta` a step writes and a later step reads. Not meant to be opened by anyone who is not debugging the pipeline itself |
| `summary/` | `${bsummary}` | sense checks, summary statistics, the attrition ledger and the pipeline explorer — material that describes the build rather than being part of it |
| `diagnostics/` | `${btables}` | issue-specific scoping tables and review workbooks. Never a dependency of another step |
| `graphs/` | `${bgraphs}` | analytic figures meant to be read on their own |

A reader looking for a specific file: the deliverables are the eight objects the two
masters exist to produce (`nsu_reference_set.dta`/`.xlsx`, `outcome2_lookup.dta`/`.csv`,
`outcome2_lookup_noinflation.dta`, `outcome2_lookup_heteroblind.dta`/`.csv`,
`psps_converted_capped.dta`, `psps_standard_units.dta`, `psps_grams.dta`/`.csv`,
`psps_grams_heteroblind.dta`/`.csv`) and live in `deliverables/`; anything else that ends in `.dta`
lives in `intermediate/`; a sense-check CSV, a summary-statistics table, the attrition
ledger or `nsu_pipeline_explorer.html` lives in `summary/`; everything else that used to
be in a folder called `tables/` — one-off scoping exports, review queues — is in
`diagnostics/`.

The macro names keep their old spelling (`${btemp}`, `${btables}`) even though the
folders they point at are no longer called `temp/` and `tables/`: repointing a macro to a
renamed folder is a one-line change in `00_shared/00_globals.do`, and every do-file that
already reads `${btemp}` or `${btables}` needed no edit at all.

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
| `08_branch.do` | derives `branch`, the variable the build slices on. Equals `weighing_approach`, except a conventional case whose (item, harmonized unit) pair mixes approaches elsewhere becomes size-based — 99 cases, 388 weighings. Also sets `d_reclassified`, and **owns the three uncertainty flags** (`d_unusable`, `d_disputed`, `d_any_uncertain`) that both deliverables publish — a fourth, `d_step1_flagged`, was retired because it described the anchor's confidence in a decade shift the anchor no longer performs — see *The uncertainty is carried through* below. Wired into both masters. |

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
`04`, used, and dropped, so `snap_sense_check.py` and the since-deleted
`compare_anchor_keying.py` each
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
`outputs/build/`:

```stata
global build_name "anchor_pull_nsu_unit"
global unitvar    "pull_nsu_unit"
do "00_shared/03_clean_ms.do"
```

`90_diagnostics/measure_anchor_keying.do` is the worked example: it answers "would the
snap give different weights if its anchor pooled on the raw label instead of the
harmonized one?" by building the variant and leaving the published build alone, so the
two can be diffed with no backup-and-restore step. `outputs/anchor_*/` is gitignored.

**Which unit the anchor pools on.** `04_unit_snap.do` pools its anchor and all five
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
| `21_branch_size_based.do` | cuts each case's pooled weights into `n_points_conv` parts, lowest weights to the lowest price. The 99 reclassified cases are **never cut** (A12). **It also writes out the price points that ended up with no weighing behind them** — 495 of them, either because the cut's upper part came back empty or because the price was a refused unique price. They stay in the lookup deliberately: a household matches the *nearest* price point, so deleting an empty one would slide that household onto the next point along and convert it at a weight belonging to a different size. Keeping it means the household matches the empty point and is refused, which is the honest outcome |
| `22_branch_price_quantity.do` | `w_g` per case × `pull_price`. The price file is not read: every distinct peso amount is its own group, no merge (#21 §2 rows 5–6) |
| `23_branch_conventional.do` | one weight per case, for the **24** cases whose (item, unit) pair is conventional everywhere it appears (#28). The other 99 join Branch S |
| `24_inflate_to_psps_month.do` | `w_g_m`, `v_g_m` per interview month — **Branch P only**, crossed with the months of its own municipality |
| `25_lookup.do` | appends the three branches, and builds #11's no-inflation variant as a second file |
| `27_standard_units.do` | kg / L / stated-quantity answers convert from the unit's own name, with no market-survey input (#14) |
| `28_match_and_convert.do` | the household join: nearest point, tie on `v`, `CF_h`, `grams_h`. Climbs cell → province → regional for the households the price match cannot serve. **§6b** builds the hetero-blind counterfactual from the same rung tempfiles — `cf_h_blind`, `grams_h_blind`, `fallback_level_blind` — so no median is recomputed |
| `29_cap.do` | clamps `p_h/p_g` to `[1/t, t]` and flags, `t = 5` (A18) |
| `31_psps_grams.do` | **the single household-level deliverable.** Appends `psps_converted_capped.dta` (35,448 NSU rows) and `psps_standard_units.dta` (52,489 standard-unit rows) — they share 23 columns and do not overlap — and adds the 22 `conv_path == 3` rows (reach the crosswalk join, judged not an NSU at all) that ship in neither, so the row count reconciles to 20a's own 87,959, not to 87,937. Publishes `psps_grams.dta` and a labeled `psps_grams.csv`, and **§6b** the hetero-blind drop-in `psps_grams_heteroblind.dta`/`.csv`, where `grams_h` *is* the blind number so no column has to be renamed to run the counterfactual. The labeled-CSV writer is the `_labeled_csv` program, defined once and called for both |
| `30_fallback.do` | the **weight ladder**, three ways. Per (cell × size): **L0** the cell's own rung → **L1** the cell pooled across sizes → **L2** province × item × unit → **L3** item × unit regionally → unconvertible. Per cell, for when the price match fails. And **L2 and L3 on their own keys**, which is the only reading that can serve a cell the market survey never visited — #30's actual population, one PSPS observation in six. Also publishes the cell-grain ladder as `outcome2_lookup_heteroblind.dta`/`.csv` — 1,986 rows on the five-column key — since it answers a question on its own |

**#30 was the gate and it is now built.** Note that its cost argument was written against a 14×
cross-municipality spread; the corrected figure is **6.7×**, so read it against that.

### Multiple price points inside one harmonized unit (#21) — which file does what

Folding two `pull_nsu_unit` spellings into one `harmonized_nsu_unit` can pull their price
points together into a single cell. The two spellings' MP25/MP50/MP75 need not line up, so
a cell can arrive holding more points than the S/M/L ladder has rungs. **The collision is
created by the fold, not by the field** — measured, no raw `pull_nsu_unit` ever carries two
price types on its own.

**It affects both outcomes, and each fixes it in a different file.** Read these four in order:

| file | outcome | what it does about #21 |
| :-- | :-- | :-- |
| `20_case_price_points.do` §7 | both | **Merges the points first.** Single-linkage within **`PMERGE` = ₱20**, so points that are close in price become one. This is what stops a 6-point cell existing at all, and it runs before anything cuts or converts |
| `21_branch_size_based.do` | Outcome 2 | **Guards the result.** The cut has branches for 1, 2 or 3 groups, so a 4-point case would leave rows unassigned; the file stops instead. An *implementation* limit, not a methodological one — see below |
| `10_size_assignment.do` §2b | **Outcome 1** | **Orders the survivors.** Where a fold leaves a cell holding a municipality median *and* a province median, both of which map to `medium`, they publish as two rungs ordered by price — cheaper `small`, dearer `large` — instead of one averaged row |
| `10_size_assignment.do` §2b-ii | **Outcome 1** | **Halts on duplicate quartile labels.** §2b's repair works for medians because they all map to `medium`, leaving `small` and `large` free; `mp25`/`mp50`/`mp75` already occupy all three rungs, so two `mp25` points at different prices have nowhere to go. Widen `PMERGE` or revisit the fold — both decisions above this file. Zero occurrences now; see A2 |
| `20_case_price_points.do` §7 (A11) | Outcome 2 | **Refuses the tail.** A priced-but-unweighed spelling more than **2.0×** from its cell's weighed price is not converted; 304 household rows are refused on this |

**This matters for Outcome 1 — it is not an Outcome 2 problem only.** Without §2b, the two
live cases published a single averaged row: at NEGROS OCCIDENTAL / VALLADOLID a 325 g group
and a 780 g group became one 425 g `medium`, with nothing on the row saying two genuinely
different quantities had been averaged. The ordering has to come from **price**, not
geography — the province median is the dearer point for cabbage and the cheaper one for
carrot, so no "municipality beats province" rule gets both right.

**Inflation does not enter any of this.** The merge is step `20` and the CPI factor is
applied at step `24`, so grouping is fixed before any price is restated. The ₱20 threshold
is therefore in market-survey-period pesos.

**Why a 4-point case stops the build instead of being cut into quartiles.** The cut in
`21_branch_size_based.do` has branches for `k_use` of 1, 2 and 3; a 4 would leave `grp`
missing and those rows silently unassigned, so the file exits. That is an implementation
limit — this file does not use the field's S/M/L labels at all, and four price points are
no harder to reason about than three. Adding a quartile branch would be about four lines.
It is deliberately not done, for two reasons:

- **Nothing would exercise it.** `n_points_conv` has never exceeded 3, so the branch would
  ship untested.
- **A fourth rung buys resolution the data cannot support.** The nearest live case, ILOILO
  / CARLES chicken, holds 10 weighings; three ways that is about 3 per group, already on
  `THIN`, and four ways it is 2.5, putting most groups below the threshold.

That case is also why the guard looks unreachable and is not. It has **four** price points
after the ₱20 merge — ₱200 (mp25), ₱240 (mp50), ₱336.25 (mp75, two merged) and ₱380 (a
unique price). It passes only because ₱380 has no weighing behind it, so `n_points_conv`
is 3 and the household matching ₱380 is refused rather than cut against. A vintage that
weighs that fourth point reaches the guard for real.

**How far the pile-up actually goes, and what stops it.** Four is the live maximum after
the merge, not the ceiling of the problem:

| stage | max points in one case |
| :-- | --: |
| raw price points, as the price file supplies them | **11** |
| after the ₱20 single-linkage merge | 4 |
| convertible — points with a weighing behind them, which is what the cut sees | 3 |

**Two mechanisms in series hold the cut at three, and neither was designed as a bound.**
The merge reduces the point count in 358 cases; the convertibility filter removes the
rest. Twenty cases carry 4 or more raw points, and **17 of those 20 fold two or more
spellings** — so harmonization really is the driver at the top end, which is what #21
said. The exception is the largest case of all: NEGROS OCCIDENTAL / PONTEVEDRA / cabbage
/ `pieces or units` reaches 11 raw points from a **single** spelling, `bilog`, whose
municipal quotes simply span a wide range. Eight of them collapse into one ₱33.28 point.

The margin to the guard is therefore one unweighed price point, in one case. If that
concerns you, the lever is `PMERGE`, not the cut: a wider tolerance merges more and pulls
the maximum down; a narrower one pushes cases into the guard.

### The hetero-blind pair: what the price/size matching is worth

`outcome2_lookup_heteroblind.dta`/`.csv` and `psps_grams_heteroblind.dta`/`.csv` are the
same pipeline with **within-NSU heterogeneity removed entirely** — one conversion factor
per province × municipality × item × harmonized unit × `corrected_unit`, and every
household in a cell gets it whatever it paid and whatever size it bought.

They exist because matching a household to its own size rung by price is the most
consequential thing Outcome 2 does — it resolves 81,377 household rows — and the build
otherwise has no way to say how much it moves. The variant is identical in every other
respect, so **a difference between the two files is the price/size matching and nothing
else.** Read them as a robustness object, not a better answer: this is A15's cost applied
universally, and nothing downstream should prefer the blind file without saying why.

| | headline | hetero-blind |
|---|---|---|
| converted NSU rows | 34,893 | 35,019 |
| rung: L0 / L1 / L2 / L3 | 81,377 / 118 / 5,522 / 365 | — / 23,791 / 10,823 / 405 |
| **total grams over comparable rows** | 27,349,919 | **34,496,233 (126.1%)** |
| rows larger / smaller / identical | — | 20,598 / 6,155 / 8,118 |

**Going blind raises household grams by about a quarter**, median row ratio 1.154. The
matching is therefore pulling households toward *smaller* units on balance — which is
what you would expect if purchases skew to the cheap end of each NSU, and is the substance
of what the blind file gives up.

Two asymmetries are deliberate and asserted in `28_match_and_convert.do` §6b:

- **A11 spelling-gap refusals survive.** The objection is that the household's NSU label
  may not name the object the market survey weighed; that is unaffected by removing the
  price match, so those 304 rows are refused in both files.
- **"unique price" refusals do not.** That refusal says a price point had no weighing
  behind it — an obstacle only the price match faces. 148 rows are legitimately served in
  the blind file and refused in the headline one.

The five-column key is not optional: 65 cells hold both a gram and a millilitre reading,
and `corrected_unit` is what keeps those apart. The ladder still climbs — 1,473 cells
serve themselves, 474 borrow their province, 25 the region, 14 get nothing — so both files
cover the same cells.

**Not build steps, and still open:** #20 (approach A vs B, needs `psps_converted_capped.dta`),
#11 (compare the two lookups' household grams — both are built).

### Joining the grams back onto PSPS consumption

**The key is `hhid` + `psps_item_code` + `slot`**, asserted unique on those three.

The raw PSPS consumption file is **wide by slot** — one row per (`hhid`, `item`), unique on
that pair, with three sets of columns for the three acquisition routes. `psps_grams` is
**long**, one row per slot that recorded something. So the merge is `m:1`:

```stata
use "<psps_grams.dta>", clear
rename psps_item_code item
merge m:1 hhid item using "${psps_cons}", keep(1 3)
```

**`m:1`, not `1:1`.** A household that both bought and was gifted the same item is one raw
row and two rows here — 340 (household × item) pairs are in that position, and a `1:1`
merge fails on them while a `1:m` in the other direction silently multiplies grams.

`slot` names which raw columns the row came from: **2** purchased (`fd_cons_2a`,
`fd_cons_2b`, 68,100 rows), **3** own production (`fd_cons_3a/3b`, 15,971), **4** gift
(`fd_cons_4a/4b`, 3,888). `q_h` is `fd_cons_<slot>a`; `p_h` is `fd_cons_<slot>b / q_h`.

Four things worth knowing before you use it:

* **Not every raw row yields three rows.** A slot appears only if it recorded a usable
  quantity — non-missing and non-zero. 245,051 raw rows → 129,094 food rows
  (`item_type == 1`) → **87,959** slot rows.
* **Do not key on `hh_row`.** It is assigned by a sort and is stable only *within* a build.
  It exists for joining one build's intermediates to each other.
* **Filter on `d_converted`, not on `grams_h > 0`.** 554 rows have no grams — 532 refusals
  plus the 22 non-NSU rows — and `conv_route` says which and why. Filtering on `grams_h`
  throws the reason away.
* **To reach household × item, sum over `slot`.** `cf_h` and `p_h` are per-unit rates and
  must not be summed.

`conv_path` separates two different kinds of number: **1** (52,489 rows) is a stated
container size × a reported count, arithmetic with no market survey in it; **2** (35,448)
is `q_h × CF_h`, the conversion this project exists to produce; **3** (22) is not an NSU
and has no grams. The uncertainty columns are populated on path 2 only, and are missing
rather than zero on path 1 — there is no weighing behind a standard unit to have
questioned (A20).

`docs/conversion_factor_methodology.md`, *Joining the grams back onto PSPS consumption*,
has the same account with the full column table.

### Checking the two deliverables

**`31_psps_grams.do` is now the single household-level artefact for Outcome 2.**
Before it, "grams for a PSPS household consumption row" had no single file and no
non-Stata export: it was split across `psps_converted_capped.dta` (the NSU rows)
and `psps_standard_units.dta` (the standard-unit rows), which share 23 columns and
never overlap. `psps_grams.dta` / `psps_grams.csv` append the two and add the 22
`conv_path == 3` rows — reaching the crosswalk join but judged not an NSU at all —
that shipped in neither, carrying missing grams and a route that says why rather
than disappearing from the count. A reader wanting one household x item x slot row
per PSPS food observation, with its grams or the reason it has none, reads this
file; the two inputs above remain the place to read a route's own diagnostic
columns (price points, fallback rungs, the cap ratio) that this file does not carry.

Two diagnostics exist for the questions "does it rebuild?" and "is the answer sensible?".
They are separate because a build can reproduce byte for byte and still be wrong by a
factor of ten, and nothing in the reproduction check would notice.

| file | asks |
|---|---|
| `90_diagnostics/test_full_rebuild.do` | **does the pipeline reproduce from the raw files?** Sets `${build_name}` to its own subtree, clears it, runs both masters from the raw market survey, price file and PSPS file, then compares every published dataset against the live build on row count, variable count and a hex-float sum of every numeric column. Hex float rather than a decimal sum because `local x = r(sum)` truncates a double to about 13 significant digits, which hides a difference in the last bits. Writes `outputs/tables/test_full_rebuild_diff.csv`; its build tree is gitignored |
| `90_diagnostics/sense_check_outputs.do` | **is the answer plausible?** Reads only published outputs, plus household size from the raw PSPS file, which the pipeline does not compute. Four sections: Outcome 1's reference grams by item, Outcome 2's conversion factors by fallback rung, the two deliverables on the same cells (#16), and implied grams per person per day — the one check with a referent outside the pipeline. Writes four CSVs and four panels, all to `summary/` |

**Read `sense_check_outputs.do`'s section 4 first if something looks wrong.** Sections 1–3
judge the outputs against other outputs from the same build, which cannot catch an error
shared by all of them. Section 4 leaves the pipeline: it asks whether the implied food
intake is an amount a person could eat.

Two things the sense check has established, worth knowing before reading it:

* **Its implausible tail is upstream.** Every household above 10 kg per person per day is
  a *standard-unit* report — a reported count of 5-gallon water containers, or 250 kg of
  pork — where the conversion is a stated container size times a reported count. An
  implausible total there is an implausible reported quantity, not a conversion error.
  The `route` column in section 4b separates the two.
* **The borrowed rungs' higher medians are mostly composition.** L2 and L3 sit about 1.7×
  above L0 on the raw comparison, but a borrowed rung is used exactly where the cell had
  no weighings, so the comparison mixes rungs with baskets. Holding (item × harmonized
  unit) fixed, the high-volume pairs come back to 0.92–1.09. What survives is concentrated
  on labels that do not pin down a quantity in the first place — `pieces or units`,
  `small packs` — which is a limit of the fallback ladder rather than a defect in it.

**The uncertainty is carried through (#35).** Roughly one weighing in seven is disputed,
anchor-flagged or unusable, and both deliverables now say so per published row.

`08_branch.do` owns the definition — four flags read off `corrected_weight`, `snap_block`
and `review_step1`, all of which the build already carries. It is defined there because
`08` is the last step both masters share, so one definition reaches both deliverables and
neither can re-implement it differently.

| output | columns |
|---|---|
| reference set | `n_disputed`, `n_uncertain`, `share_uncertain` |
| `outcome2_lookup` (and the no-inflation variant) | the same three |
| converted household rows | `nu_used`, `share_uncertain`, taken **at the fallback rung that supplied the weight** |

That last row is the part that needed care. A household served by a province pool must
inherit the uncertainty of the pool it got, not of its own cell — so the ladder computes
`nu_l0`…`nu_l3` and `30_fallback.do` picks `nu_used` in the same `replace` as
`grams_used`, with an assertion per rung that the two came from the same place. A count
from one rung printed beside a weight from another is the mislabel class closed in
`12_publish_reference_set.do` section 5c.

**Read the counts, not a dummy.** 27.7% of reference-set rows rest on at least one
questioned weighing but only 7.6% rest entirely on them, and the median row sits on four
weighings. `share_uncertain == 1` is the signal worth acting on.

**Nothing is dropped or down-weighted.** The columns let a reader apply a tolerance; the
build applies none. A20 says why the three kinds of doubt are not weighted against each
other.

**The coarser fallback rungs are not cleaner than L0, but do not overstate the gradient.**
Per household row the mean `share_uncertain` runs L0 0.120 → L2 0.195 → L3 0.384; pooled
over the weighings themselves it runs 0.121 → 0.148 → 0.148, because L2 and L3 draw on much
larger pools (median 60 and 21 weighings against L0's 4). Both are correct and they answer
different questions — A20 states both with their formulas. Quote neither without naming the
aggregation.

`90_diagnostics/report_weight_corrections.py` still writes
`weight_correction_report.csv`, which the pipeline explorer reads — but it now **reads**
these flags from the build instead of deriving its own copy, so the report and the
deliverables cannot disagree. It keeps `magnitude_corrected` and `decades_moved`, which
are its own and are not needed downstream.

## Adjudicating a weight: the snap review loop

> **This loop is now rarely needed, and that is a recent change.** The snap publishes the
> **block reading** — the typed weight in canonical units — on 11,402 of 11,421 rows, and
> the 19 exceptions are all existing hand decisions. The referee ladder in `04` decides
> **nothing** on this vintage. Two changes did that: `03a_block_reading.do` repairs the
> misplaced decimal that produced most of the genuinely unreadable rows, and STEP 3e-v-b
> consults the ladder only where a block reading is impossible. What follows is still the
> mechanism for overriding a weight, and the ledger still wins over any rule — there is
> just much less for it to do. See *The block reading governs* in the methodology.

`04_unit_snap.do` decides magnitude by rule. A reading it cannot settle goes to a human,
and the loop that does it is:

1. **`python dofiles/90_diagnostics/snap_sense_check.py`** writes
   `outputs/build/diagnostics/snap_sense_check.xlsx`. Open the **`to_review`**
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
- **A verdict that matches no row in the current build blocks the ledger write.** The
  ledger is rebuilt from the rows the script is looking at, so a verdict whose row has
  moved out of that set would simply be absent from the new file — warned about, then
  deleted. It now raises instead, writes the workbook, and leaves the ledger alone. This
  was not hypothetical: the misplaced-decimal repair moved two TIGBAUAN rows and a
  regeneration took the ledger from 227 verdicts to 225. Both were still applied by `05`,
  whose key is `item_nsu_hetero_type` and did not move, so the build stayed correct and
  only the regeneration was wrong.
- **The ledger is rewritten in full from the archive on every run, never appended.** That
  makes it idempotent. Do not hand-edit `snap_verdicts.csv` — the next run overwrites it.
  Across review rounds a later verdict overrides an earlier one on the same row, which is
  how a decision gets revised; a conflict *within* one round halts the run instead.

`verdict_landed` in the workbook says whether each past verdict actually reached the
published value, so a decision cannot fall out of the build unnoticed.

**What is left to adjudicate, and what the 227 existing verdicts now mean.** Five rows
have no block reading at all — a zero or missing raw weight — and fall to the anchor;
they are the only rows the ladder decides. Everything else publishes what the enumerator
typed. Of the 227 verdicts already in the ledger, **200 chose the block reading**, which
is what the rule now does unaided; they are no longer doing work but are kept, because a
verdict that stops being needed is not a verdict that was wrong. The **21 that chose the
anchor still override the rule** and are the reason the ledger is applied after `04`
rather than folded into it.

**Five verdicts now disagree with a block reading that has since changed.** The
misplaced-decimal repair moved 41 rows; 12 carry a verdict; 7 of those 12 independently
arrived at the same ×10⁶ reading the repair now produces, which is good corroboration.
The other 5 were decided when the choice was between 2 mL and 183 mL — 1,830 mL was not on
the table — and they still win. That leaves one raw pattern resolved two ways in the
published file. Re-review those 5 or retire them; do not leave it implicit.

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
`outputs/build/intermediate/nsu_weighings_cpi.dta`**; anything reading
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
