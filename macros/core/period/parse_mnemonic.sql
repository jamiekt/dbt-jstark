{#
  Feature period parsing.

  A feature period is a window expressed in whole units, counted backwards
  from as_at: '3m1' means "from 3 months ago to 1 month ago inclusive".

  Everything downstream works with the dict this produces:
    {'uom': 'm', 'start': 3, 'end': 1, 'mnemonic': '3m1', 'number_of_periods': 3}

  Parsing is split so that failures are inspectable: try_parse_feature_period
  reports, parse_feature_period raises. Jinja has no try/except, so this is
  the only way the error paths can be asserted on.
#}

{% macro feature_period(uom, start, end) %}
  {{ return({
      'uom': uom,
      'start': start,
      'end': end,
      'mnemonic': (start | string) ~ uom ~ (end | string),
      'number_of_periods': start - end + 1
  }) }}
{% endmacro %}


{% macro try_parse_feature_period(value) %}

  {#- already a parsed period? pass it through -#}
  {% if value is mapping and 'mnemonic' in value %}
    {{ return({'ok': true, 'error': none, 'period': value}) }}
  {% endif %}

  {% if value is mapping %}
    {% set uom = value.get('unit') %}
    {% set start = value.get('start', 0) %}
    {% set end = value.get('end', 0) %}
    {% if uom not in ['d', 'w', 'm', 'q', 'y'] or start < 0 or end < 0 %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['mnemonic_is_invalid'],
              (value | string) ~ ' is not a valid feature period; expected keys '
              ~ "unit (one of d, w, m, q, y), start and end, all non-negative"
          ),
          'period': none
      }) }}
    {% endif %}
  {% else %}
    {% set matches = modules.re.findall(
        '^(\\d*)([dwmqy])(\\d*)$', value | string
    ) %}
    {% if matches | length == 0 %}
      {{ return({
          'ok': false,
          'error': jstark.error_message(
              jstark.error_codes()['mnemonic_is_invalid'],
              "'" ~ (value | string) ~ "' is not a valid feature period mnemonic; "
              ~ 'expected <start><d|w|m|q|y><end>, for example 52w0'
          ),
          'period': none
      }) }}
    {% endif %}
    {#- findall with three groups yields one tuple: (start, uom, end).
        An omitted count means zero, so 'm' is the current month. -#}
    {% set groups = matches[0] %}
    {% set start = (groups[0] | int) if groups[0] else 0 %}
    {% set uom = groups[1] %}
    {% set end = (groups[2] | int) if groups[2] else 0 %}
  {% endif %}

  {% if end > start %}
    {{ return({
        'ok': false,
        'error': jstark.error_message(
            jstark.error_codes()['end_greater_than_start'],
            'feature period end (' ~ end ~ ') is greater than start (' ~ start ~ ')'
        ),
        'period': none
    }) }}
  {% endif %}

  {{ return({
      'ok': true, 'error': none, 'period': jstark.feature_period(uom, start, end)
  }) }}

{% endmacro %}


{% macro parse_feature_period(value) %}
  {% set result = jstark.try_parse_feature_period(value) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['period']) }}
{% endmacro %}


{% macro parse_feature_periods(value) %}
  {% if value is none or (value is not string and value | length == 0) %}
    {{ return([jstark.parse_feature_period('52w0')]) }}
  {% endif %}
  {% set values = [value] if (value is string or value is mapping) else value %}
  {% set periods = [] %}
  {% for item in values %}
    {% do periods.append(jstark.parse_feature_period(item)) %}
  {% endfor %}
  {{ return(periods) }}
{% endmacro %}
