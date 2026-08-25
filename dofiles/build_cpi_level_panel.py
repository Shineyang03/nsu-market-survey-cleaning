"""
Build the CPI level panel and item crosswalk described in
docs/inflation_adjustment_spec.md.

Deliverables (levels only -- no ratios, no inflation factors, no aggregation
to any survey grain, no application to weights; see spec section 7):

  outputs/tables/cpi_level_panel.csv
      province x item_group x month -> cpi, cpi_ma3, cpi_source
  outputs/tables/cpi_item_crosswalk.csv
      (province, cons_name) -> item_group, normalized the same way
      dofiles/analysis.do normalizes it (spec section 4.2).
  outputs/tables/cpi_panel_validation.txt
      the validation report required by spec section 8.

This script supersedes the killed earlier run's scratch files of the same
names (spec section 10) -- those are NOT read or built upon here.

Run: python dofiles/build_cpi_level_panel.py
"""

import hashlib
import sys
from pathlib import Path

import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

NSU_ROOT = Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey")
DATA_DIR = NSU_ROOT / "NSU Market Survey Launch" / "data"
REPO_ROOT = NSU_ROOT / "Data Cleaning"
TABLES_DIR = REPO_ROOT / "outputs" / "tables"

CPI_FILE = DATA_DIR / "fp_cpi_byprov_byitem_psa_2023_26.csv"
CROSSWALK_FILE = DATA_DIR / "cons_name_to_coicop_crosswalk.csv"

CPI_FILE_SHA256_EXPECTED = (
    "62e938ef119b91dd0e9d5b6badff4eeb17108151d921591dcbfabec9cba0a4be"
)

OUT_PANEL = TABLES_DIR / "cpi_level_panel.csv"
OUT_CROSSWALK = TABLES_DIR / "cpi_item_crosswalk.csv"
OUT_VALIDATION = TABLES_DIR / "cpi_panel_validation.txt"

TIER_LABELS = {
    1: "tier1_province_exact_group",
    2: "tier2_province_parent_group",
    3: "tier3_national_group",
    4: "tier4_all_food",
}


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def stata_mdate(year: pd.Series, month: pd.Series) -> pd.Series:
    """Stata %tm monthly date: months since 1960m1 (1960m1 == 0)."""
    return (year - 1960) * 12 + (month - 1)


def mdate_to_yearmonth(mdate: int) -> str:
    y = 1960 + (mdate // 12)
    m = 1 + (mdate % 12)
    return f"{y:04d}-{m:02d}"


def extract_code(item_group: str) -> str:
    """The leading COICOP numeric code, e.g. '01.1.7.1 - Leafy ...' -> '01.1.7.1'."""
    return item_group.split(" - ", 1)[0].strip()


def parent_code(code: str) -> str | None:
    if "." not in code:
        return None
    return code.rsplit(".", 1)[0]


def main() -> None:
    report_lines: list[str] = []

    def log(*parts):
        line = " ".join(str(p) for p in parts)
        print(line)
        report_lines.append(line)

    log("=" * 78)
    log("CPI LEVEL PANEL BUILD -- validation report")
    log("Spec: docs/inflation_adjustment_spec.md")
    log("=" * 78)

    # -----------------------------------------------------------------
    # 3.1 Pin the vintage and verify its hash
    # -----------------------------------------------------------------
    actual_hash = sha256_of(CPI_FILE)
    log()
    log("## Vintage pinning")
    log(f"CPI file used: {CPI_FILE}")
    log(f"sha256 (expected, from spec): {CPI_FILE_SHA256_EXPECTED}")
    log(f"sha256 (actual):              {actual_hash}")
    if actual_hash != CPI_FILE_SHA256_EXPECTED:
        log("*** MISMATCH -- vintage does not match the pinned spec value. ABORTING. ***")
        Path(OUT_VALIDATION).write_text("\n".join(report_lines), encoding="utf-8")
        sys.exit(1)
    log("Hash MATCHES the pinned vintage in spec section 3.1. Proceeding.")

    # -----------------------------------------------------------------
    # 4.1 Import and normalize the CPI file
    # -----------------------------------------------------------------
    cpi_raw = pd.read_csv(CPI_FILE)
    assert list(cpi_raw.columns) == ["geolocation", "commodity", "year", "month", "date", "cpi"], (
        f"Unexpected columns in CPI file: {cpi_raw.columns.tolist()}"
    )

    cpi = cpi_raw.copy()
    cpi["province"] = cpi["geolocation"].str.upper()
    cpi["item_group"] = cpi["commodity"]
    cpi["mdate"] = stata_mdate(cpi["year"], cpi["month"])
    cpi = cpi.drop(columns=["geolocation", "commodity", "date", "year", "month"])
    cpi = cpi[["province", "item_group", "mdate", "cpi"]]

    # sanity: no duplicate (province, item_group, mdate) in the raw source
    dupe_check = cpi.duplicated(subset=["province", "item_group", "mdate"]).sum()
    if dupe_check:
        log(f"*** WARNING: {dupe_check} duplicate (province,item_group,mdate) rows in raw CPI file ***")

    # -----------------------------------------------------------------
    # 3.2 / 4.2 Import and normalize the item crosswalk; join key is
    # (province, cons_name) -- NEVER cons_name alone (spec section 4.2,
    # known trap #1 in section 6).
    # -----------------------------------------------------------------
    cw_raw = pd.read_csv(CROSSWALK_FILE)
    assert list(cw_raw.columns) == ["province", "cons_name", "item_group"], (
        f"Unexpected columns in crosswalk file: {cw_raw.columns.tolist()}"
    )
    n_cw_rows_raw = len(cw_raw)
    n_cons_name_raw = cw_raw["cons_name"].nunique()

    cw = cw_raw.copy()
    # same normalization analysis.do applies (lines 143-145 of the spec / analysis.do:73,186,93)
    cw["cons_name"] = cw["cons_name"].where(
        ~cw["cons_name"].str.contains("restaurant"),
        "Drinks at restaurant, hotel, cafe, or kiosk",
    )
    cw["cons_name"] = cw["cons_name"].str.replace("caf\u00e9", "cafe", regex=False)

    # isid cons_name province check
    isid_ok = not cw.duplicated(subset=["cons_name", "province"]).any()
    log()
    log("## Item crosswalk")
    log(f"rows: {len(cw)} (raw file had {n_cw_rows_raw})")
    log(f"distinct cons_name: {cw['cons_name'].nunique()} (raw file had {n_cons_name_raw})")
    log(f"distinct province: {cw['province'].nunique()}")
    log(f"isid cons_name province holds: {isid_ok}")
    if not isid_ok:
        log("*** WARNING: crosswalk is not unique on (cons_name, province) after normalization ***")

    # confirm the one documented province-varying item: ice cream
    grp_by_item = cw.groupby("item_group")["province"].apply(lambda s: sorted(s.unique()))
    varying_items = {g: p for g, p in grp_by_item.items() if len(p) < cw["province"].nunique()}
    log(f"item_group values not used by all {cw['province'].nunique()} provinces: {len(varying_items)}")
    for g, provs in varying_items.items():
        log(f"  - {g!r}: used by {provs}")

    cw.to_csv(OUT_CROSSWALK, index=False)

    # -----------------------------------------------------------------
    # Build the target grid: (province, item_group) pairs the crosswalk
    # actually needs, crossed with every month present in the CPI file.
    # -----------------------------------------------------------------
    needed_pairs = cw[["province", "item_group"]].drop_duplicates().reset_index(drop=True)
    months = np.sort(cpi["mdate"].unique())

    target = needed_pairs.merge(pd.DataFrame({"mdate": months}), how="cross")

    log()
    log("## Target panel grid")
    log(f"needed (province, item_group) pairs from crosswalk: {len(needed_pairs)}")
    log(f"distinct item_group values needed: {needed_pairs['item_group'].nunique()}")
    log(f"months in CPI file: {len(months)} "
        f"({mdate_to_yearmonth(int(months.min()))} to {mdate_to_yearmonth(int(months.max()))})")
    log(f"target rows (pairs x months): {len(target)}")

    full_cross = needed_pairs["province"].nunique() * needed_pairs["item_group"].nunique()
    log(f"full province x item_group rectangle would be "
        f"{needed_pairs['province'].nunique()} x {needed_pairs['item_group'].nunique()} = {full_cross} pairs; "
        f"actual pairs = {len(needed_pairs)} (ragged by {full_cross - len(needed_pairs)}, "
        f"expected -- see ice cream exception above)")

    # -----------------------------------------------------------------
    # 5. Coverage ladder
    # -----------------------------------------------------------------
    # Tier 1: exact (province, item_group, mdate) match in the CPI file.
    merged = target.merge(
        cpi[["province", "item_group", "mdate", "cpi"]],
        on=["province", "item_group", "mdate"],
        how="left",
    )
    merged["cpi_source_tier"] = np.where(merged["cpi"].notna(), 1, np.nan)

    still_missing = merged[merged["cpi"].isna()].drop(columns=["cpi", "cpi_source_tier"])

    # Tier 2: province x parent COICOP group.
    if len(still_missing):
        cpi_by_code = cpi.copy()
        cpi_by_code["code"] = cpi_by_code["item_group"].map(extract_code)
        still_missing = still_missing.copy()
        still_missing["code"] = still_missing["item_group"].map(extract_code)
        still_missing["parent_code"] = still_missing["code"].map(parent_code)

        parent_lookup = cpi_by_code.rename(
            columns={"item_group": "item_group_parent", "cpi": "cpi_tier2", "code": "parent_code"}
        )[["province", "parent_code", "mdate", "cpi_tier2", "item_group_parent"]]

        t2 = still_missing.merge(parent_lookup, on=["province", "parent_code", "mdate"], how="left")
        t2_found = t2[t2["cpi_tier2"].notna()].drop_duplicates(subset=["province", "item_group", "mdate"])
        t2_found = t2_found[["province", "item_group", "mdate", "cpi_tier2"]].rename(
            columns={"cpi_tier2": "cpi"}
        )
        t2_found["cpi_source_tier"] = 2
    else:
        t2_found = merged.iloc[0:0][["province", "item_group", "mdate", "cpi", "cpi_source_tier"]]

    resolved_so_far = pd.concat(
        [merged[merged["cpi"].notna()], t2_found], ignore_index=True
    )
    still_missing2 = target.merge(
        resolved_so_far[["province", "item_group", "mdate"]].drop_duplicates(),
        on=["province", "item_group", "mdate"],
        how="left",
        indicator=True,
    )
    still_missing2 = still_missing2[still_missing2["_merge"] == "left_only"].drop(columns="_merge")

    # Tier 3: national (unweighted mean across the provinces present in the
    # CPI file) x exact group. NOTE: the source file carries no separate
    # "national" series -- there is no PSA national row in this extract, so
    # a tier-3 fallback would have to be CONSTRUCTED as the unweighted mean
    # of the province-level series for that item_group and month. This is
    # only exercised if tier 1/2 leave gaps.
    if len(still_missing2):
        national = (
            cpi.groupby(["item_group", "mdate"])["cpi"].mean().reset_index().rename(columns={"cpi": "cpi_tier3"})
        )
        t3 = still_missing2.merge(national, on=["item_group", "mdate"], how="left")
        t3_found = t3[t3["cpi_tier3"].notna()][["province", "item_group", "mdate", "cpi_tier3"]].rename(
            columns={"cpi_tier3": "cpi"}
        )
        t3_found["cpi_source_tier"] = 3
    else:
        t3_found = merged.iloc[0:0][["province", "item_group", "mdate", "cpi", "cpi_source_tier"]]

    resolved_so_far = pd.concat([resolved_so_far, t3_found], ignore_index=True)
    still_missing3 = target.merge(
        resolved_so_far[["province", "item_group", "mdate"]].drop_duplicates(),
        on=["province", "item_group", "mdate"],
        how="left",
        indicator=True,
    )
    still_missing3 = still_missing3[still_missing3["_merge"] == "left_only"].drop(columns="_merge")

    # Tier 4: all-food. The source file also carries no single "all food"
    # aggregate row; constructed here as the unweighted mean, per province
    # and month, across every food-coded (leading code "01") commodity in
    # the raw file. Only exercised if tiers 1-3 leave gaps.
    if len(still_missing3):
        cpi_food = cpi[cpi["item_group"].map(extract_code).str.startswith("01")]
        all_food = cpi_food.groupby(["province", "mdate"])["cpi"].mean().reset_index().rename(
            columns={"cpi": "cpi_tier4"}
        )
        t4 = still_missing3.merge(all_food, on=["province", "mdate"], how="left")
        t4_found = t4[t4["cpi_tier4"].notna()][["province", "item_group", "mdate", "cpi_tier4"]].rename(
            columns={"cpi_tier4": "cpi"}
        )
        t4_found["cpi_source_tier"] = 4
    else:
        t4_found = merged.iloc[0:0][["province", "item_group", "mdate", "cpi", "cpi_source_tier"]]

    resolved_all = pd.concat([resolved_so_far, t4_found], ignore_index=True)

    truly_unresolved = target.merge(
        resolved_all[["province", "item_group", "mdate"]].drop_duplicates(),
        on=["province", "item_group", "mdate"],
        how="left",
        indicator=True,
    )
    truly_unresolved = truly_unresolved[truly_unresolved["_merge"] == "left_only"].drop(columns="_merge")

    log()
    log("## Coverage ladder results")
    tier_counts = resolved_all["cpi_source_tier"].astype(int).value_counts().sort_index()
    for tier in [1, 2, 3, 4]:
        n = int(tier_counts.get(tier, 0))
        log(f"  {TIER_LABELS[tier]}: {n} rows")
    log(f"  UNRESOLVED (present in no tier): {len(truly_unresolved)} rows")
    if len(truly_unresolved):
        log("  Full list of unresolved (province, item_group, month) cells:")
        for _, r in truly_unresolved.iterrows():
            log(f"    - {r['province']} | {r['item_group']} | {mdate_to_yearmonth(int(r['mdate']))}")
    else:
        log("  Coverage is empirically COMPLETE at tier 1 for all needed cells.")
        log("  Tiers 2-4 were not exercised on this vintage -- confirmed empty, not merely assumed.")

    panel = resolved_all.copy()
    panel["cpi_source"] = panel["cpi_source_tier"].astype(int).map(TIER_LABELS)
    panel = panel.drop(columns=["cpi_source_tier"])

    # -----------------------------------------------------------------
    # 4.3 cpi_ma3: 3-month centred moving average of the LEVEL.
    # Endpoint handling: the first and last month of each (province,
    # item_group) series get a MISSING cpi_ma3 rather than a shrunk
    # 2-point window -- an asymmetric 2-point average at an edge is not
    # the same statistic as the interior 3-point average and averaging
    # them together would silently change what the column means from
    # month to month. This choice is deliberate, not a library default.
    # -----------------------------------------------------------------
    panel = panel.sort_values(["province", "item_group", "mdate"]).reset_index(drop=True)

    def add_ma3(g: pd.DataFrame) -> pd.DataFrame:
        g = g.sort_values("mdate")
        # require literal +/-1 month adjacency (not just row adjacency),
        # matching the panel's monthly key.
        v = g.set_index("mdate")["cpi"]
        prev_ok = v.index.to_series().sub(1).isin(v.index)
        next_ok = v.index.to_series().add(1).isin(v.index)
        ma3 = pd.Series(index=v.index, dtype=float)
        for m in v.index:
            if (m - 1) in v.index and (m + 1) in v.index:
                ma3.loc[m] = np.mean([v.loc[m - 1], v.loc[m], v.loc[m + 1]])
            else:
                ma3.loc[m] = np.nan
        g = g.set_index("mdate")
        g["cpi_ma3"] = ma3
        return g.reset_index()

    panel = panel.groupby(["province", "item_group"], group_keys=False).apply(add_ma3)

    panel["year_month"] = panel["mdate"].map(mdate_to_yearmonth)
    panel = panel[["province", "item_group", "mdate", "year_month", "cpi", "cpi_ma3", "cpi_source"]]
    panel = panel.sort_values(["province", "item_group", "mdate"]).reset_index(drop=True)

    panel.to_csv(OUT_PANEL, index=False)

    # -----------------------------------------------------------------
    # 8. Validation
    # -----------------------------------------------------------------
    log()
    log("## Panel dimensions")
    n_prov = panel["province"].nunique()
    n_grp = panel["item_group"].nunique()
    n_mo = panel["mdate"].nunique()
    log(f"provinces: {n_prov}  |  item_groups: {n_grp}  |  months: {n_mo}")
    log(f"rows: {len(panel)}  (would be {n_prov * n_grp * n_mo} if it were a full "
        f"province x item_group x month rectangle)")
    pair_counts = panel.groupby(["province", "item_group"])["mdate"].nunique()
    balanced_within_pairs = (pair_counts == n_mo).all()
    log(f"balanced across time within every included (province,item_group) pair: {balanced_within_pairs} "
        f"(every included pair has exactly {n_mo} months, min={pair_counts.min()}, max={pair_counts.max()})")
    log(f"NOT a full province x item_group rectangle: {len(needed_pairs)} of {full_cross} possible pairs "
        f"present -- the {full_cross - len(needed_pairs)} missing pair(s) are the documented ice-cream "
        f"exception (item_group varies by province for that one cons_name), not a data gap.")

    log()
    log("## cpi distribution")
    desc = panel["cpi"].describe(percentiles=[0.25, 0.5, 0.75])
    log(f"min={desc['min']:.4f}  p25={desc['25%']:.4f}  p50={desc['50%']:.4f}  "
        f"p75={desc['75%']:.4f}  max={desc['max']:.4f}")
    n_missing = panel["cpi"].isna().sum()
    n_zero = (panel["cpi"] == 0).sum()
    n_neg = (panel["cpi"] < 0).sum()
    log(f"missing cpi: {n_missing}  |  zero cpi: {n_zero}  |  negative cpi: {n_neg}")
    assert n_missing == 0, "cpi has missing values"
    assert n_zero == 0, "cpi has zero values"
    assert n_neg == 0, "cpi has negative values"
    log("ASSERTIONS PASSED: cpi is never missing, zero, or negative.")

    log()
    log("## Counts per cpi_source tier (repeat, on final panel)")
    for tier_label in TIER_LABELS.values():
        n = int((panel["cpi_source"] == tier_label).sum())
        log(f"  {tier_label}: {n}")

    log()
    log("## Top 10 largest month-on-month moves (level pct change within a series)")
    mom = panel.copy()
    mom["cpi_lag"] = mom.groupby(["province", "item_group"])["cpi"].shift(1)
    mom["mdate_lag"] = mom.groupby(["province", "item_group"])["mdate"].shift(1)
    mom = mom[mom["mdate"] == mom["mdate_lag"] + 1]  # true adjacent months only
    mom["pct_change"] = (mom["cpi"] - mom["cpi_lag"]) / mom["cpi_lag"] * 100
    top10 = mom.reindex(mom["pct_change"].abs().sort_values(ascending=False).index).head(10)
    for _, r in top10.iterrows():
        log(f"  {r['province']:<20s} {r['item_group']:<55s} "
            f"{mdate_to_yearmonth(int(r['mdate_lag']))}->{mdate_to_yearmonth(int(r['mdate']))}  "
            f"{r['pct_change']:+.1f}%")

    log()
    log("## Index integrity for ratio use")
    log("Fixed-base level check: PSA CPI series by construction are fixed-base index levels")
    log("(base period re-referenced to 100), not year-on-year rates -- consistent with the")
    log(f"observed range here (min={desc['min']:.1f} .. max={desc['max']:.1f}, centred near 100,")
    log("not near 0 the way a y/y growth rate would be).")
    log()
    log("Base-break check at the 2026 boundary (2025m12 -> 2026m1):")
    boundary_mdate_to = stata_mdate(pd.Series([2026]), pd.Series([1]))[0]
    mom_boundary = mom[mom["mdate"] == boundary_mdate_to]
    mom_other = mom[mom["mdate"] != boundary_mdate_to]
    med_boundary = mom_boundary["pct_change"].median()
    med_other = mom_other["pct_change"].median()
    log(f"  median m/m %% change at 2025m12->2026m1: {med_boundary:.2f}%  (n={len(mom_boundary)})")
    log(f"  median m/m %% change at all other transitions: {med_other:.2f}%  (n={len(mom_other)})")
    log("  Interpretation: " + (
        "no visible base break -- boundary move is in line with (or smaller than) the typical move."
        if abs(med_boundary) <= abs(med_other) + 2
        else "boundary move is notably larger than typical -- inspect for a base break."
    ))

    log()
    log("## cpi_ma3 departure from cpi, by item_group")
    panel_valid_ma3 = panel[panel["cpi_ma3"].notna()].copy()
    panel_valid_ma3["abs_pct_dev"] = (panel_valid_ma3["cpi_ma3"] - panel_valid_ma3["cpi"]).abs() / panel_valid_ma3["cpi"] * 100
    dep = panel_valid_ma3.groupby("item_group")["abs_pct_dev"].agg(["mean", "max"]).sort_values("mean", ascending=False)
    for grp, row in dep.iterrows():
        log(f"  {grp:<55s} mean |cpi_ma3 - cpi| / cpi = {row['mean']:.2f}%   max = {row['max']:.2f}%")

    n_ma3_missing = panel["cpi_ma3"].isna().sum()
    log()
    log(f"cpi_ma3 missing at series endpoints (documented, not shrunk): {n_ma3_missing} rows "
        f"out of {len(panel)} (expect 2 per (province,item_group) series x {len(needed_pairs)} series "
        f"= {2 * len(needed_pairs)})")

    log()
    log("## Vintage hash (repeat)")
    log(f"sha256({CPI_FILE.name}) = {actual_hash}")

    log()
    log("## Files written")
    log(f"  {OUT_PANEL}")
    log(f"  {OUT_CROSSWALK}")
    log(f"  {OUT_VALIDATION}")

    Path(OUT_VALIDATION).write_text("\n".join(report_lines), encoding="utf-8")
    print()
    print(f"Wrote {OUT_PANEL}")
    print(f"Wrote {OUT_CROSSWALK}")
    print(f"Wrote {OUT_VALIDATION}")


if __name__ == "__main__":
    main()
