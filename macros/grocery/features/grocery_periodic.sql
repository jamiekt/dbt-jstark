{#
  Features that look at each whole unit inside the window separately, rather
  than at the window as a whole. For 3m1 that means October, November and
  December individually.

  Those per-unit aggregates are dependencies at periods the caller never asked
  for (3m3, 2m2, 1m1). The engine computes them in the base CTE and drops them
  from the final projection, so BasketPeriods and RecencyWeightedBasket* share
  one set of them rather than each computing its own.

  The exponential weights are evaluated here in Jinja, so the emitted SQL
  contains plain float literals and never calls power() — one less thing to
  differ between warehouses.
#}

{% macro register_grocery_periodic_features(definitions, ctx) %}

  {% set period = ctx['period'] %}
  {% set unit = jstark.period_unit_name(period['uom']) | lower %}
  {% set unit_title = jstark.period_unit_name(period['uom']) %}
  {% set sub_periods = jstark.single_unit_periods(period) %}
  {% set n = period['number_of_periods'] %}

  {#- BasketPeriods: how many whole units saw at least one basket.
      jstark tests BasketCount at each sub-period, not Count (basket_periods.py),
      so a unit counts as active only if a distinct basket falls in it - not
      merely a row. The two differ whenever a basket spans several rows. -#}
  {% set activity_stem = 'BasketCount' %}
  {% set terms = [] %}
  {% set deps = [] %}
  {% for sub in sub_periods %}
    {% set column = jstark.column_name(activity_stem, sub) %}
    {% do terms.append('case when ' ~ column ~ ' > 0 then 1 else 0 end') %}
    {% do deps.append([activity_stem, sub]) %}
  {% endfor %}
  {% do definitions.update({'BasketPeriods': {
      'stem': 'BasketPeriods',
      'kind': 'derived',
      'depends_on': deps,
      'expression': terms | join(' + '),
      'default': 'null',
      'description_subject': 'Number of ' ~ unit
                             ~ 's in which at least one basket was purchased',
      'commentary': 'The number of ' ~ unit ~ 's '
          ~ 'in which at least one basket was purchased. The value will be in the '
          ~ 'range 0 to ' ~ n ~ ' '
          ~ 'because ' ~ n ~ ' is '
          ~ 'the number of ' ~ unit
          ~ 's between ' ~ jstark.date_string(ctx['start_date']) ~ ' and'
          ~ ' ' ~ jstark.date_string(ctx['end_date']) ~ '. When grouped by Customer and'
          ~ ' Product this feature is a useful indicator of the frequency of'
          ~ ' which a Customer purchases a Product.'
  }}) %}

  {#- AvgBasket: baskets per whole unit across the window. Divides
      BasketCount, not Count: see average_basket.py:16-27, which constructs a
      BasketCount at the same feature period and divides that by
      number_of_periods. jstark does not override commentary for this
      feature, so it inherits the base class default. -#}
  {% do definitions.update({'AvgBasket': {
      'stem': 'AvgBasket',
      'kind': 'derived',
      'depends_on': [['BasketCount', period]],
      'expression': jstark.safe_divide(
          jstark.column_name('BasketCount', period),
          period['number_of_periods'] | string
      ),
      'default': 'null',
      'description_subject': 'Average number of baskets per ' ~ unit,
      'commentary': 'No commentary supplied'
  }}) %}

  {#- the six recency-weighted variants: three smoothing factors, exact and
      approximate basket counts -#}
  {% for variant in [
      {'stem_prefix': 'RecencyWeightedBasket', 'count_stem': 'BasketCount',
       'adjective': ''},
      {'stem_prefix': 'RecencyWeightedApproxBasket',
       'count_stem': 'ApproxBasketCount', 'adjective': 'approximate '}
  ] %}
    {% for smoothing_factor in [0.9, 0.95, 0.99] %}
      {% set suffix = (smoothing_factor * 100) | round | int | string %}
      {% set weighted_terms = [] %}
      {% set weighted_deps = [] %}
      {% for sub in sub_periods %}
        {% do weighted_terms.append(
            jstark.column_name(variant['count_stem'], sub)
            ~ ' * ' ~ (smoothing_factor ** sub['start'])
        ) %}
        {% do weighted_deps.append([variant['count_stem'], sub]) %}
      {% endfor %}

      {#- the two feature names of this suffix, both directions, so each
          commentary can point at its counterpart exactly as jstark does -#}
      {% set feature_name_basket =
          'RecencyWeightedBasket' ~ unit_title ~ 's' ~ suffix ~ '_' ~ period['mnemonic'] %}
      {% set feature_name_approx =
          'RecencyWeightedApproxBasket' ~ unit_title ~ 's' ~ suffix ~ '_' ~ period['mnemonic'] %}

      {% if variant['stem_prefix'] == 'RecencyWeightedApproxBasket' %}
        {% set commentary =
            'Exponential smoothing '
            ~ '(https://en.wikipedia.org/wiki/Exponential_smoothing)'
            ~ ' is an alternative to a simple moving average which'
            ~ ' gives greater weighting to more recent observations, thus is an'
            ~ ' exponentially weighted moving average. It uses a smoothing factor'
            ~ ' between 0 & 1 which for this feature is ' ~ smoothing_factor ~ '.'
            ~ ' Here the approximate number of baskets per'
            ~ ' ' ~ unit ~ ' is smoothed.'
            ~ ' This feature is considered to be a highly effective predictor of future'
            ~ " purchases, if a customer has bought a product recently then there's a"
            ~ ' relatively high probability they will buy it again.'
            ~ ' This is less accurate than ' ~ feature_name_basket
            ~ ' though is less computationally expensive to calculate because it '
            ~ ' does not calculate a distinct count for each'
            ~ ' ' ~ unit ~ '.'
        %}
      {% else %}
        {% set plural = 's' if n > 1 else '' %}
        {% set commentary =
            'Exponential smoothing '
            ~ '(https://en.wikipedia.org/wiki/Exponential_smoothing)'
            ~ ' is an alternative to a simple moving average which'
            ~ ' gives greater weighting to more recent observations, thus is an'
            ~ ' exponentially weighted moving average. It uses a smoothing factor'
            ~ ' between 0 & 1 which for this feature is ' ~ smoothing_factor ~ '.'
            ~ ' Here the number of baskets per'
            ~ ' ' ~ unit ~ ' is smoothed.'
            ~ ' This feature is considered to be a highly effective predictor of future'
            ~ " purchases, if a customer has bought a product recently then there's a"
            ~ ' relatively high probability they will buy it again.'
            ~ ' This is computationally expensive to calculate because it '
            ~ ' requires a distinct count of baskets for each'
            ~ ' ' ~ unit ~ '. Every'
            ~ ' distinct count operation is expensive so the less that are performed,'
            ~ ' the better (YMMV based on a number of factors, '
            ~ 'mainly the volume of data'
            ~ ' being processed). For this reason you should consider choosing a small'
            ~ ' number of ' ~ unit ~ 's'
            ~ ' for the feature period. This feature'
            ~ ' (' ~ feature_name_basket ~ ') is for'
            ~ ' ' ~ n
            ~ ' ' ~ unit
            ~ plural ~ '. You might'
            ~ ' consider using ' ~ feature_name_approx
            ~ ' instead which is less accurate but computationally cheaper.'
        %}
      {% endif %}

      {% do definitions.update({variant['stem_prefix'] ~ suffix: {
          'stem': variant['stem_prefix'] ~ suffix,
          'kind': 'derived',
          'depends_on': weighted_deps,
          'expression': weighted_terms | join(' + '),
          'default': 'null',
          'description_subject':
              'Exponentially weighted moving average, with smoothing factor of '
              ~ smoothing_factor ~ ', of the ' ~ variant['adjective']
              ~ 'number of baskets per ' ~ unit,
          'commentary': commentary
      }}) %}
    {% endfor %}
  {% endfor %}

{% endmacro %}
