#!/bin/bash
# Full-grid Tiberias subsidy sweep with the current (fixed/expanded)
# subsidy code: subsidy_residents_mode {0..6} x subsidy_businesses_mode
# {0,1,2}, 2 seeds (74110, 82937) - chat 2026-09-19, after (1) residents
# modes 3-6 were added and (2) ashkelonwork's fix restoring 2 jobs per
# eligible destroyed commercial building so businesses modes 1/2's
# destroyed-buildings half actually fires (see
# run_model_earthquake_shelteroverflow.m's shock block, and
# cal_bui_sa_subsidy_targeted.m).
#
# The (0,0) no-subsidy baseline is NOT rerun here for either seed -
# reused directly from the earlier seed-74110/seed-82937 sweeps
# (hotels EQ S 20260917_180445 1 pid15680.mat / hotels EQ S
# 20260918_164012 1 pid14688.mat). Safe to reuse: subsidy_residents_mode=0
# skips HH_subsidy_targeted's grant logic entirely, and
# subsidy_businesses_mode=0 skips both cal_bui_sa_subsidy_targeted's
# eligibility logic AND the new pre-shock-snapshot/restore block (both
# gated on businesses_mode==1||2) - nothing about the (0,0) combo's
# behavior has changed under any of the recent fixes.
#
# Same Tiberias config as every other sweep driver this session
# (shock_step=25, steps=150, land-use calibration, staged-sheltering
# defaults set explicitly).
#
# One matlab process at a time (established crash-avoidance discipline
# this session, and multiple other sessions are actively contending for
# the same machine right now) -- sequential, not parallel. Also re-checks
# for other processes between every run, not just at the start, so this
# doesn't race a gap-filling run from another session.
set -e
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_subsidy_sweep_full_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,biz_mode,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"
# Seed the manifest with the reused (0,0) baseline rows so
# analyze_subsidy_sweep.py has both seeds' baselines without rerunning them.
echo "74110,0,0,\"earthquakeF/hotels EQ S 20260917_180445 1 pid15680.mat\",0" >> "$MANIFEST"
echo "82937,0,0,\"earthquakeF/hotels EQ S 20260918_164012 1 pid14688.mat\",0" >> "$MANIFEST"

SEEDS=(74110 82937)
RESID_MODES=(0 1 2 3 4 5 6)
BIZ_MODES=(0 1 2)

wait_for_matlab_clear() {
  while true; do
    COUNT=$(powershell -NoProfile -Command "(Get-Process matlab -ErrorAction SilentlyContinue | Measure-Object).Count" | tr -d '\r')
    if [ "$COUNT" -eq 0 ] 2>/dev/null; then break; fi
    sleep 30
  done
}

for SEED in "${SEEDS[@]}"; do
  for RM in "${RESID_MODES[@]}"; do
    for BM in "${BIZ_MODES[@]}"; do
      if [ "$RM" -eq 0 ] && [ "$BM" -eq 0 ]; then
        continue # reused from earlier sweeps, see header comment
      fi
      wait_for_matlab_clear
      TS=$(date +%Y%m%d_%H%M%S)
      LOGFILE="logs/tiberias_sweep_full_seed${SEED}_R${RM}_B${BM}_${TS}.output"
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
done

echo "SWEEP_COMPLETE -> $MANIFEST"
