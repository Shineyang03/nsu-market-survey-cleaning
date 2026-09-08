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

## Everything else

See `~/.claude/CLAUDE.md` for the general working style, Stata conventions, and the
documentation and git policies that apply here.

Project-specific layout, run order and conventions live in `dofiles/README.md`; the
thresholds and what each one assumes live in `docs/implicit_assumptions.md`.
