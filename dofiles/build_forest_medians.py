import os
import numpy as np, pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.lines import Line2D

DTA    = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs\temp\nsu_data.dta"
GRAPHS = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs\graphs"

HETERO = {1:'conventional_nsu',2:'large_size',3:'medium_size',4:'mp25_price',5:'mp50_price',
          6:'mp75_price',7:'municipality_median',8:'province_median',9:'small_size',
          10:'unique_mun_price6',11:'unique_mun_price7'}

# fixed hetero type -> color, consistent across every page
HET_COLORS = {
    'conventional_nsu':     '#1f3d5c',
    'large_size':           '#7a1f1f',
    'medium_size':          '#2e5339',
    'mp25_price':           '#cc6600',
    'mp50_price':           '#5b2a86',
    'mp75_price':           '#1f7a6c',
    'municipality_median':  '#a3178f',
    'province_median':      '#6b6b1f',
    'small_size':           '#7a4a1f',
    'unique_mun_price6':    '#777777',
    'unique_mun_price7':    '#c94f7c',
}
HET_ORDER = list(HET_COLORS.keys())

ROW_H       = 1.35   # inches per province row (base; grows if many label tiers needed)
TIER_H      = 0.16   # extra inches per row per label tier beyond the base allotment
MUNI_MSIZE  = 70
PROV_MSIZE  = 260
HET_POOL_MSIZE = 60
HET_MUNI_MSIZE = 18
MAX_LABELED_MUNI = 10   # provinces with more municipalities: label only the top/bottom 5 by median
MIN_TIERS   = 3         # base tiers reserved even for uncrowded rows

def stack_labels(xs, xrange, min_gap_frac=0.11):
    """Greedily assign each x-position (in sorted order) to the first non-colliding
    vertical tier. Tiers alternate above/below with increasing magnitude:
    [+1,-1,+2,-2,...]. Returns (offsets_in_points, va_list, ntiers_used) aligned to
    the ORIGINAL (unsorted) order of xs."""
    order = np.argsort(xs)
    min_gap = xrange * min_gap_frac if xrange > 0 else 1.0
    tier_seq = []
    k = 1
    while len(tier_seq) < 40:
        tier_seq += [k, -k]; k += 1
    last_x = {}
    tier_of = [None]*len(xs)
    for idx in order:
        x = xs[idx]
        placed = False
        for t in tier_seq:
            if t not in last_x or (x - last_x[t]) >= min_gap:
                tier_of[idx] = t; last_x[t] = x; placed = True; break
        if not placed:
            tier_of[idx] = tier_seq[0]; last_x[tier_seq[0]] = x
    ntiers = max(abs(t) for t in tier_of) if tier_of else 1
    offsets = [10 + (abs(t)-1)*11 if t > 0 else -(10 + (abs(t)-1)*11) for t in tier_of]
    vas = ['bottom' if t > 0 else 'top' for t in tier_of]
    return offsets, vas, ntiers

def fix_enc(s):
    if not isinstance(s, str): return s
    try:    return s.encode('latin-1').decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError): return s

def load():
    df = pd.read_stata(DTA, convert_categoricals=False)
    df = df[df['corrected_weight'].notna() & (df['corrected_weight']>0)].copy()
    df['corrected_unit'] = df['corrected_unit'].map({1:'g',2:'mL'})
    for c in ['pull_province','pull_municipal_city']:
        df[c] = df[c].map(fix_enc)
    df['hetero_lbl'] = df['item_nsu_hetero_type'].map(HETERO).fillna('NA')
    return df

SHAPE_LEGEND = [
    Line2D([0],[0], marker='D', color='w', markerfacecolor='black', markeredgecolor='white',
           markersize=11, label='Province median'),
    Line2D([0],[0], marker='o', color='w', markerfacecolor='#1f4e79', markersize=8,
           label='Municipality median'),
    Line2D([0],[0], marker='D', color='w', markerfacecolor='none', markeredgecolor='gray',
           markersize=8, label='Hetero median (pooled across province)'),
    Line2D([0],[0], marker='o', color='w', markerfacecolor='gray', markersize=6,
           label='Hetero median (within municipality)'),
]

def draw_item(item_df, item):
    prov_med_all = item_df.groupby('pull_province')['corrected_weight'].median().sort_values(ascending=False)
    provinces = prov_med_all.index.tolist()
    n = len(provinces)

    xmin, xmax = item_df['corrected_weight'].min(), item_df['corrected_weight'].max()
    xrange = xmax - xmin

    # ---- pre-compute per-province municipality label plan (which get labeled, tiers) ----
    plans = {}
    max_tiers = MIN_TIERS
    for p in provinces:
        sub = item_df[item_df['pull_province']==p]
        muni_g = (sub.groupby('pull_municipal_city')['corrected_weight']
                     .agg(med='median', n='size').reset_index()
                     .sort_values('med').reset_index(drop=True))
        if len(muni_g) > MAX_LABELED_MUNI:
            keep = pd.concat([muni_g.head(5), muni_g.tail(5)]).index
            n_hidden = len(muni_g) - len(keep)
        else:
            keep = muni_g.index
            n_hidden = 0
        labeled = muni_g.loc[keep].reset_index(drop=True)
        offsets, vas, ntiers = stack_labels(labeled['med'].values, xrange) if len(labeled) else ([], [], 1)
        max_tiers = max(max_tiers, ntiers)
        plans[p] = dict(muni_g=muni_g, labeled=labeled, offsets=offsets, vas=vas, n_hidden=n_hidden)

    row_h = ROW_H + TIER_H*max_tiers
    y_of = {p: n - i for i, p in enumerate(provinces)}
    fig_h = max(3.2, row_h*n + 2.0)
    fig, ax = plt.subplots(figsize=(14, fig_h))
    used_het = set()

    for p in provinces:
        y = y_of[p]
        sub = item_df[item_df['pull_province']==p]
        plan = plans[p]
        ax.axhline(y, color='#e8e8e8', lw=0.6, zorder=0)

        pmed, pn = sub['corrected_weight'].median(), len(sub)
        ax.scatter(pmed, y, marker='D', s=PROV_MSIZE, color='black', edgecolor='white',
                   linewidths=0.8, zorder=6)
        ax.annotate(f"n={pn}", (pmed, y), xytext=(0, (max_tiers)*11+14), textcoords='offset points',
                    ha='center', va='bottom', fontsize=7.5, fontweight='bold', zorder=7)

        # unlabeled municipality dots (crowded provinces: middle municipalities, dot only)
        for _, r in plan['muni_g'].iterrows():
            ax.scatter(r['med'], y, marker='o', s=MUNI_MSIZE, color='#1f4e79', alpha=0.55, zorder=4)
        # labeled municipality dots + fanned-out text
        for j, (_, r) in enumerate(plan['labeled'].iterrows()):
            ax.scatter(r['med'], y, marker='o', s=MUNI_MSIZE, color='#1f4e79', alpha=0.95,
                       zorder=5, edgecolor='white', linewidths=0.4)
            ax.annotate(f"{r['pull_municipal_city']} ({int(r['n'])})", (r['med'], y),
                        xytext=(0, plan['offsets'][j]), textcoords='offset points',
                        ha='center', va=plan['vas'][j],
                        fontsize=5.4, color='#1f4e79', zorder=6,
                        arrowprops=dict(arrowstyle='-', lw=0.3, color='#a9c2d8',
                                         shrinkA=0, shrinkB=2))
        if plan['n_hidden'] > 0:
            ax.annotate(f"(+{plan['n_hidden']} more municipalities, dots only)",
                        (xmax, y), xytext=(8, 0), textcoords='offset points',
                        ha='left', va='center', fontsize=6, color='#777777', style='italic')

        het_pool = sub.groupby('hetero_lbl')['corrected_weight'].median()
        for h, val in het_pool.items():
            if h == 'NA': continue
            c = HET_COLORS.get(h, '#888888'); used_het.add(h)
            ax.scatter(val, y, marker='D', s=HET_POOL_MSIZE, facecolors='none',
                       edgecolors=c, linewidths=1.2, zorder=3)

        het_muni = sub.groupby(['pull_municipal_city','hetero_lbl'])['corrected_weight'].median()
        for (m, h), val in het_muni.items():
            if h == 'NA': continue
            c = HET_COLORS.get(h, '#888888'); used_het.add(h)
            ax.scatter(val, y, marker='o', s=HET_MUNI_MSIZE, color=c, alpha=0.75, zorder=2)

    ax.set_yticks([y_of[p] for p in provinces])
    ax.set_yticklabels(provinces, fontsize=9, fontweight='bold')
    ax.set_ylim(0.4, n + 0.55 + max_tiers*0.11)
    ax.margins(x=0.10)
    ax.set_xlabel("corrected_weight", fontsize=10)
    ax.set_title(f"{item}\none row = one province (dots = municipality / hetero-type medians within it)",
                 fontsize=11, loc='left')
    ax.grid(axis='x', ls=':', alpha=0.4)
    ax.spines[['top','right']].set_visible(False)

    leg1 = ax.legend(handles=SHAPE_LEGEND, loc='upper left', bbox_to_anchor=(0, 1.0),
                      fontsize=6.3, frameon=False, ncol=1,
                      bbox_transform=fig.transFigure)
    ax.add_artist(leg1)

    het_handles = [Line2D([0],[0], marker='o', color='w', markerfacecolor=HET_COLORS[h],
                          markersize=6, label=h) for h in HET_ORDER if h in used_het]
    if het_handles:
        ax.legend(handles=het_handles, title='hetero type (color)', loc='upper right',
                  bbox_to_anchor=(1, 1.0), fontsize=6, title_fontsize=6.5, frameon=False,
                  bbox_transform=fig.transFigure)
        ax.add_artist(leg1)

    fig.subplots_adjust(left=0.13, right=0.86, top=1 - 1.35/fig_h, bottom=1.0/fig_h)
    return fig

def build(sample_items=None, out_png_dir=None):
    df = load()
    items = sorted(df['nsu_item'].unique())
    if sample_items:
        items = [i for i in items if i in sample_items]
    pdf = None
    if not sample_items:
        os.makedirs(GRAPHS, exist_ok=True)
        pdf = PdfPages(os.path.join(GRAPHS, 'forest_v6_pull_province_x_nsu_item_medians.pdf'))
    for item in items:
        sub = df[df['nsu_item']==item]
        fig = draw_item(sub, item)
        if pdf: pdf.savefig(fig, bbox_inches='tight')
        if out_png_dir:
            safe = item.replace('/', '_').replace(' ', '_')[:60]
            fig.savefig(os.path.join(out_png_dir, f"medians_{safe}.png"), dpi=130, bbox_inches='tight')
        plt.close(fig)
    if pdf: pdf.close()

if __name__ == '__main__':
    d = os.path.join(os.path.dirname(__file__), 'sample')
    os.makedirs(d, exist_ok=True)
    build(sample_items={'Cabbage_Bilog'}, out_png_dir=d)
    print("sample ->", d)
