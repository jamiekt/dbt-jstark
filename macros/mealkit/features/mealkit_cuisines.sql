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

  The comparison itself is case-insensitive on both sides, matching jstark
  (cuisine_count.py:31-33: `f.lower(f.col("Cuisine")) == self.CUISINE_NAME.lower()`),
  even though CUISINE_NAME casing does not need it there because jstark's own
  constants are already lowercase. Here a caller-supplied cuisine can be cased
  any way, so lowering both the column and the literal is what actually makes
  cuisines=['Italian'] match data stored as 'italian'. Only the comparison
  lowercases: the stem, column name, description_subject and commentary keep
  the caller's original casing unchanged.

  A single quote embedded in the cuisine value (e.g. an apostrophe in a place
  name) is doubled before being spliced into the SQL string literal, so the
  emitted SQL stays valid. jstark.sql_string() would be the natural home for
  this, but that macro does not exist until Task 13; do not wait for it here.
#}

{% macro register_mealkit_cuisine_features(definitions, ctx) %}

  {% for cuisine in ctx['cuisines'] %}
    {% set stem = cuisine ~ 'CuisineCount' %}
    {% set cuisine_literal = cuisine | lower | replace("'", "''") %}
    {% do definitions.update({stem: {
        'stem': stem,
        'kind': 'base',
        'aggregator': 'count_if',
        'expression': 'lower(' ~ ctx['cols']['cuisine'] ~ ") = '" ~ cuisine_literal ~ "'",
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
