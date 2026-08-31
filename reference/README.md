# Frozen reference outputs

These are the crosswalk build's outputs **as they stood before `01_build_crosswalk.py`
was split apart** (issue #33). They exist so that "the split changed no answer" is a
check that runs, not a claim someone made once.

Check them with:

```bash
python dofiles/90_diagnostics/verify_reproducibility.py --reference
```

Byte comparison is meaningful here — these are plain CSV with no embedded timestamp, so
an identical rebuild is identical bytes. (That is not true of the `.dta` and `.xlsx`
outputs, which carry a creation time; those are compared on values by the same script's
default mode.)

## Why the split happened

`01_build_crosswalk.py` produces `master_nsu_rename.csv`, the harmonization crosswalk
that `03_clean_ms.do` reads and every price-side diagnostic joins on. It **could not
run**: it loaded two pickles, `ms_keys.pkl` and `nsu_all.pkl`, that nothing in the repo
wrote and that no longer existed on disk. The crosswalk sitting in `outputs/` was the
only copy of itself, and no change to the fold rule could be applied and measured.

The two pickles turned out to be different problems:

- **`ms_keys.pkl`** held `(ng(province), raw municipality, ni(item), nz(raw label))`
  tuples from the raw launch data. Recovered by deriving them inline — 2,001 distinct
  tuples, matching the reference crosswalk's 2,001 MS-source rows exactly.
- **`nsu_all.pkl`** held corrected *weights*, which exist only after the Stata build. It
  was used by exactly one block — the fold map — so that block made the crosswalk build
  depend on its own downstream output. It moved to `90_diagnostics/fold_map.py`.

## What each file is

| file | produced by | compared? |
|---|---|---|
| `master_nsu_rename.csv` | `01` then `02 --apply` | yes |
| `master_nsu_rename_prefilter.csv` | `01` alone, before the non-NSU trim | yes, as `01`'s direct output |
| `master_nsu_rename.xlsx` | `01`/`02` | no — Excel embeds a timestamp |
| `cases_in_price_not_in_MS_diagnosed.csv` | `01` | yes |
| `price_only_coverage_summary.csv` | `01` | yes |
| `unit_fold_map.csv` | the old in-`01` fold-map block | **no — see below** |

## `unit_fold_map.csv` is NOT a comparison target

The frozen copy is wrong in two independent ways, and the rebuild corrects both. A
difference there is the point, not a regression — do not "restore" the old figures.

1. **It was built from the 27 July data.** Its `n` column sums to **11,259**, which is
   the row count of the pre-Aug11 `outputs/temp/nsu_data.dta`, not the 11,453 of the
   current `nsu_data_master.dta`. So it described a build predating both the non-NSU
   label trim and the `w_ref` retirement.
2. **Its `dimension` column never worked.** All 103 rows read `?`. The pickle held
   `corrected_unit` as a pandas *categorical* (`'g'`/`'mL'`), because that is
   `read_stata`'s default, while the lookup keyed on floats (`1.0`/`2.0`). Every lookup
   missed.

**The fold rule itself was proved bit-exact**, separately from those two input defects:
fed the same July input, read the same categorical way, the extracted
`00_shared/nsu_fold_rule.py` reproduces this frozen file byte for byte. So the rule
survived extraction unchanged; only its inputs were wrong.

## Regenerating the reference

Don't, unless you mean to move the baseline. If you do — because a fold-rule change is
*intended* to move the crosswalk — replace these files in the same commit as the rule
change, and say in the message what moved and why. A reference set quietly refreshed to
match a new result is worth nothing.
