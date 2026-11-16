# Project instructions

## Tell a subagent what already exists before it builds it

**Before dispatching any agent, list `scripts/` (and the relevant do-file directory) and
name in the prompt the tooling that already covers its task — including tooling that was
TRIED AND FAILED, and what it scored.** An agent cannot read the repository's history. It
will solve the problem in front of it, and it will solve it from scratch.

Three readers were dispatched in parallel to read scale displays. Each independently
built a seven-segment decoder — masking lit pixels, splitting digit boxes, sampling
segment windows — at roughly 300,000 tokens apiece. `scripts/sevenseg.py` already does
exactly that, and the README already recorded both that it fails and the specific method
that had not yet been tried. Nobody told them, because nobody looked.

The waste is the smaller half. The real cost is that **three independent decoders are
three different rules**, tuned by three agents against whatever each happened to be
looking at, none written down, all discarded when the agents exited. Any disagreement
between their readings would then have to be re-diagnosed from scratch, and the diagnosis
would be wrong, because the discrepancy would be in the code rather than in the data.
That is the same silent-duplication failure as the rule below and the one above, at the
scale of a whole method.

So every dispatch prompt states: what exists, what it scored, and whether the agent may
touch it. If an agent genuinely needs a capability the repository lacks, it reports that
back and the capability is added ONCE, to the existing file, by the session — not
reinvented per agent and thrown away.

## A subagent writes to its assigned paths and nowhere else

**Every subagent is told, in its own prompt, exactly which files it may create or modify:
its one output file, and a private scratch directory that belongs to it alone. Everything
else is read-only to it.** Name both paths explicitly. Do not rely on the agent inferring
a sensible boundary.

This is not hypothetical tidiness. Five readers were dispatched in parallel over one set
of contact sheets, all sharing the session scratchpad, and three of them independently
wrote helper scripts called `zoom_tile.py`, `zoom_digits.py` and `tile.py`. They
overwrote each other mid-run. One reader noticed its own script had been replaced with a
version importing a module that did not exist, and reported that "something outside this
session" was editing its files — a frightening conclusion that was wrong, and took real
work to disprove.

Two things make this worse than ordinary clutter:

* **It is silent.** An overwritten helper either still runs, and the reader trusts output
  from code it did not write, or it fails in a way that looks like the reader's own bug.
  Neither announces that a different process changed the file.
* **An agent that can reach outside its lane can reach anywhere.** The same loose
  boundary that lets a reader clobber a sibling's scratch file lets it clobber a
  published crosswalk or a ledger of hand-adjudicated verdicts. The blast radius is set
  by what the prompt forbids, not by what the task happens to need.

So each parallel agent gets `scratchpad/<its own tag>/`, is told never to overwrite a
file it did not create, and is told not to run `git` at all. Reading anything is fine;
writing is confined. Ask each agent to confirm in its report that it wrote nothing
outside its two permitted locations.

## Editing files: use Edit/Write. Never a heredoc.

**Use the Edit and Write tools for every file change. Not "by default" — always.** They
have no string-literal layer, so no escape can be silently eaten.

**A heredoc is not permitted to edit a file, even for a one-line substitution, even with
a raw string, even when it looks safe.** Every recurrence in this project started as a
substitution that looked safe. If a change feels too small to be worth an Edit call, that
is not a reason to reach for `sed` or `python - <<'PY'` — it is a reason to make the Edit
call, which costs the same.

Reading, measuring and running things with Bash/Python is fine and expected. The rule is
about **writing file content**.

This has bitten this project four times, always the same way. The shell heredoc is not the
problem — `python - <<'PY'` is quoted and expands nothing. **The problem is the Python
string literal inside it.** In a normal Python string:

| written | becomes | fails how |
| :-- | :-- | :-- |
| `'00_shared\00b_price.do'` | NUL + `b_price.do` | **silently** — a valid-but-wrong byte |
| `'C:\temp\xerox'` | tab, then a hex-escape error | loudly, if you are lucky |
| `'a\nb'` inside generated content | a real newline | silently — breaks the target's syntax |

`\0` and `\x` are the dangerous ones: they produce a wrong byte rather than a syntax error,
so the script runs, the file is written, and nothing looks wrong until much later.

**When Python genuinely is the right tool** — a measurement over a `.dta`, a bulk
transformation, anything reading a Box path — then:

1. **Every literal containing a backslash is a raw string.** `r'C:\Users\...'`, always.
   A Windows path in a non-raw literal is a bug even when it happens to work today.
2. **To emit a backslash into generated content, build it: `BS = chr(92)`.** Never a
   literal `\\` inside a heredoc — that is two escape layers arguing with each other.
3. **Assert before writing.** `assert '\x00' not in s` costs nothing and is what caught
   the last one before it reached disk. Add a length or anchor check too:
   `assert old in s` fails loudly where a silent no-op replace would not.

"It ran without error" does not mean the file is what you meant. Interpreters tolerate
corruption a diff would show instantly.

## Read the written record before running anything

**Before any diagnostic and before any implementation, read — in this order:**

1. the GitHub issue the work belongs to, **body and all comments**;
2. `dofiles/README.md`, for the run order and where a quantity is produced;
3. `docs/conversion_factor_methodology.md` and `docs/implicit_assumptions.md`.

Not after the first result looks odd. Before the first command.

This is not diligence for its own sake. Two analyses in one session were wrong because
they rested on a half-remembered premise instead of the written one:

| what happened | what the record already said |
| :-- | :-- |
| the #30 grams-per-peso measurement paired on `pull_price`, the market-survey price | Outcome 2 pairs at **(case × rung)** through `size_ord`, documented in `10_size_assignment.do`. `pull_price` exists only on the price-quantity branch, so the wrong pairing missed all 1,046 size-based pairs, cut the estimable base from 79 groups to 29, and reversed **both** conclusions — including "the ray screen does not work", which on the correct pairing is cleanly monotonic |
| a `KGMAX` figure was quoted from a diagnostic that recomputed the block rule | the pipeline publishes `w_block`; the diagnostic should read it |

The issue body usually already carries the counts and the grain. **Quote the numbers that
are written down rather than deriving fresh ones**, which risks answering a different
question and reporting it as if it were the same one. Where a derived number must
disagree with a recorded one, that disagreement is the finding — say so explicitly.

## Build objects in Stata. Python only where Stata cannot.

**Any object the pipeline reads — a `.dta`, a crosswalk, a CSV, a column — is produced in
Stata.** Python is for the things Stata genuinely cannot do:

* fuzzy string matching (`difflib.SequenceMatcher`, as in `01_build_crosswalk.py`),
* `.xlsx` reading and writing, including the review workbooks,
* unicode normalization.

Everything else belongs in a do-file. This is not a style preference — each language
boundary is a place where Stata's data model has to be re-interpreted, and that
re-interpretation fails silently:

| what happened | why |
| :-- | :-- |
| `unit == 1` matched nothing | a labelled numeric read back as the label string `"Kilograms (Kgs)"` |
| `wider`/`narrower` came out inverted | `.map()` on a Categorical returns a Categorical, whose `>` compares category ORDER |

Both ran without error. Neither can happen inside a do-file, where the variable is just
a variable.

**A diagnostic reads the quantity the pipeline computed. It never recomputes it.** If the
build discards something a diagnostic needs, the fix is to KEEP it, not to re-derive it.
The block reading was computed in `04_unit_snap.do`, used, and dropped, so two Python
diagnostics each carried their own copy of the rule — scraping `KGMAX` out of the do-file
to do it. Those copies guarded the *constant* and not the *branch structure*, so changing
`weight>=10` in STEP 3a would have left both silently computing a rule the pipeline no
longer used. One of them builds the review workbook whose verdicts are frozen into a
ledger, so a stale reading there becomes a permanent hand-adjudicated weight. The fix was
one word: add `w_block` to the `keep`.

The same rule applies to reading a build column that records a decision rather than the
rule that made it. `audit_weight_derived_folds.py` asks `nsu_fold_rule.py` for fold
membership and treats the built `cleaned_nsu_unit` only as a tripwire, because a register
whose purpose is catching staleness must not depend on something that can go stale.

**Do not add a new script where an existing one or a do-file will do.** The diagnostic
layer is already larger than the pipeline it validates.

## How the owner wants to work here

These were each stated by the owner or learned from a failure on this project.

* **Discuss before implementing.** State the plan and the reasoning, then wait for a
  go-ahead. Approval for one step is not approval for the follow-on steps it reveals. A bug
  found mid-task is reported with its proposed fix, not fixed in passing. Running a
  diagnostic to answer a question is fine; writing or changing pipeline code needs a
  check-in first.
* **Finish a task by committing and pushing it.** This is a solely owned repo
  (`Shineyang03/nsu-market-survey-cleaning`): add, commit and push the files the task
  touched, with no "confirming before I push" framing. Ask only when unrelated uncommitted
  files are also present.
* **Review material goes in a GitHub issue,** and the chat reply is the conclusion plus the
  issue number. A correction to a figure already stated in an issue is a new comment on that
  issue, not only a chat message.
* **Point at exactly what needs review.** Name the rows and the columns (about six). Never
  hand over a wide sheet and call it a review request.
* **Find N before building a review.** Count the decisions and measure what each one moves,
  then review the rule, not the instances, and state the stopping rule. Full method:
  `docs/adjudication_playbook.md`.
* **Every number comes from a script in `dofiles/`.** No throwaway code for anything whose
  number is cited. Give the script a docstring saying what question it answers. Claims that
  no build file produces go in `dofiles/90_diagnostics/verify_documented_claims.py`.
* **Bulk model judgement runs in escalating batches with blind human spot-checks.** Persist
  batch membership in a ledger so a still-running upstream job cannot reshuffle it. Never
  quote an accuracy figure that rests only on Claude's own readings; say how many
  independent readings are behind it.
* **Delegate only mechanical work to cheaper models** (inventories, environment surveys,
  repeated measurements). Say in one line what went to the agent. Judgement-heavy or
  load-bearing work stays in the session.
* **If the owner pushes back on a claim, re-measure** before conceding or defending.
* **A heredoc edit that gets caught is fixed without narration.**

## Facts that have already produced wrong findings

* **`pull_price` is the price file.** The market-survey `pull_price` is preloaded from
  `NSU_prices_from_Makayla.csv`, so the two are meant to be the same number and any gap is a
  defect to explain, not a difference in kind. Measured in September: on price-quantity
  cells only 76 of 510 price-file points have an identical `pull_price` in the same cell.
  The leading hypothesis (a vintage mismatch between the SurveyCTO preload and the delivered
  CSV) is unverified.
* **Which number a photograph yields** (owner rulings of 2026-10-02, recorded as A25 in
  `docs/implicit_assumptions.md`): a printed package quantity beats a scale display; on a
  label printing both mass and volume the grams win; on a label printing only a volume
  beside a legible scale reading the weighed grams win, for single-serve ice cream capped at
  250 mL; no reading may be negative or zero, and non-positive readings are withdrawn to
  missing, never made absolute. Approving a review row approves `photo_g` and `photo_unit`.
  Ice cream density is an assumption of 0.9 g/mL (observed 0.474 to 0.938 on seven packs).
* **GitHub's math renderer rejects `\operatorname`.** Use `\text`. Do not trust the markdown
  API as proof that an expression renders; check a real browser render for the red "macros
  are not allowed" box.

## Hooks that enforce rules here

The project's `.claude/` folder holds two hooks (they need `python` on the PATH and travel
with this Box folder):

* `hooks/block_shell_file_writes.py` (before any Bash call) blocks writing file content from
  the shell.
* `hooks/block_unstarted_work_claims.py` (when a turn ends) blocks a closing message that
  promises work nothing in the turn did, such as "starting the re-read now".

A hook is used where a text rule in this file had been broken repeatedly; its docstring has
the reasoning. When a rule here keeps being broken, make it a hook rather than adding text.

## Where things stand

`HANDOFF.md` holds the status, open decisions and next steps (status update of 2026-11-16 at
the top). The GitHub issues are the source of truth for open decisions.

## Everything else

See `~/.claude/CLAUDE.md` for the general working style, Stata conventions, and the
documentation and git policies that apply here.

Project-specific layout, run order and conventions live in `dofiles/README.md`; the
thresholds and what each one assumes live in `docs/implicit_assumptions.md`.
