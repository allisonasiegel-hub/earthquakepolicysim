function [building_average_sa, n_businesses_subsidized_total, businesses_subsidized_ever_ids] = cal_bui_sa_subsidy_targeted(...
    Work_places, Build_Data, destroyed_B, subsidy_businesses_mode, n_businesses_subsidized_total, businesses_subsidized_ever_ids)
% n_businesses_subsidized_total/businesses_subsidized_ever_ids:
% pass-through accumulators (same threading pattern as HH_subsidy_
% targeted.m's counters - init once outside the step loop, fed back in
% and out every call) for sweep-analysis outputs (chat 2026-09-15).
% businesses_subsidized_ever_ids tracks which building ids have already
% been counted, since mode 2's size-based half can make a building
% eligible on one step and not the next as it hires/reopens - each
% building is only added to the cumulative count once, the first time it
% qualifies, not re-counted every week it happens to still qualify.
% Targeted business subsidy for run_model_earthquake_shelteroverflow.m.
% Kept separate from the shared cal_bui_sa_subsidy.m (used unmodified by
% run_model_eq.m, run_model_earthquake.m, diag_*.m) since this variant
% adds two new eligibility rules alongside the original one - see chat
% 2026-09-15.
%
% subsidy_businesses_mode:
%   0 = off
%   1 = a commercial building's wage expense is covered if it was
%       destroyed by the shock and has more than 1 worker.
%   2 = mode 1's destroyed-buildings rule, UNION the smallest 30% of
%       commercial buildings by CURRENT worker headcount (Work_places) -
%       a building qualifies if it was destroyed OR is small, not only
%       if both. The size half of this union is re-evaluated every call,
%       so that part of the eligible set can shift over time as
%       businesses reopen, hire, or shrink; the destroyed half is a
%       fixed one-time set like mode 1's.
%
% Ported from b7/b7ABM-matlab/cal_bui_sa_sub.m's epidemic-era business
% subsidy (chat 2026-09-15): for an eligible building, the wage expense
% counted below is the sum of every worker's salary EXCEPT its 2 lowest-
% paid workers - i.e. the subsidy covers what the business would have
% owed its 2 lowest earners, not its whole payroll. b7's own version had
% a comment ("Remove the 2 lowest salaries") that didn't match its code
% (which sorted descending and kept index 3: onward, actually dropping
% the 2 HIGHEST-paid instead) - this port follows the comment's intent,
% not that bug. Requires at least 3 workers to have any 2 to drop; a
% 1-2-worker eligible building simply has its entire (small) payroll
% covered, same as before.
%
% In every mode, eligibility still requires more than 1 worker (same
% guard the original had) - a building with 0-1 workers has nothing
% meaningful to subsidize.
%
% building_average_sa columns: [building_id, subsidized_wage_sum,
% original_wage_sum]. STABLE-YARDSTICK FIX (chat 2026-09-15): the caller
% builds its percentile scale from column 3 (the real, unsubsidized wage
% total for every building) and only looks up column 2 (the eligibility-
% adjusted total) to find each INDIVIDUAL building's own position on
% that scale. Before this fix, the caller built the percentile scale
% directly from the subsidized column - fine when only 1-2 buildings are
% touched (mode 1), but mode 2 can subsidize ~30% of all commercial
% buildings at once, which visibly compresses the whole distribution and
% silently shifts every OTHER (non-subsidized) building's rank too - a
% business the policy never touched could gain or lose jobs purely
% because of how many other buildings got subsidized that week. Column 3
% keeps the scale itself invariant to how generous either subsidy mode
% is; column 2 still lets a subsidized building benefit from looking
% cheaper against that fixed scale.
    u = unique(Work_places(:,1));
    h = Build_Data(ismember(Build_Data(:,1),u),3); % col 3 'Usage'
    u2 = u(h==3); % only commercial

    destroyed_ids = 0;
    if ~isempty(destroyed_B)
        destroyed_ids = destroyed_B(:,1);
    end

    worker_counts = zeros(length(u2),1);
    for i = 1:length(u2)
        worker_counts(i) = sum(Work_places(:,1) == u2(i));
    end
    size_threshold = -Inf;
    if subsidy_businesses_mode == 2 && ~isempty(worker_counts)
        size_threshold = prctile(worker_counts, 30);
    end

    building_average_sa = zeros(0,3);
    for i = 1:length(u2)
        building_salaries = Work_places(Work_places(:,1) == u2(i), 8); % col 8 'salary'
        original_sum = sum(building_salaries);
        eligible = false;
        switch subsidy_businesses_mode
            case 1
                eligible = ismember(u2(i), destroyed_ids);
            case 2
                eligible = ismember(u2(i), destroyed_ids) || worker_counts(i) <= size_threshold;
        end
        if eligible && length(building_salaries) > 1
            % Drop the 2 lowest-paid workers' salaries from the counted
            % wage bill - the subsidy covers their wages, not the whole
            % building's payroll. A building with only 2 eligible workers
            % has both dropped (fully covered); 1-worker buildings never
            % reach here due to the length>1 guard above.
            sorted_asc = sort(building_salaries, 'ascend');
            n_drop = min(2, length(sorted_asc));
            building_salaries = sorted_asc(n_drop+1:end);
            if ~ismember(u2(i), businesses_subsidized_ever_ids)
                businesses_subsidized_ever_ids = [businesses_subsidized_ever_ids; u2(i)];
                n_businesses_subsidized_total = n_businesses_subsidized_total + 1;
            end
        end
        building_average_sa(i,:) = [u2(i), sum(building_salaries), original_sum];
    end
end
