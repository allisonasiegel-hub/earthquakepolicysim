function res = run_sweep_setting(wservice, eld_movef, lu_update_every, steps, svc_filter)
% Runs nextchangesfortracker.m once with the given parameter values and
% returns the outcome metrics tagged with those values.
%
% Note: nextchangesfortracker.m's internal kk replicate loop is forced to a
% single iteration here (n_sims=1 below) - each kk overwrites the same
% variable names, so only the last kk's results are capturable and extra
% iterations are wasted compute. Independent replicates come from calling
% this function multiple times from the sweep driver. Standalone runs of
% the script (without n_sims pre-set) still default to 2 internal reps.
%
% IMPORTANT: nextchangesfortracker.m ends with a hardcoded
% "clearvars -except ..." that wipes every variable in this function's
% workspace not on that list (run() shares this function's workspace with
% the script). Only wservice, eld_movef, steps, Metric_Track, Metric_Change,
% and SA_Demographics survive that cleanup - anything else (including a
% struct built before run() finishes) gets deleted along with it. So res is
% built entirely AFTER run() returns, using only those surviving variables.

if nargin<3
    lu_update_every = 1;
end
if nargin<4
    steps = 200;
end
if nargin<5
    svc_filter = 0;
end

% Only the last kk replicate survives for capture below, so running the
% script's default 2 internal replicates doubles runtime for no benefit.
n_sims = 1;

run('nextchangesfortracker.m');

res.wservice = wservice;
res.eld_movef = eld_movef;
res.svc_filter = svc_filter;
res.steps = steps;
res.Metric_Track = Metric_Track;
res.Metric_Change = Metric_Change;
res.SA_Demographics = SA_Demographics;

end
