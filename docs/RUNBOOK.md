# Trainer Runbook

**Format:** trainer-led demo. Team watches, discusses, asks questions.

**Environment:** Snowflake training account, Snowsight Workspace connected to git.

**dbt version:** 1.11 on dbt Projects on Snowflake.

---

## Before the session — do all of this in advance

Do not do any of this live. Wiring an API integration in front of the team
teaches nothing they need and spends credibility you will want later.

| # | Step | Notes |
|---|---|---|
| 1 | Push this project to a GitHub repo | Must have at least one commit — Snowflake cannot connect to an empty repo |
| 2 | Decide GitHub auth | PAT in a Snowflake secret is the safe default. OAuth2 needs GitHub org-admin approval in most corporate orgs — check this **now**, not on the morning |
| 3 | Edit `setup/00_admin_setup.sql` | Replace `<YOUR_GITHUB_ORG_OR_USER>`, `<YOUR_REPO_NAME>`, username and PAT |
| 4 | Run `setup/00_admin_setup.sql` as ACCOUNTADMIN | Creates roles, warehouses, database, git integration |
| 5 | Create the Workspace in Snowsight from the git repo | Projects → Workspaces → Create from git. Snowflake auto-detects `dbt_project.yml` and shows a dbt tab — all live commands run from there |
| 6 | *(Optional)* Create the dbt project object | Only needed if you plan to demonstrate scheduling. Connect → Deploy dbt project → `TASTY_BYTES_DBT_PROJECT` in `DBT_TRAINING_DB.DEV`. The live session runs entirely from the workspace dbt tab. Snowflake detects the dbt project and provisions it automatically. |
| 7 | **Do a full dry run** | All three days end to end. Roughly 40 minutes. Do not skip this |
| 8 | Reset with `99_teardown.sql` section 1 | Drops the database only, keeping roles and integration |
| 9 | Re-run `setup/00_admin_setup.sql` sections 3–5 | Recreates database, schemas, git repository |

**Rehearsal is not optional.** Every number in the evidence queries should be
one you have already seen on your own screen. The session depends on you
saying "watch this figure change" and being right.

---

## Session 1 — Why dbt (~60 min)

### Cold open (10 min) — do this before explaining anything
Put `snapshots/snap_customer.yml` on screen. Say only: *"This produces a Type 2
slowly changing dimension. New versions on change, correct validity windows,
exactly one current row, closed records when a customer is erased."*

Then ask the room to estimate how many lines the equivalent hand-written MERGE
would be. Let them answer. It is usually eighty and it is usually right.

Say nothing else for a moment. That comparison is the most persuasive thing
available to this audience and it costs thirty seconds.

Then the framing for the whole course:

> Nothing here replaces what you already know. The dimensional modelling is
> identical — same grain, same conformed dimensions, same Type 1 and Type 2
> decisions. What changes is who can own it, and what happens to it over the
> next five years.

### Vocabulary bridge (10 min)

Almost nothing in dbt is a new idea. Put the translation table from
`docs/CONCEPTS.md` on screen and walk it. Ten minutes here saves an hour of
people quietly translating in their heads.

### Setup tour (10 min)

 -  The Workspace, connected to git. This is a repository, not a folder.
 -  `dbt_project.yml` — note how little is in it. Convention over configuration.
 -  `profiles.yml` — **no credentials.** Point this out explicitly. For a team 
    used to managing a service account per ETL tool, it lands.
 -  The four roles. Explain the INGEST/TRANSFORM split: dbt's read-only 
    relationship to raw is enforced by the grant model, not by a code review.
    
### First build (20 min)

Run `setup/01_day1_initial_load.sql` as `DBT_TRAINING_INGEST`. Show the CSVs
being read directly from the git repository stage — the data and the code that
loads it are the same commit.

Then, in the Workspace:

```
    dbt seed
    dbt snapshot
    dbt build
```

Talk through the run output as it goes. Point out:
 -  models built in dependency order, without anyone writing a schedule
 -  tests running interleaved with models, not afterwards
 -  the DAG in Snowsight afterwards
 
 ### Show the generated SQL (10 min) — **do not skip this**
 
 Open Snowsight query history. Find the MERGE that `dbt snapshot` emitted.
 
 This is the single highest-value move for this audience. Two things happen at
 once: dbt stops being magic — it is a SQL generator, and the SQL is
 recognisably what they would have written — and their expertise is validated
 rather than displaced. A veteran who has read the generated merge with their
 own eyes becomes an advocate. One asked to trust a black box becomes a quiet
 blocker.
 
 **Close session 1 by running evidence query 01 and writing the numbers on a
 whiteboard.** They are the baseline for everything in session 2.
 
 ---
 
 ## Session 2 — The repeated run (~75 min)
 
 **This is the session that does the convincing. Protect it.**
 
 ### Day 2 (35 min)
 
 Run `setup/02_day2_ingestion.sql` as `DBT_TRAINING_INGEST` — but **read each
 change aloud before executing it.** The script is written to be narrated. The
 whole value is that the room sees the cause, then sees the effect thirty
 seconds later.
 
 Pause especially on the late-arriving order. Before running the build, ask the
 room how they would pick up new rows incrementally. Someone will say "anything
 newer than the newest one I have". Agree that it is the obvious answer, then
 show them order 1099.
 
 ```
    dbt snapshot
    dbt build
```

Evidence queries, in this order:

| Query | What to show |
|---|---|
| 02 | Customer 3 now has two versions. Windows abut, exactly one current |
| 04 | The late order landed on 2026-02-28. Run the counterfactual at the end |
| **03** | **The money shot.** Two revenue numbers, both correct |
| 07 | 2026-02-28's aggregate changed since yesterday, with no backfill |

Query 03 is the one to linger on. Ask the room which number is right before
telling them. The realisation that both are, and that only one is obtainable
without a snapshot, is the moment the course pays for itself.

### Day 3 (30 min)

Same pattern. Narrate, run, build, evidence.

```
    dbt snapshot
    dbt build
```

| Query | What to show |
|---|---|
| 05 | Row count flat, revenue up $31.50. Merge, not append |
| 06 | Customer 5 erased, history intact, orders still reconcile |
| 03 | Re-run — the tier question is sharper than the city one |

For query 05, **run it before the build as well as after.** The comparison is
the evidence; a single set of numbers proves nothing.

### Time Travel vs snapshots (10 min)

Somebody will ask why snapshots are needed when Snowflake keeps history
automatically. Have the answer ready:

 -  **Time Travel** is an operational safety net. Retention-limited, table-level, 
    answers "what did this table look like on Tuesday".
 -  **Snapshots** are modelled business history. Permanent, queryable, joinable, 
    answers "what was this customer's city when they placed that order".
    
Show them side by side — `select ... at(offset => -60*60*24)` against
`RAW.CUSTOMER` next to `dim_customer_history`. Both give history; only one
gives you a dimension you can join a fact to.

---

## Session 3 — Trust and consumption (~60 min)

### The failure drill (15 min)

Run `setup/04_day4_bad_data.sql`, then `dbt build`.

Read the **skipped** model list aloud. Those are the models that would have
contained wrong numbers. The lesson: `dbt build` refuses to construct a mart
on top of data it cannot trust, and leaves the previous good state in place.

"Stale but right beats fresh but wrong" is the line. It lands with anyone who
has shipped a bad dimension load on a Sunday night.

Then `dbt retry` after fixing.

### Tests, docs, lineage (15 min)

 -  The two SCD2 tests. Explain what overlapping windows do — silent revenue 
    duplication that nothing else catches. Suggest running these against their 
    existing hand-built Type 2 dimensions. It is frequently an uncomfortable 
    morning.
 -  `severity: warn` vs error — encoding "must never happen" vs "someone should 
    look at this".
 -  `store_failures` — the failing rows in a real table, not just a count.
 -  The DAG and column-level lineage in Snowsight.
 
### The semantic view (15 min)
 
```
    dbt run-operation create_semantic_view
```

Then evidence query 08, and Cortex Analyst in natural language.

The closing argument: the semantic view was trivial to write **because the star
schema is clean**. Over a flat wide mart, the RELATIONSHIPS clause has nothing
to point at. Their dimensional modelling expertise is not obsolete in the age
of AI tooling — it is the thing that makes the AI tooling work.

### The git loop (15 min) — the closer

Entirely inside Snowsight:

 1. Create a branch in the Workspace
 2. Change a model — ideally so a test fails
 3. `dbt build`, watch it fail and skip downstream
 4. Fix, commit, push
 5. Open the PR on GitHub, show the diff **of the business logic**
 6. Merge, pull back, re-run
 
For people whose previous experience of changing a dimension load involved a
change ticket and someone else's release window, this loop is the whole
argument for the ownership shift.

---

## Questions they will ask

Have these ready. Seasoned people ask precise questions, and "let me get back
to you" is expensive in front of a room.

**"Where's my surrogate key sequence?"**
Hash keys are deterministic: the same business key produces the same surrogate
key on every environment and every full rebuild. Sequences do not — rebuild the
dimension and every key changes. You lose compact integers and insert ordering;
you gain reproducibility. It is a genuine trade-off, and saying so earns
credibility. See `macros/generate_surrogate_key.sql`.

**"How do I do a full historical reload?"**
`dbt build --full-refresh`. Everything rebuilds from source — except snapshots,
which is exactly why they matter.

**"What about late-arriving dimensions?"**
`int_order_lines_customer_attributed` is the answer. Classic Kimball problem,
and worth knowing in advance so it lands as a designed response.

**"Who schedules it?"**A Snowflake task wrapping `EXECUTE DBT PROJECT`. Must use a user-managed
warehouse — serverless tasks cannot run dbt projects.

**"Can I use dbt_utils?"**
Yes, two ways. Vendor `dbt_packages/` into the repo after running `dbt deps`
locally, or attach an external access integration to the dbt project object.
This training account has git (an API integration) but no EAI, which is why
everything here is hand-rolled. See `packages.yml`. **Do not let "you can't use
packages on Snowflake" become team folklore.**

**"What happens when two people change the same model?"**
Git. Show them session 3's closing loop.**

"What timestamp goes into `dbt_valid_from`?"**
Depends on the strategy, and the difference matters. `timestamp` takes it from the
`updated_at` column. `check` uses the **snapshot run time** unless you also give it an
`updated_at` — which this project does, pointing at the source's load timestamp, so the
history lines up with the simulated batch dates rather than with the clock on the day
you run the demo. Without that, every order would fall inside version 1 and the
point-in-time comparison would be silently wrong. See `snapshots/snap_customer.yml`.

---

## Things to say out loud

 -  **On snapshots being irreplaceable.** Every other model rebuilds from source 
    with one command. Snapshots cannot. Drop that schema and the history is gone 
    permanently. In a training account that gets torn down at the end, the irony 
    is worth pointing out — it makes the lesson stick.
    
 -  **On never disparaging the old way.** These people built things that ran for 
    years under real constraints. The framing that works is that their modelling 
    expertise is the scarce asset and dbt is finally tooling that respects it. 
    That is tactically smart and it also happens to be true.
    
 -  **On seeds.** `RAW.CUSTOMER` is six rows and must never be a seed. Size is a 
    coincidence; ownership is the criterion. Is the git repo the system of 
    record?
    
---

## Command reference

```
    dbt seed                                                load the CSV reference tables
    dbt snapshot                                            capture SCD2 history — ALWAYS FIRST
    dbt build                                               models + tests, in dependency order
    dbt build --full-refresh                                rebuild everything except snapshots
    dbt build --select stg_order_lines+                     a model and everything downstream
    dbt build --select +fct_orders                          a model and everything upstream
    dbt test --select dim_customer_history                  just the SCD2 tests
    dbt retry                                               resume after a failure
    dbt source freshness                                    is the source data current?
    dbt run-operation create_semantic_view                  build the semantic layer
    dbt docs generate --static                              docs (no `docs serve` on DPoS)
    dbt ls --select +exposure:tasty_bytes_sales_review      impact analysis
```

**`dbt snapshot` always runs before `dbt build`.** Snapshot late and the change
is captured a run behind, and the point-in-time attribution for that day's
orders is wrong.
