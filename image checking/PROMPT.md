# Reading instrument v1.0

**Version `v1.0`, 2026-09-19.** This file is the coding manual for reading NSU market
survey photographs. It is committed, versioned, and its hash is recorded against every
reading made with it.

Changing it means issuing a new version, not editing in place — readings made under
different versions are not comparable, and a verdict that cannot say which instrument
produced it cannot be audited. If you need a change, add `v1.1` below and leave `v1.0`
intact.

**Why an instrument at all.** Readings are made by a model, and a model's output is not
bit-reproducible. What *can* be fixed is the question. That is how survey coding is made
rigorous: you do not make the coder deterministic, you fix the manual, record its
version, and measure agreement between coders. This file is that manual.

---

## The prompt

Everything between the rules below is passed verbatim to a reader. Do not paraphrase it,
and do not add context about the weighing — see *Blinding*.

---

You are reading photographs taken by field officers during a market survey in Western
Visayas, Philippines. Officers were asked to record what a non-standard local unit (for
example a *bundle*, a *putos* sachet, a *lapad* of liquor) weighs.

You will be shown a **contact sheet**: a grid of photographs, each with a white-on-black
label in its top-left corner reading `#0001`, `#0002`, and so on.

**Report one line per photograph, using the label printed on that tile.** Never report a
grid position. If a tile is blank or its label is unreadable, skip it — do not guess
which number it should have been.

### What to record

For each photograph, output exactly one JSON object on its own line, with these keys:

```json
{"label":"0007","photo_type":"scale_with_item","item_on_scale":true,"display_text":"0.155","display_legible":"clear","display_unit_shown":"none_shown","package_text":null,"package_qty":null,"package_unit":null,"notes":""}
```

**`label`** — the four digits from the tile's corner, as a string, without the `#`.

**`photo_type`** — exactly one of:

| value | means |
| :-- | :-- |
| `scale_with_item` | an electronic scale with an object on its platter |
| `scale_no_item` | a scale is visible but nothing is on it |
| `item_no_scale` | an object, held or placed, with no scale in the picture |
| `label_closeup` | the photograph is mostly a printed label or packaging |
| `jug_graduated` | a measuring jug, graduated cylinder, or marked container |
| `other` | none of the above, but the image is legible |
| `unreadable` | too dark, blurred, or obstructed to classify |

**`item_on_scale`** — `true`, `false`, or `null` if there is no scale.

**`display_text`** — **the characters shown on the scale display, exactly as displayed.**
This is the single most important field.

- Copy what you see, character for character: `"0.155"`, `"1085"`, `"0.800"`, `"1.22"`.
- **Keep the decimal point and every leading and trailing zero.** `0.800` is not `0.8`
  and is not `800`. The whole purpose of this reading is to tell those apart.
- Do not convert units. Do not tidy the number. Do not infer a plausible weight from the
  object.
- If there is no scale, or the display is off or blank, use `null`.
- If you can read some digits but not all, use `null` here and put what you could see in
  `notes`.

Most of these scales show three stacked red rows — **WEIGHT** on top, then unit price,
then total price. **Report the WEIGHT row only.** Unlit segments still glow faintly; a
row showing a dim `8.8.8.8.8` is *blank*, not eights.

**`display_legible`** — `clear`, `probable`, `ambiguous`, or `not_visible`.

Use `probable` when you are fairly confident but glare, angle or blur leave real doubt.
Use `ambiguous` when you cannot settle it. **`ambiguous` is a correct and useful answer.**
A wrong number is far worse here than an admission that the display could not be read.

**`display_unit_shown`** — `kg`, `g`, `none_shown`, or `indeterminate`. Many of these
displays print no unit at all; `none_shown` is common and correct.

**`package_text`** — any printed weight or volume on the packaging, copied verbatim:
`"Net Wt. 640 g"`, `"375 mL"`, `"6 LITERS"`. `null` if there is none or the object is
unpackaged. If several appear, give the most prominent and mention the others in `notes`.

**`package_qty`** and **`package_unit`** — the same value parsed, e.g. `640` and `"g"`.
Use `g`, `kg`, `mL`, `L`, `oz`, or `lb`. `null` if absent.

Do not confuse a printed package label with a scale display. They are different fields
and telling them apart is a large part of what this reading is for.

**`notes`** — free text, short. Use it for partial digit readings, glare, a second
visible label, a second scale, or anything that qualifies your answer. Empty string if
nothing to say.

### Rules

1. **Never guess a number.** If the display is not legible, say so. An `ambiguous` is
   worth more than a plausible invention.
2. **Read only what is in the picture.** Do not reason from the object to what it
   probably weighs. A bottle that looks like 375 mL is not evidence about the display.
3. **Report every tile you can see**, including `unreadable` ones.
4. **Output only the JSON lines.** No commentary before or after, no markdown code
   fences, no summary. One line per photograph.

---

## Blinding

**Readers are shown the photograph and nothing else.** They do not see the id, the typed
weight, the unit tick, the published value, the item name, or what the pipeline decided.

This is load-bearing. A reader told "the officer typed 0.8 and we published 800" is being
asked to confirm a number rather than read one, and will tend to confirm it — which would
make the check validate the pipeline because it was told what the pipeline said.

`make_contact_sheets.py` enforces this: a sheet carries a sequence number and nothing
else, and the sequence-to-id mapping is written to a separate manifest joined only after
readings are recorded.

**Check 3 is the exception.** It asks whether two labels name the same object, which
cannot be asked without naming the labels. There, blind the *verdict* the crosswalk
reached, not the label names.

## Known limits of readings made with this instrument

State these wherever a number produced by it is reported.

- **Not deterministic.** A re-run may differ. The instrument is fixed; the reader is not.
- **Agreement is not correctness.** Two readers of the same model family share failure
  modes — both will misread the same dim display the same way. Cross-model agreement is
  weaker-but-real evidence; only a human check is ground truth.
- **The decimal point is the weakest link and the one that matters most.** It is a few
  pixels, and Check 2 turns on it. If readers systematically miss decimals, agreement
  will be *high* while accuracy is *low* — the failure that looks most like success.
  Decimal recovery is therefore scored as its own metric, never folded into a headline
  agreement rate.
- **Contact sheets may induce anchoring** across tiles, which reading images singly would
  not. Untested as of v1.0.

## Changelog

| version | date | change |
| :-- | :-- | :-- |
| v1.0 | 2026-09-19 | first issue |
