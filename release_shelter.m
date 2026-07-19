function [Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, forced_release_hh] = release_shelter( ...
    Build_Data, Individuals_data, HH_data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, Assets, recovered_bldgs, i, max_shelter_duration)
% Releases agents from shelter after home recovery or when new assets become
% available. Agents are also released once their household secures any asset
% from the available list. Shelters are closed if no agents remain.
%
% max_shelter_duration (optional, trailing arg - existing callers that omit
% it keep the original no-cap behavior): hard cap (steps) a shelter
% building may stay open. assign_shelter.m never tops up an
% already-designated shelter building, so every agent ever assigned to a
% given building entered on the exact same step - the building's own
% start step (Shelters(:,2)) is an exact proxy for each occupant's
% shelter-entry time, no per-agent tracking needed. Agents released this
% way are reported (at household granularity) in forced_release_hh so the
% caller can give them one final housing-search attempt without exempting
% them from deletion if it fails.

    if nargin < 11 || isempty(max_shelter_duration)
        max_shelter_duration = Inf; % no cap - matches original behavior
    end

    forced_release_hh = [];

    for sidx = size(Shelters,1):-1:1
        b_id       = Shelters(sidx,1);
        start_step = Shelters(sidx,2);
        timed_out  = (i - start_step) >= max_shelter_duration;

        % Remove assignments of agents no longer in the population
        assigned_agents = Shelter_Assign(Shelter_Assign(:,2)==b_id,1);
        keep_mask = ismember(assigned_agents, Individuals_data(:,1));
        if any(~keep_mask)
            stale_agents = assigned_agents(~keep_mask);
            for sa = 1:length(stale_agents)
                idx = (Shelter_Assign(:,1)==stale_agents(sa)) & (Shelter_Assign(:,2)==b_id);
                Shelter_Assign(idx,:) = [];
            end
        end

        % Updated list after removing stale entries
        assigned_agents = Shelter_Assign(Shelter_Assign(:,2)==b_id,1);

        if timed_out
            % duration cap hit: force-release everyone still in this shelter
            agents_to_release = assigned_agents;
            timed_out_agents  = assigned_agents;
        else
            agents_to_release = [];
            timed_out_agents  = [];
            for a = 1:length(assigned_agents)
                agent_row = find(Individuals_data(:,1)==assigned_agents(a), 1);
                if ~isempty(agent_row)
                    agent_hh = Individuals_data(agent_row,3); % scalar
                    hh_row = find(HH_data(:,2)==agent_hh, 1);
                    if ~isempty(hh_row)
                        agent_bldg  = HH_data(hh_row,10);
                        asset_id    = HH_data(hh_row,11);

                        asset_in_use = ismember(asset_id, Assets(:,3));
                        if ismember(agent_bldg, recovered_bldgs) || asset_in_use
                            agents_to_release = [agents_to_release; assigned_agents(a)];
                        end
                    end
                end
            end
        end

        if ~isempty(timed_out_agents)
            hh_forced = unique(Individuals_data(ismember(Individuals_data(:,1), timed_out_agents), 3));
            forced_release_hh = [forced_release_hh; hh_forced];
        end

        % Remove released agents from assignment
        for r = 1:length(agents_to_release)
            idx = (Shelter_Assign(:,1)==agents_to_release(r)) & (Shelter_Assign(:,2)==b_id);
            Shelter_Assign(idx,:) = [];
        end
        still_assigned = Shelter_Assign(Shelter_Assign(:,2)==b_id,1);
        if isempty(still_assigned)
            Build_Data(Build_Data(:,1)==b_id,3) = 5; % revert to public
            Shelters(sidx,3) = i; % end step
            % Optional: Restore building in routines
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

    forced_release_hh = unique(forced_release_hh);
end
