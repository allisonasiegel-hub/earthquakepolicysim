"""
plot_macro_comparison.py
=========================
Full macro-economic (SA_*) comparison report for a modellab city run,
adapted from modelthesis/analysis_scripts/standard_report.py's macro-plot
logic for run_model_earthquake_shelteroverflow.m's output (which saves the
24 SA_* variables directly, with no Metric_Track/age-split table -- that
part of standard_report.py doesn't apply here).

Produces, for one or more scenario labels (each a glob pattern matched
against modellab/earthquakeF/*.mat):
  - macro_trends.png : overview grid, all 30 SA_* variables at a glance
    (24 raw + 6 derived, mirrored from modelthesis/analysis_scripts/
    abm_analysis.py -- see DERIVED_VARS below), mean +/-1 std band across
    replicates, 7-step rolling smoothed (smoothing window is in STEPS,
    which are WEEKS in this pipeline -- see
    day_to_week_step_rescaling_audit.md; standard_report.py's 30-day
    window doesn't apply, so this defaults to a shorter window)
  - macro_trends.pdf : same 30 variables, one full-size page each
  - macro_pngs/<VAR>.png : each variable as its own PNG
  - If more than one scenario label is given, all are overlaid on the same
    axes per variable for direct comparison instead of one plot per label.

USAGE (run from modellab/):
    python plot_macro_comparison.py --city Jerusalem
    python plot_macro_comparison.py --city Jerusalem --label "JER EQ S 20260901*"
    python plot_macro_comparison.py --city Jerusalem --city Tiberias   (side-by-side comparison)

--city accepts a friendly name (Jerusalem/Tiberias/Ashkelon) mapped to its
known earthquakeF/ filename prefix below, or pass --pattern directly for
anything else (e.g. a specific run_uid or timestamp to isolate one run).
"""

from __future__ import annotations

import argparse
import glob
import os

import numpy as np
import scipy.io as sio
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

HERE = os.path.dirname(os.path.abspath(__file__))

# friendly city name -> earthquakeF/ filename prefix (see out_file_name
# construction in run_model_earthquake_shelteroverflow.m: data2{end}, i.e.
# the last '_'-separated token of the `data` variable in the city
# configuration block)
CITY_PREFIX = {
    'Ashkelon': 'Ash2',
    'Tiberias': 'hotels',   # data_for_model_TVR_hotels -> data2{end}='hotels'
    'Jerusalem': 'JER',
    'Arad': 'Arad',
}

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

DECILE_VARS = [v for v, _, _ in MACRO_VARS if v.startswith('SA_') and v not in (
    'SA_POP', 'SA_WAGE', 'SA_JOBS', 'SA_PRICE', 'SA_SERVICE', 'SA_HOUSE', 'SA_COMERCIAL',
    'SA_RESIDENT', 'SA_WP', 'SA_LOCAL', 'SA_WORKING', 'SA_IDLE', 'SA_OUTCOME', 'SA_AREA',
)]

# Mirrors modelthesis/analysis_scripts/abm_analysis.py's 6 derived variables
# (see that file's add_derived_variables() docstring for its own
# definitions) and, in turn, modelthesis/analysis_scripts/
# standard_report.py's DERIVED_VARS (this list and its methodology are kept
# in sync with that one by hand -- see its comment for the full writeup).
# NOT added: SA_COMMUTE -- also in abm_analysis.py's VARIABLE_TITLES, but
# neither this model (run_model_earthquake_shelteroverflow.m) nor
# modelthesis's actually saves an SA_COMMUTE variable, so there's no data
# behind that label anywhere.
#
# Computed here as CITY-TOTAL ratios (e.g. citywide total jobs / citywide
# total floorspace, one division per surviving step on the already-SA-
# aggregated MACRO_VARS series above) -- a standard, directly-interpretable
# citywide number. This is NOT the same computation abm_analysis.py itself
# uses: abm_analysis.py computes each ratio PER SA PER DAY first (NaN on
# 0/0), and only afterward reduces the resulting per-SA ratio array to one
# city-wide line by SUMMING across SAs (like any other MACRO_VARS entry --
# none of these 6 titles start with "Mean", so its own is_mean_variable()
# check picks 'sum' for all of them). That sums 18 independently-computed
# per-SA ratios together, a different and less standard quantity than a
# true citywide ratio. Documented here, not implemented, in case the exact
# abm_analysis.py-matching version is wanted later:
#   SA_JPM2[SA,day]        = SA_WP[SA,day] / SA_AREA[SA,day]        -- per SA
#   SA_JPP[SA,day]         = SA_WP[SA,day] / SA_POP[SA,day]         -- per SA
#   SA_TOTAL_HH[SA,day]    = sum of the 10 decile counts, per SA
#   SA_JPTOTAL[SA,day]     = SA_WP[SA,day] / SA_TOTAL_HH[SA,day]    -- per SA
#   SA_WAGE_TOT[SA,day]    = SA_WAGE[SA,day] * SA_TOTAL_HH[SA,day]  -- per SA
#   SA_WAGE_HPRICE[SA,day] = SA_WAGE[SA,day] / SA_HOUSE[SA,day]     -- per SA
#   -- then each of the above summed across SAs for the city-wide line.
DERIVED_VARS = [
    ('SA_JPM2', 'Jobs per m2', 'SA_WP / SA_AREA, city-total ratio'),
    ('SA_JPP', 'Jobs per Occupied Asset', 'SA_WP / SA_POP, city-total ratio'),
    ('SA_TOTAL_HH', 'Total Households', 'sum of the 10 income-decile city totals'),
    ('SA_JPTOTAL', 'Jobs per Total Households', 'SA_WP / SA_TOTAL_HH, city-total ratio'),
    ('SA_WAGE_TOT', 'Total Wage Income', 'SA_WAGE(mean) * SA_TOTAL_HH, city-total product'),
    ('SA_WAGE_HPRICE', 'Wage-to-House Price Ratio', 'SA_WAGE / SA_HOUSE, city-total ratio'),
]

# Combined iteration order used by every plotting function below: the 24
# raw MACRO_VARS (each carrying its SA-aggregation method) followed by the
# 6 DERIVED_VARS (each carrying its formula instead). `derived` flag picks
# which label-suffix phrasing full_label() uses.
ALL_VARS = [(v, label, agg, False) for v, label, agg in MACRO_VARS] + \
           [(v, label, formula, True) for v, label, formula in DERIVED_VARS]


def full_label(v, label, detail, derived):
    """'Population (occupied assets) (SA_POP, sum across SAs)' for a raw
    MACRO_VARS entry; 'Jobs per m2 (SA_JPM2, SA_WP / SA_AREA, city-total
    ratio)' for a DERIVED_VARS entry (whose `detail` is already fully
    descriptive, so it's used as-is rather than getting an 'across SAs'
    suffix appended)."""
    suffix = detail if derived else f'{detail} across SAs'
    return f'{label} ({v}, {suffix})'


SMOOTH_WINDOW = 7  # steps = weeks; ~1 quarter smoothing
COLORS = ['tab:green', 'tab:blue', 'tab:orange', 'tab:red', 'tab:purple']

# Scalar shelter/reconstruction outcomes saved by
# run_model_earthquake_shelteroverflow.m (added alongside the SA_* trends -
# see that script's "outcome tracking" block near Shelters=[]/Sheltered_Outside
# init, and the per-step headcount snapshot at the end of the step loop).
# Not present in .mat files saved before that change - load_shelter_outcomes
# reports those as NaN rather than erroring.
SHELTER_VARS = [
    ('n_destroyed_total', 'Buildings destroyed (at shock)'),
    ('n_reconstructed_final', 'Buildings reconstructed (by end of sim)'),
    ('n_immediate_hh_max', 'In-city shelter - peak households'),
    ('n_immediate_hh_final', 'In-city shelter - households at end'),
    ('n_outside_hh_max', 'Sheltered outside city - peak households'),
    ('n_outside_hh_final', 'Sheltered outside city - households at end'),
    ('n_tempdev_hh_max', 'Temp-dev sites - peak households'),
    ('n_tempdev_hh_final', 'Temp-dev sites - households at end'),
    ('n_permanently_displaced_total', 'Permanently displaced (by end of sim)'),
]

# Per-step shelter/displacement tracks (n_replicates x n_steps arrays),
# saved alongside SHELTER_VARS's scalar summaries -- see that block's
# comment. Used by load_shelter_tracks()/plot_shelter_timeseries() for the
# two "standard output" time-series charts: shelter tiers + total currently
# sheltered, and cumulative permanent displacement on its own chart (see
# chat 2026-09-15 -- these replaced an earlier single combined chart that
# put permanent displacement on a second axis alongside the tiers).
SHELTER_TRACK_VARS = ['n_immediate_hh_track', 'n_outside_hh_track', 'n_tempdev_hh_track',
                       'n_permanently_displaced_track']


def find_files(root, pattern):
    files = sorted(glob.glob(os.path.join(root, 'earthquakeF', f'{pattern}.mat')))
    if not files:
        # allow patterns without a trailing/leading wildcard already baked in
        files = sorted(glob.glob(os.path.join(root, 'earthquakeF', pattern)))
    return files


def load_macro(files):
    """Returns dict var -> {'values': (n_replicates, n_steps) array, 'x': real
    simulation-week index (0-based) of each surviving column}. 'x' matters:
    SA_* only updates every sa_update_every real steps (currently 4 - the
    `mod(i,4)==0` trigger in run_model_earthquake_shelteroverflow.m), so
    after dropping the unpopulated zero-filled columns, column position in
    the trimmed array is NOT the real week number - column 5 of the
    survivors is real week 20, not week 5. Plotting against a fresh
    np.arange(len(...)) instead of the real column index silently mislabels
    every x-axis by a factor of sa_update_every. 'x' is taken from the
    first replicate file for a given scenario/var (the update cadence is a
    fixed step-count trigger, not data-dependent, so all replicates share
    the same populated positions for a given run length)."""
    out = {v: [] for v, _, _ in MACRO_VARS}
    out_x = {v: [] for v, _, _ in MACRO_VARS}
    for f in files:
        m = sio.loadmat(f, variable_names=[v for v, _, _ in MACRO_VARS], simplify_cells=True)
        for v, _, agg in MACRO_VARS:
            if v not in m:
                continue
            arr = np.asarray(m[v])  # (n_SA, n_steps)
            # SA_* columns are only populated every sa_update_every steps --
            # unpopulated step-columns are literally zero-filled, not NaN.
            # Same heuristic modelthesis/analysis_scripts/plot_sim_results.py's
            # compare mode uses. Without this, sa_update_every>1 runs plot a
            # sawtooth crashing to 0 between each real update instead of a
            # smooth line through only the populated steps.
            populated = (arr != 0).any(axis=0)
            step_idx = np.nonzero(populated)[0]  # real week number of each surviving column
            if populated.any():
                arr = arr[:, populated]
            daily = arr.sum(axis=0) if agg == 'sum' else np.nanmean(arr, axis=0)
            out[v].append(daily)
            out_x[v].append(step_idx)
    result = {}
    for v in out:
        lens = [len(x) for x in out[v]]
        n = min(lens) if lens else 0
        values = np.array([x[:n] for x in out[v]]) if n else np.array([])
        x = out_x[v][0][:n] if n and out_x[v] else np.array([])
        result[v] = {'values': values, 'x': x}

    # derived variables -- city-total ratios/product on the already-reduced
    # series above (see DERIVED_VARS comment for methodology). All base
    # SA_* vars update on the same sa_update_every-step cadence within one
    # file, so they share the same populated positions/'x' -- reuse
    # SA_WP's, truncating every input to the shortest of the ones involved
    # in case a replicate's columns don't align exactly.
    def _safe_div(a, b):
        with np.errstate(divide='ignore', invalid='ignore'):
            return np.where(b != 0, a / b, np.nan)

    def _common(*names):
        n = min(result[nm]['values'].shape[1] if result[nm]['values'].size else 0 for nm in names)
        return n

    dec_present = [d for d in DECILE_VARS if result.get(d, {}).get('values', np.array([])).size]
    if dec_present:
        n = _common(*dec_present)
        total_hh_vals = sum(result[d]['values'][:, :n] for d in dec_present)
        result['SA_TOTAL_HH'] = {'values': total_hh_vals, 'x': result[dec_present[0]]['x'][:n]}
    else:
        result['SA_TOTAL_HH'] = {'values': np.array([]), 'x': np.array([])}

    def _ratio_entry(num, den):
        if not (result.get(num, {}).get('values', np.array([])).size and
                result.get(den, {}).get('values', np.array([])).size):
            return {'values': np.array([]), 'x': np.array([])}
        n = _common(num, den)
        return {'values': _safe_div(result[num]['values'][:, :n], result[den]['values'][:, :n]),
                'x': result[num]['x'][:n]}

    result['SA_JPM2'] = _ratio_entry('SA_WP', 'SA_AREA')
    result['SA_JPP'] = _ratio_entry('SA_WP', 'SA_POP')
    if result['SA_WP']['values'].size and result['SA_TOTAL_HH']['values'].size:
        n = min(result['SA_WP']['values'].shape[1], result['SA_TOTAL_HH']['values'].shape[1])
        result['SA_JPTOTAL'] = {'values': _safe_div(result['SA_WP']['values'][:, :n], result['SA_TOTAL_HH']['values'][:, :n]),
                                 'x': result['SA_WP']['x'][:n]}
    else:
        result['SA_JPTOTAL'] = {'values': np.array([]), 'x': np.array([])}
    if result['SA_WAGE']['values'].size and result['SA_TOTAL_HH']['values'].size:
        n = min(result['SA_WAGE']['values'].shape[1], result['SA_TOTAL_HH']['values'].shape[1])
        result['SA_WAGE_TOT'] = {'values': result['SA_WAGE']['values'][:, :n] * result['SA_TOTAL_HH']['values'][:, :n],
                                  'x': result['SA_WAGE']['x'][:n]}
    else:
        result['SA_WAGE_TOT'] = {'values': np.array([]), 'x': np.array([])}
    result['SA_WAGE_HPRICE'] = _ratio_entry('SA_WAGE', 'SA_HOUSE')

    return result


def load_shelter_outcomes(files):
    """Returns dict var -> 1D array of per-replicate scalar values (one per
    file). A var missing from a given file (saved before these outcome
    variables were added to the model script) is recorded as NaN for that
    replicate rather than raising."""
    out = {v: [] for v, _ in SHELTER_VARS}
    for f in files:
        m = sio.loadmat(f, variable_names=[v for v, _ in SHELTER_VARS], simplify_cells=True)
        for v, _ in SHELTER_VARS:
            out[v].append(float(m[v]) if v in m else np.nan)
    return {v: np.array(vals) for v, vals in out.items()}


def load_shelter_tracks(files):
    """Returns (tracks, shock_step, temp_dev_delay) for one scenario's
    replicate files. tracks maps each SHELTER_TRACK_VARS name to an
    (n_replicates, n_steps) array (replicates padded/truncated to the
    shortest one, same convention as load_macro's daily-aggregate arrays).
    shock_step/temp_dev_delay are read from the first file (assumed
    consistent across replicates of one scenario) -- used to place the
    "shock" and "temp-dev opens" markers and to auto-detect the
    shock-to-settling window in plot_shelter_timeseries(). Returns
    shock_step=None if the file predates that variable being saved."""
    want = SHELTER_TRACK_VARS + ['shock_step', 'temp_dev_delay']
    out = {v: [] for v in SHELTER_TRACK_VARS}
    shock_step = temp_dev_delay = None
    for i, f in enumerate(files):
        m = sio.loadmat(f, variable_names=want, simplify_cells=True)
        for v in SHELTER_TRACK_VARS:
            if v in m:
                out[v].append(np.asarray(m[v]).astype(float).squeeze())
        if i == 0:
            shock_step = float(m['shock_step']) if 'shock_step' in m else None
            temp_dev_delay = float(m['temp_dev_delay']) if 'temp_dev_delay' in m else None
    tracks = {}
    for v, arrs in out.items():
        if not arrs:
            tracks[v] = np.array([])
            continue
        n = min(len(a) for a in arrs)
        tracks[v] = np.array([a[:n] for a in arrs])
    return tracks, shock_step, temp_dev_delay


def _mean_std(a):
    return a.mean(axis=0), a.std(axis=0, ddof=1) if a.shape[0] > 1 else np.zeros(a.shape[1])


def _prepare_shelter_plot(scenario_tracks):
    """Shared setup for the shelter-outcome charts (total_sheltered,
    permanent_displacement, shelter_tiers): filters scenario_tracks down
    to scenarios with a firing shock, and computes the shared "shock
    through settling" window. Returns (plotted, window_start, window_end,
    mask, steps_full, multi) or None if no scenario has a firing shock."""
    plotted = []
    for label, tracks, shock_step, temp_dev_delay in scenario_tracks:
        imm, out_, tmp, perm = (tracks.get(v, np.array([])) for v in SHELTER_TRACK_VARS)
        if shock_step is None or imm.size == 0 or out_.size == 0 or tmp.size == 0:
            continue
        n_steps = imm.shape[1]
        if shock_step >= n_steps:
            continue  # shock never fires this run (e.g. a no-shock baseline) -- nothing to show
        plotted.append((label, imm, out_, tmp, perm, shock_step, temp_dev_delay, n_steps))

    if not plotted:
        return None

    window_start = int(min(p[5] for p in plotted))
    max_steps = max(p[7] for p in plotted)
    window_end = max_steps
    for _, _, _, _, perm, _, _, n_steps in plotted:
        if perm.size == 0:
            continue
        m = perm.mean(axis=0)
        changed = np.nonzero(np.diff(m) != 0)[0]
        last_change = (changed[-1] + 2) if changed.size else 1  # +1 for diff offset, +1 for 1-indexed step
        window_end = min(window_end, max(last_change + 5, window_start + 1))
    window_end = min(window_end, max_steps)

    steps_full = np.arange(1, max_steps + 1)
    mask = (steps_full >= window_start) & (steps_full <= window_end)
    multi = len(plotted) > 1
    return plotted, window_start, window_end, mask, steps_full, multi


def _draw_shock_markers(ax, shock_step, temp_dev_delay):
    ax.axvline(shock_step, color='gray', linestyle='--', alpha=0.5, label=f'Shock (week {int(shock_step)})')
    if temp_dev_delay is not None:
        opens_at = shock_step + temp_dev_delay
        ax.axvline(opens_at, color='black', linewidth=2.8, alpha=0.85,
                   label=f'Temp-dev opens (week {int(opens_at)})')


def build_total_sheltered_fig(prepared, title_suffix):
    """Total-currently-sheltered (sum of all three tiers, regardless of
    location) as its own figure -- shared by plot_shelter_timeseries'
    standalone PNG and plot_pdf_and_pngs' PDF page."""
    plotted, window_start, window_end, mask, steps_full, multi = prepared
    fig, ax = plt.subplots(figsize=(9, 5))
    for idx, (label, imm, out_, tmp, perm, shock_step, temp_dev_delay, n_steps) in enumerate(plotted):
        total = imm + out_ + tmp
        m = min(mask.size, n_steps)
        sub_mask = mask[:m]
        sub_steps = steps_full[:m][sub_mask]
        dm, ds = _mean_std(total)
        color = COLORS[idx % len(COLORS)]
        ax.plot(sub_steps, dm[:m][sub_mask], color=color, linewidth=2.4,
                 label=f'Total currently sheltered{f" -- {label}" if multi else ""}')
        ax.fill_between(sub_steps, np.clip(dm[:m][sub_mask] - ds[:m][sub_mask], 0, None),
                         dm[:m][sub_mask] + ds[:m][sub_mask], color=color, alpha=0.15)
        _draw_shock_markers(ax, shock_step, temp_dev_delay)
    ax.set_xlabel('Week')
    ax.set_ylabel('Households currently sheltered (any location)')
    ax.set_xlim(window_start, window_end)
    ax.legend(loc='upper right', fontsize=9)
    ax.set_title(f'Total households currently sheltered, any location{title_suffix}\n'
                 f'mean ± 1 std across replicates (shock through settling)')
    plt.tight_layout()
    return fig


def build_permanent_displacement_fig(prepared, title_suffix):
    """Cumulative permanently-displaced households as its own figure --
    shared by plot_shelter_timeseries' standalone PNG and
    plot_pdf_and_pngs' PDF page."""
    plotted, window_start, window_end, mask, steps_full, multi = prepared
    fig, ax = plt.subplots(figsize=(9, 5.5))
    for idx, (label, imm, out_, tmp, perm, shock_step, temp_dev_delay, n_steps) in enumerate(plotted):
        if perm.size == 0:
            continue
        m = min(mask.size, n_steps)
        sub_mask = mask[:m]
        sub_steps = steps_full[:m][sub_mask]
        dm, ds = _mean_std(perm)
        color = COLORS[idx % len(COLORS)] if multi else 'tab:red'
        ax.plot(sub_steps, dm[:m][sub_mask], color=color, linewidth=2.4,
                 label=f'Cumulative permanently displaced{f" -- {label}" if multi else " (mean)"}')
        ax.fill_between(sub_steps, np.clip(dm[:m][sub_mask] - ds[:m][sub_mask], 0, None),
                         dm[:m][sub_mask] + ds[:m][sub_mask], color=color, alpha=0.18)
        _draw_shock_markers(ax, shock_step, temp_dev_delay)
    ax.set_xlabel('Week')
    ax.set_ylabel('Cumulative permanently displaced households')
    ax.set_xlim(window_start, window_end)
    ax.legend(loc='upper left', fontsize=9)
    ax.set_title(f'Cumulative permanent displacement{title_suffix}\n'
                 f'mean ± 1 std across replicates (shock through settling)')
    plt.tight_layout()
    return fig


def plot_shelter_timeseries(scenario_tracks, out_dir, title_suffix):
    """Three "standard output" charts built from SHELTER_TRACK_VARS, for
    whichever labeled scenarios actually have a firing shock (shock_step
    is set and less than the run length -- a no-shock baseline is skipped
    here since every tier and the displacement count stay at zero):
      shelter_tiers.png       -- the three tiers + total currently
                                  sheltered (sum of the three), one line
                                  set per scenario
      total_sheltered.png     -- just the total-currently-sheltered line,
                                  no tier breakdown (a simpler at-a-glance
                                  version of the chart above)
      permanent_displacement.png -- cumulative permanently displaced,
                                  on its own chart (previously a second
                                  axis on the tiers chart -- split out so
                                  each chart has one shared unit)
    All three share an auto-detected "shock through settling" window:
    starts at the earliest firing shock_step among the plotted scenarios,
    ends 5 steps after the last step at which ANY plotted scenario's
    cumulative-displacement mean still changes (falls back to the full
    run length if a scenario never settles within it -- e.g. an
    unbounded per-household patience test that's still resolving at the
    end of a short smoke-test run)."""
    prepared = _prepare_shelter_plot(scenario_tracks)
    if prepared is None:
        return
    plotted, window_start, window_end, mask, steps_full, multi = prepared

    os.makedirs(out_dir, exist_ok=True)

    # ---- shelter_tiers.png: three tiers + total currently sheltered ----
    fig, ax = plt.subplots(figsize=(10, 6))
    for idx, (label, imm, out_, tmp, perm, shock_step, temp_dev_delay, n_steps) in enumerate(plotted):
        total = imm + out_ + tmp
        m = min(mask.size, n_steps)
        sub_mask = mask[:m]
        sub_steps = steps_full[:m][sub_mask]
        tier_suffix = f' -- {label}' if multi else ''
        for tlabel, data, color, ls, lw in [
            (f'Immediate/hotel shelter{tier_suffix}', imm, 'tab:blue', '-', 1.8),
            (f'Sheltered outside (overflow){tier_suffix}', out_, 'tab:orange', '-', 1.8),
            (f'Temp-dev sites{tier_suffix}', tmp, 'tab:green', '-', 1.8),
            (f'Total currently sheltered{tier_suffix}', total, COLORS[idx % len(COLORS)], '--', 2.4),
        ]:
            dm, ds = _mean_std(data)
            ax.plot(sub_steps, dm[:m][sub_mask], color=color, linewidth=lw, linestyle=ls, label=tlabel)
            ax.fill_between(sub_steps, np.clip(dm[:m][sub_mask] - ds[:m][sub_mask], 0, None),
                             dm[:m][sub_mask] + ds[:m][sub_mask], color=color, alpha=0.13)
        _draw_shock_markers(ax, shock_step, temp_dev_delay)
    ax.set_xlabel('Week')
    ax.set_ylabel('Households')
    ax.set_xlim(window_start, window_end)
    ax.legend(loc='upper right', fontsize=8)
    ax.set_title(f'Shelter tiers and total currently sheltered{title_suffix}\n'
                 f'mean ± 1 std across replicates (shock through settling)')
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, 'shelter_tiers.png'), dpi=150)
    plt.close(fig)

    # ---- total_sheltered.png / permanent_displacement.png: shared with
    # the PDF pages built by plot_pdf_and_pngs -- see build_total_sheltered_fig
    # / build_permanent_displacement_fig ----
    fig = build_total_sheltered_fig(prepared, title_suffix)
    fig.savefig(os.path.join(out_dir, 'total_sheltered.png'), dpi=150)
    plt.close(fig)

    fig = build_permanent_displacement_fig(prepared, title_suffix)
    fig.savefig(os.path.join(out_dir, 'permanent_displacement.png'), dpi=150)
    plt.close(fig)


def smooth(v, window=SMOOTH_WINDOW):
    import pandas as pd
    s = pd.Series(v)
    return s.rolling(window, min_periods=1, center=True).mean().values


def plot_grid(macros, labels, out_path, title_suffix):
    n_vars = len(ALL_VARS)
    ncols = 4
    nrows = -(-n_vars // ncols)
    fig, axes = plt.subplots(nrows, ncols, figsize=(5 * ncols, 3.6 * nrows))
    for ax, (v, vlabel, detail, derived) in zip(axes.flat, ALL_VARS):
        any_data = False
        for macro, label, color in zip(macros, labels, COLORS):
            entry = macro.get(v)
            series = entry['values'] if entry else np.array([])
            if series.size == 0:
                continue
            any_data = True
            steps = entry['x']
            mean_raw = np.nanmean(series, axis=0)
            std_raw = np.nanstd(series, axis=0)
            ax.plot(steps, smooth(mean_raw), color=color, linewidth=1.6, label=label if len(labels) > 1 else None)
            ax.fill_between(steps, smooth(mean_raw - std_raw), smooth(mean_raw + std_raw), color=color, alpha=0.15)
        if not any_data:
            ax.axis('off')
            continue
        # line-wrap full_label()'s text after the descriptive label so it
        # fits the small grid panel -- same content, newline instead of a
        # space before the parenthetical
        title = full_label(v, vlabel, detail, derived).replace(' (', '\n(', 1)
        ax.set_title(title, fontsize=9.5)
        ax.set_xlabel('step (week)', fontsize=8)
        ax.tick_params(labelsize=8)
        if len(labels) > 1:
            ax.legend(fontsize=7)
    for ax in axes.flat[n_vars:]:
        ax.axis('off')
    fig.suptitle(f'Macro-economic (SA_*) trends{title_suffix}', fontsize=14)
    plt.tight_layout(rect=[0, 0, 1, 0.97])
    plt.savefig(out_path, dpi=130)
    plt.close(fig)


def format_stat(vals):
    """vals: per-replicate scalar array for one metric/scenario. Mean across
    replicates, with the observed range appended when replicates disagree
    (n_sims=1 or all-equal replicates just show the single number)."""
    vals = np.asarray(vals, dtype=float)
    valid = vals[~np.isnan(vals)]
    if valid.size == 0:
        return 'n/a'
    mean = valid.mean()
    if valid.size > 1 and valid.max() != valid.min():
        return f'{mean:,.0f} ({valid.min():,.0f}-{valid.max():,.0f})'
    return f'{mean:,.0f}'


def build_table_figure(shelter_by_label, labels, title_suffix):
    """One page: reconstruction + per-tier sheltering headcounts (from
    SHELTER_VARS, saved by run_model_earthquake_shelteroverflow.m), rows =
    metric, columns = scenario. 'n/a' means that .mat file predates these
    outcome variables being added to the model script."""
    row_labels = [desc for _, desc in SHELTER_VARS]
    cell_text = [
        [format_stat(shelter_by_label.get(label, {}).get(v, [np.nan])) for label in labels]
        for v, _ in SHELTER_VARS
    ]
    fig_h = 1.1 + 0.5 * len(SHELTER_VARS)
    fig, ax = plt.subplots(figsize=(max(9, 2.3 * len(labels) + 4.5), fig_h))
    ax.axis('off')
    tbl = ax.table(cellText=cell_text, rowLabels=row_labels, colLabels=labels, loc='center', cellLoc='center')
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(9.5)
    tbl.scale(1, 1.7)
    for (r, c), cell in tbl.get_celld().items():
        if r == 0 or c == -1:
            cell.set_text_props(weight='bold')
            cell.set_facecolor('#eeeeee')
    ax.set_title(f'Shelter & reconstruction outcomes{title_suffix}\n'
                 f'(mean across replicates; range shown in parentheses when replicates differ)',
                 fontsize=12, pad=18)
    fig.tight_layout()
    return fig


def plot_pdf_and_pngs(macros, labels, shelter_by_label, pdf_path, png_dir, title_suffix, scenario_tracks=None):
    os.makedirs(png_dir, exist_ok=True)
    with PdfPages(pdf_path) as pdf:
        table_fig = build_table_figure(shelter_by_label, labels, title_suffix)
        pdf.savefig(table_fig, bbox_inches='tight')
        plt.close(table_fig)
        if scenario_tracks:
            prepared = _prepare_shelter_plot(scenario_tracks)
            if prepared is not None:
                for fig in (build_total_sheltered_fig(prepared, title_suffix),
                            build_permanent_displacement_fig(prepared, title_suffix)):
                    pdf.savefig(fig, bbox_inches='tight')
                    plt.close(fig)
        for v, vlabel, detail, derived in ALL_VARS:
            if all((macro.get(v) or {}).get('values', np.array([])).size == 0 for macro in macros):
                continue
            fig, ax = plt.subplots(figsize=(9, 5.5))
            for macro, label, color in zip(macros, labels, COLORS):
                entry = macro.get(v)
                series = entry['values'] if entry else np.array([])
                if series.size == 0:
                    continue
                steps = entry['x']
                mean_raw = np.nanmean(series, axis=0)
                std_raw = np.nanstd(series, axis=0)
                ax.plot(steps, smooth(mean_raw), color=color, linewidth=2, label=f'{label} (n={series.shape[0]})')
                ax.fill_between(steps, smooth(mean_raw - std_raw), smooth(mean_raw + std_raw), color=color, alpha=0.15)
            ax.set_title(f'{full_label(v, vlabel, detail, derived)}{title_suffix}', fontsize=12)
            ax.set_xlabel('step (week)')
            ax.set_ylabel(vlabel)
            if len(labels) > 1:
                ax.legend(fontsize=9)
            plt.tight_layout()
            fig.savefig(os.path.join(png_dir, f'{v}.png'), dpi=200)
            pdf.savefig(fig, bbox_inches='tight')
            plt.close(fig)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--city', action='append', default=[], help=f'friendly city name ({", ".join(CITY_PREFIX)}) - repeatable for a side-by-side comparison')
    ap.add_argument('--pattern', action='append', default=[], help='raw glob pattern (without .mat) against earthquakeF/, for anything not in --city\'s known prefixes; pairs positionally with --label')
    ap.add_argument('--label', action='append', default=[], help='label for the matching --pattern entry (defaults to the pattern itself)')
    ap.add_argument('--root', default=HERE, help='project root containing earthquakeF/ (default: this script\'s directory)')
    ap.add_argument('--out', default=os.path.join(HERE, 'plots_macro_comparison'), help='output directory')
    args = ap.parse_args()

    scenarios = []  # list of (label, pattern)
    for c in args.city:
        if c not in CITY_PREFIX:
            raise SystemExit(f'Unknown --city "{c}". Known: {list(CITY_PREFIX)}. Use --pattern for anything else.')
        scenarios.append((c, f'{CITY_PREFIX[c]} EQ*'))
    for i, p in enumerate(args.pattern):
        label = args.label[i] if i < len(args.label) else p
        scenarios.append((label, p))

    if not scenarios:
        raise SystemExit('Pass at least one --city or --pattern.')

    macros, labels, shelter_by_label = [], [], {}
    scenario_tracks = []
    for label, pattern in scenarios:
        files = find_files(args.root, pattern)
        if not files:
            print(f'[warn] no files found for "{label}" (pattern "{pattern}*") under {args.root}\\earthquakeF\\ - skipping')
            continue
        print(f'[{label}] {len(files)} replicate file(s): ' + ', '.join(os.path.basename(f) for f in files))
        macros.append(load_macro(files))
        shelter_by_label[label] = load_shelter_outcomes(files)
        tracks, shock_step, temp_dev_delay = load_shelter_tracks(files)
        scenario_tracks.append((label, tracks, shock_step, temp_dev_delay))
        labels.append(label)

    if not macros:
        raise SystemExit('No matching files for any requested scenario.')

    os.makedirs(args.out, exist_ok=True)
    title_suffix = ' vs. '.join(labels) if len(labels) > 1 else f' -- {labels[0]}'
    title_suffix = f' ({title_suffix})' if len(labels) > 1 else f' -- {labels[0]}'

    plot_grid(macros, labels, os.path.join(args.out, 'macro_trends.png'), title_suffix)
    plot_pdf_and_pngs(macros, labels, shelter_by_label, os.path.join(args.out, 'macro_trends.pdf'), os.path.join(args.out, 'macro_pngs'), title_suffix, scenario_tracks=scenario_tracks)
    plot_shelter_timeseries(scenario_tracks, args.out, title_suffix)
    print(f'[done] -> {os.path.abspath(args.out)}')


if __name__ == '__main__':
    main()
