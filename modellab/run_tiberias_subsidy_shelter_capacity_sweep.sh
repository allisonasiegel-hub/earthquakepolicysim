#!/bin/bash
# Tiberias policy sweep: household (residents) subsidy options crossed
# with shelter capacity options only (chat 2026-09-22) - businesses
# subsidy deliberately left off (0) for now, per the user's explicit
# request to defer that axis.
#
# Axis 1 - subsidy_residents_mode: {0 (off), 5, 6} - modes 1-4 were
# removed 2026-09-18; mode 6 is the current 12-step-duration version
# (extended from 8 on 2026-09-20) and both 5/6 reflect the 2026-09-20
# "wage-yardstick fix" (subsidy no longer leaks into Individuals_data
# col 14 / the citywide wage yardstick) - see HH_subsidy_targeted.m.
#
# Axis 2 - temp_dev_capacity_frac: {0.5, 1.0} - the two named "standard
# sheltering-policy options" documented at
# run_model_earthquake_shelteroverflow.m's temp_dev_capacity_frac default
# (chat 2026-09-20): 0.5 = "limited capacity" (the script's own default,
# used implicitly by every earlier sweep this session), 1.0 = "everyone
# gets sheltered".
#
# subsidy_businesses_mode held at 0 throughout.
#
# Only (residents_mode=0, capacity_frac=0.5) is reused, from the earlier
# seed-74110/seed-82937 (0,0)-baseline runs - that combo is exactly the
# model's own defaults on every axis touched here, unaffected by any
# subsequent fix. Every other combo is fresh: 3 x 2 - 1 = 5 combos x 2
# seeds (74110, 82937) = 10 new runs.
#
# Same Tiberias config as every other sweep driver this session
# (shock_step=25, steps=150, land-use calibration, staged-sheltering
# defaults set explicitly).
#
# One matlab process at a time (established crash-avoidance discipline
# this session, and other sessions are actively contending for the same
# machine) -- sequential, not parallel, re-checked between every run. No
# `set -e`: a single combo failing logs and continues rather than killing
# the rest of the sweep (see chat 2026-09-19's full-sweep crash).
set -u
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_subsidy_shelter_capacity_sweep_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,capacity_frac,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"
echo "74110,0,0.5,\"earthquakeF/hotels EQ S 20260917_180445 1 pid15680.mat\",0" >> "$MANIFEST"
echo "82937,0,0.5,\"earthquakeF/hotels EQ S 20260918_164012 1 pid14688.mat\",0" >> "$MANIFEST"

SEEDS=(74110 82937)
RESID_MODES=(0 5 6)
CAPACITY_FRACS=(0.5 1.0)

wait_for_matlab_clear() {
  while true; do
    COUNT=$(powershell -NoProfile -Command "(Get-Process matlab -ErrorAction SilentlyContinue | Measure-Object).Count" | tr -d '\r')
    if [ "$COUNT" -eq 0 ] 2>/dev/null; then break; fi
    sleep 30
  done
}

for SEED in "${SEEDS[@]}"; do
  for RM in "${RESID_MODES[@]}"; do
    for CAP in "${CAPACITY_FRACS[@]}"; do
      if [ "$RM" -eq 0 ] && [ "$CAP" = "0.5" ]; then
        continue # reused baseline, see header comment
      fi
      wait_for_matlab_clear
      TS=$(date +%Y%m%d_%H%M%S)
      CAPTAG=$(echo "$CAP" | tr '.' 'p')
      LOGFILE="logs/tiberias_sweep_subshelt_seed${SEED}_R${RM}_CAP${CAPTAG}_${TS}.output"
      echo "=== seed=$SEED R=$RM capacity_frac=$CAP -> $LOGFILE ==="
      BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
      matlab -batch "city='Tiberias'; jobs_per_meter_multiplier=3; potential_jobs_per_meter_multiplier=2; lu_change_rank_lower=45; lu_change_rank_upper=85; shock_step=25; steps=150; n_sims=1; outside_patience_duration=4; tempdev_patience_duration=8; rng_seed=${SEED}; subsidy_residents_mode=${RM}; subsidy_businesses_mode=0; temp_dev_capacity_frac=${CAP}; run('run_model_earthquake_shelteroverflow.m')" > "$LOGFILE" 2>&1
      EXIT_CODE=$?
      echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
      AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
      NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
      echo "$SEED,$RM,$CAP,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
      if [ "$EXIT_CODE" -ne 0 ]; then
        echo "!!! seed=$SEED R=$RM CAP=$CAP FAILED (exit=$EXIT_CODE) - see $LOGFILE - continuing with remaining combos"
      fi
      echo "=== finished seed=$SEED R=$RM capacity_frac=$CAP exit=$EXIT_CODE file=$NEWFILE ==="
    done
  done
done

echo "SWEEP_COMPLETE -> $MANIFEST"
