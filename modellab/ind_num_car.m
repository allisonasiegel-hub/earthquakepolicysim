function [Individuals_data,Individuals_data_P]=ind_num_car(Individuals_data, Individuals_data_P,HH_data)
[~,locB]=ismember(Individuals_data(:,3),HH_data(:,2));
Individuals_data(:,19)=HH_data(locB,8);
Individuals_data_P=[Individuals_data_P,'cars'];