"""
plot_allocation.py
===================
Plots every major variable checked by validate_allocation.py, plus SA-level
choropleth maps of elderly household distribution (total elderly, young-old
65-69, old-old 70+), using the shapefile in ../tveriashape/.

This is the pre-simulation view: the synthetic population as built by
main_alloc.m, before any ABM run. For post-simulation plots (SA_* time
series, sweep results, before/after elderly maps), see
plot_sim_results.py in the project root -- that one needs actual sim output
and can't be run yet.

Usage
-----
    python plot_allocation.py
    python plot_allocation.py --mat data_for_model_tmine_agesplit70.mat --out plots_agesplit70
"""

from __future__ import annotations

import argparse
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

from validate_allocation import (
    load_mat, load_census, HH_COLS, IND_COLS, KID, ADULT, OLD,
    NOT_LABOR_FORCE, WANTS_WORK, WORKING, LOCAL_WORK_SENTINEL,
)

HERE = os.path.dirname(os.path.abspath(__file__))
SHAPE_PATH = os.path.join(HERE, '..', 'tveriashape', 'tveriastats.shp')


# ---------------------------------------------------------------------------
# bar-chart helper: simulated vs census, grouped
# ---------------------------------------------------------------------------

def bar_compare(ax, labels, sim_vals, census_vals, title, ylabel='%'):
    x = np.arange(len(labels))
    w = 0.35
    ax.bar(x - w / 2, sim_vals, w, label='Simulated', color='tab:blue')
    if census_vals is not None:
        ax.bar(x + w / 2, census_vals, w, label='Census', color='tab:orange')
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=45, ha='right', fontsize=8)
    ax.set_title(title, fontsize=11)
    ax.set_ylabel(ylabel)
    ax.legend(fontsize=8)


# ---------------------------------------------------------------------------
# plot sections
# ---------------------------------------------------------------------------

def plot_demographics(d, census, pdf):
    HH, IND = d['HH'], d['IND']
    fig, axes = plt.subplots(2, 2, figsize=(11, 9))

    # age shares
    n = len(IND)
    kid_pct = 100 * (IND['age_group'] == KID).sum() / n
    adult_pct = 100 * (IND['age_group'] == ADULT).sum() / n
    old_pct = 100 * (IND['age_group'] == OLD).sum() / n
    pop_cols = ['demog_yishuv.age_0_14', 'demog_yishuv.age_15_19',
                'demog_yishuv.age_20_29', 'demog_yishuv.age_30_64', 'demog_yishuv.age_65_up']
    census_pop = census[pop_cols].sum()
    total_pop = census_pop.sum()
    c_kid = 100 * (census_pop['demog_yishuv.age_0_14'] + census_pop['demog_yishuv.age_15_19']) / total_pop
    c_adult = 100 * (census_pop['demog_yishuv.age_20_29'] + census_pop['demog_yishuv.age_30_64']) / total_pop
    c_old = 100 * census_pop['demog_yishuv.age_65_up'] / total_pop
    bar_compare(axes[0, 0], ['Kid', 'Adult', 'Elderly'], [kid_pct, adult_pct, old_pct],
                [c_kid, c_adult, c_old], 'Age group shares')

    # young-old / old-old split, if present
    if 'is_old_old' in IND.columns:
        elderly = IND[IND['age_group'] == OLD]
        yo = 100 * (elderly['is_old_old'] == 0).sum() / len(elderly) if len(elderly) else np.nan
        oo = 100 * (elderly['is_old_old'] == 1).sum() / len(elderly) if len(elderly) else np.nan
        total_pop_sa = census[pop_cols].sum(axis=1)
        age_70up = (census['demog_yishuv.age_70_79_pcnt'] + census['demog_yishuv.age_80_pcnt']) / 100 * total_pop_sa
        c_oo = 100 * age_70up.sum() / census['demog_yishuv.age_65_up'].sum()
        c_yo = 100 - c_oo
        bar_compare(axes[0, 1], ['Young-old (65-69)', 'Old-old (70+)'], [yo, oo], [c_yo, c_oo],
                    'Elderly age split (share of all elderly)')
    else:
        axes[0, 1].axis('off')
        axes[0, 1].text(0.5, 0.5, 'is_old_old not present\nin this .mat file',
                         ha='center', va='center', fontsize=10)

    # HH size distribution
    size_map = {1: 'households.size1_pcnt', 2: 'households.size2_pcnt', 3: 'households.size3_pcnt',
                4: 'households.size4_pcnt', 5: 'households.size5_pcnt', 6: 'households.size6_pcnt'}
    sizes_capped = HH['individuals'].clip(upper=7)
    sim_vals, c_vals, labels = [], [], []
    for k, col in size_map.items():
        sim_vals.append(100 * (sizes_capped == k).sum() / len(HH))
        c_vals.append(census[col].mean())
        labels.append(str(k))
    sim_vals.append(100 * (sizes_capped >= 7).sum() / len(HH))
    c_vals.append(census['households.size7up_pcnt'].mean())
    labels.append('7+')
    bar_compare(axes[1, 0], labels, sim_vals, c_vals, 'Household size distribution', ylabel='% of HH')

    # HH with children / elderly
    sim_child = 100 * (HH['children'] > 0).sum() / len(HH)
    sim_eld = 100 * (HH['n_old'] > 0).sum() / len(HH)
    bar_compare(axes[1, 1], ['HH with children', 'HH with elderly (65+)'],
                [sim_child, sim_eld],
                [census['households.hh0_17_pcnt'].mean(), census['households.hh65_pcnt'].mean()],
                'Household composition', ylabel='% of HH')

    plt.tight_layout()
    fig.savefig(os.path.join(out_dir, 'demographics.png'), dpi=200)
    pdf.savefig(fig)
    plt.close(fig)


def plot_disabilities(d, census, pdf):
    IND = d['IND']
    fig, ax = plt.subplots(figsize=(7, 5))
    cols = [('dis_hear', 'disabilities.hear5_pcnt', 'Hearing'),
            ('dis_see', 'disabilities.see5_pcnt', 'Seeing'),
            ('dis_reme', 'disabilities.remember5_pcnt', 'Remembering'),
            ('dis_dress', 'disabilities.dress5_pcnt', 'Dressing'),
            ('dis_walk', 'disabilities.walk5_pcnt', 'Walking')]
    labels = [c[2] for c in cols]
    sim_vals = [100 * (IND[c[0]] > 0).sum() / len(IND) for c in cols]
    c_vals = [census[c[1]].mean() for c in cols]
    bar_compare(ax, labels, sim_vals, c_vals, 'Disability rates')
    plt.tight_layout()
    fig.savefig(os.path.join(out_dir, 'disabilities.png'), dpi=200)
    pdf.savefig(fig)
    plt.close(fig)


def plot_income(d, census, pdf):
    IND, HH = d['IND'], d['HH']
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))

    labor_force = IND[IND['working_status'].isin([WANTS_WORK, WORKING])]
    deciles = list(range(1, 11))
    sim_vals = [100 * (labor_force['asiron'] == k).sum() / len(labor_force) for k in deciles]
    c_vals = [census[f'income.q{k}'].mean() for k in deciles]
    bar_compare(axes[0], [str(k) for k in deciles], sim_vals, c_vals,
                'Individual income decile shares (labor force)', ylabel='%')

    car_1up = 100 * (HH['n_cars'] >= 1).sum() / len(HH)
    car_2up = 100 * (HH['n_cars'] >= 2).sum() / len(HH)
    bar_compare(axes[1], ['>=1 car', '>=2 cars'], [car_1up, car_2up],
                [census['durable_goods.Vehicle1up_pcnt'].mean(), census['durable_goods.Vehicle2up_pcnt'].mean()],
                'Car ownership', ylabel='% of HH')

    plt.tight_layout()
    fig.savefig(os.path.join(out_dir, 'income_cars.png'), dpi=200)
    pdf.savefig(fig)
    plt.close(fig)


def plot_labor(d, census, pdf):
    IND = d['IND']
    fig, ax = plt.subplots(figsize=(7, 5))

    labor_pool = IND[IND['age_group'] >= ADULT]
    in_lf = labor_pool['working_status'].isin([WANTS_WORK, WORKING])
    lfpr = 100 * in_lf.sum() / len(labor_pool)
    lf = labor_pool[in_lf]
    emp = 100 * (lf['working_status'] == WORKING).sum() / len(lf) if len(lf) else np.nan

    workers = IND[IND['working_status'] == WORKING]
    n_w = len(workers)
    outside = 100 * (workers['stat_wp'] == LOCAL_WORK_SENTINEL).sum() / n_w if n_w else np.nan
    within = 100 - outside if n_w else np.nan

    labels = ['Labor force\nparticipation', 'Employment rate\n(of labor force)',
              'Outside-locality\nshare (comm99)', 'Within-locality\nshare (comm31)']
    sim_vals = [lfpr, emp, outside, within]
    c_vals = [census['LaborForce.LaborForceY_pcnt'].mean(), census['LaborForce.Wrk2008Y_pcnt'].mean(),
              100 * census['comm99'].mean(), 100 * (1 - census['comm99']).mean()]
    bar_compare(ax, labels, sim_vals, c_vals, 'Labor force & commuting')
    plt.tight_layout()
    fig.savefig(os.path.join(out_dir, 'labor.png'), dpi=200)
    pdf.savefig(fig)
    plt.close(fig)


# ---------------------------------------------------------------------------
# elderly maps
# ---------------------------------------------------------------------------

def plot_elderly_maps(d, pdf):
    try:
        import geopandas as gpd
    except ImportError:
        print('[skip] geopandas not installed -- skipping elderly maps')
        return

    HH = d['HH']
    shp = gpd.read_file(SHAPE_PATH)

    is_elderly_hh = HH['n_old'] >= 2  # encoded 0/3/6, matches HH_data(:,5)>=2 convention used model-wide
    has_split = 'old_old_count' in HH.columns

    per_sa = HH.groupby('stat').size().rename('n_hh').to_frame()
    per_sa['n_elderly_hh'] = HH[is_elderly_hh].groupby('stat').size()
    per_sa['n_elderly_hh'] = per_sa['n_elderly_hh'].fillna(0)
    per_sa['pct_elderly_hh'] = 100 * per_sa['n_elderly_hh'] / per_sa['n_hh']

    if has_split:
        is_old_old_hh = is_elderly_hh & (HH['old_old_count'] >= 1)
        is_young_old_hh = is_elderly_hh & (HH['old_old_count'] == 0)
        per_sa['n_old_old_hh'] = HH[is_old_old_hh].groupby('stat').size()
        per_sa['n_young_old_hh'] = HH[is_young_old_hh].groupby('stat').size()
        per_sa[['n_old_old_hh', 'n_young_old_hh']] = per_sa[['n_old_old_hh', 'n_young_old_hh']].fillna(0)
        per_sa['pct_old_old_hh'] = 100 * per_sa['n_old_old_hh'] / per_sa['n_hh']
        per_sa['pct_young_old_hh'] = 100 * per_sa['n_young_old_hh'] / per_sa['n_hh']

    merged = shp.merge(per_sa, left_on='YISHUV_STA', right_on='stat', how='left')

    panels = [('pct_elderly_hh', 'All elderly households (%)', 'Purples')]
    if has_split:
        panels += [
            ('pct_young_old_hh', 'Young-old (65-69) households (%)', 'Blues'),
            ('pct_old_old_hh', 'Old-old (70+) households (%)', 'Reds'),
        ]

    fig, axes = plt.subplots(1, len(panels), figsize=(6 * len(panels), 6))
    if len(panels) == 1:
        axes = [axes]
    for ax, (col, title, cmap) in zip(axes, panels):
        merged.plot(column=col, ax=ax, cmap=cmap, legend=True,
                    edgecolor='black', linewidth=0.5,
                    missing_kwds={'color': 'lightgrey'})
        ax.set_title(title, fontsize=11)
        ax.set_axis_off()
    plt.tight_layout()
    fig.savefig(os.path.join(out_dir, 'elderly_maps.png'), dpi=200)
    pdf.savefig(fig)
    plt.close(fig)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    global out_dir
    ap = argparse.ArgumentParser()
    ap.add_argument('--mat', default=os.path.join(HERE, 'data_for_model_tmine.mat'))
    ap.add_argument('--census', default=os.path.join(HERE, '..', 'TVR', 'sa_data_b7.csv'))
    ap.add_argument('--out', default=os.path.join(HERE, 'plots_allocation'))
    args = ap.parse_args()

    out_dir = args.out
    os.makedirs(out_dir, exist_ok=True)

    d = load_mat(args.mat)
    census = load_census(args.census)

    pdf_path = os.path.join(out_dir, 'allocation_plots.pdf')
    with PdfPages(pdf_path) as pdf:
        plot_demographics(d, census, pdf)
        plot_disabilities(d, census, pdf)
        plot_income(d, census, pdf)
        plot_labor(d, census, pdf)
        plot_elderly_maps(d, pdf)

    print(f'[done] plots -> {os.path.abspath(out_dir)}; combined PDF -> {pdf_path}')


if __name__ == '__main__':
    main()
