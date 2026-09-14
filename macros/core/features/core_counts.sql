{#
  Core features: the ones that make sense whatever the domain.

  register_core_features takes the generator name because mealkit uses only a
  subset: spend has no meaning for a business that sells recipe boxes at a
  fixed price, so the Gross/Net spend and price features are grocery-only.

  Registration order is the column order in the generated SQL, so it is fixed
  deliberately and matches the order of the table in the implementation plan.
#}

{% macro core_stems_for_mealkit() %}
  {{ return([
      'Count', 'CustomerCount', 'ApproxCustomerCount', 'ProductCount',
      'ApproxProductCount', 'Quantity', 'Discount', 'RecencyDays',
      'EarliestPurchaseDate', 'MostRecentPurchaseDate'
  ]) }}
{% endmacro %}


{% macro register_core_features(definitions, ctx, generator) %}
  {% set all_core = {} %}
  {% do jstark.register_core_count_features(all_core, ctx) %}
  {% do jstark.register_core_sum_features(all_core, ctx) %}
  {% do jstark.register_core_minmax_features(all_core, ctx) %}
  {% do jstark.register_core_date_features(all_core, ctx) %}

  {% if generator == 'mealkit' %}
    {% set wanted = jstark.core_stems_for_mealkit() %}
  {% else %}
    {% set wanted = all_core.keys() | list %}
  {% endif %}

  {#- iterate all_core, not wanted, so registration order is preserved -#}
  {% for stem, definition in all_core.items() %}
    {% if stem in wanted %}
      {% do definitions.update({stem: definition}) %}
    {% endif %}
  {% endfor %}
{% endmacro %}


{% macro register_core_count_features(definitions, ctx) %}

  {% do definitions.update({'Count': {
      'stem': 'Count',
      'kind': 'base',
      'aggregator': 'count',
      'expression': '1',
      'default': '0',
      'required_columns': ['event_timestamp'],
      'description_subject': 'Count of rows',
      'commentary': 'No commentary supplied'
  }}) %}

  {% do definitions.update({'CustomerCount': {
      'stem': 'CustomerCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['customer'],
      'default': '0',
      'required_columns': ['event_timestamp', 'customer'],
      'description_subject': 'Distinct count of Customers',
      'commentary': 'The number of customers. Typically the dataframe supplied '
          ~ 'to this feature will have many transactions for many baskets each bought'
          ~ ' a different customer, this feature allows you to determine how many '
          ~ 'disinct customerss bought those baskets.'
  }}) %}

  {% do definitions.update({'ApproxCustomerCount': {
      'stem': 'ApproxCustomerCount',
      'kind': 'base',
      'aggregator': 'approx_count_distinct',
      'expression': ctx['cols']['customer'],
      'default': '0',
      'required_columns': ['event_timestamp', 'customer'],
      'description_subject': 'Approximate distinct count of Customers',
      'commentary': 'The approximate number of customers. Similar to '
          ~ ('CustomerCount_' ~ ctx['period']['mnemonic'] ~ ' ')
          ~ 'except that it uses an approximation algorithm which '
          ~ 'will not be as accurate as '
          ~ ('CustomerCount_' ~ ctx['period']['mnemonic'] ~ ' but will be a lot ')
          ~ 'quicker to compute and in many cases will be "close enough".'
  }}) %}

  {% do definitions.update({'ProductCount': {
      'stem': 'ProductCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['product'],
      'default': '0',
      'required_columns': ['event_timestamp', 'product'],
      'description_subject': 'Distinct count of Products',
      'commentary': 'The number of products. Typically the dataframe supplied '
          ~ 'to this feature will have many transactions for many baskets with '
          ~ 'many products bought, this feature allows you to determine how many '
          ~ 'disinct products were bought in those baskets.'
  }}) %}

  {% do definitions.update({'ApproxProductCount': {
      'stem': 'ApproxProductCount',
      'kind': 'base',
      'aggregator': 'approx_count_distinct',
      'expression': ctx['cols']['product'],
      'default': '0',
      'required_columns': ['event_timestamp', 'product'],
      'description_subject': 'Approximate distinct count of Products',
      'commentary': 'The approximate number of products. Similar to '
          ~ ('ProductCount_' ~ ctx['period']['mnemonic'] ~ ' ')
          ~ 'except that it uses an approximation algorithm which '
          ~ 'will not be as accurate as '
          ~ ('ProductCount_' ~ ctx['period']['mnemonic'] ~ ' but will be a lot ')
          ~ 'quicker to compute and in many cases will be "close enough".'
  }}) %}

{% endmacro %}
