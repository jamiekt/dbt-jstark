{#
  Absolute period labels.

  With use_absolute_periods=true the column suffix names the calendar period
  covered rather than the offset from as_at, so a monthly feature reads
  gross_spend_2021oct_to_2021dec instead of gross_spend_3m1.

  jstark joins the two ends with a hyphen (2021Oct-2021Dec). A hyphen cannot
  appear in an unquoted SQL identifier, so this uses '_to_' and lowercases
  throughout.
#}

{% macro month_abbreviations() %}
  {{ return([
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
  ]) }}
{% endmacro %}


{% macro week_label(week_start_date, first_day_of_week) %}
  {#
    W01 of a year is the week beginning on the first occurrence of
    first_day_of_week on or before 1 January. A week that starts in late
    December therefore often belongs to the following year, which is why the
    next year's W01 has to be checked before the number is worked out.
    Mirrors Feature._week_label in jstark.
  #}
  {% set year = week_start_date.year %}
  {% set w01_start = jstark.first_date_in_week(
      modules.datetime.date(year, 1, 1), first_day_of_week
  ) %}
  {% set w01_start_next = jstark.first_date_in_week(
      modules.datetime.date(year + 1, 1, 1), first_day_of_week
  ) %}

  {% if week_start_date >= w01_start_next %}
    {% set label_year = year + 1 %}
    {% set reference = w01_start_next %}
  {% else %}
    {% set label_year = year %}
    {% set reference = w01_start %}
  {% endif %}

  {% set week_number = (week_start_date - reference).days // 7 + 1 %}
  {{ return((label_year | string) ~ 'w' ~ ('%02d' | format(week_number))) }}
{% endmacro %}


{% macro absolute_period_label(feature_period, as_at, first_day_of_week) %}

  {% set uom = feature_period['uom'] %}
  {% set start_offset = feature_period['start'] %}
  {% set end_offset = feature_period['end'] %}

  {% if uom == 'd' %}
    {% set start_label = jstark.date_string(
        jstark.add_days(as_at, -start_offset)
    ) | replace('-', '') %}
    {% set end_label = jstark.date_string(
        jstark.add_days(as_at, -end_offset)
    ) | replace('-', '') %}

  {% elif uom == 'w' %}
    {% set start_label = jstark.week_label(
        jstark.first_date_in_week(
            jstark.add_weeks(as_at, -start_offset), first_day_of_week
        ),
        first_day_of_week
    ) %}
    {% set end_label = jstark.week_label(
        jstark.first_date_in_week(
            jstark.add_weeks(as_at, -end_offset), first_day_of_week
        ),
        first_day_of_week
    ) %}

  {% elif uom == 'm' %}
    {% set start_month = jstark.add_months(as_at, -start_offset) %}
    {% set end_month = jstark.add_months(as_at, -end_offset) %}
    {% set months = jstark.month_abbreviations() %}
    {% set start_label = (start_month.year | string) ~ months[start_month.month - 1] %}
    {% set end_label = (end_month.year | string) ~ months[end_month.month - 1] %}

  {% elif uom == 'q' %}
    {% set start_quarter = jstark.add_months(as_at, -start_offset * 3) %}
    {% set end_quarter = jstark.add_months(as_at, -end_offset * 3) %}
    {% set start_label = (start_quarter.year | string)
                         ~ 'q' ~ jstark.quarter_of(start_quarter) %}
    {% set end_label = (end_quarter.year | string)
                       ~ 'q' ~ jstark.quarter_of(end_quarter) %}

  {% else %}
    {% set start_label = jstark.add_months(as_at, -start_offset * 12).year | string %}
    {% set end_label = jstark.add_months(as_at, -end_offset * 12).year | string %}
  {% endif %}

  {% if start_label == end_label %}
    {{ return(start_label) }}
  {% endif %}
  {{ return(start_label ~ '_to_' ~ end_label) }}

{% endmacro %}
