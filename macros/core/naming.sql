{#
  Feature naming.

  A feature is identified by its CamelCase *stem* (e.g. RecencyWeightedBasket95).
  The emitted column name is the snake_cased stem with the feature period
  appended (recency_weighted_basket_weeks95_52w0).

  Some stems are unit-dependent: jstark's BasketPeriods feature is called
  BasketMonths when the period unit is months and BasketWeeks when it is
  weeks. name_stem_overrides holds those as [prefix, suffix] pairs; the unit
  name is inserted between them before snake_casing.
#}

{% macro snake_case(name) %}
  {#- collapse anything that is not alphanumeric into a single underscore -#}
  {% set cleaned = modules.re.sub('[^A-Za-z0-9]+', '_', name | string) %}
  {#- lowercase-or-digit followed by uppercase is a word boundary -#}
  {% set s1 = modules.re.sub('([a-z0-9])([A-Z])', '\\1_\\2', cleaned) %}
  {#- an acronym run followed by a capitalised word is a word boundary -#}
  {% set s2 = modules.re.sub('([A-Z]+)([A-Z][a-z])', '\\1_\\2', s1) %}
  {#- tidy up doubled and edge underscores left by the steps above -#}
  {% set s3 = modules.re.sub('_+', '_', s2) %}
  {{ return(s3 | lower | trim('_')) }}
{% endmacro %}


{% macro period_unit_name(uom) %}
  {% set names = {
      'd': 'Day', 'w': 'Week', 'm': 'Month', 'q': 'Quarter', 'y': 'Year'
  } %}
  {% if uom not in names %}
    {% do jstark.raise_error(
        jstark.error_codes()['mnemonic_is_invalid'],
        "'" ~ uom ~ "' is not a period unit of measure; expected one of d, w, m, q, y"
    ) %}
  {% endif %}
  {{ return(names[uom]) }}
{% endmacro %}


{% macro name_stem_overrides() %}
  {#- stem -> [prefix, suffix]; the unit name goes between them -#}
  {{ return({
      'BasketPeriods': ['Basket', 's'],
      'OrderPeriods': ['Order', 's'],
      'AvgBasket': ['AverageBasketsPer', ''],
      'AvgOrder': ['AverageOrdersPer', ''],
      'RecencyWeightedBasket90': ['RecencyWeightedBasket', 's90'],
      'RecencyWeightedBasket95': ['RecencyWeightedBasket', 's95'],
      'RecencyWeightedBasket99': ['RecencyWeightedBasket', 's99'],
      'RecencyWeightedApproxBasket90': ['RecencyWeightedApproxBasket', 's90'],
      'RecencyWeightedApproxBasket95': ['RecencyWeightedApproxBasket', 's95'],
      'RecencyWeightedApproxBasket99': ['RecencyWeightedApproxBasket', 's99']
  }) }}
{% endmacro %}


{% macro feature_base_name(stem, uom) %}
  {% set overrides = jstark.name_stem_overrides() %}
  {% if stem in overrides %}
    {% set parts = overrides[stem] %}
    {% set camel = parts[0] ~ jstark.period_unit_name(uom) ~ parts[1] %}
  {% else %}
    {% set camel = stem %}
  {% endif %}
  {{ return(jstark.snake_case(camel)) }}
{% endmacro %}


{% macro column_name(stem, feature_period) %}
  {{ return(
      jstark.feature_base_name(stem, feature_period['uom'])
      ~ '_' ~ feature_period['mnemonic']
  ) }}
{% endmacro %}


{% macro public_column_name(
    stem, feature_period, use_absolute_periods, as_at, first_day_of_week
) %}
  {% if not use_absolute_periods %}
    {{ return(jstark.column_name(stem, feature_period)) }}
  {% endif %}
  {{ return(
      jstark.feature_base_name(stem, feature_period['uom'])
      ~ '_'
      ~ jstark.absolute_period_label(feature_period, as_at, first_day_of_week)
  ) }}
{% endmacro %}
