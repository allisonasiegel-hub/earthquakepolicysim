
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
shock_step=900;
RECOVERY = 0.01;
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
displaced_shelter=1; % toggle: 0=off (baseline), 1=on - shelter policy of public turn to 99
agents_per_sqm=0.2;
% max_shelter_duration: hard cap (steps) on how long a household may stay
% sheltered before being forced to relocate-or-leave. Placeholder value -
% not yet set through sensitivity testing.
max_shelter_duration=120;
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

if ~exist('eld_movef','var'); eld_movef=1; end %reduction in movement for elderly; allow a sweep driver to pre-set this
if ~exist('svc_filter','var'); svc_filter=0; end % building service ratio filter for within-SA elderly pool (0=off, 1=on)
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

HH_MOVE_TRACK = [...
    HH_ORIGINAL,...
    nan(size(HH_ORIGINAL,1),1),...   % Final SA
    zeros(size(HH_ORIGINAL,1),1),... % Displaced (0/1)
    zeros(size(HH_ORIGINAL,1),1)];   % Left city (0/1)


HH_MOVE_TRACK_P = {

'HH_ID',...
'Original_SA',...
'Elderly_Count',...
'Final_SA',...
'Displaced',...
'Left_City'

};

% HH_MOVE_TRACK columns:
% 1 HH ID
% 2 Original SA
% 3 Elderly count
% 4 Final SA
% 5 Displaced
% 6 Left city
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
Metric_Track = nan(steps,41);

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
'SuccessRate_City_OldOld'
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
        recovery_rate=RECOVERY*ones(size(destroyed_B,1),1);    
        if priority_recovery==1
            [~, idx_in_build]=ismember(destroyed_B(:,1),Build_Data(:,1));
            usg=Build_Data(idx_in_build,3);          
            recovery_rate(usg==1)=RECOVERY*recovery_factor; % priority for residential
        end    
        destroyed_B(:,2)=destroyed_B(:,2)+recovery_rate.*destroyed_B(:,3);    
        f=destroyed_B(:,2)>=destroyed_B(:,3);
        BI=destroyed_B(f,1); 
        destroyed_B(f,:)=[]; % remove all recovered
        if size(bad_Assets,1)>0 % bad assets remaining 
            loca=ismember(bad_Assets(:,2),BI); % indexes of recovered
            Assets=[Assets;bad_Assets(loca,:)]; % return recovered to avalible list
            bad_Assets(loca,:)=[]; % clear recovered
        end      
        Work_places=new_works_after_recovery(Work_places,Build_Data,BI,average_wage,std_wage);
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
    % damage table at [file,'earthquake_damage.csv'] - see earth_quake.m.
    if i==shock_step && shock==0
        shock=1;
        [destroyed_B_P, destroyed_B] = earth_quake(Build_Data, [file,'earthquake_damage.csv']);
        [bad_Assets,Assets,destroyed_B]=shock_A(Assets,destroyed_B);
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

    [HH_data,HH_subsidy_tracker]=HH_subsidy_pct(HH_data,HH_destroyed,HH_subsidy_tracker,subsidy_residents,subsidy_pct,w_subsidy_eld,subsidy_duration,i);

    % HH still waiting in shelter after this step's releases/new
    % assignments above - these retry the within-SA search every step
    % (from their original SA/building, since HH_data still points there)
    % until they find housing or their home recovers. forced_release_hh
    % (set above by release_shelter_capped) are NOT exempt from deletion
    % below if this attempt fails - the duration cap means relocate-or-leave.
    still_sheltered_hh = Shelter_HH_Track(:,1);

    moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,2,eld_movef); % K=2, probability of moving within SA
    moving_HH=[moving_HH;HH_destroyed;still_sheltered_hh;forced_release_hh];
    moving_HH=unique(moving_HH);
    if isempty(moving_HH)==0 % assign new asset for agent
        [HH_ID_left,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]...
            =find_new_house_same_stat(HH_ID_left,pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data, ...
            Build_Data,Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change,Asset_Avail,svc_filter);

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

    moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,3,eld_movef); % K=3, probability of moving within the city

    if isempty(moving_HH)==0
        [HH_ID_left,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data,Asset_Avail]= ...
            find_new_house_yeshuv(HH_ID_left,pd,wservice,wservice_old,service_mean,service_std,stat_data,HH_data,Individuals_data,Build_Data ...
            ,Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change,Asset_Avail);
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
    if ~exist('lost_jobs_rank_thresh','var'); lost_jobs_rank_thresh=-60; end    % rank diff below this -> delete building's workplaces entirely
    if ~exist('lu_change_rank_lower','var'); lu_change_rank_lower=40; end       % Change_LU band lower bound
    if ~exist('lu_change_rank_upper','var'); lu_change_rank_upper=60; end       % Change_LU band upper bound

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
        if ~exist('lu_potential_jobs_per_meter','var'); lu_potential_jobs_per_meter=JobsPerM_comm_loaded; end % dynamically loaded, city-correct
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
                    Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change,Asset_Avail,svc_filter);

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
            if ~exist('lu_jobs_per_meter','var'); lu_jobs_per_meter=JobsPerM_comm_loaded; end % dynamically loaded, city-correct
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
    % wage_lamda default changed from 0.95 -> 0.55: a late-period OAT
    % sweep (land-use activity frozen, day 360+) found lamda controls the
    % sign of the persistent post-freeze wage drift via the 1/lamda
    % exponent on income_ratio -- 0.95 gave a small but permanent decline
    % (-0.49% over days 360-550), 0.55 was the closest-to-flat value
    % actually tested (+0.24%). alfa/beta/delta showed no comparably
    % clean lever (alfa provably can't matter once land-use freezes,
    % since floor_ratio's base is exactly 1 then; beta/delta showed real
    % but non-monotonic sensitivity, not a usable dial).
    if ~exist('wage_lamda','var'); wage_lamda=0.55; end
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
            wservice wservice_old eld_movef svc_filter steps sa_update_every resSearchLen...
            new_jobs_rank_thresh lost_jobs_rank_thresh lu_change_rank_lower lu_change_rank_upper lu_jobs_per_meter lu_potential_jobs_per_meter init_dataset_name commute_outside_rate...
            wage_alfa wage_beta wage_lamda wage_delta...
            subsidy_residents subsidy_pct w_subsidy_eld subsidy_duration HH_subsidy_tracker...
            displaced_shelter agents_per_sqm max_shelter_duration Shelters Shelter_Assign Shelter_HH_Track SA_Shelter_Rank
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
