"""
sweep_significance_test.py
=============================
Formal significance testing for the wservice_old 1D sweep (movers-only
service-ratio exposure), to answer: with only 3 replicates per grid point,
can we actually tell these values apart?

Re-extracts raw per-replicate values (same logic as
analyze_wservice_old_sweep.py, but keeps the raw per-rep rows instead of
just the mean/std summary), then runs:
  1. Pairwise Welch's t-test (unequal variance, appropriate for n=3 vs n=3)
     between every pair of wservice_old grid values, for each subgroup.
  2. Pearson correlation of subgroup svc vs wservice_old across all 12
     points (4 grid values x 3 reps) -- tests for a monotonic trend, which
     has more power than pairwise comparisons at small n.

Usage: python sweep_significance_test.py
"""
import glob
import re
import numpy as np
import pandas as pd
import scipy.io as sio
from scipy import stats
from itertools import combinations

HH_COLS = ['stat', 'hh_id', 'individuals', 'children', 'n_old', 'hh_income',
           'hh_asiron', 'n_cars', 'yeshuv', 'building_id', 'asset_id', 'old_old_count']
BUILD_COLS = ['bldg_id', 'height', 'usage', 'said', 'x', 'y', 'area', 'travel_time',
              'travel_dist', 'year', 'floors', 'yeshuv', 'near_far_b', 'tt_near_b',
              'dist_near_b', 'price_m', 'work_place', 'empty', 'service_ratio',
              'n_hh_in_bldg', 'b_score', 'building_value', 'working_zone']

pattern = re.compile(r'wsold(\d+)_rep(\d+)')
files = glob.glob('earthquakeF/agesplit70 EQ S 1 wsold*_rep*.mat')

rows = []
for f in files:
    m = pattern.search(f)
    if not m:
        continue
    wsold_tag, rep = m.group(1), int(m.group(2))
    wsold_val = {'025': 0.25, '05': 0.5, '1': 1.0, '2': 2.0}[wsold_tag]

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

    yo_movers = is_young_old & hh_is_mover
    oo_movers = is_old_old & hh_is_mover
    ne_movers = (~is_elderly) & hh_is_mover

    rows.append({
        'wservice_old': wsold_val, 'rep': rep,
        'n_old_old_movers': oo_movers.sum(), 'n_young_old_movers': yo_movers.sum(),
        'svc_old_old': hh.loc[oo_movers, 'svc'].mean(),
        'svc_young_old': hh.loc[yo_movers, 'svc'].mean(),
        'svc_non_elderly': hh.loc[ne_movers, 'svc'].mean(),
    })

df = pd.DataFrame(rows).sort_values(['wservice_old', 'rep'])
df.to_csv('wservice_old_sweep_raw.csv', index=False)
print(df.to_string(index=False))
print()

grid = sorted(df['wservice_old'].unique())
groups = ['svc_old_old', 'svc_young_old', 'svc_non_elderly']

print('=' * 78)
print('PAIRWISE WELCH T-TESTS (unequal variance, n=3 vs n=3 per point)')
print('=' * 78)
for group in groups:
    print(f'\n--- {group} ---')
    for a, b in combinations(grid, 2):
        xa = df.loc[df['wservice_old'] == a, group].dropna().values
        xb = df.loc[df['wservice_old'] == b, group].dropna().values
        if len(xa) < 2 or len(xb) < 2:
            continue
        t, p = stats.ttest_ind(xa, xb, equal_var=False)
        sig = '*' if p < 0.05 else (' (n.s.)')
        print(f'  wservice_old {a} vs {b}: mean {xa.mean():.4f} vs {xb.mean():.4f}, '
              f't={t:.2f}, p={p:.3f}{sig}')

print()
print('=' * 78)
print('MONOTONIC TREND TEST (Pearson correlation, svc vs wservice_old, all 12 points)')
print('=' * 78)
for group in groups:
    sub = df[['wservice_old', group]].dropna()
    r, p = stats.pearsonr(sub['wservice_old'], sub[group])
    sig = '*' if p < 0.05 else ' (n.s.)'
    print(f'  {group}: r={r:.3f}, p={p:.3f}{sig}  (n={len(sub)})')

print()
print('[done] wservice_old_sweep_raw.csv')
