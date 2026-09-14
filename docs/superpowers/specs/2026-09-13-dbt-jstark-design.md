# dbt-jstark design

Date: 2026-09-13

## Purpose

[jstark](https://github.com/jamiekt/jstark) is a PySpark library that dynamically generates
time-based features — aggregations of transactional data calculated relative to an *as at* date
over configurable time windows. `dbt-jstark` reimplements the same logic as dbt macros so that
someone working in SQL can generate the same features without PySpark.

The package is warehouse agnostic. It is developed and tested against DuckDB because DuckDB is
free and runs in CI without credentials, with the seams and CI scaffolding needed to add other
warehouses later.

## Scope

In scope:

- A core engine that turns feature definitions into SQL.
- Full parity with jstark's grocery catalogue (37 features).
- Full parity with jstark's mealkit catalogue (23 features), with the 95 hardcoded
  `*CuisineCount` classes replaced by a parameterised `cuisines` argument.
- A queryable feature metadata catalogue and a `schema.yml` code generator.
- Three layers of tests, all runnable in CI on DuckDB.
- README-driven documentation with generated, drift-checked feature tables.
- A GitHub Actions workflow running the tests.

Out of scope:

- Publishing the package (dbt Hub or otherwise).
- Running CI against warehouses other than DuckDB. The scaffolding is built; the jobs are
  gated on absent secrets and skip.

## Packaging

A single dbt package named `jstark` at the repository root, with macros namespaced by
directory: `macros/core/`, `macros/grocery/`, `macros/mealkit/`. Users install one thing and
call `jstark.grocery_features(...)`.

Multi-package monorepos *are* possible — `packages.yml` supports a `subdirectory` key on git
installs — and were considered. They were rejected because core changes would need version
coordination across three packages, local development would need relative-path dependencies,
and dbt Hub indexes only one package per repository root. Macros are inert until called, so a
grocery user downloading the mealkit macros costs nothing.

## Repository layout

```
dbt-jstark/
├── dbt_project.yml                      # name: jstark
├── macros/
│   ├── core/
│   │   ├── generate_features.sql        # the engine
│   │   ├── feature_catalog.sql          # metadata model builder
│   │   ├── generate_schema_yml.sql      # run-operation docs codegen
│   │   ├── generate_feature_reference.sql  # run-operation README table codegen
│   │   ├── registry.sql                 # stem -> definition, dependency closure
│   │   ├── naming.sql                   # stem + period -> snake_case column name
│   │   ├── exceptions.sql               # named compile-time errors
│   │   ├── period/
│   │   │   ├── parse_mnemonic.sql       # '3m1' -> {uom, start, end}
│   │   │   ├── period_bounds.sql        # -> start_date, end_date
│   │   │   ├── date_math.sql            # month/quarter/year arithmetic, week starts
│   │   │   └── period_label.sql         # absolute labels: 2021q4, 2026w13, 20211231
│   │   ├── adapters/
│   │   │   ├── jstark_approx_count_distinct.sql
│   │   │   ├── jstark_collect_set.sql
│   │   │   └── jstark_to_date.sql
│   │   └── features/                    # cross-industry definitions
│   ├── grocery/
│   │   ├── grocery_features.sql         # public entry point
│   │   └── features/
│   └── mealkit/
│       ├── mealkit_features.sql
│       └── features/
├── integration_tests/
│   ├── dbt_project.yml
│   ├── packages.yml                     # local: ../
│   ├── profiles.yml                     # duckdb default + gated warehouse targets
│   ├── seeds/
│   ├── models/{core,grocery,mealkit}/    # models + unit_tests YAML
│   └── macros/jstark_test_suite.sql      # L1 assertions
├── .github/workflows/
│   ├── build.yml
│   └── warehouses.yml
├── pyproject.toml                       # uv; dbt-core, dbt-duckdb
├── .python-version
├── .pre-commit-config.yaml
├── README.md
├── CONTRIBUTING.md
└── LICENSE.txt
```

`require-dbt-version: [">=1.8.0", "<2.0.0"]` — dbt unit tests need 1.8.

## Public API

```sql
jstark.grocery_features(input, group_by, as_at=none, feature_periods=none,
                        feature_stems=none, first_day_of_week=none,
                        use_absolute_periods=false, column_map={})

jstark.mealkit_features(...same..., cuisines=[])

jstark.feature_catalog(generator='grocery', as_at=none, feature_periods=none,
                       feature_stems=none, first_day_of_week=none,
                       use_absolute_periods=false, cuisines=[])

jstark.generate_features(input, group_by, catalogue=[...], ...)   -- core; build your own industry
```

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `input` | Relation or string | required | `ref()`/`source()` result, or a raw SQL statement. Detected at compile time; wrapped as a CTE either way. |
| `group_by` | list of strings | required | Input column names, emitted verbatim. May be empty for a single-row result. |
| `as_at` | string `YYYY-MM-DD` or date | see below | The point in time all windows are relative to. |
| `feature_periods` | list | `['52w0']` | Each entry is either a mnemonic string (`'3m1'`) or a dict `{'unit': 'm', 'start': 3, 'end': 1}` — the Jinja analogue of jstark's `FeaturePeriod`. Default matches `FeaturePeriod(WEEK, 52, 0)`. |
| `feature_stems` | list of strings | all | Unknown stems are a compile error listing valid ones. |
| `first_day_of_week` | string | `'Monday'` | One of the seven English weekday names. |
| `use_absolute_periods` | boolean | `false` | Suffix column names with absolute period labels instead of mnemonics. |
| `column_map` | dict | `{}` | Remaps canonical input column names. Unknown keys are a compile error. |
| `cuisines` | list of strings | `[]` | Mealkit only. Each entry yields one `<name>_cuisine_count_<period>` feature. |

### `as_at` resolution

jstark defaults `as_at` to `date.today()`. A dbt model doing the same silently produces
different numbers on every rebuild, so resolution is:

1. The `as_at` argument, if given.
2. `var('jstark_as_at')`, if set.
3. The run date, accompanied by a compile-time warning naming the var.

An explicit `as_at` is deterministic and unit-testable; the fallback exists so the quick start
works without ceremony.

## The core engine

### Feature definitions

One macro per feature, one file per macro, mirroring jstark's one-class-per-file layout. The
macro receives a `ctx` carrying the resolved period, `as_at`, `first_day_of_week` and the
resolved column map — the analogue of jstark's `Feature.__init__`.

Base feature:

```sql
{% macro jstark_feature__gross_spend(ctx) %}
  {{ return({
      'stem': 'GrossSpend',
      'kind': 'base',
      'aggregator': 'sum',
      'expression': ctx.cols['gross_spend'],
      'default': '0.0',
      'required_columns': ['event_timestamp', 'gross_spend'],
      'description_subject': 'Sum of GrossSpend',
      'commentary': 'The definition of GrossSpend can be whatever you want it to be ...'
  }) }}
{% endmacro %}
```

Base definitions are rendered by a single template, jstark's `BaseFeature.column`
transliterated:

```sql
coalesce(<aggregator>(case when <jstark_to_date(event_timestamp)>
                           between <start_date literal> and <end_date literal>
                      then <expression> end), <default>)
```

Aggregators available to base features, matching jstark's `BaseFeature`:
`sum`, `count`, `count_if`, `count_distinct`, `approx_count_distinct`, `max`, `min`,
`collect_set`. `count_if` renders as `count(case when <window> and <expression> then 1 end)`,
which is portable and equivalent.

Derived feature:

```sql
{% macro jstark_feature__avg_gross_spend_per_basket(ctx) %}
  {% set gs = jstark.column_name('GrossSpend', ctx.period) %}
  {% set bc = jstark.column_name('BasketCount', ctx.period) %}
  {{ return({
      'stem': 'AvgGrossSpendPerBasket',
      'kind': 'derived',
      'depends_on': [('GrossSpend', ctx.period), ('BasketCount', ctx.period)],
      'expression': jstark.safe_divide(gs, bc),
      'default': 'null',
      'description_subject': 'Average GrossSpend per Basket',
      'commentary': 'Total GrossSpend divided by the number of baskets'
  }) }}
{% endmacro %}
```

`depends_on` and `expression` name the same columns twice. An L1 test closes that gap: for
every derived feature, every feature-shaped identifier appearing in `expression` must be
declared in `depends_on`.

Derived definitions render as `coalesce(<expression>, <default>)`, matching
`DerivedFeature.column`.

### Resolution and SQL shape

Requested stems × requested periods form the initial set. Dependencies are expanded
transitively — `CyclesSinceLastPurchase` → `AvgPurchaseCycle` →
{`MostRecentPurchaseDate`, `EarliestPurchaseDate`, `BasketCount`} — until only base features
remain. Because SQL cannot reference an alias defined in the same select list, features are
topologically sorted into levels and one CTE is emitted per level:

```sql
with jstark_input as ( <input> ),

jstark_base as (
    select <group_by>,
           <every base aggregate, requested or required as a dependency>
    from jstark_input
    group by <group_by>
),
jstark_derived_1 as ( select *, <derived features whose deps are all base> from jstark_base ),
jstark_derived_2 as ( select *, <derived features depending on level 1>    from jstark_derived_1 )

select <group_by>, <only the requested feature columns>
from jstark_derived_2
```

The grocery catalogue bottoms out at level 2. Helper aggregates existing only to feed derived
features — `basket_count_3m3`, `basket_count_2m2`, `basket_count_1m1` behind
`basket_months_3m1` — live in `jstark_base` and are dropped by the final projection. This is
the main improvement over jstark: `BasketMonths_3m1` and
`RecencyWeightedBasketMonths95_3m1` share one set of distinct-counts, where jstark's
`DerivedFeature.column_expression()` inlines a separate copy for each.

When `group_by` is empty the `group by` clause is omitted.

### Period arithmetic

All period arithmetic runs in Jinja at compile time, so `start_date` and `end_date` reach the
warehouse as literals and no date math happens at query time.

dbt exposes only `modules.datetime` — no `pendulum`, no `dateutil.relativedelta` — so
month, quarter and year arithmetic is hand-rolled integer math on `(year, month)`:

```
total = year * 12 + (month - 1) - n
y     = total // 12
m     = total % 12 + 1
day   = min(original_day, days_in_month(y, m))
```

End-of-month clamping matches pendulum: `2022-03-31` minus one month is `2022-02-28`.

Week boundaries derive from `first_day_of_week`:
`first_date_in_week = d - ((d.weekday() - target_weekday) % 7)`, and
`last_date_in_week = first_date_in_week + 6 days`.

`end_date` is capped at `as_at`, matching jstark's `min(last_day_of_period, self.as_at)`.

Mnemonics parse as `^(\d*)([dwmqy])(\d*)$`, matching jstark's regex and unit values
(`d`, `w`, `m`, `q`, `y`).

### Naming

Feature column names are `<snake_case stem>_<suffix>`, all lowercase and unquoted.

The CamelCase-to-snake_case rule: insert `_` before an uppercase letter that follows a
lowercase letter or a digit; digits stay attached to the token they follow; then lowercase.

| Stem | Column base |
| --- | --- |
| `Count` | `count` |
| `MinNetPrice` | `min_net_price` |
| `AvgGrossSpendPerBasket` | `avg_gross_spend_per_basket` |
| `AverageBasketsPerMonth` | `average_baskets_per_month` |
| `RecencyWeightedApproxBasketMonths95` | `recency_weighted_approx_basket_months95` |
| `CyclesSinceLastPurchase` | `cycles_since_last_purchase` |

Some features override the name derived from their stem, interpolating the period's unit —
exactly as jstark's `feature_name` property does, so `BasketPeriods` never appears in output:

| Stem | Emitted name for period `3m1` |
| --- | --- |
| `BasketPeriods` | `basket_months_3m1` |
| `OrderPeriods` | `order_months_3m1` |
| `AvgBasket` | `average_baskets_per_month_3m1` |
| `AvgOrder` | `average_orders_per_month_3m1` |
| `RecencyWeightedBasket95` | `recency_weighted_basket_months95_3m1` |
| `RecencyWeightedApproxBasket95` | `recency_weighted_approx_basket_months95_3m1` |

A definition may therefore supply a `name` key; the engine falls back to the snake_cased stem
when it is absent. `feature_stems` and `depends_on` always refer to the stem, never the emitted
name.

The suffix is the period mnemonic (`3m1`) or, when `use_absolute_periods` is true, the absolute
period label. jstark builds absolute names like `BasketCount_2021Oct-2021Dec`, and a hyphen is
illegal in an unquoted SQL identifier, so absolute suffixes are lowercased and use `_to_` for
spanning windows:

| Unit | Single period | Spanning |
| --- | --- | --- |
| day | `20211231` | `20211001_to_20211231` |
| week | `2021w40` | `2021w40_to_2021w52` |
| month | `2021dec` | `2021oct_to_2021dec` |
| quarter | `2021q4` | `2021q3_to_2021q4` |
| year | `2021` | `2020_to_2021` |

The week label replicates jstark's `_week_label`: W01 of a year begins on the first occurrence
of `first_day_of_week` on or before 1 January.

### Canonical input columns

Input column references are emitted **unquoted**, so that warehouse case-folding does the right
thing — quoting `"gross_spend"` would break on Snowflake, where an unquoted `create table`
stores the column as `GROSS_SPEND`. Because references are unquoted, canonical names must avoid
reserved words.

| jstark | dbt-jstark canonical | Used by |
| --- | --- | --- |
| `Timestamp` | `event_timestamp` | every feature |
| `Basket` | `basket` | grocery |
| `Order` | `order_id` | mealkit |
| `Store` | `store` | grocery |
| `Channel` | `channel` | grocery |
| `Customer` | `customer` | both |
| `Product` | `product` | both |
| `Quantity` | `quantity` | both |
| `NetSpend` | `net_spend` | grocery |
| `GrossSpend` | `gross_spend` | grocery |
| `Discount` | `discount` | both |
| `Cuisine` | `cuisine` | mealkit |
| `Recipe` | `recipe` | mealkit |
| `Allergen` | `allergen` | mealkit |

`timestamp` and `order` are deliberately avoided: `cast(timestamp as date)` is a syntax error
on Postgres, which parses `timestamp` as a type name, and `order` is reserved everywhere.
Users whose columns carry those names remap via `column_map` to a safe canonical name and
rename in a staging model, which the README documents.

### Validation

Compile-time errors, because a clear Jinja error beats a warehouse error:

| Error | Trigger |
| --- | --- |
| `jstark_feature_period_mnemonic_is_invalid` | mnemonic fails the regex |
| `jstark_feature_period_end_greater_than_start` | `end > start` |
| `jstark_feature_not_found` | unknown stem; message lists valid stems |
| `jstark_unknown_column_map_key` | `column_map` key is not a canonical name |
| `jstark_invalid_first_day_of_week` | not one of the seven weekday names |

Input column existence is not validated: the relation frequently does not exist at parse time.
`feature_catalog` reports required columns per feature instead.

## Feature catalogue

### Core (cross-industry)

`Count`, `CustomerCount`, `ApproxCustomerCount`, `ProductCount`, `ApproxProductCount`,
`Quantity`, `Discount`, `GrossSpend`, `NetSpend`, `MinGrossSpend`, `MaxGrossSpend`,
`MinNetSpend`, `MaxNetSpend`, `MinGrossPrice`, `MaxGrossPrice`, `MinNetPrice`, `MaxNetPrice`,
`RecencyDays`, `EarliestPurchaseDate`, `MostRecentPurchaseDate`.

### Grocery (37 total)

All 20 core features, plus 17 grocery-specific ones: `BasketCount`, `ApproxBasketCount`, `StoreCount`,
`ChannelCount`, `AvgGrossSpendPerBasket`, `AvgQuantityPerBasket`, `AvgDiscountPerBasket`,
`AvgPurchaseCycle`, `CyclesSinceLastPurchase`, `BasketPeriods` (named
`basket_<unit>s_<period>`), `AvgBasket` (named `average_baskets_per_<unit>_<period>`),
`RecencyWeightedBasket90/95/99`, `RecencyWeightedApproxBasket90/95/99`.

### Mealkit (23 total, plus parameterised cuisines)

`Count`, `CustomerCount`, `ApproxCustomerCount`, `ProductCount`, `ApproxProductCount`,
`Quantity`, `Discount`, `RecencyDays`, `EarliestPurchaseDate`, `MostRecentPurchaseDate`,
`OrderCount`, `ApproxOrderCount`, `RecipeCount`, `ApproxRecipeCount`, `AllergenCount`,
`Allergens`, `CuisineCount`, `Cuisines`, `AvgQuantityPerOrder`, `AvgPurchaseCycle`,
`CyclesSinceLastOrder`, `OrderPeriods` (named `order_<unit>s_<period>`), `AvgOrder` (named
`average_orders_per_<unit>_<period>`).

Plus, for each entry in `cuisines`, a `<snake_case name>_cuisine_count_<period>` feature
rendering as `count(case when <window> and cuisine = '<name>' then 1 end)`.

## Metadata

Two consumers, two mechanisms, both driven from the same definitions.

`jstark.feature_catalog(...)` builds a queryable model, one row per generated feature:

```
feature_name | stem | period_mnemonic | period_unit | start_date | end_date
             | description | commentary | required_columns | kind
```

`dbt run-operation jstark_generate_schema_yml --args '{...}'` prints ready-to-paste
`schema.yml`, so descriptions reach dbt docs and, with `persist_docs`, warehouse column
comments.

Descriptions follow jstark: `"<description_subject> between <start_date> and <end_date>"`.

## Portability

Cross-database primitives come from dbt-core's own macros: `dbt.datediff`, `dbt.safe_cast`,
`dbt.type_float`. Three seams need `adapter.dispatch`:

| Seam | DuckDB | Snowflake | BigQuery | Postgres |
| --- | --- | --- | --- | --- |
| `jstark_approx_count_distinct` | `approx_count_distinct(x)` | `approx_count_distinct(x)` | `approx_count_distinct(x)` | exact `count(distinct x)` + warning |
| `jstark_collect_set` | `list_sort(array_agg(distinct x))` | `array_agg(distinct x) within group (order by x)` | `array_agg(distinct x ignore nulls order by x)` | `array_agg(distinct x order by x)` |
| `jstark_to_date` | `cast(x as date)` | `cast(x as date)` | `cast(x as date)` | `cast(x as date)` |

`jstark_to_date` is identical across the four adapters today; the seam exists so an adapter that
differs can be added without touching feature definitions.

Two further portability points:

- **Integer division.** `gross_spend / nullif(basket_count, 0)` truncates on Postgres and
  Redshift, where `integer / integer` is integer division, whereas jstark's `try_divide` always
  returns a float. A shared `jstark.safe_divide(a, b)` helper emits
  `cast(<a> as {{ dbt.type_float() }}) / nullif(<b>, 0)`. Null-on-divide-by-zero matches
  `try_divide`.
- **Exponential smoothing weights.** `0.95 ** period` is evaluated in Jinja, so weights land as
  float literals and no SQL `pow` is needed.

Adding a warehouse means implementing the three dispatch macros and adding a target to
`integration_tests/profiles.yml`.

## Testing

### L1 — pure Jinja assertions

`dbt run-operation jstark_test_suite`, run from `integration_tests/`. Sub-second, no data. An
assertion helper accumulates failures and raises once with a summary of all of them, so a run
reports every broken case rather than the first.

Coverage:

- Mnemonic parsing: valid (`3m1`, `52w0`, `0d0`, `1y1`, `4q4`) and invalid (`3x1`, `abc`, ``).
- Period bounds for every unit, checked against hand-computed dates.
- Month-end clamping (`2022-03-31` minus one month) and leap years (`2020-02-29`).
- `end_date` capping at `as_at` — `0m0` on 2022-01-15 ends 2022-01-15, not 2022-01-31.
- Week starts for all seven `first_day_of_week` values.
- `_week_label` year-boundary cases.
- Absolute period labels for every unit, single and spanning.
- CamelCase-to-snake_case on the awkward stems in the naming table above.
- Every stem in every industry catalogue resolves to a definition.
- Derived-feature `expression`/`depends_on` consistency.
- Dependency graph acyclicity and correct level assignment.
- Each named error firing on its trigger.

### L2 — dbt unit tests

Small purpose-built models in `integration_tests/models/`, each pinned to a fixed `as_at`, with
`unit_tests:` YAML supplying input rows and expected output rows. One model per concern rather
than one wide model:

- One model per aggregator family: sum, count, count_distinct, min, max, collect_set, count_if.
- One model per derived feature.
- A window-boundary model with rows exactly on `start_date`, exactly on `end_date`, and one day
  either side.
- An empty-window model asserting defaults: `0.0` for sums, `0` for counts, `null` for derived.
- A `column_map` model.
- A `use_absolute_periods` model.
- A multi-period × multi-`group_by` model.
- A mealkit `cuisines` model.
- An empty `group_by` model returning one row.

Array-valued features (`allergens`, `cuisines`) use `format: sql` fixtures so expected arrays
can be written as literals.

Approximate-count features are the one place exact assertions are unsafe in general. On
fixtures this small HLL is exact, so they get exact L2 assertions plus a tolerance-based L3 test
on the larger seed.

### L3 — full build on DuckDB

`dbt build` over the integration project: seeds → all models → `dbt_utils.equality` data tests
against expected seeds → `feature_catalog` row-count and not-null assertions. Then
`dbt docs generate`, and a check that the generated `schema.yml` output parses.

## CI

`.github/workflows/build.yml`, on push and pull request:

1. `uv sync`
2. `dbt deps`
3. `dbt parse` — syntax gate
4. `dbt run-operation jstark_test_suite` — L1
5. `dbt test --select test_type:unit` — L2
6. `dbt build` — L3
7. `dbt docs generate`
8. Regenerate the README feature tables and `git diff --exit-code`, so documentation cannot
   drift from the code — the analogue of jstark's cog blocks.

`.github/workflows/warehouses.yml`, on `workflow_dispatch` and a nightly schedule: the same
suite against a matrix of Postgres (service container), Snowflake, BigQuery and Databricks
targets, each job skipped when its secret is absent.

SQL linting is deliberately omitted. Both `sqlfluff` and `sqlfmt` fight heavily-Jinja'd macro
files, and `dbt parse` plus a `pre-commit` config for trailing whitespace, end-of-file and YAML
checks covers what matters without the friction.

Dev tooling is `uv` with `pyproject.toml` declaring `dbt-core` and `dbt-duckdb`, matching
jstark.

## Documentation

`README.md`, in jstark's style:

1. What it is, and the relationship to jstark.
2. Feature period mnemonics.
3. Quick start — copy-paste runnable against DuckDB.
4. The input contract: canonical column names, and required columns per feature.
5. Calling conventions: Relation vs SQL string, `column_map`.
6. Full parameter reference.
7. Feature catalogue tables for grocery and mealkit, generated and inside collapsed
   `<details>`.
8. Using `feature_catalog` and the `schema.yml` generator.
9. Adding your own industry on top of the core macros.
10. Parity with jstark: the divergence table below.

`CONTRIBUTING.md` covers how to add a feature and how to add an adapter.

## Divergences from jstark

| jstark | dbt-jstark | Why |
| --- | --- | --- |
| `BasketCount_3m1` | `basket_count_3m1` | Warehouses disagree on unquoted identifier case-folding; snake_case is identical everywhere and needs no quoting. |
| `Timestamp`, `Order` input columns | `event_timestamp`, `order_id` | Input refs are unquoted so case-folding works; `cast(timestamp as date)` is a Postgres syntax error and `order` is reserved. |
| 95 hardcoded `*CuisineCount` classes | `cuisines=[...]` parameter | Same capability, far less generated SQL, and drops inherited typos (`IsrealiCuisineCount`, `FusionCuisineCusiineCount`, `SouthHyphenAfricanCuisineCount`). |
| `try_divide(a, b)` | `cast(a as float) / nullif(b, 0)` | Portable, and identical null-on-zero semantics. |
| `BasketCount_2021Oct-2021Dec` | `basket_count_2021oct_to_2021dec` | Hyphens are illegal in unquoted SQL identifiers. |
| `gf.references[...]` from the Spark query plan | `required_columns` in each definition | There is no query plan to introspect from Jinja. |
| `collect_set` (unordered) | sorted array | Makes `allergens_3m1` deterministic and therefore testable. |
| Column metadata on the DataFrame schema | `feature_catalog()` model + `schema.yml` codegen | SQL columns carry no metadata. |
| Derived features inline their dependencies | Shared base CTE, dependencies computed once | `BasketMonths_52w0` and `RecencyWeightedBasketMonths95_52w0` would otherwise compute 106 distinct-counts instead of 53. |
| `as_at` defaults to `date.today()` | `as_at` → `var('jstark_as_at')` → run date, with a warning | A model whose numbers change on every rebuild is a trap; dbt makes the alternative easy. |

## Implementation order

Each phase leaves the repository green, so CI is meaningful from phase 2 onward.

1. **Scaffolding** — `dbt_project.yml`, `pyproject.toml`, `integration_tests/` skeleton with a
   DuckDB profile, `.pre-commit-config.yaml`. `dbt parse` succeeds.
2. **Period arithmetic and naming** — `period/`, `naming.sql`, `exceptions.sql`, and the L1
   assertion harness covering them. This is where most of the subtle logic lives, and it is
   testable with no SQL at all.
3. **Engine** — `registry.sql`, `generate_features.sql`: dependency closure, topological
   levelling, CTE emission. Proven with two hand-written toy features (one base, one derived)
   and L2 unit tests.
4. **Adapter seams** — the three dispatch macros plus `safe_divide`.
5. **Core features** — all 20, each with L2 unit tests as it lands.
6. **Grocery** — the 17 grocery-specific features, `grocery_features.sql`, L2 and L3 tests.
7. **Mealkit** — the 13 mealkit-specific features, parameterised cuisines,
   `mealkit_features.sql`, L2 and L3 tests.
8. **Metadata** — `feature_catalog.sql`, `generate_schema_yml.sql`.
9. **Docs and CI** — `generate_feature_reference.sql`, `README.md`, `CONTRIBUTING.md`,
   `build.yml`, `warehouses.yml`, drift check.

## Open risks

- **dbt unit test support for wide, dynamically-named models.** L2 assumes `unit_tests` handles
  models whose column list is generated at compile time. It should — unit tests mock inputs,
  not outputs — but if a limitation surfaces, the affected cases fall back to L3-style seed
  equality tests, which are strictly more capable and only slower.
- **`array_agg(distinct x order by x)` support.** Verified as correct for DuckDB and Postgres
  from documentation; the Snowflake and BigQuery forms are untested until those CI jobs run
  with credentials. They are isolated behind one dispatch macro.
