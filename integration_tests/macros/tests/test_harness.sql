{% macro jstark_test_harness(failures) %}

  {# jstark_assert_equal records nothing when values match #}
  {% set probe = [] %}
  {% do jstark_assert_equal(probe, 'probe', 1, 1) %}
  {% do jstark_assert_equal(failures, 'assert_equal is silent on a match', probe | length, 0) %}

  {# jstark_assert_equal records exactly one message when values differ #}
  {% set probe2 = [] %}
  {% do jstark_assert_equal(probe2, 'probe2', 1, 2) %}
  {% do jstark_assert_equal(failures, 'assert_equal records a mismatch', probe2 | length, 1) %}
  {% do jstark_assert_equal(
      failures,
      'assert_equal message format',
      probe2[0],
      'probe2: expected 2 but got 1'
  ) %}

  {# jstark_assert_true records only for falsey values #}
  {% set probe3 = [] %}
  {% do jstark_assert_true(probe3, 'probe3', true) %}
  {% do jstark_assert_true(probe3, 'probe3', false) %}
  {% do jstark_assert_equal(failures, 'assert_true records only falsey', probe3 | length, 1) %}

  {# error codes are stable #}
  {% set codes = jstark.error_codes() %}
  {% do jstark_assert_equal(
      failures, 'code: mnemonic_is_invalid',
      codes['mnemonic_is_invalid'], 'feature_period_mnemonic_is_invalid'
  ) %}
  {% do jstark_assert_equal(
      failures, 'code: end_greater_than_start',
      codes['end_greater_than_start'], 'feature_period_end_greater_than_start'
  ) %}
  {% do jstark_assert_equal(
      failures, 'code: feature_not_found',
      codes['feature_not_found'], 'feature_not_found'
  ) %}
  {% do jstark_assert_equal(
      failures, 'code: unknown_column_map_key',
      codes['unknown_column_map_key'], 'unknown_column_map_key'
  ) %}
  {% do jstark_assert_equal(
      failures, 'code: invalid_first_day_of_week',
      codes['invalid_first_day_of_week'], 'invalid_first_day_of_week'
  ) %}

  {# error_message formats consistently #}
  {% do jstark_assert_equal(
      failures, 'error_message format',
      jstark.error_message('feature_not_found', "['Nope'] is not a known feature stem"),
      "jstark: feature_not_found: ['Nope'] is not a known feature stem"
  ) %}

{% endmacro %}
