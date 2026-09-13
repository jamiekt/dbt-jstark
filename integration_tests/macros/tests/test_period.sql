{% macro jstark_test_period(results) %}

  {% set d = modules.datetime.date %}

  {# --- mnemonic parsing --- #}
  {% set parse_cases = [
      ['3m1', 'm', 3, 1, '3m1', 3],
      ['52w0', 'w', 52, 0, '52w0', 53],
      ['0d0', 'd', 0, 0, '0d0', 1],
      ['4q4', 'q', 4, 4, '4q4', 1],
      ['1y1', 'y', 1, 1, '1y1', 1],
      ['12m0', 'm', 12, 0, '12m0', 13],
      ['m', 'm', 0, 0, '0m0', 1]
  ] %}
  {% for case in parse_cases %}
    {% set p = jstark.parse_feature_period(case[0]) %}
    {% do jstark_assert_equal(results, 'parse(' ~ case[0] ~ ').uom', p['uom'], case[1]) %}
    {% do jstark_assert_equal(results, 'parse(' ~ case[0] ~ ').start', p['start'], case[2]) %}
    {% do jstark_assert_equal(results, 'parse(' ~ case[0] ~ ').end', p['end'], case[3]) %}
    {% do jstark_assert_equal(
        results, 'parse(' ~ case[0] ~ ').mnemonic', p['mnemonic'], case[4]
    ) %}
    {% do jstark_assert_equal(
        results, 'parse(' ~ case[0] ~ ').number_of_periods',
        p['number_of_periods'], case[5]
    ) %}
  {% endfor %}

  {# --- dict form --- #}
  {% set from_dict = jstark.parse_feature_period({'unit': 'm', 'start': 3, 'end': 1}) %}
  {% do jstark_assert_equal(
      results, 'parse(dict).mnemonic', from_dict['mnemonic'], '3m1'
  ) %}

  {# --- an already-parsed period passes through unchanged --- #}
  {% do jstark_assert_equal(
      results, 'parse(period dict) is idempotent',
      jstark.parse_feature_period(from_dict)['mnemonic'], '3m1'
  ) %}

  {# --- invalid mnemonics report, not crash --- #}
  {% set bad_mnemonics = ['3x1', '3m1m', 'weekly', '', '3 m 1', '-1m0'] %}
  {% for bad in bad_mnemonics %}
    {% set result = jstark.try_parse_feature_period(bad) %}
    {% do jstark_assert_equal(
        results, "try_parse('" ~ bad ~ "').ok", result['ok'], false
    ) %}
    {% do jstark_assert_equal(
        results, "try_parse('" ~ bad ~ "').error",
        result['error'],
        jstark.error_message(
            jstark.error_codes()['mnemonic_is_invalid'],
            "'" ~ bad ~ "' is not a valid feature period mnemonic; "
            ~ 'expected <start><d|w|m|q|y><end>, for example 52w0'
        )
    ) %}
  {% endfor %}

  {# --- end may not be greater than start --- #}
  {% set reversed = jstark.try_parse_feature_period('1m3') %}
  {% do jstark_assert_equal(results, "try_parse('1m3').ok", reversed['ok'], false) %}
  {% do jstark_assert_equal(
      results, "try_parse('1m3').error",
      reversed['error'],
      jstark.error_message(
          jstark.error_codes()['end_greater_than_start'],
          'feature period end (3) is greater than start (1)'
      )
  ) %}

  {# --- parse_feature_periods defaulting and normalisation --- #}
  {% do jstark_assert_equal(
      results, 'parse_feature_periods(none) defaults to 52w0',
      jstark.parse_feature_periods(none) | map(attribute='mnemonic') | list,
      ['52w0']
  ) %}
  {% do jstark_assert_equal(
      results, 'parse_feature_periods([]) defaults to 52w0',
      jstark.parse_feature_periods([]) | map(attribute='mnemonic') | list,
      ['52w0']
  ) %}
  {% do jstark_assert_equal(
      results, 'parse_feature_periods(string) wraps',
      jstark.parse_feature_periods('3m1') | map(attribute='mnemonic') | list,
      ['3m1']
  ) %}
  {% do jstark_assert_equal(
      results, 'parse_feature_periods(list) preserves order',
      jstark.parse_feature_periods(['3m1', '0d0', {'unit': 'y', 'start': 1, 'end': 1}])
        | map(attribute='mnemonic') | list,
      ['3m1', '0d0', '1y1']
  ) %}

  {# --- period_bounds. Values cross-checked against jstark at 51d9083. --- #}
  {% set bound_cases = [
      ['3m1',  d(2022, 1, 1),  'Monday', d(2021, 10, 1), d(2021, 12, 31)],
      ['4q4',  d(2022, 1, 1),  'Monday', d(2021, 1, 1),  d(2021, 3, 31)],
      ['0m0',  d(2022, 1, 15), 'Monday', d(2022, 1, 1),  d(2022, 1, 15)],
      ['1m1',  d(2022, 3, 31), 'Monday', d(2022, 2, 1),  d(2022, 2, 28)],
      ['1m1',  d(2020, 3, 31), 'Monday', d(2020, 2, 1),  d(2020, 2, 29)],
      ['1w1',  d(2022, 1, 1),  'Monday', d(2021, 12, 20), d(2021, 12, 26)],
      ['0w0',  d(2022, 1, 1),  'Monday', d(2021, 12, 27), d(2022, 1, 1)],
      ['0w0',  d(2022, 1, 1),  'Sunday', d(2021, 12, 26), d(2022, 1, 1)],
      ['0d0',  d(2022, 1, 1),  'Monday', d(2022, 1, 1),  d(2022, 1, 1)],
      ['1d1',  d(2022, 1, 1),  'Monday', d(2021, 12, 31), d(2021, 12, 31)],
      ['1y1',  d(2022, 1, 1),  'Monday', d(2021, 1, 1),  d(2021, 12, 31)],
      ['0y0',  d(2022, 1, 1),  'Monday', d(2022, 1, 1),  d(2022, 1, 1)],
      ['0q0',  d(2022, 1, 1),  'Monday', d(2022, 1, 1),  d(2022, 1, 1)],
      ['52w0', d(2022, 1, 1),  'Monday', d(2020, 12, 28), d(2022, 1, 1)]
  ] %}
  {% for case in bound_cases %}
    {% set bounds = jstark.period_bounds(
        jstark.parse_feature_period(case[0]), case[1], case[2]
    ) %}
    {% set label = 'period_bounds(' ~ case[0] ~ ', ' ~ jstark.date_string(case[1])
                   ~ ', ' ~ case[2] ~ ')' %}
    {% do jstark_assert_equal(
        results, label ~ '.start_date', bounds['start_date'], case[3]
    ) %}
    {% do jstark_assert_equal(
        results, label ~ '.end_date', bounds['end_date'], case[4]
    ) %}
  {% endfor %}

  {# --- an unknown first_day_of_week is rejected --- #}
  {% set fdow = jstark.try_weekday_index('Funday') %}
  {% do jstark_assert_equal(results, "try_weekday_index('Funday').ok", fdow['ok'], false) %}

  {# --- try_weekday_index with empty string is rejected --- #}
  {% set fdow_empty = jstark.try_weekday_index('') %}
  {% do jstark_assert_equal(results, "try_weekday_index('').ok", fdow_empty['ok'], false) %}

  {# --- try_weekday_index with none defaults to Monday --- #}
  {% set fdow_none = jstark.try_weekday_index(none) %}
  {% do jstark_assert_equal(results, "try_weekday_index(none).ok", fdow_none['ok'], true) %}
  {% do jstark_assert_equal(results, "try_weekday_index(none).index", fdow_none['index'], 0) %}

{% endmacro %}
