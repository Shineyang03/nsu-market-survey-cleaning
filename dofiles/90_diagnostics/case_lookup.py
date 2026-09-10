"""Case lookup: everything recorded for one province x municipality x item x NSU cell.

WHY THIS EXISTS. The summary-statistics output (dofiles/summary_statistics.py ->
summary_stats_raw.csv / summary_stats_cleaned.csv / summary_stats.json) is aggregate:
it answers "how many weighings per province", not "what exactly did the field record
for cabbage / pack in CAPIZ / DUMARAO". The diagnostics (scope_multi_price_points.py,
validate_folds.do) print shortlists but flatten each case to a median or a ratio. When
a shortlisted case needs adjudicating, you need the underlying rows.

This file is that view. It does not compute anything new and decides nothing -- it is a
reshaped dump of the restated weighings plus the price-file rows that key to the same
cell, arranged so a single case can be read off in one place.

THE GRAIN. A "case" is
    pull_province x pull_municipal_city x pull_item x harmonized_nsu_unit x corrected_unit
which is the grain both outcomes are keyed on. Inside a case, a weighing is further
identified by raw spelling (pull_nsu_unit), weighing approach, size/price label
(item_nsu_hetero_type), market type and vendor. Those are the columns that matter when
asking whether a fold was sound: two raw spellings pooled into one case can differ
because they are genuinely different objects, or because different vendors happened to
use different spellings. Only the per-row view distinguishes those.

RUN
    python dofiles/90_diagnostics/case_lookup.py                 # writes the workbook
    python dofiles/90_diagnostics/case_lookup.py cabbage pack    # also prints matching cases

The optional arguments are substrings matched case-insensitively against the item and
the harmonized unit, for reading a case at the terminal without opening the workbook.

OUTPUT  outputs/tables/case_lookup.xlsx
    weighings         one row per weighing, sorted by case. The raw view.
    unit_x_label      case x raw spelling x size/price label -> n, min, median, max
                      weight. The view that answers "is pack the same thing as packs
                      here": compare spellings WITHIN a label, never across labels,
                      since a spelling holding a full S/M/L ladder has a higher median
                      than one holding only smalls for reasons that have nothing to do
                      with the fold.
    vendor_x_label    case x vendor x label -> n, median. Vendor heterogeneity is the
                      main rival explanation for a spelling gap; if each spelling has
                      disjoint vendors the two cannot be told apart from this data.
    price_file        the price-file rows keyed to the same cell, so the rungs the case
                      inherits sit beside the weighings they will be matched to.
"""
import sys
from pathlib import Path

import pandas as pd

BOX = Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey")
DC = BOX / "Data Cleaning"
RESTATED = DC / "outputs" / "master_rename_build" / "intermediate" / "nsu_weighings_cpi.dta"
PRICE = BOX / "NSU Market Survey Launch" / "data" / "NSU_prices_from_Makayla.csv"
OUT = DC / "outputs" / "tables" / "case_lookup.xlsx"

CASE = ["pull_province", "pull_municipal_city", "pull_item",
        "harmonized_nsu_unit", "corrected_unit"]
DIM = {1.0: "g", 2.0: "mL"}


def load():
    """The restated weighings, with the numeric codes resolved to their labels.

    Both reads are needed: convert_categoricals=False keeps weighing_approach and
    item_nsu_hetero_type as the codes the do-files branch on, and the labelled read
    supplies the human-readable text. Reading only the labelled version would make the
    codes unavailable; reading only the numeric one would print bare integers whose
    meaning depends on a label definition three files away.
    """
    num = pd.read_stata(RESTATED, convert_categoricals=False)
    lab = pd.read_stata(RESTATED, convert_categoricals=True)
    d = num.copy()
    d["approach"] = lab.weighing_approach.astype(str)
    d["size_or_price_label"] = lab.item_nsu_hetero_type.astype(str)
    d["dim"] = d.corrected_unit.map(DIM)
    return d


def weighings_sheet(d):
    cols = CASE + ["dim", "pull_nsu_unit", "cleaned_nsu_unit", "approach",
                   "weighing_approach", "size_or_price_label", "item_nsu_hetero_type",
                   "market_type", "vendor_id", "corrected_weight",
                   "pull_price", "actual_price", "price_source", "m_ms", "cpi_factor",
                   "n_raw_labels", "source"]
    cols = [c for c in cols if c in d.columns]
    return d[cols].sort_values(CASE + ["pull_nsu_unit", "item_nsu_hetero_type",
                                       "corrected_weight"])


def agg_sheet(d, by):
    """n / min / median / max of the weight, grouped by `by` within the case.

    Uses corrected_weight, the weight as measured. The former w_ref -- a restatement of
    price-quantity weights into one reference month -- is retired (issue #29), so there
    is a single weight variable on every branch.
    """
    g = d.groupby(CASE + by, dropna=False).corrected_weight
    out = g.agg(n="size", w_min="min", w_median="median", w_max="max").reset_index()
    out["w_spread"] = (out.w_max / out.w_min.replace(0, pd.NA)).round(2)
    return out.sort_values(CASE + by)


def price_sheet():
    """Price-file rows, keyed so they line up with the weighings sheet.

    The price file carries the RAW spelling (Unit_lbl), not the harmonized unit, which
    is exactly why a case can inherit more than one ladder. It is left un-harmonized
    here on purpose: the point of this sheet is to show which spelling each rung came
    from.
    """
    pr = pd.read_csv(PRICE, encoding="utf-8-sig", dtype=str)
    pr["price"] = pd.to_numeric(pr.Price, errors="coerce")
    keep = ["province", "pull_municipal_city", "cons_name", "Unit_lbl",
            "price_type", "price"]
    keep = [c for c in keep if c in pr.columns]
    return (pr[keep].rename(columns={"cons_name": "pull_item",
                                     "Unit_lbl": "pull_nsu_unit_raw"})
            .sort_values(["province", "pull_municipal_city", "pull_item",
                          "pull_nsu_unit_raw", "price_type"]))


def show(d, item_sub, unit_sub):
    """Print every case whose item and harmonized unit contain the given substrings."""
    m = d.pull_item.str.contains(item_sub, case=False, na=False)
    if unit_sub:
        m &= d.harmonized_nsu_unit.str.contains(unit_sub, case=False, na=False)
    s = d[m]
    if not len(s):
        print(f"no weighings match item~'{item_sub}' unit~'{unit_sub}'")
        return
    pd.set_option("display.width", 250)
    for k, g in s.groupby(CASE, dropna=False):
        print("\n" + "=" * 100)
        print(f"{k[0]} / {k[1]} / {k[2]} / harmonized unit '{k[3]}' / {DIM.get(k[4], k[4])}")
        print("=" * 100)
        print(g[["pull_nsu_unit", "approach", "size_or_price_label", "market_type",
                 "vendor_id", "corrected_weight", "pull_price"]]
              .sort_values(["pull_nsu_unit", "size_or_price_label", "corrected_weight"])
              .to_string(index=False))
        # the fold question, stated the only way that is fair: within a label
        both = (g.groupby("size_or_price_label").pull_nsu_unit.nunique() > 1)
        shared = list(both[both].index)
        if len(g.pull_nsu_unit.unique()) > 1:
            print(f"\n  raw spellings pooled: {sorted(g.pull_nsu_unit.unique())}")
            print(f"  labels recorded under >1 spelling: {shared or 'none'}")
            if shared:
                cmp = (g[g.size_or_price_label.isin(shared)]
                       .groupby(["size_or_price_label", "pull_nsu_unit"]).corrected_weight
                       .agg(["size", "median"]))
                print("  within-label comparison (the only fair one):")
                print("   " + cmp.to_string().replace("\n", "\n   "))
            else:
                print("  NO label is shared, so no within-label comparison exists and a"
                      "\n  cross-spelling median ratio would compare unlike labels.")
            vv = g.groupby("pull_nsu_unit").vendor_id.agg(lambda s: set(s.dropna()))
            if len(vv) > 1:
                sets = list(vv)
                disjoint = all(not (a & b) for i, a in enumerate(sets)
                               for b in sets[i + 1:])
                print(f"  vendors disjoint across spellings: {disjoint}"
                      + ("   <- spelling is confounded with vendor; a gap here cannot"
                         " be attributed to the fold" if disjoint else ""))


def main():
    d = load()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with pd.ExcelWriter(OUT, engine="openpyxl") as xw:
        weighings_sheet(d).to_excel(xw, sheet_name="weighings", index=False)
        agg_sheet(d, ["pull_nsu_unit", "size_or_price_label"]).to_excel(
            xw, sheet_name="unit_x_label", index=False)
        agg_sheet(d, ["vendor_id", "size_or_price_label"]).to_excel(
            xw, sheet_name="vendor_x_label", index=False)
        price_sheet().to_excel(xw, sheet_name="price_file", index=False)
    print(f"wrote {OUT}")
    print(f"  weighings      {len(weighings_sheet(d)):>6} rows")
    print(f"  unit_x_label   {len(agg_sheet(d, ['pull_nsu_unit', 'size_or_price_label'])):>6} rows")
    print(f"  price_file     {len(price_sheet()):>6} rows")

    if len(sys.argv) > 1:
        show(d, sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")


if __name__ == "__main__":
    main()
