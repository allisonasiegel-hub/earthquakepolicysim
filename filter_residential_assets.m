function possible_assets = filter_residential_assets(possible_assets, Build_Data)
% Restricts a candidate-assets pool (Assets rows) to assets whose building
% is still zoned residential (Build_Data(:,3) == 1 or 2, matching
% SA_RESIDENT's own definition of "residential"). A building converted to
% commercial via land-use change should not be re-occupiable until it
% converts back -- the underlying Assets row itself is never deleted, only
% blocked from being assigned while its building isn't residential.
if isempty(possible_assets)
    return
end
[~, locB] = ismember(possible_assets(:,2), Build_Data(:,1)); % col(2) = building id
is_residential = false(size(possible_assets,1),1);
valid = locB > 0;
is_residential(valid) = Build_Data(locB(valid),3) == 1 | Build_Data(locB(valid),3) == 2;
possible_assets = possible_assets(is_residential, :);
end
