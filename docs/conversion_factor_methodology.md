# NSU → Gram Conversion Factors: Methodology

**Purpose.** Convert quantities reported in non-standard units (NSUs) in the PSPS
household panel into grams, using the NSU Market Survey as the measurement source.

## Two deliverables

**Outcome 1 — reference set for future data collection.** A lookup key, one per
province, with columns

> municipality | market type | item | NSU | size | grams per unit

keeping within-item heterogeneity (a row per size, not one averaged scalar). Use
case: a respondent reports 1 mango; the enumerator asks the size (small / medium /
large, e.g. with reference pictures) and logs the answer directly in grams.

**Outcome 2 — conversion factors for PSPS.** For each item-NSU-municipality
observed in PSPS, a grams-per-unit value, so PSPS NSU quantities can be turned
into grams retrospectively. This is the pipeline documented below.

---

## Notation

A **case** $`c`$ is a province × municipality × item × NSU combination.

**Market survey (MS) side**, per size $`s \in \{S, M, L\}`$ within a case:

- $`w_s`$ — grams per NSU (the weight of a size-$`s`$ unit)
- $`p_s`$ — price, **PHP per NSU**, of a size-$`s`$ unit (in MS-round pesos)
- $`v_s \equiv p_s / w_s`$ — unit value, **PHP per gram**

**PSPS side**, household $`h`$ in case $`c`$:

- $`q_h`$ — quantity the household reports buying, in NSU units
- $`e_h`$ — total value it paid for that quantity (PHP)
- $`p_h \equiv e_h / q_h`$ — implied price, **PHP per NSU** (in PSPS-round pesos)
- $`\pi`$ — cumulative inflation *rate* between the PSPS round and the MS round
  (the MS was fielded ~2 years *after* PSPS), so $`1+\pi`$ is the price factor;
  dividing an MS-round price by $`1+\pi`$ restates it in PSPS-round pesos. A tilde
  marks such a deflated MS quantity: $`\tilde p_s \equiv p_s / (1+\pi)`$ and
  $`\tilde v_s \equiv v_s / (1+\pi)`$

Throughout, **$`p`$ is always PHP per NSU** and **$`v`$ is always PHP per gram** —
they are never interchangeable.

---

## Conventional NSU (the simple case)

Some NSUs are effectively standard within a locality (gantang, salop, salmon …).
There is no size to resolve: a single weight $`w_c`$ characterizes the unit, so

```math
\widehat{CF}_h = w_c \quad\text{for every household in the case.}
```

Everything below concerns the non-standard case, where a unit's grams vary with
its size / price.

---

## The pipeline (size / price-varying NSUs)

### Step A — build the reference from the market survey

Within a case, **pool all weighings** — across market types, vendors, and the
survey's original heterogeneity labels — into one weight distribution. Let $`w`$
be a pooled weighing and let $`Q_{1/3}, Q_{2/3}`$ be the terciles of that
distribution. **Relabel each weighing by its weight tercile:**

```math
\text{size}(w) = \begin{cases}
S & \text{if } w \le Q_{1/3} \\[4pt]
M & \text{if } Q_{1/3} < w \le Q_{2/3} \\[4pt]
L & \text{if } w > Q_{2/3}
\end{cases}
```

For each size $`s`$, take its representative weight $`w_s`$ (the tercile median)
and its price $`p_s`$ (PHP per NSU), giving the unit value $`v_s = p_s / w_s`$.
Because bigger units cost more, the three prices order as $`p_S \le p_M \le p_L`$;
these are the case's price points (**$`S \leftrightarrow`$ MP25,
$`M \leftrightarrow`$ MP50, $`L \leftrightarrow`$ MP75**).

This re-terciling is deliberate: the survey's own S/M/L labels overlap heavily in
weight across vendors, so we re-derive the sizes from the pooled weights rather
than trust the labels.

#### Where $`w_s`$ and $`p_s`$ actually come from

The market survey used one of three **weighing approaches** per case, and a case
uses exactly one of them. The approach decides where the pair $`(w_s, p_s)`$ comes
from — and, critically, **which peso frame $`p_s`$ is already in**:

| approach | share of cases | $`w_s`$ | $`p_s`$ | frame of $`p_s`$ |
|---|---|---|---|---|
| conventional | 123 (6%) | the single $`w_c`$ | none needed | — |
| price-quantity based | 314 (16%) | weight bought at each price point | the peso amount the enumerator **actually spent**, recorded in the MS | **MS round** |
| size-based | **1,515 (78%)** | tercile median (above) | **not in the MS at all** — must be joined from the price file | **PSPS round** |

For size-based cases the enumerator was asked for a *small / medium / large* unit,
never for a peso amount, so no price was recorded (the MS `pull_price` field is
empty for them by construction). Their price points therefore have to be joined in
from the price file, where they are PSPS-derived percentiles that were never spent
in the MS round.

#### Which price points exist for a case

The price file does not carry a mp25/mp50/mp75 triple for every case. Point
selection followed the field protocol below, so **the set of available price points
is itself a signal of how thin or how homogeneous the PSPS data was for that cell**:

- **≥3 unique PSPS prices in the municipality** → record p25, p50, p75 — *unless*
  the interquartile range is ≤ ₱40, in which case record only the municipality
  median. (₱20 — the smallest bill and a common coin — was taken as the smallest
  meaningful gap between quartiles; ₱40 is two of those. There is no strong prior
  behind the threshold beyond that.)
- **≤2 unique PSPS prices in the municipality** → record the province median
  alongside the 1–2 municipal prices — *unless* those municipal prices sit within
  ₱20 of the province median, in which case record only the province median.

So a case whose only price point is a municipality or province median is one where
few PSPS respondents used that NSU in that cell, or where the prices they reported
barely varied.

#### Degrading gracefully: the size ladder

Two things independently limit how many sizes a case can support — how many
weighings it has, and how many price points exist. Take the **weaker** of the two.

By weighings (size-based cases, split by measurement dimension):

| weighings in the case | sizes resolved |
|---|---|
| ≥ 6 — 45% of cases | three terciles, S/M/L |
| 3–5 — 31% of cases | two groups, median split |
| < 3 — 24% of cases | one case-level scalar |

By available price points: a case with a full p25/p50/p75 triple can carry three
sizes; a case with **only a municipality or province median carries one**. In that
case the sizes are not separated at all — pool every size-based weighing in the
cell across vendors, market types and the original S/M/L labels, take the median of
that single pooled weight distribution, and map it to the one available price point.
The result is a case-level scalar $`\widehat{CF} = \text{median}(w)`$, which is the
same object the conventional-NSU branch produces.

This matters more than it looks: fewer than half of size-based cases can support a
genuine three-way tercile, so the scalar and two-group rungs are the common case,
not the exception.

### Step B — apply to a PSPS household

**B1. Restate the MS price points** into PSPS-round pesos. The weights $`w_s`$ are
unchanged — grams do not inflate:

```math
\tilde p_s = \frac{p_s}{1+\pi}, \qquad \tilde v_s = \frac{v_s}{1+\pi} = \frac{\tilde p_s}{w_s}
```

Three things about this step that the notation hides:

1. **Only the price-quantity branch needs it.** $`p_s`$ is in MS-round pesos only
   where the enumerator actually spent the money — 16% of cases. For the 78% that
   are size-based, $`p_s`$ comes from the price file and is *already* in PSPS-round
   pesos, so restating it again would double-count the gap. Which branch a case is
   on therefore decides whether B1 applies at all. **This is the single
   highest-leverage decision in the pipeline: it is the difference between the
   inflation adjustment touching ~11% of weighings and touching all of them.**
2. **$`\pi`$ is not one number, and it is often negative.** Measured on the PSA
   province × COICOP food CPI over the median-to-median window (PSPS 2024m5 → MS
   2026m4), the median across province × group is **+7.4%**, but the range is
   **−18.1% to +58.1%**, and 6 of 16 groups have a negative median: rice −6.8%,
   fresh meat −4.0%, other meat −2.9%, sugar/confectionery −2.4%, ice cream −1.9%,
   water ≈ 0. Signs flip *within* a group across provinces — leafy vegetables run
   −9.4% in Iloilo and +58.1% in Antique. So $`\pi`$ must be province × COICOP
   specific; a pooled or national figure would be wrong in both directions, and
   "deflate" is a misnomer for a factor that is frequently below 1. Prefer naming
   any precomputed column `price_psps_frame` (or `_restated`) over `_deflated`.
3. **$`\pi`$ is household-specific, so B1 does not save operations.** PSPS fielding
   ran 2023m12–2025m1 and is **bimodal** (Dec 2023–Jul 2024, then Oct 2024–Jan
   2025), and which mode a province sits in differs: Aklan appears only in the
   early wave, Negros Occidental only in the late one. There is no single "PSPS
   round" month, so $`\tilde p_s`$ varies household by household just as $`p_h`$
   does. Moving the PSPS anchor across its range moves $`\pi`$ by **15.6 pp** for
   other vegetables, 10.5 pp for tubers, 9.3 pp for fruits. Since the operation
   count is the same either way and grams are frame-invariant, it is equivalent —
   and cheaper in variables — to inflate $`p_h`$ into the MS frame instead:
   $`p_h^{MS} = p_h(1+\pi)`$, match against the un-restated $`p_s`$, and divide by
   $`v_s`$. That leaves $`p_s`$ and $`v_s`$ as clean case-level constants fit to
   publish in the Outcome-1 reference table with no peso-frame caveat attached.

The index itself is sound for this use: the PSA series is a fixed-base level index
(range 83–308, median 137 at 2023m12 rising to 148 at 2026m1) with no base break at
the 2026 boundary (median month-on-month change +1.3% there vs +0.0% elsewhere), so
ratios across the window are valid. Coverage is **complete** — all 5 provinces × 16
COICOP groups — because the `cons_name → item_group` crosswalk is province-specific
by design: ice cream maps to `01.1.8.6` everywhere except Iloilo, which has only the
parent `01.1.8`. The two rows are complementary, not redundant, so no fallback
ladder is needed.

**B2. Match** the household's price to the nearest MS price point, both sides in one
frame — this decides the size:

```math
s(h) = \underset{s \in \{S, M, L\}}{\arg\min} \; \bigl\lvert p_h - \tilde p_s \bigr\rvert
```

**B3. Convert** price into grams using that size's (deflated) PHP-per-gram value:

```math
\widehat{CF}_h = \frac{p_h}{\tilde v_{s(h)}}
\qquad\Longrightarrow\qquad
\widehat g_h = q_h \cdot \widehat{CF}_h
```

$`\widehat{CF}_h`$ is the grams in one NSU unit; $`\widehat g_h`$ is the
household's total grams.

> **Why we adjust only once, on the MS side (the doubt, resolved).** Grams are
> physical — they do not inflate — so the division returns grams only if numerator
> and denominator are in the *same* peso-frame, letting pesos cancel:
> ```math
> \frac{\text{PHP}_{\text{PSPS}} / \text{NSU}}{\text{PHP}_{\text{PSPS}} / \text{g}} = \text{g} / \text{NSU}.
> ```
> Restating the MS price points into PSPS pesos in B1 puts everything — the
> household's raw $`p_h`$, the matched price $`\tilde p_s`$, and the unit value
> $`\tilde v_s`$ — in one frame, so no further adjustment happens at the division.
> Inflating each household's $`p_h`$ into MS pesos instead gives the **identical**
> grams, because grams are frame-invariant:
> ```math
> \frac{p_h}{v_s / (1+\pi)} \;=\; \frac{(1+\pi)\,p_h}{v_s}.
> ```
> **Which side you adjust is therefore free, and the original "the MS side has
> fewer points" argument does not hold.** It assumed $`\pi`$ is constant within a
> case, so that three $`\tilde p_s`$ values could be computed once and reused. They
> cannot: $`\pi`$ depends on the household's own PSPS submission month, and those
> months are spread over 2023m12–2025m1 *within* a cell (see B1 note 3), so
> $`\tilde p_s`$ is as household-specific as $`p_h`$. Adjusting $`p_h`$ is the
> cheaper of the two equivalent routes — one derived variable instead of up to
> three — and it leaves $`p_s`$ and $`v_s`$ frame-free for the reference table.
>
> Two rules follow regardless of which route is taken: **match and divide in the
> same frame** (whichever side you move, use the moved values in *both* B2 and B3 —
> matching on restated prices and then dividing by an un-restated $`v_s`$ would
> reintroduce the whole gap), and the method assumes PHP-per-gram for the item
> moved only with its province × COICOP index (no differential *real* price change
> within the group) — this is what makes both the match and the division valid.

**Consistency check.** If $`p_h = \tilde p_{s(h)}`$ exactly, then
$`\widehat{CF}_h = w_{s(h)}`$ — the household is assigned exactly the weight the MS
measured for that size.

---

## Assumptions to keep visible

1. **Single price schedule within the case.** All households in a case face the
   same price-per-gram schedule, so different PHP-per-gram means different sizes
   bought, not different prices for the same grams. Bargaining, quality, and
   vendor differences violate this; within a matched size, any price variation
   that is *not* size passes proportionally into $`\widehat g_h`$.
2. **Temporal alignment.** The two rounds are ~2 years apart, so prices must be
   put in a common frame before matching (Step B1 deflates the MS price points to
   PSPS terms); the item's real price-per-gram is assumed to have moved only with
   the general index between rounds.
3. **Weight terciles ↔ sizes.** Defining S / M / L as bottom / middle / top thirds
   of the pooled weights is a convention; if transactions concentrate in one size,
   the tercile cut misallocates the tails. Worth a robustness check (alternative
   cuts, or a modal-size assumption).
4. **Conventional units standard within locality.** Taken as standard within a
   locality; they may still vary *across* municipalities, which is testable where
   the MS weighed the same unit in several municipalities.
5. **Rank-pairing of sizes to price points (size-based cases only).** Pairing the
   $`k`$-th weight tercile from the MS with the $`k`$-th price percentile from the
   PSPS price file assumes the two distributions are *monotonically aligned* —
   that the households who paid the 25th-percentile price are the ones who bought
   the lightest units. Nothing in the data establishes this; the two distributions
   come from different rounds and different respondents, and only their rank order
   links them. If size and price are only weakly related in a cell (bargaining,
   quality, vendor differences — see assumption 1), the pairing misassigns, and it
   does so systematically rather than noisily. This assumption does **not** apply
   to the price-quantity branch, where $`w_s`$ and $`p_s`$ were observed together
   in the same transaction.
6. **Unit size stable between rounds (size-based cases only).** Because $`w_s`$ is
   measured in the MS round while $`p_s`$ comes from the PSPS round, the ratio
   $`v_s = p_s/w_s`$ is only a valid PSPS-round price-per-gram if the physical size
   of a "small"/"medium"/"large" unit did not change between rounds. Shrinkflation
   — vendors holding the peso price and reducing the unit — would make $`w_s`$ too
   small and $`v_s`$ too high. Note the symmetry with assumption 2: the
   price-quantity branch assumes the *price* schedule moved only with the index,
   while the size-based branch assumes the *quantity* schedule did not move at all.
   Neither branch is assumption-free; they lean on different things.

## Warning for downstream use

**Measurement error in $`p_h`$ propagates into grams.** $`p_h = e_h / q_h`$ is a
derived unit value: misreporting $`e_h`$ or $`q_h`$ feeds into $`p_h`$, which can
flip the household across a size boundary in B2 and scales $`\widehat g_h`$
proportionally in B3.

## Practical prerequisites

- **Unit-name harmonization.** The MS has ~173 raw item × NSU spellings for 19
  items; PSPS NSU strings must be mapped onto these after consolidating spelling
  variants (this is Outcome 1).
- **Incomplete sizes degrade gracefully.** Not every case has all of S / M / L;
  matching is nearest-neighbor over whatever price points exist, so a case with a
  single point maps every household to it (a case-level scalar).
- **Multiple vendors.** Vendor-level weights within a case are aggregated with a
  robust estimator (median, or a fixed light-trimmed mean); the pooling in Step A
  already dilutes single-vendor outliers.
