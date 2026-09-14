{#
  Feature period bounds.

  Mirrors Feature.start_date / Feature.end_date in jstark
  (jstark/features/feature.py at 51d9083): step back `start` (or `end`) whole
  units from as_at, then snap to the first (or last) date of that unit. The
  end date is capped at as_at, so a period that includes the current,
  incomplete unit does not claim to cover the future.
#}

{% macro period_bounds(feature_period, as_at, first_day_of_week) %}

  {% set uom = feature_period['uom'] %}

  {#- start -#}
  {% if uom == 'd' %}
    {% set start_date = jstark.add_days(as_at, -feature_period['start']) %}
  {% elif uom == 'w' %}
    {% set start_date = jstark.first_date_in_week(
        jstark.add_weeks(as_at, -feature_period['start']), first_day_of_week
    ) %}
  {% elif uom == 'm' %}
    {% set start_date = jstark.first_date_in_month(
        jstark.add_months(as_at, -feature_period['start'])
    ) %}
  {% elif uom == 'q' %}
    {% set start_date = jstark.first_date_in_quarter(
        jstark.add_months(as_at, -feature_period['start'] * 3)
    ) %}
  {% else %}
    {% set start_date = jstark.first_date_in_year(
        jstark.add_months(as_at, -feature_period['start'] * 12)
    ) %}
  {% endif %}

  {#- end -#}
  {% if uom == 'd' %}
    {% set last_date_of_period = jstark.add_days(as_at, -feature_period['end']) %}
  {% elif uom == 'w' %}
    {% set last_date_of_period = jstark.last_date_in_week(
        jstark.add_weeks(as_at, -feature_period['end']), first_day_of_week
    ) %}
  {% elif uom == 'm' %}
    {% set last_date_of_period = jstark.last_date_in_month(
        jstark.add_months(as_at, -feature_period['end'])
    ) %}
  {% elif uom == 'q' %}
    {% set last_date_of_period = jstark.last_date_in_quarter(
        jstark.add_months(as_at, -feature_period['end'] * 3)
    ) %}
  {% else %}
    {% set last_date_of_period = jstark.last_date_in_year(
        jstark.add_months(as_at, -feature_period['end'] * 12)
    ) %}
  {% endif %}

  {{ return({
      'start_date': start_date,
      'end_date': jstark.min_date(last_date_of_period, as_at)
  }) }}

{% endmacro %}
