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

THE CELL KEY IS THE PROJECT NORMALIZER, AND ON THIS PRICE FILE THAT CHANGES NOTHING.
Every figure below is a count of cells, so the figures are only as good as the rule that
decides which rows share a cell. That rule is `nsu_normalize` (00_shared), the same one
the crosswalk and the do-files join on. Switching this key onto it leaves all of them
where they were -- 2,950 cases, 350 in the 'province median + unique_mun_price' group,
38 of those inside PHP 20 -- because the three spellings the price file carries that the
normalizer folds and a bare strip/lower does not are each isolated: DUENAS is the only
non-ASCII municipality and no other spelling of it exists; one item contains
"restaurant", so the prepped-food collapse has nothing to merge; and the one pair of
raw NSU labels that differ only by internal whitespace, 'Ice Cream in cone' and
'ice cream  in cone', sit in different municipalities (POTOTAN and LEON) and so were
never one cell to begin with. The exposure is real and unguarded -- a second spelling of
any of the three would split one cell in two and move these counts -- but it is latent,
not active, so no number here has ever been wrong on this account.

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
import sys
from pathlib import Path

# The one definition of the project's string normalization, imported rather than copied.
# The cell key below is the grain every figure in this file is counted at, so it has to
# fold spellings exactly the way the rest of the pipeline does: province and
# municipality UPPER-cased (ng), item through the prepped-food collapse (ni), raw NSU
# label lower-cased (nz), all four with non-ASCII DROPPED rather than transliterated.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
from nsu_normalize import nz, ni, ng

SRC = (Path(__file__).resolve().parents[2] / "inputs"
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
            key = (ng(r["province"]), ng(r["pull_municipal_city"]),
                   ni(r["cons_name"]), nz(r["Unit_lbl"]))
            cells[key].append(r)
    return cells


def groups_reference_reading(rows):
    """Municipal price = hetero-group; an accompanying province median = reference.

    THIS IS ONE OF TWO READINGS THIS SCRIPT REPORTS, NOT THE PROJECT'S RULE. The
    `if q: return q' below is the "quartiles take precedence" convention: where any
    quartile exists in a case, the municipal prices are ignored entirely. Its
    justification covers one pairing -- a province median accompanying a thin municipal
    observation estimates the same central tendency at a different geography, so it is a
    fallback reference rather than a second hetero-group. Generalising it to every case
    was never ratified, which is why issue #27 item 4 flagged it.

    IT IS NOT WHAT OUTCOME 2 DOES. Issue #21 section 2 settled that: price points are
    merged within P20 on the peso VALUE, not on the rung label, so an mp25 of one
    spelling can merge with an mp50 of another, and the pooled weights are cut into as
    many parts as there are surviving points. Quartile precedence plays no part in it.

    Both readings are printed side by side deliberately. Reporting one number would be
    asserting a convention the project has not adopted.
    """
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
