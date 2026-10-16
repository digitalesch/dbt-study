# dbt-study: setup, cheat sheet, misconception tracker

Hands-on dbt study project (DuckDB locally, Databricks concepts mapped on top), built as interview prep for a Data Engineer role (dbt, Python, Spark, Databricks).

Each day has a notes file with: concepts, what was built, my checkpoint answers, corrections, and an interview-ready summary.

| Day | Topic | Notes |
|---|---|---|
| 1 | Foundations: sources, staging, marts, `ref()`, docs | [day-01.md](day-01.md) |
| 2 | Incremental models and tests | [day-02.md](day-02.md) |
| 3 | Macros, packages, seeds, snapshots | [day-03.md](day-03.md) |
| 4 | Selectors, environments, slim CI, freshness, contracts, Databricks mapping | [day-04.md](day-04.md) |
| 5 | Interview rehearsal | _pending_ |

---

## Setup

```bash
git clone git@github.com:digitalesch/dbt-study.git && cd dbt-study
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install dbt-duckdb pandas      # or: pip install -r requirements.txt
```

`profiles.yml` is gitignored (never commit real credentials). For this local DuckDB project, create it in the project root:

```bash
cat > profiles.yml << 'EOF'
dbt_study:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: dbt_study.duckdb
      threads: 4
    prod:
      type: duckdb
      path: dbt_study.duckdb
      schema: prod
      threads: 4
    ci:
      type: duckdb
      path: dbt_study.duckdb
      schema: "{{ env_var('CI_SCHEMA', 'ci') }}"
      threads: 4
EOF

export DBT_PROFILES_DIR=.          # or pass --profiles-dir . to every command
dbt debug                          # expect: All checks passed!
dbt deps && dbt seed && dbt build
```

Recommended `.gitignore`:

```
.venv/
target/
dbt_packages/
logs/
*.duckdb
*.duckdb.wal
profiles.yml
.user.yml
prod-artifacts/
ci.duckdb
!ci/profiles.yml
```

Docs and lineage:

```bash
dbt docs generate && dbt docs serve     # http://localhost:8080
```

![DBT Docs](../dbt_docs_0001.png)

---

## "What happens when": the cheat sheet

Most of my misconceptions so far were variants of "which stage does what". Keep this page for the night before the interview.

| Command | Parses and checks refs | Compiles Jinja to SQL | Executes against compute | Builds objects | Runs tests |
|---|---|---|---|---|---|
| `dbt parse` | yes | no | no | no | no |
| `dbt compile` | yes | yes | no | no | no |
| `dbt run` | yes | yes | yes | models | no |
| `dbt test` | yes | yes | yes (test queries) | no | yes |
| `dbt build` | yes | yes | yes | seeds, snapshots, models | yes, interleaved in DAG order |
| `dbt ls` | yes | no | no | no | no |
| `dbt source freshness` | yes | no | yes (one query per source) | no | no |
| `dbt deps` | no | no | no | no | no (downloads packages) |

Where each kind of error is caught:

| Error type | Example | Caught at |
|---|---|---|
| Broken `ref()` / `source()` | renamed a model, forgot a caller | **Parse time**, nothing runs |
| SQL error inside a model | misspelled column | **Execution time**, upstream built, downstream skipped |
| Bad data | duplicate key, unexpected status | **Test time** (`build` stops downstream models) |
| Wrong shape (names, types) | dropped a column | **Contract**, at build time before the table is replaced |
| Stale data | pipeline stopped | **Source freshness** (separate command) |

`target/` folders:
- `target/compiled/`: your SQL with Jinja rendered.
- `target/run/`: what was actually sent to the database (compiled SQL plus the DDL wrapper).
- `target/manifest.json`: full project description, used for state comparison (slim CI).
- `target/run_results.json`: outcome of the last invocation (statuses, timings).

Where state lives:
- **Incremental state:** the target table itself (`select max(updated_at) from {{ this }}`).
- **Slim CI state:** the production `manifest.json`.
- **Snapshot history:** the snapshot table itself (the only copy, so protect it).

---

## Misconception tracker

Things I got wrong, so I can check they have stuck. Mark the last column when I can answer without notes.

| Day | I thought | Actually | Solid? |
|---|---|---|---|
| 1 | `dbt test` catches a broken `ref()` | Broken refs fail at **parse time**; tests check **data** | [ ] |
| 1 | Run-time DDL is just Jinja resolved | `target/run` adds the `create ... as` DDL wrapper; `compiled` is only Jinja resolved | [ ] |
| 2 | `dbt build` only compiles, `test` executes | `build` **executes** everything (seeds, snapshots, models, tests) in DAG order; only `compile` skips execution | [ ] |
| 2 | Incremental state lives in `run_results.json` | It is the **target table** (max watermark). Manifest is for slim CI | [ ] |
| 2 | `append` keeps history | `append` creates **duplicates**; history is what snapshots are for | [ ] |
| 2 | `is_incremental()` returns nothing on first run | Returns **False** (a boolean) | [ ] |
| 3 | `ref()` is for external data, `source()` for models | **Reversed.** `source()` = outside dbt, `ref()` = dbt builds it (models, seeds, snapshots) | [ ] |
| 3 | Snapshot vs incremental is about strategy mechanics | Incremental keeps **latest state** (efficiency); snapshot keeps **every version** (history) | [ ] |
| 4 | Comma in a selector is a union | Space = OR (union), **comma = AND (intersection)** | [ ] |
| 4 | `--defer` builds only what changed | `state:modified+` picks **what to build**; `--defer` decides **where unbuilt `ref()`s point** (prod) | [ ] |

---

## Interview one-liners

- **What is dbt?** A build and governance layer on top of the warehouse. It turns SELECTs into managed tables, handles dependencies, tests, and docs, and delegates all execution to the compute underneath. It does not move data or translate SQL dialects.
- **`source()` vs `ref()`?** `source()` declares external raw tables and is where lineage, freshness, and raw tests attach. `ref()` references objects dbt builds, creates the DAG, and resolves schemas per environment.
- **What happens on `dbt build`?** Parse, build the DAG, compile Jinja, then execute seeds, snapshots, models and tests in dependency order. A failed test skips downstream models.
- **Where is a broken reference caught?** At parse time, before any compute runs. SQL errors surface at execution.
- **Incremental model?** Filters the source with a watermark (`updated_at`) against the max in its own target table. `unique_key` lets merge or delete+insert replace changed rows. `--full-refresh` resets it when logic or data drifts.
- **Snapshot vs incremental?** Incremental is about processing efficiency and keeps current state. A snapshot is about history (SCD2) and keeps every version. Snapshot from the source, and protect the table.
- **Contract vs test?** Contract guards the shape at build time and leaves the existing table untouched on failure. Tests guard the content after the build.
- **Slim CI?** `dbt build --select state:modified+ --defer --state <prod manifest>` into a per-PR schema: pick changed models and descendants, and point unbuilt upstream refs at production.
- **Macros vs UDFs?** Macros generate SQL text at compile time. UDFs live in the database and run at query time.
- **Why does `dbt_utils` work across warehouses?** Adapter dispatch: package authors wrote each dialect (`databricks__`, `duckdb__`, ...) and dbt picks one by adapter.

---

## Repo layout

```
.
├── analyses/
├── ci/profiles.yml            # credential-free profile for GitHub Actions
├── docs/                      # screenshots
├── macros/                    # cents_to_currency
├── models/
│   ├── staging/               # views, stg_*, _sources.yml, _staging.yml
│   └── marts/                 # tables, dim_* / fct_*, _marts.yml, _exposures.yml
├── docs/notes/                # one file per study day, plus this cheat sheet
├── seeds/                     # raw_orders, raw_customers (fake raw layer), order_status_map
├── snapshots/                 # snap_customers (SCD2)
├── tests/
├── .github/workflows/dbt_ci.yml
├── dbt_project.yml
├── packages.yml
└── requirements.txt
```

Conventions: `stg_` (1:1 with a source), `int_` (reusable building blocks), `fct_` (facts), `dim_` (dimensions), `snap_` (snapshots). One model, one purpose.

---

_Study chat with Claude: https://claude.ai/share/837babdf-58ba-48b5-a459-d67e1996a4bf_
