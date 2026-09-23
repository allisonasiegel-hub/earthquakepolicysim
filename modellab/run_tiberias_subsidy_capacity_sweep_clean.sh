#!/bin/bash
# Full, clean rerun of the household-subsidy x shelter-capacity sweep
# (chat 2026-09-23) - ALL 18 combos rerun from scratch under whatever
# code is checked out AT LAUNCH TIME, no reuse of any earlier file.
#
# Why: the previous version of this sweep (2026-09-22 evening) got split
# across a mid-sweep upstream edit - HH_subsidy_targeted.m's "wage-
# yardstick fix" was reverted by another session at 22:08:07 while this
# sweep was still running, so seed 74110's mode-5 combos landed on the
# pre-revert code and its mode-6 combos (plus every combo for seeds
# 82937/30581) landed on the post-revert code. That's a real confound on
# top of the intended mode-5-vs-mode-6 comparison. Running all 18 combos
# back-to-back in one sitting, right before a commit, minimizes the
# chance of the same thing happening again mid-sweep.
#
# Grid: subsidy_residents_mode {0,5,6} x temp_dev_capacity_frac {0.5,1.0}
# x seed {74110,82937,30581} = 18 runs. subsidy_businesses_mode=0
# throughout (not part of this comparison). Same Tiberias config as every
# other sweep driver this session (shock_step=25, steps=150, land-use
# calibration, staged-sheltering defaults set explicitly).
#
# One matlab process at a time (established crash-avoidance discipline
# this session, and other sessions are actively contending for the same
# machine) -- sequential, not parallel, re-checked between every run. No
# `set -e`: a single combo failing logs and continues rather than killing
# the rest of the sweep.
set -u
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_subsidy_capacity_sweep_clean_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,capacity_frac,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

SEEDS=(74110 82937 30581)
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
      wait_for_matlab_clear
      TS=$(date +%Y%m%d_%H%M%S)
      CAPTAG=$(echo "$CAP" | tr '.' 'p')
      LOGFILE="logs/tiberias_sweep_clean_seed${SEED}_R${RM}_CAP${CAPTAG}_${TS}.output"
      echo "=== seed=$SEED R=$RM capacity_frac=$CAP -> $LOGFILE ==="
      BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
      matlab -batch "city='Tiberias'; jobs_per_meter_multiplier=3; potential_jobs_per_meter_multiplier=2; lu_change_rank_lower=45; lu_change_rank_upper=85; shock_step=25; steps=150; n_sims=1; outside_patience_duration=4; tempdev_patience_duration=8; rng_seed=${SEED}; subsidy_residents_mode=${RM}; subsidy_businesses_mode=0; temp_dev_capacity_frac=${CAP}; run('run_model_earthquake_shelteroverflow.m')" > "$LOGFILE" 2>&1
      EXIT_CODE=$?
      echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
      AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
      NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
      echo "$SEED,$RM,$CAP,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
      if [ "$EXIT_CODE" -ne 0 ]; then
        echo "!!! seed=$SEED R=$RM CAP=$CAP FAILED (exit=$EXIT_CODE) - see $LOGFILE - continuing"
      fi
      echo "=== finished seed=$SEED R=$RM capacity_frac=$CAP exit=$EXIT_CODE file=$NEWFILE ==="
    done
  done
done

echo "SWEEP_COMPLETE -> $MANIFEST"
