# Running an adjudication

**Purpose.** Some work in this project cannot be decided by a rule: whether two vendor
spellings name one unit, whether a typed weight is a mis-key, whether a label denotes a
unit at all. Those decisions need a person, and a person's attention is the scarcest
input the project has. This file is how to spend it well.

It generalizes two efforts that between them consumed a large share of the project — the
harmonization review and the unit-snap review — and it is written so a third one does not
have to rediscover the same lessons.

**Who this is for.** Whoever is about to put a list of judgement calls in front of a
reviewer. Read it before building the artifact, not after.

---

## The one-page version

1. **Find N before building anything.** How many decisions are there really, and how much
   does each one move?
2. **Review the rule, not the instances.** Twenty-six spelling folds are one rule and
   three exceptions: four decisions, not twenty-six.
3. **Decide by exception.** Pre-apply everything a rule settles. Show the residual.
4. **Order by downstream impact and give a stopping rule.** Explicit permission to stop.
5. **Pre-fill every verdict.** Confirm/override is cheap; decide-from-scratch is not.
6. **Put the deciding number in the row.**
7. **Key verdicts on content and tripwire them**, so a review is never re-run.
8. **Offer a "park" verdict.** Not every row can be decided today.
9. **Make reversibility visible**, and demonstrate it once.

---

## 1. Find N before you build the apparatus

Both expensive reviews in this project were *"adjudicate N things"* problems where the
machinery was built before anyone knew N. In both cases the real N was one or two orders
of magnitude smaller than the apparatus assumed.

The harmonization review is the clean illustration:

| question | answer |
|---|--:|
| no-group labels in the crosswalk | 156 |
| …whose group actually governs a published value | **91** |
| …reaching the deliverable at all | 57 |
| …carrying 81% of the affected household rows | **5** |
| …that decided the reference-book question | **9** |

A five-line message would have resolved the reference-book question. A 156-row workbook
with a column guide and a self-check was built instead.

**Do this first, and it is usually a few minutes' work:**

* count the candidate decisions;
* measure how many **downstream rows** each one moves — not how many source records
  mention it;
* plot or sort that distribution and find where it flattens.

**Measure impact, never proxy it.** The first version of this review ranked by a column
that summed a *weighing*-level count to a *case*-level count. Adding observations to
groups is not a quantity, and it put a label with 9 affected household rows above one
with 424. Whatever the impact measure is, it must be one thing counted once.

## 2. Review the rule, not the instances

This is the largest single saving available and the one most often missed.

A list of twenty-six pairs to fold is not twenty-six decisions if the same reasoning
covers all of them. It is one decision — *"these are one word, differently spelled,
spaced or prepositioned; fold them"* — plus however many exceptions genuinely differ.

So present a proposed **rule**, the instances it covers, and, critically, **what else it
would catch**:

> Rule: strip a leading count of 1, strip prepositions, singularize from a whitelist.
> Covers: 26 pairs (listed).
> Would also catch, and should not: `3bugkos`/`bugkos` — a count of three.

The reviewer confirms the rule and rules on the exceptions. Four decisions replace
twenty-six, and the rule is reusable next time while twenty-six verdicts are not.

## 3. Decide by exception

Pre-apply everything a rule settles and list it in an appendix the reviewer can spot-check
but does not have to read. Put in front of them only what no rule reaches.

Tag every row with **what the proposal rests on**, because that determines who can check
it:

| basis | who should look |
|---|---|
| `structural` | nobody — a rule decides it; spot-check the rule |
| `measured` | anyone — check the number in the row |
| `language` | **the reviewer, or a native/field reader.** If the reading is wrong, nothing in the data will show it |
| `field` | someone who was there, or exclude the row |

The reviewer's real queue is the `language` and `field` rows. In the harmonization review
that was about 30 of 156.

## 4. Order by impact, and say where to stop

Sort by downstream rows affected and **write the stopping rule into the artifact**:

> The top 5 labels are 81% of the affected household rows. Below row 12, each decision
> moves fewer than 5 rows. Stopping there is a defensible place to stop.

Without this the reviewer either reads everything or guesses where to stop, and both are
expensive. Giving explicit permission to stop is part of the deliverable.

## 5. Pre-fill every verdict

An empty cell is the most expensive thing on a review sheet. Every row should arrive with
a proposed verdict, the reasoning, and the evidence — so the task is *confirm or override*,
which is seconds, rather than *decide from scratch*, which is minutes.

Pre-filling is not presumption as long as the basis is stated and the proposal is
reversible. Say what you are unsure about rather than leaving it blank.

## 6. Put the deciding number in the row

Not a reference to where the evidence lives — the number that settles it:

> `piece` → `pieces or units`: pork 272.5 g (n=4) vs 260 g (n=15), **x1.05**

**Compute it at the grain the decision is made at.** A median pooled across the items a
label appears in describes none of them: `per pack` pools to 530 g across cabbage and
fresh fish, and an earlier draft of this review raised it as an outlier on exactly that
figure. Against fresh-fish `pack` alone it is x0.85 and unremarkable.

**And be clear what the evidence may decide.** Two different claims get gated the same way
if you are not careful:

| claim | example | may evidence veto it? |
|---|---|---|
| one word, differently written | `per pack` vs `pack` | **No.** Identity is settled by the string. A weight divergence is variation *within* a unit, or a measurement problem |
| different words, same referent | `putos` vs `pack` | **Yes.** This is a claim about the world |

## 7. Key verdicts on content, and tripwire them

**This is the mechanism that stops a review being re-run, and it is worth building on day
one.**

The unit-snap review went through three rounds, largely because verdicts were tied to
things that moved. The fix was a ledger keyed on the *content* of the row — cell, group,
raw value — rather than on a row id or a position, plus a tripwire that stops the build
when a verdict matches nothing:

> `2 verdict(s) in the ledger match no weighing in this build. The content key moved — an
> upstream respelling, a changed fold, or a row dropped. Reconcile it; do not delete the
> ledger row.`

That tripwire fired during a later harmonization change and protected two hand-adjudicated
weights. **Reconcile the key; never silence the tripwire and never delete the verdict.**

Note the coupling it implies: if a content key contains a harmonized label, then changing
the harmonization carries a ledger-reconciliation step. That is correct — it is the
coupling being visible rather than the coupling existing.

## 8. Offer a verdict that parks a row

Not every row can be decided when it is looked at. Without somewhere to put those, a
reviewer either guesses or stalls. Provide:

* `park` — revisit, with a note on what would settle it;
* `ask the field` — needs someone who was there.

Both are tracked and neither blocks. `1 bowl cooked` is the canonical example: it must not
fold to `bowl`, because cooked and raw weights differ, and no amount of staring at the
string resolves that.

## 9. Make reversibility visible

Decisions feel heavy when their cost of being wrong is unknown. State it:

* each verdict is one line in one table;
* the pipeline reproduces from raw, so reverting is a rebuild;
* a rejected proposal stays in the code as a **commented rejection with its measurement**,
  so it is not re-derived in six months.

Demonstrate it once. In this project a fold was proposed, applied, measured, found to cost
39 households their conversion, and reverted — in about eleven minutes. After that the
reviewer knows what a wrong decision costs.

## 10. Sample the tail

Where the tail is long and low-impact, census review is not the only option. Draw ten at
random, review those, and if none is wrong accept the rest by rule — recording that this
is what was done. That is a defensible basis for not reading 140 rows, and it is honest
about what was and was not checked.

---

## Building the artifact

Once the above is settled, the sheet itself is easy to get wrong in two ways.

**Keep it narrow.** A review sheet earns about six columns: what it is, what is proposed,
the evidence, what the proposal rests on, the reviewer's cell, and a note. Provenance,
self-check and audit columns belong on a second sheet. A wide sheet moves the work of
finding the decision onto the reviewer; forty columns was handed over once in this
project and it was not a review request.

**Verify every derived column by recomputing it a different way, and mutation-test the
check.** A column that is *argued for* rather than *measured* is the failure mode. One
column here was derived from which code branch resolved a label, on the reasoning that a
resolved label's group could not matter — and it was wrong for 34 of 76 labels, because
the lookup happens on a value the branch had already rewritten. The honest test was to
assign each label a sentinel value, recompute everything, and count what moved. That took
two minutes.

A self-check that cannot fail is worse than none, because it is trusted. After writing
one, reintroduce the defect it guards against and confirm it fails.

**Regenerate, never maintain.** Every hand-maintained number in this project went stale —
the attrition ledger, the explorer's expectations, the crosswalk's own observation counts.
Anything quoted should be produced by a script that can be re-run, and anything frozen
should say so in its column name.
