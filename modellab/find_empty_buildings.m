function [Build_Data,Build_Data_p]=find_empty_buildings(Assets,Build_Data,Build_Data_p)
% find occupied assets and thier buildings
[locA,locB]=ismember(Build_Data(:,1),Assets(Assets(:,11)==1,2)); % match building ID only for occupied assets

if size(Build_Data_p,2)==17
    Build_Data_p=[Build_Data_p,'empty']; % set header
end
Build_Data(:,18)=locA; % col(18) set occupied assets True
a=Build_Data(:,3)>1; % all usage excluding living
Build_Data(a,18)=1; % set all but living True
Build_Data(Build_Data(:,18)==0,3)=0; % 'Usage'=0

Build_Data(:,18)=abs(Build_Data(:,18)-1); % invert col(18)
