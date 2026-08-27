function saved_path = run_earthquake_setting(wservice, wservice_old, eld_movef, svc_filter, scenario_tag, steps, lu_update_every, lu_warmup, sa_update_every, resSearchLen, new_jobs_rank_thresh, lost_jobs_rank_thresh, lu_change_rank_lower, lu_change_rank_upper, lu_jobs_per_meter, lu_potential_jobs_per_meter, init_dataset_name, commute_outside_rate, wage_alfa, wage_beta, wage_lamda, wage_delta, elderly_search_mode, shock_step, eld_movef_old, displaced_shelter, use_staggered_relocation)
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
% shock_step (optional, default 900): the simulation day the earthquake
% triggers (one-time, via run_model_earthquake.m's `if i==shock_step &&
% shock==0` check). With steps <= shock_step (e.g. any of this file's
% default-900 760-day runs), the shock never fires and the run is a
% no-shock baseline regardless of the behavioral parameters. Pass a
% shock_step below `steps` to actually exercise the earthquake/subsidy/
% shelter logic -- requires TVR\earthquake_damage.csv (per-SA damage
% table) to exist, which it already does.
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
% eld_movef_old: same pattern, but for relocation-probability multiplier
% instead of service preference -- eld_movef applies to young-old,
% eld_movef_old to old-old, defaulting to eld_movef if not given.
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
% BUG FIX: lu_update_every/lu_warmup/sa_update_every previously defaulted
% to the original, untested values (3/4/30) -- every single run this
% session explicitly passed 1/30/1 instead (daily land-use updates
% starting day 30, daily macro updates), matching the actually-validated
% methodology. Same class of trap as the svc_filter bug: a bare call with
% too few args would silently fall back to untested cadence values. Locked
% in here so that can't happen again.
if nargin<7 || isempty(lu_update_every); lu_update_every=1; end
if nargin<8 || isempty(lu_warmup); lu_warmup=30; end
if nargin<9 || isempty(sa_update_every); sa_update_every=1; end
if nargin<10; resSearchLen=max(1,round(steps*30/760)); end
if nargin<11 || isempty(new_jobs_rank_thresh); new_jobs_rank_thresh=20; end
% lost_jobs_rank_thresh/lu_change_rank_lower/lu_change_rank_upper/
% lu_jobs_per_meter/lu_potential_jobs_per_meter defaults locked in
% together as a validated combo (band widened 60-80 -> 45-85, kept with
% the same threshold/jobs multipliers used in every band test this
% session -- these were never varied independently). 10-replicate 95%
% CI (default_ci_rep1-10, run against find_job_1.m's true original
% matching logic -- no candidate-shuffling, no job_search_breadth/
% job_threshold_skew_a, both fully removed) confirmed band 45-85 lets
% SA_JOBS (occupied-job share) reach a genuine, reproducible saturation
% point (1.0000 [1.0000,1.0000] by day 550, vs 60-80's 0.9480
% [0.9456,0.9504] still climbing) which lets mean wage actually plateau
% instead of drifting indefinitely (8796.7 [8767.3,8826.1] at day 550) --
% see the wage-taper investigation this session. Trade-off: population
% ends essentially flat at day 550 (17450.4 [17424.9,17475.9], vs the
% 60-80 band's continued growth to 17680 [17664,17697]), and workplace
% count overbuilds substantially (28220.5 [27729.6,28711.4] vs 60-80's
% ~21686). NOTE: an earlier round of this same CI (documented in prior
% commits) used find_job_1.m's job_search_breadth mechanism set to Inf,
% intended to be equivalent to "no cap" -- it wasn't quite: that code
% shuffled the candidate pool via randperm before matching (picking a
% random qualifying workplace on ties) where the true original (and
% current) code always picks the lowest-index qualifying workplace. That
% produced a real, non-overlapping-CI difference in outcomes (e.g. wage
% 8504.8 vs the correct 8796.7) -- the numbers above are the correct
% ones, from the actual current matching logic.
%
% ALTERNATIVE OPTION -- lu_jobs_per_meter=2.0x (0.017865406) instead of
% the locked-in 4.5x, band held at 45-85: from the jobs-per-meter
% isolation test (band fixed at 45-85, lu_potential_jobs_per_meter fixed
% at its own 2.0x value, only lu_jobs_per_meter varied), 2x reaches
% ~96% occupied-job share by day 550 (vs 4.5x's full saturation at
% 100%), with noticeably less workplace overbuild (SA_WP ~21850 vs
% ~27100) and a comparable population trajectory -- a reasonable, less
% job-oversupplied alternative to the 4.5x default if overbuild is a
% concern. Not the default; not separately CI-validated (single run
% only, see jpm_test_2x_band45_85.mat) -- flagged here as a noted,
% viable option, not a replacement.
if nargin<12 || isempty(lost_jobs_rank_thresh); lost_jobs_rank_thresh=-100; end
if nargin<13 || isempty(lu_change_rank_lower); lu_change_rank_lower=45; end
if nargin<14 || isempty(lu_change_rank_upper); lu_change_rank_upper=85; end
if nargin<15 || isempty(lu_jobs_per_meter); lu_jobs_per_meter=0.040197164; end % 4.5x Tiberias JobsPerM_comm, validated combo
if nargin<16 || isempty(lu_potential_jobs_per_meter); lu_potential_jobs_per_meter=0.017865406; end % 2.0x Tiberias JobsPerM_comm, validated combo
if nargin<17 || isempty(init_dataset_name); init_dataset_name='data_for_model_tmine_agesplit70'; end
if nargin<18 || isempty(commute_outside_rate); commute_outside_rate=0.246; end % Tiberias zone-99 share
if nargin<19 || isempty(wage_alfa); wage_alfa=0.3; end
if nargin<20 || isempty(wage_beta); wage_beta=0.8; end
% wage_lamda reverted to 0.95 (original default) per user request -- see
% the matching comment in run_model_earthquake.m for the late-period OAT
% sweep finding (0.55 was closest-to-flat post-freeze wage trend actually
% tested, 0.95 gives a small permanent late-period decline instead).
if nargin<21 || isempty(wage_lamda); wage_lamda=0.95; end
if nargin<22 || isempty(wage_delta); wage_delta=0.75; end
% FINALIZED METHODOLOGY: elderly_search_mode=2 -- see the matching
% comment in run_model_earthquake.m for the full rationale (largest,
% most significant SA-service-ratio gain of every mode tested, n=10,
% full 760-day average, p<1e-7 both groups vs baseline). eld_movef is
% NOT part of the finalized methodology -- every reduction tested
% delayed young-old's SA-service crossover point enough to break full-
% run significance; see run_model_earthquake.m for the detail.
if nargin<23 || isempty(elderly_search_mode); elderly_search_mode=2; end
if nargin<24 || isempty(shock_step); shock_step=900; end
% eld_movef_old: movement-probability multiplier for old-old (70+)
% specifically; eld_movef itself now applies to young-old (65-69).
% Defaults to eld_movef (no differentiation) if not given -- same
% pattern as wservice_old defaulting to wservice.
if nargin<25 || isempty(eld_movef_old); eld_movef_old=eld_movef; end
% displaced_shelter: 0=off (pure shock, no shelter intervention -- also
% removes the shelter-location service-ratio substitution in
% run_model_earthquake.m's Metric_Track block, so displaced households'
% service metrics reflect their actual home, not a shelter). 1=on
% (default, matches run_model_earthquake.m's own internal default).
if nargin<26 || isempty(displaced_shelter); displaced_shelter=1; end
% use_staggered_relocation: 0=off (original behavior -- every displaced
% household enters the housing search the same day as the shock), 1=on
% (default -- fast/slow mover Bernoulli mixture, calibrated against 2015
% Nepal earthquake IDP data; see run_model_earthquake.m's matching
% comment for full rationale and the caveat that this is a placeholder
% pending better, Tiberias/Israel-specific reference data).
if nargin<27 || isempty(use_staggered_relocation); use_staggered_relocation=1; end

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
