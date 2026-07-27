"""
population_balance_wy1_wo15.py
=================================
Population balance (start vs end of sim) for the wservice=1.0,
wservice_old=1.5 combo, split old-old / young-old / non-elderly.

Elderly vs non-elderly start/end counts come from Metric_Track (col 6 =
elderly pop, col 7 = non-elderly pop, 1-indexed; step 1 = start, last
non-nan step = end). The old-old/young-old split isn't tracked over time
in Metric_Track, so the START split is read from the initial data file
(data_for_model_tmine_agesplit70.mat, same initial household composition
for every replicate) and the END split is read from each replicate's
final HH_data (old_old_count column).

Usage: python population_balance_wy1_wo15.py
"""
import glob
import re
import numpy as np
import pandas as pd
import scipy.io as sio

HH_COLS = ['stat', 'hh_id', 'individuals', 'children', 'n_old', 'hh_income',
           'hh_asiron', 'n_cars', 'yeshuv', 'building_id', 'asset_id', 'old_old_count']

# --- starting old-old / young-old split (same for every replicate) ---
init = sio.loadmat('data_for_model_tmine_agesplit70.mat', variable_names=['HH_data'], simplify_cells=True)
hh0 = pd.DataFrame(init['HH_data'][:, :len(HH_COLS)], columns=HH_COLS)
is_elderly0 = hh0['n_old'] >= 2
n_old_old_0 = (is_elderly0 & (hh0['old_old_count'] >= 1)).sum()
n_young_old_0 = (is_elderly0 & (hh0['old_old_count'] == 0)).sum()
n_non_elderly_0 = (~is_elderly0).sum()
print(f'Starting population (same for all reps): old-old={n_old_old_0}, young-old={n_young_old_0}, '
      f'non-elderly={n_non_elderly_0}, total={len(hh0)}')
print()

pattern = re.compile(r'wy1_wo15_rep(\d+)')
files = glob.glob('earthquakeF/agesplit70 EQ S 1 wy1_wo15_rep*.mat')

rows = []
for f in files:
    m = pattern.search(f)
    if not m:
        continue
    rep = int(m.group(1))

    mat = sio.loadmat(f, variable_names=['HH_data', 'Metric_Track'], simplify_cells=True)
    hh = pd.DataFrame(mat['HH_data'][:, :len(HH_COLS)], columns=HH_COLS)
    mt = mat['Metric_Track']

    is_elderly = hh['n_old'] >= 2
    n_old_old = (is_elderly & (hh['old_old_count'] >= 1)).sum()
    n_young_old = (is_elderly & (hh['old_old_count'] == 0)).sum()
    n_non_elderly = (~is_elderly).sum()

    elderly_track = mt[:, 5]
    non_elderly_track = mt[:, 6]
    idx = np.where(~np.isnan(elderly_track))[0]
    elderly_start, elderly_end = elderly_track[idx[0]], elderly_track[idx[-1]]
    ne_start, ne_end = non_elderly_track[idx[0]], non_elderly_track[idx[-1]]

    rows.append({
        'rep': rep,
        'end_old_old': n_old_old, 'end_young_old': n_young_old, 'end_non_elderly': n_non_elderly,
        'end_total': len(hh),
        'elderly_track_start': elderly_start, 'elderly_track_end': elderly_end,
        'non_elderly_track_start': ne_start, 'non_elderly_track_end': ne_end,
    })

df = pd.DataFrame(rows).sort_values('rep')
df['end_old_old_pct_chg'] = 100 * (df['end_old_old'] - n_old_old_0) / n_old_old_0
df['end_young_old_pct_chg'] = 100 * (df['end_young_old'] - n_young_old_0) / n_young_old_0
df['end_non_elderly_pct_chg'] = 100 * (df['end_non_elderly'] - n_non_elderly_0) / n_non_elderly_0
print(df.to_string(index=False))
print()
print('=== mean +/- std across reps ===')
summary_cols = ['end_old_old', 'end_young_old', 'end_non_elderly', 'end_total',
                'end_old_old_pct_chg', 'end_young_old_pct_chg', 'end_non_elderly_pct_chg']
summary = df[summary_cols].agg(['mean', 'std'])
print(summary.to_string())
df.to_csv('population_balance_wy1_wo15.csv', index=False)
print('\n[done] population_balance_wy1_wo15.csv')
