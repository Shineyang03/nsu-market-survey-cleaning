# NSU → Gram Conversion Factors: Methodology

**Purpose.** Convert quantities reported in non-standard units (NSUs) in the PSPS
household panel into grams, using the NSU Market Survey as the measurement source.

**Two desired outcomes:**

### Outcome 1 — Reference set for future data collection

A lookup key with columns

> municipality | market type | Item | NSU | Heterogeneity | Grams per unit (CF)

with one such key per province — **keeping within item-NSU heterogeneity**
(separate rows per size or price point, not one averaged scalar).

Use case: a respondent reports consuming 1 mango; the enumerator asks which size
(small/medium/large, e.g. with reference pictures) — or at what price — and the
answer is logged directly in grams (e.g., 1 small mango → 500 g of mango).

### Outcome 2 — Conversion factors for PSPS

A crosswalk: for each item-NSU-municipality observed in PSPS, a grams-per-unit
(CF) value — converting PSPS-reported NSU quantities into grams. PSPS does not need the market
survey's unique price values — **only the quantiles**: market-survey price levels
are never the quantity of interest (the deliverable is grams). Prices enter only
as matching devices that select which measured weight applies: the household's
own reported price (and, in the size-based approach, its position in the PSPS
price distribution) is matched against market-survey price points to pick the
corresponding gram weight.

---

## Outcome 2 in detail: three approaches, keyed to `weighing_approach`

Within each item-NSU-municipality, the conversion rule follows the protocol under
which the market survey measured that pair. Empirically the protocols partition
the cases — each of the 2,001 item-NSU-municipality cases uses exactly one
approach (conventional 124, price-based 319, size-based 1,558; no case mixes
approaches) — so the estimator choice is fully determined by the cell.

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
range (price points or size labels), and why approaches 2–3 must first locate the
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

```math
w = \begin{cases} w_c & \text{conventional NSU (weighing approach == 1): standard within the locality, so a single weight characterizes the cell} \\[4pt] w_\tau, \;\; \tau \in \{25, 50, 75\} & \text{price-varying NSU (weighing approach == 2): measured at price point } \tau \text{ of the municipality price distribution} \\[4pt] w_s, \;\; s \in \{S, M, L\} & \text{size-labeled NSU (weighing approach == 3): measured per size label} \end{cases}
```

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

### 2. Price-based (`weighing_approach == 2`; obs_type `mp25/mp50/mp75_price`, `municipality_median`, `province_median`)

For NSUs whose size scales with price (e.g., a pile/tumpok at different price
points). The price points $p_\tau$ are quantiles of the **municipality-level**
price distribution for the item-NSU (the P25/P50/P75 over all vendors in the
municipality), *not* any single vendor's prices; at each such municipal price
point the MS records the weight of what that price buys, giving pairs
$(p_\tau, w_\tau)$.

> **Empirical caveat — the three-point spread is the exception, not the rule.**
> In the launch data only ~11% of price-based cells carry ≥2 distinct price
> points and ~4% carry all three; **89% have a single price mark**, overwhelmingly
> `municipality_median` (or `province_median` as a fallback when the municipality
> was thin). So for most cells the machinery below collapses to a single
> proportional segment (one $v_\tau$ at the median), and the piecewise
> non-linearity it is designed to capture is *unobserved*. The full $p \mapsto w$
> curve is only identified in the minority of cells with multiple marks. This
> weakens the case for the price-based approach over simply anchoring PHP-per-gram
> at the median.

**Step 1.** Match the household to the nearest MS price point:

```math
\tau^\ast = \begin{cases} 25 & \text{if } \lvert p_h - p_{25} \rvert \text{ is smallest} \\ 50 & \text{if } \lvert p_h - p_{50} \rvert \text{ is smallest} \\ 75 & \text{if } \lvert p_h - p_{75} \rvert \text{ is smallest} \end{cases}
```

**Step 2.** Take the unit value at that point:

$$v_{\tau^\ast} = p_{\tau^\ast} / w_{\tau^\ast}$$

**Step 3.** Invert price into grams per unit (by A2):

$$\widehat{CF}_h = \frac{p_h}{v_{\tau^\ast}}$$

> **A2** — local price–quantity equivalence: in a neighborhood of price point
> $\tau^\ast$, variation in price per NSU reflects variation in grams at a constant
> PHP-per-gram, i.e. $w(p) = p / v_{\tau^\ast}$. In plain terms: *extrapolate
> proportionally along the price-per-gram ratio measured at the closest price
> point.* Where a cell has multiple price points the resulting $p \mapsto w$
> mapping is piecewise-proportional — each point has its own $v_\tau$, so
> non-linearity in the price–gram relationship (e.g., bulk discounting) is
> captured *across* the points, while proportionality is only assumed *within*
> each point's neighborhood. Where a cell has a single point (the common case —
> see empirical caveat above), the mapping is a single proportional segment and
> no non-linearity is captured.
> Price differences due to price level, timing, quality, or bargaining violate
> A2 (see caveats).

Consistency check: if $`p_h = p_{\tau^\ast}`$ exactly, then $`\widehat{CF}_h = w_{\tau^\ast}`$
— the household is assigned exactly the weight measured at that price point.

### 3. Size-based (`weighing_approach == 3`; obs_type `small/medium/large_size`)

The MS weighed one specimen per size label: $w_S, w_M, w_L$. PSPS does not record
size, so size is imputed from the household's position in the *PSPS* price
distribution within cell $c$.

**Step 1.** Compute PSPS price quantiles $P^{25}_c, P^{50}_c, P^{75}_c$.

**Step 2.** Assign the household to a size via its nearest quantile (by A3):

```math
s(h) = \begin{cases} S & \text{if } \lvert p_h - P^{25}_c \rvert \text{ is smallest} \\ M & \text{if } \lvert p_h - P^{50}_c \rvert \text{ is smallest} \\ L & \text{if } \lvert p_h - P^{75}_c \rvert \text{ is smallest} \end{cases}
```

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
   would violate this). Two remarks:
   - *Within a kink, price variation converts to grams one-for-one.* Matching
     to the nearest price point only selects the local slope $v_{\tau^\ast}$; the
     weight itself is $p_h / v_{\tau^\ast}$, so two households matched to the same
     price point but paying different unit prices are assigned proportionally different
     grams. Any within-kink price variation that is *not* quantity (bargaining,
     quality, misreporting) passes through proportionally into $\hat g_h$ —
     finer matching cannot fix this.
   - *The pooling level determines the strength of the assumption.* The finer
     the cell at which schedules are estimated and matched, the weaker the
     assumption needs to be. Since market type of purchase is missing in PSPS,
     matching is effectively at municipality × item-NSU pooled across market
     types (unless an assignment rule is adopted — see open decisions), and the
     single-schedule assumption must hold at that coarser level.
2. **Temporal alignment — PSPS prices must be inflation-adjusted before matching**
   (A2). PSPS prices come from recall periods that need not coincide with the
   market-survey field dates; under general price inflation the *price-based*
   method mechanically inflates implied grams (a nominally higher $p_h$ maps to
   more grams at fixed $v_{\tau^\ast}$). So deflate/inflate $p_h$ to the MS field
   window (e.g., regional CPI for the item group) as a pre-processing step, before
   any nearest-price-point matching. The *size-based* method is immune to proportional
   price-level shifts (quantiles shift together; the S/M/L weights are fixed) — a
   point in its favor as the workhorse (85% of market-survey obs are size-based).
3. **Quantile ↔ size mapping** (A3). "P25 = small" is a convention, not a
   measurement. If most transactions are, say, medium, the mapping misallocates
   the tails. Worth a robustness check (e.g., alternative mapping P33/P50/P67, or
   modal-size assumption).
4. **Conventional NSU standard within locality** (A1). The unit is taken as
   standard within its locality; it may still vary *across* municipalities —
   where the market survey weighed the same conventional unit in several
   municipalities, this is testable.
## Warning for downstream use of the CFs

**Measurement error in $p_h$ propagates into imputed grams.** $p_h = e_h / q_h$
is a derived unit value: misreporting in either the total value $e_h$ or the
quantity $q_h$ propagates into $p_h$, and from there into the gram imputation —
e.g., a household that rounds its total expenditure looks like it bought a
different-sized unit. Under the price-based approach the error passes through
proportionally into $\hat g_h$; under the size-based approach it can flip the
household across a quantile boundary into the wrong size bin.

## Practical prerequisites / open decisions

- **Unit-name harmonization.** The market survey has ~173 raw item × NSU-unit
  spellings for 19 items (Bilog/Binilog/…; municipality-specific variants). PSPS
  NSU strings must be mapped into these — likely after consolidating spelling
  variants. This is the reference-set deliverable (outcome 1).
- **Incomplete heterogeneity levels degrade gracefully via nearest-neighbor
  matching.** Not every cell has the full set of heterogeneity levels (all of
  S/M/L, or all three price points): some have, e.g., only a medium weighing, a
  single unique municipal price (`unique_mun_price6/7`), or only a
  `municipality_median` / `province_median` price. No special-casing is needed:
  the matching step is nearest-neighbor over whatever levels exist, so with a
  single level every household maps to it (the cell-level scalar case). The cost
  is assumption strength, not mechanics — with one level, the piecewise schedule
  collapses to one proportional segment (price-based) or one size bin
  (size-based) for the whole cell.
- **Market type as a heterogeneity dimension.** Market type of purchase is not
  recorded in PSPS. The open question is whether to treat market type as a
  separate dimension of heterogeneity in the matching: instead of
  nearest-neighbor over 3 price points (pooled across market types), match over
  all market type × price point combinations where available — up to 9 candidate
  points ($P25_{M_1}, P25_{M_2}, P25_{M_3}, P50_{M_1}, \ldots$) — letting the
  household's price implicitly select the market type along with the point on
  the schedule.
- **Multiple vendors per cell.** Within item-NSU-municipality × market type, 98%
  of cells have 1–3 distinct vendors (32% / 23% / 43% for 1/2/3), with 63 cells
  (1.7%) at 4–5; only 24% of item-NSU-municipality cases cover all three market
  types (41% have one). Aggregation rule: vendor-level $w$ is aggregated via
  **mean after dropping outliers**.
