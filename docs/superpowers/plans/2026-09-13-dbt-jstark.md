# dbt-jstark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `dbt-jstark`, a warehouse-agnostic dbt macro package that reimplements the [jstark](https://github.com/jamiekt/jstark) PySpark feature generator in SQL, with core, grocery and mealkit feature generators.

**Architecture:** A single dbt package named `jstark` whose macros are namespaced by directory (`macros/core/`, `macros/grocery/`, `macros/mealkit/`). All period arithmetic, feature-name derivation, catalogue resolution, dependency closure and topological levelling happen at Jinja compile time; the macro emits one `select` per level as a chain of CTEs. Three `adapter.dispatch` seams isolate warehouse differences. Tests run in three layers: pure-Jinja assertions via `dbt run-operation`, dbt `unit_tests` on small models, and a full `dbt build` against DuckDB.

**Tech Stack:** dbt-core >=1.8, dbt-duckdb, Jinja2 (dbt's sandboxed environment), uv, pytest-free (all tests are dbt-native), GitHub Actions, pre-commit.

**Spec:** `docs/superpowers/specs/2026-09-13-dbt-jstark-design.md`

**jstark reference:** pinned at commit `51d9083209bf40077c5fdc307b80f59bcb70de1b`. Clone to `/tmp/jstark-ref` if you need to read it: `git clone https://github.com/jamiekt/jstark /tmp/jstark-ref && git -C /tmp/jstark-ref checkout 51d9083209bf40077c5fdc307b80f59bcb70de1b`.

## Global Constraints

- Package name is `jstark`. Every public macro is called as `jstark.<name>(...)`.
- `require-dbt-version: [">=1.8.0", "<2.0.0"]` in `dbt_project.yml`.
- **No Python.** Every line of logic lives in a `.sql` macro file. There is no Python test suite; `pyproject.toml` exists only to pin dbt via `uv`.
- Jinja restrictions in dbt's sandbox — these are hard constraints, not preferences:
  - No `pendulum`, no `dateutil`. Only `modules.datetime`, `modules.re`, `modules.itertools`, `modules.pytz`.
  - No `try`/`except`. Validators that need to be testable expose a non-raising `jstark.try_<name>(...)` returning `{'ok': bool, 'error': str, ...}` plus a thin raising wrapper.
  - No `{% break %}` / `{% continue %}` (loopcontrols extension is not enabled).
  - `{% set %}` inside a `{% for %}` does **not** persist after the loop. Accumulate with `{% do list.append(...) %}` or `{% do dict.update(...) %}` on a namespace or a mutable container declared outside the loop.
  - Prefer `modules.re.findall` / `modules.re.sub` over `.match(...).group(...)` — Match objects behave inconsistently in the sandbox.
  - No dynamic macro-name dispatch (`context[name]`). Catalogues are built by explicit `{% if generator == '...' %}` branches.
- All emitted identifiers are lowercase `snake_case` and **unquoted**, so warehouse case-folding works. Never emit `"gross_spend"`.
- Canonical input column names (these are what feature definitions reference):
  `event_timestamp`, `basket`, `order_id`, `store`, `channel`, `customer`, `product`, `quantity`, `net_spend`, `gross_spend`, `discount`, `cuisine`, `recipe`, `allergen`.
  `timestamp` and `order` are forbidden: `cast(timestamp as date)` is a Postgres syntax error and `order` is reserved everywhere.
- `feature_stems` and `depends_on` **always** refer to the CamelCase **stem** (e.g. `RecencyWeightedBasket95`), never to the emitted column name.
- Internal CTE column names always use the mnemonic suffix (`gross_spend_52w0`). The final projection aliases internal → public, applying absolute period labels when `use_absolute_periods=true`.
- Division always goes through `jstark.safe_divide(a, b)` — never emit a bare `/`.
- Preserved jstark quirk: `min`-aggregated features default to `0.0` on an empty window while `max`-aggregated features default to `null`. This asymmetry is intentional parity, documented in the README.
- Commit style: Conventional Commits (`feat:`, `test:`, `docs:`, `chore:`, `ci:`). Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  ```
- Work on a branch. Task 1 creates it.

---

## File Structure

```
dbt-jstark/
├── dbt_project.yml                                  # name: jstark, macro-paths, require-dbt-version
├── packages.yml                                     # empty (no runtime deps)
├── pyproject.toml                                   # uv project: dbt-core, dbt-duckdb
├── .python-version                                  # 3.12
├── .pre-commit-config.yaml                          # whitespace/EOF/yaml hooks only
├── .gitignore
├── LICENSE.txt
├── README.md
├── CONTRIBUTING.md
├── macros/
│   ├── core/
│   │   ├── exceptions.sql                # jstark_raise_* + try_* helpers
│   │   ├── naming.sql                    # snake_case, name_stem overrides, column_name
│   │   ├── generate_features.sql         # the engine: closure, levelling, CTE emission
│   │   ├── registry.sql                  # jstark.catalogue(generator, ctx), expand_deps
│   │   ├── feature_catalog.sql           # queryable metadata select
│   │   ├── generate_schema_yml.sql       # run-operation: prints schema.yml
│   │   ├── generate_feature_reference.sql# run-operation: prints README markdown tables
│   │   ├── period/
│   │   │   ├── date_math.sql             # add_months, days_in_month, week boundaries
│   │   │   ├── parse_mnemonic.sql        # '3m1' -> {uom, start, end}
│   │   │   ├── period_bounds.sql         # feature_period + as_at -> start_date, end_date
│   │   │   └── period_label.sql          # absolute labels + _week_label
│   │   ├── adapters/
│   │   │   ├── jstark_approx_count_distinct.sql
│   │   │   ├── jstark_collect_set.sql
│   │   │   ├── jstark_to_date.sql
│   │   │   └── safe_divide.sql
│   │   └── features/
│   │       ├── core_counts.sql           # Count, CustomerCount, ApproxCustomerCount,
│   │       │                             #   ProductCount, ApproxProductCount
│   │       ├── core_sums.sql             # Quantity, Discount, GrossSpend, NetSpend
│   │       ├── core_minmax.sql           # Min/Max Gross/Net Spend/Price (8)
│   │       └── core_dates.sql            # RecencyDays, EarliestPurchaseDate,
│   │                                     #   MostRecentPurchaseDate
│   ├── grocery/
│   │   ├── grocery_features.sql          # public entry point
│   │   └── features/
│   │       ├── grocery_base.sql          # BasketCount, ApproxBasketCount,
│   │       │                             #   StoreCount, ChannelCount
│   │       ├── grocery_averages.sql      # AvgGrossSpendPerBasket, AvgQuantityPerBasket,
│   │       │                             #   AvgDiscountPerBasket, AvgPurchaseCycle,
│   │       │                             #   CyclesSinceLastPurchase
│   │       └── grocery_periodic.sql      # BasketPeriods, AvgBasket,
│   │                                     #   RecencyWeightedBasket{90,95,99},
│   │                                     #   RecencyWeightedApproxBasket{90,95,99}
│   └── mealkit/
│       ├── mealkit_features.sql          # public entry point
│       └── features/
│           ├── mealkit_base.sql          # OrderCount, ApproxOrderCount, RecipeCount,
│           │                             #   ApproxRecipeCount, AllergenCount, Allergens,
│           │                             #   CuisineCount, Cuisines
│           ├── mealkit_averages.sql      # AvgQuantityPerOrder, AvgPurchaseCycle,
│           │                             #   CyclesSinceLastOrder
│           ├── mealkit_periodic.sql      # OrderPeriods, AvgOrder
│           └── mealkit_cuisines.sql      # per-cuisine <name>CuisineCount
├── integration_tests/
│   ├── dbt_project.yml
│   ├── packages.yml                                 # local: ../
│   ├── profiles.yml                                 # duckdb default + gated targets
│   ├── seeds/
│   │   ├── grocery_transactions.csv
│   │   ├── mealkit_orders.csv
│   │   ├── expected_grocery_features.csv
│   │   └── expected_mealkit_features.csv
│   ├── macros/
│   │   ├── jstark_test_suite.sql                    # L1 entry point
│   │   └── tests/                                   # L1 assertion groups, one file each
│   └── models/
│       ├── core/
│       ├── grocery/
│       └── mealkit/
└── .github/workflows/
    ├── build.yml
    └── warehouses.yml
```

---

## Task 1: Scaffolding and the L1 test harness

Creates the package project, the integration-test project that consumes it, and the pure-Jinja assertion harness every later task adds to. Nothing warehouse-touching happens here — the deliverable is `dbt run-operation jstark_test_suite` exiting 0.

**Files:**
- Create: `pyproject.toml`, `.python-version`, `.gitignore`, `.pre-commit-config.yaml`, `LICENSE.txt`
- Create: `dbt_project.yml`, `packages.yml`
- Create: `integration_tests/dbt_project.yml`, `integration_tests/packages.yml`, `integration_tests/profiles.yml`
- Create: `macros/core/exceptions.sql`
- Test: `integration_tests/macros/jstark_assert.sql`, `integration_tests/macros/jstark_test_suite.sql`, `integration_tests/macros/tests/test_harness.sql`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `jstark.error_codes()` → dict of short key → error code string.
  - `jstark.error_message(code, detail)` → `'jstark: <code>: <detail>'`.
  - `jstark.raise_error(code, detail)` → raises a compiler error with that message. Never returns.
  - `jstark_assert_equal(failures, label, actual, expected)` — appends a message to `failures` when unequal.
  - `jstark_assert_true(failures, label, actual)` — appends when `actual` is not truthy.
  - `jstark_test_suite()` — run-operation entry point. Calls each `jstark_test_*` group with a shared `failures` list, then raises once if non-empty.
  - Later tasks register new groups by adding one `{% do jstark_test_<group>(failures) %}` line to `jstark_test_suite`.

- [ ] **Step 1: Create the branch**

```bash
cd /Users/jamiethomson/github/jamiekt/dbt-jstark
git checkout -b feat/dbt-jstark-implementation
```

- [ ] **Step 2: Create the Python environment files**

`.python-version`:
```
3.12
```

`pyproject.toml`:
```toml
[project]
name = "dbt-jstark-dev"
version = "0.1.0"
description = "Development environment for the dbt-jstark package. Not published; the deliverable is the dbt package itself."
requires-python = ">=3.11"
dependencies = [
    "dbt-core>=1.8,<2.0",
    "dbt-duckdb>=1.8,<2.0",
]

[tool.uv]
package = false
```

`.gitignore`:
```
.venv/
uv.lock
__pycache__/
target/
dbt_packages/
logs/
*.duckdb
*.duckdb.wal
.user.yml
```

`.pre-commit-config.yaml`:
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-merge-conflict
      - id: mixed-line-ending
```

`LICENSE.txt`: MIT licence text, `Copyright (c) 2026 Jamie Thomson`.

- [ ] **Step 3: Install the environment**

```bash
uv sync
uv run dbt --version
```
Expected: prints `dbt-core` 1.8 or later and the `duckdb` adapter.

- [ ] **Step 4: Create the package project**

`dbt_project.yml`:
```yaml
name: 'jstark'
version: '0.1.0'
config-version: 2

require-dbt-version: [">=1.8.0", "<2.0.0"]

macro-paths: ["macros"]
```

`packages.yml`:
```yaml
packages: []
```

Note: dbt is never run from the repo root. All dbt commands run from `integration_tests/`, which installs the root as a local package.

- [ ] **Step 5: Create the integration test project**

`integration_tests/dbt_project.yml`:
```yaml
name: 'jstark_integration_tests'
version: '0.1.0'
config-version: 2

profile: 'jstark_integration_tests'

require-dbt-version: [">=1.8.0", "<2.0.0"]

model-paths: ["models"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
target-path: "target"

clean-targets:
  - "target"
  - "dbt_packages"

models:
  jstark_integration_tests:
    +materialized: table

seeds:
  jstark_integration_tests:
    +quote_columns: false
```

`integration_tests/packages.yml`:
```yaml
packages:
  - local: ../
```

`integration_tests/profiles.yml`:
```yaml
jstark_integration_tests:
  target: duckdb
  outputs:
    duckdb:
      type: duckdb
      path: "{{ env_var('DBT_DUCKDB_PATH', 'target/jstark.duckdb') }}"
      threads: 4
    postgres:
      type: postgres
      host: "{{ env_var('POSTGRES_HOST', 'localhost') }}"
      port: "{{ env_var('POSTGRES_PORT', '5432') | int }}"
      user: "{{ env_var('POSTGRES_USER', 'postgres') }}"
      password: "{{ env_var('POSTGRES_PASSWORD', 'postgres') }}"
      dbname: "{{ env_var('POSTGRES_DATABASE', 'postgres') }}"
      schema: "{{ env_var('POSTGRES_SCHEMA', 'jstark') }}"
      threads: 4
    snowflake:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT', '') }}"
      user: "{{ env_var('SNOWFLAKE_USER', '') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD', '') }}"
      role: "{{ env_var('SNOWFLAKE_ROLE', '') }}"
      database: "{{ env_var('SNOWFLAKE_DATABASE', '') }}"
      warehouse: "{{ env_var('SNOWFLAKE_WAREHOUSE', '') }}"
      schema: "{{ env_var('SNOWFLAKE_SCHEMA', 'jstark') }}"
      threads: 4
    bigquery:
      type: bigquery
      method: service-account-json
      project: "{{ env_var('BIGQUERY_PROJECT', '') }}"
      dataset: "{{ env_var('BIGQUERY_DATASET', 'jstark') }}"
      threads: 4
      keyfile_json: "{{ env_var('BIGQUERY_KEYFILE_JSON', '{}') | fromjson }}"
```

- [ ] **Step 6: Write the failing harness test**

`integration_tests/macros/jstark_assert.sql`:
```sql
{% macro jstark_assert_equal(failures, label, actual, expected) %}
  {% if actual != expected %}
    {% do failures.append(
        label ~ ': expected ' ~ (expected | string) ~ ' but got ' ~ (actual | string)
    ) %}
  {% endif %}
{% endmacro %}


{% macro jstark_assert_true(failures, label, actual) %}
  {% if not actual %}
    {% do failures.append(label ~ ': expected a truthy value but got ' ~ (actual | string)) %}
  {% endif %}
{% endmacro %}
```

`integration_tests/macros/tests/test_harness.sql` — this group tests the harness and the error helpers:
```sql
{% macro jstark_test_harness(failures) %}

  {# jstark_assert_equal records nothing when values match #}
  {% set probe = [] %}
  {% do jstark_assert_equal(probe, 'probe', 1, 1) %}
  {% do jstark_assert_equal(failures, 'assert_equal is silent on a match', probe | length, 0) %}

  {# jstark_assert_equal records exactly one message when values differ #}
  {% set probe2 = [] %}
  {% do jstark_assert_equal(probe2, 'probe2', 1, 2) %}
  {% do jstark_assert_equal(failures, 'assert_equal records a mismatch', probe2 | length, 1) %}
  {% do jstark_assert_equal(
      failures,
      'assert_equal message format',
      probe2[0],
      'probe2: expected 2 but got 1'
  ) %}

  {# jstark_assert_true records only for falsey values #}
  {% set probe3 = [] %}
  {% do jstark_assert_true(probe3, 'probe3', true) %}
  {% do jstark_assert_true(probe3, 'probe3', false) %}
  {% do jstark_assert_equal(failures, 'assert_true records only falsey', probe3 | length, 1) %}

  {# error codes are stable #}
  {% set codes = jstark.error_codes() %}
  {% do jstark_assert_equal(
      failures, 'code: mnemonic_is_invalid',
      codes['mnemonic_is_invalid'], 'feature_period_mnemonic_is_invalid'
  ) %}
  {% do jstark_assert_equal(
      failures, 'code: end_greater_than_start',
      codes['end_greater_than_start'], 'feature_period_end_greater_than_start'
  ) %}
  {% do jstark_assert_equal(
      failures, 'code: feature_not_found',
      codes['feature_not_found'], 'feature_not_found'
  ) %}
  {% do jstark_assert_equal(
      failures, 'code: unknown_column_map_key',
      codes['unknown_column_map_key'], 'unknown_column_map_key'
  ) %}
  {% do jstark_assert_equal(
      failures, 'code: invalid_first_day_of_week',
      codes['invalid_first_day_of_week'], 'invalid_first_day_of_week'
  ) %}

  {# error_message formats consistently #}
  {% do jstark_assert_equal(
      failures, 'error_message format',
      jstark.error_message('feature_not_found', "['Nope'] is not a known feature stem"),
      "jstark: feature_not_found: ['Nope'] is not a known feature stem"
  ) %}

{% endmacro %}
```

`integration_tests/macros/jstark_test_suite.sql`:
```sql
{% macro jstark_test_suite() %}

  {% set failures = [] %}

  {% do jstark_test_harness(failures) %}

  {% if failures | length > 0 %}
    {% set report = [] %}
    {% do report.append(
        (failures | length | string) ~ ' jstark L1 assertion(s) failed:'
    ) %}
    {% for failure in failures %}
      {% do report.append('  - ' ~ failure) %}
    {% endfor %}
    {{ exceptions.raise_compiler_error(report | join('\n')) }}
  {% endif %}

  {% do log('jstark L1 test suite passed.', info=true) %}

{% endmacro %}
```

- [ ] **Step 7: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt deps
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `'jstark' is undefined` (or `macro 'error_codes' not found`), because `macros/core/exceptions.sql` does not exist yet.

- [ ] **Step 8: Write the minimal implementation**

`macros/core/exceptions.sql`:
```sql
{#
  Named compile-time errors.

  Every error jstark raises goes through raise_error so that the message
  format is uniform and so that L1 tests can assert on the exact text
  without needing try/except (which Jinja does not have).
#}

{% macro error_codes() %}
  {{ return({
      'mnemonic_is_invalid': 'feature_period_mnemonic_is_invalid',
      'end_greater_than_start': 'feature_period_end_greater_than_start',
      'feature_not_found': 'feature_not_found',
      'unknown_column_map_key': 'unknown_column_map_key',
      'invalid_first_day_of_week': 'invalid_first_day_of_week'
  }) }}
{% endmacro %}


{% macro error_message(code, detail) %}
  {{ return('jstark: ' ~ code ~ ': ' ~ detail) }}
{% endmacro %}


{% macro raise_error(code, detail) %}
  {{ exceptions.raise_compiler_error(jstark.error_message(code, detail)) }}
{% endmacro %}
```

- [ ] **Step 9: Run the test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS — `jstark L1 test suite passed.`

- [ ] **Step 10: Commit**

```bash
cd /Users/jamiethomson/github/jamiekt/dbt-jstark
git add -A
git commit -m "$(cat <<'EOF'
feat: scaffold the jstark dbt package and L1 test harness

Adds the package dbt_project.yml, the integration_tests project that
installs it as a local package, the uv environment, and the pure-Jinja
assertion harness invoked via `dbt run-operation jstark_test_suite`.

Also adds macros/core/exceptions.sql: every jstark error goes through
raise_error so message text is uniform and assertable.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Naming — snake_case, unit-infix overrides, internal column names

Turns a CamelCase stem plus a period into the internal column name (`recency_weighted_basket_months95_3m1`). This is pure string manipulation with no dbt dependencies, so it is entirely L1-testable.

**Files:**
- Create: `macros/core/naming.sql`
- Test: `integration_tests/macros/tests/test_naming.sql`
- Modify: `integration_tests/macros/jstark_test_suite.sql` (register the new group)

**Interfaces:**
- Consumes: `jstark.error_codes()`, `jstark.error_message()` (Task 1).
- Produces:
  - `jstark.snake_case(name)` → lowercase snake_case string. Handles CamelCase boundaries, acronym runs, and non-alphanumeric separators (spaces, hyphens).
  - `jstark.period_unit_name(uom)` → `'Day' | 'Week' | 'Month' | 'Quarter' | 'Year'` for `'d' | 'w' | 'm' | 'q' | 'y'`.
  - `jstark.name_stem_overrides()` → dict of stem → `[prefix, suffix]`. The unit name is inserted between them.
  - `jstark.feature_base_name(stem, uom)` → snake_case name without the period suffix.
  - `jstark.column_name(stem, feature_period)` → internal column name: `feature_base_name(stem, feature_period['uom']) ~ '_' ~ feature_period['mnemonic']`. `feature_period` is the dict produced by `jstark.parse_feature_period` (Task 4), but this task only needs its `uom` and `mnemonic` keys, so tests build the dict inline.

- [ ] **Step 1: Write the failing test**

`integration_tests/macros/tests/test_naming.sql`:
```sql
{% macro jstark_test_naming(failures) %}

  {# --- snake_case: CamelCase boundaries --- #}
  {% set cases = [
      ['Count', 'count'],
      ['MinNetPrice', 'min_net_price'],
      ['AvgGrossSpendPerBasket', 'avg_gross_spend_per_basket'],
      ['AverageBasketsPerMonth', 'average_baskets_per_month'],
      ['RecencyWeightedApproxBasketMonths95', 'recency_weighted_approx_basket_months95'],
      ['CyclesSinceLastPurchase', 'cycles_since_last_purchase'],
      ['ApproxCustomerCount', 'approx_customer_count'],
      ['EarliestPurchaseDate', 'earliest_purchase_date'],
      ['RecencyDays', 'recency_days'],
      ['BasketMonths', 'basket_months'],
      ['RecencyWeightedBasketWeeks90', 'recency_weighted_basket_weeks90']
  ] %}
  {% for case in cases %}
    {% do jstark_assert_equal(
        failures, 'snake_case(' ~ case[0] ~ ')', jstark.snake_case(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- snake_case: separators and acronyms (used for cuisine names) --- #}
  {% set sep_cases = [
      ['Thai', 'thai'],
      ['South African', 'south_african'],
      ['Sub-Saharan', 'sub_saharan'],
      ['Tex Mex', 'tex_mex'],
      ['  Padded  ', 'padded'],
      ['HTTPServer', 'http_server']
  ] %}
  {% for case in sep_cases %}
    {% do jstark_assert_equal(
        failures, 'snake_case(' ~ case[0] ~ ')', jstark.snake_case(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- period_unit_name --- #}
  {% set unit_cases = [
      ['d', 'Day'], ['w', 'Week'], ['m', 'Month'], ['q', 'Quarter'], ['y', 'Year']
  ] %}
  {% for case in unit_cases %}
    {% do jstark_assert_equal(
        failures, 'period_unit_name(' ~ case[0] ~ ')',
        jstark.period_unit_name(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- feature_base_name: stems with no override pass through snake_case --- #}
  {% do jstark_assert_equal(
      failures, 'feature_base_name(GrossSpend, m)',
      jstark.feature_base_name('GrossSpend', 'm'), 'gross_spend'
  ) %}
  {% do jstark_assert_equal(
      failures, 'feature_base_name(BasketCount, w)',
      jstark.feature_base_name('BasketCount', 'w'), 'basket_count'
  ) %}

  {# --- feature_base_name: unit-infix overrides --- #}
  {% set override_cases = [
      ['BasketPeriods', 'm', 'basket_months'],
      ['BasketPeriods', 'w', 'basket_weeks'],
      ['BasketPeriods', 'd', 'basket_days'],
      ['BasketPeriods', 'q', 'basket_quarters'],
      ['BasketPeriods', 'y', 'basket_years'],
      ['OrderPeriods', 'm', 'order_months'],
      ['AvgBasket', 'm', 'average_baskets_per_month'],
      ['AvgBasket', 'w', 'average_baskets_per_week'],
      ['AvgOrder', 'm', 'average_orders_per_month'],
      ['RecencyWeightedBasket90', 'm', 'recency_weighted_basket_months90'],
      ['RecencyWeightedBasket95', 'm', 'recency_weighted_basket_months95'],
      ['RecencyWeightedBasket99', 'm', 'recency_weighted_basket_months99'],
      ['RecencyWeightedBasket95', 'w', 'recency_weighted_basket_weeks95'],
      ['RecencyWeightedApproxBasket90', 'm', 'recency_weighted_approx_basket_months90'],
      ['RecencyWeightedApproxBasket95', 'm', 'recency_weighted_approx_basket_months95'],
      ['RecencyWeightedApproxBasket99', 'm', 'recency_weighted_approx_basket_months99']
  ] %}
  {% for case in override_cases %}
    {% do jstark_assert_equal(
        failures, 'feature_base_name(' ~ case[0] ~ ', ' ~ case[1] ~ ')',
        jstark.feature_base_name(case[0], case[1]), case[2]
    ) %}
  {% endfor %}

  {# --- column_name appends the mnemonic --- #}
  {% set fp_3m1 = {'uom': 'm', 'start': 3, 'end': 1, 'mnemonic': '3m1'} %}
  {% set fp_52w0 = {'uom': 'w', 'start': 52, 'end': 0, 'mnemonic': '52w0'} %}
  {% do jstark_assert_equal(
      failures, 'column_name(GrossSpend, 3m1)',
      jstark.column_name('GrossSpend', fp_3m1), 'gross_spend_3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'column_name(BasketPeriods, 3m1)',
      jstark.column_name('BasketPeriods', fp_3m1), 'basket_months_3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'column_name(RecencyWeightedBasket95, 52w0)',
      jstark.column_name('RecencyWeightedBasket95', fp_52w0),
      'recency_weighted_basket_weeks95_52w0'
  ) %}
  {% do jstark_assert_equal(
      failures, 'column_name(AvgBasket, 52w0)',
      jstark.column_name('AvgBasket', fp_52w0), 'average_baskets_per_week_52w0'
  ) %}

{% endmacro %}
```

Register it in `integration_tests/macros/jstark_test_suite.sql` immediately after the `jstark_test_harness` line:
```sql
  {% do jstark_test_naming(failures) %}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `macro 'snake_case' not found in package 'jstark'`.

- [ ] **Step 3: Write the minimal implementation**

`macros/core/naming.sql`:
```sql
{#
  Feature naming.

  A feature is identified by its CamelCase *stem* (e.g. RecencyWeightedBasket95).
  The emitted column name is the snake_cased stem with the feature period
  appended (recency_weighted_basket_weeks95_52w0).

  Some stems are unit-dependent: jstark's BasketPeriods feature is called
  BasketMonths when the period unit is months and BasketWeeks when it is
  weeks. name_stem_overrides holds those as [prefix, suffix] pairs; the unit
  name is inserted between them before snake_casing.
#}

{% macro snake_case(name) %}
  {#- collapse anything that is not alphanumeric into a single underscore -#}
  {% set cleaned = modules.re.sub('[^A-Za-z0-9]+', '_', name | string) %}
  {#- lowercase-or-digit followed by uppercase is a word boundary -#}
  {% set s1 = modules.re.sub('([a-z0-9])([A-Z])', '\\1_\\2', cleaned) %}
  {#- an acronym run followed by a capitalised word is a word boundary -#}
  {% set s2 = modules.re.sub('([A-Z]+)([A-Z][a-z])', '\\1_\\2', s1) %}
  {#- tidy up doubled and edge underscores left by the steps above -#}
  {% set s3 = modules.re.sub('_+', '_', s2) %}
  {{ return(s3 | lower | trim('_')) }}
{% endmacro %}


{% macro period_unit_name(uom) %}
  {% set names = {
      'd': 'Day', 'w': 'Week', 'm': 'Month', 'q': 'Quarter', 'y': 'Year'
  } %}
  {% if uom not in names %}
    {% do jstark.raise_error(
        jstark.error_codes()['mnemonic_is_invalid'],
        "'" ~ uom ~ "' is not a period unit of measure; expected one of d, w, m, q, y"
    ) %}
  {% endif %}
  {{ return(names[uom]) }}
{% endmacro %}


{% macro name_stem_overrides() %}
  {#- stem -> [prefix, suffix]; the unit name goes between them -#}
  {{ return({
      'BasketPeriods': ['Basket', 's'],
      'OrderPeriods': ['Order', 's'],
      'AvgBasket': ['AverageBasketsPer', ''],
      'AvgOrder': ['AverageOrdersPer', ''],
      'RecencyWeightedBasket90': ['RecencyWeightedBasket', 's90'],
      'RecencyWeightedBasket95': ['RecencyWeightedBasket', 's95'],
      'RecencyWeightedBasket99': ['RecencyWeightedBasket', 's99'],
      'RecencyWeightedApproxBasket90': ['RecencyWeightedApproxBasket', 's90'],
      'RecencyWeightedApproxBasket95': ['RecencyWeightedApproxBasket', 's95'],
      'RecencyWeightedApproxBasket99': ['RecencyWeightedApproxBasket', 's99']
  }) }}
{% endmacro %}


{% macro feature_base_name(stem, uom) %}
  {% set overrides = jstark.name_stem_overrides() %}
  {% if stem in overrides %}
    {% set parts = overrides[stem] %}
    {% set camel = parts[0] ~ jstark.period_unit_name(uom) ~ parts[1] %}
  {% else %}
    {% set camel = stem %}
  {% endif %}
  {{ return(jstark.snake_case(camel)) }}
{% endmacro %}


{% macro column_name(stem, feature_period) %}
  {{ return(
      jstark.feature_base_name(stem, feature_period['uom'])
      ~ '_' ~ feature_period['mnemonic']
  ) }}
{% endmacro %}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS — `jstark L1 test suite passed.`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: derive feature column names from CamelCase stems

snake_case handles CamelCase boundaries, acronym runs and non-alphanumeric
separators (needed for user-supplied cuisine names). name_stem_overrides
reproduces jstark's unit-dependent names, where BasketPeriods becomes
BasketMonths for a monthly period and BasketWeeks for a weekly one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Date arithmetic

jstark uses `pendulum` for month/quarter/year arithmetic and week boundaries. `pendulum` is unavailable in dbt's Jinja sandbox, so this task reimplements exactly the behaviour jstark relies on using `modules.datetime` only. The critical behaviour is pendulum's end-of-month clamping: `2022-03-31` minus one month is `2022-02-28`.

Dates are represented as real `modules.datetime.date` objects throughout — they compare, subtract and expose `.year`/`.month`/`.day`/`.weekday()`. They are only converted to strings at the point a SQL literal is emitted.

**Files:**
- Create: `macros/core/period/date_math.sql`
- Test: `integration_tests/macros/tests/test_date_math.sql`
- Modify: `integration_tests/macros/jstark_test_suite.sql`

**Interfaces:**
- Consumes: `jstark.raise_error()`, `jstark.error_codes()` (Task 1).
- Produces:
  - `jstark.as_date(value)` → `datetime.date`. Accepts a `date`, a `datetime`, `'2022-01-01'`, or `'2022-01-01 09:30:00'`.
  - `jstark.date_string(d)` → `'2022-01-01'`.
  - `jstark.is_leap_year(year)` → bool.
  - `jstark.days_in_month(year, month)` → int.
  - `jstark.add_days(d, n)`, `jstark.add_weeks(d, n)`, `jstark.add_months(d, n)` → `date`. `n` may be negative. `add_months` clamps the day to the last day of the target month.
  - `jstark.quarter_of(d)` → 1-4.
  - `jstark.first_date_in_month(d)`, `jstark.last_date_in_month(d)`, `jstark.first_date_in_quarter(d)`, `jstark.last_date_in_quarter(d)`, `jstark.first_date_in_year(d)`, `jstark.last_date_in_year(d)` → `date`.
  - `jstark.weekday_names()` → `['Monday', ..., 'Sunday']`.
  - `jstark.weekday_index(first_day_of_week)` → 0-6. `none` means Monday. Raises `invalid_first_day_of_week` otherwise.
  - `jstark.first_date_in_week(d, first_day_of_week)`, `jstark.last_date_in_week(d, first_day_of_week)` → `date`.
  - `jstark.min_date(a, b)` → the earlier of two dates.

- [ ] **Step 1: Write the failing test**

`integration_tests/macros/tests/test_date_math.sql`:
```sql
{% macro jstark_test_date_math(failures) %}

  {% set d = modules.datetime.date %}

  {# --- as_date accepts dates, date strings and timestamp strings --- #}
  {% do jstark_assert_equal(
      failures, 'as_date(date)', jstark.as_date(d(2022, 1, 1)), d(2022, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      failures, 'as_date(iso string)', jstark.as_date('2022-01-01'), d(2022, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      failures, 'as_date(timestamp string)',
      jstark.as_date('2022-01-01 09:30:00'), d(2022, 1, 1)
  ) %}

  {# --- date_string zero-pads --- #}
  {% do jstark_assert_equal(
      failures, 'date_string', jstark.date_string(d(2021, 2, 3)), '2021-02-03'
  ) %}

  {# --- leap years --- #}
  {% set leap_cases = [
      [2020, true], [2021, false], [2000, true], [1900, false], [2024, true]
  ] %}
  {% for case in leap_cases %}
    {% do jstark_assert_equal(
        failures, 'is_leap_year(' ~ case[0] ~ ')',
        jstark.is_leap_year(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- days_in_month --- #}
  {% set dim_cases = [
      [2021, 1, 31], [2021, 2, 28], [2020, 2, 29], [2000, 2, 29], [1900, 2, 28],
      [2021, 4, 30], [2021, 12, 31]
  ] %}
  {% for case in dim_cases %}
    {% do jstark_assert_equal(
        failures, 'days_in_month(' ~ case[0] ~ ',' ~ case[1] ~ ')',
        jstark.days_in_month(case[0], case[1]), case[2]
    ) %}
  {% endfor %}

  {# --- add_days / add_weeks, including negatives across year boundaries --- #}
  {% do jstark_assert_equal(
      failures, 'add_days(2022-01-01, -1)',
      jstark.add_days(d(2022, 1, 1), -1), d(2021, 12, 31)
  ) %}
  {% do jstark_assert_equal(
      failures, 'add_days(2022-01-01, 0)',
      jstark.add_days(d(2022, 1, 1), 0), d(2022, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      failures, 'add_weeks(2022-01-01, -1)',
      jstark.add_weeks(d(2022, 1, 1), -1), d(2021, 12, 25)
  ) %}
  {% do jstark_assert_equal(
      failures, 'add_weeks(2022-01-01, -52)',
      jstark.add_weeks(d(2022, 1, 1), -52), d(2021, 1, 2)
  ) %}

  {# --- add_months: pendulum-compatible end-of-month clamping --- #}
  {% set am_cases = [
      [d(2022, 3, 31), -1, d(2022, 2, 28)],
      [d(2020, 3, 31), -1, d(2020, 2, 29)],
      [d(2021, 1, 31), 1, d(2021, 2, 28)],
      [d(2022, 1, 1), -1, d(2021, 12, 1)],
      [d(2022, 1, 31), -12, d(2021, 1, 31)],
      [d(2022, 1, 15), 0, d(2022, 1, 15)],
      [d(2022, 5, 31), -3, d(2022, 2, 28)],
      [d(2022, 1, 1), -3, d(2021, 10, 1)],
      [d(2022, 1, 1), -12, d(2021, 1, 1)]
  ] %}
  {% for case in am_cases %}
    {% do jstark_assert_equal(
        failures,
        'add_months(' ~ jstark.date_string(case[0]) ~ ', ' ~ case[1] ~ ')',
        jstark.add_months(case[0], case[1]), case[2]
    ) %}
  {% endfor %}

  {# --- month / quarter / year boundaries --- #}
  {% do jstark_assert_equal(
      failures, 'first_date_in_month',
      jstark.first_date_in_month(d(2021, 2, 17)), d(2021, 2, 1)
  ) %}
  {% do jstark_assert_equal(
      failures, 'last_date_in_month(feb 2020)',
      jstark.last_date_in_month(d(2020, 2, 17)), d(2020, 2, 29)
  ) %}
  {% set q_cases = [
      [d(2021, 1, 5), 1, d(2021, 1, 1), d(2021, 3, 31)],
      [d(2021, 6, 30), 2, d(2021, 4, 1), d(2021, 6, 30)],
      [d(2021, 8, 1), 3, d(2021, 7, 1), d(2021, 9, 30)],
      [d(2021, 11, 15), 4, d(2021, 10, 1), d(2021, 12, 31)]
  ] %}
  {% for case in q_cases %}
    {% do jstark_assert_equal(
        failures, 'quarter_of(' ~ jstark.date_string(case[0]) ~ ')',
        jstark.quarter_of(case[0]), case[1]
    ) %}
    {% do jstark_assert_equal(
        failures, 'first_date_in_quarter(' ~ jstark.date_string(case[0]) ~ ')',
        jstark.first_date_in_quarter(case[0]), case[2]
    ) %}
    {% do jstark_assert_equal(
        failures, 'last_date_in_quarter(' ~ jstark.date_string(case[0]) ~ ')',
        jstark.last_date_in_quarter(case[0]), case[3]
    ) %}
  {% endfor %}
  {% do jstark_assert_equal(
      failures, 'first_date_in_year',
      jstark.first_date_in_year(d(2021, 7, 4)), d(2021, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      failures, 'last_date_in_year',
      jstark.last_date_in_year(d(2021, 7, 4)), d(2021, 12, 31)
  ) %}

  {# --- weekday_index, defaulting to Monday --- #}
  {% do jstark_assert_equal(
      failures, 'weekday_index(none)', jstark.weekday_index(none), 0
  ) %}
  {% set wd_cases = [
      ['Monday', 0], ['Tuesday', 1], ['Wednesday', 2], ['Thursday', 3],
      ['Friday', 4], ['Saturday', 5], ['Sunday', 6]
  ] %}
  {% for case in wd_cases %}
    {% do jstark_assert_equal(
        failures, 'weekday_index(' ~ case[0] ~ ')',
        jstark.weekday_index(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- week boundaries. 2022-01-01 is a Saturday. --- #}
  {% set wk_cases = [
      ['Monday', d(2021, 12, 27), d(2022, 1, 2)],
      ['Tuesday', d(2021, 12, 28), d(2022, 1, 3)],
      ['Wednesday', d(2021, 12, 29), d(2022, 1, 4)],
      ['Thursday', d(2021, 12, 30), d(2022, 1, 5)],
      ['Friday', d(2021, 12, 31), d(2022, 1, 6)],
      ['Saturday', d(2022, 1, 1), d(2022, 1, 7)],
      ['Sunday', d(2021, 12, 26), d(2022, 1, 1)]
  ] %}
  {% for case in wk_cases %}
    {% do jstark_assert_equal(
        failures, 'first_date_in_week(2022-01-01, ' ~ case[0] ~ ')',
        jstark.first_date_in_week(d(2022, 1, 1), case[0]), case[1]
    ) %}
    {% do jstark_assert_equal(
        failures, 'last_date_in_week(2022-01-01, ' ~ case[0] ~ ')',
        jstark.last_date_in_week(d(2022, 1, 1), case[0]), case[2]
    ) %}
  {% endfor %}

  {# --- min_date --- #}
  {% do jstark_assert_equal(
      failures, 'min_date(a<b)', jstark.min_date(d(2021, 1, 1), d(2022, 1, 1)),
      d(2021, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      failures, 'min_date(a>b)', jstark.min_date(d(2022, 1, 1), d(2021, 1, 1)),
      d(2021, 1, 1)
  ) %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_date_math(failures) %}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `macro 'as_date' not found in package 'jstark'`.

- [ ] **Step 3: Write the minimal implementation**

`macros/core/period/date_math.sql`:
```sql
{#
  Date arithmetic.

  jstark uses pendulum, which is not available in dbt's Jinja sandbox, so
  this reimplements the parts jstark depends on with modules.datetime only.
  The behaviour that matters most is pendulum's end-of-month clamping:
  2022-03-31 minus one month is 2022-02-28, not an invalid 2022-02-31.

  Dates are real datetime.date objects everywhere; they become strings only
  when a SQL literal is emitted.
#}

{% macro as_date(value) %}
  {% if value is string %}
    {#- tolerate '2022-01-01' and '2022-01-01 09:30:00' without
        relying on classmethods being reachable in the sandbox -#}
    {% set parts = modules.re.findall('\\d+', value) %}
    {{ return(modules.datetime.date(parts[0] | int, parts[1] | int, parts[2] | int)) }}
  {% endif %}
  {{ return(modules.datetime.date(value.year, value.month, value.day)) }}
{% endmacro %}


{% macro date_string(d) %}
  {{ return('%04d-%02d-%02d' | format(d.year, d.month, d.day)) }}
{% endmacro %}


{% macro is_leap_year(year) %}
  {{ return(year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) }}
{% endmacro %}


{% macro days_in_month(year, month) %}
  {% if month == 2 and jstark.is_leap_year(year) %}
    {{ return(29) }}
  {% endif %}
  {% set lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] %}
  {{ return(lengths[month - 1]) }}
{% endmacro %}


{% macro add_days(d, n) %}
  {{ return(d + modules.datetime.timedelta(days=n)) }}
{% endmacro %}


{% macro add_weeks(d, n) %}
  {{ return(d + modules.datetime.timedelta(weeks=n)) }}
{% endmacro %}


{% macro add_months(d, n) %}
  {% set total = d.year * 12 + (d.month - 1) + n %}
  {% set year = total // 12 %}
  {% set month = total % 12 + 1 %}
  {% set month_length = jstark.days_in_month(year, month) %}
  {% set day = d.day if d.day < month_length else month_length %}
  {{ return(modules.datetime.date(year, month, day)) }}
{% endmacro %}


{% macro quarter_of(d) %}
  {{ return((d.month - 1) // 3 + 1) }}
{% endmacro %}


{% macro first_date_in_month(d) %}
  {{ return(modules.datetime.date(d.year, d.month, 1)) }}
{% endmacro %}


{% macro last_date_in_month(d) %}
  {{ return(modules.datetime.date(
      d.year, d.month, jstark.days_in_month(d.year, d.month)
  )) }}
{% endmacro %}


{% macro first_date_in_quarter(d) %}
  {{ return(modules.datetime.date(
      d.year, (jstark.quarter_of(d) - 1) * 3 + 1, 1
  )) }}
{% endmacro %}


{% macro last_date_in_quarter(d) %}
  {% set month = jstark.quarter_of(d) * 3 %}
  {{ return(modules.datetime.date(
      d.year, month, jstark.days_in_month(d.year, month)
  )) }}
{% endmacro %}


{% macro first_date_in_year(d) %}
  {{ return(modules.datetime.date(d.year, 1, 1)) }}
{% endmacro %}


{% macro last_date_in_year(d) %}
  {{ return(modules.datetime.date(d.year, 12, 31)) }}
{% endmacro %}


{% macro weekday_names() %}
  {{ return([
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ]) }}
{% endmacro %}


{% macro weekday_index(first_day_of_week) %}
  {% set names = jstark.weekday_names() %}
  {% set name = first_day_of_week if first_day_of_week else 'Monday' %}
  {% if name not in names %}
    {% do jstark.raise_error(
        jstark.error_codes()['invalid_first_day_of_week'],
        "'" ~ name ~ "' is not a day name; expected one of " ~ (names | join(', '))
    ) %}
  {% endif %}
  {{ return(names.index(name)) }}
{% endmacro %}


{% macro first_date_in_week(d, first_day_of_week) %}
  {% set target = jstark.weekday_index(first_day_of_week) %}
  {% set days_back = (d.weekday() - target) % 7 %}
  {{ return(jstark.add_days(d, -days_back)) }}
{% endmacro %}


{% macro last_date_in_week(d, first_day_of_week) %}
  {{ return(jstark.add_days(jstark.first_date_in_week(d, first_day_of_week), 6)) }}
{% endmacro %}


{% macro min_date(a, b) %}
  {{ return(a if a < b else b) }}
{% endmacro %}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add pendulum-free date arithmetic

Reimplements the month/quarter/year arithmetic and week boundaries jstark
gets from pendulum, using only modules.datetime, which is all dbt's Jinja
sandbox exposes. add_months clamps to the end of the target month so that
2022-03-31 minus one month is 2022-02-28, matching pendulum.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Feature period parsing and bounds

Turns `'3m1'` (or `{'unit': 'm', 'start': 3, 'end': 1}`) into a period dict, then turns a period plus an `as_at` into the concrete `start_date`/`end_date` pair that every base feature filters on.

Because Jinja has no `try`/`except`, parsing is split into a non-raising `try_parse_feature_period` returning `{'ok': ..., 'error': ...}` and a thin raising `parse_feature_period` wrapper. That is what makes the error paths L1-testable.

**Files:**
- Create: `macros/core/period/parse_mnemonic.sql`, `macros/core/period/period_bounds.sql`
- Test: `integration_tests/macros/tests/test_period.sql`
- Modify: `integration_tests/macros/jstark_test_suite.sql`

**Interfaces:**
- Consumes: `jstark.raise_error()`, `jstark.error_codes()`, `jstark.error_message()` (Task 1); all of `date_math.sql` (Task 3).
- Produces:
  - A **feature period dict**, the value passed around for the rest of the project:
    `{'uom': 'm', 'start': 3, 'end': 1, 'mnemonic': '3m1', 'number_of_periods': 3}`.
  - `jstark.try_parse_feature_period(value)` → `{'ok': bool, 'error': string_or_none, 'period': dict_or_none}`. `value` is a mnemonic string or a dict with keys `unit`, `start`, `end`.
  - `jstark.parse_feature_period(value)` → period dict; raises on failure.
  - `jstark.parse_feature_periods(value)` → list of period dicts. `none` or an empty list yields `[parse_feature_period('52w0')]`. A bare string is treated as a one-element list.
  - `jstark.period_bounds(feature_period, as_at, first_day_of_week)` → `{'start_date': date, 'end_date': date}`. `as_at` is a `date`; `end_date` is capped at `as_at`.

- [ ] **Step 1: Write the failing test**

`integration_tests/macros/tests/test_period.sql`:
```sql
{% macro jstark_test_period(failures) %}

  {% set d = modules.datetime.date %}

  {# --- mnemonic parsing --- #}
  {% set parse_cases = [
      ['3m1', 'm', 3, 1, '3m1', 3],
      ['52w0', 'w', 52, 0, '52w0', 53],
      ['0d0', 'd', 0, 0, '0d0', 1],
      ['4q4', 'q', 4, 4, '4q4', 1],
      ['1y1', 'y', 1, 1, '1y1', 1],
      ['12m0', 'm', 12, 0, '12m0', 13],
      ['m', 'm', 0, 0, '0m0', 1]
  ] %}
  {% for case in parse_cases %}
    {% set p = jstark.parse_feature_period(case[0]) %}
    {% do jstark_assert_equal(failures, 'parse(' ~ case[0] ~ ').uom', p['uom'], case[1]) %}
    {% do jstark_assert_equal(failures, 'parse(' ~ case[0] ~ ').start', p['start'], case[2]) %}
    {% do jstark_assert_equal(failures, 'parse(' ~ case[0] ~ ').end', p['end'], case[3]) %}
    {% do jstark_assert_equal(
        failures, 'parse(' ~ case[0] ~ ').mnemonic', p['mnemonic'], case[4]
    ) %}
    {% do jstark_assert_equal(
        failures, 'parse(' ~ case[0] ~ ').number_of_periods',
        p['number_of_periods'], case[5]
    ) %}
  {% endfor %}

  {# --- dict form --- #}
  {% set from_dict = jstark.parse_feature_period({'unit': 'm', 'start': 3, 'end': 1}) %}
  {% do jstark_assert_equal(
      failures, 'parse(dict).mnemonic', from_dict['mnemonic'], '3m1'
  ) %}

  {# --- an already-parsed period passes through unchanged --- #}
  {% do jstark_assert_equal(
      failures, 'parse(period dict) is idempotent',
      jstark.parse_feature_period(from_dict)['mnemonic'], '3m1'
  ) %}

  {# --- invalid mnemonics report, not crash --- #}
  {% set bad_mnemonics = ['3x1', '3m1m', 'weekly', '', '3 m 1', '-1m0'] %}
  {% for bad in bad_mnemonics %}
    {% set result = jstark.try_parse_feature_period(bad) %}
    {% do jstark_assert_equal(
        failures, "try_parse('" ~ bad ~ "').ok", result['ok'], false
    ) %}
    {% do jstark_assert_equal(
        failures, "try_parse('" ~ bad ~ "').error",
        result['error'],
        jstark.error_message(
            jstark.error_codes()['mnemonic_is_invalid'],
            "'" ~ bad ~ "' is not a valid feature period mnemonic; "
            ~ 'expected <start><d|w|m|q|y><end>, for example 52w0'
        )
    ) %}
  {% endfor %}

  {# --- end may not be greater than start --- #}
  {% set reversed = jstark.try_parse_feature_period('1m3') %}
  {% do jstark_assert_equal(failures, "try_parse('1m3').ok", reversed['ok'], false) %}
  {% do jstark_assert_equal(
      failures, "try_parse('1m3').error",
      reversed['error'],
      jstark.error_message(
          jstark.error_codes()['end_greater_than_start'],
          'feature period end (3) is greater than start (1)'
      )
  ) %}

  {# --- parse_feature_periods defaulting and normalisation --- #}
  {% do jstark_assert_equal(
      failures, 'parse_feature_periods(none) defaults to 52w0',
      jstark.parse_feature_periods(none) | map(attribute='mnemonic') | list,
      ['52w0']
  ) %}
  {% do jstark_assert_equal(
      failures, 'parse_feature_periods([]) defaults to 52w0',
      jstark.parse_feature_periods([]) | map(attribute='mnemonic') | list,
      ['52w0']
  ) %}
  {% do jstark_assert_equal(
      failures, 'parse_feature_periods(string) wraps',
      jstark.parse_feature_periods('3m1') | map(attribute='mnemonic') | list,
      ['3m1']
  ) %}
  {% do jstark_assert_equal(
      failures, 'parse_feature_periods(list) preserves order',
      jstark.parse_feature_periods(['3m1', '0d0', {'unit': 'y', 'start': 1, 'end': 1}])
        | map(attribute='mnemonic') | list,
      ['3m1', '0d0', '1y1']
  ) %}

  {# --- period_bounds. Values cross-checked against jstark at 51d9083. --- #}
  {% set bound_cases = [
      ['3m1',  d(2022, 1, 1),  'Monday', d(2021, 10, 1), d(2021, 12, 31)],
      ['4q4',  d(2022, 1, 1),  'Monday', d(2021, 1, 1),  d(2021, 3, 31)],
      ['0m0',  d(2022, 1, 15), 'Monday', d(2022, 1, 1),  d(2022, 1, 15)],
      ['1m1',  d(2022, 3, 31), 'Monday', d(2022, 2, 1),  d(2022, 2, 28)],
      ['1m1',  d(2020, 3, 31), 'Monday', d(2020, 2, 1),  d(2020, 2, 29)],
      ['1w1',  d(2022, 1, 1),  'Monday', d(2021, 12, 20), d(2021, 12, 26)],
      ['0w0',  d(2022, 1, 1),  'Monday', d(2021, 12, 27), d(2022, 1, 1)],
      ['0w0',  d(2022, 1, 1),  'Sunday', d(2021, 12, 26), d(2022, 1, 1)],
      ['0d0',  d(2022, 1, 1),  'Monday', d(2022, 1, 1),  d(2022, 1, 1)],
      ['1d1',  d(2022, 1, 1),  'Monday', d(2021, 12, 31), d(2021, 12, 31)],
      ['1y1',  d(2022, 1, 1),  'Monday', d(2021, 1, 1),  d(2021, 12, 31)],
      ['0y0',  d(2022, 1, 1),  'Monday', d(2022, 1, 1),  d(2022, 1, 1)],
      ['0q0',  d(2022, 1, 1),  'Monday', d(2022, 1, 1),  d(2022, 1, 1)],
      ['52w0', d(2022, 1, 1),  'Monday', d(2020, 12, 28), d(2022, 1, 1)]
  ] %}
  {% for case in bound_cases %}
    {% set bounds = jstark.period_bounds(
        jstark.parse_feature_period(case[0]), case[1], case[2]
    ) %}
    {% set label = 'period_bounds(' ~ case[0] ~ ', ' ~ jstark.date_string(case[1])
                   ~ ', ' ~ case[2] ~ ')' %}
    {% do jstark_assert_equal(
        failures, label ~ '.start_date', bounds['start_date'], case[3]
    ) %}
    {% do jstark_assert_equal(
        failures, label ~ '.end_date', bounds['end_date'], case[4]
    ) %}
  {% endfor %}

  {# --- an unknown first_day_of_week is rejected --- #}
  {% set fdow = jstark.try_weekday_index('Funday') %}
  {% do jstark_assert_equal(failures, "try_weekday_index('Funday').ok", fdow['ok'], false) %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_period(failures) %}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `macro 'parse_feature_period' not found in package 'jstark'`.

- [ ] **Step 3: Add the non-raising weekday validator**

The test needs `jstark.try_weekday_index`. Add it to `macros/core/period/date_math.sql` and refactor `weekday_index` to use it:

```sql
{% macro try_weekday_index(first_day_of_week) %}
  {% set names = jstark.weekday_names() %}
  {% set name = first_day_of_week if first_day_of_week else 'Monday' %}
  {% if name not in names %}
    {{ return({
        'ok': false,
        'error': jstark.error_message(
            jstark.error_codes()['invalid_first_day_of_week'],
            "'" ~ name ~ "' is not a day name; expected one of " ~ (names | join(', '))
        ),
        'index': none
    }) }}
  {% endif %}
  {{ return({'ok': true, 'error': none, 'index': names.index(name)}) }}
{% endmacro %}


{% macro weekday_index(first_day_of_week) %}
  {% set result = jstark.try_weekday_index(first_day_of_week) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['index']) }}
{% endmacro %}
```

Delete the original `weekday_index` body (the one that called `raise_error` directly) so there is exactly one definition of each macro.

- [ ] **Step 4: Write the parser**

`macros/core/period/parse_mnemonic.sql`:
```sql
{#
  Feature period parsing.

  A feature period is a window expressed in whole units, counted backwards
  from as_at: '3m1' means "from 3 months ago to 1 month ago inclusive".

  Everything downstream works with the dict this produces:
    {'uom': 'm', 'start': 3, 'end': 1, 'mnemonic': '3m1', 'number_of_periods': 3}

  Parsing is split so that failures are inspectable: try_parse_feature_period
  reports, parse_feature_period raises. Jinja has no try/except, so this is
  the only way the error paths can be asserted on.
#}

{% macro feature_period(uom, start, end) %}
  {{ return({
      'uom': uom,
      'start': start,
      'end': end,
      'mnemonic': (start | string) ~ uom ~ (end | string),
      'number_of_periods': start - end + 1
  }) }}
{% endmacro %}


{% macro try_parse_feature_period(value) %}

  {#- already a parsed period? pass it through -#}
  {% if value is mapping and 'mnemonic' in value %}
    {{ return({'ok': true, 'error': none, 'period': value}) }}
  {% endif %}

  {% if value is mapping %}
    {% set uom = value.get('unit') %}
    {% set start = value.get('start', 0) %}
    {% set end = value.get('end', 0) %}
    {% if uom not in ['d', 'w', 'm', 'q', 'y'] or start < 0 or end < 0 %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['mnemonic_is_invalid'],
              (value | string) ~ ' is not a valid feature period; expected keys '
              ~ "unit (one of d, w, m, q, y), start and end, all non-negative"
          ),
          'period': none
      }) }}
    {% endif %}
  {% else %}
    {% set matches = modules.re.findall(
        '^(\\d*)([dwmqy])(\\d*)$', value | string
    ) %}
    {% if matches | length == 0 %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['mnemonic_is_invalid'],
              "'" ~ (value | string) ~ "' is not a valid feature period mnemonic; "
              ~ 'expected <start><d|w|m|q|y><end>, for example 52w0'
          ),
          'period': none
      }) }}
    {% endif %}
    {#- findall with three groups yields one tuple: (start, uom, end).
        An omitted count means zero, so 'm' is the current month. -#}
    {% set groups = matches[0] %}
    {% set start = (groups[0] | int) if groups[0] else 0 %}
    {% set uom = groups[1] %}
    {% set end = (groups[2] | int) if groups[2] else 0 %}
  {% endif %}

  {% if end > start %}
    {{ return({
        'ok': false,
        'error': jstark.error_message(
            jstark.error_codes()['end_greater_than_start'],
            'feature period end (' ~ end ~ ') is greater than start (' ~ start ~ ')'
        ),
        'period': none
    }) }}
  {% endif %}

  {{ return({
      'ok': true, 'error': none, 'period': jstark.feature_period(uom, start, end)
  }) }}

{% endmacro %}


{% macro parse_feature_period(value) %}
  {% set result = jstark.try_parse_feature_period(value) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['period']) }}
{% endmacro %}


{% macro parse_feature_periods(value) %}
  {% if value is none or (value is not string and value | length == 0) %}
    {{ return([jstark.parse_feature_period('52w0')]) }}
  {% endif %}
  {% set values = [value] if (value is string or value is mapping) else value %}
  {% set periods = [] %}
  {% for item in values %}
    {% do periods.append(jstark.parse_feature_period(item)) %}
  {% endfor %}
  {{ return(periods) }}
{% endmacro %}
```

Note on the `value is mapping` check in `parse_feature_periods`: a single `{'unit': ..., 'start': ..., 'end': ...}` dict is a period, not an iterable of periods, so it must be wrapped like a string is.

- [ ] **Step 5: Write the bounds calculator**

`macros/core/period/period_bounds.sql`:
```sql
{#
  Feature period bounds.

  Mirrors Feature.start_date / Feature.end_date in jstark
  (jstark/features/feature.py at 51d9083): step back `start` (or `end`) whole
  units from as_at, then snap to the first (or last) date of that unit. The
  end date is capped at as_at, so a period that includes the current,
  incomplete unit does not claim to cover the future.
#}

{% macro period_bounds(feature_period, as_at, first_day_of_week) %}

  {% set uom = feature_period['uom'] %}

  {#- start -#}
  {% if uom == 'd' %}
    {% set start_date = jstark.add_days(as_at, -feature_period['start']) %}
  {% elif uom == 'w' %}
    {% set start_date = jstark.first_date_in_week(
        jstark.add_weeks(as_at, -feature_period['start']), first_day_of_week
    ) %}
  {% elif uom == 'm' %}
    {% set start_date = jstark.first_date_in_month(
        jstark.add_months(as_at, -feature_period['start'])
    ) %}
  {% elif uom == 'q' %}
    {% set start_date = jstark.first_date_in_quarter(
        jstark.add_months(as_at, -feature_period['start'] * 3)
    ) %}
  {% else %}
    {% set start_date = jstark.first_date_in_year(
        jstark.add_months(as_at, -feature_period['start'] * 12)
    ) %}
  {% endif %}

  {#- end -#}
  {% if uom == 'd' %}
    {% set last_date_of_period = jstark.add_days(as_at, -feature_period['end']) %}
  {% elif uom == 'w' %}
    {% set last_date_of_period = jstark.last_date_in_week(
        jstark.add_weeks(as_at, -feature_period['end']), first_day_of_week
    ) %}
  {% elif uom == 'm' %}
    {% set last_date_of_period = jstark.last_date_in_month(
        jstark.add_months(as_at, -feature_period['end'])
    ) %}
  {% elif uom == 'q' %}
    {% set last_date_of_period = jstark.last_date_in_quarter(
        jstark.add_months(as_at, -feature_period['end'] * 3)
    ) %}
  {% else %}
    {% set last_date_of_period = jstark.last_date_in_year(
        jstark.add_months(as_at, -feature_period['end'] * 12)
    ) %}
  {% endif %}

  {{ return({
      'start_date': start_date,
      'end_date': jstark.min_date(last_date_of_period, as_at)
  }) }}

{% endmacro %}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: parse feature period mnemonics and resolve their bounds

'3m1' becomes {'uom': 'm', 'start': 3, 'end': 1, ...}, and a period plus an
as_at becomes the concrete date window base features filter on, capped at
as_at exactly as jstark caps it.

Parsing is split into a reporting try_parse_feature_period and a raising
parse_feature_period. Jinja has no try/except, so a non-raising variant is
the only way to assert on error messages.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Absolute period labels

When `use_absolute_periods=true` the period suffix names the calendar period rather than the offset: `gross_spend_2021oct_to_2021dec` instead of `gross_spend_3m1`. jstark produces `2021Oct-2021Dec`; a hyphen is illegal in an unquoted identifier, so this uses `_to_` and lowercases.

The week label is the fiddly part: jstark defines W01 of a year as the week beginning on the first occurrence of `first_day_of_week` on or before 1 January, which means a week starting in late December can belong to the following year.

**Files:**
- Create: `macros/core/period/period_label.sql`
- Modify: `macros/core/naming.sql` (add `public_column_name`)
- Test: `integration_tests/macros/tests/test_period_label.sql`
- Modify: `integration_tests/macros/jstark_test_suite.sql`

**Interfaces:**
- Consumes: `date_math.sql` (Task 3), `period_bounds.sql` (Task 4), `column_name` (Task 2).
- Produces:
  - `jstark.month_abbreviations()` → `['jan', 'feb', ..., 'dec']`.
  - `jstark.week_label(week_start_date, first_day_of_week)` → e.g. `'2021w52'`.
  - `jstark.absolute_period_label(feature_period, as_at, first_day_of_week)` → e.g. `'2021oct_to_2021dec'`, or the single label when start and end labels are equal.
  - `jstark.public_column_name(stem, feature_period, use_absolute_periods, as_at, first_day_of_week)` → the column name a user sees. Falls back to `jstark.column_name` when `use_absolute_periods` is false.

- [ ] **Step 1: Write the failing test**

`integration_tests/macros/tests/test_period_label.sql`:
```sql
{% macro jstark_test_period_label(failures) %}

  {% set d = modules.datetime.date %}

  {# --- week_label. W01 begins on the first `first_day_of_week` on or
         before Jan 1, so late-December weeks can belong to the next year. --- #}
  {% set week_cases = [
      [d(2021, 12, 20), 'Monday', '2021w52'],
      [d(2021, 12, 27), 'Monday', '2022w01'],
      [d(2020, 12, 28), 'Monday', '2021w01'],
      [d(2021, 1, 4),   'Monday', '2021w02'],
      [d(2021, 6, 7),   'Monday', '2021w24'],
      [d(2021, 12, 26), 'Sunday', '2021w52']
  ] %}
  {% for case in week_cases %}
    {% do jstark_assert_equal(
        failures,
        'week_label(' ~ jstark.date_string(case[0]) ~ ', ' ~ case[1] ~ ')',
        jstark.week_label(case[0], case[1]), case[2]
    ) %}
  {% endfor %}

  {# --- absolute_period_label, all as_at 2022-01-01, Monday weeks.
         Cross-checked against jstark's column_metadata at 51d9083, then
         lowercased with '-' replaced by '_to_'. --- #}
  {% set as_at = d(2022, 1, 1) %}
  {% set label_cases = [
      ['0d0',  '20220101'],
      ['1d1',  '20211231'],
      ['3d1',  '20211229_to_20211231'],
      ['1w1',  '2021w52'],
      ['52w0', '2021w01_to_2022w01'],
      ['0m0',  '2022jan'],
      ['3m1',  '2021oct_to_2021dec'],
      ['12m12','2021jan'],
      ['4q4',  '2021q1'],
      ['0q0',  '2022q1'],
      ['3q1',  '2021q2_to_2021q4'],
      ['1y1',  '2021'],
      ['0y0',  '2022'],
      ['2y1',  '2020_to_2021']
  ] %}
  {% for case in label_cases %}
    {% do jstark_assert_equal(
        failures, 'absolute_period_label(' ~ case[0] ~ ')',
        jstark.absolute_period_label(
            jstark.parse_feature_period(case[0]), as_at, 'Monday'
        ),
        case[1]
    ) %}
  {% endfor %}

  {# --- public_column_name switches on use_absolute_periods --- #}
  {% set fp = jstark.parse_feature_period('3m1') %}
  {% do jstark_assert_equal(
      failures, 'public_column_name relative',
      jstark.public_column_name('GrossSpend', fp, false, as_at, 'Monday'),
      'gross_spend_3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'public_column_name absolute',
      jstark.public_column_name('GrossSpend', fp, true, as_at, 'Monday'),
      'gross_spend_2021oct_to_2021dec'
  ) %}
  {% do jstark_assert_equal(
      failures, 'public_column_name absolute with a unit-infix override',
      jstark.public_column_name('BasketPeriods', fp, true, as_at, 'Monday'),
      'basket_months_2021oct_to_2021dec'
  ) %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_period_label(failures) %}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `macro 'week_label' not found in package 'jstark'`.

- [ ] **Step 3: Write the minimal implementation**

`macros/core/period/period_label.sql`:
```sql
{#
  Absolute period labels.

  With use_absolute_periods=true the column suffix names the calendar period
  covered rather than the offset from as_at, so a monthly feature reads
  gross_spend_2021oct_to_2021dec instead of gross_spend_3m1.

  jstark joins the two ends with a hyphen (2021Oct-2021Dec). A hyphen cannot
  appear in an unquoted SQL identifier, so this uses '_to_' and lowercases
  throughout.
#}

{% macro month_abbreviations() %}
  {{ return([
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
  ]) }}
{% endmacro %}


{% macro week_label(week_start_date, first_day_of_week) %}
  {#
    W01 of a year is the week beginning on the first occurrence of
    first_day_of_week on or before 1 January. A week that starts in late
    December therefore often belongs to the following year, which is why the
    next year's W01 has to be checked before the number is worked out.
    Mirrors Feature._week_label in jstark.
  #}
  {% set year = week_start_date.year %}
  {% set w01_start = jstark.first_date_in_week(
      modules.datetime.date(year, 1, 1), first_day_of_week
  ) %}
  {% set w01_start_next = jstark.first_date_in_week(
      modules.datetime.date(year + 1, 1, 1), first_day_of_week
  ) %}

  {% if week_start_date >= w01_start_next %}
    {% set label_year = year + 1 %}
    {% set reference = w01_start_next %}
  {% else %}
    {% set label_year = year %}
    {% set reference = w01_start %}
  {% endif %}

  {% set week_number = (week_start_date - reference).days // 7 + 1 %}
  {{ return((label_year | string) ~ 'w' ~ ('%02d' | format(week_number))) }}
{% endmacro %}


{% macro absolute_period_label(feature_period, as_at, first_day_of_week) %}

  {% set uom = feature_period['uom'] %}
  {% set start_offset = feature_period['start'] %}
  {% set end_offset = feature_period['end'] %}

  {% if uom == 'd' %}
    {% set start_label = jstark.date_string(
        jstark.add_days(as_at, -start_offset)
    ) | replace('-', '') %}
    {% set end_label = jstark.date_string(
        jstark.add_days(as_at, -end_offset)
    ) | replace('-', '') %}

  {% elif uom == 'w' %}
    {% set start_label = jstark.week_label(
        jstark.first_date_in_week(
            jstark.add_weeks(as_at, -start_offset), first_day_of_week
        ),
        first_day_of_week
    ) %}
    {% set end_label = jstark.week_label(
        jstark.first_date_in_week(
            jstark.add_weeks(as_at, -end_offset), first_day_of_week
        ),
        first_day_of_week
    ) %}

  {% elif uom == 'm' %}
    {% set start_month = jstark.add_months(as_at, -start_offset) %}
    {% set end_month = jstark.add_months(as_at, -end_offset) %}
    {% set months = jstark.month_abbreviations() %}
    {% set start_label = (start_month.year | string) ~ months[start_month.month - 1] %}
    {% set end_label = (end_month.year | string) ~ months[end_month.month - 1] %}

  {% elif uom == 'q' %}
    {% set start_quarter = jstark.add_months(as_at, -start_offset * 3) %}
    {% set end_quarter = jstark.add_months(as_at, -end_offset * 3) %}
    {% set start_label = (start_quarter.year | string)
                         ~ 'q' ~ jstark.quarter_of(start_quarter) %}
    {% set end_label = (end_quarter.year | string)
                       ~ 'q' ~ jstark.quarter_of(end_quarter) %}

  {% else %}
    {% set start_label = jstark.add_months(as_at, -start_offset * 12).year | string %}
    {% set end_label = jstark.add_months(as_at, -end_offset * 12).year | string %}
  {% endif %}

  {% if start_label == end_label %}
    {{ return(start_label) }}
  {% endif %}
  {{ return(start_label ~ '_to_' ~ end_label) }}

{% endmacro %}
```

Append to `macros/core/naming.sql`:
```sql
{% macro public_column_name(
    stem, feature_period, use_absolute_periods, as_at, first_day_of_week
) %}
  {% if not use_absolute_periods %}
    {{ return(jstark.column_name(stem, feature_period)) }}
  {% endif %}
  {{ return(
      jstark.feature_base_name(stem, feature_period['uom'])
      ~ '_'
      ~ jstark.absolute_period_label(feature_period, as_at, first_day_of_week)
  ) }}
{% endmacro %}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: label periods absolutely as well as relatively

use_absolute_periods=true names the calendar period covered rather than the
offset from as_at, so gross_spend_3m1 becomes
gross_spend_2021oct_to_2021dec. jstark joins the ends with a hyphen, which
is illegal in an unquoted identifier, so '_to_' is used instead.

week_label reproduces jstark's week numbering, where W01 begins on the first
first_day_of_week on or before 1 January and a late-December week can
therefore belong to the following year.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Warehouse portability seams

Four places where SQL differs between warehouses, each isolated behind one macro so that adding an adapter never means touching a feature definition:

| Seam | DuckDB (`default__`) | Snowflake | BigQuery | Postgres |
|---|---|---|---|---|
| `approx_count_distinct` | `approx_count_distinct(x)` | inherits default | inherits default | exact `count(distinct x)` + warning |
| `collect_set` | `list_sort(array_agg(distinct x) filter (where …))` | `array_sort(array_agg(distinct case when … end))` | `array_agg(distinct case when … end ignore nulls)` | `array_agg(distinct x order by x) filter (where …)` |
| `to_date` | `cast(x as date)` | inherits default | inherits default | inherits default |
| `safe_divide` | `cast(a as double) / nullif(b, 0)` | (uses `dbt.type_float()`) | " | " |

`safe_divide` exists because jstark's `try_divide` always returns a float, whereas a bare `/` between two integers truncates on Postgres and Redshift. `nullif(b, 0)` reproduces `try_divide`'s null-on-zero-denominator behaviour.

This task also adds `jstark.aggregate_sql`, the single place where an aggregator name becomes SQL. Every aggregator takes the same `(expression, window)` pair so the engine stays uniform even though `collect_set` needs both parts separately.

**Files:**
- Create: `macros/core/adapters/jstark_to_date.sql`, `macros/core/adapters/jstark_approx_count_distinct.sql`, `macros/core/adapters/jstark_collect_set.sql`, `macros/core/adapters/safe_divide.sql`, `macros/core/adapters/aggregate_sql.sql`
- Test: `integration_tests/macros/tests/test_adapters.sql`
- Modify: `integration_tests/macros/jstark_test_suite.sql`

**Interfaces:**
- Consumes: `jstark.error_codes()` (Task 1).
- Produces:
  - `jstark.to_date(expression)` → SQL string.
  - `jstark.approx_count_distinct(expression)` → SQL string.
  - `jstark.collect_set(expression, window)` → SQL string for the whole aggregate.
  - `jstark.safe_divide(numerator, denominator)` → SQL string.
  - `jstark.aggregators()` → the list of valid aggregator names.
  - `jstark.aggregate_sql(aggregator, expression, window)` → SQL string for the whole aggregate. `aggregator` is one of `sum`, `count`, `count_if`, `count_distinct`, `approx_count_distinct`, `max`, `min`, `collect_set`.
- Dispatch targets to override per adapter: `default__jstark_to_date`, `default__jstark_approx_count_distinct`, `default__jstark_collect_set` (plus `postgres__`, `snowflake__`, `bigquery__` variants where the table above differs).

- [ ] **Step 1: Write the failing test**

`integration_tests/macros/tests/test_adapters.sql`:
```sql
{% macro jstark_test_adapters(failures) %}

  {# These assertions pin the SQL text, so they are target-specific.
     Other adapters are covered by the warehouses.yml workflow actually
     running the queries rather than by string comparison. #}
  {% if target.type != 'duckdb' %}
    {% do log('Skipping adapter string assertions on ' ~ target.type, info=true) %}
    {{ return('') }}
  {% endif %}

  {% do jstark_assert_equal(
      failures, 'to_date',
      jstark.to_date('event_timestamp'), 'cast(event_timestamp as date)'
  ) %}

  {% do jstark_assert_equal(
      failures, 'approx_count_distinct',
      jstark.approx_count_distinct('customer'), 'approx_count_distinct(customer)'
  ) %}

  {% set window = "cast(event_timestamp as date) between date '2021-10-01' and date '2021-12-31'" %}

  {% do jstark_assert_equal(
      failures, 'collect_set',
      jstark.collect_set('allergen', window),
      'list_sort(array_agg(distinct allergen) filter (where ('
      ~ window ~ ') and allergen is not null))'
  ) %}

  {% do jstark_assert_equal(
      failures, 'safe_divide',
      jstark.safe_divide('gross_spend_3m1', 'basket_count_3m1'),
      'cast(gross_spend_3m1 as ' ~ dbt.type_float()
      ~ ') / nullif(basket_count_3m1, 0)'
  ) %}

  {# --- aggregate_sql covers every aggregator --- #}
  {% do jstark_assert_equal(
      failures, 'aggregate_sql(sum)',
      jstark.aggregate_sql('sum', 'gross_spend', window),
      'sum(case when ' ~ window ~ ' then gross_spend end)'
  ) %}
  {% do jstark_assert_equal(
      failures, 'aggregate_sql(count)',
      jstark.aggregate_sql('count', '1', window),
      'count(case when ' ~ window ~ ' then 1 end)'
  ) %}
  {% do jstark_assert_equal(
      failures, 'aggregate_sql(count_if)',
      jstark.aggregate_sql('count_if', 'count_1m1 > 0', window),
      'count(case when (' ~ window ~ ') and (count_1m1 > 0) then 1 end)'
  ) %}
  {% do jstark_assert_equal(
      failures, 'aggregate_sql(count_distinct)',
      jstark.aggregate_sql('count_distinct', 'basket', window),
      'count(distinct case when ' ~ window ~ ' then basket end)'
  ) %}
  {% do jstark_assert_equal(
      failures, 'aggregate_sql(approx_count_distinct)',
      jstark.aggregate_sql('approx_count_distinct', 'basket', window),
      'approx_count_distinct(case when ' ~ window ~ ' then basket end)'
  ) %}
  {% do jstark_assert_equal(
      failures, 'aggregate_sql(max)',
      jstark.aggregate_sql('max', 'net_spend', window),
      'max(case when ' ~ window ~ ' then net_spend end)'
  ) %}
  {% do jstark_assert_equal(
      failures, 'aggregate_sql(min)',
      jstark.aggregate_sql('min', 'net_spend', window),
      'min(case when ' ~ window ~ ' then net_spend end)'
  ) %}
  {% do jstark_assert_equal(
      failures, 'aggregate_sql(collect_set)',
      jstark.aggregate_sql('collect_set', 'allergen', window),
      jstark.collect_set('allergen', window)
  ) %}

  {# --- an unknown aggregator is rejected rather than silently emitted --- #}
  {% set bad = jstark.try_aggregate_sql('median', 'x', window) %}
  {% do jstark_assert_equal(
      failures, "try_aggregate_sql('median').ok", bad['ok'], false
  ) %}

  {# --- aggregators() is the single source of truth --- #}
  {% do jstark_assert_equal(
      failures, 'aggregators()',
      jstark.aggregators(),
      ['sum', 'count', 'count_if', 'count_distinct', 'approx_count_distinct',
       'max', 'min', 'collect_set']
  ) %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_adapters(failures) %}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `macro 'to_date' not found in package 'jstark'`.

- [ ] **Step 3: Write the three dispatch seams**

`macros/core/adapters/jstark_to_date.sql`:
```sql
{#
  Truncate a timestamp expression to a date.

  Every base feature filters on the date, not the timestamp, so this is
  applied to event_timestamp in the window predicate. `cast(x as date)` is
  ANSI and works everywhere tested so far; the seam exists so an adapter that
  spells it differently has somewhere to say so.
#}

{% macro to_date(expression) %}
  {{ return(adapter.dispatch('jstark_to_date', 'jstark')(expression)) }}
{% endmacro %}

{% macro default__jstark_to_date(expression) %}
  {{ return('cast(' ~ expression ~ ' as date)') }}
{% endmacro %}
```

`macros/core/adapters/jstark_approx_count_distinct.sql`:
```sql
{#
  Approximate distinct count.

  jstark uses Spark's approx_count_distinct (HyperLogLog). Most warehouses
  spell it the same way. Postgres has no built-in HLL, so it falls back to an
  exact count and warns: the values are still correct, just more expensive.
#}

{% macro approx_count_distinct(expression) %}
  {{ return(adapter.dispatch('jstark_approx_count_distinct', 'jstark')(expression)) }}
{% endmacro %}

{% macro default__jstark_approx_count_distinct(expression) %}
  {{ return('approx_count_distinct(' ~ expression ~ ')') }}
{% endmacro %}

{% macro postgres__jstark_approx_count_distinct(expression) %}
  {% do exceptions.warn(
      'jstark: postgres has no approx_count_distinct, so the Approx* features '
      ~ 'are computed exactly with count(distinct ...). Results are correct '
      ~ 'but slower than on warehouses with HyperLogLog support.'
  ) %}
  {{ return('count(distinct ' ~ expression ~ ')') }}
{% endmacro %}

{% macro redshift__jstark_approx_count_distinct(expression) %}
  {{ return('approximate count(distinct ' ~ expression ~ ')') }}
{% endmacro %}
```

`macros/core/adapters/jstark_collect_set.sql`:
```sql
{#
  Sorted array of the distinct non-null values in the window.

  jstark uses Spark's collect_set, which ignores nulls and returns values in
  an unspecified order. Ordering is imposed here so that results are
  comparable between runs and between warehouses.

  This is the least portable seam. DuckDB and Postgres take the window as a
  FILTER clause; Snowflake and BigQuery have no FILTER, so the window goes
  into a CASE expression and null exclusion is handled by the aggregate.

  The snowflake__ and bigquery__ variants are written from documentation and
  have not been run against a live warehouse. If you have credentials, the
  warehouses.yml workflow is the place to prove them.
#}

{% macro collect_set(expression, window) %}
  {{ return(adapter.dispatch('jstark_collect_set', 'jstark')(expression, window)) }}
{% endmacro %}

{% macro default__jstark_collect_set(expression, window) %}
  {{ return(
      'list_sort(array_agg(distinct ' ~ expression ~ ') filter (where ('
      ~ window ~ ') and ' ~ expression ~ ' is not null))'
  ) }}
{% endmacro %}

{% macro postgres__jstark_collect_set(expression, window) %}
  {{ return(
      'array_agg(distinct ' ~ expression ~ ' order by ' ~ expression
      ~ ') filter (where (' ~ window ~ ') and ' ~ expression ~ ' is not null)'
  ) }}
{% endmacro %}

{% macro snowflake__jstark_collect_set(expression, window) %}
  {{ return(
      'array_sort(array_agg(distinct case when ' ~ window ~ ' then '
      ~ expression ~ ' end))'
  ) }}
{% endmacro %}

{% macro bigquery__jstark_collect_set(expression, window) %}
  {{ return(
      'array_agg(distinct case when ' ~ window ~ ' then ' ~ expression
      ~ ' end ignore nulls order by case when ' ~ window ~ ' then '
      ~ expression ~ ' end)'
  ) }}
{% endmacro %}
```

- [ ] **Step 4: Write safe_divide**

`macros/core/adapters/safe_divide.sql`:
```sql
{#
  Division that behaves like Spark's try_divide.

  Two things need fixing relative to a bare `/`:
   - integer division truncates on Postgres and Redshift, whereas try_divide
     always returns a float, so the numerator is cast first;
   - dividing by zero raises on most warehouses, whereas try_divide returns
     null, so the denominator goes through nullif.
#}

{% macro safe_divide(numerator, denominator) %}
  {{ return(
      'cast(' ~ numerator ~ ' as ' ~ dbt.type_float() ~ ') / nullif('
      ~ denominator ~ ', 0)'
  ) }}
{% endmacro %}
```

- [ ] **Step 5: Write aggregate_sql**

`macros/core/adapters/aggregate_sql.sql`:
```sql
{#
  Turn an aggregator name plus an expression and a window predicate into a
  complete SQL aggregate.

  Every aggregator takes the same (expression, window) pair even though only
  collect_set needs them separately, which keeps the engine's rendering
  uniform: it never has to know which aggregator it is dealing with.

  count_if is Spark-specific; it becomes a count over a case that only yields
  a row when the expression is true.
#}

{% macro aggregators() %}
  {{ return([
      'sum', 'count', 'count_if', 'count_distinct', 'approx_count_distinct',
      'max', 'min', 'collect_set'
  ]) }}
{% endmacro %}


{% macro try_aggregate_sql(aggregator, expression, window) %}

  {% if aggregator not in jstark.aggregators() %}
    {{ return({
        'ok': false,
        'error': jstark.error_message(
            'unknown_aggregator',
            "'" ~ aggregator ~ "' is not a known aggregator; expected one of "
            ~ (jstark.aggregators() | join(', '))
        ),
        'sql': none
    }) }}
  {% endif %}

  {% set windowed = 'case when ' ~ window ~ ' then ' ~ expression ~ ' end' %}

  {% if aggregator == 'collect_set' %}
    {% set sql = jstark.collect_set(expression, window) %}
  {% elif aggregator == 'count_if' %}
    {% set sql = 'count(case when (' ~ window ~ ') and (' ~ expression
                 ~ ') then 1 end)' %}
  {% elif aggregator == 'count_distinct' %}
    {% set sql = 'count(distinct ' ~ windowed ~ ')' %}
  {% elif aggregator == 'approx_count_distinct' %}
    {% set sql = jstark.approx_count_distinct(windowed) %}
  {% else %}
    {% set sql = aggregator ~ '(' ~ windowed ~ ')' %}
  {% endif %}

  {{ return({'ok': true, 'error': none, 'sql': sql}) }}

{% endmacro %}


{% macro aggregate_sql(aggregator, expression, window) %}
  {% set result = jstark.try_aggregate_sql(aggregator, expression, window) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['sql']) }}
{% endmacro %}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: isolate warehouse differences behind four macros

to_date, approx_count_distinct and collect_set are adapter.dispatch seams;
safe_divide reproduces Spark's try_divide, which always returns a float and
yields null rather than raising on a zero denominator.

aggregate_sql is the single place an aggregator name becomes SQL. All eight
aggregators take the same (expression, window) pair, so the engine never has
to special-case collect_set even though it is the only one that needs the
window separately.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Input columns, `as_at` resolution and the feature context

Feature definitions never mention a raw column name directly; they read `ctx.cols['gross_spend']`. That indirection is what makes `column_map` work: a user whose column is called `sales_value` passes `column_map={'gross_spend': 'sales_value'}` and every feature follows.

This task also builds the **feature context** (`ctx`) — one dict per feature period, holding everything a feature definition needs. Every definition macro in Tasks 10-12 takes exactly one argument, and it is this.

**Files:**
- Create: `macros/core/context.sql`
- Test: `integration_tests/macros/tests/test_context.sql`
- Modify: `integration_tests/macros/jstark_test_suite.sql`

**Interfaces:**
- Consumes: `jstark.error_codes()`, `jstark.error_message()` (Task 1); `date_math.sql` (Task 3); `period_bounds.sql` (Task 4); `jstark.to_date()` (Task 6).
- Produces:
  - `jstark.canonical_columns()` → the list of canonical input column names.
  - `jstark.try_resolve_columns(column_map)` → `{'ok', 'error', 'cols'}`. `cols` maps every canonical name to the SQL expression to use for it; unmapped names map to themselves. An unknown key in `column_map` fails with `unknown_column_map_key`.
  - `jstark.resolve_columns(column_map)` → the `cols` dict; raises.
  - `jstark.resolve_as_at(as_at)` → `date`. Precedence: the argument, then `var('jstark_as_at')`, then the run date with a warning naming the var.
  - `jstark.date_literal(d)` → `"date '2021-10-01'"`.
  - `jstark.feature_context(feature_period, as_at, first_day_of_week, use_absolute_periods, cols, cuisines)` → the `ctx` dict:

    | Key | Type | Meaning |
    |---|---|---|
    | `period` | dict | the feature period (Task 4) |
    | `as_at` | date | resolved `as_at` |
    | `start_date`, `end_date` | date | window bounds |
    | `window` | string | SQL predicate restricting rows to the window |
    | `cols` | dict | canonical name → SQL expression |
    | `first_day_of_week` | string | e.g. `'Monday'` |
    | `use_absolute_periods` | bool | |
    | `cuisines` | list | mealkit only; `[]` elsewhere |

- [ ] **Step 1: Write the failing test**

`integration_tests/macros/tests/test_context.sql`:
```sql
{% macro jstark_test_context(failures) %}

  {% set d = modules.datetime.date %}

  {# --- canonical columns: the full set, in a fixed order --- #}
  {% do jstark_assert_equal(
      failures, 'canonical_columns()',
      jstark.canonical_columns(),
      ['event_timestamp', 'basket', 'order_id', 'store', 'channel', 'customer',
       'product', 'quantity', 'net_spend', 'gross_spend', 'discount',
       'cuisine', 'recipe', 'allergen']
  ) %}

  {# --- an empty column_map maps every canonical name to itself --- #}
  {% set cols = jstark.resolve_columns({}) %}
  {% do jstark_assert_equal(
      failures, 'resolve_columns({}).gross_spend', cols['gross_spend'], 'gross_spend'
  ) %}
  {% do jstark_assert_equal(
      failures, 'resolve_columns({}) is complete',
      cols | length, jstark.canonical_columns() | length
  ) %}

  {# --- a mapped name is substituted, unmapped names are untouched --- #}
  {% set mapped = jstark.resolve_columns(
      {'gross_spend': 'sales_value', 'event_timestamp': 'txn_ts'}
  ) %}
  {% do jstark_assert_equal(
      failures, 'column_map substitutes gross_spend',
      mapped['gross_spend'], 'sales_value'
  ) %}
  {% do jstark_assert_equal(
      failures, 'column_map substitutes event_timestamp',
      mapped['event_timestamp'], 'txn_ts'
  ) %}
  {% do jstark_assert_equal(
      failures, 'column_map leaves others alone', mapped['quantity'], 'quantity'
  ) %}

  {# --- an unknown key is a typo, not a new column --- #}
  {% set bad = jstark.try_resolve_columns({'grosspend': 'sales_value'}) %}
  {% do jstark_assert_equal(failures, 'try_resolve_columns bad key ok', bad['ok'], false) %}
  {% do jstark_assert_equal(
      failures, 'try_resolve_columns bad key error',
      bad['error'],
      jstark.error_message(
          jstark.error_codes()['unknown_column_map_key'],
          "'grosspend' is not a jstark input column; expected one of "
          ~ (jstark.canonical_columns() | join(', '))
      )
  ) %}

  {# --- date literals --- #}
  {% do jstark_assert_equal(
      failures, 'date_literal', jstark.date_literal(d(2021, 10, 1)),
      "date '2021-10-01'"
  ) %}

  {# --- as_at precedence: an explicit argument always wins --- #}
  {% do jstark_assert_equal(
      failures, 'resolve_as_at(explicit date)',
      jstark.resolve_as_at(d(2022, 1, 1)), d(2022, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      failures, 'resolve_as_at(explicit string)',
      jstark.resolve_as_at('2022-01-01'), d(2022, 1, 1)
  ) %}

  {# --- the context stitches period, window and columns together --- #}
  {% set ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), d(2022, 1, 1), 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.period.mnemonic', ctx['period']['mnemonic'], '3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.start_date', ctx['start_date'], d(2021, 10, 1)
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.end_date', ctx['end_date'], d(2021, 12, 31)
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.window', ctx['window'],
      jstark.to_date('event_timestamp')
      ~ " between date '2021-10-01' and date '2021-12-31'"
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.cols passes through', ctx['cols']['gross_spend'], 'gross_spend'
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.first_day_of_week', ctx['first_day_of_week'], 'Monday'
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.use_absolute_periods', ctx['use_absolute_periods'], false
  ) %}
  {% do jstark_assert_equal(failures, 'ctx.cuisines', ctx['cuisines'], []) %}

  {# --- the window follows a remapped timestamp column --- #}
  {% set remapped_ctx = jstark.feature_context(
      jstark.parse_feature_period('0d0'), d(2022, 1, 1), 'Monday', false, mapped, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.window honours column_map', remapped_ctx['window'],
      jstark.to_date('txn_ts')
      ~ " between date '2022-01-01' and date '2022-01-01'"
  ) %}

  {# --- first_day_of_week defaults to Monday --- #}
  {% set default_dow_ctx = jstark.feature_context(
      jstark.parse_feature_period('0w0'), d(2022, 1, 1), none, false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx.first_day_of_week defaults',
      default_dow_ctx['first_day_of_week'], 'Monday'
  ) %}
  {% do jstark_assert_equal(
      failures, 'ctx bounds use the default first_day_of_week',
      default_dow_ctx['start_date'], d(2021, 12, 27)
  ) %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_context(failures) %}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `macro 'canonical_columns' not found in package 'jstark'`.

- [ ] **Step 3: Write the minimal implementation**

`macros/core/context.sql`:
```sql
{#
  Input columns, as_at resolution, and the per-period feature context.

  Feature definitions never name a raw column; they read ctx.cols['gross_spend'].
  That is what makes column_map work without every definition knowing about it.

  Column references are emitted unquoted so that warehouse case-folding
  applies: Snowflake stores gross_spend as GROSS_SPEND and resolves the
  unquoted lower-case reference to it, whereas "gross_spend" would not match.
  This is also why the canonical names avoid `timestamp` (Postgres parses
  `cast(timestamp as date)` as a type name) and `order` (reserved everywhere).
#}

{% macro canonical_columns() %}
  {{ return([
      'event_timestamp', 'basket', 'order_id', 'store', 'channel', 'customer',
      'product', 'quantity', 'net_spend', 'gross_spend', 'discount',
      'cuisine', 'recipe', 'allergen'
  ]) }}
{% endmacro %}


{% macro try_resolve_columns(column_map) %}
  {% set canonical = jstark.canonical_columns() %}
  {% set overrides = column_map if column_map else {} %}

  {% for key in overrides %}
    {% if key not in canonical %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['unknown_column_map_key'],
              "'" ~ key ~ "' is not a jstark input column; expected one of "
              ~ (canonical | join(', '))
          ),
          'cols': none
      }) }}
    {% endif %}
  {% endfor %}

  {% set cols = {} %}
  {% for name in canonical %}
    {% do cols.update({name: overrides.get(name, name)}) %}
  {% endfor %}

  {{ return({'ok': true, 'error': none, 'cols': cols}) }}
{% endmacro %}


{% macro resolve_columns(column_map) %}
  {% set result = jstark.try_resolve_columns(column_map) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['cols']) }}
{% endmacro %}


{% macro resolve_as_at(as_at) %}
  {#
    Precedence: the argument, then the jstark_as_at var, then the run date.

    Falling back to the run date makes features non-deterministic between
    runs, which is almost never what someone wants in a scheduled job, so the
    fallback warns and names the var to set.
  #}
  {% if as_at is not none %}
    {{ return(jstark.as_date(as_at)) }}
  {% endif %}

  {% set from_var = var('jstark_as_at', none) %}
  {% if from_var is not none %}
    {{ return(jstark.as_date(from_var)) }}
  {% endif %}

  {% do exceptions.warn(
      'jstark: no as_at was supplied, so features are being generated as at the '
      ~ 'run date. Pass as_at=... or set the jstark_as_at var to make results '
      ~ 'reproducible.'
  ) %}
  {{ return(jstark.as_date(run_started_at)) }}
{% endmacro %}


{% macro date_literal(d) %}
  {{ return("date '" ~ jstark.date_string(d) ~ "'") }}
{% endmacro %}


{% macro feature_context(
    feature_period, as_at, first_day_of_week, use_absolute_periods, cols, cuisines
) %}
  {% set day_of_week = first_day_of_week if first_day_of_week else 'Monday' %}
  {#- validate eagerly so a typo fails before any SQL is emitted -#}
  {% do jstark.weekday_index(day_of_week) %}

  {% set bounds = jstark.period_bounds(feature_period, as_at, day_of_week) %}
  {% set event_date = jstark.to_date(cols['event_timestamp']) %}

  {{ return({
      'period': feature_period,
      'as_at': as_at,
      'start_date': bounds['start_date'],
      'end_date': bounds['end_date'],
      'window': event_date
                ~ ' between ' ~ jstark.date_literal(bounds['start_date'])
                ~ ' and ' ~ jstark.date_literal(bounds['end_date']),
      'cols': cols,
      'first_day_of_week': day_of_week,
      'use_absolute_periods': use_absolute_periods,
      'cuisines': cuisines if cuisines else []
  }) }}
{% endmacro %}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: resolve input columns, as_at and the per-period feature context

Feature definitions read ctx.cols['gross_spend'] rather than naming a column
directly, which is what lets column_map redirect an input column without any
definition knowing about it. An unrecognised column_map key is treated as a
typo and rejected.

as_at falls back to the jstark_as_at var and then to the run date, warning in
the last case because a run-date default makes features irreproducible.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: The registry, dependency closure and topological levelling

This is the heart of the package and it contains no SQL emission at all — it works out *what* to compute and *in what order*, leaving Task 9 to render it.

Three things make this harder than a two-stage aggregate-then-derive shape:

1. **Derived features depend on other derived features.** `CyclesSinceLastPurchase` needs `AvgPurchaseCycle`, which needs base aggregates. SQL cannot reference a `select`-list alias from the same `select`, so each dependency level needs its own CTE.
2. **Some dependencies are in a different period.** `BasketPeriods` for `3m1` counts how many of the months `3m3`, `2m2`, `1m1` had activity, so the closure has to pull in features at periods the user never asked for.
3. **Those extra features must not appear in the output.** They are computed in the base CTE and dropped by the final projection.

So a dependency is a `[stem, period]` pair, and each pair is identified by its internal column name — which is unique by construction.

The `'test'` generator introduced here is a three-feature fixture the package's own tests use. It is documented as not part of the public API, and it is what lets the engine be tested before any real feature exists.

**Files:**
- Create: `macros/core/registry.sql`
- Create: `macros/core/features/test_features.sql`
- Test: `integration_tests/macros/tests/test_registry.sql`
- Modify: `integration_tests/macros/jstark_test_suite.sql`

**Interfaces:**
- Consumes: Tasks 1-7 in full.
- Produces:
  - A **feature definition** dict — the normative shape every definition macro in Tasks 10-12 returns:

    | Key | Base | Derived | Meaning |
    |---|---|---|---|
    | `stem` | required | required | CamelCase identity |
    | `kind` | `'base'` | `'derived'` | |
    | `aggregator` | required | absent | one of `jstark.aggregators()` |
    | `expression` | required | required | SQL. Base: the value aggregated. Derived: the whole expression. |
    | `default` | required | required | SQL literal used when the window is empty; `'null'` means emit the expression bare |
    | `depends_on` | absent | required | list of `[stem, period]` pairs |
    | `required_columns` | required | absent | canonical input column names |
    | `description_subject` | required | required | prefixed to `" between <start> and <end>"` |
    | `commentary` | required | required | free text carried into the catalogue and docs |

  - `jstark.generators()` → `['core', 'grocery', 'mealkit', 'test']`.
  - `jstark.catalogue(generator, ctx)` → ordered dict of stem → definition for that generator at that period.
  - `jstark.single_unit_periods(period)` → `[period, ...]` one per whole unit in the window, ascending by offset. For `3m1`: `1m1`, `2m2`, `3m3`.
  - `jstark.dependency_key(stem, period)` → `jstark.column_name(stem, period)`.
  - `jstark.build_plan(generator, feature_stems, periods, as_at, first_day_of_week, use_absolute_periods, cols, cuisines)` → `{'levels': [[item, ...], ...], 'requested': [item, ...]}`.
    A **plan item** is `{'key', 'stem', 'period', 'definition', 'ctx', 'requested', 'level'}`. `levels[0]` is every base feature; `levels[n]` holds derived features whose deepest dependency is in `levels[n-1]`. `requested` is ordered stem-outer, period-inner.

- [ ] **Step 1: Write the failing test**

`integration_tests/macros/tests/test_registry.sql`:
```sql
{% macro jstark_test_registry(failures) %}

  {% set d = modules.datetime.date %}
  {% set as_at = d(2022, 1, 1) %}
  {% set cols = jstark.resolve_columns({}) %}

  {# --- single_unit_periods expands a window into whole units --- #}
  {% do jstark_assert_equal(
      failures, 'single_unit_periods(3m1)',
      jstark.single_unit_periods(jstark.parse_feature_period('3m1'))
        | map(attribute='mnemonic') | list,
      ['1m1', '2m2', '3m3']
  ) %}
  {% do jstark_assert_equal(
      failures, 'single_unit_periods(0d0)',
      jstark.single_unit_periods(jstark.parse_feature_period('0d0'))
        | map(attribute='mnemonic') | list,
      ['0d0']
  ) %}
  {% do jstark_assert_equal(
      failures, 'single_unit_periods(2w0)',
      jstark.single_unit_periods(jstark.parse_feature_period('2w0'))
        | map(attribute='mnemonic') | list,
      ['0w0', '1w1', '2w2']
  ) %}

  {# --- the test catalogue is the fixture the rest of this group uses --- #}
  {% set ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  ) %}
  {% set cat = jstark.catalogue('test', ctx) %}
  {% do jstark_assert_equal(
      failures, 'test catalogue stems',
      cat.keys() | list, ['TestSpend', 'TestBasketCount', 'TestSpendPerBasket',
                          'TestSpendPerBasketPerBasket', 'TestActiveMonths']
  ) %}
  {% do jstark_assert_equal(
      failures, 'TestSpend is base', cat['TestSpend']['kind'], 'base'
  ) %}
  {% do jstark_assert_equal(
      failures, 'TestSpendPerBasket is derived',
      cat['TestSpendPerBasket']['kind'], 'derived'
  ) %}

  {# --- generators are enumerated in one place --- #}
  {% do jstark_assert_equal(
      failures, 'generators()',
      jstark.generators(), ['core', 'grocery', 'mealkit', 'test']
  ) %}

  {# --- an unknown stem names the valid ones --- #}
  {% set bad = jstark.try_build_plan(
      'test', ['NoSuchFeature'], [jstark.parse_feature_period('3m1')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(failures, 'unknown stem ok', bad['ok'], false) %}
  {% do jstark_assert_equal(
      failures, 'unknown stem error', bad['error'],
      jstark.error_message(
          jstark.error_codes()['feature_not_found'],
          "['NoSuchFeature'] not found. Valid feature stems for the test "
          ~ 'generator are: TestActiveMonths, TestBasketCount, TestSpend, '
          ~ 'TestSpendPerBasket, TestSpendPerBasketPerBasket'
      )
  ) %}

  {# --- a base-only request produces one level --- #}
  {% set plan = jstark.build_plan(
      'test', ['TestSpend'], [jstark.parse_feature_period('3m1')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(failures, 'base-only levels', plan['levels'] | length, 1) %}
  {% do jstark_assert_equal(
      failures, 'base-only level 0 keys',
      plan['levels'][0] | map(attribute='key') | list, ['test_spend_3m1']
  ) %}
  {% do jstark_assert_equal(
      failures, 'base-only requested',
      plan['requested'] | map(attribute='key') | list, ['test_spend_3m1']
  ) %}

  {# --- a two-deep derived chain produces three levels, and pulls in
         dependencies the caller never asked for --- #}
  {% set plan2 = jstark.build_plan(
      'test', ['TestSpendPerBasketPerBasket'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(failures, 'chain levels', plan2['levels'] | length, 3) %}
  {% do jstark_assert_equal(
      failures, 'chain level 0',
      plan2['levels'][0] | map(attribute='key') | sort | list,
      ['test_basket_count_3m1', 'test_spend_3m1']
  ) %}
  {% do jstark_assert_equal(
      failures, 'chain level 1',
      plan2['levels'][1] | map(attribute='key') | list, ['test_spend_per_basket_3m1']
  ) %}
  {% do jstark_assert_equal(
      failures, 'chain level 2',
      plan2['levels'][2] | map(attribute='key') | list,
      ['test_spend_per_basket_per_basket_3m1']
  ) %}
  {% do jstark_assert_equal(
      failures, 'chain requested is only what was asked for',
      plan2['requested'] | map(attribute='key') | list,
      ['test_spend_per_basket_per_basket_3m1']
  ) %}
  {% do jstark_assert_equal(
      failures, 'pulled-in dependencies are not requested',
      plan2['levels'][0] | selectattr('requested') | list | length, 0
  ) %}

  {# --- a cross-period dependency pulls in sub-period base features --- #}
  {% set plan3 = jstark.build_plan(
      'test', ['TestActiveMonths'], [jstark.parse_feature_period('3m1')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'cross-period level 0',
      plan3['levels'][0] | map(attribute='key') | sort | list,
      ['test_basket_count_1m1', 'test_basket_count_2m2', 'test_basket_count_3m3']
  ) %}
  {% do jstark_assert_equal(
      failures, 'cross-period level 1',
      plan3['levels'][1] | map(attribute='key') | list, ['test_active_months_3m1']
  ) %}
  {% do jstark_assert_equal(
      failures, 'cross-period dependency contexts differ',
      plan3['levels'][0][0]['ctx']['period']['mnemonic'] !=
        plan3['levels'][1][0]['ctx']['period']['mnemonic'],
      true
  ) %}

  {# --- a shared dependency is computed once, not twice --- #}
  {% set plan4 = jstark.build_plan(
      'test', ['TestSpendPerBasket', 'TestSpendPerBasketPerBasket'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'shared dependency deduplicated',
      plan4['levels'][0] | map(attribute='key') | sort | list,
      ['test_basket_count_3m1', 'test_spend_3m1']
  ) %}
  {% do jstark_assert_equal(
      failures, 'a dependency that is also requested is marked requested',
      plan4['levels'][1] | selectattr('requested') | map(attribute='key') | list,
      ['test_spend_per_basket_3m1']
  ) %}

  {# --- requested order is stem-outer, period-inner --- #}
  {% set plan5 = jstark.build_plan(
      'test', ['TestSpend', 'TestBasketCount'],
      [jstark.parse_feature_period('3m1'), jstark.parse_feature_period('0d0')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'requested order',
      plan5['requested'] | map(attribute='key') | list,
      ['test_spend_3m1', 'test_spend_0d0',
       'test_basket_count_3m1', 'test_basket_count_0d0']
  ) %}

  {# --- an empty feature_stems means every feature, in catalogue order --- #}
  {% set plan6 = jstark.build_plan(
      'test', [], [jstark.parse_feature_period('3m1')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'no feature_stems means all of them, in catalogue order',
      plan6['requested'] | map(attribute='stem') | list,
      ['TestSpend', 'TestBasketCount', 'TestSpendPerBasket',
       'TestSpendPerBasketPerBasket', 'TestActiveMonths']
  ) %}

  {# --- feature_stems order does not affect column order --- #}
  {% set plan7 = jstark.build_plan(
      'test', ['TestBasketCount', 'TestSpend'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'column order follows the catalogue, not the request',
      plan7['requested'] | map(attribute='stem') | list,
      ['TestSpend', 'TestBasketCount']
  ) %}

  {# --- every derived expression only references declared dependencies --- #}
  {% do jstark_assert_equal(
      failures, 'derived expressions declare their dependencies',
      jstark.undeclared_dependencies(plan6), []
  ) %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_registry(failures) %}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `macro 'single_unit_periods' not found in package 'jstark'`.

- [ ] **Step 3: Write the test-generator fixture**

`macros/core/features/test_features.sql`:
```sql
{#
  Fixture features used by jstark's own test suite.

  NOT part of the public API. They exist so that the engine — dependency
  closure, levelling, CTE emission — can be tested against a catalogue small
  enough to assert on exhaustively, independently of the real feature
  definitions.

  Between them they cover every shape the engine has to handle: a base
  aggregate, a derived feature over two base aggregates, a derived feature
  over another derived feature, and a derived feature that depends on base
  aggregates from periods other than its own.
#}

{% macro register_test_features(definitions, ctx) %}

  {% do definitions.update({'TestSpend': {
      'stem': 'TestSpend',
      'kind': 'base',
      'aggregator': 'sum',
      'expression': ctx['cols']['gross_spend'],
      'default': '0.0',
      'required_columns': ['event_timestamp', 'gross_spend'],
      'description_subject': 'Sum of TestSpend',
      'commentary': 'Test fixture. Not a real feature.'
  }}) %}

  {% do definitions.update({'TestBasketCount': {
      'stem': 'TestBasketCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['basket'],
      'default': '0',
      'required_columns': ['event_timestamp', 'basket'],
      'description_subject': 'Distinct count of test Baskets',
      'commentary': 'Test fixture. Not a real feature.'
  }}) %}

  {% do definitions.update({'TestSpendPerBasket': {
      'stem': 'TestSpendPerBasket',
      'kind': 'derived',
      'depends_on': [
          ['TestSpend', ctx['period']], ['TestBasketCount', ctx['period']]
      ],
      'expression': jstark.safe_divide(
          jstark.column_name('TestSpend', ctx['period']),
          jstark.column_name('TestBasketCount', ctx['period'])
      ),
      'default': 'null',
      'description_subject': 'Test spend per basket',
      'commentary': 'Test fixture. Not a real feature.'
  }}) %}

  {% do definitions.update({'TestSpendPerBasketPerBasket': {
      'stem': 'TestSpendPerBasketPerBasket',
      'kind': 'derived',
      'depends_on': [
          ['TestSpendPerBasket', ctx['period']], ['TestBasketCount', ctx['period']]
      ],
      'expression': jstark.safe_divide(
          jstark.column_name('TestSpendPerBasket', ctx['period']),
          jstark.column_name('TestBasketCount', ctx['period'])
      ),
      'default': 'null',
      'description_subject': 'Test spend per basket per basket',
      'commentary': 'Test fixture exercising a derived-on-derived dependency.'
  }}) %}

  {#- a derived feature whose dependencies live in other periods -#}
  {% set sub_periods = jstark.single_unit_periods(ctx['period']) %}
  {% set terms = [] %}
  {% set deps = [] %}
  {% for sub in sub_periods %}
    {% set column = jstark.column_name('TestBasketCount', sub) %}
    {% do terms.append('case when ' ~ column ~ ' > 0 then 1 else 0 end') %}
    {% do deps.append(['TestBasketCount', sub]) %}
  {% endfor %}
  {% do definitions.update({'TestActiveMonths': {
      'stem': 'TestActiveMonths',
      'kind': 'derived',
      'depends_on': deps,
      'expression': terms | join(' + '),
      'default': 'null',
      'description_subject': 'Number of active test periods',
      'commentary': 'Test fixture exercising a cross-period dependency.'
  }}) %}

{% endmacro %}
```

- [ ] **Step 4: Write the registry**

`macros/core/registry.sql`:
```sql
{#
  The registry: what to compute, and in what order.

  No SQL is emitted here. build_plan resolves the requested feature stems and
  periods into a dependency closure, then levels that closure topologically so
  that Task 9's renderer can emit one CTE per level. Levelling is necessary
  because SQL cannot reference a select-list alias from the same select, and
  jstark has derived features that depend on other derived features.

  A dependency is a [stem, period] pair, not just a stem: BasketPeriods for
  3m1 depends on activity in each of 3m3, 2m2 and 1m1. Those pulled-in
  features are computed but not projected, which is why each plan item carries
  a `requested` flag.
#}

{% macro generators() %}
  {{ return(['core', 'grocery', 'mealkit', 'test']) }}
{% endmacro %}


{% macro catalogue(generator, ctx) %}
  {#
    Built with explicit branches rather than by looking up a macro by name:
    dbt's Jinja does not expose the macro namespace for dynamic dispatch, and
    an explicit list is easier to read anyway.
  #}
  {% set definitions = {} %}

  {% if generator == 'test' %}
    {% do jstark.register_test_features(definitions, ctx) %}
    {{ return(definitions) }}
  {% endif %}

  {% if generator not in jstark.generators() %}
    {% do jstark.raise_error(
        'unknown_generator',
        "'" ~ generator ~ "' is not a jstark generator; expected one of "
        ~ (jstark.generators() | join(', '))
    ) %}
  {% endif %}

  {#- Tasks 10-12 replace this branch body with real registrations. -#}
  {% do jstark.register_core_features(definitions, ctx, generator) %}
  {% if generator == 'grocery' %}
    {% do jstark.register_grocery_features(definitions, ctx) %}
  {% elif generator == 'mealkit' %}
    {% do jstark.register_mealkit_features(definitions, ctx) %}
  {% endif %}

  {{ return(definitions) }}
{% endmacro %}


{% macro single_unit_periods(feature_period) %}
  {#- 3m1 -> 1m1, 2m2, 3m3: one whole unit each, ascending by offset -#}
  {% set periods = [] %}
  {% for n in range(feature_period['end'], feature_period['start'] + 1) %}
    {% do periods.append(jstark.feature_period(feature_period['uom'], n, n)) %}
  {% endfor %}
  {{ return(periods) }}
{% endmacro %}


{% macro dependency_key(stem, period) %}
  {{ return(jstark.column_name(stem, period)) }}
{% endmacro %}


{% macro ensure_catalogue(generator, period, ctx_args, contexts, catalogues) %}
  {% if period['mnemonic'] not in catalogues %}
    {% set ctx = jstark.feature_context(
        period,
        ctx_args['as_at'],
        ctx_args['first_day_of_week'],
        ctx_args['use_absolute_periods'],
        ctx_args['cols'],
        ctx_args['cuisines']
    ) %}
    {% do contexts.update({period['mnemonic']: ctx}) %}
    {% do catalogues.update({
        period['mnemonic']: jstark.catalogue(generator, ctx)
    }) %}
  {% endif %}
{% endmacro %}


{% macro expand_deps(
    generator, stem, period, ctx_args, contexts, catalogues, resolved,
    requested, depth
) %}
  {#
    Recursive rather than iterative: a `{% set %}` inside a `{% for %}` does
    not survive the loop in Jinja, so accumulation has to happen by mutating
    the `resolved` dict that the caller owns.
  #}
  {% if depth > 20 %}
    {{ exceptions.raise_compiler_error(
        'jstark: feature dependency resolution exceeded 20 levels while '
        ~ 'resolving ' ~ stem ~ ' at ' ~ period['mnemonic']
        ~ '. This usually means a circular dependency.'
    ) }}
  {% endif %}

  {% do jstark.ensure_catalogue(generator, period, ctx_args, contexts, catalogues) %}
  {% set cat = catalogues[period['mnemonic']] %}

  {% if stem not in cat %}
    {% do jstark.raise_error(
        jstark.error_codes()['feature_not_found'],
        "['" ~ stem ~ "'] not found. Valid feature stems for the "
        ~ generator ~ ' generator are: ' ~ (cat.keys() | sort | join(', '))
    ) %}
  {% endif %}

  {% set key = jstark.dependency_key(stem, period) %}

  {% if key in resolved %}
    {% if requested %}
      {% do resolved[key].update({'requested': true}) %}
    {% endif %}
    {{ return('') }}
  {% endif %}

  {#- inserted before recursing so that a cycle terminates here rather than
      recursing forever; the cycle itself is reported by assign_levels -#}
  {% do resolved.update({key: {
      'key': key,
      'stem': stem,
      'period': period,
      'definition': cat[stem],
      'ctx': contexts[period['mnemonic']],
      'requested': requested
  }}) %}

  {% for dep in cat[stem].get('depends_on', []) %}
    {% do jstark.expand_deps(
        generator, dep[0], dep[1], ctx_args, contexts, catalogues, resolved,
        false, depth + 1
    ) %}
  {% endfor %}
{% endmacro %}


{% macro assign_levels(resolved) %}
  {#
    Base features are level 0. A derived feature sits one level below its
    deepest dependency. Repeated passes rather than a recursive walk, because
    the number of levels is tiny (grocery bottoms out at 2) and a pass that
    assigns nothing is exactly the cycle-detection signal.
  #}
  {% set levels = {} %}
  {% for key, item in resolved.items() %}
    {% if item['definition']['kind'] == 'base' %}
      {% do levels.update({key: 0}) %}
    {% endif %}
  {% endfor %}

  {% for _ in range(resolved | length + 1) %}
    {% for key, item in resolved.items() %}
      {% if key not in levels %}
        {% set state = namespace(ready=true, deepest=0) %}
        {% for dep in item['definition'].get('depends_on', []) %}
          {% set dep_key = jstark.dependency_key(dep[0], dep[1]) %}
          {% if dep_key not in levels %}
            {% set state.ready = false %}
          {% elif levels[dep_key] > state.deepest %}
            {% set state.deepest = levels[dep_key] %}
          {% endif %}
        {% endfor %}
        {% if state.ready %}
          {% do levels.update({key: state.deepest + 1}) %}
        {% endif %}
      {% endif %}
    {% endfor %}
  {% endfor %}

  {% if levels | length != resolved | length %}
    {% set stuck = [] %}
    {% for key in resolved %}
      {% if key not in levels %}
        {% do stuck.append(key) %}
      {% endif %}
    {% endfor %}
    {{ exceptions.raise_compiler_error(
        'jstark: circular feature dependency involving ' ~ (stuck | sort | join(', '))
    ) }}
  {% endif %}

  {{ return(levels) }}
{% endmacro %}


{% macro try_build_plan(
    generator, feature_stems, periods, as_at, first_day_of_week,
    use_absolute_periods, cols, cuisines
) %}

  {% set ctx_args = {
      'as_at': as_at,
      'first_day_of_week': first_day_of_week,
      'use_absolute_periods': use_absolute_periods,
      'cols': cols,
      'cuisines': cuisines
  } %}

  {% set contexts = {} %}
  {% set catalogues = {} %}
  {% do jstark.ensure_catalogue(
      generator, periods[0], ctx_args, contexts, catalogues
  ) %}
  {% set available = catalogues[periods[0]['mnemonic']] %}

  {% set requested_stems = feature_stems if feature_stems else [] %}
  {% set missing = [] %}
  {% for stem in requested_stems %}
    {% if stem not in available %}
      {% do missing.append(stem) %}
    {% endif %}
  {% endfor %}
  {% if missing | length > 0 %}
    {{ return({
        'ok': false,
        'error': jstark.error_message(
            jstark.error_codes()['feature_not_found'],
            (missing | sort | string) ~ ' not found. Valid feature stems for the '
            ~ generator ~ ' generator are: '
            ~ (available.keys() | sort | join(', '))
        ),
        'plan': none
    }) }}
  {% endif %}

  {#- catalogue order, not request order, so column order is stable -#}
  {% set target_stems = [] %}
  {% for stem in available %}
    {% if requested_stems | length == 0 or stem in requested_stems %}
      {% do target_stems.append(stem) %}
    {% endif %}
  {% endfor %}

  {% set resolved = {} %}
  {% set requested_items = [] %}
  {% for stem in target_stems %}
    {% for period in periods %}
      {% do jstark.expand_deps(
          generator, stem, period, ctx_args, contexts, catalogues, resolved,
          true, 0
      ) %}
      {% do requested_items.append(resolved[jstark.dependency_key(stem, period)]) %}
    {% endfor %}
  {% endfor %}

  {% set levels = jstark.assign_levels(resolved) %}
  {% set depth = (levels.values() | list | max) if levels else 0 %}

  {% set buckets = [] %}
  {% for level in range(0, depth + 1) %}
    {% set bucket = [] %}
    {% for key, item in resolved.items() %}
      {% if levels[key] == level %}
        {% do item.update({'level': level}) %}
        {% do bucket.append(item) %}
      {% endif %}
    {% endfor %}
    {% do buckets.append(bucket) %}
  {% endfor %}

  {{ return({
      'ok': true,
      'error': none,
      'plan': {'levels': buckets, 'requested': requested_items}
  }) }}

{% endmacro %}


{% macro build_plan(
    generator, feature_stems, periods, as_at, first_day_of_week,
    use_absolute_periods, cols, cuisines
) %}
  {% set result = jstark.try_build_plan(
      generator, feature_stems, periods, as_at, first_day_of_week,
      use_absolute_periods, cols, cuisines
  ) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['plan']) }}
{% endmacro %}


{% macro undeclared_dependencies(plan) %}
  {#
    Guards against a derived feature referencing a column it did not declare
    in depends_on, which would compile to "column not found" at run time on
    one warehouse and silently resolve to something else on another.

    Every derived expression is scanned for identifiers that look like a
    feature column — a name ending in a period mnemonic — and each one must
    appear in that feature's declared dependencies.
  #}
  {% set problems = [] %}
  {% for level in plan['levels'] %}
    {% for item in level %}
      {% if item['definition']['kind'] == 'derived' %}
        {% set declared = [] %}
        {% for dep in item['definition']['depends_on'] %}
          {% do declared.append(jstark.dependency_key(dep[0], dep[1])) %}
        {% endfor %}
        {% set referenced = modules.re.findall(
            '[a-z][a-z0-9_]*_\\d+[dwmqy]\\d+', item['definition']['expression']
        ) %}
        {% for name in referenced %}
          {% if name not in declared %}
            {% do problems.append(item['key'] ~ ' references ' ~ name
                                  ~ ' but does not declare it in depends_on') %}
          {% endif %}
        {% endfor %}
      {% endif %}
    {% endfor %}
  {% endfor %}
  {{ return(problems | unique | list) }}
{% endmacro %}
```

- [ ] **Step 5: Stub the not-yet-written registration macros**

`jstark.catalogue` references `register_core_features`, `register_grocery_features` and `register_mealkit_features`, which Tasks 10-12 write. Add empty versions now so `dbt parse` succeeds, each with a comment saying which task fills it in.

Create `macros/core/features/core_counts.sql` containing only:
```sql
{% macro register_core_features(definitions, ctx, generator) %}
  {#- Task 10 fills this in. `generator` is needed because mealkit uses only
      a subset of the core features. -#}
{% endmacro %}
```

Create `macros/grocery/features/grocery_base.sql` containing only:
```sql
{% macro register_grocery_features(definitions, ctx) %}
  {#- Task 11 fills this in. -#}
{% endmacro %}
```

Create `macros/mealkit/features/mealkit_base.sql` containing only:
```sql
{% macro register_mealkit_features(definitions, ctx) %}
  {#- Task 12 fills this in. -#}
{% endmacro %}
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: resolve feature dependencies and level them topologically

build_plan turns requested stems and periods into a dependency closure, then
sorts that closure into levels so each can become its own CTE. Levelling is
needed because SQL cannot reference a select-list alias from the same select
and jstark has derived features built on other derived features.

A dependency is a [stem, period] pair: BasketPeriods for 3m1 depends on
activity in 3m3, 2m2 and 1m1. Features pulled in that way are computed but
not projected, so each plan item carries a `requested` flag.

Adds a `test` generator — five fixture features covering every dependency
shape — so the engine can be tested before any real feature exists.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: The engine — emitting SQL, and the first dbt unit test

Renders a plan as SQL, and proves the L2 test layer works. The emitted shape is one CTE for the input, one for the base aggregates, one per derived level, and a final projection that keeps only what was requested:

```sql
with jstark_input as (
    select * from <input>
),
jstark_base as (
    select
        customer,
        coalesce(sum(case when cast(event_timestamp as date)
                          between date '2021-10-01' and date '2021-12-31'
                     then gross_spend end), 0.0) as test_spend_3m1,
        coalesce(count(distinct case when ... then basket end), 0) as test_basket_count_3m1
    from jstark_input
    group by customer
),
jstark_derived_1 as (
    select *, cast(test_spend_3m1 as double) / nullif(test_basket_count_3m1, 0)
              as test_spend_per_basket_3m1
    from jstark_base
)
select customer, test_spend_3m1, test_basket_count_3m1, test_spend_per_basket_3m1
from jstark_derived_1
```

The spec flagged one open risk: whether dbt `unit_tests` cope with a model whose column list is generated at compile time. This task settles it. If unit tests turn out not to work, stop and report before continuing — the fallback is seed-equality tests via `dbt_utils.equality`, which changes every later task's test layer.

**Files:**
- Create: `macros/core/generate_features.sql`
- Create: `integration_tests/seeds/jstark_test_input.csv`
- Create: `integration_tests/models/core/engine_shape.sql`
- Create: `integration_tests/models/core/_engine.yml`
- Test: `integration_tests/macros/tests/test_engine.sql`
- Modify: `integration_tests/macros/jstark_test_suite.sql`

**Interfaces:**
- Consumes: everything from Tasks 1-8.
- Produces:
  - `jstark.render_feature(item)` → the SQL expression for one plan item, without the alias. Wraps in `coalesce(..., <default>)` unless `default` is `'null'`, in which case the expression is emitted bare.
  - `jstark.generate_features(input, group_by, generator='core', as_at=none, feature_periods=none, feature_stems=none, first_day_of_week=none, use_absolute_periods=false, column_map={}, cuisines=[])` → a complete `select` statement. `input` is a `ref()`/`source()` relation or a SQL string.
  - CTE names, which are part of the emitted SQL and therefore effectively public: `jstark_input`, `jstark_base`, `jstark_derived_1`, `jstark_derived_2`, ….

- [ ] **Step 1: Write the failing L1 structural test**

Add a whitespace normaliser to `integration_tests/macros/jstark_assert.sql`:
```sql
{% macro jstark_normalise_sql(sql) %}
  {{ return(modules.re.sub('\\s+', ' ', sql | string) | trim) }}
{% endmacro %}


{% macro jstark_assert_contains(failures, label, haystack, needle) %}
  {% if needle not in haystack %}
    {% do failures.append(
        label ~ ': expected to find <' ~ needle ~ '> in <' ~ haystack ~ '>'
    ) %}
  {% endif %}
{% endmacro %}
```

`integration_tests/macros/tests/test_engine.sql`:
```sql
{% macro jstark_test_engine(failures) %}

  {% if target.type != 'duckdb' %}
    {% do log('Skipping engine string assertions on ' ~ target.type, info=true) %}
    {{ return('') }}
  {% endif %}

  {% set sql = jstark_normalise_sql(jstark.generate_features(
      input='select * from transactions',
      group_by=['customer'],
      generator='test',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['TestSpend', 'TestBasketCount', 'TestSpendPerBasket']
  )) %}

  {% do jstark_assert_contains(
      failures, 'input CTE',
      sql, 'with jstark_input as ( select * from transactions )'
  ) %}
  {% do jstark_assert_contains(failures, 'base CTE', sql, 'jstark_base as (') %}
  {% do jstark_assert_contains(
      failures, 'derived CTE', sql, 'jstark_derived_1 as ( select *,'
  ) %}
  {% do jstark_assert_contains(
      failures, 'base aggregate',
      sql,
      'coalesce(sum(case when cast(event_timestamp as date) between '
      ~ "date '2021-10-01' and date '2021-12-31' then gross_spend end), 0.0) "
      ~ 'as test_spend_3m1'
  ) %}
  {% do jstark_assert_contains(
      failures, 'derived expression has no coalesce when the default is null',
      sql,
      'cast(test_spend_3m1 as ' ~ dbt.type_float()
      ~ ') / nullif(test_basket_count_3m1, 0) as test_spend_per_basket_3m1'
  ) %}
  {% do jstark_assert_contains(failures, 'group by', sql, 'group by customer') %}
  {% do jstark_assert_contains(
      failures, 'final projection',
      sql,
      'select customer, test_spend_3m1, test_basket_count_3m1, '
      ~ 'test_spend_per_basket_3m1 from jstark_derived_1'
  ) %}

  {# --- helper features are computed but not projected --- #}
  {% set cross_sql = jstark_normalise_sql(jstark.generate_features(
      input='select * from transactions',
      group_by=['customer'],
      generator='test',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['TestActiveMonths']
  )) %}
  {% do jstark_assert_contains(
      failures, 'sub-period helper is computed',
      cross_sql, 'as test_basket_count_2m2'
  ) %}
  {% do jstark_assert_contains(
      failures, 'only the requested feature is projected',
      cross_sql,
      'select customer, test_active_months_3m1 from jstark_derived_1'
  ) %}

  {# --- an empty group_by omits the group by clause entirely --- #}
  {% set nogroup_sql = jstark_normalise_sql(jstark.generate_features(
      input='select * from transactions',
      group_by=[],
      generator='test',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['TestSpend']
  )) %}
  {% do jstark_assert_equal(
      failures, 'no group by clause when group_by is empty',
      'group by' in nogroup_sql, false
  ) %}
  {% do jstark_assert_contains(
      failures, 'no leading comma when group_by is empty',
      nogroup_sql, 'select coalesce(sum('
  ) %}
  {% do jstark_assert_contains(
      failures, 'projection with no group_by',
      nogroup_sql, 'select test_spend_3m1 from jstark_base'
  ) %}

  {# --- a relation input is wrapped rather than inlined --- #}
  {% set relation_sql = jstark_normalise_sql(jstark.generate_features(
      input=api.Relation.create(schema='some_schema', identifier='some_table'),
      group_by=['customer'],
      generator='test',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['TestSpend']
  )) %}
  {% do jstark_assert_contains(
      failures, 'relation input',
      relation_sql, 'with jstark_input as ( select * from '
  ) %}

  {# --- absolute periods change only the projected alias --- #}
  {% set absolute_sql = jstark_normalise_sql(jstark.generate_features(
      input='select * from transactions',
      group_by=['customer'],
      generator='test',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['TestSpend'],
      use_absolute_periods=true
  )) %}
  {% do jstark_assert_contains(
      failures, 'internal name is still the mnemonic',
      absolute_sql, 'as test_spend_3m1'
  ) %}
  {% do jstark_assert_contains(
      failures, 'projection aliases to the absolute label',
      absolute_sql,
      'select customer, test_spend_3m1 as test_spend_2021oct_to_2021dec '
      ~ 'from jstark_base'
  ) %}

  {# --- multiple periods and multiple group_by columns --- #}
  {% set multi_sql = jstark_normalise_sql(jstark.generate_features(
      input='select * from transactions',
      group_by=['customer', 'store'],
      generator='test',
      as_at='2022-01-01',
      feature_periods=['3m1', '0d0'],
      feature_stems=['TestSpend']
  )) %}
  {% do jstark_assert_contains(
      failures, 'multiple group_by columns', multi_sql, 'group by customer, store'
  ) %}
  {% do jstark_assert_contains(
      failures, 'multiple periods',
      multi_sql,
      'select customer, store, test_spend_3m1, test_spend_0d0 from jstark_base'
  ) %}

  {# --- column_map reaches the emitted SQL --- #}
  {% set mapped_sql = jstark_normalise_sql(jstark.generate_features(
      input='select * from transactions',
      group_by=['customer'],
      generator='test',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['TestSpend'],
      column_map={'gross_spend': 'sales_value', 'event_timestamp': 'txn_ts'}
  )) %}
  {% do jstark_assert_contains(
      failures, 'column_map in the aggregate',
      mapped_sql, 'then sales_value end)'
  ) %}
  {% do jstark_assert_contains(
      failures, 'column_map in the window',
      mapped_sql, 'cast(txn_ts as date) between'
  ) %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_engine(failures) %}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `macro 'generate_features' not found in package 'jstark'`.

- [ ] **Step 3: Write the engine**

`macros/core/generate_features.sql`:
```sql
{#
  SQL emission.

  One CTE for the input, one for the base aggregates, one per derived level,
  then a projection that keeps only what was requested. Derived levels get
  their own CTEs because SQL cannot reference a select-list alias from the
  same select, and jstark has derived features built on other derived ones.

  Internal column names always carry the period mnemonic. The final
  projection is the only place a name changes, which is where absolute period
  labels are applied.
#}

{% macro render_feature(item) %}
  {% set definition = item['definition'] %}

  {% if definition['kind'] == 'base' %}
    {% set expression = jstark.aggregate_sql(
        definition['aggregator'], definition['expression'], item['ctx']['window']
    ) %}
  {% else %}
    {% set expression = definition['expression'] %}
  {% endif %}

  {#- a 'null' default adds nothing, so it is left off rather than emitted
      as a redundant coalesce(x, null) -#}
  {% if definition['default'] == 'null' %}
    {{ return(expression) }}
  {% endif %}
  {{ return('coalesce(' ~ expression ~ ', ' ~ definition['default'] ~ ')') }}
{% endmacro %}


{% macro generate_features(
    input,
    group_by,
    generator='core',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={},
    cuisines=[]
) %}

  {% set resolved_as_at = jstark.resolve_as_at(as_at) %}
  {% set periods = jstark.parse_feature_periods(feature_periods) %}
  {% set cols = jstark.resolve_columns(column_map) %}
  {% set group_by_columns = group_by if group_by else [] %}

  {% set plan = jstark.build_plan(
      generator, feature_stems, periods, resolved_as_at, first_day_of_week,
      use_absolute_periods, cols, cuisines
  ) %}

  {% set levels = plan['levels'] %}
  {% set group_by_sql = group_by_columns | join(', ') %}

with jstark_input as (
    {% if input is string %}
    {{ input }}
    {% else %}
    select * from {{ input }}
    {% endif %}
),

jstark_base as (
    select
        {% for column in group_by_columns %}
        {{ column }},
        {% endfor %}
        {% for item in levels[0] %}
        {{ jstark.render_feature(item) }} as {{ item['key'] }}
        {{- ',' if not loop.last }}
        {% endfor %}
    from jstark_input
    {% if group_by_columns | length > 0 %}
    group by {{ group_by_sql }}
    {% endif %}
)

  {%- set last_cte = namespace(name='jstark_base') %}
  {% for level in levels %}
    {% if not loop.first %}
,

jstark_derived_{{ loop.index0 }} as (
    select
        *,
        {% for item in level %}
        {{ jstark.render_feature(item) }} as {{ item['key'] }}
        {{- ',' if not loop.last }}
        {% endfor %}
    from {{ last_cte.name }}
)
      {%- set last_cte.name = 'jstark_derived_' ~ loop.index0 %}
    {% endif %}
  {% endfor %}

select
    {% for column in group_by_columns %}
    {{ column }},
    {% endfor %}
    {% for item in plan['requested'] %}
    {%- set public = jstark.public_column_name(
        item['stem'], item['period'], use_absolute_periods, resolved_as_at,
        item['ctx']['first_day_of_week']
    ) %}
    {{ item['key'] }}{{ ' as ' ~ public if public != item['key'] }}
    {{- ',' if not loop.last }}
    {% endfor %}
from {{ last_cte.name }}

{% endmacro %}
```

Note on `namespace(name=...)`: a plain `{% set %}` inside the `{% for %}` would not survive to the next iteration, which is why the running CTE name is held in a namespace.

- [ ] **Step 4: Run the L1 test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS. If any assertion fails on whitespace rather than content, fix the emitted SQL's whitespace — the normaliser collapses runs of whitespace but does not remove spaces before commas, so keep `{{- ',' }}` hugging the preceding expression.

- [ ] **Step 5: Write the seed and the model under test**

`integration_tests/seeds/jstark_test_input.csv`:
```csv
customer,store,basket,event_timestamp,gross_spend
c1,s1,b1,2021-11-15,10.0
c1,s1,b1,2021-11-15,5.0
c1,s1,b2,2021-12-31,20.0
c1,s1,b3,2022-01-01,99.0
c2,s2,b4,2021-10-01,7.5
c2,s2,b5,2021-09-30,99.0
```

Rows 4 and 6 sit one day outside the `3m1` window (which is 2021-10-01 to 2021-12-31 for an `as_at` of 2022-01-01); rows 3 and 5 sit exactly on its boundaries.

`integration_tests/models/core/engine_shape.sql`:
```sql
{{ jstark.generate_features(
    input=ref('jstark_test_input'),
    group_by=['customer'],
    generator='test',
    as_at='2022-01-01',
    feature_periods=['3m1'],
    feature_stems=['TestSpend', 'TestBasketCount', 'TestSpendPerBasket']
) }}
```

- [ ] **Step 6: Write the dbt unit test**

`integration_tests/models/core/_engine.yml`:
```yaml
version: 2

models:
  - name: engine_shape
    description: >
      Exercises the engine end to end against the test generator: a base sum,
      a base distinct count, and a derived feature over both.

unit_tests:
  - name: engine_shape_respects_the_window
    description: >
      Rows on the window boundaries are included and rows one day outside are
      excluded, at both ends.
    model: engine_shape
    given:
      - input: ref('jstark_test_input')
        format: sql
        rows: |
          select 'c1' as customer, 's1' as store, 'b1' as basket,
                 cast('2021-11-15' as date) as event_timestamp,
                 cast(10.0 as double) as gross_spend
          union all
          select 'c1', 's1', 'b1', cast('2021-11-15' as date), cast(5.0 as double)
          union all
          select 'c1', 's1', 'b2', cast('2021-12-31' as date), cast(20.0 as double)
          union all
          select 'c1', 's1', 'b3', cast('2022-01-01' as date), cast(99.0 as double)
          union all
          select 'c2', 's2', 'b4', cast('2021-10-01' as date), cast(7.5 as double)
          union all
          select 'c2', 's2', 'b5', cast('2021-09-30' as date), cast(99.0 as double)
    expect:
      format: sql
      rows: |
          select 'c1' as customer,
                 cast(35.0 as double) as test_spend_3m1,
                 2 as test_basket_count_3m1,
                 cast(17.5 as double) as test_spend_per_basket_3m1
          union all
          select 'c2', cast(7.5 as double), 1, cast(7.5 as double)

  - name: engine_shape_defaults_when_the_window_is_empty
    description: >
      A group with no rows in the window falls back to each feature's default:
      0.0 for the sum, 0 for the count, and null for the derived feature,
      whose denominator is zero.
    model: engine_shape
    given:
      - input: ref('jstark_test_input')
        format: sql
        rows: |
          select 'c9' as customer, 's1' as store, 'b9' as basket,
                 cast('2020-01-01' as date) as event_timestamp,
                 cast(42.0 as double) as gross_spend
    expect:
      format: sql
      rows: |
          select 'c9' as customer,
                 cast(0.0 as double) as test_spend_3m1,
                 0 as test_basket_count_3m1,
                 cast(null as double) as test_spend_per_basket_3m1
```

`format: sql` is used rather than `format: dict` throughout because it pins the types explicitly. Type coercion between the fixture and the generated SQL is otherwise the most common cause of a confusing unit-test failure, and later tasks need array columns, which `dict` cannot express at all.

- [ ] **Step 7: Run the unit tests**

```bash
cd integration_tests
uv run dbt seed --profiles-dir .
uv run dbt test --select test_type:unit --profiles-dir .
```
Expected: PASS, 2 of 2.

**If dbt unit tests cannot handle this model, stop here and report.** The spec's fallback is `dbt_utils.equality` against expected seeds; adopting it changes the test layer of every later task, so it is a decision to surface rather than to make silently.

- [ ] **Step 8: Verify the model actually builds**

```bash
cd integration_tests
uv run dbt build --profiles-dir .
```
Expected: PASS. This is the first proof that the emitted SQL is valid, not merely well-shaped.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: emit feature SQL as levelled CTEs

generate_features renders a plan as an input CTE, a base aggregate CTE, one
CTE per derived level, and a projection that keeps only the requested
features. Absolute period labels are applied in that final projection, so
internal names always carry the mnemonic and every dependency reference has
exactly one spelling.

Also establishes the L2 test layer: a model built from the test generator with
dbt unit tests covering window boundaries at both ends and the empty-window
defaults. Fixtures use format: sql so column types are pinned explicitly.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: The 20 core features

The table below is **exhaustive and normative**. Every value was read from jstark at commit `51d9083`; do not infer, adjust or "improve" any of it. Columns marked *SQL* are Jinja expressions to write literally in the definition.

`min` defaults to `0.0` while `max` defaults to `null`. That asymmetry is in jstark (`Min.default_value()` returns `f.lit(0.0)`, `Max.default_value()` returns `f.lit(None)`) and is reproduced deliberately, not fixed.

| # | Stem | Aggregator | `expression` (SQL) | `default` | `description_subject` | `required_columns` |
|---|---|---|---|---|---|---|
| 1 | `Count` | `count` | `'1'` | `'0'` | Count of rows | `event_timestamp` |
| 2 | `CustomerCount` | `count_distinct` | `ctx['cols']['customer']` | `'0'` | Distinct count of Customers | `event_timestamp`, `customer` |
| 3 | `ApproxCustomerCount` | `approx_count_distinct` | `ctx['cols']['customer']` | `'0'` | Approximate distinct count of Customers | `event_timestamp`, `customer` |
| 4 | `ProductCount` | `count_distinct` | `ctx['cols']['product']` | `'0'` | Distinct count of Products | `event_timestamp`, `product` |
| 5 | `ApproxProductCount` | `approx_count_distinct` | `ctx['cols']['product']` | `'0'` | Approximate distinct count of Products | `event_timestamp`, `product` |
| 6 | `Quantity` | `sum` | `ctx['cols']['quantity']` | `'0'` | Sum of Quantity | `event_timestamp`, `quantity` |
| 7 | `Discount` | `sum` | `ctx['cols']['discount']` | `'0.0'` | Sum of Discount | `event_timestamp`, `discount` |
| 8 | `GrossSpend` | `sum` | `ctx['cols']['gross_spend']` | `'0.0'` | Sum of GrossSpend | `event_timestamp`, `gross_spend` |
| 9 | `NetSpend` | `sum` | `ctx['cols']['net_spend']` | `'0.0'` | Sum of NetSpend | `event_timestamp`, `net_spend` |
| 10 | `MinGrossSpend` | `min` | `ctx['cols']['gross_spend']` | `'0.0'` | Minimum GrossSpend value | `event_timestamp`, `gross_spend` |
| 11 | `MaxGrossSpend` | `max` | `ctx['cols']['gross_spend']` | `'null'` | Maximum GrossSpend value | `event_timestamp`, `gross_spend` |
| 12 | `MinNetSpend` | `min` | `ctx['cols']['net_spend']` | `'0.0'` | Minimum of NetSpend value | `event_timestamp`, `net_spend` |
| 13 | `MaxNetSpend` | `max` | `ctx['cols']['net_spend']` | `'null'` | Maximum of NetSpend value | `event_timestamp`, `net_spend` |
| 14 | `MinGrossPrice` | `min` | `jstark.safe_divide(ctx['cols']['gross_spend'], ctx['cols']['quantity'])` | `'0.0'` | Minimum of (GrossSpend / Quantity) | `event_timestamp`, `gross_spend`, `quantity` |
| 15 | `MaxGrossPrice` | `max` | `jstark.safe_divide(ctx['cols']['gross_spend'], ctx['cols']['quantity'])` | `'null'` | Maximum of (GrossSpend / Quantity) | `event_timestamp`, `gross_spend`, `quantity` |
| 16 | `MinNetPrice` | `min` | `jstark.safe_divide(ctx['cols']['net_spend'], ctx['cols']['quantity'])` | `'0.0'` | Minimum of (NetSpend / Quantity) | `event_timestamp`, `net_spend`, `quantity` |
| 17 | `MaxNetPrice` | `max` | `jstark.safe_divide(ctx['cols']['net_spend'], ctx['cols']['quantity'])` | `'null'` | Maximum of (NetSpend / Quantity) | `event_timestamp`, `net_spend`, `quantity` |
| 18 | `RecencyDays` | `min` | `dbt.datediff(jstark.to_date(ctx['cols']['event_timestamp']), jstark.date_literal(ctx['as_at']), 'day')` | `'0'` | Minimum number of days since occurrence | `event_timestamp` |
| 19 | `EarliestPurchaseDate` | `min` | `jstark.to_date(ctx['cols']['event_timestamp'])` | `'null'` | Earliest purchase date | `event_timestamp` |
| 20 | `MostRecentPurchaseDate` | `max` | `jstark.to_date(ctx['cols']['event_timestamp'])` | `'null'` | Most recent purchase date | `event_timestamp` |

`dbt.datediff(first, second, part)` returns `second - first`, so `RecencyDays` puts the event date first and `as_at` second, matching jstark's `f.datediff(f.lit(self.as_at), f.col("Timestamp"))`.

**Mealkit uses only 10 of these.** `register_core_features` therefore takes the generator name and registers the full 20 for `core` and `grocery`, but only `Count`, `CustomerCount`, `ApproxCustomerCount`, `ProductCount`, `ApproxProductCount`, `Quantity`, `Discount`, `RecencyDays`, `EarliestPurchaseDate`, `MostRecentPurchaseDate` for `mealkit`.

**Files:**
- Modify: `macros/core/features/core_counts.sql` (replace the Task 8 stub)
- Create: `macros/core/features/core_sums.sql`, `macros/core/features/core_minmax.sql`, `macros/core/features/core_dates.sql`
- Create: `integration_tests/seeds/core_transactions.csv`
- Create: `integration_tests/models/core/core_features.sql`, `integration_tests/models/core/_core_features.yml`
- Modify: `integration_tests/macros/tests/test_registry.sql` (add core-catalogue assertions)

**Interfaces:**
- Consumes: `ctx` (Task 7), `jstark.safe_divide`, `jstark.to_date` (Task 6), the definition dict shape (Task 8).
- Produces:
  - `jstark.register_core_features(definitions, ctx, generator)` — mutates `definitions`, in the numbered order above.
  - `jstark.core_stems_for_mealkit()` → the 10-stem list.
  - Helper registration macros, each mutating `definitions`: `jstark.register_core_count_features`, `jstark.register_core_sum_features`, `jstark.register_core_minmax_features`, `jstark.register_core_date_features`.

- [ ] **Step 1: Extract the commentary strings from jstark**

Each definition carries a `commentary` string that ends up in the catalogue and the generated docs. Copy them verbatim rather than inventing them:

```bash
git clone https://github.com/jamiekt/jstark /tmp/jstark-ref 2>/dev/null; \
git -C /tmp/jstark-ref checkout -q 51d9083209bf40077c5fdc307b80f59bcb70de1b && \
grep -rn -A6 'def commentary' /tmp/jstark-ref/jstark/features/
```

For every stem in the table above, use the exact string from its `commentary` property. Where a feature class does not define one, use `'No commentary supplied'` — that is `Feature.commentary`'s default in `jstark/features/feature.py`.

- [ ] **Step 2: Write the failing test**

Add to `integration_tests/macros/tests/test_registry.sql`, inside `jstark_test_registry`, before its final `{% endmacro %}`:

```sql
  {# --- the core catalogue is complete and in a fixed order --- #}
  {% set core_ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  ) %}
  {% set core_cat = jstark.catalogue('core', core_ctx) %}
  {% do jstark_assert_equal(
      failures, 'core catalogue',
      core_cat.keys() | list,
      ['Count', 'CustomerCount', 'ApproxCustomerCount', 'ProductCount',
       'ApproxProductCount', 'Quantity', 'Discount', 'GrossSpend', 'NetSpend',
       'MinGrossSpend', 'MaxGrossSpend', 'MinNetSpend', 'MaxNetSpend',
       'MinGrossPrice', 'MaxGrossPrice', 'MinNetPrice', 'MaxNetPrice',
       'RecencyDays', 'EarliestPurchaseDate', 'MostRecentPurchaseDate']
  ) %}

  {# --- every core feature is a base feature, and every one is fully specified --- #}
  {% for stem, definition in core_cat.items() %}
    {% do jstark_assert_equal(
        failures, stem ~ ' is base', definition['kind'], 'base'
    ) %}
    {% do jstark_assert_true(
        failures, stem ~ ' has a valid aggregator',
        definition['aggregator'] in jstark.aggregators()
    ) %}
    {% do jstark_assert_true(
        failures, stem ~ ' has an expression', definition['expression']
    ) %}
    {% do jstark_assert_true(
        failures, stem ~ ' has a default', definition['default']
    ) %}
    {% do jstark_assert_true(
        failures, stem ~ ' has a description_subject', definition['description_subject']
    ) %}
    {% do jstark_assert_true(
        failures, stem ~ ' has commentary', definition['commentary']
    ) %}
    {% do jstark_assert_true(
        failures, stem ~ ' requires event_timestamp',
        'event_timestamp' in definition['required_columns']
    ) %}
    {% for column in definition['required_columns'] %}
      {% do jstark_assert_true(
          failures, stem ~ ' requires only canonical columns (' ~ column ~ ')',
          column in jstark.canonical_columns()
      ) %}
    {% endfor %}
  {% endfor %}

  {# --- the min/max default asymmetry is deliberate parity with jstark --- #}
  {% do jstark_assert_equal(
      failures, 'MinGrossSpend default', core_cat['MinGrossSpend']['default'], '0.0'
  ) %}
  {% do jstark_assert_equal(
      failures, 'MaxGrossSpend default', core_cat['MaxGrossSpend']['default'], 'null'
  ) %}

  {# --- Quantity sums as an integer, Discount as a float --- #}
  {% do jstark_assert_equal(
      failures, 'Quantity default', core_cat['Quantity']['default'], '0'
  ) %}
  {% do jstark_assert_equal(
      failures, 'Discount default', core_cat['Discount']['default'], '0.0'
  ) %}

  {# --- RecencyDays counts days from the event to as_at, not the reverse --- #}
  {% do jstark_assert_equal(
      failures, 'RecencyDays expression',
      core_cat['RecencyDays']['expression'],
      dbt.datediff(
          jstark.to_date('event_timestamp'), "date '2022-01-01'", 'day'
      )
  ) %}

  {# --- mealkit takes only 10 of the core features --- #}
  {% do jstark_assert_equal(
      failures, 'core_stems_for_mealkit',
      jstark.core_stems_for_mealkit(),
      ['Count', 'CustomerCount', 'ApproxCustomerCount', 'ProductCount',
       'ApproxProductCount', 'Quantity', 'Discount', 'RecencyDays',
       'EarliestPurchaseDate', 'MostRecentPurchaseDate']
  ) %}
```

Run it:
```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — the core catalogue is empty, so the first assertion reports `[]` against the 20 expected stems.

- [ ] **Step 3: Write the count features**

Replace the whole of `macros/core/features/core_counts.sql`:
```sql
{#
  Core features: the ones that make sense whatever the industry.

  register_core_features takes the generator name because mealkit uses only a
  subset: spend has no meaning for a business that sells recipe boxes at a
  fixed price, so the Gross/Net spend and price features are grocery-only.

  Registration order is the column order in the generated SQL, so it is fixed
  deliberately and matches the order of the table in the implementation plan.
#}

{% macro core_stems_for_mealkit() %}
  {{ return([
      'Count', 'CustomerCount', 'ApproxCustomerCount', 'ProductCount',
      'ApproxProductCount', 'Quantity', 'Discount', 'RecencyDays',
      'EarliestPurchaseDate', 'MostRecentPurchaseDate'
  ]) }}
{% endmacro %}


{% macro register_core_features(definitions, ctx, generator) %}
  {% set all_core = {} %}
  {% do jstark.register_core_count_features(all_core, ctx) %}
  {% do jstark.register_core_sum_features(all_core, ctx) %}
  {% do jstark.register_core_minmax_features(all_core, ctx) %}
  {% do jstark.register_core_date_features(all_core, ctx) %}

  {% if generator == 'mealkit' %}
    {% set wanted = jstark.core_stems_for_mealkit() %}
  {% else %}
    {% set wanted = all_core.keys() | list %}
  {% endif %}

  {#- iterate all_core, not wanted, so registration order is preserved -#}
  {% for stem, definition in all_core.items() %}
    {% if stem in wanted %}
      {% do definitions.update({stem: definition}) %}
    {% endif %}
  {% endfor %}
{% endmacro %}


{% macro register_core_count_features(definitions, ctx) %}

  {% do definitions.update({'Count': {
      'stem': 'Count',
      'kind': 'base',
      'aggregator': 'count',
      'expression': '1',
      'default': '0',
      'required_columns': ['event_timestamp'],
      'description_subject': 'Count of rows',
      'commentary': '<verbatim from jstark Count.commentary>'
  }}) %}

  {% do definitions.update({'CustomerCount': {
      'stem': 'CustomerCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['customer'],
      'default': '0',
      'required_columns': ['event_timestamp', 'customer'],
      'description_subject': 'Distinct count of Customers',
      'commentary': '<verbatim from jstark CustomerCount.commentary>'
  }}) %}

  {% do definitions.update({'ApproxCustomerCount': {
      'stem': 'ApproxCustomerCount',
      'kind': 'base',
      'aggregator': 'approx_count_distinct',
      'expression': ctx['cols']['customer'],
      'default': '0',
      'required_columns': ['event_timestamp', 'customer'],
      'description_subject': 'Approximate distinct count of Customers',
      'commentary': '<verbatim from jstark ApproxCustomerCount.commentary>'
  }}) %}

  {% do definitions.update({'ProductCount': {
      'stem': 'ProductCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['product'],
      'default': '0',
      'required_columns': ['event_timestamp', 'product'],
      'description_subject': 'Distinct count of Products',
      'commentary': '<verbatim from jstark ProductCount.commentary>'
  }}) %}

  {% do definitions.update({'ApproxProductCount': {
      'stem': 'ApproxProductCount',
      'kind': 'base',
      'aggregator': 'approx_count_distinct',
      'expression': ctx['cols']['product'],
      'default': '0',
      'required_columns': ['event_timestamp', 'product'],
      'description_subject': 'Approximate distinct count of Products',
      'commentary': '<verbatim from jstark ApproxProductCount.commentary>'
  }}) %}

{% endmacro %}
```

Replace each `<verbatim from jstark ...>` with the string extracted in Step 1. The same applies to every definition in Steps 4-6.

- [ ] **Step 4: Write the sum features**

`macros/core/features/core_sums.sql`, following exactly the same dict shape, registering in order: `Quantity` (`sum`, `ctx['cols']['quantity']`, default `'0'`), `Discount` (`sum`, `ctx['cols']['discount']`, default `'0.0'`), `GrossSpend` (`sum`, `ctx['cols']['gross_spend']`, default `'0.0'`), `NetSpend` (`sum`, `ctx['cols']['net_spend']`, default `'0.0'`), inside:
```sql
{% macro register_core_sum_features(definitions, ctx) %}
  ...
{% endmacro %}
```
Take `description_subject` and `required_columns` from rows 6-9 of the table above. `Quantity` defaults to the integer `'0'` rather than `'0.0'` because jstark's `Quantity` overrides `Sum.default_value()`; keep that distinction.

- [ ] **Step 5: Write the min/max features**

`macros/core/features/core_minmax.sql`, registering rows 10-17 in order inside:
```sql
{% macro register_core_minmax_features(definitions, ctx) %}
  ...
{% endmacro %}
```

Add this comment above the first `Min`/`Max` pair, so the asymmetry is not mistaken for a bug and quietly corrected:
```sql
  {#
    Min features default to 0.0 and Max features default to null on an empty
    window. That is asymmetric, and it is what jstark does:
    Min.default_value() returns f.lit(0.0) while Max.default_value() returns
    f.lit(None). Reproduced for parity rather than fixed.
  #}
```

The four price features share one expression shape; write it out in each definition rather than factoring it into a variable, so each definition reads independently:
```sql
      'expression': jstark.safe_divide(
          ctx['cols']['gross_spend'], ctx['cols']['quantity']
      ),
```

- [ ] **Step 6: Write the date features**

`macros/core/features/core_dates.sql`, registering rows 18-20 in order inside:
```sql
{% macro register_core_date_features(definitions, ctx) %}

  {% do definitions.update({'RecencyDays': {
      'stem': 'RecencyDays',
      'kind': 'base',
      'aggregator': 'min',
      'expression': dbt.datediff(
          jstark.to_date(ctx['cols']['event_timestamp']),
          jstark.date_literal(ctx['as_at']),
          'day'
      ),
      'default': '0',
      'required_columns': ['event_timestamp'],
      'description_subject': 'Minimum number of days since occurrence',
      'commentary': '<verbatim from jstark RecencyDays.commentary>'
  }}) %}

  {% do definitions.update({'EarliestPurchaseDate': {
      'stem': 'EarliestPurchaseDate',
      'kind': 'base',
      'aggregator': 'min',
      'expression': jstark.to_date(ctx['cols']['event_timestamp']),
      'default': 'null',
      'required_columns': ['event_timestamp'],
      'description_subject': 'Earliest purchase date',
      'commentary': '<verbatim from jstark EarliestPurchaseDate.commentary>'
  }}) %}

  {% do definitions.update({'MostRecentPurchaseDate': {
      'stem': 'MostRecentPurchaseDate',
      'kind': 'base',
      'aggregator': 'max',
      'expression': jstark.to_date(ctx['cols']['event_timestamp']),
      'default': 'null',
      'required_columns': ['event_timestamp'],
      'description_subject': 'Most recent purchase date',
      'commentary': '<verbatim from jstark MostRecentPurchaseDate.commentary>'
  }}) %}

{% endmacro %}
```

`dbt.datediff` argument order is `(first, second, part)` and returns `second - first`, so the event date goes first and `as_at` second. Getting this backwards makes every recency value negative.

- [ ] **Step 7: Run the L1 test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 8: Add the L2 model and unit tests**

`integration_tests/seeds/core_transactions.csv`:
```csv
customer,product,basket,event_timestamp,quantity,gross_spend,net_spend,discount
c1,p1,b1,2021-10-01,2,10.0,8.0,2.0
c1,p2,b1,2021-11-15,4,20.0,16.0,4.0
c1,p1,b2,2021-12-31,1,3.0,3.0,0.0
c1,p3,b3,2022-01-01,9,99.0,99.0,9.0
```

`integration_tests/models/core/core_features.sql`:
```sql
{{ jstark.generate_features(
    input=ref('core_transactions'),
    group_by=['customer'],
    generator='core',
    as_at='2022-01-01',
    feature_periods=['3m1']
) }}
```

`integration_tests/models/core/_core_features.yml`:
```yaml
version: 2

models:
  - name: core_features
    description: All 20 core features for a single customer over a 3m1 period.

unit_tests:
  - name: core_features_values
    description: >
      Every core feature over a window containing three rows, with a fourth
      row one day past the end of the window that must be excluded.
    model: core_features
    given:
      - input: ref('core_transactions')
        format: sql
        rows: |
          select 'c1' as customer, 'p1' as product, 'b1' as basket,
                 cast('2021-10-01' as date) as event_timestamp,
                 2 as quantity, cast(10.0 as double) as gross_spend,
                 cast(8.0 as double) as net_spend, cast(2.0 as double) as discount
          union all
          select 'c1', 'p2', 'b1', cast('2021-11-15' as date), 4,
                 cast(20.0 as double), cast(16.0 as double), cast(4.0 as double)
          union all
          select 'c1', 'p1', 'b2', cast('2021-12-31' as date), 1,
                 cast(3.0 as double), cast(3.0 as double), cast(0.0 as double)
          union all
          select 'c1', 'p3', 'b3', cast('2022-01-01' as date), 9,
                 cast(99.0 as double), cast(99.0 as double), cast(9.0 as double)
    expect:
      format: sql
      rows: |
          select 'c1' as customer,
                 3 as count_3m1,
                 1 as customer_count_3m1,
                 1 as approx_customer_count_3m1,
                 2 as product_count_3m1,
                 2 as approx_product_count_3m1,
                 7 as quantity_3m1,
                 cast(6.0 as double) as discount_3m1,
                 cast(33.0 as double) as gross_spend_3m1,
                 cast(27.0 as double) as net_spend_3m1,
                 cast(3.0 as double) as min_gross_spend_3m1,
                 cast(20.0 as double) as max_gross_spend_3m1,
                 cast(3.0 as double) as min_net_spend_3m1,
                 cast(16.0 as double) as max_net_spend_3m1,
                 cast(3.0 as double) as min_gross_price_3m1,
                 cast(5.0 as double) as max_gross_price_3m1,
                 cast(3.0 as double) as min_net_price_3m1,
                 cast(4.0 as double) as max_net_price_3m1,
                 1 as recency_days_3m1,
                 cast('2021-10-01' as date) as earliest_purchase_date_3m1,
                 cast('2021-12-31' as date) as most_recent_purchase_date_3m1

  - name: core_features_empty_window_defaults
    description: >
      With no rows in the window every feature falls back to its default. Note
      that the Min features return 0.0 while the Max features return null:
      that asymmetry is jstark's and is reproduced deliberately.
    model: core_features
    given:
      - input: ref('core_transactions')
        format: sql
        rows: |
          select 'c9' as customer, 'p1' as product, 'b9' as basket,
                 cast('2020-01-01' as date) as event_timestamp,
                 5 as quantity, cast(50.0 as double) as gross_spend,
                 cast(45.0 as double) as net_spend, cast(5.0 as double) as discount
    expect:
      format: sql
      rows: |
          select 'c9' as customer,
                 0 as count_3m1,
                 0 as customer_count_3m1,
                 0 as approx_customer_count_3m1,
                 0 as product_count_3m1,
                 0 as approx_product_count_3m1,
                 0 as quantity_3m1,
                 cast(0.0 as double) as discount_3m1,
                 cast(0.0 as double) as gross_spend_3m1,
                 cast(0.0 as double) as net_spend_3m1,
                 cast(0.0 as double) as min_gross_spend_3m1,
                 cast(null as double) as max_gross_spend_3m1,
                 cast(0.0 as double) as min_net_spend_3m1,
                 cast(null as double) as max_net_spend_3m1,
                 cast(0.0 as double) as min_gross_price_3m1,
                 cast(null as double) as max_gross_price_3m1,
                 cast(0.0 as double) as min_net_price_3m1,
                 cast(null as double) as max_net_price_3m1,
                 0 as recency_days_3m1,
                 cast(null as date) as earliest_purchase_date_3m1,
                 cast(null as date) as most_recent_purchase_date_3m1
```

The expected values: within the window there are three rows totalling `quantity` 7, `gross_spend` 33.0, `net_spend` 27.0 and `discount` 6.0; two distinct products (`p1`, `p2`); gross unit prices of 5.0, 5.0 and 3.0 and net unit prices of 4.0, 4.0 and 3.0; and a most recent purchase one day before `as_at`, so `recency_days` is 1.

- [ ] **Step 9: Run the unit tests and build**

```bash
cd integration_tests
uv run dbt seed --profiles-dir .
uv run dbt test --select test_type:unit --profiles-dir .
uv run dbt build --profiles-dir .
```
Expected: PASS. If a column-type mismatch is reported, adjust the `cast(...)` in the fixture to match what the engine emits — do not change a feature's `default`.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add the 20 core features

Counts, sums, min/max spend and price, and the recency/date features, each
transcribed from jstark at 51d9083 rather than reinterpreted.

Mealkit takes only 10 of them: gross and net spend have no meaning for a
business selling recipe boxes at a fixed price, so register_core_features
takes the generator name and filters.

The min/max default asymmetry (0.0 versus null on an empty window) is jstark's
and is reproduced deliberately; there is a unit test asserting it so it is not
quietly "fixed" later.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: The 17 grocery features and the `grocery_features` entry point

Grocery is the first real generator, and the first place derived features appear. It is also where the levelling from Task 8 earns its keep: `CyclesSinceLastPurchase` depends on `AvgPurchaseCycle`, which depends on base aggregates, so grocery bottoms out at level 2.

The table below is **exhaustive and normative**, read from jstark at `51d9083`. `P` means `ctx['period']`; `col(X)` abbreviates `jstark.column_name('X', P)`.

**Base (level 0):**

| Stem | Aggregator | `expression` | `default` | `description_subject` | `required_columns` |
|---|---|---|---|---|---|
| `BasketCount` | `count_distinct` | `ctx['cols']['basket']` | `'0'` | Distinct count of Baskets | `event_timestamp`, `basket` |
| `ApproxBasketCount` | `approx_count_distinct` | `ctx['cols']['basket']` | `'0'` | Approximate distinct count of Baskets | `event_timestamp`, `basket` |
| `StoreCount` | `count_distinct` | `ctx['cols']['store']` | `'0'` | Distinct count of Stores | `event_timestamp`, `store` |
| `ChannelCount` | `count_distinct` | `ctx['cols']['channel']` | `'0'` | Distinct count of Channels | `event_timestamp`, `channel` |

**Derived.** Every one has `default: 'null'`, matching jstark, where `DerivedFeature` subclasses all return `f.lit(None)`.

| Stem | `depends_on` | `expression` | `description_subject` |
|---|---|---|---|
| `AvgGrossSpendPerBasket` | `GrossSpend`, `BasketCount` at `P` | `jstark.safe_divide(col(GrossSpend), col(BasketCount))` | Average GrossSpend per Basket |
| `AvgQuantityPerBasket` | `Quantity`, `BasketCount` at `P` | `jstark.safe_divide(col(Quantity), col(BasketCount))` | Average Quantity per Basket |
| `AvgDiscountPerBasket` | `Discount`, `BasketCount` at `P` | `jstark.safe_divide(col(Discount), col(BasketCount))` | Average Discount per Basket |
| `AvgPurchaseCycle` | `EarliestPurchaseDate`, `MostRecentPurchaseDate`, `BasketCount` at `P` | `jstark.safe_divide(dbt.datediff(col(EarliestPurchaseDate), col(MostRecentPurchaseDate), 'day'), col(BasketCount))` | Average purchase cycle |
| `CyclesSinceLastPurchase` | `RecencyDays`, `AvgPurchaseCycle` at `P` | `jstark.safe_divide(col(RecencyDays), col(AvgPurchaseCycle))` | Cycles since last purchase |
| `BasketPeriods` | the activity aggregate at each of `jstark.single_unit_periods(P)` | `' + '` joined `case when <col> > 0 then 1 else 0 end` | `'Number of ' ~ unit ~ 's in which at least one basket was purchased'` |
| `AvgBasket` | `Count` at `P` | `jstark.safe_divide(col(Count), P['number_of_periods'] \| string)` | `'Average number of baskets per ' ~ unit` |
| `RecencyWeightedBasket90` / `95` / `99` | `BasketCount` at each of `single_unit_periods(P)` | `' + '` joined `<basket_count col> * <sf ** n>` | `'Exponentially weighted moving average, with smoothing factor of ' ~ sf ~ ', of the number of baskets per ' ~ unit` |
| `RecencyWeightedApproxBasket90` / `95` / `99` | `ApproxBasketCount` at each of `single_unit_periods(P)` | `' + '` joined `<approx_basket_count col> * <sf ** n>` | as the row above, but `'of the approximate number of baskets per '` |

`unit` is `jstark.period_unit_name(ctx['period']['uom']) | lower` — so `month`, `week`, and so on.

Smoothing factors are `0.9`, `0.95` and `0.99`, and the weights are evaluated in Jinja (`sf ** n`) so no SQL `power()` is emitted — one fewer portability problem. `n` runs over the *offsets* of the single-unit periods, so for `3m1` the terms are `basket_count_1m1 * 0.95`, `basket_count_2m2 * 0.9025`, `basket_count_3m3 * <0.95 ** 3>`, in that order.

- [ ] **Step 1: Confirm two details against the pinned jstark source**

Two things must be read rather than assumed:

```bash
ls /tmp/jstark-ref/jstark/features/grocery/
grep -rn -B2 -A20 'class Basket\|class RecencyWeighted\|def description_subject\|def commentary' \
  /tmp/jstark-ref/jstark/features/grocery/
```

1. **Which aggregate `BasketPeriods` tests for activity** — `Count` or `BasketCount` at each sub-period. Both give identical results (a period has a basket exactly when it has a row), but the choice determines which helper aggregates land in `jstark_base`, and therefore whether `BasketPeriods` shares its sub-period aggregates with `RecencyWeightedBasket*`. Use whichever the source uses.
2. **The exact `description_subject` text for the recency-weighted features**, including how the smoothing factor is rendered. The shape is:
   `'Exponentially weighted moving average, with smoothing factor of <sf>, of the number of baskets per <unit>'`, with `approximate number` for the `Approx` variants. Copy the rendering of `<sf>` exactly.

Also collect the `commentary` strings for all 17, exactly as in Task 10 Step 1.

- [ ] **Step 2: Write the failing L1 test**

Create `integration_tests/macros/tests/test_grocery.sql`:
```sql
{% macro jstark_test_grocery(failures) %}

  {% set d = modules.datetime.date %}
  {% set as_at = d(2022, 1, 1) %}
  {% set cols = jstark.resolve_columns({}) %}
  {% set ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  ) %}
  {% set cat = jstark.catalogue('grocery', ctx) %}

  {# --- grocery is the 20 core features plus 17 of its own --- #}
  {% do jstark_assert_equal(failures, 'grocery catalogue size', cat | length, 37) %}
  {% set grocery_only = [
      'BasketCount', 'ApproxBasketCount', 'StoreCount', 'ChannelCount',
      'AvgGrossSpendPerBasket', 'AvgQuantityPerBasket', 'AvgDiscountPerBasket',
      'AvgPurchaseCycle', 'CyclesSinceLastPurchase', 'BasketPeriods', 'AvgBasket',
      'RecencyWeightedBasket90', 'RecencyWeightedBasket95', 'RecencyWeightedBasket99',
      'RecencyWeightedApproxBasket90', 'RecencyWeightedApproxBasket95',
      'RecencyWeightedApproxBasket99'
  ] %}
  {% for stem in grocery_only %}
    {% do jstark_assert_true(
        failures, 'grocery catalogue contains ' ~ stem, stem in cat
    ) %}
  {% endfor %}
  {% for stem in jstark.catalogue('core', ctx) %}
    {% do jstark_assert_true(
        failures, 'grocery catalogue contains core ' ~ stem, stem in cat
    ) %}
  {% endfor %}

  {# --- every derived feature defaults to null, as in jstark --- #}
  {% for stem, definition in cat.items() %}
    {% if definition['kind'] == 'derived' %}
      {% do jstark_assert_equal(
          failures, stem ~ ' derived default', definition['default'], 'null'
      ) %}
      {% do jstark_assert_true(
          failures, stem ~ ' declares dependencies', definition['depends_on'] | length > 0
      ) %}
    {% endif %}
  {% endfor %}

  {# --- the names that vary with the period unit --- #}
  {% do jstark_assert_equal(
      failures, 'BasketPeriods name for a monthly period',
      jstark.column_name('BasketPeriods', ctx['period']), 'basket_months_3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'AvgBasket name for a monthly period',
      jstark.column_name('AvgBasket', ctx['period']),
      'average_baskets_per_month_3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'RecencyWeightedBasket95 name for a monthly period',
      jstark.column_name('RecencyWeightedBasket95', ctx['period']),
      'recency_weighted_basket_months95_3m1'
  ) %}

  {# --- descriptions follow the period unit --- #}
  {% do jstark_assert_contains(
      failures, 'BasketPeriods description names the unit',
      cat['BasketPeriods']['description_subject'], 'months'
  ) %}
  {% set weekly_ctx = jstark.feature_context(
      jstark.parse_feature_period('52w0'), as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_contains(
      failures, 'BasketPeriods description follows a weekly period',
      jstark.catalogue('grocery', weekly_ctx)['BasketPeriods']['description_subject'],
      'weeks'
  ) %}

  {# --- the exponential weights are Jinja literals, not SQL power() calls --- #}
  {% do jstark_assert_contains(
      failures, 'recency weight for the most recent period',
      cat['RecencyWeightedBasket95']['expression'],
      'basket_count_1m1 * ' ~ (0.95 ** 1)
  ) %}
  {% do jstark_assert_contains(
      failures, 'recency weight for the oldest period',
      cat['RecencyWeightedBasket95']['expression'],
      'basket_count_3m3 * ' ~ (0.95 ** 3)
  ) %}
  {% do jstark_assert_equal(
      failures, 'no SQL power() is emitted',
      'power(' in cat['RecencyWeightedBasket95']['expression'], false
  ) %}
  {% do jstark_assert_contains(
      failures, 'the approximate variant uses the approximate count',
      cat['RecencyWeightedApproxBasket95']['expression'], 'approx_basket_count_1m1'
  ) %}

  {# --- AvgBasket divides by the number of whole periods in the window --- #}
  {% do jstark_assert_equal(
      failures, 'AvgBasket expression',
      cat['AvgBasket']['expression'],
      jstark.safe_divide('count_3m1', '3')
  ) %}

  {# --- grocery is two derived levels deep --- #}
  {% set plan = jstark.build_plan(
      'grocery', ['CyclesSinceLastPurchase'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'CyclesSinceLastPurchase is two levels deep',
      plan['levels'] | length, 3
  ) %}
  {% do jstark_assert_equal(
      failures, 'AvgPurchaseCycle sits between them',
      plan['levels'][1] | map(attribute='key') | list, ['avg_purchase_cycle_3m1']
  ) %}

  {# --- every derived expression declares what it references --- #}
  {% set full_plan = jstark.build_plan(
      'grocery', [], [jstark.parse_feature_period('3m1')], as_at, 'Monday',
      false, cols, []
  ) %}
  {% do jstark_assert_equal(
      failures, 'grocery declares all its dependencies',
      jstark.undeclared_dependencies(full_plan), []
  ) %}

  {# --- the entry point is equivalent to calling the engine directly --- #}
  {% if target.type == 'duckdb' %}
    {% do jstark_assert_equal(
        failures, 'grocery_features delegates to generate_features',
        jstark_normalise_sql(jstark.grocery_features(
            input='select * from t', group_by=['customer'], as_at='2022-01-01',
            feature_periods=['3m1'], feature_stems=['BasketCount']
        )),
        jstark_normalise_sql(jstark.generate_features(
            input='select * from t', group_by=['customer'], generator='grocery',
            as_at='2022-01-01', feature_periods=['3m1'],
            feature_stems=['BasketCount']
        ))
    ) %}
  {% endif %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_grocery(failures) %}
```

Run it:
```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `grocery catalogue size: expected 37 but got 20`.

- [ ] **Step 3: Write the grocery base features**

Replace the whole of `macros/grocery/features/grocery_base.sql`:
```sql
{#
  Grocery-specific features.

  register_grocery_features runs after register_core_features, so the core
  aggregates it depends on (GrossSpend, Quantity, Discount, RecencyDays,
  EarliestPurchaseDate, MostRecentPurchaseDate) are already registered.
#}

{% macro register_grocery_features(definitions, ctx) %}
  {% do jstark.register_grocery_base_features(definitions, ctx) %}
  {% do jstark.register_grocery_average_features(definitions, ctx) %}
  {% do jstark.register_grocery_periodic_features(definitions, ctx) %}
{% endmacro %}


{% macro register_grocery_base_features(definitions, ctx) %}

  {% do definitions.update({'BasketCount': {
      'stem': 'BasketCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['basket'],
      'default': '0',
      'required_columns': ['event_timestamp', 'basket'],
      'description_subject': 'Distinct count of Baskets',
      'commentary': '<verbatim from jstark BasketCount.commentary>'
  }}) %}

  {% do definitions.update({'ApproxBasketCount': {
      'stem': 'ApproxBasketCount',
      'kind': 'base',
      'aggregator': 'approx_count_distinct',
      'expression': ctx['cols']['basket'],
      'default': '0',
      'required_columns': ['event_timestamp', 'basket'],
      'description_subject': 'Approximate distinct count of Baskets',
      'commentary': '<verbatim from jstark ApproxBasketCount.commentary>'
  }}) %}

  {% do definitions.update({'StoreCount': {
      'stem': 'StoreCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['store'],
      'default': '0',
      'required_columns': ['event_timestamp', 'store'],
      'description_subject': 'Distinct count of Stores',
      'commentary': '<verbatim from jstark StoreCount.commentary>'
  }}) %}

  {% do definitions.update({'ChannelCount': {
      'stem': 'ChannelCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['channel'],
      'default': '0',
      'required_columns': ['event_timestamp', 'channel'],
      'description_subject': 'Distinct count of Channels',
      'commentary': '<verbatim from jstark ChannelCount.commentary>'
  }}) %}

{% endmacro %}
```

- [ ] **Step 4: Write the grocery average features**

`macros/grocery/features/grocery_averages.sql`:
```sql
{#
  Per-basket averages, the purchase cycle, and how many cycles have elapsed
  since the last purchase.

  CyclesSinceLastPurchase depends on AvgPurchaseCycle, which is itself derived.
  That two-deep chain is why the engine levels dependencies into separate CTEs
  rather than computing every derived feature in one pass.
#}

{% macro register_grocery_average_features(definitions, ctx) %}

  {% set period = ctx['period'] %}
  {% set basket_count = jstark.column_name('BasketCount', period) %}

  {% do definitions.update({'AvgGrossSpendPerBasket': {
      'stem': 'AvgGrossSpendPerBasket',
      'kind': 'derived',
      'depends_on': [['GrossSpend', period], ['BasketCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('GrossSpend', period), basket_count
      ),
      'default': 'null',
      'description_subject': 'Average GrossSpend per Basket',
      'commentary': '<verbatim from jstark AvgGrossSpendPerBasket.commentary>'
  }}) %}

  {% do definitions.update({'AvgQuantityPerBasket': {
      'stem': 'AvgQuantityPerBasket',
      'kind': 'derived',
      'depends_on': [['Quantity', period], ['BasketCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('Quantity', period), basket_count
      ),
      'default': 'null',
      'description_subject': 'Average Quantity per Basket',
      'commentary': '<verbatim from jstark AvgQuantityPerBasket.commentary>'
  }}) %}

  {% do definitions.update({'AvgDiscountPerBasket': {
      'stem': 'AvgDiscountPerBasket',
      'kind': 'derived',
      'depends_on': [['Discount', period], ['BasketCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('Discount', period), basket_count
      ),
      'default': 'null',
      'description_subject': 'Average Discount per Basket',
      'commentary': '<verbatim from jstark AvgDiscountPerBasket.commentary>'
  }}) %}

  {% do definitions.update({'AvgPurchaseCycle': {
      'stem': 'AvgPurchaseCycle',
      'kind': 'derived',
      'depends_on': [
          ['EarliestPurchaseDate', period],
          ['MostRecentPurchaseDate', period],
          ['BasketCount', period]
      ],
      'expression': jstark.safe_divide(
          dbt.datediff(
              jstark.column_name('EarliestPurchaseDate', period),
              jstark.column_name('MostRecentPurchaseDate', period),
              'day'
          ),
          basket_count
      ),
      'default': 'null',
      'description_subject': 'Average purchase cycle',
      'commentary': '<verbatim from jstark AvgPurchaseCycle.commentary>'
  }}) %}

  {% do definitions.update({'CyclesSinceLastPurchase': {
      'stem': 'CyclesSinceLastPurchase',
      'kind': 'derived',
      'depends_on': [['RecencyDays', period], ['AvgPurchaseCycle', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('RecencyDays', period),
          jstark.column_name('AvgPurchaseCycle', period)
      ),
      'default': 'null',
      'description_subject': 'Cycles since last purchase',
      'commentary': '<verbatim from jstark CyclesSinceLastPurchase.commentary>'
  }}) %}

{% endmacro %}
```

- [ ] **Step 5: Write the grocery periodic features**

`macros/grocery/features/grocery_periodic.sql`:
```sql
{#
  Features that look at each whole unit inside the window separately, rather
  than at the window as a whole. For 3m1 that means October, November and
  December individually.

  Those per-unit aggregates are dependencies at periods the caller never asked
  for (3m3, 2m2, 1m1). The engine computes them in the base CTE and drops them
  from the final projection, so BasketPeriods and RecencyWeightedBasket* share
  one set of them rather than each computing its own.

  The exponential weights are evaluated here in Jinja, so the emitted SQL
  contains plain float literals and never calls power() — one less thing to
  differ between warehouses.
#}

{% macro register_grocery_periodic_features(definitions, ctx) %}

  {% set period = ctx['period'] %}
  {% set unit = jstark.period_unit_name(period['uom']) | lower %}
  {% set sub_periods = jstark.single_unit_periods(period) %}

  {#- BasketPeriods: how many whole units saw at least one basket.
      ACTIVITY_STEM is whichever aggregate jstark tests; see Step 1. -%}
  {% set activity_stem = 'Count' %}
  {% set terms = [] %}
  {% set deps = [] %}
  {% for sub in sub_periods %}
    {% set column = jstark.column_name(activity_stem, sub) %}
    {% do terms.append('case when ' ~ column ~ ' > 0 then 1 else 0 end') %}
    {% do deps.append([activity_stem, sub]) %}
  {% endfor %}
  {% do definitions.update({'BasketPeriods': {
      'stem': 'BasketPeriods',
      'kind': 'derived',
      'depends_on': deps,
      'expression': terms | join(' + '),
      'default': 'null',
      'description_subject': 'Number of ' ~ unit
                             ~ 's in which at least one basket was purchased',
      'commentary': '<verbatim from jstark BasketMonths.commentary>'
  }}) %}

  {#- AvgBasket: baskets per whole unit across the window -#}
  {% do definitions.update({'AvgBasket': {
      'stem': 'AvgBasket',
      'kind': 'derived',
      'depends_on': [['Count', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('Count', period),
          period['number_of_periods'] | string
      ),
      'default': 'null',
      'description_subject': 'Average number of baskets per ' ~ unit,
      'commentary': '<verbatim from jstark AverageBasketsPerMonth.commentary>'
  }}) %}

  {#- the six recency-weighted variants: three smoothing factors, exact and
      approximate basket counts -#}
  {% for variant in [
      {'stem_prefix': 'RecencyWeightedBasket', 'count_stem': 'BasketCount',
       'adjective': ''},
      {'stem_prefix': 'RecencyWeightedApproxBasket',
       'count_stem': 'ApproxBasketCount', 'adjective': 'approximate '}
  ] %}
    {% for smoothing_factor in [0.9, 0.95, 0.99] %}
      {% set suffix = (smoothing_factor * 100) | round | int | string %}
      {% set weighted_terms = [] %}
      {% set weighted_deps = [] %}
      {% for sub in sub_periods %}
        {% do weighted_terms.append(
            jstark.column_name(variant['count_stem'], sub)
            ~ ' * ' ~ (smoothing_factor ** sub['start'])
        ) %}
        {% do weighted_deps.append([variant['count_stem'], sub]) %}
      {% endfor %}
      {% do definitions.update({variant['stem_prefix'] ~ suffix: {
          'stem': variant['stem_prefix'] ~ suffix,
          'kind': 'derived',
          'depends_on': weighted_deps,
          'expression': weighted_terms | join(' + '),
          'default': 'null',
          'description_subject':
              'Exponentially weighted moving average, with smoothing factor of '
              ~ smoothing_factor ~ ', of the ' ~ variant['adjective']
              ~ 'number of baskets per ' ~ unit,
          'commentary': '<verbatim from the matching jstark class commentary>'
      }}) %}
    {% endfor %}
  {% endfor %}

{% endmacro %}
```

`suffix` derives `'90'`, `'95'` and `'99'` from the factor rather than being listed separately, so the stem and the description can never disagree about which factor a feature uses.

- [ ] **Step 6: Write the entry point**

`macros/grocery/grocery_features.sql`:
```sql
{#
  Public entry point for grocery feature generation.

  Thin by design: it names the generator and forwards everything else, so
  there is exactly one implementation of the parameter handling.

  Usage:
    {{ jstark.grocery_features(
        input=ref('transactions'),
        group_by=['customer'],
        as_at='2022-01-01',
        feature_periods=['3m1', '52w0']
    ) }}
#}

{% macro grocery_features(
    input,
    group_by,
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={}
) %}
  {{ jstark.generate_features(
      input=input,
      group_by=group_by,
      generator='grocery',
      as_at=as_at,
      feature_periods=feature_periods,
      feature_stems=feature_stems,
      first_day_of_week=first_day_of_week,
      use_absolute_periods=use_absolute_periods,
      column_map=column_map
  ) }}
{% endmacro %}
```

- [ ] **Step 7: Run the L1 test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 8: Add the L2 model and unit test**

`integration_tests/seeds/grocery_transactions.csv`:
```csv
customer,basket,store,channel,product,event_timestamp,quantity,gross_spend,net_spend,discount
c1,b1,s1,online,p1,2021-10-01,2,10.0,8.0,2.0
c1,b1,s1,online,p2,2021-10-01,2,6.0,6.0,0.0
c1,b2,s2,store,p1,2021-12-30,4,16.0,14.0,2.0
c1,b3,s1,online,p1,2022-01-01,9,99.0,99.0,9.0
```

`integration_tests/models/grocery/grocery_specific_features.sql` — only the 17 grocery-specific stems, so the fixture stays readable; the core 20 are already covered by Task 10:
```sql
{{ jstark.grocery_features(
    input=ref('grocery_transactions'),
    group_by=['customer'],
    as_at='2022-01-01',
    feature_periods=['3m1'],
    feature_stems=[
        'BasketCount', 'ApproxBasketCount', 'StoreCount', 'ChannelCount',
        'AvgGrossSpendPerBasket', 'AvgQuantityPerBasket', 'AvgDiscountPerBasket',
        'AvgPurchaseCycle', 'CyclesSinceLastPurchase', 'BasketPeriods',
        'AvgBasket', 'RecencyWeightedBasket90', 'RecencyWeightedBasket95',
        'RecencyWeightedBasket99', 'RecencyWeightedApproxBasket90',
        'RecencyWeightedApproxBasket95', 'RecencyWeightedApproxBasket99'
    ]
) }}
```

`integration_tests/models/grocery/grocery_all_features.sql` — all 37, to prove the whole catalogue compiles and runs:
```sql
{{ jstark.grocery_features(
    input=ref('grocery_transactions'),
    group_by=['customer', 'store'],
    as_at='2022-01-01',
    feature_periods=['3m1', '52w0']
) }}
```

`integration_tests/models/grocery/_grocery.yml`:
```yaml
version: 2

models:
  - name: grocery_specific_features
    description: The 17 grocery-specific features over a 3m1 period.
  - name: grocery_all_features
    description: >
      All 37 grocery features over two periods and two grouping columns. Built
      but not asserted on value-by-value; its job is to prove the whole
      catalogue compiles and runs.

unit_tests:
  - name: grocery_specific_features_values
    description: >
      Two baskets in the window, one in October and one in December, with
      November empty so that BasketPeriods is 2 rather than 3. A fourth row on
      2022-01-01 falls outside the window and must be excluded.
    model: grocery_specific_features
    given:
      - input: ref('grocery_transactions')
        format: sql
        rows: |
          select 'c1' as customer, 'b1' as basket, 's1' as store,
                 'online' as channel, 'p1' as product,
                 cast('2021-10-01' as date) as event_timestamp,
                 2 as quantity, cast(10.0 as double) as gross_spend,
                 cast(8.0 as double) as net_spend, cast(2.0 as double) as discount
          union all
          select 'c1', 'b1', 's1', 'online', 'p2', cast('2021-10-01' as date), 2,
                 cast(6.0 as double), cast(6.0 as double), cast(0.0 as double)
          union all
          select 'c1', 'b2', 's2', 'store', 'p1', cast('2021-12-30' as date), 4,
                 cast(16.0 as double), cast(14.0 as double), cast(2.0 as double)
          union all
          select 'c1', 'b3', 's1', 'online', 'p1', cast('2022-01-01' as date), 9,
                 cast(99.0 as double), cast(99.0 as double), cast(9.0 as double)
    expect:
      format: sql
      rows: |
          select 'c1' as customer,
                 2 as basket_count_3m1,
                 2 as approx_basket_count_3m1,
                 2 as store_count_3m1,
                 2 as channel_count_3m1,
                 cast(16.0 as double) as avg_gross_spend_per_basket_3m1,
                 cast(4.0 as double) as avg_quantity_per_basket_3m1,
                 cast(2.0 as double) as avg_discount_per_basket_3m1,
                 cast(45.0 as double) as avg_purchase_cycle_3m1,
                 cast(2.0 as double) / 45.0 as cycles_since_last_purchase_3m1,
                 2 as basket_months_3m1,
                 cast(3.0 as double) / 3.0 as average_baskets_per_month_3m1,
                 cast({{ 1 * (0.9 ** 1) + 0 * (0.9 ** 2) + 1 * (0.9 ** 3) }} as double)
                   as recency_weighted_basket_months90_3m1,
                 cast({{ 1 * (0.95 ** 1) + 0 * (0.95 ** 2) + 1 * (0.95 ** 3) }} as double)
                   as recency_weighted_basket_months95_3m1,
                 cast({{ 1 * (0.99 ** 1) + 0 * (0.99 ** 2) + 1 * (0.99 ** 3) }} as double)
                   as recency_weighted_basket_months99_3m1,
                 cast({{ 1 * (0.9 ** 1) + 0 * (0.9 ** 2) + 1 * (0.9 ** 3) }} as double)
                   as recency_weighted_approx_basket_months90_3m1,
                 cast({{ 1 * (0.95 ** 1) + 0 * (0.95 ** 2) + 1 * (0.95 ** 3) }} as double)
                   as recency_weighted_approx_basket_months95_3m1,
                 cast({{ 1 * (0.99 ** 1) + 0 * (0.99 ** 2) + 1 * (0.99 ** 3) }} as double)
                   as recency_weighted_approx_basket_months99_3m1
```

Where the expected value is awkward to write as a decimal it is written as the arithmetic instead — `cast(2.0 as double) / 45.0`, and Jinja-evaluated weights for the recency-weighted features. Both sides are then computed as IEEE doubles by the same engine in the same order, so they are bit-identical, and nobody has to transcribe seventeen significant figures correctly.

The derivations: gross spend in the window is 32.0 over 2 baskets, so `avg_gross_spend_per_basket` is 16.0; quantity 8 over 2 baskets is 4.0; discount 4.0 over 2 baskets is 2.0; the first and last purchases are 90 days apart, so `avg_purchase_cycle` is 45.0; the last purchase is 2 days before `as_at`, so `recency_days` is 2. October and December each contain a row and November does not, so `basket_months` is 2 and the recency weights for `2m2` are multiplied by a count of zero.

- [ ] **Step 9: Add dbt_utils and the L3 seed-equality test**

Modify `integration_tests/packages.yml`:
```yaml
packages:
  - local: ../
  - package: dbt-labs/dbt_utils
    version: [">=1.1.0", "<2.0.0"]
```

Create `integration_tests/seeds/expected_grocery_features.csv` by generating it rather than hand-writing it:
```bash
cd integration_tests
uv run dbt deps
uv run dbt seed --profiles-dir .
uv run dbt run --select grocery_specific_features --profiles-dir .
uv run dbt show --select grocery_specific_features --limit 50 \
  --output json --profiles-dir . > /tmp/grocery_actual.json
```
Read `/tmp/grocery_actual.json`, check every value against the unit-test expectations above, and only then write it out as `expected_grocery_features.csv` with a header row of the 18 column names. Generating the fixture from the output is only safe because the values have already been asserted independently by the unit test — do not skip that check.

Add to `integration_tests/models/grocery/_grocery.yml` under `models: - name: grocery_specific_features`:
```yaml
    tests:
      - dbt_utils.equality:
          compare_model: ref('expected_grocery_features')
```

- [ ] **Step 10: Run everything**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
uv run dbt build --profiles-dir .
```
Expected: PASS. `dbt build` covers the unit tests, both models and the equality test.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add the 17 grocery features and the grocery_features entry point

Includes the first derived-on-derived chain: CyclesSinceLastPurchase depends
on AvgPurchaseCycle, which depends on base aggregates, so grocery exercises
the levelling from the previous commit rather than just describing it.

The periodic features (BasketPeriods, AvgBasket and the six recency-weighted
variants) depend on aggregates at periods the caller never asked for. Those
land in the base CTE and are dropped from the projection, so all of them share
one set of per-month aggregates.

Exponential weights are evaluated in Jinja, so the SQL contains float literals
and never calls power().

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: The 13 mealkit features, per-cuisine counts, and the `mealkit_features` entry point

Mealkit is the second generator, and it differs from grocery in three ways that the design has to accommodate rather than paper over:

1. It uses only 10 of the 20 core features — `jstark.core_stems_for_mealkit()` — because spend and price have no meaning for a business selling recipe boxes at a fixed price.
2. It defines `AvgPurchaseCycle` with the same stem as grocery but a **different denominator**: orders rather than baskets. Because the catalogue is built per generator, both can exist without either knowing about the other. This is the reason `catalogue()` takes a generator name instead of merging one global registry.
3. It has features whose *set* depends on a runtime parameter: one count per entry in `cuisines`.

The table below is **exhaustive and normative**, read from jstark at `51d9083`.

**Base (level 0).** Every one has `event_timestamp` in `required_columns` alongside the column it aggregates.

| Stem | Aggregator | `expression` | `default` | `description_subject` |
|---|---|---|---|---|
| `OrderCount` | `count_distinct` | `ctx['cols']['order_id']` | `'0'` | Distinct count of Orders |
| `ApproxOrderCount` | `approx_count_distinct` | `ctx['cols']['order_id']` | `'0'` | Approximate distinct count of Orders |
| `RecipeCount` | `count_distinct` | `ctx['cols']['recipe']` | `'0'` | Distinct count of Recipes |
| `ApproxRecipeCount` | `approx_count_distinct` | `ctx['cols']['recipe']` | `'0'` | Approximate distinct count of Recipes |
| `AllergenCount` | `count_distinct` | `ctx['cols']['allergen']` | `'0'` | Distinct count of Allergens |
| `Allergens` | `collect_set` | `ctx['cols']['allergen']` | `jstark.empty_string_array()` | Set of Allergens |
| `CuisineCount` | `count_distinct` | `ctx['cols']['cuisine']` | `'0'` | Distinct count of Cuisines |
| `Cuisines` | `collect_set` | `ctx['cols']['cuisine']` | `jstark.empty_string_array()` | Set of Cuisines |

**Derived**, all with `default: 'null'`:

| Stem | `depends_on` | `expression` | `description_subject` |
|---|---|---|---|
| `AvgQuantityPerOrder` | `Quantity`, `OrderCount` at `P` | `jstark.safe_divide(col(Quantity), col(OrderCount))` | Average Quantity per Order |
| `AvgPurchaseCycle` | `EarliestPurchaseDate`, `MostRecentPurchaseDate`, `OrderCount` at `P` | `jstark.safe_divide(dbt.datediff(col(EarliestPurchaseDate), col(MostRecentPurchaseDate), 'day'), col(OrderCount))` | Average purchase cycle |
| `CyclesSinceLastOrder` | `RecencyDays`, `AvgPurchaseCycle` at `P` | `jstark.safe_divide(col(RecencyDays), col(AvgPurchaseCycle))` | Cycles since last order |
| `OrderPeriods` | the activity aggregate at each of `single_unit_periods(P)` | `' + '` joined `case when <col> > 0 then 1 else 0 end` | `'Number of ' ~ unit ~ 's in which at least one order was placed'` |
| `AvgOrder` | `Count` at `P` | `jstark.safe_divide(col(Count), P['number_of_periods'] \| string)` | `'Average number of orders per ' ~ unit` |

**Per-cuisine, one per entry in `cuisines`** (base, level 0):

| | |
|---|---|
| Stem | `<cuisine> ~ 'CuisineCount'` — so `'South African'` gives `South AfricanCuisineCount` |
| Aggregator | `count_if` |
| `expression` | `ctx['cols']['cuisine'] ~ " = '" ~ cuisine ~ "'"` |
| `default` | `'0'` |
| `description_subject` | `'Count of ' ~ cuisine ~ ' Cuisine'` |
| Column name | `jstark.snake_case(stem)` handles the space: `south_african_cuisine_count` |

Nothing special is needed to make that stem snake-case correctly. `snake_case` replaces runs of non-alphanumerics with `_` before splitting camel humps, so `'South AfricanCuisineCount'` becomes `south_african_cuisine_count` without a name override.

**A deliberate divergence from jstark.** jstark hard-codes its cuisine list and has inherited three typos in it: `IsrealiCuisineCount`, `FusionCuisineCusiineCount`, and a hyphen-stripping bug that produces `SouthHyphenAfricanCuisineCount`. Because the cuisines here are a caller-supplied parameter, those names cannot arise, and reproducing them would mean shipping deliberately misspelled columns. Note the divergence in the README (Task 14) so anyone migrating from jstark knows the column names differ.

**Interfaces:**
- Consumes: everything from Tasks 6-9, plus `jstark.core_stems_for_mealkit()` from Task 10 and the `register_grocery_features` shape from Task 11.
- Produces:
  - `jstark.mealkit_features(input, group_by, as_at=none, feature_periods=none, feature_stems=none, first_day_of_week=none, use_absolute_periods=false, column_map={}, cuisines=[])` → the SQL string.
  - `jstark.register_mealkit_features(definitions, ctx)`, mutating `definitions` in place.
  - `jstark.empty_string_array()` → a portable empty-array-of-strings literal.

- [ ] **Step 1: Confirm the details against the pinned jstark source**

```bash
ls /tmp/jstark-ref/jstark/features/mealkit/
grep -rn -A6 'def commentary\|def description_subject\|def default_value' \
  /tmp/jstark-ref/jstark/features/mealkit/
grep -rn 'CuisineCount\|cuisines' /tmp/jstark-ref/jstark/mealkit_feature_generator.py
```

Confirm three things and copy the `commentary` strings verbatim as in Task 10 Step 1:

1. **Which aggregate `OrderPeriods` tests for activity** — as with `BasketPeriods` in Task 11, use whichever the source uses so the two stay consistent.
2. **The default for `Allergens` and `Cuisines`.** In Spark, `collect_set` over zero matching rows returns an empty array, not null, so jstark most likely defaults to `f.array()`. If the source defaults to null instead, use `'null'` and skip Step 3.
3. **The `description_subject` wording for the per-cuisine counts.**

- [ ] **Step 2: Write the failing L1 test**

Create `integration_tests/macros/tests/test_mealkit.sql`:
```sql
{% macro jstark_test_mealkit(failures) %}

  {% set d = modules.datetime.date %}
  {% set as_at = d(2022, 1, 1) %}
  {% set cols = jstark.resolve_columns({}) %}
  {% set cuisines = ['Italian', 'Thai', 'South African'] %}
  {% set ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, cuisines
  ) %}
  {% set cat = jstark.catalogue('mealkit', ctx) %}

  {# --- mealkit is 10 core features plus 13 of its own plus one per cuisine --- #}
  {% do jstark_assert_equal(
      failures, 'mealkit catalogue size', cat | length, 10 + 13 + 3
  ) %}

  {# --- and only those 10 core features --- #}
  {% set core_cat = jstark.catalogue('core', ctx) %}
  {% for stem in jstark.core_stems_for_mealkit() %}
    {% do jstark_assert_true(
        failures, 'mealkit includes core ' ~ stem, stem in cat
    ) %}
  {% endfor %}
  {% for stem in core_cat %}
    {% if stem not in jstark.core_stems_for_mealkit() %}
      {% do jstark_assert_true(
          failures, 'mealkit excludes core ' ~ stem, stem not in cat
      ) %}
    {% endif %}
  {% endfor %}
  {% do jstark_assert_true(
      failures, 'mealkit has no spend features', 'GrossSpend' not in cat
  ) %}
  {% do jstark_assert_true(
      failures, 'mealkit has no price features', 'MinNetPrice' not in cat
  ) %}

  {% set mealkit_only = [
      'OrderCount', 'ApproxOrderCount', 'RecipeCount', 'ApproxRecipeCount',
      'AllergenCount', 'Allergens', 'CuisineCount', 'Cuisines',
      'AvgQuantityPerOrder', 'AvgPurchaseCycle', 'CyclesSinceLastOrder',
      'OrderPeriods', 'AvgOrder'
  ] %}
  {% for stem in mealkit_only %}
    {% do jstark_assert_true(
        failures, 'mealkit catalogue contains ' ~ stem, stem in cat
    ) %}
  {% endfor %}

  {# --- AvgPurchaseCycle is per-order here and per-basket in grocery --- #}
  {% do jstark_assert_contains(
      failures, 'mealkit AvgPurchaseCycle divides by orders',
      cat['AvgPurchaseCycle']['expression'], 'order_count_3m1'
  ) %}
  {% set grocery_ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_contains(
      failures, 'grocery AvgPurchaseCycle divides by baskets',
      jstark.catalogue('grocery', grocery_ctx)['AvgPurchaseCycle']['expression'],
      'basket_count_3m1'
  ) %}

  {# --- unit-dependent names --- #}
  {% do jstark_assert_equal(
      failures, 'OrderPeriods name for a monthly period',
      jstark.column_name('OrderPeriods', ctx['period']), 'order_months_3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'AvgOrder name for a monthly period',
      jstark.column_name('AvgOrder', ctx['period']),
      'average_orders_per_month_3m1'
  ) %}

  {# --- one feature per cuisine, named without any special-casing --- #}
  {% do jstark_assert_equal(
      failures, 'per-cuisine column name',
      jstark.column_name('South AfricanCuisineCount', ctx['period']),
      'south_african_cuisine_count_3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'per-cuisine expression',
      cat['ItalianCuisineCount']['expression'], "cuisine = 'Italian'"
  ) %}
  {% do jstark_assert_equal(
      failures, 'per-cuisine aggregator',
      cat['ThaiCuisineCount']['aggregator'], 'count_if'
  ) %}
  {% do jstark_assert_equal(
      failures, 'per-cuisine default', cat['ThaiCuisineCount']['default'], '0'
  ) %}

  {# --- no cuisines parameter means no per-cuisine features --- #}
  {% set no_cuisine_cat = jstark.catalogue(
      'mealkit',
      jstark.feature_context(
          jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
      )
  ) %}
  {% do jstark_assert_equal(
      failures, 'mealkit catalogue size with no cuisines',
      no_cuisine_cat | length, 10 + 13
  ) %}

  {# --- the collect_set features default to an empty array, not null --- #}
  {% do jstark_assert_equal(
      failures, 'Allergens aggregator', cat['Allergens']['aggregator'], 'collect_set'
  ) %}
  {% do jstark_assert_true(
      failures, 'Allergens does not default to null',
      cat['Allergens']['default'] != 'null'
  ) %}

  {# --- mealkit is two derived levels deep, as grocery is --- #}
  {% set plan = jstark.build_plan(
      'mealkit', ['CyclesSinceLastOrder'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, cuisines
  ) %}
  {% do jstark_assert_equal(
      failures, 'CyclesSinceLastOrder is two levels deep', plan['levels'] | length, 3
  ) %}

  {% set full_plan = jstark.build_plan(
      'mealkit', [], [jstark.parse_feature_period('3m1')], as_at, 'Monday',
      false, cols, cuisines
  ) %}
  {% do jstark_assert_equal(
      failures, 'mealkit declares all its dependencies',
      jstark.undeclared_dependencies(full_plan), []
  ) %}

  {# --- the entry point is equivalent to calling the engine directly --- #}
  {% if target.type == 'duckdb' %}
    {% do jstark_assert_equal(
        failures, 'mealkit_features delegates to generate_features',
        jstark_normalise_sql(jstark.mealkit_features(
            input='select * from t', group_by=['customer'], as_at='2022-01-01',
            feature_periods=['3m1'], feature_stems=['OrderCount'],
            cuisines=cuisines
        )),
        jstark_normalise_sql(jstark.generate_features(
            input='select * from t', group_by=['customer'], generator='mealkit',
            as_at='2022-01-01', feature_periods=['3m1'],
            feature_stems=['OrderCount'], cuisines=cuisines
        ))
    ) %}
  {% endif %}

{% endmacro %}
```

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_mealkit(failures) %}
```

Run it:
```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `mealkit catalogue size: expected 26 but got 10`.

- [ ] **Step 3: Add the empty-array portability seam**

Append to `macros/core/adapters/jstark_collect_set.sql`:
```sql
{#
  A literal empty array of strings, used as the default for the collect_set
  features so that a customer with no matching rows gets [] rather than null.
  Spark's collect_set already behaves that way; SQL array_agg returns null, so
  the coalesce in the generated SQL needs something to fall back to.

  Every warehouse spells this differently and most of them need the element
  type stated, which is why it is a seam rather than a literal.
#}

{% macro empty_string_array() %}
  {{ return(adapter.dispatch('empty_string_array', 'jstark')()) }}
{% endmacro %}

{% macro default__empty_string_array() %}
  {{ return('cast(array[] as ' ~ dbt.type_string() ~ '[])') }}
{% endmacro %}

{% macro duckdb__empty_string_array() %}
  {#- DuckDB builds lists with list_value(); an argument-less call gives [] -#}
  {{ return('cast(list_value() as ' ~ dbt.type_string() ~ '[])') }}
{% endmacro %}

{% macro snowflake__empty_string_array() %}
  {#- Snowflake arrays are untyped, so no cast is needed or allowed.
      Written from the docs and not yet run against a real warehouse. -#}
  {{ return('array_construct()') }}
{% endmacro %}

{% macro bigquery__empty_string_array() %}
  {#- Written from the docs and not yet run against a real warehouse. -#}
  {{ return('array<string>[]') }}
{% endmacro %}
```

If Step 1 found that jstark defaults these two features to null, skip this step and use `'null'` in Step 4 instead.

- [ ] **Step 4: Write the mealkit base features**

Replace the whole of `macros/mealkit/features/mealkit_base.sql`:
```sql
{#
  Mealkit-specific features.

  register_mealkit_features runs after register_core_features, which for the
  mealkit generator registers only the 10 stems in core_stems_for_mealkit():
  spend and price mean nothing for a business selling recipe boxes at a fixed
  price.
#}

{% macro register_mealkit_features(definitions, ctx) %}
  {% do jstark.register_mealkit_base_features(definitions, ctx) %}
  {% do jstark.register_mealkit_average_features(definitions, ctx) %}
  {% do jstark.register_mealkit_periodic_features(definitions, ctx) %}
  {% do jstark.register_mealkit_cuisine_features(definitions, ctx) %}
{% endmacro %}


{% macro register_mealkit_base_features(definitions, ctx) %}

  {% for spec in [
      {'stem': 'OrderCount', 'aggregator': 'count_distinct', 'column': 'order_id',
       'subject': 'Distinct count of Orders'},
      {'stem': 'ApproxOrderCount', 'aggregator': 'approx_count_distinct',
       'column': 'order_id', 'subject': 'Approximate distinct count of Orders'},
      {'stem': 'RecipeCount', 'aggregator': 'count_distinct', 'column': 'recipe',
       'subject': 'Distinct count of Recipes'},
      {'stem': 'ApproxRecipeCount', 'aggregator': 'approx_count_distinct',
       'column': 'recipe', 'subject': 'Approximate distinct count of Recipes'},
      {'stem': 'AllergenCount', 'aggregator': 'count_distinct', 'column': 'allergen',
       'subject': 'Distinct count of Allergens'},
      {'stem': 'CuisineCount', 'aggregator': 'count_distinct', 'column': 'cuisine',
       'subject': 'Distinct count of Cuisines'}
  ] %}
    {% do definitions.update({spec['stem']: {
        'stem': spec['stem'],
        'kind': 'base',
        'aggregator': spec['aggregator'],
        'expression': ctx['cols'][spec['column']],
        'default': '0',
        'required_columns': ['event_timestamp', spec['column']],
        'description_subject': spec['subject'],
        'commentary': '<verbatim from the matching jstark class commentary>'
    }}) %}
  {% endfor %}

  {#- the two set-valued features. Registered after the counts so that
      allergen_count sits next to allergens in the output. -#}
  {% for spec in [
      {'stem': 'Allergens', 'column': 'allergen', 'subject': 'Set of Allergens'},
      {'stem': 'Cuisines', 'column': 'cuisine', 'subject': 'Set of Cuisines'}
  ] %}
    {% do definitions.update({spec['stem']: {
        'stem': spec['stem'],
        'kind': 'base',
        'aggregator': 'collect_set',
        'expression': ctx['cols'][spec['column']],
        'default': jstark.empty_string_array(),
        'required_columns': ['event_timestamp', spec['column']],
        'description_subject': spec['subject'],
        'commentary': '<verbatim from the matching jstark class commentary>'
    }}) %}
  {% endfor %}

{% endmacro %}
```

The six counting features are registered from a list because they differ only in stem, aggregator and column. That is not true of the grocery base features in Task 11, which is why those are written out one at a time — do not retrofit this loop onto them just for symmetry.

Registration order fixes column order, so `AllergenCount` and `CuisineCount` come before `Allergens` and `Cuisines` in the emitted SQL. If Step 1 shows jstark ordering them differently and matching that matters, reorder here.

- [ ] **Step 5: Write the mealkit average features**

`macros/mealkit/features/mealkit_averages.sql`:
```sql
{#
  Per-order averages, the purchase cycle, and cycles since the last order.

  AvgPurchaseCycle has the same stem as the grocery feature but divides by
  orders rather than baskets. Because the catalogue is built per generator,
  the two definitions never meet.
#}

{% macro register_mealkit_average_features(definitions, ctx) %}

  {% set period = ctx['period'] %}
  {% set order_count = jstark.column_name('OrderCount', period) %}

  {% do definitions.update({'AvgQuantityPerOrder': {
      'stem': 'AvgQuantityPerOrder',
      'kind': 'derived',
      'depends_on': [['Quantity', period], ['OrderCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('Quantity', period), order_count
      ),
      'default': 'null',
      'description_subject': 'Average Quantity per Order',
      'commentary': '<verbatim from jstark AvgQuantityPerOrder.commentary>'
  }}) %}

  {% do definitions.update({'AvgPurchaseCycle': {
      'stem': 'AvgPurchaseCycle',
      'kind': 'derived',
      'depends_on': [
          ['EarliestPurchaseDate', period],
          ['MostRecentPurchaseDate', period],
          ['OrderCount', period]
      ],
      'expression': jstark.safe_divide(
          dbt.datediff(
              jstark.column_name('EarliestPurchaseDate', period),
              jstark.column_name('MostRecentPurchaseDate', period),
              'day'
          ),
          order_count
      ),
      'default': 'null',
      'description_subject': 'Average purchase cycle',
      'commentary': '<verbatim from jstark AvgPurchaseCycle.commentary>'
  }}) %}

  {% do definitions.update({'CyclesSinceLastOrder': {
      'stem': 'CyclesSinceLastOrder',
      'kind': 'derived',
      'depends_on': [['RecencyDays', period], ['AvgPurchaseCycle', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('RecencyDays', period),
          jstark.column_name('AvgPurchaseCycle', period)
      ),
      'default': 'null',
      'description_subject': 'Cycles since last order',
      'commentary': '<verbatim from jstark CyclesSinceLastOrder.commentary>'
  }}) %}

{% endmacro %}
```

- [ ] **Step 6: Write the mealkit periodic features**

`macros/mealkit/features/mealkit_periodic.sql`:
```sql
{#
  Features that look at each whole unit inside the window separately. See the
  equivalent grocery file for why the per-unit aggregates are dependencies at
  periods the caller never asked for.

  Mealkit has no recency-weighted variants; jstark defines those for grocery
  only.
#}

{% macro register_mealkit_periodic_features(definitions, ctx) %}

  {% set period = ctx['period'] %}
  {% set unit = jstark.period_unit_name(period['uom']) | lower %}

  {#- ACTIVITY_STEM must match the grocery choice; see Task 11 Step 1 -#}
  {% set activity_stem = 'Count' %}
  {% set terms = [] %}
  {% set deps = [] %}
  {% for sub in jstark.single_unit_periods(period) %}
    {% set column = jstark.column_name(activity_stem, sub) %}
    {% do terms.append('case when ' ~ column ~ ' > 0 then 1 else 0 end') %}
    {% do deps.append([activity_stem, sub]) %}
  {% endfor %}
  {% do definitions.update({'OrderPeriods': {
      'stem': 'OrderPeriods',
      'kind': 'derived',
      'depends_on': deps,
      'expression': terms | join(' + '),
      'default': 'null',
      'description_subject': 'Number of ' ~ unit
                             ~ 's in which at least one order was placed',
      'commentary': '<verbatim from jstark OrderMonths.commentary>'
  }}) %}

  {% do definitions.update({'AvgOrder': {
      'stem': 'AvgOrder',
      'kind': 'derived',
      'depends_on': [['Count', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('Count', period),
          period['number_of_periods'] | string
      ),
      'default': 'null',
      'description_subject': 'Average number of orders per ' ~ unit,
      'commentary': '<verbatim from jstark AverageOrdersPerMonth.commentary>'
  }}) %}

{% endmacro %}
```

- [ ] **Step 7: Write the per-cuisine features**

`macros/mealkit/features/mealkit_cuisines.sql`:
```sql
{#
  One count per cuisine the caller asked about.

  jstark hard-codes its cuisine list; here it is a parameter, so the feature
  set is decided at compile time from `cuisines`. That also means the three
  misspelled column names jstark has inherited cannot arise.

  The stem is the cuisine name concatenated with 'CuisineCount', spaces and
  all. snake_case turns runs of non-alphanumerics into underscores before it
  splits camel humps, so 'South AfricanCuisineCount' becomes
  south_african_cuisine_count with no special-casing.
#}

{% macro register_mealkit_cuisine_features(definitions, ctx) %}

  {% for cuisine in ctx['cuisines'] %}
    {% set stem = cuisine ~ 'CuisineCount' %}
    {% do definitions.update({stem: {
        'stem': stem,
        'kind': 'base',
        'aggregator': 'count_if',
        'expression': ctx['cols']['cuisine'] ~ " = '" ~ cuisine ~ "'",
        'default': '0',
        'required_columns': ['event_timestamp', 'cuisine'],
        'description_subject': 'Count of ' ~ cuisine ~ ' Cuisine',
        'commentary': '<verbatim from a jstark *CuisineCount class commentary>'
    }}) %}
  {% endfor %}

{% endmacro %}
```

A cuisine name containing an apostrophe would break the generated SQL. That is out of scope: the parameter is developer-supplied at compile time, not user input, and no cuisine in jstark's list contains one. Note it in `CONTRIBUTING.md` (Task 14) rather than adding quoting here.

- [ ] **Step 8: Write the entry point**

`macros/mealkit/mealkit_features.sql`:
```sql
{#
  Public entry point for mealkit feature generation.

  Identical to grocery_features except for the generator name and the extra
  `cuisines` parameter, which decides how many per-cuisine counts to emit.

  Usage:
    {{ jstark.mealkit_features(
        input=ref('orders'),
        group_by=['customer'],
        as_at='2022-01-01',
        feature_periods=['3m1'],
        cuisines=['Italian', 'Thai', 'South African']
    ) }}
#}

{% macro mealkit_features(
    input,
    group_by,
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={},
    cuisines=[]
) %}
  {{ jstark.generate_features(
      input=input,
      group_by=group_by,
      generator='mealkit',
      as_at=as_at,
      feature_periods=feature_periods,
      feature_stems=feature_stems,
      first_day_of_week=first_day_of_week,
      use_absolute_periods=use_absolute_periods,
      column_map=column_map,
      cuisines=cuisines
  ) }}
{% endmacro %}
```

- [ ] **Step 9: Run the L1 test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 10: Add the L2 models and unit tests**

`integration_tests/seeds/mealkit_orders.csv`:
```csv
customer,order_id,recipe,cuisine,allergen,product,event_timestamp,quantity
c1,o1,r1,Italian,gluten,p1,2021-10-01,2
c1,o1,r2,Thai,nuts,p2,2021-10-01,2
c1,o2,r1,Italian,gluten,p1,2021-12-30,4
c1,o3,r3,Mexican,soy,p3,2022-01-01,9
```

`integration_tests/models/mealkit/mealkit_scalar_features.sql` — every mealkit-specific feature except the two array-valued ones, which are tested separately:
```sql
{{ jstark.mealkit_features(
    input=ref('mealkit_orders'),
    group_by=['customer'],
    as_at='2022-01-01',
    feature_periods=['3m1'],
    feature_stems=[
        'OrderCount', 'ApproxOrderCount', 'RecipeCount', 'ApproxRecipeCount',
        'AllergenCount', 'CuisineCount', 'AvgQuantityPerOrder',
        'AvgPurchaseCycle', 'CyclesSinceLastOrder', 'OrderPeriods', 'AvgOrder',
        'ItalianCuisineCount', 'ThaiCuisineCount', 'South AfricanCuisineCount'
    ],
    cuisines=['Italian', 'Thai', 'South African']
) }}
```

`integration_tests/models/mealkit/mealkit_set_features.sql`:
```sql
{{ jstark.mealkit_features(
    input=ref('mealkit_orders'),
    group_by=['customer'],
    as_at='2022-01-01',
    feature_periods=['3m1'],
    feature_stems=['Allergens', 'Cuisines']
) }}
```

`integration_tests/models/mealkit/mealkit_all_features.sql` — all 23 plus three cuisines, to prove the whole catalogue compiles and runs:
```sql
{{ jstark.mealkit_features(
    input=ref('mealkit_orders'),
    group_by=['customer'],
    as_at='2022-01-01',
    feature_periods=['3m1', '52w0'],
    cuisines=['Italian', 'Thai', 'South African']
) }}
```

`integration_tests/models/mealkit/_mealkit.yml`:
```yaml
version: 2

models:
  - name: mealkit_scalar_features
    description: Every scalar mealkit-specific feature over a 3m1 period.
  - name: mealkit_set_features
    description: The two set-valued mealkit features, Allergens and Cuisines.
  - name: mealkit_all_features
    description: >
      All 23 mealkit features plus three per-cuisine counts over two periods.
      Built but not asserted on value-by-value; its job is to prove the whole
      catalogue compiles and runs.

unit_tests:
  - name: mealkit_scalar_features_values
    description: >
      Two orders in the window, one in October and one in December, with
      November empty so that OrderPeriods is 2. A third order on 2022-01-01
      falls outside the window and must be excluded, which is also what makes
      the Mexican rows invisible to the per-cuisine counts.
    model: mealkit_scalar_features
    given:
      - input: ref('mealkit_orders')
        format: sql
        rows: |
          select 'c1' as customer, 'o1' as order_id, 'r1' as recipe,
                 'Italian' as cuisine, 'gluten' as allergen, 'p1' as product,
                 cast('2021-10-01' as date) as event_timestamp, 2 as quantity
          union all
          select 'c1', 'o1', 'r2', 'Thai', 'nuts', 'p2',
                 cast('2021-10-01' as date), 2
          union all
          select 'c1', 'o2', 'r1', 'Italian', 'gluten', 'p1',
                 cast('2021-12-30' as date), 4
          union all
          select 'c1', 'o3', 'r3', 'Mexican', 'soy', 'p3',
                 cast('2022-01-01' as date), 9
    expect:
      format: sql
      rows: |
          select 'c1' as customer,
                 2 as order_count_3m1,
                 2 as approx_order_count_3m1,
                 2 as recipe_count_3m1,
                 2 as approx_recipe_count_3m1,
                 2 as allergen_count_3m1,
                 2 as cuisine_count_3m1,
                 cast(4.0 as double) as avg_quantity_per_order_3m1,
                 cast(45.0 as double) as avg_purchase_cycle_3m1,
                 cast(2.0 as double) / 45.0 as cycles_since_last_order_3m1,
                 2 as order_months_3m1,
                 cast(3.0 as double) / 3.0 as average_orders_per_month_3m1,
                 2 as italian_cuisine_count_3m1,
                 1 as thai_cuisine_count_3m1,
                 0 as south_african_cuisine_count_3m1

  - name: mealkit_set_features_values
    description: >
      Allergens and Cuisines come back sorted, with the out-of-window soy and
      Mexican values excluded. Kept separate from the scalar test because the
      array literals below are DuckDB syntax.
    model: mealkit_set_features
    config:
      tags: ['duckdb_only']
    given:
      - input: ref('mealkit_orders')
        format: sql
        rows: |
          select 'c1' as customer, 'o1' as order_id, 'r1' as recipe,
                 'Italian' as cuisine, 'gluten' as allergen, 'p1' as product,
                 cast('2021-10-01' as date) as event_timestamp, 2 as quantity
          union all
          select 'c1', 'o1', 'r2', 'Thai', 'nuts', 'p2',
                 cast('2021-10-01' as date), 2
          union all
          select 'c1', 'o3', 'r3', 'Mexican', 'soy', 'p3',
                 cast('2022-01-01' as date), 9
    expect:
      format: sql
      rows: |
          select 'c1' as customer,
                 cast(['gluten', 'nuts'] as varchar[]) as allergens_3m1,
                 cast(['Italian', 'Thai'] as varchar[]) as cuisines_3m1

  - name: mealkit_set_features_default_to_empty_arrays
    description: >
      A customer with no rows in the window gets empty arrays rather than
      nulls, matching Spark's collect_set.
    model: mealkit_set_features
    config:
      tags: ['duckdb_only']
    given:
      - input: ref('mealkit_orders')
        format: sql
        rows: |
          select 'c1' as customer, 'o3' as order_id, 'r3' as recipe,
                 'Mexican' as cuisine, 'soy' as allergen, 'p3' as product,
                 cast('2022-01-01' as date) as event_timestamp, 9 as quantity
    expect:
      format: sql
      rows: |
          select 'c1' as customer,
                 cast(list_value() as varchar[]) as allergens_3m1,
                 cast(list_value() as varchar[]) as cuisines_3m1
```

The `duckdb_only` tag on the two set-valued tests exists because their expected values are written with DuckDB array syntax. Task 14's cross-warehouse workflow excludes that tag with `--exclude tag:duckdb_only`; the scalar test runs everywhere.

The derivations are the same shape as grocery's: quantity 8 over 2 orders is 4.0; the first and last orders are 90 days apart, so `avg_purchase_cycle` is 45.0; the last order is 2 days before `as_at`; October and December each contain a row and November does not, so `order_months` is 2. `italian_cuisine_count` is 2 because two in-window rows are Italian, and `south_african_cuisine_count` is 0 because no row is — which is the point of asserting it, since a `count_if` over no matching rows must give 0 rather than null.

- [ ] **Step 11: Add the L3 seed-equality tests**

Generate the expected seeds exactly as in Task 11 Step 9 — run the models, check every value against the unit-test expectations above, and only then write them out:
```bash
cd integration_tests
uv run dbt seed --profiles-dir .
uv run dbt run --select mealkit_scalar_features --profiles-dir .
uv run dbt show --select mealkit_scalar_features --limit 50 \
  --output json --profiles-dir . > /tmp/mealkit_actual.json
```
Write `integration_tests/seeds/expected_mealkit_features.csv` with a header row of the 15 column names, then add to `_mealkit.yml` under `models: - name: mealkit_scalar_features`:
```yaml
    tests:
      - dbt_utils.equality:
          compare_model: ref('expected_mealkit_features')
```

No equality test for `mealkit_set_features`: array columns do not round-trip through a CSV seed. The unit tests above cover it.

- [ ] **Step 12: Run everything**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
uv run dbt build --profiles-dir .
```
Expected: PASS.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add the mealkit features, per-cuisine counts and mealkit_features

Mealkit exercises three things grocery does not: it uses only 10 of the 20
core features, it defines AvgPurchaseCycle with the same stem as grocery but
a different denominator, and its feature set depends on a runtime parameter.
The first two work because the catalogue is built per generator rather than
merged from one global registry.

Adds empty_string_array as a portability seam so the two set-valued features
default to [] rather than null, matching Spark's collect_set.

Diverges from jstark by taking cuisines as a parameter, which means the three
misspelled cuisine column names jstark has inherited cannot arise here.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: The feature catalogue and the schema.yml generator

Everything so far emits features. This task makes the package able to describe them, which is what the design promised in place of jstark's Spark column metadata: SQL has nowhere to hang a per-column `metadata` dict, so the metadata becomes a queryable relation and a `schema.yml` generator instead.

Two deliverables:

1. `jstark.feature_catalog(...)` — a macro usable as a model or in an ad-hoc query, returning one row per feature the same parameters would generate.
2. `dbt run-operation jstark_generate_schema_yml` — prints a `schema.yml` fragment to stdout so a user can paste column descriptions into their own project.

Catalogue columns, in order:

| Column | Value |
|---|---|
| `feature_name` | the public column name — absolute-labelled when `use_absolute_periods` is true |
| `stem` | the CamelCase stem |
| `period_mnemonic` | e.g. `3m1` |
| `period_unit` | `Day`, `Week`, `Month`, `Quarter` or `Year` |
| `start_date` | a `date` |
| `end_date` | a `date` |
| `description` | `'<description_subject> between <start_date> and <end_date>'`, matching jstark's `column_metadata['description']` |
| `commentary` | verbatim from the definition |
| `required_columns` | comma-separated input columns, transitively for derived features |
| `kind` | `base` or `derived` |

`required_columns` is a comma-separated string rather than an array so the catalogue needs no array literal and works on every warehouse. Derived features have no `required_columns` of their own, so theirs is the union of the base features they reach through their dependencies — `AvgGrossSpendPerBasket` requires `event_timestamp`, `basket` and `gross_spend` even though its own expression names none of them.

**Interfaces:**
- Consumes: `jstark.build_plan`, `jstark.public_column_name`, `jstark.period_unit_name`, `jstark.date_string`, `jstark.resolve_columns`, `jstark.resolve_as_at`, `jstark.parse_feature_periods` — all from Tasks 2-9.
- Produces:
  - `jstark.sql_string(value)` → a single-quoted SQL string literal with embedded quotes doubled.
  - `jstark.catalog_rows(generator, as_at, feature_periods, feature_stems, first_day_of_week, use_absolute_periods, column_map, cuisines)` → a list of dicts with the ten keys above. Reusable by anything that needs the metadata as data rather than as SQL.
  - `jstark.feature_catalog(...)` (same parameters) → the SQL string.
  - `jstark_generate_schema_yml(...)` → prints, returns nothing.

- [ ] **Step 1: Write the failing L1 test**

Create `integration_tests/macros/tests/test_catalog.sql`:
```sql
{% macro jstark_test_catalog(failures) %}

  {% set rows = jstark.catalog_rows(
      generator='grocery',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['GrossSpend', 'AvgGrossSpendPerBasket'],
      first_day_of_week='Monday',
      use_absolute_periods=false,
      column_map={},
      cuisines=[]
  ) %}

  {# --- one row per requested feature, and only the requested ones --- #}
  {% do jstark_assert_equal(failures, 'catalog row count', rows | length, 2) %}
  {% do jstark_assert_equal(
      failures, 'catalog feature names',
      rows | map(attribute='feature_name') | sort | list,
      ['avg_gross_spend_per_basket_3m1', 'gross_spend_3m1']
  ) %}

  {% set by_name = {} %}
  {% for row in rows %}
    {% do by_name.update({row['feature_name']: row}) %}
  {% endfor %}

  {# --- a base feature --- #}
  {% set gross = by_name['gross_spend_3m1'] %}
  {% do jstark_assert_equal(failures, 'catalog stem', gross['stem'], 'GrossSpend') %}
  {% do jstark_assert_equal(
      failures, 'catalog mnemonic', gross['period_mnemonic'], '3m1'
  ) %}
  {% do jstark_assert_equal(
      failures, 'catalog period unit', gross['period_unit'], 'Month'
  ) %}
  {% do jstark_assert_equal(
      failures, 'catalog start date', gross['start_date'], '2021-10-01'
  ) %}
  {% do jstark_assert_equal(
      failures, 'catalog end date', gross['end_date'], '2021-12-31'
  ) %}
  {% do jstark_assert_equal(failures, 'catalog kind', gross['kind'], 'base') %}
  {% do jstark_assert_equal(
      failures, 'catalog description',
      gross['description'],
      gross['description_subject'] ~ ' between 2021-10-01 and 2021-12-31'
  ) %}
  {% do jstark_assert_equal(
      failures, 'catalog required columns for a base feature',
      gross['required_columns'], 'event_timestamp,gross_spend'
  ) %}

  {# --- a derived feature inherits the input columns it reaches --- #}
  {% set avg = by_name['avg_gross_spend_per_basket_3m1'] %}
  {% do jstark_assert_equal(failures, 'catalog derived kind', avg['kind'], 'derived') %}
  {% do jstark_assert_equal(
      failures, 'catalog required columns for a derived feature',
      avg['required_columns'], 'basket,event_timestamp,gross_spend'
  ) %}

  {# --- a two-deep derived feature reaches all the way to the base --- #}
  {% set deep = jstark.catalog_rows(
      generator='grocery', as_at='2022-01-01', feature_periods=['3m1'],
      feature_stems=['CyclesSinceLastPurchase'], first_day_of_week='Monday',
      use_absolute_periods=false, column_map={}, cuisines=[]
  ) %}
  {% do jstark_assert_equal(
      failures, 'catalog required columns two levels down',
      deep[0]['required_columns'], 'basket,event_timestamp'
  ) %}

  {# --- absolute labels flow through to feature_name --- #}
  {% set absolute = jstark.catalog_rows(
      generator='grocery', as_at='2022-01-01', feature_periods=['3m1'],
      feature_stems=['GrossSpend'], first_day_of_week='Monday',
      use_absolute_periods=true, column_map={}, cuisines=[]
  ) %}
  {% do jstark_assert_equal(
      failures, 'catalog honours absolute periods',
      absolute[0]['feature_name'], 'gross_spend_2021oct_to_2021dec'
  ) %}
  {% do jstark_assert_equal(
      failures, 'catalog reports the mnemonic even when labels are absolute',
      absolute[0]['period_mnemonic'], '3m1'
  ) %}

  {# --- string literals are escaped --- #}
  {% do jstark_assert_equal(
      failures, 'sql_string quotes a plain value',
      jstark.sql_string('abc'), "'abc'"
  ) %}
  {% do jstark_assert_equal(
      failures, 'sql_string doubles embedded quotes',
      jstark.sql_string("Shepherd's Pie"), "'Shepherd''s Pie'"
  ) %}

  {# --- the emitted SQL is one row per feature and casts the dates --- #}
  {% set sql = jstark.feature_catalog(
      generator='mealkit', as_at='2022-01-01', feature_periods=['3m1', '1y1'],
      cuisines=['Italian']
  ) %}
  {#- two periods times 24 features is 48 rows, so 47 union alls -#}
  {% do jstark_assert_equal(
      failures, 'catalog SQL has one select per feature',
      sql.split('union all') | length, (10 + 13 + 1) * 2
  ) %}
  {% do jstark_assert_contains(
      failures, 'catalog SQL casts start_date',
      sql, "cast('2021-10-01' as date) as start_date"
  ) %}
  {% do jstark_assert_contains(
      failures, 'catalog SQL names the columns', sql, 'as feature_name'
  ) %}

  {# --- the catalogue covers exactly the columns the engine emits --- #}
  {% if target.type == 'duckdb' %}
    {% set engine_sql = jstark.mealkit_features(
        input='select * from t', group_by=['customer'], as_at='2022-01-01',
        feature_periods=['3m1'], cuisines=['Italian']
    ) %}
    {% set catalog_names = jstark.catalog_rows(
        generator='mealkit', as_at='2022-01-01', feature_periods=['3m1'],
        feature_stems=none, first_day_of_week=none, use_absolute_periods=false,
        column_map={}, cuisines=['Italian']
    ) | map(attribute='feature_name') | list %}
    {% for name in catalog_names %}
      {% do jstark_assert_true(
          failures, 'engine emits catalogued column ' ~ name,
          name in engine_sql
      ) %}
    {% endfor %}
    {% do jstark_assert_equal(
        failures, 'catalog covers every mealkit feature',
        catalog_names | length, 10 + 13 + 1
    ) %}
  {% endif %}

{% endmacro %}
```

`description_subject` is asserted via the row itself rather than a hard-coded string, because Task 10 Step 1 copies those from jstark and this test should not duplicate them. Add `description_subject` to the row dict for that reason — it is genuinely useful to anyone consuming `catalog_rows` directly.

Register it in `jstark_test_suite`:
```sql
  {% do jstark_test_catalog(failures) %}
```

Run it:
```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `'jstark' has no attribute 'catalog_rows'`.

- [ ] **Step 2: Write the catalogue**

Create `macros/core/feature_catalog.sql`:
```sql
{#
  Feature metadata as data.

  jstark attaches a metadata dict to every Spark column. SQL has nowhere to
  put that, so instead the same information is available two ways: as a
  relation (feature_catalog) and as a schema.yml fragment (see
  generate_schema_yml.sql).

  The parameters are deliberately identical to the generator entry points, so
  a caller can copy the arguments from their model into a catalogue query and
  get a description of exactly the columns that model produces.
#}

{% macro sql_string(value) %}
  {{ return("'" ~ (value | string | replace("'", "''")) ~ "'") }}
{% endmacro %}


{#
  Which input columns a feature ultimately needs.

  Base features declare their own. Derived features declare none, because
  their expression references other features rather than input columns, so
  theirs is the union of everything they reach transitively.

  Jinja has no while loop, so this iterates to a fixpoint over a bounded
  range instead. The bound is the longest possible dependency chain; grocery's
  deepest is 2, so 20 is generous.
#}
{% macro required_columns_closure(plan) %}

  {% set by_key = {} %}
  {% for level in plan['levels'] %}
    {% for item in level %}
      {% do by_key.update({item['key']: item}) %}
    {% endfor %}
  {% endfor %}

  {#- seed: base features contribute their own declared columns -#}
  {% set closure = {} %}
  {% for key, item in by_key.items() %}
    {% do closure.update({
        key: item['definition'].get('required_columns', []) | list
    }) %}
  {% endfor %}

  {#- propagate: a feature needs whatever its dependencies need -#}
  {% for _ in range(20) %}
    {% for key, item in by_key.items() %}
      {% for dep in item['definition'].get('depends_on', []) %}
        {% set dep_key = jstark.dependency_key(dep[0], dep[1]) %}
        {% for column in closure.get(dep_key, []) %}
          {% if column not in closure[key] %}
            {% do closure[key].append(column) %}
          {% endif %}
        {% endfor %}
      {% endfor %}
    {% endfor %}
  {% endfor %}

  {{ return(closure) }}
{% endmacro %}


{% macro catalog_rows(
    generator='grocery',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={},
    cuisines=[]
) %}

  {% set cols = jstark.resolve_columns(column_map) %}
  {% set resolved_as_at = jstark.resolve_as_at(as_at) %}
  {% set periods = jstark.parse_feature_periods(feature_periods) %}
  {% set plan = jstark.build_plan(
      generator, feature_stems or [], periods, resolved_as_at,
      first_day_of_week, use_absolute_periods, cols, cuisines
  ) %}
  {% set closure = jstark.required_columns_closure(plan) %}

  {% set rows = [] %}
  {% for item in plan['requested'] %}
    {% set definition = item['definition'] %}
    {% set period = item['period'] %}
    {% set ctx = item['ctx'] %}
    {% set start_date = jstark.date_string(ctx['start_date']) %}
    {% set end_date = jstark.date_string(ctx['end_date']) %}
    {% set subject = definition['description_subject'] %}
    {% do rows.append({
        'feature_name': jstark.public_column_name(
            definition['stem'], period, use_absolute_periods,
            resolved_as_at, first_day_of_week
        ),
        'stem': definition['stem'],
        'period_mnemonic': period['mnemonic'],
        'period_unit': jstark.period_unit_name(period['uom']),
        'start_date': start_date,
        'end_date': end_date,
        'description_subject': subject,
        'description': subject ~ ' between ' ~ start_date ~ ' and ' ~ end_date,
        'commentary': definition['commentary'],
        'required_columns': closure.get(item['key'], []) | sort | join(','),
        'kind': definition['kind']
    }) %}
  {% endfor %}

  {{ return(rows) }}
{% endmacro %}


{% macro feature_catalog(
    generator='grocery',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={},
    cuisines=[]
) %}
{%- set rows = jstark.catalog_rows(
    generator, as_at, feature_periods, feature_stems, first_day_of_week,
    use_absolute_periods, column_map, cuisines
) -%}
{%- for row in rows %}
{% if not loop.first %}union all
{% endif %}select
    {{ jstark.sql_string(row['feature_name']) }} as feature_name,
    {{ jstark.sql_string(row['stem']) }} as stem,
    {{ jstark.sql_string(row['period_mnemonic']) }} as period_mnemonic,
    {{ jstark.sql_string(row['period_unit']) }} as period_unit,
    cast({{ jstark.sql_string(row['start_date']) }} as date) as start_date,
    cast({{ jstark.sql_string(row['end_date']) }} as date) as end_date,
    {{ jstark.sql_string(row['description']) }} as description,
    {{ jstark.sql_string(row['commentary']) }} as commentary,
    {{ jstark.sql_string(row['required_columns']) }} as required_columns,
    {{ jstark.sql_string(row['kind']) }} as kind
{% endfor -%}
{% endmacro %}
```

`feature_catalog` is written with whitespace-trimming markers rather than building a string, because it emits a model body and the layout matters when someone reads the compiled SQL. Everything else in the package builds strings and returns them; this and `generate_features` are the two exceptions.

`sort` on the required columns is what makes `'basket,event_timestamp,gross_spend'` deterministic — the closure is built in dependency order, which is stable but unhelpful to read.

- [ ] **Step 3: Run the L1 test to verify it passes**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

- [ ] **Step 4: Write the schema.yml generator**

Create `macros/core/generate_schema_yml.sql`:
```sql
{#
  Prints a schema.yml fragment describing the columns a generator produces, so
  a user can paste real descriptions into their own project rather than
  documenting 37 generated columns by hand.

  Named jstark_generate_schema_yml rather than generate_schema_yml because
  dbt run-operation resolves macro names without package qualification, and an
  unprefixed name that generic would collide with the user's own macros.

  Usage:
    dbt run-operation jstark_generate_schema_yml --args '{
        "model_name": "customer_features",
        "generator": "grocery",
        "as_at": "2022-01-01",
        "feature_periods": ["3m1"]
    }'
#}

{% macro jstark_generate_schema_yml(
    model_name,
    generator='grocery',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={},
    cuisines=[],
    group_by=[]
) %}

  {% set rows = jstark.catalog_rows(
      generator, as_at, feature_periods, feature_stems, first_day_of_week,
      use_absolute_periods, column_map, cuisines
  ) %}

  {% set lines = ['version: 2', '', 'models:', '  - name: ' ~ model_name,
                  '    columns:'] %}
  {% for column in group_by %}
    {% do lines.append('      - name: ' ~ column) %}
    {% do lines.append('        description: Grouping column.') %}
  {% endfor %}
  {% for row in rows %}
    {% do lines.append('      - name: ' ~ row['feature_name']) %}
    {#- double-quoted YAML with embedded quotes escaped, so a description
        containing a colon or a quote cannot break the output -#}
    {% do lines.append(
        '        description: "'
        ~ (row['description'] | replace('\\', '\\\\') | replace('"', '\\"'))
        ~ '"'
    ) %}
  {% endfor %}

  {% do print(lines | join('\n')) %}

{% endmacro %}
```

`print` rather than `log` so the output is clean enough to redirect into a file.

- [ ] **Step 5: Verify the generator by eye and by parsing**

```bash
cd integration_tests
uv run dbt --quiet run-operation jstark_generate_schema_yml --profiles-dir . --args '{
    "model_name": "grocery_specific_features",
    "generator": "grocery",
    "as_at": "2022-01-01",
    "feature_periods": ["3m1"],
    "group_by": ["customer"]
}' > /tmp/generated_schema.yml
uv run python -c "import yaml,sys; d=yaml.safe_load(open('/tmp/generated_schema.yml')); print(len(d['models'][0]['columns']), 'columns')"
```
Expected: valid YAML, 38 columns — 37 grocery features plus `customer`.

`--quiet` is a global flag, so it precedes the subcommand. If log lines still land in the redirect, discard any line that does not start with a space or with `version:`/`models:`. Check the file before running the parse.

- [ ] **Step 6: Add the L2 catalogue model and unit test**

`integration_tests/models/core/feature_catalog_grocery.sql`:
```sql
{{ jstark.feature_catalog(
    generator='grocery',
    as_at='2022-01-01',
    feature_periods=['3m1'],
    feature_stems=['GrossSpend', 'AvgGrossSpendPerBasket']
) }}
```

Add to `integration_tests/models/core/_engine.yml`:
```yaml
models:
  - name: feature_catalog_grocery
    description: >
      Feature metadata as a relation, for two grocery features over one
      period. Takes no input, so its unit test has no `given`.

unit_tests:
  - name: feature_catalog_grocery_rows
    description: >
      One row per feature, with the derived feature's required_columns
      reaching through to the input columns its dependencies need.
    model: feature_catalog_grocery
    given: []
    expect:
      format: sql
      rows: |
          select 'gross_spend_3m1' as feature_name,
                 'GrossSpend' as stem,
                 '3m1' as period_mnemonic,
                 'Month' as period_unit,
                 cast('2021-10-01' as date) as start_date,
                 cast('2021-12-31' as date) as end_date,
                 'event_timestamp,gross_spend' as required_columns,
                 'base' as kind
          union all
          select 'avg_gross_spend_per_basket_3m1', 'AvgGrossSpendPerBasket',
                 '3m1', 'Month', cast('2021-10-01' as date),
                 cast('2021-12-31' as date),
                 'basket,event_timestamp,gross_spend', 'derived'
```

`required_columns` for the derived feature is `'basket,event_timestamp,gross_spend'`: `AvgGrossSpendPerBasket` divides `GrossSpend` by `BasketCount`, so it transitively needs all three, sorted. It matches the L1 assertion in Step 1 — if the two ever disagree, the L1 test is the one to trust, since it exercises `required_columns_closure` directly.

Note the expected rows omit `description` and `commentary`: dbt unit tests compare only the columns the `expect` fixture names, and those two come verbatim from jstark, so asserting them here would duplicate Task 10 Step 1's transcription. The L1 test above already checks that `description` is built from `description_subject` and the two dates.

- [ ] **Step 7: Run everything**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
uv run dbt build --profiles-dir .
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add the feature catalogue and the schema.yml generator

jstark hangs a metadata dict off every Spark column. SQL has nowhere to put
that, so the same information is available two other ways: feature_catalog
returns it as a queryable relation, and jstark_generate_schema_yml prints a
schema.yml fragment.

Derived features declare no input columns of their own, so the catalogue
computes the transitive closure: AvgGrossSpendPerBasket reports that it needs
basket and gross_spend even though its own expression names neither.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Documentation, the feature reference generator, and CI

The last task makes the package usable by someone who did not write it, and makes the test suite run on every push.

Four deliverables: a generated feature reference, a README that embeds it, a `CONTRIBUTING.md`, and two workflows.

**Files:**
- Create: `macros/core/generate_feature_reference.sql`, `README.md`, `CONTRIBUTING.md`, `scripts/update-readme.sh`, `.github/workflows/build.yml`, `.github/workflows/warehouses.yml`
- Modify: `integration_tests/macros/tests/test_catalog.sql`

**Interfaces:**
- Consumes: `jstark.catalog_rows` from Task 13.
- Produces: `jstark_generate_feature_reference(generator, cuisines=[])` → prints a markdown table.

- [ ] **Step 1: Read jstark's README and note its section order**

```bash
sed -n '1,200p' /tmp/jstark-ref/README.md
grep -n '^#' /tmp/jstark-ref/README.md
```

The design says to document this package "just like jstark". The outline in Step 4 below covers the same ground, but where jstark has a section this outline lacks, or names one differently, prefer jstark's wording — a reader coming from jstark should recognise the shape. Do not copy prose that describes PySpark behaviour this package does not have.

- [ ] **Step 2: Write the failing test for the reference generator**

Append to `jstark_test_catalog` in `integration_tests/macros/tests/test_catalog.sql`, before its final `{% endmacro %}`:
```sql
  {# --- the feature reference is one row per stem, not per stem-and-period --- #}
  {% set reference = jstark.feature_reference_rows('grocery', []) %}
  {% do jstark_assert_equal(
      failures, 'grocery reference row count', reference | length, 37
  ) %}
  {% do jstark_assert_equal(
      failures, 'reference rows are unique per stem',
      reference | map(attribute='stem') | unique | list | length, 37
  ) %}
  {% set first = reference[0] %}
  {% for key in ['stem', 'column_name_pattern', 'kind', 'description_subject',
                 'commentary', 'required_columns'] %}
    {% do jstark_assert_true(
        failures, 'reference row has ' ~ key, key in first
    ) %}
  {% endfor %}
  {#- indexed with [] rather than the attr filter: attr does not fall back to
      item lookup, so on a dict it returns undefined -#}
  {% set order_periods_row = jstark.feature_reference_rows('mealkit', [])
      | selectattr('stem', 'equalto', 'OrderPeriods') | first %}
  {% do jstark_assert_equal(
      failures, 'reference column name pattern keeps the period placeholder',
      order_periods_row['column_name_pattern'], 'order_{unit}s_{period}'
  ) %}
  {% do jstark_assert_equal(
      failures, 'mealkit reference row count',
      jstark.feature_reference_rows('mealkit', []) | length, 23
  ) %}
```

Run it:
```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: FAIL — `'jstark' has no attribute 'feature_reference_rows'`.

- [ ] **Step 3: Write the reference generator**

Create `macros/core/generate_feature_reference.sql`:
```sql
{#
  The feature reference that goes in the README.

  feature_catalog describes the columns one particular set of parameters
  produces, dates and all. The README needs the opposite: one row per feature
  stem, period-independent, so it stays correct whatever as_at a reader uses.

  So this builds the catalogue for one canonical period and then strips the
  period back out of the column names, turning basket_months_3m1 into
  basket_{unit}s_{period}. The canonical period is monthly because that is the
  unit the unit-dependent names read most naturally in.
#}

{% macro feature_reference_rows(generator='grocery', cuisines=[]) %}

  {% set canonical_period = '3m1' %}
  {% set canonical_as_at = '2022-01-01' %}
  {% set rows = jstark.catalog_rows(
      generator=generator,
      as_at=canonical_as_at,
      feature_periods=[canonical_period],
      feature_stems=none,
      first_day_of_week='Monday',
      use_absolute_periods=false,
      column_map={},
      cuisines=cuisines
  ) %}

  {% set reference = [] %}
  {% for row in rows %}
    {#- 'basket_months_3m1' -> 'basket_{unit}s_{period}' -#}
    {% set without_period = row['feature_name']
        | replace('_' ~ canonical_period, '_{period}') %}
    {% set pattern = without_period | replace('_month', '_{unit}') %}
    {% do reference.append({
        'stem': row['stem'],
        'column_name_pattern': pattern,
        'kind': row['kind'],
        'description_subject': row['description_subject'],
        'commentary': row['commentary'],
        'required_columns': row['required_columns']
    }) %}
  {% endfor %}

  {{ return(reference) }}
{% endmacro %}


{#
  Usage:
    dbt run-operation jstark_generate_feature_reference \
      --args '{"generator": "grocery"}'
#}
{% macro jstark_generate_feature_reference(generator='grocery', cuisines=[]) %}

  {% set rows = jstark.feature_reference_rows(generator, cuisines) %}
  {% set lines = [
      '| Feature | Column | Kind | Description | Requires |',
      '| --- | --- | --- | --- | --- |'
  ] %}
  {% for row in rows %}
    {% do lines.append(
        '| `' ~ row['stem'] ~ '` | `' ~ row['column_name_pattern'] ~ '` | '
        ~ row['kind'] ~ ' | ' ~ row['description_subject'] ~ ' | `'
        ~ row['required_columns'] ~ '` |'
    ) %}
  {% endfor %}
  {% do print(lines | join('\n')) %}

{% endmacro %}
```

The `_month` → `_{unit}` replacement is why the canonical period is monthly: `average_baskets_per_month_3m1` has to become `average_baskets_per_{unit}_{period}`, and no other feature name contains the substring `_month`. If a future feature does, this substitution will corrupt it — the L1 assertion on `order_{unit}s_{period}` is what would catch that.

- [ ] **Step 4: Run the L1 test, then write the README**

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```
Expected: PASS.

Then create `README.md`. The generated tables go between marker comments so `scripts/update-readme.sh` can replace them:

````markdown
# dbt-jstark

Feature generation for dbt. Give it a table of transactions and it generates
hundreds of aggregated features — spend, counts, recency, purchase cycles — over
whatever time windows you ask for.

This is a SQL reimplementation of [jstark](https://github.com/jamiekt/jstark),
which does the same thing in PySpark. If you know jstark, the parameters and the
feature names will be familiar; see [Parity with
jstark](#11-parity-with-jstark) for where they are not.

## 1. Why

Feature engineering for retail ML is repetitive and easy to get subtly wrong. You
want net spend in the last 13 weeks, and also the 13 weeks before that, and also
per-basket averages, and also how many months the customer was active in — and
each one has to filter to the right window, default sensibly when the window is
empty, and be named consistently enough that a hundred of them stay legible.

That is the whole job. Describe the windows and the features; the macro writes the
SQL.

## 2. Installation

Add to your `packages.yml`:

```yaml
packages:
  - git: "https://github.com/jamiekt/dbt-jstark.git"
    revision: main
```

Then:

```bash
dbt deps
```

Requires dbt-core 1.8 or later.

## 3. Quickstart

```sql
-- models/customer_features.sql
{{ jstark.grocery_features(
    input=ref('transactions'),
    group_by=['customer'],
    as_at='2022-01-01',
    feature_periods=['13w0', '26w14', '52w0']
) }}
```

That produces one row per customer and 37 features per period — 111 columns plus
the grouping column. `dbt run`, then look at the result.

For mealkits:

```sql
{{ jstark.mealkit_features(
    input=ref('orders'),
    group_by=['customer'],
    as_at='2022-01-01',
    feature_periods=['13w0'],
    cuisines=['Italian', 'Thai', 'Indian']
) }}
```

`input` takes a `ref()`, a `source()`, or a SQL string:

```sql
{{ jstark.grocery_features(
    input="select * from raw.transactions where country = 'GB'",
    group_by=['customer'],
    feature_periods=['13w0']
) }}
```

## 4. Feature periods

A feature period is a window ending on or before `as_at`, written as a mnemonic:

```
52w0
││ └── end:   0 weeks before as_at
│└──── unit:  weeks
└───── start: 52 weeks before as_at
```

Units are `d`ay, `w`eek, `m`onth, `q`uarter and `y`ear. `start` must be greater
than or equal to `end`. Omitted numbers mean 0, so `m` is `0m0` — the current
month to date.

Windows snap to whole units, then get clipped at `as_at`. With
`as_at = 2022-01-01`:

| Mnemonic | Window | Meaning |
| --- | --- | --- |
| `0d0` | 2022-01-01 to 2022-01-01 | today |
| `3d1` | 2021-12-29 to 2021-12-31 | the three days before today |
| `52w0` | 2020-12-28 to 2022-01-01 | the last 52 whole weeks, to date |
| `3m1` | 2021-10-01 to 2021-12-31 | the last three whole months |
| `1y1` | 2021-01-01 to 2021-12-31 | last year |
| `4q4` | 2021-01-01 to 2021-03-31 | the quarter four quarters ago |

The default is `['52w0']`.

## 5. Parameters

Both generators take the same parameters, and `mealkit_features` adds `cuisines`.

| Parameter | Default | Meaning |
| --- | --- | --- |
| `input` | required | A `ref()`, `source()`, or SQL string producing the input rows. |
| `group_by` | required | Columns to aggregate by, e.g. `['customer']`. |
| `as_at` | see below | The date the features are calculated as at. |
| `feature_periods` | `['52w0']` | Mnemonics or period dicts. |
| `feature_stems` | all | Restrict to named features, e.g. `['NetSpend', 'BasketCount']`. |
| `first_day_of_week` | `Monday` | Which day starts a week, for `w` periods. |
| `use_absolute_periods` | `false` | Name columns by date rather than by mnemonic. |
| `column_map` | `{}` | Rename input columns; see below. |
| `cuisines` | `[]` | Mealkit only: one count feature per cuisine. |

**`as_at`** resolves in this order: the argument, then `var('jstark_as_at')`, then
`run_started_at`. Relying on `run_started_at` makes your features change every day
and your tests unreproducible, so the macro warns when it falls through to it. Set
it explicitly, or pass it in:

```bash
dbt run --vars '{jstark_as_at: 2022-01-01}'
```

**`use_absolute_periods`** changes the column suffix from the mnemonic to the dates
it resolves to, which is useful when you are appending feature rows over time and
`net_spend_3m1` would mean something different in each run:

| Mnemonic | Default name | With `use_absolute_periods=true` |
| --- | --- | --- |
| `0d0` | `net_spend_0d0` | `net_spend_20220101` |
| `1w1` | `net_spend_1w1` | `net_spend_2021w52` |
| `3m1` | `net_spend_3m1` | `net_spend_2021oct_to_2021dec` |
| `1y1` | `net_spend_1y1` | `net_spend_2021` |

**`feature_stems`** names features by their CamelCase stem, not by column name, and
naming a derived feature pulls in whatever it needs. Asking only for
`CyclesSinceLastPurchase` computes `RecencyDays`, `AvgPurchaseCycle` and the base
aggregates behind them, and returns just the one column.

## 6. Input data

The macro expects these columns. Everything is optional except
`event_timestamp` — a feature is only available if its input columns are.

| Column | Used by |
| --- | --- |
| `event_timestamp` | everything; a date or timestamp |
| `basket` | grocery basket counts and per-basket averages |
| `order_id` | mealkit order counts and per-order averages |
| `store`, `channel` | grocery store and channel counts |
| `customer` | customer counts |
| `product` | product counts |
| `quantity` | quantity sums, per-unit prices |
| `net_spend`, `gross_spend`, `discount` | spend features |
| `cuisine`, `recipe`, `allergen` | mealkit features |

If your columns are named differently, map them:

```sql
{{ jstark.grocery_features(
    input=ref('transactions'),
    group_by=['customer_id'],
    column_map={'event_timestamp': 'txn_date', 'basket': 'transaction_id'},
    feature_periods=['13w0']
) }}
```

Note there is no `timestamp` or `order` column, unlike jstark: both are reserved
words in one warehouse or another. Use `event_timestamp` and `order_id`.

## 7. The features

Column names are the snake_case stem plus the period, so `NetSpend` at `13w0`
becomes `net_spend_13w0`. Features whose meaning depends on the period's unit put
the unit in the name: `BasketPeriods` at `3m1` is `basket_months_3m1` and at
`13w0` is `basket_weeks_13w0`.

<details>
<summary><b>Grocery — 37 features</b></summary>

<!-- BEGIN GENERATED grocery -->
<!-- END GENERATED grocery -->

</details>

<details>
<summary><b>Mealkit — 23 features, plus one per cuisine</b></summary>

Every cuisine you pass adds one more: `cuisines=['South African']` adds
`south_african_cuisine_count_13w0`.

<!-- BEGIN GENERATED mealkit -->
<!-- END GENERATED mealkit -->

</details>

Empty windows get defaults rather than nulls, and the defaults are deliberately
asymmetric: sums and counts default to 0, minima default to 0, and **maxima
default to null**. That is jstark's behaviour and it is preserved here — a maximum
of 0 would be a claim about data that does not exist, whereas a minimum of 0 reads
as "nothing, so nothing spent". Derived features default to null throughout.

## 8. Feature metadata

`feature_catalog` describes what a given set of parameters produces:

```sql
-- models/feature_catalog.sql
{{ jstark.feature_catalog(
    generator='grocery',
    as_at='2022-01-01',
    feature_periods=['13w0']
) }}
```

One row per feature, with `feature_name`, `stem`, `period_mnemonic`,
`period_unit`, `start_date`, `end_date`, `description`, `commentary`,
`required_columns` and `kind`.

To document the columns in your own project:

```bash
dbt run-operation jstark_generate_schema_yml --args '{
    "model_name": "customer_features",
    "generator": "grocery",
    "as_at": "2022-01-01",
    "feature_periods": ["13w0"],
    "group_by": ["customer"]
}'
```

## 9. Warehouse support

The generated SQL is warehouse-agnostic: date arithmetic happens in Jinja at
compile time, and the handful of constructs that genuinely differ go through
dbt-core's cross-database macros or through adapter dispatch.

| Warehouse | Status |
| --- | --- |
| DuckDB | Tested on every commit |
| Postgres | Tested nightly. `ApproxCustomerCount` and friends fall back to exact counts and warn, because Postgres has no approximate distinct count. |
| Snowflake | Tested nightly when credentials are configured |
| BigQuery | Tested nightly when credentials are configured |
| Databricks | Tested nightly when credentials are configured |

Adding an adapter means implementing four macros; see `CONTRIBUTING.md`.

## 10. Adding your own industry

Grocery and mealkit are not special. Each is a set of feature definitions plus a
three-line entry point, sitting on the same core engine — so a new industry is the
same two things.

1. **Write a registration macro** that adds your definitions to a dict. Base
   features aggregate input columns; derived features reference other features by
   stem and period. `CONTRIBUTING.md` has the dict shape for both.

   ```sql
   {% macro register_telco_features(definitions, ctx) %}
     {% do definitions.update({'CallCount': {
         'stem': 'CallCount',
         'kind': 'base',
         'aggregator': 'count_distinct',
         'expression': ctx['cols']['call_id'],
         'default': '0',
         'required_columns': ['event_timestamp', 'call_id'],
         'description_subject': 'Distinct count of Calls',
         'commentary': 'Calls, not call attempts.'
     }}) %}
   {% endmacro %}
   ```

2. **Add a branch to `jstark.catalogue`** naming your generator, and add its name
   to `jstark.generators()`. dbt cannot dispatch a macro by a name computed at
   runtime, so this is an explicit `if` rather than a lookup.

3. **Write the entry point**, which just names the generator:

   ```sql
   {% macro telco_features(input, group_by, as_at=none, feature_periods=none,
                           feature_stems=none, first_day_of_week=none,
                           use_absolute_periods=false, column_map={}) %}
     {{ jstark.generate_features(
         input=input, group_by=group_by, generator='telco', as_at=as_at,
         feature_periods=feature_periods, feature_stems=feature_stems,
         first_day_of_week=first_day_of_week,
         use_absolute_periods=use_absolute_periods, column_map=column_map
     ) }}
   {% endmacro %}
   ```

You get periods, naming, absolute labels, defaults, dependency levelling, the
catalogue and the `schema.yml` generator for free. If your industry needs an input
column that is not in the canonical list, add it to `jstark.canonical_columns()`.

Steps 2 and 3 mean this has to happen inside a fork or a PR rather than in your
own project — the core cannot discover generators it does not know about. A PR is
welcome; two industries is not a design, it is a coincidence.

## 11. Parity with jstark

| jstark | dbt-jstark | Why |
| --- | --- | --- |
| `BasketCount_3m1` | `basket_count_3m1` | Warehouses disagree on unquoted identifier case-folding; snake_case is identical everywhere and needs no quoting. |
| `Timestamp`, `Order` input columns | `event_timestamp`, `order_id` | Input refs are unquoted so case-folding works; `cast(timestamp as date)` is a Postgres syntax error and `order` is reserved. |
| 95 hardcoded `*CuisineCount` classes | `cuisines=[...]` parameter | Same capability, far less generated SQL, and drops inherited typos (`IsrealiCuisineCount`, `FusionCuisineCusiineCount`, `SouthHyphenAfricanCuisineCount`). |
| `try_divide(a, b)` | `cast(a as float) / nullif(b, 0)` | Portable, and identical null-on-zero semantics. |
| `BasketCount_2021Oct-2021Dec` | `basket_count_2021oct_to_2021dec` | Hyphens are illegal in unquoted SQL identifiers. |
| `gf.references[...]` from the Spark query plan | `required_columns` in each definition | There is no query plan to introspect from Jinja. |
| `collect_set` (unordered) | sorted array | Makes `allergens_3m1` deterministic and therefore testable. |
| Column metadata on the DataFrame schema | `feature_catalog()` model plus `schema.yml` codegen | SQL columns carry no metadata. |
| Derived features inline their dependencies | Shared base CTE, dependencies computed once | `BasketMonths_52w0` and `RecencyWeightedBasketMonths95_52w0` would otherwise compute 106 distinct-counts instead of 53. |
| Column order follows a Python `set` | Fixed registration order | Deterministic, and independent of the order you list `feature_stems`. |
| `as_at` defaults to `date.today()` | `as_at` → `var('jstark_as_at')` → run date, with a warning | A model whose numbers change on every rebuild is a trap; dbt makes the alternative easy. |

If you are migrating and depend on jstark's column names, the mapping is
mechanical apart from the three misspelled cuisine columns, which have no
equivalent here.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
````

- [ ] **Step 5: Write the README update script and run it**

Create `scripts/update-readme.sh`:
```bash
#!/usr/bin/env bash
# Regenerates the feature tables in README.md from the macros themselves, so
# the documented features cannot drift from the implemented ones. CI runs this
# and fails if it produces a diff.
set -euo pipefail

cd "$(dirname "$0")/.."
readme="README.md"

for generator in grocery mealkit; do
    table="$(mktemp)"
    # --quiet is a global flag, so it goes before the subcommand. grep '^|'
    # keeps only the table, whatever else dbt decides to log.
    (cd integration_tests && uv run dbt --quiet run-operation \
        jstark_generate_feature_reference --profiles-dir . \
        --args "{\"generator\": \"${generator}\"}") \
        | grep '^|' > "${table}"

    updated="$(mktemp)"
    awk -v gen="${generator}" -v table="${table}" '
        $0 == "<!-- BEGIN GENERATED " gen " -->" { print; skip = 1
            while ((getline line < table) > 0) print line
            next }
        $0 == "<!-- END GENERATED " gen " -->" { skip = 0 }
        !skip { print }
    ' "${readme}" > "${updated}"
    mv "${updated}" "${readme}"
    rm -f "${table}"
done

echo "README.md feature tables regenerated."
```

```bash
chmod +x scripts/update-readme.sh
./scripts/update-readme.sh
git diff --stat README.md
```
Expected: the two `<!-- BEGIN GENERATED -->` blocks now contain markdown tables of 37 and 23 rows. Read them — this is the first time the transcribed descriptions from Tasks 10-12 are visible all together, and it is the cheapest place to notice a wrong one.

Run it twice and confirm the second run produces no diff; if it does not converge, the `awk` guard is wrong and CI will fail on every commit.

- [ ] **Step 6: Write CONTRIBUTING.md**

Create `CONTRIBUTING.md`:
````markdown
# Contributing

## Setup

```bash
uv sync
cd integration_tests && uv run dbt deps
```

Install the hooks:

```bash
uv run pre-commit install
```

## Running the tests

Three layers, each catching something the others cannot.

**Layer 1 — macro logic, no warehouse.** Pure Jinja assertions on parsing, date
arithmetic, naming, the catalogue and dependency levelling. This is where most of
the coverage is, because most of the logic is compile-time.

```bash
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
```

**Layer 2 — generated SQL against known inputs.** dbt unit tests over models that
call the macros. This is what proves the SQL means what the macros intended.

```bash
cd integration_tests
uv run dbt test --select test_type:unit --profiles-dir .
```

**Layer 3 — the whole thing end to end.** Seeds, models and equality tests.

```bash
cd integration_tests
uv run dbt build --profiles-dir .
```

## Adding a feature

1. Add the definition to the right `register_*` macro in
   `macros/<generator>/features/`. Registration order is column order, so put it
   where it belongs in the output.
2. Add its stem to the expected-catalogue assertion in the matching
   `integration_tests/macros/tests/test_*.sql`, and bump the expected count.
3. Add its expected value to the matching unit test in
   `integration_tests/models/<generator>/_*.yml`.
4. Run `./scripts/update-readme.sh` and commit the regenerated table.

A definition is a dict. Base features aggregate input columns:

```sql
{% do definitions.update({'StoreCount': {
    'stem': 'StoreCount',
    'kind': 'base',
    'aggregator': 'count_distinct',
    'expression': ctx['cols']['store'],
    'default': '0',
    'required_columns': ['event_timestamp', 'store'],
    'description_subject': 'Distinct count of Stores',
    'commentary': '...'
}}) %}
```

Derived features reference other features by stem and period, and declare it:

```sql
{% do definitions.update({'AvgQuantityPerBasket': {
    'stem': 'AvgQuantityPerBasket',
    'kind': 'derived',
    'depends_on': [['Quantity', period], ['BasketCount', period]],
    'expression': jstark.safe_divide(
        jstark.column_name('Quantity', period),
        jstark.column_name('BasketCount', period)
    ),
    'default': 'null',
    'description_subject': 'Average Quantity per Basket',
    'commentary': '...'
}}) %}
```

**`depends_on` is not optional.** The engine builds one CTE per dependency level
and only computes what is declared, so an undeclared reference compiles to a
missing-column error. The `undeclared_dependencies` assertion in the L1 suite
catches this, which is why every generator has one.

A dependency's period need not be the caller's — `[['Count', sub_period]]` is how
the periodic features get per-month aggregates out of a three-month window. Those
helpers are computed and then dropped from the final projection.

## Adding a warehouse adapter

Implement whichever of these your warehouse needs, in
`macros/core/adapters/`, as `<adapter>__<name>`:

| Macro | What it must return |
| --- | --- |
| `<adapter>__jstark_to_date(expression)` | SQL casting a timestamp to a date |
| `<adapter>__jstark_approx_count_distinct(expression)` | SQL for an approximate distinct count. If your warehouse has none, return an exact count and `exceptions.warn` — that is what `postgres__` does. |
| `<adapter>__jstark_collect_set(expression, window)` | SQL for a sorted, deduplicated, null-free array of `expression` over rows matching `window`. Two shapes work: `FILTER (WHERE ...)` where supported, `CASE WHEN` otherwise. |
| `<adapter>__empty_string_array()` | A literal empty array of strings |

Everything else routes through dbt-core's cross-database macros (`dbt.datediff`,
`dbt.type_float`, `dbt.type_string`) and needs nothing.

Then add a target to `integration_tests/profiles.yml` and a matrix entry to
`.github/workflows/warehouses.yml`. The Snowflake and BigQuery variants that ship
today were written from the documentation and have not been run against a real
warehouse; verifying them is a genuinely useful contribution.

## Things to know before you edit the macros

- **dbt's Jinja sandbox is restrictive.** No `try`/`except`, no `{% break %}`,
  and only `modules.datetime`, `modules.re`, `modules.itertools` and
  `modules.pytz` are importable. There is no `pendulum` and no `dateutil`, which
  is why `macros/core/period/date_math.sql` reimplements month-end clamping.
- **`{% set %}` inside a `for` loop does not escape the loop.** Mutate a
  caller-owned dict or list, or use `namespace()`.
- **Macros cannot be dispatched by a name computed at runtime.** That is why
  `catalogue()` is a chain of explicit `if` branches rather than a lookup.
- **Errors are raised by paired macros.** `try_<name>` returns
  `{'ok': ..., 'error': ...}` and the wrapper raises. Without `try`/`except`
  there is no other way to assert on an error message in a test.
- **Never emit `/`.** Use `jstark.safe_divide`, which casts to float and
  `nullif`s the denominator — otherwise Postgres and Redshift truncate integer
  division, and everything divides by zero eventually.
- **Cuisine names go into SQL as literals.** A name containing an apostrophe
  would break the generated SQL. They are developer-supplied at compile time,
  not user input, so this is not quoted; do not pass untrusted values.
````

- [ ] **Step 7: Write the build workflow**

Create `.github/workflows/build.yml`:
```yaml
name: build

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/setup-uv@v5
        with:
          enable-cache: true

      - name: Install dependencies
        run: uv sync

      - name: Install dbt packages
        working-directory: integration_tests
        run: uv run dbt deps

      - name: Parse the project
        working-directory: integration_tests
        run: uv run dbt parse --profiles-dir .

      - name: Layer 1 — macro logic
        working-directory: integration_tests
        run: uv run dbt run-operation jstark_test_suite --profiles-dir .

      - name: Layer 2 — generated SQL
        working-directory: integration_tests
        run: |
          uv run dbt seed --profiles-dir .
          uv run dbt test --select test_type:unit --profiles-dir .

      - name: Layer 3 — end to end
        working-directory: integration_tests
        run: uv run dbt build --profiles-dir .

      - name: Generate docs
        working-directory: integration_tests
        run: uv run dbt docs generate --profiles-dir .

      - name: Check the README feature tables are up to date
        run: |
          ./scripts/update-readme.sh
          git diff --exit-code README.md \
            || (echo "README feature tables are stale. Run ./scripts/update-readme.sh and commit." && exit 1)

  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: uv sync
      - run: uv run pre-commit run --all-files
```

The layers run as separate steps rather than one `dbt build` so a failure names
the layer that broke. Layer 3's `dbt build` re-runs the unit tests, which is
cheap and means a green Layer 2 with a red Layer 3 points at the seeds.

`dbt docs generate` is there to catch documentation errors that `parse` does not,
such as a `schema.yml` describing a column no model produces.

- [ ] **Step 8: Write the cross-warehouse workflow**

Create `.github/workflows/warehouses.yml`:
```yaml
name: warehouses

# Not run on push: these need credentials, and forks do not have them.
on:
  schedule:
    - cron: '0 3 * * *'
  workflow_dispatch:

jobs:
  postgres:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: jstark
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready --health-interval 10s
          --health-timeout 5s --health-retries 5
    env:
      JSTARK_POSTGRES_HOST: localhost
      JSTARK_POSTGRES_USER: postgres
      JSTARK_POSTGRES_PASSWORD: postgres
      JSTARK_POSTGRES_DATABASE: jstark
      JSTARK_POSTGRES_SCHEMA: jstark
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
      - run: uv sync --extra postgres
      - working-directory: integration_tests
        run: uv run dbt deps
      - working-directory: integration_tests
        run: uv run dbt build --target postgres --profiles-dir . --exclude tag:duckdb_only

  warehouse:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - target: snowflake
            extra: snowflake
            gate: SNOWFLAKE_ACCOUNT
          - target: bigquery
            extra: bigquery
            gate: BIGQUERY_KEYFILE_JSON
          - target: databricks
            extra: databricks
            gate: DATABRICKS_HOST
    steps:
      - uses: actions/checkout@v4

      - name: Check whether credentials are configured
        id: gate
        env:
          GATE: ${{ secrets[matrix.gate] }}
        run: |
          if [ -z "${GATE}" ]; then
            echo "configured=false" >> "$GITHUB_OUTPUT"
            echo "::notice::No ${{ matrix.gate }} secret; skipping ${{ matrix.target }}."
          else
            echo "configured=true" >> "$GITHUB_OUTPUT"
          fi

      - uses: astral-sh/setup-uv@v5
        if: steps.gate.outputs.configured == 'true'

      - run: uv sync --extra ${{ matrix.extra }}
        if: steps.gate.outputs.configured == 'true'

      - working-directory: integration_tests
        if: steps.gate.outputs.configured == 'true'
        run: uv run dbt deps

      - working-directory: integration_tests
        if: steps.gate.outputs.configured == 'true'
        env:
          JSTARK_SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
          JSTARK_SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
          JSTARK_SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_PASSWORD }}
          JSTARK_SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_ROLE }}
          JSTARK_SNOWFLAKE_DATABASE: ${{ secrets.SNOWFLAKE_DATABASE }}
          JSTARK_SNOWFLAKE_WAREHOUSE: ${{ secrets.SNOWFLAKE_WAREHOUSE }}
          JSTARK_SNOWFLAKE_SCHEMA: ${{ secrets.SNOWFLAKE_SCHEMA }}
          JSTARK_BIGQUERY_PROJECT: ${{ secrets.BIGQUERY_PROJECT }}
          JSTARK_BIGQUERY_DATASET: ${{ secrets.BIGQUERY_DATASET }}
          JSTARK_BIGQUERY_KEYFILE_JSON: ${{ secrets.BIGQUERY_KEYFILE_JSON }}
          JSTARK_DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}
          JSTARK_DATABRICKS_HTTP_PATH: ${{ secrets.DATABRICKS_HTTP_PATH }}
          JSTARK_DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN }}
          JSTARK_DATABRICKS_SCHEMA: ${{ secrets.DATABRICKS_SCHEMA }}
        run: |
          uv run dbt build --target ${{ matrix.target }} --profiles-dir . \
            --exclude tag:duckdb_only
```

A missing secret makes the job succeed with a notice rather than fail, so the
nightly run is green for anyone who has not configured a warehouse — including
anyone who forks this. `fail-fast: false` keeps one broken warehouse from hiding
the others.

`--exclude tag:duckdb_only` drops the two unit tests whose expected values use
DuckDB array syntax (Task 12 Step 10). Everything else is expected to pass
everywhere; where it does not, that is the bug this workflow exists to find.

- [ ] **Step 9: Add the optional adapter extras**

Modify `pyproject.toml` to add the extras the workflow installs:
```toml
[project.optional-dependencies]
postgres = ["dbt-postgres>=1.8,<2.0"]
snowflake = ["dbt-snowflake>=1.8,<2.0"]
bigquery = ["dbt-bigquery>=1.8,<2.0"]
databricks = ["dbt-databricks>=1.8,<2.0"]
```

`[tool.uv] package = false` from Task 1 stays: this is not a Python package, and
the extras exist only to give the workflow something to install.

Verify the Postgres path locally if Docker is available — it is the one adapter
in that workflow that can be tested without credentials, and the one whose
fallbacks (`postgres__jstark_approx_count_distinct`, integer division) are most
likely to be wrong:
```bash
docker run -d --name jstark-pg -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=jstark -p 5432:5432 postgres:16
uv sync --extra postgres
cd integration_tests
JSTARK_POSTGRES_HOST=localhost JSTARK_POSTGRES_USER=postgres \
  JSTARK_POSTGRES_PASSWORD=postgres JSTARK_POSTGRES_DATABASE=jstark \
  JSTARK_POSTGRES_SCHEMA=jstark \
  uv run dbt build --target postgres --profiles-dir . --exclude tag:duckdb_only
docker rm -f jstark-pg
```
If this fails, fix it — a broken Postgres path is a real portability bug, not a
CI configuration problem. If Docker is unavailable, say so in the final report
rather than silently skipping it.

- [ ] **Step 10: Run everything one last time**

```bash
uv run pre-commit run --all-files
cd integration_tests
uv run dbt run-operation jstark_test_suite --profiles-dir .
uv run dbt build --profiles-dir .
uv run dbt docs generate --profiles-dir .
cd ..
./scripts/update-readme.sh && git diff --exit-code README.md
```
Expected: all pass, and no README diff.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
docs: add the README, contributing guide and CI workflows

The README's feature tables are generated from the macros by
scripts/update-readme.sh, and CI fails if they are stale, so the documented
features cannot drift from the implemented ones.

Two workflows: build runs the three test layers on DuckDB for every push, and
warehouses runs nightly against Postgres in a service container plus any
warehouse whose credentials are configured. A missing secret skips its job with
a notice rather than failing, so a fork's nightly run is green.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 12: Open the pull request**

```bash
git push -u origin feat/dbt-jstark-implementation
gh pr create --title "Implement dbt-jstark" --body "$(cat <<'EOF'
Reimplements [jstark](https://github.com/jamiekt/jstark)'s feature generation as
a dbt macro package, per `docs/superpowers/specs/2026-09-13-dbt-jstark-design.md`.

- `jstark.grocery_features` and `jstark.mealkit_features` generate 37 and 23
  features respectively over any number of feature periods
- All date arithmetic happens in Jinja at compile time, so the emitted SQL is
  warehouse-agnostic; the four constructs that genuinely differ go through
  adapter dispatch
- Three test layers: macro logic with no warehouse, dbt unit tests over the
  generated SQL, and end-to-end builds
- Tested on DuckDB on every push, and nightly against Postgres and any
  warehouse with credentials configured

See the README for usage and for the differences from jstark.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Appendix: what is deliberately not here

- **Publishing to the dbt Hub.** Out of scope by request.
- **SQL linting.** sqlfluff cannot lint a macro that emits a fragment of a
  larger query without a lot of configuration for little benefit; the tests
  check the SQL means the right thing, which matters more than its layout.
- **Separately installable industry packages.** dbt resolves one
  `dbt_project.yml` per package, so shipping `jstark-grocery` and
  `jstark-mealkit` separately would mean separate repositories or a
  monorepo-with-subdirectory-refs arrangement that dbt does not support
  cleanly. A single package with namespaced macros gives the same isolation:
  a grocery user calls `jstark.grocery_features` and never sees the mealkit
  macros.
- **jstark's `references` / `flattened_references`.** They inspect a Spark
  query plan. `feature_catalog`'s `required_columns` serves the same purpose.
