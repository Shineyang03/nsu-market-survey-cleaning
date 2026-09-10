# Implicit assumptions register

Every hard-coded threshold, tie rule, normalizer choice and fallback in this pipeline
encodes a claim about the data. Those claims are invisible unless you read the do-file.
This is the list of them.

**This is a register, not a backlog.** An entry stays here after it is settled. "Closed"
means *decided*, not *removed* — a reader needs to know what the pipeline assumes, not
only what is still being argued about. Nothing here is a bug report.

## Scope: what belongs here, and what belongs in the methodology

Two documents carry assumptions and they do not overlap:

| | covers | lives in |
| :-- | :-- | :-- |
| **methodological assumptions** | claims the *method* makes — a single price schedule within a case, rank alignment of the weight and price ladders, unit size stable between rounds | `conversion_factor_methodology.md`, "Assumptions to keep visible" |
| **implicit assumptions** (this file) | claims the *code* makes — a threshold set to 30, a tie rule that is lower-inclusive, a normalizer that drops accented characters | here |

Several entries bind to a methodological assumption; where they do, the entry names it
rather than restating it. The numbers behind the shared ones live in the methodology
section, in one place, so the two files cannot drift apart.

## How to read an entry

Each has four parts:

- **Claims** — what has to be true of the world for the code to be right
- **Rests on it** — what breaks if it is false, and how much
- **Status** — falsified / accepted / closed / untested, and who owns the decision
- **Checked by** — the script that re-derives the evidence, or *nothing* if it is unverified

**Figures are not restated here where a check re-derives them.** Anything asserted is
named by its check in `90_diagnostics/verify_documented_claims.py`, which fails the build
when a documented number moves. Descriptive figures name the script that produces them.
Run both before trusting any number in this file:

```
python dofiles/90_diagnostics/verify_documented_claims.py
python dofiles/90_diagnostics/audit_implicit_assumptions.py
```

---

# The register

Ordered by how much rests on each.

## A1 — Conventional units are standard within a locality

**Claims.** A unit weighed on the conventional branch — a `tumpok`, a `putos` — is a
standardised measure, so one weight per case is enough and no size dimension is needed.

**Rests on it.** The whole conventional branch of both outcomes. `23_branch_conventional.do`
publishes one weight per case on the strength of it.

**Status: FALSIFIED, and the pipeline is protected only by accident.** Owned by **#28**.

Across municipalities, conventional (item, unit) combinations vary by up to **6.7×** —
camote tops `bundle` runs 95 g to 635 g over 28 municipalities, prawns `tumpok` 95 g to
570 g over 17. Neither is a recording artefact: removing any single municipality moves
the camote tops ratio not at all.

*(An earlier reading of 14× is superseded. It was inflated by a contaminated snap anchor
that the adjudication in `04_unit_snap.do` removed. Anywhere the 14× figure still appears,
it is stale.)*

Worse, the variation is not only *between* municipalities. Of 106 conventional cases with
at least two weighings, **41 disperse beyond 2×** inside a single municipality, and for
three units the within-municipality spread exceeds the between-municipality spread.

**The accidental protection.** The conventional branch publishes a *case* median, and a
case is municipality-specific, so between-municipality variation never gets pooled. That
is a side effect of the grain, not a stated constraint — **any future step that aggregates
conventional units above the municipality silently averages a 6.7× spread.** A province
fallback (#30) and a national reference list (#24) both do exactly that.

Within-municipality dispersion is not protected against at all.

**Checked by** `90_diagnostics/scope_conventional_units.py`, and A8 of
`90_diagnostics/audit_implicit_assumptions.py`.

## A2 — A median is a "medium"

**Claims.** A price-quantity weighing whose price point is a municipality or province
median describes a mid-sized unit, so it can be published as `size_ord = 2`.

**Rests on it.** Most of what Outcome 1 publishes as "medium". Of **944** rows at
`size_ord = 2`, **853 (90%)** come from a median rather than a real `mp50`, and **274 of
307** price-quantity cases carry only a median label — each publishing exactly one row,
called "medium", with no small and no large beside it.

**Status: ACCEPTED, and documented rather than changed.** Decided on **#21 §3**.

A median is the middle of a *price distribution*, which is a defensible reason to call it
a middle size, but it is a convention and not a measurement. The alternative — a distinct
`unsized` label — was rejected: an enumerator looking up what a local unit weighs needs one
value per size, and a vocabulary that varies with how much structure the survey happened to
capture is harder to use, not more honest.

The honesty lives in two places instead. `conversion_factor_methodology.md`, "What 'medium'
means in the published file", states the composition; and `n_g` is published beside every
row so a reader can see how thin a value is.

**Two cases collide under this rule** and are still undecided — see **#21 §5.1**. At
NEGROS OCCIDENTAL / VALLADOLID, a municipality median and a province median both map to
`size_ord = 2`, so cabbage `pieces or units` publishes a 325 g group and a 780 g group as a
single 425 g "medium", with `d_thin = 0` and nothing on the row to say so.

**Checked by** `90_diagnostics/scope_outcome1_partition.py`.

## A3 — `THIN = 3` is the right cut

**Claims.** Fewer than three weighings behind a published value is thin enough to warn
about; three or more is not.

**Rests on it.** The `d_thin` flag only. No weight changes, nothing is dropped.

**Status: ACCEPTED, with the sensitivity stated.**

| threshold | rows flagged | share of 2,559 |
| --: | --: | --: |
| 2 | 270 | 10.6% |
| **3 (current)** | **518** | **20.3%** |
| 4 | 1,042 | 40.7% |
| 5 | 1,474 | 57.6% |

Moving the cut by one still roughly doubles or halves the flagged share, so the threshold
sits on a steep part of the distribution and no substantive argument selects 3 over 2 or 4.

**These figures changed when the fallback ladder landed, and the direction is worth
understanding.** `THIN = 3` now does two jobs rather than one. It still flags a published
row as resting on few weighings, but it *also* decides which cells collapse across their
size rungs — see A15 and the L1 rule. So a cell with any thin rung publishes one pooled
row instead of two or three per-rung rows, the denominator falls from 3,305 rows to 2,557,
and the flagged share falls further because pooling raises `n_g` on the rows that survive.

The flagged share therefore reads *lower* than before while the underlying evidence is
unchanged. Do not read the fall from 38.3% to 20.3% as an improvement in coverage: 518 of
the 962 collapsed cells are still thin after pooling, and the rest were thin at rung level
before being pooled. `n_g` on every row is the quantity to reason from, not the share.

**Why that is tolerable.** `n_g` is published on every row, so a user who disagrees with the
cut can set their own. The flag is a convenience, not a filter — treat `d_thin` as one
reading of `n_g` rather than as a verdict.

**Related:** #31 measures the same exposure from the other direction — the *field* groups
the pipeline starts from, before re-terciling, where 778 hetero-groups rest on a single
weighing.

## A4 — "Quartiles take precedence"

**Claims.** If a case holds any quartile price point, every median in that case is a
fallback reference rather than a second hetero-group, and should be ignored.

**Status: CLOSED — superseded by #21 §2, and never load-bearing.**

The convention originated in `90_diagnostics/tally_price_points.py`, a diagnostic. **No
`.do` file ever implemented it.** Its justification covered one pairing — a province median
accompanying a thin municipal observation, where the two estimate the same central tendency
at different geographies — and was then generalised in `points_pooled()` to "if any quartile
exists anywhere in the case, ignore every median", including a median belonging to a
different raw spelling computed from different observations. Nothing justified that step.

**#21 §2 settles it by replacing it.** Price points merge within ₱20 **on the peso value,
not the rung label** — an `mp25` of one spelling may merge with an `mp50` of another — and
the pooled weights are cut into as many parts as there are surviving points. Quartile
precedence plays no part.

`tally_price_points.py` still prints both readings side by side, deliberately: reporting one
would assert a convention the project has not adopted. Its docstring says which is which.

**One consequence is still open, on #23.** The retired convention is nonetheless what the
point count *effectively* does today with a `unique_mun_price`: it counts the unique-price
levels and discards the province median. Branch S has no arm for that case at all, so three
parts of the project currently treat a unique price three incompatible ways — Branch S
ignores it, Outcome 1 excludes those weighings outright, and the point count keeps it and
throws the median away. 196 size-based cases and 884 PSPS observations sit on the
difference. Deciding it is what unblocks the cap threshold `t` (#19).

## A5 — The tercile tie rule is lower-inclusive, and groups may empty

**Claims.** Cutting a pooled weight distribution as `g1: w ≤ cut1 | g2: cut1 < w ≤ cut2 |
g3: w > cut2` assigns tied weights correctly, and a group emptying is informative.

**Rests on it.** Which size a weighing lands in, on the size-based branch. Weights are whole
grams, so ties on a cut are common and the direction of the rule genuinely bites.

**Status: RESOLVED on naming; the direction is still untested.** Owned by **#3** (closed).

Ties go to the **smaller** weight — the conservative reading. What changed is how
under-filled cases are *named*: `10_reference_set/10_size_assignment.do` §2d no longer names
surviving groups by rank. **100 cases** fill fewer groups than the field recorded labels:

| shape | cases | published as |
| :-- | --: | :-- |
| one group filled, `k ≥ 2` | 36 | **medium** |
| groups (1,2) filled — top emptied | 50 | small + medium |
| groups (1,3) filled — middle emptied | 14 | small + large |

The rule fires only where `n_filled < k_sizes`. **Keyed on `n_filled` alone it would also
catch 753 cases** that recorded one label and filled one group — overwriting 408 the field
called small and 155 it called large. That is why the (1,2) and (1,3) split matters and why
the rule cannot read the filled-group count by itself.

**Still untested: the direction.** An upper-inclusive robustness run would change which
cases are under-filled at all, and has not been done.

**Checked by** the under-filled claims in `verify_documented_claims.py`, which assert the
100 and its 36 / 50 / 14 decomposition sum correctly.

## A5b — The field label is wrong per weighing but informative in aggregate

**Claims.** If a group is made mostly of weighings the enumerator called *large*, then
"large" is the right name for that group.

**Rests on it.** It is **the criterion that chose A5's naming rule.** Read this before
trusting that rule.

**Status: PARTLY HOLDS — the weakest link in Outcome 1.**

This sits in open tension with re-terciling existing at all: if the field labels could be
trusted they would simply be used, and Step A would not re-cut anything. The tension
resolves only if the labels are noisy per weighing but **unbiased in aggregate**. They are
noisy, they do aggregate — and they are **not unbiased**. The modal field label runs
systematically low, so a criterion built on it favours the *lower* of two candidate names,
which is the same direction as the status quo it was used to judge.

The three figures — per-weighing agreement, per-group modal agreement, and the mean signed
error — live in `conversion_factor_methodology.md`, assumption 7, and are re-derived by
`verify_documented_claims.py`. They are not repeated here.

**What would settle it** is evidence independent of the field labels: the reference
photographs the LSMS guidebook recommends, or a size-comparability check against them. That
is a data-collection question, not a code one. Until then, A5's naming rule is the best
available reading of the labels, not a measurement.

## A6 — `KGMAX = 30`

**Claims.** A weight ticked "kg" above 30 is really grams mis-ticked; below 30 it is a
genuine kilogram reading.

**Where.** `00_shared/04_unit_snap.do`.

**Status: SAFE ON THIS DATA, unjustified in principle.**

The **(30, 50] band is empty**, so 30 versus 50 changes nothing today, and the verdict
barely moves across the whole plausible range — 89 rows read as grams at a cut of 10, 86 at
25–60, 85 at 100. **86 rows** currently exceed 30 while ticked kg.

Nothing argues for 30 specifically. New data landing in the empty band would need a real
rule. Document the empty band as the *reason* the threshold is harmless rather than treating
30 as a considered choice.

**Checked by** the "kg band (30,50] is empty" and "rows read as grams mis-ticked as kg"
claims in `verify_documented_claims.py`.

## A7 — The litres rule reuses the grams premise

**Claims.** A weight ticked "litres" at 10 or more is already millilitres.

**Where.** `00_shared/04_unit_snap.do`, the `unit == 3` block.

**Status: REVIEWED AND ACCEPTED.** Raised as #18 item 1; you accepted the block as it
stands.

It belongs in the register because of what it assumes: **that no genuine litre reading of
10 L or more exists in the data.** **67 rows** sit in the exposed band, ranging 35 to 7,680.
Every one is treated as already-mL, so a true litre value there would be silently divided by
a thousand.

It is protected in part by accident — the mineral-water cell that held real litre readings
was removed by the standard-quantity exclusion upstream.

**Check the range, not just the count.** The claim in `verify_documented_claims.py` prints
both, because a stable count with a moved range is the failure this would show up as.

## A8 — Three rules confirmed to hold, and one that turned out false

All three are now assertions rather than beliefs. Adding them found the third does not hold.

| premise | verdict |
| :-- | :-- |
| dropping non-ASCII collides no two distinct names (`DUEÑAS` → `DUEAS`) | **holds** — 0 collisions across provinces, municipalities, items, raw units, harmonized units |
| the "restaurant" collapse maps to one canonical item | **holds** — 1 distinct item, so the collapse is a no-op today |
| harmonization is item-conditioned but **cell-independent** | **FALSE, by design** |

**On the third.** `CELL_MIX` in `00_shared/nsu_fold_rule.py` folds `putos` to
`putos (mix vegetable)` at ILOILO / TIGBAUAN only, on the strength of a field comment:
*"There is no cabbage packs alone this is mixed with carrots"*. So the claim is **split**
rather than patched:

- **Must hold** — one raw label means one harmonized unit **within** a cell. Break this and
  a case pools two different objects under one median. Asserted: **0 of 2,927 cells** violate
  it.
- **May vary** — the same (item, spelling) across *different* cells, but **only where
  `CELL_MIX` declares it**. Asserted against `CELL_MIX` itself, so a new cell-conditioned
  pair fails the build rather than passing as drift.

**One subtlety in the ASCII check.** It tests the **strip alone**, not full normalization.
Case-folding and whitespace collapse are *supposed* to merge names and do; testing the
composed rule would fail on labels that are meant to be one.

**Checked by** `verify_documented_claims.py`, and A1 of `audit_implicit_assumptions.py`.

## A9 — Untested: flagged, not measured

No sensitivity run exists for any of these. Each is listed with why it matters, so a reader
knows which are worth the effort.

| assumption | where | why it is untested, and what a run would tell you |
| :-- | :-- | :-- |
| `FOLD = 0.85` string-similarity cut | crosswalk build | how many folds change at 0.80 or 0.90 is unknown. Cheap to run; a fold change moves a pooling key. |
| `MIN = 10`, `FLOOR = 5`, `SIB = 1.5`, `AMB = 0.35` in the anchor machinery | `04_unit_snap.do` | #18 item 5 found these are near-dead — tuning them changes almost nothing. **A reader would reasonably assume they are load-bearing.** Either document that they are not, or reconsider whether the anchor should be the primary rule. |
| `MIN_LABEL_N = 10`, `MIN_STRATA = 2`, `RATIO_HI = 1.25` | `90_diagnostics/validate_folds.py` | these define which folds are *testable* and which count as sufficiently different, so they set the denominator of the fold validation itself |
| unit size stable between rounds (shrinkflation) | methodology assumption 3 — **load-bearing** | needs a size-comparability check against the reference photos. Recommended by the guidebook; not done. |
| rank alignment of the weight and price ladders | methodology assumption 4 | nothing in the data establishes it — the two distributions come from different rounds and different respondents |
| terciles are the right cut | methodology assumption 5 | no robustness check against alternative cuts or a modal-size rule |

## A10 — One peso-per-gram exchange rate across acquisition modes

**Claims.** A unit of an item is the same physical size whether the household bought it,
grew it, or was given it — so a conversion factor derived entirely from *purchase* prices
can be applied to all three.

**Where.** Not in any one line yet. It will bind at `28_match_and_convert.do`, which applies
`CF_h` to the household's quantity `q_h` regardless of how the item was acquired.

**Status: NEW, and unmeasured.** Raised on **#27**.

**A convention worth carrying forward.** The archived `26_psps_extract.do` refused to treat
gifts and own production as prices: only the **purchased** slot fed `p_h`, because the other
two carry an imputed value rather than a price the household faced. That is the right rule
and the assumption does **not** bite at price construction — but the file is now in
`dofiles/archive/` and its replacement, `20a_psps_households.do`, is unwritten. **The rule
has to be re-stated there**, or `p_h` will silently start absorbing imputed values.

**Where it does bite.** It bites at conversion. A household that received camote tops as a
gift still reports a quantity in a non-standard unit, and that quantity gets grams from a
factor estimated on purchase transactions. The claim is that a gifted `bugkos` is the same
size as a bought one. That is plausible and completely untested.

**Exposure.** Of 129,094 PSPS food rows, 102,444 record a purchase, 21,597 own production
and 5,627 a gift — the slots are separate, so a row can hold more than one. Roughly **one
food observation in five is acquired without a purchase price.** Reproduce with:

```
python -c "import pandas as pd; d=pd.read_stata(r'<psps_cons>', convert_categoricals=False, columns=['item_type','cons_purchased','cons_own_production','cons_gift']); f=d[d.item_type==1]; print(len(f), [(c,int((f[c]==1).sum())) for c in f.columns[1:]])"
```

where `<psps_cons>` is the path in `00_shared/00_globals.do`.

**Not yet cut to the population that matters** — these are all food rows, including the
~52,000 already answered in kilograms or litres, which need no conversion factor at all.
The share among *non-standard-unit* observations is the number this entry needs, and it has
not been measured.

**Why it is worth measuring rather than asserting.** Own production is the mode most likely
to break it: a household harvesting its own camote tops is not buying a vendor's bundle, and
"one bundle" may mean whatever they chose to tie together. If own-production units are
systematically larger or smaller, the error is one-directional across a sixth of the data.

## A11 — `GAP_FLAG = 2.0`: when two pooled spellings are "the same object"

**Claims.** Where a harmonized case pools a weighed spelling and a priced-but-never-weighed
one, a price-level difference between them **up to 2×** is a pricing difference (vendor,
quality, market), so the household can be converted using the weighed spelling's price
point. **Beyond 2×** it is more likely a size difference, and the case is flagged rather
than converted.

**Where.** `90_diagnostics/scope_spelling_price_gap.py`. Not yet in a build step — it
will bind at `21_branch_size_based.do`.

**Rests on it.** 273 mixed cases carrying **1,778 MS weighings**. At the current cut, **54
cases (345 weighings) are flagged** and 219 convert.

**Status: DECIDED, and the cut is a judgement.** Settled on **#21 §5.3** — option (a) for
the bulk, so those cases behave like every other case, and option (c) for the tail.

**Why the underlying question cannot be measured.** The two candidate rules are opposite
extremes about the same unobserved quantity:

- **(a)** the whole price gap is size — a spelling costing 2.29× more *is* 2.29× bigger;
- **(b)** none of it is size — the gap is vendor or quality pricing.

**The data cannot adjudicate**, because the flagged spelling has no weighings. That is the
definition of the population. So the cut is not a measurement and no sensitivity run will
make it one; the flag exists precisely so those cases are not silently decided either way.

**What the cut costs**, so a reader can disagree with it:

| cut | cases flagged | MS weighings | share of 273 |
| --: | --: | --: | --: |
| 1.25× | 157 | 1,028 | 57.5% |
| 1.5× | 98 | 617 | 35.9% |
| **2.0× (current)** | **54** | **345** | **19.8%** |
| 3.0× | 15 | 91 | 5.5% |
| 5.0× | 4 | 28 | 1.5% |

The median ratio across all 273 is **1.00** — half the cases sit at the same price level
and nothing about them needs deciding. The cut only has to separate the tail.

**Interaction with the #19 cap, worth knowing.** Without a flag, these cases are caught
by nothing in Branch S — only by the `p_h/p_g` cap, whose threshold `t` is still unset.
A 2.29× structural gap would present to the cap as an ordinary extrapolation. So flagging
here keeps `t` answering the question it was designed for rather than absorbing this one.

**Checked by** `scope_spelling_price_gap.py`, which also asserts that every mixed case
carries at least one MS weighing — if that ever fails, the crosswalk's `source` column has
drifted from the market-survey file.

## A12 — A conventionally-weighed unit is the *typical* one, so it is a "medium"

**Claims.** Where an (item, NSU) pair is recorded conventional in some municipalities and
size-based or price-quantity in others, its conventional weighings represent the **typical**
unit. The market survey imposed no size instruction on those weighings — the enumerator did
not ask for a small or a large — so the vendor is assumed to have handed over a
representative one. Those cases are therefore processed as size-based, publishing a single
group as **medium** (`size_ord = 2`) and matching **mp50 / municipality median** in
Outcome 2.

**Where.** Not implemented yet. It will bind on the `branch` variable in `00_shared` and on
`10_reference_set/10_size_assignment.do` §2a–2c.

**Rests on it.** **99 of the 123 published conventional rows**, 388 weighings — four fifths
of the branch. The other 24 cases, whose (item, unit) pair is conventional everywhere it
appears, keep `weighing_approach == 1` and `size_ord = 0`.

**Status: ADOPTED as a convention, with partial empirical support.** Decided on **#28**.

**What the evidence says.** The claim is testable: if a vendor hands over a typical unit,
the conventional weighings should sit at the **medium** tercile of the same item × unit
measured size-based elsewhere. On the 16 pairs with enough of both:

| conventional median ÷ size-based medium | |
| :-- | --: |
| median | **1.00** |
| interquartile range | 0.93 – 1.25 |
| min / max | 0.65 / 3.08 |

That is a good result. But mean absolute log10 distance tells a more equivocal story:

| tercile | distance |
| :-- | --: |
| small | **0.095** |
| medium | 0.108 |
| large | 0.256 |

**Medium beats large decisively and ties with small.** Pair by pair it splits — camote tops
`bugkos` and crackers `pieces or units` sit at the small tercile; prawns `tumpok`, preserved
meat `cans` and loaf bread `medium packs` sit at the medium.

Two explanations, pointing opposite ways, and nothing here separates them:

1. **The comparator runs low.** A5b measures the modal field label sitting systematically
   below its tercile, currently −0.131 of a rank. If the size-based "small" group is
   over-populated, conventional looking small-ish is an artefact of the yardstick.
2. **Vendors really do hand over a smaller-than-typical unit** when no size is named. That
   would make "medium" an overstatement.

**So medium is the better of two defensible choices, not a measured result**, and this entry
exists to say so rather than let the ratio-median-of-1.00 stand alone.

**It inherits A2's caveat.** "A median is a medium" was already a naming convention rather
than a measurement, carrying 90% of Outcome 1's medium rows. This extends it to a fourth
source, so a reader seeing "medium" now has one more thing it can mean. `n_g` and the
planned `d_reclassified` flag are the only ways to tell them apart.

**One caveat specific to this branch.** #28 Q4 found 41 of 106 conventional cases dispersing
beyond 2× *within* one municipality. Calling the median of a case spanning 65–1,020 g a
"medium" is a naming choice about a number that already describes little precisely. This
does not make that worse, but it does file those rows alongside genuinely-terciled mediums
where they are harder to spot.

**Deliberately NOT re-terciled**, whatever the weighing count. A conventional case's
weighings carry no size information to re-derive: they are not small, medium and large
readings that lost their labels, they are readings taken without a size being asked for.
Terciling them would manufacture a size structure the field never observed.

**Checked by** `90_diagnostics/scope_conventional_units.py`, which must keep reading
`weighing_approach` rather than `branch` — on `branch` it would report no mixed pairs at
all, which is the finding erasing itself.

## A13 — CPI panel precision and base-break tolerance

**Claims.** Two thresholds in the CPI panel build:

1. A month-on-month move is a "base break" only if it exceeds the typical month-on-month move elsewhere by more than **2 percentage points**. The `+2` is a tolerance on the reference median applied in the base-break check (see spec section 8, index-integrity validation).
2. When writing the panel CSV, the CPI values are serialized through a **15/16/17 significant-digit ladder**: try 15 digits, then 16, then 17, and keep the shortest spelling that round-trips exactly through `real()`.

**Where.**

- Base-break tolerance: `dofiles/00_shared/06_cpi_panel.do`, the validation section comparing `med_boundary` to `med_other + 2`. Inherited from the retired Python step, `dofiles/archive/06_cpi_panel.py` lines 425–437.
- CSV precision: the digit ladder in `06_cpi_panel.do`, around line 150. The retired Python wrote `panel.to_csv(...)` with no `float_format`, i.e. whatever pandas chose.

**Status: UNDOCUMENTED threshold; precision is inconsistent with the Stata port.**

The `+2` percentage-point tolerance has no stated justification in the code. It is an undocumented design choice used to flag suspicious moves for review. New data with different month-to-month volatility would need a real rule.

**On precision.** The ladder exists because a double carries between 1 and 17 significant decimal
digits: a fixed `%21.17g` always round-trips but spells short values noisily (`100.49232867321599`),
while `%21.15g` is exact for every value in the current source file and is not guaranteed to be for
the next one. Taking the shortest spelling that round-trips gives both properties.

**One value does not agree with the retired Python's spelling**, and it is worth knowing about
rather than discovering later. Stata's number-to-text converter tops out at 18 significant digits,
so a request for 17 is rounded a second time from that 18-digit intermediate; where the 18th digit
is exactly 5 the two roundings disagree. Four `cpi_ma3` values are spelled differently as a result,
and one of them — ANTIQUE / ice cream and sorbet / 2025-05 — parses to a double **1 ULP** away from
the Python's (relative difference 1.1e-16). No downstream figure can turn on that, but it is not
exactly zero, and it is the only respect in which the current panel differs from the one the project
published before the port.

Repairing it properly needs an exact decimal expansion of the mantissa in Mata big-integer
arithmetic. Truncating instead of rounding fixes these four rows and breaks others, so it is not the
fix it appears to be.

**Rests on it.** Nothing substantial rests on the `+2` — it is diagnostic only, flagging cases for human review and not altering any computation. The precision difference matters only to readers inspecting the CSV by eye or comparing ASCII content; the double values are bit-identical once loaded.

**Checked by** nothing.

---

# Adding an assumption

## A14 — The province fallback is validated on cells that do not need it

**Claims.** The province grams-per-peso schedule in `20_psps_retrofitting/30_fallback.do` gives a
weight to cases with no market-survey weighing of their own. Its accuracy is known from a
leave-one-municipality-out test: hold out a municipality, estimate the median `w/p` from the others
in the province × item × harmonized unit, predict the held-out municipality's grams from its own
price, and compare to the grams the reference set publishes there.

**The assumption.** That test can only run where the answer is known — that is, on cells that **do**
have their own weighings. The cases the fallback actually serves are by construction the ones nobody
weighed locally. Using the harness figures for them assumes the two populations behave alike.

**What rests on it.** Every accuracy figure quoted for the fallback, including the `cv_gpp` bands
that motivate publishing that statistic alongside each fallback weight. There is a plausible reason
the assumption fails in the pessimistic direction: a cell with no local weighing is more likely to
hold a rarer unit in a thinner market, so the schedule may do worse there than the harness suggests.

**Status: UNTESTED and not testable from this data.** Measuring it would need weighings in the very
cells that lack them. The gap is not quantified and should not be assumed small.

Mitigated rather than resolved: no accuracy threshold is enforced. `cv_gpp`, `n_pairs`, `n_price`
and `n_mun` ship with every fallback weight so a reader can apply their own cut, and cases whose
province group cannot support a schedule at all are refused outright rather than served a weak one.

**Checked by:** nothing.

## A15 — Within-NSU heterogeneity ignored from L1 down (Outcome 2 fallback ladder)

**Claims.** When the reference set's cell-level data are thin or absent, Outcome 2 climbs a fallback ladder pooling across geographies. Beginning at level L1, every rung treats all hetero-groups (sizes) alike by pooling them: a household that bought the cheap, small version and one that bought the expensive, large version receive the same grams per NSU. In exchange, the estimate no longer depends on validating a price–weight relationship across municipalities — it rests instead on a municipal or provincial median.

**Where.** `dofiles/20_psps_retrofitting/30_fallback.do`, the L0–L3 rung structure and the pooling logic at each level. Outcome 1 stops at L1 and does not borrow further; Outcome 2 continues to L3 because the PSPS retroactively needs a conversion factor and there is no other source.

**Rests on it.** The fallback ladder's grain and what happens when a cell holds no weighings at all. L1 collapses hetero-groups by pooling across size terciles within the cell; L2 pools across municipalities when there is no MS weighing at that grain; L3 pools across provinces when provincial coverage fails. **518 of 962 cells that lose their size ladder** remain thin even after pooling to L1 and publish a median with both `fallback_level = 1` and `d_thin = 1`, resting on one or two weighings. Every household in those cells receives a single conversion factor regardless of what it paid, so size heterogeneity is erased from the household-level estimate, yet size-specific medians survive in Outcome 1 and can be compared by a reader.

**Status: ACCEPTED, and deliberate.** This is an explicit trade: narrower precision — fewer weighings behind the conversion factor, higher `fallback_level` values — in exchange for dropping a cross-municipality price–weight relationship that is unobserved on both PSPS and MS sides and cannot be validated. It is a design choice, not a threshold or a tie rule.

**What gets published.** `fallback_level` (0–3, ordinal) flags which rung supplied the weight, and `n_g` gives the weighing count **at the rung actually used** — so a reader can keep L1 and drop L3 rather than facing one all-or-nothing switch. Those two columns are the whole apparatus; there is deliberately nothing else.

`cv_gpp`, `n_pairs`, `n_price` and `n_mun` are **not** published on fallback rows. They belong to a superseded design in which the fallback borrowed a *price–weight slope* across municipalities and needed a ray-fit statistic to say where that was safe. This ladder borrows a *median weight* at a coarser grain instead, so the statistic has nothing to qualify. They survive only in `90_diagnostics/scope_price_weight_ray.do` as a measurement of the alternative that was not taken.

L3 is flagged distinctly because the same NSU varies up to **6.7×** across municipalities — see A1, which supersedes an earlier 14× reading — so a national median describes no single municipality.

**Checked by** nothing.

---

Add an entry when you write a threshold, a tie rule, a fallback, or a normalizer choice that
could reasonably have gone another way. The test is: *would a reader of this line know that
a decision was made here?* If not, it belongs in the register.

Give it the next free number, fill in the four parts, and — if it is testable — add a check
to `90_diagnostics/verify_documented_claims.py` so it fails loudly rather than drifting. An
entry with **Checked by: nothing** is a promise to a future reader that nobody has verified
it, which is useful information and should not be hidden.

**Do not restate a figure that a check already re-derives.** Name the check instead. Numbers
copied into prose are how this document goes stale, and the register's whole value is that it
does not.
