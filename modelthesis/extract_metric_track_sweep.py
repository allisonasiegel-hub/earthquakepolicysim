"""
extract_metric_track_sweep.py
===============================
Extracts the same results_long summary structure run_sensitivity_sweep.m
builds (PopPctChange_E/NE, SAServiceAvg/Delta_E/NE, etc.) directly from a
set of already-completed run_earthquake_setting.m output .mat files --
no need to re-run MATLAB, since Metric_Track/Metric_Change are already
saved in each file.

Usage: python extract_metric_track_sweep.py "earthquakeF/agesplit70 EQ S 1 wsold*_rep*.mat" wservice_old wsold --out sensitivity_sweep_results_wsold.csv
  arg1: glob pattern for the run files
  arg2: name of the swept parameter (must match a variable saved in each .mat, e.g. wservice_old)
  arg3: filename tag regex prefix to pull replicate number from (looks for '_rep(\\d+)')
"""
import sys
import glob
import re
import numpy as np
import pandas as pd
import scipy.io as sio


def endpoint_delta(track_col):
    v = np.asarray(track_col, dtype=float)
    idx = np.where(~np.isnan(v))[0]
    if len(idx) == 0:
        return np.nan
    return v[idx[-1]] - v[idx[0]]


def extract_row(mat_path, param_name):
    m = sio.loadmat(mat_path, variable_names=['Metric_Track', param_name, 'wservice', 'eld_movef', 'svc_filter'],
                     simplify_cells=True)
    mt = m['Metric_Track']
    param_val = m[param_name]

    pop_init_e, pop_init_ne = mt[0, 5], mt[0, 6]
    pop_change_e = endpoint_delta(mt[:, 5])
    pop_change_ne = endpoint_delta(mt[:, 6])
    pop_pct_e = 100 * pop_change_e / pop_init_e if pop_init_e > 0 else np.nan
    pop_pct_ne = 100 * pop_change_ne / pop_init_ne if pop_init_ne > 0 else np.nan

    row = {
        'ParamVaried': param_name, param_name: param_val,
        'wservice': m.get('wservice'), 'eld_movef': m.get('eld_movef'), 'svc_filter': m.get('svc_filter'),
        'PopChange_E': pop_change_e, 'PopChange_NE': pop_change_ne,
        'PopPctChange_E': pop_pct_e, 'PopPctChange_NE': pop_pct_ne,
        'SAServiceAvg_E': np.nanmean(mt[:, 1]), 'SAServiceAvg_NE': np.nanmean(mt[:, 2]),
        'SAServiceDelta_E': endpoint_delta(mt[:, 1]), 'SAServiceDelta_NE': endpoint_delta(mt[:, 2]),
        'BldServiceAvg_E': np.nanmean(mt[:, 3]), 'BldServiceAvg_NE': np.nanmean(mt[:, 4]),
        'BldServiceDelta_E': endpoint_delta(mt[:, 3]), 'BldServiceDelta_NE': endpoint_delta(mt[:, 4]),
        'NormAssetsCity_Avg_E': np.nanmean(mt[:, 13]), 'NormAssetsCity_Avg_NE': np.nanmean(mt[:, 14]),
        'NormAssetsCity_Delta_E': endpoint_delta(mt[:, 13]), 'NormAssetsCity_Delta_NE': endpoint_delta(mt[:, 14]),
        'NormAssetsSA_Avg_E': np.nanmean(mt[:, 9]), 'NormAssetsSA_Avg_NE': np.nanmean(mt[:, 10]),
        'NormAssetsSA_Delta_E': endpoint_delta(mt[:, 9]), 'NormAssetsSA_Delta_NE': endpoint_delta(mt[:, 10]),
        'AttemptSA_Avg_E': np.nanmean(mt[:, 15]), 'AttemptSA_Avg_NE': np.nanmean(mt[:, 16]),
        'AttemptSA_Delta_E': endpoint_delta(mt[:, 15]), 'AttemptSA_Delta_NE': endpoint_delta(mt[:, 16]),
        'AttemptCity_Avg_E': np.nanmean(mt[:, 17]), 'AttemptCity_Avg_NE': np.nanmean(mt[:, 18]),
        'AttemptCity_Delta_E': endpoint_delta(mt[:, 17]), 'AttemptCity_Delta_NE': endpoint_delta(mt[:, 18]),
        'SuccessSA_Avg_E': np.nanmean(mt[:, 19]), 'SuccessSA_Avg_NE': np.nanmean(mt[:, 20]),
        'SuccessSA_Delta_E': endpoint_delta(mt[:, 19]), 'SuccessSA_Delta_NE': endpoint_delta(mt[:, 20]),
        'SuccessCity_Avg_E': np.nanmean(mt[:, 21]), 'SuccessCity_Avg_NE': np.nanmean(mt[:, 22]),
        'SuccessCity_Delta_E': endpoint_delta(mt[:, 21]), 'SuccessCity_Delta_NE': endpoint_delta(mt[:, 22]),
    }
    return row


def main():
    file_pattern = sys.argv[1]
    param_name = sys.argv[2]
    rep_pattern = re.compile(r'_rep(\d+)')
    out_path = 'sensitivity_sweep_results_' + param_name + '.csv'
    if '--out' in sys.argv:
        out_path = sys.argv[sys.argv.index('--out') + 1]

    files = glob.glob(file_pattern)
    rows = []
    for f in files:
        m = rep_pattern.search(f)
        rep = int(m.group(1)) if m else 1
        row = extract_row(f, param_name)
        row['Replicate'] = rep
        rows.append(row)

    df = pd.DataFrame(rows).sort_values([param_name, 'Replicate'])
    df.to_csv(out_path, index=False)
    print(f'[done] {len(df)} rows -> {out_path}')
    print(df[['ParamVaried', param_name, 'Replicate', 'PopPctChange_E', 'PopPctChange_NE',
              'SAServiceAvg_E', 'SAServiceAvg_NE']].to_string(index=False))


if __name__ == '__main__':
    main()
