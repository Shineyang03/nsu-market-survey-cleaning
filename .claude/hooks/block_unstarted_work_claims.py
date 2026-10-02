"""block_unstarted_work_claims.py -- a Stop hook that catches a promise with no work behind it.

THE FAILURE THIS CATCHES. A turn ends with a sentence like "starting the re-read now" or
"continuing through sheets 39-48", and nothing was run. The sentence reads like an action
and costs nothing to emit, so it discharges the feeling of having done the work without
doing any. It happened three times in one session, each time caught by the user rather
than by anything in the system.

WHY A HOOK AND NOT A LINE IN CLAUDE.md. The natural experiment is already in this
project's history. The rule against heredoc file writes is enforced by a hook and was
violated zero times in a long session -- blocked once, complied with immediately. The
rules that live only as text in CLAUDE.md -- read the record first, list scripts/ before
dispatching -- were violated repeatedly in that same session by the same reader of the
same file. Instructions are advice; a hook is a wall.

WHAT IT DOES. On Stop, it reads the transcript, finds the assistant's final message and
the tool calls made in that turn, and blocks if the message makes a forward-looking claim
about work while the turn ran nothing that could constitute that work.

WHAT IT DELIBERATELY ALLOWS, because a hook that cries wolf gets worked around:

  * Any turn that made a substantive tool call. Doing the work and then describing it is
    the behaviour being encouraged, not punished.
  * Offers and questions -- "shall I start?", "want me to run it?" -- which are not
    claims.
  * Plain future tense about a NEXT turn when it is explicitly conditional on the user,
    e.g. "say go and I'll start".
  * Reporting that something was NOT done, which is the honest alternative and must never
    be penalised.

It is a backstop for one specific, repeated, verifiable error, not a general style check.
"""

from __future__ import annotations

import json
import os
import re
import sys

# Phrases that assert work is underway or imminent *in this turn*. Deliberately narrow:
# each one has actually appeared in a false claim.
CLAIM = re.compile(
    r"\b("
    r"(?:i'?m |i am )?(?:now )?(?:starting|kicking off|launching|beginning|firing off)\b"
    r"|(?:starting|running|reading|continuing|proceeding|working)\s+(?:it|that|this|them|through|on|now)\b"
    r"|continuing\s+(?:through|with|to)\b"
    r"|i'?ll\s+(?:report|update|come back|let you know|tell you|have)\b[^.!?]*\b(?:when|once|after|as soon as)\b"
    r"|(?:dispatching|re-?dispatching|kicking)\s+(?:it|them|the)\b"
    r"|work(?:ing)?\s+through\s+(?:it|them|the rest|the remaining)\b"
    r")",
    re.IGNORECASE,
)

# A claim is excused when the sentence makes it conditional on the user acting.
CONDITIONAL = re.compile(
    r"\b(say\s+(?:go|the word)|if you|once you|when you|let me know|shall i|want me to|"
    r"should i|tell me|your call|unless you)\b",
    re.IGNORECASE,
)

# Tool calls that do not constitute doing the work.
INERT = {"TodoWrite", "Read", "Glob", "Grep", "ListAgents", "ToolSearch",
         "mcp__ccd_view__show_pane", "AskUserQuestion"}


def transcript_path(payload: dict) -> str | None:
    for k in ("transcript_path", "transcriptPath"):
        if payload.get(k):
            return payload[k]
    return None


def last_turn(path: str):
    """Return (final assistant text, tool names used since the last user message)."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = [json.loads(l) for l in fh if l.strip()]
    except Exception:
        return None, []

    # Walk backwards to the most recent genuine user message.
    start = 0
    for i in range(len(lines) - 1, -1, -1):
        e = lines[i]
        if e.get("type") == "user" and not e.get("isMeta"):
            content = e.get("message", {}).get("content")
            # A tool_result is delivered as a user entry; it does not start a new turn.
            if isinstance(content, str) or (
                isinstance(content, list)
                and not any(isinstance(c, dict) and c.get("type") == "tool_result"
                            for c in content)
            ):
                start = i + 1
                break

    text, tools = "", []
    for e in lines[start:]:
        if e.get("type") != "assistant":
            continue
        for c in e.get("message", {}).get("content", []) or []:
            if not isinstance(c, dict):
                continue
            if c.get("type") == "text":
                text = c.get("text", "")        # keep the LAST text block
            elif c.get("type") == "tool_use":
                tools.append(c.get("name", ""))
    return text, tools


def offending_sentences(text: str) -> list[str]:
    out = []
    # Only the closing stretch of the message matters; a mid-message "starting" that is
    # followed by results is fine.
    tail = text.strip().split("\n")
    tail = "\n".join(tail[-12:])
    for s in re.split(r"(?<=[.!?:])\s+|\n+", tail):
        s = s.strip(" -*#>|")
        if not s or CONDITIONAL.search(s):
            continue
        if CLAIM.search(s):
            out.append(s)
    return out


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0                      # never break the session on a malformed payload

    if payload.get("stop_hook_active"):
        return 0                      # we already fired once this turn

    path = transcript_path(payload)
    if not path or not os.path.exists(path):
        return 0

    text, tools = last_turn(path)
    if not text:
        return 0

    did_work = any(t and t not in INERT for t in tools)
    if did_work:
        return 0

    bad = offending_sentences(text)
    if not bad:
        return 0

    quoted = "\n".join(f"    {s}" for s in bad[:3])
    sys.stderr.write(
        "BLOCKED: this turn claims work is starting or continuing, but ran no tool that "
        "could do it.\n\n"
        f"{quoted}\n\n"
        "Text does not do work -- only a tool call does. Either:\n"
        "  * do the work NOW, in this turn, and describe it afterwards; or\n"
        "  * say plainly that it is not started, and why.\n\n"
        "Do not end a turn with a forward-looking claim about work. If you intend to do "
        "something, the tool call comes first and the sentence comes after.\n"
    )
    return 2                          # exit 2 = block, stderr goes back to the model


if __name__ == "__main__":
    raise SystemExit(main())
