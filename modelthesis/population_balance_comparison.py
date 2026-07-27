"""
population_balance_comparison.py
===================================
Compares population growth rates between the wservice=1.0/wservice_old=1.5
combo (n=16) and the true no-behavioral-changes baseline (n=8), split
old-old/young-old/non-elderly, with a proper two-sample Welch's t-test on
each subgroup instead of eyeballing a single baseline run.
"""
import glob
import re
import numpy as np
import pandas as pd
import scipy.io as sio
from scipy import stats

HH_COLS = ['stat', 'hh_id', 'individuals', 'children', 'n_old', 'hh_income',
           'hh_asiron', 'n_cars', 'yeshuv', 'building_id', 'asset_id', 'old_old_count']

init = sio.loadmat('data_for_model_tmine_agesplit70.mat', variable_names=['HH_data'], simplify_cells=True)
hh0 = pd.DataFrame(init['HH_data'][:, :len(HH_COLS)], columns=HH_COLS)
is_elderly0 = hh0['n_old'] >= 2
n_old_old_0 = (is_elderly0 & (hh0['old_old_count'] >= 1)).sum()
n_young_old_0 = (is_elderly0 & (hh0['old_old_count'] == 0)).sum()
n_non_elderly_0 = (~is_elderly0).sum()
n_total_0 = len(hh0)


def load_scenario(glob_pattern, label):
    files = glob.glob(glob_pattern)
    rows = []
    for f in files:
        mat = sio.loadmat(f, variable_names=['HH_data'], simplify_cells=True)
        hh = pd.DataFrame(mat['HH_data'][:, :len(HH_COLS)], columns=HH_COLS)
        is_elderly = hh['n_old'] >= 2
        n_old_old = (is_elderly & (hh['old_old_count'] >= 1)).sum()
        n_young_old = (is_elderly & (hh['old_old_count'] == 0)).sum()
        n_non_elderly = (~is_elderly).sum()
        n_total = len(hh)
        rows.append({
            'scenario': label,
            'old_old_pct': 100 * (n_old_old - n_old_old_0) / n_old_old_0,
            'young_old_pct': 100 * (n_young_old - n_young_old_0) / n_young_old_0,
            'non_elderly_pct': 100 * (n_non_elderly - n_non_elderly_0) / n_non_elderly_0,
            'total_pct': 100 * (n_total - n_total_0) / n_total_0,
        })
    return pd.DataFrame(rows)


baseline = load_scenario('earthquakeF/agesplit70 EQ S 1 baseline_100steps_v3_rep*.mat', 'baseline')
behavioral = load_scenario('earthquakeF/agesplit70 EQ S 1 wy1_wo15_rep*.mat', 'wy1.0_wo1.5')

print(f'baseline n={len(baseline)}, behavioral n={len(behavioral)}')
print()

cols = ['old_old_pct', 'young_old_pct', 'non_elderly_pct', 'total_pct']
summary = pd.concat([baseline, behavioral]).groupby('scenario')[cols].agg(['mean', 'std'])
print(summary.to_string())
print()

print('=' * 78)
print('WELCH T-TESTS: baseline vs wservice=1.0/wservice_old=1.5')
print('=' * 78)
for col in cols:
    a = baseline[col].values
    b = behavioral[col].values
    t, p = stats.ttest_ind(b, a, equal_var=False)
    sig = '*' if p < 0.05 else ' (n.s.)'
    print(f'  {col}: baseline {a.mean():.3f}% (n={len(a)}) vs behavioral {b.mean():.3f}% (n={len(b)}), '
          f'diff={b.mean()-a.mean():+.3f}pp, t={t:.2f}, p={p:.3f}{sig}')
