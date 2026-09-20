# Photograph checks

Machinery for checking the cleaning pipeline against the field photographs: 11,506
JPEGs taken by field officers at the point of weighing, held in
`NSU Market Survey Launch/data/pictures`.

Three checks are defined in issue **#38** and the handover brief. This folder builds the
apparatus they need; it is not part of the build and nothing under `dofiles/` depends on
it.

| check | question | measured on |
| :-- | :-- | :-- |
| 1 | was a measurement taken at all, and is the unit tick right? | raw `weight` / `unit` |
| 2 | where the decimal was moved, did we get it right? | raw joined to published |
| 3 | do two pooled labels name one object? | the fold verdicts |

---

## Run order

A prerequisite, from `dofiles/` in the main project — it publishes the row-level flags
the target list reads:

```
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 90_diagnostics/photo_check_scope.do
```

Then, from `image checking/dofiles`:

```
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 01_photo_bridge.do
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 02_photo_targets.do
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 03_calibration_draw.do
```

From `image checking/scripts`, to build the sheets:

```
python make_contact_sheets.py --out-tag calib_v1 --ids ../outputs/tables/calibration_ids.csv \
    --shuffle --seed 20260919 --cell 700 --cols 2 --per-sheet 4
```

Readers then read those sheets under `PROMPT.md` and write one JSONL file each into
`outputs/readings/raw/<tag>/`. See *Dispatching readers*. Finally:

```
python parse_readings.py --tag calib_v1 --out ../outputs/qc/readings_calib_v1.csv
"C:\Program Files\StataNow19\StataSE-64.exe" -e do 04_photo_reconcile.do
```

`stata -e` exits 0 even when a do-file errors. Check the log for `r(` followed by a
number and a semicolon; an exit status of 0 is not evidence the step ran. The same
applies to the shell: a Stata invocation that never starts leaves the PREVIOUS log in
place, and reading it looks exactly like a successful run. Check the log's timestamp.

## What each file does

| file | does |
| :-- | :-- |
| `PROMPT.md` | **the reading instrument.** Versioned; its version is recorded against every reading |
| `dofiles/00_photo_globals.do` | paths. Runs the build's own `00_globals.do` first, so `${data}`, `${tables}` and `def_hetero` mean the same here as in the pipeline |
| `dofiles/01_photo_bridge.do` | **the join.** Links every photograph to the weighing it depicts, via the durable `id` |
| `dofiles/02_photo_targets.do` | which photographs to pull for Checks 1 and 2. Defines no populations of its own |
| `dofiles/03_calibration_draw.do` | the stratified, seeded sample the instrument is tested on |
| `dofiles/04_photo_reconcile.do` | **the unblinding step.** Reliability, then Check 1, then Check 2 |
| `scripts/make_contact_sheets.py` | tiles photographs into blinded sheets, and writes the manifest that unblinds them |
| `scripts/parse_readings.py` | validates reader output and joins it back to `id` |
| `scripts/sevenseg.py` | reads the red LED scale display. **Does not work — see below** |

## Dispatching readers

Readers are subagents. Each is given `PROMPT.md` verbatim, a list of sheet filenames,
and an output path; it reads the sheets and writes one JSON object per photograph.

**Two models read the same sheets.** That is what makes agreement measurable, and it is
the only reason a reading can be quoted at all. Within a model the work is split across
several workers over *disjoint* sheets, so the model is one reader between them —
`04_photo_reconcile.do` halts if two workers of one model read the same image, because
an overlap would silently corrupt the agreement denominator.

Reader output is never edited. A malformed batch is re-run, not patched.

## What the calibration is drawn from, and why not at random

A random sample of the target list is dominated by easy images, and agreement measured
on easy images does not transfer to the hard ones — which are the only ones the answer
turns on. `03_calibration_draw.do` therefore stratifies and over-samples the awkward
cells, 20 per stratum:

| stratum | why |
| :-- | :-- |
| C1 solid as Litres | 17 in the build; small enough to do exhaustively |
| C2 review queue | already wrong relative to its neighbours |
| C2 dimension overrule | asserts the officer picked the wrong dropdown item |
| C1 flat-group rep | expected answer is a printed label and no scale at all |
| C2 block governs | where `KGMAX` and the `<10` threshold actually decided something |
| C1 liquid as mass | A23's item-level verdict overruled these |
| C1 dual-ticked | a contradiction inside one cell |
| C2 magnitude | the bulk case |

Two ordering choices in that file are load-bearing, and both were bugs first:

- **Stratify before collapsing to one row per image.** All 348 dimension overrules are
  also Check 1 rows — overruling a tick is exactly what makes a weighing
  liquid-ticked-as-mass or dual-ticked — so taking the lowest `check` per image first
  absorbed every one of them into Check 1 and left the Check 2 dimension cell with zero
  rows, while reporting success.
- **Break ties by scarcity, not by check.** An image wanted by two strata is worth more
  to the calibration in the smaller one.

Images already seen are excluded by id through `outputs/qc/seen_ids.csv`, which is
appended to and never rewritten: an image once seen is seen permanently. Sixteen
photographs were read openly while this pipeline was being built, so a "blind" re-read
of them would not be blind.

## The join

The photo crosswalk keys a filename on a submission `KEY` and a photo slot; the raw
survey keys a weighing on `key` and `obs_type`. The slots and the obs_type values are
the same nine categories under two spellings:

```
crosswalk KEY + photo_variable  ==  raw key + obs_type  ->  one weighing  ->  id
```

`key` + `obs_type` is unique in the raw survey. The `id` is looked up in
`outputs/tables/weighing_id_registry.csv` and never minted here — if a row has no id the
fix is in `00_shared/00a_weighing_ids.do`, not a number invented in a diagnostic.

Neither `prelim_nsu_data.dta` nor `nsu_weighings_cpi.dta` carries `key`, which is why
the join starts from the raw survey.

Measured 2026-09-19:

| | count |
| :-- | ---: |
| crosswalk rows | 11,480 |
| matched to a raw weighing | 11,459 |
| raw weighings with no photo slot | 36 — all `unique_mun_price6/7` |
| photos matching no raw weighing | 21 |
| **usable pairs published in the bridge** | **11,449** |

The do-file reports these against a recorded baseline. A move is **information**, not a
failure: it means the survey was re-exported or the crosswalk rebuilt. Structural
violations — a duplicate filename, a caseid disagreement, a row with no id — halt.

## Blinding

**Contact sheets carry a sequence number and nothing else.** No id, no typed weight, no
unit tick, no published value.

This is not ceremony. A reader who sees "typed 0.8, published 800" before looking at the
display is being asked to confirm a number rather than read one, and will tend to
confirm it — which would make the check validate the pipeline because it was told what
the pipeline said. The sequence-to-id mapping is written to a separate manifest and
joined only after readings are recorded.

Samples are drawn with a recorded seed, stored in the manifest, so a later session
drawing the same population reproduces the same rows.

## Status of the OCR reader

`sevenseg.py` **does not work well enough to use.** Recorded here rather than deleted,
because the negative result is worth keeping and the diagnosis says what a second
attempt would have to solve.

Tested on 45 photographs of fresh items, where a scale is nearly always present:

| | |
| :-- | ---: |
| reported `ok` | 22 |
| reported `partial` | 23 |
| **actually correct** | **≈0** |

The `ok` rows are the dangerous part — confident readings like `88` where the display
plainly reads `0.430`. Two independent failures:

1. **Colour does not isolate the display.** The mask keys on red, and a market stall is
   full of red and orange: carrots, tomatoes, crates, signage. On one carrot photograph
   the largest "display" candidate was the carrot, at 601×196 px. Tightening the mask to
   require genuinely low green and blue (LED red is ~`(220,30,20)`, carrot orange
   ~`(230,130,60)`) cuts stray pixels by 90% on some images and barely moves others.
2. **Inactive segments still glow.** The Micromatic shows three rows — WEIGHT, UNIT
   PRICE, TOTAL PRICE — and the unlit ones read as a faint `8.8.8.8.8`. Deciding lit
   from unlit is genuinely ambiguous at the pixel level, which is why so many readings
   decode as `8` or `88`.

### What this does NOT establish

That no reproducible reader is possible. **One method was tested, and it was the weakest
plausible one.** Colour thresholding is what you reach for when the target object is not
repeatable. Here it is: every photograph shows the same Micromatic body, with a
high-contrast keypad (`7 8 9 / TARE`, `4 5 6 / ZERO`, …) in a fixed geometric
relationship to the display. That is the standard case for **feature matching against a
reference image** — match, solve a homography, rectify, then crop the display at known
relative coordinates. It handles angle and distance, it is deterministic, and it was not
tried. `opencv-python` installs cleanly on this machine's Python 3.14.

Two things also make the problem smaller than it first looks:

* **Check 2 may not need full digit recognition.** What it asks is whether the decimal
  was moved correctly — `0.800` against `800`. Digit *count* and decimal *position*
  answer most of that, and are far easier to recover than every glyph.
* **The population is probably well under 2,472.** If the label-transcription pattern
  above holds, many Check 2 rows have no scale in the photograph at all. Those are
  settled by Check 1, and no OCR is owed on them.

Rescuing the colour approach — dark-bezel constraint, local contrast normalisation,
WEIGHT-row identification — is a real effort for an uncertain payoff. The template route
is the one to try first, and it has not been tried.

**No OCR tooling is installed on this machine** (no tesseract, no opencv, no GPU) and
none was needed to establish the above — `sevenseg.py` uses only numpy, scipy and
Pillow, which are present. General-purpose OCR would not obviously help: tesseract has
no seven-segment training data and performs poorly on LED glyphs.

## What the photographs actually show

Worth stating up front, because it contradicts the premise the checks were specified
under. The brief assumes each image shows a scale with a reading and an object on it.
On an initial sample of 7, **only the fresh items did**:

| item | typed | photograph |
| :-- | :-- | :-- |
| chicken | `1085 g` | scale, display `1085` |
| cabbage | `0.8 g` | scale, display `0.800` |
| liquor | `375 g` | bottle held to shelf. Label `375 mL`. No scale |
| loaf bread | `640 g` | loaf in a crate. Label `Net Wt. 640 g`. No scale |
| crackers | `40 g` | wafer pack on a table. No scale |
| ice cream | `0.085 L` | sachet. Label `85 ml`. No scale |
| mineral water | `0.006 L` | bottle. Label `6 LITERS / 6000 ml`. No scale |

Two consequences, both unconfirmed at this sample size:

- **The flat-group test under-detects.** Crackers (1.5% flat) and loaf bread (12.3%)
  both showed label photographs, so label-reading reaches items the test scores as
  genuinely weighed.
- **A23 may not be a safe relabel.** The ice cream and water readings are printed
  *volumes*, so converting at 1 g per mL relabels a volume as a mass.

Sizing these properly is what Check 1 is for.

Separately, the scale displays in **kilograms to three decimals** on some photographs
and in grams on others, and field officers typed the display verbatim either way. That
is a mechanism for the `< 10 → ×1,000` rule in `03a_block_reading.do`, which until now
rested on convention — and it bears directly on issue **#37 item 2**.

## Conventions

Inherited from the project's `CLAUDE.md` and `dofiles/README.md`:

- Objects the checks read are built in **Stata**. Python only for image I/O and `.xlsx`.
- A diagnostic reads what the pipeline computed; it never recomputes it.
- Write files with editor tools, never a shell heredoc.
- Verdicts are an **input** to the pipeline, keyed on `id` — never a hand-edit of a
  deliverable, which rebuilds from its inputs and would overwrite them.

## Not built yet

- `02_photo_targets.do` — the Check 1 and Check 2 must-tier target lists
- the verdict ledger, and `04_photo_reconcile.do` which joins it to the published columns
- Check 3's label-pair file
