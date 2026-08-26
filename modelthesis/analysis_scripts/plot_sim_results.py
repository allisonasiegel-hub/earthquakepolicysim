"""
plot_sim_results.py
====================
Post-simulation plotting. THREE separate things live here -- use whichever
you need via the --mode flag:

  1. `runs`   -- per-run SA_* time series (SA_OUTCOME, SA_POP, SA_PRICE, ...),
                 a thin wrapper around abm_analysis.py's existing
                 load_runs/add_derived_variables/plot_all_timeseries. For
                 many-replicate ensembles named "{prefix} {run}.mat" in one
                 folder (the Ash22_png.ipynb / New_EQ_07sep.ipynb convention).

  1b. `compare` -- compare 2+ individually-named scenario .mat files
                 directly (e.g. the single-replicate outputs of
                 run_earthquake_setting.m) -- doesn't need the
                 directory+prefix+n_runs convention `runs` expects. Give it
                 one --scenario NAME PATH per scenario.

  2. `sweep`  -- plots run_sensitivity_sweep.m's output (sensitivity_sweep_
                 results.csv / _summary.csv): each metric vs the swept
                 parameter value (wservice / eld_movef / svc_filter), split
                 elderly vs non-elderly, mean +/- std across replicates.

  3. `eldmap` -- before/after choropleth of elderly household share by SA:
                 "before" = the synthetic population from the data-allocation
                 stage (HH_data in e.g. data_for_model_tmine.mat), "after" =
                 SA_Demographics from a completed nextchangesfortracker.m /
                 run_sweep_setting.m run (saved in that run's output .mat,
                 columns: [SA, n_elderly_hh, n_nonelderly_hh, n_total_hh,
                 pct_elderly, pct_nonelderly, service_ratio] per
                 nextchangesfortracker.m's SA_Demographics block).

NOTE: modes 1 and 2 need real simulation/sweep output to run against, which
doesn't exist yet as of writing this. Built against the documented column
layouts (CLAUDE.md, run_sensitivity_sweep.m's header comment,
abm_analysis.py's VARIABLE_TITLES) but UNTESTED -- check the first real
output carefully rather than trusting this blindly. Mode 3's "before" half
works today (it's the same data plot_allocation.py already validates); only
the "after" half needs real sim output.

Usage
-----
    python plot_sim_results.py runs --mat-dir D:\\MATLAB\\Ash\\rocketFinal --prefix "Ash22Q 0" --n-runs 30 --out plots_runs
    python plot_sim_results.py sweep --csv sensitivity_sweep_results_summary.csv --out plots_sweep
    python plot_sim_results.py eldmap --before data_allocation/data_for_model_tmine.mat --after baseline run1.mat --after behavioral run2.mat --out plots_eldmap
"""

from __future__ import annotations

import argparse
import os
import sys
import numpy as np
import pandas as pd
import scipy.io as sio
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data_allocation'))

HERE = os.path.dirname(os.path.abspath(__file__))
SHAPE_PATH = os.path.join(HERE, 'tveriashape', 'tveriastats.shp')


# ---------------------------------------------------------------------------
# mode 1: per-run SA_* time series, via abm_analysis.py
# ---------------------------------------------------------------------------

def mode_runs(args):
    import abm_analysis as aa

    cfg = aa.Config(
        mat_dir=args.mat_dir,
        scenarios={args.prefix: args.label},
        n_runs=args.n_runs,
        day_slice=slice(args.day_start, args.day_end),
    )
    data = aa.load_runs(cfg)
    data = aa.add_derived_variables(data, cfg)
    os.makedirs(args.out, exist_ok=True)
    aa.plot_all_timeseries(data, cfg, out_dir=args.out, relative=False)
    print(f'[done] per-run SA_* plots -> {os.path.abspath(args.out)}')


# ---------------------------------------------------------------------------
# mode 2: sweep results
# ---------------------------------------------------------------------------

# metric-family -> (avg_col_E, avg_col_NE, delta_col_E, delta_col_NE, y-label)
SWEEP_METRIC_FAMILIES = {
    'Population % change':      (None, None, 'PopPctChange_E', 'PopPctChange_NE', '% change'),
    'SA service ratio':         ('SAServiceAvg_E', 'SAServiceAvg_NE', 'SAServiceDelta_E', 'SAServiceDelta_NE', 'ratio'),
    'Building service ratio':   ('BldServiceAvg_E', 'BldServiceAvg_NE', 'BldServiceDelta_E', 'BldServiceDelta_NE', 'ratio'),
    'Norm. possible assets (SA)':   ('NormAssetsSA_Avg_E', 'NormAssetsSA_Avg_NE', 'NormAssetsSA_Delta_E', 'NormAssetsSA_Delta_NE', 'count/HH'),
    'Norm. possible assets (city)': ('NormAssetsCity_Avg_E', 'NormAssetsCity_Avg_NE', 'NormAssetsCity_Delta_E', 'NormAssetsCity_Delta_NE', 'count/HH'),
    'Attempt rate (SA)':        ('AttemptSA_Avg_E', 'AttemptSA_Avg_NE', 'AttemptSA_Delta_E', 'AttemptSA_Delta_NE', 'rate'),
    'Attempt rate (city)':      ('AttemptCity_Avg_E', 'AttemptCity_Avg_NE', 'AttemptCity_Delta_E', 'AttemptCity_Delta_NE', 'rate'),
    'Success rate (SA)':        ('SuccessSA_Avg_E', 'SuccessSA_Avg_NE', 'SuccessSA_Delta_E', 'SuccessSA_Delta_NE', 'rate'),
    'Success rate (city)':      ('SuccessCity_Avg_E', 'SuccessCity_Avg_NE', 'SuccessCity_Delta_E', 'SuccessCity_Delta_NE', 'rate'),
}

PARAM_AXES = ['wservice', 'eld_movef', 'svc_filter', 'wservice_old']


def _plot_one_sweep_metric(ax, df_summary, param, col_e, col_ne, ylabel, title):
    sub = df_summary[df_summary['ParamVaried'] == param].sort_values(param)
    x = sub[param]
    for col, label, color in [(col_e, 'Elderly', 'tab:red'), (col_ne, 'Non-elderly', 'tab:blue')]:
        if col is None:
            continue
        mean_col = f'mean_{col}'
        std_col = f'std_{col}'
        if mean_col not in sub.columns:
            continue
        y = sub[mean_col]
        ax.plot(x, y, marker='o', label=label, color=color)
        if std_col in sub.columns:
            ax.fill_between(x, y - sub[std_col], y + sub[std_col], alpha=0.15, color=color)
    ax.set_xlabel(param)
    ax.set_ylabel(ylabel)
    ax.set_title(title, fontsize=10)
    ax.legend(fontsize=8)


def mode_sweep(args):
    df = pd.read_csv(args.csv)
    # groupsummary() produces columns like 'mean_PopPctChange_E' already if
    # this is the _summary.csv; if it's results_long.csv instead, summarize
    # here so mean_/std_ columns exist either way.
    if not any(c.startswith('mean_') for c in df.columns):
        # group by every axis column actually present, not just the
        # original 3 -- otherwise a sweep over an axis like wservice_old
        # (with wservice/eld_movef/svc_filter held constant) collapses
        # every row into one group and the swept values are lost.
        axis_cols = [c for c in PARAM_AXES if c in df.columns]
        metric_cols = [c for c in df.columns if c not in (['ParamVaried', 'Replicate', 'GroupCount'] + axis_cols)]
        df = df.groupby(['ParamVaried'] + axis_cols)[metric_cols].agg(['mean', 'std'])
        df.columns = [f'{stat}_{col}' for col, stat in df.columns]
        df = df.reset_index()

    os.makedirs(args.out, exist_ok=True)
    pdf_path = os.path.join(args.out, 'sweep_plots.pdf')
    with PdfPages(pdf_path) as pdf:
        for param in PARAM_AXES:
            if param not in df['ParamVaried'].values:
                print(f'[skip] no rows for ParamVaried=={param}')
                continue
            fig, axes = plt.subplots(3, 3, figsize=(15, 12))
            axes = axes.flatten()
            for ax, (title, (avg_e, avg_ne, delta_e, delta_ne, ylabel)) in zip(axes, SWEEP_METRIC_FAMILIES.items()):
                if avg_e is not None:
                    _plot_one_sweep_metric(ax, df, param, avg_e, avg_ne, ylabel, f'{title} (whole-run avg)')
                else:
                    _plot_one_sweep_metric(ax, df, param, delta_e, delta_ne, ylabel, f'{title} (delta)')
            fig.suptitle(f'Sensitivity sweep: {param}', fontsize=13)
            plt.tight_layout()
            fig.savefig(os.path.join(args.out, f'sweep_{param}.png'), dpi=200)
            pdf.savefig(fig)
            plt.close(fig)

            # deltas as a second page per axis, for the families that also have one
            fig, axes = plt.subplots(3, 3, figsize=(15, 12))
            axes = axes.flatten()
            for ax, (title, (avg_e, avg_ne, delta_e, delta_ne, ylabel)) in zip(axes, SWEEP_METRIC_FAMILIES.items()):
                _plot_one_sweep_metric(ax, df, param, delta_e, delta_ne, ylabel, f'{title} (delta, final-initial)')
            fig.suptitle(f'Sensitivity sweep: {param} (deltas)', fontsize=13)
            plt.tight_layout()
            fig.savefig(os.path.join(args.out, f'sweep_{param}_deltas.png'), dpi=200)
            pdf.savefig(fig)
            plt.close(fig)

    print(f'[done] sweep plots -> {os.path.abspath(args.out)}; combined PDF -> {pdf_path}')


# ---------------------------------------------------------------------------
# mode 1b: direct scenario-file comparison (2+ named .mat files)
# ---------------------------------------------------------------------------
# Built for single-replicate testing runs (e.g. run_earthquake_setting.m),
# where each scenario is exactly one .mat file with a name you choose --
# not the directory+prefix+n_runs convention abm_analysis.py's load_runs
# expects (that one's for many-replicate ensembles named "{prefix} {run}.mat").
# Reuses abm_analysis.py's VARIABLE_TITLES/is_mean_variable/plot_timeseries
# for consistent aggregation and styling.

def mode_compare(args):
    import abm_analysis as aa

    cfg = aa.Config(mat_dir='', scenarios={s[0]: s[0] for s in args.scenario}, colors=dict(args.color))
    runs_by_var = {v: {} for v in cfg.variables}

    for label, path in args.scenario:
        m = sio.loadmat(path, variable_names=cfg.variables, simplify_cells=True)
        for v in cfg.variables:
            if v not in m:
                continue
            df = pd.DataFrame(m[v])
            if args.day_end is not None:
                df = df.iloc[:, args.day_start:args.day_end]
            else:
                df = df.iloc[:, args.day_start:]
            # SA_* columns are only populated every sa_update_every days --
            # unpopulated day-columns are literally zero-filled, not NaN.
            # Same heuristic plot_baseline_macro_all.py uses. Without this,
            # sa_update_every>1 runs (e.g. the model's monthly default of
            # 30) plot a sawtooth crashing to 0 between each real update
            # instead of a smooth line through only the populated days.
            populated = (df != 0).any(axis=0)
            if populated.any():
                df = df.loc[:, populated]
            series = df.mean(axis=0) if aa.is_mean_variable(v, cfg.variable_titles) else df.sum(axis=0)
            runs_by_var[v].setdefault(label, []).append(series)

    data = aa.add_derived_variables(runs_by_var, cfg)

    missing = [v for v in cfg.variables if not any(data.get(v, {}).values())]
    if missing:
        print(f'[note] not found in any scenario file, skipped: {missing}')

    os.makedirs(args.out, exist_ok=True)
    aa.plot_all_timeseries(data, cfg, out_dir=args.out, relative=False, pdf_name='comparison_plots.pdf')
    print(f'[done] scenario comparison plots (SA_* variables) -> {os.path.abspath(args.out)}')

    _plot_metric_track_comparison(args.scenario, args.out)


# Metric_Track column layout (0-indexed), 3-way non-elderly/young-old/
# old-old for every family (added this session -- HH_data col5 encodes
# 0=non-elderly, 3=young-old/65-69, 6=old-old/70+). Tuple = (non_elderly,
# young_old, old_old, ylabel). Requires Metric_Track to have the extended
# columns (41 total) added this session -- see _plot_metric_track_comparison's
# fallback for older files that don't.
METRIC_TRACK_FAMILIES = {
    'Population': (6, 23, 24, 'count'),
    'SA service ratio': (2, 25, 26, 'ratio'),
    'Building service ratio': (4, 27, 28, 'ratio'),
    'Norm. possible assets (SA)': (10, 29, 30, 'count/HH'),
    'Norm. possible assets (city)': (14, 31, 32, 'count/HH'),
    'Attempt rate (SA)': (16, 33, 34, 'rate'),
    'Attempt rate (city)': (18, 35, 36, 'rate'),
    'Success rate (SA)': (20, 37, 38, 'rate'),
    'Success rate (city)': (22, 39, 40, 'rate'),
}

# Fixed color per age group (consistent across every panel and scenario);
# linestyle distinguishes scenarios instead, cycling if there are more
# than 4. This reads more clearly than the old scheme (color=scenario,
# linestyle=elderly/non-elderly), especially now that there are 3 groups.
GROUP_COLORS = {'non-elderly': 'tab:blue', 'young-old': 'tab:orange', 'old-old': 'tab:red'}
SCENARIO_DASHES = ['-', '--', ':', '-.']

# These families are ratios/normalized counts computed from whichever
# households actually attempted a move THAT DAY -- often just 1-3
# households, especially for the smaller elderly subgroups (confirmed by
# inspection: e.g. success rate only takes values like {0, 0.5, 0.67, 0.8,
# 1.0} on many days -- literally small-integer ratios). The daily series
# is real and correctly computed, but it's dominated by which specific
# household/SA happened to attempt that day rather than any underlying
# trend, so it's plotted as a light raw scatter UNDER a rolling-mean line
# that reveals the trend. SA/building service ratio and population are
# smooth continuous quantities and don't need this.
SMOOTH_FAMILIES = {
    'Norm. possible assets (SA)', 'Norm. possible assets (city)',
    'Attempt rate (SA)', 'Attempt rate (city)',
    'Success rate (SA)', 'Success rate (city)',
}
SMOOTH_WINDOW = 30  # days; matches the model's own VISITS/MVB30 smoothing window


def _plot_metric_track_comparison(scenarios, out_dir):
    """Metric_Track is the fully-populated (real per-step) 3-way
    non-elderly/young-old/old-old tracking system -- unlike the SA_*
    variables above, which in run_model_earthquake.m as of this writing
    only record step 1 and the final step (confirmed by inspecting
    SA_POP/SA_SERVICE directly: every intermediate day is a hard zero).
    This gives a genuine day-by-day baseline-vs-scenario comparison using
    the data that's actually reliable."""
    tracks = {}
    for label, path in scenarios:
        m = sio.loadmat(path, variable_names=['Metric_Track'], simplify_cells=True)
        if 'Metric_Track' not in m:
            print(f'[skip] Metric_Track not found in {path}')
            continue
        tracks[label] = m['Metric_Track']

    if not tracks:
        return

    scenario_dash = {label: SCENARIO_DASHES[i % len(SCENARIO_DASHES)]
                      for i, label in enumerate(tracks)}

    fig, axes = plt.subplots(3, 3, figsize=(15, 12))
    axes = axes.flatten()
    for ax, (title, (ne_col, yo_col, oo_col, ylabel)) in zip(axes, METRIC_TRACK_FAMILIES.items()):
        smooth = title in SMOOTH_FAMILIES
        for label, mt in tracks.items():
            day = mt[:, 0]
            dash = scenario_dash[label]
            if mt.shape[1] <= max(ne_col, yo_col, oo_col):
                # older file, predates this session's extended columns --
                # skip this scenario for this family rather than erroring
                print(f'[note] {label}: missing extended Metric_Track columns for "{title}" (older run)')
                continue
            for group, col in [('non-elderly', ne_col), ('young-old', yo_col), ('old-old', oo_col)]:
                color = GROUP_COLORS[group]
                series = pd.Series(mt[:, col], index=day)
                if smooth:
                    ax.plot(day, series.values, color=color, linestyle=dash,
                            alpha=0.15, linewidth=0.8)
                    smoothed = series.rolling(SMOOTH_WINDOW, min_periods=1).mean()
                    ax.plot(day, smoothed.values, color=color, linestyle=dash,
                            linewidth=2.0, label=f'{label} ({group}, {SMOOTH_WINDOW}d avg)')
                else:
                    ax.plot(day, series.values, color=color, linestyle=dash,
                            linewidth=1.6, label=f'{label} ({group})')
        ax.set_xlabel('step')
        ax.set_ylabel(ylabel)
        ax.set_title(title + (' [30d smoothed]' if smooth else ''), fontsize=10)
        ax.legend(fontsize=6)
    fig.suptitle('Metric_Track comparison -- color=age group (blue=non-elderly, orange=young-old, red=old-old), '
                 'linestyle=scenario', fontsize=12)
    plt.tight_layout()
    out_path = os.path.join(out_dir, 'metric_track_comparison.png')
    fig.savefig(out_path, dpi=200)
    plt.close(fig)
    print(f'[done] Metric_Track comparison -> {out_path}')


# ---------------------------------------------------------------------------
# mode 3: before/after elderly household map
# ---------------------------------------------------------------------------

def _before_per_sa(mat_path):
    from validate_allocation import load_mat
    d = load_mat(mat_path)
    HH = d['HH']
    is_elderly_hh = HH['n_old'] >= 2
    per_sa = HH.groupby('stat').size().rename('n_hh').to_frame()
    per_sa['n_elderly_hh'] = HH[is_elderly_hh].groupby('stat').size()
    per_sa['n_elderly_hh'] = per_sa['n_elderly_hh'].fillna(0)
    per_sa['pct_elderly_hh'] = 100 * per_sa['n_elderly_hh'] / per_sa['n_hh']
    return per_sa[['pct_elderly_hh']].rename(columns={'pct_elderly_hh': 'before_pct_elderly'})


def _after_per_sa(mat_path):
    m = sio.loadmat(mat_path, simplify_cells=True)
    if 'SA_Demographics' not in m:
        raise KeyError(f"'SA_Demographics' not found in {mat_path} -- is this a completed "
                        "nextchangesfortracker.m / run_sweep_setting.m output?")
    sd = m['SA_Demographics']
    # columns per nextchangesfortracker.m: SA, n_elderly_hh, n_nonelderly_hh,
    # n_total_hh, pct_elderly, pct_nonelderly, service_ratio
    df = pd.DataFrame(sd, columns=['stat', 'n_elderly_hh', 'n_nonelderly_hh',
                                    'n_total_hh', 'pct_elderly', 'pct_nonelderly', 'service_ratio'])
    return df.set_index('stat')[['pct_elderly']].rename(columns={'pct_elderly': 'after_pct_elderly'})


def mode_eldmap(args):
    import geopandas as gpd

    shp = gpd.read_file(SHAPE_PATH)
    before = _before_per_sa(args.before)

    # one "after" column per scenario, all joined onto the same shapefile so
    # they can share one color scale and one image
    per_sa = before.copy()
    scenario_cols = []
    for label, path in args.after:
        after = _after_per_sa(path).rename(columns={'after_pct_elderly': f'after__{label}'})
        per_sa = per_sa.join(after, how='outer')
        scenario_cols.append(f'after__{label}')

    merged = shp.merge(per_sa, left_on='YISHUV_STA', right_index=True, how='left')

    all_cols = ['before_pct_elderly'] + scenario_cols
    vmin = merged[all_cols].min().min()
    vmax = merged[all_cols].max().max()

    os.makedirs(args.out, exist_ok=True)
    panels = [('before_pct_elderly', 'Elderly HH share -- beginning')] + \
             [(col, f'Elderly HH share -- end of run ({label})') for col, (label, _) in zip(scenario_cols, args.after)]

    fig, axes = plt.subplots(1, len(panels), figsize=(7 * len(panels), 6))
    if len(panels) == 1:
        axes = [axes]
    im = None
    for ax, (col, title) in zip(axes, panels):
        plot = merged.plot(column=col, ax=ax, cmap='Purples', legend=False, vmin=vmin, vmax=vmax,
                            edgecolor='black', linewidth=0.5, missing_kwds={'color': 'lightgrey'})
        ax.set_title(title, fontsize=11)
        ax.set_axis_off()
        im = plot.collections[-1] if plot.collections else im

    # one shared colorbar for every panel, instead of one per panel
    sm = plt.cm.ScalarMappable(cmap='Purples', norm=plt.Normalize(vmin=vmin, vmax=vmax))
    sm.set_array([])
    fig.colorbar(sm, ax=axes, fraction=0.03, pad=0.02, label='% elderly households')

    out_png = os.path.join(args.out, 'elderly_before_after.png')
    fig.savefig(out_png, dpi=200, bbox_inches='tight')
    plt.close(fig)
    print(f'[done] before/after elderly map (shared scale) -> {out_png}')


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='mode', required=True)

    p1 = sub.add_parser('runs', help='per-run SA_* time series via abm_analysis.py')
    p1.add_argument('--mat-dir', required=True)
    p1.add_argument('--prefix', required=True, help='file prefix, e.g. "Ash22Q 0" for "Ash22Q 0 1.mat"')
    p1.add_argument('--label', default='run')
    p1.add_argument('--n-runs', type=int, default=1)
    p1.add_argument('--day-start', type=int, default=0)
    p1.add_argument('--day-end', type=int, default=None)
    p1.add_argument('--out', default='plots_runs')

    p1b = sub.add_parser('compare', help='compare 2+ named scenario .mat files directly (single-replicate runs)')
    p1b.add_argument('--scenario', nargs=2, action='append', required=True, metavar=('NAME', 'PATH'),
                      help='repeatable, e.g. --scenario baseline earthquakeF/"agesplit70 EQ 1 baseline.mat" '
                           '--scenario behavioral earthquakeF/"agesplit70 EQ 1 wservice025_svcfilter1.mat"')
    p1b.add_argument('--day-start', type=int, default=0)
    p1b.add_argument('--day-end', type=int, default=None)
    p1b.add_argument('--out', default='plots_compare')
    p1b.add_argument('--color', nargs=2, action='append', default=[], metavar=('NAME', 'COLOR'),
                      help='repeatable, e.g. --color a5 tab:blue --color a15 tab:green --color a30 tab:red. '
                           'Without this, scenario_style() colors anything with "base" in its name tab:blue '
                           'and everything else tab:green -- indistinguishable once you have 3+ non-baseline '
                           'scenarios in one plot.')

    p2 = sub.add_parser('sweep', help='sensitivity sweep plots')
    p2.add_argument('--csv', default='sensitivity_sweep_results_summary.csv')
    p2.add_argument('--out', default='plots_sweep')

    p3 = sub.add_parser('eldmap', help='before/after elderly household map, one shared color scale, 2+ scenarios in one image')
    p3.add_argument('--before', default=os.path.join(HERE, 'data_allocation', 'data_for_model_tmine.mat'))
    p3.add_argument('--after', nargs=2, action='append', required=True, metavar=('NAME', 'PATH'),
                     help='repeatable, e.g. --after baseline earthquakeF/"agesplit70 EQ S 1 baseline.mat" '
                          '--after behavioral earthquakeF/"agesplit70 EQ S 1 behavioral.mat"')
    p3.add_argument('--out', default='plots_eldmap')

    args = ap.parse_args()
    if args.mode == 'runs':
        mode_runs(args)
    elif args.mode == 'compare':
        mode_compare(args)
    elif args.mode == 'sweep':
        mode_sweep(args)
    elif args.mode == 'eldmap':
        mode_eldmap(args)


if __name__ == '__main__':
    main()
