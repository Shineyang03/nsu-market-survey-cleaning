# Data oddities and one-off decisions

A register of individual cases, coding conventions and small exclusions that a
reader would otherwise trip over. Each entry says what the oddity is, what was
decided, and — where it matters — **why not to "fix" it later**.

Methodology lives in `docs/conversion_factor_methodology.md`; this file is
deliberately separate so the methodology does not accumulate footnotes.

---

## 1. ILOILO / TIGBAUAN carrot — one case, two weighing approaches

The NSU harmonization folds two raw labels into one cell, and they were fielded
under different approaches:

| raw label | harmonized | approach | obs |
|---|---|---|---|
| `bilog` | `pieces or units` | size-based | 9 |
| `pieces or units` | `pieces or units` | price-quantity | 7 |

This is the **only** such case in 1,952, and the fold creates it — not the
fieldwork. At the raw and cleaned NSU grains every case is single-branch with zero
exceptions, and that holds when the grain is split further by `corrected_unit`.
Exported to `outputs/master_rename_build/tables/fold_multi_weighing_approach.xlsx`.

**Decision — split by deliverable rather than assigning the case a branch:**

- **Outcome 1 (reference set)** uses only the **9 size-based** observations. Its
  output is organised by size heterogeneity, and only size-based rows carry S/M/L.
- **Outcome 2 (PSPS conversion)** uses only the **7 price-quantity** observations.

Nothing is discarded and neither deliverable sees a mixed pool.

> **Do not "fix" the resulting mismatch.** For this one cell the reference weight
> and the conversion weight come from *different observations*, so they will not
> agree. That is the intended consequence of the rule above, not an error.

For Step A re-terciling this case has **9** weighings, not 16.

---

## 2. Zero means "not available", not zero

Two places in the raw data use `0` to record *the item was not observed at the
requested price or size*, rather than a measured value of zero.

**Weights.** Enumerators entered `0` weight when they could not find the item at the
specified price/size — 5 observations. `cleaning_Aug11.do` recodes these to `.c`.

**Prices.** One row carries `actual_price == 0`:

> NEGROS OCCIDENTAL / VALLADOLID / preserved or processed meat / `bilog`
> `pull_price = 16.5`, `approx_price = 1`
> comment: *"There is no 16.5 Frozen that cost"*

The vendor had nothing at ₱16.5. This is **not** a cleaning error and **not** a
price of zero. It falls inside the 95 rows dropped under §3 and needs no separate
handling.

---

## 3. When the preloaded price no longer held

`pull_price` is preloaded and system-filled — per
`NSU Market Survey Launch/data/nsu_long_data_description.pdf`, "the enumerator does
not enter this" — and it is per-NSU. It is verified to be exactly the value the
enumerator was sent to spend: `pull_price` matches the SurveyCTO case-file preload
in **1,176 of 1,176** matched rows, at 98.6% coverage.

The enumerator approached the vendor with that PSPS price. Sometimes the vendor no
longer sold the item at it, and the data records **two different outcomes**:

| situation | recorded as | price-quantity weighings | cases |
|---|---|---|---|
| vendor gave a **replacement price** | `actual_price` = that price | 95 of 1,220 (7.8%) | 41 of 315 (13.0%) |
| vendor gave **no price at all** | `approx_price` = 1 | 27 of 1,220 (2.2%) | 13 of 315 (4.1%) |

`approx_price` is a **0/1 flag**, not a price (27 ones, 230 explicit zeros). Only one
row carries both.

### 3a. Vendor named a replacement price — the rescue rule

These 95 rows break the premise B1 rests on: that a *fixed preloaded* amount was
spent, so the weight is what flexed. Here the vendor's own price governed, so the
weight is a property of whatever they handed over.

When `actual_price` is present it is usually close to the preloaded figure — median
ratio 1.037 — but 56 of 95 differ by ≥10%, 15 by ≥50%, max 4.93×.

**Decision: drop them, except where dropping would delete the case.**

- **74 rows dropped** — the case retains at least one preloaded-price hetero-group.
- **21 rows kept and flagged** — these were the case's *only* hetero-group, so
  dropping them removed 6 cases outright.

The objection to using `actual_price` is that it puts two different prices inside one
hetero-group's median, and `p_g` is defined as one price per case × hetero-group.
That objection only bites where a preloaded hetero-group *survives to be mixed with*.
Where nothing survives there is nothing to mix, and losing the case entirely is the
worse outcome.

A `price_source` variable records which peso figure is `p_g` for every
price-quantity row — `preloaded` or `vendor_actual` — so no downstream step can
mistake a vendor quote for a preloaded price. All 315 price-quantity cases survive.

> **Known defect in this rule.** `has_preloaded` in `nsu_restate_weights.do` is
> computed on province × municipality × item × `harmonized_nsu_unit`, **omitting
> `corrected_unit`** — a coarser grain than the case grain it protects. One cell is
> affected today: NEGROS OCCIDENTAL / ENRIQUE B. MAGALONA (SARAVIA) / ice cream /
> `putos` / mL. Its **g** sub-cell has a preloaded row, so the rule concluded the
> case was safe and dropped the mL row, deleting that cell — exactly the loss the
> rescue rule exists to prevent. The "lost its only hetero-group" check uses the same
> key, so it reports 0 and is structurally blind to this. Found independently by two
> reviewers. Fix: add `corrected_unit` to both the `bysort` and the check.

### 3b. Vendor gave no price — nothing can be recovered

Where `approx_price == 1` the vendor said the item was unavailable at the preloaded
price and offered no alternative. There is no valid `p_g` for that weighing: the
grams that were recorded do not correspond to the preloaded peso figure, and no
replacement figure exists.

The `actual_price == 0` row is this case, not a price of zero:

> NEGROS OCCIDENTAL / VALLADOLID / preserved or processed meat / `bilog`
> `pull_price = 16.5`, `approx_price = 1`, `actual_price = 0`
> comment: *"There is no 16.5 Frozen that cost"*

Zero encodes "not available", the same convention §2 describes for weights.

**Decision: drop them.** There is no price to pair the weight with and no way to
recover one, so the weighing cannot support a conversion factor.

26 of the 27 carry no `actual_price`, so the §3a rule never sees them — as built they
survive with `price_source == "preloaded"`, i.e. treated as though the preloaded
price held, which is exactly what the vendor denied. They must be dropped explicitly.
13 cases are affected; check whether any loses its only hetero-group as a result, the
same check §3a applies.

> **Not yet implemented.** As of this writing the 26 rows are still present in
> `nsu_weights_restated.dta`. Tracked with the rescue-rule grain defect above, since
> both are changes to the same file.

### 3c. Cross-hetero-group contamination is a 1-case problem

The worry that one hetero-group might carry a repriced value while another does not
affects exactly **1** case, out of the 38 that have ≥2 hetero-groups at all. In 35 of
the 41 affected cases the mixing is *within* a hetero-group — different vendors, some
commented and some not.

---

## 4. Mixed-dimension items: two sets of conversion factors

Two items were recorded in **both** mass and volume, and are left without a
dimension verdict, so every row keeps whatever the enumerator recorded:

| item | mass obs | volume obs |
|---|---|---|
| drinks at restaurant, hotel, cafe or kiosk | 25 | 164 |
| ice cream, sorbet, edible ice | 324 | 554 |

Since `corrected_unit` is part of the re-terciling grain, these items produce
**separate g and mL cells** — i.e. two conversion factors per case, one for each
dimension. That is intended.

Cost of the split, measured:

| item | pooled g+mL | split g \| mL |
|---|---|---|
| ice cream | 229 cells — 32 three-tercile / 111 two / 86 scalar | 278 cells — 21 / 113 / 144 |
| drinks at restaurant | 41 cells — 11 / 8 / 22 | 49 cells — 10 / 8 / 31 |

So roughly 11 cells lose a three-way size split and ~58 fall back to a single
scalar. Accepted in exchange for not pooling mass with volume.

Ice cream was unverdicted in the pre-Aug11 build too, so this continues existing
behaviour rather than introducing a new choice. **Beer** previously appeared here
and no longer does — its `bottle (500 ml)` rows were standard-quantity labels and
are excluded under §5.

---

## 5. Standard-quantity labels excluded

33 weighings across 10 raw labels name their own quantity and are therefore not
non-standard units at all — `bottle (500 ml)`, `1.5kg per balde`,
`1/2 sack of rice (25kls.)`, `bottle of ginebra s. miguel 350ml`, `pieces/ kilo`,
`1/4 kilo`, `6 liters of water (2 blue containers)`, `each 10 litres of gallon`.
Listed in `outputs/master_rename_build/tables/excluded_standard_unit_obs.xlsx`.

They are dropped **before** the order-of-magnitude snap, so they can never become an
anchor for it. They are reconciled by hand on the PSPS side at merge time.

This exclusion resolved two problems that had needed separate handling:

- **ILOILO / TUBUNGAN mineral water** — the same NSU was recorded as ~21 kg by four
  vendors and 0.006 L by three, contaminating the snap anchor so the kg readings
  collapsed to ~21 mL. The label was `6 liters of water (2 blue containers)`, a
  standard quantity, so the exclusion removes it.
- **Beer** stopped being a mixed-dimension item (see §4).

---

## 6. Other single-row fixes

**TIGBAUAN fresh fish `bilog`** — rows with no stated price, apparently a SurveyCTO
glitch. Dropped in `cleaning_Aug11.do`.

**CAPIZ / PANAY distilled water, 0.007 L** — a manual correction that the pre-Aug11
build targeted by row id. Row ids are `_n` and are not stable: the two saved copies
of the old build disagree about which observation id 4242 is. Re-targeted on content
instead. Note `weight` is a **float**, so `weight == 0.007` matches nothing —
`float(0.007)` is required, with an `assert` so a future miss halts rather than
silently doing nothing.

**`fish  sold per pack 90 each  pack`** — a double-spaced NSU name. The Python
normalizer collapses internal whitespace and Stata's `ustrtrim` does not, so this
one weighing failed to match its rename row. `nsu_normalize` now mirrors the Python
operation order exactly.

---

## 7. CPI series with no survey item

`01.1.7.3 - Green leguminous vegetables` exists in the PSA extract and is highly
volatile (Aklan +77% in one month), but **no survey item maps to it**, so it never
enters any calculation. It appeared in an early draft as a motivating example for
the moving-average variant; it should not be used that way.

The largest single-month moves among series the panel *does* carry are Aklan other
vegetables +37.6% (2025m8), Aklan tubers +35.4% (2025m8), and Antique other
vegetables +24.3% (2025m12) followed by −20.0% (2026m1).

---

## 8. The CPI panel is 75 pairs, not 5 × 16

Each province uses exactly **15** COICOP groups; the union across provinces is 16.
The extra group exists only because PSA publishes an ice-cream index (`01.1.8.6`)
for four provinces but **not for Iloilo**, which falls back to the parent
sweets/confectionery index (`01.1.8`).

So 5 × 15 = 75 province × group pairs. The 5 combinations absent from a naive 5 × 16
grid — four provinces × sweets-parent, and Iloilo × ice-cream — are absent because
nothing maps to them, not because data is missing.

This is also why the item crosswalk must be joined on `(province, cons_name)` and
never on `cons_name` alone.
