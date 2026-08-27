function possible_assets = filter_by_building_service(possible_assets, Build_Data, curr_svc)
% Restrict a candidate-assets pool (col 2 = building ID) to buildings with
% service ratio (Build_Data col 19) >= curr_svc. Used for elderly
% svc_filter, applied uniformly to within-SA and out-of-SA (same-yeshuv /
% other-yeshuv) candidate pools alike.
if size(possible_assets,1)==0
    return
end
[~,locB] = ismember(possible_assets(:,2), Build_Data(:,1));
valid = locB>0;
asset_svc = zeros(size(possible_assets,1),1);
asset_svc(valid) = Build_Data(locB(valid), 19);
possible_assets = possible_assets(asset_svc >= curr_svc, :);
end
