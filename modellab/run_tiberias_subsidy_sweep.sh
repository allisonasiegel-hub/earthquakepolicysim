#!/bin/bash
# Subsidy policy sweep for Tiberias: every (subsidy_residents_mode,
# subsidy_businesses_mode) combination in {0,1,2} x {0,1,2}, 1 seed
# (74110 - reused from run_subsidy_sweep.sh's Ashkelon sweep so the two
# cities' sweeps are seed-comparable). 150 steps, shock at week 25 (NOT
# Ashkelon's week 40 - see run_tiberias_shock_step25_150.m: Tiberias's
# land-use module settles even faster than Ashkelon's, by week 8 vs
# week 20-21, so week 25 is its own validated shock point), staged-
# sheltering design (tempdev_patience_duration=8, outside_patience_
# duration=4 - both already the script's own defaults, set explicitly
# here anyway per run_ashkelon_shock_step25_150.m's convention so this
# driver can't silently drift if those defaults ever change).
# One matlab process at a time (established crash-avoidance discipline
# this session) -- sequential, not parallel. Do not run this concurrently
# with run_subsidy_sweep.sh (Ashkelon) -- check for other running matlab
# processes first.
set -e
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_subsidy_sweep_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,biz_mode,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

SEED=74110
MODES=(0 1 2)

for RM in "${MODES[@]}"; do
  for BM in "${MODES[@]}"; do
    TS=$(date +%Y%m%d_%H%M%S)
    LOGFILE="logs/tiberias_sweep_seed${SEED}_R${RM}_B${BM}_${TS}.output"
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
