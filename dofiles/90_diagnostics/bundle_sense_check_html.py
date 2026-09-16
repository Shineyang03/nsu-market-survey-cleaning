"""Bundle the NSU sense-check page and its data into ONE self-contained .html file.

WHY. The published Artifact is private to its owner and loads `data.js` and
`unit_sources.js` as separate files. A single file with the data inlined opens from a
local path, an email attachment or any static host, with no server and no network, so it
can be handed to someone who has no access to the Artifact.

The inlining is a `<script src=...>` -> `<script>...</script>` substitution and nothing
else: the page's own code is untouched, so the bundle and the Artifact render identically.

INPUTS   a directory holding nsu_weights.html, data.js, unit_sources.js
OUTPUT   <indir>/nsu_weights_standalone.html

RUN
    python dofiles/90_diagnostics/bundle_sense_check_html.py --dir <dir> [--out <file>]
"""

import argparse
import re
from pathlib import Path

PAGE = "nsu_weights.html"
ASSETS = ["data.js", "unit_sources.js"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="directory holding the page and its .js")
    ap.add_argument("--out", default=None, help="output path (default: <dir>/nsu_weights_standalone.html)")
    args = ap.parse_args()

    d = Path(args.dir)
    html = (d / PAGE).read_text(encoding="utf-8")

    for name in ASSETS:
        src = (d / name).read_text(encoding="utf-8")
        # A data payload must never be able to close the script element early. This is the
        # one substitution that can go wrong silently, so it is checked rather than assumed.
        if re.search(r"</script", src, re.I):
            raise SystemExit(f"{name} contains a literal </script — refusing to inline")
        tag = f'<script src="{name}"></script>'
        if html.count(tag) != 1:
            raise SystemExit(f"expected exactly one {tag} in {PAGE}, found {html.count(tag)}")
        html = html.replace(tag, "<script>\n" + src + "\n</script>")

    # A standalone file is opened straight from disk, so it needs the document scaffolding
    # the Artifact host supplies. Charset first, or the peso sign and the em dashes break.
    if not html.lstrip().lower().startswith("<!doctype"):
        html = (
            "<!doctype html>\n<html lang=\"en\">\n<head>\n"
            "<meta charset=\"utf-8\">\n"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
            "</head>\n<body>\n" + html + "\n</body>\n</html>\n"
        )

    assert "\x00" not in html
    assert "window.LOOKUP" in html and "window.UNITSRC" in html
    assert 'src="data.js"' not in html and 'src="unit_sources.js"' not in html

    out = Path(args.out) if args.out else (d / "nsu_weights_standalone.html")
    out.write_text(html, encoding="utf-8")
    print(f"wrote {out}  ({len(html.encode('utf-8')):,} bytes)")


if __name__ == "__main__":
    main()
