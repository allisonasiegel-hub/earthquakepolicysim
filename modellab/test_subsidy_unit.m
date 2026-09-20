% Standalone unit test for HH_subsidy_targeted.m and
% cal_bui_sa_subsidy_targeted.m against synthetic data - much faster than
% waiting on a full earthquake simulation to verify the mechanics.

%% --- shared synthetic setup for HH_subsidy_targeted (modes 5/6) ---
% HH_data cols used: 2=HH ID, 3=size, 6=income, 7=decile, 11=asset id
HH_data = [ ...
    1, 0, 2, 0, 0, 5000, 1, 0, 0, 0, 101; ...  % hh 1: destroyed (asset 101), decile 1
    1, 0, 3, 0, 0, 8000, 5, 0, 0, 0, 102; ...  % hh 2: destroyed (asset 102), decile 5
    1, 0, 4, 0, 0, 4000, 2, 0, 0, 0, 103; ...  % hh 3: NOT destroyed, decile 2
    1, 0, 2, 0, 0, 9000, 9, 0, 0, 0, 104; ...  % hh 4: NOT destroyed, decile 9
];
HH_data(:,2) = [1;2;3;4];

Individuals_data = zeros(0,15);
agent_id = 1;
for hh = 1:4
    sz = HH_data(hh,3);
    for m = 1:sz
        Individuals_data(end+1,:) = [agent_id,0,hh,zeros(1,11),1000]; %#ok<SAGROW>
        agent_id = agent_id + 1;
    end
end

HH_destroyed = [1; 2]; % hh 1 and 2 destroyed

Assets = [0,0,103,0,0,0,0,0,0,0,0,0,3200; 0,0,104,0,0,0,0,0,0,0,0,0,4100]; % col13 cost-of-life for still-standing homes
bad_Assets = [0,0,101,0,0,0,0,0,0,0,0,0,2500; 0,0,102,0,0,0,0,0,0,0,0,0,6000]; % col13 for destroyed homes
% Shelter_Assign/Sheltered_Outside/Temp_Dev_Assign are still required
% params (call-site signature stability) but unused by modes 5/6, which
% have no early-exit-on-resettlement mechanic - pass placeholders.
Shelter_Assign_m3grant = [1,900; 2,900; 3,900; 4,900; 5,900]; % [agent_id, building_id]
Sheltered_Outside = zeros(0,3); Temp_Dev_Assign = zeros(0,3);

subsidy_duration = 9; % modes 5/6 ignore this (fixed 4/8-step duration) - kept to match the real call site

%% --- mode 5: displaced only, decile-tiered % of housing cost, fixed 4-step duration ---
% hh1: decile 1 (low tier, 40%), hh2: decile 5 (middle tier, 35%).
subsidy_residents_mode5 = 5;
tracker5 = zeros(0,4);
n_hh5 = 0; aid5 = 0;
[HH_data_m5, ~, tracker5, n_hh5, aid5] = HH_subsidy_targeted(HH_data, Individuals_data, HH_destroyed, tracker5, Assets, bad_Assets, Shelter_Assign_m3grant, Sheltered_Outside, Temp_Dev_Assign, subsidy_residents_mode5, subsidy_duration, 40, n_hh5, aid5);
fprintf('=== Mode 5 grant test (hh1 decile1->40%%, hh2 decile5->35%%) ===\n'); disp(tracker5);
assert(isequal(sort(tracker5(:,1)), [1;2]), 'mode 5 should grant only the displaced (hh1,hh2)');
assert(abs(HH_data_m5(HH_data_m5(:,2)==1,6) - (5000+0.40*2500)) < 1e-9, 'hh1 (decile 1, low tier) should get 40% of 2500 = 1000');
assert(abs(HH_data_m5(HH_data_m5(:,2)==2,6) - (8000+0.35*6000)) < 1e-9, 'hh2 (decile 5, middle tier) should get 35% of 6000 = 2100');

% Fixed 4-step duration test: expires at i=44 (40+4), NOT at the general
% subsidy_duration=9 - verifies mode 5 ignores the externally-passed value.
[HH_data_m5b, ~, tracker5b, ~, aid5b] = HH_subsidy_targeted(HH_data_m5, Individuals_data, [], tracker5, Assets, bad_Assets, Shelter_Assign_m3grant, Sheltered_Outside, Temp_Dev_Assign, subsidy_residents_mode5, subsidy_duration, 44, n_hh5, aid5);
fprintf('=== Mode 5 fixed-duration test at step 44 (40+4, should have expired) ===\n'); disp(tracker5b);
assert(isempty(tracker5b), 'mode 5 should use its own fixed 4-step duration, not subsidy_duration=9 - expired by step 44');
fprintf('PASS: mode 5 grants decile-tiered amounts and expires at its own fixed 4-step duration.\n\n');

%% --- mode 6: displaced only, decile-tiered % of housing cost, fixed 12-step (3-month) duration ---
subsidy_residents_mode6 = 6;
tracker6 = zeros(0,4);
n_hh6 = 0; aid6 = 0;
[HH_data_m6, ~, tracker6, n_hh6, aid6] = HH_subsidy_targeted(HH_data, Individuals_data, HH_destroyed, tracker6, Assets, bad_Assets, Shelter_Assign_m3grant, Sheltered_Outside, Temp_Dev_Assign, subsidy_residents_mode6, subsidy_duration, 40, n_hh6, aid6);
fprintf('=== Mode 6 grant test (hh1 decile1->20%%, hh2 decile5->15%%) ===\n'); disp(tracker6);
assert(abs(HH_data_m6(HH_data_m6(:,2)==1,6) - (5000+0.20*2500)) < 1e-9, 'hh1 (decile 1, low tier) should get 20% of 2500 = 500');
assert(abs(HH_data_m6(HH_data_m6(:,2)==2,6) - (8000+0.15*6000)) < 1e-9, 'hh2 (decile 5, middle tier) should get 15% of 6000 = 900');

% Should still be active at step 51 (40+11 < 40+12) but expired by step 52 (40+12).
[~, ~, tracker6_wk51, ~, ~] = HH_subsidy_targeted(HH_data_m6, Individuals_data, [], tracker6, Assets, bad_Assets, Shelter_Assign_m3grant, Sheltered_Outside, Temp_Dev_Assign, subsidy_residents_mode6, subsidy_duration, 51, n_hh6, aid6);
[~, ~, tracker6_wk52, ~, ~] = HH_subsidy_targeted(HH_data_m6, Individuals_data, [], tracker6, Assets, bad_Assets, Shelter_Assign_m3grant, Sheltered_Outside, Temp_Dev_Assign, subsidy_residents_mode6, subsidy_duration, 52, n_hh6, aid6);
assert(~isempty(tracker6_wk51), 'mode 6 should still be active at step 51 (only 11 of its 12 steps elapsed)');
assert(isempty(tracker6_wk52), 'mode 6 should have expired by step 52 (40+12), its own fixed duration');
fprintf('PASS: mode 6 grants decile-tiered amounts and expires at its own fixed 12-step (3-month) duration.\n\n');

%% --- cal_bui_sa_subsidy_targeted: modes 1/2/3 ---
% Work_places cols: 1=building id, 8=salary
Work_places = [ ...
    10, 0,0,0,0,0,0, 100; ... % building 10: 1 worker, salary 100 (destroyed, only 2 workers total)
    10, 0,0,0,0,0,0, 150; ... % building 10: 2nd worker
    20, 0,0,0,0,0,0, 200; ... % building 20: 1 worker (not destroyed, small)
    30, 0,0,0,0,0,0, 300; ... % building 30: 1 worker
    30, 0,0,0,0,0,0, 300; ... % building 30: 2nd worker
    30, 0,0,0,0,0,0, 300; ... % building 30: 3rd worker (largest by headcount, not destroyed)
    40, 0,0,0,0,0,0, 50;  ... % building 40: destroyed, 4 workers -> tests partial (drop-2-lowest) coverage
    40, 0,0,0,0,0,0, 80;  ...
    40, 0,0,0,0,0,0, 200; ...
    40, 0,0,0,0,0,0, 300; ...
];
Build_Data = [10,0,3,0; 20,0,3,0; 30,0,3,0; 40,0,3,0]; % col1=id, col3=usage(3=commercial)
destroyed_B = [10, 0, 0; 40, 0, 0]; % buildings 10 and 40 destroyed
% destroyed_commercial_B0: all 4 test buildings are usage=3 throughout
% (no land-use-conversion scenario here), so "destroyed AND was
% originally commercial" is the same set as destroyed_B itself.
destroyed_commercial_B0 = destroyed_B;

% mode 1: only destroyed (buildings 10, 40) get the wage-drop treatment.
% Building 10 has only 2 workers, so dropping its "2 lowest" drops both
% (fully covered, total 0). Building 40 has 4 workers [50,80,200,300] -
% dropping the 2 lowest (50,80) leaves [200,300] = 500 still counted
% (PARTIAL coverage - this is the case the old zero-everything version
% couldn't distinguish from full coverage).
[r1, n_biz1, biz_ids1] = cal_bui_sa_subsidy_targeted(Work_places, Build_Data, destroyed_B, destroyed_commercial_B0, 1, 0, []);
fprintf('=== Business mode 1 (destroyed only) ===\n'); disp(r1);
assert(r1(r1(:,1)==10,2) == 0, 'building 10 (destroyed, 2 workers) should be fully covered (both dropped)');
assert(r1(r1(:,1)==20,2) == 200, 'building 20 (not destroyed) should be untouched');
assert(r1(r1(:,1)==30,2) == 900, 'building 30 (not destroyed) should be untouched');
assert(r1(r1(:,1)==40,2) == 500, 'building 40 (destroyed, 4 workers) should keep its 2 highest earners (200+300=500) after dropping the 2 lowest');
assert(n_biz1 == 2, 'cumulative subsidized-business count should be 2 (buildings 10 and 40)');
assert(isequal(sort(biz_ids1), [10;40]), 'subsidized-ever id list should be exactly {10,40}');
% col 3 (original, unsubsidized wage sum) should be unaffected by eligibility -
% stable-yardstick fix's whole point (chat 2026-09-15).
assert(r1(r1(:,1)==10,3) == 250, 'building 10 original wage sum should be 100+150=250 regardless of eligibility');
assert(r1(r1(:,1)==20,3) == 200, 'building 20 original wage sum should be untouched at 200');
assert(r1(r1(:,1)==30,3) == 900, 'building 30 original wage sum should be untouched at 900');
assert(r1(r1(:,1)==40,3) == 630, 'building 40 original wage sum should be 50+80+200+300=630 regardless of eligibility');

% mode 2: destroyed UNION smallest 30% by worker headcount.
% Counts: b10=2, b20=1, b30=3, b40=4. 30th percentile of [2,1,3,4] should
% select building 20 (headcount 1, smallest) on the size side; buildings
% 10 and 40 also qualify via the destroyed side.
[r2, n_biz2, biz_ids2] = cal_bui_sa_subsidy_targeted(Work_places, Build_Data, destroyed_B, destroyed_commercial_B0, 2, 0, []);
fprintf('=== Business mode 2 (destroyed UNION smallest 30%% by headcount) ===\n'); disp(r2);
assert(r2(r2(:,1)==10,2) == 0, 'building 10 (destroyed) should be fully covered under mode 2');
assert(r2(r2(:,1)==20,2) == 200, 'building 20 qualifies by size but has only 1 worker so the >1-worker guard keeps it un-zeroed');
assert(r2(r2(:,1)==30,2) == 900, 'building 30 (not destroyed, not small) should be untouched');
assert(r2(r2(:,1)==40,2) == 500, 'building 40 (destroyed) should keep its 2 highest earners under mode 2 too');
assert(n_biz2 == 2, 'building 20 does NOT get counted (blocked by the >1-worker guard), so cumulative count is still 2');
assert(isequal(sort(biz_ids2), [10;40]), 'subsidized-ever id list should be exactly {10,40} even under mode 2 (building 20 never actually gets subsidized)');

% WAGE-YARDSTICK FIX regression test (chat 2026-09-20): building 50 is
% CURRENTLY destroyed (in destroyed_B) but was NOT commercial when the
% quake hit (absent from destroyed_commercial_B0) - simulating a
% residential building destroyed by the earthquake that later got
% converted to commercial via ordinary land-use growth, unrelated to the
% quake. It must NOT be treated as an eligible destroyed business under
% either mode, despite matching destroyed_B membership alone.
Work_places_lu = [Work_places; 50,0,0,0,0,0,0,120; 50,0,0,0,0,0,0,180];
Build_Data_lu = [Build_Data; 50,0,3,0]; % now commercial (post-conversion)
destroyed_B_lu = [destroyed_B; 50,0,0]; % still tracked as destroyed
% destroyed_commercial_B0 deliberately does NOT include building 50 -
% it was residential (usage~=3) at shock time, not commercial.
[r3, ~, biz_ids3] = cal_bui_sa_subsidy_targeted(Work_places_lu, Build_Data_lu, destroyed_B_lu, destroyed_commercial_B0, 1, 0, []);
assert(r3(r3(:,1)==50,2) == 300, 'building 50 (destroyed-but-not-originally-commercial) must be untouched: 120+180=300, no wage-bill suppression');
assert(~ismember(50, biz_ids3), 'building 50 must never be counted as a subsidized business');
fprintf('PASS: a building destroyed while residential and later converted to commercial via land-use is correctly excluded from destroyed-business eligibility.\n\n');

fprintf('\nALL TESTS PASSED\n');
