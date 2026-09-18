function [Build_Data,Build_Data_p]=find_empty_buildings_arad(Assets,Build_Data,Build_Data_p)
% Arad-only variant of find_empty_buildings.m. The shared version
% permanently reclassifies ANY residential building (usage=1) as
% non-residential (usage=0) the instant it has zero occupied assets, even
% momentarily - checked every 4 weeks, irreversible. Arad's building
% stock is unusually fragmented (50.9% of residential buildings have only
% 1-2 units - see modellab investigation 2026-09-17), so ordinary
% household turnover trivially drives small buildings to momentary zero
% occupancy, triggering permanent removal and compounding into a runaway
% ~50% population loss over 150 weeks in a no-shock baseline. Confirmed
% via diagnostics that this is independent of land-use conversion
% (Change_LU) and job-creation multipliers - disabling/tripling both left
% the collapse essentially unchanged - and that loosening Arad's vacancy
% calibration (7% -> 10%) didn't help either, since it doesn't change the
% underlying unit-count-per-building distribution.
%
% Fix: exempt buildings with <=2 total units from ever being reclassified
% here - they can still show as transiently "empty" (col 18, used by
% building_score.m's local-emptiness scoring - left untouched/accurate),
% just never lose their residential usage code over it. Buildings with 3+
% units keep the original unconditional behavior.
%
% Only wired into run_model_earthquake_shelteroverflow.m for
% city=='Arad' (see its two find_empty_buildings call sites) - every
% other city keeps calling the original, unmodified find_empty_buildings.m.
SMALL_BLDG_UNIT_THRESHOLD = 2;

[locA,~]=ismember(Build_Data(:,1),Assets(Assets(:,11)==1,2)); % match building ID only for occupied assets

if size(Build_Data_p,2)==17
    Build_Data_p=[Build_Data_p,'empty']; % set header
end
Build_Data(:,18)=locA; % col(18) set occupied assets True
a=Build_Data(:,3)>1; % all usage excluding living
Build_Data(a,18)=1; % set all but living True

% units per building (from ALL assets, occupied or not - a building's
% total unit count, not just how many are currently filled)
[~,bld_idx]=ismember(Assets(:,2),Build_Data(:,1));
n_units=accumarray(bld_idx(bld_idx>0),1,[size(Build_Data,1),1]);
small_bldg=n_units<=SMALL_BLDG_UNIT_THRESHOLD;

Build_Data(Build_Data(:,18)==0 & ~small_bldg,3)=0; % 'Usage'=0 - skip small buildings

Build_Data(:,18)=abs(Build_Data(:,18)-1); % invert col(18) - unchanged, stays an accurate "is empty" signal
