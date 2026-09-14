{% macro register_core_date_features(definitions, ctx) %}

  {% do definitions.update({'RecencyDays': {
      'stem': 'RecencyDays',
      'kind': 'base',
      'aggregator': 'min',
      'expression': dbt.datediff(
          jstark.to_date(ctx['cols']['event_timestamp']),
          jstark.date_literal(ctx['as_at']),
          'day'
      ),
      'default': '0',
      'required_columns': ['event_timestamp'],
      'description_subject': 'Minimum number of days since occurrence',
      'commentary': 'This could be particularly useful (for example) in a grocery retailer '
          ~ 'for determining when a customer most recently bought a product or '
          ~ ' when a product was most recently bought in a store'
          ~ 'Also note that this is very similar to '
          ~ ('MostRecentPurchaseDate_' ~ ctx['period']['mnemonic'] ~ ' ')
          ~ 'so consider which of these '
          ~ 'features is most useful to you.'
  }}) %}

  {% do definitions.update({'EarliestPurchaseDate': {
      'stem': 'EarliestPurchaseDate',
      'kind': 'base',
      'aggregator': 'min',
      'expression': jstark.to_date(ctx['cols']['event_timestamp']),
      'default': 'null',
      'required_columns': ['event_timestamp'],
      'description_subject': 'Earliest purchase date',
      'commentary': 'Basically, when was a purchase first made. This could '
          ~ 'be used to determine a whole myriad of useful information'
          ~ ' such as when a customer first shopped, or'
          ~ 'when a customer first bought a particular product. To make '
          ~ 'use of this you would likely need to define '
          ~ "a large feature period, there isn't much use"
          ~ "in knowing when someone's earliest purchase was "
          ~ 'in the previous two weeks.'
  }}) %}

  {% do definitions.update({'MostRecentPurchaseDate': {
      'stem': 'MostRecentPurchaseDate',
      'kind': 'base',
      'aggregator': 'max',
      'expression': jstark.to_date(ctx['cols']['event_timestamp']),
      'default': 'null',
      'required_columns': ['event_timestamp'],
      'description_subject': 'Most recent purchase date',
      'commentary': 'It is useful to be able to see when something was most recently '
          ~ 'purchased.For example, grouping by Store and filtering where '
          ~ 'MostRecentPurchaseDate is more than 2 days ago could be a useful '
          ~ 'indicator of things which might not be available for purchase.'
          ~ 'Also note that this is very similar to '
          ~ ('RecencyDays_' ~ ctx['period']['mnemonic'] ~ ' so consider which of these ')
          ~ 'features is most useful to you.'
  }}) %}

{% endmacro %}
