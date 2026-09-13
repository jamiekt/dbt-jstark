{% macro register_core_sum_features(definitions, ctx) %}

  {% do definitions.update({'Quantity': {
      'stem': 'Quantity',
      'kind': 'base',
      'aggregator': 'sum',
      'expression': ctx['cols']['quantity'],
      'default': '0',
      'required_columns': ['event_timestamp', 'quantity'],
      'description_subject': 'Sum of Quantity',
      'commentary': 'No commentary supplied'
  }}) %}

  {% do definitions.update({'Discount': {
      'stem': 'Discount',
      'kind': 'base',
      'aggregator': 'sum',
      'expression': ctx['cols']['discount'],
      'default': '0.0',
      'required_columns': ['event_timestamp', 'discount'],
      'description_subject': 'Sum of Discount',
      'commentary': 'Requires a field called `Discount` in the input data.'
  }}) %}

  {% do definitions.update({'GrossSpend': {
      'stem': 'GrossSpend',
      'kind': 'base',
      'aggregator': 'sum',
      'expression': ctx['cols']['gross_spend'],
      'default': '0.0',
      'required_columns': ['event_timestamp', 'gross_spend'],
      'description_subject': 'Sum of GrossSpend',
      'commentary': 'The definition of GrossSpend can be whatever you want '
          ~ 'it to be though typically its the price inclusive of any tax paid'
  }}) %}

  {% do definitions.update({'NetSpend': {
      'stem': 'NetSpend',
      'kind': 'base',
      'aggregator': 'sum',
      'expression': ctx['cols']['net_spend'],
      'default': '0.0',
      'required_columns': ['event_timestamp', 'net_spend'],
      'description_subject': 'Sum of NetSpend',
      'commentary': 'The definition of NetSpend can be whatever you want '
          ~ 'it to be though typically its the price exclusive of any tax paid'
  }}) %}

{% endmacro %}
