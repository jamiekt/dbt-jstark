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
      safe_divide's own output pass unnoticed here.

      `order_count_3m1`, NOT `count_3m1`. jstark's AverageOrder divides by
      OrderCount (average_order.py), so this averages distinct orders, not
      input rows. The two differ whenever an order spans several recipe lines,
      which the mealkit_orders fixture is built to exercise. -#}
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
  {#- the comparison is case-insensitive on both sides, matching jstark
      (cuisine_count.py:31-33: f.lower(f.col("Cuisine")) ==
      self.CUISINE_NAME.lower()), so cuisines=['Italian'] matches data stored
      as 'italian'. Only the comparison lowercases; the stem and column name
      keep the caller's casing (checked separately above/below). -#}
  {% do jstark_assert_equal(
      results, 'per-cuisine expression is case-insensitive',
      cat['ItalianCuisineCount']['expression'], "lower(cuisine) = 'italian'"
  ) %}
  {#- pins both halves at once: the caller's value is lowercased, and the
      space in a multi-word cuisine survives in the SQL literal even though
      it becomes an underscore in the column name. -#}
  {% do jstark_assert_equal(
      results, 'per-cuisine expression lowercases a multi-word cuisine',
      cat['South AfricanCuisineCount']['expression'],
      "lower(cuisine) = 'south african'"
  ) %}
  {% do jstark_assert_equal(
      results, 'per-cuisine aggregator',
      cat['ThaiCuisineCount']['aggregator'], 'count_if'
  ) %}
  {% do jstark_assert_equal(
      results, 'per-cuisine default', cat['ThaiCuisineCount']['default'], '0'
  ) %}

  {#- an embedded single quote in the cuisine value must not break the
      generated SQL: it is doubled, not stripped, so the literal round-trips
      to the original apostrophe when the warehouse parses it back. -#}
  {% set apostrophe_ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols,
      ["Shepherd's"]
  ) %}
  {% do jstark_assert_equal(
      results, 'per-cuisine expression escapes an embedded apostrophe',
      jstark.catalogue('mealkit', apostrophe_ctx)["Shepherd'sCuisineCount"]['expression'],
      "lower(cuisine) = 'shepherd''s'"
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
  {#- pins that Allergens routes its default through the empty_string_array
      adapter seam rather than hardcoding a literal (e.g. 'null', '[]', or an
      empty string) - the class of bug this mealkit test can and should own.
      What empty_string_array() itself renders on each adapter is pinned
      per-warehouse in test_adapters.sql, and on non-DuckDB warehouses that
      rendering is proven against a live query by the warehouses.yml
      workflow (see test_adapters.sql's own header comment) - not here. That
      keeps this assertion adapter-independent, so it neither needs nor wants
      a target.type guard: both sides render through whichever adapter is
      active. -#}
  {% do jstark_assert_equal(
      results, 'Allergens defaults through the empty_string_array seam',
      cat['Allergens']['default'], jstark.empty_string_array()
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

  {#- deliberately not wrapped in a `{% if target.type == 'duckdb' %}` guard,
      unlike the string-pinning assertions in test_adapters.sql. Both sides of
      this comparison render through whichever adapter is active, so it asserts
      that the entry point delegates rather than asserting any warehouse's SQL
      text, and it is therefore correct on every adapter. -#}
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

  {#- commentary is catalogue metadata the SQL engine never emits, so L1 is
      the only surface that can catch a wrong splice position - a truthiness
      or "contains" check would pass even if the interpolated value landed in
      the wrong place. Each expected string below is a whole hard-coded
      literal, not built from the definition or from the macro under test,
      per the precedent in test_registry.sql (core commentaries) and
      test_grocery.sql (BasketPeriods and RecencyWeighted*). -#}
  {% do jstark_assert_equal(
      results, 'ApproxOrderCount commentary is verbatim for 3m1',
      cat['ApproxOrderCount']['commentary'],
      'The approximate number of orders. Similar to OrderCount_3m1 except '
      ~ 'that it uses an approximation algorithm which will not be as '
      ~ 'accurate as OrderCount_3m1 but will be a lot quicker to compute and '
      ~ 'in many cases will be "close enough".'
  ) %}
  {% do jstark_assert_equal(
      results, 'ApproxRecipeCount commentary is verbatim for 3m1',
      cat['ApproxRecipeCount']['commentary'],
      'The approximate number of recipes. Similar to RecipeCount_3m1 except '
      ~ 'that it uses an approximation algorithm which will not be as '
      ~ 'accurate as RecipeCount_3m1 but will be a lot quicker to compute '
      ~ 'and in many cases will be "close enough".'
  ) %}
  {#- carries the deliberate divergence from jstark's own (copy-pasted, wrong)
      commentary: jstark's order_periods.py says "at least one basket was
      purchased"; this pins what dbt-jstark actually emits, "at least one
      order was placed". -#}
  {% do jstark_assert_equal(
      results, 'OrderPeriods commentary is verbatim for 3m1',
      cat['OrderPeriods']['commentary'],
      'The number of months in which at least one order was placed. The '
      ~ 'value will be in the range 0 to 3 because 3 is the number of months '
      ~ 'between 2021-10-01 and 2021-12-31. When grouped by Customer and '
      ~ 'Product this feature is a useful indicator of the frequency of '
      ~ 'which a Customer purchases a Product.'
  ) %}
  {% do jstark_assert_equal(
      results, 'ItalianCuisineCount commentary is verbatim',
      cat['ItalianCuisineCount']['commentary'],
      'The number of Italian recipes. Typically the dataframe supplied to '
      ~ 'this feature will have many recipes for the same cuisine, this '
      ~ 'feature allows you to determine how many Italian recipes have been '
      ~ 'ordered.'
  ) %}

  {# --- a cuisine that cannot become its own column is rejected --- #}
  {#- `cuisines` is the only parameter whose values become identifiers, so it is
      the only place a caller can name a column. Each case below produced a
      wrong catalogue silently before the validation existed: the empty string
      replaced the CuisineCount feature with a count_if under CuisineCount's own
      column name, '-' collided with it, and two spellings of one cuisine
      produced a single column where the caller asked for two. The base
      catalogue is passed in so the messages can name what a cuisine collides
      with. -#}
  {% set base_cat = jstark.catalogue('mealkit', jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  )) %}
  {% set period = jstark.parse_feature_period('3m1') %}

  {#- the shape that ships: no cuisines at all is valid, and CuisineCount is
      still the distinct count it documents -#}
  {% do jstark_assert_equal(
      results, 'no cuisines is valid',
      jstark.try_validate_cuisines([], base_cat, period),
      {'ok': true, 'error': none}
  ) %}
  {% do jstark_assert_equal(
      results, 'CuisineCount is still a distinct count when cuisines is empty',
      base_cat['CuisineCount']['aggregator'], 'count_distinct'
  ) %}
  {% do jstark_assert_equal(
      results, 'three distinct cuisines are valid',
      jstark.try_validate_cuisines(
          ['Italian', 'Thai', 'South African'], base_cat, period
      ),
      {'ok': true, 'error': none}
  ) %}

  {% set empty_cuisine = jstark.try_validate_cuisines([''], base_cat, period) %}
  {% do jstark_assert_equal(
      results, "cuisines=[''] is rejected", empty_cuisine['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, "cuisines=[''] error", empty_cuisine['error'],
      "jstark: invalid_cuisine: cuisines entry '' is empty or whitespace only; "
      ~ 'every entry must be a non-empty string naming a cuisine'
  ) %}

  {% set blank_cuisine = jstark.try_validate_cuisines(['  '], base_cat, period) %}
  {% do jstark_assert_equal(
      results, "cuisines=['  '] is rejected", blank_cuisine['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, "cuisines=['  '] error", blank_cuisine['error'],
      "jstark: invalid_cuisine: cuisines entry '  ' is empty or whitespace "
      ~ 'only; every entry must be a non-empty string naming a cuisine'
  ) %}

  {% set none_cuisine = jstark.try_validate_cuisines([none], base_cat, period) %}
  {% do jstark_assert_equal(
      results, 'cuisines=[none] is rejected', none_cuisine['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, 'cuisines=[none] error', none_cuisine['error'],
      'jstark: invalid_cuisine: cuisines entry None is not a string; every '
      ~ 'entry must be a non-empty string naming a cuisine'
  ) %}

  {#- '-CuisineCount' is not a stem in the catalogue, but its column name is
      CuisineCount's, which is why the check is on the column and not the stem -#}
  {% set hyphen_cuisine = jstark.try_validate_cuisines(['-'], base_cat, period) %}
  {% do jstark_assert_equal(
      results, "cuisines=['-'] is rejected", hyphen_cuisine['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, "cuisines=['-'] error", hyphen_cuisine['error'],
      "jstark: duplicate_column_name: cuisines entry '-' produces the column "
      ~ 'cuisine_count_3m1, which is already taken by the CuisineCount feature. '
      ~ 'Two columns cannot share one name, so rename or drop one of them'
  ) %}
  {% do jstark_assert_true(
      results, "cuisines=['-'] names a stem the catalogue does not have",
      '-CuisineCount' not in base_cat
  ) %}

  {% set cased_cuisines = jstark.try_validate_cuisines(
      ['Italian', 'italian'], base_cat, period
  ) %}
  {% do jstark_assert_equal(
      results, "cuisines=['Italian','italian'] is rejected",
      cased_cuisines['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, "cuisines=['Italian','italian'] error", cased_cuisines['error'],
      "jstark: duplicate_column_name: cuisines entry 'italian' produces the "
      ~ 'column italian_cuisine_count_3m1, which is already taken by cuisines '
      ~ "entry 'Italian'. Two columns cannot share one name, so rename or drop "
      ~ 'one of them'
  ) %}

  {#- the originally-reported pair, kept as its own case: punctuation, not
      casing, is what makes these two collide -#}
  {% set texmex = jstark.try_validate_cuisines(
      ['TexMex', 'Tex-Mex'], base_cat, period
  ) %}
  {% do jstark_assert_equal(
      results, "cuisines=['TexMex','Tex-Mex'] is rejected", texmex['ok'], false
  ) %}
  {% do jstark_assert_contains(
      results, "cuisines=['TexMex','Tex-Mex'] names the shared column",
      texmex['error'], 'tex_mex_cuisine_count_3m1'
  ) %}

{% endmacro %}
