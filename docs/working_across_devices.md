# Working from more than one device

The same person runs Claude Code sessions from two machines. This file is what keeps them
from diverging. **Git is the only thing that travels between machines**, plus whatever the
Box drive syncs. Nothing else does: not a session's context, not Claude's memory, not
uncommitted files, not installed tools.

## Machines

| | Windows (original) | Mac |
| :-- | :-- | :-- |
| repo path | `C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning` | `/Users/shineyang/nsu-market-survey-cleaning` (a git clone, **not** on Box) |
| Stata 19 | yes (`StataSE-64.exe`) | installed, **not on the PATH**: StataNow 19.5 SE at `/Applications/StataNow/StataSE.app/Contents/MacOS/stata-se`. Also Stata 18 MP (`/Applications/Stata`) and Stata 17 (expired licence, per `HANDOFF.md`). **Use 19.5.** Not yet run against this repo |
| Python + OpenCV | assumed | `python3` is 3.11.4 and `pip3` belongs to a different interpreter (anaconda 3.12), so install with `python3 -m pip`. **`cv2` is not installed yet**; `python3 -m pip install opencv-python-headless` should provide it. Not yet done |
| the photographs | Box, at the `photo_path` in the bridge | **not reachable** unless Box Drive is installed |

Checked on the Mac on 2026-09-29 by looking at `/Applications` and importing `cv2`; nothing
was run. The Windows column is from `HANDOFF.md` and the bridge file, not re-checked.
Update this table when a machine changes, and when the Mac's setup is actually proven.

### What that means for the work

- **The Mac needs setting up before it can run the pipeline.** Stata is there but nothing
  has been run through it. Before trusting a Mac build, run a step from `dofiles/` (the
  working directory must be `dofiles/`), then `verify_reproducibility.py` against a Windows
  build. Path separators in the do-files (`00_shared\00a_weighing_ids.do` in the README's
  commands) are Windows-style and may need forward slashes on the Mac.
  Until that is proven, treat Windows as the machine that builds the published outputs.
- **Anything that opens a photograph runs where Box is mounted.** `photo_id_bridge.csv`
  stores absolute Windows paths in `photo_path`. On the Mac every one of them is a dead
  path. Do not "fix" that by rewriting the committed bridge; it is an input, and both
  machines must read the same file. If the Mac needs photos, resolve the path at run time
  behind an explicit option or environment variable and leave the file alone.
- **Two builds from two machines are not interchangeable until proven so.**
  `verify_reproducibility.py` compares on values and is the test.

## The rules

1. **Start every session with `git fetch` and `git status`.** If `origin/main` is ahead,
   `git pull --ff-only` before touching anything. If `--ff-only` refuses, the two
   machines diverged: stop and read both histories rather than merging blind.
2. **End every session with the tree clean and pushed.** A commit that has not been pushed
   does not exist on the other machine. Finished work: commit and push. Unfinished work:
   commit it on a named branch (`wip/<topic>`) and push that branch, so the other machine
   can pick it up. `HANDOFF.md`'s "never commit half-finished work" applies to `main`, not
   to a pushed WIP branch.
3. **One machine at a time per branch.** Two machines editing `main` is how a rebase or a
   force-push gets contemplated, and both are forbidden here. If both must work, use
   separate branches and merge on one.
4. **Long jobs record where they run.** Note in the issue or the commit message which
   machine is running what (`rectify_display.py --all` is 3+ hours). Otherwise the other
   machine cannot tell a running job from a dead one, and cannot tell whose output
   directory it is looking at.
5. **Outputs of a live run are not committed.** Commit the finished result and its status
   file, not a snapshot of a run in progress. `36bc14e` committed 149 crops from a run
   that had not finished; do not repeat that.
6. **Nothing untracked is shared.** These are deliberately not in git and exist only on the
   machine that has them: `*.dta`, `inputs/PSPS NSU Market Survey Launch.dta`,
   `inputs/NSU_prices*.csv`, `reference/archive/*`, `outputs/temp/_verify_rebuild/`,
   `outputs/temp/_folds_port/`. A fresh clone can rebuild everything downstream of the
   crosswalk; the raw survey and the price file must be placed by hand (README, "Inputs").
7. **Line endings.** Windows and macOS disagree. If `git diff` shows a whole file changed
   after a pull, check for CRLF before committing anything. Do not commit a whole-file
   line-ending rewrite as if it were a change.

## What does not carry over, and where it goes instead

| lives only on one machine | put it here instead |
| :-- | :-- |
| a session's conversation and reasoning | the GitHub issue, body or comment. **The issues are the source of truth for open decisions.** |
| Claude's auto-memory | the repo: `CLAUDE.md` for rules, this file for workflow. Memory files are per-machine and per-project-path, so the Mac's memory and the Windows one will differ. |
| "what I was in the middle of" | `HANDOFF.md`, updated as the last step of a session |
| a finding | an issue comment, with the counts and the grain |
| local paths and tool locations | the machine table above |

`CLAUDE.md` is committed, so its rules load on both machines. Its instructions are the
same everywhere; do not make one machine's copy differ.

## Starting a session on either machine

Tell Claude, as the first message:

> Read `docs/working_across_devices.md`, then `git fetch && git status`, then `HANDOFF.md`.
> Tell me which machine this is, what is ahead of or behind `origin`, and what you
> cannot run here.

Claude should answer before doing any work: which machine, whether the branch is current,
and which steps are unavailable on it.

## Ending a session

1. Commit or branch-and-push everything. `git status` shows a clean tree.
2. Push. `git log origin/main..HEAD` is empty.
3. If a job is running, name the machine, the command, the output directory and the
   expected finish in the relevant issue.
4. If the state of the work changed, update `HANDOFF.md` (branch, counts, what is next).

## Known gap

`HANDOFF.md` was last updated 2026-09-16. It still names the Windows path and a branch that
no longer exists, and says nothing of the photograph checks, the display cropper or the
ledger overrides. Until it is refreshed it is wrong for a new session on either machine.
