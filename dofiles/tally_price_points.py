"""How many price points (hetero-groups) does each prov x mun x item x nsu case have?

Reads NSU_prices_from_Makayla.csv and reports the hetero-group availability that Limit 2
of the conversion-factor ladder depends on (docs/conversion_factor_methodology.md,
"Degrading gracefully").

WHY THIS IS A SCRIPT AND NOT A ONE-LINER: an earlier ad-hoc version of this tally
classified each case with an if/elif chain over price_type that returned on the
first match, so a case carrying BOTH 'province median' and 'unique_mun_price' was
labelled "unique municipal price only", and a hetero-group() helper written as
    return q if q else 1          # q = count of mp25/mp50/mp75 labels
could not return 2 for any case. That produced the false conclusion "no case has
exactly two price points" and a 67.5% single-group share. The real figures are
below. Count distinct price LEVELS and enumerate label COMBINATIONS -- never
first-match-wins over a set.

Definitions used:
  hetero-group  = a distinct price level that can be paired with a size.
          - a full mp25/mp50/mp75 triple gives 3 hetero-groups
          - the observed municipal price level(s) give 1-2 hetero-groups
          - a lone municipality or province median gives 1 hetero-group
  The province median accompanying a municipal price is treated as a FALLBACK
  REFERENCE, not a second hetero-group: the two are estimates of the same central
  tendency at different geographies, so pairing them as small/large would be
  meaningless. The alternative reading (count every distinct level as a hetero-group) is
  also reported so the choice is visible.
"""
import csv, collections
from pathlib import Path

SRC = (Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel"
             r"\14 NSU Market Survey\NSU Market Survey Launch\data")
       / "NSU_prices_from_Makayla.csv")
QUARTILE = {"mp25_price", "mp50_price", "mp75_price"}


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def load():
    cells = collections.defaultdict(list)
    with open(SRC, encoding="utf-8-sig") as fh:
        for r in csv.DictReader(fh):
            key = (r["province"], r["pull_municipal_city"],
                   r["cons_name"].strip().lower(), r["Unit_lbl"].strip().lower())
            cells[key].append(r)
    return cells


def groups_reference_reading(rows):
    """Municipal price = hetero-group; an accompanying province median = reference."""
    types = {r["price_type"] for r in rows}
    q = len(QUARTILE & types)
    if q:
        return q
    mun = {num(r["Price"]) for r in rows if r["price_type"] == "unique_mun_price"}
    mun.discard(None)
    return len(mun) if mun else 1


def groups_level_reading(rows):
    """Every distinct price level counts as a hetero-group."""
    lv = {num(r["Price"]) for r in rows}
    lv.discard(None)
    return len(lv) or 1


def show(title, counter, total):
    print(f"\n=== {title} ===")
    for k in sorted(counter):
        print(f"  {k} hetero-group(s): {counter[k]:>5}  {100 * counter[k] / total:>5.1f}%")


def main():
    cells = load()
    total = len(cells)
    print(f"price-file cases (prov x mun x item x raw nsu): {total}")

    print("\n=== price_type combinations present ===")
    combos = collections.Counter(
        " + ".join(sorted({r["price_type"] for r in rows})) for rows in cells.values())
    for combo, n in combos.most_common():
        print(f"  {n:>5}  {100 * n / total:>5.1f}%   {combo}")

    show("hetero-group count -- province median as REFERENCE (preferred)",
         collections.Counter(groups_reference_reading(r) for r in cells.values()), total)
    show("hetero-group count -- every distinct price level a hetero-group (alternative)",
         collections.Counter(groups_level_reading(r) for r in cells.values()), total)

    # the two-label group, and whether it respects the >P20 rule it was built on
    tgt = {k: v for k, v in cells.items()
           if {r["price_type"] for r in v} == {"province median", "unique_mun_price"}}
    print(f"\n=== the 'province median + unique_mun_price' group: {len(tgt)} cases ===")
    lv = collections.Counter(
        len({num(r["Price"]) for r in v if r["price_type"] == "unique_mun_price"} - {None})
        for v in tgt.values())
    for k in sorted(lv):
        print(f"  {k} distinct municipal price level(s): {lv[k]}")

    gaps = []
    for v in tgt.values():
        mun = {num(r["Price"]) for r in v if r["price_type"] == "unique_mun_price"} - {None}
        pro = [num(r["Price"]) for r in v if r["price_type"] == "province median"]
        pro = [p for p in pro if p is not None]
        if mun and pro:
            gaps.append(min(abs(m - pro[0]) for m in mun))
    gaps.sort()
    if gaps:
        print(f"  |nearest municipal - province median|: min {gaps[0]:.0f}  "
              f"median {gaps[len(gaps) // 2]:.0f}  max {gaps[-1]:.0f}")
        tight = sum(1 for g in gaps if g <= 20)
        print(f"  within P20 -- the stated protocol would have collapsed these to "
              f"province median only: {tight} of {len(gaps)}")


if __name__ == "__main__":
    main()
