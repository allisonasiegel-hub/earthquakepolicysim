function [building_average_sa, n_businesses_subsidized_total, businesses_subsidized_ever_ids, biz_subsidy_tracker] = cal_bui_sa_subsidy_targeted(...
    Work_places, Build_Data, destroyed_B, destroyed_commercial_B0, subsidy_businesses_mode, n_businesses_subsidized_total, businesses_subsidized_ever_ids, biz_subsidy_tracker, step_num)
% destroyed_commercial_B0: fixed, one-time snapshot (taken at shock time
% in run_model_earthquake_shelteroverflow.m, before shock_W/shock_I strip
% anything) of buildings that were ALREADY commercial (usage=3) the
% moment the earthquake hit. REQUIRED for the "destroyed" half of modes
% 1/2's eligibility (see below) - destroyed_B alone isn't enough, since
% it just tracks "currently still destroyed" and doesn't know a
% building's usage history. Change_LU's candidate pool
% (Build_Data(:,3)<2) doesn't check destruction status, so a RESIDENTIAL
% building destroyed by the quake can sit in destroyed_B for many steps
% while ALSO getting converted to commercial with a brand-new, real
% workforce via ordinary land-use growth - unrelated to the earthquake's
% business impact. Without this distinction that building would
% incorrectly qualify as an eligible "destroyed business" too. Confirmed
% happening for Arad (chat 2026-09-20): 68 buildings, all usage=1 at
% shock time and usage=3 by end of run, several still in destroyed_B at
% the final step, continuously eligible for the "drop 2 lowest earners"
% wage-bill suppression below despite having nothing to do with the
% quake - the actual cause of a large, consistent, widening negative
% "jobs saved" a subsidy sweep found for modes 1/2.
%
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
%   3/4 = FIXED-DURATION modes (chat 2026-09-22), ported closer to the
%       ORIGINAL rocketattack/RABM-matlab cal_bui_sa_subsidy.m design
%       (destroyed-buildings-only eligibility, whole wage-bill treatment)
%       than modes 1/2's "drop 2 lowest earners" - but time-limited
%       instead of running for as long as the building stays destroyed,
%       matching HH_subsidy_targeted.m modes 5/6's "grant once on first
%       eligibility, no early exit" pattern via biz_subsidy_tracker
%       (columns: [building_id, subsidy_start_step]). Eligibility to
%       START the clock is the same "was destroyed AND was commercial at
%       shock" rule as mode 1; once started, the fixed window runs to
%       completion regardless of later recovery.
%   3 = the ENTIRE wage bill is zeroed (not just the 2 lowest earners),
%       for a fixed 4-step (1-month) window.
%   4 = HALF the wage bill is counted, for a fixed 12-step (3-month)
%       window.
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
    % "was destroyed AND was already commercial when hit" - see
    % destroyed_commercial_B0's header comment above for why both
    % conditions are required, not just destroyed_ids membership.
    orig_commercial_ids = 0;
    if ~isempty(destroyed_commercial_B0)
        orig_commercial_ids = destroyed_commercial_B0(:,1);
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
        was_destroyed_commercial = ismember(u2(i), destroyed_ids) && ismember(u2(i), orig_commercial_ids);
        switch subsidy_businesses_mode
            case 1
                eligible = was_destroyed_commercial;
            case 2
                eligible = was_destroyed_commercial || worker_counts(i) <= size_threshold;
            case {3, 4}
                % Start the clock once, on first eligibility - see this
                % function's header. biz_subsidy_tracker is checked (not
                % just started) every call so the fixed window keeps
                % running on later steps even after the building recovers
                % and was_destroyed_commercial goes false. isempty guard
                % first (like HH_subsidy_tracker elsewhere) - indexing
                % column 1 of an empty [] errors in MATLAB.
                already_tracked = ~isempty(biz_subsidy_tracker) && ismember(u2(i), biz_subsidy_tracker(:,1));
                if was_destroyed_commercial && ~already_tracked
                    biz_subsidy_tracker = [biz_subsidy_tracker; u2(i), step_num];
                end
                tracked_row = [];
                if ~isempty(biz_subsidy_tracker)
                    tracked_row = find(biz_subsidy_tracker(:,1) == u2(i), 1);
                end
                if ~isempty(tracked_row)
                    if subsidy_businesses_mode == 3
                        duration = 4; % 1 month
                    else
                        duration = 12; % 3 months
                    end
                    eligible = (step_num - biz_subsidy_tracker(tracked_row,2)) < duration;
                end
        end
        if eligible && length(building_salaries) > 1
            switch subsidy_businesses_mode
                case 3
                    % Original rocketattack/RABM-matlab treatment: zero
                    % the entire counted wage bill, not just 2 earners.
                    building_salaries = zeros(size(building_salaries));
                case 4
                    % Half the wage bill counted - the subsidy covers the
                    % other half.
                    building_salaries = building_salaries * 0.5;
                otherwise
                    % Modes 1/2: drop the 2 lowest-paid workers' salaries
                    % from the counted wage bill - the subsidy covers
                    % their wages, not the whole building's payroll. A
                    % building with only 2 eligible workers has both
                    % dropped (fully covered); 1-worker buildings never
                    % reach here due to the length>1 guard above.
                    sorted_asc = sort(building_salaries, 'ascend');
                    n_drop = min(2, length(sorted_asc));
                    building_salaries = sorted_asc(n_drop+1:end);
            end
            if ~ismember(u2(i), businesses_subsidized_ever_ids)
                businesses_subsidized_ever_ids = [businesses_subsidized_ever_ids; u2(i)];
                n_businesses_subsidized_total = n_businesses_subsidized_total + 1;
            end
        end
        building_average_sa(i,:) = [u2(i), sum(building_salaries), original_sum];
    end
end
