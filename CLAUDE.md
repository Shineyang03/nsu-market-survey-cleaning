# Project instructions

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

## Everything else

See `~/.claude/CLAUDE.md` for the general working style, Stata conventions, and the
documentation and git policies that apply here.

Project-specific layout, run order and conventions live in `dofiles/README.md`; the
thresholds and what each one assumes live in `docs/implicit_assumptions.md`.
