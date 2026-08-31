"""THE string normalization for this project, on the Python side. One definition.

WHY THIS FILE EXISTS. Every join in this pipeline is a string join: province,
municipality, item and raw NSU label are matched across the market survey, the price
file, the crosswalk and the PSPS consumption module, none of which agree on case,
spacing or accents. So a normalizer is not a convenience here -- it decides which rows
find each other, and two normalizers that disagree by one character silently drop rows.

There were thirteen definitions of it. Eleven were byte-identical copies scattered
through 90_diagnostics/, agreeing on every input, and the cost was not disagreement but
that a fix to one propagated to none of the others. One WAS divergent and could be
wrong on real data. This file is the single definition they all now import.

THE STATA COUNTERPART IS `nsu_normalize` IN 00_globals.do, AND THE TWO MUST AGREE
CHARACTER FOR CHARACTER. master_nsu_rename.csv is built by the Python side and joined
by the Stata side, so any drift between them loses rows from that join and nothing
reports it. If you change a rule here, change it there in the same commit.

    Python (here)         Stata (00_globals.do)
    A()                   ustrto(s, "ascii", 2)
    nz()  lower           ustrtrim(ustrlower(...)) + collapse \\s+
    ng()  upper           ustrtrim(ustrupper(...)) + collapse \\s+
    ni()  restaurant      replace ... if strpos(item, "restaurant") > 0

NON-ASCII IS DROPPED, NOT TRANSLITERATED, and this is deliberate. A clean n-tilde and a
mojibaked one have to collapse to the SAME string, and they do only if both LOSE the
character: DUEÑAS -> DUEAS and the mojibaked variant -> DUEAS. Do not "improve" this to
NFKD-decompose. NFKD maps a clean DUEÑAS to DUENAS and a mojibaked one to something
else, so the two stop matching and the join quietly loses those rows.

WHAT EACH FUNCTION IS FOR.

    A(s)    drop every non-ASCII byte. The primitive the other three build on.
    nz(s)   the general normalizer: ASCII, lowercased, trimmed, whitespace collapsed.
            Use for NSU unit labels and anything else without a special rule.
    ni(s)   nz() plus the prepped-food collapse. The item string for restaurant/cafe
            purchases differs across datasets only by an accent and some wording, so
            every spelling of it folds to one canonical label.
    ng(s)   nz() but UPPERCASED. Use for province and municipality, which are held
            upper-case throughout this project.

Choosing the wrong one of nz/ng is a silent no-match, not an error: ng("iloilo") is
"ILOILO" and nz("ILOILO") is "iloilo", and neither ever equals the other.

USE IT LIKE THIS, from anywhere under dofiles/:

    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "00_shared"))
    from nsu_normalize import A, nz, ni, ng

The sys.path line is needed because the pipeline steps are numbered
(01_build_crosswalk.py and friends), and a module whose name starts with a digit cannot
be imported. This file is deliberately NOT numbered: it is a shared definition, not a
step, and nothing runs it.
"""
import re

# The prepped-food item label. Spelled once, here, because it is a literal that has to
# match byte for byte between the Python and Stata sides.
PREPPED_FOOD = "drinks at restaurant, hotel, cafe, or kiosk"


def A(s):
    """Drop every non-ASCII byte. Never transliterate -- see the module docstring."""
    return str(s).encode("ascii", "ignore").decode("ascii")


def nz(s):
    """ASCII, lower-cased, trimmed, internal whitespace collapsed to single spaces."""
    return re.sub(r"\s+", " ", A(s).lower().strip())


def ni(s):
    """nz(), plus folding every spelling of the prepped-food item onto one label."""
    s = nz(s)
    return PREPPED_FOOD if "restaurant" in s else s


def ng(s):
    """nz() but UPPER-cased. For province and municipality."""
    return re.sub(r"\s+", " ", A(s).strip().upper())
