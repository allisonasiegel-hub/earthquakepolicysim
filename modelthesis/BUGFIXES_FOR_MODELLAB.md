# Bug fixes found in modelthesis (Tiberias) — handoff for modellab (Ashkelon)

modelthesis (Tiberias) and modellab (Ashkelon) fork the same underlying
ABM architecture. Everything below was found and fixed in
`modelthesis/run_model_earthquake.m` (and its helper functions) this
session. Each entry says whether it's a **universal logic bug** (worth
checking for and porting into modellab's equivalent script, most likely
`nextchangesfortracker.m` or whatever modellab's active main script is)
or a **Tiberias-specific recalibration** (the underlying *pattern* is
worth checking for, but the fix itself used Tiberias-specific data that
doesn't transfer directly — modellab would need Ashkelon's own
equivalent).

None of this was verified against modellab's actual files — that check
needs to happen in the modellab chat. Function/variable names below may
differ there; match by *behavior*, not literal name.

---

## Universal logic bugs (worth checking for directly)

### 1. Land-use eviction routed through the wrong retry pathway
**Symptom:** households get recorded as still occupying an asset inside a
building that has already converted to commercial ("ghost occupancy"),
sometimes for weeks.

**Root cause:** when a building converts to commercial, households whose
housing search fails get put through the same `resSearchLen`
consecutive-failed-attempt retry counter used for *voluntary* moves. That
counter grants up to N days of grace before eviction — appropriate for
someone who's shopping around, wrong for someone whose home just
legally stopped being residential. There's nowhere left to retry
against; the conversion trigger fires once.

**Fix:** for land-use-triggered displacement specifically, skip the
retry counter and evict immediately (call the eviction/removal path,
e.g. `did_not_find_house`, directly) if the household's one relocation
attempt fails. Other `resSearchLen` retry sites (voluntary moves) are
untouched.

**Check in modellab:** find where land-use conversion (usage → 3)
triggers a housing search for displaced households, and see whether it
shares a retry-count gate with voluntary-move logic.

### 2. Housing search not filtering out non-residential buildings
**Symptom:** households can be assigned to assets inside buildings that
are no longer zoned residential.

**Root cause:** candidate-asset queries (`possible_assets` and similar)
filtered by SA, occupancy, and affordability, but not by whether the
asset's building is still usage 1 or 2 (residential).

**Fix:** added a shared helper (`filter_residential_assets.m` in
modelthesis) that restricts any candidate-assets pool to
`Build_Data(:,3)==1 | Build_Data(:,3)==2` buildings, applied everywhere
candidate assets get pulled (in-SA search, out-of-SA search, migration
of new arrivals).

**Check in modellab:** grep for wherever `possible_assets`-style
candidate pools get built from `Assets`, and check whether they're
cross-referenced against current building usage.

### 3. Job-loss mechanism firing on the wrong population
**Symptom:** when a building's commercial activity gets flagged for job
loss, potentially *every* current employee of that building loses their
job — even on multi-job buildings that should only lose one slot.

**Root cause:** the "who lost their job" step matched individuals by
**building ID**, not by the *specific workplace slot* that actually
closed. Multi-job buildings only close one slot per flagged day (single-
job buildings close entirely) — matching by building ID unemploys
everyone at that building regardless.

**Fix:** track the specific closed workplace IDs for the day
(`closed_wp_ids_today`), and match individuals against that list via
their specific `work_place_id` column, not the building ID.

**Check in modellab:** find the job-loss/layoff block and see whether
individuals get matched by building ID or by their own workplace-ID
column.

### 4. Metric formula testing a column value that can never occur
**Symptom:** a "local vs. commutes-outside" share metric reads exactly
1.0 (or 0.0) permanently, regardless of actual dynamics — looks
suspiciously too clean.

**Root cause:** the metric checked `Individuals_data(:,12)==99`
("working status" column) to detect "works outside the city." But
whatever function actually assigns jobs (in modelthesis, `find_job_1.m`)
sets that column to a fixed "employed" value (`2`) for *both* local and
outside-city hires — the outside-city flag actually lives in a
*different* column (`building_work_place`, col 15 in modelthesis).
Column 12 structurally never holds 99, so any metric comparing against
it is either trivially 1.0 or trivially 0.0.

**Fix:** read the local/outside distinction off the correct column.

**Check in modellab:** any metric computing a local-vs-outside or
similar share — verify the column it's testing against can actually
take the value it's checking for. If a ratio is suspiciously exactly
1.0 or 0.0 across an entire run, this is the first thing to check.

### 5. Labor-pool "add people to working market" applied to the wrong set
**Symptom:** a persistent post-warmup unemployment spike/backlog that
takes many simulated days to work through, then never recurs at
meaningful scale.

**Root cause:** the code correctly computes a probability-scaled sample
size `S` (how many people *should* enter job search) and correctly draws
a random sample `P` of that size from the eligible pool `F` — then
applies the status change to the *entire pool* `F` instead of the sample
`P`. `S`/`P` end up as dead-end computed-but-unused values.

**Fix:** apply the status change to `P` (the sample), not `F` (the full
pool).

**Check in modellab:** find the block that pushes non-working
individuals into active job search when the local economy signals
demand (an `income_ratio`-style gate), and check whether the final
assignment line uses the *sampled* subset or the *full eligible* set.
This is a one-line diff (`Individuals_data(F,...)` vs
`Individuals_data(P,...)`) that's easy to miss on a read-through.

---

## Tiberias-specific recalibrations (check the *pattern*, not the fix)

These four all follow the same shape: a value or file path that's
correct for Ashkelon got hardcoded into what's now the Tiberias fork.
**If modellab is the actual Ashkelon codebase, these specific values are
probably already correct there** — but it's worth checking whether
modellab has its *own* version of the same failure pattern (a
dynamically-loaded value that regressed to a hardcoded stale one, or a
wrong-city file path).

### 6. Job-density parameter (`JobsPerM_comm`) hardcoded instead of loaded
Tiberias had Ashkelon's `JobsPerM_comm` value (`0.007790361`) hardcoded
into the land-use job-seeding logic in two places, instead of being
loaded dynamically from `model parameters.csv` the way the original
model does it. Fixed by restoring dynamic loading.
**Check in modellab:** confirm `JobsPerM_comm` (or modellab's equivalent
parameter) is still loaded from its parameters file at script start, not
hardcoded anywhere downstream.

### 7. Outside-commute probability hardcoded to the wrong city
Tiberias had `commute_outside=0.778038196`, literally commented "Ashkelon
commuting 99 probability," hardcoded into the labor-market module.
**Check in modellab:** if this constant is genuinely Ashkelon's own rate,
no action needed — just worth confirming it's still sourced from real
Ashkelon commuting data rather than a stale literal.

### 8. Wrong-city commuting data file
Tiberias's root-level `commuting.xlsx` actually contained a *different*
city's data (a different settlement ID than Tiberias's own). Same bug
class as the `sas_national.xlsx` mismatch found earlier in this project.
**Check in modellab:** confirm whichever `commuting.xlsx`/equivalent file
modellab loads actually contains Ashkelon's settlement ID, not a
leftover from whichever city's data was loaded last during development.

### 9. Migration rate using a dimensionless ratio as an annual rate
**Root cause (universal):** `migration_19.m` used a per-SA "inOutRatio"
value (a *dimensionless* in/out migration ratio, from
`sas_national.xlsx`, roughly 0.4–2.1 across SAs) directly as an annual
fraction of vacant housing to fill (`x = inOutRatio/365`) — producing
~21x too much population growth vs. real Tiberias census data.

**Fix (Tiberias-specific data, universal method):** replaced with real
per-SA annual growth rates derived from actual census data
(`TVR/growthrates1.xlsx` → `TVR/real_growth_rates.csv`), applied to each
SA's *current household count* (not vacant-asset count, which is now
only a cap on how many new households can actually find housing).

**Check in modellab:** this is the highest-value item to check even
though the specific fix doesn't transfer — verify whether Ashkelon's
`migration_19.m` (or equivalent) has the *same* inOutRatio-as-annual-rate
misuse. If so, the fix pattern is: find or derive real per-SA annual
population growth rates for Ashkelon (census data, if available) and use
those instead of the raw ratio column. Sanity-check by comparing modeled
annual population growth against real Ashkelon growth rates — if the
model is running ~10-20x hotter than reality, this is almost certainly
present.

---

## Performance (optional, no behavior change — validated bit-for-bit
## identical against the original loop-based versions on real data)

These are pure vectorizations, worth porting to modellab **only if**
modellab's equivalent script has similarly-structured loops **and**
runtime is actually a pain point there. Each one was validated by
running old and new logic side-by-side on live simulation data and
confirming exact match (day-by-day, for a 100-day test run) before
removing the old code path.

- **Land-use percentile ranking**: replaced a per-candidate-building
  loop that called `prctile` fresh for every candidate, then linearly
  scanned 100 bins by re-testing membership against the *entire* base
  salary array just to read its own last element — with a single batched
  matrix computation across all candidates at once.
- **Visit/salary ranking** (modelthesis: `MVB30`,
  `building_average_salary`): same pattern — a 100-iteration loop
  re-scanning a whole column to bucket every row into a percentile bin —
  replaced with a single vectorized rank-count (`sum(P(1:100) <= value)`
  per row, computed for all rows in one broadcast comparison).
- **Per-SA metrics block**: a loop over every SA re-scanning the *entire*
  Assets/Build_Data/Work_places/Individuals_data/HH_data arrays from
  scratch for every single metric (~20 SAs × ~25 metrics of redundant
  full-array filtering) — replaced with precomputed group indices +
  `accumarray`. The non-metric parts of that same loop (building-value
  mutation, price updates) were left as a loop since they're
  order-dependent, not a pure aggregation.

If porting any of these, the validation method that worked well: compute
both old and new versions side-by-side (gated behind a temporary
boolean flag defaulting to false), run a real simulation for enough days
to exercise the code path multiple times, assert exact match, then
delete the old path once confirmed.

---

## Concurrency (only relevant if modellab has a similar sweep wrapper)

If modellab has a wrapper function analogous to
`run_earthquake_setting.m` that calls the main script via `run()` and
saves output to a fixed filename, check whether that filename (and any
temp-file the wrapper uses to survive the script's own `clearvars`) is
unique per invocation. modelthesis's wrapper used a fixed path — running
two sweep configs concurrently (two `matlab -batch` processes, or a
`parfor`) silently cross-contaminated each other's output (confirmed:
one process's run got saved under the other's tag/parameters). Fixed by
suffixing both paths with the OS process ID
(`sprintf('pid%d', feature('getpid'))`), obtained once per invocation and
threaded through both the script's own save call and the wrapper's
copy/rename step.
