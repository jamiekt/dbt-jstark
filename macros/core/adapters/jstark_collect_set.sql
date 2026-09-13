{#
  Sorted array of the distinct non-null values in the window.

  jstark uses Spark's collect_set, which ignores nulls and returns values in
  an unspecified order. Ordering is imposed here so that results are
  comparable between runs and between warehouses.

  This is the least portable seam. DuckDB and Postgres take the window as a
  FILTER clause; Snowflake and BigQuery have no FILTER, so the window goes
  into a CASE expression and null exclusion is handled by the aggregate.

  The snowflake__ and bigquery__ variants are written from documentation and
  have not been run against a live warehouse. If you have credentials, the
  warehouses.yml workflow is the place to prove them.
#}

{% macro collect_set(expression, window) %}
  {{ return(adapter.dispatch('jstark_collect_set', 'jstark')(expression, window)) }}
{% endmacro %}

{% macro default__jstark_collect_set(expression, window) %}
  {{ return(
      'list_sort(array_agg(distinct ' ~ expression ~ ') filter (where ('
      ~ window ~ ') and ' ~ expression ~ ' is not null))'
  ) }}
{% endmacro %}

{% macro postgres__jstark_collect_set(expression, window) %}
  {{ return(
      'array_agg(distinct ' ~ expression ~ ' order by ' ~ expression
      ~ ') filter (where (' ~ window ~ ') and ' ~ expression ~ ' is not null)'
  ) }}
{% endmacro %}

{% macro snowflake__jstark_collect_set(expression, window) %}
  {{ return(
      'array_sort(array_agg(distinct case when ' ~ window ~ ' then '
      ~ expression ~ ' end))'
  ) }}
{% endmacro %}

{% macro bigquery__jstark_collect_set(expression, window) %}
  {{ return(
      'array_agg(distinct case when ' ~ window ~ ' then ' ~ expression
      ~ ' end ignore nulls order by case when ' ~ window ~ ' then '
      ~ expression ~ ' end)'
  ) }}
{% endmacro %}
