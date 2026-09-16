"""Emit the raw-spelling map the NSU sense-check artifact annotates its panels with.

WHAT THIS ANSWERS. Every chart in the artifact is keyed on `harmonized_nsu_unit`, which is
a FOLD of one or more raw `pull_nsu_unit` spellings. The chart cannot say which spellings
were pooled to make it, and that is the first thing a reader wants when a panel looks odd:
`pieces or units` in one municipality may be `bilog`, in another `binilog`, and the two are
not the same object.

GRAIN. province x municipality x item x harmonized_nsu_unit -- the case, which is the grain
at which the fold is decided and the grain the artifact's panels are built from.

SOURCE. `master_nsu_rename.dta`, the crosswalk itself, rather than the weighings. A
spelling that was PRICED but never weighed still folds into the case and still shapes it
(#21 sec 5.3, A11), so it belongs in the list; reading the weighings would silently drop
those. The `source` column carries the distinction and it is kept.

OUTPUT  scratchpad/unit_sources.js   window.UNITSRC = {raw:[...], map:{key:[[i,src],...]}}
        where key is "province|municipality|item|harmonized_unit" and src is
        0 = seen in the market survey, 1 = price file only.

RUN
    python dofiles/90_diagnostics/build_unit_sources_js.py [--out <dir>]
"""

import argparse
import json
from pathlib import Path

import pandas as pd

DC = Path(__file__).resolve().parents[2]
IN_DTA = DC / "outputs" / "build" / "intermediate" / "master_nsu_rename.dta"

KEYS = ["pull_province", "pull_municipal_city", "pull_item", "harmonized_nsu_unit"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None,
                    help="directory to write unit_sources.js into")
    args = ap.parse_args()

    # convert_categoricals=False on principle: every column used here is a string, but a
    # labelled numeric read back as its label is the trap this project keeps hitting.
    d = pd.read_stata(IN_DTA, convert_categoricals=False)
    print(f"read {IN_DTA.name}: {len(d):,} crosswalk rows")

    need = KEYS + ["pull_nsu_unit", "source"]
    missing = [c for c in need if c not in d.columns]
    if missing:
        raise SystemExit(f"missing column(s): {missing}")

    d = d[need].copy()
    for c in need:
        d[c] = d[c].fillna("").astype(str).str.strip()
    d = d[(d.pull_nsu_unit != "") & (d.harmonized_nsu_unit != "")]

    # 1 = the price file alone knows this spelling; 0 = the market survey saw it too.
    d["src"] = (d.source == "Price Only").astype(int)

    # A spelling can appear twice in one case with different `source` values. Keep the
    # STRONGER claim -- if the market survey saw it at all, it is not price-only.
    d = (d.groupby(KEYS + ["pull_nsu_unit"], as_index=False)["src"].min())

    raw_vals = sorted(d.pull_nsu_unit.unique())
    raw_ix = {v: i for i, v in enumerate(raw_vals)}

    out_map: dict[str, list[list[int]]] = {}
    for key, g in d.groupby(KEYS, sort=True):
        k = "|".join(key)
        # sort so the market-survey spellings lead, then alphabetically: the list reads
        # as "what was weighed here, then what was only priced here".
        entries = sorted(
            ([raw_ix[r.pull_nsu_unit], int(r.src)] for r in g.itertuples()),
            key=lambda e: (e[1], raw_vals[e[0]]),
        )
        out_map[k] = entries

    payload = {"raw": raw_vals, "map": out_map}
    js = "window.UNITSRC=" + json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    assert "\x00" not in js
    assert js.startswith("window.UNITSRC={")

    out_dir = Path(args.out) if args.out else (DC / "outputs" / "tables")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "unit_sources.js"
    out_path.write_text(js, encoding="utf-8")

    folded = sum(1 for k, v in out_map.items()
                 if len(v) > 1 or raw_vals[v[0][0]] != k.rsplit("|", 1)[1])
    print(f"wrote {out_path}  ({len(js):,} bytes)")
    print(f"  cases: {len(out_map):,}   distinct raw spellings: {len(raw_vals):,}")
    print(f"  cases whose harmonized name is NOT just its own spelling: {folded:,}")
    multi = sum(1 for v in out_map.values() if len(v) > 1)
    print(f"  cases pooling two or more spellings: {multi:,}")


if __name__ == "__main__":
    main()
