# Team Lead Feedback — Status & Outstanding Items

All work below is in `run_model_earthquake_shelteroverflow.m` and its called
functions (the current main run script) unless noted.

---

## 1. Immediate sheltering (public buildings + hotels) — **DONE**

**Methodology:** [`assign_shelter.m`](assign_shelter.m) builds a candidate
pool of usage=5 (public) and/or usage=8 (school) buildings —
`restrict_public_shelters_to_schools` toggles whether generic public
buildings are included — concatenated with usage=7 (hotel) buildings.
Public/school tried first, hotels second. Capacity: public/school =
`agents_per_sqm * public_bldg_usable_fraction * Area * floors`; hotels =
`hotel_room_density * agents_per_room * Area * floors`. `hotel_room_density`
for Tiberias was calibrated from real CBS hotel-room-count data cross-
referenced against raw USG_CODE land-use codes ([`identify_hotels_TVR.m`](identify_hotels_TVR.m));
Ashkelon has no hotels tagged yet (`hotel_room_density=0`, harmless).
Occupied buildings get marked usage=99 and stripped from other agents'
routines; original usage is recorded in `Shelters` for reversion.
[`release_shelter.m`](release_shelter.m) releases an agent once their
original home recovers or they secure a new asset — checked every step.
Sheltered households are folded into the normal `moving_HH` retry pool
every step (never deleted). Full detail: [`sheltering_logic.md`](sheltering_logic.md).

---

## 2. Medium-term sheltering (new developments) — **DONE**

**Methodology:** A fixed count of abstract residential spaces
(`n_temp_dev_sites=3`) — explicitly **not** individual buildings, no
`Build_Data` row or distance-matrix entry is ever created for them.
Tracked entirely in `Temp_Dev_Sites` `[site_id, X, Y, capacity, start_step,
end_step]` and `Temp_Dev_Assign` `[agent_id, site_id]`
([`site_temp_dev_locations.m`](site_temp_dev_locations.m), [`release_temp_dev.m`](release_temp_dev.m)).

- **Location:** either user-supplied `[X,Y]` coordinates
  (`temp_dev_site_coords`), or a data-driven proxy — ranks SAs by total
  destroyed floor area (any usage type) and anchors each site at the
  largest currently-standing building's location in the top-damaged SAs.
- **Residential capacity:** combined capacity across all sites =
  `temp_dev_capacity_frac` (0.75) × total currently-sheltered population
  (immediate tier + out-of-city overflow), split evenly. Households from
  both pools are combined and shuffled into random order before greedy
  fill.
- **Exclusion from the housing market:** automatic by construction — no
  `Assets` row exists for a temp-dev site, so the normal housing search
  can never place anyone there.
- **Defined existence period:** `temp_dev_delay=2` weeks after shock
  before sites open; `temp_dev_duration=26` weeks after opening, sites
  close and force-release remaining residents into the out-of-city
  overflow pool. Nothing is left behind on closure (no building existed).
- Natural exit (before duration expires): same two conditions as every
  other tier — original home recovered, or new asset secured.

Full detail: [`sheltering_logic.md`](sheltering_logic.md).

---

## 3. Reconstruction rate updates — **DONE**

**Methodology:** The old mechanism gave every destroyed building the
*exact same* recovery time regardless of size (building size canceled
out of the deterministic threshold formula), which structurally can't
represent a real recovery-rate statistic — it produces a step function
(0% recovered, then 100% all at once), not a curve. Replaced with an
independent weekly Bernoulli recovery draw per building. Calibrated from
real data you provided (31.35% of residential housing recovered within 1
year): `RECOVERY = 1-(1-0.3135)^(1/52) ≈ 0.0072/week`. Applied uniformly
to all building types by default (your call); the existing
`priority_recovery`/`recovery_factor` toggle still works for
differentiated-recovery scenario testing, clamped to a valid probability.
Smoke-tested: ~35.3% of a damaged building stock recovered after 60
weeks against a theoretical expectation of ~35.2%.

---

## 4. Temporal resolution — **PARTIALLY DONE**

**Done (mechanical unit conversions):** `RECOVERY` (superseded by #3
above), `subsidy_duration`, the `VISITS` rolling window, `lu_warmup`, the
SA/price update cadence (`mod(i,4)`), `find_job_1.m`'s job-search give-up
curve, `migration_19.m`'s `inOutRatio`, `read_sas_data.m`'s
`intraSAProb`/`intraYeshuvProb`, and `temp_dev_delay`/`temp_dev_duration`.
Full derivation table: [`day_to_week_step_rescaling_audit.md`](day_to_week_step_rescaling_audit.md).

**Tested empirically, accepted as-is:** the `alfa/beta/lamda/delta`
wage-adjustment block (`income_ratio`). Compared `average_wage`
trajectories under daily vs. weekly steps over the same 90-day span (4
replicates each, Ashkelon, no shock). Long-run wage level holds up
(~0.3–1.1% divergence after the first few weeks, comparable to
replicate-to-replicate noise); the **initial post-shock settling
transient is ~7x slower in calendar time** under weekly steps, since
`income_ratio` only applies once per step regardless of how much real
time that step represents. You said this is okay — flagging here in case
that changes for a specific study that cares about the first few weeks.

**Explicitly deferred (your call):** `lu_update_every` — the land-use
update cadence — stays at 1 (every step) rather than being converted.

**Not yet addressed at all — new gaps surfaced by your question, not
previously audited:**
- **Land-use change procedure beyond cadence:** the *thresholds* that
  trigger land-use churn (visit-rank diff `>20`/`<-20` for job
  gain/loss, the `20<V<40` band for commercial conversion) were tuned
  against daily-accumulated visit/salary swings. Now that the rolling
  window spans weeks instead of days, week-to-week rank shifts could be
  larger than day-to-day ones were, which may make these fixed
  thresholds trigger land-use churn at a different real-world rate than
  originally intended. I have not examined or tested this.
- **Job search volume:** the give-up *curve* (`find_job_1.m`) is
  rescaled, but whether the *number* of job-seekers matched per step, or
  any implicit assumption about market liquidity per step, should also
  scale for weekly granularity has not been examined.
- **Housing search volume:** `who_is_moving.m`'s per-step probability of
  attempting a move is correctly rescaled, but the search mechanics
  themselves (`find_new_house_same_stat.m`, `find_new_house_yeshuv.m`,
  `find_new_house_sa_score.m`) — how large a pool of candidate
  assets/SAs a household evaluates in one step — have not been reviewed
  for whether that pool should be different (e.g. larger) now that one
  step represents a week's worth of market activity instead of a day's.

This last set is genuinely open — I'd want to actually read through
those search/matching functions with you before proposing a fix, since
it's not obvious there's a single constant to rescale the way the other
items were.

---

## 5. Design choices — shelter logic updates — **NOT STARTED**

Three distinct asks here, none implemented yet:

- **Housing search based on previous asset:** currently, a sheltered
  household retries the exact same `find_new_house_same_stat` →
  `find_new_house_yeshuv` cascade as any other mover/migrant, with no
  reference at all to the asset they lost (price tier, size, SA). Needs
  a design decision on what "based on previous asset" should concretely
  mean before I build it (e.g. an affordability/preference anchor tied
  to their old asset instead of just current income).

- **Local-shelter routine recomputation (shelter as "home"):**
  currently, a sheltered household's `HH_data` is deliberately never
  repointed away from their original destroyed home (by design, so
  release conditions work correctly) — but nothing recomputes their
  *routine* (non-work activity locations) to anchor on the shelter they're
  actually living in. Their local-activity routine is still computed
  relative to their old, destroyed home's location. This was flagged as
  a known gap earlier in this project and hasn't been built.

- **Out-of-city commuting agents' routines:** currently handled with a
  blunt placeholder — all non-work routine columns get hard NaN'd out
  (zero local activities) plus a separate flat income haircut
  (`outside_commute_penalty_pct`), unrelated to each other. What you're
  describing is more specific: routines should *start at the workplace*,
  and the commute penalty should factor into the *computed number of
  activities* (presumably via `number_of_routine.m`/
  `new_number_of_routine.m`), rather than just zeroing everything out.
  Not implemented as described.

This item (5) is the largest remaining body of work and touches the
routine-generation pipeline (`new_number_of_routine.m`,
`find_activity_location_new_A.m`, `number_of_routine.m`) more deeply than
anything done so far — worth a dedicated design discussion before
implementation, same as we did for medium-term sheltering.
