# Sheltering system — `run_model_earthquake_shelteroverflow.m`

Three sheltering tiers, tried in this order as displacement plays out over time. All three share the same underlying philosophy: a sheltered household's `HH_data` is **never repointed** away from its original (destroyed) home while sheltered, and every tier releases a household the same two ways — their original home building recovers, or they secure a new asset through the normal housing search.

| Tier | What it is | Opens | Tracked in |
|---|---|---|---|
| 1. Immediate | Real buildings: public/school + hotels | At shock | `Shelters`, `Shelter_Assign` |
| 2. Out-of-city overflow | Not a physical place — commuting in from outside | When tier 1 runs out of capacity | `Sheltered_Outside` |
| 3. Medium-term | Abstract spaces (tent city/containers) — **not buildings** | `temp_dev_delay` steps after shock | `Temp_Dev_Sites`, `Temp_Dev_Assign` |

---

## Tier 1 — Immediate shelter (public/school + hotels)

**Trigger:** once, at `i==shock_step`, for every household in `HH_destroyed`.

**Function:** [`assign_shelter.m`](assign_shelter.m)
```
[Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, unsheltered_agents] = ...
    assign_shelter(Build_Data, Individuals_data, HH_destroyed, Shelters, Shelter_Assign, ...
    Shelter_Building_Routines, Building_routine_id, i, agents_per_sqm, public_bldg_usable_fraction, ...
    restrict_public_shelters_to_schools, hotel_room_density, agents_per_room)
```
- Candidate pool: usage=5 (public) and/or usage=8 (school) buildings — `restrict_public_shelters_to_schools` toggles whether generic public buildings are included — concatenated with usage=7 (hotel) buildings. Public/school tried first, hotels second, by concatenation order only.
- Capacity:
  - Public/school: `agents_per_sqm * public_bldg_usable_fraction * Area * floors`
  - Hotel: `hotel_room_density * agents_per_room * Area * floors` (see [`identify_hotels_TVR.m`](identify_hotels_TVR.m) for how `hotel_room_density` is calibrated per city)
- Occupied buildings are marked `Build_Data(:,3)=99` (transient shelter marker); their real `original_usage` (5/7/8) is recorded in `Shelters` so it can be restored later. The building is stripped from every agent's routine (cached in `Shelter_Building_Routines` for restoration).
- Displaced agents beyond available capacity come back as `unsheltered_agents` → become tier 2 (see below).

**Release:** every step, via [`release_shelter.m`](release_shelter.m), called from the `if shock==1` recovery block:
```
[Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id] = ...
    release_shelter(Build_Data, Individuals_data, HH_data, Shelters, Shelter_Assign, ...
    Shelter_Building_Routines, Building_routine_id, Assets, BI, i)
```
Releases an agent once their household's original building is in `BI` (recovered this step) or their current asset is a real, in-use `Assets` row (found new housing). Once a shelter building empties out completely, `Build_Data(:,3)` reverts to its recorded `original_usage` and its routine is restored from `Shelter_Building_Routines`.

**Data structures:**
- `Shelters` — `[building_id, start_step, end_step, original_usage]`
- `Shelter_Assign` — `[agent_id, building_id]`
- `Shelter_Building_Routines` — `{building_id, cached_routine_rows}`

---

## Tier 2 — Out-of-city overflow

**Trigger:** at shock time, whenever `assign_shelter.m` returns non-empty `unsheltered_agents` (tier 1 exhausted). Handled inline in the shock block (not a separate function for entry).

For each newly-overflowing household:
- A stylized flat commute penalty is deducted from income: `penalty = outside_commute_penalty_pct * HH_data(hh_row,6)`, stored so the exact amount can be refunded on exit.
- Their non-work routine is suppressed (`Building_routine_id(a_idx, 4:end) = NaN`) — work location (col 3) is untouched, so job continuity holds by construction. Re-applied every step in case the routine engine reassigns local activities to them.
- Added to `Sheltered_Outside`.

**Release:** every step, via [`release_outside_shelter.m`](release_outside_shelter.m):
```
[HH_data, Sheltered_Outside] = release_outside_shelter(HH_data, Assets, BI, Sheltered_Outside)
```
Same two exit conditions as tier 1; refunds the exact penalty amount stored at entry. No duration cap — this pool has no capacity constraint to force a cutoff.

**Data structure:** `Sheltered_Outside` — `[HH_ID, start_step, income_penalty_amount]` (household-level, not per-agent).

---

## Tier 3 — Medium-term temp-dev sites

Per the team lead's spec: an abstract residential *space*, not individual buildings — needs a specific location, a residential capacity, exclusion from the housing market, and a defined lifespan. **No `Build_Data` row or distance-matrix entry is ever created** for these sites; they exist purely as bookkeeping.

### Opening (one-time, `i >= shock_step + temp_dev_delay`)

**Siting** — [`site_temp_dev_locations.m`](site_temp_dev_locations.m):
```
site_xy = site_temp_dev_locations(Build_Data, destroyed_B, n_temp_dev_sites, temp_dev_site_coords)
```
- If `temp_dev_site_coords` (user-supplied `[X,Y]` pairs) is non-empty, those are used directly.
- Otherwise, data-driven: ranks SAs by total destroyed floor area (any usage type - doesn't matter if residential or not) and anchors one site per top-`n_temp_dev_sites` SA at that SA's largest *currently-standing* building's location — purely as a real-world reference point, not a building being reused.

**Capacity:** combined across all sites = `temp_dev_capacity_frac * (size(Shelter_Assign,1) + count of agents whose HH is in Sheltered_Outside)`, split evenly across however many sites actually opened.

**Transfer:** the candidate pool is every household currently in tier 1 (`Shelter_Assign`) **or** tier 2 (`Sheltered_Outside`), combined and shuffled into random order (no priority between the two pools). Households are filled into sites greedily, in that random order, up to each site's capacity (not optimal bin-packing — a household is never split across sites, but capacity can go slightly under-used at the boundary).
- From tier 1: their old shelter building is freed (reverts to `original_usage` via the same `Shelters` bookkeeping, if now empty).
- From tier 2: the exact commute penalty is refunded, same as a normal tier-2 release.
- Anyone not transferred (capacity ran out) simply stays in whichever tier they were already in — no further cascade needed, since tier 2 is already the catch-all.

### Closing (one-time, `i >= shock_step + temp_dev_delay + temp_dev_duration`)

Everyone still in `Temp_Dev_Assign` is force-released into tier 2 (`Sheltered_Outside`) — same income-penalty and routine-suppression mechanics as a normal tier-2 entry. `Temp_Dev_Assign` is cleared and every open row in `Temp_Dev_Sites` gets its `end_step` stamped. Since no `Build_Data` row was ever created, there's nothing to revert or delete.

### Natural release (every step, before duration expires)

[`release_temp_dev.m`](release_temp_dev.m):
```
[Temp_Dev_Assign, released_agents] = release_temp_dev(Individuals_data, HH_data, Assets, BI, Temp_Dev_Assign)
```
Same two exit conditions as the other tiers (original home recovered, or new asset secured) — called from the same per-step recovery block as `release_shelter.m`/`release_outside_shelter.m`.

**Data structures:**
- `Temp_Dev_Sites` — `[site_id, X, Y, capacity, start_step, end_step]` (`end_step=0` while open)
- `Temp_Dev_Assign` — `[agent_id, site_id]`

**New parameters** (all in the policy block):
| Parameter | Default | Meaning |
|---|---|---|
| `temp_dev_delay` | 14 | steps after shock before sites open (~2 weeks daily) |
| `n_temp_dev_sites` | 3 | fixed site count |
| `temp_dev_capacity_frac` | 0.75 | combined capacity ÷ total sheltered population, placeholder |
| `temp_dev_site_coords` | `[]` | optional user-supplied `[X,Y]` siting, else data-driven |
| `temp_dev_duration` | 180 | steps a site stays open, placeholder (~6 months daily) |

---

## Per-step retry/exit mechanics (all three tiers)

Every step, before the housing search runs:
```
still_sheltered_hh   = households currently in Shelter_Assign      (tier 1)
still_temp_dev_hh    = households currently in Temp_Dev_Assign     (tier 3)
moving_HH = [normal movers; HH_destroyed; still_sheltered_hh; Sheltered_Outside(:,1); still_temp_dev_hh]
```
All sheltered households (any tier) are folded into the same `moving_HH` pool and retried through the normal `find_new_house_same_stat` → `find_new_house_yeshuv` cascade every step, exactly like migrants searching for a new home. If a household in any tier fails to find housing this step, it's exempted from `did_not_find_house` deletion (`exempt_sheltered`) and simply retries again next step. No household sheltered by any tier is ever deleted from the simulation.

---

## Known simplifications (flagged, not fixed)

- Tier-3 site-fill is greedy over a randomly-shuffled household order, not optimal bin-packing.
- Households pulled from tier 2 into tier 3 stop being re-suppressed going forward, but there's no cached "original routine" to restore immediately the way tier-1 buildings get — their non-work routine cols stay `NaN` until the normal `HH_change → new_number_of_routine → find_activity_location_new_A` path eventually regenerates them.
- `temp_dev_capacity_frac` and `temp_dev_duration` are uncalibrated placeholders, same status as `outside_commute_penalty_pct`, `agents_per_room`, `public_bldg_usable_fraction`.
