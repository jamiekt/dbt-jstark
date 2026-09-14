{#
  Per-basket averages, the purchase cycle, and how many cycles have elapsed
  since the last purchase.

  CyclesSinceLastPurchase depends on AvgPurchaseCycle, which is itself derived.
  That two-deep chain is why the engine levels dependencies into separate CTEs
  rather than computing every derived feature in one pass.
#}

{% macro register_grocery_average_features(definitions, ctx) %}

  {% set period = ctx['period'] %}
  {% set basket_count = jstark.column_name('BasketCount', period) %}

  {% do definitions.update({'AvgGrossSpendPerBasket': {
      'stem': 'AvgGrossSpendPerBasket',
      'kind': 'derived',
      'depends_on': [['GrossSpend', period], ['BasketCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('GrossSpend', period), basket_count
      ),
      'default': 'null',
      'description_subject': 'Average GrossSpend per Basket',
      'commentary': 'Total GrossSpend divided by the number of baskets'
  }}) %}

  {% do definitions.update({'AvgQuantityPerBasket': {
      'stem': 'AvgQuantityPerBasket',
      'kind': 'derived',
      'depends_on': [['Quantity', period], ['BasketCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('Quantity', period), basket_count
      ),
      'default': 'null',
      'description_subject': 'Average Quantity per Basket',
      'commentary': 'Total Quantity divided by the number of baskets. '
          ~ 'Very useful to know how large, on average, each basket is.'
  }}) %}

  {% do definitions.update({'AvgDiscountPerBasket': {
      'stem': 'AvgDiscountPerBasket',
      'kind': 'derived',
      'depends_on': [['Discount', period], ['BasketCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('Discount', period), basket_count
      ),
      'default': 'null',
      'description_subject': 'Average Discount per Basket',
      'commentary': 'Total Discount divided by the number of baskets.'
  }}) %}

  {% do definitions.update({'AvgPurchaseCycle': {
      'stem': 'AvgPurchaseCycle',
      'kind': 'derived',
      'depends_on': [
          ['EarliestPurchaseDate', period],
          ['MostRecentPurchaseDate', period],
          ['BasketCount', period]
      ],
      'expression': jstark.safe_divide(
          dbt.datediff(
              jstark.column_name('EarliestPurchaseDate', period),
              jstark.column_name('MostRecentPurchaseDate', period),
              'day'
          ),
          basket_count
      ),
      'default': 'null',
      'description_subject': 'Average purchase cycle',
      'commentary': 'How often (measured in days) is a purchase made. This '
          ~ 'is very useful to determine how often a customer buys '
          ~ 'a particular product'
  }}) %}

  {% do definitions.update({'CyclesSinceLastPurchase': {
      'stem': 'CyclesSinceLastPurchase',
      'kind': 'derived',
      'depends_on': [['RecencyDays', period], ['AvgPurchaseCycle', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('RecencyDays', period),
          jstark.column_name('AvgPurchaseCycle', period)
      ),
      'default': 'null',
      'description_subject': 'Cycles since last purchase',
      'commentary': 'Days since last purchase divided by average purchase cycle. '
          ~ 'This may be a predictor of when a customer is '
          ~ 'likely to next buy a particular product.'
  }}) %}

{% endmacro %}
