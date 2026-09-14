{% macro jstark_test_harness(results) %}

  {# jstark_assert_equal records a passing entry on a match #}
  {% set probe = [] %}
  {% do jstark_assert_equal(probe, 'probe', 1, 1) %}
  {% do jstark_assert_equal(
      results, 'assert_equal records a passing entry on a match: length',
      probe | length, 1
  ) %}
  {% do jstark_assert_true(
      results, 'assert_equal records a passing entry on a match: ok flag',
      probe[0]['ok']
  ) %}

  {# jstark_assert_equal records the failure message wording on a mismatch #}
  {% set probe2 = [] %}
  {% do jstark_assert_equal(probe2, 'probe2', 1, 2) %}
  {% do jstark_assert_equal(results, 'assert_equal records a mismatch', probe2 | length, 1) %}
  {% do jstark_assert_equal(
      results, 'assert_equal message format: ok flag',
      probe2[0]['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results,
      'assert_equal message format',
      probe2[0]['message'],
      'probe2: expected 2 but got 1'
  ) %}

  {# jstark_assert_true records both calls but fails only the falsey one #}
  {% set probe3 = [] %}
  {% do jstark_assert_true(probe3, 'probe3', true) %}
  {% do jstark_assert_true(probe3, 'probe3', false) %}
  {% do jstark_assert_equal(
      results, 'assert_true records both calls but fails only the falsey one: length',
      probe3 | length, 2
  ) %}
  {% do jstark_assert_equal(
      results, 'assert_true records both calls but fails only the falsey one: failure count',
      probe3 | rejectattr('ok') | list | length, 1
  ) %}

  {# jstark_assert_contains fails an empty needle instead of passing vacuously #}
  {% set probe4 = [] %}
  {% do jstark_assert_contains(probe4, 'probe4', 'a haystack', '') %}
  {% do jstark_assert_equal(
      results, 'assert_contains records the empty-needle call', probe4 | length, 1
  ) %}
  {% do jstark_assert_equal(
      results, 'assert_contains fails an empty needle', probe4[0]['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, 'assert_contains empty-needle message', probe4[0]['message'],
      'probe4: the needle is empty, so this assertion would pass against any '
      ~ 'haystack; assert on a real value'
  ) %}
  {#- the paired positive: a non-empty needle that is present still passes, so
      the guard above cannot be satisfied by breaking the assertion outright -#}
  {% set probe5 = [] %}
  {% do jstark_assert_contains(probe5, 'probe5', 'a haystack', 'hay') %}
  {% do jstark_assert_equal(
      results, 'assert_contains still passes a needle that is present',
      probe5[0]['ok'], true
  ) %}

  {#- a none haystack fails as an assertion rather than raising a TypeError out
      of Jinja, which would abort the suite and hide the failures collected
      before it. The common source is result['error'] on a try_ result that
      unexpectedly came back ok. -#}
  {% set probe6 = [] %}
  {% do jstark_assert_contains(probe6, 'probe6', none, 'hay') %}
  {% do jstark_assert_equal(
      results, 'assert_contains records the none-haystack call', probe6 | length, 1
  ) %}
  {% do jstark_assert_equal(
      results, 'assert_contains fails a none haystack', probe6[0]['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, 'assert_contains none-haystack message', probe6[0]['message'],
      'probe6: the haystack is not a string but None, so it cannot contain <hay>'
  ) %}

  {# error codes are stable #}
  {#- every code is pinned individually, by name: an error code is user-facing
      surface, and a renamed one should break a test rather than silently change
      what a caller greps for -#}
  {% set codes = jstark.error_codes() %}
  {% do jstark_assert_equal(
      results, 'code: mnemonic_is_invalid',
      codes['mnemonic_is_invalid'], 'feature_period_mnemonic_is_invalid'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: end_greater_than_start',
      codes['end_greater_than_start'], 'feature_period_end_greater_than_start'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: feature_not_found',
      codes['feature_not_found'], 'feature_not_found'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: invalid_first_day_of_week',
      codes['invalid_first_day_of_week'], 'invalid_first_day_of_week'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: unknown_aggregator',
      codes['unknown_aggregator'], 'unknown_aggregator'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: as_at_is_not_a_date',
      codes['as_at_is_not_a_date'], 'as_at_is_not_a_date'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: unknown_generator',
      codes['unknown_generator'], 'unknown_generator'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: duplicate_column_name',
      codes['duplicate_column_name'], 'duplicate_column_name'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: invalid_cuisine',
      codes['invalid_cuisine'], 'invalid_cuisine'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: invalid_group_by',
      codes['invalid_group_by'], 'invalid_group_by'
  ) %}
  {% do jstark_assert_equal(
      results, 'code: unsupported_adapter',
      codes['unsupported_adapter'], 'unsupported_adapter'
  ) %}
  {#- the count as well as the names: a code added without an assertion here
      leaves the newest, least-exercised error message unpinned -#}
  {% do jstark_assert_equal(
      results, 'every error code is pinned above', codes | length, 11
  ) %}

  {# error_message formats consistently #}
  {% do jstark_assert_equal(
      results, 'error_message format',
      jstark.error_message('feature_not_found', "['Nope'] is not a known feature stem"),
      "jstark: feature_not_found: ['Nope'] is not a known feature stem"
  ) %}

{% endmacro %}
