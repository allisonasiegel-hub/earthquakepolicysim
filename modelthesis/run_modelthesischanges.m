
%edits include removing commercial submodel, reducing runs, adding in a HH
%move tracker, integrating the new land use change policies


tic
sims=2;
for kk = 1:sims
        %kk;kk
data='data_for_model_Ash2'; data2 = split(data, '_');
file='C:\Users\allis\Documents\MATLAB\testingcodechanges\'; % load and define
load(data);
[sas_data,intra_SA,intra_P]=read_sas_data(file,'sas_national.xlsx'); %SA data
unique_stat=unique(Build_Data(:,4));
intra_SA=intra_SA(ismember(intra_SA(:,1),unique_stat),:);
random_number=rand(size(HH_data,1)*4,1);
comm_policy=0;
min_sal = 5000; % min salary according to BTL in 2017
sims=30;
steps=200; 
hits_ratio = 0.05;
total_hits = floor(size(Build_Data,1)*hits_ratio);
shock=0;
shock_step=90;
RECOVERY = 0.01;
%% Polocies
subsidy_businesses=0; % help business during 
subsidy_residents=0; %
subsidy_amount=750;
subsidy_duration=60;
priority_recovery=0; % faster recovery of residential 
recovery_factor=2.5;
displaced_shelter=1; % shelter policy of public turn to 99
agents_per_sqm=0.2;
commercial_preservation=1;
residential_preservation=1;

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



out_file_name = strcat(data2{end}, {' '}, string(total_hits), suffix);


%% model parameters
acts=3;
wactsnum=3;
wact1=0.5;
wact2=0.5;
Pa=12;
wresd=0.5;
w_dis_job=0.5;

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

%% more model parameters
[commute]=xlsread([file,'commuting.xlsx']);
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
    SA_LOCAL(g,1)=sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==2))/sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==2 | Individuals_data(:,12)==99));
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

buildings_added=0;
destroyed_B=[];
HH_track=zeros(0,2);
Shelters=[];
Shelter_Assign=[];
Shelter_Building_Routines={};
HH_MOVE_TRACK = [];

HH_MOVE_TRACK_P = {...
    'HH_ID', ...
    'Yeshuv', ...
    'BuildingID', ...
    'Timestep', ...
    'Move Type'};


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
            [Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id] = ...
                release_shelter(Build_Data, Individuals_data, HH_data, Shelters, Shelter_Assign,...
                Shelter_Building_Routines, Building_routine_id, Assets, BI, i);
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
    LU=[];new_A=[];new_B=[];HH_change=[];
    new_jobs_work_places=[];HH_ID_left=[];lost_job_id=[];
    HH_destroyed=[];bad_Assets=[];lost_jobs=[];Ind_change_routine=[];
    max_salary = max(Work_places(:,8)); 
    row = find(Work_places(:,8) == max_salary); % index fo max salary
    max_WP_id=Work_places(row(1),6); % id of workplace with max salary
     % columns: [HH_ID, start_day]
    
    %% rockets
    if i>shock_step && buildings_added<=total_hits && total_hits~=0
        % damaged buildings
		num_buildings=randi([0,ceil(total_hits*0.05)]);
        [destroyed_B_P, destroyed_B2]=rocket_attack2(Build_Data, num_buildings); % with clustering
		num_added=min(total_hits - buildings_added,size(destroyed_B2, 1));
		destroyed_B(buildings_added+1:buildings_added+num_added,:)=destroyed_B2(1:num_added,:);
		buildings_added=buildings_added+num_added;

        % bad assets bad assets include destroied assets that were deleted from assets
        if num_buildings>0
            shock=1;
            [bad_Assets,Assets,destroyed_B]=shock_A(Assets,destroyed_B);        
            % HH no house
            HH_destroyed=shock_H(HH_data,Assets);
            
            % working places
            if ~isempty(HH_destroyed)
                destroyed_ids = unique(HH_destroyed(:));
                locA = ismember(HH_data(:,2),destroyed_ids);
                selected_HH = HH_data(locA,:);

                n = size(selected_HH,1);
                move_type = 0; % initial displacement event
                displaced_data = [
                   selected_HH(:,2), ...   % HH ID
                   selected_HH(:,1), ...   % SA
                   selected_HH(:,9), ...   % yeshuv
                   selected_HH(:,10), ...  % building
                   i*ones(n,1), ...        % timestep
                   move_type*ones(n,1)     % move type
                ];

                HH_MOVE_TRACK = [HH_MOVE_TRACK; displaced_data];
            end
            % lost jobs (work places id - to find workers) and delete working places
            [Work_places,lost_jobs]=shock_W(Work_places,destroyed_B);       
            % people loosing work (change from working to looking) and
            % change location and keep track because need to change routine
            [Individuals_data,Ind_change_routine]=shock_I(Individuals_data,lost_jobs);
        end
        if displaced_shelter==1 && ~isempty(HH_destroyed)
            [Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id] = ...
                assign_shelter(Build_Data, Individuals_data, HH_destroyed, Shelters, Shelter_Assign,...
                Shelter_Building_Routines, Building_routine_id, i, agents_per_sqm);
        end
    end

    [HH_data,Individuals_data,HH_track]=HH_subsidy(HH_data,Individuals_data,HH_destroyed,HH_track,subsidy_residents,subsidy_amount,subsidy_duration,i);
    
    moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,2); % K=2
    moving_HH=[moving_HH;HH_destroyed];
    moving_HH=unique(moving_HH);
    if isempty(moving_HH)==0 % assign new asset for agent
        [HH_ID_left,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data]...
            =find_new_house_same_stat(HH_ID_left,pd,HH_data,Individuals_data, ...
            Build_Data,Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change);

        if ~isempty(HH_change)

            moved_hh = unique(HH_change(:,1));

            locA = ismember(HH_data(:,2),moved_hh);

            selected_HH = HH_data(locA,:);

            n = size(selected_HH,1);
            move_type = 1; % earthquake displacement

            relocation_data = [
                selected_HH(:,2), ...
                selected_HH(:,1), ...
                selected_HH(:,9), ...
                selected_HH(:,10), ...
                i*ones(n,1), ...
                ones(n,1)   % move type
            ];

            HH_MOVE_TRACK = [HH_MOVE_TRACK; relocation_data];

        end

    end
    
    moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,3); % K=3

    if isempty(moving_HH)==0
        [HH_ID_left,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data]= ...
            find_new_house_yeshuv(HH_ID_left,pd,HH_data,Individuals_data,Build_Data ...
            ,Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change);
        if ~isempty(HH_change)

            moved_hh = unique(HH_change(:,1));

            locA = ismember(HH_data(:,2),moved_hh);

            selected_HH = HH_data(locA,:);

            n = size(selected_HH,1);
            move_type = 3; % moved to different yeshuv

            relocation_data = [
                selected_HH(:,2), ...
                selected_HH(:,1), ...
                selected_HH(:,9), ...
                selected_HH(:,10), ...
                i*ones(n,1), ...
                ones(n,1)   % move type
            ];

            HH_MOVE_TRACK = [HH_MOVE_TRACK; relocation_data];
    
        end
    end
    
    %% delete HH that left
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

    if i>99999  % after 30 simulation steps
        %% mean visit per building
        MVB30=[VISITS(:,1),nanmean(VISITS(:,2:end),2)];
        % calculate visits by precentile up to 100
        P=[0,prctile(MVB30(:,2),1:100)]; % first element is zero then 101 in total. index shift
        for ppp=1:size(P,2)-1 % Now size-1?
            a=MVB30(:,2)>=P(ppp) &  MVB30(:,2)<P(ppp+1); % locate precentile
            MVB30(a,3)=ppp; % update
        end
        MVB30(MVB30(:,3)==0,3)=100; % update upper precentile
                
        %% mean salary for all buildings withe workers comm only!!!
        %building_average_salary=cal_bui_sa(Work_places,Build_Data); % building sum salary
        building_average_salary=cal_bui_sa_subsidy(Work_places, Build_Data, destroyed_B, subsidy_businesses); % building sum salary
        P=[0,prctile(building_average_salary(:,2),1:100)]; % salary by precentiles
        for ppp=1:size(P,2)-1
            a=building_average_salary(:,2)>=P(ppp) &  building_average_salary(:,2)<P(ppp+1); % locate precentile
            building_average_salary(a,3)=ppp; % update
        end
        % highest score
        building_average_salary(building_average_salary(:,3)==0,3)=100; % update upper precentile
        
        %% empty building or residance - potential salary
        B=Build_Data(Build_Data(:,3)<2,:); % living or combined and no HH
        %% building area floors*area
        workers=ceil((B(:,7).*ceil(B(:,11)).*0.007790361)); % model parameter jobs per comm
        pot_sal_for_B=[B(:,1),workers.*average_wage]; % building ID and total wage
        
        %% find_comm_visit_rank
        [locA,locB]=ismember(building_average_salary(:,1),MVB30(:,1)); % locate building id in visits metrix
        building_average_salary(locA,4)=MVB30(locB(locB>0),3); % col(4) visits ranking
        building_average_salary(:,5)=building_average_salary(:,4)-building_average_salary(:,3); % diff in ranks
        
        %% new jobs - com only 
        % check sensitivity of condition limit
        new_jobs=building_average_salary(building_average_salary(:,5)>20,1); % only rank diff above 20 vector
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
            working99_prob = 1-0.778038196; % Ashkelon commuting 99 probability
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
        lost_jobs_B_ID=building_average_salary(building_average_salary(:,5)<-20,1); % only rank diff below -20 vector
        lost_jobs_B_ID=Build_Data(ismember(Build_Data(:,1),lost_jobs_B_ID),[1,17]); % all matching ID cols(1 and 17)
        [~, newB] = ismember(lost_jobs_B_ID(:,1),Work_places(:,1)); % building ID first index matching
        lost_jobs_WP_ID = Work_places( newB,[1,5]); % current WP count out of avalible by building
        lost_jobs_B_ID = sortrows(lost_jobs_B_ID, 1); % sort to match building ID
        lost_jobs_WP_ID = sortrows(lost_jobs_WP_ID, 1); % sort to match building ID
        lost_jobs_B_ID(:,3)=round(lost_jobs_WP_ID(:,2)-1); % col(3) workplace-1
        newB = ismember(Work_places(:,1),lost_jobs_B_ID(:,1)); % find all building id
        lost_jobs_B_ID(:,4)=lost_jobs_B_ID(:,3)./lost_jobs_B_ID(:,2)<0.5; % normilized value < 0.5
        
        %% people lost job        
        ind_lost_job = ismember(Individuals_data(:,15),lost_jobs_B_ID(:,1)); % 'building_work_place'
        Individuals_data(ind_lost_job,12) = 1; % 'working status' = 1
        Individuals_data(ind_lost_job,15) = 0; % 'building_work_place' = 0
        Individuals_data(ind_lost_job,14) = 0; % 'income' = 0
        
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
        
        Build_Data(ismember(Build_Data(:,1),F) & Build_Data(:,3)==3,3)=0;




        %% delete one job
        % Check if only one job is deleted for each building
        % sort worplaces by building and wage, and delete the lost wage
        F=lost_jobs_B_ID(lost_jobs_B_ID(:,4)==0,1); % value above 0.5 ; workplace/round(worplace-1)
        [~,locB]=ismember(F,Work_places(:,1)); % indexes by matching building ID
        Work_places(locB,7)=2; % 'occupied'=2
        lost_job_id=[lost_job_id;Work_places(locB,6)]; % append rows only col(6) - 'id'
        
        %% commercial potantial change LU
        if  comm_policy==0
            [locA,locB]=ismember(pot_sal_for_B(:,1),MVB30(:,1)); % building ID and total wage ; mean visit per building
            pot_sal_for_B(locA,3)=MVB30(locB(locB>0),3); % new col(3) append mean visits ranking
            Change_LU=[]; 
            for iiiii=1:size(pot_sal_for_B,1)
                A=[building_average_salary(:,2);pot_sal_for_B(iiiii,2)]; % new vector salary by building
                P=[0,prctile(A,1:100)]; % salary by precentiles with new adeed values
                for ppp=1:size(P,2)-1 
                    a=A>=P(ppp) &  A<P(ppp+1); % locate salary ranking
                    if a(end)==1 % break when found ranking
                        break
                    end
                end
                V=pot_sal_for_B(iiiii,3)-ppp; % substruct new rank from old
                if V>20 && V<40
                    Change_LU=[Change_LU;pot_sal_for_B(iiiii,1)]; % save building id ; 20 < diff < 40
                end
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
                    new_A,new_B,Build_Data]...
                    =find_new_house_same_stat(HH_ID_left,pd,HH_data,Individuals_data,Build_Data,...
                    Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change);

                if ~isempty(HH_change)

                    moved_hh = unique(HH_change(:,1));

                    locA = ismember(HH_data(:,2),moved_hh);
        
                    selected_HH = HH_data(locA,:);
        
                    n = size(selected_HH,1);
                    move_type = 2; % land-use conversion displacement
        
                    relocation_data = [
                        selected_HH(:,2), ...
                        selected_HH(:,1), ...
                        selected_HH(:,9), ...
                        selected_HH(:,10), ...
                        i*ones(n,1), ...
                        ones(n,1)   % move type
                    ];
                
                    HH_MOVE_TRACK = [HH_MOVE_TRACK; relocation_data];

                end
            end
            
            %% delete HH that left
            [Individuals_data,Work_places,HH_data,Assets,HH_ID_left]= ...
            did_not_find_house(HH_ID_left,Individuals_data,Work_places,HH_data,Assets);
    
            %% new jobs because of land use
            JOBS_per_meter=0.007790361;
            workers=(New_Comm_B(:,7).*ceil(New_Comm_B(:,11)).*JOBS_per_meter); % Area*roundup(floor)*0.014 ; have col(25) already claculated
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
    commute_outside=0.778038196;
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
    alfa=0.3;%0.4
    beta=0.8;%0.6
    lamda=0.95;%0.25 % Ash: 0.85
    delta=0.75;%0.8 % Ash:0.75
    
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
        Individuals_data(F,12)=1; % 'working status'=1
    end
    
    %% imiggratoin inside ; update agents list and workplaces
    [Assets,HH_data,Individuals_data,Work_places,routine,new_A]=...
    migration_19(Assets,intra_SA,HH_data,Individuals_data,Work_places,new_A);
    
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
    if mod(i,30)==0
        for g=1:length(g_sa) % unique SA ID ; next step calculations
            SA_PRICE(g,i+1)=nanmean(Assets(Assets(:,1)==g_sa(g),5)); % mean 'price M' 
            SA_HOUSE(g,i+1)=nanmean(Assets(ismember(Assets(:, 2),Build_Data(Build_Data(:,3)==1 | Build_Data(:,3)==2,1)) & Assets(:,1)==g_sa(g), 5));
            SA_COMERCIAL(g,i+1)=nanmean(Assets(ismember(Assets(:, 2),Build_Data(Build_Data(:,3)>2,1)) & Assets(:,1)==g_sa(g), 5));
            SA_POP(g,i+1)=sum(Assets(Assets(:,1)==g_sa(g),11)); % sum accupied assests in SA 
            SA_ASSETS(g,i+1)=sum(Assets(:,1)==g_sa(g)); % sum total assets in SA
            SA_SERVICE(g,i+1)=sum(Build_Data(Build_Data(:,4)==g_sa(g),3)>2); % sum all building with usage>2 
            SA_RESIDENT(g,i+1)=sum(Build_Data(Build_Data(:,4)==g_sa(g),3)==1 | Build_Data(Build_Data(:,4)==g_sa(g),3)==2); % sum all residential         
            SA_WP(g,i+1)=sum(Work_places(:,2)==g_sa(g));
            SA_JOBS(g,i+1)=sum(Work_places(:,2)==g_sa(g) & ((Work_places(:,7)==1 | Work_places(:,7)==3)))/sum(Work_places(:,2)==g_sa(g) & (Work_places(:,7)~=2 & Work_places(:,7)~=99));
            SA_WORKING(g,i+1)=sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==2))/sum(Work_places(:,2)==g_sa(g) & (Work_places(:,7)~=2 & Work_places(:,7)~=99));
            SA_LOCAL(g,i+1)=sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==2))/sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==2 | Individuals_data(:,12)==99));
            SA_IDLE(g,i+1)=sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==1))/sum(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,12)>0);
            SA_WAGE(g,i+1)=mean(Individuals_data(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
            SA_OUTCOME(g,i+1)=sum(Work_places(Work_places(:,2)==g_sa(g),8));
            SA_FIRST(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==1);
            SA_SECOND(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==2);
            SA_THIRD(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==3);
            SA_FOURTH(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==4);
            SA_FIFTH(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==5);
            SA_SIXTH(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==6);
            SA_SEVENTH(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==7);
            SA_EIGHTH(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==8);
            SA_NINTH(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==9);
            SA_TENTH(g,i+1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==10);
            SA_AREA(g,i+1)=sum(Build_Data(Build_Data(:,4)==g_sa(g) & Build_Data(:,3)==3, 25));		
            SA_POP_RATIO(g,i+1)=SA_POP(g,i+1)/SA_POP(g,i);
            SA_ASSET_RATIO(g,i+1)=SA_ASSETS(g,i)/SA_ASSETS(g,i+1); 
            SA_SERVICE_RATIO(g,i+1)=SA_SERVICE(g,i+1)/SA_SERVICE(g,i);
            % (population+asset+service)/3
            SA_C=(SA_POP_RATIO(g,i+1)+ SA_ASSET_RATIO(g,i+1)+ SA_SERVICE_RATIO(g,i+1))./3;
            SA_LOGC(g,i+1)=log(SA_C);
            SA_price1(g,i+1)= SA_PRICE(g,i+1).*(1+ SA_LOGC(g,i+1)); % price*(1+log(total ratio))
    
            b_data=Build_Data(Build_Data(:,4)==g_sa(g),:); % building list within SA 
            
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

end
clearvars -except Assets Assets_P Build_Data Build_Data_p HH_data HH_data_P...
            Individuals_data Individuals_data_P Work_places Work_places_P out_file_name file kk...
            SA_OUTCOME SA_POP SA_PRICE SA_SERVICE SA_WAGE SA_WP SA_RESIDENT SA_HOUSE SA_COMERCIAL...
            SA_IDLE SA_LOCAL SA_WORKING SA_JOBS SA_FIRST SA_SECOND SA_THIRD SA_FOURTH...
            SA_FIFTH SA_SIXTH SA_SEVENTH SA_EIGHTH SA_NINTH SA_TENTH SA_AREA HH_MOVE_TRACK HH_MOVE_TRACK_P
full_file_name = fullfile(['rocketF\',char(out_file_name),' ',num2str(kk)]);
save(full_file_name);
end