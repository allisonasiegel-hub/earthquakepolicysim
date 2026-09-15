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
- Candidate pool: usage=7 (hotel) buildings concatenated with usage=5 (public) and/or usage=8 (school) buildings — `restrict_public_shelters_to_schools` toggles whether generic public buildings are included. Hotels tried first, public/school second, by concatenation order only. Default policy restricts the public/school tier to schools only (`restrict_public_shelters_to_schools=1`).
- Capacity:
  - Public/school: `agents_per_sqm * public_bldg_usable_fraction * Area * floors`
  - Hotel: `hotel_room_density * agents_per_room * Area * floors` (see [`identify_hotels_TVR.m`](identify_hotels_TVR.m) for how `hotel_room_density` is calibrated per city)
- Occupied buildings are marked `Build_Data(:,3)=99` (transient shelter marker); their real `original_usage` (5/7/8) is recorded in `Shelters` so it can be restored later. The building is stripped from every agent's routine (cached in `Shelter_Building_Routines` for restoration).
- Displaced agents beyond available capacity come back as `unsheltered_agents` → become tier 2 (see below).

**Release:** every step, via [`release_shelter.m`](release_shelter.m), called from the `if shock==1` recovery block:
```
[Build_Data, Shelters, Shelter_Assign, Shelter_Building_Routines, Building_routine_id, released_agents] = ...
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
[HH_data, Sheltered_Outside, released_hh] = release_outside_shelter(HH_data, Assets, BI, Sheltered_Outside)
```
Same two exit conditions as tier 1; refunds the exact penalty amount stored at entry.

**Patience (decreasing tolerance for being sheltered outside):** unlike tiers 1 and 3, this pool has no capacity constraint to force a cutoff — but a household does eventually give up. Once a household has been in `Sheltered_Outside` for `outside_patience_duration` steps (13 steps = 3 months equivalent at the model's weekly step resolution) **and** still fails to find housing that same step, it loses its exemption from `did_not_find_house` deletion in the main per-step retry block and is removed from the simulation entirely — same mechanism as a regular migrant who repeatedly can't find a house. Recovering the original home or securing a new asset always takes priority and releases the household from this pool first, so patience-based deletion only ever catches households that are still genuinely unhoused.

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

**Capacity:** combined across all sites = `temp_dev_capacity_frac * (size(Shelter_Assign,1) + count of agents whose HH is in Sheltered_Outside)`, split evenly across however many sites actually opened. Applies identically in both the "limited capacity" (e.g. 0.5) and "everyone gets sheltered" (1.0) scenarios — only the resulting `total_capacity` differs, not the fill order below.

**Transfer:** households are filled into sites greedily, up to each site's capacity (not optimal bin-packing — a household is never split across sites, but capacity can go slightly under-used at the boundary), in **strict priority order**, not one shuffled pool:
1. Public/school-sheltered households (tier 1, non-hotel)
2. Out-of-city overflow households (tier 2)
3. Hotel-sheltered households (tier 1) — last, since hotels are the most comfortable of the immediate options

Households are shuffled only *within* each tier, never across tiers.
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
| `outside_patience_duration` | 13 | steps a household tolerates being sheltered outside the city before it's removed from the sim if still unhoused (~3 months at weekly resolution) |

---

## Per-step retry/exit mechanics (all three tiers)

Every step, before the housing search runs:
```
still_sheltered_hh   = households currently in Shelter_Assign      (tier 1)
still_temp_dev_hh    = households currently in Temp_Dev_Assign     (tier 3)
moving_HH = [normal movers; HH_destroyed; still_sheltered_hh; Sheltered_Outside(:,1); still_temp_dev_hh]
```
All sheltered households (any tier) are folded into the same `moving_HH` pool and retried through the normal `find_new_house_same_stat` → `find_new_house_yeshuv` cascade every step, exactly like migrants searching for a new home. If a household in any tier fails to find housing this step, it's exempted from `did_not_find_house` deletion (`exempt_sheltered`) and simply retries again next step — **except** once its own patience runs out (see below), where it loses that exemption and is deleted like any other migrant who's given up. **Tier 1 (immediate shelter) has no patience cutoff of its own** — households there are never deleted from the simulation, unlike tiers 2 and 3.

### Decreasing patience → permanent departure

- **Tier 2 (out-of-city overflow) and `LU_Displaced`** (households evicted by a land-use conversion of their home, tracked the same way): governed by `outside_patience_duration` (default 4 weeks). Elapsed time is measured from whichever is later — the household's own entry, or the point at which search actually starts (see "stage 1/2" note below) — since nothing searches during stage 1 regardless of nominal entry time.
- **Tier 3 (temp-dev)**: governed by `tempdev_patience_duration` (default 8 weeks, using each household's own `Temp_Dev_Assign` entry step). This is a *per-household* mechanic, independent of the *site-level* `temp_dev_duration` force-close/transfer-to-overflow described above — both can be active at once, or `temp_dev_duration=Inf` can disable the site-level mechanic entirely so tier-3 exits happen only via patience (this is Ashkelon's/Tiberias's current validated shock-scenario configuration — see the main README's "Validated shock scenario configuration").
- Recovering the original home or securing a new asset always takes priority over any patience clock — departure only ever catches households still genuinely unresolved once time runs out.
- Tracked in `n_permanently_displaced_total`/`n_permanently_displaced_track` — the only channel through which shock-caused population loss doesn't eventually recover.

### Two-stage search design

**Stage 1** (from the shock until temp-dev opens, `i < shock_step + temp_dev_delay`): no displaced household searches for new housing at all — none of tiers 1/2/3 are folded into `moving_HH`. Reconstruction proceeds regardless. **Stage 2** begins once temp-dev opens; from then on every displaced household searches every step like any other mover.

---

## Known simplifications (flagged, not fixed)

- Tier-3 site-fill is greedy within each priority tier (randomly shuffled inside a tier), not optimal bin-packing.
- Households pulled from tier 2 into tier 3 stop being re-suppressed going forward, but there's no cached "original routine" to restore immediately the way tier-1 buildings get — their non-work routine cols stay `NaN` until the normal `HH_change → new_number_of_routine → find_activity_location_new_A` path eventually regenerates them.
- `temp_dev_capacity_frac`, `temp_dev_duration`, and `outside_patience_duration` are uncalibrated placeholders, same status as `outside_commute_penalty_pct`, `agents_per_room`, `public_bldg_usable_fraction`.
- Patience-based deletion (tier 2) only fires on a step where the household also fails the normal housing-search cascade — a household whose patience expires but who happens to find housing that exact same step is released normally instead, never deleted.
