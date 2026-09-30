# Reading instrument `crop-v1.2`

**Version `crop-v1.2`, 2026-09-30.** `v1.1` added the blank-display rule; `v1.2` tightens
`not_visible` after readers were measured against a human and one was found asserting
"no display" on crops that plainly carried one. Readings made under `v1.0` and `v1.1`
remain valid — both changes narrow an answer that was previously loose rather than
redefining a settled one — but a `v1.0`/`v1.1` reader's `not_visible` rows are worth
re-reading, because that is the answer the tightening affects. The coding manual for
reading **rectified display
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

**A BLANK DISPLAY AND A MISSING DISPLAY ARE DIFFERENT ANSWERS.** Both take
`display_text: null`, but they are not the same observation:

| what you see | `display_legible` | `notes` |
| :-- | :-- | :-- |
| a display is in frame, powered or not, with no segments lit | `clear` | say "display present but blank" |
| no display in the crop at all — the cropper locked onto something else | `not_visible` | say what is there instead |

Record what is in the picture and stop there. **Do not infer why the display is blank, and
do not reason about where the recorded weight came from** — that question is answered
from the whole photograph under a different instrument, and answering it here would let
one reading contaminate the other. Two checks that lean on each other agree by
construction, which is worth nothing.

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
3. **`not_visible` should be rare, and you must earn it.** Every crop you are shown exists
   *because* feature matching located a Micromatic scale body in the photograph and cut
   the display out at a fixed offset from it. A display is therefore in frame by
   construction. The cropper does occasionally lock onto something that is not a scale, so
   `not_visible` is a real and correct answer — but it is an assertion that the evidence is
   absent, not an admission that you could not read it, and the two are constantly
   confused.

   Before writing `not_visible`, satisfy yourself that you can see what the crop contains
   INSTEAD of a display, and name it in `notes`. If you can make out a display bezel, a
   rounded rectangle, a `WEIGHT` legend, or a row of segment cells — even a completely
   unlit one — then a display is present and the answer is `clear` (blank) or `ambiguous`
   (defeated you), never `not_visible`.

   Rates observed across readers on the same material ranged from 0% to 6.9%. The high
   figure came from the one reader independently shown to be wrong on checked tiles,
   including a crop it called `not_visible` whose display in fact read `0.290`. If your
   own rate is heading past about 2%, you are recording "I could not read it" as "it was
   not there".

   That substitution is costly in a way an honest `ambiguous` is not. A weighing marked
   `not_visible` is dropped from the set of weighings that have a display reading at all,
   so it is never compared against the published value — and it disappears silently,
   counted as "no evidence existed" rather than as a check that failed. `ambiguous` keeps
   the weighing visible as unresolved, which is the truth.
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

**THEY ARE ALSO KEPT INDEPENDENT ON PURPOSE, AND THAT IS THE POINT OF SEPARATING THEM.**
The two instruments feed two different checks:

| check | question | evidence | instrument |
| :-- | :-- | :-- | :-- |
| Check 1 | was this item weighed, or was the number taken off its packaging? | whether an item sits on the platter; whether a package with a legible printed quantity is in frame | whole photograph, `PROMPT.md` |
| Check 2 | is the published weight right? | the display reading against the published value | display crop, this instrument |

A reader working under one instrument must not reason about the other's question. A blank
display is not evidence that a weight was copied from a label, and a legible label is not
evidence that a display reading is wrong: each is an observation, and turning one into an
argument about the other makes the two checks agree by construction.

The corroboration happens **afterwards**, once both readings exist and neither was allowed
to see the other. Where they agree, the agreement is worth something because it was not
arranged. Where they disagree — a package reading `26 g` on a weighing whose display reads
`0.290` — that disagreement is the finding, and it only survives because neither reader
was permitted to explain it away.
