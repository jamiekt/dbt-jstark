{#
  Grocery-specific features.

  register_grocery_features runs after register_core_features, so the core
  aggregates it depends on (GrossSpend, Quantity, Discount, RecencyDays,
  EarliestPurchaseDate, MostRecentPurchaseDate) are already registered.
#}

{% macro register_grocery_features(definitions, ctx) %}
  {% do jstark.register_grocery_base_features(definitions, ctx) %}
  {% do jstark.register_grocery_average_features(definitions, ctx) %}
  {% do jstark.register_grocery_periodic_features(definitions, ctx) %}
{% endmacro %}


{% macro register_grocery_base_features(definitions, ctx) %}

  {% do definitions.update({'BasketCount': {
      'stem': 'BasketCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['basket'],
      'default': '0',
      'required_columns': ['event_timestamp', 'basket'],
      'description_subject': 'Distinct count of Baskets',
      'commentary': 'The number of baskets. Typically the dataframe supplied '
          ~ 'to this feature will have many transactions for the same basket, '
          ~ 'this feature allows you to determine how many shopping baskets '
          ~ 'existed in that collection of transactions.'
  }}) %}

  {% do definitions.update({'ApproxBasketCount': {
      'stem': 'ApproxBasketCount',
      'kind': 'base',
      'aggregator': 'approx_count_distinct',
      'expression': ctx['cols']['basket'],
      'default': '0',
      'required_columns': ['event_timestamp', 'basket'],
      'description_subject': 'Approximate distinct count of Baskets',
      'commentary': 'The approximate number of baskets. Similar to '
          ~ ('BasketCount_' ~ ctx['period']['mnemonic'] ~ ' ')
          ~ 'except that it uses an approximation algorithm which '
          ~ 'will not be as accurate as '
          ~ ('BasketCount_' ~ ctx['period']['mnemonic'] ~ ' but will be a lot ')
          ~ 'quicker to compute and in many cases will be "close enough".'
  }}) %}

  {% do definitions.update({'StoreCount': {
      'stem': 'StoreCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['store'],
      'default': '0',
      'required_columns': ['event_timestamp', 'store'],
      'description_subject': 'Distinct count of Stores',
      'commentary': 'The number of stores. Typically the dataframe supplied '
          ~ 'to this feature will have many transactions for many baskets for '
          ~ 'many stores, this feature allows you to determine how many '
          ~ 'stores those baskets were purchased in.'
  }}) %}

  {% do definitions.update({'ChannelCount': {
      'stem': 'ChannelCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['channel'],
      'default': '0',
      'required_columns': ['event_timestamp', 'channel'],
      'description_subject': 'Distinct count of Channels',
      'commentary': "Channels may be things like 'instore' or 'online', although you can supply"
          ~ ' whatever values you want. Perhaps they are marketing channels. This '
          ~ ' feature is the number of distinct channels in which activity occurred.'
  }}) %}

{% endmacro %}
