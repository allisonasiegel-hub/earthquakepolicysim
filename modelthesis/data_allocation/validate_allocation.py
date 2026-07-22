"""
validate_allocation.py
=======================
Sanity-checks the synthetic population/assets/workplaces produced by the
data-allocation pipeline (main_alloc.m -> distribute_workers.m) against the
CBS census inputs in sa_data_b7.csv.

This validates the *allocation-stage* output (data_for_model_tmine.mat:
HH_data, Individuals_data, Assets, Build_Data, Work_places) -- a
cross-sectional synthetic population, NOT the SA_* ABM simulation time
series handled by abm_analysis.py (those only exist after actually running
the ABM, e.g. nextchangesfortracker.m / run_model_eq.m). Different data
shape, so this uses its own checks, but mirrors abm_analysis.py's pattern
of a labeled metadata dict + tabular report for consistency.

Usage
-----
    python validate_allocation.py
    python validate_allocation.py --mat data_for_model_tmine.mat --census ..\\TVR\\sa_data_b7.csv
"""

from __future__ import annotations

import argparse
import os
import numpy as np
import pandas as pd
import scipy.io as sio

# ---------------------------------------------------------------------------
# 1. Column layouts (must match the *_P label arrays saved by the pipeline)
# ---------------------------------------------------------------------------

HH_COLS = ['stat', 'hh_id', 'individuals', 'children', 'n_old', 'hh_income',
           'hh_asiron', 'n_cars', 'yeshuv', 'building_id', 'asset_id']

IND_COLS = ['ind_id', 'stat', 'hh_id', 'fam_size', 'kids_in_fam', 'age_group',
            'dis_hear', 'dis_see', 'dis_reme', 'dis_dress', 'dis_walk',
            'working_status', 'asiron', 'income',
            'building_wp', 'stat_wp', 'wp_id']

ASSET_COLS = ['stat', 'building_id', 'asset_id', 'area_m', 'price', 'yeshuv',
              'travel_time', 'travel_dist', 'near_tt', 'near_p', 'occupied']

BUILD_COLS = ['bldg_id', 'height', 'usage', 'stat', 'x', 'y', 'area',
              'travel_time', 'travel_dist', 'year', 'floors', 'yeshuv',
              'near_far_b', 'tt_near_b', 'dist_near_b', 'price_m', 'work_place']

WP_COLS = ['building_id', 'stat', 'x', 'y', 'n_places', 'id', 'occupied', 'salary']

# working_status codes (set in labor_datasample.m / distribute_workers.m)
NOT_LABOR_FORCE, WANTS_WORK, WORKING = 0, 1, 2
LOCAL_WORK_SENTINEL = 99  # building_wp/stat_wp value for comm99 (local) workers

# age_group codes (Individuals_data col 6)
KID, ADULT, OLD = 1, 2, 3

# Flag a check when simulated share is off from the census target by more
# than this many percentage points (absolute) or this relative fraction,
# whichever check applies.
PP_TOL = 8.0     # percentage points, for share comparisons
REL_TOL = 0.30   # 30% relative, for count/rate comparisons


# ---------------------------------------------------------------------------
# 2. Loading
# ---------------------------------------------------------------------------

def _cols_for(base_cols, width, *extra_names):
    """Pad base_cols with extra_names if the .mat has trailing columns the
    base layout doesn't account for (e.g. old_old_count / is_old_old, only
    present in files built after the young-old/old-old split was added)."""
    if width <= len(base_cols):
        return base_cols[:width]
    extras = list(extra_names[:width - len(base_cols)])
    while len(extras) < width - len(base_cols):
        extras.append(f'extra_{len(extras)}')
    return base_cols + extras


def load_mat(mat_path: str) -> dict:
    m = sio.loadmat(mat_path, simplify_cells=True)
    hh_raw = m['HH_data']
    ind_raw = m['Individuals_data']
    return {
        'HH': pd.DataFrame(hh_raw, columns=_cols_for(HH_COLS, hh_raw.shape[1], 'old_old_count')),
        'IND': pd.DataFrame(ind_raw, columns=_cols_for(IND_COLS, ind_raw.shape[1], 'is_old_old')),
        'ASSETS': pd.DataFrame(m['Assets'], columns=ASSET_COLS),
        'BUILD': pd.DataFrame(m['Build_Data'], columns=BUILD_COLS),
        'WP': pd.DataFrame(m['Work_places'], columns=WP_COLS),
    }


def load_census(census_path: str) -> pd.DataFrame:
    df = pd.read_csv(census_path)
    return df.rename(columns={'locality_stat': 'stat'})


# ---------------------------------------------------------------------------
# 3. Report helper
# ---------------------------------------------------------------------------

def row(category, metric, sim, census, unit='%', note=''):
    """Build one report row; flags FAIL if sim deviates too far from census."""
    status = 'INFO'
    if census is not None and not (isinstance(census, float) and np.isnan(census)):
        if unit == '%':
            status = 'FAIL' if abs(sim - census) > PP_TOL else 'OK'
        else:
            denom = abs(census) if abs(census) > 1e-9 else 1e-9
            status = 'FAIL' if abs(sim - census) / denom > REL_TOL else 'OK'
    return {
        'category': category, 'metric': metric,
        'simulated': round(sim, 3) if sim is not None else None,
        'census': round(census, 3) if isinstance(census, (int, float)) and not np.isnan(census) else census,
        'unit': unit, 'status': status, 'note': note,
    }


# ---------------------------------------------------------------------------
# 4. Structural integrity checks (no census needed)
# ---------------------------------------------------------------------------

def structural_checks(d: dict) -> list[dict]:
    HH, IND, ASSETS, BUILD, WP = d['HH'], d['IND'], d['ASSETS'], d['BUILD'], d['WP']
    out = []

    dup_hh = HH['hh_id'].duplicated().sum()
    out.append(row('structural', 'duplicate HH IDs', dup_hh, 0, unit='count'))

    dup_ind = IND['ind_id'].duplicated().sum()
    out.append(row('structural', 'duplicate individual IDs', dup_ind, 0, unit='count'))

    orphan_hh = (~IND['hh_id'].isin(HH['hh_id'])).sum()
    out.append(row('structural', 'individuals with missing HH', orphan_hh, 0, unit='count'))

    orphan_bldg = (~HH['building_id'].isin(BUILD['bldg_id'])).sum()
    out.append(row('structural', 'HH assigned to unknown building', orphan_bldg, 0, unit='count'))

    # each housed HH's (building,asset) pair should match exactly one Assets row
    housed = HH.dropna(subset=['building_id', 'asset_id'])
    key_hh = set(zip(housed['building_id'], housed['asset_id']))
    key_assets = set(zip(ASSETS['building_id'], ASSETS['asset_id']))
    unmatched = len(key_hh - key_assets)
    out.append(row('structural', 'HH housing refs not found in Assets', unmatched, 0, unit='count'))

    dup_asset_assign = housed.duplicated(subset=['building_id', 'asset_id']).sum()
    out.append(row('structural', 'assets assigned to >1 HH', dup_asset_assign, 0, unit='count'))

    # working individuals should have a workplace ref (either real or the 99 local sentinel)
    workers = IND[IND['working_status'] == WORKING]
    missing_wp = workers['stat_wp'].isna().sum()
    out.append(row('structural', 'workers with no workplace assigned', missing_wp,
                    0, unit='count',
                    note='working_status==2 but stat_wp is NaN -> allocation shortfall'))

    neg_price = (ASSETS['price'] < 0).sum()
    out.append(row('structural', 'assets with negative price', neg_price, 0, unit='count'))

    over_capacity = (WP['occupied'] > WP['n_places']).sum()
    out.append(row('structural', 'workplace rows over capacity', over_capacity, 0, unit='count'))

    return out


# ---------------------------------------------------------------------------
# 5. Demographic checks vs census
# ---------------------------------------------------------------------------

def demographic_checks(d: dict, census: pd.DataFrame) -> list[dict]:
    HH, IND = d['HH'], d['IND']
    out = []

    # --- age shares: model has 3 buckets (kid/adult/old); census has 5 ---
    n = len(IND)
    kid_pct = 100 * (IND['age_group'] == KID).sum() / n
    adult_pct = 100 * (IND['age_group'] == ADULT).sum() / n
    old_pct = 100 * (IND['age_group'] == OLD).sum() / n

    pop_cols = ['demog_yishuv.age_0_14', 'demog_yishuv.age_15_19',
                'demog_yishuv.age_20_29', 'demog_yishuv.age_30_64',
                'demog_yishuv.age_65_up']
    census_pop = census[pop_cols].sum()
    total_pop = census_pop.sum()
    census_kid = 100 * (census_pop['demog_yishuv.age_0_14'] + census_pop['demog_yishuv.age_15_19']) / total_pop
    census_adult = 100 * (census_pop['demog_yishuv.age_20_29'] + census_pop['demog_yishuv.age_30_64']) / total_pop
    census_old = 100 * census_pop['demog_yishuv.age_65_up'] / total_pop

    out.append(row('demographics', 'kid share (age_group=1 vs age 0-19)', kid_pct, census_kid))
    out.append(row('demographics', 'adult share (age_group=2 vs age 20-64)', adult_pct, census_adult))
    out.append(row('demographics', 'elderly share (age_group=3 vs age 65+)', old_pct, census_old))

    # --- young-old (65-69) vs old-old (70+) split, among elderly ---
    # only present in files built after the age-split feature was added.
    if 'is_old_old' in IND.columns:
        pop_cols5 = pop_cols  # the 5 demog_yishuv.age_* count columns, reused
        total_pop_sa = census[pop_cols5].sum(axis=1)
        age_70up_count = (census['demog_yishuv.age_70_79_pcnt'] + census['demog_yishuv.age_80_pcnt']) / 100 * total_pop_sa
        # city-wide, population-weighted -- mirrors the per-SA math in create_HH_12_2018.m
        census_old_old_frac = 100 * age_70up_count.sum() / census['demog_yishuv.age_65_up'].sum()

        elderly = IND[IND['age_group'] == OLD]
        sim_old_old_frac = 100 * (elderly['is_old_old'] == 1).sum() / len(elderly) if len(elderly) else np.nan
        out.append(row('demographics', 'old-old (70+) share of elderly', sim_old_old_frac, census_old_old_frac))

    # --- household size distribution ---
    size_map = {1: 'households.size1_pcnt', 2: 'households.size2_pcnt',
                3: 'households.size3_pcnt', 4: 'households.size4_pcnt',
                5: 'households.size5_pcnt', 6: 'households.size6_pcnt'}
    sizes_capped = HH['individuals'].clip(upper=7)
    for k, col in size_map.items():
        sim_pct = 100 * (sizes_capped == k).sum() / len(HH)
        out.append(row('demographics', f'HH size {k} share', sim_pct, census[col].mean()))
    sim_pct = 100 * (sizes_capped >= 7).sum() / len(HH)
    out.append(row('demographics', 'HH size 7+ share', sim_pct, census['households.size7up_pcnt'].mean()))

    # --- households with children / elderly ---
    sim_child = 100 * (HH['children'] > 0).sum() / len(HH)
    out.append(row('demographics', 'HH with children share', sim_child,
                    census['households.hh0_17_pcnt'].mean()))

    sim_eld = 100 * (HH['n_old'] > 0).sum() / len(HH)
    out.append(row('demographics', 'HH with elderly (65+) share', sim_eld,
                    census['households.hh65_pcnt'].mean()))

    # --- disability rates (population-level, census reports %-with-disability) ---
    for col, census_col in [
        ('dis_hear', 'disabilities.hear5_pcnt'), ('dis_see', 'disabilities.see5_pcnt'),
        ('dis_reme', 'disabilities.remember5_pcnt'), ('dis_dress', 'disabilities.dress5_pcnt'),
        ('dis_walk', 'disabilities.walk5_pcnt'),
    ]:
        sim_pct = 100 * (IND[col] > 0).sum() / len(IND)
        out.append(row('demographics', f'{col} share', sim_pct, census[census_col].mean()))

    return out


# ---------------------------------------------------------------------------
# 6. Economic checks vs census
# ---------------------------------------------------------------------------

def income_checks(d: dict, census: pd.DataFrame) -> list[dict]:
    IND, HH = d['IND'], d['HH']
    out = []
    income_cols = {i: f'income.q{i}' for i in range(1, 11)}

    # Individual-level asiron is the fair comparison: labor_datasample.m
    # samples it directly from these same census income.q1-q10 shares
    # (Individuals_data col 13, values 1-10 by construction).
    labor_force = IND[IND['working_status'].isin([1, 2])]
    for decile, col in income_cols.items():
        sim_pct = 100 * (labor_force['asiron'] == decile).sum() / len(labor_force)
        out.append(row('income', f'individual income decile {decile} share', sim_pct, census[col].mean()))

    # HH_asiron (HH_data col 7) is NOT comparable to income.q1-q10 the same
    # way: it re-buckets summed multi-earner household income through the
    # same per-person bracket table (income2asiron.m), and uses an 11-row
    # table (data(i,1)-1 -> asiron 0-10) shared/intentional across all city
    # data_allocation folders (confirmed against b7ABM-matlab,
    # romansunedited). A multi-earner household will land in a higher
    # bucket than any single person in it purely from summation, so this
    # is reported for visibility only, not scored against the census.
    for asiron_val in range(0, 11):
        sim_pct = 100 * (HH['hh_asiron'] == asiron_val).sum() / len(HH)
        out.append(row('income', f'HH_asiron={asiron_val} share (info only, not census-comparable)',
                        sim_pct, None))
    return out


def car_checks(d: dict, census: pd.DataFrame) -> list[dict]:
    HH = d['HH']
    out = []
    sim_1up = 100 * (HH['n_cars'] >= 1).sum() / len(HH)
    sim_2up = 100 * (HH['n_cars'] >= 2).sum() / len(HH)
    out.append(row('cars', 'HH with >=1 car share', sim_1up,
                    census['durable_goods.Vehicle1up_pcnt'].mean()))
    out.append(row('cars', 'HH with >=2 cars share', sim_2up,
                    census['durable_goods.Vehicle2up_pcnt'].mean()))
    return out


# ---------------------------------------------------------------------------
# 7. Labor force & commuting checks vs census
# ---------------------------------------------------------------------------

def labor_commute_checks(d: dict, census: pd.DataFrame) -> list[dict]:
    IND = d['IND']
    out = []

    labor_pool = IND[IND['age_group'] >= ADULT]  # adults+elderly are the labor-eligible pool
    in_labor_force = labor_pool['working_status'].isin([WANTS_WORK, WORKING])
    sim_lfpr = 100 * in_labor_force.sum() / len(labor_pool)
    out.append(row('labor', 'labor force participation rate', sim_lfpr,
                    census['LaborForce.LaborForceY_pcnt'].mean()))

    lf = labor_pool[in_labor_force]
    sim_emp = 100 * (lf['working_status'] == WORKING).sum() / len(lf) if len(lf) else np.nan
    out.append(row('labor', 'employment rate (of labor force)', sim_emp,
                    census['LaborForce.Wrk2008Y_pcnt'].mean()))

    # commuting shares among those who actually got a job.
    # comm99 == tv_sa_data.csv's WrkOutLoc_pcnt (verified byte-for-byte per SA) --
    # i.e. comm99 is the share working OUTSIDE the tracked locality (untracked,
    # sentinel stat_wp==99), and comm31 (=1-comm99, derived in start_HH_2018up.m)
    # is the share working WITHIN it (assigned a real building_wp).
    workers = IND[IND['working_status'] == WORKING]
    n_w = len(workers)
    outside_locality = (workers['stat_wp'] == LOCAL_WORK_SENTINEL).sum()
    unassigned = workers['stat_wp'].isna().sum()
    within_locality = n_w - outside_locality - unassigned  # went to a real building_wp
    out.append(row('labor', 'commuters: outside-locality (comm99, untracked workplace) share',
                    100 * outside_locality / n_w if n_w else np.nan,
                    100 * census['comm99'].mean()))
    out.append(row('labor', 'commuters: within-locality (comm31, real workplace) share',
                    100 * within_locality / n_w if n_w else np.nan,
                    100 * (1 - census['comm99']).mean()))
    out.append(row('labor', 'workers with no workplace at all', unassigned, 0, unit='count',
                    note='allocation shortfall -- ran out of workplaces for this SA/metro zone'))

    # how many wanted-work individuals got downgraded from WORKING back to WANTS_WORK
    # inside distribute_workers.m (i.e. demand exceeded available workplaces)
    downgraded = (IND['working_status'] == WANTS_WORK).sum()
    out.append(row('labor', 'individuals wanting work but unemployed', downgraded, None,
                    unit='count', note='expected > 0; census unemployment isn\'t directly comparable here'))

    return out


# ---------------------------------------------------------------------------
# 8. Main
# ---------------------------------------------------------------------------

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('--mat', default=os.path.join(here, 'data_for_model_tmine.mat'))
    ap.add_argument('--census', default=os.path.join(here, '..', 'TVR', 'sa_data_b7.csv'))
    ap.add_argument('--out', default=os.path.join(here, 'allocation_validation_report.csv'))
    args = ap.parse_args()

    d = load_mat(args.mat)
    census = load_census(args.census)

    checks = []
    checks += structural_checks(d)
    checks += demographic_checks(d, census)
    checks += income_checks(d, census)
    checks += car_checks(d, census)
    checks += labor_commute_checks(d, census)

    report = pd.DataFrame(checks)
    pd.set_option('display.width', 160)
    pd.set_option('display.max_rows', None)
    for cat in report['category'].unique():
        print(f'\n=== {cat.upper()} ===')
        print(report[report['category'] == cat].drop(columns='category').to_string(index=False))

    report.to_csv(args.out, index=False)
    n_fail = (report['status'] == 'FAIL').sum()
    n_ok = (report['status'] == 'OK').sum()
    print(f'\n{n_fail} FAIL / {n_ok} OK / {len(report) - n_fail - n_ok} INFO out of {len(report)} checks.')
    print(f'Full report written to {args.out}')


if __name__ == '__main__':
    main()
