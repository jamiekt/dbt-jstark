{% macro jstark_test_suite() %}

  {% set results = [] %}

  {% do jstark_test_harness(results) %}

  {% if results | length == 0 %}
    {{ exceptions.raise_compiler_error('jstark L1 test suite ran no assertions at all.') }}
  {% endif %}

  {% set failed = results | rejectattr('ok') | list %}

  {% if failed | length > 0 %}
    {% set report = [] %}
    {% do report.append(
        (failed | length | string) ~ ' jstark L1 assertion(s) failed:'
    ) %}
    {% for failure in failed %}
      {% do report.append('  - ' ~ failure['message']) %}
    {% endfor %}
    {{ exceptions.raise_compiler_error(report | join('\n')) }}
  {% endif %}

  {% do log('jstark L1 test suite passed: ' ~ (results | length) ~ ' assertion(s).', info=true) %}

{% endmacro %}
