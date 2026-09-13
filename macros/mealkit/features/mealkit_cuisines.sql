{#
  One count per cuisine the caller asked about.

  jstark hard-codes its cuisine list; here it is a parameter, so the feature
  set is decided at compile time from `cuisines`. That also means the three
  misspelled column names jstark has inherited cannot arise.

  The stem is the cuisine name concatenated with 'CuisineCount', spaces and
  all. snake_case turns runs of non-alphanumerics into underscores before it
  splits camel humps, so 'South AfricanCuisineCount' becomes
  south_african_cuisine_count with no special-casing.

  jstark's CuisineCountIf.description_subject and .commentary both apply
  Python's str.capitalize() to CUISINE_NAME, which is safe for jstark because
  its CUISINE_NAME constants are lowercase ("italian"). Here the cuisine
  arrives already cased from the caller ("South African"), so no capitalize
  equivalent is applied - it would turn 'South African' into 'South african'.
#}

{% macro register_mealkit_cuisine_features(definitions, ctx) %}

  {% for cuisine in ctx['cuisines'] %}
    {% set stem = cuisine ~ 'CuisineCount' %}
    {% do definitions.update({stem: {
        'stem': stem,
        'kind': 'base',
        'aggregator': 'count_if',
        'expression': ctx['cols']['cuisine'] ~ " = '" ~ cuisine ~ "'",
        'default': '0',
        'required_columns': ['event_timestamp', 'cuisine'],
        'description_subject': 'Count of ' ~ cuisine ~ ' recipes',
        'commentary': 'The number of ' ~ cuisine ~ ' recipes. Typically the '
            ~ 'dataframe supplied to this feature will have '
            ~ 'many recipes for the same cuisine, this feature '
            ~ 'allows you to determine how many ' ~ cuisine ~ ' '
            ~ 'recipes have been ordered.'
    }}) %}
  {% endfor %}

{% endmacro %}
