"""Price-level gaps between raw spellings pooled into one harmonized case (#21 sec 5.3).

THE SITUATION. Harmonization folds several raw NSU spellings into one
`harmonized_nsu_unit`. Some of those spellings were weighed in the market survey and
some were only priced. #21 sec 1 decided that a spelling never weighed in the cell
contributes no weight moment, so it is excluded from group construction -- correct, since
it has no weights to contribute.

THE CONSEQUENCE THAT WAS NOT DECIDED. A PSPS household reporting the unweighed spelling
still needs a conversion factor, and is matched against a ladder built entirely from the
OTHER spelling's price points. Since

    CF_h = p_h * w_g / p_g

is linear in p_h/p_g, any PRICE-LEVEL difference between the two spellings is silently
converted into a SIZE difference that was never measured.

Worked example, ILOILO / GUIMBAL / carrot / harmonized `pieces or units':

    bilog     MS & Price    municipality median PHP 35     24 weighings, median 122.5 g
    binilog   Price Only    municipality median PHP 80     0 weighings

  A household reporting `binilog' and paying the typical PHP 80 receives
      80 * 122.5 / 35 = 280 g   -- heavier than any of the 24 carrots actually weighed
  where scoring it against its own spelling's point would give
      80 * 122.5 / 80 = 122.5 g

THE DECISION THIS SCRIPT SUPPORTS. Option (a) -- score every household against the
weighed spelling's points, consistent with every other case -- EXCEPT where the two
spellings' price levels differ by more than GAP_FLAG, which are flagged rather than
converted. This script produces that flag list and the sensitivity behind the cut.

WHY THE CUT IS NOT OBVIOUS, and belongs in docs/implicit_assumptions.md rather than
here: (a) and (b) are opposite extreme assumptions about the same unobserved quantity.
(a) says the whole price gap is size; (b) says none of it is. The data cannot adjudicate,
because the spelling has no weighings -- that is the definition of the population.

IT ALSO GIVES price_pool_weighed_vs_unweighed.csv A PRODUCER. That table was committed
with no script that writes it, the same orphan problem as #33. It is rebuilt here.

GRAIN. province x municipality x item x harmonized_nsu_unit -- WITHOUT corrected_unit,
which exists only on the MS side, so a price-only spelling has no dimension to split on.
65 of the 1,941 weighed cells span both g and mL; the coarser grain merges those.

RUN
    python dofiles/90_diagnostics/scope_spelling_price_gap.py
    python dofiles/90_diagnostics/scope_spelling_price_gap.py --gap 3

OUTPUTS  (outputs/tables/)
    price_pool_weighed_vs_unweighed.csv   one row per harmonized case that pools any
                                          priced spelling: how many spellings, how many
                                          weighed, how many not, MS weighing count
    issue21_spelling_price_gap.csv        the 273 mixed cases with both price levels,
                                          the ratio, and the flag at the chosen cut
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

_HERE = Path(__file__).resolve()
sys.path.insert(0, str(_HERE.parent.parent / "00_shared"))
from nsu_normalize import ng, ni, nz   # noqa: E402

BOX = str(_HERE.parents[3])
DC = str(_HERE.parents[2])
OUT = DC + r"\outputs\tables"

XW = OUT + r"\master_nsu_rename.csv"
PRICE = BOX + r"\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv"
MS = DC + r"\outputs\build\intermediate\nsu_weighings_cpi.dta"

KEY = ["province", "pull_municipal_city", "cons_name"]
RKEY = KEY + ["pull_nsu_unit"]
HKEY = KEY + ["harmonized_nsu_unit"]

# The cut at which a price-level gap is treated as "these are probably not the same
# object" and the case is flagged rather than converted. NOT a measured quantity --
# see A11 in docs/implicit_assumptions.md. The sensitivity table below is the evidence
# a reader needs to disagree with it.
GAP_FLAG = 2.0
GAP_GRID = [1.25, 1.5, 2.0, 3.0, 5.0]


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def load():
    xw = pd.read_csv(XW, encoding="utf-8-sig", dtype=str)
    pr = pd.read_csv(PRICE, dtype=str).rename(columns={"Unit_lbl": "pull_nsu_unit"})
    for c, f in [("province", ng), ("pull_municipal_city", ng),
                 ("cons_name", ni), ("pull_nsu_unit", nz)]:
        pr[c] = pr[c].map(f)
        xw[c] = xw[c].map(f)
    pr["Price"] = pd.to_numeric(pr.Price, errors="coerce")

    n_before = len(pr)
    pr = pr.merge(xw[RKEY + ["harmonized_nsu_unit", "source"]], on=RKEY, how="left")
    # Price rows on labels the crosswalk deliberately dropped (standard quantity,
    # ambiguous, free text) have no harmonized unit and are not NSUs. Ignore them,
    # but say how many, so a silent join failure cannot hide here.
    lost = pr[pr.harmonized_nsu_unit.isna()]
    print(f"price rows {n_before:,}  |  unmatched to the crosswalk (dropped labels): "
          f"{len(lost):,} ({lost.pull_nsu_unit.nunique()} labels)")
    pr = pr[pr.harmonized_nsu_unit.notna()].copy()

    ms = pd.read_stata(MS, convert_categoricals=False).rename(
        columns={"pull_province": "province", "pull_item": "cons_name"})
    for c, f in [("province", ng), ("pull_municipal_city", ng), ("cons_name", ni),
                 ("pull_nsu_unit", nz), ("harmonized_nsu_unit", nz)]:
        ms[c] = ms[c].map(f)
    ms["w"] = pd.to_numeric(ms.corrected_weight, errors="coerce")
    ms = ms[ms.w.notna()]
    print(f"MS weighings with a corrected weight: {len(ms):,}")
    return pr, ms


def main(gap_flag):
    pr, ms = load()

    # ---- the pool table (this is what price_pool_weighed_vs_unweighed.csv holds) ----
    h("THE POOL: how many priced spellings each harmonized case carries")
    spell = pr.groupby(HKEY + ["pull_nsu_unit", "source"]).Price.median().reset_index()
    nms = ms.groupby(HKEY).size().rename("n_ms_weighings")

    pool = spell.groupby(HKEY).agg(
        n_price_spellings=("pull_nsu_unit", "nunique"),
        n_weighed=("source", lambda s: int((s == "MS & Price").sum())),
        n_unweighed=("source", lambda s: int((s == "Price Only").sum())),
    ).join(nms).fillna({"n_ms_weighings": 0})
    pool["n_ms_weighings"] = pool.n_ms_weighings.astype(int)
    pool["kind"] = np.where(
        pool.n_unweighed.eq(0), "all spellings weighed",
        np.where(pool.n_weighed.eq(0), "no weighed spelling at all", "MIXED"))

    print(f"harmonized cases present in the price file: {len(pool):,}\n")
    print(pool.kind.value_counts().rename("cases").to_string())
    print("\n  'no weighed spelling at all' is #30's population (a province fallback"
          "\n  question), NOT this one. 'MIXED' is the #21 sec 5.3 population.")

    mixed = pool[pool.kind == "MIXED"]
    # Every mixed case must have MS weighings -- that is what "weighed spelling" means.
    # If this ever fails, `source' in the crosswalk has drifted from the MS file.
    assert (mixed.n_ms_weighings > 0).all(), \
        "a MIXED case carries no MS weighing: crosswalk `source' disagrees with the MS"
    print(f"\nMIXED cases: {len(mixed):,}, carrying {int(mixed.n_ms_weighings.sum()):,}"
          f" MS weighings and {int(mixed.n_unweighed.sum()):,} unweighed spellings."
          "\n  All of them have MS weighings -- asserted, not assumed.")

    pool.reset_index().sort_values(HKEY).to_csv(
        OUT + r"\price_pool_weighed_vs_unweighed.csv", index=False,
        encoding="utf-8-sig")

    # ---- the price gap ---------------------------------------------------------
    h("THE GAP: weighed spelling's price level vs unweighed spelling's")
    print("Representative level per side = median of that side's price points.")
    sub = spell[spell.set_index(HKEY).index.isin(mixed.index)]
    w = sub[sub.source == "MS & Price"].groupby(HKEY).Price.median().rename("p_weighed")
    u = sub[sub.source == "Price Only"].groupby(HKEY).Price.median().rename("p_unweighed")
    d = pd.concat([w, u], axis=1).dropna()
    d["ratio"] = d.p_unweighed / d.p_weighed
    d = d[np.isfinite(d.ratio)]
    print(f"\ncases comparable on price: {len(d):,} of {len(mixed):,}")
    print(d.ratio.describe(percentiles=[.1, .25, .5, .75, .9]).round(3).to_string())

    print("\nsensitivity -- how many cases a given cut would flag:")
    for t in GAP_GRID:
        n = int(((d.ratio >= t) | (d.ratio <= 1 / t)).sum())
        mark = "  <- GAP_FLAG" if abs(t - gap_flag) < 1e-9 else ""
        print(f"  beyond {t:>4}x : {n:>4}  ({100 * n / len(d):>4.1f}%)"
              f"  {int(mixed.loc[d.index[((d.ratio>=t)|(d.ratio<=1/t))]].n_ms_weighings.sum()):>5}"
              f" MS weighings{mark}")

    d["flag_unconvertible"] = ((d.ratio >= gap_flag) | (d.ratio <= 1 / gap_flag))
    d = d.join(mixed[["n_ms_weighings", "n_price_spellings", "n_unweighed"]])

    h(f"THE FLAG LIST at GAP_FLAG = {gap_flag}x")
    fl = d[d.flag_unconvertible]
    print(f"{len(fl)} cases flagged; the other {len(d) - len(fl)} convert under option"
          " (a), consistent with every other case.")
    print("\nworst 12 by ratio:")
    print(fl.reindex(fl.ratio.sort_values(ascending=False).index).head(12)
          .reset_index().to_string(index=False))

    d.reset_index().sort_values("ratio", ascending=False).to_csv(
        OUT + r"\issue21_spelling_price_gap.csv", index=False, encoding="utf-8-sig")
    print(f"\nwrote {OUT}\\price_pool_weighed_vs_unweighed.csv")
    print(f"wrote {OUT}\\issue21_spelling_price_gap.csv")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--gap", type=float, default=GAP_FLAG,
                    help=f"price-ratio cut beyond which a case is flagged "
                         f"(default {GAP_FLAG})")
    main(ap.parse_args().gap)
