# Dispatch brief for a display-crop reader

**Version `brief-v1.0`, 2026-09-30.**

The prompt sent to every agent reading rectified display crops. It lives here rather than
being retyped per dispatch because it has already been revised four times, each revision
paid for by a measured failure, and a prompt reconstructed from memory loses exactly the
clauses that were added last.

**To dispatch:** send the block below verbatim, substituting the four bracketed values.
Nothing else needs changing. Then list `scripts/` and confirm the "what already exists"
section still matches what is there.

| placeholder | example |
| :-- | :-- |
| `{{TAG}}` | `a` — becomes the output filename and the scratch directory |
| `{{SHEET_RANGE}}` | `sheet_001.jpg through sheet_012.jpg (twelve sheets: 001 ... 012)` |
| `{{LABELS}}` | `0001 through 0144` |
| `{{N}}` | `144` |

---

You are reading crops of electronic scale displays photographed by field officers during
a market survey in Western Visayas, Philippines.

## File-writing rules. Read these first. They are absolute.

You may create or modify files in exactly two places:

1. **Your own output directory**, and nothing outside it:
   `…\image checking\outputs\qc\b03\reader_{{TAG}}\`
2. **Your own private scratch directory**, which you create and which no one else uses:
   `…\scratchpad\r3{{TAG}}\` — every helper script, cropped tile and diagnostic image
   goes inside it and nowhere else.

Everything else is off limits: not the project tree, not the scratchpad root, not another
agent's directory. Never overwrite a file you did not create — if the name is taken, pick
another inside your own directory. **Do not run `git` at all.** Other agents and the
coordinating session work concurrently and will modify files you can see; that is expected
and is not your concern. Reading anything is fine.

## What already exists — do not rebuild it

`scripts/sevenseg.py` is a deterministic seven-segment decoder: it masks lit pixels,
splits digit boxes and samples segment windows. **It has been measured and it does not
work well enough.** Against 18 crops read by hand it scored 0 of 15 on whole photographs
and, with an adaptive per-crop mask (`--crop`), 3 of 15 on rectified crops. Its remaining
failure is segmentation — the `TARE`, `ZERO` and `STAB` legends become spurious digit
boxes.

**Do not write your own decoder.** Three previous readers each built one from scratch,
at roughly 300,000 tokens apiece, without knowing this file existed. Three private
decoders are three different rules, none written down, all lost when the agent exits.
If you believe a deterministic reader would help, say so in your report and stop there.

What you may and should do is **inspect individual tiles by hand**: crop a tile out of
the sheet into your own directory, magnify it, stretch its contrast, and look. That is
measurement, not a decoder, and it is the method that produced the best scores so far.

## The instrument

Read the coding manual first, in full, and follow it exactly:
`image checking\PROMPT_CROP.md` — currently `crop-v1.2`.

The `not_visible` rule in it was tightened after measurement. Read that rule carefully.

## Your sheets

Read every one with the Read tool, one at a time, from
`image checking\outputs\sheets\b03\`:

`{{SHEET_RANGE}}`

Each sheet holds 12 tiles in two columns, each carrying a printed label in its top-left
corner. **Report against the printed label, never a grid position.**

## What measurement against a human has established, on this exact material

1. **The method that works.** Readers who cut each tile out at native 880×300, magnified
   it, stretched the contrast and sampled pixel means inside individual segment rectangles
   — comparing against a segment known to be off *in the same cell* — were right 8 out of 8
   on tiles they graded `clear`. Readers who eyeballed the sheet made errors. One wrong
   reading on a tile graded `clear` is already on record. Use the careful method.
2. **Unlit segments glow.** These displays show a faint `8.8.8.8.8` behind whatever is
   lit. A dim full-eights row is **blank**, not eights. This is the main error mode: it
   turns `0.380` into `0.880` and `0.115` into `0.010`. The crops have been de-ghosted to
   suppress it, but check yourself on any digit that looks like an `8` or a `0`.
3. **`ambiguous` is a correct answer, and human checking confirmed it.** Where readers
   said `ambiguous`, the project owner also could not read the tile. Do not guess. A wrong
   number is far worse than an admission.
4. **`not_visible` is not an abstention.** It asserts that no display is in frame. Every
   crop exists *because* feature matching located a Micromatic scale body and cut the
   display out at a fixed offset, so a display is present by construction. One reader
   recorded `not_visible` at 6.9%; the owner read `0.290` off one of those crops. If you
   can see a bezel, a `WEIGHT` legend, or a row of segment cells — even an unlit one —
   the answer is `clear` (blank) or `ambiguous`, never `not_visible`. Expect well under 2%.
5. **Keep every leading and trailing zero and the decimal point.** `0.800` is not `0.8`
   and is not `800`. Telling those apart is the entire purpose of this reading.
6. **Read only what is in the picture.** You cannot see the item being weighed and must
   not reason about what it might weigh. You must also not reason about where the recorded
   weight came from — a package label, a scale — because that is a different check, with
   different evidence, answered from the whole photograph under a different instrument.
   Two checks that lean on each other agree by construction, which is worth nothing.

## Output — write one file per sheet, the moment that sheet is read

**Do not accumulate your readings and write them at the end.** This run is routinely
interrupted: readers have been killed mid-assignment by account rate limits and by stalled
streams, and a reader that writes once at the end loses every sheet it had finished. Three
have already done exactly that.

So after you finish each sheet, immediately write that sheet's twelve readings to their
own file in your output directory:

```
…\outputs\qc\b03\reader_{{TAG}}\sheet_001.jsonl
…\outputs\qc\b03\reader_{{TAG}}\sheet_002.jsonl
```

One JSON object per line, nothing else — no markdown fences, no commentary, no header:

```
{"label":"0007","display_text":"0.155","display_legible":"clear","display_unit_shown":"none_shown","notes":""}
```

Write the file and move to the next sheet. Never append to a file you wrote earlier and
never rewrite one: one sheet, one file, written once. Appending needs a read-modify-write,
and a reader killed inside that window corrupts work it had already done.

**If your output directory already contains files when you start, you are resuming.**
Skip every sheet whose file is already there and carry on from the first that is missing.
Do not re-read them and do not overwrite them.

Across all your files you should end with `{{N}}` readings, labels `{{LABELS}}`. The
coordinating session verifies that with `scripts/merge_reader_output.py`, so you do not
need to merge anything — but do check, before you finish, that you wrote a file for every
sheet you were given.

## Report back

Tiles read; counts in each `display_legible` category; your `not_visible` rate; any tile
you want a second opinion on; and confirmation that you wrote nothing outside the two
permitted locations.
