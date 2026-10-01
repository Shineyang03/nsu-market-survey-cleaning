# Reading instrument — objects — v2.0

**Version `objects-v2.0`, 2026-09-30.** The coding manual for describing **what is in**
an NSU market survey photograph, as opposed to what a scale display reads. It is
committed, versioned, and its version is recorded against every reading made with it.

`PROMPT.md` (`v1.0`) remains the instrument for Checks 1 and 2. It asks what number the
photograph shows. **This file asks what the object is**, and the two are not
interchangeable: a reading made under one cannot be compared with a reading made under
the other. Changing this file means issuing `objects-v2.1`, not editing in place.

---

## Why this instrument exists

Check 3 asks whether the harmonization crosswalk is right: when it pools two vendor
labels — `bilog` with `binilog`, `large` with `dalagku nga putos` — do those labels
actually name the same kind of object?

`v1.0` cannot answer that. It records `display_text`, `package_text`, `photo_type` — all
numbers and formats. A reader could complete every `v1.0` field perfectly and say nothing
about whether a whole chicken and a chicken piece are the same thing.

**The grouping is applied afterwards, not shown to you.** You describe one photograph at
a time and never learn which label it belongs to, or that any grouping is under test.
`17_check3_reconcile.do` joins your descriptions to the labels and asks whether they
separate. This is deliberate: a reader told two photographs are *supposed* to match will
tend to report that they match, and the whole value of the check would be lost.

So the burden on these descriptions is unusual. **They must be detailed enough that
somebody who never sees the photograph can tell two different objects apart from the
words alone.** "A sachet" is not enough. "A clear plastic sachet, roughly palm-sized,
containing orange-brown crackers" is.

---

## The prompt

Everything below the rule is passed verbatim to a reader. Do not paraphrase it, and do
not add context about the weighing, the label, or the pipeline.

---

You are describing photographs taken by field officers during a market survey in Western
Visayas, Philippines. Officers photographed the goods they were measuring — a *bundle* of
vegetables, a *putos* sachet, a *lapad* of liquor, a whole chicken, a loaf of bread.

You will be shown a **contact sheet**: a grid of photographs, each with a white-on-black
label in its top-left corner reading `#0001`, `#0002`, and so on.

**Report one line per photograph, using the label printed on that tile.** Never report a
grid position. If a tile is blank or its label is unreadable, skip it — do not guess which
number it should have been.

Your job is to say **what the object is**. Not what it weighs, not what it costs, not
what it is called.

### What to record

For each photograph, output exactly one JSON object on its own line, with these keys:

```json
{"label":"0007","visible":"clear","object":"whole chicken, plucked, uncooked","form":"whole_animal","container":"none","container_material":null,"count_visible":1,"size_cue":"roughly the size of two hands","colour":"pale yellow-pink","product_text":null,"distinguishing":"head and feet still attached","notes":""}
```

**`label`** — the four digits from the tile's corner, as a string, without the `#`.

**`visible`** — `clear`, `partial`, or `unusable`.
Use `partial` when you can see the object but not well enough to describe it fully —
blocked by a hand, cut off by the frame, badly lit. Use `unusable` when you cannot tell
what the object is at all. **`unusable` is a correct and useful answer.** A confident
wrong description is far worse than an admission that the photograph does not show
enough.

**`object`** — **the single most important field.** A short plain description of the
thing being sold, as you would describe it to someone who cannot see the picture. Aim for
five to fifteen words. Say what it is, and what state it is in.

- Good: `"whole chicken, plucked, uncooked"`, `"single cut piece of raw chicken, bone in"`,
  `"small clear sachet of orange crackers"`, `"loaf of sliced white bread in a printed bag"`,
  `"flat rectangular bottle of clear spirit"`, `"small plastic cup of pale ice cream"`
- Too vague: `"food"`, `"a package"`, `"meat"`, `"snack"`
- Wrong kind of answer: `"375 mL"`, `"about 500 grams"`, `"a putos"`

**`form`** — exactly one of:

| value | means |
| :-- | :-- |
| `whole_animal` | an entire bird, fish, or animal |
| `portion` | a cut piece or part of a larger thing |
| `whole_produce` | an entire fruit or vegetable, or several loose ones |
| `bundle` | items tied, bound, or banded together |
| `packaged_unit` | a sealed or wrapped retail package |
| `loose_in_container` | goods sitting in a cup, tub, bowl, or open bag |
| `bottle` | a bottle, jar, or similar rigid vessel of liquid |
| `prepared_serving` | a made-up serving, e.g. a cone, a glass of drink |
| `other` | none of the above, but the object is identifiable |
| `indeterminate` | you cannot tell |

**`container`** — what the object is in or on, if anything: `none`, `sachet`, `bag`,
`cup`, `tub`, `bottle`, `can`, `box`, `tray`, `plate`, `cone`, `wrapper`, `net`, `other`.

**`container_material`** — `plastic`, `glass`, `metal`, `paper`, `foil`, `leaf`,
`other`, or `null` if there is no container.

**`count_visible`** — how many separate units of the thing are shown, as a number. Use
`1` for a single object. Use `null` if they cannot be counted (a heap, a pile, a crowd of
items).

**`size_cue`** — **free text, and worth real effort.** Anything in the picture that tells
a reader how big the object is: a hand holding it, a coin, a scale platter, a standard
bottle, a crate, floor tiles. Say what the reference is and how the object compares.
`"held in one hand, fills the palm"`, `"about a third the width of the scale platter"`,
`"roughly two-thirds the height of the 1.5 L bottle beside it"`. `null` if there is
nothing to judge by.

This field is how a size difference gets separated from a kind difference, so a vague
answer here costs more than it looks.

**`colour`** — the dominant colour or colours of the product itself, not its packaging.
`null` if the product is not visible.

**`product_text`** — any brand name, product name, or flavour printed on the packaging,
copied verbatim. `"Rebisco Crackers"`, `"Ginebra San Miguel"`. **Do not record net
weights or volumes here** — they belong to the other instrument and are not what this
check is about. `null` if there is none.

**`distinguishing`** — free text. The single feature that would most help someone tell
this object from a similar one: `"head and feet still attached"`, `"individually wrapped
inside the outer bag"`, `"flat hip-flask shape rather than round"`, `"served in a cone
rather than a cup"`. `null` if nothing stands out.

**`notes`** — free text, short. Anything that qualifies your answer: a second object in
frame, an obstruction, uncertainty about what you are looking at. Empty string if nothing
to say.

### Rules

1. **Describe only what is in the picture.** Do not infer the product from the setting,
   and do not guess a brand you cannot read.
2. **Never report a weight or a volume in any field.** If a package states one, ignore it.
   A different instrument records those, and reporting them here invites the comparison
   this check exists to make to be made on numbers instead of objects.
3. **Do not name the local unit.** Do not write `putos`, `bilog`, `lapad`, `bundle` as
   your `object` description even if you recognise it. Those are the labels under test.
   Describe the thing, not the word for it.
4. **`partial` and `unusable` are real answers.** Use them.
5. **Report every tile you can see**, including `unusable` ones.
6. **Output only the JSON lines.** No commentary before or after, no markdown code
   fences, no summary. One line per photograph.

---

## Blinding

**Readers are shown the photograph and nothing else.** No id, no label, no item name, no
weight, no indication that photographs are grouped or that any pair is under test.

`PROMPT.md` v1.0 records that Check 3 *may* name the labels — "it asks whether two labels
name the same object, which cannot be asked without naming the labels." That permission is
real but **not needed under this design**, because the grouping is applied afterwards, by
`17_check3_reconcile.do`, to the descriptions. Reading blind costs the same number of
photographs and buys a stronger inference.

The asymmetry this avoids is worth stating, because it is why the design is built this
way. A reader shown a group and told the members are supposed to match is primed to agree.
Under that design a report of "these look different" is strong evidence — it was made
against the prime — but a report of "these look the same" is weak, because it is what the
reader was set up to say. Reading blind makes both directions mean the same thing.

---

## How this instrument is validated

**It is calibrated against the weight test, not against a person.** Checks 1 and 2 could
be scored by a human because "what does this display read" has one right answer a person
can supply. "Are these two labels the same kind of object" does not — a person would be
guessing from the same photographs.

So `16_check3_draw.do` includes controls whose answer is already known:

| control | pairs | what a failure means |
| :-- | :-- | :-- |
| **positive** — the weight test says `different` on a large ratio | chicken `bilog` / `pieces or units` (3.74×), crackers `putos` / `pack` (0.27×), ice cream `putos` / `pack` (0.56×), camote `bilog` / `binilog` (1.33×) | if the descriptions cannot separate these, the instrument cannot separate anything, and nothing it says about the unresolved pairs is worth reading |
| **negative** — the weight test confirms `equivalent` near 1.00 | cabbage `bilog` / `binilog` (0.96), liquor `lipid / lapad` / `lapad` (1.00), loaf bread `large` / `dalagku nga putos` (1.00) | if the descriptions report a difference here, the instrument finds differences that are not there — the more dangerous failure, since an objection is the actionable verdict |

Only if both controls behave does a reading of the 7 unresolved pairs mean anything.

---

## Known limits of readings made with this instrument

State these wherever a verdict produced by it is reported.

- **Not deterministic.** A re-run may differ. The instrument is fixed; the reader is not.
- **Agreement is not correctness.** Two readers of the same model family share failure
  modes. Cross-model agreement is weaker-but-real evidence.
- **No human ground truth exists for the question.** Unlike Checks 1 and 2, the controls
  are the validation. That makes the control result load-bearing in a way a reader
  agreement rate is not.
- **A description can be right and still too coarse.** Two genuinely different objects
  may both be honestly described as "a small clear sachet", and the difference lost. This
  is the failure the positive controls are designed to detect, and the reason `size_cue`
  and `distinguishing` exist.
- **Photographs are not a random sample of the label.** Six per label, stratified by
  hetero band. A label whose photographs happen to show one vendor's product will look
  more homogeneous than the label really is.
- **Untested as of v2.0**: whether blind description separates pairs at all. That is what
  the calibration measures, and until it reports, this instrument has no established
  performance of any kind.

## Changelog

| version | date | change |
| :-- | :-- | :-- |
| objects-v2.0 | 2026-09-30 | first issue. Object description for Check 3; no overlap with `PROMPT.md` v1.0, which stays the instrument for Checks 1 and 2 |
