"""
analyze_wservice_young_sweep.py
==================================
Analyzes run_wservice_young_sweep.m output: young-old wservice in
{0.5, 0.75, 1.0, 1.5} x old-old wservice_old in {1.0, 1.5}, n=8 reps.

Purpose: find whether/where young-old movers' service-ratio exposure
clears the non-elderly baseline (observed ~0.64-0.66 across every prior
sweep, with young-old always below it at wservice=0.25/0.35). Flags each
cell with whether young-old's mean exceeds that cell's own non-elderly
mean, using a Welch's t-test rather than eyeballing.

Restricts to actual movers (HH_MOVE_TRACK Final_SA != Original_SA), same
reasoning as prior analysis scripts.
"""
import glob
import re
import numpy as np
import pandas as pd
import scipy.io as sio
import matplotlib.pyplot as plt
from scipy import stats

HH_COLS = ['stat', 'hh_id', 'individuals', 'children', 'n_old', 'hh_income',
           'hh_asiron', 'n_cars', 'yeshuv', 'building_id', 'asset_id', 'old_old_count']
BUILD_COLS = ['bldg_id', 'height', 'usage', 'said', 'x', 'y', 'area', 'travel_time',
              'travel_dist', 'year', 'floors', 'yeshuv', 'near_far_b', 'tt_near_b',
              'dist_near_b', 'price_m', 'work_place', 'empty', 'service_ratio',
              'n_hh_in_bldg', 'b_score', 'building_value', 'working_zone']

pattern = re.compile(r'wy(\d+)_wo(\d+)_rep(\d+)')
files = glob.glob('earthquakeF/agesplit70 EQ S 1 wy*_wo*_rep*.mat')
val_map = {'05': 0.5, '075': 0.75, '1': 1.0, '15': 1.5}

rows = []
for f in files:
    m = pattern.search(f)
    if not m:
        continue
    wy_tag, wo_tag, rep = m.group(1), m.group(2), int(m.group(3))
    if wy_tag not in ('05', '075', '1', '15') or wo_tag not in ('1', '15'):
        continue  # skip files from the earlier 2D sweep (wy025/wy035, wo2)
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
        'svc_old_old_movers': hh.loc[oo_m, 'svc'].mean(),
        'svc_young_old_movers': hh.loc[yo_m, 'svc'].mean(),
        'svc_non_elderly_movers': hh.loc[ne_m, 'svc'].mean(),
    })

df = pd.DataFrame(rows).sort_values(['wservice', 'wservice_old', 'rep'])
df.to_csv('wservice_young_sweep_raw.csv', index=False)
print(df.to_string(index=False))

summary = df.groupby(['wservice', 'wservice_old']).agg(['mean', 'std']).reset_index()
summary.columns = ['_'.join(c).rstrip('_') for c in summary.columns]
summary.to_csv('wservice_young_sweep_summary.csv', index=False)
print()
print(summary.to_string(index=False))

print()
print('=' * 78)
print('YOUNG-OLD vs NON-ELDERLY, per cell (Welch t-test)')
print('=' * 78)
for (wy, wo), sub in df.groupby(['wservice', 'wservice_old']):
    yo = sub['svc_young_old_movers'].dropna().values
    ne = sub['svc_non_elderly_movers'].dropna().values
    t, p = stats.ttest_ind(yo, ne, equal_var=False)
    crossed = yo.mean() > ne.mean()
    sig = '*' if p < 0.05 else ' (n.s.)'
    flag = 'YOUNG-OLD ABOVE' if crossed else 'young-old still below'
    print(f'  wservice={wy}, wservice_old={wo}: young-old {yo.mean():.4f} vs non-elderly {ne.mean():.4f} '
          f'-> {flag}, t={t:.2f}, p={p:.3f}{sig}')

print()
print('=' * 78)
print('OLD-OLD vs NON-ELDERLY, per cell (Welch t-test, sanity check -- should stay above)')
print('=' * 78)
for (wy, wo), sub in df.groupby(['wservice', 'wservice_old']):
    oo = sub['svc_old_old_movers'].dropna().values
    ne = sub['svc_non_elderly_movers'].dropna().values
    t, p = stats.ttest_ind(oo, ne, equal_var=False)
    crossed = oo.mean() > ne.mean()
    sig = '*' if p < 0.05 else ' (n.s.)'
    flag = 'OLD-OLD ABOVE' if crossed else 'old-old below'
    print(f'  wservice={wy}, wservice_old={wo}: old-old {oo.mean():.4f} vs non-elderly {ne.mean():.4f} '
          f'-> {flag}, t={t:.2f}, p={p:.3f}{sig}')

# --- plot ---
wo_grid = sorted(df['wservice_old'].unique())
fig, axes = plt.subplots(1, len(wo_grid), figsize=(7 * len(wo_grid), 6), sharey=True)
if len(wo_grid) == 1:
    axes = [axes]
for ax, wo in zip(axes, wo_grid):
    sub = summary[summary['wservice_old'] == wo].sort_values('wservice')
    x = sub['wservice']
    for col, label, color in [('svc_old_old_movers', 'Old-old (70+) movers', 'tab:red'),
                               ('svc_young_old_movers', 'Young-old (65-69) movers', 'tab:orange'),
                               ('svc_non_elderly_movers', 'Non-elderly movers', 'tab:blue')]:
        ax.errorbar(x, sub[f'{col}_mean'], yerr=sub[f'{col}_std'], marker='o', label=label, color=color, capsize=4)
    ax.set_xlabel('wservice (young-old)')
    ax.set_title(f'wservice_old = {wo}', fontsize=11)
    ax.legend(fontsize=9)
axes[0].set_ylabel('Mean building service ratio of current residence (movers only)')
fig.suptitle('Young-old wservice sweep: does raising young-old\'s own weight clear the non-elderly baseline?', fontsize=13)
plt.tight_layout()
plt.savefig('wservice_young_sweep_plot.png', dpi=200)
print('\n[done] wservice_young_sweep_plot.png, wservice_young_sweep_summary.csv, wservice_young_sweep_raw.csv')
