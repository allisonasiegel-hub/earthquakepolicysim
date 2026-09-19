%% Identify hotel buildings for Arad, tag them usage=7
% Produces data_for_model_Aradhotels.mat (does NOT overwrite the original
% data_for_model_Arad.mat), with Build_Data(:,3) set to 7 for the 3 known
% hotel buildings, alongside the calibrated hotel room density - same
% convention as identify_hotels_ASH.m (see that file's header for the
% full method vs. Tiberias's more involved raw-code+backfill approach):
%
%   Arad, like Ashkelon, has all 3 real-world hotels fully known (name +
%   WGS84 coordinates + room count) and 3 known hotels = 3 target count,
%   so there's no missing-count gap to backfill. Each hotel is matched
%   directly to its NEAREST Build_Data building by coordinate distance
%   (after converting WGS84 -> ITM via wgs84_to_itm.m, the same projected
%   system Build_Data(:,5)/(:,6) use).
%
%   Room density: 230 real rooms / sum(floor-adjusted area) across the 3
%   matched buildings - same formula as Ashkelon/Tiberias (rooms per sqm
%   of Area*floors).
%
%   NOTE on the output filename: deliberately "Aradhotels" with NO
%   underscore before "hotels" - same reasoning as Ash2hotels (see that
%   file's header): run_model_earthquake_shelteroverflow.m derives each
%   run's earthquakeF/ output prefix from the LAST '_'-split token of the
%   `data` variable name - "data_for_model_Arad_hotels" would split to a
%   last token of just "hotels", identical to Tiberias's
%   data_for_model_TVR_hotels, making both cities' runs share the same
%   "hotels EQ S..." filename prefix and be indistinguishable by pattern
%   in earthquakeF/. Keep it "Aradhotels".

data_file = 'data_for_model_Arad.mat';
out_file = 'data_for_model_Aradhotels.mat';

NEW_HOTEL_USAGE = 7;
TOTAL_REAL_ROOMS = 118 + 100 + 12; % 230

hotel_names = {'Roxon Desert Arad', 'Hotel Inbar Arad', 'Yehelim Boutique Hotel'};
hotel_lat = [31.2601, 31.2562, 31.26084];
hotel_lon = [35.2246, 35.2097, 35.22601];
hotel_rooms = [118, 100, 12];

[hotel_X, hotel_Y] = wgs84_to_itm(hotel_lat, hotel_lon);

%% 1. Load model data (load everything so out_file is a complete,
% drop-in replacement for data_for_model_Arad.mat)
load(data_file);

%% 2. Match each hotel to its nearest Build_Data building by distance
n_hotels = numel(hotel_names);
matched_ids = zeros(n_hotels,1);
matched_dist = zeros(n_hotels,1);
matched_usage = zeros(n_hotels,1);
for k = 1:n_hotels
    d = hypot(Build_Data(:,5) - hotel_X(k), Build_Data(:,6) - hotel_Y(k));
    [dmin, idx] = min(d);
    matched_ids(k) = Build_Data(idx,1);
    matched_dist(k) = dmin;
    matched_usage(k) = Build_Data(idx,3);
    fprintf('%-25s -> building ID %d, %.1f m away, current usage=%d, floor-adj area=%.1f sqm, %d real rooms\n', ...
        hotel_names{k}, matched_ids(k), matched_dist(k), matched_usage(k), ...
        Build_Data(idx,7)*ceil(Build_Data(idx,11)), hotel_rooms(k));
end

if numel(unique(matched_ids)) < n_hotels
    warning('Two or more hotels matched the SAME building - check matched IDs/distances above before proceeding.');
end

%% 2b. Data-quality patch: a matched building can have floors=0 recorded
% (not NaN, so it wasn't caught by start_spatial_dataupdate.m's
% missing-height mean-fill) despite a valid positive Area - a building
% with recorded floor area obviously has at least 1 usable floor. Left
% unpatched, this zeroes that hotel's floor-adjusted area entirely,
% inflating hotel_room_density (computed from ALL 3 hotels' combined
% area) by ~6-8x and overstating the OTHER 2 hotels' shelter capacity too
% (same global density applied to every usage=7 building). Confirmed for
% Roxon Desert Arad (building 67178859, Area=254.0 sqm, floors=0) against
% its 7 nearest neighbors (77-97m away) - none are meaningfully larger,
% so this reads as a data gap on this specific record, not a bad nearest-
% building match.
[~, locB_check] = ismember(matched_ids, Build_Data(:,1));
zero_floor_bldgs = Build_Data(locB_check,11)==0;
if any(zero_floor_bldgs)
    fixed_ids = matched_ids(zero_floor_bldgs);
    Build_Data(locB_check(zero_floor_bldgs), 11) = 1;
    fprintf('Data-quality patch: building(s) %s had floors=0 (valid Area, missing floor count) - set to 1\n', mat2str(fixed_ids));
end

%% 3. Tag matched buildings as usage=7
[~, locB] = ismember(matched_ids, Build_Data(:,1));
Build_Data(locB, 3) = NEW_HOTEL_USAGE;
fprintf('Tagged %d buildings as usage=%d (hotel)\n', n_hotels, NEW_HOTEL_USAGE);

%% 4. Room density from the 3 tagged hotels' total floor-adjusted area
all_floor_adj_area = Build_Data(locB,7) .* ceil(Build_Data(locB,11));
hotel_room_density = TOTAL_REAL_ROOMS / sum(all_floor_adj_area);
fprintf('Hotel room density: %.5f rooms per sqm floor-adjusted area (%.0f rooms / %.0f sqm across %d hotels)\n', ...
    hotel_room_density, TOTAL_REAL_ROOMS, sum(all_floor_adj_area), n_hotels);

%% 5. Sanity check - should equal TOTAL_REAL_ROOMS by construction
est_total_rooms = hotel_room_density * sum(all_floor_adj_area);
fprintf('Estimated total rooms across all %d tagged hotels: %.0f (real: %d)\n', ...
    n_hotels, est_total_rooms, TOTAL_REAL_ROOMS);

%% 6. Save updated data (new file - does not overwrite the original)
save(out_file, 'Assets','Assets_P','Build_Data','Build_Data_p', ...
    'HH_data','HH_data_P','Individuals_data','Individuals_data_P', ...
    'Work_places','Work_places_P');
fprintf('Saved %s\n', out_file);
