{% macro jstark_test_adapters(results) %}

  {# These assertions pin the SQL text, so they are target-specific.
     Other adapters are covered by the warehouses.yml workflow actually
     running the queries rather than by string comparison. #}
  {% if target.type != 'duckdb' %}
    {% do log('Skipping adapter string assertions on ' ~ target.type, info=true) %}
    {{ return('') }}
  {% endif %}

  {% do jstark_assert_equal(
      results, 'to_date',
      jstark.to_date('event_timestamp'), 'cast(event_timestamp as date)'
  ) %}

  {% do jstark_assert_equal(
      results, 'approx_count_distinct',
      jstark.approx_count_distinct('customer'), 'approx_count_distinct(customer)'
  ) %}

  {% set window = "cast(event_timestamp as date) between date '2021-10-01' and date '2021-12-31'" %}

  {% do jstark_assert_equal(
      results, 'collect_set',
      jstark.collect_set('allergen', window),
      'list_sort(array_agg(distinct allergen) filter (where ('
      ~ window ~ ') and allergen is not null))'
  ) %}

  {#- pinned as a literal 'double precision', not dbt.type_float() ~ ..., so
      this cannot pass vacuously if the implementation regresses to a
      single-precision cast: see jstark_double_type.sql for why that
      distinction matters (it is invisible until a safe_divide result feeds
      another safe_divide, as grocery's AvgPurchaseCycle chain does). -#}
  {% do jstark_assert_equal(
      results, 'safe_divide',
      jstark.safe_divide('gross_spend_3m1', 'basket_count_3m1'),
      'cast(gross_spend_3m1 as double precision) / nullif(basket_count_3m1, 0)'
  ) %}

  {#- double_type() itself has no standalone assertion elsewhere; it is
      otherwise only exercised indirectly through safe_divide. Both variants
      are plain string-returning macros, so neither needs a live warehouse:
      double_type() dispatches to the active adapter (duckdb here), and the
      bigquery__ variant is called directly regardless of target. -#}
  {% do jstark_assert_equal(
      results, 'double_type on duckdb', jstark.double_type(), 'double precision'
  ) %}
  {% do jstark_assert_equal(
      results, 'double_type on bigquery',
      jstark.bigquery__jstark_double_type(), 'float64'
  ) %}

  {# --- aggregate_sql covers every aggregator --- #}
  {% do jstark_assert_equal(
      results, 'aggregate_sql(sum)',
      jstark.aggregate_sql('sum', 'gross_spend', window),
      'sum(case when ' ~ window ~ ' then gross_spend end)'
  ) %}
  {% do jstark_assert_equal(
      results, 'aggregate_sql(count)',
      jstark.aggregate_sql('count', '1', window),
      'count(case when ' ~ window ~ ' then 1 end)'
  ) %}
  {% do jstark_assert_equal(
      results, 'aggregate_sql(count_if)',
      jstark.aggregate_sql('count_if', 'count_1m1 > 0', window),
      'count(case when (' ~ window ~ ') and (count_1m1 > 0) then 1 end)'
  ) %}
  {% do jstark_assert_equal(
      results, 'aggregate_sql(count_distinct)',
      jstark.aggregate_sql('count_distinct', 'basket', window),
      'count(distinct case when ' ~ window ~ ' then basket end)'
  ) %}
  {% do jstark_assert_equal(
      results, 'aggregate_sql(approx_count_distinct)',
      jstark.aggregate_sql('approx_count_distinct', 'basket', window),
      'approx_count_distinct(case when ' ~ window ~ ' then basket end)'
  ) %}
  {% do jstark_assert_equal(
      results, 'aggregate_sql(max)',
      jstark.aggregate_sql('max', 'net_spend', window),
      'max(case when ' ~ window ~ ' then net_spend end)'
  ) %}
  {% do jstark_assert_equal(
      results, 'aggregate_sql(min)',
      jstark.aggregate_sql('min', 'net_spend', window),
      'min(case when ' ~ window ~ ' then net_spend end)'
  ) %}
  {% do jstark_assert_equal(
      results, 'aggregate_sql(collect_set)',
      jstark.aggregate_sql('collect_set', 'allergen', window),
      jstark.collect_set('allergen', window)
  ) %}

  {# --- an unknown aggregator is rejected rather than silently emitted --- #}
  {% set bad = jstark.try_aggregate_sql('median', 'x', window) %}
  {% do jstark_assert_equal(
      results, "try_aggregate_sql('median').ok", bad['ok'], false
  ) %}

  {% do jstark_assert_equal(
      results, "try_aggregate_sql('median').error",
      bad['error'],
      jstark.error_message(
          jstark.error_codes()['unknown_aggregator'],
          "'median' is not a known aggregator; expected one of "
          ~ (jstark.aggregators() | join(', '))
      )
  ) %}

  {# --- aggregators() is the single source of truth --- #}
  {% do jstark_assert_equal(
      results, 'aggregators()',
      jstark.aggregators(),
      ['sum', 'count', 'count_if', 'count_distinct', 'approx_count_distinct',
       'max', 'min', 'collect_set']
  ) %}

{% endmacro %}
