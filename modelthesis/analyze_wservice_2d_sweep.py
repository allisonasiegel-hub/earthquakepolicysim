"""
analyze_wservice_2d_sweep.py
==============================
Analyzes run_wservice_2d_sweep.m output: young-old wservice in {0.25, 0.35}
x old-old wservice_old in {1, 1.5, 2}, 3 reps each. Extends the single-axis
analysis (analyze_wservice_old_sweep.py) with a third group -- non-elderly
-- as a flat baseline, and facets by young-old wservice so both grids show
side by side.

Restricts service-ratio-exposure to actual movers (HH_MOVE_TRACK Final_SA
!= Original_SA), same reasoning as before: wservice/wservice_old only
affect the cross-SA destination-scoring step, so non-movers dilute the
signal with their unchanged initial assignment.
"""
import glob
import re
import numpy as np
import pandas as pd
import scipy.io as sio
import matplotlib.pyplot as plt

HH_COLS = ['stat', 'hh_id', 'individuals', 'children', 'n_old', 'hh_income',
           'hh_asiron', 'n_cars', 'yeshuv', 'building_id', 'asset_id', 'old_old_count']
BUILD_COLS = ['bldg_id', 'height', 'usage', 'said', 'x', 'y', 'area', 'travel_time',
              'travel_dist', 'year', 'floors', 'yeshuv', 'near_far_b', 'tt_near_b',
              'dist_near_b', 'price_m', 'work_place', 'empty', 'service_ratio',
              'n_hh_in_bldg', 'b_score', 'building_value', 'working_zone']

pattern = re.compile(r'wy(\d+)_wo(\d+)_rep(\d+)')
files = glob.glob('earthquakeF/agesplit70 EQ S 1 wy*_wo*_rep*.mat')
val_map = {'025': 0.25, '035': 0.35, '1': 1.0, '15': 1.5, '2': 2.0}

rows = []
for f in files:
    m = pattern.search(f)
    if not m:
        continue
    wy_tag, wo_tag, rep = m.group(1), m.group(2), int(m.group(3))
    wy_val, wo_val = val_map[wy_tag], val_map[wo_tag]

    mat = sio.loadmat(f, variable_names=['HH_data', 'Build_Data', 'HH_MOVE_TRACK'], simplify_cells=True)
    hh = pd.DataFrame(mat['HH_data'][:, :len(HH_COLS)], columns=HH_COLS)
    bd = pd.DataFrame(mat['Build_Data'][:, :len(BUILD_COLS)], columns=BUILD_COLS)
    mt = mat['HH_MOVE_TRACK']

    orig_sa, final_sa = mt[:, 1], mt[:, 3]
    has_final = ~np.isnan(final_sa)
    real_movers = set(mt[has_final & (orig_sa != final_sa), 0].astype(int))
    hh_is_mover = hh['hh_id'].isin(real_movers)

    is_elderly = hh['n_old'] >= 2
    is_old_old = is_elderly & (hh['old_old_count'] >= 1)
    is_young_old = is_elderly & (hh['old_old_count'] == 0)

    svc_by_bldg = bd.drop_duplicates('bldg_id').set_index('bldg_id')['service_ratio']
    hh['svc'] = hh['building_id'].map(svc_by_bldg)

    oo_m = is_old_old & hh_is_mover
    yo_m = is_young_old & hh_is_mover
    ne_m = (~is_elderly) & hh_is_mover

    rows.append({
        'wservice': wy_val, 'wservice_old': wo_val, 'rep': rep,
        'n_old_old': is_old_old.sum(), 'n_young_old': is_young_old.sum(), 'n_non_elderly': (~is_elderly).sum(),
        'n_old_old_movers': oo_m.sum(), 'n_young_old_movers': yo_m.sum(), 'n_non_elderly_movers': ne_m.sum(),
        'pct_old_old_movers': 100 * oo_m.sum() / is_old_old.sum() if is_old_old.sum() else np.nan,
        'pct_young_old_movers': 100 * yo_m.sum() / is_young_old.sum() if is_young_old.sum() else np.nan,
        'pct_non_elderly_movers': 100 * ne_m.sum() / (~is_elderly).sum(),
        'svc_old_old_movers': hh.loc[oo_m, 'svc'].mean(),
        'svc_young_old_movers': hh.loc[yo_m, 'svc'].mean(),
        'svc_non_elderly_movers': hh.loc[ne_m, 'svc'].mean(),
    })

df = pd.DataFrame(rows).sort_values(['wservice', 'wservice_old', 'rep'])
print(df.to_string(index=False))
df.to_csv('wservice_2d_sweep_raw.csv', index=False)

summary = df.groupby(['wservice', 'wservice_old']).agg(['mean', 'std']).reset_index()
summary.columns = ['_'.join(c).rstrip('_') for c in summary.columns]
summary.to_csv('wservice_2d_sweep_summary.csv', index=False)
print()
print(summary.to_string(index=False))

# --- plot: service-ratio exposure, faceted by young-old wservice ---
wy_grid = sorted(df['wservice'].unique())
fig, axes = plt.subplots(1, len(wy_grid), figsize=(7 * len(wy_grid), 6), sharey=True)
if len(wy_grid) == 1:
    axes = [axes]
for ax, wy in zip(axes, wy_grid):
    sub = summary[summary['wservice'] == wy].sort_values('wservice_old')
    x = sub['wservice_old']
    for col, label, color in [('svc_old_old_movers', 'Old-old (70+) movers', 'tab:red'),
                               ('svc_young_old_movers', 'Young-old (65-69) movers', 'tab:orange'),
                               ('svc_non_elderly_movers', 'Non-elderly movers', 'tab:blue')]:
        ax.errorbar(x, sub[f'{col}_mean'], yerr=sub[f'{col}_std'], marker='o', label=label, color=color, capsize=4)
    ax.set_xlabel('wservice_old')
    ax.set_title(f'wservice (young-old) = {wy}', fontsize=11)
    ax.legend(fontsize=9)
axes[0].set_ylabel('Mean building service ratio of current residence (movers only)')
fig.suptitle('Service-ratio exposure vs wservice_old, faceted by young-old wservice', fontsize=13)
plt.tight_layout()
plt.savefig('wservice_2d_sweep_plot.png', dpi=200)
print('\n[done] wservice_2d_sweep_plot.png, wservice_2d_sweep_summary.csv, wservice_2d_sweep_raw.csv')
