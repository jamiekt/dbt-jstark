{#
  Input columns, as_at resolution, and the per-period feature context.

  Feature definitions never name a raw column; they read ctx.cols['gross_spend'].
  That is what makes column_map work without every definition knowing about it.

  Column references are emitted unquoted so that warehouse case-folding
  applies: Snowflake stores gross_spend as GROSS_SPEND and resolves the
  unquoted lower-case reference to it, whereas "gross_spend" would not match.
  This is also why the canonical names avoid `timestamp` (Postgres parses
  `cast(timestamp as date)` as a type name) and `order` (reserved everywhere).
#}

{% macro canonical_columns() %}
  {{ return([
      'event_timestamp', 'basket', 'order_id', 'store', 'channel', 'customer',
      'product', 'quantity', 'net_spend', 'gross_spend', 'discount',
      'cuisine', 'recipe', 'allergen'
  ]) }}
{% endmacro %}


{% macro try_resolve_columns(column_map) %}
  {% set canonical = jstark.canonical_columns() %}
  {% set overrides = column_map if column_map else {} %}

  {% for key in overrides %}
    {% if key not in canonical %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['unknown_column_map_key'],
              "'" ~ key ~ "' is not a jstark input column; expected one of "
              ~ (canonical | join(', '))
          ),
          'cols': none
      }) }}
    {% endif %}
  {% endfor %}

  {% set cols = {} %}
  {% for name in canonical %}
    {% do cols.update({name: overrides.get(name, name)}) %}
  {% endfor %}

  {{ return({'ok': true, 'error': none, 'cols': cols}) }}
{% endmacro %}


{% macro resolve_columns(column_map) %}
  {% set result = jstark.try_resolve_columns(column_map) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['cols']) }}
{% endmacro %}


{% macro try_resolve_as_at(as_at) %}
  {#
    Precedence: the argument, then the jstark_as_at var, then the run date.

    Falling back to the run date makes features non-deterministic between
    runs, which is almost never what someone wants in a scheduled job, so the
    fallback warns and names the var to set.
  #}
  {% if as_at is not none %}
    {# Validate string dates match ISO 8601 format #}
    {% if as_at is string %}
      {% if not modules.re.match('^\\d{4}-\\d{2}-\\d{2}$', as_at) %}
        {{ return({
            'ok': false,
            'error': jstark.error_message(
                jstark.error_codes()['as_at_is_not_a_date'],
                "'" ~ as_at ~ "' is not a valid ISO date; expected format YYYY-MM-DD"
            ),
            'date': none
        }) }}
      {% endif %}
    {% endif %}
    {{ return({
        'ok': true,
        'error': none,
        'date': jstark.as_date(as_at)
    }) }}
  {% endif %}

  {% set from_var = var('jstark_as_at', none) %}
  {% if from_var is not none %}
    {# Validate string dates match ISO 8601 format #}
    {% if from_var is string %}
      {% if not modules.re.match('^\\d{4}-\\d{2}-\\d{2}$', from_var) %}
        {{ return({
            'ok': false,
            'error': jstark.error_message(
                jstark.error_codes()['as_at_is_not_a_date'],
                "'" ~ from_var ~ "' is not a valid ISO date; expected format YYYY-MM-DD"
            ),
            'date': none
        }) }}
      {% endif %}
    {% endif %}
    {{ return({
        'ok': true,
        'error': none,
        'date': jstark.as_date(from_var)
    }) }}
  {% endif %}

  {{ return({
      'ok': true,
      'error': none,
      'date': jstark.as_date(run_started_at)
  }) }}
{% endmacro %}


{% macro resolve_as_at(as_at) %}
  {#
    Precedence: the argument, then the jstark_as_at var, then the run date.

    Falling back to the run date makes features non-deterministic between
    runs, which is almost never what someone wants in a scheduled job, so the
    fallback warns and names the var to set.
  #}
  {% if as_at is not none %}
    {# Validate string dates match ISO 8601 format #}
    {% if as_at is string %}
      {% if not modules.re.match('^\\d{4}-\\d{2}-\\d{2}$', as_at) %}
        {{ jstark.raise_error(
            jstark.error_codes()['as_at_is_not_a_date'],
            "'" ~ as_at ~ "' is not a valid ISO date; expected format YYYY-MM-DD"
        ) }}
      {% endif %}
    {% endif %}
    {{ return(jstark.as_date(as_at)) }}
  {% endif %}

  {% set from_var = var('jstark_as_at', none) %}
  {% if from_var is not none %}
    {# Validate string dates match ISO 8601 format #}
    {% if from_var is string %}
      {% if not modules.re.match('^\\d{4}-\\d{2}-\\d{2}$', from_var) %}
        {{ jstark.raise_error(
            jstark.error_codes()['as_at_is_not_a_date'],
            "'" ~ from_var ~ "' is not a valid ISO date; expected format YYYY-MM-DD"
        ) }}
      {% endif %}
    {% endif %}
    {{ return(jstark.as_date(from_var)) }}
  {% endif %}

  {% do exceptions.warn(
      'jstark: no as_at was supplied, so features are being generated as at the '
      ~ 'run date. Pass as_at=... or set the jstark_as_at var to make results '
      ~ 'reproducible.'
  ) %}
  {{ return(jstark.as_date(run_started_at)) }}
{% endmacro %}


{% macro date_literal(d) %}
  {{ return("date '" ~ jstark.date_string(d) ~ "'") }}
{% endmacro %}


{% macro feature_context(
    feature_period, as_at, first_day_of_week, use_absolute_periods, cols, cuisines
) %}
  {% set day_of_week = 'Monday' if first_day_of_week is none else first_day_of_week %}
  {#- validate eagerly so a typo fails before any SQL is emitted -#}
  {% do jstark.weekday_index(day_of_week) %}

  {% set bounds = jstark.period_bounds(feature_period, as_at, day_of_week) %}
  {% set event_date = jstark.to_date(cols['event_timestamp']) %}

  {{ return({
      'period': feature_period,
      'as_at': as_at,
      'start_date': bounds['start_date'],
      'end_date': bounds['end_date'],
      'window': event_date
                ~ ' between ' ~ jstark.date_literal(bounds['start_date'])
                ~ ' and ' ~ jstark.date_literal(bounds['end_date']),
      'cols': cols,
      'first_day_of_week': day_of_week,
      'use_absolute_periods': use_absolute_periods,
      'cuisines': cuisines if cuisines else []
  }) }}
{% endmacro %}
