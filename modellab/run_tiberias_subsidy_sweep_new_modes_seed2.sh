#!/bin/bash
# Second-seed replicate of run_tiberias_subsidy_sweep_new_modes.sh, to
# check whether that sweep's businesses-mode-1 result (0 businesses
# supported in every mode-1 combo, identical to businesses off) is a
# seed-specific artifact of that particular shock's damage draw, or a
# consistent pattern across seeds. Same combo grid: (0,0) baseline, then
# subsidy_residents_mode {5,6} x subsidy_businesses_mode {0,1,2} = 7 runs.
# Seed 82937 - reused from the Ashkelon subsidy sweep's second replicate
# seed for cross-run consistency. Same Tiberias config as the seed-74110
# run (shock_step=25, steps=150, land-use calibration, staged-sheltering
# defaults set explicitly).
#
# One matlab process at a time (established crash-avoidance discipline
# this session) -- sequential, not parallel. Check for other running
# matlab processes before launching.
set -e
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_subsidy_sweep_newmodes_seed2_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,biz_mode,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

SEED=82937
RESID_MODES=(0 5 6)
BIZ_MODES=(0 1 2)

for RM in "${RESID_MODES[@]}"; do
  for BM in "${BIZ_MODES[@]}"; do
    if [ "$RM" -eq 0 ] && [ "$BM" -ne 0 ]; then
      continue # baseline is just the single (0,0) combo, not 0 x every biz mode
    fi
    TS=$(date +%Y%m%d_%H%M%S)
    LOGFILE="logs/tiberias_sweep_newmodes_seed${SEED}_R${RM}_B${BM}_${TS}.output"
    echo "=== seed=$SEED R=$RM B=$BM -> $LOGFILE ==="
    BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
    matlab -batch "city='Tiberias'; jobs_per_meter_multiplier=3; potential_jobs_per_meter_multiplier=2; lu_change_rank_lower=45; lu_change_rank_upper=85; shock_step=25; steps=150; n_sims=1; outside_patience_duration=4; tempdev_patience_duration=8; rng_seed=${SEED}; subsidy_residents_mode=${RM}; subsidy_businesses_mode=${BM}; run('run_model_earthquake_shelteroverflow.m')" > "$LOGFILE" 2>&1
    EXIT_CODE=$?
    echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
    AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
    NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
    echo "$SEED,$RM,$BM,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
    echo "=== finished seed=$SEED R=$RM B=$BM exit=$EXIT_CODE file=$NEWFILE ==="
  done
done

echo "SWEEP_COMPLETE -> $MANIFEST"
