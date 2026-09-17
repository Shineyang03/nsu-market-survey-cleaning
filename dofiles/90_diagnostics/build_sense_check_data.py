"""Build data.js, the payload behind the Outcome 2 conversion-factor sense-check page.

WHY A GENERATOR. The first version of this payload was produced by hand and could not be
rebuilt, so it silently went stale: it still described the build as it stood before
05_manual_corrections.do section 1c merged the dual-dimension cells. A figure nobody can
regenerate is a figure nobody can trust.

WHAT ONE ROW IS. One published price point: province x municipality x item x harmonized
unit x dimension x rung. The month dimension is DROPPED -- Branch P rows are restated into
each PSPS interview month, so one point appears up to twelve times in the lookup with the
same weight and a different `psps_month`. The page is about weights, and w_g does not vary
by month, so the rows are deduplicated on what the page shows.

THREE INPUTS, and the last two are the point of this file:

  outcome2_lookup.dta             the rows themselves
  case_price_points.dta           what the price file CALLED each point. The lookup keeps
                                  `conv_rank` (an ordinal) and, on the size-based branch,
                                  nothing else -- so a rung reads "rung 2 of 3" with no
                                  way back to mp50 or `province median`. The has_* flags
                                  here carry the original labels, and a point can hold
                                  SEVERAL of them once the PHP 20 merge has run.
  outcome2_lookup_heteroblind.dta the conversion factor with within-NSU heterogeneity
                                  removed entirely -- one factor per case, whatever the
                                  household paid. Shown beside the rungs so the cost of
                                  the price/size matching is visible per case rather than
                                  only in aggregate.

OUTPUT  outputs/tables/data.js    window.LOOKUP = {dict, n, col, blind}

RUN
    python dofiles/90_diagnostics/build_sense_check_data.py [--out <dir>]
"""

import argparse
import json
from pathlib import Path

import pandas as pd

DC = Path(__file__).resolve().parents[2]
DELIV = DC / "outputs" / "build" / "deliverables"
INTER = DC / "outputs" / "build" / "intermediate"

CASE = ["pull_province", "pull_municipal_city", "pull_item", "harmonized_nsu_unit"]

DIM = {1: "g", 2: "mL"}
BRANCH = {1: "conventional", 2: "price-quantity", 3: "size-based"}
# item_nsu_hetero_type, as 03_clean_ms.do declares it. Only the price-side codes reach
# `hetero_code`; the size-side ones never do, which is why the size-based branch needs
# case_price_points to name its rungs at all.
HETERO = {1: "conventional_nsu", 2: "small_size", 3: "medium_size", 4: "large_size",
          5: "mp25_price", 6: "mp50_price", 7: "mp75_price",
          8: "municipality_median", 9: "province_median",
          10: "unique_mun_price6", 11: "unique_mun_price7"}
# The price file's own vocabulary, in the order a reader expects to meet it.
PLABEL = [("has_mp25", "MP25"), ("has_mp50", "MP50"), ("has_mp75", "MP75"),
          ("has_mun_med", "municipal median"), ("has_prov_med", "province median"),
          ("has_unique", "unique price")]


def _s(x) -> str:
    return "" if pd.isna(x) else str(x).strip()


def _n(x):
    """JSON-safe number, or None. NaN is not valid JSON and json.dumps emits it anyway."""
    if x is None or pd.isna(x):
        return None
    f = float(x)
    return int(f) if f.is_integer() else round(f, 4)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    lk = pd.read_stata(DELIV / "outcome2_lookup.dta", convert_categoricals=False)
    pp = pd.read_stata(INTER / "case_price_points.dta", convert_categoricals=False)
    hb = pd.read_stata(DELIV / "outcome2_lookup_heteroblind.dta", convert_categoricals=False)
    print(f"lookup {len(lk):,} rows | price points {len(pp):,} | hetero-blind {len(hb):,}")

    # ---- the price file's own label for each point ------------------------------
    # Joined on the PRICE, which is what the lookup keeps. A case cannot hold two
    # convertible points at the same price -- the PHP 20 merge would have merged them --
    # so this is 1:1 within a case; assert rather than assume.
    for c in CASE:
        pp[c] = pp[c].map(_s)
    pp["_p"] = pp.p_g.round(4)
    dup = pp.duplicated(CASE + ["_p"]).sum()
    if dup:
        raise SystemExit(f"{dup} price points share a case and a price — cannot key on p_g")

    def plabel(r) -> str:
        got = [name for col, name in PLABEL if int(r[col] or 0) == 1]
        return " + ".join(got)

    pp["_lab"] = pp.apply(plabel, axis=1)
    plab = pp.set_index(CASE + ["_p"])["_lab"]

    # ---- the rows the page draws ------------------------------------------------
    for c in CASE:
        lk[c] = lk[c].map(_s)
    lk["dim"] = lk.corrected_unit.map(DIM).fillna("")
    lk["br"] = lk.branch.map(BRANCH).fillna("")

    def rung(r) -> str:
        """The rung's NAME. Price-side branches carry it; the size-based branch does not,
        so it is built from the cut -- and `plab` supplies the price file's label beside
        it rather than in place of it, because they answer different questions."""
        h = HETERO.get(r.hetero_code) if pd.notna(r.hetero_code) else None
        if h:
            return h
        cr, k = r.conv_rank, r.k_use
        if pd.isna(cr):
            return "unconvertible"
        if pd.isna(k):
            return f"rung {int(cr)}"
        # A RECLASSIFIED case is never cut (A12): it gets ONE weight group whatever the
        # point count, matched to the case's mp50 or median. That point need not be the
        # cheapest, so conv_rank can exceed k_use and "rung 2 of 1" is not a thing. 17
        # rows, all d_reclassified. The price-file label beside it says which point.
        if int(cr) > int(k):
            return "single rung (reclassified)"
        return f"rung {int(cr)} of {int(k)}"

    lk["rg"] = lk.apply(rung, axis=1)
    lk["_p"] = lk.p_g.round(4)
    lk["pl"] = lk.set_index(CASE + ["_p"]).index.map(plab).fillna("")
    lk["why"] = lk.unusable_why.map(_s)

    keep = CASE + ["dim", "br", "rg", "pl", "why", "p_g", "w_g", "n_g",
                   "d_point_usable"]
    rows = lk[keep].drop_duplicates().reset_index(drop=True)
    print(f"  rows after dropping the month dimension: {len(rows):,}")

    # ---- dictionary-encode the repeated strings ---------------------------------
    out_dict, col = {}, {}
    for key, src in [("pv", "pull_province"), ("mu", "pull_municipal_city"),
                     ("it", "pull_item"), ("un", "harmonized_nsu_unit"),
                     ("dim", "dim"), ("br", "br"), ("rg", "rg"),
                     ("pl", "pl"), ("why", "why")]:
        vals = sorted(rows[src].unique())
        ix = {v: i for i, v in enumerate(vals)}
        out_dict[key] = vals
        col[key] = [ix[v] for v in rows[src]]

    col["p"] = [_n(v) for v in rows.p_g]
    col["w"] = [_n(v) for v in rows.w_g]
    col["n"] = [_n(v) for v in rows.n_g]
    col["ok"] = [int(v) if pd.notna(v) else 0 for v in rows.d_point_usable]

    # ---- the hetero-blind factor, one per case x dimension ----------------------
    for c in CASE:
        hb[c] = hb[c].map(_s)
    blind = {}
    for r in hb.itertuples():
        if r.d_unconvertible == 1 or pd.isna(r.cf_blind):
            continue
        k = "|".join([r.pull_province, r.pull_municipal_city, r.pull_item,
                      r.harmonized_nsu_unit, DIM.get(r.corrected_unit, "")])
        blind[k] = [_n(r.cf_blind), _n(r.n_g_used), _n(r.fallback_level)]
    print(f"  hetero-blind factors carried: {len(blind):,}")

    payload = {"dict": out_dict, "n": len(rows), "col": col, "blind": blind}
    js = "window.LOOKUP=" + json.dumps(payload, ensure_ascii=False,
                                       separators=(",", ":"), allow_nan=False)
    assert "\x00" not in js and "</script" not in js.lower()

    out_dir = Path(args.out) if args.out else (DC / "outputs" / "tables")
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "data.js").write_text(js, encoding="utf-8")
    print(f"wrote {out_dir / 'data.js'}  ({len(js):,} bytes)")

    named = sum(1 for i in col["pl"] if out_dict["pl"][i])
    print(f"  rows carrying a price-file label: {named:,} of {len(rows):,}")


if __name__ == "__main__":
    main()
