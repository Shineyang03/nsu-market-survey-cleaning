# Archived outputs — produced by code that no longer runs

Nothing in the live pipeline writes these, and nothing reads them. They are kept because
they are the only surviving output of a rejected approach, and a rejected approach is
easier to argue against when you can see what it produced.

**These files are frozen. Do not cite a number from them as current.** A full rebuild
with `outputs/master_rename_build/` cleared does not recreate them — that is how they
were identified (`dofiles/90_diagnostics/verify_reproducibility.py` reported them as
MISSING).

| file | written by | dated |
|---|---|---|
| `nsu_rungs.dta` | `dofiles/archive/nsu_step_a_rungs.do` | 2026-08-25 |
| `stepA_empty_rungs.xlsx` | same | 2026-08-25 |
| `stepA_label_vs_tercile.xlsx` | same | 2026-08-25 |
| `stepA_nonmonotonic.xlsx` | same | 2026-08-25 |

## Why `nsu_step_a_rungs.do` was rejected

It was a shared "Step A" meant to serve both outcomes. `dofiles/archive/README.md` has
the full argument; the short version is two reasons, both still worth knowing:

1. **It set the number of groups from the weighing count** (`MIN3 = 6` / `MIN2 = 3`).
   Neither outcome uses the weighing count — Outcome 1 counts the distinct S/M/L labels
   the field recorded, Outcome 2 reads the price file's point structure. That ladder
   demoted 77 of the 553 cases that genuinely had all three sizes recorded.
2. **The shared-file premise is wrong.** The two deliverables slice the same weighings by
   different evidence and on different grains, so the same case can yield three sizes in
   Outcome 1 and one weight in Outcome 2.

It also still references `w_ref`, a column retired in issue #29, so it errors on its first
substantive line against any current input.

The live equivalents are the three `dofiles/10_reference_set/` steps.
