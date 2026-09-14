{#
  Fixture features used by jstark's own test suite.

  NOT part of the public API. They exist so that the engine — dependency
  closure, levelling, CTE emission — can be tested against a catalogue small
  enough to assert on exhaustively, independently of the real feature
  definitions.

  Between them they cover every shape the engine has to handle: a base
  aggregate, a derived feature over two base aggregates, a derived feature
  over another derived feature, and a derived feature that depends on base
  aggregates from periods other than its own.
#}

{% macro register_test_features(definitions, ctx) %}

  {% do definitions.update({'TestSpend': {
      'stem': 'TestSpend',
      'kind': 'base',
      'aggregator': 'sum',
      'expression': ctx['cols']['gross_spend'],
      'default': '0.0',
      'required_columns': ['event_timestamp', 'gross_spend'],
      'description_subject': 'Sum of TestSpend',
      'commentary': 'Test fixture. Not a real feature.'
  }}) %}

  {% do definitions.update({'TestBasketCount': {
      'stem': 'TestBasketCount',
      'kind': 'base',
      'aggregator': 'count_distinct',
      'expression': ctx['cols']['basket'],
      'default': '0',
      'required_columns': ['event_timestamp', 'basket'],
      'description_subject': 'Distinct count of test Baskets',
      'commentary': 'Test fixture. Not a real feature.'
  }}) %}

  {% do definitions.update({'TestSpendPerBasket': {
      'stem': 'TestSpendPerBasket',
      'kind': 'derived',
      'depends_on': [
          ['TestSpend', ctx['period']], ['TestBasketCount', ctx['period']]
      ],
      'expression': jstark.safe_divide(
          jstark.column_name('TestSpend', ctx['period']),
          jstark.column_name('TestBasketCount', ctx['period'])
      ),
      'default': 'null',
      'description_subject': 'Test spend per basket',
      'commentary': 'Test fixture. Not a real feature.'
  }}) %}

  {% do definitions.update({'TestSpendPerBasketPerBasket': {
      'stem': 'TestSpendPerBasketPerBasket',
      'kind': 'derived',
      'depends_on': [
          ['TestSpendPerBasket', ctx['period']], ['TestBasketCount', ctx['period']]
      ],
      'expression': jstark.safe_divide(
          jstark.column_name('TestSpendPerBasket', ctx['period']),
          jstark.column_name('TestBasketCount', ctx['period'])
      ),
      'default': 'null',
      'description_subject': 'Test spend per basket per basket',
      'commentary': 'Test fixture exercising a derived-on-derived dependency.'
  }}) %}

  {#- a derived feature whose dependencies live in other periods -#}
  {% set sub_periods = jstark.single_unit_periods(ctx['period']) %}
  {% set terms = [] %}
  {% set deps = [] %}
  {% for sub in sub_periods %}
    {% set column = jstark.column_name('TestBasketCount', sub) %}
    {% do terms.append('case when ' ~ column ~ ' > 0 then 1 else 0 end') %}
    {% do deps.append(['TestBasketCount', sub]) %}
  {% endfor %}
  {% do definitions.update({'TestActiveMonths': {
      'stem': 'TestActiveMonths',
      'kind': 'derived',
      'depends_on': deps,
      'expression': terms | join(' + '),
      'default': 'null',
      'description_subject': 'Number of active test periods',
      'commentary': 'Test fixture exercising a cross-period dependency.'
  }}) %}

{% endmacro %}
