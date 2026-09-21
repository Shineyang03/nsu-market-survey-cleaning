"""make_contact_sheets.py -- tile field photographs into blinded contact sheets.

WHY THIS EXISTS. The photograph checks need thousands of images classified ("is there
a scale in this picture?"). Read one at a time that is thousands of round trips; tiled
nine to a sheet it is a few hundred. The sheets are the throughput mechanism, and the
manifest is what makes the reading reproducible afterwards.

WHY IT IS PYTHON. Composing a JPEG mosaic is one of the three things the project's
CLAUDE.md names as outside Stata's reach (image I/O). The population being drawn from
is chosen in Stata and arrives here as a CSV of ids; this script chooses nothing about
which weighings matter.

THE BLIND SPLIT IS ENFORCED HERE, and this is the whole point of the file.

A sheet carries ONLY a sequence number. It never carries the id, the typed weight, the
unit tick, or the published value. A reader who sees "typed 0.8, published 800" before
looking at the display is being asked to confirm a number rather than read one, and
will tend to confirm it -- which would make the check validate the pipeline because it
was told what the pipeline said. The mapping from sequence number back to id is written
to a SEPARATE manifest file, joined only after the readings are recorded.

That is also why the bridge carries raw_weight and this script drops it: withholding
the column upstream would make the bridge less useful to every other consumer, so the
blinding belongs at the point of presentation instead.

SAMPLES ARE SEEDED. --seed is recorded in the manifest, so a second session drawing the
same population with the same seed gets the same rows, per the handover brief's
requirement that spot samples be reproducible.

THE DOWNSCALED CACHE GOES TO LOCAL DISK, never back into Box. The picture folder is
~30 GB inside a sync drive inside a git repo; writing 11,449 derived files beside it is
the failure mode the project's CLAUDE.md warns about twice.

USAGE
    python make_contact_sheets.py --n 50 --seed 20260919 \
        --item "Cabbage|Carrot|Chicken|Fresh Fish|Camote" \
        --out-tag ocr_test

    python make_contact_sheets.py --ids targets.csv --out-tag check1_flat
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys

import pandas as pd
from PIL import Image, ImageDraw, ImageOps

# Paths are derived from this file's location so the script runs from anywhere.
HERE = os.path.dirname(os.path.abspath(__file__))
IMGCHK = os.path.dirname(HERE)
BRIDGE = os.path.join(IMGCHK, "outputs", "bridge", "photo_id_bridge.csv")
SHEETDIR = os.path.join(IMGCHK, "outputs", "sheets")

# Local, NOT Box. See the header.
CACHE = os.path.join(
    os.path.expanduser("~"), "AppData", "Local", "nsu_photo_cache"
)


def file_sha256(path: str, nbytes: int = 1 << 20) -> str:
    """Hash the first nbytes of a file.

    A verdict row records this so that a changed image invalidates its verdict
    rather than silently keeping a reading of a picture that is no longer there.
    Only the head is hashed: these JPEGs are zero-padded to a 2/4/8 MiB boundary
    after their EOI marker, so the tail carries no information and hashing 30 GB
    to learn nothing would be the slowest possible way to be rigorous.
    """
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read(nbytes))
    return h.hexdigest()[:16]


def load_photo(path: str, cell: int) -> Image.Image:
    """Open, correct orientation, and downscale one field photograph.

    EXIF transpose is not optional. These were taken on phones held every which
    way; without it a third of the sheet arrives rotated and a scale display
    reads sideways.
    """
    im = Image.open(path)
    im = ImageOps.exif_transpose(im)
    im = im.convert("RGB")
    im.thumbnail((cell, cell), Image.LANCZOS)
    return im


def cached_photo(path: str, cell: int) -> Image.Image:
    """load_photo, memoised on local disk.

    Box streams these on demand, so the second read of an image costs as much as
    the first. Pass 2 re-reads a subset of pass 1, which is what makes the cache
    worth its complexity.
    """
    os.makedirs(CACHE, exist_ok=True)
    key = f"{os.path.basename(path)}.{cell}.jpg"
    cpath = os.path.join(CACHE, key)
    if os.path.exists(cpath):
        try:
            return Image.open(cpath).convert("RGB")
        except OSError:
            pass  # corrupt cache entry: fall through and rebuild it
    im = load_photo(path, cell)
    im.save(cpath, quality=88)
    return im


def prefetch(paths, cell, workers=12):
    """Warm the cache in parallel before any sheet is built.

    THE BOTTLENECK IS THE NETWORK, NOT THE CPU. The photographs live on a streamed
    Box drive, so each one is fetched over the wire on first access -- about 1.5
    seconds for a 2-4 MB JPEG. Building 592 sheets sequentially measured at 10
    sheets a minute, which is roughly 40 images a minute, and essentially all of
    that was waiting.

    Waiting parallelises. A dozen threads fetch a dozen images at once, and because
    `cached_photo` writes each decoded thumbnail to local disk, the sequential pass
    that follows reads everything from there instead of from Box.

    The real fix is upstream and belongs to whoever runs this: pin the picture
    folder to "Available offline" first. The project's CLAUDE.md says so for Stata
    and the reason is identical here. This makes an unpinned folder tolerable; it
    does not make it fast.

    Failures are swallowed on purpose. A prefetch is an optimisation, and an image
    that cannot be fetched here will raise again in build_sheet, where there is a
    tile to mark UNREADABLE and a manifest row to record it.
    """
    from concurrent.futures import ThreadPoolExecutor

    done = 0
    total = len(paths)
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(cached_photo, p, cell) for p in paths]
        for f in futs:
            try:
                f.result()
            except Exception:
                pass
            done += 1
            if done % 200 == 0 or done == total:
                print(f"  prefetched {done}/{total}", flush=True)


def build_sheet(rows, cell, cols, label_h):
    """Compose one grid image. Returns (image, [(seq, cell_index), ...])."""
    n = len(rows)
    grid_rows = (n + cols - 1) // cols
    W = cols * cell
    H = grid_rows * (cell + label_h)
    sheet = Image.new("RGB", (W, H), (245, 245, 245))
    draw = ImageDraw.Draw(sheet)
    placed = []

    for i, r in enumerate(rows):
        gx, gy = i % cols, i // cols
        x0 = gx * cell
        y0 = gy * (cell + label_h)
        try:
            im = cached_photo(r["photo_path"], cell)
        except Exception as exc:  # a missing or unreadable file must not kill a sheet
            draw.rectangle([x0, y0 + label_h, x0 + cell, y0 + cell + label_h],
                           fill=(220, 220, 220))
            draw.text((x0 + 8, y0 + label_h + 8), f"UNREADABLE\n{exc}",
                      fill=(150, 0, 0))
            placed.append((r["seq"], i, "unreadable"))
            continue

        # centre the thumbnail in its cell
        ox = x0 + (cell - im.width) // 2
        oy = y0 + label_h + (cell - im.height) // 2
        sheet.paste(im, (ox, oy))

        # THE ONLY TEXT ON THE SHEET. A sequence number, nothing else.
        draw.rectangle([x0, y0, x0 + cell, y0 + label_h], fill=(20, 20, 20))
        draw.text((x0 + 6, y0 + 4), f"#{r['seq']:04d}", fill=(255, 255, 255))
        draw.rectangle([x0, y0, x0 + cell, y0 + cell + label_h],
                       outline=(120, 120, 120), width=2)
        placed.append((r["seq"], i, "ok"))

    return sheet, placed


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out-tag", required=True,
                    help="names the sheet folder and the manifest")
    ap.add_argument("--ids", default=None,
                    help="CSV with an 'id' column: the target list to draw from. "
                         "Omit to draw from the whole bridge.")
    ap.add_argument("--item", default=None,
                    help="regex on pull_item, applied before sampling")
    ap.add_argument("--obs-type", default=None, help="regex on obs_type")
    ap.add_argument("--n", type=int, default=None,
                    help="sample size. Omit to take every row.")
    ap.add_argument("--seed", type=int, default=20260919,
                    help="recorded in the manifest so the draw reproduces")
    ap.add_argument("--shuffle", action="store_true",
                    help="seeded shuffle after selection, so sheets do not cluster "
                         "by item or stratum")
    ap.add_argument("--workers", type=int, default=12,
                    help="threads used to prefetch images over the network. "
                         "1 disables prefetching.")
    ap.add_argument("--cell", type=int, default=500, help="px per tile")
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--per-sheet", type=int, default=9)
    args = ap.parse_args(argv)

    if not os.path.exists(BRIDGE):
        print(f"bridge not found: {BRIDGE}\nRun 01_photo_bridge.do first.",
              file=sys.stderr)
        return 2

    df = pd.read_csv(BRIDGE)
    n_all = len(df)

    if args.ids:
        want = pd.read_csv(args.ids)
        if "id" not in want.columns:
            print(f"{args.ids} has no 'id' column", file=sys.stderr)
            return 2
        before = len(df)
        df = df[df.id.isin(want.id)]
        print(f"target list {args.ids}: {len(want)} ids, {len(df)} matched in bridge")
        if len(df) < len(want.id.unique()):
            missing = len(want.id.unique()) - len(df)
            print(f"  NOTE {missing} target id(s) have no usable photograph")
        del before
    if args.item:
        df = df[df.pull_item.str.contains(args.item, case=False, regex=True, na=False)]
    if args.obs_type:
        df = df[df.obs_type.str.contains(args.obs_type, case=False, regex=True, na=False)]

    if df.empty:
        print("no rows selected", file=sys.stderr)
        return 2

    # Sort before sampling. pandas' sample walks the frame in its current order, so
    # an unsorted input makes the seed meaningless -- the same seed on a differently
    # ordered frame draws different rows.
    df = df.sort_values("id").reset_index(drop=True)
    if args.n and args.n < len(df):
        df = df.sample(n=args.n, random_state=args.seed).sort_values("id")

    if args.shuffle:
        # Seeded shuffle, so sheets do not cluster by item or stratum.
        # `id` is assigned on a content key beginning with province and municipality,
        # so ordering by it puts all of one market's cabbages on one sheet. That is a
        # reading hazard rather than a blinding one: a reader who has just read four
        # cabbages is primed for a fifth. Seeded, so the draw still reproduces.
        df = df.sample(frac=1.0, random_state=args.seed)

    df = df.reset_index(drop=True)
    df["seq"] = range(1, len(df) + 1)

    outdir = os.path.join(SHEETDIR, args.out_tag)
    os.makedirs(outdir, exist_ok=True)

    if args.workers > 1:
        print(f"prefetching {len(df)} images with {args.workers} threads...")
        prefetch(df.photo_path.tolist(), args.cell, workers=args.workers)

    manifest = []
    sheets = []
    label_h = 22
    for s0 in range(0, len(df), args.per_sheet):
        chunk = df.iloc[s0:s0 + args.per_sheet].to_dict("records")
        sheet_no = s0 // args.per_sheet + 1
        sheet, placed = build_sheet(chunk, args.cell, args.cols, label_h)
        spath = os.path.join(outdir, f"sheet_{sheet_no:03d}.jpg")
        sheet.save(spath, quality=90)
        sheets.append(spath)
        for (seq, cellidx, status), r in zip(placed, chunk):
            manifest.append({
                "seq": seq,
                "sheet": os.path.basename(spath),
                "cell": cellidx,
                "status": status,
                "id": r["id"],
                "filename": r["filename"],
                "photo_path": r["photo_path"],
                "img_sha16": file_sha256(r["photo_path"]) if status == "ok" else "",
                "seed": args.seed,
            })
        print(f"  {os.path.basename(spath)}  ({len(chunk)} images)")

    mf = pd.DataFrame(manifest)
    # THE UNBLINDING KEY. Written outside the sheet folder on purpose, so that
    # opening the folder to read the sheets does not put the answers in view.
    mpath = os.path.join(SHEETDIR, f"manifest_{args.out_tag}.csv")
    mf.to_csv(mpath, index=False)

    print(f"\nbridge rows        {n_all}")
    print(f"selected           {len(df)}")
    print(f"sheets             {len(sheets)}  in {outdir}")
    print(f"manifest           {mpath}")
    print(f"seed               {args.seed}")
    print("\nSheets carry a sequence number and nothing else. Record readings against")
    print("the sequence number, then join the manifest to recover id.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
