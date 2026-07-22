function [Individuals_data,Individuals_data_P]=working_pref(Build_Data,Individuals_data,Individuals_data_P,HH_data,w_dis_job)
% w_dis_job=model parameter
% dis_job=distance between job to work place
% I_job = individual salary
% minI= min salary in the world
% maxI = max salary in world

%% working individuals
% find working individuals use only them
ind=Individuals_data;
ind(:,18)=1:size(ind,1);
ind=ind(ind(:,12)==2,:);
if isempty(ind)
    Individuals_data_P = [Individuals_data_P, 'pref'];
    return;
end
% delete working individuals when working outside
ind(ind(:,16)==99,:)=[];
if isempty(ind)
    Individuals_data_P = [Individuals_data_P, 'pref'];
    return;
end
%% find HH ID - house locations and work locations
% find working individuals houses - buildings- locations
[locA,locB]=ismember(ind(:,3),HH_data(:,2));
ind_houses=HH_data(locB(locB>0),10); % find HH(individual) house id
[locA,locB]=ismember(ind_houses,Build_Data(:,1)); 
ind_house_xy=Build_Data(locB(locB>0),5:6);

% working locations
[locA,locB]=ismember(ind(:,15),Build_Data(:,1)); 
ind_works_xy=Build_Data(locB(locB>0),5:6); % work place xy

%% THE equation
dis_job=sqrt((ind_house_xy(:,1)-ind_works_xy(:,1)).^2+(ind_house_xy(:,2)-ind_works_xy(:,2)).^2);
salaries_I=ind(:,14);
min_I=min(ind(:,14));
max_I=max(ind(:,14));
max_D=max(dis_job);
if max_D==0
    max_D=eps;
end

% calculate pref
A=(dis_job./max_D)* w_dis_job;
B=1-w_dis_job;
M=max_I-min_I;
if M==0
    M=eps;
end
c0=salaries_I-min_I;
c1=c0/M;
C=1-c1;

pref=A+B*C;

Individuals_data(ind(:,18),18)=pref;
Individuals_data_P=[Individuals_data_P,'pref'];
