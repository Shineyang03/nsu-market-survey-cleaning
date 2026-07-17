# NSU → Gram Conversion Factors: Methodology

**Purpose.** Convert quantities reported in non-standard units (NSUs) in the PSPS
household panel into grams, using the NSU Market Survey as the measurement source.

**Two desired outcomes:**

### Outcome 1 — Reference set for future data collection

A lookup table of gram weights per item-NSU, by municipality × market type,
**keeping within item-NSU heterogeneity** (separate entries per size or price
point, not one averaged scalar).

Use case: a respondent reports consuming 1 mango; the enumerator asks which size
(small/medium/large, e.g. with reference pictures) — or at what price — and the
answer is logged directly in grams (e.g., 1 small mango → 500 g of mango).

### Outcome 2 — Conversion factors for PSPS

Convert PSPS-reported NSU quantities into grams. PSPS does not need the market
survey's unique price values — **only the quantiles**: market-survey price levels
are never the quantity of interest (the deliverable is grams). Prices enter only
as matching devices that select which measured weight applies: the household's
own reported price (and, in the size-based approach, its position in the PSPS
price distribution) is matched against market-survey price points to pick the
corresponding gram weight.

---

## Outcome 2 in detail: three approaches, keyed to `weighing_approach`

Within each item-NSU-municipality, the conversion rule follows the protocol under
which the market survey measured that pair (one or more of three).

**Why $w$ is measured at multiple points (the motivation for everything below).**
When a household records consumption of an item in an NSU, PSPS observes the
total value paid ($e_h$, PHP) and the quantity ($q_h$, number of NSU units that
cost that total) — from which the price per unit $p_h = e_h / q_h$ is derived.
Grams are never recorded, and within a cell the only household-level observable
that co-varies with the gram content of a unit (a small vs. a large pile) is
this unit price — so grams must be inferred *through prices*. If PHP per gram
were constant within a cell, one
scalar would convert any price to grams and a single $w$ would suffice. In
reality PHP per gram varies with how many grams one unit contains (e.g., bulk
discounting: a large pile is cheaper per gram than a small one) — equivalently,
the estimand $CF$ faced by households is **non-linear in the unit's price**.
This non-linearity is why the MS measured $w$ at several points of each unit's
range (price marks or size labels), and why approaches 2–3 must first locate the
household on that range before converting.

### Notation

Fix a cell $c = (x, n, m)$: item $x$, NSU $n$, municipality $m$ (refined by market
type $M$ where available).

**Price-unit convention.** Two different "prices" appear throughout; they are
never interchangeable:

- $p$ (and its variants $p_\tau$, $p_h$, $P^{25}_c$…) is always **PHP per 1 unit
  of $n$** — the sticker price of one pile/piece/pack.
- $v$ is always **PHP per gram** — a unit value, only ever *derived* as
  $v = p / w$.

**Market survey (MS), within cell $c$:**

$w$ always denotes **weight in grams per 1 unit of $n$** [observed]. Its
subscript says at which variant of the unit it was measured:

$$w = \begin{cases} w_c & \text{conventional NSU (weighing\_approach == 1): standard within the locality, so a single weight characterizes the cell} \\[4pt] w_\tau, \;\; \tau \in \{25, 50, 75\} & \text{price-varying NSU (weighing\_approach == 2): measured at price point } \tau \text{ of the vendor's offer distribution} \\[4pt] w_s, \;\; s \in \{S, M, L\} & \text{size-labeled NSU (weighing\_approach == 3): measured per size label} \end{cases}$$

Two auxiliary MS objects (price-varying units only):

| Symbol | Definition |
|---|---|
| $p_\tau$ | price, **PHP per 1 $n$**, at price point $\tau$ [observed] |
| $v_\tau \equiv p_\tau / w_\tau$ | unit value, **PHP per gram**, at price point $\tau$ [derived] |

**PSPS, household $h$ in cell $c$:**

| Symbol | Definition |
|---|---|
| $e_h$ | reported total value of consumption, PHP [observed] |
| $q_h$ | reported quantity, in units of $n$ [observed] |
| $p_h = e_h / q_h$ | price per unit, **PHP per 1 unit of $n$** [derived] |
| $P^{25}_c, P^{50}_c, P^{75}_c$ | quantiles of the PSPS distribution of $p_h$ within cell $c$ [derived] |
| $s(h)$ | size of the unit bought [missing — imputed via A3] |

**Target object.** The conversion factor is defined as

$$CF \equiv \text{grams per 1 unit of } n .$$

$CF$ and $w$ share the same units (grams per 1 unit of $n$) but play different
roles:

- **Estimand** — $CF_h$: grams per unit in household $h$'s actual transaction.
  Never observed.
- **Data** — the $w$'s: weights of the specimens the MS weighed.
- **Estimator** — $\widehat{CF}_h$: each approach below is a rule mapping the
  data to an estimate of the estimand (scalar within the cell under approach 1,
  household-specific under approaches 2 and 3).

The deliverable (implied grams) is then always

$$\hat g_h = q_h \cdot \widehat{CF}_h .$$

### 1. Conventional NSU (`weighing_approach == 1`, e.g. gantang, salop, salmon)

There is no within-unit heterogeneity to model: the unit is essentially standard
within the locality, so a single gram weight $w_c$ characterizes it (measured
weighings within the cell are averaged/medianed into $w_c$).

$$\widehat{CF}_h = w_c \quad \text{for all } h \text{ in cell } c \qquad \text{(by A1)}$$

> **A1** — $n^{PSPS} = n^{MS}$: the unit the household reports is the same
> physical unit the market survey weighed (by definition of "conventional,"
> standard within the locality).

### 2. Price-based (`weighing_approach == 2`; obs_type `mp25/mp50/mp75_price`)

For NSUs whose size scales with price (e.g., a pile/tumpok at different price
points). The MS provides pairs $(p_\tau, w_\tau)$, $\tau \in \{25, 50, 75\}$.

**Step 1.** Match the household to the nearest MS price point:

$$\tau^* = \arg\min_{\tau \in \{25,50,75\}} \; \lvert p_h - p_\tau \rvert$$

**Step 2.** Take the unit value at that point:

$$v_{\tau^*} = p_{\tau^*} / w_{\tau^*}$$

**Step 3.** Invert price into grams per unit: $\;$ (by A2)

$$\widehat{CF}_h = \frac{p_h}{v_{\tau^*}}$$

> **A2** — local price–quantity equivalence: in a neighborhood of price point
> $\tau^*$, variation in price per NSU reflects variation in grams at a constant
> PHP-per-gram, i.e. $w(p) = p / v_{\tau^*}$. In plain terms: *extrapolate
> proportionally along the price-per-gram ratio measured at the closest price
> mark.* The resulting $p \mapsto w$ mapping is piecewise-proportional — each
> price mark has its own $v_\tau$, so non-linearity in the price–gram
> relationship (e.g., bulk discounting) is captured *across* the three marks,
> while proportionality is only assumed *within* each mark's neighborhood.
> Price differences due to price level, timing, quality, or bargaining violate
> A2 (see caveats).

Consistency check: if $p_h = p_{\tau^*}$ exactly, then $\widehat{CF}_h = w_{\tau^*}$
— the household is assigned exactly the weight measured at that price point.

### 3. Size-based (`weighing_approach == 3`; obs_type `small/medium/large_size`)

The MS weighed one specimen per size label: $w_S, w_M, w_L$. PSPS does not record
size, so size is imputed from the household's position in the *PSPS* price
distribution within cell $c$.

**Step 1.** Compute PSPS price quantiles $P^{25}_c, P^{50}_c, P^{75}_c$.

**Step 2.** Assign the household to a size via its nearest quantile: $\;$ (by A3)

$$s(h) = \begin{cases} S & \text{if } \lvert p_h - P^{25}_c \rvert \text{ is smallest} \\ M & \text{if } \lvert p_h - P^{50}_c \rvert \text{ is smallest} \\ L & \text{if } \lvert p_h - P^{75}_c \rvert \text{ is smallest} \end{cases}$$

**Step 3.** Apply the size's measured weight:

$$\widehat{CF}_h = w_{s(h)}$$

> **A3** — quantile–size equivalence: the household at the 25th percentile of the
> PSPS price distribution bought the "small" specimen, P50 ↔ M, P75 ↔ L; i.e.
> $NSU_{P25}^{PSPS} = NSU_{S}^{MS}$ (and correspondingly for M, L).

---

## Assumptions to keep visible

1. **Single price schedule within cell** (A2, A3). We assume that within a
   municipality × market type × item-NSU pair, all households face the *same*
   non-linear price schedule; so if two households pay different PHP per gram,
   it is because they bought at different points (kinks) of that schedule —
   i.e., units containing different grams — not because they paid different
   prices for the same grams (bargaining, quality, timing, vendor differences
   would violate this). Mitigation: match within municipality × market type
   where possible.
2. **Temporal alignment** (A2). PSPS prices come from recall periods that may not
   coincide with the market-survey field dates. Under general price inflation the
   *price-based* method mechanically inflates implied grams (a nominally higher
   $p_h$ maps to more grams at fixed $v_{\tau^*}$). The *size-based* method is
   immune to proportional price-level shifts (quantiles shift together; the S/M/L
   weights are fixed) — a point in its favor as the workhorse (85% of
   market-survey obs are size-based).
3. **Quantile ↔ size mapping** (A3). "P25 = small" is a convention, not a
   measurement. If most transactions are, say, medium, the mapping misallocates
   the tails. Worth a robustness check (e.g., alternative mapping P33/P50/P67, or
   modal-size assumption).
4. **Conventional NSU standard within locality** (A1). The unit is taken as
   standard within its locality; it may still vary *across* municipalities —
   where the market survey weighed the same conventional unit in several
   municipalities, this is testable.

## Practical prerequisites / open decisions

- **Unit-name harmonization.** The market survey has ~173 raw item × NSU-unit
  spellings for 19 items (Bilog/Binilog/…; municipality-specific variants). PSPS
  NSU strings must be mapped into these — likely after consolidating spelling
  variants. This is the reference-set deliverable (outcome 1).
- **Coverage gaps and fallback hierarchy.** Many item-NSU pairs are observed under
  only one approach or only in some municipality × market-type cells (see
  `outputs/graphs/heatmap_*`). Proposed fallback when the target cell is empty:
  own municipality (pooling market types) → `municipality_median` /
  `province_median` observations (already collected as obs_types) → province pool.
  To be finalized.
- **Market type in PSPS.** If PSPS does not record where the household bought the
  item, a weighting/priority rule across market types is needed (e.g., public
  market first, or obs-weighted average across types).
- **Multiple vendors per cell.** Within item-NSU-municipality-market type, weights
  come from up to 3 vendors × 3 market types — aggregate vendor-level `w` (median
  across vendors) before applying, or keep vendor spread as an uncertainty band.
- **`unique_mun_price6/7` obs_types** (36 obs): role in this scheme to be
  clarified.
