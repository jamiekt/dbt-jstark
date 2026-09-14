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

## 3. Quick start

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

## 4. Feature period mnemonics

A feature period is a window ending on or before `as_at`, written as a mnemonic:

```
52w0
│ │└── end:   0 weeks before as_at
│ └─── unit:  weeks
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
| `group_by` | required | Columns to aggregate by, e.g. `['customer']`. Bare column names only; see §6. |
| `as_at` | see below | The date the features are calculated as at. |
| `feature_periods` | `['52w0']` | Mnemonics or period dicts, each period at most once. |
| `feature_stems` | all | Restrict to named features, e.g. `['NetSpend', 'BasketCount']`. |
| `first_day_of_week` | `Monday` | Which day starts a week, for `w` periods. |
| `use_absolute_periods` | `false` | Name columns by date rather than by mnemonic. |
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

The macro expects these columns. Every column a requested feature reads has to
exist in the input: nothing here inspects your data and drops the features it
cannot compute. Ask for all of a generator's features and you need all of the
columns below; if your input has only some of them, name the features you want
with `feature_stems` and only their columns are read. The `Requires` column in
§7 lists what each feature reads.

A column that is missing is reported by the warehouse rather than by jstark —
DuckDB says `Binder Error: Referenced column "product" not found in FROM
clause!` — so if you see a binder error naming a column you never mentioned, it
is a feature asking for it, and `feature_stems` is the parameter that narrows
the set.

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

Note there is no `timestamp` or `order` column, unlike jstark: both are reserved
words in one warehouse or another. Use `event_timestamp` and `order_id`.

### Columns named something else

There is no rename parameter. If your table names these columns differently,
pass SQL instead of a `ref()` and alias them there:

```sql
{{ jstark.grocery_features(
    input="select txn_date as event_timestamp,
                  transaction_id as basket,
                  price * quantity as gross_spend,
                  customer_id
           from " ~ ref('transactions'),
    group_by=['customer_id'],
    feature_periods=['13w0']
) }}
```

The string is inlined as the first CTE, so everything downstream sees the
canonical names while your table keeps its own. The same route handles a derived
grouping column, which is why `group_by` takes bare column names and not
expressions: compute `date_trunc('month', txn_date) as txn_month` in the `input`
SQL and name `txn_month` in `group_by`.

One thing this does not change is the documentation: the `Requires` column in §7,
and `jstark_generate_schema_yml`, always report the canonical names, because a
feature's required columns are what it reads after the rename.

## 7. Features reference

Column names are the snake_case stem plus the period, so `NetSpend` at `13w0`
becomes `net_spend_13w0`. Features whose meaning depends on the period's unit put
the unit in the name: `BasketPeriods` at `3m1` is `basket_months_3m1` and at
`13w0` is `basket_weeks_13w0`.

The tables below are generated from the macros by
[cog](https://cog.readthedocs.io/) — run `uv run cog -r -I scripts README.md` to
refresh them, and note that CI fails on a stale table — so do not hand-edit the
rows. They are rendered for one canonical
monthly period, which is why the **Column** patterns keep a `{unit}` placeholder
while the **Description** of a unit-dependent feature is already resolved to
months — `AvgBasket` reads "Average number of baskets per month". Ask for the
same feature at `13w0` and both the column name and its generated description
say weeks instead.

<details>
<summary><b>Grocery — 37 features</b></summary>

<!-- [[[cog
from feature_tables import feature_table
cog.outl(feature_table("grocery"))
]]] -->
| Feature | Column | Kind | Description | Requires |
| --- | --- | --- | --- | --- |
| `Count` | `count_{period}` | base | Count of rows | `event_timestamp` |
| `CustomerCount` | `customer_count_{period}` | base | Distinct count of Customers | `customer,event_timestamp` |
| `ApproxCustomerCount` | `approx_customer_count_{period}` | base | Approximate distinct count of Customers | `customer,event_timestamp` |
| `ProductCount` | `product_count_{period}` | base | Distinct count of Products | `event_timestamp,product` |
| `ApproxProductCount` | `approx_product_count_{period}` | base | Approximate distinct count of Products | `event_timestamp,product` |
| `Quantity` | `quantity_{period}` | base | Sum of Quantity | `event_timestamp,quantity` |
| `Discount` | `discount_{period}` | base | Sum of Discount | `discount,event_timestamp` |
| `GrossSpend` | `gross_spend_{period}` | base | Sum of GrossSpend | `event_timestamp,gross_spend` |
| `NetSpend` | `net_spend_{period}` | base | Sum of NetSpend | `event_timestamp,net_spend` |
| `MinGrossSpend` | `min_gross_spend_{period}` | base | Minimum GrossSpend value | `event_timestamp,gross_spend` |
| `MaxGrossSpend` | `max_gross_spend_{period}` | base | Maximum GrossSpend value | `event_timestamp,gross_spend` |
| `MinNetSpend` | `min_net_spend_{period}` | base | Minimum of NetSpend value | `event_timestamp,net_spend` |
| `MaxNetSpend` | `max_net_spend_{period}` | base | Maximum of NetSpend value | `event_timestamp,net_spend` |
| `MinGrossPrice` | `min_gross_price_{period}` | base | Minimum of (GrossSpend / Quantity) | `event_timestamp,gross_spend,quantity` |
| `MaxGrossPrice` | `max_gross_price_{period}` | base | Maximum of (GrossSpend / Quantity) | `event_timestamp,gross_spend,quantity` |
| `MinNetPrice` | `min_net_price_{period}` | base | Minimum of (NetSpend / Quantity) | `event_timestamp,net_spend,quantity` |
| `MaxNetPrice` | `max_net_price_{period}` | base | Maximum of (NetSpend / Quantity) | `event_timestamp,net_spend,quantity` |
| `RecencyDays` | `recency_days_{period}` | base | Minimum number of days since occurrence | `event_timestamp` |
| `EarliestPurchaseDate` | `earliest_purchase_date_{period}` | base | Earliest purchase date | `event_timestamp` |
| `MostRecentPurchaseDate` | `most_recent_purchase_date_{period}` | base | Most recent purchase date | `event_timestamp` |
| `BasketCount` | `basket_count_{period}` | base | Distinct count of Baskets | `basket,event_timestamp` |
| `ApproxBasketCount` | `approx_basket_count_{period}` | base | Approximate distinct count of Baskets | `basket,event_timestamp` |
| `StoreCount` | `store_count_{period}` | base | Distinct count of Stores | `event_timestamp,store` |
| `ChannelCount` | `channel_count_{period}` | base | Distinct count of Channels | `channel,event_timestamp` |
| `AvgGrossSpendPerBasket` | `avg_gross_spend_per_basket_{period}` | derived | Average GrossSpend per Basket | `basket,event_timestamp,gross_spend` |
| `AvgQuantityPerBasket` | `avg_quantity_per_basket_{period}` | derived | Average Quantity per Basket | `basket,event_timestamp,quantity` |
| `AvgDiscountPerBasket` | `avg_discount_per_basket_{period}` | derived | Average Discount per Basket | `basket,discount,event_timestamp` |
| `AvgPurchaseCycle` | `avg_purchase_cycle_{period}` | derived | Average purchase cycle | `basket,event_timestamp` |
| `CyclesSinceLastPurchase` | `cycles_since_last_purchase_{period}` | derived | Cycles since last purchase | `basket,event_timestamp` |
| `BasketPeriods` | `basket_{unit}s_{period}` | derived | Number of months in which at least one basket was purchased | `basket,event_timestamp` |
| `AvgBasket` | `average_baskets_per_{unit}_{period}` | derived | Average number of baskets per month | `basket,event_timestamp` |
| `RecencyWeightedBasket90` | `recency_weighted_basket_{unit}s90_{period}` | derived | Exponentially weighted moving average, with smoothing factor of 0.9, of the number of baskets per month | `basket,event_timestamp` |
| `RecencyWeightedBasket95` | `recency_weighted_basket_{unit}s95_{period}` | derived | Exponentially weighted moving average, with smoothing factor of 0.95, of the number of baskets per month | `basket,event_timestamp` |
| `RecencyWeightedBasket99` | `recency_weighted_basket_{unit}s99_{period}` | derived | Exponentially weighted moving average, with smoothing factor of 0.99, of the number of baskets per month | `basket,event_timestamp` |
| `RecencyWeightedApproxBasket90` | `recency_weighted_approx_basket_{unit}s90_{period}` | derived | Exponentially weighted moving average, with smoothing factor of 0.9, of the approximate number of baskets per month | `basket,event_timestamp` |
| `RecencyWeightedApproxBasket95` | `recency_weighted_approx_basket_{unit}s95_{period}` | derived | Exponentially weighted moving average, with smoothing factor of 0.95, of the approximate number of baskets per month | `basket,event_timestamp` |
| `RecencyWeightedApproxBasket99` | `recency_weighted_approx_basket_{unit}s99_{period}` | derived | Exponentially weighted moving average, with smoothing factor of 0.99, of the approximate number of baskets per month | `basket,event_timestamp` |
<!-- [[[end]]] -->

</details>

<details>
<summary><b>Mealkit — 23 features, plus one per cuisine</b></summary>

Every cuisine you pass adds one more: `cuisines=['South African']` adds
`south_african_cuisine_count_13w0`.

<!-- [[[cog
from feature_tables import feature_table
cog.outl(feature_table("mealkit"))
]]] -->
| Feature | Column | Kind | Description | Requires |
| --- | --- | --- | --- | --- |
| `Count` | `count_{period}` | base | Count of rows | `event_timestamp` |
| `CustomerCount` | `customer_count_{period}` | base | Distinct count of Customers | `customer,event_timestamp` |
| `ApproxCustomerCount` | `approx_customer_count_{period}` | base | Approximate distinct count of Customers | `customer,event_timestamp` |
| `ProductCount` | `product_count_{period}` | base | Distinct count of Products | `event_timestamp,product` |
| `ApproxProductCount` | `approx_product_count_{period}` | base | Approximate distinct count of Products | `event_timestamp,product` |
| `Quantity` | `quantity_{period}` | base | Sum of Quantity | `event_timestamp,quantity` |
| `Discount` | `discount_{period}` | base | Sum of Discount | `discount,event_timestamp` |
| `RecencyDays` | `recency_days_{period}` | base | Minimum number of days since occurrence | `event_timestamp` |
| `EarliestPurchaseDate` | `earliest_purchase_date_{period}` | base | Earliest purchase date | `event_timestamp` |
| `MostRecentPurchaseDate` | `most_recent_purchase_date_{period}` | base | Most recent purchase date | `event_timestamp` |
| `OrderCount` | `order_count_{period}` | base | Distinct count of Orders | `event_timestamp,order_id` |
| `ApproxOrderCount` | `approx_order_count_{period}` | base | Approximate distinct count of Orders | `event_timestamp,order_id` |
| `RecipeCount` | `recipe_count_{period}` | base | Distinct count of Recipes | `event_timestamp,recipe` |
| `ApproxRecipeCount` | `approx_recipe_count_{period}` | base | Approximate distinct count of Recipes | `event_timestamp,recipe` |
| `AllergenCount` | `allergen_count_{period}` | base | Distinct count of Allergens | `allergen,event_timestamp` |
| `CuisineCount` | `cuisine_count_{period}` | base | Distinct count of Cuisines | `cuisine,event_timestamp` |
| `Allergens` | `allergens_{period}` | base | Set of Allergens | `allergen,event_timestamp` |
| `Cuisines` | `cuisines_{period}` | base | Set of Cuisines | `cuisine,event_timestamp` |
| `AvgQuantityPerOrder` | `avg_quantity_per_order_{period}` | derived | Average Quantity per Order | `event_timestamp,order_id,quantity` |
| `AvgPurchaseCycle` | `avg_purchase_cycle_{period}` | derived | Average purchase cycle | `event_timestamp,order_id` |
| `CyclesSinceLastOrder` | `cycles_since_last_order_{period}` | derived | Cycles since last order | `event_timestamp,order_id` |
| `OrderPeriods` | `order_{unit}s_{period}` | derived | Number of months in which at least one order was placed | `event_timestamp,order_id` |
| `AvgOrder` | `average_orders_per_{unit}_{period}` | derived | Average number of orders per month | `event_timestamp,order_id` |
<!-- [[[end]]] -->

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
| DuckDB | Tested on every commit. |
| Postgres | Tested nightly against a service container. `ApproxCustomerCount` and friends fall back to exact counts and warn, because Postgres has no approximate distinct count. |
| Snowflake | Adapter macros written from the documentation, not yet run against a real warehouse. Tested nightly once credentials are configured. |
| BigQuery | Adapter macros written from the documentation, not yet run against a real warehouse. Tested nightly once credentials are configured. |
| Databricks | **Not yet supported.** It has a profile target and a nightly job, but no `databricks__` adapter macros, so `collect_set` and the empty-array default still emit DuckDB and ANSI syntax Spark SQL does not accept. `collect_set` and the empty-string-array default are known to need overrides; whether the double-precision cast also does has not been checked against a running cluster. See `CONTRIBUTING.md`. |
| Redshift | Partial: the approximate-distinct-count fallback exists, the rest is untested. |

Adding an adapter means implementing at most five macros; see `CONTRIBUTING.md`.

## 10. Adding your own domain

Grocery and mealkit are not special. Each is a set of feature definitions plus a
three-line entry point, sitting on the same core engine — so a new domain is the
same two things.

1. **Write a registration macro** that adds your definitions to a dict. Base
   features aggregate input columns; derived features reference other features by
   stem and period. `CONTRIBUTING.md` has the dict shape for both. An input column
   your definitions read has to be in `jstark.canonical_columns()`, so `call_id`
   below means adding it there — that list is the one place the input columns are
   named.

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
                           use_absolute_periods=false) %}
     {{ jstark.generate_features(
         input=input, group_by=group_by, generator='telco', as_at=as_at,
         feature_periods=feature_periods, feature_stems=feature_stems,
         first_day_of_week=first_day_of_week,
         use_absolute_periods=use_absolute_periods
     ) }}
   {% endmacro %}
   ```

You get periods, naming, absolute labels, defaults, dependency levelling, the
catalogue and the `schema.yml` generator for free. If your domain needs an input
column that is not in the canonical list, add it to `jstark.canonical_columns()`.

Steps 2 and 3 mean this has to happen inside a fork or a PR rather than in your
own project — the core cannot discover generators it does not know about. A PR is
welcome; two domains is not a design, it is a coincidence.

## 11. Parity with jstark

| jstark | dbt-jstark | Why |
| --- | --- | --- |
| `BasketCount_3m1` | `basket_count_3m1` | Warehouses disagree on unquoted identifier case-folding; snake_case is identical everywhere and needs no quoting. |
| `Timestamp`, `Order` input columns | `event_timestamp`, `order_id` | Input refs are unquoted so case-folding works; `cast(timestamp as date)` is a Postgres syntax error and `order` is reserved. |
| 92 hardcoded `*CuisineCount` classes | `cuisines=[...]` parameter | Same capability, far less generated SQL, and drops inherited typos (`IsrealiCuisineCount`, `FusionCuisineCusiineCount`, `SouthHyphenAfricanCuisineCount`). |
| `try_divide(a, b)` | `cast(a as double precision) / nullif(b, 0)` | Portable, and identical null-on-zero semantics. The cast goes through `jstark.double_type()`, so it is `float64` on BigQuery. |
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

Description and commentary strings are carried verbatim from jstark wherever
possible, so that prose is never a place the two implementations quietly
disagree. Two consequences worth knowing about:

- Several commentary strings contain typos and doubled spaces. Those are
  jstark's, reproduced rather than fixed. If you want them fixed, fix them in
  jstark first.
- Commentary uses the word **dataframe** — "Typically the dataframe supplied to
  this feature will have…". That is Spark vocabulary inherited from jstark. Read
  it as "the model or SQL you passed as `input`". It is left alone deliberately:
  rewording it would mean 11 strings diverging from jstark on user-visible text.

There is exactly one place the prose intentionally diverges from jstark:
`OrderPeriods`' commentary here reads "The number of months in which at least
one **order was placed**…", matching its own `description_subject`. jstark's
`order_periods.py:50` instead says "basket was purchased" — a copy-paste slip
from the grocery `BasketPeriods` feature that contradicts jstark's own
`description_subject` two methods above it, which correctly says "order was
placed". Reproducing a self-contradiction verbatim would buy nothing, so this
one string carries the correction instead. Every other description and
commentary string is verbatim from jstark, typos and doubled spaces included.

One behaviour in the same family is **not** a divergence but is still worth
documenting, because callers will ask. The per-cuisine comparison is
case-insensitive on both sides in both implementations — `lower(cuisine) =
'italian'` here, `f.lower(f.col("Cuisine")) == CUISINE_NAME.lower()` in
`cuisine_count.py`. So `cuisines=['Italian']` matches data stored as `italian`,
and the casing you pass does not have to line up with the casing in your data.

The casing you pass *always* decides the feature's stem and its description
text — `cuisines=['Italian']` and `cuisines=['italian']` match the same rows
but register as `ItalianCuisineCount` versus `italianCuisineCount`, and
describe themselves as "Count of Italian recipes" versus "Count of italian
recipes". Whether it also changes the **column name** depends on whether the
casing introduces a word boundary. Column names go through
`jstark.snake_case()`, which lowercases *and* inserts an underscore wherever a
lowercase letter is followed by an uppercase one. A single-word cuisine has no
such boundary to introduce, so `cuisines=['Italian']` and
`cuisines=['italian']` produce the same column, `italian_cuisine_count_13w0`.
A multi-word cuisine does: `cuisines=['TexMex']` produces
`tex_mex_cuisine_count_13w0`, but `cuisines=['texmex']` — no internal
capital, so no boundary — produces `texmex_cuisine_count_13w0`. Both compare
against `lower(cuisine) = 'texmex'`, so the two columns count the same rows
under different names. This is the part that surprises people.

## License

`dbt-jstark` is distributed under the terms of the [MIT](LICENSE) license.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
