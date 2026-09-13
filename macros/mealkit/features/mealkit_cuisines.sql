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
  emitted SQL stays valid, via jstark.sql_string() (macros/core/feature_catalog.sql).
#}

{% macro try_validate_cuisines(cuisines, definitions, feature_period) %}
  {#
    The boundary where a caller-supplied string becomes a SQL identifier.

    Everything a cuisine ends up naming is derived from the cuisine itself, so
    two cuisines, or a cuisine and an existing feature, can reduce to one column
    name. That is not recoverable: the caller asked for two columns and only one
    can exist, so it is reported rather than deduplicated. Three shapes reach
    here, all of them plausible inputs:

      ['']                  -> stem 'CuisineCount', which is the mealkit
                               distinct-count feature's own stem, so registering
                               it would replace a documented feature with a
                               count_if under the same name
      ['-']                 -> stem '-CuisineCount', a different stem that
                               snake_cases to the same column as CuisineCount
      ['Italian','italian'] -> two stems, one column

    Note the second shape is why the check is on the column name and not on the
    stem: '-CuisineCount' is not in `definitions`, but its column is.

    Returns: {'ok', 'error'}. The first problem in caller order is reported, so
    the message names one offending input rather than a list.
  #}
  {% set owner = {} %}
  {% set problems = [] %}

  {% for stem in definitions %}
    {% do owner.update({
        jstark.column_name(stem, feature_period): 'the ' ~ stem ~ ' feature'
    }) %}
  {% endfor %}

  {% for cuisine in cuisines %}
    {% if cuisine is not string %}
      {% do problems.append(jstark.error_message(
          jstark.error_codes()['invalid_cuisine'],
          'cuisines entry ' ~ (cuisine | string) ~ ' is not a string; every '
          ~ 'entry must be a non-empty string naming a cuisine'
      )) %}
    {% elif cuisine | trim == '' %}
      {% do problems.append(jstark.error_message(
          jstark.error_codes()['invalid_cuisine'],
          "cuisines entry '" ~ cuisine ~ "' is empty or whitespace only; every "
          ~ 'entry must be a non-empty string naming a cuisine'
      )) %}
    {% else %}
      {% set column = jstark.column_name(cuisine ~ 'CuisineCount', feature_period) %}
      {% if column in owner %}
        {% do problems.append(jstark.error_message(
            jstark.error_codes()['duplicate_column_name'],
            "cuisines entry '" ~ cuisine ~ "' produces the column " ~ column
            ~ ', which is already taken by ' ~ owner[column]
            ~ '. Two columns cannot share one name, so rename or drop one of them'
        )) %}
      {% else %}
        {% do owner.update({column: "cuisines entry '" ~ cuisine ~ "'"}) %}
      {% endif %}
    {% endif %}
  {% endfor %}

  {% if problems | length > 0 %}
    {{ return({'ok': false, 'error': problems[0]}) }}
  {% endif %}
  {{ return({'ok': true, 'error': none}) }}
{% endmacro %}


{% macro validate_cuisines(cuisines, definitions, feature_period) %}
  {% set result = jstark.try_validate_cuisines(
      cuisines, definitions, feature_period
  ) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
{% endmacro %}


{% macro register_mealkit_cuisine_features(definitions, ctx) %}

  {#- before the loop: a rejected cuisine must not reach `definitions`, where
      it could overwrite an entry that is already there -#}
  {% do jstark.validate_cuisines(
      ctx['cuisines'], definitions, ctx['period']
  ) %}

  {% for cuisine in ctx['cuisines'] %}
    {% set stem = cuisine ~ 'CuisineCount' %}
    {% set cuisine_literal = cuisine | lower %}
    {% do definitions.update({stem: {
        'stem': stem,
        'kind': 'base',
        'aggregator': 'count_if',
        'expression': 'lower(' ~ ctx['cols']['cuisine'] ~ ') = '
              ~ jstark.sql_string(cuisine_literal),
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
