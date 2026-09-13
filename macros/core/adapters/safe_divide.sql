{#
  Division that behaves like Spark's try_divide.

  Two things need fixing relative to a bare `/`:
   - integer division truncates on Postgres and Redshift, whereas try_divide
     always returns a double, so the numerator is cast first;
   - dividing by zero raises on most warehouses, whereas try_divide returns
     null, so the denominator goes through nullif.

  The numerator is cast to jstark.double_type(), not dbt.type_float(): the
  latter renders a single-precision 4-byte FLOAT on DuckDB, which is
  indistinguishable from a double until a safe_divide result feeds another
  safe_divide (grocery's AvgPurchaseCycle -> CyclesSinceLastPurchase chain),
  at which point the rounding is visible in the result.
#}

{% macro safe_divide(numerator, denominator) %}
  {{ return(
      'cast(' ~ numerator ~ ' as ' ~ jstark.double_type() ~ ') / nullif('
      ~ denominator ~ ', 0)'
  ) }}
{% endmacro %}
