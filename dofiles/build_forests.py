import sys, os, re
import numpy as np, pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.transforms import blended_transform_factory

DTA    = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs\temp\nsu_data.dta"
GRAPHS = r"C:\Users\uzj5150\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs\graphs"

HETERO = {1:'conventional_nsu',2:'large_size',3:'medium_size',4:'mp25_price',5:'mp50_price',
          6:'mp75_price',7:'municipality_median',8:'province_median',9:'small_size',
          10:'unique_mun_price6',11:'unique_mun_price7'}
MARKET = {1:'Public Market',2:'Talipapa',3:'Roadside'}

ROWS_PER_PAGE = 42
ROWH = 0.44          # inches per row (bigger => wider spacing between distributions)
BAND = 0.5           # max histogram height within a row's slot (smaller => thinner ridgelines)
BINWIDTH = 5         # fixed histogram bar width, in g or mL (this controls bar WIDTH, not BAND)
MAX_BINS = 1500      # safety cap per facet (a few facets span thousands of g/mL)
q1 = lambda s: s.quantile(.25)
q3 = lambda s: s.quantile(.75)

def fix_enc(s):
    # repair UTF-8 bytes that were mis-decoded as latin-1 (e.g. DUEnAS)
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
    df['market_lbl'] = df['market_type'].map(MARKET).fillna('NA')
    return df

def make_edges(values, binwidth=BINWIDTH, max_bins=MAX_BINS):
    lo = np.floor(values.min()/binwidth)*binwidth
    hi = np.ceil(values.max()/binwidth)*binwidth + binwidth
    n = int(round((hi-lo)/binwidth))
    if n > max_bins:                      # coarsen only for facets with an extreme range
        binwidth = (hi-lo)/max_bins
    return np.arange(lo, hi+1e-9, binwidth)

# VERSIONS: keys = groupby columns defining one row/distribution.
# block_col = column used to keep a group's sub-rows adjacent & ordered by ITS OWN median
#             (municipality identity for v1-3; None for v4-5, i.e. sort directly within band).
# band_col  = column the shaded/labeled bands are drawn by (always province).
VERSIONS = {
    1: dict(keys=['prov_mun_nsu_item'], block_col='prov_mun_nsu_item', band_col='pull_province',
            label=lambda r: r['pull_municipal_city'],
            desc='Ver 1 - level: prov_mun_nsu_item',
            fname='forest_v1_prov_mun_nsu_item'),
    2: dict(keys=['prov_mun_nsu_item','item_nsu_hetero_type'], block_col='prov_mun_nsu_item', band_col='pull_province',
            label=lambda r: f"{r['pull_municipal_city']} | {r['hetero_lbl']}",
            desc='Ver 2 - level: prov_mun_nsu_item x item_nsu_hetero_type',
            fname='forest_v2_prov_mun_nsu_item_x_hetero'),
    3: dict(keys=['prov_mun_nsu_item','item_nsu_hetero_type','market_type'], block_col='prov_mun_nsu_item', band_col='pull_province',
            label=lambda r: f"{r['pull_municipal_city']} | {r['hetero_lbl']} | {r['market_lbl']}",
            desc='Ver 3 - level: prov_mun_nsu_item x item_nsu_hetero_type x market_type',
            fname='forest_v3_prov_mun_nsu_item_x_hetero_x_market'),
    4: dict(keys=['pull_province','corrected_unit'], block_col=None, band_col='pull_province',
            label=lambda r: r['corrected_unit'],
            desc='Ver 4 - level: pull_province x nsu_item x corrected_unit',
            fname='forest_v4_pull_province_x_corrected_unit'),
    5: dict(keys=['pull_province','item_nsu_hetero_type','corrected_unit'], block_col=None, band_col='pull_province',
            label=lambda r: f"{r['hetero_lbl']} ({r['corrected_unit']})",
            desc='Ver 5 - level: pull_province x nsu_item x item_nsu_hetero_type x corrected_unit',
            fname='forest_v5_pull_province_x_hetero_x_corrected_unit'),
}

def facet_stats(sub, keys, block_col):
    g = sub.groupby(keys, dropna=False)
    st = g['corrected_weight'].agg(n='size', med='median', q1=q1, q3=q3,
                                   lo='min', hi='max').reset_index()
    vals = g['corrected_weight'].apply(lambda s: np.asarray(s, float)).reset_index(name='vals')
    st = st.merge(vals, on=keys)
    for c in ['pull_province','pull_municipal_city','hetero_lbl','market_lbl','corrected_unit']:
        if c in sub.columns:
            st[c] = g[c].first().values
    if block_col:
        block_med = sub.groupby(block_col)['corrected_weight'].median()
        st['block_med'] = st[block_col].map(block_med)
        st = st.sort_values(['pull_province','block_med',block_col,'med'],
                            ascending=[True,False,True,False]).reset_index(drop=True)
    else:
        st = st.sort_values(['pull_province','med'], ascending=[True,False]).reset_index(drop=True)
    return st

def draw_page(st, title, xlabel, labeller, edges, band_col):
    n = len(st)
    fig_h = max(2.5, ROWH*n + 1.6)
    fig, ax = plt.subplots(figsize=(12, fig_h))
    y = np.arange(n)[::-1]
    for yi,(_,r) in zip(y, st.iterrows()):
        ax.hlines(yi, edges[0], edges[-1], color='#e3e3e3', lw=0.4, zorder=1)   # baseline
        v = np.asarray(r['vals'], float)
        counts,_ = np.histogram(v, bins=edges)
        m = counts.max()
        if m > 0:
            h = counts / m * BAND
            ax.stairs(yi + h, edges, baseline=yi, fill=True, color='#3a6f92',
                      alpha=0.8, lw=0, zorder=3)
        ax.plot(r['med'], yi, 'o', color='#12303f', ms=2.6, zorder=4)           # median marker
    ax.set_yticks(y); ax.set_yticklabels([labeller(r) for _,r in st.iterrows()], fontsize=7.5)
    ax.set_ylim(-0.6, n); ax.margins(x=0.02)
    # bands (shaded alternate) + label at top-left of each block
    tr = blended_transform_factory(ax.transAxes, ax.transData)
    bands = st[band_col].values
    k=0; band=False
    while k<n:
        j=k
        while j<n and bands[j]==bands[k]: j+=1
        top=y[k]+BAND+0.30; bot=y[j-1]-0.30
        if band: ax.axhspan(bot, top, color='k', alpha=0.04, zorder=0)
        band=not band
        ax.axhline(top, color='#cfcfcf', lw=0.7, zorder=1)
        ax.text(0.012, top-0.06, bands[k], transform=tr, va='top', ha='left',
                fontsize=8, fontweight='bold', color='#7a2d2d', zorder=5)
        k=j
    # n= column at right (at each row's baseline)
    for yi,(_,r) in zip(y, st.iterrows()):
        ax.text(1.008, yi, f"n={int(r['n'])}", transform=tr, va='bottom', ha='left',
                fontsize=6.5, color='#555')
    ax.set_xlabel(xlabel, fontsize=10)
    ax.set_title(title, fontsize=11, loc='left')
    ax.grid(axis='x', ls=':', alpha=0.5)
    ax.spines[['top','right']].set_visible(False)
    ax.set_xlim(left=0)
    fig.subplots_adjust(left=0.24, right=0.90, top=1-0.8/fig_h, bottom=0.8/fig_h)
    return fig

ROWS_TABLE = 44

def draw_table_page(chunk, version, title):
    if version in (1,2,3):
        v3 = (version==3)
        cols = [('prov_mun_nsu_item', 0.004, 'left'),
                ('item_nsu_hetero_type', 0.58 if v3 else 0.66, 'left')]
        if v3: cols.append(('market_type', 0.745, 'left'))
        cols += [('corrected_weight', 0.90, 'right'), ('corrected_unit', 0.985, 'right')]
    elif version == 4:
        cols = [('pull_province', 0.004, 'left'),
                ('corrected_weight', 0.90, 'right'), ('corrected_unit', 0.985, 'right')]
    else:  # 5
        cols = [('pull_province', 0.004, 'left'), ('item_nsu_hetero_type', 0.55, 'left'),
                ('corrected_weight', 0.90, 'right'), ('corrected_unit', 0.985, 'right')]
    n = len(chunk); fig_h = max(2.5, 0.23*n + 1.5)
    fig, ax = plt.subplots(figsize=(12, fig_h)); ax.set_xlim(0,1); ax.set_ylim(0,1); ax.axis('off')
    top=0.955; dy=(top-0.03)/(n+1)
    def put(x,yy,txt,ha,bold=False):
        ax.text(x,yy,txt,ha=ha,va='center',fontsize=6.8,family='monospace',
                fontweight='bold' if bold else 'normal')
    for name,x,ha in cols: put(x, top, name, ha, bold=True)
    ax.axhline(top-dy*0.5, color='#999', lw=0.6)
    for i,(_,r) in enumerate(chunk.iterrows()):
        yy = top - dy*(i+1)
        if version in (1,2,3):
            put(cols[0][1], yy, str(r['prov_mun_nsu_item']), 'left')
            put(cols[1][1], yy, str(r['hetero_lbl']), 'left')
            ci=2
            if version==3: put(cols[ci][1], yy, str(r['market_lbl']), 'left'); ci+=1
            put(cols[ci][1], yy, f"{r['med']:,.1f}", 'right')
            put(cols[ci+1][1], yy, str(r['corrected_unit']), 'right')
        elif version == 4:
            put(cols[0][1], yy, str(r['pull_province']), 'left')
            put(cols[1][1], yy, f"{r['med']:,.1f}", 'right')
            put(cols[2][1], yy, str(r['corrected_unit']), 'right')
        else:
            put(cols[0][1], yy, str(r['pull_province']), 'left')
            put(cols[1][1], yy, str(r['hetero_lbl']), 'left')
            put(cols[2][1], yy, f"{r['med']:,.1f}", 'right')
            put(cols[3][1], yy, str(r['corrected_unit']), 'right')
    ax.set_title(title, fontsize=11, loc='left')
    fig.subplots_adjust(left=0.02, right=0.99, top=1-0.7/fig_h, bottom=0.4/fig_h)
    return fig

def build(version, sample_items=None, out_png_dir=None):
    df = load()
    cfg = VERSIONS[version]
    items = sorted(df['nsu_item'].unique())
    if sample_items: items = [i for i in items if i in sample_items]
    pdf = None
    if not sample_items:
        os.makedirs(GRAPHS, exist_ok=True)
        pdf = PdfPages(os.path.join(GRAPHS, cfg['fname']+'.pdf'))
    singles = []
    for item in items:
        sub = df[df['nsu_item']==item]
        units = sorted({str(u) for u in sub['corrected_unit'].dropna().unique() if str(u) not in ('','nan')})
        ulab = '/'.join(units) or 'unit'
        xlabel = f"corrected_weight ({ulab})   [each row = mini histogram, bar width={BINWIDTH}{ulab if len(units)==1 else ''}, scaled to its own peak; dot = median]"
        st = facet_stats(sub, cfg['keys'], cfg['block_col'])
        singles.append(st[st['n']==1])                 # n=1 units -> table, not plotted
        st = st[st['n']>=2].reset_index(drop=True)      # ridgeline: multi-obs units only
        if len(st)==0: continue
        edges = make_edges(np.concatenate(st['vals'].values))
        npages = int(np.ceil(len(st)/ROWS_PER_PAGE))
        for pg in range(npages):
            chunk = st.iloc[pg*ROWS_PER_PAGE:(pg+1)*ROWS_PER_PAGE]
            ttl = f"{item}\n{cfg['desc']}" + (f"   (page {pg+1}/{npages})" if npages>1 else "")
            fig = draw_page(chunk, ttl, xlabel, cfg['label'], edges, cfg['band_col'])
            if pdf: pdf.savefig(fig, bbox_inches='tight')
            if out_png_dir:
                safe = re.sub(r'[^A-Za-z0-9]+','_',item)[:40]
                fig.savefig(os.path.join(out_png_dir, f"v{version}_{safe}_p{pg+1}.png"), dpi=115, bbox_inches='tight')
            plt.close(fig)
    # ---- singleton table page(s) at the end ----
    sdf = pd.concat(singles, ignore_index=True) if singles else pd.DataFrame()
    if len(sdf):
        sort_cols = ['pull_province'] + ([cfg['keys'][0]] if version in (1,2,3) else
                     (['item_nsu_hetero_type'] if version==5 else []))
        sdf = sdf.sort_values(sort_cols).reset_index(drop=True)
        tpages = int(np.ceil(len(sdf)/ROWS_TABLE))
        for pg in range(tpages):
            chunk = sdf.iloc[pg*ROWS_TABLE:(pg+1)*ROWS_TABLE]
            ttl = (f"{cfg['desc']}\nSINGLETON units (n=1): excluded from ridgelines above, listed here"
                   f"   (total {len(sdf)}; page {pg+1}/{tpages})")
            fig = draw_table_page(chunk, version, ttl)
            if pdf: pdf.savefig(fig, bbox_inches='tight')
            if out_png_dir and pg==0:
                fig.savefig(os.path.join(out_png_dir, f"v{version}_singletons_p1.png"), dpi=115, bbox_inches='tight')
            plt.close(fig)
    if pdf: pdf.close()
    return sdf

if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv)>1 else 'sample'
    if mode == 'sample':
        d = os.path.join(os.path.dirname(__file__), 'sample')
        os.makedirs(d, exist_ok=True)
        build(1, sample_items={'Cabbage_Bilog'}, out_png_dir=d)
        build(4, sample_items={'Cabbage_Bilog'}, out_png_dir=d)
        build(5, sample_items={'Cabbage_Bilog'}, out_png_dir=d)
        print("sample ->", d)
    else:
        for v in (1,2,3,4,5):
            build(v); print("done ver", v)
