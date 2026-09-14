{% macro jstark_test_naming(results) %}

  {# --- snake_case: CamelCase boundaries --- #}
  {% set cases = [
      ['Count', 'count'],
      ['MinNetPrice', 'min_net_price'],
      ['AvgGrossSpendPerBasket', 'avg_gross_spend_per_basket'],
      ['AverageBasketsPerMonth', 'average_baskets_per_month'],
      ['RecencyWeightedApproxBasketMonths95', 'recency_weighted_approx_basket_months95'],
      ['CyclesSinceLastPurchase', 'cycles_since_last_purchase'],
      ['ApproxCustomerCount', 'approx_customer_count'],
      ['EarliestPurchaseDate', 'earliest_purchase_date'],
      ['RecencyDays', 'recency_days'],
      ['BasketMonths', 'basket_months'],
      ['RecencyWeightedBasketWeeks90', 'recency_weighted_basket_weeks90']
  ] %}
  {% for case in cases %}
    {% do jstark_assert_equal(
        results, 'snake_case(' ~ case[0] ~ ')', jstark.snake_case(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- snake_case: separators and acronyms (used for cuisine names) --- #}
  {% set sep_cases = [
      ['Thai', 'thai'],
      ['South African', 'south_african'],
      ['Sub-Saharan', 'sub_saharan'],
      ['Tex Mex', 'tex_mex'],
      ['  Padded  ', 'padded'],
      ['HTTPServer', 'http_server']
  ] %}
  {% for case in sep_cases %}
    {% do jstark_assert_equal(
        results, 'snake_case(' ~ case[0] ~ ')', jstark.snake_case(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- period_unit_name --- #}
  {% set unit_cases = [
      ['d', 'Day'], ['w', 'Week'], ['m', 'Month'], ['q', 'Quarter'], ['y', 'Year']
  ] %}
  {% for case in unit_cases %}
    {% do jstark_assert_equal(
        results, 'period_unit_name(' ~ case[0] ~ ')',
        jstark.period_unit_name(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- feature_base_name: stems with no override pass through snake_case --- #}
  {% do jstark_assert_equal(
      results, 'feature_base_name(GrossSpend, m)',
      jstark.feature_base_name('GrossSpend', 'm'), 'gross_spend'
  ) %}
  {% do jstark_assert_equal(
      results, 'feature_base_name(BasketCount, w)',
      jstark.feature_base_name('BasketCount', 'w'), 'basket_count'
  ) %}

  {# --- feature_base_name: unit-infix overrides --- #}
  {% set override_cases = [
      ['BasketPeriods', 'm', 'basket_months'],
      ['BasketPeriods', 'w', 'basket_weeks'],
      ['BasketPeriods', 'd', 'basket_days'],
      ['BasketPeriods', 'q', 'basket_quarters'],
      ['BasketPeriods', 'y', 'basket_years'],
      ['OrderPeriods', 'm', 'order_months'],
      ['AvgBasket', 'm', 'average_baskets_per_month'],
      ['AvgBasket', 'w', 'average_baskets_per_week'],
      ['AvgOrder', 'm', 'average_orders_per_month'],
      ['RecencyWeightedBasket90', 'm', 'recency_weighted_basket_months90'],
      ['RecencyWeightedBasket95', 'm', 'recency_weighted_basket_months95'],
      ['RecencyWeightedBasket99', 'm', 'recency_weighted_basket_months99'],
      ['RecencyWeightedBasket95', 'w', 'recency_weighted_basket_weeks95'],
      ['RecencyWeightedApproxBasket90', 'm', 'recency_weighted_approx_basket_months90'],
      ['RecencyWeightedApproxBasket95', 'm', 'recency_weighted_approx_basket_months95'],
      ['RecencyWeightedApproxBasket99', 'm', 'recency_weighted_approx_basket_months99']
  ] %}
  {% for case in override_cases %}
    {% do jstark_assert_equal(
        results, 'feature_base_name(' ~ case[0] ~ ', ' ~ case[1] ~ ')',
        jstark.feature_base_name(case[0], case[1]), case[2]
    ) %}
  {% endfor %}

  {# --- column_name appends the mnemonic --- #}
  {% set fp_3m1 = {'uom': 'm', 'start': 3, 'end': 1, 'mnemonic': '3m1'} %}
  {% set fp_52w0 = {'uom': 'w', 'start': 52, 'end': 0, 'mnemonic': '52w0'} %}
  {% do jstark_assert_equal(
      results, 'column_name(GrossSpend, 3m1)',
      jstark.column_name('GrossSpend', fp_3m1), 'gross_spend_3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'column_name(BasketPeriods, 3m1)',
      jstark.column_name('BasketPeriods', fp_3m1), 'basket_months_3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'column_name(RecencyWeightedBasket95, 52w0)',
      jstark.column_name('RecencyWeightedBasket95', fp_52w0),
      'recency_weighted_basket_weeks95_52w0'
  ) %}
  {% do jstark_assert_equal(
      results, 'column_name(AvgBasket, 52w0)',
      jstark.column_name('AvgBasket', fp_52w0), 'average_baskets_per_week_52w0'
  ) %}

{% endmacro %}
