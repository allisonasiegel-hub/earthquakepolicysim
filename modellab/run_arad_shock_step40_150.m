% Shock driver: Arad, plain dataset (no hotel-tagged variant exists),
% staged sheltering design. Companion to run_arad_baseline.m for a
% matched baseline-vs-shock comparison pair.
%   - shock_step=40, steps=150: LATER than Ashkelon/Tiberias's usual
%     shock_step=25 convention (run_ashkelon_shock_step25_150.m,
%     run_tiberias_shock_step25_150.m). Arad's own land-use module
%     produces a sharp one-time dip around week 12 (9700ish -> ~8400,
%     with both Arad fixes applied - find_empty_buildings_arad.m and the
%     intraSAProb/intraYeshuvProb correction) before settling into smooth,
%     steady growth from ~week 16 onward. shock_step=25 already clears
%     the dip itself but only gives ~13 weeks of recovery; shock_step=40
%     gives a full ~28 weeks of clean, established growth (no more
%     one-time jumps) before the shock hits, for a cleaner separation
%     between the land-use transient and the shock's own effects.
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
%     just keeping the two scenarios comparable.
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
shock_step = 40;
steps = 150;
n_sims = 1;
outside_patience_duration = 4;
tempdev_patience_duration = 8;

run('run_model_earthquake_shelteroverflow.m')
