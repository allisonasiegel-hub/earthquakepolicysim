# Sheltering Policy Extensions — Handoff

**Purpose:** context for a new chat/working directory. Separate project, same base ABM as the elderly-focused thesis work, but **not elderly-specific** — none of the subsidy or elderly-metric material from that project applies here. Scope is five sheltering/reconstruction extension ideas, discussed conceptually only — no code written yet.

**Framing carried over from the discussion:** the goal is **conceptual accuracy, not technical accuracy** — these are meant to show how model metrics shift under different policy configurations, not to be literally faithful reconstruction-finance or informal-settlement mechanisms.

---

## Existing sheltering infrastructure to build on: the ORIGINAL mechanism, unmodified

Use `assign_shelter.m` and `release_shelter.m` **as originally written** for creating and populating shelters — **not** the SA/commercial-anchor siting rewrite (`assign_shelter_sa.m`/`release_shelter_capped.m`) built for the elderly thesis project. That rewrite (whole-household assignment, ranked candidate lists, commercial-anchor siting, overflow rules) is out of scope here; rely on the original functions instead.

Original behavior, for reference:
- `assign_shelter.m`: when households are displaced, every public building (usage=5) not already a shelter is a candidate. Displaced **agents** (not whole households) are assigned sequentially, filling each candidate building to capacity (`floor(agents_per_sqm * area * floors)`) before moving to the next. **A public building is never reused for a later wave of newly-displaced agents** — `available = setdiff(public_buildings(:,1), shelter_ids)` always excludes buildings already marked as shelters, so each new shock's displaced agents get fresh, previously-unused public buildings. Because assignment is per-agent, not per-household, a household's members can in principle end up split across two shelter buildings if one fills mid-household — a known quirk of the original mechanism, not something in scope to fix here.
- `release_shelter.m`: releases an agent if (a) their home building has recovered, or (b) their household has secured a new asset (checked via `HH_data`/`Assets`). A shelter building reverts to public (usage=5) once no agents remain assigned to it.

### What actually needs to be added on top (this is the real scope of this handoff)

**1. Retry/exit logic (main script).** The original code gives a displaced household exactly ONE housing-search attempt, in the same step as the shock — if it fails, the household is deleted entirely (`did_not_find_house`). This is why `release_shelter.m`'s "home recovered" condition can never actually fire in practice: nobody survives, unmoved, long enough for it to matter. Fix to add:
  ```
  shock → assigned to shelter (HH_data still points to destroyed home)
    each subsequent step:
      → retries the housing search
          ├─ finds a house  → moves there, released from shelter   (exit 1)
          └─ fails          → stays in shelter, tries again next step
      → meanwhile, if their original building recovers
          → released from shelter, back home                        (exit 2)
  ```
  Households with any member currently present in `Shelter_Assign` should be exempted from deletion when a search attempt fails, and re-added to the moving pool every subsequent step until one of the two exits resolves them. (Release itself naturally resolves at household granularity even though `Shelter_Assign` is agent-level, since the release condition reads from the shared `HH_data` row — all of a household's sheltered agents satisfy it at the same time.)

**2. Max shelter duration.** A hard cap forcing release after N steps regardless of housing status. Key implementation shortcut: because the original `assign_shelter.m` **never reuses/tops up an already-designated shelter building**, every agent ever assigned to a given shelter building entered on the exact same step. That means the building's own start step — already stored in `Shelters(:,2)` — is an *exact* proxy for each occupant's shelter-entry time, not an approximation. So the duration cap can be added as a simple check inside `release_shelter.m` (`(current_step - Shelters(:,2)) >= max_shelter_duration` → force-release everyone still in that building), with **no new per-household or per-agent tracking structure required**. Households forced out this way get one final housing-search attempt and are not exempt from deletion if that attempt fails — a genuine "relocate or leave" once the cap is hit.

---

## The five extensions to build (in this project)

### 1. Density-as-tenure-proxy
Classify **buildings**, not households, by density (units-per-building via `Assets` count, or floor count, above/below a threshold) as "landlord-style" (high density) vs. "owner-occupied" (low density), and branch the **recovery-rate rule** by that classification. This avoids adding a synthetic tenure column to `HH_data` or inventing a landlord decision-agent — reconstruction in this model is already building-level (a landlord would rebuild the whole building, not one unit), so the classification only needs a threshold check on data that already exists. Density threshold value not yet decided.

### 2. Empty (usage=0) buildings as shelter/temp housing — ranked first
Empty buildings have no competing use already assigned to them, so they're the lowest-"opportunity-cost" shelter tier in the model's terms. Add them as an **additional, first-priority candidate pool** in `assign_shelter.m`'s building-selection step (tried before public buildings, and before hotels once that land-use class exists), keeping the rest of the original sequential-fill mechanism as-is.

### 3. Spawning buildings via row-copy
To create "new" structures (for transitional shelters or generated capacity), copy an existing building's `Build_Data` row (new ID, new usage class) rather than synthesizing a genuinely new coordinate. Reason: `Build_Distance_matrix_400`/`250` are precomputed once at setup via brute-force pairwise distance (`building_within_D.m`); inserting a real new coordinate mid-simulation would require updating every nearby *existing* building's neighbor list too, not just the new one — expensive and invasive. The accepted simplification: **reuse the source building's distance-matrix row** for the new one, meaning the spawned building is treated as co-located with its source rather than a truly distinct location.

### 4. Transitional shelters
Combines items 2 and 3: generate new shelter capacity near damage clusters at shock time via the building-copy mechanism (item 3), then feed those synthetic buildings into `assign_shelter.m`'s existing candidate-pool/capacity-fill logic as a further building type it can select from.

### 5. Sheltering outside the city, commuting in
Reframed (per the conceptual-accuracy standard) as a **household status flag**, not literal external geography — avoids needing a second coordinate system / a distance matrix reaching outside city bounds. Mechanics:
- Household's asset is freed; excluded from the local housing search entirely.
- A working member **keeps their existing job** and keeps generating work-only routine activity.
- Local business/non-work routine participation is dropped while in this state.
- Commute penalty is stylized (e.g. a flat multiplier, or exclusion from the normal `D_work` preference term with a fixed penalty substituted) rather than a computed real distance.
- Mechanically this is a "suspend, don't delete" pattern — similar in spirit to the shelter retry/release flow above, but the household keeps partial (work-only) participation instead of being fully paused.

---

## Model constraints relevant to these five items
- **No vacant land parcel concept** — only buildings (some usage=0/"empty") and dwelling-unit assets within buildings. This is why items 2 and 3 both work by repurposing/copying existing buildings rather than creating genuine new land or structures.
- **No owner/renter distinction, no landlord agent** — item 1's density proxy is the agreed workaround; do not add a tenure column.
- **Distance matrices are precomputed once at setup** — the specific technical reason item 3 uses row-copy instead of fresh coordinates.

## Open / not yet decided
- Density threshold for item 1 (units-per-building or floor cutoff).
- None of the five extensions, nor the retry/exit/duration-cap additions to the original shelter mechanism, have any code yet — this is feasibility/design only.

## Files to bring into the new project
- `assign_shelter.m`, `release_shelter.m` — **original, unmodified** versions (not the elderly-project's `assign_shelter_sa.m`/`release_shelter_capped.m` rewrite)
- The main simulation script (`nextchangesfortracker.m` or equivalent) — retry/exit logic and the max-duration check need to be added to its shock-handling block and its `did_not_find_house` call, per the description above
- `CLAUDE.md` (base model data structures — `Build_Data`, `HH_data`, `Assets` columns, etc.)
