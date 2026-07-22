# Shock-Policy Integration — Handoff Summary

**Purpose:** context for a new chat session in a new working directory, continuing work on subsidy/sheltering policy modules for the Ashkelon ABM (see project CLAUDE.md for the base model). Carry this file, plus the four code files listed at the bottom, into the new directory.

---

## 1. What's already implemented (working, not yet run/verified in MATLAB)

A fork of the main dev script plus three new/replacement functions were built to add a housing subsidy and a corrected sheltering mechanism, fully toggle-able so baseline/no-shock and sensitivity-sweep work is unaffected. **The original `nextchangesfortracker.m` was NOT modified** — everything lives in a parallel fork.

### Files
- `nextchangesfortracker_shockpolicies.m` — fork of `nextchangesfortracker.m`, wires everything below together
- `HH_subsidy_pct.m` — replaces `HH_subsidy.m`
- `assign_shelter_sa.m` — replaces `assign_shelter.m`
- `release_shelter_capped.m` — replaces `release_shelter.m`

### Subsidy — confirmed design
- **% of household income**, frozen at the value on the step the subsidy is granted (shock/displacement step) — not recomputed later.
- **Elderly households get a higher percent**: `granted = subsidy_pct * (1 + w_subsidy_eld * isElderly) * income_at_grant`.
- Added to **HH income only** (`HH_data` col 6) — explicitly **not** added to individual wages (`Individuals_data`), so it stays out of labor-market/business-submodel dynamics (average wage, building salary rankings, land-use conversion triggers).
- No household-size term. No disabled-household flag (dropped — proposal originally included disability, this implementation is elderly-only by explicit decision).
- Tracker (`HH_subsidy_tracker`) stores the **exact granted amount** per household so removal at expiry subtracts precisely that — recomputing from current income at removal time would be wrong since income may have drifted (wage dynamics) or already include the subsidy.
- Current placeholder values (not yet sensitivity-tested): `subsidy_pct=0.15`, `w_subsidy_eld=0.5`, `subsidy_duration=60` (unchanged from original).

### Sheltering — confirmed design
- **Siting rule**: for each SA, the designated shelter is the **public building nearest that SA's largest commercial building** (largest by floorspace, `Build_Data` col 25).
- **Fallbacks**: SA has no public building, or no commercial building to anchor to → borrow the **nearest already-designated shelter from another SA** (implemented as an ascending-distance sort over all designated shelters, which naturally prefers within-400m options without needing an explicit two-tier check).
- **Overflow**: if the designated shelter is full, use the next-nearest public building to the *same* commercial anchor; if nothing has room for the whole household, place them in whichever candidate has the most free capacity — **households are never split across shelters** (the original `assign_shelter.m` assigned per-agent and could split families; this fork assigns whole households).
- `SA_Shelter_Rank` — a ranked candidate list per SA — is built **once**, on the first call, and reused for the rest of the run (siting doesn't change mid-simulation).
- **Households search from their original SA/building**, not the shelter's location — confirmed by user (the shelter is where they're staying, not where they search from; `HH_data` is left pointing at the destroyed home while sheltered, which is also what makes exit 2 below "free").
- **Service-related metrics** (`SAServiceAvg`/`BldServiceAvg`, elderly and non-elderly) for currently-sheltered households are computed from the **shelter's** SA/building, not the original destroyed home — confirmed by user, implemented as an override in the main script's per-step metrics block.
- **Max shelter duration**: a hard cap (`max_shelter_duration`, currently placeholder `120` steps, value not yet decided) forces release after that many steps regardless of housing status. Households released this way get **exactly one more** housing-search attempt that step and are **not** exempt from deletion if it fails — a genuine "relocate or leave" once the cap is hit, distinct from the indefinite retry households get before the cap.

### The corrected shelter flow (this is the core logic fix — must be preserved)

```
shock → assigned to shelter (HH_data still points to destroyed home)
  each subsequent step:
    → retries the housing search
        ├─ finds a house  → moves there, released from shelter   (exit 1)
        └─ fails          → stays in shelter, tries again next step
    → meanwhile, if their original building recovers
        → released from shelter, back home                        (exit 2)
```

**Why this was necessary:** in the original code, a displaced household got exactly **one** housing-search attempt, in the same step as the shock. If it failed, `did_not_find_house` deleted the household entirely (all members, freed job, freed asset). This meant nobody could ever actually be *living* in a shelter beyond the shock step — the shelter module's "release when home recovers" condition in `release_shelter.m` was dead code, since no sheltered household could still exist by the time recovery happened later. The fix: sheltered households are **exempt from deletion**, get re-added to the moving pool every subsequent step until resolved, and are released via exit 1 (found housing) or exit 2 (home recovered — free because `HH_data` never stopped pointing at it). The max-duration cap (above) was added on top of this as a hard backstop so households can't stay sheltered indefinitely.

---

## 2. New policy directions — discussed conceptually, NOT YET IMPLEMENTED

Framing from the user: the goal is **conceptual accuracy, not technical accuracy** — the point is to see how macroeconomic/model metrics shift under different policy configurations, not to build a literally faithful reconstruction-finance or informal-settlement model. This significantly lowers the bar for several of the harder items below.

1. **Hotels as a new land-use class**, usable as shelters — structurally parallel to public buildings (new usage code, added as a candidate pool in the same ranked-list mechanism).

2. **Temporary full removal from the city** when no shelter capacity exists, with return when housing is found or their original building recovers. Bigger lift than shelter tracking: this means *suspending*, not deleting, a household across labor/business/routine submodels while away, then cleanly reactivating on return — not just a housing-status change.

3. **Density-based tenure proxy, replacing a synthetic tenure field.** User explicitly does **not** want to add an owner/renter column to `HH_data` (deemed unnecessary complexity). Instead: classify **buildings** (not households) by density — units-per-building or floor count above/below a threshold — as "landlord-style" (high density) vs. "owner-occupied" (low density), and branch the **recovery-rate rule** by that classification. This works well because reconstruction in this model is already building-level (a landlord would rebuild the whole building, not one unit), so no new landlord agent or per-household field is needed — just a threshold check computed from existing `Assets`-per-building counts. Density threshold value not yet decided.

4. **Empty (usage=0) buildings used as shelters/temporary housing FIRST**, ahead of hotels/public buildings — they have no competing use, so they're the lowest-"opportunity-cost" tier in the model's terms. Should be added as the first-priority candidate pool in the shelter-assignment ranking.

5. **Building-spawning via row-copy**, for anything requiring "new" structures (transitional shelters, generated capacity). Mechanism: copy an existing building's `Build_Data` row (new ID, new usage class), and **reuse the source building's `Build_Distance_matrix_400`/`250` row** rather than recomputing distances. Reason: those matrices are built once at setup via brute-force pairwise distance (`building_within_D.m`); inserting a genuinely new coordinate mid-simulation would require updating every nearby *existing* building's neighbor list too, not just the new one — expensive and invasive. The accepted simplification: the spawned building is treated as co-located with its source rather than a truly distinct location.

6. **Transitional shelters** = items 4 + 5 combined: generate new shelter capacity near damage clusters at shock time via building-copy, then run it through the same ranked-candidate/capacity/release machinery already built for hotels/public buildings.

7. **Neighborhood-based priority** — meaning **not yet confirmed with the user**. Best current guess: when shelter/aid demand exceeds capacity citywide, priority ordering across SAs (e.g., by damage severity, or elderly population share — both already computable from `SA_Demographics`/`destroyed_B`) for who gets served first. Needs explicit confirmation before building — flag this as an open question in the new session.

8. **Sheltering outside the city, commuting in.** Reframed (per the conceptual-accuracy standard) as a **household status flag**, not literal external geography — avoids needing a second coordinate system / distance matrix that reaches outside city bounds. The household's asset is freed, they're excluded from the local housing search entirely, but a working member **keeps their existing job** and keeps generating work-only routine activity; local business/non-work routine participation is dropped. Commute penalty is stylized (e.g. a flat multiplier, or exclusion from the normal `D_work` preference term with a fixed penalty substituted) rather than a computed real distance. Reuses the "suspend, don't delete" bookkeeping pattern from item 2.

### Recommended build sequence (cheapest/most-leveraged first, as discussed)
1. Empty-buildings-as-shelters (near-zero new logic, extends `assign_shelter_sa`'s candidate pool)
2. Density-based recovery branching (no new data structures, just a threshold + two recovery-rate rules)
3. Transitional shelters via building-copy
4. Outside-city status-flag mechanism

---

## 3. Model constraints flagged as important context

- **No vacant land parcel concept** anywhere in the data — only buildings (which can be usage=0/"empty") and dwelling-unit assets within buildings. Blocks literal self-settlement or literal "new land" siting unless approximated via repurposing empty buildings or the building-copy mechanism (item 5 above).
- **No owner/renter distinction**, and no landlord decision-agent separate from the building-level recovery mechanic. User has decided **not** to add a tenure column — the density-based proxy (item 3 above) is the agreed path instead.
- `Build_Distance_matrix_400`/`250` are precomputed once at setup (`building_within_D.m`, brute-force pairwise) — this is the specific technical reason building-spawning is done via row-copy rather than fresh coordinate placement.
- Reconstruction/recovery is currently a single global `RECOVERY` rate (optionally boosted via `priority_recovery`/`recovery_factor` for residential), with no per-building decision-maker or milestone-gated logic — this is the mechanism that would need extending for grant-installment/owner-driven-style ideas, if pursued later.

## 4. Open parameters/decisions still pending
- `subsidy_pct`, `w_subsidy_eld`, `subsidy_duration` — placeholders, pending sensitivity testing (same treatment as `wservice`/`eld_movef`/`svc_filter`).
- `max_shelter_duration` — placeholder (120 steps), value not decided.
- Density threshold for the tenure-proxy split (units-per-building or floors cutoff) — not yet defined.
- "Neighborhood-based priority" — definition not yet confirmed with user.
- **None of the shock-policy code has been executed in MATLAB yet** — treat as a careful read-through implementation, not a verified one. Recommend a short test run (with `shock_step` lowered so the shock actually fires within `steps`) and inspecting `Shelter_HH_Track`/`HH_subsidy_tracker` over a few steps before trusting output.

---

## 5. Files to carry into the new working directory
- `nextchangesfortracker_shockpolicies.m`
- `HH_subsidy_pct.m`
- `assign_shelter_sa.m`
- `release_shelter_capped.m`
- `CLAUDE.md` (base model documentation — data structures, column meanings, architectural decisions)
- For reference/continuity on the separate baseline-sensitivity-sweep track (unrelated to shock policy, but same codebase): `nextchangesfortracker.m` (untouched original), `run_sweep_setting.m`, `run_sensitivity_sweep.m`, `run_svc_filter_interaction_sweep.m`
