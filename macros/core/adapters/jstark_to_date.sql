{#
  Truncate a timestamp expression to a date.

  Every base feature filters on the date, not the timestamp, so this is
  applied to event_timestamp in the window predicate. `cast(x as date)` is
  ANSI and works everywhere tested so far; the seam exists so an adapter that
  spells it differently has somewhere to say so.
#}

{% macro to_date(expression) %}
  {{ return(adapter.dispatch('jstark_to_date', 'jstark')(expression)) }}
{% endmacro %}

{% macro default__jstark_to_date(expression) %}
  {{ return('cast(' ~ expression ~ ' as date)') }}
{% endmacro %}
