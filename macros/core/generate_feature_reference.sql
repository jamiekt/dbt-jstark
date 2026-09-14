{#
  The feature reference that goes in the README.

  feature_catalog describes the columns one particular set of parameters
  produces, dates and all. The README needs the opposite: one row per feature
  stem, period-independent, so it stays correct whatever as_at a reader uses.

  So this builds the catalogue for one canonical period and then strips the
  period back out of the column names, turning basket_months_3m1 into
  basket_{unit}s_{period}. The canonical period is monthly because that is the
  unit the unit-dependent names read most naturally in.
#}

{% macro feature_reference_rows(generator='grocery', cuisines=[]) %}

  {% set canonical_period = '3m1' %}
  {% set canonical_as_at = '2022-01-01' %}
  {% set rows = jstark.catalog_rows(
      generator=generator,
      as_at=canonical_as_at,
      feature_periods=[canonical_period],
      feature_stems=none,
      first_day_of_week='Monday',
      use_absolute_periods=false,
      cuisines=cuisines
  ) %}

  {% set reference = [] %}
  {% for row in rows %}
    {#- 'basket_months_3m1' -> 'basket_{unit}s_{period}' -#}
    {% set without_period = row['feature_name']
        | replace('_' ~ canonical_period, '_{period}') %}
    {#- '_month' only ever appears as the unit placeholder in a feature name
        today (e.g. average_baskets_per_month_3m1). If a future feature's name
        contains '_month' for some other reason, this substitution will
        silently corrupt it: the two assertions in test_catalog.sql only prove
        the substitution fires where it should (OrderPeriods) and does not
        fire where it should not (NetSpend); neither catches a *new*
        '_month'-containing name. Add its own assertion if you add one. -#}
    {% set pattern = without_period | replace('_month', '_{unit}') %}
    {% do reference.append({
        'stem': row['stem'],
        'column_name_pattern': pattern,
        'kind': row['kind'],
        'description_subject': row['description_subject'],
        'commentary': row['commentary'],
        'required_columns': row['required_columns']
    }) %}
  {% endfor %}

  {{ return(reference) }}
{% endmacro %}


{#
  Usage:
    dbt run-operation jstark_generate_feature_reference \
      --args '{"generator": "grocery"}'
#}
{% macro jstark_generate_feature_reference(generator='grocery', cuisines=[]) %}

  {% set rows = jstark.feature_reference_rows(generator, cuisines) %}
  {% set lines = [
      '| Feature | Column | Kind | Description | Requires |',
      '| --- | --- | --- | --- | --- |'
  ] %}
  {% for row in rows %}
    {% do lines.append(
        '| `' ~ row['stem'] ~ '` | `' ~ row['column_name_pattern'] ~ '` | '
        ~ row['kind'] ~ ' | ' ~ row['description_subject'] ~ ' | `'
        ~ row['required_columns'] ~ '` |'
    ) %}
  {% endfor %}
  {% do print(lines | join('\n')) %}

{% endmacro %}
