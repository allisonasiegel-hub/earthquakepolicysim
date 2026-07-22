function start_HH_2018(file)
%% find number of HH
load buildings&assets.mat

%% read stat data 
[sa_data,sa_data_P]=xlsread([file,'sas.csv']);

%% fill empty data with mean data
for j=2:size(sa_data,2)
    M=nanmean(sa_data(:,j));
    a=isnan(sa_data(:,j));
    sa_data(a,j)=M;
end
%% find working stats
u=unique(Build_Data(:,4));
locA=ismember(sa_data(:,1),u);
sa_data=sa_data(locA,:);
    
%% randomly choose number of empty assets
empty_ass=normrnd(10,2,[size(sa_data,1),1]);
empty_ass(empty_ass<0)=0;
data=[];
for i=1:size(sa_data,1)
    stat=sa_data(i,1);
    num_ass=sum(Assets(:,1)==stat);
    occupied_ass=num_ass-round(num_ass*empty_ass(i)/100);
    data=[data;[stat,occupied_ass]];   
end

%% data includes zone, num hh/1000, pop size, number  hh 2008, number of HH 2014,
%% HH parameters
total_65='demog_yishuv.age_65_up';
HH_65_pcnt='households.hh65_pcnt';
HH_65_alone='Ages.65LiveAlone65_pcnt';
institute_65='Ages65.LiveInstM_pcnt';
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

HH_data=create_HH_12_2018(institute_65,sa_data,sa_data_P,data,total_65,HH_65_pcnt,HH_65_alone,HH1,HH2,...
    HH3,HH4,HH5,HH6,HH7,HH_child_total,...
    chil1,chil2,chil3,chil4,chil5);
% HH_data - stat, HH ID, Individuals, childrens, old

clearvars -except HH_data sa_data sa_data_P data file
%% individuals
Individuals_data=set_Ind_data(HH_data);
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

income_p=xlsread([file,'Income.xlsx']);
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
[HH_data,HH_data_P]=income2asiron(HH_data,HH_data_P,[file,'Income.xlsx']);
% number of cars for HH
[HH_data,HH_data_P]=car_number(HH_data,HH_data_P,sa_data);

clearvars -except HH_data sa_data sa_data_P Individuals_data_P Individuals_data HH_data_P
  
save('HH_&_ind_data.mat')
