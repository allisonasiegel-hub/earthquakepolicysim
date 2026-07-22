function [Individuals_data,work_places,HH_data,Assets_data,HH_ID_left]=did_not_find_house(FFF1,Individuals_data,work_places,HH_data,Assets_data)
%% if did not find house delete
FFF1=unique(FFF1);
if ~isempty(FFF1)
    for i=1:length(FFF1)
        HH_ID=FFF1(i);
        %% delete working places
        wp=Individuals_data(Individuals_data(:,3)==HH_ID,17); % 3 - 'HH id'; 17 - 'work_place_id'
        locA=ismember(work_places(:,6),wp); % 6 - 'id'
        work_places(locA,7)=0;
        %% delete individuals
        Individuals_data(Individuals_data(:,3)==HH_ID,:)=[]; % remove rows with HH ID
        A=Assets_data(:,3)==HH_data(HH_data(:,2)==HH_ID,11); % assets occupied by the HH
        Assets_data(A,11)=0; % 'occupied' = 0
        %% delete HH
        HH_data(HH_data(:,2)==HH_ID,:)=[]; % remove rows
        
    end
end
HH_ID_left=[]; % empty list
