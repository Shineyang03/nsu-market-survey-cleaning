from pathlib import Path
"""Are "conventional" NSUs actually conventional? (issue: conventional-unit treatment)

THE QUESTION. The conventional branch treats a unit as a standard measure -- a ganta,
a salop -- so it publishes one weight per case with no size or price dimension. But
`weighing_approach` is preloaded per (municipality, item, unit) cell, not per unit, so
the SAME unit label can be conventional in one cell and size-based or price-quantity in
another. Where that happens, "conventional" is a property of the cell's assignment, not
of the unit.

WHAT THIS SCRIPT DOES. It measures the overlap and the price-file coverage. It decides
nothing.

  Q1  in the RAW market-survey data, for each pull_nsu_unit that occurs under the
      conventional approach, does it also occur under another approach -- and is the
      overlap within the same item or only across items
  Q2  the same after harmonization, at the harmonized_nsu_unit level
  Q5  are all conventional cases, keyed on the RAW (pre-harmonization) NSU label,
      present in the price file with a recorded price
  Q5b what price data those cases carry -- how many could support a price ladder

Q3 (is the approach enumerator-chosen or preloaded) is answered from the SurveyCTO
instrument, not from data -- see the issue.

RUN
    python dofiles/90_diagnostics/scope_conventional_units.py

OUTPUTS  (outputs/tables/)
    conventional_unit_overlap.csv       per unit label: which approaches it appears
                                        under, at both the raw and harmonized level
    conventional_price_coverage.csv     per conventional case: whether the price file
                                        has a row, and whether the price is non-missing
"""
import re
import sys

import pandas as pd

BOX = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
DC = BOX + r"\Data Cleaning"
RAW = BOX + r"\NSU Market Survey Launch\data\PSPS NSU Market Survey Launch.dta"
PRICE = BOX + r"\NSU Market Survey Launch\data\NSU_prices_from_Makayla.csv"
RESTATED = DC + r"\outputs\master_rename_build\intermediate\nsu_weighings_cpi.dta"
XW = DC + r"\outputs\tables\master_nsu_rename.csv"
OUT = DC + r"\outputs\tables"

CONV = "conventional"
BRANCH = {1.0: "conventional", 2.0: "price-quantity", 3.0: "size-based"}


# The one definition of the project's string normalization, imported rather than
# copied. There used to be eleven byte-identical copies of these four functions across
# 90_diagnostics/; a fix to any one of them reached none of the others. The Stata
# counterpart is nsu_normalize in 00_shared/00_globals.do and must agree with it
# character for character -- see the module docstring.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import A, nz, ni, ng


def h(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def approach_of(v):
    """The raw file stores the approach as its full label string."""
    s = nz(v)
    if s.startswith("conventional"):
        return "conventional"
    if s.startswith("price-quantity"):
        return "price-quantity"
    if s.startswith("size-based"):
        return "size-based"
    return f"?? {v}"


def overlap_table(d, unit_col, item_col, label):
    """Which approaches each unit label appears under, and whether the overlap is
    within one item or only across items."""
    per_unit = d.groupby(unit_col).approach.agg(lambda s: sorted(set(s)))
    per_unit_item = d.groupby([unit_col, item_col]).approach.agg(lambda s: sorted(set(s)))

    conv_units = {u for u, a in per_unit.items() if CONV in a}
    mixed_units = {u for u in conv_units if len(per_unit[u]) > 1}
    # within-item overlap: the SAME item, same unit, seen under >1 approach
    mixed_unit_items = {k for k, a in per_unit_item.items()
                        if CONV in a and len(a) > 1}
    mixed_within = {k[0] for k in mixed_unit_items}

    print(f"\n{label}")
    print(f"  distinct unit labels                         {per_unit.size:>5}")
    print(f"  ...appearing under the conventional approach {len(conv_units):>5}")
    print(f"  ...of those, ALSO under another approach     {len(mixed_units):>5}"
          f"   ({100*len(mixed_units)/max(1,len(conv_units)):.0f}% of conventional labels)")
    print(f"  ...where the overlap is WITHIN THE SAME ITEM {len(mixed_within):>5}")
    print(f"  (unit, item) pairs mixing conventional with another approach:"
          f" {len(mixed_unit_items):>4}")

    rows = []
    for u in sorted(conv_units):
        apps = per_unit[u]
        wi = sorted({k[1] for k in mixed_unit_items if k[0] == u})
        rows.append({"grain": label, "unit": u, "approaches": " + ".join(apps),
                     "n_approaches": len(apps),
                     "mixed_within_item": len(wi),
                     "items_mixed_within": " | ".join(str(i)[:38] for i in wi[:4])})
    t = pd.DataFrame(rows)
    if len(t):
        print("\n  conventional labels also used under another approach, worst first:")
        show = t[t.n_approaches > 1].sort_values(
            ["mixed_within_item", "n_approaches"], ascending=False)
        print("   " + show.head(14)[["unit", "approaches", "mixed_within_item",
                                     "items_mixed_within"]]
              .to_string(index=False).replace("\n", "\n   "))
    return t


def main():
    raw = pd.read_stata(RAW, convert_categoricals=False)
    print(f"raw MS rows {len(raw):,}")
    raw["approach"] = raw.weighing_approach.map(approach_of)
    print(raw.approach.value_counts().to_string())
    raw["unit_raw"] = raw.pull_nsu_unit.map(nz)
    raw["item"] = raw.pull_item.map(ni)

    # ================================================================ Q1
    h("Q1  RAW DATA -- DOES A CONVENTIONAL UNIT LABEL ALSO APPEAR ELSEWHERE")
    print("A unit is only genuinely 'conventional' if that is a property of the unit.")
    print("Where the same label is conventional in one cell and size- or price-based in")
    print("another, the label is not the thing carrying the meaning -- the cell's")
    print("preloaded assignment is.")
    t_raw = overlap_table(raw, "unit_raw", "item", "RAW pull_nsu_unit")

    # ================================================================ Q2
    h("Q2  AFTER HARMONIZATION -- THE SAME QUESTION AT harmonized_nsu_unit")
    rest = pd.read_stata(RESTATED, convert_categoricals=False)
    rest["approach"] = rest.weighing_approach.map(
        lambda v: BRANCH.get(float(v), f"?? {v}") if pd.notna(v) else "?? missing")
    rest["unit_h"] = rest.harmonized_nsu_unit.map(nz)
    rest["item"] = rest.pull_item.map(ni)
    print(f"restated rows {len(rest):,}")
    t_h = overlap_table(rest, "unit_h", "item", "HARMONIZED harmonized_nsu_unit")
    print("\n  Harmonization can only INCREASE overlap: folding two spellings merges")
    print("  whatever approaches each carried. A label that was clean at the raw grain")
    print("  and mixed here was made mixed by the fold.")

    pd.concat([t_raw, t_h]).to_csv(OUT + r"\conventional_unit_overlap.csv",
                                   index=False, encoding="utf-8-sig")

    # ================================================================ Q5
    h("Q5  DO ALL CONVENTIONAL CASES HAVE A PRICE-FILE ROW WITH A RECORDED PRICE")
    print("Keyed on the RAW (pre-harmonization) NSU label, as asked.")
    pr = pd.read_csv(PRICE, encoding="utf-8-sig", dtype=str)
    pr["province"] = pr.province.map(ng)
    pr["pull_municipal_city"] = pr.pull_municipal_city.map(ng)
    pr["cons_name"] = pr.cons_name.map(ni)
    pr["unit_raw"] = pr.Unit_lbl.map(nz)
    pr["price"] = pd.to_numeric(pr.Price, errors="coerce")

    KEY = ["province", "pull_municipal_city", "cons_name", "unit_raw"]
    have_row = set(pr.set_index(KEY).index)
    have_price = set(pr[pr.price.notna()].set_index(KEY).index)

    cv = raw[raw.approach == CONV].copy()
    cv["province"] = cv.pull_province.map(ng)
    cv["pull_municipal_city"] = cv.pull_municipal_city.map(ng)
    cv["cons_name"] = cv.item
    cases = cv.groupby(KEY).size().rename("n_weighings").reset_index()
    cases["has_price_row"] = [tuple(r) in have_row
                              for r in cases[KEY].itertuples(index=False)]
    cases["has_price_value"] = [tuple(r) in have_price
                                for r in cases[KEY].itertuples(index=False)]

    n = len(cases)
    print(f"\n  conventional cases (raw NSU grain):        {n:>5}")
    print(f"    with a price-file row:                   {int(cases.has_price_row.sum()):>5}"
          f"   ({100*cases.has_price_row.mean():.1f}%)")
    print(f"    with a NON-MISSING price:                {int(cases.has_price_value.sum()):>5}"
          f"   ({100*cases.has_price_value.mean():.1f}%)")
    miss = cases[~cases.has_price_row]
    print(f"    with NO price-file row at all:           {len(miss):>5}")
    if len(miss):
        print("\n  uncovered conventional cases (up to 20):")
        print("   " + miss.sort_values("n_weighings", ascending=False).head(20)[
            KEY + ["n_weighings"]].to_string(index=False).replace("\n", "\n   "))
    novalue = cases[cases.has_price_row & ~cases.has_price_value]
    if len(novalue):
        print(f"\n  have a row but a MISSING price: {len(novalue)}")
        print("   " + novalue.head(10)[KEY + ["n_weighings"]]
              .to_string(index=False).replace("\n", "\n   "))

    # ---------------------------------------------------------------- Q5b
    h("Q5b  WHAT PRICE DATA THE CONVENTIONAL CASES CARRY")
    print("If a conventional case has a full quartile ladder in the price file, it")
    print("could be run through the size-based or price-quantity machinery instead of")
    print("being collapsed to a single case median. This says how many could.")
    QUART = ["mp25_price", "mp50_price", "mp75_price"]

    def comp(t):
        t = set(t)
        q = [p for p in QUART if p in t]
        bits = []
        if len(q) == 3:
            bits.append("full_triple")
        elif q:
            bits.append("partial_quartile")
        if "municipality median" in t:
            bits.append("mun_median")
        if "province median" in t:
            bits.append("prov_median")
        if "unique_mun_price" in t:
            bits.append("unique")
        return " + ".join(bits) or "none"

    pc = pr.groupby(KEY).price_type.agg(comp)
    got = cases.set_index(KEY).index.map(lambda k: pc.get(k, "none"))
    cases["price_composition"] = list(got)
    print(f"\n  price-file composition of the {len(cases):,} conventional cases:")
    print("   " + cases.price_composition.value_counts()
          .to_string().replace("\n", "\n   "))
    n_lad = int(cases.price_composition.str.contains("full_triple").sum())
    print(f"\n  carrying a FULL mp25/mp50/mp75 ladder: {n_lad}"
          f"   ({100*n_lad/max(1,len(cases)):.0f}%)")
    print("  Those could support three hetero-groups today; the conventional branch")
    print("  publishes one weight for them instead.")

    print("\n  the six high-variance (item, unit) combos from"
          " audit_implicit_assumptions.py A8:")
    HOT = ["putos", "tumpok", "bundle", "bugkos"]
    hot = cases[cases.unit_raw.isin(HOT)]
    if len(hot):
        print("   " + hot.groupby(["cons_name", "unit_raw", "price_composition"])
              .n_weighings.sum().to_string().replace("\n", "\n   "))

    cases.to_csv(OUT + r"\conventional_price_coverage.csv", index=False,
                 encoding="utf-8-sig")
    print(f"\nwrote conventional_unit_overlap.csv and conventional_price_coverage.csv")


if __name__ == "__main__":
    main()
