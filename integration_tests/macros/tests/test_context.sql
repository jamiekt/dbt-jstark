{% macro jstark_test_context(results) %}

  {% set d = modules.datetime.date %}

  {# --- canonical columns: the full set, in a fixed order --- #}
  {% do jstark_assert_equal(
      results, 'canonical_columns()',
      jstark.canonical_columns(),
      ['event_timestamp', 'basket', 'order_id', 'store', 'channel', 'customer',
       'product', 'quantity', 'net_spend', 'gross_spend', 'discount',
       'cuisine', 'recipe', 'allergen']
  ) %}

  {# --- an empty column_map maps every canonical name to itself --- #}
  {% set cols = jstark.resolve_columns({}) %}
  {% do jstark_assert_equal(
      results, 'resolve_columns({}).gross_spend', cols['gross_spend'], 'gross_spend'
  ) %}
  {% do jstark_assert_equal(
      results, 'resolve_columns({}) is complete',
      cols | length, jstark.canonical_columns() | length
  ) %}

  {# --- a mapped name is substituted, unmapped names are untouched --- #}
  {% set mapped = jstark.resolve_columns(
      {'gross_spend': 'sales_value', 'event_timestamp': 'txn_ts'}
  ) %}
  {% do jstark_assert_equal(
      results, 'column_map substitutes gross_spend',
      mapped['gross_spend'], 'sales_value'
  ) %}
  {% do jstark_assert_equal(
      results, 'column_map substitutes event_timestamp',
      mapped['event_timestamp'], 'txn_ts'
  ) %}
  {% do jstark_assert_equal(
      results, 'column_map leaves others alone', mapped['quantity'], 'quantity'
  ) %}

  {# --- an unknown key is a typo, not a new column --- #}
  {% set bad = jstark.try_resolve_columns({'grosspend': 'sales_value'}) %}
  {% do jstark_assert_equal(results, 'try_resolve_columns bad key ok', bad['ok'], false) %}
  {% do jstark_assert_equal(
      results, 'try_resolve_columns bad key error',
      bad['error'],
      jstark.error_message(
          jstark.error_codes()['unknown_column_map_key'],
          "'grosspend' is not a jstark input column; expected one of "
          ~ (jstark.canonical_columns() | join(', '))
      )
  ) %}

  {# --- date literals --- #}
  {% do jstark_assert_equal(
      results, 'date_literal', jstark.date_literal(d(2021, 10, 1)),
      "date '2021-10-01'"
  ) %}

  {# --- as_at precedence: an explicit argument always wins --- #}
  {% do jstark_assert_equal(
      results, 'resolve_as_at(explicit date)',
      jstark.resolve_as_at(d(2022, 1, 1)), d(2022, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'resolve_as_at(explicit string)',
      jstark.resolve_as_at('2022-01-01'), d(2022, 1, 1)
  ) %}

  {# --- as_at rejects malformed date strings --- #}
  {% set bad_date = jstark.try_resolve_as_at('22-01-01') %}
  {% do jstark_assert_equal(results, 'try_resolve_as_at bad date ok', bad_date['ok'], false) %}
  {% do jstark_assert_equal(
      results, 'try_resolve_as_at bad date error',
      bad_date['error'],
      jstark.error_message(
          jstark.error_codes()['as_at_is_not_a_date'],
          "'22-01-01' is not a valid ISO date; expected format YYYY-MM-DD"
      )
  ) %}

  {# --- as_at precedence: the argument, then the var, then the run date --- #}
  {# `dbt run-operation` does pass --vars, so this rung is reachable, but which
     branch below runs depends on how the suite was invoked. Both branches make
     the same number of assertions so the printed total does not move.

     .github/workflows/build.yml runs the suite twice, once plain and once with
     --vars '{jstark_as_at: 2021-10-01}', so CI exercises both branches. Run it
     that way locally to check the var branch:

       dbt run-operation jstark_test_suite --profiles-dir . \
         --vars '{jstark_as_at: 2021-10-01}'

     The expected date is rebuilt from the raw var string here rather than by
     calling jstark.as_date on it, which is what the implementation does.

     The run-date branch is also the only assertion that the run_date rung is
     reached at all. resolve_as_at turns that rung into the warning covered by
     integration_tests/check_as_at_warning.sh; here it is only the 'source'
     value that is checked. #}
  {% set raw_var = var('jstark_as_at', none) %}
  {% set from_nothing = jstark.try_resolve_as_at(none) %}
  {% if raw_var is none %}
    {% do jstark_assert_equal(
        results, 'as_at falls through to the run date when no var is set',
        from_nothing['source'], 'run_date'
    ) %}
    {% do jstark_assert_true(
        results, 'the run-date rung still yields a date',
        from_nothing['date'] is not none
    ) %}
  {% else %}
    {% do jstark_assert_equal(
        results, 'as_at comes from the var when one is set',
        from_nothing['source'], 'var'
    ) %}
    {% do jstark_assert_equal(
        results, 'the var rung parses the var into its date',
        from_nothing['date'],
        d((raw_var | string)[0:4] | int, (raw_var | string)[5:7] | int,
          (raw_var | string)[8:10] | int)
    ) %}
  {% endif %}
  {#- and the argument still wins over the var, whichever way this was run -#}
  {% do jstark_assert_equal(
      results, 'the as_at argument outranks the var',
      jstark.try_resolve_as_at('2019-03-04')['source'], 'argument'
  ) %}
  {% do jstark_assert_equal(
      results, 'the as_at argument outranks the var: date',
      jstark.try_resolve_as_at('2019-03-04')['date'], d(2019, 3, 4)
  ) %}

  {# --- as_at accepts valid ISO date strings --- #}
  {% set good_date = jstark.try_resolve_as_at('2021-10-01') %}
  {% do jstark_assert_equal(results, 'try_resolve_as_at good date ok', good_date['ok'], true) %}
  {% do jstark_assert_equal(
      results, 'try_resolve_as_at good date value',
      good_date['date'], d(2021, 10, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'try_resolve_as_at good date source',
      good_date['source'], 'argument'
  ) %}

  {# --- as_at rejects impossible dates (shape-valid but calendar-invalid) --- #}
  {% set bad_month = jstark.try_resolve_as_at('2021-13-45') %}
  {% do jstark_assert_equal(results, 'try_resolve_as_at invalid month ok', bad_month['ok'], false) %}
  {% do jstark_assert_true(
      results, 'try_resolve_as_at invalid month contains code',
      'as_at_is_not_a_date' in bad_month['error']
  ) %}

  {# --- as_at rejects non-existent days in leap year edge cases --- #}
  {% set bad_day = jstark.try_resolve_as_at('2021-02-30') %}
  {% do jstark_assert_equal(results, 'try_resolve_as_at invalid day ok', bad_day['ok'], false) %}
  {% do jstark_assert_true(
      results, 'try_resolve_as_at invalid day contains code',
      'as_at_is_not_a_date' in bad_day['error']
  ) %}

  {# --- as_at accepts valid leap day (Feb 29 in a leap year) --- #}
  {% set leap_day = jstark.try_resolve_as_at('2020-02-29') %}
  {% do jstark_assert_equal(results, 'try_resolve_as_at leap day ok', leap_day['ok'], true) %}
  {% do jstark_assert_equal(
      results, 'try_resolve_as_at leap day value',
      leap_day['date'], d(2020, 2, 29)
  ) %}

  {# --- as_at rejects non-string non-date inputs like integers --- #}
  {% set bad_type = jstark.try_resolve_as_at(20220101) %}
  {% do jstark_assert_equal(results, 'try_resolve_as_at int input ok', bad_type['ok'], false) %}
  {% do jstark_assert_true(
      results, 'try_resolve_as_at int input contains code',
      'as_at_is_not_a_date' in bad_type['error']
  ) %}

  {# --- column_map rejects empty string values --- #}
  {% set bad_value = jstark.try_resolve_columns({'gross_spend': ''}) %}
  {% do jstark_assert_equal(results, 'try_resolve_columns empty value ok', bad_value['ok'], false) %}
  {% do jstark_assert_equal(
      results, 'try_resolve_columns empty value error',
      bad_value['error'],
      jstark.error_message(
          jstark.error_codes()['invalid_column_map_value'],
          "column_map['gross_spend'] must be a non-empty string, got ''"
      )
  ) %}

  {# --- column_map rejects whitespace-only values --- #}
  {% set bad_ws_value = jstark.try_resolve_columns({'gross_spend': '   '}) %}
  {% do jstark_assert_equal(results, 'try_resolve_columns whitespace value ok', bad_ws_value['ok'], false) %}
  {% do jstark_assert_true(
      results, 'try_resolve_columns whitespace value error has code',
      'invalid_column_map_value' in bad_ws_value['error']
  ) %}

  {# --- group_by takes bare column names, and each one only once --- #}
  {#- unlike a column_map value, a group_by entry is re-emitted by name against
      the base CTE, so an expression cannot resolve there; before this
      validation existed group_by=["date_trunc('month', event_timestamp)"] gave
      a raw Binder Error naming a column the caller never mentioned -#}
  {% do jstark_assert_equal(
      results, 'group_by accepts bare identifiers',
      jstark.try_resolve_group_by(['customer', 'store_id', '_internal']),
      {'ok': true, 'error': none,
       'columns': ['customer', 'store_id', '_internal']}
  ) %}
  {% do jstark_assert_equal(
      results, 'group_by accepts none',
      jstark.try_resolve_group_by(none),
      {'ok': true, 'error': none, 'columns': []}
  ) %}

  {% set expr_group_by = jstark.try_resolve_group_by(
      ["date_trunc('month', event_timestamp)"]
  ) %}
  {% do jstark_assert_equal(
      results, 'group_by rejects an expression', expr_group_by['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, 'group_by expression error', expr_group_by['error'],
      "jstark: invalid_group_by: group_by entry 'date_trunc('month', "
      ~ "event_timestamp)' is not a column name. group_by takes bare column "
      ~ 'names, not expressions: compute a derived grouping column in the SQL '
      ~ 'you pass as `input` and name that column here'
  ) %}
  {% do jstark_assert_equal(
      results, 'group_by rejects a quoted identifier',
      jstark.try_resolve_group_by(['"customer"'])['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, 'group_by rejects a dotted reference',
      jstark.try_resolve_group_by(['t.customer'])['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, 'group_by rejects a non-string entry',
      jstark.try_resolve_group_by([3])['ok'], false
  ) %}

  {% set repeat_group_by = jstark.try_resolve_group_by(['customer', 'customer']) %}
  {% do jstark_assert_equal(
      results, 'group_by rejects a repeat', repeat_group_by['ok'], false
  ) %}
  {% do jstark_assert_equal(
      results, 'group_by repeat error', repeat_group_by['error'],
      "jstark: duplicate_column_name: group_by asks for the column 'customer' "
      ~ 'more than once (entries customer and customer), which would emit two '
      ~ 'grouping columns with one name'
  ) %}
  {#- case-folded, because an unquoted identifier is case-insensitive on every
      warehouse this package targets -#}
  {% do jstark_assert_equal(
      results, 'group_by rejects a repeat differing only in case',
      jstark.try_resolve_group_by(['customer', 'CUSTOMER'])['ok'], false
  ) %}

  {# --- the context stitches period, window and columns together --- #}
  {% set ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), d(2022, 1, 1), 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.period.mnemonic', ctx['period']['mnemonic'], '3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.start_date', ctx['start_date'], d(2021, 10, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.end_date', ctx['end_date'], d(2021, 12, 31)
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.window', ctx['window'],
      jstark.to_date('event_timestamp')
      ~ " between date '2021-10-01' and date '2021-12-31'"
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.cols passes through', ctx['cols']['gross_spend'], 'gross_spend'
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.first_day_of_week', ctx['first_day_of_week'], 'Monday'
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.use_absolute_periods', ctx['use_absolute_periods'], false
  ) %}
  {% do jstark_assert_equal(results, 'ctx.cuisines', ctx['cuisines'], []) %}

  {# --- the window follows a remapped timestamp column --- #}
  {% set remapped_ctx = jstark.feature_context(
      jstark.parse_feature_period('0d0'), d(2022, 1, 1), 'Monday', false, mapped, []
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.window honours column_map', remapped_ctx['window'],
      jstark.to_date('txn_ts')
      ~ " between date '2022-01-01' and date '2022-01-01'"
  ) %}

  {# --- first_day_of_week defaults to Monday --- #}
  {% set default_dow_ctx = jstark.feature_context(
      jstark.parse_feature_period('0w0'), d(2022, 1, 1), none, false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx.first_day_of_week defaults',
      default_dow_ctx['first_day_of_week'], 'Monday'
  ) %}
  {% do jstark_assert_equal(
      results, 'ctx bounds use the default first_day_of_week',
      default_dow_ctx['start_date'], d(2021, 12, 27)
  ) %}

  {# --- first_day_of_week empty string must fail (not become Monday) --- #}
  {# NOTE: The end-to-end raise of feature_context(..., first_day_of_week='', ...)
     is verified live but cannot be asserted in-sandbox because Jinja has no try/except.
     This assertion on try_weekday_index('') is the proxy: it confirms the lower-level
     validation works. What connects this proxy to the full behaviour is feature_context's
     eager jstark.weekday_index(day_of_week) call, which means removing that call would
     expose the gap. If that call is removed, the suite will not catch it, so this
     comment serves as a record of that known limitation. #}
  {% set bad_dow = jstark.try_weekday_index('') %}
  {% do jstark_assert_equal(results, 'try_weekday_index empty ok', bad_dow['ok'], false) %}

  {# --- first_day_of_week none must become Monday --- #}
  {% set default_dow = jstark.try_weekday_index(none) %}
  {% do jstark_assert_equal(results, 'try_weekday_index none ok', default_dow['ok'], true) %}
  {% do jstark_assert_equal(results, 'try_weekday_index none index', default_dow['index'], 0) %}

{% endmacro %}
