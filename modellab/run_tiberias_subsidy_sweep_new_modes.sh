#!/bin/bash
# Subsidy policy sweep for Tiberias, NEW residents modes only: 5 and 6
# (decile-tiered % of housing cost, fixed 4-step / 8-step duration - see
# HH_subsidy_targeted.m's header, chat 2026-09-17), crossed with all 3
# subsidy_businesses_mode values {0,1,2} (businesses side got a "stable
# yardstick" wage-ranking calibration fix the same day, not a new mode -
# see cal_bui_sa_subsidy_targeted.m's header). 1 seed (74110, matches the
# earlier Ashkelon/Tiberias sweeps for cross-comparability). 150 steps,
# shock at week 25 (Tiberias's own validated shock point - see
# run_tiberias_shock_step25_150.m), staged-sheltering design
# (tempdev_patience_duration=8, outside_patience_duration=4 - both
# already the script's own defaults, set explicitly anyway per
# run_ashkelon_shock_step25_150.m's convention).
#
# Includes one (0,0) no-subsidy baseline combo (same seed) up front, so
# analyze_subsidy_sweep.py's "HH prevented"/"jobs saved" delta columns
# have something to compare modes 5/6 against.
#
# One matlab process at a time (established crash-avoidance discipline
# this session) -- sequential, not parallel. Check for other running
# matlab processes before launching.
set -e
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_subsidy_sweep_newmodes_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,biz_mode,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

SEED=74110
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
