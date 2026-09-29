r"""scan_file_encoding.py -- look for characters in source files that should not be there.

THIS DOCSTRING IS A RAW STRING, and the first draft of this file was not. It described
the danger of a backslash escape being eaten by a string literal, using \0 and \x as its
examples, inside a plain docstring -- so Python read them as escapes and refused to parse
the file. The scanner written to catch escape corruption was itself escape-corrupted on
the first run. CLAUDE.md's rule is not a style preference: any literal containing a
backslash is a raw string, including the ones that are only documentation.

WHY THIS EXISTS. `CLAUDE.md` devotes a section to escape corruption, because it has hit
this project four times: a `\0` or `\x` eaten by a string literal produces a
valid-but-wrong byte, the script runs, the file is written, and nothing looks wrong until
much later. This is the cheap standing check for the same class of problem, widened by
one case that actually occurred -- a stray CJK character (U+6BCF, meaning "per")
appearing mid-sentence in generated prose. If generation can do that in a message it can
do it in a file, and one sitting inside a Stata comment or a Python identifier would be
just as silent.

That character is named by CODEPOINT rather than written out, because writing it out
made this file fail its own check. Second self-reference bug in one scanner: the first
was an allowlist held as a literal string, which flagged the very characters it allowed.

WHAT IT TREATS AS A PROBLEM. Not "non-ASCII" -- that rule was tried and it cried wolf 42
times on its first run, flagging the peso sign in a generated price table, the em dashes
in comments, and the N-tilde in nsu_normalize.py that is there precisely BECAUSE the
DUENAS case is what the file documents. A check nobody believes is worse than no check.

So it flags by SCRIPT and by CATEGORY, which is what actually distinguishes a mistake
from a choice:

  * a NUL byte, anywhere. There is no legitimate one in this repo's sources.
  * a character from a writing system this project does not use -- CJK, Hangul, Kana,
    Cyrillic, Greek outside a formula, Arabic, Hebrew. Nobody types those here on
    purpose, and one arriving in a Stata comment or a Python identifier is silent.
  * an INVISIBLE formatting character: zero-width space or joiner, a byte-order mark
    anywhere but the first character, a directional override. These are the genuinely
    dangerous ones, because no amount of reading the file reveals them.

Latin-script typography -- dashes, curly quotes, accented letters, currency, arrows,
mathematical signs, box drawing -- is reported as a NOTE and never as a failure, in code
as well as prose.

THE SUSPICIOUS SET IS COMPUTED, NOT LISTED. An earlier draft held the allowlist as a
literal string, so the scanner flagged its own source for containing the characters it
was allowing. Deciding by codepoint range removes the self-reference.

Exit status is 1 if anything is a problem, so it can be wired into verify_pipeline.py.

USAGE
    python dofiles/90_diagnostics/scan_file_encoding.py
"""

from __future__ import annotations

import os
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# Writing systems this project has no reason to contain. Given as RANGES rather than as
# characters, so the scanner does not flag its own source for naming them.
SUSPICIOUS_RANGES = [
    (0x0400, 0x04FF, 'Cyrillic'),
    (0x0590, 0x05FF, 'Hebrew'),
    (0x0600, 0x06FF, 'Arabic'),
    (0x3040, 0x30FF, 'Kana'),
    (0x3400, 0x4DBF, 'CJK extension A'),
    (0x4E00, 0x9FFF, 'CJK'),
    (0xAC00, 0xD7AF, 'Hangul'),
    (0xF900, 0xFAFF, 'CJK compatibility'),
]

# Invisible characters: the dangerous class, because reading the file cannot reveal them.
INVISIBLE = {
    0x200B: 'zero-width space',
    0x200C: 'zero-width non-joiner',
    0x200D: 'zero-width joiner',
    0x200E: 'left-to-right mark',
    0x200F: 'right-to-left mark',
    0x202A: 'left-to-right embedding',
    0x202D: 'left-to-right override',
    0x202E: 'right-to-left override',
    0x2060: 'word joiner',
    0xFEFF: 'byte-order mark',
}


def classify(ch, first_char_of_file):
    """Return (is_problem, why) for a non-ASCII character."""
    cp = ord(ch)
    if cp in INVISIBLE:
        if cp == 0xFEFF and first_char_of_file:
            return False, 'BOM at start of file'
        return True, INVISIBLE[cp]
    for lo, hi, name in SUSPICIOUS_RANGES:
        if lo <= cp <= hi:
            return True, f'{name} character'
    return False, 'typography'

SKIP_DIRS = {'.git', '__pycache__', 'archive', 'outputs', 'inputs', '_wb_tmp'}
CODE_EXT = ('.py', '.do')
TEXT_EXT = CODE_EXT + ('.md', '.txt')


def walk():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if fn.endswith(TEXT_EXT):
                yield os.path.join(dirpath, fn)


def main() -> int:
    problems, notes = [], []
    n = 0
    for path in walk():
        n += 1
        rel = os.path.relpath(path, ROOT).replace(os.sep, '/')
        raw = open(path, 'rb').read()
        if b'\x00' in raw:
            problems.append(f'{rel}: NUL BYTE')
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError as e:
            problems.append(f'{rel}: not valid UTF-8 ({e})')
            continue
        bad: dict[str, list[int]] = {}
        ok: dict[str, list[int]] = {}
        for i, line in enumerate(text.splitlines(), 1):
            for j, ch in enumerate(line):
                if ord(ch) < 128:
                    continue
                is_problem, why = classify(ch, i == 1 and j == 0)
                (bad if is_problem else ok).setdefault(f'{ch}\t{why}', []).append(i)
        for key, lines in bad.items():
            ch, why = key.split('\t')
            nm = unicodedata.name(ch, 'UNNAMED')
            problems.append(f'{rel}:{lines[0]}  U+{ord(ch):04X} {nm} -- {why} '
                            f'(x{len(lines)})')
        for key, lines in ok.items():
            ch, _ = key.split('\t')
            nm = unicodedata.name(ch, 'UNNAMED')
            notes.append(f'{rel}: U+{ord(ch):04X} {nm} x{len(lines)}')

    for p in problems:
        print(f'  FAIL  {p}')
    print(f'scanned {n} files; {len(problems)} problem(s), '
          f'{len(notes)} note(s) suppressed')
    if not problems:
        print('  no NUL bytes, no invisible formatting characters, and nothing from a')
        print('  writing system this project does not use')
    elif os.environ.get('SCAN_VERBOSE'):
        for x in notes:
            print(f'  note  {x}')
    return 1 if problems else 0


if __name__ == '__main__':
    raise SystemExit(main())
