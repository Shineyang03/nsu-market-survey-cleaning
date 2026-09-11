r"""PreToolUse hook: refuse Bash commands that write file content.

WHY. CLAUDE.md requires every file change to go through the Edit/Write tools, because a
shell heredoc wrapping a Python string literal silently eats escapes -- `\0' becomes a
NUL byte and `\x' a bad hex escape, so the script runs, the file is written, and nothing
looks wrong until much later. That rule has been broken five times, each time on a change
that "looked safe". Judgement is not the control; this is.

WHAT IS BLOCKED. A command that both opens a heredoc and writes a file, plus the
in-place editors that do the same thing without one (`sed -i', `tee', `Set-Content',
`Out-File', `Add-Content').

WHAT IS NOT BLOCKED. Reading and measuring, which CLAUDE.md explicitly allows: heredocs
that only read, `grep', `python -c' that prints, redirects to /dev/null, and anything
writing under a temp or scratchpad directory, where throwaway measurement output belongs.

Exit 0 = allow, exit 2 = block and show the message to Claude.
"""
import json
import re
import sys

# Opening a heredoc of any flavour: <<EOF, <<'PY', <<"X", <<-EOF
HEREDOC = re.compile(r"<<-?\s*['\"]?[A-Za-z_][A-Za-z0-9_]*['\"]?")

# Writing a file from inside a script
PY_WRITE = re.compile(
    r"""open\s*\([^)]*['"][waxr]?\+?[waxr]\+?['"]"""      # open(path, 'w') / 'a' / 'r+'
    r"""|\.write_text\s*\("""
    r"""|\.write_bytes\s*\("""
    r"""|\.to_csv\s*\("""
    r"""|\.to_excel\s*\("""
    r"""|shutil\.(copy|move|copy2|copyfile)\s*\("""
    r"""|os\.(replace|rename|remove|unlink)\s*\("""
)

# Shell-level writers that need no heredoc at all
SHELL_WRITE = re.compile(
    r"""(^|\s|;|\||&)sed\s+(-[a-zA-Z]*\s+)*-[a-zA-Z]*i"""   # sed -i, sed -n -i, sed -Ei
    r"""|(^|\s|;|\||&)tee\s"""
    r"""|Set-Content|Add-Content|Out-File"""
    r"""|(^|\s)perl\s+(-[a-zA-Z]*\s+)*-[a-zA-Z]*i"""
)

# A redirect that actually lands in a file. `2>&1', `>/dev/null' and `>&2' are not writes.
REDIRECT = re.compile(r"(?<![0-9&])>>?\s*(?!&|/dev/null|/dev/stderr|/dev/stdout)\S")

# Paths where throwaway measurement output is expected and allowed
TEMP_HINT = re.compile(r"scratchpad|[/\\][Tt]emp[/\\]|AppData[/\\]Local[/\\]Temp|/tmp/",
                       re.IGNORECASE)

MESSAGE = (
    "BLOCKED by .claude/hooks/block_shell_file_writes.py.\n\n"
    "This command writes file content from the shell. CLAUDE.md requires the Edit or "
    "Write tool for every file change -- not 'by default', always -- because the Python "
    "string literal inside a heredoc eats escapes silently.\n\n"
    "Use Edit (for a substitution, even a one-line one, even eight identical ones) or "
    "Write (for a whole file). If the change is a loop over many substitutions, that is "
    "still a file edit: make the Edit calls.\n\n"
    "Reading and measuring with Bash stays fine -- this only fires on writes."
)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)                       # never block on a malformed payload
    if payload.get("tool_name") != "Bash":
        sys.exit(0)
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    if not cmd:
        sys.exit(0)

    # writing into a scratch/temp location is measurement output, not a project edit
    if TEMP_HINT.search(cmd):
        sys.exit(0)

    heredoc = bool(HEREDOC.search(cmd))
    writes = bool(PY_WRITE.search(cmd)) or (heredoc and bool(REDIRECT.search(cmd)))

    if SHELL_WRITE.search(cmd) or (heredoc and writes) or (writes and not heredoc
                                                           and "python" in cmd):
        print(MESSAGE, file=sys.stderr)
        sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    main()
