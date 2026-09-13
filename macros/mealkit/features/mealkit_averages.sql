{#
  Per-order averages, the purchase cycle, and cycles since the last order.

  AvgPurchaseCycle has the same stem as the grocery feature but divides by
  orders rather than baskets. Because the catalogue is built per generator,
  the two definitions never meet.
#}

{% macro register_mealkit_average_features(definitions, ctx) %}

  {% set period = ctx['period'] %}
  {% set order_count = jstark.column_name('OrderCount', period) %}

  {% do definitions.update({'AvgQuantityPerOrder': {
      'stem': 'AvgQuantityPerOrder',
      'kind': 'derived',
      'depends_on': [['Quantity', period], ['OrderCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('Quantity', period), order_count
      ),
      'default': 'null',
      'description_subject': 'Average Quantity per Order',
      'commentary': 'Total Quantity divided by the number of orders. '
          ~ 'Very useful to know how large, on average, each order is.'
  }}) %}

  {% do definitions.update({'AvgPurchaseCycle': {
      'stem': 'AvgPurchaseCycle',
      'kind': 'derived',
      'depends_on': [
          ['EarliestPurchaseDate', period],
          ['MostRecentPurchaseDate', period],
          ['OrderCount', period]
      ],
      'expression': jstark.safe_divide(
          dbt.datediff(
              jstark.column_name('EarliestPurchaseDate', period),
              jstark.column_name('MostRecentPurchaseDate', period),
              'day'
          ),
          order_count
      ),
      'default': 'null',
      'description_subject': 'Average purchase cycle',
      'commentary': 'How often (measured in days) is a purchase made. This '
          ~ 'is very useful to determine how often a customer buys '
          ~ 'something'
  }}) %}

  {% do definitions.update({'CyclesSinceLastOrder': {
      'stem': 'CyclesSinceLastOrder',
      'kind': 'derived',
      'depends_on': [['RecencyDays', period], ['AvgPurchaseCycle', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('RecencyDays', period),
          jstark.column_name('AvgPurchaseCycle', period)
      ),
      'default': 'null',
      'description_subject': 'Cycles since last order',
      'commentary': 'Days since last order divided by average purchase cycle. '
          ~ 'This may be a predictor of when a customer is '
          ~ 'likely to next order something.'
  }}) %}

{% endmacro %}
