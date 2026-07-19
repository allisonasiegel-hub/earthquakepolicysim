function [Individuals_data,ID_change_routine]=shock_I(Individuals_data,lost_jobs)
loca=ismember(Individuals_data(:,17),lost_jobs);
Individuals_data(loca,15:17)=0;
Individuals_data(loca,12)=1;
%% need to change routine because lost job
ID_change_routine=Individuals_data(loca,1);