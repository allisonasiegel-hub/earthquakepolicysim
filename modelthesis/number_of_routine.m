function [Individuals_data,Individuals_data_P]=number_of_routine(Individuals_data,Individuals_data_P,acts,W_acts_num)

s=size(Individuals_data,1); % returns the number of culumns in data set
R=rand(s,1); % random matrix 

%% THE equation
% data for equation
% 12 - 'working status'
work=Individuals_data(:,12)==2; % a[i]=true if col(12)=2, else a[i]=false
% 7-11 - 'disability_hear'	'disability_see'	'disability_reme'	'disability_dress'	'disability_walk'
disability=sum(Individuals_data(:,7:11),2)>0; % a[i]=true if sum for all rows within cols(7 to 11) is positive
% 6 - 'age - 1-kid,2 adult, 3-old'
age_1or3=Individuals_data(:,6)~=2; % a[i]=true if col(6) is kid or old
age_2=Individuals_data(:,6)==2; % adults
% 19 - 'cars'
car=Individuals_data(:,19)>0; % a[i]=true if col(19) is positive
% 16 - 'stat_work_place'
work_in=Individuals_data(:,16)~=99 & Individuals_data(:,16)>0; % a[i]=true if col(16) neq 99 and positive

% calculation of equation
a1=work./2; % 0.5 if true and 0 if false
a11=acts-a1; % sub a1 form acts 
a2=a11.*R.*2; % fill Random matrix with pruduct of a11*2*R[i][j]
% (1+car/3)*(1-dis/3)*(1+age(2)/3)*(1-age(!2)/3)
b_car = 1+car/W_acts_num; 
b_dis = 1-disability/W_acts_num; 
b_age_2 = 1+age_2/W_acts_num; 
b_age_1or3 = 1-age_1or3/W_acts_num; 
I = round(a2.*b_car.*b_dis.*b_age_2.*b_age_1or3); 
I = I + work_in; 

Individuals_data(:,20)=I; % append new col(20) to data
Individuals_data_P=[Individuals_data_P,'number_of_activities']; % append col(20) name