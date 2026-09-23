#!/bin/bash
# Full-grid Tiberias subsidy sweep, re-run from scratch (chat 2026-09-22)
# after further upstream changes made the previous full-sweep attempt's
# data (and even the earlier "new modes"/business-retest runs) stale:
#   - subsidy_residents_mode: modes 1-4 removed 2026-09-18 (only 0/5/6
#     remain); mode 6's duration extended 8->12 steps AND the
#     "WAGE-YARDSTICK FIX" (2026-09-20) stopped feeding subsidized income
#     into Individuals_data col 14 (was leaking into the citywide wage
#     yardstick used by land-use job-growth ranking) - this changes mode
#     5/6's behavior even at subsidy_businesses_mode=0, so the old
#     seed-74110/82937 R5B0/R6B0 runs from 2026-09-17/18 are stale too.
#   - subsidy_businesses_mode: cal_bui_sa_subsidy_targeted.m now takes a
#     destroyed_commercial_B0 snapshot (2026-09-20) excluding buildings
#     that became commercial via ordinary land-use conversion AFTER the
#     shock rather than being commercial when it hit - changes modes 1/2's
#     destroyed-buildings eligibility, so the R0B1/R0B2 retest from
#     2026-09-19 is also stale.
#
# Net effect: only the (0,0) no-subsidy baseline is untouched by any of
# this (both residents_mode=0 and businesses_mode=0 skip all the changed
# code paths) - reused directly from the seed-74110/82937 sweeps
# (hotels EQ S 20260917_180445 1 pid15680.mat / hotels EQ S
# 20260918_164012 1 pid14688.mat). Every other combo is rerun fresh here:
# subsidy_residents_mode {0,5,6} x subsidy_businesses_mode {0,1,2} minus
# (0,0) = 8 combos x 2 seeds (74110, 82937) = 16 new runs.
#
# Same Tiberias config as every other sweep driver this session
# (shock_step=25, steps=150, land-use calibration, staged-sheltering
# defaults set explicitly).
#
# One matlab process at a time (established crash-avoidance discipline
# this session, and other sessions are actively contending for the same
# machine) -- sequential, not parallel, re-checked between every run
# (not just at the start) so this doesn't race a gap-filling run from
# another session. NOTE: unlike earlier sweep scripts, this one does NOT
# use `set -e` at the top level around the per-combo matlab call - a
# single combo erroring out (e.g. another invalid-mode-style bug) now
# logs and continues to the next combo instead of silently killing the
# rest of the sweep (see chat 2026-09-19: the first full-sweep attempt
# died completely, mid-run, the moment residents modes 1-4 turned out to
# already be removed).
set -u
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

MANIFEST="logs/tiberias_subsidy_sweep_full2_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,resid_mode,biz_mode,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"
echo "74110,0,0,\"earthquakeF/hotels EQ S 20260917_180445 1 pid15680.mat\",0" >> "$MANIFEST"
echo "82937,0,0,\"earthquakeF/hotels EQ S 20260918_164012 1 pid14688.mat\",0" >> "$MANIFEST"

SEEDS=(74110 82937)
RESID_MODES=(0 5 6)
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
        continue # reused baseline, see header comment
      fi
      wait_for_matlab_clear
      TS=$(date +%Y%m%d_%H%M%S)
      LOGFILE="logs/tiberias_sweep_full2_seed${SEED}_R${RM}_B${BM}_${TS}.output"
      echo "=== seed=$SEED R=$RM B=$BM -> $LOGFILE ==="
      BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
      matlab -batch "city='Tiberias'; jobs_per_meter_multiplier=3; potential_jobs_per_meter_multiplier=2; lu_change_rank_lower=45; lu_change_rank_upper=85; shock_step=25; steps=150; n_sims=1; outside_patience_duration=4; tempdev_patience_duration=8; rng_seed=${SEED}; subsidy_residents_mode=${RM}; subsidy_businesses_mode=${BM}; run('run_model_earthquake_shelteroverflow.m')" > "$LOGFILE" 2>&1
      EXIT_CODE=$?
      echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
      AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
      NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
      echo "$SEED,$RM,$BM,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
      if [ "$EXIT_CODE" -ne 0 ]; then
        echo "!!! seed=$SEED R=$RM B=$BM FAILED (exit=$EXIT_CODE) - see $LOGFILE - continuing with remaining combos"
      fi
      echo "=== finished seed=$SEED R=$RM B=$BM exit=$EXIT_CODE file=$NEWFILE ==="
    done
  done
done

echo "SWEEP_COMPLETE -> $MANIFEST"
