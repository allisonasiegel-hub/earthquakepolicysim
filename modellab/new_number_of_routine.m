function  [Individuals_data,IDS]=new_number_of_routine(Individuals_data,acts,W_acts_num,agent_rot,HH_change,routine,Ind_change_routine)

I=Individuals_data(ismember(Individuals_data(:,3),HH_change),1); % agent ID match
IDS=unique([agent_rot;Ind_change_routine;routine;I]); % all agents ID
IDS=IDS(ismember(IDS,Individuals_data(:,1))); % Agent ID match
ID_data=Individuals_data(ismember(Individuals_data(:,1),IDS),:); % Agents data

%% same as number_of_routine

s=size(ID_data,1); 
R=rand(s,1); % random matrix 
work=ID_data(:,12)==2; % all 'working status'=2
disability=sum(ID_data(:,7:11),2)>0; % any disability
age_1or3=ID_data(:,6)~=2; % kid or old
age_2=ID_data(:,6)==2; % adult
car=ID_data(:,19)>0; % have car
work_in=ID_data(:,16)~=99 & ID_data(:,16)>0; % working inside world

a1=work./2;
a11=acts-a1; % acts=3
a2=a11.*R.*2;
% (1+car/3)*(1-dis/3)*(1+age(2)/3)*(1-age(!2)/3)
b_car = 1+car/W_acts_num; 
b_dis = 1-disability/W_acts_num; 
b_age_2 = 1+age_2/W_acts_num; 
b_age_1or3 = 1-age_1or3/W_acts_num; 
I = round(a2.*b_car.*b_dis.*b_age_2.*b_age_1or3); 
I = I + work_in; 
Individuals_data(ismember(Individuals_data(:,1),IDS),20)=I; % update 'number_of_activities'