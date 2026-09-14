{#
  Approximate distinct count.

  jstark uses Spark's approx_count_distinct (HyperLogLog). Most warehouses
  spell it the same way. Postgres has no built-in HLL, so it falls back to an
  exact count and warns: the values are still correct, just more expensive.
#}

{% macro approx_count_distinct(expression) %}
  {{ return(adapter.dispatch('jstark_approx_count_distinct', 'jstark')(expression)) }}
{% endmacro %}

{% macro default__jstark_approx_count_distinct(expression) %}
  {{ return('approx_count_distinct(' ~ expression ~ ')') }}
{% endmacro %}

{% macro postgres__jstark_approx_count_distinct(expression) %}
  {% do exceptions.warn(
      'jstark: postgres has no approx_count_distinct, so the Approx* features '
      ~ 'are computed exactly with count(distinct ...). Results are correct '
      ~ 'but slower than on warehouses with HyperLogLog support.'
  ) %}
  {{ return('count(distinct ' ~ expression ~ ')') }}
{% endmacro %}

{% macro redshift__jstark_approx_count_distinct(expression) %}
  {{ return('approximate count(distinct ' ~ expression ~ ')') }}
{% endmacro %}
