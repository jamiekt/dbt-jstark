{#
  Sorted array of the distinct non-null values in the window.

  jstark uses Spark's collect_set, which ignores nulls and returns values in
  an unspecified order. Ordering is imposed here so that results are
  comparable between runs and between warehouses.

  This is the least portable seam, and the only one with no portable default.
  DuckDB and Postgres take the window as a FILTER clause; Snowflake and
  BigQuery have no FILTER, so the window goes into a CASE expression and null
  exclusion is handled by the aggregate. Every one of the four spellings below
  is rejected by at least one of the other three warehouses, so default__
  raises instead of picking a favourite: an adapter with no variant here gets a
  jstark error naming itself, rather than another warehouse's syntax error.

  The snowflake__ and bigquery__ variants are written from documentation and
  have not been run against a live warehouse. If you have credentials, the
  warehouses.yml workflow is the place to prove them.
#}

{% macro collect_set(expression, window) %}
  {{ return(adapter.dispatch('jstark_collect_set', 'jstark')(expression, window)) }}
{% endmacro %}

{% macro default__jstark_collect_set(expression, window) %}
  {% do jstark.raise_error(
      jstark.error_codes()['unsupported_adapter'],
      jstark.unsupported_adapter_detail('jstark_collect_set', target.type)
  ) %}
{% endmacro %}

{% macro duckdb__jstark_collect_set(expression, window) %}
  {#- list_sort is DuckDB's own; array_sort is the Postgres/Snowflake spelling -#}
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
  {#- Unproven. If it returns arrays containing a NULL, try ARRAY_UNIQUE_AGG in
      place of ARRAY_AGG(DISTINCT ...): the CASE yields NULL for out-of-window
      rows, and the two aggregates differ on whether that NULL is kept. -#}
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
