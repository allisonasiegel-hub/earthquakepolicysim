"""
standard_report.py
===================
ONE-COMMAND standard output for any tested elderly_search_mode config, for
Allison's Tiberias ABM thesis project (housing/labor/land-use ABM, elderly
housing-search modes 0-6, see CLAUDE.md in the repo root for full context).

Produces THREE things for a given config, run against `baseline` as the
reference:
  1. A results table: SA service level, building service level, SA-level
     success rate, city-level success rate, normalized possible assets
     (SA level), normalized possible assets (city level) -- average +/-
     std across replicates, for each population group (non-senior,
     young-senior [65-69], old-senior [70+]). Values are the FULL 760-day
     per-replicate average. An asterisk marks a group as significantly
     different (Welch's two-sample t-test, p<0.05) from the non-senior
     row WITHIN THAT SAME config -- i.e. does this config show seniors
     differing from non-seniors, not "does this config differ from
     another config".
  2. Metric_Track trend plots: the same 6 metrics above, plotted over all
     760 days, one line per population group (color) with a shaded
     +/-1 std band across replicates. A 30-day rolling average is
     overlaid (raw daily values are noisy at small per-SA sample sizes).
  3. Macro-economic (SA_*) trend plots: EVERY SA_* variable saved by the
     model (24 total -- population, wage, job occupancy, asset/house/
     commercial prices, residential/commercial/workplace counts, local-
     work/working/idle ratios, wage bill, commercial floor area, and all
     10 income-decile household counts), aggregated across all SAs each
     day (sum for counts, mean for ratios/prices -- see MACRO_VARS below
     for which), mean +/-1 std band across replicates.

DESIGNED TO BE CALLABLE FROM A FRESH CHAT SESSION WITH ZERO PRIOR CONTEXT.
Everything needed to understand and run this is in this docstring and the
CONFIGS dict below -- no other file or conversation history required.

USAGE (run from the modelthesis/ directory; or pass --root to point
elsewhere):
    python analysis_scripts/standard_report.py mode2
    python analysis_scripts/standard_report.py mode6
    python analysis_scripts/standard_report.py mode2 mode3 mode5
    python analysis_scripts/standard_report.py mode2 --baseline baseline

Known config names (edit CONFIGS below to add a new one -- just needs a
name and the glob pattern its .mat files share in earthquakeF/):
    baseline, mode1, mode2, mode3, mode4, mode5, mode6

Output goes to analysis_scripts/reports/<config>/:
    table.md                  -- the results table, markdown
    metric_track_trends.png   -- plot 2 above
    macro_trends.png          -- plot 3 above, overview grid (all 24 at a glance)
    macro_trends.pdf          -- plot 3 above, one full-size page per variable
                                  (same per-variable-page pattern as
                                  abm_analysis.py's plot_all_timeseries)
    macro_pngs/<VAR>.png      -- each of the 24 variables as its own PNG too
The table is also printed to the console.

Metric_Track column layout (0-indexed, from run_model_earthquake.m's
Metric_Track_P label list -- see that file if this ever needs updating):
  2/25/26  = SA service ratio            non-elderly/young-old/old-old
  4/27/28  = Building service ratio      non-elderly/young-old/old-old
  10/29/30 = Norm. possible assets, SA   non-elderly/young-old/old-old
  14/31/32 = Norm. possible assets, city non-elderly/young-old/old-old
  20/37/38 = Success rate, SA level      non-elderly/young-old/old-old
  22/39/40 = Success rate, city level    non-elderly/young-old/old-old
"""

from __future__ import annotations

import argparse
import glob
import os

import numpy as np
import pandas as pd
import scipy.io as sio
from scipy import stats
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

HERE = os.path.dirname(os.path.abspath(__file__))

# config name -> glob pattern (matched against earthquakeF/agesplit70 EQ S 1 <pattern>*.mat)
CONFIGS = {
    'baseline': 'baseline_full3way',
    'mode1': '760day_mode1',
    'mode2': '760day_mode2',
    'mode3': '760day_mode3',
    'mode4': '760day_mode4',
    'mode5': '760day_mode5',
    'mode6': '760day_mode6',
    'radius600': 'radius400_600_svcf1_full760',
    'radius700': 'radius250_700_svcf1_full760',
    'radius350': 'radius200_350_svcf1_full760',
    'radius300': 'radius300_400_svcf1',
    'radius500': 'radius250_500_svcf1',
    'radius400control': 'radius250_400_svcf1',
}

# metric label -> (Metric_Track col: non-elderly, young-old, old-old)
METRICS = [
    ('SA service level',       2, 25, 26),
    ('Building service level', 4, 27, 28),
    ('SA success rate',        20, 37, 38),
    ('City success rate',      22, 39, 40),
    ('Norm. assets SA',        10, 29, 30),
    ('Norm. assets city',      14, 31, 32),
]

GROUP_COLORS = {'non-senior': 'tab:blue', 'young-senior': 'tab:orange', 'old-senior': 'tab:red'}
SMOOTH_WINDOW = 30

# var -> (label, aggregation across SAs). Aggregation matches how each
# variable is actually computed per-SA in run_model_earthquake.m: ratios
# (occupancy/local-work/idle rates, mean prices/wages) are averaged across
# SAs; raw counts (population, building/workplace counts, income-decile
# household counts, wage bill, commercial floor area) are summed
# city-wide. See run_model_earthquake.m's SA_*(:, i+1) = ... assignments
# (search for accsum/accmean/accnanmean) if this ever needs re-deriving.
MACRO_VARS = [
    ('SA_POP', 'Population (occupied assets)', 'sum'),
    ('SA_WAGE', 'Average individual wage', 'mean'),
    ('SA_JOBS', 'Job occupancy rate', 'mean'),
    ('SA_PRICE', 'Average asset price', 'mean'),
    ('SA_SERVICE', 'Commercial building count', 'sum'),
    ('SA_HOUSE', 'Residential asset price', 'mean'),
    ('SA_COMERCIAL', 'Commercial asset price', 'mean'),
    ('SA_RESIDENT', 'Residential building count', 'sum'),
    ('SA_WP', 'Workplace count', 'sum'),
    ('SA_LOCAL', 'Local-work ratio', 'mean'),
    ('SA_WORKING', 'Working ratio (employed/jobs)', 'mean'),
    ('SA_IDLE', 'Idle ratio (unemployed/labor force)', 'mean'),
    ('SA_OUTCOME', 'Total wage bill (occupied workplaces)', 'sum'),
    ('SA_AREA', 'Total commercial building area', 'sum'),
    ('SA_FIRST', 'Income decile 1 household count', 'sum'),
    ('SA_SECOND', 'Income decile 2 household count', 'sum'),
    ('SA_THIRD', 'Income decile 3 household count', 'sum'),
    ('SA_FOURTH', 'Income decile 4 household count', 'sum'),
    ('SA_FIFTH', 'Income decile 5 household count', 'sum'),
    ('SA_SIXTH', 'Income decile 6 household count', 'sum'),
    ('SA_SEVENTH', 'Income decile 7 household count', 'sum'),
    ('SA_EIGHTH', 'Income decile 8 household count', 'sum'),
    ('SA_NINTH', 'Income decile 9 household count', 'sum'),
    ('SA_TENTH', 'Income decile 10 household count', 'sum'),
]


def find_files(root, pattern):
    return sorted(glob.glob(os.path.join(root, 'earthquakeF', f'agesplit70 EQ S 1 {pattern}*.mat')))


def load_metric_tracks(files):
    tracks = []
    for f in files:
        m = sio.loadmat(f, variable_names=['Metric_Track'], simplify_cells=True)
        mt = np.asarray(m['Metric_Track'])
        mt = mt[~np.all(np.isnan(mt), axis=1)]
        tracks.append(mt)
    return tracks


def load_macro(files):
    """Returns dict var -> (n_replicates, n_days) array of the daily aggregate."""
    out = {v: [] for v, _, _ in MACRO_VARS}
    for f in files:
        m = sio.loadmat(f, variable_names=[v for v, _, _ in MACRO_VARS], simplify_cells=True)
        for v, _, agg in MACRO_VARS:
            arr = np.asarray(m[v])  # (n_SA, n_days)
            daily = arr.sum(axis=0) if agg == 'sum' else np.nanmean(arr, axis=0)
            out[v].append(daily)
    # pad/truncate to common length
    for v in out:
        lens = [len(x) for x in out[v]]
        n = min(lens) if lens else 0
        out[v] = np.array([x[:n] for x in out[v]])
    return out


def per_rep_avg(tracks, col):
    return np.array([np.nanmean(mt[:, col]) for mt in tracks])


def build_table(tracks, config_name):
    rows = []
    for mname, c_ne, c_yo, c_oo in METRICS:
        ne = per_rep_avg(tracks, c_ne)
        yo = per_rep_avg(tracks, c_yo)
        oo = per_rep_avg(tracks, c_oo)
        _, p_yo = stats.ttest_ind(yo, ne, equal_var=False)
        _, p_oo = stats.ttest_ind(oo, ne, equal_var=False)
        rows.append({
            'metric': mname,
            'ne_mean': np.mean(ne), 'ne_std': np.std(ne, ddof=1) if len(ne) > 1 else np.nan,
            'yo_mean': np.mean(yo), 'yo_std': np.std(yo, ddof=1) if len(yo) > 1 else np.nan, 'yo_p': p_yo,
            'oo_mean': np.mean(oo), 'oo_std': np.std(oo, ddof=1) if len(oo) > 1 else np.nan, 'oo_p': p_oo,
        })
    return rows


def render_table_md(rows, config_name, n):
    lines = [f'## {config_name} (n={n} replicates, full 760-day average)', '']
    lines.append('| Metric | Non-senior (avg±std) | Young-senior (avg±std) | Old-senior (avg±std) |')
    lines.append('|---|---|---|---|')
    for r in rows:
        yo_star = '*' if r['yo_p'] < 0.05 else ''
        oo_star = '*' if r['oo_p'] < 0.05 else ''
        lines.append(
            f"| {r['metric']} | {r['ne_mean']:.4f} ± {r['ne_std']:.4f} "
            f"| {r['yo_mean']:.4f} ± {r['yo_std']:.4f}{yo_star} "
            f"| {r['oo_mean']:.4f} ± {r['oo_std']:.4f}{oo_star} |"
        )
    lines.append('')
    lines.append('\\* p < 0.05 (Welch\'s two-sample t-test, senior group vs. non-senior, within this config)')
    return '\n'.join(lines)


def smooth(v, window=SMOOTH_WINDOW):
    s = pd.Series(v)
    return s.rolling(window, min_periods=1, center=True).mean().values


def plot_metric_track_trends(tracks, config_name, out_path):
    fig, axes = plt.subplots(3, 2, figsize=(14, 15))
    for ax, (mname, c_ne, c_yo, c_oo) in zip(axes.flat, METRICS):
        for label, col in [('non-senior', c_ne), ('young-senior', c_yo), ('old-senior', c_oo)]:
            series = np.array([mt[:, col] for mt in tracks])  # (n_reps, n_days)
            n_days = series.shape[1]
            days = np.arange(n_days)
            mean_raw = np.nanmean(series, axis=0)
            std_raw = np.nanstd(series, axis=0)
            mean_s = smooth(mean_raw)
            color = GROUP_COLORS[label]
            ax.plot(days, mean_s, color=color, label=label, linewidth=1.8)
            ax.fill_between(days, smooth(mean_raw - std_raw), smooth(mean_raw + std_raw), color=color, alpha=0.15)
        ax.set_title(mname, fontsize=12)
        ax.set_xlabel('day')
        ax.legend(fontsize=8)
    fig.suptitle(f'{config_name} -- Metric_Track trends (mean ±1 std across {len(tracks)} replicates, 30-day smoothed)', fontsize=14)
    plt.tight_layout(rect=[0, 0, 1, 0.97])
    plt.savefig(out_path, dpi=140)
    plt.close(fig)


def plot_macro_trends(macro, config_name, out_path):
    """Overview grid PNG -- all 24 variables at a glance, small panels."""
    n_vars = len(MACRO_VARS)
    ncols = 4
    nrows = -(-n_vars // ncols)  # ceil
    fig, axes = plt.subplots(nrows, ncols, figsize=(5 * ncols, 3.6 * nrows))
    n_reps = 0
    for ax, (v, label, agg) in zip(axes.flat, MACRO_VARS):
        series = macro[v]
        if series.size == 0:
            ax.axis('off')
            continue
        n_reps = series.shape[0]
        days = np.arange(series.shape[1])
        mean_raw = np.nanmean(series, axis=0)
        std_raw = np.nanstd(series, axis=0)
        ax.plot(days, smooth(mean_raw), color='tab:green', linewidth=1.6)
        ax.fill_between(days, smooth(mean_raw - std_raw), smooth(mean_raw + std_raw), color='tab:green', alpha=0.15)
        ax.set_title(f'{label}\n({v}, {agg} across SAs)', fontsize=9.5)
        ax.set_xlabel('day', fontsize=8)
        ax.tick_params(labelsize=8)
    for ax in axes.flat[n_vars:]:
        ax.axis('off')
    fig.suptitle(f'{config_name} -- macro-economic (SA_*) trends, all variables (mean ±1 std across {n_reps} replicates, 30-day smoothed)', fontsize=14)
    plt.tight_layout(rect=[0, 0, 1, 0.97])
    plt.savefig(out_path, dpi=130)
    plt.close(fig)


def plot_macro_trends_pdf(macro, config_name, pdf_path, png_dir):
    """One full-size page per SA_* variable, all combined into one PDF --
    same pattern as abm_analysis.py's plot_all_timeseries (individual PNG
    per variable + one combined multi-page PDF)."""
    os.makedirs(png_dir, exist_ok=True)
    with PdfPages(pdf_path) as pdf:
        for v, label, agg in MACRO_VARS:
            series = macro[v]
            if series.size == 0:
                continue
            days = np.arange(series.shape[1])
            mean_raw = np.nanmean(series, axis=0)
            std_raw = np.nanstd(series, axis=0)
            fig, ax = plt.subplots(figsize=(9, 5.5))
            ax.plot(days, smooth(mean_raw), color='tab:green', linewidth=2)
            ax.fill_between(days, smooth(mean_raw - std_raw), smooth(mean_raw + std_raw), color='tab:green', alpha=0.15)
            ax.set_title(f'{config_name} -- {label} ({v}, {agg} across SAs, mean ±1 std across {series.shape[0]} replicates)', fontsize=12)
            ax.set_xlabel('day')
            ax.set_ylabel(label)
            plt.tight_layout()
            fig.savefig(os.path.join(png_dir, f'{v}.png'), dpi=200)
            pdf.savefig(fig, bbox_inches='tight')
            plt.close(fig)


def run_one(root, config_name, out_root):
    if config_name not in CONFIGS:
        raise SystemExit(f'Unknown config "{config_name}". Known: {list(CONFIGS)}. Edit CONFIGS in this file to add one.')
    files = find_files(root, CONFIGS[config_name])
    if not files:
        raise SystemExit(f'No files found for config "{config_name}" (pattern "{CONFIGS[config_name]}*") under {root}/earthquakeF/')
    tracks = load_metric_tracks(files)
    macro = load_macro(files)

    out_dir = os.path.join(out_root, config_name)
    os.makedirs(out_dir, exist_ok=True)

    rows = build_table(tracks, config_name)
    table_md = render_table_md(rows, config_name, len(files))
    with open(os.path.join(out_dir, 'table.md'), 'w') as f:
        f.write(table_md + '\n')
    print(table_md)
    print()

    plot_metric_track_trends(tracks, config_name, os.path.join(out_dir, 'metric_track_trends.png'))
    plot_macro_trends(macro, config_name, os.path.join(out_dir, 'macro_trends.png'))
    plot_macro_trends_pdf(macro, config_name, os.path.join(out_dir, 'macro_trends.pdf'), os.path.join(out_dir, 'macro_pngs'))
    print(f'[done] {config_name}: {len(files)} replicates -> {os.path.abspath(out_dir)}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('configs', nargs='+', help='config name(s), e.g. mode2 mode6 (see CONFIGS in this file)')
    ap.add_argument('--root', default=os.path.dirname(HERE), help='project root containing earthquakeF/ (default: parent of this script\'s dir)')
    ap.add_argument('--out', default=os.path.join(HERE, 'reports'), help='output directory (default: analysis_scripts/reports)')
    args = ap.parse_args()

    for cfg in args.configs:
        run_one(args.root, cfg, args.out)


if __name__ == '__main__':
    main()
