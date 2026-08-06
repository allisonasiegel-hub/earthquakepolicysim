function saved_path = run_earthquake_setting(wservice, wservice_old, eld_movef, svc_filter, scenario_tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen, new_jobs_rank_thresh, lost_jobs_rank_thresh, lu_change_rank_lower, lu_change_rank_upper, lu_jobs_per_meter, lu_potential_jobs_per_meter, init_dataset_name, commute_outside_rate, wage_alfa, wage_beta, wage_lamda, wage_delta)
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
% CONCURRENCY: FIXED (was a warning here for most of this project's
% history -- kept for context). The temp tag file and the intermediate
% output path run_model_earthquake.m itself writes were both fixed,
% non-unique paths, so two MATLAB processes calling this function
% concurrently would race on both files and silently cross-contaminate
% output (confirmed: one process's run got saved under the other's
% scenario_tag -- this bit us twice before it was tracked down). Both
% paths are now suffixed with run_uid (this process's OS PID, set
% below), so concurrent `matlab -batch` sweep jobs against this
% directory -- or parfor-based sweeps now that Parallel Computing
% Toolbox is installed -- are safe.
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
if nargin<11 || isempty(new_jobs_rank_thresh); new_jobs_rank_thresh=20; end
if nargin<12 || isempty(lost_jobs_rank_thresh); lost_jobs_rank_thresh=-60; end
if nargin<13 || isempty(lu_change_rank_lower); lu_change_rank_lower=40; end
if nargin<14 || isempty(lu_change_rank_upper); lu_change_rank_upper=60; end
if nargin<15 || isempty(lu_jobs_per_meter); lu_jobs_per_meter=0.008932703; end % Tiberias JobsPerM_comm
if nargin<16 || isempty(lu_potential_jobs_per_meter); lu_potential_jobs_per_meter=0.008932703; end % Tiberias JobsPerM_comm
if nargin<17 || isempty(init_dataset_name); init_dataset_name='data_for_model_tmine_agesplit70'; end
if nargin<18 || isempty(commute_outside_rate); commute_outside_rate=0.246; end % Tiberias zone-99 share
if nargin<19 || isempty(wage_alfa); wage_alfa=0.3; end
if nargin<20 || isempty(wage_beta); wage_beta=0.8; end
% wage_lamda default changed from 0.95 -> 0.55 -- see the matching
% comment in run_model_earthquake.m for the late-period OAT sweep that
% justified this (closest-to-flat post-freeze wage trend actually tested).
if nargin<21 || isempty(wage_lamda); wage_lamda=0.55; end
if nargin<22 || isempty(wage_delta); wage_delta=0.75; end

n_sims=1;

% CONCURRENCY FIX: run_uid uniquely identifies this MATLAB process (OS
% PID), so the temp tag file below AND run_model_earthquake.m's own
% intermediate output path (earthquakeF\<out_file_name> <kk> <run_uid>.mat)
% no longer collide when multiple sweep runs execute concurrently. Set
% explicitly here (rather than relying on run_model_earthquake.m's own
% default) so this function and the script it runs agree on the exact
% same value for building `src` below.
run_uid = sprintf('pid%d', feature('getpid'));
tmp_tag_file = sprintf('__run_earthquake_setting_tmp_%s.mat', run_uid);

% run_model_earthquake.m ends with a hardcoded "clearvars -except [...]"
% that wipes every variable in this function's workspace not on ITS list
% (run() shares this function's workspace) -- scenario_tag isn't on that
% list, so it would be gone by the time we get here. Stash it on disk
% instead, which survives regardless of what clearvars does to the
% workspace. The tag file itself is now PID-suffixed so two concurrent
% processes never share the same file.
save(tmp_tag_file, 'scenario_tag');

run('run_model_earthquake.m');

% tmp_tag_file itself doesn't survive run_model_earthquake.m's clearvars
% (only run_uid is on its keep-list) -- rebuild the same filename from
% run_uid, which does survive, rather than adding wrapper-only state to
% the script's keep-list.
tmp_tag_file = sprintf('__run_earthquake_setting_tmp_%s.mat', run_uid);
tmp = load(tmp_tag_file);
scenario_tag = tmp.scenario_tag;
delete(tmp_tag_file);

src = fullfile('earthquakeF', [char(out_file_name) ' ' num2str(kk) ' ' run_uid '.mat']);
dst = fullfile('earthquakeF', [char(out_file_name) ' ' num2str(kk) ' ' scenario_tag '.mat']);
copyfile(src, dst);
delete(src); % clean up the PID-tagged intermediate file now that it's copied to its final name
saved_path = dst;

fprintf('Saved: %s\n', dst);

end
