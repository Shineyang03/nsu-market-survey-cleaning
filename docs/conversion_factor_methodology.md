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

### Step B — apply to a PSPS household

**B1. Deflate the MS price points** into PSPS-round pesos (we adjust the MS side,
not each household: a case has at most three MS price points but many households,
so this is fewer operations). The weights $`w_s`$ are unchanged — grams do not
inflate:

```math
\tilde p_s = \frac{p_s}{1+\pi}, \qquad \tilde v_s = \frac{v_s}{1+\pi} = \frac{\tilde p_s}{w_s}
```

**B2. Match** the household's price to the nearest deflated MS price point — this
decides the size:

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
> Deflating the MS price points to PSPS pesos in B1 puts everything — the
> household's raw $`p_h`$, the matched price $`\tilde p_s`$, and the unit value
> $`\tilde v_s`$ — in one frame, so no further adjustment happens at the division.
> Inflating each household's $`p_h`$ into MS pesos instead would give the identical
> grams (grams are frame-invariant); we deflate the MS side only because it has
> fewer points:
> ```math
> \frac{p_h}{v_s / (1+\pi)} \;=\; \frac{(1+\pi)\,p_h}{v_s}.
> ```
> Two rules follow: **match and divide in the same frame** (deflate the MS points
> once in B1 and reuse $`\tilde v_s`$ in B3 — dividing by the un-deflated $`v_s`$
> would reintroduce the 2-year gap), and the method assumes PHP-per-gram for the
> item moved only with the general index $`1+\pi`$ (no differential *real* price
> change) — this is what makes both the match and the division valid.

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
