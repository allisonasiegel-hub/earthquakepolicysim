"""
sweep_significance_test_2d.py
================================
Same logic as sweep_significance_test.py, applied to the 2D sweep
(wservice_2d_sweep_raw.csv from analyze_wservice_2d_sweep.py):
  1. Pairwise Welch's t-test between wservice_old grid values (1, 1.5, 2),
     separately within each wservice (young-old) facet -- n=3 per point.
  2. Pearson correlation of svc vs wservice_old across all 9 points per
     facet (monotonic trend test, more power than pairwise at small n).
  3. Pairwise Welch's t-test for the wservice (young-old) effect itself
     (0.25 vs 0.35), pooling across the wservice_old grid -- n=9 vs n=9.

Usage: python sweep_significance_test_2d.py
(run analyze_wservice_2d_sweep.py first to produce wservice_2d_sweep_raw.csv)
"""
import pandas as pd
from scipy import stats
from itertools import combinations

df = pd.read_csv('wservice_2d_sweep_raw.csv')
groups = ['svc_old_old_movers', 'svc_young_old_movers', 'svc_non_elderly_movers']

n_per_cell = df.groupby(['wservice', 'wservice_old']).size().iloc[0]
n_per_wservice = df.groupby('wservice').size().iloc[0]

print('=' * 78)
print(f'PAIRWISE WELCH T-TESTS on wservice_old, WITHIN each young-old wservice facet (n={n_per_cell} vs n={n_per_cell})')
print('=' * 78)
for wy in sorted(df['wservice'].unique()):
    sub = df[df['wservice'] == wy]
    grid = sorted(sub['wservice_old'].unique())
    for group in groups:
        print(f'\n--- wservice={wy}, {group} ---')
        for a, b in combinations(grid, 2):
            xa = sub.loc[sub['wservice_old'] == a, group].dropna().values
            xb = sub.loc[sub['wservice_old'] == b, group].dropna().values
            if len(xa) < 2 or len(xb) < 2:
                continue
            t, p = stats.ttest_ind(xa, xb, equal_var=False)
            sig = '*' if p < 0.05 else ' (n.s.)'
            print(f'  wservice_old {a} vs {b}: mean {xa.mean():.4f} vs {xb.mean():.4f}, '
                  f't={t:.2f}, p={p:.3f}{sig}')

print()
print('=' * 78)
print('MONOTONIC TREND TEST (Pearson r, svc vs wservice_old, n=3*reps per facet)')
print('=' * 78)
for wy in sorted(df['wservice'].unique()):
    sub = df[df['wservice'] == wy]
    print(f'\n--- wservice={wy} ---')
    for group in groups:
        s = sub[['wservice_old', group]].dropna()
        r, p = stats.pearsonr(s['wservice_old'], s[group])
        sig = '*' if p < 0.05 else ' (n.s.)'
        print(f'  {group}: r={r:.3f}, p={p:.3f}{sig}  (n={len(s)})')

print()
print('=' * 78)
print(f'WSERVICE (YOUNG-OLD) EFFECT: 0.25 vs 0.35, pooled across wservice_old grid (n={n_per_wservice} vs n={n_per_wservice})')
print('=' * 78)
for group in groups:
    xa = df.loc[df['wservice'] == 0.25, group].dropna().values
    xb = df.loc[df['wservice'] == 0.35, group].dropna().values
    t, p = stats.ttest_ind(xa, xb, equal_var=False)
    sig = '*' if p < 0.05 else ' (n.s.)'
    print(f'  {group}: mean {xa.mean():.4f} (wy=0.25) vs {xb.mean():.4f} (wy=0.35), '
          f't={t:.2f}, p={p:.3f}{sig}')
