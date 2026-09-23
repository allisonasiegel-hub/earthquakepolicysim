#!/bin/bash
# Rerun the (subsidy_residents_mode=0, subsidy_businesses_mode=0,
# temp_dev_capacity_frac=0.5) "baseline" fresh, under TODAY's code, for
# all 3 seeds used in the subsidy x shelter-capacity sweep (chat
# 2026-09-23). Replaces the Sept17/18-vintage reused baseline files,
# which turned out to be a confound: comparing them against fresh Sept22
# capacity=1.0 runs showed a household-count difference AT THE SHOCK STEP
# itself (before capacity_frac ever acts), proving the shared
# run_model_earthquake_shelteroverflow.m changed in some way (by other
# sessions, for unrelated reasons) between when the old baseline was
# generated and now - making the "capacity causes more permanent
# displacement" finding partly/wholly an artifact of comparing two
# different code versions, not a clean capacity_frac effect.
#
# Same Tiberias config as every other sweep driver this session
# (shock_step=25, steps=150, land-use calibration, staged-sheltering
# defaults set explicitly).
set -u
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_baseline_refresh_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,capacity_frac,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

SEEDS=(74110 82937 30581)

wait_for_matlab_clear() {
  while true; do
    COUNT=$(powershell -NoProfile -Command "(Get-Process matlab -ErrorAction SilentlyContinue | Measure-Object).Count" | tr -d '\r')
    if [ "$COUNT" -eq 0 ] 2>/dev/null; then break; fi
    sleep 30
  done
}

for SEED in "${SEEDS[@]}"; do
  wait_for_matlab_clear
  TS=$(date +%Y%m%d_%H%M%S)
  LOGFILE="logs/tiberias_baseline_refresh_seed${SEED}_${TS}.output"
  echo "=== seed=$SEED R=0 capacity_frac=0.5 (fresh) -> $LOGFILE ==="
  BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
  matlab -batch "city='Tiberias'; jobs_per_meter_multiplier=3; potential_jobs_per_meter_multiplier=2; lu_change_rank_lower=45; lu_change_rank_upper=85; shock_step=25; steps=150; n_sims=1; outside_patience_duration=4; tempdev_patience_duration=8; rng_seed=${SEED}; subsidy_residents_mode=0; subsidy_businesses_mode=0; temp_dev_capacity_frac=0.5; run('run_model_earthquake_shelteroverflow.m')" > "$LOGFILE" 2>&1
  EXIT_CODE=$?
  echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
  AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
  NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
  echo "$SEED,0,0.5,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "!!! seed=$SEED FAILED (exit=$EXIT_CODE) - see $LOGFILE - continuing"
  fi
  echo "=== finished seed=$SEED exit=$EXIT_CODE file=$NEWFILE ==="
done

echo "SWEEP_COMPLETE -> $MANIFEST"
