# Summary statistics: raw vs cleaned

Descriptive statistics for the NSU Market Survey, computed independently on the raw
launch data and on the cleaned weighings, so the two can be compared directly. This
does not feed the cleaning or conversion-factor pipeline -- it is a description of
what the data look like at each end, not a step in producing either.

**Sources**

| | file | rows |
|---|---|---|
| raw | `NSU Market Survey Launch/data/PSPS NSU Market Survey Launch.dta` | 11,495 |
| cleaned | `outputs/master_rename_build/temp/nsu_data_master.dta` | 11,458 |

**Built by** `dofiles/summary_statistics.py`. **Full output**:

- `outputs/master_rename_build/tables/summary_stats_raw.csv` and `summary_stats_cleaned.csv` --
  every statistic below (and several not shown here) in tidy long format:
  `statistic, grouping, level, value`. Pivot on `statistic` to get a wide table for
  any one metric.
- `outputs/master_rename_build/tables/summary_stats.json` -- the same numbers, each
  carrying its title, description and grain, for a script to read without this page.
  Not used by anything in the repository today; open the CSVs instead unless you are
  writing code against it.

Where a count differs between raw and cleaned, this page reports the difference and
moves on. It does not attempt to explain why the two differ -- that is what the
attrition ledger (built separately) is for.

---

## Grain

A **weighing** is one row: province x municipality x item x NSU x market_type x
vendor_id x obs_type (`item_nsu_hetero_type` on the cleaned side). Both sides are
unique at this grain -- verified directly, not assumed:

| | rows | distinct groups |
|---|---|---|
| raw | 11,495 | 11,495 |
| cleaned | 11,458 | 11,458 |

A **case** is province x municipality x item x NSU, the pooling unit. Raw data has
no harmonized NSU column, so `pull_nsu_unit` (the free-text field) stands in for it
on that side -- this is a parallel role, not the same key. On the cleaned side the
case key also carries `corrected_unit` (g vs mL), so the two items recorded in both
mass and volume (see `docs/data_oddities.md` section 4) never get a mass reading and
a volume reading pooled into one case; every other item has a constant
`corrected_unit` within the rest of the key, so this never inflates a case count
that shouldn't be inflated.

| | case key | distinct cases |
|---|---|---|
| raw | province x municipality x item x `pull_nsu_unit` | 2,001 |
| cleaned | province x municipality x item x `harmonized_nsu_unit` x `corrected_unit` | 2,020 |

**The raw `uuid` column is never used.** It is `item_unit_MUNICIPALITY` with no
province, and PONTEVEDRA (Capiz and Negros Occidental) and SAN ENRIQUE (Iloilo and
Negros Occidental) each occur in two provinces -- 33 price-file uuids are ambiguous
on this basis. Every municipality-level statistic below carries its province
alongside it, written `PROVINCE | MUNICIPALITY`, so the two repeats never collide.

---

## Headline counts

| metric | raw | cleaned |
|---|---:|---:|
| weighings | 11,495 | 11,458 |
| distinct items | 19 | 19 |
| distinct provinces | 5 | 5 |
| distinct province x municipality pairs | 104 | 104 |
| distinct vendors | 7,857 | 7,828 |
| distinct markets | 709 | 709 |
| distinct NSU raw labels (`pull_nsu_unit`) | 129 | 119 |
| distinct NSU harmonized labels (`harmonized_nsu_unit`) | -- | 64 |
| distinct item x NSU-raw-label pairs | 173 | 162 |
| distinct item x NSU-harmonized pairs | -- | 93 |
| distinct cases (own case key, see above) | 2,001 | 2,020 |
| max vendors observed in one (case x hetero-type x market_type) cell | 5 | 6 |
| average vendors per (case x hetero-type x market_type) cell | 1.98 | 1.98 |
| cases with weighings spanning more than one weighing approach | 0 | 1 |
| cases with weighings spanning more than one hetero-group type | 851 | 851 |

The 19 items and 5 provinces are identical on both sides, as expected -- cleaning
does not add or remove items or provinces. The single cross-weighing-approach case
on the cleaned side is the documented ILOILO / TIGBAUAN carrot exception, where
harmonization folds `bilog` (size-based) and `pieces or units` (price-quantity) into
one harmonized label -- see `docs/data_oddities.md` section 1. Raw data has zero
such cases because it has not yet been folded. A case spanning more than one
hetero-group type (851 on both sides) is normal and expected -- most size-based
cases legitimately contain small, medium and large weighings; this only becomes
anomalous for weighing approach, where the field instrument fixes exactly one
approach per item x NSU.

---

## Composition

### By weighing approach

| approach | raw weighings | cleaned weighings |
|---|---:|---:|
| Size-based (small, medium, large) | 9,796 | 9,770 |
| Price-quantity based (lower, median, higher price) | 1,229 | 1,220 |
| Conventional NSU (eg. ganta, salmon, salop) | 470 | 468 |

The cleaned-side shares (85.3% / 10.6% / 4.1%) match
`docs/conversion_factor_methodology.md`'s branch-share table exactly, which is a
useful cross-check that this script's `weighing_approach` decoding agrees with the
pipeline's.

### By obs_type / hetero-group type

| type | raw weighings | cleaned weighings |
|---|---:|---:|
| small_size | 3,849 | 3,842 |
| medium_size | 3,338 | 3,326 |
| large_size | 2,609 | 2,602 |
| conventional_nsu | 470 | 468 |
| municipality_median | 531 | 531 |
| province_median | 414 | 409 |
| mp50_price | 104 | 104 |
| mp25_price | 74 | 73 |
| mp75_price | 70 | 70 |
| unique_mun_price6 | 31 | 31 |
| unique_mun_price7 | 5 | 2 |

### By market type

| market type | raw weighings | raw share | cleaned weighings | cleaned share |
|---|---:|---:|---:|---:|
| Public Market | 6,343 | 55.2% | 6,322 | 55.2% |
| Roadside Vendors | 3,239 | 28.2% | 3,230 | 28.2% |
| Talipapa | 1,913 | 16.6% | 1,906 | 16.6% |

`market_type` carries a stored value label on the raw side (1=Public Market,
2=Talipapa, 3=Roadside Vendors) but not on the cleaned side. This table applies the
raw labels to the cleaned data's numeric codes on the assumption the coding survived
the build unchanged -- the same assumption `dofiles/cleaning.do`'s own summary
section made. The near-identical shares above (55.2/16.6/28.2 on both sides, to one
decimal place) support that assumption but do not prove it.

### By province (cases)

| province | raw cases | cleaned cases |
|---|---:|---:|
| ILOILO | 842 | 840 |
| CAPIZ | 326 | 332 |
| NEGROS OCCIDENTAL | 308 | 320 |
| ANTIQUE | 294 | 297 |
| AKLAN | 231 | 231 |

Weighing counts by province, and every other province/municipality/item breakdown,
are in the CSV/JSON under `n_weighings_by_province`, `n_weighings_by_municipality`
and `n_weighings_by_item`; omitted here for space.

---

## Coverage

**Items per municipality.** Computed at province x municipality grain (104 pairs)
to avoid the PONTEVEDRA / SAN ENRIQUE collision:

| | raw | cleaned |
|---|---:|---:|
| min | 7 | 7 |
| median | 12 | 12 |
| mean | 11.85 | 11.83 |
| max | 17 | 17 |

**Market slots filled** -- of the 3 possible market types, how many does each case
actually appear in:

| market types present | raw cases | cleaned cases |
|---|---:|---:|
| 1 | 814 | 843 |
| 2 | 713 | 705 |
| 3 (all) | 474 | 468 |

**Vendors per cell, by market type** -- for each (case x hetero-type x market_type)
cell, the number of distinct vendors weighed, bucketed 1 / 2 / 3+ (cleaned data):

| market type | 1 vendor | 2 vendors | 3+ vendors |
|---|---:|---:|---:|
| Public Market | 806 | 622 | 1,412 |
| Roadside Vendors | 894 | 527 | 416 |
| Talipapa | 584 | 278 | 253 |

Public Market cells are the ones most likely to have 3+ independent vendors backing
a single hetero-group estimate; Talipapa cells are the thinnest.

**Average weighings per case, by hetero-group type** (excluding cases with zero
weighings under that type):

| hetero-group type | raw | cleaned |
|---|---:|---:|
| conventional_nsu | 3.79 | 3.80 |
| municipality_median | 3.64 | 3.56 |
| small_size | 3.43 | 3.34 |
| medium_size | 3.41 | 3.41 |
| province_median | 3.26 | 3.12 |
| mp75_price | 3.18 | 3.09 |
| large_size | 3.14 | 3.20 |
| mp25_price | 3.08 | 3.04 |
| mp50_price | 3.06 | 3.00 |
| unique_mun_price6 | 2.58 | 2.58 |
| unique_mun_price7 | 2.50 | 2.00 |

---

## Weight distribution: before vs after the order-of-magnitude correction

Raw data records `weight` in whatever unit was handy (`unit`: Kilograms / grams /
Litres). `dofiles/00_shared/04_unit_snap.do` canonicalizes the dimension (kg to g, L to
mL) and snaps obvious order-of-magnitude entry errors toward an item x
harmonized-NSU anchor, producing `corrected_weight` / `corrected_unit` (g / mL). Raw
`weight` and `unit` do not survive into `nsu_data_master.dta`, so "before" always
means the raw file and "after" always means the cleaned file -- there is no
row-level before/after pair to difference here (that belongs to the attrition
ledger, not this page).

**Recorded unit, before correction (raw):**

| unit | weighings |
|---|---:|
| grams (g) | 9,175 |
| Litres (L) | 1,630 |
| Kilograms (Kgs) | 690 |

**Corrected unit, after correction (cleaned):**

| unit | weighings |
|---|---:|
| g | 9,596 |
| mL | 1,855 |
| (missing) | 7 |

The 7 missing rows are deliberate: 5 raw weighings recorded literal `0`
(enumerator shorthand for "item not found at the requested price/size", see
`docs/data_oddities.md` section 2) plus 2 further rows the cleaning script flags as
genuinely unreadable (the 0.007 L CAPIZ/PANAY distilled-water row and the 5 g/cup
prawns rows) -- all set to Stata's `.c` rather than guessed at.

**Item x unit weight statistics** (mean shown; n, median, sd, min, max are in the
CSV/JSON as `weight_raw_*` and `weight_corrected_*`). A sample:

| item | raw unit | raw mean | cleaned unit | cleaned mean |
|---|---|---:|---|---:|
| Beef | Kilograms (Kgs) | 823.1 | g | 1,100.6 |
| Cabbage | Kilograms (Kgs) | 229.1 | g | 643.6 |
| Carrot | Kilograms (Kgs) | 0.14 | g | 156.0 |
| Chicken | Litres (L) | 0.48 | g | 1,010.4 |
| Loaf Bread | grams (g) | 501.0 | g | 501.0 |

Carrot's raw "Kilograms" mean of 0.14 kg (140 g) illustrates exactly the kind of
unit-entry slip the snap targets: an item plainly not sold by the tens-of-kilos is
recorded in a unit that reads as implausible, and the corrected figure (156 g,
across all units pooled) is in the range the item's other weighings support. The
full item x unit tables for both sides let this kind of check be repeated for any
item.

---

## NSU vocabulary

| | count |
|---|---:|
| distinct raw NSU strings, raw data (`pull_nsu_unit`) | 129 |
| distinct raw NSU strings surviving into cleaned data | 119 |
| distinct spelling-corrected strings, reference only (`cleaned_nsu_unit`) | 65 |
| distinct pooling-key strings (`harmonized_nsu_unit`) | 64 |

119 raw free-text NSU labels fold down to 64 harmonized pooling keys. The fold is
item-conditioned (the same raw string can map to a different harmonized label for a
different item), so the natural unit to count collapsing on is item x harmonized
cell, not harmonized label alone:

| distinct raw labels folding into the cell | item x harmonized-unit cells |
|---|---:|
| 1 (no fold) | 65 |
| 2 | 10 |
| 3 or more | 18 |

The heaviest folds: cabbage's `putos (mix vegetable)` absorbs 8 distinct raw
labels, cabbage's `pack` absorbs 6, and chicken's `whole (chicken)` absorbs 4. The
full item x harmonized-unit table (93 cells) is in the CSV/JSON as
`n_raw_labels_by_item_harmonized_unit`.

---

## Reading the CSV / JSON

Every number above (and more not reproduced here -- full province/municipality/item
breakdowns, the complete item x unit weight tables, per-cell vendor counts) is in
`summary_stats_raw.csv` and `summary_stats_cleaned.csv` as one row per
`(statistic, grouping, level, value)`. `grouping` names the dimension `level` runs
over ("overall" means a single scalar, its `level` is always `"all"`).
**Which file to open.** For reading numbers yourself, use the CSVs -- they open in
Excel and filtering on `statistic` gives you one metric at a time.

`summary_stats.json` holds the same numbers plus, for each statistic, a `title`, a
`description` naming its caveats, and the grain definitions the statistic was computed
at. It exists so a script can pick up a statistic and know what it means without
parsing this page. Nothing in the repository reads it today; it is a convenience for
code that might, and it is safe to ignore or delete if nothing ever does. To list what
it contains:

```
python -c "import json,io; d=json.load(io.open(r'outputs/master_rename_build/tables/summary_stats.json',encoding='utf-8')); [print(s['id'], '|', s['grouping'], '|', s['title']) for s in d['cleaned']['statistics']]"
```

Read the `$schema_note` key first if you do use it -- it states the one place where the
same statistic id means different things on the raw and cleaned sides.
