#!/bin/bash
# Matched-seed sweep: mode 5 (4-week, decile-tiered 30/35/40%) and mode 6
# (12-week/3-month, decile-tiered 10/15/20%) vs the (0,0) no-subsidy baseline.
# (Mode 6 was 8 weeks until chat 2026-09-20, extended to match a 3-month
# policy target - this script's own logic doesn't hardcode the duration,
# it's read from HH_subsidy_targeted.m each run, so no other change needed here.)
# Business subsidy off throughout (isolating the household-subsidy effect
# only). 5 matched-seed replicates: same rng_seed reused across all 3
# combos per replicate index, so combo-to-combo differences reflect the
# policy change, not random noise (chat 2026-09-15/18). 150 steps, shock
# at week 40, staged-sheltering design. One matlab process at a time
# (established crash-avoidance discipline this session) - sequential,
# not parallel.
set -e
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/subsidy_sweep_r56_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,biz_mode,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

SEEDS=(60301 60302 60303 60304 60305)

for SEED in "${SEEDS[@]}"; do
  for RM in 0 5 6; do
    TS=$(date +%Y%m%d_%H%M%S)
    LOGFILE="logs/sweep_r56_seed${SEED}_R${RM}_${TS}.output"
    echo "=== seed=$SEED R=$RM -> $LOGFILE ==="
    BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
    matlab -batch "city='Ashkelon'; shock_step=40; steps=150; n_sims=1; tempdev_patience_duration=8; rng_seed=${SEED}; subsidy_residents_mode=${RM}; subsidy_businesses_mode=0; run('run_model_earthquake_shelteroverflow.m')" > "$LOGFILE" 2>&1
    EXIT_CODE=$?
    echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
    AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
    NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
    echo "$SEED,$RM,0,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
    echo "=== finished seed=$SEED R=$RM exit=$EXIT_CODE file=$NEWFILE ==="
  done
done

echo "SWEEP_COMPLETE -> $MANIFEST"
