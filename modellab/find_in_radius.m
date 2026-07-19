function [HH_in_R,Assets_in_R,individuals_in_R]=find_in_radius(Distance_matrix,Assets,HH_data,Individuals_data,build_id)
        
buildings=Distance_matrix(Distance_matrix(:,1)==build_id,:); % compare ID for building within radius 400m

%% find Assets in area    
[locA]=ismember(Assets(:,2),buildings); % all assets indexes in current buildings
Assets_in_R=Assets(locA,:); 

%%find HH in Area   
[locA,locB]=ismember(HH_data(:,11),Assets_in_R(:,3)); % all HH matching asset ID
HH_in_R=HH_data(locA,:); 


%% find individuals in Area
[locA,locB]=ismember(Individuals_data(:,3),HH_in_R(:,2)); % all agents that is part og the HH
individuals_in_R=Individuals_data(locA,:);
