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

  {#- a public_column_name regression that collapsed every feature_name to ''
      would still pass the two checks above (the loop's `in` check and the
      length count), since '' in engine_sql is true and the length is
      unaffected by what the names actually are. These two close that hole:
      no name is ever empty, and at least a few real mealkit names are
      pinned by literal value rather than by membership in a list the
      implementation just built. -#}
  {% do jstark_assert_true(
      results, 'no catalogued mealkit feature_name is empty',
      '' not in catalog_names
  ) %}
  {% do jstark_assert_true(
      results, 'catalog includes order_count_3m1', 'order_count_3m1' in catalog_names
  ) %}
  {% do jstark_assert_true(
      results, 'catalog includes recipe_count_3m1', 'recipe_count_3m1' in catalog_names
  ) %}
  {% do jstark_assert_true(
      results, 'catalog includes italian_cuisine_count_3m1',
      'italian_cuisine_count_3m1' in catalog_names
  ) %}

  {# --- jstark.schema_yml_text: escaping --- #}
  {#- a cuisine carrying all four characters the YAML builder must escape or
      preserve: an apostrophe (no escaping needed in a double-quoted YAML
      scalar), a double quote (escaped as \"), a colon (harmless once quoted)
      and a backslash (escaped as \\, and it must happen before the quote
      escaping step or a real backslash immediately before a real quote would
      end up mis-paired). -#}
  {% set hostile_cuisine = "D'Angelo's \"Grill\": N\\A" %}
  {% set hostile_stem = hostile_cuisine ~ 'CuisineCount' %}
  {% set schema_text = jstark.schema_yml_text(
      model_name='mealkit_customer_features',
      generator='mealkit',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=[hostile_stem],
      cuisines=[hostile_cuisine]
  ) %}
  {% do jstark_assert_contains(
      results, 'schema.yml escapes apostrophe, quote, colon and backslash together',
      schema_text,
      "        description: \"Count of D'Angelo's \\\"Grill\\\": N\\\\A recipes between 2021-10-01 and 2021-12-31\""
  ) %}

  {# --- jstark.schema_yml_text: structure --- #}
  {% set structure_text = jstark.schema_yml_text(
      model_name='structure_check_model',
      generator='grocery',
      as_at='2022-01-01',
      feature_periods=['3m1'],
      feature_stems=['GrossSpend'],
      group_by=['customer']
  ) %}
  {% do jstark_assert_equal(
      results, 'schema.yml starts with the version line',
      structure_text.split('\n')[0], 'version: 2'
  ) %}
  {% do jstark_assert_contains(
      results, 'schema.yml has a models section', structure_text, '\nmodels:\n'
  ) %}
  {% do jstark_assert_contains(
      results, 'schema.yml names the model', structure_text,
      '  - name: structure_check_model'
  ) %}
  {% do jstark_assert_contains(
      results, 'schema.yml opens a columns block', structure_text, '    columns:'
  ) %}
  {% do jstark_assert_contains(
      results, 'schema.yml labels a group_by column',
      structure_text, '      - name: customer\n        description: Grouping column.'
  ) %}
  {#- the ordering itself, not just the presence of both blocks: a caller
      pastes this straight into a model's schema.yml, where column docs read
      top to bottom in the order the columns are selected, group_by first. -#}
  {% do jstark_assert_true(
      results, 'schema.yml lists group_by columns before feature columns',
      structure_text.index('      - name: customer')
      < structure_text.index('      - name: gross_spend_3m1')
  ) %}

  {# --- the feature reference is one row per stem, not per stem-and-period --- #}
  {% set reference = jstark.feature_reference_rows('grocery', []) %}
  {% do jstark_assert_equal(
      results, 'grocery reference row count', reference | length, 37
  ) %}
  {% do jstark_assert_equal(
      results, 'reference rows are unique per stem',
      reference | map(attribute='stem') | unique | list | length, 37
  ) %}
  {% set first = reference[0] %}
  {% for key in ['stem', 'column_name_pattern', 'kind', 'description_subject',
                 'commentary', 'required_columns'] %}
    {% do jstark_assert_true(
        results, 'reference row has ' ~ key, key in first
    ) %}
  {% endfor %}
  {#- indexed with [] rather than the attr filter: attr does not fall back to
      item lookup, so on a dict it returns undefined -#}
  {% set order_periods_row = jstark.feature_reference_rows('mealkit', [])
      | selectattr('stem', 'equalto', 'OrderPeriods') | first %}
  {% do jstark_assert_equal(
      results, 'reference column name pattern keeps the period placeholder',
      order_periods_row['column_name_pattern'], 'order_{unit}s_{period}'
  ) %}
  {% do jstark_assert_equal(
      results, 'mealkit reference row count',
      jstark.feature_reference_rows('mealkit', []) | length, 23
  ) %}
  {#- the paired negative: a feature whose name does not depend on the unit
      must come out with no {unit} in it at all, which is what proves the
      _month substitution fires only where it should -#}
  {% set net_spend_row = jstark.feature_reference_rows('grocery', [])
      | selectattr('stem', 'equalto', 'NetSpend') | first %}
  {% do jstark_assert_equal(
      results, 'reference leaves a unit-independent name alone',
      net_spend_row['column_name_pattern'], 'net_spend_{period}'
  ) %}

{% endmacro %}
