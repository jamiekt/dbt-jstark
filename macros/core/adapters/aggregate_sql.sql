{#
  Turn an aggregator name plus an expression and a window predicate into a
  complete SQL aggregate.

  Every aggregator takes the same (expression, window) pair even though only
  collect_set needs them separately, which keeps the engine's rendering
  uniform: it never has to know which aggregator it is dealing with.

  count_if is Spark-specific; it becomes a count over a case that only yields
  a row when the expression is true.
#}

{% macro aggregators() %}
  {{ return([
      'sum', 'count', 'count_if', 'count_distinct', 'approx_count_distinct',
      'max', 'min', 'collect_set'
  ]) }}
{% endmacro %}


{% macro try_aggregate_sql(aggregator, expression, window) %}

  {% if aggregator not in jstark.aggregators() %}
    {{ return({
        'ok': false,
        'error': jstark.error_message(
            jstark.error_codes()['unknown_aggregator'],
            "'" ~ aggregator ~ "' is not a known aggregator; expected one of "
            ~ (jstark.aggregators() | join(', '))
        ),
        'sql': none
    }) }}
  {% endif %}

  {% set windowed = 'case when ' ~ window ~ ' then ' ~ expression ~ ' end' %}

  {% if aggregator == 'collect_set' %}
    {% set sql = jstark.collect_set(expression, window) %}
  {% elif aggregator == 'count_if' %}
    {% set sql = 'count(case when (' ~ window ~ ') and (' ~ expression
                 ~ ') then 1 end)' %}
  {% elif aggregator == 'count_distinct' %}
    {% set sql = 'count(distinct ' ~ windowed ~ ')' %}
  {% elif aggregator == 'approx_count_distinct' %}
    {% set sql = jstark.approx_count_distinct(windowed) %}
  {% else %}
    {% set sql = aggregator ~ '(' ~ windowed ~ ')' %}
  {% endif %}

  {{ return({'ok': true, 'error': none, 'sql': sql}) }}

{% endmacro %}


{% macro aggregate_sql(aggregator, expression, window) %}
  {% set result = jstark.try_aggregate_sql(aggregator, expression, window) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['sql']) }}
{% endmacro %}
