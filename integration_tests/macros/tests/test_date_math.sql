{% macro jstark_test_date_math(results) %}

  {% set d = modules.datetime.date %}

  {# --- as_date accepts dates, date strings and timestamp strings --- #}
  {% do jstark_assert_equal(
      results, 'as_date(date)', jstark.as_date(d(2022, 1, 1)), d(2022, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'as_date(iso string)', jstark.as_date('2022-01-01'), d(2022, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'as_date(timestamp string)',
      jstark.as_date('2022-01-01 09:30:00'), d(2022, 1, 1)
  ) %}

  {# --- date_string zero-pads --- #}
  {% do jstark_assert_equal(
      results, 'date_string', jstark.date_string(d(2021, 2, 3)), '2021-02-03'
  ) %}

  {# --- leap years --- #}
  {% set leap_cases = [
      [2020, true], [2021, false], [2000, true], [1900, false], [2024, true]
  ] %}
  {% for case in leap_cases %}
    {% do jstark_assert_equal(
        results, 'is_leap_year(' ~ case[0] ~ ')',
        jstark.is_leap_year(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- days_in_month --- #}
  {% set dim_cases = [
      [2021, 1, 31], [2021, 2, 28], [2020, 2, 29], [2000, 2, 29], [1900, 2, 28],
      [2021, 4, 30], [2021, 12, 31]
  ] %}
  {% for case in dim_cases %}
    {% do jstark_assert_equal(
        results, 'days_in_month(' ~ case[0] ~ ',' ~ case[1] ~ ')',
        jstark.days_in_month(case[0], case[1]), case[2]
    ) %}
  {% endfor %}

  {# --- add_days / add_weeks, including negatives across year boundaries --- #}
  {% do jstark_assert_equal(
      results, 'add_days(2022-01-01, -1)',
      jstark.add_days(d(2022, 1, 1), -1), d(2021, 12, 31)
  ) %}
  {% do jstark_assert_equal(
      results, 'add_days(2022-01-01, 0)',
      jstark.add_days(d(2022, 1, 1), 0), d(2022, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'add_weeks(2022-01-01, -1)',
      jstark.add_weeks(d(2022, 1, 1), -1), d(2021, 12, 25)
  ) %}
  {% do jstark_assert_equal(
      results, 'add_weeks(2022-01-01, -52)',
      jstark.add_weeks(d(2022, 1, 1), -52), d(2021, 1, 2)
  ) %}

  {# --- add_months: pendulum-compatible end-of-month clamping --- #}
  {% set am_cases = [
      [d(2022, 3, 31), -1, d(2022, 2, 28)],
      [d(2020, 3, 31), -1, d(2020, 2, 29)],
      [d(2021, 1, 31), 1, d(2021, 2, 28)],
      [d(2022, 1, 1), -1, d(2021, 12, 1)],
      [d(2022, 1, 31), -12, d(2021, 1, 31)],
      [d(2022, 1, 15), 0, d(2022, 1, 15)],
      [d(2022, 5, 31), -3, d(2022, 2, 28)],
      [d(2022, 1, 1), -3, d(2021, 10, 1)],
      [d(2022, 1, 1), -12, d(2021, 1, 1)]
  ] %}
  {% for case in am_cases %}
    {% do jstark_assert_equal(
        results,
        'add_months(' ~ jstark.date_string(case[0]) ~ ', ' ~ case[1] ~ ')',
        jstark.add_months(case[0], case[1]), case[2]
    ) %}
  {% endfor %}

  {# --- month / quarter / year boundaries --- #}
  {% do jstark_assert_equal(
      results, 'first_date_in_month',
      jstark.first_date_in_month(d(2021, 2, 17)), d(2021, 2, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'last_date_in_month(feb 2020)',
      jstark.last_date_in_month(d(2020, 2, 17)), d(2020, 2, 29)
  ) %}
  {% set q_cases = [
      [d(2021, 1, 5), 1, d(2021, 1, 1), d(2021, 3, 31)],
      [d(2021, 6, 30), 2, d(2021, 4, 1), d(2021, 6, 30)],
      [d(2021, 8, 1), 3, d(2021, 7, 1), d(2021, 9, 30)],
      [d(2021, 11, 15), 4, d(2021, 10, 1), d(2021, 12, 31)]
  ] %}
  {% for case in q_cases %}
    {% do jstark_assert_equal(
        results, 'quarter_of(' ~ jstark.date_string(case[0]) ~ ')',
        jstark.quarter_of(case[0]), case[1]
    ) %}
    {% do jstark_assert_equal(
        results, 'first_date_in_quarter(' ~ jstark.date_string(case[0]) ~ ')',
        jstark.first_date_in_quarter(case[0]), case[2]
    ) %}
    {% do jstark_assert_equal(
        results, 'last_date_in_quarter(' ~ jstark.date_string(case[0]) ~ ')',
        jstark.last_date_in_quarter(case[0]), case[3]
    ) %}
  {% endfor %}
  {% do jstark_assert_equal(
      results, 'first_date_in_year',
      jstark.first_date_in_year(d(2021, 7, 4)), d(2021, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'last_date_in_year',
      jstark.last_date_in_year(d(2021, 7, 4)), d(2021, 12, 31)
  ) %}

  {# --- weekday_index, defaulting to Monday --- #}
  {% do jstark_assert_equal(
      results, 'weekday_index(none)', jstark.weekday_index(none), 0
  ) %}
  {% set wd_cases = [
      ['Monday', 0], ['Tuesday', 1], ['Wednesday', 2], ['Thursday', 3],
      ['Friday', 4], ['Saturday', 5], ['Sunday', 6]
  ] %}
  {% for case in wd_cases %}
    {% do jstark_assert_equal(
        results, 'weekday_index(' ~ case[0] ~ ')',
        jstark.weekday_index(case[0]), case[1]
    ) %}
  {% endfor %}

  {# --- weekday_index must only default when omitted, not on invalid values --- #}
  {% do jstark_assert_equal(
      results, "weekday_index('Monday') still returns 0",
      jstark.weekday_index('Monday'), 0
  ) %}

  {# --- week boundaries. 2022-01-01 is a Saturday. --- #}
  {% set wk_cases = [
      ['Monday', d(2021, 12, 27), d(2022, 1, 2)],
      ['Tuesday', d(2021, 12, 28), d(2022, 1, 3)],
      ['Wednesday', d(2021, 12, 29), d(2022, 1, 4)],
      ['Thursday', d(2021, 12, 30), d(2022, 1, 5)],
      ['Friday', d(2021, 12, 31), d(2022, 1, 6)],
      ['Saturday', d(2022, 1, 1), d(2022, 1, 7)],
      ['Sunday', d(2021, 12, 26), d(2022, 1, 1)]
  ] %}
  {% for case in wk_cases %}
    {% do jstark_assert_equal(
        results, 'first_date_in_week(2022-01-01, ' ~ case[0] ~ ')',
        jstark.first_date_in_week(d(2022, 1, 1), case[0]), case[1]
    ) %}
    {% do jstark_assert_equal(
        results, 'last_date_in_week(2022-01-01, ' ~ case[0] ~ ')',
        jstark.last_date_in_week(d(2022, 1, 1), case[0]), case[2]
    ) %}
  {% endfor %}

  {# --- min_date --- #}
  {% do jstark_assert_equal(
      results, 'min_date(a<b)', jstark.min_date(d(2021, 1, 1), d(2022, 1, 1)),
      d(2021, 1, 1)
  ) %}
  {% do jstark_assert_equal(
      results, 'min_date(a>b)', jstark.min_date(d(2022, 1, 1), d(2021, 1, 1)),
      d(2021, 1, 1)
  ) %}

{% endmacro %}
