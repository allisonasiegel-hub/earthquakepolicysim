%% Identify hotel AND school buildings for Tiberias, tag them usage=7/8
% Produces data_for_model_TVR_hotels.mat (does NOT overwrite the original
% data_for_model_TVR.mat) with Build_Data(:,3) set to 7 for hotel
% buildings and 8 for school buildings, alongside a report of the
% calibrated hotel room density.
%
% Hotel method:
%   1. Confirmed hotels: raw Usage=5900 ("Hotel/Guest House" per
%      USG_CODE.csv) in TVR\bldgs_height_tt.csv, before find_usage.m
%      collapses codes 5740-5900 into the model's generic usage=3
%      ("commercial"). All 26 of these building IDs are verified present
%      in the final Build_Data.
%   2. Real-world target: CBS Table D/7 (Sept 2023) reports 39 hotels in
%      Tiberias, 4,765 total rooms - so 26 confirmed leaves ~13 missing
%      from the building data (likely coded as generic commercial in the
%      source cadastral data rather than mislabeled by this pipeline).
%   3. Backfill: among usage==3 buildings not already confirmed as
%      hotels, rank by distance from the known hotels' MEDIAN
%      floor-adjusted area (Area*floors) and take the closest
%      (target_hotel_count - confirmed_count). NOT the largest remaining
%      buildings overall - an earlier attempt at that pulled in
%      mall/industrial-scale commercial buildings far outside the known
%      hotels' size range.
%   4. Room density: 4,765 rooms / sum(Area*floors) across ALL 39 tagged
%      hotels (confirmed + backfilled combined) - NOT just the 26
%      confirmed ones. Using only the confirmed 26 as the density base
%      was a real bug in an earlier version of this script: it silently
%      "spent" the entire 4,765-room budget on the 26 confirmed buildings
%      alone, so any backfilled building's estimated rooms were added on
%      top, guaranteeing an overshoot regardless of how well-chosen the
%      backfill was. Computing density from the full 39-building total
%      makes the citywide total match 4,765 by construction; the backfill
%      selection then only affects how that fixed budget is distributed
%      BETWEEN individual buildings, not the total. Density is NOT stored
%      per-building in Build_Data - it's reported here for use as a
%      constant in assign_shelter.m's hotel-capacity formula
%      (density * Area * floors), parallel to how agents_per_sqm already
%      works for public buildings.
%
% School method: unlike hotels, no city-wide "real" school count is
% needed - the raw source data is presumably complete for schools (no
% missing-count problem like the CBS-vs-building-data hotel gap), so
% every building whose raw code falls in the educational-institution
% range is tagged directly, no backfill/estimation needed. Excludes
% kindergarten (5305 - small, arguably not a realistic shelter building)
% and yeshiva/kollel (5340 - adult religious study, not a conventional
% school) - both easy to add back in by widening SCHOOL_USG_CODES below
% if wanted.

city_folder = 'TVR';
raw_file = fullfile(city_folder, 'bldgs_height_tt.csv');
data_file = 'data_for_model_TVR.mat';
out_file = 'data_for_model_TVR_hotels.mat';

HOTEL_USG_CODE = 5900;
TARGET_HOTEL_COUNT = 39; % CBS Table D/7, Sept 2023
TOTAL_REAL_ROOMS = 4765; % CBS Table D/7, Sept 2023
NEW_HOTEL_USAGE = 7;

SCHOOL_USG_CODES = [5300 5310 5312 5320 5321 5330 5332 5337 5338 5370 5380]; % educational institutions, excl. kindergarten/yeshiva - see header
NEW_SCHOOL_USAGE = 8;

%% 1. Confirmed hotels from raw source data
raw = readtable(raw_file);
confirmed_ids = raw.BLDG_ID(raw.Usage == HOTEL_USG_CODE);
fprintf('Raw source: %d buildings tagged Usage=%d (hotel)\n', length(confirmed_ids), HOTEL_USG_CODE);

%% 2. Load model data, verify confirmed hotels survive
% Load everything (not just Build_Data) so out_file is a complete,
% drop-in replacement for data_for_model_TVR.mat.
load(data_file);
confirmed_present = ismember(confirmed_ids, Build_Data(:,1));
if ~all(confirmed_present)
    warning('%d of %d confirmed hotel IDs are missing from Build_Data - excluding them.', ...
        sum(~confirmed_present), length(confirmed_ids));
end
confirmed_ids = confirmed_ids(confirmed_present);
fprintf('%d confirmed hotel buildings verified present in Build_Data\n', length(confirmed_ids));

%% 3. Typical hotel size (for backfill selection only - not density)
[~, locB] = ismember(confirmed_ids, Build_Data(:,1));
confirmed_floor_adj_area = Build_Data(locB,7) .* ceil(Build_Data(locB,11));
typical_size = median(confirmed_floor_adj_area);
fprintf('Known hotels floor-adjusted area: min=%.0f median=%.0f mean=%.0f max=%.0f\n', ...
    min(confirmed_floor_adj_area), typical_size, mean(confirmed_floor_adj_area), max(confirmed_floor_adj_area));

%% 4. Backfill from usage==3 buildings closest in size to known hotels
n_backfill = TARGET_HOTEL_COUNT - length(confirmed_ids);
if n_backfill < 0
    error('Confirmed hotel count (%d) already exceeds target (%d) - nothing to backfill.', ...
        length(confirmed_ids), TARGET_HOTEL_COUNT);
end

usage3 = Build_Data(Build_Data(:,3)==3, :);
usage3 = usage3(~ismember(usage3(:,1), confirmed_ids), :);
floor_adj_area = usage3(:,7) .* ceil(usage3(:,11)); % Area * floors
size_distance = abs(floor_adj_area - typical_size);
[~, sortidx] = sort(size_distance, 'ascend');
backfill_ids = usage3(sortidx(1:n_backfill), 1);
fprintf('Backfilling %d additional hotel buildings (usage=3, closest in floor-adjusted area to known hotels'' median of %.0f sqm)\n', ...
    n_backfill, typical_size);

%% 5. Tag all hotel buildings (confirmed + backfilled) as usage=7
all_hotel_ids = [confirmed_ids; backfill_ids];
[~, locB] = ismember(all_hotel_ids, Build_Data(:,1));
Build_Data(locB, 3) = NEW_HOTEL_USAGE;
fprintf('Tagged %d buildings total as usage=%d (hotel)\n', length(all_hotel_ids), NEW_HOTEL_USAGE);

%% 6. Room density from the FULL 39-building total (confirmed + backfilled)
all_floor_adj_area = Build_Data(locB,7) .* ceil(Build_Data(locB,11));
hotel_room_density = TOTAL_REAL_ROOMS / sum(all_floor_adj_area); % rooms per sqm of floor-adjusted area
fprintf('Hotel room density: %.5f rooms per sqm floor-adjusted area (%.0f rooms / %.0f sqm across all %d)\n', ...
    hotel_room_density, TOTAL_REAL_ROOMS, sum(all_floor_adj_area), length(all_hotel_ids));

%% 7. Sanity check - should now equal TOTAL_REAL_ROOMS by construction
est_total_rooms = hotel_room_density * sum(all_floor_adj_area);
fprintf('Estimated total rooms across all %d tagged hotels: %.0f (real: %d)\n', ...
    length(all_hotel_ids), est_total_rooms, TOTAL_REAL_ROOMS);

%% 8. Identify and tag school buildings as usage=8
school_ids = raw.BLDG_ID(ismember(raw.Usage, SCHOOL_USG_CODES));
school_present = ismember(school_ids, Build_Data(:,1));
if ~all(school_present)
    warning('%d of %d school IDs are missing from Build_Data - excluding them.', ...
        sum(~school_present), length(school_ids));
end
school_ids = school_ids(school_present);
[~, locB_school] = ismember(school_ids, Build_Data(:,1));
Build_Data(locB_school, 3) = NEW_SCHOOL_USAGE;
fprintf('Tagged %d buildings as usage=%d (school)\n', length(school_ids), NEW_SCHOOL_USAGE);

%% 9. Save updated data (new file - does not overwrite the original)
% Only the original 10 variables - keeps out_file a clean, exact
% drop-in replacement for data_for_model_TVR.mat (script-internal
% variables like raw/confirmed_ids/backfill_ids are not included).
save(out_file, 'Assets','Assets_P','Build_Data','Build_Data_p', ...
    'HH_data','HH_data_P','Individuals_data','Individuals_data_P', ...
    'Work_places','Work_places_P');
fprintf('Saved %s\n', out_file);
