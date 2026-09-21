"""check_reshape_corrections.py -- do our published weights honour the reshape's
image-confirmed corrections?

WHY THIS EXISTS. `reshape_nsu_v2.do` -- the script that produces this project's raw
input -- contains a section headed "Corrections from pictures" which applies fixes
derived from SurveyCTO scale photographs. It reached the same conclusion our own Check 2
sweep did, that officers typed a kilogram display verbatim, from the same evidence.

Two efforts reading the same photographs, neither aware of the other. That is worth
checking in both directions:

  * a row corrected upstream and corrected AGAIN by us would be corrected twice;
  * a row corrected upstream and then MOVED by our snap is a correction we quietly
    discarded.

THE STRICT SUBSET ONLY. It extracts the 31 `_corr` calls, each of which carries a per-case
image citation naming the flagged size, the scale reading and the before/after value.
It deliberately ignores the ~114 rows in Section 2, which are corrected by a RULE
(`unit==grams & weight<10 -> x1000`) generalised from three spot-checked images. Those
are an inference from photographs, not a reading of 114 of them, and conflating the two
would overstate how much of the build has actually been checked against an image.

IT READS THE DO-FILE'S SOURCE, not its audit log. The log is written to a `tempfile` and
does not survive the run, and the do-file's input sits in a Cryptomator vault so it
cannot be re-run from here. The `_corr` calls are literal and self-documenting, which
makes the source the more reliable record in this case -- but it does mean this checks
what the file SAYS it does, not what a run produced.

WHAT AGREEMENT MEANS. The reshape writes its corrected value into `weight`, the raw
column our pipeline reads. Our published `corrected_weight` is that value after the
block reading, the snap and any manual correction. So they agree when the pipeline has
left the reshape's number alone, in grams.

USAGE
    python check_reshape_corrections.py
"""

from __future__ import annotations

import os
import re
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
IMGCHK = os.path.dirname(HERE)
PROJ = os.path.dirname(IMGCHK)
ROOT = os.path.dirname(PROJ)

RESHAPE = os.path.join(ROOT, "NSU Market Survey Launch", "data", "reshape_nsu_v2.do")
RAW = os.path.join(PROJ, "inputs", "PSPS NSU Market Survey Launch.dta")
PUB = os.path.join(PROJ, "outputs", "build", "intermediate", "nsu_weighings_cpi.dta")
OUT = os.path.join(IMGCHK, "outputs", "qc", "reshape_correction_check.csv")

# _corr "uuid:...." "obs_type" NEWVAL ///
CORR_RE = re.compile(
    r'^\s*_corr\s+"(uuid:[0-9a-f-]+)"\s+"(\w+)"\s+([0-9.]+)', re.MULTILINE)


def main() -> int:
    for p in (RESHAPE, RAW, PUB):
        if not os.path.exists(p):
            print(f"missing input: {p}", file=sys.stderr)
            return 2

    src = open(RESHAPE, encoding="utf-8", errors="replace").read()
    rows = [{"key": m.group(1), "obs_type": m.group(2),
             "reshape_says": float(m.group(3))} for m in CORR_RE.finditer(src)]
    c = pd.DataFrame(rows)
    print(f"image-confirmed corrections in reshape_nsu_v2.do : {len(c)}")
    print(f"distinct submissions                             : {c.key.nunique()}")
    if c.duplicated(["key", "obs_type"]).any():
        print("WARNING: the same (key, obs_type) is corrected twice in the do-file")
        print(c[c.duplicated(['key', 'obs_type'], keep=False)].to_string(index=False))

    raw = pd.read_stata(RAW)
    raw["obs_type"] = raw.obs_type.astype(str)
    raw = raw[["key", "obs_type", "weight", "unit", "pull_item",
               "pull_province", "pull_municipal_city", "pull_nsu_unit", "vendor_id"]]
    raw["unit"] = raw.unit.astype(str)
    raw = raw.rename(columns={"weight": "raw_weight", "unit": "raw_tick"})

    m = c.merge(raw, on=["key", "obs_type"], how="left", indicator=True)
    lost = int((m._merge == "left_only").sum())
    print(f"corrections whose row is absent from the raw file : {lost}")
    if lost:
        print(m[m._merge == "left_only"][["key", "obs_type", "reshape_says"]]
              .to_string(index=False))
    m = m[m._merge == "both"].drop(columns="_merge")

    # Did the correction survive into the raw file the pipeline reads?
    m["in_raw"] = (m.raw_weight - m.reshape_says).abs() / m.reshape_says < 0.001

    # …and into the published weight?
    pub = pd.read_stata(PUB)[["id", "corrected_weight", "corrected_unit",
                              "snap_rule", "pull_item"]]
    pub["corrected_unit"] = pub.corrected_unit.astype(str)
    pub["snap_rule"] = pub.snap_rule.astype(str)

    # id comes through the bridge, which is keyed on the same raw row
    br = pd.read_csv(os.path.join(IMGCHK, "outputs", "bridge", "photo_id_bridge.csv"))
    br = br[["id", "key", "obs_type"]]
    m = m.merge(br, on=["key", "obs_type"], how="left")
    m = m.merge(pub.drop(columns="pull_item"), on="id", how="left")

    m["published_matches"] = (
        (m.corrected_weight - m.reshape_says).abs() / m.reshape_says < 0.02)

    print()
    print("DID THE RESHAPE'S CORRECTED VALUE SURVIVE?")
    print(f"  present in the raw file we read ......... "
          f"{int(m.in_raw.sum())} / {len(m)}")
    got = m.corrected_weight.notna()
    print(f"  reached a published weighing ............ {int(got.sum())} / {len(m)}")
    print(f"  published value equals the reshape's .... "
          f"{int(m.published_matches.fillna(False).sum())} / {int(got.sum())}")

    bad = m[got & ~m.published_matches.fillna(False)]
    if len(bad):
        print()
        print("  WHERE THE PIPELINE MOVED AN IMAGE-CONFIRMED VALUE:")
        print(bad[["key", "obs_type", "pull_item", "raw_weight", "raw_tick",
                   "reshape_says", "corrected_weight", "snap_rule"]]
              .to_string(index=False))

    nr = m[~m.in_raw]
    if len(nr):
        print()
        print("  CORRECTIONS NOT PRESENT IN THE RAW FILE (applied but overwritten,")
        print("  or the do-file claims a value its own output does not carry):")
        print(nr[["key", "obs_type", "pull_item", "raw_weight", "reshape_says"]]
              .to_string(index=False))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    m.to_csv(OUT, index=False)
    print(f"\nwrote {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
