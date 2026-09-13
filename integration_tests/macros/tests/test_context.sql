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

  {# --- as_at accepts valid ISO date strings --- #}
  {% set good_date = jstark.try_resolve_as_at('2021-10-01') %}
  {% do jstark_assert_equal(results, 'try_resolve_as_at good date ok', good_date['ok'], true) %}
  {% do jstark_assert_equal(
      results, 'try_resolve_as_at good date value',
      good_date['date'], d(2021, 10, 1)
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
  {% set bad_dow = jstark.try_weekday_index('') %}
  {% do jstark_assert_equal(results, 'try_weekday_index empty ok', bad_dow['ok'], false) %}

  {# --- first_day_of_week none must become Monday --- #}
  {% set default_dow = jstark.try_weekday_index(none) %}
  {% do jstark_assert_equal(results, 'try_weekday_index none ok', default_dow['ok'], true) %}
  {% do jstark_assert_equal(results, 'try_weekday_index none index', default_dow['index'], 0) %}

{% endmacro %}
