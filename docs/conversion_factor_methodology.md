# NSU → Gram Conversion Factors: Methodology

**Purpose.** Convert quantities reported in non-standard units (NSUs) in the PSPS
household panel into grams, using the NSU Market Survey as the measurement source.

**Two desired outcomes:**

1. A **reference set** of item-NSU conversion factors for future data collection.
2. Conversion factors that **preserve within item-NSU heterogeneity** — a "small
   mango" and a "large mango" sold as the same NSU (piece/bilog) should convert to
   different gram amounts. The conversion factor is therefore a *function* of an
   observable in PSPS (price paid, or price quantile), not a single scalar per
   item-NSU.

**Target object.** For item *x*, NSU *n*, municipality *m*, market type *M*:

> cf_xn(·) = grams per 1 unit of *n* of item *x*, in (*m*, *M*), possibly varying
> with the price/size at which the unit is transacted.

Example query: *how many grams is a small mango (or a mango costing P xx) bought in
municipality m at market type M?*

Note: PSPS uses only the **quantiles** of its own price distribution (and each
household's reported price), never the market survey's raw price levels as
quantities of interest — market survey prices only serve to anchor weights.

---

## Three approaches, keyed to `weighing_approach`

Each item-NSU-municipality in the market survey was measured under one (or more)
of three protocols. The conversion rule in PSPS mirrors the protocol.

### 1. Conventional NSU (`weighing_approach == 1`, e.g. gantang, salop, salmon)

These units are physically standardized, so one weighing suffices.

- **From the market survey:** weigh the unit once → `cf = g per 1 n` (e.g., 1
  gantang of rice = *w* g).
- **Apply to PSPS:** by definition of "conventional," the gantang a PSPS household
  reports is the same physical unit as the gantang weighed in the market survey
  (`n_psps == n_nsu`). So:

  `qty_g = qty_n × cf`

- No heterogeneity within the unit — the cf is a scalar.

### 2. Price-based (`weighing_approach == 2`; obs_type `mp25/mp50/mp75_price`)

For NSUs whose size scales with price (e.g., a "pile"/tumpok at different price
points). The market survey observed, at each of three price points of the vendor's
offer distribution (P25/P50/P75), the **price per NSU** and the **weight in grams**
of what that price buys.

- **From the market survey:** for each price point q ∈ {25, 50, 75}:
  `p_q = PHP per 1 n` and `w_q = grams per 1 n` → unit value `v_q = p_q / w_q`
  (PHP per gram).
- **Apply to PSPS**, for a household reporting price `p_psps` per NSU:
  1. Find the market-survey price point `q*` with `p_q` closest to `p_psps`.
  2. Take the PHP-per-gram at that point: `v_q* = p_q* / w_q*`.
  3. Convert: `grams per NSU_psps = p_psps / v_q*`.

  I.e., a household paying more per unit is inferred to receive proportionally
  more grams, locally anchored at the nearest observed price point.

- **Key assumption:** within a neighborhood of a price point, price variation
  across transactions reflects **quantity** variation (bigger pile), not price-level
  or quality variation. See caveats below.

### 3. Size-based (`weighing_approach == 3`; obs_type `small/medium/large_size`)

For NSUs sold in labeled sizes (small/medium/large piece, bilog, etc.). The market
survey weighed one specimen of each size: `w_S, w_M, w_L` grams.

PSPS does not record "small/medium/large" — so size is *imputed from the
household's position in the local price distribution*:

- **From PSPS:** within each item-NSU-municipality cell, compute the P25/P50/P75
  of the *PSPS* price-per-NSU distribution.
- **Bridging assumption:** the household at the 25th percentile of the PSPS price
  distribution bought the "small" specimen, P50 ↔ medium, P75 ↔ large:

  `NSU_P25_psps == NSU_Small_market_survey` (and correspondingly for M, L)

- **Apply:** a household is assigned to the nearest PSPS price quantile and
  receives the corresponding market-survey weight (`w_S`, `w_M`, or `w_L`).

---

## Assumptions to keep visible

1. **Price ↔ quantity, not price ↔ quality/price-level** (approaches 2 & 3).
   If two households pay different prices for the same grams (different market
   type, bargaining, timing, quality), the method attributes the difference to
   size. Mitigation: match within municipality × market type where possible.
2. **Temporal alignment.** PSPS prices come from recall periods that may not
   coincide with the market-survey field dates. Under general price inflation the
   *price-based* method mechanically inflates implied grams (a nominally higher
   `p_psps` maps to more grams at fixed `v_q`). The *size-based* method is immune
   to proportional price-level shifts (quantiles shift together; the S/M/L weights
   are fixed) — a point in its favor as the workhorse (85% of market-survey obs
   are size-based).
3. **Quantile ↔ size mapping** (approach 3). "P25 = small" is a convention, not a
   measurement. If most transactions are, say, medium, the mapping misallocates
   the tails. Worth a robustness check (e.g., alternative mapping P33/P50/P67, or
   modal-size assumption).
4. **Conventional NSU homogeneity** (approach 1). Assumes the standardized unit
   does not vary across municipalities; where the market survey weighed it in
   several municipalities, this is testable.

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
