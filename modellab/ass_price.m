function [Build_Data,Build_Data_p,Assets,Assets_P]=ass_price(Build_Data,Build_Data_p,stat_service_ratio,Assets,Assets_P)

for i=1:size(stat_service_ratio,1) % run for all stat areas
    % 4 - 'SAID' ; 1 - 'stat'
    FFF=find(Build_Data(:,4)==stat_service_ratio(i,1)); % find the index for matching SA in ratio
    %% assets mean price
    %  1 - 'stat' ;  1 - 'stat' ; 5 - 'price M'
    mean_price= nanmean(Assets(Assets(:,1)==stat_service_ratio(i,1),5)); % mean price for all matching assets in SA
    %% building size
    B_size =Build_Data(FFF,25); % col(25) floorsize ; no header after col(21)
    B_pric=B_size*mean_price; % floor price
    %% building service ratio
    % 19 - 'service ratio'
    B_service_area=Build_Data(FFF,19); % new vector for building service ratio
    B_service_area_ratio= B_service_area./max(stat_service_ratio(i,2), eps); % (building service ratio)/(SA service ratio)

    %% normalization building service ratio
    B_service_area_ratio(B_service_area_ratio<0.5)=0.5; % set 0.5 as lower limit
    B_service_area_ratio(B_service_area_ratio>2)=2; % set 2 as upper limit

    %% building value
    B_value=B_pric.*B_service_area_ratio; % (floor price)*(normilized ratio)
    Build_Data(FFF,22)=B_value; % col(22) adapted floor price
    
   %% assets prices - area/building price*building size
    B_id=[Build_Data(FFF,[1,22]),B_size]; % building ID, price, size
    [locA,locB]=ismember(Assets(:,2),B_id(:,1)); % match building id and save index
    
    % col(12) = (asset size)/(floor zise)*(building value)
    Assets(locA,12)=Assets(locA,4)./B_id(locB(locB>0),3).*B_id(locB(locB>0),2);
    %%%%
end

Build_Data_p=[Build_Data_p,'Building value']; % add header for col(22)
Assets_P=[Assets_P,'real price']; % add header for col(12)

m = nanmean(Assets(:,12)); % mean asset price
s = nanstd(Assets(:,12)); % standard deviation for asset price
f = Assets(:,12) > (m + 2*s); % binary vector
Assets(f,12) = m + 2.5*s .*rand(sum(f),1); % replace with new value based on random
end