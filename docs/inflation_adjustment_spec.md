# Inflation adjustment: build spec

**What this builds.** A clean panel of consumer price index **levels**, keyed
`province × item_group × month`, plus the crosswalk that maps survey item names onto
`item_group`. Downstream code forms every ratio it needs from these levels.

**What this does not build.** No inflation factors, no ratios, no `(1+π)`, no
aggregation to case or municipality, no application to any weight. See
[§7 Out of scope](#7-out-of-scope).

Companion reading: `docs/conversion_factor_methodology.md` (the methodology this
feeds). This spec is self-contained for implementation purposes.

---

## 1. Why an inflation adjustment exists at all

PSPS households reported food quantities in non-standard units — "1 bilog of
carrot", "2 tumpok of prawns". The NSU Market Survey went to markets in
**2026m3–2026m5** and weighed those units so the quantities can be converted to
grams. PSPS itself was fielded **2023m12–2025m1**. The two sit in different price
rounds, roughly one to two years apart.

That gap only matters for one of the three weighing approaches.

| approach | what was measured | does the weight depend on the price level? |
|---|---|---|
| size-based (78% of cases) | enumerator asked for a small / medium / large unit and weighed it | **No.** A medium mango's grams are a property of the object. No money changed hands. |
| conventional (6%) | a traditional local unit (ganta, salop) | **No.** Same reasoning. |
| price-quantity (16%) | vendor's item weighed **at a preloaded reference price point** | **Yes.** A fixed peso amount buys less when prices are higher. |

Only the third row needs adjusting, and the adjustment lands on the **weight**, not
the price — the peso figure was preloaded into the form and could not be altered by
the enumerator, so it is the grams that flexed. Full argument in
`conversion_factor_methodology.md`, section "Why the adjustment sits on the weight".

### Why π cannot simply be set to zero

Measured over PSPS 2024m5 → MS 2026m4 on the PSA province × COICOP food CPI:

- Median correction **+7.4%**, range **−18.1% to +58.1%**. Field weights are
  recorded to the whole gram, so on a 200 g unit the median correction is ~15 g
  against 1 g of rounding.
- **Six of sixteen groups moved the other way** (rice −6.8%, fresh meat −4.0%, other
  meat −2.9%, sugar −2.4%, ice cream −1.9%, water ≈ 0), and signs flip *within* a
  group across provinces — leafy vegetables −9.4% in Iloilo, +58.1% in Antique. No
  single scalar can stand in for π.
- Because the sign is known per province × group, setting π to zero is not neutral
  noise; it biases every affected household in one direction, differing by item.

---

## 2. The deliverable

One table:

```
province × item_group × month  →  cpi, cpi_ma3, cpi_source
```

| column | meaning |
|---|---|
| `province` | UPPERCASE (`AKLAN`, `ILOILO`, …) |
| `item_group` | COICOP food group code as published by PSA |
| `mdate` | Stata monthly date |
| `cpi` | the index **level**, as published |
| `cpi_ma3` | 3-month centred moving average of the level |
| `cpi_source` | which coverage tier supplied the row (see §5) |

Plus the item crosswalk `(province, cons_name) → item_group` as a separate output.

### Why levels and not ratios

The pipeline will use these levels twice — once to restate a market-survey weighing
from its own month to a common reference month, and once to carry that
reference-month figure back to a household's PSPS interview month. Both are ratios
of these levels, and both are the pipeline's job.

Shipping levels keeps this table **immune to four decisions that are still open**:
how market-survey months are aggregated within a case, how the preloaded price's
divisor is recovered, whether a given row qualifies for adjustment at all, and how
`p_r`'s peso round is worded. None of those can change a CPI level. Shipping ratios
would bake all four in.

---

## 3. Inputs

All paths relative to
`C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\`.

### 3.1 The CPI file — pin the vintage first

Three vintages sit in `NSU Market Survey Launch\data\`, and they differ:

| file | rows | sha256 |
|---|---|---|
| **`fp_cpi_byprov_byitem_psa_2023_26.csv`** ← use this | 5,820 | `62e938ef119b91dd0e9d5b6badff4eeb17108151d921591dcbfabec9cba0a4be` |
| `fp_cpi_byprov_byitem_psa_2023_26.bak2.csv` | 5,790 | `00155a31e5ad009c28e702617520ba44af6ad28c384854e67ac74f11052253af` |
| `fp_cpi_byprov_byitem_psa_2023_26.bak.csv` | 4,890 | `51d9eea993581e08a9396d5459935d95c3bc4c7cf6aa51de3dcd49daa47241c1` |

Use the plain `.csv` — that is what `dofiles/analysis.do:37` uses. **Verify its
sha256 against the value above and write the hash into your output**, so a silent
vintage swap is detectable later.

Columns: `geolocation, commodity, year, month, date, cpi`.

### 3.2 The item crosswalk

`NSU Market Survey Launch\data\cons_name_to_coicop_crosswalk.csv` — 95 rows, columns
`province / cons_name / item_group`. 19 distinct `cons_name` across 5 provinces.

### 3.3 Reference implementation

`dofiles/analysis.do` **lines 35–60 and 182–205** already do the import correctly.
Read them first and follow them rather than reinventing. Caveats in §6.

---

## 4. Build steps

### 4.1 Import and normalize

Following `analysis.do:35–51`:

- `geolocation` → `province`, then **`strupper`**. The CPI file says `Aklan`;
  everything downstream uses `AKLAN`.
- `commodity` → `item_group`.
- `mdate = ym(year, month)`, format `%tm`. Drop `date`, `year`, `month`.

### 4.2 The item crosswalk join

> **Join on `(province, cons_name)`. Never on `cons_name` alone.**

The crosswalk is `isid cons_name province`: 95 rows, 19 unique `cons_name`. Exactly
one item's group varies by province — **ice cream**, because Iloilo has no CPI series
for it and falls back to the parent sweets/confectionery category. A `merge m:1
cons_name` against this file is an r(459).

Apply the same name normalization `analysis.do` does:

```stata
replace cons_name = "Drinks at restaurant, hotel, cafe, or kiosk" if strpos(cons_name, "restaurant") > 0
replace cons_name = subinstr(cons_name, "café", "cafe", .)
```

### 4.3 `cpi_ma3`

A 3-month centred moving average of the **level** (never of a ratio). Motivation:
individual series are violently volatile — Aklan green leguminous vegetables jumped
**+77% in one month** (2025m7→08), Iloilo the same series +73% (2025m11→12) — so the
pipeline needs a robustness variant.

Handle series endpoints explicitly and **document the choice** (leave missing, or
shrink the window). Do not let the decision be implicit in whatever the function
defaults to.

---

## 5. Coverage ladder

Emit `cpi_source` recording which tier supplied each row:

| tier | source |
|---|---|
| 1 | province × exact COICOP group |
| 2 | province × parent COICOP group |
| 3 | national × group |
| 4 | all-food |

Report counts per tier. Coverage is *believed* complete for 5 provinces × 16 groups,
so tiers 2–4 may come back empty — **confirm this empirically and say so either
way** rather than assuming.

Do not silently drop unmatched rows. List every `(province, item_group, month)` that
a survey item maps to but the CPI file lacks.

---

## 6. Known traps

These are verified, not hypothetical.

1. **`analysis.do:535`** runs `merge m:1 cons_name using coicop_item_crosswalk` —
   the bug §4.2 warns about. Do not copy it.
2. **`analysis.do` does not currently run to completion.** Line 537 is a bare `merge`
   with no arguments. Lines 37–210 are sound; do not assume the file executes.
3. **`analysis.do:204`** uses `assert(2 3) keep(3)`. The `assert(2 3)` means an
   unmatched household *halts* rather than being dropped — so this is not a silent
   drop, contrary to what one might assume from `keep(3)` alone.
4. `cap` and `cap rename` **silence failures**. Verify after any batch of them.
5. Before recoding any coded variable, inspect its actual coding (`label list`,
   `tab var, m`, `describe`). Never infer a scheme from a sibling variable. Treat
   `(0 real changes made)` on a mapping line as a red flag, not noise.

---

## 7. Out of scope

Do **not**:

- compute ratios, inflation factors, or `(1+π)` — if you find yourself dividing one
  CPI by another, stop
- aggregate to case, municipality, or any survey grain
- apply anything to any weight
- modify `dofiles/cleaning_Aug11.do`, anything under `outputs/master_rename_build/`,
  or `docs/conversion_factor_methodology.md`
- run `git commit` or `git push` — leave work uncommitted and list files created

Create **new files only**.

### Note on municipality

Municipality is deliberately absent from the key. PSA publishes at province level.
Municipality enters the pipeline only through which households sit where, via each
household's own interview month — never through the index itself.

---

## 8. Validation to report

- panel dimensions: provinces × item_groups × months; is it balanced; list gaps
- `cpi` distribution: min / p25 / p50 / p75 / max; assert none missing, zero, or
  negative
- counts per `cpi_source` tier
- top 10 largest month-on-month moves with province / group / month — a check that
  the volatility in §4.3 is real and not a parsing artefact
- **index integrity for ratio use**: confirm the series are fixed-base *levels*, not
  year-on-year rates, and check for a base break at the 2026 boundary. Prior work
  found median m/m change +1.3% at 2025m12→2026m1 vs +0.0% elsewhere, i.e. no break
  — verify this independently rather than taking it on trust.
- how far `cpi_ma3` departs from `cpi`, by group
- the full sha256 of the vintage used

---

## 9. Environment

- Stata: `"C:\Program Files\StataNow19\StataSE-64.exe" -e do <file>`. Always a
  **fresh isolated batch process**. Never kill Stata by image name — only a PID you
  spawned yourself. Do **not** use `C:\Program Files\Stata17` (expired licence).
  `-e` writes `<dofile>.log`; a static log does not mean the process is hung.
- **No nested `preserve`** in Stata — that is r(621). Use a tempfile `save`/`use`
  round trip to restore state instead.
- Python is acceptable for any or all of this.
- Verify magnitudes, not just structure. "Ran without error" is not "correct".

---

## 10. Scratch files to ignore

An earlier run was killed partway through and left these behind. They are **not
validated** and `cpi_panel_validation.txt` in particular will read as authoritative
when it is not. Overwrite or delete them; do not build on them.

```
dofiles/build_cpi_level_panel.py
dofiles/verify_cpi_level_panel.do
outputs/tables/cpi_level_panel.csv
outputs/tables/cpi_item_crosswalk.csv
outputs/tables/cpi_panel_validation.txt
```
