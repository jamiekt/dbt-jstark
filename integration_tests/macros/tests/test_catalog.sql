{% macro jstark_test_catalog(results) %}

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
  {% do jstark_assert_equal(results, 'catalog row count', rows | length, 2) %}
  {% do jstark_assert_equal(
      results, 'catalog feature names',
      rows | map(attribute='feature_name') | sort | list,
      ['avg_gross_spend_per_basket_3m1', 'gross_spend_3m1']
  ) %}

  {% set by_name = {} %}
  {% for row in rows %}
    {% do by_name.update({row['feature_name']: row}) %}
  {% endfor %}

  {# --- a base feature --- #}
  {% set gross = by_name['gross_spend_3m1'] %}
  {% do jstark_assert_equal(results, 'catalog stem', gross['stem'], 'GrossSpend') %}
  {% do jstark_assert_equal(
      results, 'catalog mnemonic', gross['period_mnemonic'], '3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'catalog period unit', gross['period_unit'], 'Month'
  ) %}
  {% do jstark_assert_equal(
      results, 'catalog start date', gross['start_date'], '2021-10-01'
  ) %}
  {% do jstark_assert_equal(
      results, 'catalog end date', gross['end_date'], '2021-12-31'
  ) %}
  {% do jstark_assert_equal(results, 'catalog kind', gross['kind'], 'base') %}
  {% do jstark_assert_equal(
      results, 'catalog exposes the subject on its own',
      gross['description_subject'], 'Sum of GrossSpend'
  ) %}
  {% do jstark_assert_equal(
      results, 'catalog description',
      gross['description'],
      'Sum of GrossSpend between 2021-10-01 and 2021-12-31'
  ) %}
  {% do jstark_assert_equal(
      results, 'catalog required columns for a base feature',
      gross['required_columns'], 'event_timestamp,gross_spend'
  ) %}

  {# --- a derived feature inherits the input columns it reaches --- #}
  {% set avg = by_name['avg_gross_spend_per_basket_3m1'] %}
  {% do jstark_assert_equal(results, 'catalog derived kind', avg['kind'], 'derived') %}
  {% do jstark_assert_equal(
      results, 'catalog required columns for a derived feature',
      avg['required_columns'], 'basket,event_timestamp,gross_spend'
  ) %}

  {# --- a two-deep derived feature reaches all the way to the base --- #}
  {% set deep = jstark.catalog_rows(
      generator='grocery', as_at='2022-01-01', feature_periods=['3m1'],
      feature_stems=['CyclesSinceLastPurchase'], first_day_of_week='Monday',
      use_absolute_periods=false, column_map={}, cuisines=[]
  ) %}
  {% do jstark_assert_equal(
      results, 'catalog required columns two levels down',
      deep[0]['required_columns'], 'basket,event_timestamp'
  ) %}

  {# --- absolute labels flow through to feature_name --- #}
  {% set absolute = jstark.catalog_rows(
      generator='grocery', as_at='2022-01-01', feature_periods=['3m1'],
      feature_stems=['GrossSpend'], first_day_of_week='Monday',
      use_absolute_periods=true, column_map={}, cuisines=[]
  ) %}
  {% do jstark_assert_equal(
      results, 'catalog honours absolute periods',
      absolute[0]['feature_name'], 'gross_spend_2021oct_to_2021dec'
  ) %}
  {% do jstark_assert_equal(
      results, 'catalog reports the mnemonic even when labels are absolute',
      absolute[0]['period_mnemonic'], '3m1'
  ) %}

  {# --- string literals are escaped --- #}
  {% do jstark_assert_equal(
      results, 'sql_string quotes a plain value',
      jstark.sql_string('abc'), "'abc'"
  ) %}
  {% do jstark_assert_equal(
      results, 'sql_string doubles embedded quotes',
      jstark.sql_string("Shepherd's Pie"), "'Shepherd''s Pie'"
  ) %}

  {# --- the emitted SQL is one row per feature and casts the dates --- #}
  {% set sql = jstark.feature_catalog(
      generator='mealkit', as_at='2022-01-01', feature_periods=['3m1', '1y1'],
      cuisines=['Italian']
  ) %}
  {#- two periods times 24 features is 48 rows, so 47 union alls -#}
  {% do jstark_assert_equal(
      results, 'catalog SQL has one select per feature',
      sql.split('union all') | length, (10 + 13 + 1) * 2
  ) %}
  {% do jstark_assert_contains(
      results, 'catalog SQL casts start_date',
      sql, "cast('2021-10-01' as date) as start_date"
  ) %}
  {% do jstark_assert_contains(
      results, 'catalog SQL names the columns', sql, 'as feature_name'
  ) %}

  {# --- the catalogue covers exactly the columns the engine emits --- #}
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
        results, 'engine emits catalogued column ' ~ name,
        name in engine_sql
    ) %}
  {% endfor %}
  {% do jstark_assert_equal(
      results, 'catalog covers every mealkit feature',
      catalog_names | length, 10 + 13 + 1
  ) %}

{% endmacro %}
