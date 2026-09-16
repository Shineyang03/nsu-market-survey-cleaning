# reference/

Inputs that were decided by a person and must not be regenerated.

Everything here is **read by the build or frozen on purpose**. Nothing here is a copy of a
build output — if you are looking for the crosswalk, the fold map or a coverage tally, they
live in `outputs/tables/` and are rebuilt every run.

## What is here

| path | what it is | who reads it |
| :-- | :-- | :-- |
| `reviewed/snap_verdicts.csv` | hand-adjudicated weight verdicts, content-keyed | `00_shared/05_manual_corrections.do` §6 |
| `reviewed/*.xlsx` | the review workbooks those verdicts were entered in | nobody — kept as provenance |
| `archive/` | third-party data kept for comparison, with its own README | nobody in the build |

`reviewed/snap_verdicts.csv` is the one file here the pipeline depends on. It is
content-keyed rather than row-keyed, so a verdict survives the rows moving; the build fails
loudly if a verdict no longer matches anything, which is the point.

## The frozen crosswalk baselines were retired

There used to be copies here of `master_nsu_rename.csv`, `master_nsu_rename_prefilter.csv`,
`cases_in_price_not_in_MS_diagnosed.csv`, `price_only_coverage_summary.csv` and
`unit_fold_map.csv`, frozen as they stood before `01_build_crosswalk.py` was split apart
(issue #33), plus a `frozen_pre_port/` copy of an older vintage again. A
`verify_reproducibility.py --reference` mode byte-compared the live build against them.

**They were removed, and that mode with them.** The baseline had drifted six rows and 87
harmonized values behind the live crosswalk, and every one of those differences was
*intended* — the non-NSU label trim, and the harmonization work under #36. So the check
reported three failures on every run and a reader learned nothing from any of them. A
baseline that is always red is indistinguishable from no baseline, except that it costs
attention every time someone runs the script.

**What answers the question now.** `verify_reproducibility.py` still has its snapshot mode,
which compares a build against the *last* build rather than against a fixed past one:

```bash
python dofiles/90_diagnostics/verify_reproducibility.py --save   # before a change
python dofiles/90_diagnostics/verify_reproducibility.py          # after it
```

That is the question worth asking now. The split is long done; the live risk is a change
today moving an output nobody expected it to move. For the full raw-to-deliverable rebuild
there is also `90_diagnostics/test_full_rebuild.do`.

**The single confirmed copy of the crosswalk is `outputs/tables/master_nsu_rename.csv`**,
written by `01_build_crosswalk.py`, filtered by `02_drop_non_nsu_labels.py`, and read by
`03_clean_ms.do`. A documented copy with labelled variables and value labels is written by
`90_diagnostics/label_master_rename.do` to `outputs/tables/master_nsu_rename_labelled.dta`.

If you want a frozen baseline again, take it from a tagged commit rather than a second copy
of a file in the working tree — the copy is what went stale.

## Adding something here

Only if a person decided it and the build reads it. A generated file that happens to be
useful belongs in `outputs/`, where it is rebuilt and cannot silently disagree with the
thing it was copied from.
