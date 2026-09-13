{#
  Named compile-time errors.

  Every error jstark raises goes through raise_error so that the message
  format is uniform and so that L1 tests can assert on the exact text
  without needing try/except (which Jinja does not have).
#}

{% macro error_codes() %}
  {{ return({
      'mnemonic_is_invalid': 'feature_period_mnemonic_is_invalid',
      'end_greater_than_start': 'feature_period_end_greater_than_start',
      'feature_not_found': 'feature_not_found',
      'unknown_column_map_key': 'unknown_column_map_key',
      'invalid_first_day_of_week': 'invalid_first_day_of_week',
      'unknown_aggregator': 'unknown_aggregator'
  }) }}
{% endmacro %}


{% macro error_message(code, detail) %}
  {{ return('jstark: ' ~ code ~ ': ' ~ detail) }}
{% endmacro %}


{% macro raise_error(code, detail) %}
  {{ exceptions.raise_compiler_error(jstark.error_message(code, detail)) }}
{% endmacro %}
