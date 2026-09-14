{% macro jstark_test_engine(results) %}

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
      results, 'input CTE',
      sql, 'with jstark_input as ( select * from transactions )'
  ) %}
  {% do jstark_assert_contains(results, 'base CTE', sql, 'jstark_base as (') %}
  {% do jstark_assert_contains(
      results, 'derived CTE', sql, 'jstark_derived_1 as ( select *,'
  ) %}
  {% do jstark_assert_contains(
      results, 'base aggregate',
      sql,
      'coalesce(sum(case when cast(event_timestamp as date) between '
      ~ "date '2021-10-01' and date '2021-12-31' then gross_spend end), 0.0) "
      ~ 'as test_spend_3m1'
  ) %}
  {% do jstark_assert_contains(
      results, 'derived expression has no coalesce when the default is null',
      sql,
      'cast(test_spend_3m1 as double precision) '
      ~ '/ nullif(test_basket_count_3m1, 0) as test_spend_per_basket_3m1'
  ) %}
  {% do jstark_assert_contains(results, 'group by', sql, 'group by customer') %}
  {% do jstark_assert_contains(
      results, 'final projection',
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
      results, 'sub-period helper is computed',
      cross_sql, 'as test_basket_count_2m2'
  ) %}
  {% do jstark_assert_contains(
      results, 'only the requested feature is projected',
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
      results, 'no group by clause when group_by is empty',
      'group by' in nogroup_sql, false
  ) %}
  {% do jstark_assert_contains(
      results, 'no leading comma when group_by is empty',
      nogroup_sql, 'select coalesce(sum('
  ) %}
  {% do jstark_assert_contains(
      results, 'projection with no group_by',
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
      results, 'relation input',
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
      results, 'internal name is still the mnemonic',
      absolute_sql, 'as test_spend_3m1'
  ) %}
  {% do jstark_assert_contains(
      results, 'projection aliases to the absolute label',
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
      results, 'multiple group_by columns', multi_sql, 'group by customer, store'
  ) %}
  {% do jstark_assert_contains(
      results, 'multiple periods',
      multi_sql,
      'select customer, store, test_spend_3m1, test_spend_0d0 from jstark_base'
  ) %}

  {#- An input whose columns are named differently is handled by renaming them
      in the SQL passed as `input`, which is the only route this package
      provides — see README section 6. The string is inlined as the first CTE,
      so the aggregate and the window below both see the canonical names while
      the caller's table keeps its own. A computed input column works the same
      way, which is why gross_spend is aliased from an expression here. -#}
  {% set renaming_input =
      'select txn_ts as event_timestamp, price * quantity as gross_spend, '
      ~ 'customer from transactions' %}
  {% set renamed_sql = jstark_normalise_sql(jstark.generate_features(
      input=renaming_input,
      group_by=['customer'],
      generator='test',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['TestSpend']
  )) %}
  {% do jstark_assert_contains(
      results, 'the input SQL is inlined verbatim',
      renamed_sql, renaming_input
  ) %}
  {% do jstark_assert_contains(
      results, 'the aggregate reads the canonical column name',
      renamed_sql, 'then gross_spend end)'
  ) %}
  {% do jstark_assert_contains(
      results, 'the window reads the canonical timestamp column',
      renamed_sql, 'cast(event_timestamp as date) between'
  ) %}

{% endmacro %}
