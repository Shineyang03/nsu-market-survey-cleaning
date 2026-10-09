# Checking the cleaning pipeline against the field photographs

The NSU market survey recorded what a non-standard local unit weighs — a *bundle* of
camote tops, a *putos* of crackers, a *lapad* of liquor. Field officers weighed on a
portable scale and typed a number plus a unit tick, and **they also photographed what
they were looking at**: 11,506 JPEGs, one per weighing.

Those photographs are ground truth. They show what was measured, what it was measured
on, and what the vendor called it — things the recorded numbers can only be argued
about. This folder is the machinery for reading them and checking the build against
what they say.

**Start here:** run order below, then *What the photographs showed* for the results.
The three checks are defined in issue **#38**.

---

## Run order

Prerequisite, from `dofiles/` in the main project:

```
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics/photo_check_scope.do
```

Then from `image checking/dofiles`:

```
01_photo_bridge.do            link every photograph to its weighing
02_photo_targets.do           which photographs each check needs
11_sweep_draw.do              the Check 2 population, and what is unread
```

From `image checking/scripts`, to build blinded sheets:

```
python make_contact_sheets.py --out-tag <tag> --ids <ids.csv> --shuffle --seed 20260920 \
    --cell 700 --cols 2 --per-sheet 4
```

Readers read those sheets under `PROMPT.md`, one JSONL each into
`outputs/readings/raw/<tag>/`. Then:

```
python parse_readings.py --tag <tag> --out ../outputs/qc/readings_<tag>.csv --expect-readers 1
```

Back in `image checking/dofiles`:

```
12_photo_readings_master.do   every reading, one dataset
13_apply_photo_rule.do        the override rule and what it proposes
```

`13` writes a review queue. A person rules on it in Excel, and the answers come back
through the same parser that reads the blind workbooks, in its other mode:

```
python parse_validation_workbook.py --mode adjudicate --shown proposed_value \
    --xlsx ../outputs/qc/override_review_v2.xlsx \
    --key  ../outputs/qc/override_review_v2_key.csv \
    --out  ../outputs/qc/override_verdicts_v2.csv
```

Use `--shown photo_g` for the hold workbook, whose proposal column is named differently.
**It exits non-zero on an unanswered row, a malformed value, or a rejection with no
replacement**, so an incomplete review cannot be mistaken for a finished one.

Re-running `13` once a verdict file exists also writes `override_review_new.csv` — the
queue minus the rows already ruled on. Build the next workbook from *that*, not from the
full queue: a rule change upstream regenerates the whole population, and handing back
photographs someone has already judged invites them to disagree with themselves.

**Which number a photograph yields** when it shows a display, a label, or both is
**A25** in `docs/implicit_assumptions.md`. The one non-unit density this project applies
— 0.9 g per mL for ice cream — is `${DENS_ICECREAM}` in `00_shared/00_globals.do`, with
its derivation and the spread it papers over.

**`stata -e` exits 0 even when a do-file errors.** Check the log for `r(` followed by a
number and a semicolon. Check its **timestamp** too: a Stata invocation that never
starts leaves the previous log in place, and reading it is indistinguishable from a
successful run. That happened here.

**Pin the picture folder to *Available offline* before any sweep.** Generating 592
sheets from the streamed Box drive took 50 minutes at ~1.5 s per image, essentially all
of it network wait. `make_contact_sheets.py` now prefetches on 12 threads, which makes
an unpinned folder tolerable, not fast.

---

## How the pieces fit

| file | does |
| :-- | :-- |
| `PROMPT.md` | **the reading instrument**, versioned. Every reading records its version |
| `dofiles/00_photo_globals.do` | paths; runs the build's own globals first |
| `dofiles/01_photo_bridge.do` | **the join** — photograph ↔ weighing, via the durable `id` |
| `dofiles/02_photo_targets.do` | must-tier target lists for Checks 1 and 2 |
| `dofiles/03_calibration_draw.do` | the stratified set the instrument was tested on |
| `dofiles/04_photo_reconcile.do` | reliability, then Check 1, then Check 2 |
| `dofiles/05_resolution_test_draw.do` | the presentation A/B |
| `dofiles/06_resolution_compare.do` | …and its result |
| `dofiles/07_human_validation_draw.do` | the 40 a person reads |
| `dofiles/08_score_against_human.do` | **the only non-circular scoring** |
| `dofiles/09_photo_corrections.do` | verdict ledger from the human readings |
| `dofiles/10_stage_ledger_additions.do` | those verdicts in the build ledger's schema |
| `dofiles/11_sweep_draw.do` | the full Check 2 population |
| `dofiles/12_photo_readings_master.do` | **every reading, one dataset** |
| `dofiles/13_apply_photo_rule.do` | the override rule |
| `scripts/make_contact_sheets.py` | blinded sheets + the manifest that unblinds them |
| `scripts/parse_readings.py` | validation gate on reader output |
| `scripts/make_validation_workbook.py` | the workbook a person reads |
| `scripts/parse_validation_workbook.py` | reads it back |
| `scripts/sevenseg.py` | deterministic OCR. **Does not work** — see below |

## The join

The photo crosswalk keys a filename on a submission `KEY` and a photo slot; the raw
survey keys a weighing on `key` and `obs_type`. The nine slots and nine obs_type values
are the same categories under two spellings:

```
crosswalk KEY + photo_variable  ==  raw key + obs_type  ->  one weighing  ->  id
```

`key` + `obs_type` is unique in the raw survey. The `id` is looked up in
`weighing_id_registry.csv` and **never minted here**.

| | |
| :-- | ---: |
| crosswalk rows | 11,480 |
| matched to a raw weighing | 11,459 |
| raw weighings with no photo slot | 36 — all `unique_mun_price6/7` |
| photos matching no weighing | 21 |
| **usable pairs** | **11,449** |

---

## The three rules that make the readings worth anything

### 1. Blinding

**A contact sheet carries a sequence number and nothing else** — no id, no typed weight,
no published value, no item name, no stratum, and no hint which rows are contentious.
The sequence-to-id manifest is written separately and joined only after readings are
recorded.

This is load-bearing, not ceremony. A reader shown *"the officer typed 0.8 and we
published 800"* is being asked to confirm a number rather than read one, and will tend
to confirm it — which would make the check validate the pipeline because it was told
what the pipeline said.

The human workbook goes further: nothing is pre-filled. That **deliberately breaks**
`docs/adjudication_playbook.md`, which says to pre-fill every verdict because
confirm/override is cheap. That rule is right when a reviewer *adjudicates* a judgement
call. Here the person is the measuring instrument, and pre-filling an instrument with
the answer destroys it.

### 2. The typed value is never the yardstick

Early scoring compared readings against the typed weight. **That is backwards** — the
photographs are what the typed data is being checked against, so scoring against it
makes the evidence answerable to the thing it judges, and it cannot yield an accuracy
figure at all: a perfect reader would score `100% − (officer mis-typing rate)`, which is
the unknown being sought.

Reader quality is therefore measured two ways only: **against each other** (yardstick
free) and **against a human** (`08_score_against_human.do`). Anything comparing a
reading with a typed or published value is a *finding*, never a score.

### 3. Everything is keyed on something durable

Readings key on `image_code` — the crosswalk's own key, unique per photograph, and safe
to show since it is a capture timestamp carrying nothing about the weight. **A row
number is not a key**: it changes when a set is re-drawn, re-shuffled, re-sent, or
sorted. `id` would leak a little (ids run in province, municipality, item order), so it
stays out of anything a reader sees.

---

## What the photographs showed

### The premise the checks were written under was wrong

`NSU_photograph_checks_brief.md` assumes each image shows a scale with a reading and an
object on it. The first seven read say otherwise — **only the fresh items did**:

| item | typed | photograph |
| :-- | :-- | :-- |
| chicken | `1085 g` | scale, display `1085` |
| cabbage | `0.8 g` | scale, display `0.800` |
| liquor | `375 g` | bottle held to a shelf. Label `375 mL`. No scale |
| loaf bread | `640 g` | loaf in a crate. Label `Net Wt. 640 g`. No scale |
| ice cream | `0.085 L` | sachet. Label `85 ml`. No scale |
| mineral water | `0.006 L` | bottle. Label `6 LITERS / 6000 ml`. No scale |

The scale displays in **kilograms to three decimals** on some photographs and grams on
others, and officers typed the display verbatim either way while the tick did not track
the mode. That is a mechanism for `03a_block_reading.do`'s `< 10 → ×1,000` rule, which
until now rested on convention — and it answers issue **#37 item 2**.

### Reader reliability, measured

Two models read 148 stratified images; a person then read 40 of them blind.

| | agreement / accuracy |
| :-- | ---: |
| is a scale present (model vs model) | **96.6%** |
| exact display text (model vs model) | 54.3% |
| **Sonnet vs the human** | **97.0%** |
| **Haiku vs the human** | **55.6%** |

The 54.3% was **not** a hard task — it was one bad reader. **Haiku is never used for
digit reading.** It survives in the master as a column only so the disagreement that
established this stays visible in the data.

**Resolution is not a lever.** The same 46 images at 1500px single versus 700px 4-up
scored **88.4% either way**, and the two presentations agreed with each other on all 43
they both read. Presenting images larger buys nothing.

### Check 1 — a clean split runs through the build

| stratum | no scale | scale |
| :-- | ---: | ---: |
| C2 dimension overrule | **19 (95%)** | 0 |
| C1 flat-group rep | **19 (95%)** | 0 |
| C1 dual-ticked | 17 (85%) | 3 |
| C1 solid as Litres | 13 (76%) | 4 |
| C2 block governs | 3 | 16 (80%) |
| C1 liquid as mass | 1 | **18 (90%)** |
| C2 magnitude | 0 | **19 (95%)** |

Where the pipeline made a **dimension** judgement there is usually no scale — the number
was read off a package label. Where it made a **magnitude** judgement there usually is
one.

- **The flat-group test is vindicated.** Its representatives really are label
  transcriptions.
- **The dimension overrules reach the right answer by the wrong mechanism.** All 20 show
  no scale and 19 carry a printed label whose volume *equals the typed number exactly* —
  `750 g` typed against `750 mL` printed. So relabelling to mL recovers the printed unit
  and is correct. But the recorded justification (an officer weighed it and ticked grams
  for want of an mL option) is not what happened: these are **declared pack sizes**, not
  measurements of a vendor's unit. Filed as **#40**.
- **A23's one verdict acts on two populations with opposite provenance.** Liquor was
  never weighed. *Drinks at restaurant* were — 19 of 20 show a scale, and the display
  corroborates the typed value. A density correction, if one were ever owed, belongs to
  the drinks rows and not the liquor rows where the discussion has been.

### Check 2 — the sweep

All 2,460 Check 2 must-tier weighings with a photograph were read.

| | |
| :-- | ---: |
| photographed weighings with a reading attempt | 2,515 |
| **with a resolved display reading** | **1,862** |
| **published value matches the photograph** | **1,746 (93.8%)** |
| override, under 2× | 79 (4.2%) |
| **held for a human, 2× or more** | **37 (2.0%)** |

**Where the errors are:**

| rule that set the published value | confirm | hold |
| :-- | ---: | ---: |
| `block governs` | 82.4% | **10.8%** |
| `log10 median` | 94.4% | 1.5% |

`block governs` rows are **7× more likely** to need review — independent confirmation of
`photo_review_queue.do`, which predicted exactly that concentration. Those are the rows
where `KGMAX = 30` and the `< 10` threshold actually decided something.

Held rows by magnitude: 19 at 2–5×, 16 at 5–20×, **2 at 20×+**.

Human-confirmed decade errors so far, each published 10× too high:

| image code | display | published | should be |
| :-- | --: | --: | --: |
| `1773810007262` | `0.095` | 950 | 95 |
| `1773724826947` | `0.06` | 600 | 60 |
| `1773796774872` | `0.04` | 400 | 40 |
| `1775787569138` | `0.045` | 450 | 45 |

---

## The override rule

Set by the project owner, 2026-09-20:

> Where a photograph reading differs from the published value, **the photograph
> governs** — except that anything **2× or more** away is held for a human first.

The gate spends attention where a model error would do damage. Sonnet reads at 97%, so
roughly 3% of overrides are wrong: a poor trade if the wrong changes are large, a fine
one if they are small. A decade slip moves a weight 1,000%; a 5% disagreement is within
the noise of a glary display. **A human-read row is never held** — the confirmation the
gate exists to obtain has already happened.

### The mL rule

> Where a printed volume and a scale reading are both legible, **the printed volume
> governs**, even against the enumerator's record.

Applied only on human-read rows, because it overrides a field record. Model rows that
saw a package label carry `mL_rule_pending` so the rule's reach is visible — 385 of
them.

### Nothing here is applied

These write **proposals**. Section 9 of the brief: verdicts are an *input* to the
pipeline, never an edit to a deliverable, because deliverables rebuild from their inputs
and a hand edit is silently overwritten.

| to change | edit |
| :-- | :-- |
| a weight | `reference/reviewed/snap_verdicts.csv` (§6 of `05_manual_corrections.do`) |
| a dimension | `reference/reviewed/unit_verdicts.csv` (§1d, added here) |

Then rebuild and run `python dofiles/verify_pipeline.py`.

**Two cautions on applying.** Superseded ledger rows must be **removed**, not appended
beside — §6 asserts one key never carries two verdicts, so a careless append halts the
build. And three of the human corrections **overwrite an earlier human adjudication**;
on two of them the ledger chose the block reading and the photograph agrees with the
anchor, which is itself evidence on #38 §3.

---

## Things that went wrong, and what they cost

Recorded because each was silent, and a reader deserves to know which numbers were once
wrong.

| what | cost | fix |
| :-- | :-- | :-- |
| A Stata call never ran; the **previous log** was read instead | counts quoted from a stale run | check the log's timestamp |
| Collapsing by `check` before stratifying **emptied a whole stratum** — all 348 dimension overrules are also Check 1 rows | the Check 2 dimension cell came out zero while reporting success | stratify first, break ties by scarcity |
| The parser's missing-tile check only looked *within sheets a reader touched* | a wholly skipped sheet was invisible; 4 images unread | coverage checked against the manifest |
| Re-scaling the **raw typed value** re-implements the block rule and missed the litre branch | a false positive reported **twice** | compare `corrected_weight`, which the pipeline already computed |
| Excel coerced 37 of 40 human answers to numbers | `0.300` returned as `0.3`; exact-string check unavailable | text format on the answer column |
| A transient Box read failure was baked into a sheet as UNREADABLE | 3 photographs recorded as corrupt when they were fine | retry with backoff in `cached_photo` |
| `import delimited` lowercases names | `mL_rule_pending` not found | rename on import |

The pattern is the same each time: **a failure recorded as a property of the data when it
was a property of the process.**

## The OCR reader does not work

`sevenseg.py` scored roughly zero on 45 photographs, and its confident readings were the
dangerous part — `88` where the display plainly reads `0.430`. Two causes: colour cannot
isolate an LED display in a stall full of carrots and crates, and unlit segments still
glow so everything decodes toward `8`.

**This does not establish that no deterministic reader is possible.** One method was
tested and it was the weakest plausible one. Every photograph shows the same Micromatic
body with a rigid keypad, which is the standard case for feature matching against a
reference image — match, solve a homography, rectify, crop at known coordinates.

### That rectification was then built, and the reader retried on it. It is still not good enough.

`rectify_display.py` does exactly what the paragraph above proposed, and it works: 6,939
displays located in 11,449 photographs (61%). `sevenseg.py --crop` then reads those
rectified crops with an adaptive mask — the red channel stretched between the crop's own
60th and 99.5th percentiles under a gamma of 2.2, the same transform `deghost_crops.py`
applies for human readers — instead of the absolute red threshold that produced the `8`s.

Measured against **18 crops whose readings the project owner confirmed by hand**:

| reader | exact matches |
| :-- | ---: |
| `sevenseg.py` on whole photographs | 0 of 15 readable, and `ok` on 14 of 18 |
| `sevenseg.py --crop`, threshold swept 0.35 → 0.70 | best **3 of 15**, at 0.60 |

**The failure moved but did not go away.** Digit decoding is now broadly right — the
hardest crop in the set decoded as `0.290`, exactly, and both independent readers had got
that one wrong. What breaks is segmentation: the crop still contains the `TARE`, `ZERO`
and `STAB` legends and the odd glare speck, each of which becomes a spurious box, and a
short box is read as a decimal point. So `0.145` arrives as `..0.145` and fails to parse.

The remaining work is bounded and obvious — restrict the band to the digit row, impose a
minimum blob area, require a decimal point to sit near the baseline. It was **not** done,
for one reason worth recording: there are 18 ground-truth crops, and tuning three more
thresholds against 18 observations produces a reader that works on those 18. Anyone
picking this up should collect a few dozen more confirmed readings first, and hold some
back.

**Until then the deterministic reader is not in the pipeline and its output is not
banked anywhere.** `--crop` exists so the next attempt starts from a measured baseline
rather than from zero.

## Decade only: the magnitude classifier and decimal-drift correction

Check 2's commonest error is a moved decimal point — the display read `0.045` and 450 g
was published. That needs the decade of the display, not its digits. Because the display
is always `x.xxx` kg, the decade is fixed by **where the first non-zero digit sits** among
the four positions, and that is a far easier question than reading a number: each
position is only *zero* or *not zero*, at a location the rectified crop already fixes.

`sevenseg.py --magnitude` answers it deterministically (no model): it fits a five-cell
digit grid to the unlit `8.8.8.8.8` ghost, scores each segment against the crop's own lit
level, and calls a position zero only when every seven-segment digit still consistent with
it is 0. It returns `uncertain` rather than guess — on weak contrast, an ambiguous middle
bar, a grid pinned at its search bounds, a missing decimal point, or disagreement across
ten perturbed repeats. Its thresholds and their rationale are in `MAG_PARAMS`.

`20_decimal_drift.do` then takes the decade from the display and the significant digits
from the published value: `k = decade(display) − floor(log10(published g))`, proposal =
published × 10^k. Status is `corrected`, `no_change` (checked, passed), `uncertain` (not
checked: no photograph, no crop, or the classifier declined) or `invalid_input`
(published in mL, missing or non-positive). Nothing is applied.

```
19_magnitude_labels.do        human-confirmed decade labels; tune/holdout split (frozen ledger)
python ../scripts/sevenseg.py --magnitude --manifest ../outputs/decimal_drift/check2_crop_manifest.csv \
    --crops ../outputs/rect_all --out ../outputs/decimal_drift/magnitude_check2.csv
20_decimal_drift.do           the proposal, the Sonnet comparison, the human scoring
```

Run it on the **as-shot** crops (`rect_all`), not `rect_all_dg`: the de-ghosting gamma
erases dim but lit segments. `rect_all/` is gitignored, so a clone or worktree holds only
the few crops that were committed early; point `--crops` at the full folder on Box.

**Measured, Check 2 (2,472 weighings):**

| | |
| :-- | --: |
| crops the classifier committed on | 1,760 of 1,971 (89.3%) |
| `corrected` | 13 |
| `no_change` | 1,715 |
| `uncertain` — 140 no crop, 11 no photograph, 207 classifier declined | 358 |
| `invalid_input` — almost all published in mL | 386 |

| against a person's reading | tune (67) | **holdout (65)** |
| :-- | --: | --: |
| classifier committed | 56 | **56** |
| wrong decade when committed | 0 | **0** |
| wrong automatic corrections | 0 | **0** |
| decade errors passed as `no_change` | 0 | **0** |

0 of 56 on the holdout bounds the confident error rate below roughly 5% (rule of three),
no tighter. **The labels are not a random sample**: most are owner verdicts on rows where a
model disagreed with the published value, so they over-represent hard displays and decade
disputes. That suits measuring wrong corrections and does not give a population accuracy.

**Against Sonnet** (agreement, not accuracy): on the 1,659 crops both read, they agree on
the decade on 1,650. All 9 disagreements have a human label, and **the person sides with
the classifier on all 9** — each is a Sonnet reading that would have moved a correct
published weight by a factor of ten.

## Limits to state wherever these numbers are quoted

- **No result here is a population rate.** The calibration strata deliberately
  over-sample awkward cells; the sweep covers the Check 2 must tier, which is 21.8% of
  weighings chosen because judgement was applied to them.
- **Agreement is not accuracy.** Only the 40 human readings are ground truth, and 97%
  rests on 33 of them.
- **Readings are not bit-reproducible.** The instrument is fixed and versioned; the
  reader is not. This is the same standing as the hand verdicts already in
  `05_manual_corrections.do`.
- **`05_manual_corrections.do` §1d is untested.** It was added but the build has not been
  re-run, because rebuilding would overwrite the outputs the sweep reads.

- **A scale reading and a package label are not the same measurement, and no density
  reconciles them.** A scale reading is whatever sat on the pan — for a packaged good
  that is usually **gross**: contents plus wrapper, cup, stick or bottle. A printed
  label states **net contents**. So where a case holds both kinds of number, converting
  the volume to grams makes the two *comparable in units* without making them
  *measurements of the same thing*; a residual gap remains, in the direction of the
  scale reading being the larger. The gap is widest exactly where it matters most —
  small items whose packaging is a large share of gross weight, such as an 85 mL
  sorbetes sachet or a cone. Nothing in the collected data sizes it. Quote any
  reconciled figure with this stated, and do not read a leftover discrepancy between a
  weighed row and a label row as evidence that one of them is wrong.

## The display cropper, and what it turned out to be

`scripts/rectify_display.py` cuts the WEIGHT display out of a photograph by matching the
keypad and solving a homography. Two measurements, on top of the 38-of-40 in its header.

**A cropped display is a better thing to read than a whole photograph.** The same reader
read the same 38 photographs twice, blind, once as full photographs and once as crops:

| | |
| :-- | --: |
| same number both ways | **35 / 38** |
| crop marked legible | **38 / 38** |

Of the three differences, **two are not disagreements**. On the full photograph the
reader read the *package label*; on the crop they read the *scale display*, and the two
say different things about the same weighing:

| image | label | display | |
| :-- | :-- | :-- | :-- |
| `1773731054952` | 355 mL | 0.700 kg | a drink whose cup and ice weigh as much again |
| `1773730865630` | 355 mL | 0.760 kg | |

That is the gross-vs-net gap in the limits section above, measured rather than asserted.
The third difference is a genuine digit ambiguity, `0.545` against `0.540`.

**It is also a scale detector, which was not the intention.** On a seeded random sample
of 150 photographs it located a display in 86 (57.3%). That looked like a coverage
problem until it was cut against what the photographs actually contain:

| the photograph is | cropper found | missed | |
| :-- | --: | --: | --: |
| a scale reading | **21** | **0** | **100%** |
| a package label — nothing to crop | 0 | 15 | correctly |

Perfect separation on the 36 sampled photographs that had already been read. So 57.3% is
not a failure rate; it is roughly the share of photographs that contain a scale, and
**whether the cropper succeeds is itself the routing signal** — scale photographs to the
crop reader, label photographs to a full-photograph reader. n=36 is small and the claim
deserves re-testing at scale, but the separation is clean and the marginal cases are not
marginal in practice: the weakest match in the sample, 13 inliers, still produced a
clean legible crop.

**A correction to commit `1f5b0c4`.** Its message claims image `1775610644371` reads
`1.300` where the human recorded `0.3`, and calls it a probable human error. That was a
misreading of a montage, not a finding: both passes read `0.405`, and they agree. The
image is not a disagreement and nothing rests on it.

## Not done

- Check 1's own sweep — only its calibration sample has been read.
- Check 3 entirely; its unit is a label pair, so it needs its own file.
- Spot tiers, which need the packaged/fresh classification published out of
  `photo_check_packaging.do` the way the other two now are.
- Whether `psps_grams` forces mL → g at 1:1 downstream. Until that is traced, the
  density question is settled for Outcome 1 only.
