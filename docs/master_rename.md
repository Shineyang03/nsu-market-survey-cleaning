# The master NSU rename sheet — construction & use

**File:** `outputs/tables/master_nsu_rename.csv`
**Built by:** `dofiles/diagnose_price_only.py`

This is the authoritative map from every raw non-standard unit (NSU) recorded in the survey to a
weight-validated pooling key, and it makes explicit which raw NSUs in the same cell are the same referent
recorded with a different spelling or translation.

---

## 1. What the sheet is

One row per **`(province, municipality, item, raw_nsu)`** — the *prov-mun-item-nsu* grain. The universe is
the union of the market survey (MS) and the price (PSPS-derived) data:

| `source` | meaning | rows |
|---|---|---|
| `MS & Price` | raw NSU present in both the market survey and the price data | 2,001 |
| `Price Only` | raw NSU in the price data but not in the raw MS data for that cell | 949 |
| `MS` | raw NSU present only in the market survey, never in the price data | 2 |

Total **2,952 rows**; **759** are part of an in-cell merge (`n_cell_merged > 1`).

---

## 2. The three unit layers

Each raw NSU is expressed at three levels. Only the third is operational.

```
pull_nsu_unit  ──►  cleaned_nsu_unit  ──►  harmonized_nsu_unit
  (raw label)      (cleaned vocabulary,     (pooling key —
                    REFERENCE only)          POOL AND CONVERT ON THIS)
```

- **`pull_nsu_unit`** — the raw unit as recorded, normalized only for matching: lowercase, trimmed, and
  non-ASCII characters dropped (mirrors the Stata `ustrto(., "ascii", 2)` mode-2 rule, which drops rather
  than transliterates, so a clean `ñ` and a mojibaked `ñ` collapse identically).
- **`cleaned_nsu_unit`** — the raw label cleaned to canonical spelling/vocabulary. **Reference only:** it
  preserves the recorded vocabulary for a unit reference book. Nothing downstream needs to operate on it.
- **`harmonized_nsu_unit`** — the **pooling key**. Labels that share a physical referent collapse to one
  value here; labels that only look similar but weigh differently stay separate. This is the column you
  aggregate conversion weights over, and the one to change when reconciling a unit (§7).

---

## 3. Why `harmonized_nsu_unit` is item-conditioned but cell-independent

The fold from a label to its harmonized key is decided per **item**, and is the **same in every cell**.

- **Item-conditioned.** The same raw word can denote different objects for different items, so it folds
  differently:
  - `bilog` → `pieces or units` for cabbage/carrot (a round piece of vegetable), but for **chicken**
    `bilog` is a *whole bird* and stays its own unit; for preserved/processed meat it is its own piece.
  - `putos` folds into `pack` for most items, but for **ice cream** (~60 g sachet) and **crackers**
    (~160 g sachet) it is far lighter than a `pack` (~300–525 g) and is kept separate.

  So the rule is keyed on `(item × unit)`, never on the unit alone.

- **Cell-independent.** Given the item, the harmonized key does not depend on province or municipality —
  cabbage `binilog` → `pieces or units` everywhere. This lets a thin cell reuse a conversion factor
  estimated from richer cells for the same unit. If the key were cell-specific, the identical physical
  unit would fall into different pools town-by-town and could not share weights.

Note the contrast with two neighbouring columns: `in_MS_as` **is** cell-specific (the concrete sibling
found in that one cell), and the conversion *weight in grams* is still estimated per prov-mun. Only the
**label that identifies the referent** is cell-independent.

---

## 4. Columns

| column | definition |
|---|---|
| `province`, `pull_municipal_city`, `cons_name` | the prov-mun-item cell (normalized). |
| `pull_nsu_unit` | raw unit, normalized (§2). |
| `cleaned_nsu_unit` | cleaned-vocabulary label. Reference only. Never blank. |
| `harmonized_nsu_unit` | the pooling key (§2, §3). For `Price Only` nonsensical rows this is `.c` (unmappable junk) or a recovered base unit (quantity-prefixed strings). Never blank. |
| `source` | `MS & Price` / `Price Only` / `MS` (§1). |
| `cell_merge_with` | the **other** raw NSUs *in this same cell* that share this row's `harmonized_nsu_unit` — the sibling spellings/translations it pools with (`; `-separated). Empty if it is the only spelling in its cell. |
| `n_cell_merged` | count of raw spellings in this cell collapsing to this `harmonized_nsu_unit` (this row + `cell_merge_with`). `>1` means an in-cell merge occurred. |
| `cause_label` | `Price Only` rows only: why the unit was missing from MS — `harmonizable`, `empty/uncommon`, `nonsensical (recoverable)`, or `nonsensical (unmappable)`. Blank otherwise. |
| `in_MS_as` | `Price Only` **harmonizable** rows only: the concrete MS unit already present in that exact cell that the case matched — the evidence the case is not a real gap. Cell-specific, so it generally differs from `harmonized_nsu_unit` (e.g. cabbage `binilog` → `in_MS_as = bilog` but `harmonized_nsu_unit = pieces or units`). Blank otherwise. |

`cause_label` and `in_MS_as` are documented in full in `cases_in_price_not_in_MS_diagnosed.csv`
(see `data_dictionary.md`).

---

## 5. How it is built

**Inputs**

- `${data}` — raw MS survey units (`pull_nsu_unit`), the cell inventory.
- `nsu_rename_crosswalk.xlsx` — `(item, raw unit) → cleaned unit`, the spelling/vocabulary map.
- `price_ms_unit_harmonization_crosswalk.xlsx` — `unit → translation_group`, the fold groups.
- `nsu_data.dta` — MS weighings (`corrected_weight`), used only to estimate weights and validate folds.
- `cases_in_price_not_in_MS.csv` — the authoritative MS-vs-price source flag and the price-only case list.

**Pipeline (per raw NSU)**

1. `cleaned_nsu_unit` = the rename crosswalk applied to `(item, raw)`, trying exact match, then a
   descriptor-reduced retry, then a fuzzy (word-order/typo) match, then a heuristic for units the
   crosswalk never covered.
2. `harmonized_nsu_unit` = the translation-group fold of the cleaned label, subject to the item-specific
   separations in §6.
3. `cell_merge_with` / `n_cell_merged` = computed within each `(province, municipality, item)` cell by
   grouping raw NSUs that share a `harmonized_nsu_unit`.

**Weights are read from raw units, not pre-cleaned ones.** The cell inventory and the fold-map weights are
built from the raw `pull_nsu_unit` re-cleaned by the crosswalk above — not from a previously cleaned unit
column that had folded ice-cream/crackers `putos` into `pack` and so contaminated the `pack` weight.
Re-cleaning the raw directly keeps `putos` separate with its own weight.

---

## 6. Item-specific separations (weight-validated)

Most translation groups fold safely, but the following are kept apart because MS weighings showed the
variants are different referents:

| item | units kept separate | reason |
|---|---|---|
| chicken | `bilog` (whole bird) vs `binilog`/`piraso`/`pieces or units` (portion) | whole bird ≈ 1,045 g vs a portion ≈ 500 g (confirmed, size-stratified). Only `bilog` is pulled out; the other pieces-variants stay folded together. |
| preserved/processed meat | `bilog` vs `binilog`/`piraso`/`pieces or units` (portion) | piece-vs-whole; weight test inconclusive, `bilog` kept separate conservatively while the other pieces-variants fold together |
| ice cream | `putos` (~65 g) vs `pack` | sachet vs pack (confirmed) |
| crackers/cookies | `putos` (~78 g) vs `pack` (~135 g) | sachet vs pack (confirmed) |
| camote | `bilog` vs `binilog` (whole pieces group unfolded) | test flagged a difference but on thin data → low confidence → not folded |
| camote tops | `bundle` vs `bugkos` | ~2× difference (confirmed) |

`pack` and `packs` (singular/plural of one word) are merged to `pack`. These decisions are recorded in
`unit_fold_map.csv` via the `fold_verdict` column.

**Fold policy — when the weight evidence is weak, do not fold.** Translation-group folding
(`bilog`/`binilog`/`piraso` → `pieces or units`, etc.) is validated against the size-stratified weight
test in `validate_folds.py` (comparing labels within province × size × measurement-unit). A group is kept
folded only where the test *confirms* the members weigh the same; where it shows a difference, or the data
are too thin to be confident, the labels are kept separate. A few size-descriptor groups (`whole
(chicken)`, `small cup`, `small packs`) fold on the official-translation basis alone because too few
observations co-occur to test them.

---

## 7. Using the sheet

**Pooling weights (primary use).** Join incoming rows on
`(province, municipality, item, pull_nsu_unit)` and aggregate `corrected_weight` over
`(item, harmonized_nsu_unit)`. Do **not** pool over the raw or cleaned label — only `harmonized_nsu_unit`
identifies the referent consistently across cells.

**Reconciling price data to MS.** For `Price Only` rows with `cause_label = harmonizable`, `in_MS_as`
names the concrete in-cell MS unit the price unit reconciles to; relabelling the price observation to its
`harmonized_nsu_unit` places it in the same pool as that MS unit.

**Finding same-referent variants in a cell.** Filter `n_cell_merged > 1` (or non-empty `cell_merge_with`)
to see every cell where two or more raw spellings/translations collapse to one referent — e.g. cabbage
`bilog` + `binilog` → `pieces or units`, or loaf-bread `large` / `mabahoe nga putos` / `malaking packs`
→ `large packs`.

**Auditing residual gaps.** Among `Price Only` rows: `empty/uncommon` = a real but empty/uncommon cell;
`nonsensical (unmappable)` = free-text junk routed to `.c`; `nonsensical (recoverable)` = a
quantity-prefixed string whose base unit was recovered.

---

## 8. Manually reconciling a `pull_nsu_unit`

To reassign how a raw unit is cleaned or pooled, **edit the input and re-run the script** rather than
editing the CSV. The script recomputes every derived column (`harmonized_nsu_unit`, `cell_merge_with`,
`n_cell_merged`, and the price-only diagnosis) consistently; a hand edit does not.

Pick the layer the change belongs to:

1. **Change the cleaned spelling of a raw unit** (e.g. a typo variant should read as an existing cleaned
   unit): add or edit a row in **`nsu_rename_crosswalk.xlsx`** — `(pull_item, pull_nsu_unit,
   cleaned_nsu_unit)`. This updates `cleaned_nsu_unit`, and `harmonized_nsu_unit` follows automatically.
2. **Change which pool a unit belongs to** (a unit should fold into, or out of, a translation group):
   edit **`price_ms_unit_harmonization_crosswalk.xlsx`** — set the unit's `translation_group`.
3. **Add an item-specific exception** (keep a unit separate for one item only, as in §6): add it to the
   corresponding rule in `diagnose_price_only.py` (`KEEP_SEPARATE`, `PUTOS_KEEP_SEPARATE_ITEMS`, or
   `unsafe_pieces`).

Then re-run:

```bash
python dofiles/diagnose_price_only.py
```

and spot-check the cell(s) you touched.

**If you must edit `master_nsu_rename.csv` directly** (a one-off that a re-run will overwrite): change the
row's `harmonized_nsu_unit`, then — because `cell_merge_with` / `n_cell_merged` are within-cell
aggregates — recompute those two columns for **every** row sharing the same
`(province, pull_municipal_city, cons_name)` cell, not just the row you changed. Leaving the siblings
untouched makes the cell internally inconsistent.
