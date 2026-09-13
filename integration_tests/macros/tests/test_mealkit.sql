{% macro jstark_test_mealkit(results) %}

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
      results, 'mealkit catalogue size', cat | length, 10 + 13 + 3
  ) %}

  {# --- and only those 10 core features --- #}
  {% set core_cat = jstark.catalogue('core', ctx) %}
  {% for stem in jstark.core_stems_for_mealkit() %}
    {% do jstark_assert_true(
        results, 'mealkit includes core ' ~ stem, stem in cat
    ) %}
  {% endfor %}
  {% for stem in core_cat %}
    {% if stem not in jstark.core_stems_for_mealkit() %}
      {% do jstark_assert_true(
          results, 'mealkit excludes core ' ~ stem, stem not in cat
      ) %}
    {% endif %}
  {% endfor %}
  {% do jstark_assert_true(
      results, 'mealkit has no spend features', 'GrossSpend' not in cat
  ) %}
  {% do jstark_assert_true(
      results, 'mealkit has no price features', 'MinNetPrice' not in cat
  ) %}

  {% set mealkit_only = [
      'OrderCount', 'ApproxOrderCount', 'RecipeCount', 'ApproxRecipeCount',
      'AllergenCount', 'Allergens', 'CuisineCount', 'Cuisines',
      'AvgQuantityPerOrder', 'AvgPurchaseCycle', 'CyclesSinceLastOrder',
      'OrderPeriods', 'AvgOrder'
  ] %}
  {% for stem in mealkit_only %}
    {% do jstark_assert_true(
        results, 'mealkit catalogue contains ' ~ stem, stem in cat
    ) %}
  {% endfor %}

  {# --- AvgPurchaseCycle is per-order here and per-basket in grocery --- #}
  {% do jstark_assert_contains(
      results, 'mealkit AvgPurchaseCycle divides by orders',
      cat['AvgPurchaseCycle']['expression'], 'order_count_3m1'
  ) %}
  {% set grocery_ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_contains(
      results, 'grocery AvgPurchaseCycle divides by baskets',
      jstark.catalogue('grocery', grocery_ctx)['AvgPurchaseCycle']['expression'],
      'basket_count_3m1'
  ) %}

  {# --- unit-dependent names --- #}
  {% do jstark_assert_equal(
      results, 'OrderPeriods name for a monthly period',
      jstark.column_name('OrderPeriods', ctx['period']), 'order_months_3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'AvgOrder name for a monthly period',
      jstark.column_name('AvgOrder', ctx['period']),
      'average_orders_per_month_3m1'
  ) %}

  {# --- AvgOrder divides distinct orders by the number of whole periods --- #}
  {#- the expected value is a literal, not jstark.safe_divide(...): building it
      with the same macro the implementation calls would let a change in
      safe_divide's own output pass unnoticed here. `order_count_3m1`, NOT
      `count_3m1` --- see CONTROLLER NOTE 4 in Step 1. -#}
  {% do jstark_assert_equal(
      results, 'AvgOrder divides distinct orders, not rows',
      cat['AvgOrder']['expression'],
      'cast(order_count_3m1 as double precision) / nullif(3, 0)'
  ) %}

  {# --- one feature per cuisine, named without any special-casing --- #}
  {% do jstark_assert_equal(
      results, 'per-cuisine column name',
      jstark.column_name('South AfricanCuisineCount', ctx['period']),
      'south_african_cuisine_count_3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'per-cuisine expression',
      cat['ItalianCuisineCount']['expression'], "cuisine = 'Italian'"
  ) %}
  {% do jstark_assert_equal(
      results, 'per-cuisine aggregator',
      cat['ThaiCuisineCount']['aggregator'], 'count_if'
  ) %}
  {% do jstark_assert_equal(
      results, 'per-cuisine default', cat['ThaiCuisineCount']['default'], '0'
  ) %}

  {# --- no cuisines parameter means no per-cuisine features --- #}
  {% set no_cuisine_cat = jstark.catalogue(
      'mealkit',
      jstark.feature_context(
          jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
      )
  ) %}
  {% do jstark_assert_equal(
      results, 'mealkit catalogue size with no cuisines',
      no_cuisine_cat | length, 10 + 13
  ) %}

  {# --- the collect_set features default to an empty array, not null --- #}
  {% do jstark_assert_equal(
      results, 'Allergens aggregator', cat['Allergens']['aggregator'], 'collect_set'
  ) %}
  {% do jstark_assert_true(
      results, 'Allergens does not default to null',
      cat['Allergens']['default'] != 'null'
  ) %}

  {# --- mealkit is two derived levels deep, as grocery is --- #}
  {% set plan = jstark.build_plan(
      'mealkit', ['CyclesSinceLastOrder'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, cuisines
  ) %}
  {% do jstark_assert_equal(
      results, 'CyclesSinceLastOrder is two levels deep', plan['levels'] | length, 3
  ) %}

  {% set full_plan = jstark.build_plan(
      'mealkit', [], [jstark.parse_feature_period('3m1')], as_at, 'Monday',
      false, cols, cuisines
  ) %}
  {% do jstark_assert_equal(
      results, 'mealkit declares all its dependencies',
      jstark.undeclared_dependencies(full_plan), []
  ) %}

  {#- CONTROLLER CORRECTION: dropped the `{% if target.type == 'duckdb' %}`
      guard the brief wrapped this in. Both sides render through whichever
      adapter is active, so the comparison is adapter-independent, and the guard
      would make the suite's assertion count differ per warehouse --- which
      defeats the count as a coverage check on the BigQuery job Task 14 adds. -#}
  {% do jstark_assert_equal(
      results, 'mealkit_features delegates to generate_features',
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

{% endmacro %}
