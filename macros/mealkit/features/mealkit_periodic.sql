{#
  Features that look at each whole unit inside the window separately. See the
  equivalent grocery file for why the per-unit aggregates are dependencies at
  periods the caller never asked for.

  Mealkit has no recency-weighted variants; jstark defines those for grocery
  only.
#}

{% macro register_mealkit_periodic_features(definitions, ctx) %}

  {% set period = ctx['period'] %}
  {% set unit = jstark.period_unit_name(period['uom']) | lower %}
  {% set sub_periods = jstark.single_unit_periods(period) %}
  {% set n = period['number_of_periods'] %}

  {#- OrderPeriods: how many whole units saw at least one order.
      jstark tests OrderCount at each sub-period, not Count -
      jstark/mealkit/order_periods.py:23. -#}
  {% set activity_stem = 'OrderCount' %}
  {% set terms = [] %}
  {% set deps = [] %}
  {% for sub in sub_periods %}
    {% set column = jstark.column_name(activity_stem, sub) %}
    {% do terms.append('case when ' ~ column ~ ' > 0 then 1 else 0 end') %}
    {% do deps.append([activity_stem, sub]) %}
  {% endfor %}
  {#- One deliberate departure from jstark's wording. jstark's commentary for
      this feature (order_periods.py:50) says "at least one basket was
      purchased" - a copy-paste from the grocery BasketPeriods feature, and
      contradicted by its own description_subject seven lines above, which
      correctly says "order was placed". Reproducing a self-contradiction
      verbatim buys nothing, so the commentary below carries the correction.
      Everywhere else, description and commentary text is verbatim from jstark. -#}
  {% do definitions.update({'OrderPeriods': {
      'stem': 'OrderPeriods',
      'kind': 'derived',
      'depends_on': deps,
      'expression': terms | join(' + '),
      'default': 'null',
      'description_subject': 'Number of ' ~ unit
                             ~ 's in which at least one order was placed',
      'commentary': 'The number of ' ~ unit ~ 's '
          ~ 'in which at least one order was placed. The value will be in the '
          ~ 'range 0 to ' ~ n ~ ' '
          ~ 'because ' ~ n ~ ' is '
          ~ 'the number of ' ~ unit
          ~ 's between ' ~ jstark.date_string(ctx['start_date']) ~ ' and'
          ~ ' ' ~ jstark.date_string(ctx['end_date']) ~ '. When grouped by Customer and'
          ~ ' Product this feature is a useful indicator of the frequency of'
          ~ ' which a Customer purchases a Product.'
  }}) %}

  {#- AvgOrder: orders per whole unit across the window. Divides
      OrderCount, not Count: see average_order.py:15-26, which constructs an
      OrderCount at the same feature period and divides that by
      number_of_periods. jstark does not override commentary for this
      feature, so it inherits the base class default. -#}
  {% do definitions.update({'AvgOrder': {
      'stem': 'AvgOrder',
      'kind': 'derived',
      'depends_on': [['OrderCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('OrderCount', period),
          period['number_of_periods'] | string
      ),
      'default': 'null',
      'description_subject': 'Average number of orders per ' ~ unit,
      'commentary': 'No commentary supplied'
  }}) %}

{% endmacro %}
