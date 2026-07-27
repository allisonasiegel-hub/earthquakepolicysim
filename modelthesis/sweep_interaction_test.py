"""
sweep_interaction_test.py
============================
Formal two-way ANOVA (wservice x wservice_old) on the n=8 2D sweep, to
answer directly: is there any combination/interaction where BOTH wservice
(young-old) and wservice_old jointly reach significance, or does
wservice_old's effect (confirmed significant for old-old in
sweep_significance_test_2d.py) depend on the wservice level at all?

Usage: python sweep_interaction_test.py
(run analyze_wservice_2d_sweep.py first to produce wservice_2d_sweep_raw.csv)
"""
import pandas as pd
import statsmodels.api as sm
from statsmodels.formula.api import ols

df = pd.read_csv('wservice_2d_sweep_raw.csv')
groups = ['svc_old_old_movers', 'svc_young_old_movers', 'svc_non_elderly_movers']

for group in groups:
    print('=' * 78)
    print(f'TWO-WAY ANOVA: {group} ~ wservice * wservice_old  (n={len(df)})')
    print('=' * 78)
    model = ols(f'{group} ~ C(wservice) * C(wservice_old)', data=df).fit()
    table = sm.stats.anova_lm(model, typ=2)
    print(table.to_string())
    print()
