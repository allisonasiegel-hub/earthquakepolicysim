% Driver script: runs run_model_earthquake_shelteroverflow.m for Jerusalem
% with the "quick win" calibration values filled in (commute_outside,
% alfa/beta/lamda/delta - see the city configuration block's Jerusalem
% case for sourcing/caveats). Land-use conversion calibration
% (jobs_per_meter_multiplier/potential_jobs_per_meter_multiplier/
% lu_change_rank_lower/upper) is left at the script's unmultiplied
% defaults (1/1/20/40) - no Jerusalem-specific reference growth/shape data
% exists yet to tune those against (see run_tiberias_calibrated.m for the
% pattern once that data is available).
%
% steps/n_sims below are set short deliberately for fast smoke-test runs
% while iterating on calibration - bump both up for a real/final run.

city = 'Jerusalem';
steps = 60;   % ~1 year of weekly steps - smoke-test length, not a full run
n_sims = 1;   % single replicate - smoke-test speed, not statistically robust

run('run_model_earthquake_shelteroverflow.m')
