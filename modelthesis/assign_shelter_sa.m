function [Build_Data, Shelters, Shelter_Assign, Shelter_HH_Track, Shelter_Building_Routines, Building_routine_id, SA_Shelter_Rank] = ...
    assign_shelter_sa(Build_Data, Individuals_data, HH_data, HH_destroyed, Shelters, Shelter_Assign, Shelter_HH_Track, ...
    Shelter_Building_Routines, Building_routine_id, SA_Shelter_Rank, i, agents_per_sqm)
% Assigns whole displaced households (not individual agents split across
% buildings) to a shelter, sited per SA as the public building nearest
% that SA's largest commercial building (largest by floorspace, col 25).
%
% SA_Shelter_Rank is a ranked candidate list per SA: [SA_id, rank,
% building_id, distance]. It is built once (first call, when empty) by
% build_SA_shelter_rank() below and reused on every subsequent call -
% shelter siting does not change mid-simulation.
%
% Overflow: if an SA's rank-1 candidate is full, the household is placed
% in rank 2 (next-nearest public building to the same commercial anchor),
% then rank 3, etc. If nothing has room for the whole household, it is
% placed in whichever candidate has the most free capacity rather than
% splitting the family across buildings.
%
% Fallback rules baked into build_SA_shelter_rank (see that function):
%  - SA has no public building -> borrow the nearest ALREADY-DESIGNATED
%    shelter from another SA, within 400m if possible, else nearest
%    anywhere.
%  - SA has no commercial building -> same borrowing rule (no anchor to
%    rank this SA's own public buildings against).
%
% Shelter_HH_Track columns: [HH_ID, shelter_building_id, start_step].
% This is the household-level record used by release_shelter_capped.m
% for the max-duration cap and by the caller for the sheltered-household
% retry loop and shelter-location service metrics.

    if isempty(SA_Shelter_Rank)
        SA_Shelter_Rank = build_SA_shelter_rank(Build_Data);
    end

    if isempty(HH_destroyed)
        return
    end

    displaced_ids = unique(HH_destroyed(:));

    for h = 1:length(displaced_ids)
        hh_id = displaced_ids(h);
        hh_row = find(HH_data(:,2)==hh_id, 1);
        if isempty(hh_row)
            continue
        end
        sa_id = HH_data(hh_row,1);
        agent_ids = Individuals_data(Individuals_data(:,3)==hh_id, 1);
        if isempty(agent_ids)
            continue
        end
        n_needed = length(agent_ids);

        ranks = SA_Shelter_Rank(SA_Shelter_Rank(:,1)==sa_id, :);
        ranks = sortrows(ranks, 2);

        placed = false;
        for r = 1:size(ranks,1)
            b_id = ranks(r,3);
            row = Build_Data(:,1)==b_id;
            if ~any(row)
                continue
            end
            capacity = floor(agents_per_sqm * Build_Data(row,7) * Build_Data(row,11));
            free_capacity = capacity - sum(Shelter_Assign(:,2)==b_id);
            if free_capacity >= n_needed
                [Build_Data, Shelters, Shelter_Building_Routines, Building_routine_id] = ...
                    mark_as_shelter_if_new(Build_Data, Shelters, Shelter_Building_Routines, Building_routine_id, b_id, i);
                Shelter_Assign = [Shelter_Assign; [agent_ids, repmat(b_id, n_needed, 1)]];
                Shelter_HH_Track = [Shelter_HH_Track; hh_id, b_id, i];
                placed = true;
                break
            end
        end

        if ~placed && ~isempty(ranks)
            % nothing had room for the whole household - place in the
            % least-full candidate rather than split the family
            best_r = 1; best_free = -inf;
            for r = 1:size(ranks,1)
                b_id = ranks(r,3);
                row = Build_Data(:,1)==b_id;
                if ~any(row)
                    continue
                end
                capacity = floor(agents_per_sqm * Build_Data(row,7) * Build_Data(row,11));
                free_capacity = capacity - sum(Shelter_Assign(:,2)==b_id);
                if free_capacity > best_free
                    best_free = free_capacity;
                    best_r = r;
                end
            end
            b_id = ranks(best_r,3);
            [Build_Data, Shelters, Shelter_Building_Routines, Building_routine_id] = ...
                mark_as_shelter_if_new(Build_Data, Shelters, Shelter_Building_Routines, Building_routine_id, b_id, i);
            Shelter_Assign = [Shelter_Assign; [agent_ids, repmat(b_id, n_needed, 1)]];
            Shelter_HH_Track = [Shelter_HH_Track; hh_id, b_id, i];
        end
    end
end


function [Build_Data, Shelters, Shelter_Building_Routines, Building_routine_id] = ...
    mark_as_shelter_if_new(Build_Data, Shelters, Shelter_Building_Routines, Building_routine_id, b_id, i)
    row = Build_Data(:,1)==b_id;
    if Build_Data(row,3) ~= 99
        Build_Data(row,3) = 99;
        Shelters = [Shelters; b_id, i, 0]; % [b_id, start_step, end_step=0]
        agents_with_b = find(any(Building_routine_id(:,2:end)==b_id,2));
        Shelter_Building_Routines{end+1,1} = b_id;
        Shelter_Building_Routines{end,2} = Building_routine_id(agents_with_b,:);
        for aidx = agents_with_b'
            br = Building_routine_id(aidx,:);
            br(br==b_id) = NaN; % remove building from routine
            Building_routine_id(aidx,:) = br;
        end
    end
end


function SA_Shelter_Rank = build_SA_shelter_rank(Build_Data)
    all_sa = unique(Build_Data(:,4));
    SA_Shelter_Rank = zeros(0,4); % [SA_id, rank, building_id, distance]
    unresolved_sa = [];

    for s = 1:length(all_sa)
        sa_id = all_sa(s);
        sa_buildings = Build_Data(Build_Data(:,4)==sa_id, :);
        comm = sa_buildings(sa_buildings(:,3)>=2 & sa_buildings(:,3)<=3, :); % commercial only
        publ = sa_buildings(sa_buildings(:,3)==5, :); % public

        if ~isempty(comm) && ~isempty(publ)
            [~, ix] = max(comm(:,25)); % largest commercial building by floorspace
            anchor_xy = comm(ix, 5:6);
            d = pdist2(anchor_xy, publ(:,5:6));
            [d_sorted, order] = sort(d);
            n = length(order);
            SA_Shelter_Rank = [SA_Shelter_Rank; ...
                repmat(sa_id,n,1), (1:n)', publ(order,1), d_sorted(:)];
        else
            unresolved_sa = [unresolved_sa; sa_id]; %#ok<AGROW>
        end
    end

    % second pass: SAs with no commercial anchor and/or no public
    % building borrow the nearest already-designated shelter (rank-1
    % pick) from a resolved SA
    if ~isempty(unresolved_sa)
        designated = unique(SA_Shelter_Rank(SA_Shelter_Rank(:,2)==1, 3));
        designated_xy = zeros(length(designated),2);
        for k = 1:length(designated)
            row = Build_Data(:,1)==designated(k);
            designated_xy(k,:) = Build_Data(row,5:6);
        end

        for s = 1:length(unresolved_sa)
            sa_id = unresolved_sa(s);
            sa_buildings = Build_Data(Build_Data(:,4)==sa_id, :);
            comm = sa_buildings(sa_buildings(:,3)>=2 & sa_buildings(:,3)<=3, :);
            if ~isempty(comm)
                [~, ix] = max(comm(:,25));
                ref_xy = comm(ix, 5:6);
            elseif ~isempty(sa_buildings)
                ref_xy = mean(sa_buildings(:,5:6), 1); % SA centroid fallback
            else
                continue % SA has no buildings at all
            end

            d = pdist2(ref_xy, designated_xy);
            [d_sorted, order] = sort(d);
            n = length(order);
            SA_Shelter_Rank = [SA_Shelter_Rank; ...
                repmat(sa_id,n,1), (1:n)', designated(order), d_sorted(:)];
        end
    end
end
