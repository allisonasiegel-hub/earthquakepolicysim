%% Identify hotel buildings for Ashkelon, tag them usage=7
% Produces data_for_model_Ash2hotels.mat (does NOT overwrite the
% original data_for_model_Ash2.mat), with Build_Data(:,3) set to 7 for
% the 3 known hotel buildings, alongside the calibrated hotel room
% density - same convention as identify_hotels_TVR.m (see that file's
% header), adapted for Ashkelon's data:
%
%   Tiberias had a raw usage code (5900) to confirm hotels directly, plus
%   a real-world city-wide TARGET COUNT (CBS Table D/7) exceeding what
%   the raw codes captured, needing a size-based backfill from generic
%   usage=3 buildings to close the gap.
%
%   Ashkelon has neither of those complications: all 3 real-world hotels
%   are already fully known (name + WGS84 coordinates), and 3 known
%   hotels = 3 target count, so there's no missing-count gap to backfill.
%   Each hotel is matched directly to its NEAREST Build_Data building by
%   coordinate distance (after converting WGS84 -> ITM via
%   wgs84_to_itm.m, the same projected system Build_Data(:,5)/(:,6) use -
%   validated against the ITM origin point, exact to sub-mm).
%
%   Room density: 404 real rooms / sum(floor-adjusted area) across the 3
%   matched buildings - same formula as Tiberias (rooms per sqm of
%   Area*floors), just over 3 buildings instead of 39.
%
%   NOTE on the output filename: deliberately "Ash2hotels" with NO
%   underscore before "hotels". run_model_earthquake_shelteroverflow.m
%   derives each run's earthquakeF/ output prefix from the LAST
%   '_'-split token of the `data` variable name - "data_for_model_Ash2_
%   hotels" would split to a last token of just "hotels", identical to
%   Tiberias's data_for_model_TVR_hotels (SAME last token), making both
%   cities' runs share the same "hotels EQ S..." filename prefix and be
%   indistinguishable by pattern in earthquakeF/. Keep it "Ash2hotels".

data_file = 'data_for_model_Ash2.mat';
out_file = 'data_for_model_Ash2hotels.mat';

NEW_HOTEL_USAGE = 7;
TOTAL_REAL_ROOMS = 404;

hotel_names = {'Tamara Ashkelon', 'Hotel Regina Goren', 'Golden Tower'};
hotel_lat = [31.6747, 31.675781, 31.67494];
hotel_lon = [34.5539, 34.55501, 34.56264];

[hotel_X, hotel_Y] = wgs84_to_itm(hotel_lat, hotel_lon);

%% 1. Load model data (load everything so out_file is a complete,
% drop-in replacement for data_for_model_Ash2.mat)
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
    fprintf('%-20s -> building ID %d, %.1f m away, current usage=%d, floor-adj area=%.1f sqm\n', ...
        hotel_names{k}, matched_ids(k), matched_dist(k), matched_usage(k), ...
        Build_Data(idx,7)*ceil(Build_Data(idx,11)));
end

if numel(unique(matched_ids)) < n_hotels
    warning('Two or more hotels matched the SAME building - check matched IDs/distances above before proceeding.');
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
