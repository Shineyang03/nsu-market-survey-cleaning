"""parse_validation_workbook.py -- read the returned human validation workbook.

WHAT IT DOES. Extracts the human's answers, normalises them, and writes a CSV keyed on
`image_code` -- the workbook's own join key, which survives sorting and re-sending.

THE HUMAN'S ANSWERS ARE NEVER REWRITTEN. `display_raw` holds exactly what the cell
contained; every derived column sits beside it. A ground truth that has been tidied in
place is no longer a ground truth, and the project rule is the same one that applies to
the deliverables: never overwrite a raw value with a cleaned one.

THREE THINGS THE RETURNED WORKBOOK REVEALED, all handled here rather than silently:

1. EXCEL COERCED THE READINGS TO NUMBERS. 37 of 40 answers came back as floats, so a
   display read as `0.300` is stored as `0.3`. That is the trailing-zero destruction the
   instrument warns about, and it is a defect in the WORKBOOK GENERATOR -- `image_code`
   was given a text format and `display_text` was not. It is fixed for v2.

   It is survivable here because the distinction that matters -- 0.3 against 3 against
   300 -- is preserved by the number. What is lost is literal character fidelity, so
   `display_exact_ok` records that an exact-string comparison is NOT available for these
   rows and no such comparison is attempted.

2. THE `legible` DROPDOWN DID NOT BIND. Answers came back as free text -- "Y",
   "Y (bad glare)", "Y (just about)". The closed vocabulary was not enforced. The free
   text is in fact MORE informative than the vocabulary would have been, so it is
   parsed rather than rejected: `legible_yes` and `glare_flag`.

3. THREE ROWS RECORD A PACKAGE VOLUME, NOT THE SCALE DISPLAY -- "355 mL", "800 mL". The
   reviewer stated the rule: where both a package volume and a scale reading are
   visible, prefer the volume. Those rows are flagged `reading_source == "package"` and
   are EXCLUDED from scale-reading accuracy, because the question there is what the
   DISPLAY said and these rows do not answer it. They are not discarded: for Check 1 and
   A23 the package volume may be the better datum, and excluding them from one score is
   not the same as ignoring them.

TWO MODES, MATCHING THE TWO THINGS A WORKBOOK CAN ASK.

  measure     "what does this display say?" -- the blind workbook. The answer is
              ground truth and scores the readers. Everything above describes it.

  adjudicate  "approve or reject this proposal?" -- the review workbook. The answer
              is a VERDICT, not a reading, because the reviewer saw the proposed
              value before answering. It must never be used to score a reader; an
              answer given while looking at the proposal agrees with the proposal
              for reasons that have nothing to do with the photograph.

WHAT `approve' MEANS, and it is the whole contract of adjudicate mode. The reviewer is
ruling on `photo_g' and `photo_unit' -- the resolved reading from the photograph, the
number AND its dimension (owner, 2026-10-02). Not the published value, not the ratio,
not whether the pipeline should change. So:

    approve = yes               photo_g and photo_unit stand as the workbook showed
    approve = no                `correct_value' replaces BOTH -- it carries its own
                                unit, and "45 g" against a shown "95 mL" is a ruling
                                on the dimension as much as on the number
    approve blank               UNRESOLVED. Never guessed, never defaulted to either
                                answer, and it exits non-zero so a half-reviewed
                                workbook cannot be mistaken for a finished one

A `correct_value' supplied ALONGSIDE `yes' is not a contradiction to be rejected. It is
usually a confirmation -- the reviewer wrote out the value they were approving -- and
occasionally a refinement, approving the proposal's direction while fixing its last
digit. The explicit value wins either way, and `approve_with_value' flags every such
row so the two cases stay separable.

NO VERDICT MAY BE NEGATIVE OR ZERO (owner, 2026-10-02). A mass and a volume are
non-negative; a verdict that is not is a transcription error, and it halts the parse
rather than entering a ledger that `05_manual_corrections.do' will later trust.

USAGE
    python parse_validation_workbook.py \
        --xlsx ../outputs/qc/human_validation_v1.xlsx \
        --key  ../outputs/qc/human_validation_v1_key.csv \
        --out  ../outputs/qc/human_verdicts_v1.csv

    python parse_validation_workbook.py --mode adjudicate \
        --xlsx ../outputs/qc/photo_hold_review_v2.xlsx \
        --key  ../outputs/qc/photo_hold_review_v2_key.csv \
        --shown photo_g \
        --out  ../outputs/qc/hold_verdicts_v2.csv
"""

from __future__ import annotations

import argparse
import os
import re
import sys

import pandas as pd
from openpyxl import load_workbook

# A reading that names a volume unit is a package label, not a scale display. These
# scales print no unit at all on the rows we read, so a unit in the answer can only have
# come from packaging.
UNIT_RE = re.compile(r"\b(m\s?l|ml|millilitre|milliliter|litre|liter|l|g|kg|oz|lb)\b",
                     re.IGNORECASE)
NUM_RE = re.compile(r"[-+]?\d*\.?\d+")
GLARE_RE = re.compile(r"glare|blur|dark|reflect|just about|not sure|unsure|hard to",
                      re.IGNORECASE)


def parse_answer(v):
    """Return (raw_string, numeric_value, unit_named, exact_available)."""
    if v is None:
        return "", None, None, False
    if isinstance(v, (int, float)):
        # Excel coerced it. The number is intact; the literal characters are not.
        return repr(v), float(v), None, False
    s = str(v).strip()
    if not s:
        return "", None, None, False
    unit = None
    m = UNIT_RE.search(s)
    if m:
        unit = m.group(0).replace(" ", "").lower()
    n = NUM_RE.search(s.replace(",", ""))
    val = float(n.group(0)) if n else None
    # A string answer preserves what was typed, so an exact comparison is meaningful.
    return s, val, unit, True


# A verdict cell: a number, then a unit. "45 g", "750 mL", " 45 g". The unit is part of
# the ruling, so a bare number is accepted but recorded as carrying no dimension.
VERDICT_RE = re.compile(r"^\s*([0-9]*\.?[0-9]+)\s*(g|gram[s]?|kg|ml|mls|l|litre[s]?|liter[s]?)?\s*$",
                        re.IGNORECASE)


def parse_verdict(v):
    """Return (raw, value_in_base, unit, ok). Base is grams for mass, mL for volume."""
    if v is None:
        return "", None, None, True          # blank is not malformed; it is unanswered
    if isinstance(v, (int, float)):
        return repr(v), float(v), None, True
    s = str(v).strip()
    if not s:
        return "", None, None, True
    m = VERDICT_RE.match(s)
    if not m:
        return s, None, None, False
    val = float(m.group(1))
    u = (m.group(2) or "").lower()
    if u in ("kg",):
        val, unit = val * 1000, "g"
    elif u in ("l", "litre", "litres", "liter", "liters"):
        val, unit = val * 1000, "mL"
    elif u in ("ml", "mls"):
        unit = "mL"
    elif u in ("g", "gram", "grams"):
        unit = "g"
    else:
        unit = None                          # a bare number: dimension not ruled on
    return s, val, unit, True


def run_adjudicate(args) -> int:
    """Read a review workbook: approve / correct_value / notes, keyed on image_code."""
    wb = load_workbook(args.xlsx, data_only=True)
    if args.sheet not in wb.sheetnames:
        print(f"sheet '{args.sheet}' not in {wb.sheetnames}", file=sys.stderr)
        return 2
    ws = wb[args.sheet]
    hdr = [c.value for c in ws[1]]

    need = {"image_code", "approve", "correct_value", args.shown, "photo_unit"}
    missing = need - set(hdr)
    if missing:
        print(f"workbook is missing columns: {sorted(missing)}", file=sys.stderr)
        return 2
    col = {name: i + 1 for i, name in enumerate(hdr) if name}

    rows, malformed, nonpositive = [], [], []
    for r in range(2, ws.max_row + 1):
        code = ws.cell(row=r, column=col["image_code"]).value
        if code in (None, ""):
            continue
        code = str(code).strip()
        appr = str(ws.cell(row=r, column=col["approve"]).value or "").strip().lower()
        raw, val, unit, ok = parse_verdict(
            ws.cell(row=r, column=col["correct_value"]).value)
        shown_v = ws.cell(row=r, column=col[args.shown]).value
        shown_u = ws.cell(row=r, column=col["photo_unit"]).value
        notes = str(ws.cell(row=r, column=col["notes"]).value or "").strip() \
            if "notes" in col else ""

        if not ok:
            malformed.append((code, raw))

        # The contract. An explicit value always wins; absent one, `yes' adopts what
        # was shown and `no' has ruled against a value without supplying its
        # replacement, which is a hole and is reported as one.
        if val is not None:
            v_final, u_final, basis = val, (unit or shown_u), "correct_value"
        elif appr == "yes":
            v_final, u_final, basis = (
                float(shown_v) if shown_v not in (None, "") else None, shown_u, "approved as shown")
        else:
            v_final, u_final, basis = None, None, ("rejected, no replacement"
                                                  if appr == "no" else "unanswered")

        if v_final is not None and v_final <= 0:
            nonpositive.append((code, v_final))

        rows.append({
            "image_code": code,
            "approve": appr or "",
            "approve_yes": 1 if appr == "yes" else (0 if appr == "no" else None),
            "correct_raw": raw,
            "shown_value": shown_v,
            "shown_unit": shown_u,
            "verdict_value": v_final,
            "verdict_unit": u_final,
            "verdict_basis": basis,
            # Approved AND written out: a confirmation, unless the numbers differ.
            "approve_with_value": int(appr == "yes" and val is not None),
            "value_moved": int(
                appr == "yes" and val is not None and shown_v not in (None, "")
                and float(shown_v) != val),
            "notes": notes,
        })

    df = pd.DataFrame(rows)
    key = pd.read_csv(args.key, dtype={"image_code": str})
    df = df.merge(key[["image_code", "id", "filename"]], on="image_code", how="left")

    unanswered = df[df.approve_yes.isna()]
    unmatched = df[df.id.isna()]

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    df.to_csv(args.out, index=False)

    print(f"rows in workbook           {len(df)}")
    print(f"  approved                 {int((df.approve == 'yes').sum())}")
    print(f"  rejected                 {int((df.approve == 'no').sum())}")
    print(f"  UNANSWERED               {len(unanswered)}")
    print(f"a verdict value resolved   {int(df.verdict_value.notna().sum())}")
    print(f"  approved with a value    {int(df.approve_with_value.sum())}")
    print(f"    ... and it DIFFERS     {int(df.value_moved.sum())}")
    print()
    print("verdict_unit:")
    print(df.verdict_unit.value_counts(dropna=False).to_string())
    print(f"\nwrote {args.out}")

    fatal = False
    if malformed:
        print(f"\nMALFORMED correct_value on {len(malformed)} row(s):", file=sys.stderr)
        for c, raw in malformed[:20]:
            print(f"    {c}  {raw!r}", file=sys.stderr)
        fatal = True
    if nonpositive:
        print(f"\nNON-POSITIVE verdict on {len(nonpositive)} row(s) -- a mass or a "
              f"volume cannot be <= 0:", file=sys.stderr)
        for c, v in nonpositive[:20]:
            print(f"    {c}  {v}", file=sys.stderr)
        fatal = True
    if len(unmatched):
        print(f"\n{len(unmatched)} row(s) match no image code in the key:", file=sys.stderr)
        print("    " + ", ".join(unmatched.image_code.tolist()[:20]), file=sys.stderr)
        fatal = True
    if len(unanswered):
        print(f"\n{len(unanswered)} row(s) have no approve verdict. They are NOT "
              f"guessed; nothing downstream may treat this workbook as complete:",
              file=sys.stderr)
        print("    " + ", ".join(unanswered.image_code.tolist()[:20]), file=sys.stderr)
        fatal = True
    rejected_empty = df[(df.approve == "no") & df.verdict_value.isna()]
    if len(rejected_empty):
        print(f"\n{len(rejected_empty)} row(s) rejected with no replacement value:",
              file=sys.stderr)
        print("    " + ", ".join(rejected_empty.image_code.tolist()[:20]), file=sys.stderr)
        fatal = True

    if fatal:
        print("\nThe CSV was still written so the answered rows are not lost, but it "
              "is INCOMPLETE -- resolve the rows above before applying it.",
              file=sys.stderr)
        return 1
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--xlsx", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--sheet", default="read the display")
    ap.add_argument("--mode", choices=["measure", "adjudicate"], default="measure",
                    help="measure: a blind reading, usable as ground truth. "
                         "adjudicate: a verdict on a shown proposal, NEVER ground truth.")
    ap.add_argument("--shown", default="photo_g",
                    help="adjudicate mode: the column holding the value the reviewer "
                         "was ruling on -- photo_g in the hold workbook, "
                         "proposed_value in the override workbook.")
    args = ap.parse_args(argv)

    if args.mode == "adjudicate":
        return run_adjudicate(args)

    wb = load_workbook(args.xlsx, data_only=True)
    if args.sheet not in wb.sheetnames:
        print(f"sheet '{args.sheet}' not in {wb.sheetnames}", file=sys.stderr)
        return 2
    ws = wb[args.sheet]

    hdr = [c.value for c in ws[1]]
    need = {"image_code", "display_text", "legible", "scale_present", "notes"}
    missing = need - set(hdr)
    if missing:
        print(f"workbook is missing columns: {sorted(missing)}", file=sys.stderr)
        return 2
    col = {name: i + 1 for i, name in enumerate(hdr)}

    rows = []
    for r in range(2, ws.max_row + 1):
        code = ws.cell(row=r, column=col["image_code"]).value
        if code in (None, ""):
            continue
        raw, val, unit, exact = parse_answer(
            ws.cell(row=r, column=col["display_text"]).value)
        leg = str(ws.cell(row=r, column=col["legible"]).value or "").strip()
        scp = str(ws.cell(row=r, column=col["scale_present"]).value or "").strip()
        notes = ws.cell(row=r, column=col["notes"]).value or ""

        blob = f"{leg} {notes}"
        rows.append({
            "image_code": str(code).strip(),
            "h_display_raw": raw,
            "h_display_val": val,
            "h_unit_named": unit,
            "h_exact_available": int(exact),
            # A package volume answers a different question from a scale display.
            "reading_source": "package" if unit in ("ml", "l", "litre", "liter") else "scale",
            "h_legible_raw": leg,
            "h_legible_yes": int(leg.upper().startswith("Y")),
            "h_glare_flag": int(bool(GLARE_RE.search(blob))),
            "h_scale_present": int(scp.lower().startswith("y")),
            "h_notes": str(notes).strip(),
        })

    df = pd.DataFrame(rows)

    key = pd.read_csv(args.key, dtype={"image_code": str})
    df = df.merge(key[["image_code", "id", "filename"]], on="image_code", how="left")

    unmatched = df.id.isna().sum()
    if unmatched:
        print(f"WARNING {unmatched} answered row(s) match no image code in the key",
              file=sys.stderr)
        print(df[df.id.isna()].image_code.tolist(), file=sys.stderr)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    df.to_csv(args.out, index=False)

    print(f"answered rows              {len(df)}")
    print(f"matched to an id           {int(df.id.notna().sum())}")
    print(f"scale present (human)      {int(df.h_scale_present.sum())}")
    print(f"legible (human)            {int(df.h_legible_yes.sum())}")
    print(f"flagged glare/uncertainty  {int(df.h_glare_flag.sum())}")
    print()
    print("reading_source:")
    print(df.reading_source.value_counts().to_string())
    print()
    print(f"exact-string comparison available on {int(df.h_exact_available.sum())} "
          f"of {len(df)} rows")
    print("  (Excel coerced the rest to numbers, dropping trailing zeros --")
    print("   the numeric comparison is unaffected; see the header.)")
    print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
