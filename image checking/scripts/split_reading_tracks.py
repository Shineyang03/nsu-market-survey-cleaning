"""split_reading_tracks.py -- divide the unread photographs into the two reading tracks.

A photograph linked to a weighing is read in one of two ways, and which one depends on
whether `rectify_display.py` located a scale display in it:

    display found  ->  CROP TRACK.  Read the rectified display crop under PROMPT_CROP.md
                       (`crop-v1.0`). The crop shows the display and nothing else, so it
                       supports the weight reading and no other field.

    no display     ->  PHOTO TRACK. Read the whole photograph under PROMPT.md (`v1.0`),
                       which asks for the packaging label as well as the display.

THE SECOND TRACK IS NOT "PHOTOGRAPHS WITHOUT A DISPLAY". The cropper finds a display in
61% of photographs, and the shortfall is a mix of two quite different things: weighings
whose number really did come off a package label rather than a scale, and weighings where
a display is plainly in frame but feature matching failed on it. Only a reading tells
them apart, which is why the photo-track instrument asks for `display_text` too. Treating
"no crop" as "no display" would answer Check 1 -- was this weight read off packaging or
off a scale? -- with an artefact of the detector instead of evidence.

WHAT COUNTS AS ALREADY READ is an image code present in `outputs/qc/photo_readings_master.csv`.
Readings made under either instrument count, because the question here is only "does this
photograph still need a reader", not which instrument produced the existing answer.

OUTPUTS feed `make_read_batches.py`, which assigns these ids to numbered reading batches.

USAGE
    python split_reading_tracks.py
"""

from __future__ import annotations

import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "outputs"))

PER_SHEET = {"crop": 17, "photo": 9}


def main() -> int:
    with open(os.path.join(OUT, "bridge", "photo_id_bridge.csv"),
              encoding="utf-8-sig") as fh:
        bridge = list(csv.DictReader(fh))
    for r in bridge:
        r["image_code"] = r["filename"].replace(".jpg", "")

    read = set()
    with open(os.path.join(OUT, "qc", "photo_readings_master.csv"),
              encoding="utf-8-sig") as fh:
        for r in csv.DictReader(fh):
            if r.get("image_code"):
                read.add(r["image_code"])

    status: dict[str, str] = {}
    spath = os.path.join(OUT, "rect_all_status.csv")
    if os.path.exists(spath):
        with open(spath, encoding="utf-8-sig") as fh:
            for r in csv.DictReader(fh):
                status[r["image_code"]] = r["status"]

    unread = [r for r in bridge if r["image_code"] not in read]
    cropped = [r for r in unread if status.get(r["image_code"], "").startswith("ok")]
    nocrop = [r for r in unread
              if r["image_code"] in status
              and not status[r["image_code"]].startswith("ok")]
    pending = [r for r in unread if r["image_code"] not in status]

    print(f"photographs linked to a weighing ........ {len(bridge)}")
    print(f"already read into the master ............ {len(read)}")
    print(f"UNREAD .................................. {len(unread)}")
    print()
    print(f"  crop track  (display located) ......... {len(cropped):>6}")
    print(f"  photo track (no display located) ...... {len(nocrop):>6}")
    print(f"  not yet cropped ....................... {len(pending):>6}")
    print()
    for name, rows, track in (("read_crop_ids.csv", cropped, "crop"),
                              ("read_photo_ids.csv", nocrop, "photo")):
        path = os.path.join(OUT, "tables", name)
        with open(path, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["id"])
            for r in rows:
                w.writerow([r["id"]])
        sheets = -(-len(rows) // PER_SHEET[track])
        print(f"  wrote tables/{name}  ({len(rows)} ids, "
              f"{sheets} sheets at {PER_SHEET[track]}/sheet)")

    if pending:
        print(f"\n{len(pending)} photographs have no cropper verdict yet; rerun this "
              f"after rectify_display.py finishes, or they fall into neither track.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
