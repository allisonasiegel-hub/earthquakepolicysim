"""
plot_wservice_old_sweep_maps.py
=================================
For each wservice_old value in the sweep, maps the % of households per SA
that are young-old vs old-old (averaged across the 3 replicates), on one
shared color scale per subgroup so the panels are directly comparable
across the sweep.
"""
import glob
import re
import numpy as np
import pandas as pd
import scipy.io as sio
import geopandas as gpd
import matplotlib.pyplot as plt

HH_COLS = ['stat', 'hh_id', 'individuals', 'children', 'n_old', 'hh_income',
           'hh_asiron', 'n_cars', 'yeshuv', 'building_id', 'asset_id', 'old_old_count']
SHAPE_PATH = 'tveriashape/tveriastats.shp'

pattern = re.compile(r'wsold(\d+)_rep(\d+)')
files = glob.glob('earthquakeF/agesplit70 EQ S 1 wsold*_rep*.mat')
wsold_map = {'025': 0.25, '05': 0.5, '1': 1.0, '2': 2.0}

per_sa_rows = []
for f in files:
    m = pattern.search(f)
    if not m:
        continue
    wsold_tag, rep = m.group(1), int(m.group(2))
    wsold_val = wsold_map[wsold_tag]

    mat = sio.loadmat(f, variable_names=['HH_data'], simplify_cells=True)
    hh = pd.DataFrame(mat['HH_data'][:, :len(HH_COLS)], columns=HH_COLS)

    is_elderly = hh['n_old'] >= 2
    hh['is_old_old'] = is_elderly & (hh['old_old_count'] >= 1)
    hh['is_young_old'] = is_elderly & (hh['old_old_count'] == 0)

    per_sa = hh.groupby('stat').agg(n_hh=('hh_id', 'count'),
                                     n_old_old=('is_old_old', 'sum'),
                                     n_young_old=('is_young_old', 'sum')).reset_index()
    per_sa['pct_old_old'] = 100 * per_sa['n_old_old'] / per_sa['n_hh']
    per_sa['pct_young_old'] = 100 * per_sa['n_young_old'] / per_sa['n_hh']
    per_sa['wservice_old'] = wsold_val
    per_sa['rep'] = rep
    per_sa_rows.append(per_sa)

all_sa = pd.concat(per_sa_rows, ignore_index=True)
avg_sa = all_sa.groupby(['wservice_old', 'stat'])[['pct_old_old', 'pct_young_old']].mean().reset_index()

shp = gpd.read_file(SHAPE_PATH)
grid = sorted(avg_sa['wservice_old'].unique())

vmax_oo = avg_sa['pct_old_old'].max()
vmax_yo = avg_sa['pct_young_old'].max()
vmin = 0

fig, axes = plt.subplots(2, len(grid), figsize=(5 * len(grid), 10))
for col_i, wsold in enumerate(grid):
    sub = avg_sa[avg_sa['wservice_old'] == wsold]
    merged = shp.merge(sub, left_on='YISHUV_STA', right_on='stat', how='left')

    ax = axes[0, col_i]
    merged.plot(column='pct_young_old', ax=ax, cmap='Oranges', legend=False, vmin=vmin, vmax=vmax_yo,
                edgecolor='black', linewidth=0.5, missing_kwds={'color': 'lightgrey'})
    ax.set_title(f'Young-old, wservice_old={wsold}', fontsize=10)
    ax.set_axis_off()

    ax = axes[1, col_i]
    merged.plot(column='pct_old_old', ax=ax, cmap='Reds', legend=False, vmin=vmin, vmax=vmax_oo,
                edgecolor='black', linewidth=0.5, missing_kwds={'color': 'lightgrey'})
    ax.set_title(f'Old-old, wservice_old={wsold}', fontsize=10)
    ax.set_axis_off()

sm_yo = plt.cm.ScalarMappable(cmap='Oranges', norm=plt.Normalize(vmin=vmin, vmax=vmax_yo))
sm_yo.set_array([])
fig.colorbar(sm_yo, ax=axes[0, :], fraction=0.02, pad=0.02, label='% young-old HH')

sm_oo = plt.cm.ScalarMappable(cmap='Reds', norm=plt.Normalize(vmin=vmin, vmax=vmax_oo))
sm_oo.set_array([])
fig.colorbar(sm_oo, ax=axes[1, :], fraction=0.02, pad=0.02, label='% old-old HH')

fig.suptitle('Elderly subgroup distribution across the wservice_old sweep (avg of 3 reps each)', fontsize=13)
out = 'wservice_old_sweep_maps.png'
fig.savefig(out, dpi=200, bbox_inches='tight')
print(f'[done] {out}')
