{% macro jstark_test_suite() %}

  {% set failures = [] %}

  {% do jstark_test_harness(failures) %}

  {% if failures | length > 0 %}
    {% set report = [] %}
    {% do report.append(
        (failures | length | string) ~ ' jstark L1 assertion(s) failed:'
    ) %}
    {% for failure in failures %}
      {% do report.append('  - ' ~ failure) %}
    {% endfor %}
    {{ exceptions.raise_compiler_error(report | join('\n')) }}
  {% endif %}

  {% do log('jstark L1 test suite passed.', info=true) %}

{% endmacro %}
