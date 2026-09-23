
% SHELTERING POLICY EXTENSIONS VARIANT + SHELTER-OVERFLOW (this file):
% forked from run_model_earthquake.m, adding what happens when the
% in-city shelter mechanism runs out of available public buildings (see
% shelter_policy_extensions_handoff.md item 5, "sheltering outside the
% city, commuting in"). Inherited from run_model_earthquake.m:
%   - Shock delivery: one-time earth_quake() trigger (same pattern as the
%     original run_model_eq.m).
%   - Sheltering: the ORIGINAL per-agent assign_shelter.m/release_shelter.m
%     mechanism , extended with
%     retry/exit logic (no max duration - see run_model_earthquake.m's
%     header for the full description) and hotels as a second "immediate"
%     shelter-candidate pool alongside public buildings, with their own
%     room-density-based capacity formula (hotel_room_density *
%     agents_per_room * Area * floors) - see run_model_earthquake.m's
%     header and identify_hotels_TVR.m for how hotel_room_density is
%     calibrated. Hotels are excluded from the routine activity-location
%     draw pool but do NOT yet participate in land-use/job-creation
%     dynamics (separate follow-up work).
%   -  The find_new_house_sa_score.m SA-score bug fix is applied
%      . Subsidy logic matches
%     run_model_eq.m's flat-amount version;
%
% NEW IN THIS FORK - shelter overflow ("sheltered outside the city"):
%   When assign_shelter.m runs out of available public buildings
%   (unsheltered_agents, its new optional output), the leftover displaced
%   households are NOT deleted - they're tracked in Sheltered_Outside
%   ([HH_ID, start_step, income_penalty_amount], no capacity limit) and:
%     1. Search: treated exactly like in-city sheltered households -
%        folded into the moving_HH pool every step, exempt from
%        did_not_find_house deletion, retried via the same
%        find_new_house_same_stat cascade (same-SA -> same-yeshuv ->
%        other-yeshuv) "movers"/migrants use. No duration cap - see
%        release_outside_shelter.m.
%     2. Return: released via release_outside_shelter.m the same way as
%        in-city shelter - either they secure a new asset, or their
%        original home building recovers (HH_data was never repointed
%        away from it while sheltered outside).
%     3. Job continuity: a working member keeps their existing job -
%        nothing in this mechanism touches Work_places/Individuals_data
%        job columns, so this is true by construction.
%     4. Work-only routine: local (non-work) routine participation is
%        suppressed by NaN-ing Building_routine_id cols 4:end for their
%        agents every step (col 3 = work location is left untouched) -
%        reapplied each step in case the routine engine reassigns local
%        activities to them for an unrelated reason. Restored naturally
%        once they move (the normal HH_change -> new_number_of_routine ->
%        find_activity_location_new_A path regenerates a full routine).
%     5. Commute penalty: stylized as a flat income haircut
%        (outside_commute_penalty_pct of HH_data(:,6)) applied at entry
%        and restored (exact dollar amount, from Sheltered_Outside col 3)
%        at exit - a simplification of "exclusion from the normal D_work
%        preference term with a fixed penalty substituted" per the
%        handoff, chosen to avoid touching pref_hh.m/SA_score_old.m
%
%   - Multi-city support: a `city` configuration block (top of the loop)
%     picks the data file, folder, and calibration constants for the
%     selected city. Set `city` (or let a sweep/batch driver pre-set it)
%     to switch cities - see that block's header comment for what's
%     validated vs. a TODO placeholder per city.
%
% REQUIRES a per-SA damage table at [file,'earthquake_damage.csv'] for
% whichever city is selected (columns SAID, dmg_prc - see earth_quake.m
% for accepted formats). Ashkelon's is NOT included in this repo yet;
% earth_quake.m will throw a clear error if it's missing. Drop the real
% damage assessment in before running.
%
% NOTE: shock_step defaults to 900 (inherited below), same as the
% original script. With the default steps=200 (or whatever a sweep
% driver sets), the shock never actually triggers. To exercise the
% earthquake/shelter logic in this file, set shock_step (and steps) so
% the shock actually happens within the run, e.g. shock_step=40, steps=200.


tic
% RNG seed: MATLAB initializes rand/randn/randperm to the SAME fixed
% default seed at the start of every fresh process - confirmed 2026-09-09
% (two separate `matlab -batch` invocations produced byte-identical
% rand(1,3) output). This silently made separate-process replicates (e.g.
% each n_sims=1 run launched as its own process to sidestep the
% n_sims>=2-in-one-process crash seen on the shock scenario) deterministic
% repeats rather than independent draws - all 5 shock replicates landed on
% the exact same trajectory. Reseed from time/process entropy by default so
% separate processes actually diverge; a driver can pass rng_seed to pin a
% specific seed instead, for exact reproducibility when that's wanted.
if ~exist('rng_seed','var')
    rng('shuffle');
else
    rng(rng_seed);
end
% run_timestamp: stable for this whole script invocation (all kk
% replicates), but changes between separate runs - keeps saved outputs
% from clobbering each other run-to-run (kk alone only distinguishes
% replicates within a single run).
run_timestamp = datestr(now, 'yyyymmdd_HHMMSS');
% run_uid: uniquely identifies THIS MATLAB process (same fix as
% modelthesis/run_model_earthquake.m) - run_timestamp alone is only
% second-resolution and shared for the whole script invocation, so two
% `matlab -batch` processes launched concurrently (e.g. running a
% parameter sweep or several replicates in parallel) can land on the
% exact same run_timestamp+kk and silently overwrite each other's output
% .mat files. Defaults to the OS process ID (unique across concurrently
% running processes) - lets multiple runs of this script execute at once
% (separate `matlab -batch` invocations, or a parfor-based sweep driver)
% without output collisions.
if ~exist('run_uid','var'); run_uid=sprintf('pid%d', feature('getpid')); end
% n_sims: outer replicate count. Only the LAST kk's outputs survive for a
% sweep caller (run_sweep_setting captures post-clearvars state), so sweep
% drivers set n_sims=1 to avoid paying for a discarded first replicate.
% Standalone runs keep the original default of 2.
if ~exist('n_sims','var'); n_sims=2; end
sims=n_sims;
for kk = 1:sims
        %kk;kk

%% City configuration
% Set `city` (or let a sweep/batch driver pre-set it before calling run())
% to pick which city this run targets. `file` points at each city's own
% data folder for sas_national.xlsx/commuting.xlsx/earthquake_damage.csv,
% EXCEPT Ashkelon (see that case's comment - its modellab\ASH22 folder
% has an incompatible sas_national.xlsx). JobsPerM_comm is hardcoded per
% city below (from each city's own model parameters.csv) rather than read
% dynamically at runtime - avoids assuming a single folder always has
% every needed ancillary file, which turned out false for Ashkelon.
% commute_outside and the wage-adjustment constants (alfa/beta/lamda/
% delta) have NO safe automatic source - a naive per-city
% spreadsheet-cell convention (commute_outside=commute(2,5), used in
% run_model_eq.m) was checked against Ashkelon's own commuting.xlsx and
% found to read the WRONG cell entirely. Only Ashkelon's values below are
% validated/in active use; the other cities are explicit NaN placeholders
% - the script errors out immediately if you select one before filling
% them in, rather than silently running with garbage calibration.
if ~exist('city','var'); city='Ashkelon'; end
switch city
    case 'Ashkelon'
        % data_for_model_Ash2hotels (NOT the plain data_for_model_Ash2, and
        % NOT "..._Ash2_hotels" with an underscore before "hotels" - that
        % would make its last '_'-split token 'hotels', colliding with
        % Tiberias's data_for_model_TVR_hotels (SAME last token), which
        % would make BOTH cities' output files share the identical
        % "hotels EQ S..." earthquakeF/ filename prefix, indistinguishable
        % by pattern) -
        % identical except 3 buildings are tagged usage=7 (hotel) by
        % identify_hotels_ASH.m: Tamara Ashkelon (bldg 52453214), Hotel
        % Regina Goren (52566795), Golden Tower (52661601) - matched by
        % nearest-building distance from each hotel's real WGS84
        % coordinates (converted to ITM via wgs84_to_itm.m, validated
        % against the ITM origin point). Drop-in replacement, safe
        % default - same convention as Tiberias's hotel-tagged dataset.
        data='data_for_model_Ash2hotels';
        % file: now self-contained in modellab\ASH22\ (no longer pointing
        % outside the repo at testingcodechanges\) - sas_national.xlsx there
        % was replaced with the content of ASH22\sas_national1.xlsx, which
        % has the correct 15-col layout (matching TVR/JER's format) AND is
        % already Ashkelon-specific (statID all 71000xxx), unlike the
        % previous ASH22\sas_national.xlsx (5 cols - incompatible with
        % read_sas_data.m's hardcoded column indices, backed up as
        % sas_national_5col_incompatible_backup.xlsx) and unlike
        % testingcodechanges\sas_national.xlsx (correct layout but
        % NATIONAL-scope, needing the unique_stat runtime filter below to
        % narrow to Ashkelon). earthquake_damage.csv here is a real per-SA
        % assessment (dmg_prcA/dmg_prcB/dmg_prc columns, like TVR's) -
        % replacing the earlier synthetic testing-only placeholder.
        file=[fileparts(mfilename('fullpath')),'\ASH22\'];
        commute_outside=0.778038196; % validated, in active use
        alfa=0.3; beta=0.8; lamda=0.45; delta=0.75; % Ashkelon-calibrated, validated (lamda changed from 0.95 to 0.45 2026-09-15, testing)
        % Default matches modellab\ASH22\model parameters3.csv (not the
        % unnumbered model parameters.csv, 0.007790361 - ~4x lower).
        % Overridable so a driver can isolate the parameter-scaling effect
        % (params vs. params3) while holding everything else, including
        % the land-use conversion window, fixed - see
        % run_ashkelon_full_default_window_params.m /
        % _params3.m.
        if ~exist('JobsPerM_comm','var'); JobsPerM_comm=0.031161443; end
        % rooms per sqm floor-adjusted area - 404 real rooms / 13,830 sqm
        % across the 3 tagged hotels (identify_hotels_ASH.m) - same
        % formula as Tiberias's calibration, just over 3 buildings
        % instead of 39.
        hotel_room_density=0.02921;
    case 'Tiberias'
        % data_for_model_TVR_hotels (NOT the plain data_for_model_TVR) -
        % identical except 39 buildings are tagged usage=7 (hotel) by
        % identify_hotels_TVR.m. Drop-in replacement, safe default.
        data='data_for_model_TVR_hotels';
        file=[fileparts(mfilename('fullpath')),'\TVR\']; % sas_national.xlsx here verified same 15-col layout as testingcodechanges
        commute_outside=0.246; % matches modelthesis's validated commute_outside_rate (Tiberias zone-99 share)
        % alfa/beta/lamda/delta (wage-adjustment/income_ratio mechanism):
        % defaults match modelthesis's validated values. Made overridable
        % (like city/steps/shock_step) so alternate wage-adjustment
        % calibrations can be tested without editing this file.
        if ~exist('alfa','var'); alfa=0.3; end
        if ~exist('beta','var'); beta=0.8; end
        if ~exist('lamda','var'); lamda=0.95; end
        if ~exist('delta','var'); delta=0.75; end
        JobsPerM_comm=0.008932703; % matches modellab\TVR\model parameters.csv
        hotel_room_density=0.02128; % rooms per sqm floor-adjusted area - see identify_hotels_TVR.m
    case 'Jerusalem'
        data='data_for_model_JER'; % compiled via data_allocation/main_alloc.m, validated against census (see data_allocation/VALIDATION_AND_FIXES.md)
        file=[fileparts(mfilename('fullpath')),'\JER\']; % sas_national.xlsx here verified same 15-col layout as testingcodechanges
        % commute_outside: zone-99 share read directly from JER\commuting.xlsx
        % (settlement 3000 = Jerusalem's real CBS code, row2/col5=0.149) -
        % same cell-reading convention that matched Tiberias's independently-
        % validated commute_outside_rate exactly (0.246). CAVEAT: the same
        % convention read the WRONG value for Ashkelon (commuting.xlsx gives
        % 0.379 there vs. the actual validated 0.778038196), so this is a
        % best-available data-driven placeholder, not cross-validated the way
        % Ashkelon/Tiberias's values are - revisit if Jerusalem runs look off.
        commute_outside=0.149;
        alfa=0.3; beta=0.8; lamda=0.95; delta=0.75; % reused from Ashkelon/Tiberias - alfa/beta/delta proven to have no measurable effect on outcomes (modelthesis HANDOVER.md), lamda not yet independently tuned for any city in modellab
        JobsPerM_comm=0.0440838; % matches modellab\JER\model parameters.csv
        hotel_room_density=0; % no hotel buildings tagged for this city - harmless, the hotel candidate pool is simply empty
    case 'Arad'
        % data_for_model_Aradhotels (NOT the plain data_for_model_Arad) -
        % generated via data_allocation/run_generate_arad.m (Arad/ raw
        % data had never been ported before; see that script's header for
        % the unit_size_scale=1.256 vacancy calibration, ~7% vacancy),
        % then identify_hotels_Arad.m tags Arad's 3 known real hotels
        % (Roxon Desert Arad, Hotel Inbar Arad, Yehelim Boutique Hotel -
        % 230 total real rooms) as usage=7, same convention as
        % Ashkelon/Tiberias's hotel-tagged datasets. Drop-in replacement,
        % safe default.
        %
        % hotel_room_density=0.15029 (230 rooms / 1530 sqm floor-adjusted
        % area across the 3 tagged buildings) - notably higher than
        % Ashkelon's 0.02921 or Tiberias's 0.02128. Roxon Desert Arad's
        % nearest-matched building (67178859, 57.7m away) has a Area=254
        % sqm footprint implausible for a real 118-room hotel (~2.2
        % sqm/room) - checked its 7 nearest neighbors (77-97m away, none
        % meaningfully larger), so this reads as Arad's building dataset
        % not well capturing this specific hotel's true footprint, not a
        % bad nearest-building match. Also had floors=0 recorded (valid
        % Area, missing floor count, not NaN so it wasn't caught by
        % start_spatial_dataupdate.m's mean-fill) - identify_hotels_Arad.m
        % patches that to floors=1 before calibrating. Kept the combined
        % 3-hotel density as-is (not backing Roxon out of the calibration)
        % per explicit confirmation 2026-09-19 - see identify_hotels_Arad.m's
        % header for the full writeup.
        data='data_for_model_Aradhotels';
        file=[fileparts(mfilename('fullpath')),'\Arad\']; % sas_national.xlsx here verified same 15-col layout as testingcodechanges
        % commute_outside: zone-99 share read directly from Arad\commuting.xlsx
        % (settlement 2560 = Arad's real CBS code, row2/col5=0.34) - same
        % cell-reading convention used for Jerusalem/Beer Sheva. Cross-checked
        % against Arad\sa_data_b7.csv's own per-SA comm99 column: population-
        % weighted average across all 6 SAs = 0.338, matching closely -
        % trustworthy for this city's file.
        commute_outside=0.34;
        % alfa/beta/lamda/delta: no prior modellab/modelthesis calibration
        % exists for Arad. Overridable (like Tiberias/Beer Sheva) so a driver
        % can set them explicitly; defaults below are this baseline run's
        % requested values, not a validated calibration.
        if ~exist('alfa','var'); alfa=0.30; end
        if ~exist('beta','var'); beta=0.95; end
        if ~exist('lamda','var'); lamda=0.95; end
        if ~exist('delta','var'); delta=0.50; end
        JobsPerM_comm=0.03400486; % matches modellab\Arad\model parameters.csv
        hotel_room_density=0.15029; % rooms per sqm floor-adjusted area - see identify_hotels_Arad.m
    case 'Beer Sheva'
        % data_for_model_BS08hotels (NOT the plain data_for_model_BS08) -
        % identical except 3 buildings are tagged usage=7 (hotel) by
        % identify_hotels_BS08.m. Drop-in replacement, safe default -
        % same convention as Ashkelon/Tiberias. Base data_for_model_BS08
        % generated via data_allocation/run_generate_beersheva.m (BS08/
        % raw data had never been ported before; see that script's header
        % for the census-units fix and the unit_size_scale=1.58 vacancy
        % calibration, ~7% vacancy).
        data='data_for_model_BS08hotels';
        file=[fileparts(mfilename('fullpath')),'\BS08\'];
        % commute_outside: zone-99 share read directly from BS08\commuting.xlsx
        % (settlement 9000 = Beer Sheva's real CBS code, row30/col5=0.519454) -
        % same cell-reading convention used for Jerusalem; matches BS08\
        % sa_data_B7.csv's own comm99 column for SA 90000111 (0.519454138),
        % so trustworthy for this city's file. Not independently cross-
        % validated the way Ashkelon/Tiberias's values are.
        commute_outside=0.519454;
        % alfa/beta/lamda/delta: no prior modellab/modelthesis calibration
        % exists for Beer Sheva. Overridable (like Tiberias) so a driver can
        % set them explicitly; defaults below are this baseline run's
        % requested values, not a validated calibration.
        if ~exist('alfa','var'); alfa=0.40; end
        if ~exist('beta','var'); beta=0.60; end
        if ~exist('lamda','var'); lamda=0.25; end
        if ~exist('delta','var'); delta=0.80; end
        JobsPerM_comm=0.013952158; % matches modellab\BS08\model parameters.csv
        % rooms per sqm floor-adjusted area - 299 real rooms (CBS Table D/7,
        % Sept 2023, hotelrooms.pdf) / 57,609 sqm across the 3 raw-code-
        % confirmed hotels (Usage=5900 in BS08\bldgs_height_tt.csv, exactly
        % matching the CBS count - no backfill needed) - see
        % identify_hotels_BS08.m.
        hotel_room_density=0.00519;
    otherwise
        error('Unknown city "%s" - add a case for it to the city configuration block.', city);
end
%if any(isnan([commute_outside,alfa,beta,lamda,delta]))
    %error(['City "%s" is missing calibration values (commute_outside/alfa/beta/lamda/delta) ' ...
       % 'in the city configuration block - fill them in before running.'], city);
%end

data2 = split(data, '_');
load(data);
% Arad, Beer Sheva, Ashkelon, and Jerusalem have zero usage=8 (school)
% buildings in their source data - only Tiberias has real school tags -
% which makes the in-city "immediate" public-shelter tier a structural
% no-op under restrict_public_shelters_to_schools=1 (assign_shelter.m
% only accepts usage=8). classify_school_equivalent_buildings.m derives a
% school-equivalent subset from Tiberias's real school data (4.79% of
% public+school buildings, skewed toward the largest) - see that
% function's header for the full method. Ported to Ashkelon and Jerusalem
% 2026-09-19 (chat that day) on top of the original Arad/Beer Sheva
% application - every city with this gap now opts in.
if strcmp(city,'Arad') || strcmp(city,'Beer Sheva') || strcmp(city,'Ashkelon') || strcmp(city,'Jerusalem')
    Build_Data = classify_school_equivalent_buildings(Build_Data);
end
% resSearchLen retry mechanism (ported from
% modelthesis/run_model_earthquake.m): col 13 tracks each HH's consecutive
% failed housing-search attempts. did_not_find_house.m deletes a household
% immediately with zero retry tolerance - modelthesis identified this as
% the cause of a ~85% population collapse over 30 steps, timed with
% land-use activation (conversions shrink the residential stock, ordinary
% movers' searches start failing, and with no retry budget every one of
% them was deleted on the very first miss). col 13 is a fresh append -
% HH_data has no existing col 13+ usage in this script. Land-use-evicted
% households are NOT part of this mechanism - they already get their own
% separate multi-step grace period via LU_Displaced/outside_patience_duration
% further below, a mechanism modelthesis doesn't have.
HH_data(:,13)=0;
% original_HH_ids: snapshot of every household ID present at load time,
% before any migration/shock/routine dynamics run this replicate. Used to
% distinguish "original-cohort attrition" (n_original_hh_permanently_
% displaced_total, below) from n_permanently_displaced_total's raw event
% count, which also counts newly-migrated-in households (created by
% migration_19.m to fill vacant housing) that later themselves get
% permanently displaced - the two can differ substantially since the city
% keeps gaining new households throughout the run, independent of the
% shock.
% original_HH_ids_remaining: mutable copy, pruned as each original
% household is counted displaced (see the accumulator below) - NEEDED
% because migration_19.m assigns new household IDs as
% max(HH_data(:,2))+1, which can hand out an ID number that collides with
% an EARLIER (already-departed) original household's ID once enough
% churn has occurred - without pruning, a later migrant who happens to
% reuse an original ID and is themselves later displaced would get
% double-counted as if the original household left twice. Confirmed this
% matters in practice: an Arad 250-step shock run hit
% n_original_hh_permanently_displaced_total=11521, exceeding the entire
% 9669-household original population, before this fix.
original_HH_ids = HH_data(:,2);
original_HH_ids_remaining = original_HH_ids;
[sas_data,intra_SA,intra_P]=read_sas_data(file,'sas_national.xlsx'); %SA data
% BUG FIX (Tiberias only): read_sas_data.m treats intraSAProb/
% intraYeshuvProb (raw xlsx cols 11-12) as DAILY probabilities and
% converts to weekly via 1-(1-p)^7 - confirmed correct for Ashkelon
% (day_to_week_step_rescaling_audit.md item 2), but Tiberias's raw
% values are ~1000x larger (median intraSAProb 0.0256 vs Ashkelon's
% 0.0000336) - the SAME "dimensionless ratio misused as a rate" pattern
% already found and fixed for inOutRatio in this same file (see
% migration_19.m). Reinterpreting Tiberias's raw values as ANNUAL rates
% instead brings them within ~2-5x of Ashkelon's actual daily-scale
% values (not ~1000x), and empirically fixes both the model's behavior
% (previously ~10-48% of the population attempting a move every single
% week - implausible for any real city) and performance (was 11.7x
% slower than Ashkelon despite having fewer households; now faster than
% Ashkelon, matching its smaller population as expected).
if strcmp(city,'Tiberias')
    [~,~,raw_sas_tvr]=xlsread([file,'sas_national.xlsx']);
    raw_intraSA = cell2mat(raw_sas_tvr(2:end,11));
    raw_intraYeshuv = cell2mat(raw_sas_tvr(2:end,12));
    intra_SA(:,2) = 1-(1-raw_intraSA).^(7/365);
    intra_SA(:,3) = 1-(1-raw_intraYeshuv).^(7/365);
    clearvars raw_sas_tvr raw_intraSA raw_intraYeshuv
    % CALIBRATION (Tiberias only): migration_19.m uses inOutRatio
    % (col 5) directly as an annual in-migration rate against each SA's
    % vacant-housing count (free_assets) - the data source/mechanism
    % itself is kept as-is (not switched to modelthesis's
    % real_growth_rate approach). The /17.7 factor below was derived
    % against the PRE-density-fix dataset (34,162 assets, ~47% vacant,
    % free_assets~=16,196) - a 200-step no-shock baseline grew population
    % 17,966 -> 31,804 (+77%) vs. the +4.3% expected from real per-SA
    % Tiberias census growth rates (modelthesis/TVR/real_growth_rates.csv,
    % +1.11%/year city-wide, compounded over ~3.85 years) - ~17.7x
    % overshoot. NEEDS RE-CALIBRATION after the housing-density fix
    % (see data_allocation/run_regenerate_tveria_fix.m): free_assets
    % dropped ~8x (to ~1,979 at 10% vacancy), and this mechanism scales
    % ~linearly with free_assets, so /17.7 badly under-shot growth on the
    % new dataset. RE-CALIBRATED (2026-09-15) against the post-density-fix
    % dataset: a 200-step no-shock baseline with no correction
    % (tiberias_inoutratio_scale=1) grew population 17,450 -> 18,808
    % (+7.78%) vs. the +4.35% expected (17,450*(1.0111)^3.85=18,209) -
    % only a ~1.79x overshoot now (raw net growth 1358 / expected net
    % growth 759), much smaller than the original ~17.7x since the
    % density fix already removed most of the excess free_assets "fuel"
    % this mechanism scales with. Overridable so the correction can be
    % re-derived again if the dataset changes further.
    if ~exist('tiberias_inoutratio_scale','var'); tiberias_inoutratio_scale=1.79; end
    intra_SA(:,5) = intra_SA(:,5) / tiberias_inoutratio_scale;
end
% BUG FIX (Arad only): same "daily probability" misinterpretation as
% Tiberias above - Arad's sas_national.xlsx raw intraSAProb/intraYeshuvProb
% (median 0.0237/0.0562) are essentially identical in magnitude to
% Tiberias's known-buggy values (median 0.0256), both sourced from the
% same shared national table and both ~700x larger than Ashkelon's
% confirmed-correct value (0.0000336) - NOT an Arad-specific data anomaly,
% the same systemic issue. Left uncorrected, who_is_moving.m's
% 1-(1-p)^7 daily->weekly conversion (read_sas_data.m) produces a 13-22%
% weekly move probability per SA - "10-48% of the population attempting a
% move every single week" was exactly the failure mode already diagnosed
% for Tiberias (~85% population collapse over 30 steps, timed with
% land-use activation - see the BUG FIX comment above). Confirmed via
% modellab diagnostics 2026-09-18: an Arad no-shock baseline still lost
% ~49% of its population in the first ~40 weeks even with ALL building-
% stock loss mechanisms (find_empty_buildings_arad.m, Change_LU) disabled
% entirely and housing prices falling (not scarce) throughout - ruling out
% supply/affordability and pointing at excess churn overwhelming the
% one-attempt-per-step housing search cascade instead. Same fix as
% Tiberias: reinterpret the raw values as ANNUAL rates, which brings the
% weekly probability down to a plausible ~0.04-0.07%.
if strcmp(city,'Arad')
    [~,~,raw_sas_arad]=xlsread([file,'sas_national.xlsx']);
    raw_intraSA = cell2mat(raw_sas_arad(2:end,11));
    raw_intraYeshuv = cell2mat(raw_sas_arad(2:end,12));
    intra_SA(:,2) = 1-(1-raw_intraSA).^(7/365);
    intra_SA(:,3) = 1-(1-raw_intraYeshuv).^(7/365);
    clearvars raw_sas_arad raw_intraSA raw_intraYeshuv
end
unique_stat=unique(Build_Data(:,4));
intra_SA=intra_SA(ismember(intra_SA(:,1),unique_stat),:);
% Backfill: sas_national.xlsx (ASH22's sas_national1.xlsx content, now in
% use for Ashkelon) is missing intra_SA rows for a handful of SAs that
% Build_Data still references - a real coverage gap in that source table,
% not a bug (the earlier national-scope testingcodechanges table had every
% SA; this Ashkelon-specific one doesn't). Without a row, who_is_moving.m's
% per-SA lookup comes back empty and crashes comparing against it. Per-city
% choice (not a general fallback in read_sas_data.m itself): stand in with
% a randomly-chosen EXISTING SA's row (intraSAProb/intraYeshuvProb/
% interYeshuvProb/inOutRatio/etc.) for each missing one.
missing_SAs = setdiff(unique_stat, intra_SA(:,1));
if ~isempty(missing_SAs)
    donor_idx = randi(size(intra_SA,1), numel(missing_SAs), 1);
    backfill_rows = intra_SA(donor_idx,:);
    backfill_rows(:,1) = missing_SAs;
    intra_SA = [intra_SA; backfill_rows];
end
random_number=rand(size(HH_data,1)*4,1);
comm_policy=0;
min_sal = 5000; % min salary according to BTL in 2017
sims=30;
if ~exist('steps','var'); steps=200; end % allow a sweep driver to pre-set this for faster test runs
% resSearchLen: max consecutive failed housing-search attempts before a HH
% actually leaves the city (see HH_data col 13, set at load time above).
% Ported from modelthesis/run_model_earthquake.m, which scales this with
% run length (14 fails tolerated over a 760-step run). Fixed at a flat
% baseline of 4 for every city instead (chat 2026-09-20) - not derived
% from steps. Overridable so a driver/sweep can test a different retry
% budget.
if ~exist('resSearchLen','var'); resSearchLen=4; end
% earthquake severity comes from the per-SA damage
% table passed to earth_quake() instead, see the shock block below)
shock=0;
if ~exist('shock_step','var'); shock_step=900; end % allow a sweep/test driver to pre-set this
% Land-use conversion calibration -- multipliers on the city's own base
% JobsPerM_comm (city configuration block above), not absolute values, so
% the same calibration philosophy can be tested against any city's own
% base rate. Defaults (1/1/20/40) reproduce this script's original,
% unmultiplied behavior exactly if a caller doesn't override them --
% existing city runs are unaffected unless a driver script pre-sets
% these. modelthesis's validated Tiberias calibration is
% jobs_per_meter_multiplier=3, potential_jobs_per_meter_multiplier=2,
% lu_change_rank_lower=45, lu_change_rank_upper=85 -- see
% run_tiberias_calibrated.m for a ready-made driver setting these.
if ~exist('jobs_per_meter_multiplier','var'); jobs_per_meter_multiplier=1; end % scales JobsPerM_comm for ACTUAL job creation in newly-converted commercial buildings (New_Comm_B block)
if ~exist('potential_jobs_per_meter_multiplier','var'); potential_jobs_per_meter_multiplier=1; end % scales JobsPerM_comm for the POTENTIAL-conversion candidate-scoring step (pot_sal_for_B block) -- deliberately separate from jobs_per_meter_multiplier, matching modelthesis's lu_jobs_per_meter vs lu_potential_jobs_per_meter split
if ~exist('lu_change_rank_lower','var'); lu_change_rank_lower=20; end % lower bound of the visit-vs-salary rank-diff window (V_vec) that selects which candidate buildings actually convert to commercial
if ~exist('lu_change_rank_upper','var'); lu_change_rank_upper=40; end % upper bound of that window
% Steps represent WEEKS, not days (see day_to_week_step_rescaling_audit.md)
% - every duration/rate constant below is calibrated accordingly. shock_step
% and steps itself are run-length choices, not something this rescale
% changes automatically - a caller setting shock_step=40 now means 40
% weeks, not 40 days.
% RECOVERY: weekly per-building probability of recovering (see the
% probabilistic recovery block below - replaces the old deterministic
% shared-countdown mechanism entirely, not just a /7 rescale). Derived
% from real reconstruction-timeline data: 31.35% of residential housing
% recovered within 1 year (52 weeks) on average -> solve
% 1-(1-p)^52 = 0.3135 for p. Applied uniformly to all building types
% (not just residential) per explicit decision - see
% day_to_week_step_rescaling_audit.md.
RECOVERY = 1 - (1-0.3135)^(1/52);
%% Polocies
% Subsidy logic: targeted variants via HH_subsidy_targeted.m /
% cal_bui_sa_subsidy_targeted.m (NOT the shared flat-amount HH_subsidy.m /
% cal_bui_sa_subsidy.m that run_model_eq.m and run_model_earthquake.m
% still use unmodified, and NOT the elderly-thesis percentage/elderly-
% premium version - HH_subsidy_pct.m, subsidy_pct, w_subsidy_eld. Not
% elderly-specific, so it belongs in this project).
%
% subsidy_residents_mode: 0=off, 5=displaced households only, decile-
% tiered % of housing cost (decile 7-10: 30%, 4-6: 35%, 1-3: 40%), fixed
% 4-step duration regardless of subsidy_duration, 6=displaced households
% only, decile-tiered % of housing cost (decile 7-10: 10%, 4-6: 15%,
% 1-3: 20%), fixed 8-step duration regardless of subsidy_duration. (Modes
% 1-4 were early, since-superseded designs, removed 2026-09-18.) See
% HH_subsidy_targeted.m's header for the full writeup.
if ~exist('subsidy_residents_mode','var'); subsidy_residents_mode=0; end
% subsidy_businesses_mode: 0=off, 1=destroyed commercial buildings only
% (the original cal_bui_sa_subsidy.m behavior), 2=destroyed commercial
% buildings UNION the smallest 30% of commercial buildings by current
% worker headcount, 3=destroyed commercial buildings only, ENTIRE wage
% bill zeroed for a fixed 4-step (1-month) window (closer to the
% original rocketattack/RABM-matlab cal_bui_sa_subsidy.m treatment),
% 4=destroyed commercial buildings only, HALF the wage bill counted for a
% fixed 12-step (3-month) window - see cal_bui_sa_subsidy_targeted.m.
if ~exist('subsidy_businesses_mode','var'); subsidy_businesses_mode=0; end
subsidy_duration=9; % was 60 days (~2 months) -> ~9 weeks
priority_recovery=0; % faster recovery of residential
recovery_factor=2.5;
displaced_shelter=1; % toggle: 0=off (baseline), 1=on - shelter policy of public turn to 99
agents_per_sqm=0.2;
% agents_per_room: hotel-shelter occupancy assumption (people per room),
% used with hotel_room_density (city configuration block) to convert
% estimated room counts into shelter agent capacity. Placeholder value -
% not yet set through sensitivity testing.
agents_per_room=2;
% public_bldg_usable_fraction: fraction of a public/school building's
% gross floor area (Area*floors) that's actually usable shelter space -
% accounts for hallways, offices, fixed-furniture rooms, upper floors
% without elevator access, etc. Without this, agents_per_sqm alone
% (~5 sqm/person, a reasonable Sphere-standard density) applied to 100%
% of gross floor area badly overstates real capacity - for Tiberias,
% total public capacity (80,113) otherwise exceeds the entire city
% population (50,419). Placeholder value - not yet set through
% sensitivity testing.
public_bldg_usable_fraction=0.4;
% restrict_public_shelters_to_schools: toggle - if true, only usage=8
% (school) buildings are eligible for the public/school shelter tier
% (excludes usage=5 generic public entirely). Lets "all public buildings"
% vs. "schools only" be compared as different policy runs. Default policy:
% schools only.
restrict_public_shelters_to_schools=1;
% outside_commute_penalty_pct: stylized flat income haircut applied to
% households sheltered outside the city (shelter-overflow pool), standing
% in for a computed commute cost. Placeholder value - not yet set through
% sensitivity testing.
outside_commute_penalty_pct=0.15;
% outside_patience_duration: a household sheltered outside the city loses
% patience and leaves the simulation entirely (via the normal
% did_not_find_house path - same as any migrant who repeatedly fails to
% find housing) once it's been in Sheltered_Outside for this many steps
% AND still fails to find a house that same step. Recovering their
% original home or securing a new asset (release_outside_shelter) always
% takes priority and removes them from this pool first, so this only
% catches households that are still genuinely unhoused once patience
% runs out. Default reduced from 13 (~3 months) to 4 steps - tested
% against Ashkelon's dmg_prcB shock+hotels scenario (56 permanent
% departures out of a ~471 peak overflow, vs. just 1 at 13 steps).
% Overridable (like city/steps/shock_step) for testing alternate patience
% windows.
if ~exist('outside_patience_duration','var'); outside_patience_duration=4; end
% tempdev_patience_duration: same permanent-departure mechanic as
% outside_patience_duration, but for households in Temp_Dev_Assign
% (Temp_Dev_Assign col(3) is each household's own entry step - see its
% init comment). Ported from Ashkelon's calibration (outside=4,
% tempdev=8 weeks). With this set, temp-dev households can now also
% permanently depart via patience, same as the outside-overflow and
% land-use-eviction pools - previously only those two (small) pools
% could ever produce a permanently-displaced household, since immediate
% shelter and temp-dev had no cap at all.
if ~exist('tempdev_patience_duration','var'); tempdev_patience_duration=8; end
% Medium-term sheltering ("temporary developments" - tent city/container
% site/etc., per shelter_policy_extensions notes): a fixed number of
% abstract residential SPACES, not individual buildings - no Build_Data
% row or distance-matrix entry is ever created for them. Tracked entirely
% in Temp_Dev_Sites/Temp_Dev_Assign (initialized below, near Shelters).
% temp_dev_delay: steps after shock_step before these spaces open and
% pull households in from the immediate tier and the out-of-city overflow
% pool - see the transfer block below the main shock handling. 2 steps =
% 2 weeks at the model's current weekly step resolution.
temp_dev_delay=2; % was 14 days (2 weeks) -> 2 weeks
n_temp_dev_sites=3; % fixed count - not derived from the destroyed-building set
% temp_dev_capacity_frac: combined capacity across ALL sites = this
% fraction of the total currently-sheltered population (immediate tier +
% out-of-city overflow) at the moment the sites open, split evenly across
% n_temp_dev_sites. Not tied to any building's floor area - these aren't
% buildings. Overridable (like city/steps/shock_step) so a caller can
% define policy-comparison scenarios without editing this file. Two
% standard sheltering-policy options (chat 2026-09-20), used as one of
% the 3 policy-category axes in the full multi-city policy sweep:
%   - "limited capacity" scenario: 0.5 (default below)
%   - "everyone gets sheltered" scenario: 1.0 - note the per-site greedy
%     fill (see the transfer block below) isn't optimal bin-packing, so at
%     very large populations a handful of people could still miss by a
%     site-boundary rounding edge; negligible relative to typical
%     population sizes.
% Not yet set through sensitivity testing beyond these two named options.
if ~exist('temp_dev_capacity_frac','var'); temp_dev_capacity_frac=0.5; end
% temp_dev_site_coords: optional user-supplied [X,Y] real-world staging
% locations, one row per site (n_temp_dev_sites x 2). Leave empty to fall
% back to a data-driven siting proxy (see site_temp_dev_locations.m) -
% ranks SAs by total destroyed floor area (any usage type) and anchors
% each site at the largest still-standing building's location in one of
% the top-damaged SAs, purely as a real-world location reference (no
% building or distance-matrix row is created from it).
temp_dev_site_coords=[];
commercial_preservation=0;
residential_preservation=0;

comm_damaged_prob=0.8;
comm_undamaged_prob=0.1;

res_damaged_prob=0.7;
res_undamaged_prob=0.0;


%% filename by policy
policy_tags = {};
if subsidy_residents_mode > 0
    policy_tags{end+1} = sprintf('R%d', subsidy_residents_mode);
end
if subsidy_businesses_mode > 0
    policy_tags{end+1} = sprintf('B%d', subsidy_businesses_mode);
end
if priority_recovery
    policy_tags{end+1} = 'P';
end
if displaced_shelter
    policy_tags{end+1} = 'S';
end

if commercial_preservation
    policy_tags{end+1} = 'CP';
end

if residential_preservation
    policy_tags{end+1} = 'RP';
end

if isempty(policy_tags)
    suffix = '';
else
    suffix = [' ' strjoin(policy_tags)];
end



out_file_name = strcat(data2{end}, {' EQ'}, suffix);


%% model parameters
acts=3;
wactsnum=3;
wact1=0.5;
wact2=0.5;
Pa=12;
wresd=0.5;
w_dis_job=0.5;


first_column = Build_Data(:, 1);
unique_values = unique(first_column);
unique_matrix = [];
for i = 1:length(unique_values)
    indices = find(first_column == unique_values(i));
    unique_matrix = [unique_matrix; Build_Data(indices(1), :)];
end
Build_Data=unique_matrix;					 

%% near buildings 
Build_Distance_matrix_250=building_within_D(Build_Data,250);
Build_Distance_matrix_400=building_within_D(Build_Data,400);

pd = makedist('Normal'); % normal distribution ; used for simulation of HH moving
%% prepearing the world:
% sign empty buildings
% Arad uses a patched variant (find_empty_buildings_arad.m) that exempts
% small (<=2 unit) buildings from permanent reclassification - see that
% file's header for why. Every other city keeps the original, unmodified
% behavior.
if strcmp(city,'Arad')
    [Build_Data,Build_Data_p]=find_empty_buildings_arad(Assets,Build_Data,Build_Data_p);
else
    [Build_Data,Build_Data_p]=find_empty_buildings(Assets,Build_Data,Build_Data_p);
end

%% building service ratio -
% this function calculate the service ratio for each building
[Build_Data,Build_Data_p]=building_service_ratio(Build_Data,Build_Data_p,Build_Distance_matrix_400);
%% calculate building score - atractivnes
[Build_Data,Build_Data_p]=building_score(Build_Data,Build_Data_p,Assets,wact1,wact2,Build_Distance_matrix_250);
%% building size
FLOORSPACE = [];
for hhhh = 1:size(Build_Data,1)
    floorsize=sum(Assets(Assets(:,2)==Build_Data(hhhh,1),4));
    if floorsize == 0
        floorsize=Build_Data(hhhh,7)*ceil(Build_Data(hhhh,11));
    end
    Build_Data(hhhh,25)=floorsize;   
end
Assets = mean_price_per_meter(Assets);

%% stat service data
[stat_data,stat_data_P]=stat_service(Build_Data,Individuals_data,HH_data);
%% working_preferation for each individual (if works, based on data)
[Individuals_data,Individuals_data_P]=working_pref(Build_Data,Individuals_data,Individuals_data_P,HH_data,w_dis_job);
%% create salary to empty work places
Work_places=work_place_salary(Work_places);
%% car in the family (attached to individuals)
[Individuals_data,Individuals_data_P]=ind_num_car(Individuals_data, Individuals_data_P,HH_data);
%% number of routine per person
[Individuals_data,Individuals_data_P]=number_of_routine(Individuals_data,Individuals_data_P,acts,wactsnum);
%% SA score initial data
SA=SA_score(Build_Data);
%% activities locations
[Building_routine_id,Building_routine_id_P]=find_activity_location(Individuals_data,Build_Data,Work_places,HH_data,wact1,wact2,wactsnum,SA);
%% Assets price
[Build_Data,Build_Data_p,Assets,Assets_P]=ass_price(Build_Data,Build_Data_p,stat_data,Assets,Assets_P);
%% monthly assest cost
[Assets,Assets_P]=monthly_ass_cost(HH_data,Assets,Assets_P,Pa);
%% working pre for people who are looking for jobs!
ind=(Individuals_data(:,12)==1); % all unemployed
R=rand(sum(ind),1); % random vector 
Individuals_data(ind,18)=R; % random preference 
Individuals_data(:,22)=0; % new col(22)
Individuals_data_P=[Individuals_data_P,'ind_id_empty','time looking for job']; % header for what?
%% Working out side world income
income99=[mean(Individuals_data(Individuals_data(:,15)==99,14)),std(Individuals_data(Individuals_data(:,15)==99,14))];
average_wage=mean(Individuals_data(Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
std_wage=std(Individuals_data(Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
Wage_Change=0;

%% more model parameters
% JobsPerM_comm comes from the city configuration block (hardcoded per
% city there, not read dynamically - see that block's header comment)
[commute]=xlsread([file,'commuting.xlsx']);
Y=unique(Build_Data(:,12)); % unique 'yeshuv'
for y=1:length(Y)
    a=Build_Data(:,12)==Y(y); % map all similar 'yeshuv' in col(12)
    b=commute(:,1)==Y(y); % map all similar 'yeshuv' for commuting
    if sum(b) == 0
        Build_Data(a,23)=34; % if no cummting for this 'yeshuv' set 'working zone' as 34
    else
        Build_Data(a,23)=commute(b,2); % set 'working zone' as 34 or 31
    end
end
Build_Data_p=[Build_Data_p,'Working zone']; % add header title
VISITS=[Build_Distance_matrix_400(:,1)]; % all building ID in 400m distance as first col

g_sa=unique(Build_Data(:,4)); % unique SA ID
for g=1:length(g_sa)
    SA_PRICE(g,1)=nanmean(Assets(Assets(:,1)==g_sa(g),5)); % mean assets price in SA
    SA_HOUSE(g,1)=nanmean(Assets(ismember(Assets(:, 2),Build_Data(Build_Data(:,3)==1 | Build_Data(:,3)==2,1)) & Assets(:,1)==g_sa(g), 5));
    SA_COMERCIAL(g,1)=nanmean(Assets(ismember(Assets(:, 2),Build_Data(Build_Data(:,3)>2,1)) & Assets(:,1)==g_sa(g), 5));
    SA_POP(g,1)=sum(Assets(Assets(:,1)==g_sa(g),11)); % sum accupied assests in SA
    SA_ASSETS(g,1)=sum(Assets(:,1)==g_sa(g)); % sum total assets in SA
    SA_SERVICE(g,1)=sum(Build_Data(Build_Data(:,4)==g_sa(g),3)>2); % sum all building with usage greater then 2
    SA_RESIDENT(g,1)=sum(Build_Data(Build_Data(:,4)==g_sa(g),3)==1 | Build_Data(Build_Data(:,4)==g_sa(g),3)==2); % sum all building with usage 1 or 2
    SA_WP(g,1)=sum(Work_places(:,2)==g_sa(g));
    SA_JOBS(g,1)=sum(Work_places(:,2)==g_sa(g) & ((Work_places(:,7)==1 | Work_places(:,7)==3)))/sum(Work_places(:,2)==g_sa(g) & (Work_places(:,7)~=2 & Work_places(:,7)~=99));
    % col(12) 'working status' never takes the value 99 anywhere in this
    % codebase - the local/outside distinction lives in col(15)
    % ('building_work_place'), which find_job_1.m sets to 99 specifically
    % for outside hires. The old denominator (col12==2 | col12==99) was
    % therefore always identical to the numerator (col12==2) - SA_LOCAL
    % was structurally pinned at 1.0 regardless of the real local/outside
    % split. Numerator now requires local (col15~=99); denominator is all
    % currently-working individuals in the SA.
    SA_LOCAL(g,1)=sum(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,12)==2 & Individuals_data(:,15)~=99)/sum(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,12)==2);
    SA_WORKING(g,1)=sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==2))/sum(Work_places(:,2)==g_sa(g) & (Work_places(:,7)~=2 & Work_places(:,7)~=99));
    SA_IDLE(g,1)=sum(Individuals_data(:,2)==g_sa(g) & (Individuals_data(:,12)==1))/sum(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,12)>0);
    SA_WAGE(g,1)=mean(Individuals_data(Individuals_data(:,2)==g_sa(g) & Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
    SA_OUTCOME(g,1)=sum(Work_places(Work_places(:,2)==g_sa(g),8));
    SA_INTER(g,1)=0;
    SA_OUTER(g,1)=0;
    SA_BETWEEN(g,1)=0;
    SA_NEWCOME(g,1)=0;
    SA_FIRST(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==1);
    SA_SECOND(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==2);
    SA_THIRD(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==3);
    SA_FOURTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==4);
    SA_FIFTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==5);
    SA_SIXTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==6);
    SA_SEVENTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==7);
    SA_EIGHTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==8);
    SA_NINTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==9);
    SA_TENTH(g,1)=sum(HH_data(:,1)==g_sa(g) & HH_data(:,7)==10);   
	SA_AREA(g,1)=sum(Build_Data(Build_Data(:,4)==g_sa(g) & Build_Data(:,3)==3, 25));
end

destroyed_B=[];
% destroyed_commercial_B0: fixed, one-time snapshot (set at shock time
% below) of buildings that were ALREADY commercial (usage=3) the moment
% the earthquake hit - distinct from destroyed_B, which just tracks
% "currently still destroyed" and shrinks as buildings recover. NEEDED
% because Change_LU's candidate pool (Build_Data(:,3)<2) doesn't check
% destruction status - a residential building destroyed by the quake can
% sit in destroyed_B for many steps while ALSO getting converted to
% commercial (usage=3) with a brand-new, real workforce via ordinary
% land-use growth, completely unrelated to the earthquake. Without this
% distinction, cal_bui_sa_subsidy_targeted.m's destroyed-business
% eligibility check (modes 1/2) would incorrectly match that building too
% - confirmed happening for Arad (chat 2026-09-20): 68 buildings, all
% usage=1 at shock time and usage=3 by end of run, several still in
% destroyed_B at step 150, continuously eligible for the "drop 2 lowest
% earners" wage-bill suppression despite having nothing to do with the
% quake's business impact - the actual cause of the large, consistent,
% widening negative "jobs saved" a subsidy sweep found for modes 1/2.
destroyed_commercial_B0=[];
bad_Assets=[]; % pool of destroyed dwelling-unit assets, persists across
% steps like destroyed_B - MUST be initialized once here, not reset every
% step inside the loop, or the per-step recovery block (which restores an
% asset once its building recovers) only ever gets one chance to act (the
% step immediately after shock_A first populates it) before losing track
% of every not-yet-recovered asset for good.
HH_track=zeros(0,2); % [HH_ID, subsidy_start_step] - HH_subsidy.m tracker
Shelters=[];
Shelter_Assign=[];
Shelter_Building_Routines={};
Sheltered_Outside=zeros(0,3); % [HH_ID, start_step, income_penalty_amount] - shelter-overflow pool
% LU_Displaced: [HH_ID, start_step, orig_building_id] - households whose
% home was just converted to commercial use by the land-use block below
% (Change_LU). Given the same multi-step retry grace period as
% Sheltered_Outside (outside_patience_duration) instead of being deleted
% via did_not_find_house the SAME step their building converts. Needed
% because Change_LU's selection is a percentile cut of the whole eligible
% building stock (Build_Data(:,3)<2) - not a threshold that only catches
% buildings newly crossing it since the last check - so its first-ever
% activation (i>lu_warmup) necessarily flags a large one-time batch of the
% ENTIRE untouched residential stock for conversion. Measured effect
% before this fix: ~6,250 households evicted in a single step (the exact
% step land-use first activates), overwhelming the same-step housing
% search and getting force-deleted - visible in every macro trend as an
% early population dip-and-recovery. Retrying over several steps (like
% any other displaced household already does) fixes that without
% touching the conversion ranking/calibration itself.
LU_Displaced=zeros(0,3);

% --- displacement time-series + permanent-loss tracking ---
% n_*_hh_track: per-step snapshot of each sheltering tier's household
% count (see the existing n_*_hh_max/final snapshot block near the end of
% the step loop) - lets the full rise/fall trajectory be plotted, not just
% the peak/final scalars.
% n_permanently_displaced_total/track: households that NEVER come back -
% Shelter_Assign and Temp_Dev_Assign have no duration cap (a household
% stays until it finds a new home or its original building recovers - see
% those blocks' own comments), so the ONLY path to a shock-displaced
% household actually LEAVING the simulation for good is Sheltered_Outside
% patience expiry (outside_patience_duration steps with no new home
% found, at the did_not_find_house call following the
% patient_outside_hh exemption below). Counted there: anyone in
% HH_ID_left (about to be deleted) who was in Sheltered_Outside this step.
n_immediate_hh_track=zeros(1,steps);
n_outside_hh_track=zeros(1,steps);
n_tempdev_hh_track=zeros(1,steps);
n_permanently_displaced_total=0;
n_permanently_displaced_track=zeros(1,steps);
% n_original_hh_permanently_displaced_total/track: same event (patience-
% exhausted deletion from a sheltering tier) as n_permanently_displaced_
% total above, but restricted to households that were part of the ORIGINAL
% population (original_HH_ids, captured at load time) - excludes
% newly-migrated-in households that arrive during the run and later
% themselves get displaced. Answers "how many of the city's original
% residents never came back", as opposed to the raw total displacement
% EVENT count.
n_original_hh_permanently_displaced_total=0;
n_original_hh_permanently_displaced_track=zeros(1,steps);
Outside_Activity_Backup=zeros(0,2); % [agent_id, original_number_of_activities] - for
% working out-of-city commuters (see item 3 wiring below), col(20) gets
% reduced by outside_commute_penalty_pct while they're outside; this
% backs up the pre-reduction value so it can be restored exactly on exit,
% same pattern as Sheltered_Outside col(3) restoring the income penalty.
Temp_Dev_Sites=zeros(0,6); % [site_id, X, Y, capacity, start_step, end_step] - medium-term sheltering spaces (never a Build_Data row - see site_temp_dev_locations.m)
Temp_Dev_Assign=zeros(0,3); % [agent_id, site_id, start_step] - start_step added for tempdev_patience_duration (per-household patience, parallel to Sheltered_Outside col(2)) - see that parameter's own comment
temp_dev_spawned=false; % one-time flag: sites open at shock_step+temp_dev_delay

% --- outcome tracking: reconstruction + per-tier sheltering headcounts ---
% n_destroyed_total: snapshotted once at the moment of shock (see the
% earthquake block below) - the initial destroyed_B row count, before any
% recovery. destroyed_B only ever shrinks afterward (recovered buildings
% are removed from it, never re-added), so "reconstructed units so far" =
% n_destroyed_total - size(destroyed_B,1) at any later point.
n_destroyed_total=0;
% n_*_hh_max / n_*_hh_final: household counts (not agent counts - see the
% per-step snapshot near the end of the step loop) in each sheltering
% tier - immediate (Shelter_Assign: in-city public/school/hotel shelter),
% outside (Sheltered_Outside: shelter-overflow, commuting in from outside
% the city), temp-dev (Temp_Dev_Assign: medium-term sites). _max is the
% peak across the whole run; _final is whatever it is after the last step
% processed (== the true end-of-sim value, since every step overwrites it).
n_immediate_hh_max=0; n_outside_hh_max=0; n_tempdev_hh_max=0;
n_immediate_hh_final=0; n_outside_hh_final=0; n_tempdev_hh_final=0;

% --- subsidy sweep-analysis accumulators (chat 2026-09-15) ---
% See HH_subsidy_targeted.m / cal_bui_sa_subsidy_targeted.m's own header
% comments for exactly what each counts and why (cumulative distinct
% recipients, and total aid actually paid out over time - not one-time
% grant amounts).
n_hh_subsidized_total=0;
total_aid_distributed=0;
total_aid_distributed_track=zeros(1,steps); % per-step snapshot of the cumulative running total, so aid-over-time can be plotted (chat 2026-09-19)
n_businesses_subsidized_total=0;
businesses_subsidized_ever_ids=[];
biz_subsidy_tracker=[]; % modes 3/4 fixed-duration tracker: [building_id, subsidy_start_step] - see cal_bui_sa_subsidy_targeted.m (chat 2026-09-22)

%% start running
if ~exist('loop_start_tic','var'); loop_start_tic=tic; end
for i=1:steps
    fprintf('[%s] city=%s kk=%d/%d step %d/%d (elapsed %.1f min)\n', datestr(now,'HH:MM:SS'), city, kk, sims, i, steps, toc(loop_start_tic)/60);
    %toc
    % sum data
    average_wage=mean(Individuals_data(Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
    std_wage=std(Individuals_data(Individuals_data(:,15)>0 & Individuals_data(:,15)~=99,14));
    % values for each step
    sumdata(i).avgWage= average_wage;
    sumdata(i).stdWage= std_wage;
    sumdata(i).Wage_Change= Wage_Change;
    sumdata(i).n_looking = sum(Individuals_data(:,12)==1); % currently job-seeking (status=1)
    sumdata(i).n_working = sum(Individuals_data(:,12)==2); % currently employed (status=2)

    lost_jobs_B_ID =[];

    %% building movement - recovery, assets and work places
    if shock==1 && i >= shock_step + temp_dev_delay
        % Probabilistic per-building weekly recovery (replaces the old
        % deterministic shared-countdown mechanism, where every destroyed
        % building recovered at exactly the same step count regardless of
        % size - see day_to_week_step_rescaling_audit.md). Each still-
        % destroyed building gets an independent Bernoulli draw every
        % step with probability RECOVERY, memoryless (no accumulated
        % "progress" - destroyed_B(:,2) is no longer used, kept as a
        % vestigial column since destroyed_B(:,3) [size] is still read
        % elsewhere, e.g. site_temp_dev_locations.m).
        %
        % Gated on i >= shock_step+temp_dev_delay (not just shock==1):
        % reconstruction crews need the same stand-up time as temp-dev
        % sites, so rebuilding starts at the same moment temp-dev opens,
        % not immediately at the shock itself.
        recovery_prob=RECOVERY*ones(size(destroyed_B,1),1);
        if priority_recovery==1
            [~, idx_in_build]=ismember(destroyed_B(:,1),Build_Data(:,1));
            usg=Build_Data(idx_in_build,3);
            recovery_prob(usg==1)=min(RECOVERY*recovery_factor,1); % priority for residential, clamped to a valid probability
        end
        f=rand(size(destroyed_B,1),1) < recovery_prob;
        BI=destroyed_B(f,1);
        destroyed_B(f,:)=[]; % remove all recovered
        if size(bad_Assets,1)>0 % bad assets remaining 
            loca=ismember(bad_Assets(:,2),BI); % indexes of recovered
            Assets=[Assets;bad_Assets(loca,:)]; % return recovered to avalible list
            bad_Assets(loca,:)=[]; % clear recovered
        end      
        Work_places=new_works_after_recovery(Work_places,Build_Data,BI,average_wage,std_wage);
        if displaced_shelter==1 && ~isempty(Shelters)
            [Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, released_agents] = ...
                release_shelter(Build_Data, Individuals_data, HH_data, Shelters, Shelter_Assign,...
                Shelter_Building_Routines, Building_routine_id, Assets, BI, i);
            routine_recompute_ids = [routine_recompute_ids; released_agents]; % no override - HH_data is correct again
        end
        if displaced_shelter==1 && ~isempty(Sheltered_Outside)
            [HH_data, Sheltered_Outside, released_hh] = release_outside_shelter(HH_data, Assets, BI, Sheltered_Outside);
            if ~isempty(released_hh)
                released_out_agents = Individuals_data(ismember(Individuals_data(:,3), released_hh), 1);
                % restore any reduced number_of_activities from entry, then
                % forget the backup entry
                [has_backup, locBk] = ismember(released_out_agents, Outside_Activity_Backup(:,1));
                if any(has_backup)
                    ra_working = released_out_agents(has_backup);
                    [~, locIA] = ismember(ra_working, Individuals_data(:,1));
                    Individuals_data(locIA,20) = Outside_Activity_Backup(locBk(has_backup),2);
                    Outside_Activity_Backup(locBk(has_backup),:) = [];
                end
                routine_recompute_ids = [routine_recompute_ids; released_out_agents]; % no override - HH_data is correct again
            end
        end
        if displaced_shelter==1 && ~isempty(Temp_Dev_Assign)
            [Temp_Dev_Assign, released_td_agents] = release_temp_dev(Individuals_data, HH_data, Assets, BI, Temp_Dev_Assign);
            routine_recompute_ids = [routine_recompute_ids; released_td_agents]; % no override - HH_data is correct again
        end
    end

    %% medium-term sheltering: open temporary-development spaces
    % One-time event, temp_dev_delay steps after the shock. A fixed count
    % (n_temp_dev_sites) of abstract residential SPACES open - NOT
    % buildings; no Build_Data row or distance-matrix entry is ever
    % created for them, see site_temp_dev_locations.m. Combined capacity
    % across all sites = temp_dev_capacity_frac of the total
    % currently-sheltered population (immediate tier + out-of-city
    % overflow), split evenly across the sites. Applies the same way in
    % both capacity scenarios (limited or full) - only the total capacity
    % differs, not the fill order. Candidates are filled in strict
    % priority order, not one shuffled pool: public/school-sheltered
    % households first, then out-of-city overflow households, then
    % hotel-sheltered households last (hotels are the most comfortable of
    % the immediate options, so those households are the last to be moved
    % into container-city conditions) - shuffled only within each
    % priority tier. Transferred in - greedily filling sites in that
    % order, up to capacity (not optimal bin-packing). Immediate-tier transfers free their old shelter
    % building (reverts to its original usage once empty, same as
    % release_shelter.m's normal path); out-of-city transfers get their
    % commute-penalty income refunded (same amount deducted on entry).
    % Anyone not transferred simply stays in whichever pool they were
    % already in - no further cascade needed. Temp-dev residents are
    % released the same way as any other shelter (see release_temp_dev.m
    % above: original home recovered, or a new asset secured), plus the
    % duration-based closure below.
    if displaced_shelter==1 && shock==1 && ~temp_dev_spawned && i >= shock_step + temp_dev_delay
        temp_dev_spawned = true;
        site_xy = site_temp_dev_locations(Build_Data, destroyed_B, n_temp_dev_sites, temp_dev_site_coords);

        n_immediate = size(Shelter_Assign,1);
        n_outside = sum(ismember(Individuals_data(:,3), Sheltered_Outside(:,1)));
        total_displaced = n_immediate + n_outside;
        total_capacity = floor(temp_dev_capacity_frac * total_displaced);

        if ~isempty(site_xy) && total_capacity>0 && (n_immediate>0 || n_outside>0)
            n_sites_opened = size(site_xy,1);
            per_site_capacity = floor(total_capacity / n_sites_opened);
            site_ids = (1:n_sites_opened)';
            Temp_Dev_Sites = [Temp_Dev_Sites; site_ids, site_xy, repmat(per_site_capacity,n_sites_opened,1), repmat(i,n_sites_opened,1), zeros(n_sites_opened,1)];

            site_remaining = repmat(per_site_capacity, n_sites_opened, 1);
            next_site = 1;

            if isempty(Shelter_Assign)
                immediate_hh = [];
                hotel_hh = [];
                public_hh = [];
            else
                immediate_hh = unique(Individuals_data(ismember(Individuals_data(:,1), Shelter_Assign(:,1)), 3));
                % split the immediate tier by original building usage so
                % hotel-sheltered households can be deprioritized below -
                % Shelters(:,4) is the building's original_usage (5/7/8),
                % recorded before it was marked as a shelter (usage 99).
                hotel_b_ids = Shelters(Shelters(:,4)==7, 1);
                hotel_agents = Shelter_Assign(ismember(Shelter_Assign(:,2), hotel_b_ids), 1);
                hotel_hh = unique(Individuals_data(ismember(Individuals_data(:,1), hotel_agents), 3));
                public_hh = setdiff(immediate_hh, hotel_hh);
            end
            outside_hh = Sheltered_Outside(:,1);
            % priority order: public/school shelter, then out-of-city
            % overflow, then hotel shelter last - shuffled within each
            % tier only, not across tiers.
            candidate_hh = [public_hh(randperm(length(public_hh))); ...
                             outside_hh(randperm(length(outside_hh))); ...
                             hotel_hh(randperm(length(hotel_hh)))];

            for h = 1:length(candidate_hh)
                hh_id = candidate_hh(h);
                hh_agents = Individuals_data(Individuals_data(:,3)==hh_id, 1);
                n_needed = length(hh_agents);

                while next_site <= n_sites_opened && site_remaining(next_site) < n_needed
                    next_site = next_site + 1;
                end
                if next_site > n_sites_opened
                    break % no more temp-dev capacity - remaining households stay where they already were
                end

                site_id = site_ids(next_site);

                if ismember(hh_id, immediate_hh)
                    % coming from the immediate tier - free their old shelter building
                    old_b_ids = unique(Shelter_Assign(ismember(Shelter_Assign(:,1),hh_agents),2));
                    Shelter_Assign(ismember(Shelter_Assign(:,1),hh_agents),:) = [];
                    for ob = 1:length(old_b_ids)
                        if ~any(Shelter_Assign(:,2)==old_b_ids(ob))
                            sidx = find(Shelters(:,1)==old_b_ids(ob), 1);
                            if ~isempty(sidx)
                                Build_Data(Build_Data(:,1)==old_b_ids(ob),3) = Shelters(sidx,4);
                                Shelters(sidx,3) = i;
                                Shelters(sidx,:) = [];
                            end
                        end
                    end
                else
                    % coming from the out-of-city overflow pool - refund the
                    % commute penalty, same amount deducted on entry, and
                    % restore any reduced number_of_activities (they're
                    % moving to a LOCAL tier now, not commuting in)
                    hh_row = find(HH_data(:,2)==hh_id, 1);
                    os_row = find(Sheltered_Outside(:,1)==hh_id, 1);
                    if ~isempty(hh_row) && ~isempty(os_row)
                        HH_data(hh_row,6) = HH_data(hh_row,6) + Sheltered_Outside(os_row,3);
                    end
                    Sheltered_Outside(Sheltered_Outside(:,1)==hh_id,:) = [];
                    [has_backup, locBk] = ismember(hh_agents, Outside_Activity_Backup(:,1));
                    if any(has_backup)
                        ra_working = hh_agents(has_backup);
                        [~, locIA] = ismember(ra_working, Individuals_data(:,1));
                        Individuals_data(locIA,20) = Outside_Activity_Backup(locBk(has_backup),2);
                        Outside_Activity_Backup(locBk(has_backup),:) = [];
                    end
                end

                Temp_Dev_Assign = [Temp_Dev_Assign; [hh_agents, repmat(site_id, n_needed, 1), repmat(i, n_needed, 1)]];
                site_remaining(next_site) = site_remaining(next_site) - n_needed;

                % recompute this household's routine anchored on the site
                % itself ("shelter as home" - item 2)
                site_row = find(Temp_Dev_Sites(:,1)==site_id, 1);
                routine_recompute_ids = [routine_recompute_ids; hh_agents];
                routine_home_override = [routine_home_override; hh_agents, repmat(Temp_Dev_Sites(site_row,2:3), n_needed, 1)];
            end

            % Public/school-sheltered households NOT selected for a
            % temp-dev slot (temp-dev capacity is only temp_dev_capacity_frac
            % of the combined immediate+outside pool, and public/school is
            % merely first PRIORITY, not a guarantee) move to out-of-city
            % overflow instead of remaining in their shelter building
            % indefinitely - public buildings/schools are short-term
            % emergency shelter, not a stable placement once the model has
            % moved past the initial response into medium-term sheltering.
            % Hotel-sheltered households are deliberately excluded here -
            % they're already lowest priority for temp-dev precisely
            % because hotels are the more comfortable option (see the
            % priority-order comment above), so a hotel guest left over
            % simply stays in the hotel, same as before this change.
            % Same entry procedure as the shelter-capacity-exhausted
            % overflow path (assign_shelter's unsheltered_agents branch,
            % just above this block).
            transferred_hh = unique(Individuals_data(ismember(Individuals_data(:,1), Temp_Dev_Assign(:,1)), 3));
            leftover_public_hh = setdiff(public_hh, transferred_hh);
            for lh = 1:length(leftover_public_hh)
                hh_id = leftover_public_hh(lh);
                hh_row = find(HH_data(:,2)==hh_id, 1);
                if isempty(hh_row)
                    continue
                end
                hh_agents = Individuals_data(Individuals_data(:,3)==hh_id, 1);

                % free their shelter building - same release logic as the
                % immediate-tier temp-dev transfer branch above
                old_b_ids = unique(Shelter_Assign(ismember(Shelter_Assign(:,1),hh_agents),2));
                Shelter_Assign(ismember(Shelter_Assign(:,1),hh_agents),:) = [];
                for ob = 1:length(old_b_ids)
                    if ~any(Shelter_Assign(:,2)==old_b_ids(ob))
                        sidx = find(Shelters(:,1)==old_b_ids(ob), 1);
                        if ~isempty(sidx)
                            Build_Data(Build_Data(:,1)==old_b_ids(ob),3) = Shelters(sidx,4);
                            Shelters(sidx,3) = i;
                            Shelters(sidx,:) = [];
                        end
                    end
                end

                penalty = outside_commute_penalty_pct * HH_data(hh_row,6);
                HH_data(hh_row,6) = HH_data(hh_row,6) - penalty;
                Sheltered_Outside = [Sheltered_Outside; hh_id, i, penalty];

                [~, locAg] = ismember(hh_agents, Individuals_data(:,1));
                is_working = Individuals_data(locAg,12)==2 & Individuals_data(locAg,17)>0 & Individuals_data(locAg,17)~=99;
                working_agents = hh_agents(is_working);
                nonworking_agents = hh_agents(~is_working);

                if ~isempty(working_agents)
                    [~, locWA] = ismember(working_agents, Individuals_data(:,1));
                    [foundWp, locWp] = ismember(Individuals_data(locWA,17), Work_places(:,6));
                    nonworking_agents = [nonworking_agents; working_agents(~foundWp)];
                    working_agents = working_agents(foundWp);
                    locWA = locWA(foundWp);
                    locWp = locWp(foundWp);
                end
                if ~isempty(working_agents)
                    wp_xy = Work_places(locWp,3:4);
                    Outside_Activity_Backup = [Outside_Activity_Backup; working_agents, Individuals_data(locWA,20)];
                    Individuals_data(locWA,20) = round(Individuals_data(locWA,20) * (1-outside_commute_penalty_pct));
                    routine_recompute_ids = [routine_recompute_ids; working_agents];
                    routine_home_override = [routine_home_override; working_agents, wp_xy];
                end
                if ~isempty(nonworking_agents)
                    a_idx = ismember(Building_routine_id(:,1), nonworking_agents);
                    Building_routine_id(a_idx, 4:end) = NaN;
                end
            end
        end
    end

    %% damaged building list

    if shock == 1
        damaged_buildings = destroyed_B(:,1);
    else
        damaged_buildings = [];
    end


    k=[];

    %% parameters need for later:
    Occupied_Jobs=sum(Work_places(:,7)==1)/sum(Work_places(:,7)<2); % occupied ratio in area, excluding 99
    a=Build_Data(:,3)>0; % usage > 0
    Floor_Size=sum(Build_Data(a,7).*ceil(Build_Data(a,11))); % floor size for building with usage (area*floors)
    LU=[];new_A=[];new_B=[];HH_change=[];
    new_jobs_work_places=[];HH_ID_left=[];lost_job_id=[];closed_wp_ids_today=[];
    HH_destroyed=[];lost_jobs=[];Ind_change_routine=[]; % NOT bad_Assets - see its init comment above, must persist across steps
    % routine_recompute_ids/routine_home_override: agents whose routine
    % needs recomputing this step because their shelter status just
    % changed (entered/left immediate tier, temp-dev, or out-of-city),
    % and where to anchor that recompute instead of their (possibly
    % stale) HH_data home - see the shelter/temp-dev/outside blocks below
    % and design items 2-3 in team_lead_status.md.
    routine_recompute_ids=[];
    routine_home_override=zeros(0,3);
    max_salary = max(Work_places(:,8));
    row = find(Work_places(:,8) == max_salary); % index fo max salary
    max_WP_id=Work_places(row(1),6); % id of workplace with max salary
     % columns: [HH_ID, start_day]
    
    %% earthquake
    % One-time shock (same trigger pattern as the original run_model_eq.m),
    % replacing rocket_attack2's iterative wave loop. Requires a per-SA
    % damage table at [file,'earthquake_damage.csv'] - see earth_quake.m.
    if i==shock_step && shock==0
        shock=1;
        [destroyed_B_P, destroyed_B] = earth_quake(Build_Data, [file,'earthquake_damage.csv']);
        [bad_Assets,Assets,destroyed_B]=shock_A(Assets,destroyed_B);
        n_destroyed_total = size(destroyed_B,1); % snapshot at the moment of shock, before any recovery
        % HH no house
        HH_destroyed=shock_H(HH_data,Assets);

        % BUSINESS SUBSIDY (modes 1/2/3/4's destroyed-buildings half) -
        % snapshot pre-shock Work_places/Individuals_data for destroyed
        % commercial buildings' workers BEFORE shock_W/shock_I strip them
        % below. See the restoration block right after shock_I for why
        % (chat 2026-09-19, bug found by the Tiberias session). Modes 3/4
        % (chat 2026-09-22) need this snapshot for the same reason modes
        % 1/2 do - see cal_bui_sa_subsidy_targeted.m.
        pre_shock_wp_snapshot = zeros(0, size(Work_places,2));
        pre_shock_ind_snapshot = zeros(0, size(Individuals_data,2));
        if ismember(subsidy_businesses_mode, [1 2 3 4])
            destroyed_commercial_B0 = destroyed_B(ismember(destroyed_B(:,1), Build_Data(Build_Data(:,3)==3,1)), 1);
            pre_shock_wp_snapshot = Work_places(ismember(Work_places(:,1), destroyed_commercial_B0), :);
            pre_shock_ind_snapshot = Individuals_data(ismember(Individuals_data(:,17), pre_shock_wp_snapshot(:,6)), :);
        end

        % lost jobs (work places id - to find workers) and delete working places
        [Work_places,lost_jobs]=shock_W(Work_places,destroyed_B);
        % people loosing work (change from working to looking) and
        % change location and keep track because need to change routine
        [Individuals_data,Ind_change_routine]=shock_I(Individuals_data,lost_jobs);

        % BUSINESS SUBSIDY (modes 1/2/3/4's destroyed-buildings half) -
        % restore 2 job slots per eligible destroyed commercial building
        % (chat 2026-09-19; extended to modes 3/4, chat 2026-09-22, for
        % the identical reason - see cal_bui_sa_subsidy_targeted.m, and
        % note both new modes' length(building_salaries)>1 eligibility
        % guard needs at least 2 live workers restored same as modes
        % 1/2). shock_W/shock_I above permanently strip EVERY
        % destroyed building's Work_places rows and move those workers to
        % job-search, so cal_bui_sa_subsidy_targeted.m's mode-1 eligibility
        % check (ismember(building, destroyed_ids), keyed off live
        % Work_places) could never fire - a destroyed building has 0
        % current workers by the time that function is ever called, on any
        % step (bug found by the Tiberias session: mode 1 supported 0
        % businesses in every combo they ran). The b7-ported "the subsidy
        % covers what the business would have owed its 2 lowest earners"
        % framing doesn't literally apply once those earners' jobs are
        % already gone - so here it's reinterpreted as: the subsidy
        % PHYSICALLY saves the 2 lowest-paid workers' jobs at each eligible
        % destroyed commercial building, undoing shock_W/shock_I for
        % exactly those 2 Work_places rows/individuals. This both makes
        % cal_bui_sa_subsidy_targeted.m's existing eligibility logic
        % correctly fire from here on (the building has >1 live worker
        % again, so its own per-step "drop the 2 lowest" accounting then
        % covers their full wage bill every step) and directly moves
        % SA_WP/"jobs saved" - the actual metric this sweep measures.
        % Buildings with originally <=1 worker get nothing restored,
        % matching the function's own ">1 worker" eligibility guard.
        if ismember(subsidy_businesses_mode, [1 2 3 4])
            destroyed_commercial_B = destroyed_B(ismember(destroyed_B(:,1), Build_Data(Build_Data(:,3)==3,1)), 1);
            for db = 1:length(destroyed_commercial_B)
                bld_id = destroyed_commercial_B(db);
                bld_rows = pre_shock_wp_snapshot(pre_shock_wp_snapshot(:,1)==bld_id, :);
                if size(bld_rows,1) > 1
                    [~, sort_idx] = sort(bld_rows(:,8), 'ascend'); % col 8 = salary, lowest-paid first
                    n_save = min(2, size(bld_rows,1));
                    rows_to_restore = bld_rows(sort_idx(1:n_save), :);
                    Work_places = [Work_places; rows_to_restore];
                    saved_wp_ids = rows_to_restore(:,6); % col 6 = workplace id
                    restore_mask = ismember(pre_shock_ind_snapshot(:,17), saved_wp_ids);
                    restored_agents = pre_shock_ind_snapshot(restore_mask, 1);
                    [~, cur_idx] = ismember(restored_agents, Individuals_data(:,1));
                    [~, snap_idx] = ismember(restored_agents, pre_shock_ind_snapshot(:,1));
                    Individuals_data(cur_idx, [12,15,16,17]) = pre_shock_ind_snapshot(snap_idx, [12,15,16,17]);
                    Ind_change_routine = setdiff(Ind_change_routine, restored_agents);
                end
            end
        end

        if displaced_shelter==1 && ~isempty(HH_destroyed)
            [Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, unsheltered_agents, newly_assigned] = ...
                assign_shelter(Build_Data, Individuals_data, HH_destroyed, Shelters, Shelter_Assign,...
                Shelter_Building_Routines, Building_routine_id, i, agents_per_sqm, public_bldg_usable_fraction, ...
                restrict_public_shelters_to_schools, hotel_room_density, agents_per_room);
            if ~isempty(newly_assigned)
                routine_recompute_ids = [routine_recompute_ids; newly_assigned(:,1)];
                routine_home_override = [routine_home_override; newly_assigned];
            end

            % Shelter capacity exhausted: leftover displaced households are
            % "sheltered outside the city" instead of being deleted - see
            % shelter_policy_extensions_handoff.md item 5.
            if ~isempty(unsheltered_agents)
                new_outside_hh = unique(Individuals_data(ismember(Individuals_data(:,1), unsheltered_agents), 3));
                new_outside_hh = setdiff(new_outside_hh, Sheltered_Outside(:,1));
                for oh = 1:length(new_outside_hh)
                    hh_id = new_outside_hh(oh);
                    hh_row = find(HH_data(:,2)==hh_id, 1);
                    if isempty(hh_row)
                        continue
                    end
                    % stylized commute penalty: flat income haircut, restored
                    % (exact amount) on release by release_outside_shelter.m
                    penalty = outside_commute_penalty_pct * HH_data(hh_row,6);
                    HH_data(hh_row,6) = HH_data(hh_row,6) - penalty;
                    Sheltered_Outside = [Sheltered_Outside; hh_id, i, penalty];

                    % Working members: routine recomputed anchored on their
                    % WORKPLACE instead of their (destroyed) home - "starts
                    % at their workplace" - with number_of_activities
                    % reduced by outside_commute_penalty_pct to reflect the
                    % time/opportunity cost of commuting in (backed up in
                    % Outside_Activity_Backup for exact restoration on
                    % exit). Non-working members have no reason to be in
                    % the city at all - kept on the original blunt
                    % suppression (no local activities).
                    hh_agents = Individuals_data(Individuals_data(:,3)==hh_id, 1);
                    [~, locAg] = ismember(hh_agents, Individuals_data(:,1));
                    is_working = Individuals_data(locAg,12)==2 & Individuals_data(locAg,17)>0 & Individuals_data(locAg,17)~=99;
                    working_agents = hh_agents(is_working);
                    nonworking_agents = hh_agents(~is_working);

                    if ~isempty(working_agents)
                        [~, locWA] = ismember(working_agents, Individuals_data(:,1));
                        [foundWp, locWp] = ismember(Individuals_data(locWA,17), Work_places(:,6));
                        % see the shock-time overflow path above for why
                        % this guard is needed
                        nonworking_agents = [nonworking_agents; working_agents(~foundWp)];
                        working_agents = working_agents(foundWp);
                        locWA = locWA(foundWp);
                        locWp = locWp(foundWp);
                    end
                    if ~isempty(working_agents)
                        wp_xy = Work_places(locWp,3:4);
                        Outside_Activity_Backup = [Outside_Activity_Backup; working_agents, Individuals_data(locWA,20)];
                        Individuals_data(locWA,20) = round(Individuals_data(locWA,20) * (1-outside_commute_penalty_pct));
                        routine_recompute_ids = [routine_recompute_ids; working_agents];
                        routine_home_override = [routine_home_override; working_agents, wp_xy];
                    end
                    if ~isempty(nonworking_agents)
                        a_idx = ismember(Building_routine_id(:,1), nonworking_agents);
                        Building_routine_id(a_idx, 4:end) = NaN;
                    end
                end
            end
        end
    end

    [HH_data,Individuals_data,HH_track,n_hh_subsidized_total,total_aid_distributed]=HH_subsidy_targeted(HH_data,Individuals_data,HH_destroyed,HH_track,Assets,bad_Assets,Shelter_Assign,Sheltered_Outside,Temp_Dev_Assign,subsidy_residents_mode,subsidy_duration,i,n_hh_subsidized_total,total_aid_distributed);

    % HH still waiting in shelter after this step's releases/new
    % assignments above - these retry the within-SA search every step
    % (from their original SA/building, since HH_data still points there)
    % until they find housing or their home recovers.
    %
    % Stage design: during "stage 1" (from the shock until temp-dev opens,
    % i < shock_step+temp_dev_delay), NO household searches at all -
    % neither immediate/hotel-sheltered nor outside-overflow (see the
    % moving_HH fold-in below, which is gated on stage 2 having started).
    % Reconstruction (the RECOVERY draw above) is unaffected and proceeds
    % from the shock regardless. Once "stage 2" begins (temp-dev opens),
    % every displaced household falls into exactly one of two groups by
    % whether it has a roof: (a) still has SOME shelter (still in a
    % hotel/school building, OR in a temp-dev site) - gets
    % tempdev_patience_duration attempts; (b) has no shelter at all
    % (Sheltered_Outside) - gets outside_patience_duration attempts.
    % Since this is a single one-time shock, everyone in Shelter_Assign
    % entered at the same step, so a single global elapsed-time-since-
    % stage-2-began check applies uniformly (no per-household timestamp
    % needed, unlike Sheltered_Outside/Temp_Dev_Assign below, where a
    % per-household start_step is still used for robustness).
    if isempty(Shelter_Assign)
        still_sheltered_hh = [];
        patient_shelter_hh = [];
    else
        still_sheltered_hh = unique(Individuals_data(ismember(Individuals_data(:,1), Shelter_Assign(:,1)), 3));
        if (i - (shock_step + temp_dev_delay)) < tempdev_patience_duration
            patient_shelter_hh = still_sheltered_hh;
        else
            patient_shelter_hh = [];
        end
    end
    if isempty(Temp_Dev_Assign)
        still_temp_dev_hh = [];
        patient_tempdev_hh = [];
    else
        still_temp_dev_hh = unique(Individuals_data(ismember(Individuals_data(:,1), Temp_Dev_Assign(:,1)), 3));
        % patient_tempdev_hh: per-household version of the same
        % tempdev_patience_duration concept, using Temp_Dev_Assign col(3)
        % (each agent's own temp-dev entry step) - for a single one-time
        % shock this always equals stage-2 onset anyway (temp-dev spawns
        % in one shot), so it agrees with patient_shelter_hh's global
        % check above, but stays correct if that assumption ever changes.
        tempdev_patient_agents = Temp_Dev_Assign(i - Temp_Dev_Assign(:,3) < tempdev_patience_duration, 1);
        patient_tempdev_hh = unique(Individuals_data(ismember(Individuals_data(:,1), tempdev_patient_agents), 3));
    end

    moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,2); % K=2, probability of moving within SA
    % Sheltered_Outside and Temp_Dev_Assign HH retry the same cascade
    % every step, exactly like still_sheltered_hh - "treated like
    % migrants trying to find a new asset". Stage 1 (before temp-dev
    % opens): NO displaced household searches at all - this fold-in is
    % suppressed entirely. Reconstruction still proceeds regardless (the
    % RECOVERY draw above is unconditional on this).
    if i >= shock_step + temp_dev_delay
        moving_HH=[moving_HH;HH_destroyed;still_sheltered_hh;Sheltered_Outside(:,1);still_temp_dev_hh];
    end
    moving_HH=unique(moving_HH);
    if isempty(moving_HH)==0 % assign new asset for agent
        [HH_ID_left,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data]...
            =find_new_house_same_stat(HH_ID_left,pd,HH_data,Individuals_data, ...
            Build_Data,Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change);
        % resSearchLen: reset the consecutive-fail counter (col 13) for
        % anyone in this step's K=2 candidate pool who is NOT among the
        % failures just returned - i.e., they found a home this step.
        HH_data(ismember(HH_data(:,2), setdiff(moving_HH, HH_ID_left)), 13) = 0;
    end

    moving_HH=who_is_moving(HH_data,random_number,unique_stat,intra_SA,3); % K=3, probability of moving within the city

    if isempty(moving_HH)==0
        [HH_ID_left,HH_data,Assets,HH_change,LU,new_A,new_B,Build_Data]= ...
            find_new_house_yeshuv(HH_ID_left,pd,HH_data,Individuals_data,Build_Data ...
            ,Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change);
        % resSearchLen: reset the consecutive-fail counter for anyone in
        % this step's K=3 candidate pool who is NOT among the (K=2+K=3)
        % failures just returned.
        HH_data(ismember(HH_data(:,2), setdiff(moving_HH, HH_ID_left)), 13) = 0;
    end


    % HH still sheltered (any pool) are exempt from deletion if this
    % attempt failed - they stay sheltered and retry next step. Exception
    % (item 4, "decreasing patience"): a household sheltered outside the
    % city loses its exemption once it's been there for
    % outside_patience_duration steps - if it also failed to find housing
    % this step, it falls through to the normal did_not_find_house
    % deletion below just like any other migrant who's given up.
    % patient_outside_hh: elapsed attempts measured from whichever is
    % LATER - this household's own Sheltered_Outside entry, or stage-2
    % onset (shock_step+temp_dev_delay) - since stage 1 has no attempts at
    % all (see the moving_HH gate above), the clock can't start before
    % stage 2 regardless of when the household nominally entered the pool.
    % For this single one-time shock everyone enters at the shock step
    % itself (before stage 2), so max() always picks stage-2 onset
    % uniformly here - stays correct if that assumption ever changes.
    patient_outside_hh = Sheltered_Outside(i - max(Sheltered_Outside(:,2), shock_step+temp_dev_delay) < outside_patience_duration, 1);
    % LU_Displaced households (see its init comment near Sheltered_Outside)
    % can also be swept into this step's random K=2 moving_HH draw above
    % (who_is_moving doesn't know about this pool) - same patience-based
    % exemption as Sheltered_Outside, or a K=2 search failure here would
    % delete them out from under the LU block's own retry bookkeeping
    % further down this step, leaving it holding a stale HH_ID and
    % crashing find_new_house_same_stat's per-household lookup.
    patient_lu_hh = LU_Displaced(i - LU_Displaced(:,2) < outside_patience_duration, 1);
    exempt_sheltered = ismember(HH_ID_left, patient_shelter_hh) | ismember(HH_ID_left, patient_outside_hh) | ismember(HH_ID_left, patient_tempdev_hh) | ismember(HH_ID_left, patient_lu_hh);
    HH_ID_left = HH_ID_left(~exempt_sheltered);
    %saves HH that leave simulation before they are deleted

    % Permanent displacement: anyone about to be deleted (HH_ID_left, post-
    % exemption) who was in Sheltered_Outside, still_temp_dev_hh, OR
    % still_sheltered_hh this step has exhausted its patience with no new
    % home found - this is the shock-caused population loss that never
    % recovers, as opposed to the temporary sheltering tiers above (which
    % always eventually release when patient, never delete on their own).
    displaced_now = HH_ID_left(ismember(HH_ID_left, [Sheltered_Outside(:,1); still_temp_dev_hh; still_sheltered_hh]));
    n_permanently_displaced_total = n_permanently_displaced_total + length(displaced_now);
    % original-cohort subset (see original_HH_ids/original_HH_ids_remaining's
    % init comment near load(data)) - match against the REMAINING set, then
    % prune matched IDs so a later migrant who reuses one of these ID
    % numbers can never be double-counted as the same original household.
    is_original_displaced = ismember(displaced_now, original_HH_ids_remaining);
    n_original_hh_permanently_displaced_total = n_original_hh_permanently_displaced_total + sum(is_original_displaced);
    original_HH_ids_remaining = setdiff(original_HH_ids_remaining, displaced_now(is_original_displaced));

    % resSearchLen retry gate (ported from modelthesis): increments the
    % consecutive-fail counter for everyone about to be evicted below; only
    % those who've now reached resSearchLen actually proceed to deletion -
    % everyone else keeps their (incremented) counter and simply isn't
    % passed to did_not_find_house this step, so they stay in HH_data and
    % get another chance whenever they're next selected to move.
    if ~isempty(HH_ID_left)
        [locA,~] = ismember(HH_data(:,2), HH_ID_left);
        HH_data(locA,13) = HH_data(locA,13) + 1;
        [~,locB] = ismember(HH_ID_left, HH_data(:,2));
        HH_ID_left = HH_ID_left(HH_data(locB,13) >= resSearchLen);
    end

    %% delete HH that left (sheltered HH exempted above stay in the sim)
    [Individuals_data,Work_places,HH_data,Assets,HH_ID_left]=did_not_find_house(HH_ID_left,Individuals_data,Work_places,HH_data,Assets);
    % prune Sheltered_Outside bookkeeping for anyone just deleted above
    % (patience expired) - their HH_ID no longer exists in HH_data.
    Sheltered_Outside(~ismember(Sheltered_Outside(:,1), HH_data(:,2)), :) = [];

    %% individuals steps:
    %% job status looking, finding, stoping
    [agent_rot,Individuals_data,HH_data,Work_places]=find_job_1(HH_ID_left,Individuals_data,HH_data,Work_places,Build_Data,income99);
      
    %% Buildings steps:   
    visit_volume=cal_visits(Building_routine_id,Build_Distance_matrix_400); % number of visits per building by agents
    VISITS=[VISITS,visit_volume(:,2)]; % new visits count col every iteration

    if size(VISITS,2) > 5
        VISITS(:,2)=[]; % keep rolling 4-step (~1 month) window (+1 for the ID col) - was >31 daily steps
    end

    if ~exist('lu_warmup','var'); lu_warmup=4; end % steps before land-use/business updates start - was 30 daily steps (~1 month)
    if ~exist('lu_update_every','var'); lu_update_every=1; end % run every Nth step after warmup (raise to speed up a test run)

    if i>lu_warmup && mod(i,lu_update_every)==0
        %% mean visit per building
        MVB30=[VISITS(:,1),nanmean(VISITS(:,2:end),2)];
        % calculate visits by precentile up to 100
        P=[0,prctile(MVB30(:,2),1:100)]; % first element is zero then 101 in total. index shift
        % Vectorized (was: a 100-iteration loop re-scanning the whole
        % column each time to find which bin every row falls in) -
        % ported from the same fix in modelthesis/run_model_earthquake.m.
        % Since P doesn't depend on each row's own value, the bin index
        % for row value v is exactly count(P(1:100) <= v) - same
        % P(ppp)<=v<P(ppp+1) definition, all rows computed in one
        % broadcast comparison instead of a per-bin loop.
        rank_col = sum(MVB30(:,2) >= P(1:100), 2);
        rank_col(rank_col==0) = 100; % same fallback as the old post-loop fixup
        MVB30(:,3) = rank_col;
                
        %% mean salary for all buildings withe workers comm only!!!
        %building_average_salary=cal_bui_sa(Work_places,Build_Data); % building sum salary
        [building_average_salary,n_businesses_subsidized_total,businesses_subsidized_ever_ids,biz_subsidy_tracker]=cal_bui_sa_subsidy_targeted(Work_places, Build_Data, destroyed_B, destroyed_commercial_B0, subsidy_businesses_mode, n_businesses_subsidized_total, businesses_subsidized_ever_ids, biz_subsidy_tracker, i); % building sum salary
        % STABLE-YARDSTICK FIX (chat 2026-09-15): build the percentile scale
        % from col(3), every building's REAL unsubsidized wage sum - not
        % col(2), the eligibility-adjusted one - so the scale itself never
        % moves no matter how many buildings a subsidy mode touches (mode 2
        % can affect ~30% of all commercial buildings at once, which used to
        % visibly compress the whole distribution and silently shift every
        % OTHER building's rank too). Each building's own rank is still
        % looked up using col(2), so a subsidized building still benefits
        % from looking cheaper - just against a scale that non-subsidized
        % businesses are never punished by. See cal_bui_sa_subsidy_targeted.m's
        % header for the full writeup.
        P=[0,prctile(building_average_salary(:,3),1:100)]; % salary by precentiles, from the STABLE (unsubsidized) column
        % Vectorized - same reasoning as the MVB30 ranking above.
        rank_col = sum(building_average_salary(:,2) >= P(1:100), 2);
        rank_col(rank_col==0) = 100; % highest score
        building_average_salary(:,4) = rank_col;
        
        %% empty building or residance - potential salary
        B=Build_Data(Build_Data(:,3)<2,:); % living or combined and no HH
        %% building area floors*area
        workers=ceil((B(:,7).*ceil(B(:,11)).*JobsPerM_comm*potential_jobs_per_meter_multiplier)); % model parameter jobs per comm, scaled for the potential-conversion candidate score
        pot_sal_for_B=[B(:,1),workers.*average_wage]; % building ID and total wage
        
        %% find_comm_visit_rank
        [locA,locB]=ismember(building_average_salary(:,1),MVB30(:,1)); % locate building id in visits metrix
        building_average_salary(locA,5)=MVB30(locB(locB>0),3); % col(5) visits ranking (col(3)=original wage, col(4)=salary rank - see cal_bui_sa_subsidy_targeted.m)
        building_average_salary(:,6)=building_average_salary(:,5)-building_average_salary(:,4); % diff in ranks: visits rank(5) - salary rank(4)

        %% new jobs - com only
        % check sensitivity of condition limit
        new_jobs=building_average_salary(building_average_salary(:,6)>20,1); % only rank diff above 20 vector
        std_wage_1 = std_wage/3; % normilize std wage value
		B_D = [];
        for jjjj=1:length(new_jobs)
            a=find(Work_places(:,1)==new_jobs(jjjj)); % indexes for building ID match
            b=find(Build_Data(:,1)==new_jobs(jjjj)); % find exact building id
            if sum(Work_places(a,5)<Build_Data(b,17)*1.7)>0 % current number of jobs lower then initial
                Work_places(a,5)=Work_places(a,5)+1;
                B_D=[B_D;Work_places(a(1),1:5)]; % copy ID, SA and coordinates
            end
        end
        if ~isempty(B_D)
            working99_prob = 1-commute_outside; % from city configuration block
            new_jobs_sa=normrnd(average_wage,std_wage_1,size(B_D,1),1); % normalized wage vector
            occ=zeros(size(B_D,1),1); % zeros vector
            working99 = randsample(size(B_D,1), round(working99_prob*size(B_D,1)));
            occ(working99) = 99;
            new_id=(max(Work_places(:,6))+1:max(Work_places(:,6))+size(B_D,1))'; % max workplace ID to new vector
            % {'building id','stat','X','Y','number of work places','id','occupied','salary'}
            new_jobs_work_places=[B_D,new_id,occ,new_jobs_sa]; % append cols NaN, new workspace ID, zeros, normalized wage
            Work_places=[Work_places; new_jobs_work_places]; % append rows to work places
        end

        %% lost jobs
        lost_jobs_B_ID=building_average_salary(building_average_salary(:,6)<-20,1); % only rank diff below -20 vector
        lost_jobs_B_ID=Build_Data(ismember(Build_Data(:,1),lost_jobs_B_ID),[1,17]); % all matching ID cols(1 and 17)
        [~, newB] = ismember(lost_jobs_B_ID(:,1),Work_places(:,1)); % building ID first index matching
        lost_jobs_WP_ID = Work_places( newB,[1,5]); % current WP count out of avalible by building
        lost_jobs_B_ID = sortrows(lost_jobs_B_ID, 1); % sort to match building ID
        lost_jobs_WP_ID = sortrows(lost_jobs_WP_ID, 1); % sort to match building ID
        lost_jobs_B_ID(:,3)=round(lost_jobs_WP_ID(:,2)-1); % col(3) workplace-1
        newB = ismember(Work_places(:,1),lost_jobs_B_ID(:,1)); % find all building id
        lost_jobs_B_ID(:,4)=lost_jobs_B_ID(:,3)./lost_jobs_B_ID(:,2)<0.5; % normilized value < 0.5

        %% delete all jobs (original, before policy change)
        %F=lost_jobs_B_ID(lost_jobs_B_ID(:,4)==1,1); % locate all lost jobs
        %Work_places(ismember(Work_places(:,1),F),7)=2; % delete all jobs from building
        %% lost job ID
        %lost_job_id=Work_places(ismember(Work_places(:,1),F),6); % Workplace ID match to lost 
        %Build_Data(ismember(Build_Data(:,1),F) & Build_Data(:,3)==3,3)=0; % Usage=0 if lost and was 3

        %% delete all jobs from the buildings

        F=lost_jobs_B_ID(lost_jobs_B_ID(:,4)==1,1);
        
        if commercial_preservation
        
            F_keep = [];
        
            for jj = 1:length(F)
        
                bld = F(jj);
        
                if ismember(bld,damaged_buildings)
                    p = comm_damaged_prob;
                else
                    p = comm_undamaged_prob;
                end
        
                if rand > p
                    F_keep = [F_keep; bld];
                end
        
            end
        
            F = F_keep;
        
        end
        
        Work_places(ismember(Work_places(:,1),F),7)=2;

        lost_job_id=Work_places(ismember(Work_places(:,1),F),6);
        closed_wp_ids_today=[closed_wp_ids_today;Work_places(ismember(Work_places(:,1),F),6)];

        Build_Data(ismember(Build_Data(:,1),F) & Build_Data(:,3)==3,3)=0;



        %% delete one job
        % Check if only one job is deleted for each building
        % sort worplaces by building and wage, and delete the lost wage
        F=lost_jobs_B_ID(lost_jobs_B_ID(:,4)==0,1); % value above 0.5 ; workplace/round(worplace-1)
        [~,locB]=ismember(F,Work_places(:,1)); % indexes by matching building ID
        Work_places(locB,7)=2; % 'occupied'=2
        lost_job_id=[lost_job_id;Work_places(locB,6)]; % append rows only col(6) - 'id'
        closed_wp_ids_today=[closed_wp_ids_today;Work_places(locB,6)];

        %% people lost job - matched by the SPECIFIC workplace slot that
        % actually closed today (work_place_id, col 17), not by building
        % (col 15) - matching by building previously laid off every
        % current employee at a building even when only one slot of
        % several was supposed to close.
        ind_lost_job = ismember(Individuals_data(:,17),closed_wp_ids_today);
        Individuals_data(ind_lost_job,12) = 1; % 'working status' = 1
        Individuals_data(ind_lost_job,15) = 0; % 'building_work_place' = 0
        Individuals_data(ind_lost_job,17) = 0; % 'work_place_id' = 0
        Individuals_data(ind_lost_job,14) = 0; % 'income' = 0

        %% commercial potantial change LU
        if  comm_policy==0
            [locA,locB]=ismember(pot_sal_for_B(:,1),MVB30(:,1)); % building ID and total wage ; mean visit per building
            pot_sal_for_B(locA,3)=MVB30(locB(locB>0),3); % new col(3) append mean visits ranking
            % Vectorized (was: per-candidate loop calling prctile fresh for
            % every candidate, then linearly scanning 100 bins by
            % re-testing bin membership against the WHOLE base array just
            % to read its last element) - ported from the same fix in
            % modelthesis/run_model_earthquake.m. Mathematically identical
            % result: for each candidate, prctile([base_salaries;
            % candidate_value], 1:100) is still computed with the
            % candidate as the last element, exactly as before - just
            % batched into one matrix call instead of one call per
            % candidate. The bin index (ppp) a value v falls into is
            % exactly count(P(1:100) <= v), same as the two ranking loops
            % above - thresholds now driven by lu_change_rank_lower/upper
            % (default 20/40, matching the original hardcoded values;
            % override via a driver script for a different calibration).
            Change_LU=[];
            Mcand = size(pot_sal_for_B,1);
            if Mcand>0
                % STABLE-YARDSTICK FIX (chat 2026-09-15): col(3), not col(2)
                % - same reasoning as the job-growth/loss ranking above.
                % Candidate buildings get compared against the real,
                % unsubsidized commercial wage distribution, not one
                % artificially compressed by however many buildings a
                % subsidy mode happens to be covering that week.
                base_col = building_average_salary(:,3);
                cand_vals = pot_sal_for_B(:,2)'; % 1 x Mcand
                A_mat = [repmat(base_col,1,Mcand); cand_vals]; % (Nbase+1) x Mcand
                P_raw = prctile(A_mat,1:100); % 100 x Mcand normally, but Mcand==1 makes A_mat a plain column vector and prctile degenerates to a 1x100 row instead
                if Mcand==1
                    P_raw = P_raw(:);
                end
                P_mat = [zeros(1,Mcand); P_raw]; % 101 x Mcand, row1=P(1)=0 matching the scalar P(1:100) below
                ppp_vec = sum(P_mat(1:100,:) <= cand_vals, 1)'; % Mcand x 1 - P(1:100) = [0, prctile(1)..prctile(99)], same as the two ranking loops above
                V_vec = pot_sal_for_B(:,3) - ppp_vec;
                Change_LU = pot_sal_for_B(V_vec>lu_change_rank_lower & V_vec<lu_change_rank_upper, 1);
            end
            %% change land use
            %[locA,~]=ismember(Build_Data(:,1),Change_LU); % locate building ID in new list
            %Build_Data(locA,3)=3; % 'Usage' = 3 - commercial
            %New_Comm_B=Build_Data(locA,:); % Only commercial
                
            %% residential preservation policy

            if residential_preservation
            
                Change_LU_keep = [];
            
                for jj = 1:length(Change_LU)
            
                    bld = Change_LU(jj);
            
                    if ismember(bld,damaged_buildings)
                        p = res_damaged_prob;
                    else
                        p = res_undamaged_prob;
                    end
            
                    if rand < p
                        Change_LU_keep = [Change_LU_keep; bld];
                    end
            
                end
            
                Change_LU = Change_LU_keep;
            
            end

            %% change land use
            
            [locA,~]=ismember(Build_Data(:,1),Change_LU);
            
            Build_Data(locA,3)=3;
            
            New_Comm_B=Build_Data(locA,:);

            
            %% delete residental jobs in building
            locA=ismember(Work_places,New_Comm_B(:,1)); % workplaces in commercial building
            lost_job_id=[lost_job_id;Work_places(locA,6)]; % append rows in lost jobs
            
            %% HH must find new house
            locA=ismember(HH_data(:,10),New_Comm_B(:,1)); % 'building id' in commercial buildings
            newly_evicted=HH_data(locA,[2,10]); % 'HH ID' and their (now-commercial) old building id
            % LU_Displaced retry pool (see its init comment near
            % Sheltered_Outside above) - this step's fresh evictees plus
            % anyone still waiting from a prior step's conversion both get
            % a same-SA search attempt below.
            already_tracked = ismember(newly_evicted(:,1), LU_Displaced(:,1));
            LU_Displaced = [LU_Displaced; newly_evicted(~already_tracked,1), repmat(i,sum(~already_tracked),1), newly_evicted(~already_tracked,2)];
            moving_HH=unique([newly_evicted(:,1); LU_Displaced(:,1)]);
            % Guard: an HH_ID must map to exactly one current HH_data row to
            % be safely retried - if it maps to 0 (deleted despite the
            % exemptions above - shouldn't happen, but defensive) or >1 rows
            % (HH IDs are minted via max(HH_data(:,2))+1 at creation, e.g.
            % by migration_19 - if the household that held the running-max
            % ID is later deleted, a subsequent migrant can coincidentally
            % be issued that same numeric ID again, producing two HH_data
            % rows sharing an ID), drop it from this retry batch instead of
            % feeding an ambiguous ID into find_new_house_same_stat (which
            % assumes exactly one match per ID and errors on a size
            % mismatch otherwise - observed with a large, long-lived
            % LU_Displaced pool, where the odds of hitting this rare
            % pre-existing ID-reuse edge case are much higher than for any
            % other retry pool in this script).
            [uniq_hh_ids, ~, ic] = unique(HH_data(:,2));
            ambiguous_ids = uniq_hh_ids(accumarray(ic,1) > 1);
            moving_HH = moving_HH(ismember(moving_HH, HH_data(:,2)) & ~ismember(moving_HH, ambiguous_ids));
            LU_Displaced = LU_Displaced(~ismember(LU_Displaced(:,1), ambiguous_ids), :);
            if isempty(moving_HH)==0
                [HH_ID_left,HH_data,Assets,HH_change,LU,...
                    new_A,new_B,Build_Data]...
                    =find_new_house_same_stat(HH_ID_left,pd,HH_data,Individuals_data,Build_Data,...
                    Build_Distance_matrix_400,Assets,wresd,moving_HH,LU,new_A,new_B,HH_change);
            end
            % NOTE: find_new_house_same_stat above already cascades
            % same-SA -> same-yeshuv-other-SA -> other-yeshuv internally
            % (see its own source) - a separate find_new_house_yeshuv call
            % here would just re-run the identical same-yeshuv/other-yeshuv
            % queries a second time for no benefit (confirmed empirically:
            % adding one produced byte-identical results). The real
            % bottleneck for whoever's still in HH_ID_left at this point is
            % genuine city-wide housing scarcity right after a large
            % one-time conversion wave, not narrow search scope.
            %saves HH that leave simulation before they are deleted

            % release: a LU_Displaced household is done once it's no longer
            % living in the (converted) building it was evicted from - same
            % secured-a-new-asset detection release_outside_shelter.m uses
            % for Sheltered_Outside.
            [lu_found, lu_loc] = ismember(LU_Displaced(:,1), HH_data(:,2));
            lu_still_needs_home = false(size(LU_Displaced,1),1);
            lu_still_needs_home(lu_found) = HH_data(lu_loc(lu_found),10) == LU_Displaced(lu_found,3);
            LU_Displaced = LU_Displaced(lu_found & lu_still_needs_home, :);

            % patience: same grace period as Sheltered_Outside - exempt from
            % deletion while within outside_patience_duration of first being
            % displaced; falls through to normal did_not_find_house once
            % patience runs out and this step's search also failed.
            patient_lu_hh = LU_Displaced(i - LU_Displaced(:,2) < outside_patience_duration, 1);
            HH_ID_left = HH_ID_left(~ismember(HH_ID_left, patient_lu_hh));

            %% delete HH that left
            [Individuals_data,Work_places,HH_data,Assets,HH_ID_left]= ...
            did_not_find_house(HH_ID_left,Individuals_data,Work_places,HH_data,Assets);
            % prune LU_Displaced bookkeeping for anyone just deleted above
            % (patience expired) - their HH_ID no longer exists in HH_data.
            LU_Displaced(~ismember(LU_Displaced(:,1), HH_data(:,2)), :) = [];
    
            %% new jobs because of land use
            workers=(New_Comm_B(:,7).*ceil(New_Comm_B(:,11)).*JobsPerM_comm*jobs_per_meter_multiplier); % Area*roundup(floor)*0.014, scaled for actual job creation in newly-converted buildings; have col(25) already claculated
            workers(workers<1)=1;
		    New_Comm_B(:,17)=workers; % num of workers
            a=round(New_Comm_B(:,17))>0; % all workplaces with at least 1 worker
            wp=New_Comm_B(a,:); % new data
            wp(:,17)=round(wp(:,17)); % roundup values
            u=unique(wp(:,17)); %  unique workers count
            wp1=[];
            for iii=1:length(u) % duplicate all unique workplaces into new by workers count
                data=[];
                data=repmat(wp(wp(:,17)==u(iii),:),u(iii),1); % matrix of diplicated rows
                wp1=[wp1;data]; % append workplaces 
            end
            if size(wp1,1)>0 
                WP=wp1(:,[1,4:6,17]); % copy col(1,4,5,6,17) ; 'BLDG_ID_x' 'SAID' 'X' 'Y' 'work place'
                new_id=(max(Work_places(:,6))+1:max(Work_places(:,6))+size(WP,1))'; % create id to new workpaces 
                WP(:,6)=new_id; % assing cinsecutive id to new workpaces
                occ=zeros(size(WP,1),1); % zeros vector
                working99 = randsample(size(WP,1), round(working99_prob*size(WP,1)));
                occ(working99) = 99;
                WP(:,7)=occ; % set occupied=0
                std_wage_1 = std_wage/3; % normilized wage
                N=normrnd(average_wage,std_wage_1,[size(WP,1),1]); % random values for wage
                WP(:,8)=N; % set 'salary'
                Work_places=[Work_places;WP]; % append rows
            end
            if size(VISITS, 2) > 5
                VISITS(:,2:end-1)=VISITS(:,3:end); % Shift columns left - was >31 daily steps, now 4-step (~1 month) window
                VISITS(:,end)=[]; % Delete the last column
            end
        end
    end
    
    %% MODEL SHUK HAVODA:
    % commute_outside comes from the city configuration block
    wp_prc=prctile(Work_places(:,8),1:100); % calc precentiles by salary
    top_10_prc=wp_prc(1,90); % get salary min threshold 
    lost_wp=Work_places(:,8)>top_10_prc; % workplaces with high salary
    if sum(lost_wp)>0
        WP_buildings=Work_places(lost_wp,:); % all workplaces above max salary by ID
        Work_places(lost_wp,:)=[]; % remove workplaces with high salary
        [~,locW]=ismember(WP_buildings(:,1),Build_Data(:,1)); % find workpaces building 
        Z=Build_Data((locW <= 0 | isnan(locW)),23); % 23 -'Working zone'
        F=find(Z==31); % all 31 zone
        rand_wp = randsrc(size(F,1),1,[1,0;commute_outside,1-commute_outside]);
        F(rand_wp ==0)=[];
        WP_buildings(F,7)=99; % 'occupied' = 99        
        Work_places=[Work_places;WP_buildings]; % append new rows with 99 
    end
    %% change average_wage
    % alfa/beta/lamda/delta come from the city configuration block

    Occupied_Jobs_1=sum(Work_places(:,7)==1 | Work_places(:,7)==99)/sum(Work_places(:,7)~=2); % occupied/total
    a=Build_Data(:,3)>0; % 4 - industrial ; 5 - public ; 6 - senior 
    Floor_Size_1=sum(Build_Data(a,7).*ceil(Build_Data(a,11))); % area*floors
    
    job_ratio=(Occupied_Jobs_1/Occupied_Jobs)^(1-beta); % ( (occupied ratio new)/(occupied ratio initial) )^(1-0.6)
    floor_ratio=(Floor_Size_1/Floor_Size)^alfa; % ( (all buildings size)/(class 4-5-6 buildings size) )^0.4
    income_ratio=(job_ratio/floor_ratio)^(1/lamda); % ( (job ratio)/(floor ratio) )^(1/0.25)
    if i >1 % after first iteration
        average_wage_1=income_ratio*average_wage; % new mean wage
        Wage_Change=average_wage_1-average_wage; % wage delta
        average_wage=average_wage_1; % update mean wage
    end

    %% change salary for empty jobs ; update unoccupied salary by new ratio
    Work_places(Work_places(:,7)==0,8)=Work_places(Work_places(:,7)==0,8).*income_ratio;

    %% change salary for occupied jobs
    R=datasample(random_number,sum(Work_places(:,7)==1)); % random values as size of occupied worplaces 
    R=R<abs(1/income_ratio-1); % random < |1/ratio - 1|
    Work_places(R,8)=Work_places(R,8).*delta.*income_ratio; % salary*0.8*ratio 
    low_sal = Work_places(:,8) < min_sal/4;
    Work_places(low_sal,8)=min_sal/4;
	F=find(R==1); % indexes for true values

    if income_ratio<1
        r=datasample(random_number,sum(R)); % random values as size of true values
        r=r<abs(1/(income_ratio*delta)-1); % random < |1/(ratio*0.8) - 1|
        Work_places(F(r),7)=0; % update to unoccupied
        lost_job_id=[lost_job_id;Work_places(F(r),6)]; % append ID of unoccupied workplaces
    end
    
    %% add people to working market
    if income_ratio>1
        F=(Individuals_data(:,6)>1 & Individuals_data(:,12)<1); % not kid and not working
        P=income_ratio-1; 
        if P>=1
            P = 0.8;
        end
        S=round(sum(F)*P); % qualified for work by probability
        F=find(F==1);
        P=datasample(F,S,'replace',false'); % random unique indexes
        % was Individuals_data(F,12)=1 - applied the status change to the
        % ENTIRE eligible pool F instead of the size-S random sample P
        % actually drawn from it, pushing everyone eligible into job
        % search regardless of the computed probability-scaled target.
        Individuals_data(P,12)=1; % 'working status'=1
    end
    
    %% imiggratoin inside ; update agents list and workplaces
    [Assets,HH_data,Individuals_data,Work_places,routine,new_A]=...
    migration_19(Assets,intra_SA,HH_data,Individuals_data,Work_places,new_A);

    %% delete HH that left
    % LU_Displaced exemption again (same reasoning as the K=2 site above) -
    % recomputed since the LU block earlier this step may have added fresh
    % entries after the first computation.
    patient_lu_hh = LU_Displaced(i - LU_Displaced(:,2) < outside_patience_duration, 1);
    HH_ID_left = HH_ID_left(~ismember(HH_ID_left, patient_lu_hh));
    % resSearchLen retry gate (see the K=2/K=3 site above for full
    % explanation). HH_ID_left is normally already [] by this point (the
    % earlier did_not_find_house call this step reset it, and migration_19
    % doesn't populate it) - kept for defensiveness/consistency in case
    % that ever isn't true.
    if ~isempty(HH_ID_left)
        [locA,~] = ismember(HH_data(:,2), HH_ID_left);
        HH_data(locA,13) = HH_data(locA,13) + 1;
        [~,locB] = ismember(HH_ID_left, HH_data(:,2));
        HH_ID_left = HH_ID_left(HH_data(locB,13) >= resSearchLen);
    end
    [Individuals_data,Work_places,HH_data,Assets,HH_ID_left]=did_not_find_house(HH_ID_left,Individuals_data,Work_places,HH_data,Assets);
    
    %% number of routine per person
    [Individuals_data,id]=new_number_of_routine(Individuals_data,acts,wactsnum,agent_rot,HH_change,routine,Ind_change_routine);
    % include agents whose shelter status changed this step (entered/left
    % immediate tier, temp-dev, or out-of-city) - see routine_recompute_ids
    % population above - so their routine gets rebuilt around where
    % they're actually staying instead of a stale location.
    id=unique([id;routine_recompute_ids]);

    %% new activities locations
    if size(id,1)>0
        [Building_routine_id]=find_activity_location_new_A(Individuals_data,Build_Data,Work_places,HH_data,wact1,wact2,wactsnum,SA,id,Building_routine_id,routine_home_override);
        a=ismember(Building_routine_id(:,1),Individuals_data(:,1)); % match agent ID
        Building_routine_id(a==0,:)=[]; % remove unmatched IDs
    end

    % Sheltered_Outside HH: re-suppress local (non-work) routine every
    % step for NON-working members only, in case the routine engine
    % reassigned local activities to them above for an unrelated reason.
    % Working members keep their real (reduced, workplace-anchored)
    % routine from item 3 above - re-NaNing them here would undo that.
    % Work location (col 3) is left untouched - job continuity.
    if ~isempty(Sheltered_Outside)
        outside_agents = Individuals_data(ismember(Individuals_data(:,3), Sheltered_Outside(:,1)), 1);
        [~, locOA] = ismember(outside_agents, Individuals_data(:,1));
        is_working = Individuals_data(locOA,12)==2 & Individuals_data(locOA,17)>0 & Individuals_data(locOA,17)~=99;
        outside_nonworking = outside_agents(~is_working);
        a_idx = ismember(Building_routine_id(:,1), outside_nonworking);
        Building_routine_id(a_idx, 4:end) = NaN;
    end

    %% check empty buildings ;
    % Arad uses the patched variant - see the init call above for why.
    if strcmp(city,'Arad')
        [Build_Data,Build_Data_p]=find_empty_buildings_arad(Assets,Build_Data,Build_Data_p);
    else
        [Build_Data,Build_Data_p]=find_empty_buildings(Assets,Build_Data,Build_Data_p);
    end

    %% sas move:
    % calculate building service ratio
    [Build_Data]=building_service_ratio(Build_Data,Build_Data_p,Build_Distance_matrix_400);
    m = nanmean(Assets(:,12)); % mean assets price
    s = nanstd(Assets(:,12)); % stdev assets price
    f = Assets(:,12) > (m + 2*s); % price > m+2s
    Assets(f,12) = m + 2.5*s.*rand(sum(f),1); % update price m+2.5s*random

    if length(new_A)==0
        new_A(:,4)=0;
    end
    new_A;
    if mod(i,4)==0 % was mod(i,30) daily steps (~1 month cadence)
        % VECTORIZED (ported from modelthesis/run_model_earthquake.m,
        % commit 9b078e7 "vectorize hot loops"): was a per-SA loop that
        % re-scanned the FULL Assets/Build_Data/Work_places/
        % Individuals_data/HH_data arrays from scratch for every one of
        % these ~22 metrics, every SA - ~20 SAs x ~22 metrics of redundant
        % full-array filtering per call, every 4 steps. Group indices are
        % computed ONCE and reused via accumarray, mathematically
        % identical to the original nanmean/mean/sum over the same
        % boolean masks (nanmean vs plain mean preserved exactly
        % per-metric to match the original's NaN handling).
        nSA = length(g_sa);
        [~, asset_grp] = ismember(Assets(:,1), g_sa);
        [~, build_grp] = ismember(Build_Data(:,4), g_sa);
        [~, wp_grp]    = ismember(Work_places(:,2), g_sa);
        [~, ind_grp]   = ismember(Individuals_data(:,2), g_sa);
        [~, hh_grp]    = ismember(HH_data(:,1), g_sa);

        accsum     = @(grp,val) accumarray(grp(grp>0), val(grp>0), [nSA,1], @sum, 0);
        accnanmean = @(grp,val) accumarray(grp(grp>0), val(grp>0), [nSA,1], @(x) mean(x,'omitnan'), NaN);
        accmean    = @(grp,val) accumarray(grp(grp>0), val(grp>0), [nSA,1], @mean, NaN);

        SA_PRICE(:,i+1) = accnanmean(asset_grp, Assets(:,5));

        res_bld_ids  = Build_Data(Build_Data(:,3)==1 | Build_Data(:,3)==2, 1);
        comm_bld_ids = Build_Data(Build_Data(:,3)>2, 1);
        is_res_asset  = ismember(Assets(:,2), res_bld_ids);
        is_comm_asset = ismember(Assets(:,2), comm_bld_ids);
        house_grp = asset_grp; house_grp(~is_res_asset) = 0;
        comm_grp  = asset_grp; comm_grp(~is_comm_asset) = 0;
        SA_HOUSE(:,i+1)     = accnanmean(house_grp, Assets(:,5));
        SA_COMERCIAL(:,i+1) = accnanmean(comm_grp,  Assets(:,5));

        SA_POP(:,i+1)    = accsum(asset_grp, Assets(:,11));
        SA_ASSETS(:,i+1) = accsum(asset_grp, ones(size(Assets,1),1));

        SA_SERVICE(:,i+1)  = accsum(build_grp, double(Build_Data(:,3)>2));
        SA_RESIDENT(:,i+1) = accsum(build_grp, double(Build_Data(:,3)==1 | Build_Data(:,3)==2));
        area_grp = build_grp; area_grp(Build_Data(:,3)~=3) = 0;
        SA_AREA(:,i+1) = accsum(area_grp, Build_Data(:,25));

        SA_WP(:,i+1) = accsum(wp_grp, ones(size(Work_places,1),1));
        wp7 = Work_places(:,7);
        jobs_num_grp = wp_grp; jobs_num_grp(~(wp7==1 | wp7==3)) = 0;
        jobs_den_grp = wp_grp; jobs_den_grp(wp7==2 | wp7==99) = 0;
        jobs_num = accsum(jobs_num_grp, ones(size(Work_places,1),1));
        jobs_den = accsum(jobs_den_grp, ones(size(Work_places,1),1));
        SA_JOBS(:,i+1) = jobs_num ./ jobs_den;

        ind12 = Individuals_data(:,12);
        ind15 = Individuals_data(:,15);
        working_num_grp = ind_grp; working_num_grp(ind12~=2) = 0;
        working_num = accsum(working_num_grp, ones(size(Individuals_data,1),1));
        SA_WORKING(:,i+1) = working_num ./ jobs_den;

        SA_OUTCOME(:,i+1) = accsum(wp_grp, Work_places(:,8));

        % see the day-1 SA_LOCAL init above for why col(15)~=99 (not
        % col(12)==99) is the correct local/outside check
        local_num_grp = ind_grp; local_num_grp(~(ind12==2 & ind15~=99)) = 0;
        local_den_grp = ind_grp; local_den_grp(ind12~=2) = 0;
        local_num = accsum(local_num_grp, ones(size(Individuals_data,1),1));
        local_den = accsum(local_den_grp, ones(size(Individuals_data,1),1));
        SA_LOCAL(:,i+1) = local_num ./ local_den;

        idle_num_grp = ind_grp; idle_num_grp(ind12~=1) = 0;
        idle_den_grp = ind_grp; idle_den_grp(~(ind12>0)) = 0;
        idle_num = accsum(idle_num_grp, ones(size(Individuals_data,1),1));
        idle_den = accsum(idle_den_grp, ones(size(Individuals_data,1),1));
        SA_IDLE(:,i+1) = idle_num ./ idle_den;

        wage_grp = ind_grp; wage_grp(~(ind15>0 & ind15~=99)) = 0;
        SA_WAGE(:,i+1) = accmean(wage_grp, Individuals_data(:,14));

        hh7 = HH_data(:,7);
        d1=hh_grp; d1(hh7~=1)=0;   SA_FIRST(:,i+1)  = accsum(d1,  ones(size(HH_data,1),1));
        d2=hh_grp; d2(hh7~=2)=0;   SA_SECOND(:,i+1) = accsum(d2,  ones(size(HH_data,1),1));
        d3=hh_grp; d3(hh7~=3)=0;   SA_THIRD(:,i+1)  = accsum(d3,  ones(size(HH_data,1),1));
        d4=hh_grp; d4(hh7~=4)=0;   SA_FOURTH(:,i+1) = accsum(d4,  ones(size(HH_data,1),1));
        d5=hh_grp; d5(hh7~=5)=0;   SA_FIFTH(:,i+1)  = accsum(d5,  ones(size(HH_data,1),1));
        d6=hh_grp; d6(hh7~=6)=0;   SA_SIXTH(:,i+1)  = accsum(d6,  ones(size(HH_data,1),1));
        d7=hh_grp; d7(hh7~=7)=0;   SA_SEVENTH(:,i+1)= accsum(d7,  ones(size(HH_data,1),1));
        d8=hh_grp; d8(hh7~=8)=0;   SA_EIGHTH(:,i+1) = accsum(d8,  ones(size(HH_data,1),1));
        d9=hh_grp; d9(hh7~=9)=0;   SA_NINTH(:,i+1)  = accsum(d9,  ones(size(HH_data,1),1));
        d10=hh_grp; d10(hh7~=10)=0; SA_TENTH(:,i+1)  = accsum(d10, ones(size(HH_data,1),1));

        for g=1:nSA % unique SA ID ; next step calculations
            % SA_POP/SA_ASSETS/SA_SERVICE are only ever written at column 1
            % and at columns (prior mod(i,4)==0 trigger)+1 - i.e. columns
            % {1,5,9,13,...}. The trigger column i itself (4,8,12,...) is
            % NEVER a member of that set, so SA_POP(g,i) etc. was always
            % the auto-grown-as-zero placeholder - not just on the first
            % trigger, but on EVERY trigger for the whole run - making the
            % `if >0` guard below permanently false and SA_*_RATIO
            % permanently pinned at the neutral fallback of 1. That, in
            % turn, made SA_LOGC always exactly 0 and SA_price1 always
            % exactly equal to SA_PRICE (see its formula just below) - the
            % intended price-growth-tracks-population/asset/service-growth
            % feedback never actually engaged, for the entire simulation,
            % in any run. Fix: the correct "previous" snapshot to compare
            % column i+1 against is 4 steps back, i.e. column (i+1)-4 =
            % i-3 (part of the {1,5,9,13,...} write-set, so always
            % populated by the time this trigger fires) - not column i.
            if SA_POP(g,i-3)>0
                SA_POP_RATIO(g,i+1)=SA_POP(g,i+1)/SA_POP(g,i-3);
            else
                SA_POP_RATIO(g,i+1)=1;
            end
            if SA_ASSETS(g,i-3)>0
                SA_ASSET_RATIO(g,i+1)=SA_ASSETS(g,i-3)/SA_ASSETS(g,i+1);
            else
                SA_ASSET_RATIO(g,i+1)=1;
            end
            if SA_SERVICE(g,i-3)>0
                SA_SERVICE_RATIO(g,i+1)=SA_SERVICE(g,i+1)/SA_SERVICE(g,i-3);
            else
                SA_SERVICE_RATIO(g,i+1)=1;
            end
            % (population+asset+service)/3
            SA_C=(SA_POP_RATIO(g,i+1)+ SA_ASSET_RATIO(g,i+1)+ SA_SERVICE_RATIO(g,i+1))./3;
            SA_LOGC(g,i+1)=log(SA_C);
            SA_price1(g,i+1)= SA_PRICE(g,i+1).*(1+ SA_LOGC(g,i+1)); % price*(1+log(total ratio))
    
            b_data=Build_Data(build_grp==g,:); % building list within SA - reuses the group index computed above

            [locA,~]=ismember(Assets(:,2), b_data(:,1)); % match building ID
            Assets(locA,5) = Assets(locA,5).*(1+ SA_LOGC(g,i+1)); % ppm*(1+log(total ratio))
           
            FLOORSPACE = b_data(:,25); 
            sa_service_ratio = sum(b_data(:,3) >2) / sum(b_data(:,3)<=2); % sum(usage>2)/sum(usage<=2)
            if SA_SERVICE_RATIO(g,i+1) > 0 
                B_SERVICES_RATIO=b_data(:,19)./sa_service_ratio; % (building sevice ratio) / (SA sevice ratio)
            else
                B_SERVICES_RATIO = 0;
            end
            B_VALUE = FLOORSPACE.*SA_price1(g,i+1).*(B_SERVICES_RATIO); % floorspace*mean(ppm)*ratio

         

            %% problem with b value ; % remove zeros
            A=B_VALUE==0;
            B_VALUE(A)=[];
            b_data(A,:)=[];
            FLOORSPACE(A)=[];
            
            %%
            [~,locB]=ismember(b_data(:,1),Build_Data(:,1)); % match building ID
            Build_Data(locB,22) =B_VALUE; % update 'Building value'
            [locA,locB]=ismember(Assets(:,2), b_data(:,1)); % match building ID
            % 'real price' ; (asset area)/(building area) * (building value)
            Assets(locA,12)=(Assets(locA,4)./Build_Data(locB(locB>0),25)).*Build_Data(locB(locB>0),22);
        end
    end
    %% monthly assest cost
    mp = Assets(:,12); 
    mp(isinf(Assets(:,12))) = []; % remove infinite price
    p = nanmean(mp); % mean asset price
    Assets(isinf(Assets(:,12)),12) = p; % update to mean price
    m = nanmean(Assets(:,12)); 
    s = nanstd(Assets(:,12));
    f = Assets(:,12) > (m + 2*s);
    Assets(f,12) = m + 2*s .*rand(sum(f),1);
    Assets(isnan(Assets(:,12)),12) = m; % update to mean price
    [Assets]=monthly_ass_cost(HH_data,Assets,Assets_P,Pa); % 'cost of life'
    
    if size(lost_jobs_B_ID,1) > 0
        Work_places(ismember(Work_places(:,1),lost_jobs_B_ID(:,1)),:) =[]; % remove lost jobs check
    end

    %% sheltering-tier headcount snapshot (household-level, not agent-level)
    % Taken at the very end of the step, after this step's shelter
    % assign/release/temp-dev transfer AND the moving_HH search above have
    % all settled - so it reflects who's still in each tier once this
    % step's churn is done, not a mid-step transient.
    if isempty(Shelter_Assign)
        n_immediate_hh_now = 0;
    else
        n_immediate_hh_now = numel(unique(Individuals_data(ismember(Individuals_data(:,1), Shelter_Assign(:,1)), 3)));
    end
    n_outside_hh_now = size(Sheltered_Outside,1); % one row per household already
    if isempty(Temp_Dev_Assign)
        n_tempdev_hh_now = 0;
    else
        n_tempdev_hh_now = numel(unique(Individuals_data(ismember(Individuals_data(:,1), Temp_Dev_Assign(:,1)), 3)));
    end
    n_immediate_hh_max = max(n_immediate_hh_max, n_immediate_hh_now);
    n_outside_hh_max = max(n_outside_hh_max, n_outside_hh_now);
    n_tempdev_hh_max = max(n_tempdev_hh_max, n_tempdev_hh_now);
    n_immediate_hh_final = n_immediate_hh_now;
    n_outside_hh_final = n_outside_hh_now;
    n_tempdev_hh_final = n_tempdev_hh_now;
    n_immediate_hh_track(i) = n_immediate_hh_now;
    n_outside_hh_track(i) = n_outside_hh_now;
    n_tempdev_hh_track(i) = n_tempdev_hh_now;
    n_permanently_displaced_track(i) = n_permanently_displaced_total; % cumulative running total
    n_original_hh_permanently_displaced_track(i) = n_original_hh_permanently_displaced_total; % cumulative running total, original cohort only
    total_aid_distributed_track(i) = total_aid_distributed; % cumulative running total

end


n_reconstructed_final = n_destroyed_total - size(destroyed_B,1); % buildings destroyed at shock that have since recovered

clearvars -except Assets Assets_P Build_Data Build_Data_p HH_data HH_data_P...
            Individuals_data Individuals_data_P Work_places Work_places_P out_file_name file kk run_uid...
            SA_OUTCOME SA_POP SA_PRICE SA_SERVICE SA_WAGE SA_WP SA_RESIDENT SA_HOUSE SA_COMERCIAL...
            SA_IDLE SA_LOCAL SA_WORKING SA_JOBS SA_FIRST SA_SECOND SA_THIRD SA_FOURTH...
            SA_FIFTH SA_SIXTH SA_SEVENTH SA_EIGHTH SA_NINTH SA_TENTH SA_AREA...
            steps city run_timestamp shock_step resSearchLen...
            jobs_per_meter_multiplier potential_jobs_per_meter_multiplier lu_change_rank_lower lu_change_rank_upper JobsPerM_comm...
            alfa beta lamda delta...
            displaced_shelter agents_per_sqm public_bldg_usable_fraction restrict_public_shelters_to_schools...
            hotel_room_density agents_per_room Shelters Shelter_Assign...
            subsidy_residents_mode subsidy_businesses_mode subsidy_duration HH_track...
            outside_commute_penalty_pct outside_patience_duration tempdev_patience_duration Sheltered_Outside LU_Displaced temp_dev_delay...
            n_temp_dev_sites temp_dev_capacity_frac temp_dev_site_coords Temp_Dev_Sites Temp_Dev_Assign...
            sumdata destroyed_B RECOVERY bad_Assets...
            n_destroyed_total n_reconstructed_final...
            n_immediate_hh_max n_outside_hh_max n_tempdev_hh_max...
            n_immediate_hh_final n_outside_hh_final n_tempdev_hh_final...
            n_immediate_hh_track n_outside_hh_track n_tempdev_hh_track...
            n_permanently_displaced_total n_permanently_displaced_track...
            n_original_hh_permanently_displaced_total n_original_hh_permanently_displaced_track...
            n_hh_subsidized_total total_aid_distributed total_aid_distributed_track n_businesses_subsidized_total businesses_subsidized_ever_ids biz_subsidy_tracker...
            lu_warmup...
            rng_seed
full_file_name = fullfile(['earthquakeF\',char(out_file_name),' ',run_timestamp,' ',num2str(kk),' ',run_uid]);
save(full_file_name);
end
