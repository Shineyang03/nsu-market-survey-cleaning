# Deliverables as they stood before the issue #36 harmonization

Frozen on 11 September 2026, immediately before the no-group review was applied. Kept so
the change can be argued about with the old numbers in view. **Do not cite a figure from
here as current** — the live deliverables are in `outputs/build/deliverables/`.

## What changed, and why these files exist

The official translation crosswalk assigned a group to only 54 of its 210 labels. The
other 156 were marked `resolved_by = no-group` and had never been adjudicated; 91 of them
turned out to govern a published value. Applying the review folded 142 crosswalk rows and
cut the harmonized vocabulary from 108 labels to 83.

| deliverable | before | after |
|---|--:|--:|
| `nsu_reference_set` rows | 2,559 | 2,554 |
| distinct harmonized units | 56 | 52 |
| thin cells (`d_thin = 1`) | 518 | 514 |
| `outcome2_lookup` rows | 3,750 | 3,743 |
| `psps_grams` rows with a gram figure | 87,374 | 87,343 |
| total grams | 538,656,825 | 538,344,773 (−0.058%) |

## `psps_grams_changed_rows.csv`

Every household row the change moved — 506 of 87,959 — with its before and after
`harmonized_nsu_unit`, `cf_h`, `grams_h` and `n_g_used`:

| outcome | rows |
|---|--:|
| grams changed | 381 |
| relabelled only | 78 |
| lost conversion | 39 |
| newly converted | 8 |

This file exists so the full pre-change `psps_grams.dta`, `psps_converted_capped.dta` and
`psps_standard_units.dta` (80 MB between them) did not have to be kept. They are
recoverable by reverting the harmonization commit and re-running the two masters.

## The 39 rows that lost their conversion — read this before judging the change

All 39 are loaf bread, `tama-tama nga putos`, now harmonized to `medium packs`, spread
over eight municipalities (SARA 15, SAN ENRIQUE 9, BUGASONG 6, TOBIAS FORNIER 3,
BATAD 3, BURUANGA 1, TIBIAO 1, JANIUAY 1).

They did not fail for lack of a weighing, and the fallback ladder did not refuse them —
`fallback_refused.csv` lists one loaf-bread row and it is a different unit. They fail at
the **price-point match**: the household's own price does not align with the price
structure `medium packs` has in that municipality, where the retired `tama-tama nga
putos` case had points that did.

The trade the fold makes, on the 424 rows carrying that label:

* **before** — all 424 converted, but mostly off borrowed rungs. `n_g_used` was 16 for
  210 rows and 23 for 116, i.e. a provincial or national pool rather than the
  household's own cell.
* **after** — 385 convert off *local* weighings (`n_g_used` of 4, 2, 3, 6), and 39 do
  not convert at all.

So the change buys materially better conversion factors for 385 rows at the cost of 39.
Whether that is the right trade is a judgement about which error matters more — a
borrowed weight, or no weight — and it is recorded here rather than settled.
