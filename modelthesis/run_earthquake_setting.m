function saved_path = run_earthquake_setting(wservice, wservice_old, eld_movef, svc_filter, scenario_tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen)
% Minimal-testing wrapper around run_model_earthquake.m, mirroring
% run_sweep_setting.m's existing pattern for nextchangesfortracker.m:
% pre-set fast-testing values (single replicate, short run, infrequent
% land-use updates) plus the three behavioral parameters, then run the
% real simulation script UNMODIFIED via run(). This avoids forking/
% duplicating the 1300+ line simulation file itself.
%
% run_model_earthquake.m's own output filename does NOT vary by
% wservice/eld_movef/svc_filter (only by shock-policy toggles like
% subsidy_residents/displaced_shelter) -- so with default settings, two
% different behavioral scenarios would silently overwrite the same file
% (earthquakeF\<data tag> EQ 1.mat). This wrapper copies the saved output
% to a scenario-tagged filename afterward so nothing gets clobbered.
%
% shock_step is hardcoded to 900 inside run_model_earthquake.m and can't
% be pre-set from here -- with steps well under that (default 90 below),
% the shock never triggers, so this is always a no-shock baseline run
% regardless of the behavioral parameters.
%
% sa_update_every controls how often the SA_* macro-economic block runs
% (default 30 = the model's original monthly cadence). This ISN'T just a
% recording resolution knob -- that block also updates real asset prices
% (Assets(:,5) via SA_LOGC) and building values, so lowering it changes
% simulation behavior, not just how many data points you get back.
%
% resSearchLen: max consecutive failed housing-search attempts before a HH
% actually leaves the city. Newly implemented in run_model_earthquake.m --
% previously unenforced anywhere in this codebase (households were
% deleted on their very first failed search), which was driving an ~85%
% population collapse over 30 steps. model_parameters.csv documents 30 as
% the value for a 760-step run, so the default here scales proportionally
% to whatever `steps` this call actually uses, matching
% run_model_earthquake.m's own default -- pass it explicitly to override.
%
% wservice_old: service-preference weight specifically for old-old (70+)
% households (HH_data col 12 >= 1); wservice itself now applies to
% young-old (65-69) and non-elderly-adjacent baseline. Defaults to
% wservice (no differentiation) if not given.
%
% NOTE signature changed from earlier sessions: wservice_old is now the
% 2nd argument, shifting every positional arg after it by one.
%
% Usage:
%   run_earthquake_setting(0, 0, 1, 0, 'baseline')
%   run_earthquake_setting(0.25, 0.25, 1, 1, 'both_elderly_same')
%   run_earthquake_setting(0.25, 1, 1, 1, 'old_old_stronger', 100, 3, 4, 5, 30)

if nargin<2 || isempty(wservice_old); wservice_old=wservice; end
if nargin<6; steps=100; end
if nargin<7; lu_update_every=3; end
if nargin<8; lu_warmup=4; end
if nargin<9; sa_update_every=30; end
if nargin<10; resSearchLen=max(1,round(steps*30/760)); end

n_sims=1;

% run_model_earthquake.m ends with a hardcoded "clearvars -except [...]"
% that wipes every variable in this function's workspace not on ITS list
% (run() shares this function's workspace) -- scenario_tag isn't on that
% list, so it would be gone by the time we get here. Stash it on disk
% instead, which survives regardless of what clearvars does to the
% workspace.
save('__run_earthquake_setting_tmp.mat', 'scenario_tag');

run('run_model_earthquake.m');

tmp = load('__run_earthquake_setting_tmp.mat');
scenario_tag = tmp.scenario_tag;
delete('__run_earthquake_setting_tmp.mat');

src = fullfile('earthquakeF', [char(out_file_name) ' ' num2str(kk) '.mat']);
dst = fullfile('earthquakeF', [char(out_file_name) ' ' num2str(kk) ' ' scenario_tag '.mat']);
copyfile(src, dst);
saved_path = dst;

fprintf('Saved: %s\n', dst);

end
