function site_xy = site_temp_dev_locations(Build_Data, destroyed_B, n_temp_dev_sites, temp_dev_site_coords)
% Picks [X,Y] locations for the fixed n_temp_dev_sites medium-term
% sheltering spaces (tent city/container site/etc.). These are NOT
% buildings - no Build_Data row or distance-matrix entry is created for
% them anywhere in this pipeline. A real location is only needed to
% satisfy "a specific location" per the medium-term sheltering spec.
%
% If temp_dev_site_coords is supplied (n_temp_dev_sites x 2 real [X,Y]
% pairs), those are used directly. Otherwise: ranks SAs by total
% destroyed floor area (any usage type - not just residential) and
% anchors each site at the largest currently-standing building's location
% in one of the top-damaged SAs.
%
% site_xy may have fewer than n_temp_dev_sites rows if fewer SAs have
% damage than sites requested - the caller just gets that many sites.

    if ~isempty(temp_dev_site_coords)
        site_xy = temp_dev_site_coords(1:min(n_temp_dev_sites,size(temp_dev_site_coords,1)), :);
        return
    end

    site_xy = zeros(0,2);
    if isempty(destroyed_B)
        return
    end

    [~, locB] = ismember(destroyed_B(:,1), Build_Data(:,1));
    sa_of_destroyed = Build_Data(locB,4);

    sa_list = unique(sa_of_destroyed);
    sa_damage = zeros(length(sa_list),1);
    for s = 1:length(sa_list)
        sa_damage(s) = sum(destroyed_B(sa_of_destroyed==sa_list(s), 3));
    end
    [~, order] = sort(sa_damage, 'descend');
    top_sa = sa_list(order(1:min(n_temp_dev_sites, length(sa_list))));

    still_standing = ~ismember(Build_Data(:,1), destroyed_B(:,1));
    site_xy = zeros(length(top_sa), 2);
    for s = 1:length(top_sa)
        candidates = Build_Data(Build_Data(:,4)==top_sa(s) & still_standing, :);
        if isempty(candidates)
            candidates = Build_Data(Build_Data(:,4)==top_sa(s), :); % fall back if every building in this SA is currently destroyed
        end
        sizes = candidates(:,7).*ceil(candidates(:,11));
        [~, biggest] = max(sizes);
        site_xy(s,:) = candidates(biggest,5:6);
    end
end
