{#
  Date arithmetic.

  jstark uses pendulum, which is not available in dbt's Jinja sandbox, so
  this reimplements the parts jstark depends on with modules.datetime only.
  The behaviour that matters most is pendulum's end-of-month clamping:
  2022-03-31 minus one month is 2022-02-28, not an invalid 2022-02-31.

  Dates are real datetime.date objects everywhere; they become strings only
  when a SQL literal is emitted.
#}

{% macro as_date(value) %}
  {% if value is string %}
    {#- tolerate '2022-01-01' and '2022-01-01 09:30:00' without
        relying on classmethods being reachable in the sandbox -#}
    {% set parts = modules.re.findall('\\d+', value) %}
    {{ return(modules.datetime.date(parts[0] | int, parts[1] | int, parts[2] | int)) }}
  {% endif %}
  {{ return(modules.datetime.date(value.year, value.month, value.day)) }}
{% endmacro %}


{% macro date_string(d) %}
  {{ return('%04d-%02d-%02d' | format(d.year, d.month, d.day)) }}
{% endmacro %}


{% macro is_leap_year(year) %}
  {{ return(year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) }}
{% endmacro %}


{% macro days_in_month(year, month) %}
  {% if month == 2 and jstark.is_leap_year(year) %}
    {{ return(29) }}
  {% endif %}
  {% set lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] %}
  {{ return(lengths[month - 1]) }}
{% endmacro %}


{% macro add_days(d, n) %}
  {{ return(d + modules.datetime.timedelta(days=n)) }}
{% endmacro %}


{% macro add_weeks(d, n) %}
  {{ return(d + modules.datetime.timedelta(weeks=n)) }}
{% endmacro %}


{% macro add_months(d, n) %}
  {% set total = d.year * 12 + (d.month - 1) + n %}
  {% set year = total // 12 %}
  {% set month = total % 12 + 1 %}
  {% set month_length = jstark.days_in_month(year, month) %}
  {% set day = d.day if d.day < month_length else month_length %}
  {{ return(modules.datetime.date(year, month, day)) }}
{% endmacro %}


{% macro quarter_of(d) %}
  {{ return((d.month - 1) // 3 + 1) }}
{% endmacro %}


{% macro first_date_in_month(d) %}
  {{ return(modules.datetime.date(d.year, d.month, 1)) }}
{% endmacro %}


{% macro last_date_in_month(d) %}
  {{ return(modules.datetime.date(
      d.year, d.month, jstark.days_in_month(d.year, d.month)
  )) }}
{% endmacro %}


{% macro first_date_in_quarter(d) %}
  {{ return(modules.datetime.date(
      d.year, (jstark.quarter_of(d) - 1) * 3 + 1, 1
  )) }}
{% endmacro %}


{% macro last_date_in_quarter(d) %}
  {% set month = jstark.quarter_of(d) * 3 %}
  {{ return(modules.datetime.date(
      d.year, month, jstark.days_in_month(d.year, month)
  )) }}
{% endmacro %}


{% macro first_date_in_year(d) %}
  {{ return(modules.datetime.date(d.year, 1, 1)) }}
{% endmacro %}


{% macro last_date_in_year(d) %}
  {{ return(modules.datetime.date(d.year, 12, 31)) }}
{% endmacro %}


{% macro weekday_names() %}
  {{ return([
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ]) }}
{% endmacro %}


{% macro weekday_index(first_day_of_week) %}
  {% set names = jstark.weekday_names() %}
  {% set name = first_day_of_week if first_day_of_week else 'Monday' %}
  {% if name not in names %}
    {% do jstark.raise_error(
        jstark.error_codes()['invalid_first_day_of_week'],
        "'" ~ name ~ "' is not a day name; expected one of " ~ (names | join(', '))
    ) %}
  {% endif %}
  {{ return(names.index(name)) }}
{% endmacro %}


{% macro first_date_in_week(d, first_day_of_week) %}
  {% set target = jstark.weekday_index(first_day_of_week) %}
  {% set days_back = (d.weekday() - target) % 7 %}
  {{ return(jstark.add_days(d, -days_back)) }}
{% endmacro %}


{% macro last_date_in_week(d, first_day_of_week) %}
  {{ return(jstark.add_days(jstark.first_date_in_week(d, first_day_of_week), 6)) }}
{% endmacro %}


{% macro min_date(a, b) %}
  {{ return(a if a < b else b) }}
{% endmacro %}
