
%edits include removing commercial submodel, reducing runs, adding in a HH
%move tracker, integrating the new land use change policies
%now i will edit for the metrics
% update tracking for costs of housing, moving, etc
%MOST RECENT PLEASE KEEP WORKING ON THIS
%TODAY IS JUly 27 2026
%
% FORK for shock-policy development (subsidy + shelter), branched from
% nextchangesfortracker.m. Everything here is gated by subsidy_residents
% and displaced_shelter (both toggleable below) and by shock actually
% triggering (shock_step within the run's step range) - with either
% toggle off, or in a no-shock baseline run, this fork behaves exactly
% like the original script. The original nextchangesfortracker.m is left
% untouched so baseline/sensitivity-sweep work is unaffected.
%
% EARTHQUAKE VARIANT (this file): forked again from
% nextchangesfortracker_shockpolicies.m, with ONLY the shock-delivery
% mechanism swapped - the iterative rocket_attack2 wave loop is replaced
% by the one-time earth_quake() trigger (same pattern as the original
% run_model_eq.m). Everything downstream (subsidy_pct, assign_shelter_sa,
% the sheltered-household retry/exemption loop, release_shelter_capped,
% metric tracking, wservice/eld_movef/svc_filter) is untouched - it all
% reads HH_destroyed/shock/Shelters generically and doesn't care which
% function populated them.
%
% REQUIRES a per-SA damage table at [file,'earthquake_damage.csv']
% (columns SAID, dmg_prc - see earth_quake.m for accepted formats). That
% file is NOT included in this repo yet; earth_quake.m will throw a clear
% error if it's missing. Drop the real damage assessment in before running.
%
% NOTE: shock_step defaults to 900 (inherited below), same as the
% original script. With the default steps=200 (or whatever a sweep
% driver sets), the shock never actually triggers. To exercise the
% earthquake/subsidy/shelter logic in this file, set shock_step (and
% steps) so the shock actually happens within the run, e.g.
% shock_step=40, steps=200.


tic
% n_sims: outer replicate count. Only the LAST kk's outputs survive for a
% sweep caller (run_sweep_setting captures post-clearvars state), so sweep
% drivers set n_sims=1 to avoid paying for a discarded first replicate.
% Standalone runs keep the original default of 2.
if ~exist('n_sims','var'); n_sims=2; end
sims=n_sims;
% CONCURRENCY FIX: run_uid uniquely identifies THIS MATLAB process, so
% that when multiple sweep runs execute concurrently (now safe with
% Parallel Computing Toolbox installed), their intermediate output files
% (earthquakeF\<out_file_name> <kk> <run_uid>.mat) and
% run_earthquake_setting.m's temp tag file don't collide with each
% other. Defaults to the OS process ID (unique across concurrently
% running processes); run_earthquake_setting.m sets this explicitly
% before calling run() so both sides agree on the same value.
if ~exist('run_uid','var'); run_uid=sprintf('pid%d', feature('getpid')); end
for kk = 1:sims
        %kk;kk
if ~exist('init_dataset_name','var'); init_dataset_name='data_for_model_tmine_agesplit70'; end
data=init_dataset_name; data2 = split(data, '_');
file='C:\Users\allis\Documents\MATLAB\modelthesis\'; % load and define
% BUG FIX: the original run_model_eq.m loads JobsPerM_comm dynamically
% from [file,'model parameters.csv'] at the top of the script, so it's
% automatically correct for whatever city's data is loaded. That got lost
% at some point -- run_model_earthquake.m had it hardcoded as a literal
% (0.007790361, Ashkelon's value) in two places in the land-use module.
% Restored here; lu_jobs_per_meter/lu_potential_jobs_per_meter can still
% be overridden explicitly for testing (see their ~exist guards below),
% but now default to the dynamically-loaded, city-correct value.
[~,~,models_par_tmp]=xlsread([file,'TVR\model parameters.csv']);
JobsPerM_comm_loaded=models_par_tmp{strcmp(models_par_tmp(:,1),'JobsPerM_comm'), 2};
clearvars models_par_tmp
load(data);
% resSearchLen retry mechanism: col 13 tracks each HH's consecutive failed
% housing-search attempts. Was never actually wired in anywhere in this
% codebase (confirmed back to the original run_model_eq.m baseline) --
% did_not_find_house.m deleted a household on its very first failed
% search, with zero retry tolerance, which is what was driving the ~85%
% population collapse over 30 steps. col 13 is a fresh append (HH_data
% has no existing col 13+ usage anywhere in this script).
HH_data(:,13)=0;
% BUG FIX: root-level sas_national.xlsx is the full national file and is
% missing SA 67000037 entirely (confirmed: 16/16 Tiberias SAs present in
% TVR\sas_national.xlsx vs 15/16 at root) -- causes who_is_moving.m to
% crash on an empty intra_SA_data slice for that SA. Use the TVR-specific,
% pre-filtered copy instead, which has all of them.
[sas_data,intra_SA,intra_P]=read_sas_data([file,'TVR\'],'sas_national.xlsx'); %SA data
unique_stat=unique(Build_Data(:,4));
intra_SA=intra_SA(ismember(intra_SA(:,1),unique_stat),:);

% Real per-SA annual population growth rates from actual Tiberias census
% data (TVR/real_growth_rates.csv, derived from TVR/growthrates1.xlsx),
% used by migration_19.m in place of the misused inOutRatio column --
% see the BUG FIX note in migration_19.m for the full explanation.
real_growth_rate=readmatrix([file,'TVR\real_growth_rates.csv']);
random_number=rand(size(HH_data,1)*4,1);
comm_policy=0;
min_sal = 5000; % min salary according to BTL in 2017
sims=2;
if ~exist('steps','var'); steps=100; end % allow a sweep driver to pre-set this for faster test runs
% (hits_ratio/total_hits removed - those were rocket_attack2's iterative
% wave-count controls; earthquake severity comes from the per-SA damage
% table passed to earth_quake() instead, see the shock block below)
shock=0;
if ~exist('shock_step','var'); shock_step=900; end % allow a sweep driver to pre-set this to actually trigger the shock
% RECOVERY: daily per-building probability of recovering from earthquake
% damage. Ported from modellab/run_model_earthquake_shelteroverflow.m
% (git history, commit e2ed492 -- that path no longer exists in the
% current tree but the commit is still reachable), rescaled from that
% script's weekly step to this script's daily step: real reconstruction-
% timeline data shows 31.35% of residential housing recovers within 1
% year, so solving 1-(1-p)^365=0.3135 for p gives the daily-equivalent
% probability below (modellab solved 1-(1-p)^52=0.3135 since its loop
% steps in weeks). Each still-destroyed building gets an independent
% Bernoulli draw every day, memoryless -- replaces the old deterministic
% shared-countdown mechanism, where every destroyed building recovered
% at exactly the same step count regardless of size (size canceled out
% of the old threshold formula), producing a step function rather than a
% curve. Applied uniformly to all building types by default; the
% priority_recovery/recovery_factor toggle below still works for a
% residential recovery bonus.
RECOVERY = 1 - (1-0.3135)^(1/365);
%% Polocies
subsidy_businesses=0; % help business during
subsidy_residents=0; % toggle: 0=off (baseline), 1=on
% subsidy_pct: base fraction of a displaced HH's income (frozen at grant
% step) given as a housing subsidy. w_subsidy_eld: elderly premium weight
% - elderly HH get subsidy_pct*(1+w_subsidy_eld) instead of subsidy_pct.
% Both placeholders pending sensitivity testing (same approach as
% wservice/eld_movef/svc_filter).
subsidy_pct=0.15;
w_subsidy_eld=0.5;
subsidy_duration=60;
priority_recovery=0; % faster recovery of residential
recovery_factor=2.5;
% toggle: 0=off (pure shock, no shelter intervention), 1=on (shelter
% policy of public turn to 99). Settable from run_earthquake_setting.m
% (guard added so a sweep/test driver can pre-set this before run()).
if ~exist('displaced_shelter','var'); displaced_shelter=1; end
agents_per_sqm=0.2;
% max_shelter_duration: hard cap (steps) on how long a household may stay
% sheltered before being forced to relocate-or-leave. Placeholder value -
% not yet set through sensitivity testing.
max_shelter_duration=120;

% Staggered relocation eligibility: previously, every displaced household
% entered the SAME-DAY housing search (moving_HH) on the exact shock day
% -- unrealistic, since finding/touring/arranging a new home takes real
% time even when a qualifying unit exists (confirmed empirically: ~85-90%
% of displaced households were matching same-day). Real disaster-
% displacement data doesn't follow a single constant daily "resolve"
% rate either -- it shows a fast-resolving majority plus a much slower
% "chronically displaced" minority (a well-documented pattern in the
% literature, not unique to one event). Modeled here as a two-population
% Bernoulli mixture: each displaced household is assigned (once, at the
% moment of displacement) to a "fast" or "slow" mover population, then
% draws daily against that population's fixed probability until it
% succeeds, at which point it enters the normal moving_HH search pipeline
% exactly as before (this only delays WHEN a household starts searching,
% not how the search itself works). Calibrated via least-squares fit
% (exact fit, 3 params/3 points) to the 2015 Nepal earthquake IDP
% displacement-duration data (Nepal was the only quantitative source
% found in this session -- >35% still displaced at 2wk, 13-33% at 5-6wk,
% 7-15% at 13wk; the true model-relevant target is Tiberias/Israel-
% specific data, not yet found -- treat this as a placeholder pending
% better data, not a validated calibration).
% use_staggered_relocation: 0=off (original behavior -- every displaced
% household enters moving_HH the same day, HH_destroyed feeds it
% directly), 1=on (fast/slow Bernoulli mixture above). Toggle so the two
% can be run and compared directly rather than one replacing the other.
if ~exist('use_staggered_relocation','var'); use_staggered_relocation=1; end
if ~exist('relocation_w_slow','var'); relocation_w_slow=0.3947; end % fraction of displaced HH that are 'slow' movers
if ~exist('relocation_p_slow','var'); relocation_p_slow=0.01394; end % daily eligibility probability, slow movers
if ~exist('relocation_p_fast','var'); relocation_p_fast=0.20199; end % daily eligibility probability, fast movers
if ~exist('pending_relocation','var'); pending_relocation=zeros(0,2); end % [HH_ID, is_slow]
commercial_preservation=0;
residential_preservation=0;

comm_damaged_prob=0.8;
comm_undamaged_prob=0.1;

res_damaged_prob=0.7;
res_undamaged_prob=0.0;


%% filename by policy
policy_tags = {};
if subsidy_residents
    policy_tags{end+1} = 'R';
end
if subsidy_businesses
    policy_tags{end+1} = 'B';
end
if priority_recovery
    policy_tags{end+1} = 'P';
end
if displaced_shelter
    policy_tags{end+1} = 'S';
end

if commercial_preservation
    policy_tags{end+1} = 'CP';
end

if residential_preservation
    policy_tags{end+1} = 'RP';
end

if isempty(policy_tags)
    suffix = '';
else
    suffix = [' ' strjoin(policy_tags)];
end



out_file_name = strcat(data2{end}, {' EQ'}, suffix);


%% model parameters
acts=3;
wactsnum=3;
wact1=0.5;
wact2=0.5;
Pa=12;
wresd=0.5;
w_dis_job=0.5;
if ~exist('wservice','var'); wservice=0; end % allow a sweep driver to pre-set this
if ~exist('wservice_old','var'); wservice_old=wservice; end % service-preference weight for old-old (70+) HH specifically; defaults to the same value as wservice (young-old) so this is a no-op unless explicitly set higher

% FINALIZED METHODOLOGY (locked in after the elderly_search_mode 1-6 +
% eld_movef sensitivity testing): elderly_search_mode=2 (SA-level hard
% filter + weighted SA pick for out-of-SA moves) produced the largest,
% most statistically significant SA-service-ratio gain for BOTH young-
% old and old-old of every mode tested (n=10 replicates, p<1e-7 both
% groups vs baseline over the full 760-day average). eld_movef was
% tested layered on top (0.33/0.5, 0.5/0.75, 0.6/0.8, 0.75/0.9) but
% every reduction tested delayed young-old's SA-service crossover point
% enough to drag the full-run average back to non-significance (young-
% old starts BELOW non-elderly at t=0 and only crosses above around day
% 120-180 in plain mode 2 -- any movement-probability reduction pushes
% that crossover later, eating into more of the 760-day average).
% eld_movef is therefore NOT part of the finalized methodology --
% defaults left at 1 (no-op) below. Override explicitly if testing an
% eld_movef combination for comparison.
if ~exist('eld_movef','var'); eld_movef=1; end % movement-probability multiplier for young-old (65-69)
if ~exist('eld_movef_old','var'); eld_movef_old=1; end % movement-probability multiplier for old-old (70+)
if ~exist('svc_filter','var'); svc_filter=1; end % building service ratio filter for within-SA elderly pool (0=off, 1=on) -- mode 2's within-SA hard floor
% elderly_search_mode: 0=off/legacy, 1=svc_filter's building-level filter
% extended to out-of-SA pools too + weighted asset pick, 2=SA-level
% filter (replaces the wservice/SA_score_old threshold) + weighted SA
% pick for out-of-SA, 3=no filters anywhere, weighted SA pick (among
% wservice/SA_score_old-eligible SAs) + weighted asset pick. See
% find_new_house_sa_score.m's header for full definitions. Old-old leans
% harder toward higher-service options than young-old in every weighted
% pick (service_ratio^2 vs ^1).
if ~exist('elderly_search_mode','var'); elderly_search_mode=2; end
% BUG FIX: svc_filter=1 is mode 2/6's within-SA hard floor (see comment
% above and find_new_house_sa_score.m's header) -- not an independent
% toggle a caller can leave at 0 without silently breaking the finalized
% mode-2/6 methodology. Every run_earthquake_setting.m call this session
% explicitly passed svc_filter=0 (its 4th positional arg has no default,
% so it always exists once passed, meaning the ~exist guard above never
% caught this), so every elderly_search_mode=2 earthquake run so far was
% missing its within-SA component. Enforced here unconditionally so this
% can't be silently misconfigured again from any call site.
if (elderly_search_mode==2 || elderly_search_mode==6) && svc_filter~=1
    svc_filter=1;
end
if ~exist('sa_update_every','var'); sa_update_every=30; end % cadence (steps) for the SA_* macro-economic update block (price/wage/etc.) -- 30 = original monthly cadence; allow a sweep/testing driver to pre-set this
% resSearchLen: max consecutive failed housing-search attempts before a HH
% actually leaves the city (see HH_data col 13, set at load time above).
% model_parameters.csv documents 30 as the value for a 760-step run, so
% scale it proportionally to whatever `steps` this run actually uses
% (min 1, so a short test run can't silently disable the retry budget
% entirely by rounding down to 0).
if ~exist('resSearchLen','var'); resSearchLen=max(1,round(steps*30/760)); end


first_column = Build_Data(:, 1);
unique_values = unique(first_column);
unique_matrix = [];
for i = 1:length(unique_values)
    indices = find(first_column == unique_values(i));
    unique_matrix = [unique_matrix; Build_Data(indices(1), :)];
end
Build_Data=unique_matrix;					 

%% near buildings
% RADIUS EXPERIMENT (service-radius-test branch): TRUE CONTROL - original,
% unmodified radii (250/400), otherwise identical settings/rng-seeding to
% the radius300/radius500 runs (svc_filter=1, elderly_search_mode=2,
% corrected sa_update_every=1 defaults) so it isolates the radius change
% alone, unlike baseline_full3way (which differs in elderly_search_mode
% and land-use band too).
Build_Distance_matrix_250=building_within_D(Build_Data,250);
Build_Distance_matrix_400=building_within_D(Build_Data,400);

pd = makedist('Normal'); % normal distribution ; used for simulation of HH moving
%% prepearing the world:
% sign empty buildings
[Build_Data,Build_Data_p]=find_empty_buildings(Assets,Build_Data,Build_Data_p);

%% building service ratio -
% this function calculate the service ratio for each building
[Build_Data,Build_Data_p]=building_service_ratio(Build_Data,Build_Data_p,Build_Distance_matrix_400);
%% calculate building score - atractivnes
[Build_Data,Build_Data_p]=building_score(Build_Data,Build_Data_p,Assets,wact1,wact2,Build_Distance_matrix_250);
%% building size
FLOORSPACE = [];
for hhhh = 1:size(Build_Data,1)
    floorsize=sum(Assets(Assets(:,2)==Build_Data(hhhh,1),4));
    if floorsize == 0
        floorsize=Build_Data(hhhh,7)*ceil(Build_Data(hhhh,11));
    end
    Build_Data(hhhh,25)=floorsize;
end
%% building service density (land-area, reporting-only) -- needs col(25)
% floorspace, so this must run after the loop above, not alongside
% building_service_ratio.m at line 271 (which runs before floorspace
% exists). See building_service_density.m's header for full rationale.
[Build_Data,Build_Data_p]=building_service_density(Build_Data,Build_Data_p,Build_Distance_matrix_400,400);
Assets = mean_price_per_meter(Assets);

%% stat service data
[stat_data,stat_data_P]=stat_service(Build_Data,Individuals_data,HH_data);
%% working_preferation for each individual (if works, based on data)
[Individuals_data,Individuals_data_P]=working_pref(Build_Data,Individuals_data,Individuals_data_P,HH_data,w_dis_job);
%% create salary to empty work places
Work_places=work_place_salary(Work_places);
%% car in the family (attached to individuals)
[Individuals_data,Individuals_data_P]=ind_num_car(Individuals_data, Individuals_data_P,HH_data);
%% number of routine per person
[Individuals_data,Individuals_data_P]=number_of_routine(Individuals_data,Individuals_data_P,acts,wactsnum);
%% SA score initial data
SA=SA_score(Build_Data);
%% activities locations
[Building_routine_id,Building_routine_id_P]=find_activity_location(Individuals_data,Build_Data,Work_places,HH_data,wact1,wact2,wactsnum,SA);
%% Assets price
[Build_Data,Build_Data_p,Assets,Assets_P]=ass_price(Build_Data,Build_Data_p,stat_data,Assets,Assets_P);
%% monthly assest cost
[Assets,Assets_P]=monthly_ass_cost(HH_data,Assets,Assets_P,Pa);
%% working pre for people who are looking for jobs!
ind=(Individuals_data(:,12)==1); % all unemployed
R=rand(sum(ind),1); % random vector
Individuals_data(ind,18)=R; % random preference
Individuals_data(:,22)=0; % new col(22)
Individuals_data_P=[Individuals_data_P,'ind_id_empty','time looking for job']; % header for what?
%% Working out side world income
income99=[mean(Individuals_data(Individuals_data(:,15)==99,14)),std(Individuals_data(Individuals_data(:,15)==99,14))];
average_wage=mean(Individuals_data(Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
std_wage=std(Individuals_data(Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
Wage_Change=0;

%adding for new pref_hh and SA_score_old functions, behavioral changes

% col(6) = baseline commercial-only service ratio (commercial/residential),
% consistent with building_service_ratio.m numerator (usage 2-3 only, not public/5).
% col(2) from stat_service.m (commercial+public) is kept untouched.
g_sa_init = unique(Build_Data(:,4));
for g0 = 1:length(g_sa_init)
    b0 = Build_Data(Build_Data(:,4)==g_sa_init(g0),:);
    com0 = sum(b0(:,3)>1 & b0(:,3)<4); % commercial only (usage 2-3)
    res0 = sum(b0(:,3)==1);
    if res0==0
        stat_data(stat_data(:,1)==g_sa_init(g0),6) = 0;
    else
        stat_data(stat_data(:,1)==g_sa_init(g0),6) = com0/res0;
    end
end

% col(5) = dynamic commercial-only service ratio, recalculated every 30 steps
stat_data(:,5) = stat_data(:,6);

% col(7) = fixed real land area (m^2) per SA, from TVR/sa_land_area.csv
% (derived from tveriashape/tveriastats.shp's Shape_Area field, EPSG:2039
% -- a real meters-based projection for Israel). col(8) = SA-level
% land-area service density: SA total commercial floorspace / col(7)
% land area -- a supply-only measure, immune to the shock's effect on
% residential stock (unlike col5/6, which divide by residential
% floorspace/count and can rise mechanically when housing is destroyed
% even if commercial supply itself didn't change). REPORTING-ONLY: does
% NOT feed pref_hh.m/SA_score_old.m/elderly_search_mode/svc_filter at
% all -- those still use col(5) unchanged, so elderly relocation
% behavior is completely unaffected by this metric. Two SAs (67000017,
% 67000035) aren't in the shapefile -- their land area (and therefore
% density) is left NaN rather than fabricated.
land_area_tbl = readtable([file,'TVR\sa_land_area.csv']);
stat_data(:,7) = NaN;
stat_data(:,8) = NaN;
for g0 = 1:length(g_sa_init)
    locLA = land_area_tbl.SAID == g_sa_init(g0);
    if any(locLA)
        la0_vals = land_area_tbl.land_area_m2(locLA);
        la0 = la0_vals(1);
        stat_data(stat_data(:,1)==g_sa_init(g0),7) = la0;
        b0 = Build_Data(Build_Data(:,4)==g_sa_init(g0),:);
        comm_floor0 = sum(b0(b0(:,3)>1 & b0(:,3)<4, 25)); % commercial floorspace (usage 2-3)
        if la0>0
            stat_data(stat_data(:,1)==g_sa_init(g0),8) = comm_floor0/la0;
        end
    end
end

service_mean = mean(stat_data(:,5));
service_std  = std(stat_data(:,5));
if service_std==0; service_std=eps; end


%% more model parameters
% BUG FIX: root-level commuting.xlsx is a different, wrong city's data
% (settlement 7100, not Tiberias's 6700 -- confirmed by inspecting both
% files). Same class of bug as the sas_national.xlsx fix above. Use the
% TVR-specific copy instead.
[commute]=xlsread([file,'TVR\commuting.xlsx']);
Y=unique(Build_Data(:,12)); % unique 'yeshuv'
for y=1:length(Y)
    a=Build_Data(:,12)==Y(y); % map all similar 'yeshuv' in col(12)
    b=commute(:,1)==Y(y); % map all similar 'yeshuv' for commuting
    if sum(b) == 0
        Build_Data(a,23)=34; % if no cummting for this 'yeshuv' set 'working zone' as 34
    else
        Build_Data(a,23)=commute(b,2); % set 'working zone' as 34 or 31
    end
end
Build_Data_p=[Build_Data_p,'Working zone']; % add header title
VISITS=[Build_Distance_matrix_400(:,1)]; % all building ID in 400m distance as first col
SALARY_HIST=Build_Data(:,1); % rolling history of daily building_average_sa, keyed by ALL building IDs (0 where not currently commercial) -- smooths the salary side of the ranking to match VISITS' own 30-day smoothing

g_sa=unique(Build_Data(:,4)); % unique SA ID
for g=1:length(g_sa)
    SA_PRICE(g,1)=nanmean(Assets(Assets(:,1)==g_sa(g),5)); % mean assets price in SA
    SA_HOUSE(g,1)=nanmean(Assets(ismember(Assets(:, 2),Build_Data(Build_Data(:,3)==1 | Build_Data(:,3)==2,1)) & Assets(:,1)==g_sa(g), 5));
    SA_COMERCIAL(g,1)=nanmean(Assets(ismember(Assets(:, 2),Build_Data(Build_Data(:,3)>2,1)) & Assets(:,1)==g_sa(g), 5));
    SA_POP(g,1)=sum(Assets(Assets(:,1)==g_sa(g),11)); % sum accupied assests in SA
    SA_ASSETS(g,1)=sum(Assets(:,1)==g_sa(g)); % sum total assets in SA
    SA_SERVICE(g,1)=sum(Build_Data(Build_Data(:,4)==g_sa(g),3)>2); % sum all building with usage greater then 2
    SA_RESIDENT(g,1)=sum(Build_Data(Build_Data(:,4)==g_sa(g),3)==1 | Build_Data(Build_Data(:,4)==g_sa(g),3)==2); % sum all building with usage 1 or 2
    SA_WP(g,1)=sum(Work_places(:,2)==g_sa(g));
    SA_JOBS(g,1)=sum(Work_places(:,2)==g_sa(g) & ((Work_places(:,7)==1 | Work_places(:,7)==3)))/sum(Work_places(:,2)==g_sa(g) & (Work_places(:,7)~=2 & Work_places(:,7)~=99));
    % BUG FIX: find_job_1.m always sets Individuals_data col(12) ('working
    % status') to 2 for anyone employed, whether the job is local or
    % outside-city -- the local/outside distinction lives in col(15)
    % ('building_work_place'), which find_job_1.m sets to 99 specifically
    % for outside hires (see find_job_1.m lines 35 vs 50). col(12) itself
    % never takes the value 99 anywhere in this codebase, so the old
    % formula's denominator (col12==2 | col12==99) was always identical to
    % its numerator (col12==2) -- SA_LOCAL was structurally pinned at 1.0
    % regardless of the real local/outside split.
    SA_LOCAL(g,1)=sum(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,12)==2 & Individuals_data(:,15)~=99)/sum(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,12)==2);
    SA_WORKING(g,1)=sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==2))/sum(Work_places(:,2)==g_sa(g) & (Work_places(:,7)~=2 & Work_places(:,7)~=99));
    SA_IDLE(g,1)=sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==1))/sum(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,12)>0);
    SA_WAGE(g,1)=mean(Individuals_data(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
    SA_OUTCOME(g,1)=sum(Work_places(Work_places(:,2)==g_sa(g),8));
    SA_INTER(g,1)=0;
    SA_OUTER(g,1)=0;
    SA_BETWEEN(g,1)=0;
    SA_NEWCOME(g,1)=0;
    SA_FIRST(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==1);
    SA_SECOND(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==2);
    SA_THIRD(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==3);
    SA_FOURTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==4);
    SA_FIFTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==5);
    SA_SIXTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==6);
    SA_SEVENTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==7);
    SA_EIGHTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==8);
    SA_NINTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==9);
    SA_TENTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==10);   
	SA_AREA(g,1)=sum(Build_Data(Build_Data(:,4)==g_sa(g) & Build_Data(:,3)==3, 25));
end

destroyed_B=[];
HH_subsidy_tracker=zeros(0,3); % [HH_ID, start_step, granted_amount]
Shelters=[];
Shelter_Assign=[];
Shelter_HH_Track=zeros(0,3); % [HH_ID, shelter_building_id, start_step]
SA_Shelter_Rank=[]; % built once on first assign_shelter_sa call
Shelter_Building_Routines={};

%% Household relocation tracker

HH_ORIGINAL = HH_data(:,[2 1 5]);

% Columns:
% 1 = HH ID
% 2 = Original SA
% 3 = Elderly count (HH_data(:,5)>=2)

% Cols 7-8 added for the shock-displacement-rate-by-3-way-group analysis:
% col 7 (OldOld_Count) lets a household that later LEAVES THE CITY still
% be classified young-old vs old-old (HH_data itself only holds
% currently-present households, so a left-city household's elderly
% subtype would otherwise be unrecoverable -- Elderly_Count col 3 alone
% only says "elderly", not which kind). col 8 (SA_at_3mo_snapshot) is a
% one-time snapshot of each shock-displaced household's SA taken
% shock_snapshot_days after the shock (see the shock block below) --
% NaN for everyone else, -1 if the household had already left the city
% by the snapshot day. Without this, there was no way to answer "where
% was this household 3 months post-shock" -- only final-simulation-day
% state was ever saved anywhere.
HH_MOVE_TRACK = [...
    HH_ORIGINAL,...
    nan(size(HH_ORIGINAL,1),1),...   % Final SA
    zeros(size(HH_ORIGINAL,1),1),... % Displaced (0/1)
    zeros(size(HH_ORIGINAL,1),1),... % Left city (0/1)
    HH_data(:,12),...                % OldOld_Count (0/1/2)
    nan(size(HH_ORIGINAL,1),1)];     % SA_at_3mo_snapshot (shock-displaced HH only)


HH_MOVE_TRACK_P = {

'HH_ID',...
'Original_SA',...
'Elderly_Count',...
'Final_SA',...
'Displaced',...
'Left_City',...
'OldOld_Count',...
'SA_at_3mo_snapshot'

};

% HH_MOVE_TRACK columns:
% 1 HH ID
% 2 Original SA
% 3 Elderly count
% 4 Final SA
% 5 Displaced
% 6 Left city
% 7 OldOld_Count
% 8 SA_at_3mo_snapshot
%% Time-series metrics

% cols 24-25 added: young-old (HH_data col5==3) / old-old (col5==6)
% population counts, splitting the existing elderly count (col6, which
% remains young-old+old-old combined) for the 3-way non-elderly/
% young-old/old-old population breakdown.
% cols 26-41 added: young-old/old-old versions of every remaining
% elderly-vs-non-elderly family (SA/building service ratio, normalized
% possible assets SA/city, attempt rate SA/city, success rate SA/city),
% mirroring the existing elderly-combined columns (2,4,10,11,14,15,
% 16-19,20-23) which are left unchanged.
Metric_Track = nan(steps,47);

Metric_Track_P = {
'Timestep',...
'SAServiceRatio_Elderly',...
'SAServiceRatio_NonElderly',...
'BuildingServiceRatio_Elderly',...
'BuildingServiceRatio_NonElderly',...
'ElderlyPop',...
'NonElderlyPop',...
'TotalPossAssets_SA_Elderly',...
'TotalPossAssets_SA_NonElderly',...
'NormPossAssets_SA_Elderly',...
'NormPossAssets_SA_NonElderly',...
'TotalPossAssets_City_Elderly',...
'TotalPossAssets_City_NonElderly',...
'NormPossAssets_City_Elderly',...
'NormPossAssets_City_NonElderly',...
'AttemptRate_SA_Elderly',...
'AttemptRate_SA_NonElderly',...
'AttemptRate_City_Elderly',...
'AttemptRate_City_NonElderly',...
'SuccessRate_SA_Elderly',...
'SuccessRate_SA_NonElderly',...
'SuccessRate_City_Elderly',...
'SuccessRate_City_NonElderly',...
'YoungOldPop',...
'OldOldPop',...
'SAServiceRatio_YoungOld',...
'SAServiceRatio_OldOld',...
'BuildingServiceRatio_YoungOld',...
'BuildingServiceRatio_OldOld',...
'NormPossAssets_SA_YoungOld',...
'NormPossAssets_SA_OldOld',...
'NormPossAssets_City_YoungOld',...
'NormPossAssets_City_OldOld',...
'AttemptRate_SA_YoungOld',...
'AttemptRate_SA_OldOld',...
'AttemptRate_City_YoungOld',...
'AttemptRate_City_OldOld',...
'SuccessRate_SA_YoungOld',...
'SuccessRate_SA_OldOld',...
'SuccessRate_City_YoungOld',...
'SuccessRate_City_OldOld',...
'SAServiceDensity_NonElderly',...
'SAServiceDensity_YoungOld',...
'SAServiceDensity_OldOld',...
'BuildingServiceDensity_NonElderly',...
'BuildingServiceDensity_YoungOld',...
'BuildingServiceDensity_OldOld'
};

elderly = HH_data(:,5)>=2;
nonelderly = ~elderly;

current_SA = HH_data(:,1);

[~,locStat] = ismember(current_SA,stat_data(:,1));
HH_service = stat_data(locStat,2);




mean(HH_service(elderly))
mean(HH_service(nonelderly))


% Columns:
% 1 = timestep
% 2 = service ratio - elderly
% 3 = service ratio - non-elderly
% 4 = service ratio - displaced elderly
% 5 = service ratio - displaced non-elderly
% 6 = housing cost - elderly
% 7 = housing cost - non-elderly
% 8 = housing cost - displaced elderly
% 9 = housing cost - displaced non-elderly
% 10 = Elderly population
% 11 = avg num. possible assets available - elderly HH moving
% 12 = avg num. possible assets available - non-elderly HH moving
% 13 = avg num. possible assets available - displaced elderly HH moving
% 14 = avg num. possible assets available - displaced non-elderly HH moving
% 15 = Non-elderly population
% 16 = number of elderly HH that attempted to relocate this step
% 17 = number of non-elderly HH that attempted to relocate this step
% 18 = movement rate - elderly (col16/col10)
% 19 = movement rate - non-elderly (col17/col15)
% 20 = asset availability ratio (AAR) - elderly (possible assets in HH's current SA only, avg across attempting HH)
% 21 = AAR - non-elderly
% 22 = successful relocation rate - elderly (of HH that attempted, fraction that moved)
% 23 = successful relocation rate - non-elderly





%% start running
for i=1:steps
    %toc
    % sum data
    average_wage=mean(Individuals_data(Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
    std_wage=std(Individuals_data(Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
    % values for each step
    sumdata(i).avgWage= average_wage;
    sumdata(i).stdWage= std_wage;
    sumdata(i).Wage_Change= Wage_Change;
    
    lost_jobs_B_ID =[];

    %% building movement - recovery, assets and work places
    if shock==1
        % Independent per-building daily Bernoulli recovery draw -- see
        % the RECOVERY definition above for the full derivation/ported-
        % from note. usg reads destroyed_B col(4) (pre-shock usage,
        % captured at the moment of destruction) rather than live
        % Build_Data(:,3), since the latter is now 0 for every destroyed
        % building regardless of type.
        recovery_prob=RECOVERY*ones(size(destroyed_B,1),1);
        if priority_recovery==1
            usg=destroyed_B(:,4);
            recovery_prob(usg==1)=min(RECOVERY*recovery_factor,1); % priority for residential, clamped to a valid probability
        end
        f=rand(size(destroyed_B,1),1)<recovery_prob;
        BI=destroyed_B(f,1);
        orig_usage_recovered=destroyed_B(f,4);
        destroyed_B(f,:)=[]; % remove all recovered
        if size(bad_Assets,1)>0 % bad assets remaining
            loca=ismember(bad_Assets(:,2),BI); % indexes of recovered
            Assets=[Assets;bad_Assets(loca,:)]; % return recovered to avalible list
            bad_Assets(loca,:)=[]; % clear recovered
        end
        Work_places=new_works_after_recovery(Work_places,Build_Data,BI,average_wage,std_wage);
        % Usage restoration on recovery: residential buildings (pre-shock
        % usage 1 or 2) revert to their original type, since every
        % housing-search pathway (filter_residential_assets.m) requires
        % usage in {1,2} before a household can even be offered that
        % asset -- without this, recovered housing stock is returned to
        % the Assets pool but permanently unreachable (this was the
        % actual bug behind SA_RESIDENT never recovering after a shock,
        % even though the recovery countdown completed). Non-residential
        % buildings (commercial/industrial/public) stay at usage=0
        % permanently by design -- their workplaces still function via
        % Work_places (matched by building ID, not gated by Build_Data
        % usage), they just no longer count toward service-ratio/
        % SA_SERVICE metrics once destroyed.
        restore_mask = orig_usage_recovered==1 | orig_usage_recovered==2;
        if any(restore_mask)
            [~,locRestore]=ismember(BI(restore_mask),Build_Data(:,1));
            Build_Data(locRestore,3)=orig_usage_recovered(restore_mask);
        end
        if displaced_shelter==1 && ~isempty(Shelters)
            [Build_Data, Shelters, Shelter_Assign, Shelter_HH_Track, Shelter_Building_Routines, Building_routine_id, forced_release_hh] = ...
                release_shelter_capped(Build_Data, Individuals_data, HH_data, Shelters, Shelter_Assign, Shelter_HH_Track,...
                Shelter_Building_Routines, Building_routine_id, Assets, BI, max_shelter_duration, i);
        end
    end 
    
    %% damaged building list

    if shock == 1
        damaged_buildings = destroyed_B(:,1);
    else
        damaged_buildings = [];
    end


    k=[];

    %% parameters need for later:
    Occupied_Jobs=sum(Work_places(:,7)==1)/sum(Work_places(:,7)<2); % occupied ratio in area, excluding 99
    a=Build_Data(:,3)>0; % usage > 0
    Floor_Size=sum(Build_Data(a,7).*ceil(Build_Data(a,11))); % floor size for building with usage (area*floors)
    LU=[];new_A=[];new_B=[];HH_change=[];Asset_Avail=[];
    new_jobs_work_places=[];HH_ID_left=[];lost_job_id=[];
    HH_destroyed=[];bad_Assets=[];lost_jobs=[];Ind_change_routine=[];
    forced_release_hh=[]; % HH forced out of shelter this step by max_shelter_duration
    max_salary = max(Work_places(:,8)); 
    row = find(Work_places(:,8) == max_salary); % index fo max salary
    max_WP_id=Work_places(row(1),6); % id of workplace with max salary
     % columns: [HH_ID, start_day]
    
    %% earthquake
    % One-time shock (same trigger pattern as the original run_model_eq.m),
    % replacing rocket_attack2's iterative wave loop. Requires a per-SA
    % damage table at [file,'TVR\earthquake_damage.csv'] - see earth_quake.m.
    % BUG FIX: path was missing the TVR\ subfolder prefix every other data
    % load in this file uses (model parameters.csv, sas_national.xlsx,
    % real_growth_rates.csv, commuting.xlsx all go through TVR\) -- never
    % caught before because no run prior to this had shock_step reachable
    % within its step count, so this line never actually executed.
    if i==shock_step && shock==0
        % DIAGNOSTIC (one-time): snapshot EVERY household's building
        % assignment and building-level service ratio right now, before
        % anything about today changes Build_Data at all -- Build_Data(:,19)
        % at this exact point still reflects yesterday's (day i-1) ending
        % state, since building_service_ratio.m only runs once per
        % iteration, near the end. Compared against the same households'
        % state right before today's Metric_Track row is computed, this
        % isolates how much of the immediate post-shock service-ratio jump
        % comes from the NON-displaced population (whose building didn't
        % get destroyed) vs. the displaced population (already tested
        % separately below).
        diag_allpop_pre_hh_ids = HH_data(:,2);
        [~, diag_locBuildPre] = ismember(HH_data(:,10), Build_Data(:,1));
        diag_allpop_pre_building = HH_data(:,10);
        diag_allpop_pre_svc = Build_Data(diag_locBuildPre, 19);
        diag_allpop_pre_density = Build_Data(diag_locBuildPre, 26);
        diag_allpop_pre_group = zeros(size(HH_data,1),1); % 0=non-elderly,1=young-old,2=old-old
        diag_allpop_pre_group(HH_data(:,5)==3) = 1;
        diag_allpop_pre_group(HH_data(:,5)==6) = 2;
        shock=1;
        [destroyed_B_P, destroyed_B] = earth_quake(Build_Data, [file,'TVR\earthquake_damage.csv']);
        [bad_Assets,Assets,destroyed_B]=shock_A(Assets,destroyed_B);
        % Usage-blind destruction: earth_quake.m selects damaged buildings
        % regardless of type, but previously only residential buildings'
        % usage ever actually zeroed out -- find_empty_buildings.m infers
        % "empty" from Assets occupancy, and non-residential buildings
        % have zero Assets rows to begin with (confirmed empirically:
        % Assets only ever contains rows for the city's ~2963 usage==1
        % buildings), so destroyed commercial/industrial/public buildings
        % kept counting as active service providers in
        % building_service_ratio.m/SA_SERVICE indefinitely. Capture each
        % destroyed building's pre-shock usage as destroyed_B col(4)
        % (needed to restore residential buildings correctly on recovery
        % below), then zero every destroyed building's usage immediately
        % and uniformly, matching earth_quake.m's own usage-blind
        % selection.
        [~,idx_destroyed_build] = ismember(destroyed_B(:,1),Build_Data(:,1));
        destroyed_B(:,4) = Build_Data(idx_destroyed_build,3);
        Build_Data(idx_destroyed_build,3) = 0;
        % HH no house
        HH_destroyed=shock_H(HH_data,Assets);

        % working places
        if ~isempty(HH_destroyed)
            destroyed_ids = unique(HH_destroyed(:));
            locA = ismember(HH_data(:,2),destroyed_ids);
            selected_HH = HH_data(locA,:);

            [~,locTrack] = ismember(selected_HH(:,2),HH_MOVE_TRACK(:,1));

            HH_MOVE_TRACK(locTrack,5) = 1; %sets displaced flag to 1)

            n = size(selected_HH,1);

            % Persisted (not reset next step, unlike HH_destroyed/
            % destroyed_ids above) so the short-term snapshot block below
            % can still find this exact household list weeks later.
            shock_displaced_hh_ids = destroyed_ids;

            % Staggered relocation eligibility (toggle: use_staggered_
            % relocation): assign each newly-displaced household to the
            % 'slow' or 'fast' mover population once, here, then let the
            % per-step Bernoulli draw below (near moving_HH construction)
            % decide when it actually enters the housing search. See the
            % relocation_w_slow/p_slow/p_fast definitions above for the
            % calibration source. When off, HH_destroyed feeds moving_HH
            % directly instead (original same-day behavior).
            if use_staggered_relocation==1
                is_slow_draw = rand(numel(destroyed_ids),1) < relocation_w_slow;
                pending_relocation = [pending_relocation; destroyed_ids, double(is_slow_draw)];
            end

            % DIAGNOSTIC (one-time, shock day only): does same-day housing
            % search already relocate a meaningful share of displaced
            % households before today's Metric_Track row is computed?
            % Captures each displaced household's building assignment
            % right now (still pointing at their destroyed home, before
            % any of today's moving_HH/search logic runs) so it can be
            % compared against their assignment right before the metric
            % block below, at the end of the same day's processing.
            diag_pre_search_hh_ids = selected_HH(:,2);
            diag_pre_search_building = selected_HH(:,10);
        end
        % lost jobs (work places id - to find workers) and delete working places
        [Work_places,lost_jobs]=shock_W(Work_places,destroyed_B);
        % people loosing work (change from working to looking) and
        % change location and keep track because need to change routine
        [Individuals_data,Ind_change_routine]=shock_I(Individuals_data,lost_jobs);

        if displaced_shelter==1 && ~isempty(HH_destroyed)
            [Build_Data, Shelters, Shelter_Assign, Shelter_HH_Track, Shelter_Building_Routines, Building_routine_id, SA_Shelter_Rank] = ...
                assign_shelter_sa(Build_Data, Individuals_data, HH_data, HH_destroyed, Shelters, Shelter_Assign, Shelter_HH_Track,...
                Shelter_Building_Routines, Building_routine_id, SA_Shelter_Rank, i, agents_per_sqm);
        end
    end

    % Short-term (default 90 days = "up to 3 months") post-shock snapshot
    % of where the originally shock-displaced households (persisted
    % above as shock_displaced_hh_ids) ended up -- HH_MOVE_TRACK col 8.
    % Runs exactly once, the day the snapshot window closes. Households
    % still present in the city at that moment get their current SA;
    % households no longer in HH_data (already left) get -1 rather than
    % being left NaN, so "NaN" unambiguously means "not part of the
    % shock-displaced cohort" everywhere else in this column.
    if ~exist('shock_snapshot_days','var'); shock_snapshot_days=90; end
    if exist('shock_displaced_hh_ids','var') && ~isempty(shock_displaced_hh_ids) && i==(shock_step+shock_snapshot_days)
        [~,locTrack] = ismember(shock_displaced_hh_ids,HH_MOVE_TRACK(:,1));
        validTrack = locTrack>0;
        [stillHere,locHH] = ismember(shock_displaced_hh_ids(validTrack),HH_data(:,2));
        snapSA = -1*ones(sum(validTrack),1); % default: already left the city
        snapSA(stillHere) = HH_data(locHH(stillHere),1);
        HH_MOVE_TRACK(locTrack(validTrack),8) = snapSA;
    end

    [HH_data,HH_subsidy_tracker]=HH_subsidy_pct(HH_data,HH_destroyed,HH_subsidy_tracker,subsidy_residents,subsidy_pct,w_subsidy_eld,subsidy_duration,i);

    % HH still waiting in shelter after this step's releases/new
    % assignments above - these retry the within-SA search every step
    % (from their original SA/building, since HH_data still points there)
    % until they find housing or their home recovers. forced_release_hh
    % (set above by release_shelter_capped) are NOT exempt from deletion
    % below if this attempt fails - the duration cap means relocate-or-leave.
    still_sheltered_hh = Shelter_HH_Track(:,1);

    % Staggered relocation eligibility (toggle: use_staggered_relocation):
    % each still-pending displaced household draws against its assigned
    % fast/slow daily probability; only those that pass enter today's
    % housing search (moving_HH). When off, HH_destroyed feeds moving_HH
    % directly instead (original same-day behavior, unchanged from before
    % this session's change).
    newly_eligible_hh = [];
    if use_staggered_relocation==1
        if ~isempty(pending_relocation)
            % BUG FIX: a household can sit in pending_relocation for many
            % days (slow movers average ~70 days). In the meantime it can
            % independently get picked up by the ordinary who_is_moving
            % roll, attempt (and keep failing) a search from its still-
            % destroyed home, and get deleted via the existing
            % resSearchLen/did_not_find_house eviction path -- all while
            % pending_relocation still holds its ID. If its Bernoulli draw
            % then "succeeds" for a household that no longer exists in
            % HH_data, find_new_house_same_stat crashes trying to look up
            % a non-scalar/empty SA for it. Prune stale entries first.
            still_exists_pending = ismember(pending_relocation(:,1), HH_data(:,2));
            pending_relocation = pending_relocation(still_exists_pending,:);
        end
        if ~isempty(pending_relocation)
            p_draw = zeros(size(pending_relocation,1),1);
            p_draw(pending_relocation(:,2)==1) = relocation_p_slow;
            p_draw(pending_relocation(:,2)==0) = relocation_p_fast;
            eligible_now = rand(size(pending_relocation,1),1) < p_draw;
            newly_eligible_hh = pending_relocation(eligible_now,1);
            pending_relocation(eligible_now,:) = [];
        end
    else
        newly_eligible_hh = HH_destroyed;
    end

    moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,2,eld_movef,eld_movef_old); % K=2, probability of moving within SA
    moving_HH=[moving_HH;newly_eligible_hh;still_sheltered_hh;forced_release_hh];
    moving_HH=unique(moving_HH);
    if isempty(moving_HH)==0 % assign new asset for agent
        [HH_ID_left,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]...
            =find_new_house_same_stat(HH_ID_left,pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data, ...
            Build_Data,Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change,Asset_Avail,svc_filter,elderly_search_mode);

        if ~isempty(HH_change)  

            moved_hh = unique(HH_change(:,1));

            locPost = ismember(HH_data(:,2),moved_hh);

            POST_MOVE = HH_data(locPost,:);

            [~,locTrack] = ismember(POST_MOVE(:,2),HH_MOVE_TRACK(:,1));


            HH_MOVE_TRACK(locTrack,4) = POST_MOVE(:,1);

            %updates tracker with new SA

            % resSearchLen: successful move resets the consecutive-fail counter
            HH_data(ismember(HH_data(:,2),moved_hh),13) = 0;
        end

    end

    moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,3,eld_movef,eld_movef_old); % K=3, probability of moving within the city

    if isempty(moving_HH)==0
        [HH_ID_left,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]= ...
            find_new_house_yeshuv(HH_ID_left,pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data ...
            ,Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change,Asset_Avail,svc_filter,elderly_search_mode);
        if ~isempty(HH_change)

            moved_hh = unique(HH_change(:,1));

            locPost = ismember(HH_data(:,2),moved_hh);

            POST_MOVE = HH_data(locPost,:);

            [~,locTrack] = ismember(POST_MOVE(:,2),HH_MOVE_TRACK(:,1));

            HH_MOVE_TRACK(locTrack,4) = POST_MOVE(:,1);

            % resSearchLen: successful move resets the consecutive-fail counter
            HH_data(ismember(HH_data(:,2),moved_hh),13) = 0;
        end
    end


    % HH still sheltered (and not this step's forced-duration release) are
    % exempt from deletion if this attempt failed - they stay in the
    % shelter and retry next step. forced_release_hh HH are NOT exempt:
    % the duration cap means this is their last attempt.
    exempt_sheltered = ismember(HH_ID_left, still_sheltered_hh) & ~ismember(HH_ID_left, forced_release_hh);
    HH_ID_left = HH_ID_left(~exempt_sheltered);

    % resSearchLen retry gate: a failed search increments the HH's
    % consecutive-fail counter (col 13); only once that counter reaches
    % resSearchLen does the HH actually leave the city below. Anyone still
    % under budget keeps their (incremented) counter and simply isn't
    % passed to the leave/delete step this time -- they stay in HH_data
    % and get another chance whenever they're next selected to move.
    if ~isempty(HH_ID_left)
        [locA,~] = ismember(HH_data(:,2), HH_ID_left);
        HH_data(locA,13) = HH_data(locA,13) + 1;
        [~,locB] = ismember(HH_ID_left, HH_data(:,2));
        HH_ID_left = HH_ID_left(HH_data(locB,13) >= resSearchLen);
    end

    if ~isempty(HH_ID_left)

    [~,locTrack] = ismember(HH_ID_left,HH_MOVE_TRACK(:,1));

    HH_MOVE_TRACK(locTrack,6)=1;

    end
    %saves HH that leave simulation before they are deleted


    %% delete HH that left (sheltered HH exempted above stay in the sim)
    [Individuals_data,Work_places,HH_data,Assets,HH_ID_left]=did_not_find_house(HH_ID_left,Individuals_data,Work_places,HH_data,Assets);

    %% individuals steps:
    %% job status looking, finding, stoping
    [agent_rot,Individuals_data,HH_data,Work_places]=find_job_1(HH_ID_left,Individuals_data,HH_data,Work_places,Build_Data,income99);
      
    %% Buildings steps:   
    visit_volume=cal_visits(Building_routine_id,Build_Distance_matrix_400); % number of visits per building by agents
    VISITS=[VISITS,visit_volume(:,2)]; % new visits count col every iteration

    if size(VISITS,2) > 31
        VISITS(:,2)=[]; % keep rolling 30-step window
    end

    if ~exist('lu_warmup','var'); lu_warmup=4; end % steps before land-use/business updates start
    if ~exist('lu_update_every','var'); lu_update_every=1; end % run every Nth step after warmup (raise to speed up a test run)

    % Rank-diff thresholds for the visits-vs-salary percentile ranking
    % system (building_average_salary(:,5) / pot_sal_for_B-based V).
    % Recomputed from scratch every active land-use step, so raising these
    % directly reduces both the one-time backlog-clearing spike on the
    % first active day (30 days of drift evaluated at once) and the
    % ongoing daily churn rate.
    % Defaults are the best-found combination from empirical testing
    % (see run_threshold_test_lostjobs.m): raising the LU conversion band
    % alone cuts residential/service churn roughly in half; separately
    % pushing lost_jobs_rank_thresh out (while leaving new_jobs_rank_thresh
    % at its original value, since new_jobs and lu_change are coupled --
    % raising lu_change reduces how many buildings ever get seeded with
    % workplaces, so also raising new_jobs compounds workplace loss)
    % additionally brings workplace loss below the original baseline.
    if ~exist('new_jobs_rank_thresh','var'); new_jobs_rank_thresh=20; end       % rank diff above this -> add workplaces to building
    % lost_jobs_rank_thresh/lu_change_rank_lower/lu_change_rank_upper
    % locked in as a validated combo (band widened 60-80 -> 45-85) -- see
    % the matching comment in run_earthquake_setting.m for the 10-
    % replicate CI finding that justified this (SA_JOBS reaches genuine
    % saturation, letting mean wage actually plateau instead of drifting
    % indefinitely, at the cost of a small but real population shortfall).
    if ~exist('lost_jobs_rank_thresh','var'); lost_jobs_rank_thresh=-100; end   % rank diff below this -> delete building's workplaces entirely
    if ~exist('lu_change_rank_lower','var'); lu_change_rank_lower=45; end       % Change_LU band lower bound
    if ~exist('lu_change_rank_upper','var'); lu_change_rank_upper=85; end       % Change_LU band upper bound

    if i>lu_warmup && mod(i,lu_update_every)==0
        %% mean visit per building
        MVB30=[VISITS(:,1),nanmean(VISITS(:,2:end),2)];
        % calculate visits by precentile up to 100
        P=[0,prctile(MVB30(:,2),1:100)]; % first element is zero then 101 in total. index shift
        % VECTORIZED (was: a 100-iteration loop re-scanning the whole
        % column each time to find which bin every row falls in). Since
        % P doesn't depend on each row's own value here (unlike the
        % land-use candidate ranking above), the bin index for row value
        % v is exactly count(P(1:100) <= v) -- same P(ppp)<=v<P(ppp+1)
        % definition, all rows computed in one broadcast comparison.
        rank_col = sum(MVB30(:,2) >= P(1:100), 2);
        rank_col(rank_col==0) = 100; % same fallback as the old post-loop fixup
        MVB30(:,3) = rank_col;

        %% mean salary for all buildings withe workers comm only!!!
        %building_average_salary=cal_bui_sa(Work_places,Build_Data); % building sum salary
        building_average_salary=cal_bui_sa_subsidy(Work_places, Build_Data, destroyed_B, subsidy_businesses); % building sum salary

        % Smooth the salary side of the ranking over a rolling window
        % (salary_smooth_window days, default 30 to match VISITS/MVB30's
        % own window) instead of ranking on a single noisy day-snapshot.
        % The raw daily total gets recorded for every building (0 where
        % not currently commercial) in SALARY_HIST, keyed by the FULL,
        % fixed building-ID list so buildings that only recently became
        % commercial build up history gradually rather than appearing
        % from nowhere with a single-day value.
        if ~exist('salary_smooth_window','var'); salary_smooth_window=30; end
        today_salary = zeros(size(SALARY_HIST,1),1);
        [~, locS] = ismember(building_average_salary(:,1), SALARY_HIST(:,1));
        today_salary(locS(locS>0)) = building_average_salary(locS>0,2);
        SALARY_HIST = [SALARY_HIST, today_salary];
        if size(SALARY_HIST,2) > salary_smooth_window+1
            SALARY_HIST(:,2)=[]; % keep rolling window
        end
        [~, locH] = ismember(building_average_salary(:,1), SALARY_HIST(:,1));
        building_average_salary(:,2) = mean(SALARY_HIST(locH,2:end), 2);

        P=[0,prctile(building_average_salary(:,2),1:100)]; % salary by precentiles
        % VECTORIZED -- same reasoning as the MVB30 ranking above.
        rank_col = sum(building_average_salary(:,2) >= P(1:100), 2);
        rank_col(rank_col==0) = 100; % highest score
        building_average_salary(:,3) = rank_col;

        %% empty building or residance - potential salary
        B=Build_Data(Build_Data(:,3)<2,:); % living or combined and no HH
        %% building area floors*area
        % Separate from lu_jobs_per_meter (which seeds jobs AFTER a
        % building converts) -- this one feeds the potential-salary
        % ranking that decides WHETHER a building converts in the first
        % place (Change_LU below), so it's tested independently.
        if ~exist('lu_potential_jobs_per_meter','var'); lu_potential_jobs_per_meter=0.017865406; end % 2.0x Tiberias JobsPerM_comm, validated combo
        workers=ceil((B(:,7).*ceil(B(:,11)).*lu_potential_jobs_per_meter)); % model parameter jobs per comm
        pot_sal_for_B=[B(:,1),workers.*average_wage]; % building ID and total wage
        
        %% find_comm_visit_rank
        [locA,locB]=ismember(building_average_salary(:,1),MVB30(:,1)); % locate building id in visits metrix
        building_average_salary(locA,4)=MVB30(locB(locB>0),3); % col(4) visits ranking
        building_average_salary(:,5)=building_average_salary(:,4)-building_average_salary(:,3); % diff in ranks
        
        %% new jobs - com only
        new_jobs=building_average_salary(building_average_salary(:,5)>new_jobs_rank_thresh,1); % only rank diff above threshold vector
        std_wage_1 = std_wage/3; % normilize std wage value
		B_D = [];
        for jjjj=1:length(new_jobs)
            a=find(Work_places(:,1)==new_jobs(jjjj)); % indexes for building ID match
            b=find(Build_Data(:,1)==new_jobs(jjjj)); % find exact building id
            if sum(Work_places(a,5)<Build_Data(b,17)*1.7)>0 % current number of jobs lower then initial
                Work_places(a,5)=Work_places(a,5)+1;
                B_D=[B_D;Work_places(a(1),1:5)]; % copy ID, SA and coordinates
            end
        end
        if ~isempty(B_D)
            if ~exist('commute_outside_rate','var'); commute_outside_rate=0.246; end % Tiberias zone-99 share (TVR/commuting.xlsx) -- was Ashkelon's rate (0.778038196)
            working99_prob = 1-commute_outside_rate;
            new_jobs_sa=normrnd(average_wage,std_wage_1,size(B_D,1),1); % normalized wage vector
            occ=zeros(size(B_D,1),1); % zeros vector
            working99 = randsample(size(B_D,1), round(working99_prob*size(B_D,1)));
            occ(working99) = 99;
            new_id=(max(Work_places(:,6))+1:max(Work_places(:,6))+size(B_D,1))'; % max workplace ID to new vector
            % {'building id','stat','X','Y','number of work places','id','occupied','salary'}
            new_jobs_work_places=[B_D,new_id,occ,new_jobs_sa]; % append cols NaN, new workspace ID, zeros, normalized wage
            Work_places=[Work_places; new_jobs_work_places]; % append rows to work places
        end

        %% lost jobs
        lost_jobs_B_ID=building_average_salary(building_average_salary(:,5)<lost_jobs_rank_thresh,1); % only rank diff below threshold vector
        lost_jobs_B_ID=Build_Data(ismember(Build_Data(:,1),lost_jobs_B_ID),[1,17]); % all matching ID cols(1 and 17)
        [~, newB] = ismember(lost_jobs_B_ID(:,1),Work_places(:,1)); % building ID first index matching
        lost_jobs_WP_ID = Work_places( newB,[1,5]); % current WP count out of avalible by building
        lost_jobs_B_ID = sortrows(lost_jobs_B_ID, 1); % sort to match building ID
        lost_jobs_WP_ID = sortrows(lost_jobs_WP_ID, 1); % sort to match building ID
        lost_jobs_B_ID(:,3)=round(lost_jobs_WP_ID(:,2)-1); % col(3) workplace-1
        newB = ismember(Work_places(:,1),lost_jobs_B_ID(:,1)); % find all building id
        lost_jobs_B_ID(:,4)=lost_jobs_B_ID(:,3)./lost_jobs_B_ID(:,2)<0.5; % normilized value < 0.5
        
        % NOTE: individual-level job loss used to be applied here, matched
        % by BUILDING id against ALL of lost_jobs_B_ID -- but multi-job
        % buildings (col(4)==0 below) only ever close ONE workplace slot
        % per flagged day, not all of them. Matching by building
        % unemployed every current employee of a flagged multi-job
        % building in one shot, wildly overcounting job loss relative to
        % what actually closed. Fixed below: individuals are now matched
        % by their SPECIFIC work_place_id against the workplaces that
        % actually closed today (closed_wp_ids_today), computed after both
        % the close-all (single-job buildings) and close-one (multi-job
        % buildings) branches run.
        closed_wp_ids_today = [];

        %% delete all jobs (original, before policy change)
        %F=lost_jobs_B_ID(lost_jobs_B_ID(:,4)==1,1); % locate all lost jobs
        %Work_places(ismember(Work_places(:,1),F),7)=2; % delete all jobs from building
        %% lost job ID
        %lost_job_id=Work_places(ismember(Work_places(:,1),F),6); % Workplace ID match to lost 
        %Build_Data(ismember(Build_Data(:,1),F) & Build_Data(:,3)==3,3)=0; % Usage=0 if lost and was 3

        %% delete all jobs from the buildings

        F=lost_jobs_B_ID(lost_jobs_B_ID(:,4)==1,1);
        
        if commercial_preservation
        
            F_keep = [];
        
            for jj = 1:length(F)
        
                bld = F(jj);
        
                if ismember(bld,damaged_buildings)
                    p = comm_damaged_prob;
                else
                    p = comm_undamaged_prob;
                end
        
                if rand > p
                    F_keep = [F_keep; bld];
                end
        
            end
        
            F = F_keep;
        
        end
        
        Work_places(ismember(Work_places(:,1),F),7)=2;

        lost_job_id=Work_places(ismember(Work_places(:,1),F),6);
        closed_wp_ids_today=[closed_wp_ids_today;lost_job_id];

        Build_Data(ismember(Build_Data(:,1),F) & Build_Data(:,3)==3,3)=0;




        %% delete one job
        % Check if only one job is deleted for each building
        % sort worplaces by building and wage, and delete the lost wage
        F=lost_jobs_B_ID(lost_jobs_B_ID(:,4)==0,1); % value above 0.5 ; workplace/round(worplace-1)
        [~,locB]=ismember(F,Work_places(:,1)); % indexes by matching building ID
        Work_places(locB,7)=2; % 'occupied'=2
        lost_job_id=[lost_job_id;Work_places(locB,6)]; % append rows only col(6) - 'id'
        closed_wp_ids_today=[closed_wp_ids_today;Work_places(locB,6)];

        %% people lost job -- matched by the SPECIFIC workplace slot that
        % actually closed today (work_place_id, col 17), not by building
        ind_lost_job = ismember(Individuals_data(:,17),closed_wp_ids_today);
        Individuals_data(ind_lost_job,12) = 1; % 'working status' = 1
        Individuals_data(ind_lost_job,15) = 0; % 'building_work_place' = 0
        Individuals_data(ind_lost_job,17) = 0; % 'work_place_id' = 0
        Individuals_data(ind_lost_job,14) = 0; % 'income' = 0
        % BUG FIX: col(18) ('random preference', the job-acceptance
        % threshold find_job_1.m tests candidates against) was only ever
        % drawn once at day-0 init for the original unemployed cohort --
        % anyone entering job-search status afterward (here, or at the
        % "add people to working market" site below) kept whatever
        % col(18) they had, which for anyone never in that original
        % cohort is the array's un-initialized default of exactly 0
        % (zero pickiness -- accepts the very first candidate seen every
        % time). Confirmed via direct inspection: 5 of 8 currently-
        % searching individuals in a 400-day test run had col(18)==0
        % exactly. Fix: draw a fresh threshold on every transition into
        % job-search status, same as the original day-0 initialization.
        Individuals_data(ind_lost_job,18) = rand(sum(ind_lost_job),1);

        %% commercial potantial change LU
        if  comm_policy==0
            [locA,locB]=ismember(pot_sal_for_B(:,1),MVB30(:,1)); % building ID and total wage ; mean visit per building
            pot_sal_for_B(locA,3)=MVB30(locB(locB>0),3); % new col(3) append mean visits ranking
            % VECTORIZED (was: per-candidate loop calling prctile fresh
            % for every candidate, then linearly scanning 100 bins by
            % re-testing bin membership against the WHOLE base array just
            % to read its last element -- O(candidates x 100 x buildings)
            % of pure waste). Mathematically identical result: for each
            % candidate, prctile([base_salaries; candidate_value], 1:100)
            % is still computed with the candidate as the last element,
            % exactly as before -- just batched into one matrix call
            % instead of one call per candidate. The bin index (ppp) that
            % a value v falls into, given edges P(1)=0 <= P(2) <= ... <=
            % P(101)=max, is exactly count(P(1:100) <= v) -- proven by
            % the same P(ppp)<=v<P(ppp+1) definition the original loop
            % used, so this replaces both loops with two matrix ops.
            Change_LU=[];
            Mcand = size(pot_sal_for_B,1);
            if Mcand>0
                base_col = building_average_salary(:,2);
                cand_vals = pot_sal_for_B(:,2)'; % 1 x Mcand
                A_mat = [repmat(base_col,1,Mcand); cand_vals]; % (Nbase+1) x Mcand
                P_mat = [zeros(1,Mcand); prctile(A_mat,1:100)]; % 101 x Mcand
                ppp_vec = sum(P_mat(1:100,:) <= cand_vals, 1)'; % Mcand x 1
                V_vec = pot_sal_for_B(:,3) - ppp_vec;
                Change_LU = pot_sal_for_B(V_vec>lu_change_rank_lower & V_vec<lu_change_rank_upper, 1);
            end
            %% change land use
            %[locA,~]=ismember(Build_Data(:,1),Change_LU); % locate building ID in new list
            %Build_Data(locA,3)=3; % 'Usage' = 3 - commercial
            %New_Comm_B=Build_Data(locA,:); % Only commercial
                
            %% residential preservation policy

            if residential_preservation
            
                Change_LU_keep = [];
            
                for jj = 1:length(Change_LU)
            
                    bld = Change_LU(jj);
            
                    if ismember(bld,damaged_buildings)
                        p = res_damaged_prob;
                    else
                        p = res_undamaged_prob;
                    end
            
                    if rand < p
                        Change_LU_keep = [Change_LU_keep; bld];
                    end
            
                end
            
                Change_LU = Change_LU_keep;
            
            end

            %% change land use
            
            [locA,~]=ismember(Build_Data(:,1),Change_LU);
            
            Build_Data(locA,3)=3;
            
            New_Comm_B=Build_Data(locA,:);

            
            %% delete residental jobs in building
            locA=ismember(Work_places,New_Comm_B(:,1)); % workplaces in commercial building
            lost_job_id=[lost_job_id;Work_places(locA,6)]; % append rows in lost jobs
            
            %% HH must find new house
            locA=ismember(HH_data(:,10),New_Comm_B(:,1)); % 'building id' in commercial buildings
            moving_HH=HH_data(locA,2); % 'HH ID' ; HH that moving from LU changed building
            if isempty(moving_HH)==0
                [HH_ID_left,HH_data,Assets,HH_change,LU,...
                    new_A,new_B,Build_Data,Asset_Avail]...
                    =find_new_house_same_stat(HH_ID_left,pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data,...
                    Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change,Asset_Avail,svc_filter,elderly_search_mode);

                if ~isempty(HH_change)

                    moved_hh = unique(HH_change(:,1));

                    locPost = ismember(HH_data(:,2),moved_hh);

                    POST_MOVE = HH_data(locPost,:);

                    [~,locTrack] = ismember(POST_MOVE(:,2),HH_MOVE_TRACK(:,1));

                    HH_MOVE_TRACK(locTrack,4) = POST_MOVE(:,1);

                    % resSearchLen: successful move resets the consecutive-fail counter
                    HH_data(ismember(HH_data(:,2),moved_hh),13) = 0;
                end
            end

            % Land-use displacement: NO resSearchLen retry here (unlike the
            % other two call sites). A household whose building just
            % converted to commercial has nowhere left to retry against --
            % the conversion trigger only fires once, so giving them a
            % 30-day grace period just leaves them as a ghost occupant of
            % an asset inside a now-commercial building for a month before
            % eventual eviction, silently decoupling population from
            % actual residential capacity. Matches the original (pre-fork)
            % model's behavior: evict immediately if the one relocation
            % attempt above failed.
            if ~isempty(HH_ID_left)

            [~,locTrack] = ismember(HH_ID_left,HH_MOVE_TRACK(:,1));

            HH_MOVE_TRACK(locTrack,6)=1;

            end
            %saves HH that leave simulation before they are deleted


            %% delete HH that left
            [Individuals_data,Work_places,HH_data,Assets,HH_ID_left]= ...
            did_not_find_house(HH_ID_left,Individuals_data,Work_places,HH_data,Assets);
    
            %% new jobs because of land use
            % NOTE: the inline comment on the next line says "*0.014" but
            % the value actually used is 0.00779 -- roughly half. Made
            % configurable to test both.
            if ~exist('lu_jobs_per_meter','var'); lu_jobs_per_meter=0.040197164; end % 4.5x Tiberias JobsPerM_comm, validated combo
            JOBS_per_meter=lu_jobs_per_meter;
            workers=(New_Comm_B(:,7).*ceil(New_Comm_B(:,11)).*JOBS_per_meter); % Area*roundup(floor)*jobs-per-meter ; have col(25) already claculated
            workers(workers<1)=1;
		    New_Comm_B(:,17)=workers; % num of workers
            a=round(New_Comm_B(:,17))>0; % all workplaces with at least 1 worker
            wp=New_Comm_B(a,:); % new data
            wp(:,17)=round(wp(:,17)); % roundup values
            u=unique(wp(:,17)); %  unique workers count
            wp1=[];
            for iii=1:length(u) % duplicate all unique workplaces into new by workers count
                data=[];
                data=repmat(wp(wp(:,17)==u(iii),:),u(iii),1); % matrix of diplicated rows
                wp1=[wp1;data]; % append workplaces 
            end
            if size(wp1,1)>0 
                WP=wp1(:,[1,4:6,17]); % copy col(1,4,5,6,17) ; 'BLDG_ID_x' 'SAID' 'X' 'Y' 'work place'
                new_id=(max(Work_places(:,6))+1:max(Work_places(:,6))+size(WP,1))'; % create id to new workpaces 
                WP(:,6)=new_id; % assing cinsecutive id to new workpaces
                occ=zeros(size(WP,1),1); % zeros vector
                working99 = randsample(size(WP,1), round(working99_prob*size(WP,1)));
                occ(working99) = 99;
                WP(:,7)=occ; % set occupied=0
                std_wage_1 = std_wage/3; % normilized wage
                N=normrnd(average_wage,std_wage_1,[size(WP,1),1]); % random values for wage
                WP(:,8)=N; % set 'salary'
                Work_places=[Work_places;WP]; % append rows
            end
            if size(VISITS, 2) > 31
                VISITS(:,2:end-1)=VISITS(:,3:end); % Shift columns 3 to 30 left
                VISITS(:,end)=[]; % Delete the last column
            end
        end
    end
    
    %% MODEL SHUK HAVODA:
    if ~exist('commute_outside_rate','var'); commute_outside_rate=0.246; end % Tiberias zone-99 share (TVR/commuting.xlsx) -- was Ashkelon's rate (0.778038196)
    commute_outside=commute_outside_rate;
    wp_prc=prctile(Work_places(:,8),1:100); % calc precentiles by salary
    top_10_prc=wp_prc(1,90); % get salary min threshold 
    lost_wp=Work_places(:,8)>top_10_prc; % workplaces with high salary
    if sum(lost_wp)>0
        WP_buildings=Work_places(lost_wp,:); % all workplaces above max salary by ID
        Work_places(lost_wp,:)=[]; % remove workplaces with high salary
        [~,locW]=ismember(WP_buildings(:,1),Build_Data(:,1)); % find workpaces building 
        Z=Build_Data((locW <= 0 | isnan(locW)),23); % 23 -'Working zone'
        F=find(Z==31); % all 31 zone
        rand_wp = randsrc(size(F,1),1,[1,0;commute_outside,1-commute_outside]);
        F(rand_wp ==0)=[];
        WP_buildings(F,7)=99; % 'occupied' = 99        
        Work_places=[Work_places;WP_buildings]; % append new rows with 99 
    end
    %% change average_wage
    % Candidate values seen across comments in this file and the reference
    % (romansunedited/run_model_eq.m): alfa in {0.2,0.3,0.4}, beta in
    % {0.6,0.8}, lamda in {0.25,0.45,0.95}, delta in {0.75,0.8,0.95}.
    if ~exist('wage_alfa','var'); wage_alfa=0.3; end
    if ~exist('wage_beta','var'); wage_beta=0.8; end
    % wage_lamda reverted to 0.95 (original default) per user request.
    % Note from prior tuning session: a late-period OAT sweep (land-use
    % activity frozen, day 360+) found lamda controls the sign of the
    % persistent post-freeze wage drift via the 1/lamda exponent on
    % income_ratio -- 0.95 gives a small but permanent decline (-0.49%
    % over days 360-550), 0.55 was the closest-to-flat value actually
    % tested (+0.24%). alfa/beta/delta showed no comparably clean lever
    % (alfa provably can't matter once land-use freezes, since
    % floor_ratio's base is exactly 1 then; beta/delta showed real but
    % non-monotonic sensitivity, not a usable dial).
    if ~exist('wage_lamda','var'); wage_lamda=0.95; end
    if ~exist('wage_delta','var'); wage_delta=0.75; end
    alfa=wage_alfa;
    beta=wage_beta;
    lamda=wage_lamda;
    delta=wage_delta;
    
    Occupied_Jobs_1=sum(Work_places(:,7)==1 | Work_places(:,7)==99)/sum(Work_places(:,7)~=2); % occupied/total
    a=Build_Data(:,3)>0; % 4 - industrial ; 5 - public ; 6 - senior 
    Floor_Size_1=sum(Build_Data(a,7).*ceil(Build_Data(a,11))); % area*floors
    
    job_ratio=(Occupied_Jobs_1/Occupied_Jobs)^(1-beta); % ( (occupied ratio new)/(occupied ratio initial) )^(1-0.6)
    floor_ratio=(Floor_Size_1/Floor_Size)^alfa; % ( (all buildings size)/(class 4-5-6 buildings size) )^0.4
    income_ratio=(job_ratio/floor_ratio)^(1/lamda); % ( (job ratio)/(floor ratio) )^(1/0.25)
    if i >1 % after first iteration
        average_wage_1=income_ratio*average_wage; % new mean wage
        Wage_Change=average_wage_1-average_wage; % wage delta
        average_wage=average_wage_1; % update mean wage
    end

    %% change salary for empty jobs ; update unoccupied salary by new ratio
    Work_places(Work_places(:,7)==0,8)=Work_places(Work_places(:,7)==0,8).*income_ratio;

    %% change salary for occupied jobs
    R=datasample(random_number,sum(Work_places(:,7)==1)); % random values as size of occupied worplaces 
    R=R<abs(1/income_ratio-1); % random < |1/ratio - 1|
    Work_places(R,8)=Work_places(R,8).*delta.*income_ratio; % salary*0.8*ratio 
    low_sal = Work_places(:,8) < min_sal/4;
    Work_places(low_sal,8)=min_sal/4;
	F=find(R==1); % indexes for true values

    if income_ratio<1
        r=datasample(random_number,sum(R)); % random values as size of true values
        r=r<abs(1/(income_ratio*delta)-1); % random < |1/(ratio*0.8) - 1|
        Work_places(F(r),7)=0; % update to unoccupied
        lost_job_id=[lost_job_id;Work_places(F(r),6)]; % append ID of unoccupied workplaces
    end
    
    %% add people to working market
    if income_ratio>1
        F=(Individuals_data(:,6)>1 & Individuals_data(:,12)<1); % not kid and not working
        P=income_ratio-1; 
        if P>=1
            P = 0.8;
        end
        S=round(sum(F)*P); % qualified for work by probability
        F=find(F==1);
        P=datasample(F,S,'replace',false'); % random unique indexes
        % BUG FIX: this used to write Individuals_data(F,12)=1 -- F is the
        % FULL eligible pool (everyone not-kid-and-not-working), not the
        % S-sized random sample P that was just drawn from it. That threw
        % away the intended probability-scaled sizing (S/P) and pushed the
        % ENTIRE eligible pool into job search every time income_ratio>1,
        % e.g. confirmed via diagnostic trace: day 1 eligible=12,676,
        % S=455 intended, but all 12,676 got flipped to status 1 -- this
        % is what created the artificial post-warmup unemployment
        % backlog. Present identically in the untouched reference
        % (run_model_eq.m:472), so it's an original-model bug, not
        % something introduced by this session's tuning.
        Individuals_data(P,12)=1; % 'working status'=1
        % Same col(18) fix as the land-use job-loss site above -- draw a
        % fresh acceptance threshold instead of leaving the stale/
        % un-initialized value (0 for anyone never previously searching).
        Individuals_data(P,18) = rand(length(P),1);
    end

    %% imiggratoin inside ; update agents list and workplaces
    [Assets,HH_data,Individuals_data,Work_places,routine,new_A, HH_MOVE_TRACK]=...
    migration_19(Assets,intra_SA,HH_data,Individuals_data,Work_places,new_A, HH_MOVE_TRACK, Build_Data, real_growth_rate);

    % resSearchLen retry gate (see site 1 above for full explanation).
    % HH_ID_left is normally already [] by this point (both earlier
    % did_not_find_house calls this step reset it) -- kept for
    % defensiveness/consistency in case that ever isn't true.
    if ~isempty(HH_ID_left)
        [locA,~] = ismember(HH_data(:,2), HH_ID_left);
        HH_data(locA,13) = HH_data(locA,13) + 1;
        [~,locB] = ismember(HH_ID_left, HH_data(:,2));
        HH_ID_left = HH_ID_left(HH_data(locB,13) >= resSearchLen);
    end

    if ~isempty(HH_ID_left)

    [~,locTrack] = ismember(HH_ID_left,HH_MOVE_TRACK(:,1));

    HH_MOVE_TRACK(locTrack,6) = 1;

    end

    %% delete HH that left
    [Individuals_data,Work_places,HH_data,Assets,HH_ID_left]=did_not_find_house(HH_ID_left,Individuals_data,Work_places,HH_data,Assets);
    
    %% number of routine per person
    [Individuals_data,id]=new_number_of_routine(Individuals_data,acts,wactsnum,agent_rot,HH_change,routine,Ind_change_routine);
    
    %% new activities locations
    if size(id,1)>0
        [Building_routine_id]=find_activity_location_new_A(Individuals_data,Build_Data,Work_places,HH_data,wact1,wact2,wactsnum,SA,id,Building_routine_id);
        a=ismember(Building_routine_id(:,1),Individuals_data(:,1)); % match agent ID
        Building_routine_id(a==0,:)=[]; % remove unmatched IDs
    end
    
    %% check empty buildings ; 
    [Build_Data,Build_Data_p]=find_empty_buildings(Assets,Build_Data,Build_Data_p); 
    
    %% sas move:
    % calculate building service ratio
    [Build_Data]=building_service_ratio(Build_Data,Build_Data_p,Build_Distance_matrix_400);
    % calculate building service density (land-area, reporting-only)
    [Build_Data]=building_service_density(Build_Data,Build_Data_p,Build_Distance_matrix_400,400);
    m = nanmean(Assets(:,12)); % mean assets price
    s = nanstd(Assets(:,12)); % stdev assets price
    f = Assets(:,12) > (m + 2*s); % price > m+2s
    Assets(f,12) = m + 2.5*s.*rand(sum(f),1); % update price m+2.5s*random

    if length(new_A)==0
        new_A(:,4)=0;
    end
    new_A;
    if mod(i,sa_update_every)==0
        nSA = length(g_sa);
        % VECTORIZED (was: a per-SA loop that re-scanned the FULL
        % Assets/Build_Data/Work_places/Individuals_data/HH_data arrays
        % from scratch for every metric, every SA -- ~20 SAs x ~25
        % metrics of redundant full-array filtering per update. Group
        % indices are computed ONCE and reused via accumarray, which is
        % mathematically identical to the original nanmean/mean/sum over
        % the same boolean masks. nanmean vs plain mean is preserved
        % exactly per-metric to match the original's NaN handling.
        [~, asset_grp] = ismember(Assets(:,1), g_sa);
        [~, build_grp] = ismember(Build_Data(:,4), g_sa);
        [~, wp_grp]    = ismember(Work_places(:,2), g_sa);
        [~, ind_grp]   = ismember(Individuals_data(:,2), g_sa);
        [~, hh_grp]    = ismember(HH_data(:,1), g_sa);

        accsum     = @(grp,val) accumarray(grp(grp>0), val(grp>0), [nSA,1], @sum, 0);
        accnanmean = @(grp,val) accumarray(grp(grp>0), val(grp>0), [nSA,1], @(x) mean(x,'omitnan'), NaN);
        accmean    = @(grp,val) accumarray(grp(grp>0), val(grp>0), [nSA,1], @mean, NaN);

        SA_PRICE(:,i+1) = accnanmean(asset_grp, Assets(:,5));

        res_bld_ids  = Build_Data(Build_Data(:,3)==1 | Build_Data(:,3)==2, 1);
        comm_bld_ids = Build_Data(Build_Data(:,3)>2, 1);
        is_res_asset  = ismember(Assets(:,2), res_bld_ids);
        is_comm_asset = ismember(Assets(:,2), comm_bld_ids);
        house_grp = asset_grp; house_grp(~is_res_asset) = 0;
        comm_grp  = asset_grp; comm_grp(~is_comm_asset) = 0;
        SA_HOUSE(:,i+1)     = accnanmean(house_grp, Assets(:,5));
        SA_COMERCIAL(:,i+1) = accnanmean(comm_grp,  Assets(:,5));

        SA_POP(:,i+1)    = accsum(asset_grp, Assets(:,11));
        SA_ASSETS(:,i+1) = accsum(asset_grp, ones(size(Assets,1),1));

        SA_SERVICE(:,i+1)  = accsum(build_grp, double(Build_Data(:,3)>2));
        SA_RESIDENT(:,i+1) = accsum(build_grp, double(Build_Data(:,3)==1 | Build_Data(:,3)==2));
        area_grp = build_grp; area_grp(Build_Data(:,3)~=3) = 0;
        SA_AREA(:,i+1) = accsum(area_grp, Build_Data(:,25));

        SA_WP(:,i+1) = accsum(wp_grp, ones(size(Work_places,1),1));
        wp7 = Work_places(:,7);
        jobs_num_grp = wp_grp; jobs_num_grp(~(wp7==1 | wp7==3)) = 0;
        jobs_den_grp = wp_grp; jobs_den_grp(wp7==2 | wp7==99) = 0;
        jobs_num = accsum(jobs_num_grp, ones(size(Work_places,1),1));
        jobs_den = accsum(jobs_den_grp, ones(size(Work_places,1),1));
        SA_JOBS(:,i+1) = jobs_num ./ jobs_den;

        ind12 = Individuals_data(:,12);
        ind15 = Individuals_data(:,15);
        working_num_grp = ind_grp; working_num_grp(ind12~=2) = 0;
        working_num = accsum(working_num_grp, ones(size(Individuals_data,1),1));
        SA_WORKING(:,i+1) = working_num ./ jobs_den;

        SA_OUTCOME(:,i+1) = accsum(wp_grp, Work_places(:,8));

        % BUG FIX: see the day-1 SA_LOCAL init above for the full
        % explanation -- col(12)==99 never occurs, so this must read
        % local/outside off col(15) instead.
        local_num_grp = ind_grp; local_num_grp(~(ind12==2 & ind15~=99)) = 0;
        local_den_grp = ind_grp; local_den_grp(ind12~=2) = 0;
        local_num = accsum(local_num_grp, ones(size(Individuals_data,1),1));
        local_den = accsum(local_den_grp, ones(size(Individuals_data,1),1));
        SA_LOCAL(:,i+1) = local_num ./ local_den;

        idle_num_grp = ind_grp; idle_num_grp(ind12~=1) = 0;
        idle_den_grp = ind_grp; idle_den_grp(~(ind12>0)) = 0;
        idle_num = accsum(idle_num_grp, ones(size(Individuals_data,1),1));
        idle_den = accsum(idle_den_grp, ones(size(Individuals_data,1),1));
        SA_IDLE(:,i+1) = idle_num ./ idle_den;

        wage_grp = ind_grp; wage_grp(~(ind15>0 & ind15~=99)) = 0;
        SA_WAGE(:,i+1) = accmean(wage_grp, Individuals_data(:,14));

        hh7 = HH_data(:,7);
        d1=hh_grp; d1(hh7~=1)=0;   SA_FIRST(:,i+1)  = accsum(d1,  ones(size(HH_data,1),1));
        d2=hh_grp; d2(hh7~=2)=0;   SA_SECOND(:,i+1) = accsum(d2,  ones(size(HH_data,1),1));
        d3=hh_grp; d3(hh7~=3)=0;   SA_THIRD(:,i+1)  = accsum(d3,  ones(size(HH_data,1),1));
        d4=hh_grp; d4(hh7~=4)=0;   SA_FOURTH(:,i+1) = accsum(d4,  ones(size(HH_data,1),1));
        d5=hh_grp; d5(hh7~=5)=0;   SA_FIFTH(:,i+1)  = accsum(d5,  ones(size(HH_data,1),1));
        d6=hh_grp; d6(hh7~=6)=0;   SA_SIXTH(:,i+1)  = accsum(d6,  ones(size(HH_data,1),1));
        d7=hh_grp; d7(hh7~=7)=0;   SA_SEVENTH(:,i+1)= accsum(d7,  ones(size(HH_data,1),1));
        d8=hh_grp; d8(hh7~=8)=0;   SA_EIGHTH(:,i+1) = accsum(d8,  ones(size(HH_data,1),1));
        d9=hh_grp; d9(hh7~=9)=0;   SA_NINTH(:,i+1)  = accsum(d9,  ones(size(HH_data,1),1));
        d10=hh_grp; d10(hh7~=10)=0; SA_TENTH(:,i+1)  = accsum(d10, ones(size(HH_data,1),1));

        for g=1:nSA % unique SA ID ; next step calculations
            SA_POP_RATIO(g,i+1)=SA_POP(g,i+1)/SA_POP(g,i);
            SA_ASSET_RATIO(g,i+1)=SA_ASSETS(g,i)/SA_ASSETS(g,i+1);
            SA_SERVICE_RATIO(g,i+1)=SA_SERVICE(g,i+1)/SA_SERVICE(g,i);
            % (population+asset+service)/3
            SA_C=(SA_POP_RATIO(g,i+1)+ SA_ASSET_RATIO(g,i+1)+ SA_SERVICE_RATIO(g,i+1))./3;
            SA_LOGC(g,i+1)=log(SA_C);
            SA_price1(g,i+1)= SA_PRICE(g,i+1).*(1+ SA_LOGC(g,i+1)); % price*(1+log(total ratio))

            b_data=Build_Data(build_grp==g,:); % building list within SA

            % update dynamic commercial-only service ratio col(5)
            com_b=sum(b_data(:,3)>1 & b_data(:,3)<4); % commercial only (usage 2-3)
            res_b=sum(b_data(:,3)==1); % residential (usage 1)
            if res_b==0
                stat_data(stat_data(:,1)==g_sa(g),5)=0;
            else
                stat_data(stat_data(:,1)==g_sa(g),5)=com_b/res_b;
            end

            % update dynamic land-area service density col(8) -- reporting-
            % only, see the init comment above. Land area (col7) is fixed;
            % only the commercial floorspace numerator moves.
            la_g = stat_data(stat_data(:,1)==g_sa(g),7);
            if ~isempty(la_g) && ~isnan(la_g) && la_g>0
                comm_floor_g = sum(b_data(b_data(:,3)>1 & b_data(:,3)<4, 25));
                stat_data(stat_data(:,1)==g_sa(g),8) = comm_floor_g/la_g;
            end

            [locA,~]=ismember(Assets(:,2), b_data(:,1)); % match building ID
            Assets(locA,5) = Assets(locA,5).*(1+ SA_LOGC(g,i+1)); % ppm*(1+log(total ratio))
           
            FLOORSPACE = b_data(:,25); 
            sa_service_ratio = sum(b_data(:,3) >2) / sum(b_data(:,3)<=2); % sum(usage>2)/sum(usage<=2)
            if SA_SERVICE_RATIO(g,i+1) > 0 
                B_SERVICES_RATIO=b_data(:,19)./sa_service_ratio; % (building sevice ratio) / (SA sevice ratio)
            else
                B_SERVICES_RATIO = 0;
            end
            B_VALUE = FLOORSPACE.*SA_price1(g,i+1).*(B_SERVICES_RATIO); % floorspace*mean(ppm)*ratio

         

            %% problem with b value ; % remove zeros
            A=B_VALUE==0;
            B_VALUE(A)=[];
            b_data(A,:)=[];
            FLOORSPACE(A)=[];
            
            %%
            [~,locB]=ismember(b_data(:,1),Build_Data(:,1)); % match building ID
            Build_Data(locB,22) =B_VALUE; % update 'Building value'
            [locA,locB]=ismember(Assets(:,2), b_data(:,1)); % match building ID
            % 'real price' ; (asset area)/(building area) * (building value)
            Assets(locA,12)=(Assets(locA,4)./Build_Data(locB(locB>0),25)).*Build_Data(locB(locB>0),22);
        end

        % refresh service normalization stats from the updated dynamic service ratio
        service_mean = mean(stat_data(:,5));
        service_std  = std(stat_data(:,5));
        if service_std==0
            service_std = eps;
        end
    end
    %% monthly assest cost
    mp = Assets(:,12); 
    mp(isinf(Assets(:,12))) = []; % remove infinite price
    p = nanmean(mp); % mean asset price
    Assets(isinf(Assets(:,12)),12) = p; % update to mean price
    m = nanmean(Assets(:,12)); 
    s = nanstd(Assets(:,12));
    f = Assets(:,12) > (m + 2*s);
    Assets(f,12) = m + 2*s .*rand(sum(f),1);
    Assets(isnan(Assets(:,12)),12) = m; % update to mean price
    [Assets]=monthly_ass_cost(HH_data,Assets,Assets_P,Pa); % 'cost of life'
    
    if size(lost_jobs_B_ID,1) > 0
        Work_places(ismember(Work_places(:,1),lost_jobs_B_ID(:,1)),:) =[]; % remove lost jobs check
    end
    
    % DIAGNOSTIC (one-time, shock day only): compare the same displaced
    % households' building-level service ratio right after destruction
    % (before today's search) vs. right now (after all of today's
    % moving_HH/search logic has run), to test whether same-day
    % reassignment into surviving buildings -- not shelter, not the
    % destruction math itself -- explains the immediate post-shock jump
    % in BuildingServiceRatio_*. Both shelter and pure-destruction-math
    % explanations were already ruled out via isolated tests.
    if i==shock_step && exist('diag_pre_search_hh_ids','var')
        [foundNow, locNow] = ismember(diag_pre_search_hh_ids, HH_data(:,2));
        diag_post_search_building = nan(size(diag_pre_search_hh_ids));
        diag_post_search_building(foundNow) = HH_data(locNow(foundNow), 10);
        [~, locBefore] = ismember(diag_pre_search_building, Build_Data(:,1));
        [~, locAfter] = ismember(diag_post_search_building(foundNow), Build_Data(:,1));
        svc_before = Build_Data(locBefore, 19);
        svc_after = nan(size(diag_pre_search_hh_ids));
        svc_after(foundNow) = Build_Data(locAfter, 19);
        moved_same_day = foundNow & (diag_post_search_building ~= diag_pre_search_building);
        [~, locElderlyDiag] = ismember(diag_pre_search_hh_ids, HH_data(:,2));
        fprintf('\n=== DAY %d SAME-DAY REASSIGNMENT DIAGNOSTIC ===\n', i);
        fprintf('Displaced households: %d | still present today: %d | moved to a different building same-day: %d\n', ...
            numel(diag_pre_search_hh_ids), sum(foundNow), sum(moved_same_day));
        fprintf('Mean building service ratio -- destroyed home (before search): %.4f\n', mean(svc_before, 'omitnan'));
        fprintf('Mean building service ratio -- current building (after today''s search): %.4f\n', mean(svc_after, 'omitnan'));
        fprintf('Mean building service ratio -- MOVED households only, destroyed home: %.4f | new building: %.4f\n', ...
            mean(svc_before(moved_same_day), 'omitnan'), mean(svc_after(moved_same_day), 'omitnan'));
        fprintf('=== END DIAGNOSTIC ===\n\n');
        diag_snapshot_pre = svc_before;
        diag_snapshot_post = svc_after;
        diag_snapshot_moved = moved_same_day;
    end

    % DIAGNOSTIC (one-time, shock day only): full-population decomposition.
    % The displaced-only diagnostic above already showed the displaced
    % subset's own ratio goes DOWN, not up -- so whatever is driving the
    % aggregate increase must be in the non-displaced population (~93% of
    % the city). Compares each household's building-level service ratio
    % from the pre-shock snapshot (captured above, before anything today
    % changed) against right now, split by displaced/non-displaced and by
    % whether their building assignment itself changed today.
    if i==shock_step && exist('diag_allpop_pre_hh_ids','var')
        [foundNowAll, locNowAll] = ismember(diag_allpop_pre_hh_ids, HH_data(:,2));
        allpop_post_building = nan(size(diag_allpop_pre_hh_ids));
        allpop_post_building(foundNowAll) = HH_data(locNowAll(foundNowAll), 10);
        [~, locBuildPost] = ismember(allpop_post_building(foundNowAll), Build_Data(:,1));
        allpop_post_svc = nan(size(diag_allpop_pre_hh_ids));
        allpop_post_svc(foundNowAll) = Build_Data(locBuildPost, 19);
        allpop_post_density = nan(size(diag_allpop_pre_hh_ids));
        allpop_post_density(foundNowAll) = Build_Data(locBuildPost, 26);

        is_displaced = ismember(diag_allpop_pre_hh_ids, shock_displaced_hh_ids);
        nonDisp = foundNowAll & ~is_displaced;
        bldg_unchanged = nonDisp & (allpop_post_building == diag_allpop_pre_building);
        bldg_changed = nonDisp & (allpop_post_building ~= diag_allpop_pre_building);

        fprintf('\n=== DAY %d FULL-POPULATION DECOMPOSITION ===\n', i);
        fprintf('Non-displaced households: %d\n', sum(nonDisp));
        fprintf('  Same building today as yesterday (n=%d): mean svc yesterday=%.4f -> today=%.4f (%.2f%% change)\n', ...
            sum(bldg_unchanged), mean(diag_allpop_pre_svc(bldg_unchanged),'omitnan'), mean(allpop_post_svc(bldg_unchanged),'omitnan'), ...
            100*(mean(allpop_post_svc(bldg_unchanged),'omitnan')-mean(diag_allpop_pre_svc(bldg_unchanged),'omitnan'))/mean(diag_allpop_pre_svc(bldg_unchanged),'omitnan'));
        fprintf('  Building assignment CHANGED today (n=%d, ordinary non-shock moves): mean svc yesterday''s building=%.4f -> today''s new building=%.4f\n', ...
            sum(bldg_changed), mean(diag_allpop_pre_svc(bldg_changed),'omitnan'), mean(allpop_post_svc(bldg_changed),'omitnan'));
        fprintf('  ALL non-displaced combined: mean svc yesterday=%.4f -> today=%.4f (%.2f%% change)\n', ...
            mean(diag_allpop_pre_svc(nonDisp),'omitnan'), mean(allpop_post_svc(nonDisp),'omitnan'), ...
            100*(mean(allpop_post_svc(nonDisp),'omitnan')-mean(diag_allpop_pre_svc(nonDisp),'omitnan'))/mean(diag_allpop_pre_svc(nonDisp),'omitnan'));
        fprintf('Displaced households (n=%d): mean svc yesterday=%.4f -> today=%.4f\n', ...
            sum(is_displaced & foundNowAll), mean(diag_allpop_pre_svc(is_displaced & foundNowAll),'omitnan'), mean(allpop_post_svc(is_displaced & foundNowAll),'omitnan'));
        fprintf('=== END FULL-POPULATION DIAGNOSTIC ===\n\n');

        diag_allpop_post_svc = allpop_post_svc;
        diag_allpop_post_density = allpop_post_density;
        diag_allpop_post_building = allpop_post_building;
        diag_allpop_is_displaced = is_displaced;
    end

    %below, calculations for citywide metrics in metric_track

    elderly    = HH_data(:,5)>=2;
    nonelderly = ~elderly;
    young_old  = HH_data(:,5)==3;
    old_old    = HH_data(:,5)==6;

    % --- SA service ratio per HH (commercial-only dynamic col5) ---
    [~,locStat] = ismember(HH_data(:,1), stat_data(:,1));
    HH_service = stat_data(locStat, 5);

    % --- building service ratio per HH (Build_Data col19) ---
    [~,locBuild] = ismember(HH_data(:,10), Build_Data(:,1));
    HH_build_svc = Build_Data(locBuild, 19);

    % --- SA/building land-area service density per HH (stat_data col8,
    % Build_Data col26) -- reporting-only, see building_service_density.m
    % and the stat_data col7/8 init comment for full rationale ---
    HH_service_density = stat_data(locStat, 8);
    HH_build_density = Build_Data(locBuild, 26);

    % --- sheltered HH: service metrics reflect the SHELTER's location,
    % not their (possibly still-destroyed) original home ---
    if ~isempty(Shelter_HH_Track)
        [sheltered_mask, sheltered_pos] = ismember(HH_data(:,2), Shelter_HH_Track(:,1));
        if any(sheltered_mask)
            shelter_bldg_ids = Shelter_HH_Track(sheltered_pos(sheltered_mask), 2);
            [~, locBuildShelter] = ismember(shelter_bldg_ids, Build_Data(:,1));
            shelter_sa_ids = Build_Data(locBuildShelter, 4);
            [~, locStatShelter] = ismember(shelter_sa_ids, stat_data(:,1));
            HH_service(sheltered_mask)   = stat_data(locStatShelter, 5);
            HH_build_svc(sheltered_mask) = Build_Data(locBuildShelter, 19);
            HH_service_density(sheltered_mask) = stat_data(locStatShelter, 8);
            HH_build_density(sheltered_mask) = Build_Data(locBuildShelter, 26);
        end
    end

    Metric_Track(i,1)  = i;

    % SA service ratio by subgroup
    Metric_Track(i,2)  = mean(HH_service(elderly),    'omitnan');
    Metric_Track(i,3)  = mean(HH_service(nonelderly), 'omitnan');
    Metric_Track(i,26) = mean(HH_service(young_old),  'omitnan');
    Metric_Track(i,27) = mean(HH_service(old_old),    'omitnan');

    % Building service ratio by subgroup
    Metric_Track(i,4)  = mean(HH_build_svc(elderly),    'omitnan');
    Metric_Track(i,5)  = mean(HH_build_svc(nonelderly), 'omitnan');
    Metric_Track(i,28) = mean(HH_build_svc(young_old),  'omitnan');
    Metric_Track(i,29) = mean(HH_build_svc(old_old),    'omitnan');

    % SA/building land-area service density by subgroup (reporting-only)
    Metric_Track(i,42) = mean(HH_service_density(nonelderly), 'omitnan');
    Metric_Track(i,43) = mean(HH_service_density(young_old),  'omitnan');
    Metric_Track(i,44) = mean(HH_service_density(old_old),    'omitnan');
    Metric_Track(i,45) = mean(HH_build_density(nonelderly),   'omitnan');
    Metric_Track(i,46) = mean(HH_build_density(young_old),    'omitnan');
    Metric_Track(i,47) = mean(HH_build_density(old_old),      'omitnan');

    % Population counts
    Metric_Track(i,6)  = sum(elderly);
    Metric_Track(i,7)  = sum(nonelderly);
    % 3-way split: HH_data(:,5) encodes 0=non-elderly, 3=young-old
    % (65-69), 6=old-old (70+) -- confirmed by inspection (only those
    % three values ever occur, and 3+6 sums exactly to the elderly
    % count above). col6 above stays young-old+old-old combined.
    Metric_Track(i,24) = sum(HH_data(:,5)==3); % young-old
    Metric_Track(i,25) = sum(HH_data(:,5)==6); % old-old

    % --- possible assets metrics from Asset_Avail ---
    % Asset_Avail cols: [HH_ID(1) ageGroup(2, 0=non-elderly/3=young-old/6=old-old) n_SA(3) n_city(4) tried_SA(5) tried_city(6) success_SA(7) success_city(8)]
    if size(Asset_Avail,1)>0
        AA_E  = Asset_Avail(:,2)>=3; % elderly combined (young-old + old-old) -- unchanged semantics
        AA_NE = Asset_Avail(:,2)==0;
        AA_YO = Asset_Avail(:,2)==3;
        AA_OO = Asset_Avail(:,2)==6;
        AA_trSA   = Asset_Avail(:,5)==1;
        AA_trCity = Asset_Avail(:,6)==1;
        AA_sucSA  = Asset_Avail(:,7)==1;
        AA_sucCity= Asset_Avail(:,8)==1;

        % raw totals
        Metric_Track(i,8)  = sum(Asset_Avail(AA_E  & AA_trSA,   3), 'omitnan');
        Metric_Track(i,9)  = sum(Asset_Avail(AA_NE & AA_trSA,   3), 'omitnan');
        Metric_Track(i,12) = sum(Asset_Avail(AA_E  & AA_trCity, 4), 'omitnan');
        Metric_Track(i,13) = sum(Asset_Avail(AA_NE & AA_trCity, 4), 'omitnan');
        yo_sa_raw   = sum(Asset_Avail(AA_YO & AA_trSA,   3), 'omitnan');
        oo_sa_raw   = sum(Asset_Avail(AA_OO & AA_trSA,   3), 'omitnan');
        yo_city_raw = sum(Asset_Avail(AA_YO & AA_trCity, 4), 'omitnan');
        oo_city_raw = sum(Asset_Avail(AA_OO & AA_trCity, 4), 'omitnan');

        % normalized (per attempting HH)
        n_SA_E  = sum(AA_E  & AA_trSA);
        n_SA_NE = sum(AA_NE & AA_trSA);
        n_Cy_E  = sum(AA_E  & AA_trCity);
        n_Cy_NE = sum(AA_NE & AA_trCity);
        n_SA_YO = sum(AA_YO & AA_trSA);
        n_SA_OO = sum(AA_OO & AA_trSA);
        n_Cy_YO = sum(AA_YO & AA_trCity);
        n_Cy_OO = sum(AA_OO & AA_trCity);
        if n_SA_E  >0; Metric_Track(i,10)=Metric_Track(i,8) /n_SA_E;  else; Metric_Track(i,10)=NaN; end
        if n_SA_NE >0; Metric_Track(i,11)=Metric_Track(i,9) /n_SA_NE; else; Metric_Track(i,11)=NaN; end
        if n_Cy_E  >0; Metric_Track(i,14)=Metric_Track(i,12)/n_Cy_E;  else; Metric_Track(i,14)=NaN; end
        if n_Cy_NE >0; Metric_Track(i,15)=Metric_Track(i,13)/n_Cy_NE; else; Metric_Track(i,15)=NaN; end
        if n_SA_YO >0; Metric_Track(i,30)=yo_sa_raw/n_SA_YO;     else; Metric_Track(i,30)=NaN; end
        if n_SA_OO >0; Metric_Track(i,31)=oo_sa_raw/n_SA_OO;     else; Metric_Track(i,31)=NaN; end
        if n_Cy_YO >0; Metric_Track(i,32)=yo_city_raw/n_Cy_YO;   else; Metric_Track(i,32)=NaN; end
        if n_Cy_OO >0; Metric_Track(i,33)=oo_city_raw/n_Cy_OO;   else; Metric_Track(i,33)=NaN; end

        % attempt rate within SA: per-SA (SA attempts / HH in SA for subgroup), then averaged
        [~,locAA] = ismember(Asset_Avail(:,1), HH_data(:,2));
        valid_loc = locAA > 0;
        AA_sa_id = zeros(size(Asset_Avail,1),1);
        AA_sa_id(valid_loc) = HH_data(locAA(valid_loc), 1);
        AA_sa_id(~valid_loc) = -1; % sentinel: won't match any real SA
        rate_SA_E  = NaN(length(g_sa),1);
        rate_SA_NE = NaN(length(g_sa),1);
        rate_SA_YO = NaN(length(g_sa),1);
        rate_SA_OO = NaN(length(g_sa),1);
        for g_idx = 1:length(g_sa)
            g_id = g_sa(g_idx);
            e_in_SA  = sum(HH_data(:,1)==g_id & elderly);
            ne_in_SA = sum(HH_data(:,1)==g_id & nonelderly);
            yo_in_SA = sum(HH_data(:,1)==g_id & young_old);
            oo_in_SA = sum(HH_data(:,1)==g_id & old_old);
            e_tried  = sum(AA_sa_id==g_id & AA_E  & AA_trSA);
            ne_tried = sum(AA_sa_id==g_id & AA_NE & AA_trSA);
            yo_tried = sum(AA_sa_id==g_id & AA_YO & AA_trSA);
            oo_tried = sum(AA_sa_id==g_id & AA_OO & AA_trSA);
            if e_in_SA  >0; rate_SA_E(g_idx) =e_tried /e_in_SA;  end
            if ne_in_SA >0; rate_SA_NE(g_idx)=ne_tried/ne_in_SA; end
            if yo_in_SA >0; rate_SA_YO(g_idx)=yo_tried/yo_in_SA; end
            if oo_in_SA >0; rate_SA_OO(g_idx)=oo_tried/oo_in_SA; end
        end
        Metric_Track(i,16) = mean(rate_SA_E,  'omitnan');
        Metric_Track(i,17) = mean(rate_SA_NE, 'omitnan');
        Metric_Track(i,34) = mean(rate_SA_YO, 'omitnan');
        Metric_Track(i,35) = mean(rate_SA_OO, 'omitnan');

        % attempt rate within city: citywide attempts / total subgroup HH
        n_eld = sum(elderly); n_ne = sum(nonelderly);
        n_yo = sum(young_old); n_oo = sum(old_old);
        if n_eld>0; Metric_Track(i,18)=sum(AA_E &AA_trCity)/n_eld; else; Metric_Track(i,18)=NaN; end
        if n_ne >0; Metric_Track(i,19)=sum(AA_NE&AA_trCity)/n_ne;  else; Metric_Track(i,19)=NaN; end
        if n_yo >0; Metric_Track(i,36)=sum(AA_YO&AA_trCity)/n_yo;  else; Metric_Track(i,36)=NaN; end
        if n_oo >0; Metric_Track(i,37)=sum(AA_OO&AA_trCity)/n_oo;  else; Metric_Track(i,37)=NaN; end

        % success rate within SA
        if n_SA_E  >0; Metric_Track(i,20)=sum(AA_E &AA_trSA&AA_sucSA) /n_SA_E;  else; Metric_Track(i,20)=NaN; end
        if n_SA_NE >0; Metric_Track(i,21)=sum(AA_NE&AA_trSA&AA_sucSA) /n_SA_NE; else; Metric_Track(i,21)=NaN; end
        if n_SA_YO >0; Metric_Track(i,38)=sum(AA_YO&AA_trSA&AA_sucSA) /n_SA_YO; else; Metric_Track(i,38)=NaN; end
        if n_SA_OO >0; Metric_Track(i,39)=sum(AA_OO&AA_trSA&AA_sucSA) /n_SA_OO; else; Metric_Track(i,39)=NaN; end

        % success rate within city
        if n_Cy_E  >0; Metric_Track(i,22)=sum(AA_E &AA_trCity&AA_sucCity)/n_Cy_E;  else; Metric_Track(i,22)=NaN; end
        if n_Cy_NE >0; Metric_Track(i,23)=sum(AA_NE&AA_trCity&AA_sucCity)/n_Cy_NE; else; Metric_Track(i,23)=NaN; end
        if n_Cy_YO >0; Metric_Track(i,40)=sum(AA_YO&AA_trCity&AA_sucCity)/n_Cy_YO; else; Metric_Track(i,40)=NaN; end
        if n_Cy_OO >0; Metric_Track(i,41)=sum(AA_OO&AA_trCity&AA_sucCity)/n_Cy_OO; else; Metric_Track(i,41)=NaN; end
    else
        Metric_Track(i,8:23) = NaN;
        Metric_Track(i,8)=0; Metric_Track(i,9)=0;
        Metric_Track(i,12)=0; Metric_Track(i,13)=0;
        Metric_Track(i,30:41) = NaN;
    end

    



end


%% Relocation Metrics

reloc_elderly = HH_MOVE_TRACK(:,3)>=2;
reloc_nonelderly = ~reloc_elderly;

reloc_displaced = HH_MOVE_TRACK(:,5)==1;

reloc_stay_SA = reloc_displaced & ...
    HH_MOVE_TRACK(:,6)==0 & ...
    HH_MOVE_TRACK(:,2)==HH_MOVE_TRACK(:,4);

reloc_move_SA = reloc_displaced & ...
    HH_MOVE_TRACK(:,6)==0 & ...
    HH_MOVE_TRACK(:,2)~=HH_MOVE_TRACK(:,4);

reloc_leave_city = reloc_displaced & ...
    HH_MOVE_TRACK(:,6)==1;


RelocationSummary = [

mean(reloc_stay_SA(reloc_elderly & reloc_displaced))
mean(reloc_move_SA(reloc_elderly & reloc_displaced))
mean(reloc_leave_city(reloc_elderly & reloc_displaced))

mean(reloc_stay_SA(reloc_nonelderly & reloc_displaced))
mean(reloc_move_SA(reloc_nonelderly & reloc_displaced))
mean(reloc_leave_city(reloc_nonelderly & reloc_displaced))

];


uniqueSA = unique(HH_MOVE_TRACK(:,2));

SA_Relocation = nan(length(uniqueSA),7);

for s = 1:length(uniqueSA)

    SA = uniqueSA(s);

    hh = HH_MOVE_TRACK(:,2)==SA & reloc_displaced;

    SA_Relocation(s,1)=SA;

    SA_Relocation(s,2)=mean(reloc_stay_SA(hh));
    SA_Relocation(s,3)=mean(reloc_move_SA(hh));
    SA_Relocation(s,4)=mean(reloc_leave_city(hh));

    hhE = hh & reloc_elderly;

    SA_Relocation(s,5)=mean(reloc_stay_SA(hhE));
    SA_Relocation(s,6)=mean(reloc_move_SA(hhE));
    SA_Relocation(s,7)=mean(reloc_leave_city(hhE));
end

%% Elderly household distribution by SA

elderly = HH_data(:,5)>=2;
nonelderly = ~elderly;

uniqueSA = unique(stat_data(:,1));

SA_Demographics = nan(length(uniqueSA),7);

for s = 1:length(uniqueSA)

    SA = uniqueSA(s);

    hhSA = HH_data(:,1)==SA;

    hhE = hhSA & elderly;

    hhN = hhSA & nonelderly;

    SA_Demographics(s,1) = SA;

    % Number of elderly households
    SA_Demographics(s,2) = sum(hhE);

    % Number of non-elderly households
    SA_Demographics(s,3) = sum(hhN);

    % Total households
    SA_Demographics(s,4) = sum(hhSA);

    % Percent elderly households
    SA_Demographics(s,5) = 100*sum(hhE)/sum(hhSA);

    % Percent non-elderly households
    SA_Demographics(s,6) = 100*sum(hhN)/sum(hhSA);

    % Service ratio of the SA
    SA_Demographics(s,7) = stat_data(stat_data(:,1)==SA,2);

end



Metric_Change = nan(1,18);

% Each delta uses the first and last NON-NaN step for that column, not
% literally row 1 / row end - a single step with zero attempters for a
% subgroup (common for elderly, within-SA) used to NaN out the whole delta.
Metric_Change(1) =endpointDelta(Metric_Track,2);  % SA service ratio delta - elderly
Metric_Change(2) =endpointDelta(Metric_Track,3);  % SA service ratio delta - non-elderly
Metric_Change(3) =endpointDelta(Metric_Track,4);  % building service ratio delta - elderly
Metric_Change(4) =endpointDelta(Metric_Track,5);  % building service ratio delta - non-elderly
Metric_Change(5) =endpointDelta(Metric_Track,6);  % population delta - elderly
Metric_Change(6) =endpointDelta(Metric_Track,7);  % population delta - non-elderly
Metric_Change(7) =endpointDelta(Metric_Track,10); % possible assets SA normalized delta - elderly
Metric_Change(8) =endpointDelta(Metric_Track,11); % possible assets SA normalized delta - non-elderly
Metric_Change(9) =endpointDelta(Metric_Track,14); % possible assets city normalized delta - elderly
Metric_Change(10)=endpointDelta(Metric_Track,15); % possible assets city normalized delta - non-elderly
Metric_Change(11)=endpointDelta(Metric_Track,16); % attempt rate SA delta - elderly
Metric_Change(12)=endpointDelta(Metric_Track,17); % attempt rate SA delta - non-elderly
Metric_Change(13)=endpointDelta(Metric_Track,18); % attempt rate city delta - elderly
Metric_Change(14)=endpointDelta(Metric_Track,19); % attempt rate city delta - non-elderly
Metric_Change(15)=endpointDelta(Metric_Track,20); % success rate SA delta - elderly
Metric_Change(16)=endpointDelta(Metric_Track,21); % success rate SA delta - non-elderly
Metric_Change(17)=endpointDelta(Metric_Track,22); % success rate city delta - elderly
Metric_Change(18)=endpointDelta(Metric_Track,23); % success rate city delta - non-elderly





clearvars -except Assets Assets_P Build_Data Build_Data_p HH_data HH_data_P...
            Individuals_data Individuals_data_P Work_places Work_places_P out_file_name file kk run_uid...
            SA_OUTCOME SA_POP SA_PRICE SA_SERVICE SA_WAGE SA_WP SA_RESIDENT SA_HOUSE SA_COMERCIAL...
            SA_IDLE SA_LOCAL SA_WORKING SA_JOBS SA_FIRST SA_SECOND SA_THIRD SA_FOURTH...
            SA_FIFTH SA_SIXTH SA_SEVENTH SA_EIGHTH SA_NINTH SA_TENTH SA_AREA HH_MOVE_TRACK HH_MOVE_TRACK_P Metric_Track Metric_Track_P SA_Relocation RelocationSummary SA_Demographics Metric_Change...
            wservice wservice_old eld_movef eld_movef_old svc_filter elderly_search_mode steps sa_update_every resSearchLen...
            shock_step shock_snapshot_days...
            diag_snapshot_pre diag_snapshot_post diag_snapshot_moved diag_pre_search_hh_ids...
            diag_allpop_pre_hh_ids diag_allpop_pre_building diag_allpop_pre_svc diag_allpop_post_svc diag_allpop_post_building diag_allpop_is_displaced...
            diag_allpop_pre_density diag_allpop_post_density diag_allpop_pre_group...
            new_jobs_rank_thresh lost_jobs_rank_thresh lu_change_rank_lower lu_change_rank_upper lu_jobs_per_meter lu_potential_jobs_per_meter init_dataset_name commute_outside_rate...
            wage_alfa wage_beta wage_lamda wage_delta...
            subsidy_residents subsidy_pct w_subsidy_eld subsidy_duration HH_subsidy_tracker...
            displaced_shelter agents_per_sqm max_shelter_duration Shelters Shelter_Assign Shelter_HH_Track SA_Shelter_Rank...
            pending_relocation relocation_w_slow relocation_p_slow relocation_p_fast use_staggered_relocation
full_file_name = fullfile(['earthquakeF\',char(out_file_name),' ',num2str(kk),' ',run_uid]);
save(full_file_name);
end


function d = endpointDelta(track, col)
% First non-NaN value in the column subtracted from the last non-NaN
% value. Returns NaN only if the entire column is NaN (subgroup never
% had a valid step all run).
v = track(:,col);
idx = find(~isnan(v));
if isempty(idx)
    d = NaN;
else
    d = v(idx(end)) - v(idx(1));
end
end
