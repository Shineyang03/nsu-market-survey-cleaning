"""
Summary statistics for the NSU Market Survey, raw and cleaned, side by side.

Ports the intent of the two "Summ stats" sections that lived in dofiles/archive/cleaning.do
(lines ~112-825, "Summ stats from raw data" and "Summ stats from cleaned data") but
were never carried into dofiles/00_shared/03_clean_ms.do. Those sections only ever `use`
their source and `save` to a tempfile -- nothing downstream reads them -- so this
script is purely descriptive. It does not feed the cleaning or conversion-factor
pipeline and does not modify any existing file.

Sources
-------
raw     : "../NSU Market Survey Launch/data/PSPS NSU Market Survey Launch.dta"
cleaned : outputs/master_rename_build/temp/nsu_data_master.dta

Grain (see docs/conversion_factor_methodology.md, "What identifies a row"):
  - a WEIGHING is province x municipality x item x NSU x market_type x vendor_id
    x obs_type/item_nsu_hetero_type. Unique by construction on both sides.
  - a CASE is province x municipality x item x NSU (harmonized_nsu_unit on the
    cleaned side; pull_nsu_unit is the only NSU column raw data has, so it is the
    raw-side analogue -- these are NOT the same key, just parallel roles). On the
    cleaned side the case key also carries corrected_unit, so the ~2 items that are
    recorded in both mass and volume never get mass and volume pooled into one
    case; for every other item corrected_unit is constant within the rest of the
    key, so this never inflates a case count that shouldn't be inflated.

Never joins or groups on the raw `uuid` column: it is item_unit_MUNICIPALITY with
no province, and PONTEVEDRA (Capiz and Negros Occidental) and SAN ENRIQUE (Iloilo
and Negros Occidental) each occur in two provinces. Every grouping below that
touches municipality carries province alongside it, and every municipality LEVEL
string in the outputs is written "PROVINCE | MUNICIPALITY" so the two repeats never
collide when the tables are read back.

This script reports what the data LOOK like at each end. Where a count differs
between raw and cleaned it is reported as-is with no attempt to explain or
reconcile the difference -- that is the job of the separate attrition-ledger work.

Outputs
-------
outputs/master_rename_build/tables/summary_stats_raw.csv
outputs/master_rename_build/tables/summary_stats_cleaned.csv
    Tidy long format: statistic, grouping, level, value
outputs/master_rename_build/tables/summary_stats.json
    Everything above, self-describing, keyed by statistic id
"""

import json
import re
from pathlib import Path

import numpy as np
import pandas as pd
import pyreadstat

pd.set_option("display.max_columns", None)

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------
HERE = Path(__file__).resolve().parent          # dofiles/90_diagnostics
ROOT = HERE.parent.parent                       # "Data Cleaning"
RAW_PATH = ROOT.parent / "NSU Market Survey Launch" / "data" / "PSPS NSU Market Survey Launch.dta"
CLEAN_PATH = ROOT / "outputs" / "master_rename_build" / "temp" / "nsu_data_master.dta"

OUT_DIR = ROOT / "outputs" / "master_rename_build" / "tables"
OUT_DIR.mkdir(parents=True, exist_ok=True)
DOCS_DIR = ROOT / "docs"

MARKET_TYPE_LABEL = {1: "Public Market", 2: "Talipapa", 3: "Roadside Vendors"}
HETERO_LABEL = {
    1: "conventional_nsu", 2: "small_size", 3: "medium_size", 4: "large_size",
    5: "mp25_price", 6: "mp50_price", 7: "mp75_price", 8: "municipality_median",
    9: "province_median", 10: "unique_mun_price6", 11: "unique_mun_price7",
}
WA_LABEL = {
    1: "Conventional NSU (eg. ganta, salmon, salop)",
    2: "Price-quantity based (lower, median, higher price)",
    3: "Size-based (small, medium, large)",
}
RAW_UNIT_LABEL = {1: "Kilograms (Kgs)", 2: "grams (g)", 3: "Litres (L)"}

# -----------------------------------------------------------------------------
# Row accumulator: tidy long format (statistic, grouping, level, value)
# -----------------------------------------------------------------------------
class Recorder:
    def __init__(self, source):
        self.source = source
        self.rows = []          # list of dict: statistic, grouping, level, value
        self.catalog = {}       # statistic_id -> {"title":..., "description":..., "grouping":...}

    def add(self, statistic, grouping, level, value, title=None, description=None):
        self.rows.append({"statistic": statistic, "grouping": grouping, "level": str(level), "value": value})
        if statistic not in self.catalog:
            self.catalog[statistic] = {
                "title": title or statistic,
                "description": description or "",
                "grouping": grouping,
            }

    def add_series(self, statistic, grouping, series, title=None, description=None):
        """series: pandas Series indexed by level, values are the stat value."""
        for level, value in series.items():
            self.add(statistic, grouping, level, value, title, description)

    def df(self):
        return pd.DataFrame(self.rows, columns=["statistic", "grouping", "level", "value"])


def mun_key(df, prov_col, mun_col):
    """PROVINCE | MUNICIPALITY -- never bare municipality (PONTEVEDRA, SAN ENRIQUE repeat)."""
    return df[prov_col].astype(str) + " | " + df[mun_col].astype(str)


def bucket_vendor(n):
    if n >= 3:
        return "3+"
    return str(int(n))


def weight_stats(g):
    g = g.dropna()
    if len(g) == 0:
        return pd.Series({"n": 0, "mean": np.nan, "median": np.nan, "sd": np.nan, "min": np.nan, "max": np.nan})
    return pd.Series({
        "n": len(g), "mean": g.mean(), "median": g.median(),
        "sd": g.std(ddof=1) if len(g) > 1 else 0.0, "min": g.min(), "max": g.max(),
    })


# =============================================================================
# Load
# =============================================================================
print("Loading raw ...")
raw, raw_meta = pyreadstat.read_dta(str(RAW_PATH))
print("  raw shape:", raw.shape)

print("Loading cleaned ...")
clean, clean_meta = pyreadstat.read_dta(str(CLEAN_PATH))
print("  cleaned shape:", clean.shape)

# ---- raw: decode value-labelled columns to strings for readable output -------
raw["market_type_lbl"] = raw["market_type"].map(MARKET_TYPE_LABEL)
raw["unit_lbl"] = raw["unit"].map(RAW_UNIT_LABEL)
# obs_type, weighing_approach already string on raw side

# ---- cleaned: decode -----------------------------------------------------
clean["hetero_lbl"] = clean["item_nsu_hetero_type"].map(HETERO_LABEL)
clean["weighing_approach_lbl"] = clean["weighing_approach"].map(WA_LABEL)
# market_type has NO stored label in nsu_data_master.dta; the 1/2/3 coding is
# assumed to carry through unchanged from the raw data (see cleaning.do's own
# note making the same assumption; frequency shares match closely -- checked below)
clean["market_type_lbl"] = clean["market_type"].map(MARKET_TYPE_LABEL)
# corrected_unit is stored as the numeric code 1/2 (its Stata value label "correct_unit"
# maps 1->g, 2->mL) even though pyreadstat reports it as an object dtype -- the
# object-ness comes from Stata's extended missing value .c mixing in among the floats,
# not from the column being string-typed. Decode it to the readable label ourselves,
# and use the LABEL (not the bare code) as the case-key component and the axis for
# every weight table below, so "g"/"mL" show up in the outputs instead of "1"/"2".
CORRECTED_UNIT_LABEL = {1: "g", 2: "mL"}
clean["corrected_unit_lbl"] = pd.to_numeric(clean["corrected_unit"], errors="coerce").map(CORRECTED_UNIT_LABEL)

R = Recorder("raw")
C = Recorder("cleaned")

# =============================================================================
# Section 0: sanity -- confirm the grain claims in the brief before reporting
# =============================================================================
raw_weighing_key = ["pull_province", "pull_municipal_city", "pull_item", "pull_nsu_unit",
                     "market_type", "vendor_id", "obs_type"]
n_raw_rows = len(raw)
n_raw_groups = raw.groupby(raw_weighing_key, dropna=False).ngroups
print(f"raw weighing grain: {n_raw_rows} rows, {n_raw_groups} groups (unique={n_raw_rows == n_raw_groups})")

clean_weighing_key = ["pull_province", "pull_municipal_city", "pull_item", "harmonized_nsu_unit",
                       "market_type", "vendor_id", "item_nsu_hetero_type"]
n_clean_rows = len(clean)
n_clean_groups = clean.groupby(clean_weighing_key, dropna=False).ngroups
print(f"cleaned weighing grain: {n_clean_rows} rows, {n_clean_groups} groups (unique={n_clean_rows == n_clean_groups})")

for Rec, n_rows, n_groups, label in [
    (R, n_raw_rows, n_raw_groups, "raw"),
    (C, n_clean_rows, n_clean_groups, "cleaned"),
]:
    Rec.add("weighing_grain_check", "overall", "n_rows", n_rows,
            title="Rows at the weighing grain",
            description="province x municipality x item x NSU x market_type x vendor_id x obs_type/hetero_type")
    Rec.add("weighing_grain_check", "overall", "n_distinct_groups", n_groups,
            title="Distinct groups at the weighing grain")

# =============================================================================
# Section 1: top-line unique counts
# =============================================================================
def add_toplevel_counts(Rec, df, item_col, prov_col, mun_col, nsu_cols, case_extra_cols=None):
    """nsu_cols: dict of {label: column_name} for the various NSU-name columns
    available on this side. case_extra_cols: extra columns folded into the case
    key (e.g. corrected_unit on the cleaned side)."""
    case_extra_cols = case_extra_cols or []

    Rec.add("n_weighings", "overall", "all", len(df), title="Total weighings (rows)")
    Rec.add("n_unique_items", "overall", "all", df[item_col].nunique(),
            title="Distinct items (pull_item)")
    Rec.add("n_provinces", "overall", "all", df[prov_col].nunique(), title="Distinct provinces")
    Rec.add("n_prov_mun_pairs", "overall", "all",
            df[[prov_col, mun_col]].drop_duplicates().shape[0],
            title="Distinct province x municipality pairs",
            description="Municipality alone is not a safe key; PONTEVEDRA and SAN ENRIQUE each occur in two provinces.")
    Rec.add("n_vendors", "overall", "all", df["vendor_id"].nunique(), title="Distinct vendor_id")
    Rec.add("n_markets", "overall", "all", df["market_name"].nunique(), title="Distinct market_name")

    for label, col in nsu_cols.items():
        Rec.add(f"n_unique_nsu_{label}", "overall", "all", df[col].nunique(),
                title=f"Distinct NSU unit labels ({col})")
        Rec.add(f"n_unique_item_x_nsu_{label}", "overall", "all",
                df[[item_col, col]].drop_duplicates().shape[0],
                title=f"Distinct item x NSU pairs ({col})")

    # primary "case" key: province x municipality x item x (primary NSU col) [x extras]
    primary_nsu_col = list(nsu_cols.values())[-1]  # harmonized on cleaned side, pull_nsu_unit on raw
    case_cols = [prov_col, mun_col, item_col, primary_nsu_col] + case_extra_cols
    n_cases = df[case_cols].drop_duplicates().shape[0]
    Rec.add("n_unique_cases", "overall", "all", n_cases,
            title="Distinct cases (province x municipality x item x NSU" +
                  (" x corrected_unit)" if case_extra_cols else ")"),
            description="Case key columns: " + " x ".join(case_cols))
    return case_cols


raw_case_cols = add_toplevel_counts(
    R, raw, "pull_item", "pull_province", "pull_municipal_city",
    nsu_cols={"raw_label": "pull_nsu_unit"},
)
clean_case_cols = add_toplevel_counts(
    C, clean, "pull_item", "pull_province", "pull_municipal_city",
    nsu_cols={"raw_label": "pull_nsu_unit", "cleaned_label": "cleaned_nsu_unit", "harmonized": "harmonized_nsu_unit"},
    case_extra_cols=["corrected_unit_lbl"],
)

print("raw case cols:", raw_case_cols, "-> n_cases:", raw[raw_case_cols].drop_duplicates().shape[0])
print("clean case cols:", clean_case_cols, "-> n_cases:", clean[clean_case_cols].drop_duplicates().shape[0])

# =============================================================================
# Section 2: counts by province / municipality / item / weighing approach /
#            hetero type / market type
# =============================================================================
def counts_by(Rec, df, col, statistic, title, level_fn=None):
    s = df[col].value_counts(dropna=False)
    s.index = s.index.map(level_fn) if level_fn else s.index
    s = s.sort_index()
    Rec.add_series(statistic, col, s, title=title)


counts_by(R, raw, "pull_province", "n_weighings_by_province", "Weighings by province")
counts_by(C, clean, "pull_province", "n_weighings_by_province", "Weighings by province")

for Rec, df, prov_col, mun_col in [(R, raw, "pull_province", "pull_municipal_city"),
                                    (C, clean, "pull_province", "pull_municipal_city")]:
    tmp = df.copy()
    tmp["prov_mun"] = mun_key(tmp, prov_col, mun_col)
    counts_by(Rec, tmp, "prov_mun", "n_weighings_by_municipality",
              "Weighings by province | municipality")

counts_by(R, raw, "pull_item", "n_weighings_by_item", "Weighings by item")
counts_by(C, clean, "pull_item", "n_weighings_by_item", "Weighings by item")

counts_by(R, raw, "weighing_approach", "n_weighings_by_weighing_approach", "Weighings by weighing approach")
counts_by(C, clean, "weighing_approach_lbl", "n_weighings_by_weighing_approach", "Weighings by weighing approach")

counts_by(R, raw, "obs_type", "n_weighings_by_hetero_type", "Weighings by obs_type / hetero-group type")
counts_by(C, clean, "hetero_lbl", "n_weighings_by_hetero_type", "Weighings by obs_type / hetero-group type")

counts_by(R, raw, "market_type_lbl", "n_weighings_by_market_type", "Weighings by market type")
counts_by(C, clean, "market_type_lbl", "n_weighings_by_market_type",
          "Weighings by market type (cleaned data has no stored market_type label; "
          "the 1/2/3 coding is assumed unchanged from raw -- see docs/conversion_factor_methodology.md)")

# =============================================================================
# Section 3: coverage
# =============================================================================
# ---- cases per province --------------------------------------------------
def cases_per_province(Rec, df, case_cols, prov_col):
    cases = df[case_cols].drop_duplicates()
    s = cases.groupby(prov_col).size().sort_index()
    Rec.add_series("n_cases_by_province", prov_col, s, title="Distinct cases by province")

cases_per_province(R, raw, raw_case_cols, "pull_province")
cases_per_province(C, clean, clean_case_cols, "pull_province")

# ---- items per municipality -----------------------------------------------
def items_per_municipality(Rec, df, item_col, prov_col, mun_col):
    tmp = df.copy()
    tmp["prov_mun"] = mun_key(tmp, prov_col, mun_col)
    s = tmp.groupby("prov_mun")[item_col].nunique().sort_index()
    Rec.add_series("n_items_by_municipality", "prov_mun", s,
                    title="Distinct items by province | municipality")

items_per_municipality(R, raw, "pull_item", "pull_province", "pull_municipal_city")
items_per_municipality(C, clean, "pull_item", "pull_province", "pull_municipal_city")

# ---- market slots filled: how many distinct market_types per case (orig Section 5) --
def market_slots_filled(Rec, df, case_cols):
    tmp = df[case_cols + ["market_type_lbl"]].drop_duplicates()
    n_slots = tmp.groupby(case_cols)["market_type_lbl"].nunique()
    s = n_slots.value_counts().sort_index()
    s.index = s.index.astype(str)
    Rec.add_series("n_cases_by_market_slots_filled", "n_market_types_present", s,
                    title="Cases by number of distinct market types present (of 3 possible)")

market_slots_filled(R, raw, raw_case_cols)
market_slots_filled(C, clean, clean_case_cols)

# ---- vendors per case, split by market type (orig Section 6) --------------
def vendors_per_case(Rec, df, case_cols, hetero_col):
    cell_cols = case_cols + [hetero_col, "market_type_lbl"]
    n_vendor = df.groupby(cell_cols)["vendor_id"].nunique().reset_index(name="n_vendor")
    n_vendor["bucket"] = n_vendor["n_vendor"].apply(bucket_vendor)
    Rec.add("max_vendors_observed_in_one_cell", "overall", "all", int(n_vendor["n_vendor"].max()),
            title="Max distinct vendor_id observed in any (case x hetero-type x market_type) cell")
    for mt, sub in n_vendor.groupby("market_type_lbl"):
        s = sub["bucket"].value_counts()
        for lvl in ["1", "2", "3+"]:
            Rec.add("n_vendors_per_cell_by_market_type", "market_type | n_vendor_bucket",
                    f"{mt} | {lvl}", int(s.get(lvl, 0)),
                    title="Cells (case x hetero-type x market_type), by number of distinct vendors, split by market type")
    # overall average vendors per cell (any market type)
    Rec.add("avg_vendors_per_cell", "overall", "all", float(n_vendor["n_vendor"].mean()),
            title="Average distinct vendors per (case x hetero-type x market_type) cell")

vendors_per_case(R, raw, raw_case_cols, "obs_type")
vendors_per_case(C, clean, clean_case_cols, "hetero_lbl")

# =============================================================================
# Section 4: weighing_approach / hetero-type coverage per case (orig Sections 2-4)
# =============================================================================
def approach_coverage(Rec, df, case_cols, approach_col, statistic_prefix, title_noun):
    tmp = df[case_cols + [approach_col]].copy()
    present = tmp.drop_duplicates()
    s = present.groupby(approach_col).size().sort_index()
    Rec.add_series(f"n_cases_with_ge1_obs_by_{statistic_prefix}", approach_col, s,
                    title=f"Cases with >=1 weighing under each {title_noun} (a case can appear in more than one)")

    n_cats_present = present.groupby(case_cols).size()
    n_multi = int((n_cats_present > 1).sum())
    Rec.add(f"n_cases_multi_{statistic_prefix}", "overall", "all", n_multi,
            title=f"Cases with weighings spanning more than one {title_noun}")

    # avg n weighings per case within each category, excluding zero-obs cases
    n_obs = df.groupby(case_cols + [approach_col]).size().reset_index(name="n_obs")
    avg = n_obs.groupby(approach_col)["n_obs"].mean().sort_index()
    Rec.add_series(f"avg_weighings_per_case_by_{statistic_prefix}", approach_col, avg,
                    title=f"Average weighings per case, by {title_noun} (excl. 0-obs cases)")


approach_coverage(R, raw, raw_case_cols, "weighing_approach", "weighing_approach", "weighing approach")
approach_coverage(C, clean, clean_case_cols, "weighing_approach_lbl", "weighing_approach", "weighing approach")

approach_coverage(R, raw, raw_case_cols, "obs_type", "hetero_type", "obs_type / hetero-group type")
approach_coverage(C, clean, clean_case_cols, "hetero_lbl", "hetero_type", "obs_type / hetero-group type")

# =============================================================================
# Section 5: weight distribution by item and unit -- raw (before) vs cleaned (after)
# =============================================================================
def weight_distribution(Rec, df, item_col, weight_col, unit_col, statistic_prefix, title_noun):
    grp = df.groupby([item_col, unit_col])[weight_col].apply(weight_stats).unstack()
    for (item, unit), row in grp.iterrows():
        level = f"{item} | {unit}"
        for stat_name in ["n", "mean", "median", "sd", "min", "max"]:
            val = row[stat_name]
            if pd.notna(val):
                val = float(val)
            Rec.add(f"{statistic_prefix}_{stat_name}", "item | unit", level, val,
                    title=f"{title_noun}: {stat_name} weight, by item x unit")


raw_w = raw.copy()
raw_w["weight_num"] = pd.to_numeric(raw_w["weight"], errors="coerce")
weight_distribution(R, raw_w, "pull_item", "weight_num", "unit_lbl",
                     "weight_raw", "Raw weight (before order-of-magnitude correction)")

clean_w = clean.copy()
clean_w["corrected_weight_num"] = pd.to_numeric(clean_w["corrected_weight"], errors="coerce")
weight_distribution(C, clean_w, "pull_item", "corrected_weight_num", "corrected_unit_lbl",
                     "weight_corrected", "Corrected weight (after order-of-magnitude correction)")

# unit-level frequency (how many weighings recorded in each unit)
counts_by(R, raw, "unit_lbl", "n_weighings_by_unit", "Weighings by raw unit (kg/g/L)")
counts_by(C, clean, "corrected_unit_lbl", "n_weighings_by_unit", "Weighings by corrected unit (g/mL)")

# =============================================================================
# Section 6: NSU vocabulary -- pull_nsu_unit collapsing into harmonized_nsu_unit
# =============================================================================
R.add("n_distinct_pull_nsu_unit", "overall", "all", raw["pull_nsu_unit"].nunique(),
      title="Distinct raw NSU strings (pull_nsu_unit)")
C.add("n_distinct_pull_nsu_unit", "overall", "all", clean["pull_nsu_unit"].nunique(),
      title="Distinct raw NSU strings (pull_nsu_unit) surviving into the cleaned data")
C.add("n_distinct_cleaned_nsu_unit", "overall", "all", clean["cleaned_nsu_unit"].nunique(),
      title="Distinct spelling-corrected NSU strings (cleaned_nsu_unit, reference only)")
C.add("n_distinct_harmonized_nsu_unit", "overall", "all", clean["harmonized_nsu_unit"].nunique(),
      title="Distinct pooling-key NSU strings (harmonized_nsu_unit)")

# how many distinct raw labels collapse into each harmonized unit (item-conditioned,
# so the same harmonized string in two different items is counted separately)
collapse = (clean.groupby(["pull_item", "harmonized_nsu_unit"])["pull_nsu_unit"]
            .nunique().reset_index(name="n_raw_labels"))
for _, row in collapse.iterrows():
    C.add("n_raw_labels_by_item_harmonized_unit", "item | harmonized_nsu_unit",
          f"{row['pull_item']} | {row['harmonized_nsu_unit']}", int(row["n_raw_labels"]),
          title="Distinct raw pull_nsu_unit labels folding into each item x harmonized_nsu_unit cell")

collapse_bucket = collapse["n_raw_labels"].apply(lambda n: "1" if n == 1 else ("2" if n == 2 else "3+"))
s = collapse_bucket.value_counts()
for lvl in ["1", "2", "3+"]:
    C.add("n_item_harmonized_cells_by_collapse_count", "n_raw_labels_collapsed", lvl, int(s.get(lvl, 0)),
          title="Item x harmonized_nsu_unit cells, by how many distinct raw labels fold into them")

# =============================================================================
# Write outputs
# =============================================================================
raw_df = R.df()
clean_df = C.df()

raw_out = OUT_DIR / "summary_stats_raw.csv"
clean_out = OUT_DIR / "summary_stats_cleaned.csv"
raw_df.to_csv(raw_out, index=False)
clean_df.to_csv(clean_out, index=False)
print(f"Wrote {raw_out} ({len(raw_df)} rows)")
print(f"Wrote {clean_out} ({len(clean_df)} rows)")

# ---- JSON: self-describing, keyed by statistic id -------------------------
def build_statistic_catalog(Rec):
    out = []
    for stat_id, meta in Rec.catalog.items():
        rows = [r for r in Rec.rows if r["statistic"] == stat_id]
        out.append({
            "id": stat_id,
            "title": meta["title"],
            "description": meta["description"],
            "grouping": meta["grouping"],
            "n_levels": len(rows),
            "data": [{"level": r["level"], "value": r["value"]} for r in rows],
        })
    return out

json_payload = {
    "$schema_note": (
        "Each entry in raw.statistics / cleaned.statistics has: id (short name), "
        "title (human label), description (notes/caveats), grouping (the dimension "
        "the 'level' values run over -- 'overall' means a single scalar), n_levels, "
        "and data: a list of {level, value} pairs. The same statistic id means the "
        "same definition on both sides EXCEPT where the description says otherwise "
        "(e.g. raw has no harmonized_nsu_unit, so its 'case' key uses pull_nsu_unit)."
    ),
    "generated_from": {
        "raw_source": str(RAW_PATH.resolve()),
        "cleaned_source": str(CLEAN_PATH.resolve()),
        "raw_n_rows": int(len(raw)),
        "cleaned_n_rows": int(len(clean)),
    },
    "grain_definitions": {
        "weighing": {
            "raw": " x ".join(raw_weighing_key),
            "cleaned": " x ".join(clean_weighing_key),
        },
        "case": {
            "raw": " x ".join(raw_case_cols),
            "cleaned": " x ".join(clean_case_cols),
        },
        "note": (
            "Never grouped or joined on the raw `uuid` column -- it is "
            "item_unit_MUNICIPALITY with no province, and PONTEVEDRA (Capiz and "
            "Negros Occidental) and SAN ENRIQUE (Iloilo and Negros Occidental) each "
            "occur in two provinces. Every municipality-level 'level' string in this "
            "file is written 'PROVINCE | MUNICIPALITY'."
        ),
    },
    "raw": {"statistics": build_statistic_catalog(R)},
    "cleaned": {"statistics": build_statistic_catalog(C)},
}

json_out = OUT_DIR / "summary_stats.json"
with open(json_out, "w", encoding="utf-8") as f:
    json.dump(json_payload, f, indent=2, default=str)
print(f"Wrote {json_out}")

print("\nDone.")
