"""
plot_baseline_macro_all.py
=============================
Reproduces the full set of macroeconomic plots from the colleague's
all_plots.pdf (workplace outcome, population, price, service count, wage,
workplace count, residential count/price, commercial floorspace, occupied
job share, unemployment rate, commuting rate, deciles 1-10, jobs/m²,
jobs per household, total wage income, wage/price ratio), but for THIS
project's no-shock baseline run (fullfid_baseline_rep1-10.mat, n=10
reps, wservice=0/wservice_old=0/svc_filter=0/eld_movef=1, 760 steps,
sa_update_every=1, lu_warmup=30, lu_update_every=1 -- matching
testingcodechanges/run_model_eq.m's native full-fidelity cadence, not
the fast-testing shortcuts used for the sweep work).

Colleague's population scale (~7200 households) is a different synthetic
population than this project's (~17450 households) -- not comparable in
raw levels, only in shape/trend. Mean line + shaded std band across the
8 replicates, matching the colleague's mean+band plotting style.

SA_* variable meanings (from run_model_earthquake.m):
  SA_PRICE   = mean asset price/m, ALL assets in SA
  SA_HOUSE   = mean asset price/m, residential-only (usage 1,2) assets
  SA_WAGE    = mean individual wage in SA
  SA_OUTCOME = sum of workplace salaries (Work_places col 8) in SA
  SA_POP     = count of occupied assets in SA (household count)
  SA_SERVICE = count of buildings with usage>2 in SA
  SA_RESIDENT= count of buildings with usage 1 or 2 in SA
  SA_WP      = count of workplaces in SA
  SA_JOBS    = share of occupied jobs (status 1 or 3) among all non-vacant/non-99 jobs
  SA_IDLE    = share of individuals with status==1 (idle) among status>0
  SA_LOCAL   = share of working (status==2) individuals among (status==2 or 99)
  SA_AREA    = total floorspace of usage==3 (commercial) buildings
  SA_FIRST..SA_TENTH = household count per income decile

Usage: python plot_baseline_macro_all.py
"""
import glob
import numpy as np
import scipy.io as sio
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

VARS = ['SA_PRICE', 'SA_HOUSE', 'SA_WAGE', 'SA_OUTCOME', 'SA_POP', 'SA_SERVICE',
        'SA_RESIDENT', 'SA_WP', 'SA_JOBS', 'SA_IDLE', 'SA_LOCAL', 'SA_AREA',
        'Work_places',
        'SA_FIRST', 'SA_SECOND', 'SA_THIRD', 'SA_FOURTH', 'SA_FIFTH',
        'SA_SIXTH', 'SA_SEVENTH', 'SA_EIGHTH', 'SA_NINTH', 'SA_TENTH']

files = sorted(glob.glob('earthquakeF/agesplit70 EQ S 1 test_labor_fix.mat'))
print(f'Loading {len(files)} baseline replicates...')

runs = []
for f in files:
    m = sio.loadmat(f, variable_names=VARS, simplify_cells=True)
    runs.append(m)

# columns actually populated (every sa_update_every steps)
sample = np.asarray(runs[0]['SA_POP'])
day_idx = np.where(np.any(sample != 0, axis=0))[0]
days = day_idx  # step index == day, since steps=100 and 1 step/day in this setup


def series(varname, agg='sum'):
    """Per-rep aggregate (sum or mean across SAs) at each populated day, stacked -> (n_reps, n_days)."""
    out = []
    for r in runs:
        v = np.asarray(r[varname])[:, day_idx]
        out.append(v.sum(axis=0) if agg == 'sum' else np.nanmean(v, axis=0))
    return np.array(out)


def total_wage_income():
    """Per-SA mean wage * per-SA household count, summed across SAs, as a
    real time series (not an endpoint snapshot)."""
    out = []
    for r in runs:
        wage = np.nan_to_num(np.asarray(r['SA_WAGE'])[:, day_idx], nan=0.0)
        pop = np.asarray(r['SA_POP'])[:, day_idx]
        out.append((wage * pop).sum(axis=0))
    return np.array(out)


def plot_metric(pdf, title, ylabel, values, x=None):
    x = days if x is None else x
    mean = np.nanmean(values, axis=0)
    std = np.nanstd(values, axis=0)
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.plot(x, mean, color='tab:green', label=f'Baseline (n={values.shape[0]} mean)')
    ax.fill_between(x, mean - std, mean + std, color='tab:green', alpha=0.2)
    ax.set_xlabel('Day')
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.legend()
    plt.tight_layout()
    pdf.savefig(fig)
    plt.close(fig)


with PdfPages('baseline_macro_all_plots.pdf') as pdf:
    plot_metric(pdf, 'Mean Workplace Outcome (total payroll per SA, avg across SAs)', 'Outcome',
                series('SA_OUTCOME', 'mean'))
    plot_metric(pdf, 'Total Population (occupied assets, summed across SAs)', 'Population',
                series('SA_POP', 'sum'))
    plot_metric(pdf, 'Mean Asset Price per Meter (all assets)', 'Price (per m²)',
                series('SA_PRICE', 'mean'))
    plot_metric(pdf, 'Mean Residential Price per Meter', 'Residential Price (per m²)',
                series('SA_HOUSE', 'mean'))
    plot_metric(pdf, 'Total Service Count (buildings, usage>2)', 'Service Count',
                series('SA_SERVICE', 'sum'))
    plot_metric(pdf, 'Total Residential Count (buildings, usage 1 or 2)', 'Residential Count',
                series('SA_RESIDENT', 'sum'))
    plot_metric(pdf, 'Mean Wage', 'Wage', series('SA_WAGE', 'mean'))
    plot_metric(pdf, 'Workplace Count', 'Workplace Count', series('SA_WP', 'sum'))
    plot_metric(pdf, 'Total Commercial Floorspace (usage==3)', 'Floorspace', series('SA_AREA', 'sum'))
    plot_metric(pdf, 'Mean Share of Occupied Jobs', 'Occupied Jobs', series('SA_JOBS', 'mean'))
    plot_metric(pdf, 'Mean Idle-Individual Rate (SA_IDLE; likely = unemployment rate)',
                'Idle Rate', series('SA_IDLE', 'mean'))
    plot_metric(pdf, 'Mean Local-Work Share (SA_LOCAL; commuting rate = 1 - this, tentative)',
                'Local Work Share', series('SA_LOCAL', 'mean'))

    decile_vars = ['SA_FIRST', 'SA_SECOND', 'SA_THIRD', 'SA_FOURTH', 'SA_FIFTH',
                   'SA_SIXTH', 'SA_SEVENTH', 'SA_EIGHTH', 'SA_NINTH', 'SA_TENTH']
    for i, dv in enumerate(decile_vars, start=1):
        plot_metric(pdf, f'Households in Decile {i}', f'HH in Decile {i}', series(dv, 'sum'))

    # derived: total jobs / total households, and jobs per m2 of commercial floorspace
    wp_sum = series('SA_WP', 'sum')
    pop_sum = series('SA_POP', 'sum')
    area_sum = series('SA_AREA', 'sum')
    plot_metric(pdf, 'Jobs per Household (Workplace Count / Population)', 'Jobs per HH', wp_sum / pop_sum)
    plot_metric(pdf, 'Jobs per m² (Workplace Count / Commercial Floorspace)', 'Jobs/m²', wp_sum / area_sum)

    wage_mean = series('SA_WAGE', 'mean')
    price_mean = series('SA_PRICE', 'mean')
    plot_metric(pdf, 'Wage-to-Price Ratio (mean wage / mean asset price)', 'Wage/Price', wage_mean / price_mean)

    plot_metric(pdf, 'Total Wage Income (sum of SA_WAGE x SA_POP across SAs)', 'Total Wages',
                total_wage_income())

print('[done] baseline_macro_all_plots.pdf')
