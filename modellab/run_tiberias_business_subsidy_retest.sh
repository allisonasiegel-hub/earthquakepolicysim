#!/bin/bash
# Retest of subsidy_businesses_mode 1/2 on Tiberias, after ashkelonwork's
# 2026-09-19 fix (run_model_earthquake_shelteroverflow.m now physically
# restores the 2 lowest-paid workers' jobs at each eligible destroyed
# commercial building at shock time, undoing shock_W/shock_I for those
# rows so cal_bui_sa_subsidy_targeted.m's destroyed-buildings eligibility
# check can actually fire - see that block's comment, chat 2026-09-19,
# bug found by this session).
#
# subsidy_residents_mode held at 0 (off) throughout - isolates the
# businesses-side fix from any residents-subsidy interaction. Only modes
# 1 and 2 are run here (not 0) since businesses_mode=0 is untouched by
# the fix (the new restoration code only runs inside
# `if subsidy_businesses_mode == 1 || subsidy_businesses_mode == 2`
# blocks) - the existing (0,0)-baseline .mat files from the seed-74110
# and seed-82937 sweeps are still valid, unaffected comparison points, so
# there's no need to rerun them.
#
# Both seeds used previously (74110, 82937) - same Tiberias config as
# every other sweep driver this session (shock_step=25, steps=150, land-
# use calibration, staged-sheltering defaults set explicitly).
#
# One matlab process at a time (established crash-avoidance discipline
# this session) -- sequential, not parallel. Check for other running
# matlab processes before launching.
set -e
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_business_subsidy_retest_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,biz_mode,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

SEEDS=(74110 82937)
BIZ_MODES=(1 2)

for SEED in "${SEEDS[@]}"; do
  for BM in "${BIZ_MODES[@]}"; do
    TS=$(date +%Y%m%d_%H%M%S)
    LOGFILE="logs/tiberias_biz_retest_seed${SEED}_R0_B${BM}_${TS}.output"
    echo "=== seed=$SEED R=0 B=$BM -> $LOGFILE ==="
    BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
    matlab -batch "city='Tiberias'; jobs_per_meter_multiplier=3; potential_jobs_per_meter_multiplier=2; lu_change_rank_lower=45; lu_change_rank_upper=85; shock_step=25; steps=150; n_sims=1; outside_patience_duration=4; tempdev_patience_duration=8; rng_seed=${SEED}; subsidy_residents_mode=0; subsidy_businesses_mode=${BM}; run('run_model_earthquake_shelteroverflow.m')" > "$LOGFILE" 2>&1
    EXIT_CODE=$?
    echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
    AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
    NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
    echo "$SEED,0,$BM,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
    echo "=== finished seed=$SEED R=0 B=$BM exit=$EXIT_CODE file=$NEWFILE ==="
    # wait for MATLAB to fully clear before the next run too, in case
    # another session's process starts a gap-fill in the meantime
    while true; do
      COUNT=$(powershell -NoProfile -Command "(Get-Process matlab -ErrorAction SilentlyContinue | Measure-Object).Count" | tr -d '\r')
      if [ "$COUNT" -eq 0 ] 2>/dev/null; then break; fi
      sleep 15
    done
  done
done

echo "SWEEP_COMPLETE -> $MANIFEST"
