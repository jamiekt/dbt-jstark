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
`macros/core/adapters/`, as `<adapter>__<name>`. Each is dispatched via
`adapter.dispatch('<name>', 'jstark')`, the dispatched name always carries a
`jstark_` prefix, and each one lives in its own file named after it (e.g.
`macros/core/adapters/jstark_collect_set.sql`):

| Macro | What it must return |
| --- | --- |
| `<adapter>__jstark_to_date(expression)` | SQL casting a timestamp to a date |
| `<adapter>__jstark_double_type(expression)` | The name of an 8-byte double-precision floating point type. Only needs overriding when the warehouse doesn't spell it `double precision`; `bigquery__jstark_double_type` returns `'float64'` because BigQuery has no `double precision` synonym. |
| `<adapter>__jstark_approx_count_distinct(expression)` | SQL for an approximate distinct count. If your warehouse has none, return an exact count and `exceptions.warn` — that is what `postgres__` does. **Beware when writing fixtures:** a HyperLogLog estimate need not equal the exact count on tiny inputs, so an `Approx*` expectation is only portable if the fixture's values happen to make the two agree. DuckDB 1.5.5's `approx_count_distinct` estimates the pair `('o1','o2')` as 1, not 2, while Postgres computes it exactly — which is why `mealkit_orders` uses `ord1`/`ord2`/`ord3`. If an `Approx*` value disagrees between warehouses, change the fixture values rather than pinning what one warehouse happens to return. |
| `<adapter>__jstark_collect_set(expression, window)` | SQL for a sorted, deduplicated, null-free array of `expression` over rows matching `window`. Two shapes work: `FILTER (WHERE ...)` where supported, `CASE WHEN` otherwise. |
| `<adapter>__jstark_empty_string_array()` | A literal empty array of strings |

Everything else routes through dbt-core's cross-database macros (`dbt.datediff`,
`dbt.type_float`, `dbt.type_string`) and needs nothing. Not everything in
`macros/core/adapters/` is a dispatch shim, though: `safe_divide.sql` and
`aggregate_sql.sql` live in the same directory but call the dispatched macros
above rather than being dispatched themselves — they are the same on every
warehouse.

Then add a target to `integration_tests/profiles.yml` and a matrix entry to
`.github/workflows/warehouses.yml`. The Snowflake and BigQuery variants that ship
today were written from the documentation and have not been run against a real
warehouse; verifying them is a genuinely useful contribution.

Databricks is the clearest gap: it has a profile target and a nightly job but no
`databricks__` macros at all, so it falls through to `default__`, which emits
`list_sort(...)` and `cast(array[] as text[])` — neither of which is Spark SQL.
`databricks__jstark_collect_set` and `databricks__jstark_empty_string_array`
are known to be needed. Whether `databricks__jstark_double_type` is also
needed depends on whether Spark SQL accepts `double precision` as a type
name (the `default__` value every other adapter without an override
inherits) — that has not been checked against a running cluster, so do not
assume the two macros above are the whole job until someone has run this
against Databricks and found out.

## Things to know before you edit the macros

- **dbt's Jinja sandbox is restrictive.** No `try`/`except`, no `{% break %}` or
  `{% continue %}`, no dynamic macro-name dispatch, and only `modules.datetime`,
  `modules.re`, `modules.itertools` and `modules.pytz` are importable. There is
  no `pendulum` and no `dateutil`, which is why
  `macros/core/period/date_math.sql` reimplements month-end clamping.
- **`{% set %}` inside a `for` loop does not escape the loop.** Mutate a
  caller-owned dict or list, or use `namespace()`.
- **Macros cannot be dispatched by a name computed at runtime.** That is why
  `catalogue()` is a chain of explicit `if` branches rather than a lookup.
- **Errors are raised by paired macros.** `try_<name>` returns
  `{'ok': ..., 'error': ...}` and the wrapper raises. Without `try`/`except`
  there is no other way to assert on an error message in a test. There are
  nine error codes today; see `macros/core/exceptions.sql` — that list is not
  frozen, so add to it rather than reusing a code for something new.
- **Never emit `/`.** Use `jstark.safe_divide`, which casts to
  `jstark.double_type()` and `nullif`s the denominator — otherwise Postgres and
  Redshift truncate integer division, and everything divides by zero
  eventually.
- **Cuisine names go into SQL as string literals, with quotes doubled.**
  `register_mealkit_cuisine_features` passes the cuisine through
  `jstark.sql_string()` (`macros/core/feature_catalog.sql`), which doubles
  embedded apostrophes, so a name like `Shepherd's` emits valid SQL. Any new
  feature that splices a caller-supplied *value* into a literal must go
  through `jstark.sql_string()` too. This protects the generated SQL from
  breaking on legitimate punctuation; it is not a sanitiser, and `cuisines` is
  still a compile-time developer parameter, so do not route untrusted input
  into it.
