"""CPI paths and PSPS->MS inflation for the COICOP groups used by the NSU items.

Two figures:
  fig1  small multiples, one panel per COICOP group, index = 2023m12 -> 100.
        Five provinces as thin neutral lines + cross-province median in blue.
        (Five categorical hues FAIL the all-pairs CVD/normal-vision floors, so
        province identity is deliberately not carried by colour here -- the
        panel answers "how much, and how smooth", not "which province".)
  fig2  heatmap, COICOP group x province, cumulative % change over the
        median-to-median window. Sequential single-hue blue; province identity
        is positional, so no categorical palette is involved.
"""
import csv, collections, statistics as st
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

BOX  = Path(r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey")
DATA = BOX / "NSU Market Survey Launch" / "data"
OUT  = BOX / "Data Cleaning" / "outputs" / "build" / "graphs"
OUT.mkdir(parents=True, exist_ok=True)

# ---- palette (dataviz skill reference instance) --------------------------------
SURFACE   = "#fcfcfb"
INK       = "#0b0b0b"
INK2      = "#52514e"
INK3      = "#8a8880"
SERIES1   = "#2a78d6"
GRID      = "#e6e5e1"
PSPS_TINT = "#f0efec"
MS_TINT   = "#cde2fb"
BLUE_RAMP = ["#cde2fb", "#9ec5f4", "#6da7ec", "#3987e5", "#256abf",
             "#1c5cab", "#184f95", "#104281", "#0d366b"]
CMAP = LinearSegmentedColormap.from_list("blueramp", BLUE_RAMP)

# ---- field windows, measured from the data (see field_windows.do) --------------
# Stata monthly date: 0 = 1960m1
def sm(y, m): return (y - 1960) * 12 + (m - 1)
def ym(s):    return (1960 + s // 12, s % 12 + 1)
def lbl(s):
    y, m = ym(s); return f"{y}m{m}"

PSPS_MIN, PSPS_MAX = sm(2023, 12), sm(2025, 1)
PSPS_MED           = sm(2024, 5)      # median of 53,910 PSPS obs
MS_MIN,  MS_MAX    = sm(2026, 3), sm(2026, 5)
MS_MED             = sm(2026, 4)      # mean 794.85 ~ 2026m4

# ---- inputs -------------------------------------------------------------------
xw = list(csv.DictReader(open(DATA / "cons_name_to_coicop_crosswalk.csv",
                              encoding="utf-8-sig")))
groups_used = sorted({r["item_group"] for r in xw})
items_of = collections.defaultdict(set)
for r in xw:
    items_of[r["item_group"]].add(r["cons_name"])

cpi = collections.defaultdict(dict)          # (prov, group) -> {month: level}
provs = set()
for r in csv.DictReader(open(DATA / "fp_cpi_byprov_byitem_psa_2023_26.csv",
                             encoding="utf-8-sig")):
    p = r["geolocation"].upper()
    provs.add(p)
    cpi[(p, r["commodity"])][sm(int(r["year"]), int(r["month"]))] = float(r["cpi"])
provs = sorted(provs)

# ---- coverage audit: which (province, group) series are missing? ---------------
print("=== CPI coverage for the 16 COICOP groups used by our items ===")
missing = []
for g in groups_used:
    have = [p for p in provs if (p, g) in cpi]
    if len(have) < len(provs):
        gone = [p for p in provs if p not in have]
        missing.append((g, gone))
        print(f"  MISSING {g[:52]:<54} -> {', '.join(gone)}")
if not missing:
    print("  all 16 groups present in all 5 provinces")
print(f"  groups={len(groups_used)}  provinces={len(provs)}  "
      f"series present={sum(1 for g in groups_used for p in provs if (p,g) in cpi)}"
      f"/{len(groups_used)*len(provs)}")

def short(g):
    """COICOP code + trimmed label for a panel title."""
    code, _, name = g.partition(" - ")
    name = name.replace(" (ND)", "").replace(" (S)", "").strip()
    name = name.encode("ascii", "ignore").decode()
    if len(name) > 34: name = name[:33].rstrip() + "\u2026"
    return f"{code}  {name}"

# ================================================================= figure 1 ====
months = sorted({m for s in cpi.values() for m in s})
ncol, nrow = 4, 4
fig, axes = plt.subplots(nrow, ncol, figsize=(15.5, 13.0), sharex=True,
                         facecolor=SURFACE)
fig.subplots_adjust(top=0.90, bottom=0.07, hspace=0.42, wspace=0.20)

for k, g in enumerate(groups_used):
    ax = axes[k // ncol][k % ncol]
    ax.set_facecolor(SURFACE)

    series = []
    for p in provs:
        s = cpi.get((p, g))
        if not s or PSPS_MIN not in s: continue
        base = s[PSPS_MIN]
        xs = [m for m in months if m in s]
        ys = [100.0 * s[m] / base for m in xs]
        series.append((xs, ys))
        ax.plot(xs, ys, color=INK3, lw=0.9, alpha=0.55, zorder=2,
                solid_capstyle="round")

    # cross-province median path
    if series:
        med_x, med_y = [], []
        for m in months:
            v = [ys[xs.index(m)] for xs, ys in series if m in xs]
            if v: med_x.append(m); med_y.append(st.median(v))
        ax.plot(med_x, med_y, color=SERIES1, lw=2.0, zorder=4,
                solid_capstyle="round")
        end = med_y[-1] - 100.0
        ax.annotate(f"{end:+.0f}%", xy=(med_x[-1], med_y[-1]),
                    xytext=(4, 0), textcoords="offset points",
                    va="center", ha="left", fontsize=8.5,
                    color=INK2, fontweight="bold", zorder=6)

    ax.axvspan(PSPS_MIN, PSPS_MAX, color=PSPS_TINT, zorder=0, lw=0)
    ax.axvspan(MS_MIN,  MS_MAX,   color=MS_TINT, alpha=0.75, zorder=0, lw=0)
    ax.axhline(100, color=GRID, lw=1.0, zorder=1)

    ax.set_title(short(g), fontsize=9, color=INK, loc="left", pad=6)
    sub = ", ".join(sorted(i.split(",")[0].split(" (")[0]
                           for i in items_of[g]))
    sub = sub.encode("ascii", "ignore").decode()
    ax.text(0, 1.015, sub[:48] + ("\u2026" if len(sub) > 48 else ""),
            transform=ax.transAxes, fontsize=7.4, color=INK3, va="bottom")

    ax.grid(axis="y", color=GRID, lw=0.7, zorder=1)
    ax.set_axisbelow(True)
    for sp in ("top", "right", "left"): ax.spines[sp].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=7.8, length=0)
    ax.set_xlim(min(months), max(months) + 3)

for k in range(len(groups_used), nrow * ncol):
    axes[k // ncol][k % ncol].set_visible(False)

ticks = [m for m in months if ym(m)[1] in (1, 7)]
for c in range(ncol):
    axes[nrow - 1][c].set_xticks(ticks)
    axes[nrow - 1][c].set_xticklabels([lbl(t) for t in ticks], rotation=45,
                                      ha="right", fontsize=7.4)

fig.text(0.008, 0.972, "Food-price CPI by COICOP group, 2023m12 = 100",
         fontsize=15, color=INK, fontweight="bold", va="top")
fig.text(0.008, 0.947,
         "Blue = median across the five provinces; grey = individual provinces "
         "(identity not colour-coded: five hues fail the CVD floors).",
         fontsize=9.2, color=INK2, va="top")
fig.text(0.008, 0.929,
         f"Shaded: PSPS fieldwork {lbl(PSPS_MIN)}\u2013{lbl(PSPS_MAX)} (grey, bimodal) "
         f"and NSU market survey {lbl(MS_MIN)}\u2013{lbl(MS_MAX)} (blue). "
         "Label = median cumulative change at the final month.",
         fontsize=9.2, color=INK2, va="top")
fig.savefig(OUT / "cpi_paths_by_coicop_group.png", dpi=180,
            facecolor=SURFACE, bbox_inches="tight")
print(f"\nwrote {OUT / 'cpi_paths_by_coicop_group.png'}")

# ================================================================= figure 2 ====
# pi over the median-to-median window, plus the spread implied by the PSPS range
rows, cells, spread = [], [], []
for g in groups_used:
    r, sp = [], []
    for p in provs:
        s = cpi.get((p, g))
        if s and PSPS_MED in s and MS_MED in s:
            r.append(100.0 * (s[MS_MED] / s[PSPS_MED] - 1.0))
            lo = 100.0 * (s[MS_MED] / s[PSPS_MAX] - 1.0)
            hi = 100.0 * (s[MS_MED] / s[PSPS_MIN] - 1.0)
            sp.append(abs(hi - lo))
        else:
            r.append(float("nan")); sp.append(float("nan"))
    rows.append(g); cells.append(r); spread.append(sp)

order = sorted(range(len(rows)),
               key=lambda i: -st.median([v for v in cells[i] if v == v] or [0]))
rows   = [rows[i]   for i in order]
cells  = [cells[i]  for i in order]
spread = [spread[i] for i in order]

fig2, (ax, ax2) = plt.subplots(
    1, 2, figsize=(13.2, 8.4), facecolor=SURFACE,
    gridspec_kw={"width_ratios": [5, 1.5], "wspace": 0.06})

flat = [v for r in cells for v in r if v == v]
im = ax.imshow(cells, cmap=CMAP, aspect="auto",
               vmin=min(flat), vmax=max(flat))
ax.set_xticks(range(len(provs)))
ax.set_xticklabels([p.replace(" ", "\n") for p in provs], fontsize=9, color=INK2)
ax.set_yticks(range(len(rows)))
ax.set_yticklabels([short(g) for g in rows], fontsize=8.6, color=INK)
ax.tick_params(length=0)
for sp_ in ax.spines.values(): sp_.set_visible(False)

# 2px surface gap between cells
ax.set_xticks([x - 0.5 for x in range(1, len(provs))], minor=True)
ax.set_yticks([y - 0.5 for y in range(1, len(rows))], minor=True)
ax.grid(which="minor", color=SURFACE, lw=2.0)

span = max(flat) - min(flat)
for i in range(len(rows)):
    for j in range(len(provs)):
        v = cells[i][j]
        if v != v:
            ax.text(j, i, "n/a", ha="center", va="center", fontsize=8,
                    color=INK3); continue
        frac = (v - min(flat)) / span if span else 0.5
        ax.text(j, i, f"{v:+.1f}", ha="center", va="center", fontsize=8.4,
                color=("#ffffff" if frac > 0.55 else INK), fontweight="bold")

cb = fig2.colorbar(im, ax=ax, fraction=0.030, pad=0.015)
cb.set_label("cumulative price change, % ", fontsize=8.6, color=INK2)
cb.ax.tick_params(labelsize=8, colors=INK2, length=0)
cb.outline.set_visible(False)

# right panel: how much pi moves if the PSPS anchor month moves
ax2.set_facecolor(SURFACE)
ys = list(range(len(rows)))
vals = [st.median([v for v in spread[i] if v == v] or [0]) for i in ys]
ax2.barh(ys, vals, color=SERIES1, height=0.55, zorder=3)
for y, v in zip(ys, vals):
    ax2.text(v + max(vals) * 0.03, y, f"{v:.0f}", va="center", fontsize=8,
             color=INK2, fontweight="bold")
ax2.set_ylim(len(rows) - 0.5, -0.5)
ax2.set_yticks([]); ax2.set_xticks([])
ax2.set_xlim(0, max(vals) * 1.28)
for sp_ in ax2.spines.values(): sp_.set_visible(False)
ax2.set_title("pp swing in \u03c0 if the\nPSPS anchor month\nmoves across its range",
              fontsize=8.6, color=INK2, loc="left", pad=8)

fig2.text(0.008, 0.975,
          f"\u03c0: cumulative food-price change, PSPS {lbl(PSPS_MED)} "
          f"\u2192 market survey {lbl(MS_MED)}",
          fontsize=14.5, color=INK, fontweight="bold", va="top")
fig2.text(0.008, 0.949,
          "Median-to-median window. Sorted by cross-province median. Right panel: "
          f"the PSPS window spans {lbl(PSPS_MIN)}\u2013{lbl(PSPS_MAX)}, so \u03c0 is "
          "household-specific \u2014 the bar is how much it moves.",
          fontsize=9.2, color=INK2, va="top")
fig2.subplots_adjust(top=0.90, left=0.30, right=0.94, bottom=0.06)
fig2.savefig(OUT / "cpi_inflation_psps_to_ms.png", dpi=180,
             facecolor=SURFACE, bbox_inches="tight")
print(f"wrote {OUT / 'cpi_inflation_psps_to_ms.png'}")

# ---- printed table ------------------------------------------------------------
print(f"\n=== pi (%), PSPS {lbl(PSPS_MED)} -> MS {lbl(MS_MED)} ===")
hdr = f"{'COICOP group':<50}" + "".join(f"{p[:9]:>10}" for p in provs) + \
      f"{'median':>9}{'anchor swing':>14}"
print(hdr); print("-" * len(hdr))
for i, g in enumerate(rows):
    med = st.median([v for v in cells[i] if v == v] or [float('nan')])
    sw  = st.median([v for v in spread[i] if v == v] or [float('nan')])
    line = f"{short(g)[:49]:<50}"
    line += "".join(("     n/a  " if v != v else f"{v:>+9.1f} ") for v in cells[i])
    print(line + f"{med:>+8.1f} {sw:>13.1f}")
print("-" * len(hdr))
allv = [v for r in cells for v in r if v == v]
print(f"{'ALL GROUPS x PROVINCES':<50}{'':<50}{st.median(allv):>+8.1f}")
print(f"\nmin {min(allv):+.1f}%   max {max(allv):+.1f}%   "
      f"n series {len(allv)}/{len(rows)*len(provs)}")
