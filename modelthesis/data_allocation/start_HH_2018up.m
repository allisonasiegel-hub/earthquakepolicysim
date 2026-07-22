function start_HH_2018(file)
%% find number of HH
load buildings&assets.mat

%% read stat data 
[sa_data,sa_data_P]=xlsread([file,'sa_data_b7.csv']);

%% fill empty data with mean data
for j=2:size(sa_data,2)
    M=nanmean(sa_data(:,j));
    a=isnan(sa_data(:,j));
    sa_data(a,j)=M;
end

%% derive missing metro-zone commuting shares (comm31/comm34/comm99)
% comm31 and comm34 come out all-NaN for SAs already inside metro zone 31
% (the census extract has no transition data for them, so the mean-fill
% above can't help either). comm99 = share working OUTSIDE the locality
% (verified against tv_sa_data.csv's WrkOutLoc_pcnt, an exact per-SA
% match) is the only populated column of the three. comm31 = share
% working WITHIN the locality, i.e. its complement; commuting to the
% other metro zone (comm34) has no data for this region, so it defaults
% to 0. Values are fractions (0-1), not percentages.
c31=find(strcmp(sa_data_P(1,:),'comm31'),1);
c34=find(strcmp(sa_data_P(1,:),'comm34'),1);
c99=find(strcmp(sa_data_P(1,:),'comm99'),1);
if ~isempty(c31) && ~isempty(c99)
    a=isnan(sa_data(:,c31));
    sa_data(a,c31)=1-sa_data(a,c99);
end
if ~isempty(c34)
    sa_data(isnan(sa_data(:,c34)),c34)=0;
end

%% find working stats
u=unique(Build_Data(:,4));
locA=ismember(sa_data(:,1),u);
sa_data=sa_data(locA,:);
    
%% determine number of synthetic households per SA
% FIX: the number of households should be controlled by the census/SA data,
% not by the number of generated assets. Assets are the housing stock;
% households are the population demand.
pop_cols={'demog_yishuv.age_0_14','demog_yishuv.age_15_19', ...
    'demog_yishuv.age_20_29','demog_yishuv.age_30_64', ...
    'demog_yishuv.age_65_up'};

pop_idx=[];
for pc=1:length(pop_cols)
    c=find(strcmp(sa_data_P(1,:),pop_cols{pc}),1);
    if ~isempty(c)
        pop_idx=[pop_idx,c];
    end
end
avg_hh_idx=find(strcmp(sa_data_P(1,:),'households.size_avg'),1);

data=[];
for i=1:size(sa_data,1)
    stat=sa_data(i,1);
    num_ass=sum(Assets(:,1)==stat);

    if ~isempty(pop_idx) && ~isempty(avg_hh_idx)
        total_pop=sum(sa_data(i,pop_idx),'omitnan');
        avg_hh_size=sa_data(i,avg_hh_idx);
        if total_pop>0 && avg_hh_size>0
            occupied_ass=round(total_pop/avg_hh_size);
        else
            occupied_ass=num_ass;
        end
    else
        % Fallback for older input files without corrected age/HH-size fields.
        occupied_ass=num_ass;
        total_pop=NaN;
    end

    % Do not force occupied_ass to equal num_ass. If there are surplus assets,
    % they remain vacant. If assets are missing, distribute_HH_2019 will first
    % use same-SA assets and only then relax to the city/yeshuv.
    % 3rd column (total_pop) is used by create_HH_12_2018.m to convert the
    % young-old/old-old split onto a population-level (not household-level)
    % percentage basis.
    data=[data;[stat,occupied_ass,total_pop]];
end

%% data includes zone, num hh/1000, pop size, number  hh 2008, number of HH 2014,
%% HH parameters
total_65='demog_yishuv.age_65_up';
HH_65_pcnt='households.hh65_pcnt';
HH_65_alone='Ages.65LiveAlone65_pcnt';
institute_65='Ages65.LiveInstM_pcnt';
HH_70_79_pcnt='demog_yishuv.age_70_79_pcnt';
HH_80_pcnt='demog_yishuv.age_80_pcnt';
HH1='households.size1_pcnt';
HH2='households.size2_pcnt';
HH3='households.size3_pcnt';
HH4='households.size4_pcnt';
HH5='households.size5_pcnt';
HH6='households.size6_pcnt';
HH7='households.size7up_pcnt';
HH_child_total='households.hh0_17_pcnt';
chil1='households.hh0_17_1_pcnt';
chil2='households.hh0_17_2_pcnt';
chil3='households.hh0_17_3_pcnt';
chil4='households.hh0_17_4_pcnt';
chil5='households.hh0_17_5_pcnt';

[HH_data,old_old_count]=create_HH_12_2018(institute_65,sa_data,sa_data_P,data,total_65,HH_65_pcnt,HH_65_alone,HH_70_79_pcnt,HH_80_pcnt,HH1,HH2,...
    HH3,HH4,HH5,HH6,HH7,HH_child_total,...
    chil1,chil2,chil3,chil4,chil5);
% HH_data - stat, HH ID, Individuals, childrens, old
% old_old_count - [HH_ID, count of 75+ members], additive/kept separate
% from HH_data so it never collides with the fixed-index columns
% (income/asiron/cars/yeshuv/building/asset) added later in the pipeline.

clearvars -except HH_data sa_data sa_data_P data file old_old_count
%% individuals
[Individuals_data,is_old_old]=set_Ind_data(HH_data,old_old_count);
% is_old_old_lookup: [ind_id, is_old_old flag], keyed the same way
% create_disa.m is about to mint ind_id (sequential 1:N on current row
% order) -- kept separate from Individuals_data for the same reason as
% old_old_count above (labor_datasample.m regroups/reorders rows later,
% so anything merged in now would need to survive that reorder).
is_old_old_lookup=[(1:length(is_old_old))',is_old_old];
%% disabilitie
dis1='disabilities.hear5_pcnt';  
dis2='disabilities.see5_pcnt';
dis3='disabilities.remember5_pcnt';
dis4='disabilities.dress5_pcnt';
dis5='disabilities.walk5_pcnt';
stat='locality_stat';
Individuals_data=create_disa(sa_data_P,sa_data,Individuals_data,dis1,dis2,dis3,dis4,dis5,stat);
Individuals_data_P={'ind id','stat','HH id','individuals in family','kids in family ','age - 1-kid,2 adult, 3-old',...
   'disability_hear','disability_see',...
    'disability_reme','disability_dress','disability_walk'};
%% labor
stat_Labor_Force='LaborForce.LaborForceY_pcnt'; % want to work
stat_Labor_work='LaborForce.Wrk2008Y_pcnt'; % work
income1='income.q1';income2='income.q2';income3='income.q3';
income4='income.q4';income5='income.q5';income6='income.q6';
income7='income.q7';income8='income.q8';income9='income.q9';
 income10='income.q10';

[Individuals_data,Individuals_data_P]=labor_datasample(Individuals_data_P,sa_data_P,sa_data,Individuals_data,stat_Labor_Force,stat_Labor_work...
,income1,income2,income3,income4,income5,income6,income7,income8,income9,income10);    

income_p=xlsread([file,'Income_zidon.xlsx']);
for i=2:11
    inc=income_p(i,2):income_p(i,3);
    asiron=Individuals_data(:,13)==i-1;
    Individuals_data(asiron,14)=datasample(inc,sum(asiron));
end
Individuals_data_P=[Individuals_data_P,'income'];

HH_data_P ={ 'stat', 'HH ID', 'Individuals', 'childrens', 'number of old people'};

%% HH income
works=Individuals_data(:,14)>0;
[u1,~,~]=unique(Individuals_data(works,3)); %% HH id
[~, idx]=histc(Individuals_data(works,3),u1); %# get the count of elements
binsums = accumarray(idx,Individuals_data(works,14));
[locA,~]=ismember(HH_data(:,2),u1);
HH_data(locA,6)=binsums;
HH_data_P =[HH_data_P,'HH_income'];
%% HH asiron
[HH_data,HH_data_P]=income2asiron(HH_data,HH_data_P,[file,'Income_zidon.xlsx']);
% number of cars for HH
[HH_data,HH_data_P]=car_number(HH_data,HH_data_P,sa_data);

clearvars -except HH_data sa_data sa_data_P Individuals_data_P Individuals_data HH_data_P old_old_count is_old_old_lookup

save('HH_&_ind_data.mat')
