{% macro jstark_assert_equal(results, label, actual, expected) %}
  {% if actual != expected %}
    {% do results.append({
        'ok': false,
        'label': label,
        'message': label ~ ': expected ' ~ (expected | string) ~ ' but got ' ~ (actual | string)
    }) %}
  {% else %}
    {% do results.append({'ok': true, 'label': label}) %}
  {% endif %}
{% endmacro %}


{% macro jstark_assert_true(results, label, actual) %}
  {% if not actual %}
    {% do results.append({
        'ok': false,
        'label': label,
        'message': label ~ ': expected a truthy value but got ' ~ (actual | string)
    }) %}
  {% else %}
    {% do results.append({'ok': true, 'label': label}) %}
  {% endif %}
{% endmacro %}
