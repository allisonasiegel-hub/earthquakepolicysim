function [Build_Data, Shelters, Shelter_Assign, Shelter_HH_Track, Shelter_Building_Routines, Building_routine_id, forced_release_hh] = ...
    release_shelter_capped(Build_Data, Individuals_data, HH_data, Shelters, Shelter_Assign, Shelter_HH_Track, ...
    Shelter_Building_Routines, Building_routine_id, Assets, recovered_bldgs, max_shelter_duration, i)
% Releases households from shelter under the ORIGINAL rule - home
% building recovered, or the household secured a new asset - plus a
% hard cap: (current step - shelter start step) >= max_shelter_duration
% forces release regardless of housing status. Operates at HOUSEHOLD
% granularity via Shelter_HH_Track (all of a household's members are
% released together), unlike the original per-agent release_shelter.m.
%
% forced_release_hh lists households released ONLY because they hit the
% duration cap (not because they found housing or their home recovered).
% The caller gives these households exactly one more housing-search
% attempt this step, with NO exemption from did_not_find_house if that
% attempt fails - they are treated as ordinary movers from this point,
% matching the "relocate or leave" intent of a hard cap.

    forced_release_hh = [];

    % -- drop stale agents from Shelter_Assign (no longer in the population) --
    if ~isempty(Shelter_Assign)
        keep_mask = ismember(Shelter_Assign(:,1), Individuals_data(:,1));
        Shelter_Assign(~keep_mask,:) = [];
    end

    % -- resolve each currently-sheltered household --
    for k = size(Shelter_HH_Track,1):-1:1
        hh_id      = Shelter_HH_Track(k,1);
        b_id       = Shelter_HH_Track(k,2);
        start_step = Shelter_HH_Track(k,3);

        hh_row = find(HH_data(:,2)==hh_id, 1);
        release_reason = 0; % 0=stay sheltered, 1=home/asset resolved, 2=timed out

        if isempty(hh_row)
            release_reason = 1; % household no longer exists - just clean up bookkeeping
        else
            agent_bldg   = HH_data(hh_row,10);
            asset_id     = HH_data(hh_row,11);
            asset_in_use = ismember(asset_id, Assets(:,3));
            if ismember(agent_bldg, recovered_bldgs) || asset_in_use
                release_reason = 1;
            elseif (i - start_step) >= max_shelter_duration
                release_reason = 2;
            end
        end

        if release_reason > 0
            hh_agents = Individuals_data(Individuals_data(:,3)==hh_id, 1);
            if ~isempty(Shelter_Assign)
                Shelter_Assign(ismember(Shelter_Assign(:,1), hh_agents) & Shelter_Assign(:,2)==b_id, :) = [];
            end
            Shelter_HH_Track(k,:) = [];
            if release_reason == 2
                forced_release_hh = [forced_release_hh; hh_id]; %#ok<AGROW>
            end
        end
    end

    % -- close shelters with nobody left assigned --
    for sidx = size(Shelters,1):-1:1
        b_id = Shelters(sidx,1);
        still_assigned = Shelter_Assign(Shelter_Assign(:,2)==b_id,1);
        if isempty(still_assigned)
            Build_Data(Build_Data(:,1)==b_id,3) = 5; % revert to public
            Shelters(sidx,3) = i; % end step
            k = [];
            if ~isempty(Shelter_Building_Routines)
                k = find([Shelter_Building_Routines{:,1}] == b_id, 1);
            end
            if ~isempty(k)
                orig_rows = Shelter_Building_Routines{k,2};
                for m = 1:size(orig_rows,1)
                    aid = orig_rows(m,1);
                    arow = find(Building_routine_id(:,1)==aid);
                    if ~isempty(arow)
                        Building_routine_id(arow,:) = orig_rows(m,:);
                    end
                end
                Shelter_Building_Routines(k,:) = [];
            end
            Shelters(sidx,:) = [];
        end
    end
end
