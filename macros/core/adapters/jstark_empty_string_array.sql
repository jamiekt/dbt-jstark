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
