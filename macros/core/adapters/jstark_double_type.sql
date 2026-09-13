{#
  Double-precision floating point, for casts inside safe_divide.

  jstark's numerators and denominators are pyspark DoubleType columns, and
  try_divide preserves that. dbt's own dbt.type_float() renders "float" via
  api.Column.translate_type, which on at least one warehouse (DuckDB) is a
  single-precision 4-byte FLOAT rather than an 8-byte DOUBLE. That is
  invisible until a division is chained into another division — exactly what
  grocery's AvgPurchaseCycle -> CyclesSinceLastPurchase chain does — at which
  point the rounding shows up in the result. "double precision" is ANSI SQL
  and resolves to an 8-byte double on DuckDB, Postgres and Snowflake (where
  FLOAT, DOUBLE and DOUBLE PRECISION are all synonyms for the same type);
  BigQuery spells it FLOAT64 instead.
#}

{% macro double_type() %}
  {{ return(adapter.dispatch('jstark_double_type', 'jstark')()) }}
{% endmacro %}

{% macro default__jstark_double_type() %}
  {{ return('double precision') }}
{% endmacro %}

{% macro bigquery__jstark_double_type() %}
  {{ return('float64') }}
{% endmacro %}
