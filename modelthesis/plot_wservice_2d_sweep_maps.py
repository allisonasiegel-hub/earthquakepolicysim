"""
plot_wservice_2d_sweep_maps.py
================================
Movers-destination maps for the 2D sweep (young-old wservice x old-old
wservice_old). One figure per young-old wservice value, each showing
young-old and old-old mover destinations across the old-old grid, on a
shared color scale within each figure so panels are comparable.
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

pattern = re.compile(r'wy(\d+)_wo(\d+)_rep(\d+)')
files = glob.glob('earthquakeF/agesplit70 EQ S 1 wy*_wo*_rep*.mat')
val_map = {'025': 0.25, '035': 0.35, '1': 1.0, '15': 1.5, '2': 2.0}

per_sa_rows = []
for f in files:
    m = pattern.search(f)
    if not m:
        continue
    wy_tag, wo_tag, rep = m.group(1), m.group(2), int(m.group(3))
    wy_val, wo_val = val_map[wy_tag], val_map[wo_tag]

    mat = sio.loadmat(f, variable_names=['HH_data', 'HH_MOVE_TRACK'], simplify_cells=True)
    hh = pd.DataFrame(mat['HH_data'][:, :len(HH_COLS)], columns=HH_COLS)
    mt = mat['HH_MOVE_TRACK']

    orig_sa, final_sa = mt[:, 1], mt[:, 3]
    has_final = ~np.isnan(final_sa)
    real_movers = set(mt[has_final & (orig_sa != final_sa), 0].astype(int))
    hh_is_mover = hh['hh_id'].isin(real_movers)

    is_elderly = hh['n_old'] >= 2
    hh['is_old_old'] = is_elderly & (hh['old_old_count'] >= 1) & hh_is_mover
    hh['is_young_old'] = is_elderly & (hh['old_old_count'] == 0) & hh_is_mover

    per_sa = hh.groupby('stat').agg(n_old_old=('is_old_old', 'sum'),
                                     n_young_old=('is_young_old', 'sum')).reset_index()
    tot_oo, tot_yo = hh['is_old_old'].sum(), hh['is_young_old'].sum()
    per_sa['pct_old_old_movers'] = 100 * per_sa['n_old_old'] / tot_oo if tot_oo else 0
    per_sa['pct_young_old_movers'] = 100 * per_sa['n_young_old'] / tot_yo if tot_yo else 0
    per_sa['wservice'] = wy_val
    per_sa['wservice_old'] = wo_val
    per_sa['rep'] = rep
    per_sa_rows.append(per_sa)

all_sa = pd.concat(per_sa_rows, ignore_index=True)
avg_sa = all_sa.groupby(['wservice', 'wservice_old', 'stat'])[['pct_old_old_movers', 'pct_young_old_movers']].mean().reset_index()

shp = gpd.read_file(SHAPE_PATH)
wy_grid = sorted(avg_sa['wservice'].unique())
wo_grid = sorted(avg_sa['wservice_old'].unique())

vmax_oo = avg_sa['pct_old_old_movers'].max()
vmax_yo = avg_sa['pct_young_old_movers'].max()
vmin = 0

for wy in wy_grid:
    fig, axes = plt.subplots(2, len(wo_grid), figsize=(5 * len(wo_grid), 10))
    for col_i, wo in enumerate(wo_grid):
        sub = avg_sa[(avg_sa['wservice'] == wy) & (avg_sa['wservice_old'] == wo)]
        merged = shp.merge(sub, left_on='YISHUV_STA', right_on='stat', how='left')

        ax = axes[0, col_i]
        merged.plot(column='pct_young_old_movers', ax=ax, cmap='Oranges', legend=False, vmin=vmin, vmax=vmax_yo,
                    edgecolor='black', linewidth=0.5, missing_kwds={'color': 'lightgrey'})
        ax.set_title(f'Young-old movers, wservice_old={wo}', fontsize=10)
        ax.set_axis_off()

        ax = axes[1, col_i]
        merged.plot(column='pct_old_old_movers', ax=ax, cmap='Reds', legend=False, vmin=vmin, vmax=vmax_oo,
                    edgecolor='black', linewidth=0.5, missing_kwds={'color': 'lightgrey'})
        ax.set_title(f'Old-old movers, wservice_old={wo}', fontsize=10)
        ax.set_axis_off()

    sm_yo = plt.cm.ScalarMappable(cmap='Oranges', norm=plt.Normalize(vmin=vmin, vmax=vmax_yo))
    sm_yo.set_array([])
    fig.colorbar(sm_yo, ax=axes[0, :], fraction=0.02, pad=0.02, label='% of young-old movers landing in this SA')

    sm_oo = plt.cm.ScalarMappable(cmap='Reds', norm=plt.Normalize(vmin=vmin, vmax=vmax_oo))
    sm_oo.set_array([])
    fig.colorbar(sm_oo, ax=axes[1, :], fraction=0.02, pad=0.02, label='% of old-old movers landing in this SA')

    fig.suptitle(f'Elderly mover destinations, young-old wservice={wy} (avg of 3 reps each)', fontsize=13)
    out = f'wservice_2d_sweep_maps_wy{str(wy).replace(".", "")}.png'
    fig.savefig(out, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f'[done] {out}')
