% Driver script: runs run_model_earthquake_shelteroverflow.m for Tiberias
% with modelthesis's validated land-use calibration, via the
% ~exist(...)-guarded override variables added to that script (see the
% "Land-use conversion calibration" block near its top) -- nothing in
% run_model_earthquake_shelteroverflow.m itself is hardcoded per-city for
% these three; pre-setting the variables here is the whole mechanism.
%
% To calibrate a different city, copy this file, change `city` below, and
% pick appropriate multiplier/threshold values for that city -- the
% defaults inside run_model_earthquake_shelteroverflow.m (1/1/20/40)
% reproduce the script's original, unmultiplied behavior if you omit
% these overrides entirely.
%
% NOTE: commute_outside for Tiberias in the city configuration block is
% still an unvalidated placeholder copied from Ashkelon (0.778038196) --
% modelthesis's validated value is 0.246. Not changed here since that
% wasn't part of this request; flagging again since it directly affects
% Tiberias run quality.

city = 'Tiberias';

% modelthesis's validated Tiberias land-use calibration:
jobs_per_meter_multiplier = 3;             % modelthesis: lu_jobs_per_meter = 3x base JobsPerM_comm
potential_jobs_per_meter_multiplier = 2;   % modelthesis: lu_potential_jobs_per_meter = 2x base JobsPerM_comm
lu_change_rank_lower = 45;                 % modelthesis: lu_change_rank_lower
lu_change_rank_upper = 85;                 % modelthesis: lu_change_rank_upper

% steps=150: matches Ashkelon's current standard run length
% (run_ashkelon_baseline_step25_150.m/run_ashkelon_shock_step25_150.m,
% 2026-09-15). No shock_step set here - stays a no-shock baseline by
% default (shock_step falls back to the script's own 900 default). For
% the shock scenario, use run_tiberias_shock_step25_150.m instead.
if ~exist('steps','var'); steps=150; end

run('run_model_earthquake_shelteroverflow.m')
