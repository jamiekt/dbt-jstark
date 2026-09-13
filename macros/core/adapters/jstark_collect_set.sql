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


{#
  A literal empty array of strings, used as the default for the collect_set
  features so that a customer with no matching rows gets [] rather than null.
  Spark's collect_set already behaves that way; SQL array_agg returns null, so
  the coalesce in the generated SQL needs something to fall back to.

  Every warehouse spells this differently and most of them need the element
  type stated, which is why it is a seam rather than a literal.
#}

{% macro empty_string_array() %}
  {{ return(adapter.dispatch('jstark_empty_string_array', 'jstark')()) }}
{% endmacro %}

{% macro default__jstark_empty_string_array() %}
  {{ return('cast(array[] as ' ~ dbt.type_string() ~ '[])') }}
{% endmacro %}

{% macro duckdb__jstark_empty_string_array() %}
  {#- DuckDB builds lists with list_value(); an argument-less call gives [] -#}
  {{ return('cast(list_value() as ' ~ dbt.type_string() ~ '[])') }}
{% endmacro %}

{% macro snowflake__jstark_empty_string_array() %}
  {#- Snowflake arrays are untyped, so no cast is needed or allowed.
      Written from the docs and not yet run against a real warehouse. -#}
  {{ return('array_construct()') }}
{% endmacro %}

{% macro bigquery__jstark_empty_string_array() %}
  {#- Written from the docs and not yet run against a real warehouse. -#}
  {{ return('array<string>[]') }}
{% endmacro %}
