#!/bin/bash
# Third-seed replicate of run_tiberias_subsidy_shelter_capacity_sweep.sh
# (chat 2026-09-22): same 6-combo grid (subsidy_residents_mode {0,5,6} x
# temp_dev_capacity_frac {0.5,1.0}, subsidy_businesses_mode=0 throughout),
# adding rng_seed 30581 as a third independent draw per combo, on top of
# the existing 74110/82937 replicates - requested to firm up the
# capacity-effect finding (permanent displacement roughly doubling from
# capacity 0.5->1.0 with no subsidy, but flat with residents subsidy on)
# beyond just 2 seeds' worth of noise tolerance.
#
# All 6 combos are fresh runs here - no reuse, since nothing exists yet
# for seed 30581 (including the (0,0.5) "baseline" combo, unlike the
# first two seeds which already had that one banked from earlier work).
#
# Same Tiberias config as every other sweep driver this session
# (shock_step=25, steps=150, land-use calibration, staged-sheltering
# defaults set explicitly).
#
# One matlab process at a time (established crash-avoidance discipline
# this session, and other sessions are actively contending for the same
# machine) -- sequential, not parallel, re-checked between every run. No
# `set -e`: a single combo failing logs and continues rather than killing
# the rest of the sweep.
set -u
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_subsidy_shelter_capacity_sweep_seed3_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,capacity_frac,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

SEED=30581
RESID_MODES=(0 5 6)
CAPACITY_FRACS=(0.5 1.0)

wait_for_matlab_clear() {
  while true; do
    COUNT=$(powershell -NoProfile -Command "(Get-Process matlab -ErrorAction SilentlyContinue | Measure-Object).Count" | tr -d '\r')
    if [ "$COUNT" -eq 0 ] 2>/dev/null; then break; fi
    sleep 30
  done
}

for RM in "${RESID_MODES[@]}"; do
  for CAP in "${CAPACITY_FRACS[@]}"; do
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

echo "SWEEP_COMPLETE -> $MANIFEST"
