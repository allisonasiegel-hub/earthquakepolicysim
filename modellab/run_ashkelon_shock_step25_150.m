% Shock driver: Ashkelon, hotels dataset, staged sheltering design.
% Companion to run_ashkelon_baseline_step25_150.m for a matched
% baseline-vs-shock comparison pair. See the README's "Validated shock
% scenario configuration" and "Decreasing patience -> permanent
% departure" sections for the full reasoning behind these choices;
% summary:
%   - shock_step=25, steps=150: shock_step clears the land-use module's
%     one-time initial-activation transient (settles by ~week 20-21 for
%     Ashkelon) before the shock hits, so the two effects don't confound.
%   - outside_patience_duration=4, tempdev_patience_duration=8: both
%     already the script's own defaults as of 2026-09-15 -- set
%     explicitly here anyway so this driver's behavior can't silently
%     drift if those defaults ever change later. (The old site-level
%     temp_dev_duration force-close/transfer-to-overflow mechanic these
%     used to disable via temp_dev_duration=Inf has been removed from the
%     model entirely, 2026-09-15 -- tempdev_patience_duration is now the
%     only temp-dev exit mechanism, so there's nothing left to disable.)
%
% n_sims=1, run as its own process: this exact scenario type has an
% unexplained-crash history at n_sims>=2 in one process. Run this file
% multiple times in SEPARATE sequential `matlab -batch` invocations
% (never concurrently -- that has its own separate crash history) to
% build up a batch of replicates, the same way as the baseline driver.

city = 'Ashkelon';
shock_step = 25;
steps = 150;
n_sims = 1;
outside_patience_duration = 4;
tempdev_patience_duration = 8;

run('run_model_earthquake_shelteroverflow.m')
