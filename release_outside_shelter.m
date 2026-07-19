function [HH_data, Sheltered_Outside, released_hh] = release_outside_shelter( ...
    HH_data, Assets, recovered_bldgs, Sheltered_Outside)
% Releases households sheltered "outside the city" (the shelter-capacity
% overflow pool - see shelter_policy_extensions_handoff.md item 5) once
% they secure a new asset or their original home building recovers. No
% duration cap here - unlike the in-city shelter's max_shelter_duration,
% this pool has no capacity constraint to force a cutoff.
%
% Sheltered_Outside cols: [HH_ID, start_step, income_penalty_amount].
% income_penalty_amount is the exact dollar amount that was deducted from
% HH_data(:,6) when the household entered this state (stylized commute
% penalty) - restored here on release so it isn't compounded with any
% wage changes that occurred while the household was away.

    released_hh = [];
    keep_mask = true(size(Sheltered_Outside,1),1);

    for k = 1:size(Sheltered_Outside,1)
        hh_id   = Sheltered_Outside(k,1);
        penalty = Sheltered_Outside(k,3);

        hh_row = find(HH_data(:,2)==hh_id, 1);
        if isempty(hh_row)
            keep_mask(k) = false; % household no longer exists - clean up bookkeeping
            continue
        end

        agent_bldg   = HH_data(hh_row,10);
        asset_id     = HH_data(hh_row,11);
        asset_in_use = ismember(asset_id, Assets(:,3));

        if ismember(agent_bldg, recovered_bldgs) || asset_in_use
            HH_data(hh_row,6) = HH_data(hh_row,6) + penalty; % restore stylized commute penalty
            released_hh = [released_hh; hh_id]; %#ok<AGROW>
            keep_mask(k) = false;
        end
    end

    Sheltered_Outside = Sheltered_Outside(keep_mask,:);
end
