# Deliverables as they stood before the issue #36 harmonization

Frozen on 11 September 2026, immediately before the no-group review was applied. Kept so
the change can be argued about with the old numbers in view. **Do not cite a figure from
here as current** — the live deliverables are in `outputs/build/deliverables/`.

## What changed

The official translation crosswalk assigned a group to only 54 of its 210 labels. The
other 156 were marked `resolved_by = no-group` and had never been adjudicated; 91 of them
turned out to govern a published value. Applying the review folded 40 labels — 14 given a
translation group, 26 harmonized onto another spelling — and cut the published vocabulary
from 56 harmonized units to 53.

| deliverable | before | after |
|---|--:|--:|
| `nsu_reference_set` rows | 2,559 | 2,559 |
| distinct harmonized units | 56 | **53** |
| thin cells (`d_thin = 1`) | 518 | 518 |
| `outcome2_lookup` rows | 3,750 | 3,750 |
| `psps_grams` rows with a gram figure | 87,374 | **87,382** |
| total grams | 538,656,825 | +0.001% |

34 household rows moved: 8 newly converted, 21 with a changed gram figure, 5 relabelled
only. **No row lost its conversion.** `psps_grams_changed_rows.csv` lists all 34 with
their before and after `harmonized_nsu_unit`, `cf_h`, `grams_h` and `n_g_used`.

The full pre-change `psps_grams.dta`, `psps_converted_capped.dta` and
`psps_standard_units.dta` (80 MB between them) are not kept. They are recoverable by
reverting the harmonization commits and re-running the two masters.

## One proposal was applied, measured and rejected — `tama-tama nga putos`

Worth recording, because the case for it was strong and the measurement is the only
thing that settled it.

`tama-tama` is *just right / moderate*. On loaf bread it has 23 weighings at a median of
450 g, which is exactly the `medium packs` median (n = 352); large is 640 g and small
370 g. Both the reading and the weight said medium.

The stronger argument was coverage. Its 424 household rows span 57 municipality cells and
its 23 weighings cover 8 of them, so 375 rows were converting off a **borrowed** rung —
116 of them pooling all 23 weighings nationally. Folding raised same-cell coverage to 348
of 424 and moved 385 rows onto local weighings (`n_g_used` of 4, 2, 3, 6 instead of 16
and 23).

**It was applied and it cost 39 households their gram figure entirely** — SARA 15,
SAN ENRIQUE 9, BUGASONG 6, TOBIAS FORNIER 3, BATAD 3, and one each in BURUANGA, TIBIAO
and JANIUAY. Not a missing weighing, and not a fallback refusal: `fallback_refused.csv`
lists one loaf-bread row and it is a different unit. They fail at the **price-point
match** — the household's own price does not align with the price structure `medium
packs` has in that municipality, where the retired `tama-tama` case had points that did.

So the trade was a better conversion factor for 385 rows against no conversion factor for
39. **The project's call is that a borrowed weight beats no weight**, and the fold was
reverted. `tama-tama nga putos` remains its own harmonized unit.

A middle path exists and has not been built: fold, and extend the price-point match so a
household price outside the target's local structure falls back to the target's
provincial points rather than failing. That is a change to `28_match_and_convert.do` and
`30_fallback.do`, not to the harmonization tables.

## A second thing the change surfaced

The first build attempt stopped on a tripwire in `05_manual_corrections.do`, and it was
right to. Hand-adjudicated weight verdicts in `reference/reviewed/snap_verdicts.csv` are
keyed on a content key that contains `harmonized_nsu_unit`, so folding `pieces` into
`pieces or units` orphaned two of them — both TIGBAUAN drinks-at-restaurant anchors. The
key was reconciled and the verdicts left untouched; the ledger still holds 227 rows.

**Any future fold that touches an adjudicated cell will stop the build the same way.**
That is the intended behaviour, but it means a harmonization change carries a
ledger-reconciliation step, and the ledger must be edited rather than the tripwire
silenced.
