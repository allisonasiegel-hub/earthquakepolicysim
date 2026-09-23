% One-off diagnostic (chat 2026-09-19): capture destroyed_B and Work_places
% right after the Tiberias shock fires, before meaningful recovery has had
% a chance to happen (steps=shock_step+1 - only 1 step of recovery
% opportunity at RECOVERY~=0.72%/week, negligible), to check how many
% commercial buildings the shock destroys and how many workers they have -
% this is what subsidy_businesses_mode=1's eligibility rule (destroyed +
% >1 worker) filters on. See cal_bui_sa_subsidy_targeted.m.
%
% Not part of the subsidy sweep - subsidies left at their off defaults
% (mode 0/0) since this only needs the shock's own damage draw, not any
% subsidy behavior. Same Tiberias calibration/shock config as the sweep
% drivers for consistency.
city = 'Tiberias';
jobs_per_meter_multiplier = 3;
potential_jobs_per_meter_multiplier = 2;
lu_change_rank_lower = 45;
lu_change_rank_upper = 85;
shock_step = 25;
steps = 26;
n_sims = 1;
if ~exist('rng_seed','var'); rng_seed = 74110; end

run('run_model_earthquake_shelteroverflow.m')
