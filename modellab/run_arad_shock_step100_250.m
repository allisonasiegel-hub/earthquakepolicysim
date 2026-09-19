% Shock driver: Arad, plain dataset (no hotel-tagged variant exists),
% staged sheltering design. Companion to run_arad_baseline.m for a
% matched baseline-vs-shock comparison pair.
%   - shock_step=100, steps=250: even later/longer than
%     run_arad_shock_step40_150.m's shock_step=40 - gives a long,
%     well-established pre-shock baseline (Arad's land-use module settles
%     by ~week 16-20 with both Arad fixes applied - find_empty_buildings_arad.m
%     and the intraSAProb/intraYeshuvProb correction) and a long post-shock
%     recovery window (150 steps) to see the full trajectory play out,
%     not just the initial displacement/sheltering wave.
%   - outside_patience_duration=4, tempdev_patience_duration=8: both
%     already the script's own defaults - set explicitly here anyway so
%     this driver's behavior can't silently drift if those defaults ever
%     change later. Same convention as the Ashkelon/Tiberias shock drivers.
%   - No jobs_per_meter_multiplier/lu_change_rank overrides: unlike
%     Tiberias/Ashkelon, there's no modelthesis-validated land-use
%     calibration for Arad - left at the script's own untouched defaults
%     (1/1/20/40), matching run_arad_baseline.m's "unchanged parameters"
%     baseline philosophy.
%   - alfa/beta/lamda/delta: same requested baseline values as
%     run_arad_baseline.m (0.30/0.95/0.95/0.50) - not shock-specific,
%     just keeping the scenarios comparable.
%
% n_sims=1, run as its own process: this exact scenario type has an
% unexplained-crash history at n_sims>=2 in one process for
% Ashkelon/Tiberias - untested for Arad at this combination, treated the
% same way here out of caution. Run this file multiple times in SEPARATE
% sequential `matlab -batch` invocations (never concurrently) to build up
% a batch of replicates, the same way as the baseline driver.
alfa = 0.30;
beta = 0.95;
lamda = 0.95;
delta = 0.50;

city = 'Arad';
shock_step = 100;
steps = 250;
n_sims = 1;
outside_patience_duration = 4;
tempdev_patience_duration = 8;

run('run_model_earthquake_shelteroverflow.m')
