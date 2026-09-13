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


{% macro jstark_normalise_sql(sql) %}
  {{ return(modules.re.sub('\\s+', ' ', sql | string) | trim) }}
{% endmacro %}


{% macro jstark_assert_contains(results, label, haystack, needle) %}
  {#- `'' in anything` is true in Jinja, so an empty needle would make this
      assertion pass whatever the haystack contains. An empty needle is always a
      bug in the caller — usually a value that was built from something that
      came out empty — so it fails rather than passing vacuously. -#}
  {% if needle == '' %}
    {% do results.append({
        'ok': false,
        'label': label,
        'message': label ~ ': the needle is empty, so this assertion would pass '
                   ~ 'against any haystack; assert on a real value'
    }) %}
  {% elif needle not in haystack %}
    {% do results.append({
        'ok': false,
        'label': label,
        'message': label ~ ': expected to find <' ~ needle ~ '> in <' ~ haystack ~ '>'
    }) %}
  {% else %}
    {% do results.append({'ok': true, 'label': label}) %}
  {% endif %}
{% endmacro %}
