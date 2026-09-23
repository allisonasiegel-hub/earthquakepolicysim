#!/bin/bash
# No-shock Tiberias baseline, 3 seeds (74110, 82937, 30581 - matching the
# household-subsidy x shelter-capacity sweep), for use as a reference
# scenario in the standard macro-comparison plots (chat 2026-09-23).
# Same land-use calibration and steps=150 as run_tiberias_calibrated.m;
# no shock_step set, so it stays a no-shock baseline (falls back to the
# script's own shock_step=900 default, never fires within 150 steps).
set -u
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_noshock_baseline_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,filename,exit_code" > "$MANIFEST"
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
  LOGFILE="logs/tiberias_noshock_baseline_seed${SEED}_${TS}.output"
  echo "=== seed=$SEED (no-shock) -> $LOGFILE ==="
  BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
  matlab -batch "city='Tiberias'; jobs_per_meter_multiplier=3; potential_jobs_per_meter_multiplier=2; lu_change_rank_lower=45; lu_change_rank_upper=85; steps=150; n_sims=1; rng_seed=${SEED}; run('run_model_earthquake_shelteroverflow.m')" > "$LOGFILE" 2>&1
  EXIT_CODE=$?
  echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
  AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
  NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
  echo "$SEED,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "!!! seed=$SEED FAILED (exit=$EXIT_CODE) - see $LOGFILE - continuing"
  fi
  echo "=== finished seed=$SEED exit=$EXIT_CODE file=$NEWFILE ==="
done

echo "SWEEP_COMPLETE -> $MANIFEST"
