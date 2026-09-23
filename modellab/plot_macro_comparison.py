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
  - macro_trends.pdf : one page per SA_* variable (same 30 as above),
    preceded by: (1) a shelter & reconstruction outcomes table (from
    SHELTER_VARS -- reconstruction + per-tier sheltering headcounts) and,
    for any scenario with a firing shock, (2) total households currently
    sheltered (any location, cumulative across all three tiers) and (3)
    cumulative permanent displacement -- see build_total_sheltered_fig/
    build_permanent_displacement_fig, auto-windowed to the shock-through-
    settling range
  - macro_pngs/<VAR>.png : each SA_* variable as its own PNG
  - shelter_tiers.png / total_sheltered.png / permanent_displacement.png :
    the same shock-scenario outcome charts as the PDF pages above, as
    their own standalone PNGs (shelter_tiers.png additionally breaks the
    total down by tier: immediate/hotel, outside-overflow, temp-dev) --
    see plot_shelter_timeseries()
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
    'Beer Sheva': 'BS08hotels',   # data_for_model_BS08hotels -> data2{end}='BS08hotels'
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
COLORS = ['tab:green', 'tab:blue', 'tab:orange', 'tab:red', 'tab:purple',
          'tab:brown', 'tab:pink', 'tab:gray', 'tab:olive', 'tab:cyan']
# NOTE (chat 2026-09-23): plot_grid/plot_pdf_and_pngs's per-variable charts
# build their color mapping via zip(macros, labels, COLORS) - zip() silently
# truncates to the SHORTEST of the three, so with more scenario labels than
# COLORS entries, the extra scenario(s) just vanish from those specific
# charts (not an error, not visible in the output at all) rather than
# reusing a color like every other COLORS consumer in this file (which all
# index via `idx % len(COLORS)`). Found via a 6-scenario comparison where
# the 6th scenario was silently missing from macro_trends.png/.pdf while
# present in shelter_tiers.png/total_sheltered.png/permanent_displacement.png/
# aid_distributed.png. Widened to 10 colors as a fix; if a comparison ever
# exceeds 10 scenarios, the same silent-drop will recur for #11+ unless
# COLORS is widened again or those two call sites switch to modulo indexing
# like the rest.

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

# Subsidy sweep-analysis scalars (see HH_subsidy_targeted.m / cal_bui_sa_
# subsidy_targeted.m's own header comments, chat 2026-09-15/17) -- same
# convention as SHELTER_VARS: reported as NaN/'n/a' for .mat files saved
# before these were added, rather than erroring. subsidy_residents_mode
# and subsidy_businesses_mode are the sweep axes themselves, included here
# so the table is self-labeling even when the scenario --label doesn't
# spell out the combo.
SUBSIDY_VARS = [
    ('subsidy_residents_mode', 'Residents subsidy mode'),
    ('subsidy_businesses_mode', 'Businesses subsidy mode'),
    ('n_hh_subsidized_total', 'Households subsidized (cumulative)'),
    ('total_aid_distributed', 'Total aid distributed ($, by end of sim)'),
    ('n_businesses_subsidized_total', 'Businesses subsidized (cumulative)'),
    # jobs_subsidized/final_jobs/final_avg_wage/final_n_working (chat
    # 2026-09-23): DERIVED, not saved directly under these names -
    # load_subsidy_outcomes computes them from SA_WP/Individuals_data/
    # Work_places/businesses_subsidized_ever_ids. Same metrics as
    # analyze_subsidy_sweep.py's "Jobs subsidized" and absolute-value
    # table (see that script's header docstring for exact definitions
    # and caveats - e.g. final_avg_wage only excludes the household
    # subsidy's effect on individual income when subsidy_residents_mode
    # is off for every scenario being compared).
    ('jobs_subsidized', 'Jobs subsidized (current jobs @ ever-subsidized bldgs)'),
    ('final_jobs', 'Final total jobs, city-wide (SA_WP)'),
    ('final_avg_wage', 'Final average wage (working residents)'),
    ('final_n_working', 'Final # working residents'),
]

# Per-step cumulative aid track (chat 2026-09-19), same one-mat-per-
# replicate/padded-to-shortest convention as SHELTER_TRACK_VARS above --
# kept separate from that list (not folded in) since load_shelter_tracks'
# callers unpack SHELTER_TRACK_VARS as a fixed 4-tuple (imm/out_/tmp/perm);
# adding a 5th member there would silently break that unpacking. Missing
# in .mat files saved before this track was added to the model script.
AID_TRACK_VAR = 'total_aid_distributed_track'


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


_SUBSIDY_DERIVED_VARS = {'jobs_subsidized', 'final_jobs', 'final_avg_wage', 'final_n_working'}
_SUBSIDY_RAW_VARS = [v for v, _ in SUBSIDY_VARS if v not in _SUBSIDY_DERIVED_VARS]


def load_subsidy_outcomes(files):
    """Same pattern as load_shelter_outcomes, for SUBSIDY_VARS: dict var ->
    1D per-replicate scalar array, NaN for a file saved before that
    variable existed. jobs_subsidized/final_jobs/final_avg_wage/
    final_n_working (chat 2026-09-23) are DERIVED from SA_WP/
    Individuals_data/Work_places/businesses_subsidized_ever_ids rather
    than loaded directly - see SUBSIDY_VARS' comment and
    analyze_subsidy_sweep.py's header docstring for exact definitions."""
    out = {v: [] for v, _ in SUBSIDY_VARS}
    want = _SUBSIDY_RAW_VARS + ['SA_WP', 'Individuals_data', 'Work_places', 'businesses_subsidized_ever_ids']
    for f in files:
        m = sio.loadmat(f, variable_names=want, simplify_cells=True)
        for v in _SUBSIDY_RAW_VARS:
            out[v].append(float(m[v]) if v in m else np.nan)

        final_jobs = np.nan
        if 'SA_WP' in m:
            sa_wp = np.atleast_2d(np.asarray(m['SA_WP'], dtype=float))
            final_jobs = float(sa_wp[:, -1].sum())
        out['final_jobs'].append(final_jobs)

        avg_wage = np.nan
        n_working = np.nan
        if 'Individuals_data' in m:
            ind = np.asarray(m['Individuals_data'])
            working = (ind[:, 14] > 0) & (ind[:, 14] != 99)  # col15 work_place_id, col15 commuter code 99
            n_working = float(working.sum())
            if working.sum() > 0:
                avg_wage = float(ind[working, 13].mean())  # col14 income
        out['final_avg_wage'].append(avg_wage)
        out['final_n_working'].append(n_working)

        jobs_subsidized = np.nan
        if 'Work_places' in m and 'businesses_subsidized_ever_ids' in m:
            biz_ids = np.atleast_1d(np.asarray(m['businesses_subsidized_ever_ids'], dtype=float)).flatten()
            wp = np.asarray(m['Work_places'])
            jobs_subsidized = float(np.isin(wp[:, 0], biz_ids).sum()) if biz_ids.size > 0 else 0.0
        out['jobs_subsidized'].append(jobs_subsidized)

    return {v: np.array(vals) for v, vals in out.items()}


def load_aid_track(files):
    """Returns (track, shock_step, temp_dev_delay) for one scenario's
    replicate files -- same padded-to-shortest/first-file-metadata
    convention as load_shelter_tracks, but for the single AID_TRACK_VAR
    series instead of the fixed 4-tuple of shelter tracks. track is an
    (n_replicates, n_steps) array, empty if no file in this scenario has
    the variable."""
    want = [AID_TRACK_VAR, 'shock_step', 'temp_dev_delay']
    arrs = []
    shock_step = temp_dev_delay = None
    for i, f in enumerate(files):
        m = sio.loadmat(f, variable_names=want, simplify_cells=True)
        if AID_TRACK_VAR in m:
            arrs.append(np.asarray(m[AID_TRACK_VAR]).astype(float).squeeze())
        if i == 0:
            shock_step = float(m['shock_step']) if 'shock_step' in m else None
            temp_dev_delay = float(m['temp_dev_delay']) if 'temp_dev_delay' in m else None
    if not arrs:
        return np.array([]), shock_step, temp_dev_delay
    n = min(len(a) for a in arrs)
    return np.array([a[:n] for a in arrs]), shock_step, temp_dev_delay


def load_seeds(files):
    """Returns a list of rng_seed values, one per replicate file (chat
    2026-09-23, for the report title page) - None for a file saved before
    rng_seed was added to the save list, so the title page can still
    report a replicate count even when the seed itself is unknown."""
    seeds = []
    for f in files:
        m = sio.loadmat(f, variable_names=['rng_seed'], simplify_cells=True)
        seeds.append(int(m['rng_seed']) if 'rng_seed' in m else None)
    return seeds


def load_scenario_meta(files):
    """Returns (city, steps, shock_step) read from the first replicate
    file (chat 2026-09-23, for the title page) - assumed consistent
    across replicates of one scenario. None for any field missing from a
    file saved before it was added to the save list."""
    m = sio.loadmat(files[0], variable_names=['city', 'steps', 'shock_step'], simplify_cells=True)
    city = str(m['city']) if 'city' in m else None
    steps = int(m['steps']) if 'steps' in m else None
    shock_step = float(m['shock_step']) if 'shock_step' in m else None
    return city, steps, shock_step


def build_title_page_figure(title_suffix, scenario_info, show_pattern=True):
    """First page of the PDF (chat 2026-09-23): report title plus, per
    scenario, its plain-English description (what --desc was passed, if
    any - e.g. "mode 3" is meaningless on its own, this is where "1-month
    subsidy, full wage bill covered" lives, so the rest of the report can
    just say "mode 3" everywhere else per chat 2026-09-23), the city,
    step count, and shock week, the glob pattern it came from, its
    replicate count, and the exact seeds used - so the report is self-
    describing about how much data backs it without having to go dig
    through a manifest CSV.
    show_pattern=False drops the Pattern column (chat 2026-09-23) - useful
    when scenario_info's "pattern" isn't a real reusable glob (e.g. an
    explicit-file-list caller that just concatenated filenames there),
    where the column is more clutter than signal. Defaults to True,
    unchanged for existing CLI callers.
    scenario_info: list of (label, pattern, n_replicates, seeds, desc,
    city, steps, shock_step) - shock_step display collapses to "no shock"
    whenever it's None or falls at/beyond the run length (the model's own
    convention for "never fires" - see run_model_earthquake_
    shelteroverflow.m's shock_step=900 default)."""
    row_labels = [label for label, *_ in scenario_info]
    base_cols = ['Description', 'City', 'Steps', 'Shock week']
    col_labels = base_cols + ['Pattern', 'Replicates', 'Seeds'] if show_pattern else base_cols + ['Replicates', 'Seeds']
    cell_text = []
    for _, pattern, n_rep, seeds, desc, city, steps, shock_step in scenario_info:
        if seeds and all(s is not None for s in seeds):
            seeds_str = ', '.join(str(s) for s in seeds)
        elif seeds and any(s is not None for s in seeds):
            seeds_str = ', '.join(str(s) if s is not None else '?' for s in seeds)
        else:
            seeds_str = 'n/a (predates rng_seed save)'
        if shock_step is None or steps is None or shock_step >= steps:
            shock_str = 'no shock'
        else:
            shock_str = f'week {int(shock_step)}'
        row = [desc or '-', city or '?', str(steps) if steps is not None else '?', shock_str]
        if show_pattern:
            row.append(f'{pattern}*.mat')
        row += [str(n_rep), seeds_str]
        cell_text.append(row)
    fig, ax = plt.subplots(figsize=(max(12, 3 * len(col_labels) + 4), 1.6 + 0.6 * len(scenario_info)))
    ax.axis('off')
    tbl = ax.table(cellText=cell_text, rowLabels=row_labels, colLabels=col_labels, loc='center', cellLoc='left')
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(9.5)
    tbl.scale(1, 1.9)
    tbl.auto_set_column_width(col=list(range(len(col_labels))))
    for (r, c), cell in tbl.get_celld().items():
        if r == 0 or c == -1:
            cell.set_text_props(weight='bold')
            cell.set_facecolor('#eeeeee')
    ax.set_title(f'Macro-economic comparison report{title_suffix}\n'
                 f'Generated {__import__("datetime").datetime.now():%Y-%m-%d %H:%M}',
                 fontsize=13, pad=20)
    fig.tight_layout()
    return fig


def load_step_markers(files):
    """Returns (shock_step, lu_warmup) for one scenario, read from its
    first replicate file (chat 2026-09-23) - for the thin shock/land-use-
    warmup vertical reference lines drawn on every macro trend chart.
    shock_step defaults to 900 in the model script when never overridden
    (run_model_earthquake_shelteroverflow.m) - callers must still check it
    falls within the plotted step range before drawing it, since a
    no-shock baseline's shock_step is saved but never actually fires.
    lu_warmup (the step land-use/business updates start, i>lu_warmup)
    falls back to 4 - the model's own hardcoded default - for files saved
    before lu_warmup was added to the save list."""
    if not files:
        return None, 4.0
    m = sio.loadmat(files[0], variable_names=['shock_step', 'lu_warmup'], simplify_cells=True)
    shock_step = float(m['shock_step']) if 'shock_step' in m else None
    lu_warmup = float(m['lu_warmup']) if 'lu_warmup' in m else 4.0
    return shock_step, lu_warmup


def _draw_step_markers(ax, markers_by_label, max_step):
    """Thin reference lines shared by plot_grid and the per-variable PDF
    pages (chat 2026-09-23): a dotted line where the land-use/business
    module activates (lu_warmup) and a solid line where the shock fires
    (shock_step) - each drawn once per DISTINCT value actually in range,
    so scenarios sharing the same shock_step/lu_warmup (the common case)
    don't stack duplicate lines. A no-shock scenario's shock_step (saved
    as the unfired default, usually 900) is excluded by the max_step
    check below."""
    lu_vals = sorted({lu for _, lu in markers_by_label.values() if lu is not None and lu < max_step})
    for lu in lu_vals:
        ax.axvline(lu, color='dimgray', linestyle=':', linewidth=0.8, alpha=0.6, zorder=0)
    shock_vals = sorted({s for s, _ in markers_by_label.values() if s is not None and s < max_step})
    for s in shock_vals:
        ax.axvline(s, color='dimgray', linestyle='-', linewidth=0.8, alpha=0.6, zorder=0)


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


def _draw_shock_markers(ax, shock_step, temp_dev_delay, seen_labels=None):
    """seen_labels: optional set, mutated in place (chat 2026-09-23) - a
    legend label is only attached the FIRST time a given shock/temp-dev-
    open week is drawn, not once per scenario plotted on the same axes.
    Every scenario in one comparison typically shares the same shock
    config, so without this the legend would show one duplicate "Shock
    (week N)"/"Temp-dev opens (week N)" entry per scenario instead of one
    total. The line itself is still drawn every time (just unlabeled after
    the first), so multiple distinct shock weeks across scenarios that
    genuinely differ still each get their own legend entry."""
    shock_label = f'Shock (week {int(shock_step)})'
    already_shock = seen_labels is not None and shock_label in seen_labels
    ax.axvline(shock_step, color='gray', linestyle='--', alpha=0.5,
               label=None if already_shock else shock_label)
    if seen_labels is not None:
        seen_labels.add(shock_label)
    if temp_dev_delay is not None:
        opens_at = shock_step + temp_dev_delay
        opens_label = f'Temp-dev opens (week {int(opens_at)})'
        already_opens = seen_labels is not None and opens_label in seen_labels
        ax.axvline(opens_at, color='black', linewidth=2.8, alpha=0.85,
                   label=None if already_opens else opens_label)
        if seen_labels is not None:
            seen_labels.add(opens_label)


def build_total_sheltered_fig(prepared, title_suffix):
    """Total-currently-sheltered (sum of all three tiers, regardless of
    location) as its own figure -- shared by plot_shelter_timeseries'
    standalone PNG and plot_pdf_and_pngs' PDF page."""
    plotted, window_start, window_end, mask, steps_full, multi = prepared
    fig, ax = plt.subplots(figsize=(9, 5))
    seen_labels = set()
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
        _draw_shock_markers(ax, shock_step, temp_dev_delay, seen_labels)
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
    seen_labels = set()
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
        _draw_shock_markers(ax, shock_step, temp_dev_delay, seen_labels)
    ax.set_xlabel('Week')
    ax.set_ylabel('Cumulative permanently displaced households')
    ax.set_xlim(window_start, window_end)
    ax.legend(loc='upper left', fontsize=9)
    ax.set_title(f'Cumulative permanent displacement{title_suffix}\n'
                 f'mean ± 1 std across replicates (shock through settling)')
    plt.tight_layout()
    return fig


def build_aid_over_time_fig(aid_scenario_tracks, title_suffix):
    """Cumulative total aid distributed over time, one line per scenario
    label -- mirrors build_permanent_displacement_fig's shape, but full
    run length rather than the shock-to-settling window (a subsidy's own
    duration, e.g. modes 5/6's fixed 4/8-step window, needn't line up with
    when displacement itself settles, so that window isn't reused here).
    Returns None if no scenario has a non-empty, non-all-zero track (e.g.
    every scenario has subsidies off, or predates this track being saved)."""
    plotted = [(label, track, shock_step, temp_dev_delay)
               for label, track, shock_step, temp_dev_delay in aid_scenario_tracks
               if track.size and np.any(track != 0)]
    if not plotted:
        return None

    max_steps = max(track.shape[1] for _, track, _, _ in plotted)
    multi = len(plotted) > 1
    fig, ax = plt.subplots(figsize=(9, 5.5))
    seen_labels = set()
    for idx, (label, track, shock_step, temp_dev_delay) in enumerate(plotted):
        steps = np.arange(1, track.shape[1] + 1)
        dm, ds = _mean_std(track)
        color = COLORS[idx % len(COLORS)] if multi else 'tab:red'
        ax.plot(steps, dm, color=color, linewidth=2.4,
                 label=f'Cumulative aid distributed{f" -- {label}" if multi else " (mean)"}')
        ax.fill_between(steps, np.clip(dm - ds, 0, None), dm + ds, color=color, alpha=0.18)
        if shock_step is not None and shock_step < max_steps:
            _draw_shock_markers(ax, shock_step, temp_dev_delay, seen_labels)
    ax.set_xlabel('Week')
    ax.set_ylabel('Cumulative aid distributed ($)')
    ax.set_xlim(1, max_steps)
    ax.legend(loc='upper left', fontsize=9)
    ax.set_title(f'Cumulative aid distributed over time{title_suffix}\n'
                 f'mean ± 1 std across replicates')
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
    # chat 2026-09-23: all 4 series use ONE fixed color/style each,
    # regardless of how many scenarios are overlaid (unlike
    # total_sheltered.png/permanent_displacement.png, which vary color BY
    # scenario) -- per-scenario color was previously only applied to the
    # "Total currently sheltered" line (the 3 tier lines were always fixed-
    # color), producing a legend with one entry per (tier x scenario)
    # combination whose color didn't actually vary, i.e. pure duplicate
    # text for lines rendered identically. seen_labels (shared with
    # _draw_shock_markers) now dedupes ALL 4 tier labels the same way the
    # shock/temp-dev markers already were, down to exactly 4 entries total
    # regardless of scenario count.
    fig, ax = plt.subplots(figsize=(10, 6))
    seen_labels = set()
    for idx, (label, imm, out_, tmp, perm, shock_step, temp_dev_delay, n_steps) in enumerate(plotted):
        total = imm + out_ + tmp
        m = min(mask.size, n_steps)
        sub_mask = mask[:m]
        sub_steps = steps_full[:m][sub_mask]
        for tlabel, data, color, ls, lw in [
            ('Immediate/hotel shelter', imm, 'tab:blue', '-', 1.8),
            ('Sheltered outside (overflow)', out_, 'tab:orange', '-', 1.8),
            ('Temp-dev sites', tmp, 'tab:green', '-', 1.8),
            ('Total currently sheltered', total, 'black', '--', 2.4),
        ]:
            dm, ds = _mean_std(data)
            already = tlabel in seen_labels
            ax.plot(sub_steps, dm[:m][sub_mask], color=color, linewidth=lw, linestyle=ls,
                     label=None if already else tlabel)
            seen_labels.add(tlabel)
            ax.fill_between(sub_steps, np.clip(dm[:m][sub_mask] - ds[:m][sub_mask], 0, None),
                             dm[:m][sub_mask] + ds[:m][sub_mask], color=color, alpha=0.13)
        _draw_shock_markers(ax, shock_step, temp_dev_delay, seen_labels)
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


def plot_aid_timeseries(aid_scenario_tracks, out_dir, title_suffix):
    """Standalone aid_distributed.png, mirroring plot_shelter_timeseries'
    total_sheltered.png/permanent_displacement.png pattern but for
    AID_TRACK_VAR. No-op (nothing saved) if build_aid_over_time_fig finds
    no usable data."""
    fig = build_aid_over_time_fig(aid_scenario_tracks, title_suffix)
    if fig is None:
        return
    os.makedirs(out_dir, exist_ok=True)
    fig.savefig(os.path.join(out_dir, 'aid_distributed.png'), dpi=150)
    plt.close(fig)


def smooth(v, window=SMOOTH_WINDOW, x=None, break_at=None):
    """Centered rolling mean (see SMOOTH_WINDOW). BUG FOUND chat
    2026-09-23: center=True means the window looks BOTH forward and
    backward, so a sharp discontinuity (the shock) bled backward into the
    displayed pre-shock curve - verified against raw .mat data that
    pre-shock trajectories are bit-identical across all 5 seeds between a
    no-shock and a shock scenario, yet the smoothed chart showed them
    diverging ~3 steps (window//2) before the shock actually fired. Fix:
    when x (this series' real step index, from load_macro's 'x') and
    break_at (the step the discontinuity happens at, e.g. shock_step) are
    both given, split the series at that step and smooth each side
    independently, so the window never crosses the break. Falls back to
    the old whole-series behavior when break_at is None (e.g. no known
    discontinuity for this scenario, like a no-shock baseline) or doesn't
    fall within the plotted range."""
    import pandas as pd
    if x is None or break_at is None or break_at <= x[0] or break_at >= x[-1]:
        s = pd.Series(v)
        return s.rolling(window, min_periods=1, center=True).mean().values
    pre_mask = x < break_at
    out = np.empty_like(np.asarray(v, dtype=float))
    for mask in (pre_mask, ~pre_mask):
        if mask.any():
            out[mask] = pd.Series(np.asarray(v)[mask]).rolling(window, min_periods=1, center=True).mean().values
    return out


def _common_break_at(markers_by_label, labels):
    """A single shock-step boundary shared by every curve on one chart
    (chat 2026-09-23 - see smooth()'s docstring for why this must be
    shared rather than per-scenario). Using each scenario's OWN
    shock_step (None for a no-shock baseline) gave every curve a
    DIFFERENT window-capping treatment right at the boundary - the
    no-shock curve's window was unconstrained while a shock scenario's
    was capped at its own segment edge, so even though the underlying
    pre-shock DATA was verified bit-identical across scenarios, the
    smoothed curves still diverged by a small but visible amount right
    before the boundary (worse for narrow-range variables like SA_WAGE
    than wide-range ones like SA_WP). Using the SAME break point (the
    earliest firing shock_step among all plotted scenarios) for every
    curve's smoothing call - including scenarios with no shock of their
    own - makes the windowing treatment identical everywhere, so
    identical underlying data produces identical smoothed output."""
    vals = [(markers_by_label or {}).get(l, (None, None))[0] for l in labels]
    vals = [v for v in vals if v is not None]
    return min(vals) if vals else None


def plot_grid(macros, labels, out_path, title_suffix, markers_by_label=None):
    n_vars = len(ALL_VARS)
    ncols = 4
    nrows = -(-n_vars // ncols)
    common_break = _common_break_at(markers_by_label, labels)
    fig, axes = plt.subplots(nrows, ncols, figsize=(5 * ncols, 3.6 * nrows))
    for ax, (v, vlabel, detail, derived) in zip(axes.flat, ALL_VARS):
        any_data = False
        max_step = 0.0
        for macro, label, color in zip(macros, labels, COLORS):
            entry = macro.get(v)
            series = entry['values'] if entry else np.array([])
            if series.size == 0:
                continue
            any_data = True
            steps = entry['x']
            max_step = max(max_step, np.max(steps) if len(steps) else 0.0)
            mean_raw = np.nanmean(series, axis=0)
            std_raw = np.nanstd(series, axis=0)
            break_at = common_break if common_break is not None and common_break < steps[-1] else None
            ax.plot(steps, smooth(mean_raw, x=steps, break_at=break_at), color=color, linewidth=1.6, label=label if len(labels) > 1 else None)
            ax.fill_between(steps, smooth(mean_raw - std_raw, x=steps, break_at=break_at), smooth(mean_raw + std_raw, x=steps, break_at=break_at), color=color, alpha=0.15)
        if not any_data:
            ax.axis('off')
            continue
        if markers_by_label:
            _draw_step_markers(ax, markers_by_label, max_step)
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


def build_subsidy_table_figure(subsidy_by_label, labels, title_suffix):
    """Same layout as build_table_figure, for SUBSIDY_VARS -- one column
    per scenario label, so a sweep run with one --label per (residents_mode,
    businesses_mode) combo renders as a side-by-side policy comparison
    table (chat 2026-09-19)."""
    row_labels = [desc for _, desc in SUBSIDY_VARS]
    cell_text = [
        [format_stat(subsidy_by_label.get(label, {}).get(v, [np.nan])) for label in labels]
        for v, _ in SUBSIDY_VARS
    ]
    fig_h = 1.1 + 0.5 * len(SUBSIDY_VARS)
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
    ax.set_title(f'Subsidy policy outcomes{title_suffix}\n'
                 f'(mean across replicates; range shown in parentheses when replicates differ)',
                 fontsize=12, pad=18)
    fig.tight_layout()
    return fig


def plot_pdf_and_pngs(macros, labels, shelter_by_label, pdf_path, png_dir, title_suffix, scenario_tracks=None,
                       subsidy_by_label=None, aid_scenario_tracks=None, markers_by_label=None, scenario_info=None,
                       show_pattern_column=True):
    os.makedirs(png_dir, exist_ok=True)
    with PdfPages(pdf_path) as pdf:
        if scenario_info:
            title_fig = build_title_page_figure(title_suffix, scenario_info, show_pattern=show_pattern_column)
            pdf.savefig(title_fig, bbox_inches='tight')
            plt.close(title_fig)
        table_fig = build_table_figure(shelter_by_label, labels, title_suffix)
        pdf.savefig(table_fig, bbox_inches='tight')
        plt.close(table_fig)
        if subsidy_by_label:
            subsidy_table_fig = build_subsidy_table_figure(subsidy_by_label, labels, title_suffix)
            pdf.savefig(subsidy_table_fig, bbox_inches='tight')
            plt.close(subsidy_table_fig)
        if scenario_tracks:
            prepared = _prepare_shelter_plot(scenario_tracks)
            if prepared is not None:
                for fig in (build_total_sheltered_fig(prepared, title_suffix),
                            build_permanent_displacement_fig(prepared, title_suffix)):
                    pdf.savefig(fig, bbox_inches='tight')
                    plt.close(fig)
        if aid_scenario_tracks:
            aid_fig = build_aid_over_time_fig(aid_scenario_tracks, title_suffix)
            if aid_fig is not None:
                pdf.savefig(aid_fig, bbox_inches='tight')
                plt.close(aid_fig)
        common_break = _common_break_at(markers_by_label, labels)
        for v, vlabel, detail, derived in ALL_VARS:
            if all((macro.get(v) or {}).get('values', np.array([])).size == 0 for macro in macros):
                continue
            fig, ax = plt.subplots(figsize=(9, 5.5))
            max_step = 0.0
            for macro, label, color in zip(macros, labels, COLORS):
                entry = macro.get(v)
                series = entry['values'] if entry else np.array([])
                if series.size == 0:
                    continue
                steps = entry['x']
                max_step = max(max_step, np.max(steps) if len(steps) else 0.0)
                mean_raw = np.nanmean(series, axis=0)
                std_raw = np.nanstd(series, axis=0)
                break_at = common_break if common_break is not None and common_break < steps[-1] else None
                ax.plot(steps, smooth(mean_raw, x=steps, break_at=break_at), color=color, linewidth=2, label=f'{label} (n={series.shape[0]})')
                ax.fill_between(steps, smooth(mean_raw - std_raw, x=steps, break_at=break_at), smooth(mean_raw + std_raw, x=steps, break_at=break_at), color=color, alpha=0.15)
            if markers_by_label:
                _draw_step_markers(ax, markers_by_label, max_step)
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
    ap.add_argument('--desc', action='append', default=[], help='plain-English description of the matching --pattern entry, shown on the title page only (chat 2026-09-23) - e.g. --label "mode 3" --desc "1-month subsidy, full wage bill covered", so the label used everywhere else in the report can stay short')
    ap.add_argument('--root', default=HERE, help='project root containing earthquakeF/ (default: this script\'s directory)')
    ap.add_argument('--out', default=os.path.join(HERE, 'plots_macro_comparison'), help='output directory')
    args = ap.parse_args()

    scenarios = []  # list of (label, pattern, desc)
    for c in args.city:
        if c not in CITY_PREFIX:
            raise SystemExit(f'Unknown --city "{c}". Known: {list(CITY_PREFIX)}. Use --pattern for anything else.')
        scenarios.append((c, f'{CITY_PREFIX[c]} EQ*', ''))
    for i, p in enumerate(args.pattern):
        label = args.label[i] if i < len(args.label) else p
        desc = args.desc[i] if i < len(args.desc) else ''
        scenarios.append((label, p, desc))

    if not scenarios:
        raise SystemExit('Pass at least one --city or --pattern.')

    macros, labels, shelter_by_label, subsidy_by_label = [], [], {}, {}
    scenario_tracks = []
    aid_scenario_tracks = []
    markers_by_label = {}
    scenario_info = []
    for label, pattern, desc in scenarios:
        files = find_files(args.root, pattern)
        if not files:
            print(f'[warn] no files found for "{label}" (pattern "{pattern}*") under {args.root}\\earthquakeF\\ - skipping')
            continue
        print(f'[{label}] {len(files)} replicate file(s): ' + ', '.join(os.path.basename(f) for f in files))
        macros.append(load_macro(files))
        shelter_by_label[label] = load_shelter_outcomes(files)
        subsidy_by_label[label] = load_subsidy_outcomes(files)
        tracks, shock_step, temp_dev_delay = load_shelter_tracks(files)
        scenario_tracks.append((label, tracks, shock_step, temp_dev_delay))
        aid_track, aid_shock_step, aid_temp_dev_delay = load_aid_track(files)
        aid_scenario_tracks.append((label, aid_track, aid_shock_step, aid_temp_dev_delay))
        markers_by_label[label] = load_step_markers(files)
        city_meta, steps_meta, shock_step_meta = load_scenario_meta(files)
        scenario_info.append((label, pattern, len(files), load_seeds(files), desc, city_meta, steps_meta, shock_step_meta))
        labels.append(label)

    if not macros:
        raise SystemExit('No matching files for any requested scenario.')

    os.makedirs(args.out, exist_ok=True)
    title_suffix = ' vs. '.join(labels) if len(labels) > 1 else f' -- {labels[0]}'
    title_suffix = f' ({title_suffix})' if len(labels) > 1 else f' -- {labels[0]}'

    plot_grid(macros, labels, os.path.join(args.out, 'macro_trends.png'), title_suffix, markers_by_label=markers_by_label)
    plot_pdf_and_pngs(macros, labels, shelter_by_label, os.path.join(args.out, 'macro_trends.pdf'), os.path.join(args.out, 'macro_pngs'), title_suffix,
                       scenario_tracks=scenario_tracks, subsidy_by_label=subsidy_by_label, aid_scenario_tracks=aid_scenario_tracks,
                       markers_by_label=markers_by_label, scenario_info=scenario_info)
    plot_shelter_timeseries(scenario_tracks, args.out, title_suffix)
    plot_aid_timeseries(aid_scenario_tracks, args.out, title_suffix)
    print(f'[done] -> {os.path.abspath(args.out)}')


if __name__ == '__main__':
    main()
