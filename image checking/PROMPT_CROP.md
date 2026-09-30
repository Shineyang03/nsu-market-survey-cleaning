# Reading instrument `crop-v1.1`

**Version `crop-v1.1`, 2026-09-29.** Adds the blank-display rule below; `crop-v1.0`
readings remain valid, since the change only splits an answer that instrument left
undefined. The coding manual for reading **rectified display
crops** — the output of `scripts/rectify_display.py`, which cuts the Micromatic WEIGHT
display out of a market photograph and straightens it.

`PROMPT.md` (`v1.0`) remains the instrument for **whole photographs** and is unchanged.
This is a separate instrument, not a version bump, because it asks a different question
of a different image. Readings made under the two are not interchangeable and every
reading records which produced it.

---

## Why a separate instrument was needed

`v1.0` was tried on a crop sheet first, and it does not fit. A crop shows the display and
nothing else — by design. So four of its fields cannot be answered from one:

| field | on a whole photograph | on a crop |
| :-- | :-- | :-- |
| `display_text`, `display_legible` | works | works |
| `photo_type` | works | no category fits; the item, the stall and the packaging are all cropped away |
| `item_on_scale` | works | unanswerable — the platter is not in frame |
| `package_text` / `package_qty` / `package_unit` | works | unanswerable — the packaging is not in frame |

**`item_on_scale` is the dangerous one.** A reader shown a crop with no visible item
would reasonably answer `false`, recording "nothing was on the scale" for a weighing that
certainly had something on it. Asked across thousands of crops that is a silent,
systematic corruption, and it would look like data rather than an artefact of
presentation.

So this instrument asks only what a crop can answer. What the crop cannot answer is not
lost: it is answered from the whole photograph, by `PROMPT.md`, for the photographs that
need it.

---

## The prompt

Everything between the rules below is passed verbatim to a reader. Do not paraphrase it.

---

You are reading crops of electronic scale displays, photographed by field officers during
a market survey in Western Visayas, Philippines. Each crop has been cut and straightened
so the display fills the frame. You will see the display and very little else.

You will be shown a **contact sheet**: a grid of crops, each with a white-on-black label
in its top-left corner reading `#0001`, `#0002`, and so on.

**Report one line per crop, using the label printed on that tile.** Never report a grid
position. If a tile is blank or its label is unreadable, skip it — do not guess which
number it should have been.

### What to record

For each crop, output exactly one JSON object on its own line, with these keys:

```json
{"label":"0007","display_text":"0.155","display_legible":"clear","display_unit_shown":"none_shown","notes":""}
```

**`label`** — the four digits from the tile's corner, as a string, without the `#`.

**`display_text`** — **the characters shown on the display, exactly as displayed.** This
is the single most important field.

- Copy what you see, character for character: `"0.155"`, `"1085"`, `"0.800"`, `"1.22"`.
- **Keep the decimal point and every leading and trailing zero.** `0.800` is not `0.8`
  and is not `800`. Telling those apart is the entire purpose of this reading.
- Do not convert units. Do not tidy the number.
- If the display is off, blank, or no display is present, use `null`.
- If you can read some digits but not all, use `null` here and put what you could see in
  `notes`.

**A BLANK DISPLAY AND A MISSING DISPLAY ARE DIFFERENT ANSWERS, and the difference
matters.** Both take `display_text: null`, but they are not the same finding:

| what you see | `display_legible` | `notes` |
| :-- | :-- | :-- |
| a display is in frame, powered or not, with no segments lit | `clear` | say "display present but blank" |
| no display in the crop at all — the cropper locked onto something else | `not_visible` | say what is there instead |

A blank display says the scale was not showing a weight when the photograph was taken,
which is evidence the recorded number came from somewhere else — usually a package label.
A missing display says only that the cropper failed, and carries no information about the
weighing at all. Recording one as the other destroys that distinction.

**Read the WEIGHT row only.** The crop is cut to it, and the word `WEIGHT` is usually
printed at the right-hand edge. If a second row is visible at the top or bottom of the
frame, ignore it.

**Unlit segments still glow.** These displays show a faint dark-red `8.8.8.8.8` behind
whatever is lit. A dim full-eights row is **blank**, not eights. Ghosting is the main
reason a crop is hard, and `ambiguous` is the right answer when it defeats you.

**`display_legible`** — `clear`, `probable`, `ambiguous`, or `not_visible`.

Use `probable` when you are fairly confident but glare, ghosting or blur leave real
doubt. Use `ambiguous` when you cannot settle it. **`ambiguous` is a correct and useful
answer.** A wrong number is far worse than an admission that the display could not be
read.

**`display_unit_shown`** — `kg`, `g`, `none_shown`, or `indeterminate`. Most of these
displays print no unit at all; `none_shown` is common and correct.

**`notes`** — free text, short. Partial digit readings, glare, an obstruction across the
display, or a crop that does not appear to contain a display at all. Empty string if
there is nothing to say.

### Rules

1. **Never guess a number.** If the display is not legible, say so.
2. **Read only what is in the picture.** You cannot see the object being weighed and
   must not reason about what it might weigh. There is no context to use, deliberately.
3. **Some crops contain no display.** The cropper occasionally locks onto something that
   is not a scale. Report `display_text: null`, `display_legible: "not_visible"`, and say
   so in `notes`. That is a correct reading, not a failure.
4. **Report every tile you can see.**
5. **Output only the JSON lines.** No commentary before or after, no markdown fences, no
   summary. One line per crop.

---

## What this instrument does NOT ask, and where those answers come from

`photo_type`, `item_on_scale`, `package_text`, `package_qty`, `package_unit` are absent
because a crop cannot support them. They are answered under `PROMPT.md` from the whole
photograph, for the photographs where they matter — chiefly the ones with no display,
where the recorded number came off a package label and the label is the evidence.

A crop reading and a photograph reading of the same weighing are complementary, not
duplicates. Neither supersedes the other.
