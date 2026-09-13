{% macro jstark_test_grocery(results) %}

  {% set d = modules.datetime.date %}
  {% set as_at = d(2022, 1, 1) %}
  {% set cols = jstark.resolve_columns({}) %}
  {% set ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  ) %}
  {% set cat = jstark.catalogue('grocery', ctx) %}

  {# --- grocery is the 20 core features plus 17 of its own --- #}
  {% do jstark_assert_equal(results, 'grocery catalogue size', cat | length, 37) %}
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
        results, 'grocery catalogue contains ' ~ stem, stem in cat
    ) %}
  {% endfor %}
  {% for stem in jstark.catalogue('core', ctx) %}
    {% do jstark_assert_true(
        results, 'grocery catalogue contains core ' ~ stem, stem in cat
    ) %}
  {% endfor %}

  {# --- every derived feature defaults to null, as in jstark --- #}
  {% for stem, definition in cat.items() %}
    {% if definition['kind'] == 'derived' %}
      {% do jstark_assert_equal(
          results, stem ~ ' derived default', definition['default'], 'null'
      ) %}
      {% do jstark_assert_true(
          results, stem ~ ' declares dependencies', definition['depends_on'] | length > 0
      ) %}
    {% endif %}
  {% endfor %}

  {# --- the names that vary with the period unit --- #}
  {% do jstark_assert_equal(
      results, 'BasketPeriods name for a monthly period',
      jstark.column_name('BasketPeriods', ctx['period']), 'basket_months_3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'AvgBasket name for a monthly period',
      jstark.column_name('AvgBasket', ctx['period']),
      'average_baskets_per_month_3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'RecencyWeightedBasket95 name for a monthly period',
      jstark.column_name('RecencyWeightedBasket95', ctx['period']),
      'recency_weighted_basket_months95_3m1'
  ) %}

  {# --- descriptions follow the period unit --- #}
  {% do jstark_assert_contains(
      results, 'BasketPeriods description names the unit',
      cat['BasketPeriods']['description_subject'], 'months'
  ) %}
  {% set weekly_ctx = jstark.feature_context(
      jstark.parse_feature_period('52w0'), as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_contains(
      results, 'BasketPeriods description follows a weekly period',
      jstark.catalogue('grocery', weekly_ctx)['BasketPeriods']['description_subject'],
      'weeks'
  ) %}

  {# --- the exponential weights are Jinja literals, not SQL power() calls --- #}
  {% do jstark_assert_contains(
      results, 'recency weight for the most recent period',
      cat['RecencyWeightedBasket95']['expression'],
      'basket_count_1m1 * ' ~ (0.95 ** 1)
  ) %}
  {% do jstark_assert_contains(
      results, 'recency weight for the oldest period',
      cat['RecencyWeightedBasket95']['expression'],
      'basket_count_3m3 * ' ~ (0.95 ** 3)
  ) %}
  {% do jstark_assert_equal(
      results, 'no SQL power() is emitted',
      'power(' in cat['RecencyWeightedBasket95']['expression'], false
  ) %}
  {% do jstark_assert_contains(
      results, 'the approximate variant uses the approximate count',
      cat['RecencyWeightedApproxBasket95']['expression'], 'approx_basket_count_1m1'
  ) %}

  {# --- AvgBasket divides distinct baskets by the number of whole periods --- #}
  {#- the expected value is a literal, not jstark.safe_divide(...): building it
      with the same macro the implementation calls would let a change in
      safe_divide's own output pass unnoticed here -#}
  {% do jstark_assert_equal(
      results, 'AvgBasket divides distinct baskets, not rows',
      cat['AvgBasket']['expression'],
      'cast(basket_count_3m1 as double precision) / nullif(3, 0)'
  ) %}

  {# --- grocery is two derived levels deep --- #}
  {% set plan = jstark.build_plan(
      'grocery', ['CyclesSinceLastPurchase'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'CyclesSinceLastPurchase is two levels deep',
      plan['levels'] | length, 3
  ) %}
  {% do jstark_assert_equal(
      results, 'AvgPurchaseCycle sits between them',
      plan['levels'][1] | map(attribute='key') | list, ['avg_purchase_cycle_3m1']
  ) %}

  {# --- every derived expression declares what it references --- #}
  {% set full_plan = jstark.build_plan(
      'grocery', [], [jstark.parse_feature_period('3m1')], as_at, 'Monday',
      false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'grocery declares all its dependencies',
      jstark.undeclared_dependencies(full_plan), []
  ) %}

  {#- deliberately not wrapped in a `{% if target.type == 'duckdb' %}` guard,
      unlike the string-pinning assertions in test_adapters.sql. Both sides of
      this comparison render through whichever adapter is active, so it asserts
      that the entry point delegates rather than asserting any warehouse's SQL
      text, and it is therefore correct on every adapter. -#}
  {% do jstark_assert_equal(
      results, 'grocery_features delegates to generate_features',
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

  {# --- commentary interpolates the period, so pin one rendering exactly --- #}
  {% do jstark_assert_equal(
      results, 'BasketPeriods commentary is jstark-verbatim for 3m1',
      cat['BasketPeriods']['commentary'],
      'The number of months in which at least one basket was purchased. The '
      ~ 'value will be in the range 0 to 3 because 3 is the number of months '
      ~ 'between 2021-10-01 and 2021-12-31. When grouped by Customer and '
      ~ 'Product this feature is a useful indicator of the frequency of which '
      ~ 'a Customer purchases a Product.'
  ) %}

  {#- Only two distinct commentary templates back the 12 recency-weighted
      stems (RecencyWeightedBasket* and RecencyWeightedApproxBasket*, each
      shared across the three smoothing factors). Pin both, at 95, as whole
      hard-coded literals — not assembled from the smoothing factor, the
      unit, or the definition — per recency_weighted_basket.py:66-83 (approx)
      and :133-161 (non-approx). Both contain a genuine jstark double space
      ("because it " + " does/requires ...") that must be reproduced, not
      tidied. -#}
  {% do jstark_assert_equal(
      results, 'RecencyWeightedApproxBasket95 commentary is jstark-verbatim for 3m1',
      cat['RecencyWeightedApproxBasket95']['commentary'],
      'Exponential smoothing (https://en.wikipedia.org/wiki/Exponential_smoothing)'
      ~ ' is an alternative to a simple moving average which gives greater'
      ~ ' weighting to more recent observations, thus is an exponentially'
      ~ ' weighted moving average. It uses a smoothing factor between 0 & 1'
      ~ ' which for this feature is 0.95. Here the approximate number of'
      ~ ' baskets per month is smoothed. This feature is considered to be a'
      ~ ' highly effective predictor of future purchases, if a customer has'
      ~ " bought a product recently then there's a relatively high probability"
      ~ ' they will buy it again. This is less accurate than'
      ~ ' RecencyWeightedBasketMonths95_3m1 though is less computationally'
      ~ ' expensive to calculate because it  does not calculate a distinct'
      ~ ' count for each month.'
  ) %}
  {% do jstark_assert_equal(
      results, 'RecencyWeightedBasket95 commentary is jstark-verbatim for 3m1',
      cat['RecencyWeightedBasket95']['commentary'],
      'Exponential smoothing (https://en.wikipedia.org/wiki/Exponential_smoothing)'
      ~ ' is an alternative to a simple moving average which gives greater'
      ~ ' weighting to more recent observations, thus is an exponentially'
      ~ ' weighted moving average. It uses a smoothing factor between 0 & 1'
      ~ ' which for this feature is 0.95. Here the number of baskets per'
      ~ ' month is smoothed. This feature is considered to be a highly'
      ~ ' effective predictor of future purchases, if a customer has bought a'
      ~ " product recently then there's a relatively high probability they"
      ~ ' will buy it again. This is computationally expensive to calculate'
      ~ ' because it  requires a distinct count of baskets for each month.'
      ~ ' Every distinct count operation is expensive so the less that are'
      ~ ' performed, the better (YMMV based on a number of factors, mainly'
      ~ ' the volume of data being processed). For this reason you should'
      ~ ' consider choosing a small number of months for the feature period.'
      ~ ' This feature (RecencyWeightedBasketMonths95_3m1) is for 3 months.'
      ~ ' You might consider using RecencyWeightedApproxBasketMonths95_3m1'
      ~ ' instead which is less accurate but computationally cheaper.'
  ) %}

{% endmacro %}
