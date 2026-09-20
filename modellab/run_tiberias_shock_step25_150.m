% Shock driver: Tiberias, hotels dataset, staged sheltering design
% (outside_patience_duration=4 default, tempdev_patience_duration=8 --
% both the script's own defaults), aligned to Ashkelon's current setup
% (run_ashkelon_shock_step25_150.m, 2026-09-15):
%   - shock_step=25: verified Tiberias's land-use settles even faster
%     than Ashkelon's (~week 20-21) - SA_SERVICE (commercial building
%     count) flatlines from week 8 onward in a no-shock baseline, so 25
%     clears the transient with a comfortable margin.
%   - steps=150 (matches Ashkelon's shortened standard length)
% n_sims=1, run as its own process - mirrors Ashkelon's shock driver's
% same caution (this scenario type has an unexplained-crash history at
% n_sims>=2 in one process for Ashkelon; untested for Tiberias at this
% combination, so treated the same way here).
%
% (The old site-level temp_dev_duration force-close/transfer-to-overflow
% mechanic this used to disable via temp_dev_duration=Inf has been
% removed from the model entirely, 2026-09-15 -- tempdev_patience_duration
% is now the only temp-dev exit mechanism, so there's nothing left to
% disable.)
city = 'Tiberias';

% modelthesis's validated Tiberias land-use calibration (same as
% run_tiberias_calibrated.m):
jobs_per_meter_multiplier = 3;
potential_jobs_per_meter_multiplier = 2;
lu_change_rank_lower = 45;
lu_change_rank_upper = 85;

shock_step = 25;
steps = 150;
n_sims = 1;

run('run_model_earthquake_shelteroverflow.m')
