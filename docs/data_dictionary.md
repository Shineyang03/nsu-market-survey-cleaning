# Data dictionary — NSU price↔MS matching outputs

Produced by `dofiles/00_shared/01_build_crosswalk.py`. All string keys are normalized the same way as the
Stata pipeline: lowercase + trim + **drop** non-ASCII (`ustrto(.,"ascii",2)`, mode 2 drops rather
than transliterates); province/municipality are UPPER-cased, not lowercased.

**Matching architecture (rename-first, raw-sourced):** every unit — price *and* MS — is mapped to a
`cleaned_nsu_unit` via `nsu_rename_crosswalk.xlsx` (with weight-test corrections, e.g. ice-cream/
crackers `putos` kept out of `pack`), trying in order: exact `(item, unit)`, `(item, reduce_unit(unit))`,
then a fuzzy (word-order/typo) match against that item's rename keys; strings the rename doesn't cover
fall back to the heuristic canonical. The MS cell inventory is built from the **raw `pull_nsu_unit` in
`${data}`** re-cleaned by this same rename — NOT `nsu_data`'s `cleaned_nsu_unit`, which bakes in the old
(uncorrected) rename and contaminates weights. Conversion weights (`corrected_weight`) come from
`nsu_data`, keyed on its **raw** `pull_nsu_unit` re-cleaned the same way. A price unit harmonizes to an
in-cell unit when they share a `harmonized_nsu_unit`. Inputs: `${data}` (raw units), `nsu_rename_crosswalk.xlsx`,
`nsu_data.dta` (weights only).

**Mixed-vegetable class:** units the rename maps to `Putos (mix vegetable)` (e.g. `mixmix`,
`putos (halo-halo)`, `pack of mixed vegetables`, `putos /mix mix`) share that harmonized unit, so a
mixed price unit matches a mix unit already in the cell rather than being dropped.

---

## `outputs/tables/unit_fold_map.csv` — the fold map (step 3: `cleaned_nsu_unit` → `harmonized_nsu_unit`)

One row per `(item, cleaned_nsu_unit)` observed in the cleaned MS data (`nsu_data.dta`). Defines
which labels share a referent and may be pooled for conversion factors.

| column | definition |
|---|---|
| `item` | `pull_item`, normalized. |
| `label` | `cleaned_nsu_unit`, normalized. The thing being folded. |
| `harmonized_nsu_unit` | The within-item unit this label folds to — the **pooling key** `(item, harmonized_nsu_unit)`. For safe-fold groups this is the translation-group name (e.g. `pieces or units`); for keep-separate / reassigned / ungrouped labels it is the label itself. |
| `fold_verdict` | Why the harmonized unit was chosen — see the table below. |
| `dimension` | Measurement dimension of `corrected_weight`: `mass(g)` or `vol(mL)`. |
| `n` | Number of MS weighing observations for this `(item, label)`. |
| `median_g` | Median `corrected_weight` (in the row's dimension). |

**To apply (step 3):** normalize `cleaned_nsu_unit`, join on `(item, label)`, read `harmonized_nsu_unit`.
Keep the raw/cleaned label; `harmonized_nsu_unit` is a derived pooling key, not a destructive rename.

### `fold_verdict` values
| value | meaning |
|---|---|
| `safe-fold` | Folds to its translation-group unit; the weight test **confirmed** the variants share a referent. |
| `keep-separate` | In a translation group, but the weight test showed the variants are **different referents** — not folded: `bugkos`/`bundle` stay apart; `putos`/`pakete` stay apart. Exception: `pack`≡`packs` (singular/plural of one word) **are** merged to `pack`. Harmonized unit = itself (or `pack` for pack/packs). |
| `reassigned-separate(item-specific)` | Would fold by group, but for **this item** it is a different referent and was pulled out (`bilog` on chicken / preserved meat → whole-ish piece, kept its own harmonized unit). |
| `kept-separate(low-confidence weight test)` | Would fold by group, but the size-stratified weight test flagged a difference on **too little data to be confident** (e.g. camote `bilog` vs `binilog`: p=0.004 but only 3 strata). Policy: when confidence is low, do **not** fold — the whole group is kept unfolded for this item. |
| `fold(untested/minor-flag)` | Folded to the group unit, but the weight test **could not test it** (too few co-occurring obs: `whole (chicken)`, `small cup`) or had a **minor** flag (`small packs`). These fold on the official-translation basis only; flagged for review. |
| `identity(ungrouped)` | Not in any translation group; its own harmonized unit. Free-text / one-off units. |

---

## `outputs/temp/cases_in_price_not_in_MS_diagnosed.csv` — Price-Only case diagnosis

One row per `(province, municipality, item, unit)` present in the **price** data but not in the raw
**MS** data (949 cases). Explains *why* each is missing and *how* it resolves to a weight.

| column | definition |
|---|---|
| `province`, `pull_municipal_city`, `cons_name`, `unit_lbl` | The price-only case key (normalized). |
| `harmonized_nsu_unit` | Single "maps-to" target — the **pooling key** for the conversion factor. Cause 3: the harmonized unit of the in-cell unit it folds to. Cause 2: the label's own harmonized unit. Cause 1 **unmappable**: `.c` (Stata missing). Cause 1 **recoverable** (quantity-prefixed, e.g. `14 tasa`): the base unit (`tasa`); count multiplier in `detail`. |
| `fallback_harmonized_nsu_unit` | **Cause 2 only** (blank otherwise). If a translation-group sibling that was kept separate from this unit on weight grounds (e.g. `bundle` vs `bugkos`) is nonetheless **present with data in this exact cell**, its harmonized unit is surfaced here as the best locally-available conversion target. Use only as a fallback when `harmonized_nsu_unit`'s own pool is too thin for this cell/item — it does **not** change `harmonized_nsu_unit`, which stays the item-conditioned, cell-independent pooling key. Blank when no such in-cell sibling exists (most cause-2 rows: the item is simply absent from the cell). |
| `fold_verdict` | Provenance of the fold — see table above. |
| `in_MS_as` | For harmonizable cases, the **concrete MS unit already present in the same `(prov,mun,item)` cell** that this case matched; empty otherwise. Evidence of the match — NOT the pooling key. |
| `freq_price` | Number of price-data rows for this case. |
| `mn_item_unit_pairs` | PSPS obs count at `(province, municipality, item, unit)` (from the price data, backfilled). Gauges cell thinness. |
| `pn_item_unit_pairs` | PSPS obs count at `(province, item, unit)` (province level). |
| `cause` / `cause_label` | 1 = `nonsensical`, 2 = `empty/uncommon`, 3 = `harmonizable` (see below). |
| `harmonizable` | `True` iff `cause==3`: the unit folds to a unit **already present in the same `(prov,mun,item)` MS cell** — i.e., not a real gap, just a label variant of an in-cell unit. |
| `detail` | Free-text explanation of the classification. For cause 1, prefixed with `recoverable (count x unit)` (quantity-prefixed, e.g. `100pcs of pandesal`) or `unmappable free-text`. |

### `harmonized_nsu_unit` vs `in_MS_as` — why they differ

These answer two different questions and are **meant to differ** for grouped units:

- **`in_MS_as`** is the *concrete* unit sitting in that exact cell that the case matched — the **evidence** the case isn't a real gap. It is **cell-specific**: it's whatever variant that particular cell happens to contain. Example: cabbage `binilog` in Altavas → `in_MS_as = bilog`, because that cell has `bilog`; a different cell might show `pieces or units`.
- **`harmonized_nsu_unit`** is the *group-level* pooling key — what you aggregate conversion weights over. It is **cell-independent**: every pieces-variant of an item (`bilog`, `binilog`, `piraso`, `pieces or units`) collapses to the single `pieces or units`, so they share **one** conversion factor. Example: cabbage `binilog` → `harmonized_nsu_unit = pieces or units`.

So for cabbage `binilog`: `in_MS_as = bilog` (the specific sibling in that cell) but `harmonized_nsu_unit = pieces or units` (the common pool). Setting the pool key to `in_MS_as` instead would wrongly split variants into separate pools by whichever unit each cell happened to contain.

**Downstream:** pool/convert on `harmonized_nsu_unit`; use `in_MS_as` only to inspect the concrete in-cell match.

### `cause` values
| cause | label | meaning |
|---|---|---|
| 3 | `harmonizable` | Item is in the cell **and** the unit folds to a unit already in that cell → reconcile by relabeling to `harmonized_nsu_unit` (`in_MS_as` names the concrete sibling). Not a real gap. |
| 2 | `empty/uncommon` | Not foldable in this cell, but the unit is a valid MS unit for the item elsewhere, **or** the item is absent from this cell entirely (empty case). |
| 1 | `nonsensical (recoverable)` | No MS referent, but the unit is **quantity-prefixed** (`count × base-unit`, base in a curated set) → salvageable: `harmonized_nsu_unit` = base, count in `detail`. |
| 1 | `nonsensical (unmappable)` | No MS referent and not recoverable — free-text / junk → `harmonized_nsu_unit = .c`. |

---

## `outputs/tables/master_nsu_rename.csv` — master rename sheet (prov×mun×item×nsu)

One row per **`(province, municipality, item, raw_nsu)`** observed in the raw `${data}` (MS) OR the
price data — the union (2,927 rows: 1,985 MS & Price + 942 Price Only + 0 MS-only currently). Its purpose is to
identify, **within each prov-mun-item cell**, the nsus that are the same referent but recorded with a
different spelling/translation, and show what they all pool to. 766 rows are part of such an in-cell
merge.

| column | definition |
|---|---|
| `province`, `pull_municipal_city`, `cons_name` | The prov-mun-item cell (normalized). |
| `pull_nsu_unit` | The raw unit, normalized (`nz`: lowercase, trimmed, ASCII-dropped). |
| `cleaned_nsu_unit` | `to_cleaned(item, raw)` — spelling-clean via `nsu_rename_crosswalk.xlsx` (fallback: `reduce_unit`/fuzzy/heuristic). Vocabulary-preserving; never blank. |
| `harmonized_nsu_unit` | `canonical(item, cleaned)` — the weight-validated pooling key. For `Price Only` cause-1 rows, overridden with the diagnosed value (`.c` or recoverable base) to match the diagnosed CSV. Never blank. |
| `source` | `MS & Price` / `Price Only` (from `cases_in_price_not_in_MS.csv`, authoritative), or `MS` for a raw unit seen only in `${data}` and not in the price data. |
| `cell_merge_with` | Other raw nsus **in the same `(prov,mun,item)` cell** that share this row's `harmonized_nsu_unit` — the sibling spellings/translations it pools with (`; `-separated). Empty if it's the only spelling in its cell. |
| `n_cell_merged` | Count of raw spellings in this cell that collapse to this `harmonized_nsu_unit` (this row + `cell_merge_with`). `>1` means an in-cell merge happened. |
| `cause_label`, `in_MS_as` | Populated for `Price Only` rows (from the diagnosis); blank otherwise. |
| `price_case_id` | Durable id for a `Price Only` case, continuing the same sequence as the weighing ids so a number means one thing across the project. **Blank on `MS & Price` rows by design** — those are identified by their weighing id, which lives at weighing grain and cannot sit on a case row without implying one weighing per case. Numeric; `03_clean_ms.do` destrings it after the `stringcols(_all)` import. |

**Weight de-contamination (raw-sourced):** because the cell inventory and the weights are built from
**raw** `pull_nsu_unit` re-cleaned by our (corrected) rename — not `nsu_data`'s `cleaned_nsu_unit` — the
old rename's bad `putos → pack` fold for *ice cream* and *crackers* no longer contaminates `pack`.
Those items now carry `putos` (~60 g / ~160 g) and `pack` (~525 g / ~300 g) as separate harmonized
units with their own weights; the other validated `putos` folds (e.g. cabbage `putos`≈`pack`) are
unchanged. See `docs/master_rename.md` for construction and use.

---

## `outputs/build/deliverables/outcome2_lookup.csv` — the Outcome 2 conversion lookup

One row per published conversion point. The column that causes the most confusion is
`psps_month`, so it is explained first.

### `psps_month` is blank on most rows, and that is structural — not missing data

`psps_month` is populated on **exactly** the price-quantity rows and blank on every other
row:

| `branch` | rows | `psps_month` |
|---|--:|---|
| `price-quantity` | 1,093 | populated |
| `size-based` | 2,633 | **blank** |
| `conventional` | 24 | **blank** |

`infl_factor` and `n_cpi_vals` are blank on identically the same rows.

**Why.** Only Branch P carries a market-survey *price*, and a price collected in one month
has to be restated in the household's interview month before it can be compared with what
that household paid — that is what `24_inflate_to_psps_month.do` does, and it is the only
step that needs a month. A size-based weight comes from weighings with no price attached,
so there is no month to restate and no inflation factor to apply. The row is complete
without them.

**It is not a broken join.** A join failing on a unit-label mismatch would scatter blanks
across all three branches; these align perfectly with one. Read a blank here as *not
applicable*, the same way you would read a blank `price_case_id` on an `MS & Price` row.

### The other columns readers ask about

| column | definition |
|---|---|
| `conv_rank` | Which rung of the fallback ladder supplied this row. `0` is a same-cell match; `1`–`3` are borrowed rungs, widening from municipality to province to item. Blank where no weighing stands behind the row. |
| `w_use`, `v_use` | The weight used, and the value per gram derived from it (`v = p_g / w_g`). `v_use` is what a household price is divided by to get grams. |
| `d_point_usable`, `unusable_why` | Whether the price point can carry a conversion, and if not, why. 495 of 3,750 rows are unusable and say so rather than being dropped. |
| `n_g`, `n_disputed`, `n_uncertain`, `share_uncertain` | How many weighings stand behind the row, and how many of them were questioned. `share_uncertain == 1` is the sharp signal — nothing behind the estimate went unquestioned. See A20. |
