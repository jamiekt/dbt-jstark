{#
  Division that behaves like Spark's try_divide.

  Two things need fixing relative to a bare `/`:
   - integer division truncates on Postgres and Redshift, whereas try_divide
     always returns a float, so the numerator is cast first;
   - dividing by zero raises on most warehouses, whereas try_divide returns
     null, so the denominator goes through nullif.
#}

{% macro safe_divide(numerator, denominator) %}
  {{ return(
      'cast(' ~ numerator ~ ' as ' ~ dbt.type_float() ~ ') / nullif('
      ~ denominator ~ ', 0)'
  ) }}
{% endmacro %}
