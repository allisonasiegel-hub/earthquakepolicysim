function [bad_Assets, Assets,destroyed_B]=shock_A(Assets,destroyed_B)
loca=ismember(Assets(:,2),destroyed_B(:,1)); % locate all assets in destroyed building
bad_Assets=Assets(loca,:); % all bad assets
Assets(loca,:)=[]; % clear bad assets

%% sum floor size for buildings
[u1,~,~]=unique(bad_Assets(:,2)); % unique building id
[~, idx]=histc(bad_Assets(:,2),u1); % get the count of elements
binsums = accumarray(idx,bad_Assets(:,4)); % sum bad assets area by histogram index
[locA,~]=ismember(destroyed_B(:,1),u1); % locate all destroyed buildings
% destroyed_B(locA,3)=binsums;
bad_Assets(:,11)=0; % reset occupied

