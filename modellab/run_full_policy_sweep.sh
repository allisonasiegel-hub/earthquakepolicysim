#!/bin/bash
# Master multi-city policy sweep (chat 2026-09-20): every city x every
# valid policy combination, matched-seed replicates.
#
# Cities: Ashkelon, Tiberias, Arad, Beer Sheva. Jerusalem excluded - its
# shock scenario is not yet validated (see README Quick Start), so a
# shock-driven policy sweep on it isn't meaningful yet.
#
# Per city, 10 scenario-types:
#   1. baseline_noshock      - no shock at all (organic-growth anchor)
#   2. baseline_shock_nopolicy - shock fires, all 3 policy categories at
#      their default/off state (subsidies off, temp_dev_capacity_frac at
#      its own script default, 0.5)
#   3-10. the full 2x2x2 factorial over the 3 policy categories, each
#      ALWAYS with exactly one option selected (never "off" within this
#      block - that's what scenario 2 is for):
#        sheltering:      temp_dev_capacity_frac in {0.5, 1.0}
#        household subs:  subsidy_residents_mode in {5, 6}
#        business subs:   subsidy_businesses_mode in {1, 2}
#
# Matched-seed design: the SAME rng_seed is reused across every
# scenario-type, for every city, within a given replicate index - so
# differences reflect the policy/city choice, not random noise (chat
# 2026-09-15 onward convention). REPS below controls replicate count -
# 4 cities x 10 scenario-types x REPS = total run count, e.g. REPS=2 is
# 80 runs. Adjust REPS at the top before launching; this is a genuinely
# large sweep, expect it to take a long time sequentially.
#
# Per-city shock timing (see README "Arad-specific parameters" and
# "Validated shock scenario configuration"):
#   - Ashkelon/Tiberias: shock_step=25 (validated - clears the land-use
#     transient with the smallest necessary margin), steps=125
#     (shock_step+100, per the 2026-09-19 steady-state analysis: shelter/
#     displacement dynamics fully resolve by shock_step+10, business/jobs
#     effects keep slowly drifting for the whole run with no fixed
#     equilibrium, so +100 is a deliberate compromise, not full
#     convergence).
#   - Arad: shock_step=100, steps=250 - matches its own dedicated driver
#     (run_arad_shock_step100_250.m) exactly, NOT the generic
#     shock_step+100 shortening. Independently traced 2026-09-20 from a
#     real no-shock baseline (SA_SERVICE): the one-time activation jump
#     (328->875) happens by week 9, but growth keeps creeping upward
#     gradually until essentially flat (939-940, +/-1 noise) around week
#     85-90 - NOT week 16-20 as this driver's own comment and an earlier
#     README pass both claimed (now corrected there too). shock_step=100
#     is still safely past either reading, so left unchanged; its
#     driver's long post-shock window (150 steps) is also kept as-is, not
#     second-guessed here.
#   - Beer Sheva: shock_step=40, steps=140 - independently traced
#     2026-09-20 from a real no-shock baseline (SA_SERVICE): activation
#     jump (1248->6420) by week 9, essentially flat (~7042, +/-1 noise)
#     by week 33-37. The originally-placeholder shock_step=25 here fired
#     BEFORE that settling point (confounding the shock with the tail of
#     the land-use transient - exactly what this margin is supposed to
#     prevent) and has been corrected to 40. Still no dedicated Beer
#     Sheva shock driver script exists, and this is based on a single
#     baseline replicate (n=1, unlike Ashkelon/Tiberias's multi-replicate
#     checks) - treat as a reasonable working value, not as rigorously
#     validated as Ashkelon/Tiberias.
#
# baseline_noshock always uses steps=150 (matches every city's own
# dedicated no-shock baseline driver) regardless of the city's shock
# steps value above - there's no shock to time against.
#
# tempdev_patience_duration=8 throughout (staged-sheltering default).
#
# One matlab process at a time (established crash-avoidance discipline
# this session) - sequential, not parallel. Coordinate with other
# sessions on this shared machine before launching - see this session's
# own chat history for why.
set -e
cd "/c/Users/allis/Documents/MATLAB/modellab"
mkdir -p logs

REPS=2
SEEDS=(90201 90202 90203 90204 90205)
SEEDS=("${SEEDS[@]:0:$REPS}")

MANIFEST="logs/full_policy_sweep_manifest_$(date +%Y%m%d_%H%M%S).csv"
echo "seed,city,scenario,shock_step,steps,resid_mode,biz_mode,temp_dev_capacity_frac,filename,exit_code" > "$MANIFEST"
echo "Manifest: $MANIFEST"

# city|shock_step|steps
CITY_CONFIGS=(
  "Ashkelon|25|125"
  "Tiberias|25|125"
  "Arad|100|250"
  "Beer Sheva|40|140"
)

run_one () {
  local SEED=$1 CITY=$2 SCEN=$3 SHOCK_STEP=$4 STEPS=$5 RM=$6 BM=$7 TDCF=$8
  local TS=$(date +%Y%m%d_%H%M%S)
  local SAFE_CITY=$(echo "$CITY" | tr ' ' '_')
  local LOGFILE="logs/fullsweep_${SAFE_CITY}_${SCEN}_seed${SEED}_${TS}.output"
  echo "=== seed=$SEED city=$CITY scenario=$SCEN shock_step=$SHOCK_STEP steps=$STEPS R=$RM B=$BM TDCF=$TDCF -> $LOGFILE ==="
  local BEFORE_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
  local MATLAB_CMD="city='${CITY}'; n_sims=1; tempdev_patience_duration=8; rng_seed=${SEED}; steps=${STEPS};"
  if [ "$SCEN" != "baseline_noshock" ]; then
    MATLAB_CMD="${MATLAB_CMD} shock_step=${SHOCK_STEP}; subsidy_residents_mode=${RM}; subsidy_businesses_mode=${BM}; temp_dev_capacity_frac=${TDCF};"
  fi
  MATLAB_CMD="${MATLAB_CMD} run('run_model_earthquake_shelteroverflow.m')"
  matlab -batch "$MATLAB_CMD" > "$LOGFILE" 2>&1
  local EXIT_CODE=$?
  echo "EXIT_CODE:$EXIT_CODE" >> "$LOGFILE"
  local AFTER_LIST=$(find earthquakeF -iname "*.mat" 2>/dev/null | sort)
  local NEWFILE=$(comm -13 <(echo "$BEFORE_LIST") <(echo "$AFTER_LIST") | head -1)
  echo "$SEED,$CITY,$SCEN,$SHOCK_STEP,$STEPS,$RM,$BM,$TDCF,\"$NEWFILE\",$EXIT_CODE" >> "$MANIFEST"
  echo "=== finished seed=$SEED city=$CITY scenario=$SCEN exit=$EXIT_CODE file=$NEWFILE ==="
}

for SEED in "${SEEDS[@]}"; do
  for CFG in "${CITY_CONFIGS[@]}"; do
    IFS='|' read -r CITY SHOCK_STEP STEPS <<< "$CFG"

    # 1. baseline, no shock at all
    run_one "$SEED" "$CITY" "baseline_noshock" "$SHOCK_STEP" 150 0 0 ""

    # 2. baseline shock, no policies (subsidies off, sheltering at its
    #    own script default of 0.5 - not an explicit policy choice)
    run_one "$SEED" "$CITY" "baseline_shock_nopolicy" "$SHOCK_STEP" "$STEPS" 0 0 0.5

    # 3-10. full 2x2x2 factorial - sheltering x household subs x business subs
    for TDCF in 0.5 1.0; do
      for RM in 5 6; do
        for BM in 1 2; do
          SCEN="R${RM}_B${BM}_SH$(echo $TDCF | tr -d '.')"
          run_one "$SEED" "$CITY" "$SCEN" "$SHOCK_STEP" "$STEPS" "$RM" "$BM" "$TDCF"
        done
      done
    done
  done
done

echo "SWEEP_COMPLETE -> $MANIFEST"
