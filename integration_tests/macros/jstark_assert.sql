{% macro jstark_assert_equal(failures, label, actual, expected) %}
  {% if actual != expected %}
    {% do failures.append(
        label ~ ': expected ' ~ (expected | string) ~ ' but got ' ~ (actual | string)
    ) %}
  {% endif %}
{% endmacro %}


{% macro jstark_assert_true(failures, label, actual) %}
  {% if not actual %}
    {% do failures.append(label ~ ': expected a truthy value but got ' ~ (actual | string)) %}
  {% endif %}
{% endmacro %}
