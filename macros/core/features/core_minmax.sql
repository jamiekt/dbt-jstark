{% macro register_core_minmax_features(definitions, ctx) %}

  {#
    Min features default to 0.0 and Max features default to null on an empty
    window. That is asymmetric, and it is what jstark does:
    Min.default_value() returns f.lit(0.0) while Max.default_value() returns
    f.lit(None). Reproduced for parity rather than fixed.
  #}
  {% do definitions.update({'MinGrossSpend': {
      'stem': 'MinGrossSpend',
      'kind': 'base',
      'aggregator': 'min',
      'expression': ctx['cols']['gross_spend'],
      'default': '0.0',
      'required_columns': ['event_timestamp', 'gross_spend'],
      'description_subject': 'Minimum GrossSpend value',
      'commentary': 'No commentary supplied'
  }}) %}

  {% do definitions.update({'MaxGrossSpend': {
      'stem': 'MaxGrossSpend',
      'kind': 'base',
      'aggregator': 'max',
      'expression': ctx['cols']['gross_spend'],
      'default': 'null',
      'required_columns': ['event_timestamp', 'gross_spend'],
      'description_subject': 'Maximum GrossSpend value',
      'commentary': 'No commentary supplied'
  }}) %}

  {% do definitions.update({'MinNetSpend': {
      'stem': 'MinNetSpend',
      'kind': 'base',
      'aggregator': 'min',
      'expression': ctx['cols']['net_spend'],
      'default': '0.0',
      'required_columns': ['event_timestamp', 'net_spend'],
      'description_subject': 'Minimum of NetSpend value',
      'commentary': 'No commentary supplied'
  }}) %}

  {% do definitions.update({'MaxNetSpend': {
      'stem': 'MaxNetSpend',
      'kind': 'base',
      'aggregator': 'max',
      'expression': ctx['cols']['net_spend'],
      'default': 'null',
      'required_columns': ['event_timestamp', 'net_spend'],
      'description_subject': 'Maximum of NetSpend value',
      'commentary': 'No commentary supplied'
  }}) %}

  {% do definitions.update({'MinGrossPrice': {
      'stem': 'MinGrossPrice',
      'kind': 'base',
      'aggregator': 'min',
      'expression': jstark.safe_divide(
          ctx['cols']['gross_spend'], ctx['cols']['quantity']
      ),
      'default': '0.0',
      'required_columns': ['event_timestamp', 'gross_spend', 'quantity'],
      'description_subject': 'Minimum of (GrossSpend / Quantity)',
      'commentary': 'The net price is calculated as the gross '
          ~ 'spend divided by how many were bought.'
  }}) %}

  {% do definitions.update({'MaxGrossPrice': {
      'stem': 'MaxGrossPrice',
      'kind': 'base',
      'aggregator': 'max',
      'expression': jstark.safe_divide(
          ctx['cols']['gross_spend'], ctx['cols']['quantity']
      ),
      'default': 'null',
      'required_columns': ['event_timestamp', 'gross_spend', 'quantity'],
      'description_subject': 'Maximum of (GrossSpend / Quantity)',
      'commentary': 'The gross price is calculated as the gross '
          ~ 'spend divided by how many were bought.'
  }}) %}

  {% do definitions.update({'MinNetPrice': {
      'stem': 'MinNetPrice',
      'kind': 'base',
      'aggregator': 'min',
      'expression': jstark.safe_divide(
          ctx['cols']['net_spend'], ctx['cols']['quantity']
      ),
      'default': '0.0',
      'required_columns': ['event_timestamp', 'net_spend', 'quantity'],
      'description_subject': 'Minimum of (NetSpend / Quantity)',
      'commentary': 'The net price is calculated as the net '
          ~ 'spend dividied by how many were bought.'
  }}) %}

  {% do definitions.update({'MaxNetPrice': {
      'stem': 'MaxNetPrice',
      'kind': 'base',
      'aggregator': 'max',
      'expression': jstark.safe_divide(
          ctx['cols']['net_spend'], ctx['cols']['quantity']
      ),
      'default': 'null',
      'required_columns': ['event_timestamp', 'net_spend', 'quantity'],
      'description_subject': 'Maximum of (NetSpend / Quantity)',
      'commentary': 'The net price is calculated as the net '
          ~ 'spend divided by how many were bought.'
  }}) %}

{% endmacro %}
