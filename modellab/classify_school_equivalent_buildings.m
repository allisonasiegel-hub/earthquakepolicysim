function Build_Data = classify_school_equivalent_buildings(Build_Data, school_fraction)
% Reclassifies the largest usage=5 (generic public) buildings as usage=8
% (school) so they become eligible for assign_shelter.m's public/school
% shelter tier under the model's restrict_public_shelters_to_schools=1
% default (run_model_earthquake_shelteroverflow.m), which otherwise
% excludes usage=5 entirely.
%
% Motivation: most cities in this repo have zero usage=8 buildings at all
% - their raw source data (USG_CODE_keys.csv mapping) simply doesn't
% distinguish schools from other public buildings, unlike Tiberias, which
% has 24 real usage=8 buildings out of 501 public+school (4.79%). Checked
% 2026-09-19: Jerusalem, Ashkelon, Beer Sheva, and Arad all have usage=8
% count=0, meaning the in-city "immediate" shelter tier is a structural
% no-op for all of them under the current default policy.
%
% Method (derived from Tiberias's real schools, the only ground truth
% available): Tiberias's 24 schools are 4.79% of its public+school
% buildings, with floor-adjusted area (Area*floors, matching
% assign_shelter.m's own capacity formula) ranging 107.8-3273.2 sqm
% (median 851.1) - noticeably larger than Tiberias's own non-school
% public buildings (median 244.4). Using the full Tiberias min-max range
% as a straight size filter is too loose elsewhere (67% of Arad's public
% buildings fall in that wide range, vs. Arad's public-building median of
% just 203.8 - Arad's non-school public buildings span the same range
% Tiberias's do, so size range alone doesn't discriminate well). Instead:
% take the N LARGEST usage=5 buildings by floor-adjusted area, where N is
% sized to match Tiberias's 4.79% share of the city's public+school pool
% - this combines both criteria the way Tiberias's real data actually
% supports (schools are both a small minority AND skew toward the largest
% public buildings), rather than a raw size cutoff that individually
% under- or over-selects.
%
% school_fraction (optional, default 0.0479): Tiberias's real
% school-share ratio (24/501). Overridable so a caller can test
% sensitivity to this exact figure.
%
% NOT auto-applied - call explicitly per city (see the Arad case's
% load-time call in run_model_earthquake_shelteroverflow.m) so this
% doesn't silently change behavior for cities that haven't opted in.
if nargin<2 || isempty(school_fraction); school_fraction=0.0479; end

is_public = Build_Data(:,3)==5;
n_public = sum(is_public);
n_target = round(n_public * school_fraction);
if n_target < 1
    return
end

floor_adjusted_area = Build_Data(:,7).*Build_Data(:,11);
public_idx = find(is_public);
[~,order] = sort(floor_adjusted_area(public_idx),'descend');
top_idx = public_idx(order(1:min(n_target,length(order))));
Build_Data(top_idx,3) = 8;
