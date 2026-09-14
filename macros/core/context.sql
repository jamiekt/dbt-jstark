{#
  Input columns, as_at resolution, and the per-period feature context.

  Feature definitions never name a raw column; they read ctx.cols['gross_spend'],
  so the set of input columns is declared in one place (canonical_columns) rather
  than scattered through the definitions.

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


{% macro resolve_columns() %}
  {#
    The input columns a feature definition may read, as a dict.

    Every canonical name maps to itself. The indirection is not a no-op for
    the reader: it is the single place that names the input columns, so a
    definition asks for ctx.cols['gross_spend'] rather than hard-coding the
    string, and adding an input column is one edit here plus one in
    canonical_columns.

    Renaming is the caller's job, done in the SQL passed as `input` — see
    README section 6. jstark's own FeatureGenerator works the same way: it
    takes a DataFrame whose columns are already named as it expects.
  #}
  {% set cols = {} %}
  {% for name in jstark.canonical_columns() %}
    {% do cols.update({name: name}) %}
  {% endfor %}
  {{ return(cols) }}
{% endmacro %}


{% macro try_resolve_group_by(group_by) %}
  {#
    Validate the grouping columns.

    Each entry is emitted twice — once in the base CTE's select list and once in
    its GROUP BY — and then re-emitted in the final projection against the CTE
    (macros/core/generate_features.sql). That last step is what rules out
    expressions: `date_trunc('month', event_timestamp)` selects fine in the base
    CTE but is nameless there, so re-emitting the same text against the CTE
    looks for a raw column the CTE does not have. Its comma also splits the
    select list in two. So an entry must be a bare identifier, and a caller who
    wants a derived grouping column computes it in the SQL passed as `input` and
    names the resulting column here.

    A repeat is rejected rather than deduplicated, for the reason in
    try_parse_feature_periods: two columns cannot share one name, and DuckDB
    silently renames the second to <name>_1. The comparison folds case because
    an unquoted identifier is case-insensitive on every warehouse targeted here,
    so `['customer', 'CUSTOMER']` is the same column twice.

    Returns: {'ok', 'error', 'columns'}.
  #}
  {% set entries = group_by if group_by else [] %}
  {% set columns = [] %}
  {% set seen = {} %}
  {% set problems = [] %}

  {% for entry in entries %}
    {% if not (entry is string
               and modules.re.match('^[A-Za-z_][A-Za-z0-9_]*$', entry)) %}
      {% do problems.append(jstark.error_message(
          jstark.error_codes()['invalid_group_by'],
          "group_by entry '" ~ (entry | string) ~ "' is not a column name. "
          ~ 'group_by takes bare column names, not expressions: compute a '
          ~ 'derived grouping column in the SQL you pass as `input` and name '
          ~ 'that column here'
      )) %}
    {% elif (entry | lower) in seen %}
      {% do problems.append(jstark.error_message(
          jstark.error_codes()['duplicate_column_name'],
          "group_by asks for the column '" ~ entry ~ "' more than once (entries "
          ~ seen[entry | lower] ~ ' and ' ~ entry
          ~ '), which would emit two grouping columns with one name'
      )) %}
    {% else %}
      {% do seen.update({(entry | lower): entry}) %}
      {% do columns.append(entry) %}
    {% endif %}
  {% endfor %}

  {% if problems | length > 0 %}
    {{ return({'ok': false, 'error': problems[0], 'columns': none}) }}
  {% endif %}
  {{ return({'ok': true, 'error': none, 'columns': columns}) }}
{% endmacro %}


{% macro resolve_group_by(group_by) %}
  {% set result = jstark.try_resolve_group_by(group_by) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['columns']) }}
{% endmacro %}


{% macro try_as_at_value(value, input_name) %}
  {#
    Validate a single as_at value (string, date, datetime, or bad input).

    Both the argument rung and the var rung of try_resolve_as_at depend on
    this validator, so the next person understands why it is separate rather
    than inline. This ensures that calendar validity checking, type gating,
    and error messages stay in sync across both precedence levels.

    input_name: the name the user typed for this input ("as_at" or
            "jstark_as_at"), quoted back at them in error details so they know
            which one to correct. Deliberately NOT called `source`: the 'source'
            key that try_resolve_as_at returns means something different — which
            precedence rung won ('argument' / 'var' / 'run_date').

    Returns: {'ok', 'error', 'date'} where 'date' is a datetime.date object
             if ok is true, or none if ok is false.
  #}
  {% if value is string %}
    {# Shape check: YYYY-MM-DD #}
    {% if not modules.re.match('^\\d{4}-\\d{2}-\\d{2}$', value) %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['as_at_is_not_a_date'],
              "'" ~ value ~ "' is not a valid ISO date; expected format YYYY-MM-DD"
          ),
          'date': none
      }) }}
    {% endif %}
    {# Range check: extract and validate month and day #}
    {% set parts = modules.re.findall('\\d+', value) %}
    {% set year = parts[0] | int %}
    {% set month = parts[1] | int %}
    {% set day = parts[2] | int %}
    {% if month < 1 or month > 12 %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['as_at_is_not_a_date'],
              "'" ~ value ~ "' is not a valid ISO date; month must be in 1..12"
          ),
          'date': none
      }) }}
    {% endif %}
    {% set max_day = jstark.days_in_month(year, month) %}
    {% if day < 1 or day > max_day %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['as_at_is_not_a_date'],
              "'" ~ value ~ "' is not a valid ISO date; day must be in 1.." ~ max_day
          ),
          'date': none
      }) }}
    {% endif %}
  {% elif value is number or value is mapping or (value is iterable and value is not string) %}
    {# Reject integers, lists, dicts, booleans, etc. Accept date/datetime objects. #}
    {{ return({
        'ok': false,
        'error': jstark.error_message(
            jstark.error_codes()['as_at_is_not_a_date'],
            input_name ~ " must be a date, datetime, or ISO date string (YYYY-MM-DD)"
        ),
        'date': none
    }) }}
  {% endif %}
  {{ return({
      'ok': true,
      'error': none,
      'date': jstark.as_date(value)
  }) }}
{% endmacro %}


{% macro try_resolve_as_at(as_at) %}
  {#
    Precedence: the argument, then the jstark_as_at var, then the run date.

    Falling back to the run date makes features non-deterministic between
    runs, which is almost never what someone wants in a scheduled job.

    Returns: {'ok', 'error', 'date', 'source'} where:
      - 'ok': true if validation passed, false otherwise
      - 'error': error message if ok is false, none otherwise
      - 'date': datetime.date object (none if error)
      - 'source': 'argument' if from as_at arg, 'var' if from jstark_as_at var,
                  'run_date' if fell back to run_started_at
  #}

  {% if as_at is not none %}
    {% set result = jstark.try_as_at_value(as_at, 'as_at') %}
    {% if not result['ok'] %}
      {{ return(result) }}
    {% endif %}
    {{ return({
        'ok': true,
        'error': none,
        'date': result['date'],
        'source': 'argument'
    }) }}
  {% endif %}

  {% set from_var = var('jstark_as_at', none) %}
  {% if from_var is not none %}
    {% set result = jstark.try_as_at_value(from_var, 'jstark_as_at') %}
    {% if not result['ok'] %}
      {{ return(result) }}
    {% endif %}
    {{ return({
        'ok': true,
        'error': none,
        'date': result['date'],
        'source': 'var'
    }) }}
  {% endif %}

  {{ return({
      'ok': true,
      'error': none,
      'date': jstark.as_date(run_started_at),
      'source': 'run_date'
  }) }}
{% endmacro %}


{% macro resolve_as_at(as_at) %}
  {% set result = jstark.try_resolve_as_at(as_at) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}

  {#
    Warn only on the run-date rung. No L1 assertion can reach this guard —
    Jinja cannot observe that exceptions.warn was called — so it is covered
    instead by integration_tests/check_as_at_warning.sh, which runs
    --warn-error and asserts on the exit code. This guard was once
    accidentally dead for two commits without any test noticing; if you edit
    it, run that script.
  #}
  {% if result['source'] == 'run_date' %}
    {% do exceptions.warn(
        'jstark: no as_at was supplied, so features are being generated as at the '
        ~ 'run date. Pass as_at=... or set the jstark_as_at var to make results '
        ~ 'reproducible.'
    ) %}
  {% endif %}

  {{ return(result['date']) }}
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
