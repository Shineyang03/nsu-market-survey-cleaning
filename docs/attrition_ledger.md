# Attrition ledger: from raw weighings to Outcome 1

Traces every raw market-survey (MS) weighing and every price-file case through the
conversion-factor pipeline to either (a) a row in a final output or (b) a named,
counted reason it was dropped. Companion, machine-readable version:
`outputs/master_rename_build/tables/attrition_ledger.csv` (one row per drop reason,
plus one row per individually named case loss).

**Scope.** Outcome 2 (PSPS conversion factors) has no do-file yet — see
`docs/conversion_factor_methodology.md`, "Which files are live". This ledger
therefore covers **Outcome 1 (the reference set) only**. A matching ledger for
Outcome 2 should be produced once that pipeline exists; nothing below should be
read as describing it.

**Case grain.** Unless marked "coarse grain", a *case* means

> province × municipality × item × `harmonized_nsu_unit` × `corrected_unit`

This is the grain `10_reference_set/10_size_assignment.do` actually pools on (it groups on all five
columns to build `cell`). It is one column finer than the grain used for the
headline case counts elsewhere in the project docs (`docs/conversion_factor_methodology.md`'s
"1,951 cases harmonized" figure, which omits `corrected_unit`) — the extra split
comes from the two mixed-dimension items (ice cream; drinks at restaurant/hotel/cafe/kiosk)
that get separate grams and millilitres cases. Where the coarser, no-`corrected_unit`
grain is used below, it is labeled explicitly, because the two grains give different
numbers for the same-sounding question — that difference is itself the answer to the
priority question in this document (see "The 315 → 310 question" below).

All counts below were verified independently against the pipeline's saved `.dta`
files (not read off do-file comments), using Python replications of each do-file's
row-and-case-dropping logic, cross-checked set-for-set against the actual saved
output where it mattered (the price-quantity case investigation below matches the
real `nsu_reference_set.dta` output exactly, case for case).

---

## 1. Raw weighings → `nsu_data_master.dta` (`03_clean_ms.do`)

| step | drop | rows in | dropped | rows out |
|---|---|---:|---:|---:|
| 0 | — | — | — | **11,495** |
| 1a | comment-flagged data-entry error ("enumerator re-entered 225 weight for the 187.5 price mark") | 11,495 | 1 | 11,494 |
| 1b | MS weighings with no matching `master_nsu_rename` row | 11,494 | 0 | 11,494 |
| 1c | standard-quantity label weighings (10 raw labels that name their own quantity, e.g. `bottle (500 ml)`, `1/2 sack of rice (25kls.)`) | 11,494 | 33 | 11,461 |
| 1d | TIGBAUAN fresh fish `bilog` rows with no stated price (SurveyCTO glitch) | 11,461 | 3 | 11,458 |
| **out** | **`nsu_data_master.dta`** | | **37** | **11,458** |

Step 1b's zero is expected, not merely lucky: `master_nsu_rename.csv`'s universe is
the union of MS and price-file cases at the raw-label grain, so every MS weighing is
guaranteed a match. Confirmed directly (0 unmatched rows).

**Case count.** 2,020 cases at the fine grain enter and leave Stage 1 unchanged — none
of the four drops above empties a case of every one of its rows.

---

## 2. `nsu_data_master.dta` → `nsu_weighings_cpi.dta` (`07_cpi_factor.do`)

| step | drop | rows in | dropped | rows out |
|---|---|---:|---:|---:|
| 2a | vendor-priced price-quantity rows where the case keeps a preloaded rung | 11,458 | 74 | 11,384 |
| **out** | **`nsu_weighings_cpi.dta`** | | **74** | **11,384** |

Of 95 rows where `actual_price` was recorded (a field-officer comment saying the
vendor's own price governed, not the preloaded amount), 74 are dropped and 21 are
**rescued** — kept and flagged `price_source == "vendor_actual"` — because dropping
them would have deleted their case's *only* price-quantity rung. See
`docs/data_oddities.md` §3.

**Case count: 2,020 → 2,019, one case lost.** This is a genuine finding, not
previously documented:

> **NEGROS OCCIDENTAL / ENRIQUE B. MAGALONA (SARAVIA) / ice cream, sorbet, edible
> ice / putos / mL** — emptied of its only price-quantity row.

Ice cream is one of the two items recorded in both mass and volume
(`docs/data_oddities.md` §4), so this cell splits into a `g` case and an `mL` case.
The rescue rule in `07_cpi_factor.do` decides "does this case keep a preloaded
rung" at the grain province × municipality × item × `harmonized_nsu_unit` —
**without `corrected_unit`**. The `g`-side case had a preloaded row and survived; the
`mL`-side case's only price-quantity row was vendor-priced (`actual_price = 12`). The
rescue rule, pooling both splits together, saw the `g`-side's preloaded row and
concluded the case "keeps a preloaded rung," so it dropped the `mL` row instead of
rescuing it. At the grain the pipeline actually pools on downstream, the `mL` case
had nothing to fall back on and lost its only price-quantity observation outright —
exactly the outcome the rescue rule exists to prevent, missed because the rule's
grouping variables are one column coarser than the case grain it is protecting.

Not corrected here, per this task's no-`.do`-edit rule. The fix is to add
`corrected_unit` to the rescue rule's `bysort`/`egen` grouping in
`07_cpi_factor.do`.

---

## 3. `nsu_weighings_cpi.dta` → Outcome 1 (the `10_reference_set/` steps)

| step | drop | rows in | dropped | rows out |
|---|---|---:|---:|---:|
| 3a | rows with no usable weight (missing `corrected_weight`) | 11,384 | 7 | 11,377 |
| 3b | `unique_mun_price` weighings (**Outcome 1 only** — not a size) | 11,377 | 33 | 11,344 |
| 3c | the carrot's price-quantity rows (mixed-branch cell; **Outcome 1 only** — keeps the 9 size-based rows) | 11,344 | 7 | 11,337 |
| 3d | *aggregation, not attrition* — collapse to median(`corrected_weight`) within case × size | 11,337 | — | **3,321** |

**Step 3a — the 7 rows with no usable weight:**

| province | municipality | item | NSU | branch | reason |
|---|---|---|---|---|---|
| CAPIZ | TAPAZ | chicken | whole (chicken) | price-quantity ×4 | blank field `weight` on all 4 rows |
| CAPIZ | PANITAN | fresh fish | pieces or units | size-based ×1 | missing weight |
| CAPIZ | PANAY | prawns, lobster, shrimp | cup | size-based ×1 | flagged "genuinely unsure — 5 g per cup" in the unit snap |
| CAPIZ | PANAY | mineral/spring water | distilled water | size-based ×1 | flagged "genuinely unsure — 0.007 L" in the unit snap |

All 4 of these (province, municipality, item, NSU) groups lose **every** row —
each becomes its own vanished case, because `corrected_unit` is itself missing for
a row with no `corrected_weight`, so these rows never land in a surviving
`corrected_unit`-defined case. (The CAPIZ/TAPAZ chicken case is not gone entirely:
its other 5 rows, which do have a weight, form a separate CAPIZ/TAPAZ/chicken/whole
(chicken)/**g** case that survives to the output. See "The 315 → 310 question"
below for why this matters.)

**Step 3b — `unique_mun_price` (33 rows / 11 cases, Outcome 1 only).** It is a raw
observed price recorded because the municipality had too few distinct prices to
take quartiles — not a percentile, so it has no position on a size ladder. Excluding
it is deliberate (`docs/data_oddities.md`; `10_reference_set/10_size_assignment.do` header). 11 cases
lose every price-quantity row to this drop — see the full list under "The 315 → 310
question".

**Step 3c — the carrot (7 rows, 1 case removed from the price-quantity population,
0 cases removed overall).** ILOILO/TIGBAUAN/carrot/pieces or units is the one
harmonized cell in 1,951 that spans both weighing approaches (9 size-based `bilog`
rows fold with 7 price-quantity `pieces or units` rows). Outcome 1 keeps only the
9 size-based rows; Outcome 2 will keep only the 7 price-quantity rows. The case
survives in the output (via its size-based rows), so it does not reduce the
all-branch case count — but it does remove the case from the price-quantity
population specifically. `docs/data_oddities.md` §1.

**Step 3d is aggregation, reported separately from attrition as instructed.** 11,337
weighings collapse to 3,321 reference-set rows: 123 conventional (one row per case),
355 price-quantity-derived rows (310 cases), 2,843 size-based rows (1,571 cases).

**Case count: 2,019 → 2,015 (step 3a) → 2,004 (step 3b) → 2,004 (step 3c).** 2,004
cases enter and complete the collapse; the published `nsu_reference_set.dta` has
2,004 distinct cases across its 3,321 rows.

---

## The 315 → 310 question

**Answer.** There is no unexplained gap of 5 cases. "315" and "310" are counts of
two *different* case populations — comparing them subtracts a coarse-grain count
from a fine-grain one. Measured consistently, at either grain, the loss is fully
named and matches the ~11–12 originally expected.

### What "315" actually is

315 is the count of price-quantity-*touching* cases at the **coarse** grain
(province × municipality × item × `harmonized_nsu_unit`, **without**
`corrected_unit`), measured on `nsu_weighings_cpi.dta` (the literal input to
`10_reference_set/10_size_assignment.do`). It equals **314 + 1**:

- 314 is the modal price-quantity case count from
  `docs/conversion_factor_methodology.md`'s "Branch shares" table (measured the
  same way, at the same coarse grain, on `nsu_data_master.dta`).
- **+1 is the carrot cell** (ILOILO/TIGBAUAN/carrot/pieces or units), which is
  *modally* size-based (9 size-based rows outnumber 7 price-quantity rows) but
  still counts as "price-quantity-touching" under an any-row test, because it does
  contain price-quantity rows.

This count is identical on `nsu_data_master.dta` and `nsu_weighings_cpi.dta` —
the Stage 2 ice-cream-`mL` loss doesn't move it, because that case's `g`-side
sibling (same coarse key) survives.

### What "310" actually is

310 is the price-quantity case count in the **fine**-grain (with `corrected_unit`)
published output — the grain `10_reference_set/12_publish_reference_set.do` itself pools on, and the one
this ledger uses throughout. It was verified two ways: (1) replicating
`10_reference_set/10_size_assignment.do`'s §1 drop logic step by step in Python, and (2) reading the
actual `nsu_reference_set.dta` file and taking its price-quantity case set directly.
**The two are set-identical** — same 310 cases, not just the same count.

### The like-for-like reconciliations

| comparison | grain | in | out | lost | matches expectation? |
|---|---|---:|---:|---:|---|
| coarse vs. coarse | no `corrected_unit` | 315 | 303 | **12** | yes — = 11 `unique_mun_price`-only + 1 carrot |
| fine vs. fine | with `corrected_unit` | 323 (or 324 pre-Stage-2) | 310 | **13 (or 14)** | yes — the 12 above, plus 1–2 more, both named |

The two extra fine-grain-only losses, invisible at the coarse grain because each
has a surviving sibling on the *other* `corrected_unit` split of the same coarse
cell:

1. **NEGROS OCCIDENTAL/ENRIQUE B. MAGALONA (SARAVIA)/ice cream/putos/mL** — the
   Stage 2 restate rescue-rule casualty described above. (Its `g`-side sibling
   survives, so the coarse cell looks intact.)
2. **CAPIZ/TAPAZ/chicken/whole (chicken)/[`corrected_unit` missing]** — 4 of this
   case's 9 rows have blank field weight and so no `corrected_unit` at all; they
   form their own vanished case distinct from the case's other 5 rows, which do
   have `corrected_unit = g` and do survive (as
   CAPIZ/TAPAZ/chicken/whole (chicken)/**g**, visible in the output with `grams`
   1,050 / 1,195 / 1,670 across the three sizes). Again, the coarse cell looks
   intact because its `g`-side is fine.

### The full named list (fine grain, `nsu_data_master.dta`'s 324 → 310)

| # | province | municipality | item | NSU | `corrected_unit` | stage lost | reason |
|---|---|---|---|---|---|---|---|
| 1 | NEGROS OCCIDENTAL | ENRIQUE B. MAGALONA (SARAVIA) | ice cream, sorbet, edible ice | putos | mL | Stage 2 | restate rescue-rule grain mismatch |
| 2 | CAPIZ | TAPAZ | chicken | whole (chicken) | *(missing)* | Stage 3a | no usable weight (blank field weight) |
| 3 | ANTIQUE | LIBERTAD | preserved or processed meat | pieces or units | g | Stage 3b | `unique_mun_price` only |
| 4 | NEGROS OCCIDENTAL | VALLADOLID | chicken | bilog | g | Stage 3b | `unique_mun_price` only |
| 5 | NEGROS OCCIDENTAL | PULUPANDAN | liquor | long-neck | mL | Stage 3b | `unique_mun_price` only |
| 6 | NEGROS OCCIDENTAL | SALVADOR BENEDICTO | liquor | long-neck | mL | Stage 3b | `unique_mun_price` only |
| 7 | NEGROS OCCIDENTAL | HINOBA-AN (ASIA) | chicken | whole (chicken) | g | Stage 3b | `unique_mun_price` only |
| 8 | NEGROS OCCIDENTAL | TOBOSO | chicken | whole (chicken) | g | Stage 3b | `unique_mun_price` only |
| 9 | NEGROS OCCIDENTAL | VALLADOLID | chicken | whole (chicken) | g | Stage 3b | `unique_mun_price` only |
| 10 | NEGROS OCCIDENTAL | HINOBA-AN (ASIA) | preserved or processed meat | bilog | g | Stage 3b | `unique_mun_price` only |
| 11 | NEGROS OCCIDENTAL | CAUAYAN | fresh fish | pieces or units | g | Stage 3b | `unique_mun_price` only |
| 12 | NEGROS OCCIDENTAL | HINIGARAN | liquor | long-neck | mL | Stage 3b | `unique_mun_price` only |
| 13 | NEGROS OCCIDENTAL | MURCIA | prawns, lobster, shrimp | tumpok | g | Stage 3b | `unique_mun_price` only |
| 14 | ILOILO | TIGBAUAN | carrot | pieces or units | g | Stage 3c | carrot rule (kept as size-based only) |

324 (`nsu_data_master.dta`) − 14 = **310**, matching the published output exactly.

---

## 4. Price-file side

`outputs/tables/master_nsu_rename.csv` — keyed on province × municipality × item ×
**raw** `pull_nsu_unit` (the price-file side, before NSU-name harmonization) — has
**2,950** rows:

| source | cases | meaning |
|---|---:|---|
| MS & Price | 2,001 | this price-file case also appears among the MS weighings |
| Price Only | 949 | no MS weighing exists for this item-NSU-cell at all |
| **total** | **2,950** | |

The 949 price-only cases never enter the MS-side pipeline (Stages 1–3 above) at
all — they are outside its scope by construction, not dropped by any step in it.
They matter for a future Outcome 2 build (a PSPS conversion factor can only be
built where the market survey measured something), but are out of scope for this
ledger.

---

## 5. Reconciliation

Row-level, raw MS weighing to the last row that enters the Outcome 1 collapse:

```
11,495 (raw)
   − 1   comment-flagged error
   − 0   unmatched to master_nsu_rename
   − 33  standard-quantity labels
   − 3   TIGBAUAN fresh fish bilog, no price
 = 11,458  (nsu_data_master.dta)
   − 74  vendor-priced rows not rescued
 = 11,384  (nsu_weighings_cpi.dta)
   − 7   no usable weight
   − 33  unique_mun_price (Outcome 1 only)
   − 7   carrot price-quantity rows (Outcome 1 only)
 = 11,337  rows entering the median collapse
   → 3,321 reference-set rows (aggregation, not attrition)
```

Every one of `11,495 − 1 − 33 − 3 − 74 − 7 − 33 − 7 = 11,337` is accounted for,
either by one of the eight named drop reasons above or by surviving into the
3,321-row output. No row is unaccounted for.

Case-level, at the fine grain (province × municipality × item ×
`harmonized_nsu_unit` × `corrected_unit`):

```
2,020 cases (nsu_data_master.dta)
   − 1   ice cream mL, restate rescue-rule grain mismatch
 = 2,019 (nsu_weighings_cpi.dta)
   − 4   no usable weight (1 price-quantity case + 3 size-based cases)
 = 2,015
   − 11  unique_mun_price-only (price-quantity cases)
 = 2,004
   − 0   carrot (case survives via its size-based rows)
 = 2,004  cases in the Outcome 1 output
```

2,020 − 1 − 4 − 11 = 2,004, matching the 2,004 distinct cases actually present in
`nsu_reference_set.dta`.
