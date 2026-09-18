% Driver script: runs run_model_earthquake_shelteroverflow.m for Arad as a
% no-shock baseline, using data_for_model_Arad (see
% data_allocation/run_generate_arad.m for how that dataset was
% generated/calibrated to ~7% vacancy).
%
% Requested baseline: only override alfa/beta/lamda/delta (the
% wage-adjustment constants) from whatever this script's own untouched
% defaults are -- no land-use threshold tweaking (jobs_per_meter_multiplier,
% potential_jobs_per_meter_multiplier, lu_change_rank_lower/upper all stay
% at run_model_earthquake_shelteroverflow.m's own defaults, 1/1/20/40).
alfa = 0.30;
beta = 0.95;
lamda = 0.95;
delta = 0.50;

city = 'Arad';

% steps=150: matches Ashkelon/Tiberias/Beer Sheva's standard baseline run
% length (run_ashkelon_baseline_step25_150.m, run_tiberias_calibrated.m,
% run_beersheva_calibrated.m). No shock_step set here - stays a no-shock
% baseline by default (shock_step falls back to the script's own 900
% default, well past 150 steps).
if ~exist('steps','var'); steps=150; end
if ~exist('n_sims','var'); n_sims=5; end

run('run_model_earthquake_shelteroverflow.m')
