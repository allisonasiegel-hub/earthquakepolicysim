"""
analyze_wservice_old_sweep.py
==============================
Analyzes the run_wservice_old_sweep.m output: for each wservice_old value
(young-old wservice held fixed at 0.25), splits final households into
young-old (65-69) vs old-old (70+) using HH_data's old_old_count column
(col 12), and checks whether stronger wservice_old actually moved old-old
households toward higher-service-ratio buildings/SAs -- Metric_Track only
tracks elderly vs non-elderly, not this finer split, so this bypasses it
and reads directly from each run's final HH_data/Build_Data.

Usage: python analyze_wservice_old_sweep.py
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
    mt = mat['HH_MOVE_TRACK']  # cols: HH_ID, Original_SA, Elderly_Count, Final_SA, Displaced, Left_City

    # wservice/wservice_old only affect the cross-SA destination-scoring
    # step (find_new_house_sa_score.m via the yeshuv/other-yeshuv pool) --
    # not the primary within-SA matching. Restrict to households whose
    # Final_SA actually differs from Original_SA, i.e. genuinely went
    # through that scoring pathway and relocated because of it.
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
        'n_young_old': is_young_old.sum(), 'n_old_old': is_old_old.sum(),
        'n_young_old_movers': yo_movers.sum(), 'n_old_old_movers': oo_movers.sum(),
        'mean_svc_young_old_movers': hh.loc[yo_movers, 'svc'].mean(),
        'mean_svc_old_old_movers': hh.loc[oo_movers, 'svc'].mean(),
        'mean_svc_non_elderly_movers': hh.loc[ne_movers, 'svc'].mean(),
    })

df = pd.DataFrame(rows).sort_values(['wservice_old', 'rep'])
print(df.to_string(index=False))

summary = df.groupby('wservice_old')[['mean_svc_young_old_movers', 'mean_svc_old_old_movers', 'mean_svc_non_elderly_movers']].agg(['mean', 'std'])
print()
print(summary.to_string())
summary.to_csv('wservice_old_sweep_summary.csv')

fig, ax = plt.subplots(figsize=(8, 6))
x = summary.index
for col, label, color in [('mean_svc_old_old_movers', 'Old-old (70+) movers', 'tab:red'),
                           ('mean_svc_young_old_movers', 'Young-old (65-69) movers', 'tab:orange'),
                           ('mean_svc_non_elderly_movers', 'Non-elderly movers', 'tab:blue')]:
    y = summary[(col, 'mean')]
    yerr = summary[(col, 'std')]
    ax.errorbar(x, y, yerr=yerr, marker='o', label=label, color=color, capsize=4)
ax.set_xlabel('wservice_old (young-old wservice fixed at 0.25)')
ax.set_ylabel('Mean building service ratio of current residence')
ax.set_title('Service-ratio exposure vs wservice_old -- movers only\n(HH whose Final_SA differs from Original_SA)')
ax.legend()
plt.tight_layout()
plt.savefig('wservice_old_sweep_plot_movers.png', dpi=200)
print('\n[done] wservice_old_sweep_plot_movers.png, wservice_old_sweep_summary.csv')
