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
fallback (#30) and a regional reference list (#24) both do exactly that.

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

**Two cases used to collide under this rule and no longer do.** Settled on **#21 §5.1**. At
NEGROS OCCIDENTAL / VALLADOLID, `municipality_median` and `province_median` both mapped to
`size_ord = 2`, so cabbage `pieces or units` published a 325 g group and a 780 g group as a single
425 g "medium" with nothing on the row to say so.

They are now **split by price rank** — the cheaper point publishes as `small`, the dearer as
`large`, following the same convention §2d uses for a size-based case that filled groups 1 and 3.
The ordering comes from `pull_price` and nothing is invented: `item_nsu_hetero_type` on this branch
records *which price point the vendor was quoted*, so two price points can genuinely have bought
two different quantities, and in both live cases the price order agrees with the weights. Note the
two run in **opposite directions by geography** — the province median is the dearer point for
cabbage and the cheaper one for carrot — so no rule keyed on "municipality beats province" could
have got both right. Only the price can.

### The collision has a second shape, and §2b covers it too

The other shape is two weighings carrying the **same** label at **different peso prices** —
two spellings that each brought their own `municipality_median`. Both read
`municipality_median`, both take `size_ord = 2`, and `12_publish_reference_set.do` collapses
them into one `medium` averaging two genuinely different price levels.

**Status: HANDLED, by the same rule.** §2b counts **distinct prices**, not distinct labels,
so it fires on either shape. The fold is not in question at this point: harmonization has
already decided the spellings name one unit, and this file is downstream of that. What is
left is two price points inside one cell, which is what the price-rank rule is for — whether
they arrived under one label or two makes no difference, because the ordering comes from
`pull_price` either way.

No change on this vintage: the two live cases carry two labels *and* two prices, so counting
either fires. The difference is what happens to a case that has not appeared yet.

### The one shape that still halts: duplicate quartile labels

The repair works for medians because every median maps to `medium`, leaving `small` and
`large` free to move the two points onto. **`mp25` / `mp50` / `mp75` already occupy all three
rungs.** Two spellings that each brought their own `mp25` at different prices give two
weighings both mapped to `small`, and there is no free rung to promote the dearer one to —
`medium` and `large` already mean `mp50` and `mp75`, and moving an `mp25` into one of them
would publish it as a size the price file says it is not.

**Status: GUARDED.** `10_size_assignment.do` §2b-ii halts on it. The reason is specific
rather than general caution — the ladder is full. Resolving it means widening `PMERGE` so the
two prices merge upstream, or revisiting the fold; both are decisions above this file.

**Neither shape arises on this vintage, and the reason is thin.** Zero of 361 (cell × label)
groups carry more than one price, because only three price-quantity cells pool more than one
spelling at all. Nothing prevents a fourth. That is why this is written here rather than
being rediscovered a fourth time.

The alternative that was tried and reverted was dropping the province-median weighings as "already
a fallback". That was wrong: the price type describes how a spelling's **price** was derived, not
where it was **weighed**, and all six weighings are genuine measurements taken in VALLADOLID.
2 cases, 12 weighings.

**Checked by** `90_diagnostics/scope_outcome1_partition.py`.

## A3 — `THIN = 3` is the right cut

**Claims.** Fewer than three weighings behind a published value is thin enough to warn
about; three or more is not.

**Rests on it.** The `d_thin` flag only. No weight changes, nothing is dropped.

**Status: ACCEPTED, with the sensitivity stated.**

| threshold | rows flagged | share of 2,550 |
| --: | --: | --: |
| 2 | 265 | 10.4% |
| **3 (current)** | **511** | **20.0%** |
| 4 | 1,040 | 40.8% |
| 5 | 1,469 | 57.6% |

Moving the cut by one still roughly doubles or halves the flagged share, so the threshold
sits on a steep part of the distribution and no substantive argument selects 3 over 2 or 4.

**These figures changed when the fallback ladder landed, and the direction is worth
understanding.** `THIN = 3` now does two jobs rather than one. It still flags a published
row as resting on few weighings, but it *also* decides which cells collapse across their
size rungs — see A15 and the L1 rule. So a cell with any thin rung **and at least two
rungs** publishes one pooled row instead of two or three per-rung rows, the denominator
falls, and the flagged share falls further because pooling raises `n_g` on the rows that
survive.

The flagged share therefore reads *lower* than it did before the ladder landed, while the
underlying evidence is unchanged. **Do not read that fall as an improvement in coverage.**
Two counts make the point, and they must not be confused with each other:

* **43 of the 486 pooled rows are still thin after pooling** — pooling two one-weighing
  rungs gives `n_g = 2`, which clears nothing;
* **470 thin rows were never pooled at all**, because their cell held a single rung and
  there was nothing to pool.

So the majority of thin rows are thin for a reason pooling cannot touch. `n_g` on every
row is the quantity to reason from, not the share.

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
surviving groups by rank. **94 cases** fill fewer groups than the field recorded labels:

| shape | cases | published as |
| :-- | --: | :-- |
| one group filled, `k ≥ 2` | 31 | **medium** |
| groups (1,2) filled — top emptied | 48 | small + medium |
| groups (1,3) filled — middle emptied | 15 | small + large |

The rule fires only where `n_filled < k_sizes`. **Keyed on `n_filled` alone it would also
catch 751 cases** that recorded one label and filled one group — overwriting 406 the field
called small and 155 it called large. That is why the (1,2) and (1,3) split matters and why
the rule cannot read the filled-group count by itself.

**Still untested: the direction.** An upper-inclusive robustness run would change which
cases are under-filled at all, and has not been done.

**Checked by** two independent things, which is why the numbers above are safe to quote.
`10_size_assignment.do` §2d asserts the 97 and each of 34 / 49 / 14 as it builds them and
halts on any move; `verify_documented_claims.py`'s `c_underfilled_shapes` re-derives the
same four figures from the built data. Note that check names *methodology.md* as its doc
anchor, not this entry — which is how this entry came to sit at a superseded
100 / 36 / 50 / 14 while both checks passed on 97 / 34 / 49 / 14. The history is in the
do-file's own §2d comment: 94 → 104 → 100 → 97.

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
| `MIN_LABEL_N = 10`, `MIN_STRATA = 2`, `RATIO_HI = 1.25` | `90_diagnostics/validate_folds.do` | these define which folds are *testable* and which count as sufficiently different, so they set the denominator of the fold validation itself |
| unit size stable between rounds (shrinkflation) | methodology assumption 3 — **load-bearing** | needs a size-comparability check against the reference photos. Recommended by the guidebook; not done. |
| rank alignment of the weight and price ladders | methodology assumption 4 | nothing in the data establishes it — the two distributions come from different rounds and different respondents |
| terciles are the right cut | methodology assumption 5 | no robustness check against alternative cuts or a modal-size rule |

## A10 — A household's reported unit value places it on the price ladder, whatever the acquisition mode

**Claims.** `p_h = e_h / q_h` is computed for **every** acquisition mode — purchased, own
production and gift — and used to select the rung and scale the conversion factor:
`CF_h = p_h / v_g`. The claim this rests on is **not** that a reported value is a market
price. It is narrower and more specific:

> **Within one household, item and harmonized unit, the value a household puts on one unit
> is proportional to the physical size of the unit it consumed — to the same degree
> whether it bought, grew or was given it.**

That is what licenses reading a reported value as a position on a ladder built from
purchase prices.

### Why the earlier version of this entry was wrong

This entry used to claim the opposite rule: `p_h` on the purchased slot only, because "the
own-production and gift slots carry an imputed value, so a ratio built from them is not a
price anyone faced." That reasoning conflates two different objects.

* **The price points** that build the conversion factors come from the price file and are
  fixed. They are, and should be, market transactions. Nothing here changes that.
* **A household's own `p_h`** is not an observation feeding an estimate. It is the *index*
  that says which rung of an already-built ladder this consumption sits on. Nothing about
  that role requires `p_h` to be a transaction price.

Once the factors exist, the three acquisition modes are simply rows in a long format: a
gifted `bugkos` is converted alongside a purchased one.

**And the rule it replaced was not neutral.** With `p_h` missing, those rows took the
case's *middle* price point and converted at that group's own weight — the degenerate
`p_h = p_g`, so `CF_h = w_g`. That does not abstain from an assumption; it asserts that
every own-producing household consumed the **typical-sized** unit. Refusing the data was a
stronger claim than using it.

**Where.** `20a_psps_households.do` §9 computes `p_h` on all slots.
`28_match_and_convert.do` matches on it and scales `CF_h` by it. `d_no_price` now means
"no computable price" — `e_h` or `q_h` absent — and not "not purchased".

**Rests on it.** 11,783 of the 35,448 non-standard-unit household rows — **one in three** —
now receive a price-scaled conversion factor where they previously received the group's own
weight. `d_no_price` falls from 11,809 rows to **26**, which are the rows where `e_h` or
`q_h` is genuinely absent.

### What it actually changed, measured on the build

| | before | after |
| :-- | --: | --: |
| total grams, all household rows | 541,046,055 | **538,656,825** (−0.44%) |
| NSU rows with no computable value | 11,809 | **26** |
| rows clamped by the A18 cap | 1,283 | **1,418** |
| converted rows | 87,405 | **87,374** |

**−0.44% in aggregate**, so the change is not a level shift — it redistributes grams within
the population rather than moving the total. The cap catches 135 more rows, which is the
expected consequence of a third more rows carrying a `p_h / p_g` ratio at all.

**The 31 fewer converted rows are A16 working, not a regression.** Unique-price refusals
rise from 117 to 148 — exactly the 31. A household with no `p_h` used to be sent to the
case's *middle usable* group by construction, which meant it could never land on a refused
unique-price point. Now that it has a value it is matched on distance like every other row,
and 31 of them turn out to sit nearest a unique price with no weighing behind it. A16 says
such a row must be refused rather than quietly converted at a different rung; those 31 were
exempt from that rule only by accident.

### Status: ADOPTED, on evidence, with a named cost

**The evidence for it.** Implied prices from the non-purchased slots track purchase prices
in the same province × municipality × item × unit at a **median ratio of 1.000**
(IQR 1.000–1.062, n = 11,392). The objection that an imputed value is systematically unlike
a market price is not supported by the data.

**The test on the exact case that matters.** 82 households report the same item × harmonized
unit through both a purchased and a non-purchased slot — the case where the assumption is
directly checkable:

| pair | n | reports an identical unit value (±1%) | median ratio |
| :-- | --: | --: | --: |
| own production vs purchased | 46 | 33 (**72%**) | 1.000 |
| gift vs purchased | 36 | 33 (**92%**) | 1.000 |

So in 66 of 82 cases the two rows receive the **identical** conversion factor, which is what
the assumption predicts.

**The cost, and it is real.** The other 16 pairs report different unit values for the same
item and unit, with ratios from 0.43 to 2.00. Those rows now receive different conversion
factors, and therefore different grams, for what may well be the same physical object.
**Chicken `bilog` is the worked example — read this table before relying on the rule:**

| purchased | other slot | ratio |
| --: | --: | --: |
| ₱180 | ₱350 | **1.94** |
| ₱230 | ₱280 | 1.22 |
| ₱277 | ₱300 | 1.08 |
| ₱200 | ₱200 | 1.00 |
| ₱650 | ₱500 | 0.77 |
| ₱220 | ₱250 | 1.14 |

The household that bought a bilog at ₱180 and valued a gifted one at ₱350 now gets 1.94×
the grams for the gifted bird. If the two birds were the same size, that is an error the old
rule would not have made — it would have given both `w_g`.

**So this is a trade, not a free improvement.** The old rule was right on these 16 by
construction and wrong on the other 11,767 by flattening every size difference. The new rule
is right on the 66, scales correctly across the bulk, and misprices these 16. Two things
bound the damage: the A18 cap clamps `p_h / p_g` to [1/5, 5], so no single row can run away;
and `source` ships on every row, so this subset can be excluded or sensitivity-tested by
anyone who disagrees.

**What the evidence does NOT establish.** That the *units are the same size*. Every figure
above compares reported **values**. A ratio of 1.000 is consistent with "same bundle, same
value" and equally with "a bigger self-tied bundle, valued proportionally higher" — the two
cannot be separated from prices alone. Only a weighing could separate them, and the market
survey never weighed a household's own bundle. The rule rests on the value agreement, and on
nothing stronger.

**The original worry, still unresolved and still worth naming.** A household harvesting its
own camote tops is not buying a vendor's bundle, and "one bundle" may mean whatever they
chose to tie together. If own-production units are systematically larger or smaller *and*
households value them proportionally, the value agreement above would look exactly as it
does and the grams would still be wrong. Camote tops account for 41 of the 82 checkable
pairs, so this is the item to look at first if the question is ever settled properly.

**Checked by** nothing automated yet. Every figure in this entry is recomputable from
`psps_households.dta` (`e_h`, `q_h`, `source`, `conv_path`) — recompute rather than trust
the numbers written here.

### Exposure in the raw file, for scale

Of 129,094 PSPS food rows, 102,444 record a purchase, 21,597 own production and 5,627 a
gift — the slots are separate, so a row can hold more than one. Roughly **one food
observation in five is acquired without a purchase.** Reproduce with:

```
python -c "import pandas as pd; d=pd.read_stata(r'<psps_cons>', convert_categoricals=False, columns=['item_type','cons_purchased','cons_own_production','cons_gift']); f=d[d.item_type==1]; print(len(f), [(c,int((f[c]==1).sum())) for c in f.columns[1:]])"
```

where `<psps_cons>` is the path in `00_shared/00_globals.do`. Those counts include the
~52,000 rows already answered in kilograms or litres, which need no conversion factor at
all; the figure that matters for this entry is the one in three of the **non-standard-unit**
population given above.

Raised on **#27**; the rule was reversed after the measurement above.

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

**Where.** Implemented. `00_shared/08_branch.do` derives `branch` and `d_reclassified`;
`10_reference_set/10_size_assignment.do` §2a-ii gives the reclassified cases one group at
`size_ord = 2`; `20_psps_retrofitting/21_branch_size_based.do` gives them one group in Outcome 2 and
picks the mp50 / municipality-median point explicitly rather than by rank, because after the ₱20
merge that point is generally not rank 1. `23_branch_conventional.do` is built from the remaining
24 cases, not from all 123.

**Rests on it.** **99 of the 123 published conventional rows**, 388 weighings — four fifths
of the branch. The other 24 cases, whose (item, unit) pair is conventional everywhere it
appears, keep `weighing_approach == 1` and `size_ord = 0`.

All 99 publish at `size_ord = 2` and `fallback_level = 0`. **21 of them are thin** (`n_g < 3`) and
carry `d_thin = 1`, which is the whole of what is true about them: one group, few weighings. They
used to be relabelled `size_ord = 4`, "pooled across sizes" — which was wrong twice over, since a
reclassified case has exactly one rung by construction and so nothing was pooled. The collapse in
`12_publish_reference_set.do` §5b now requires two rungs before it fires.

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

> **Read A15 first: the design this entry was written about is superseded.** The fallback no
> longer borrows a price–weight slope, so there is no grams-per-peso schedule in
> `30_fallback.do` and no `cv_gpp` in any output. What survives is the *shape* of the
> problem — the accuracy of a borrowed weight is known only from cells that did not need
> one — and that is why the entry stays. The measurement it describes is archived at
> `dofiles/archive/scope_price_weight_ray.do`.

**Claims.** A province-level estimator gives a weight to cases with no market-survey weighing of
their own. Its accuracy was established by a leave-one-municipality-out test: hold out a
municipality, estimate from the others in the province × item × harmonized unit, predict the
held-out municipality's grams, and compare to the grams the reference set publishes there.

**The assumption.** That test can only run where the answer is known — that is, on cells that **do**
have their own weighings. The cases the fallback actually serves are by construction the ones nobody
weighed locally. Using the harness figures for them assumes the two populations behave alike.

**What rests on it.** Every accuracy figure quoted for the fallback, including the `cv_gpp` bands
that motivate publishing that statistic alongside each fallback weight. There is a plausible reason
the assumption fails in the pessimistic direction: a cell with no local weighing is more likely to
hold a rarer unit in a thinner market, so the schedule may do worse there than the harness suggests.

**Status: UNTESTED and not testable from this data.** Measuring it would need weighings in the very
cells that lack them. The gap is not quantified and should not be assumed small.

Mitigated rather than resolved: no accuracy threshold is enforced. `fallback_level` and the
weighing count at the rung used ship with every fallback weight so a reader can apply their own
cut, and a pool that cannot clear `THIN` is refused outright rather than served weak. On the
current build the province schedule offers 195 of 237 pools and the regional one 74 of 94; the
rest are refused.

**Checked by:** nothing.

## A15 — Within-NSU heterogeneity ignored from L1 down (Outcome 2 fallback ladder)

**Claims.** When the reference set's cell-level data are thin or absent, Outcome 2 climbs a fallback ladder pooling across geographies. Beginning at level L1, every rung treats all hetero-groups (sizes) alike by pooling them: a household that bought the cheap, small version and one that bought the expensive, large version receive the same grams per NSU. In exchange, the estimate no longer depends on validating a price–weight relationship across municipalities — it rests instead on a municipal or provincial median.

**Where.** `dofiles/20_psps_retrofitting/30_fallback.do`, the L0–L3 rung structure and the pooling logic at each level. Outcome 1 stops at L1 and does not borrow further; Outcome 2 continues to L3 because the PSPS retroactively needs a conversion factor and there is no other source.

**Rests on it.** The fallback ladder's grain and what happens when a cell holds no weighings at all. L1 collapses hetero-groups by pooling across size terciles within the cell; L2 pools across municipalities when there is no MS weighing at that grain; L3 pools across provinces when provincial coverage fails. **518 of 962 cells that lose their size ladder** remain thin even after pooling to L1 and publish a median with both `fallback_level = 1` and `d_thin = 1`, resting on one or two weighings. Every household in those cells receives a single conversion factor regardless of what it paid, so size heterogeneity is erased from the household-level estimate, yet size-specific medians survive in Outcome 1 and can be compared by a reader.

**Status: ACCEPTED, and deliberate.** This is an explicit trade: narrower precision — fewer weighings behind the conversion factor, higher `fallback_level` values — in exchange for dropping a cross-municipality price–weight relationship that is unobserved on both PSPS and MS sides and cannot be validated. It is a design choice, not a threshold or a tie rule.

**What gets published.** `fallback_level` (0–3, ordinal) flags which rung supplied the weight, and `n_g` gives the weighing count **at the rung actually used** — so a reader can keep L1 and drop L3 rather than facing one all-or-nothing switch. Those two columns are the whole apparatus; there is deliberately nothing else.

`cv_gpp`, `n_pairs`, `n_price` and `n_mun` are **not** published on fallback rows. They belong to a superseded design in which the fallback borrowed a *price–weight slope* across municipalities and needed a ray-fit statistic to say where that was safe. This ladder borrows a *median weight* at a coarser grain instead, so the statistic has nothing to qualify. They survive only in `dofiles/archive/scope_price_weight_ray.do` as a measurement of the alternative that was not taken.

**Where it reaches a household.** `28_match_and_convert.do` puts **5,955 of 35,448** non-standard-unit household rows (16.8%) on a fallback rung — 110 at L1, 5,484 at L2 and 361 at L3 — so this entry describes one row in six rather than an edge case. Those households' own prices are not used at all.

L3 is flagged distinctly because the same NSU varies up to **6.7×** across municipalities — see A1, which supersedes an earlier 14× reading — so a regional median describes no single municipality. **L3 is regional, not national:** the five provinces surveyed — AKLAN, ANTIQUE, CAPIZ, ILOILO, NEGROS OCCIDENTAL — are all Western Visayas (Region VI), Guimaras excepted, so the widest pool available says nothing about the country beyond this region.

**Checked by** nothing.

## A16 — A `unique_mun_price` point is refused unless a weighing stands behind it

**Claims.** A price point built only from `unique_mun_price` quotes can be paired with a weight
**only** where a market-survey weighing in that cell was actually recorded against a unique price.
Everywhere else the point stays in the lookup so a household can match it, and then yields `.c` —
reported unconvertible, never imputed and never redirected to another point.

**Where.** `20_psps_retrofitting/20_case_price_points.do` sets `d_point_unconvertible`;
`28_match_and_convert.do` returns the refusal.

**Rests on it.** 238 points in 210 cases, of which the live ones are the **199 on the size-based
branch** — the 28 price-quantity and 11 conventional points are inert, because neither branch
consults a price-file point. At household level it is **117 rows** refused.

**Status: DECIDED.** Settled on **#23**, where three parts of the project had been treating a
unique price three incompatible ways.

**Why refusal rather than substitution.** The price file does not record a municipal price
separately when it is within ₱20 of the province median, so **every surviving unique price is by
construction far from the central tendency** — gap median ₱55, 75th percentile ₱130, max ₱1,110.
`CF_h` is linear in `1/p_g`, so choosing the unique price over the median rescales every conversion
factor in the case by up to 6×. Substituting the cell's pooled weight would not repair that; it
would answer a different question at a price still known to be atypical.

**The refused point is not removed from matching**, and that is the load-bearing half. A household
matches the *nearest* point, so deleting the unique price would push it onto the province median and
convert it silently. Keeping the point and refusing it is what makes the household visible.

**No case is emptied.** A unique price always accompanies another point — 347 of 351 carry a
province median, the other 4 a full quartile triple — asserted in the code rather than assumed.

**The data collapses the rule.** All 33 weighings recorded against a unique price
(`item_nsu_hetero_type` 10 or 11) are price-quantity, in 12 cells, and that branch reads
`pull_price` rather than the price file. So on exactly the cells where a unique price is legitimate
it arrives by another route. `20_case_price_points.do` asserts that, because the rule and the
shortcut coincide only while it holds.

**Checked by** the assertions in `20_case_price_points.do` sections 3 and 6.

## A17 — Rice `gantang` is a standard unit, at 2,250 g

**Claims.** A gantang (salop) of rice is a standardised measure whose size is known independently
of any one market, so a PSPS household reporting it needs no market-survey lookup. The factor is
**2,250 g**.

**Where.** The factor table in `20_psps_retrofitting/20a_psps_households.do` section 1, applied by
`27_standard_units.do`.

**Rests on it.** **11,665 household rows** — the largest single non-metric unit in PSPS and about a
third of what would otherwise be the NSU conversion population.

**Status: ADOPTED, on our own measurement.**

**It was already excluded, but by an undocumented edit.** `90_diagnostics/scope_psps_exposure.py`
carries a nineteen-entry standard-unit list described as `NSU_Analysis.R`'s "verbatim". That
script's own list has **ten** entries and does **not** contain `Gantang`. Most of the additions are
correct — the publication file spells the same metric units differently from the R's free text —
but `Gantang` is not metric, and its inclusion removed a third of the population from every figure
on #30 with nothing recording the decision. It is now a decision.

**The factor is measured, not definitional, and the two disagree by 10%.**

| | 1 gantang of rice |
| :-- | :-- |
| traditional | 1 salop = 3 litres, quoted at ~2.5 kg |
| **our market survey** | **2,237.5 – 2,275 g** over 7 municipalities, 28 weighings, spread **1.7%** |

Three litres of milled rice is 2.25 kg at a bulk density of 0.75 kg/L and 2.5 kg at 0.83. The
*volume* half of the traditional figure is therefore solid and the *density* half is loose, which is
where the 10% sits. A direct measurement of the object in the provinces concerned beats a rounded
density. `docs/data_oddities.md` already treats ~2,250 g as the project's figure.

**It is the one unit where A1 holds.** A1 reports "conventional units are standard within a
locality" as FALSIFIED, on a 6.7× spread for camote tops `bundle`. A 1.7% spread across 7
municipalities is a different animal, and it is what licenses a single sample-wide constant here
where A1 forbids one everywhere else. **Sample-wide, not national** — those 7 municipalities are
all Western Visayas, so the evidence says nothing about gantang elsewhere in the Philippines.

**`ganta` takes the same factor.** The crosswalk folds raw `ganta` to harmonized `gantang`, and the
fold pools nothing — all 14 crosswalk rows carry `n_cell_merged == 1`, because no raw `gantang`
label exists on our side at all. Only 18 PSPS rows spell it `ganta`; giving them a different factor
from the other 11,647 would be incoherent.

**One consequence, and it is #16's question.** Outcome 1 publishes the *measured* 2,237.5–2,275 g
for those 7 cells while Outcome 2 converts at 2,250 g everywhere. The two deliverables therefore
disagree slightly on rice, by construction.

**Checked by** nothing yet. The 1.7% spread is the claim to re-derive if the weighings change.

## A18 — The extrapolation cap `t = 5`

**Claims.** A household's price may stray from its matched price point by up to a factor of 5 in
either direction before linear extrapolation stops being credible. Beyond that the ratio is clamped
to `[1/5, 5]` and the row is flagged.

**Where.** `20_psps_retrofitting/29_cap.do`.

**Rests on it.** **1,283 of 19,242** household rows that carry a ratio at all (6.7%). Rows are
clamped and kept, never dropped: `d_cap` marks them and `r_h_raw` keeps the uncapped ratio.

**Status: SET FROM THE DISTRIBUTION, and it is a judgement on a continuous one.** Decided under
**#19**, which is explicit that choosing 2 or 3 in advance would be a number with no evidence.

**The distribution it answers to** (19,242 rows):

| | | | | | | | |
| :-- | --: | --: | --: | --: | --: | --: | --: |
| | min | p1 | p5 | p25 | median | p99 | max |
| `p_h / p_g` | 0.0017 | 0.100 | 0.167 | 0.500 | **0.875** | 2.000 | 16.0 |

**The binding side is the LOW tail, which is the opposite of what #19 was written about.** That
issue describes a household paying ten times the matched point being handed ten times the grams. In
this data that tail barely exists — p99 is 2.0. What does exist is the other end: a minimum ratio of
0.0017 assigns a third of a gram on a 200 g unit. The cap is symmetric, so it repairs those, and the
**total grams rise by 1.09%** rather than falling.

**The tail is worst where the price evidence is thinnest**, exactly as #19 predicted:

| price points in the case | rows | median | p99 | max |
| --: | --: | --: | --: | --: |
| 1 | 9,310 | 0.778 | 2.500 | **16.0** |
| 2 | 4,340 | 0.909 | 1.667 | 4.95 |
| 3 | 5,592 | 0.938 | 1.412 | 2.95 |

A one-point case has no ladder to bracket a household, so it matches that point however far its
spend lies from it. That the median moves toward 1 and the tail shortens as the ladder gets richer
is the first empirical support the matching step has.

**What the cut costs**, published so a reader can take another:

| `t` | rows clamped | share |
| --: | --: | --: |
| 1.5 | 6,821 | 35.5% |
| 2 | 3,828 | 19.9% |
| 3 | 2,441 | 12.7% |
| **5 (current)** | **1,283** | **6.7%** |
| 10 | 158 | 0.8% |

**Checked by** the bound assertion in `29_cap.do`, which fails if any row leaves
`[w_g/t, w_g·t]`.

## A19 — A household has no dimension, so the cell's dominant one is used

**Claims.** Where a case holds both gram and millilitre weighings, a PSPS household reporting that
unit is served by the sub-cell with more weighings behind it; grams break a tie.

**Where.** `28_match_and_convert.do` section 1, and again at each fallback rung in section 6.

**Rests on it.** **65 of 1,941** weighed cells span both dimensions.

**Status: ACCEPTED, and nearly weightless.** The lookup is keyed with `corrected_unit` because a
gram must never be pooled with a millilitre in a *median*. But a household reporting "2 pieces of
ice cream" says nothing about which, and something has to be chosen. The choice moves a **label**
and almost never a number, because this project treats a millilitre and a gram as the same reading
at the precision recorded — the items measured by volume are near water density, which is the same
assumption `04_unit_snap.do` makes when it converts litres to millilitres and then reports grams.

**Why a rule at all, if it barely matters.** Because the alternative is row order, and row order
here is whatever the sort seed chose. Determinism is the point, not accuracy.

---

## A20 — The three kinds of weight uncertainty are treated as equally serious

**Claims.** A weighing is *questioned* if any of three things is true, and the published
`n_uncertain` counts all three the same way:

| flag | means | source column |
| :-- | :-- | :-- |
| `d_unusable` | no reading was defensible, so the weight is `.c` | `corrected_weight` missing |
| `d_disputed` | the two snap readings differ and one had to be chosen | `w_step1` vs `w_block` |

**A third flag, `d_step1_flagged`, was retired.** It read `review_step1 == 1` — the
anchor's own flag, raised when its pool looked untrustworthy. The anchor no longer sets a
published weight, so the flag described a computation that does not run, on 1,473
weighings and 76% of `d_any_uncertain`. Retiring it takes the headline from 1,934 to 950.
`review_step1` still exists on the build as a diagnostic; nothing published reads it.

**Where.** Defined once in `08_branch.do`. Published as `n_disputed`, `n_uncertain` and
`share_uncertain` on the reference set; as the same three columns on the
Outcome 2 lookup; and as `nu_used` / `share_uncertain` on every converted PSPS household row,
taken at the fallback rung that actually supplied the weight.

**Rests on it.** Run `90_diagnostics/report_weight_corrections.py` for the current split —
the three counts move with every review round, which is why they are not copied here.

**Status: ACCEPTED, with the disagreement published rather than resolved.** The three are not
obviously equally serious: an unusable weight is worse than a step-1 flag, and a disputed
weight sits somewhere between. Weighting them would mean inventing exchange rates between three
kinds of doubt, on no evidence. So they are OR'd into one indicator **and each is published
separately beside it**, which lets a reader who disagrees rebuild the combination from the
columns rather than argue with ours.

**What the flags do not say.** How wrong the weight could be. These record that a reading was
questioned, not an interval around it, and no variance is propagated anywhere. A row with
`share_uncertain == 1` is not a row with a known error; it is a row where nothing behind the
estimate went unquestioned.

**Nothing is dropped or down-weighted.** Every row that published before this change still
publishes, with the same number. Baking the discount into the build would put our judgement
inside a table whose purpose is to be reusable — see #35.

**A note on the rungs, and on how much weight it will bear.** The coarser rungs of the
Outcome 2 ladder look more questioned — but by how much depends on the aggregation, and the
two readings differ enough that quoting one without naming it is misleading.

Over the 34,916 converted household rows in `psps_converted_capped.dta`:

| rung | rows | median `n_g_used` | mean of the row's `share_uncertain` | pooled `Σ nu_used / Σ n_g_used` |
| :-- | --: | --: | --: | --: |
| L0 the cell's own weighings | 28,961 | 4 | 0.120 | 0.121 |
| L1 cell pooled across sizes | 110 | 6 | 0.080 | 0.103 |
| L2 province × item × unit | 5,484 | 60 | 0.195 | 0.148 |
| L3 item × unit regionally | 361 | 21 | 0.384 | 0.148 |

**They answer different questions and both are correct.** The fourth column gives each
*household row* equal weight and is the household-facing number: for a typical converted row
at that rung, this is the share of the weighings behind its own figure that was questioned.
The fifth pools every weighing used at the rung, so a few large clean pools dominate — and
L2/L3 draw on large pools, median 60 and 21 weighings against L0's 4.

**So the gradient is real but modest, not steep.** Per household row it looks like a
three-fold rise from L0 to L3; pooled over weighings it is 0.121 to 0.148. A claim that the
ladder's weakest rung is also dramatically the most questioned does not survive the second
weighting, and should not be made. What does survive: the coarser rungs are not *cleaner*
than L0, so borrowing buys coverage without buying better provenance.

**Checked by** nothing yet, which is why both columns are stated with their formulas rather
than as bare figures — recompute them from `psps_converted_capped.dta` rather than trusting
this table. Two reviewers reading this entry reached opposite verdicts on whether the
figures reproduced, because the original entry quoted the fourth column without naming it.

---

## A21 — Eleven labels are not reusable local units, and Outcome 1 excludes them

**Claims.** A reference book is only useful for a label that *names a unit another
enumerator will hear again*. Eleven harmonized labels do not, and so are excluded from
Outcome 1 — not because the evidence behind them is weak, but because of what they are:

| kind | labels |
| :-- | :-- |
| a count, not a unit | `1 order`, `1 serve`, `2 slice`, `2bond`, `3bugkos` |
| an item, not a unit | `papaya, mango, banana` |
| **a cut of meat, not a unit** | **`chicken wings`, `intestine`** |
| a one-off phrasing | `pinutos / plastic`, `role`, `stick` |

**The last two joined late, and how they were missed is the point.** Both carried a
`notaunit` verdict in `90_diagnostics/harmonization_verdicts.py` — recorded during the
#36 review and never applied — so beef `intestine` shipped at 2,060 g and chicken
`chicken wings` at 15 g, one row each, as though they were units someone could look up.
A verdict that exists and does not reach the build is the exact failure #36 was opened
about, and it survived because nothing joined the verdict file to the exclusion list.

**Rests on it.** The Outcome 1 deliverable only. `10_size_assignment.do` drops these
before sizing; the weighings are written to
`outputs/build/diagnostics/refbook_excluded_not_a_unit.csv` with their weights, so the
exclusion is recoverable. **Outcome 2 is untouched** — a household that reported "2 slice"
still needs its grams, and `master_outcome2.do` never calls that file.

**Status: ACCEPTED, and it is a new kind of rule.** Every other exclusion in
`10_size_assignment.do` is structural — no usable weight, `unique_mun_price` is not a
size, wrong branch in a mixed cell. This is the first time the pipeline asks whether a
label denotes a unit at all, and the judgement is editorial rather than measured.

**It does not weaken A3.** Thinness still never drops a row. Several of these rest on
four weighings, and 267 published rows still sit on a single weighing. They are excluded
for their kind, not their thinness, and the two rules must not be conflated: a future
reader tempted to extend this list "because the cell is thin" would be making a different
decision from this one.

**Checked by** `10_size_assignment.do` itself, which `exit 459`s if any listed label
matches no weighing — so a respelling or an upstream fold cannot silently empty the list.
The count excluded prints on every run, and `n_g` over the published rows plus the 23
excluded weighings reconciles to the pre-exclusion total.

**What would overturn it.** Evidence that any of these is a real vendor unit rather than a
transcription of a purchase — a second municipality recording the same label, most
obviously. `pinutos / plastic` is the likeliest candidate: it is a real Visayan phrasing
(`pinutos` = wrapped), and it is excluded here as a one-off because it appears in exactly
one cell, not because the phrase is meaningless.

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
