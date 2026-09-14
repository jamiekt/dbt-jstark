{#
  Builds and prints a schema.yml fragment describing the columns a generator
  produces, so a user can paste real descriptions into their own project
  rather than documenting 37 generated columns by hand.

  jstark_generate_schema_yml is named that rather than generate_schema_yml
  because dbt run-operation resolves macro names without package
  qualification, and an unprefixed name that generic would collide with the
  user's own macros.

  Usage:
    dbt run-operation jstark_generate_schema_yml --args '{
        "model_name": "customer_features",
        "generator": "grocery",
        "as_at": "2022-01-01",
        "feature_periods": ["3m1"]
    }'
#}

{% macro yaml_double_quoted(text) %}
  {#
    A double-quoted YAML scalar. Backslashes are escaped before quotes, or a
    real backslash immediately before a real quote would end up mis-paired.
    Quoting means a value containing a colon, a quote or a leading indicator
    character cannot break the emitted document.
  #}
  {{ return(
      '"' ~ (text | string | replace('\\', '\\\\') | replace('"', '\\"')) ~ '"'
  ) }}
{% endmacro %}


{% macro schema_yml_text(
    model_name,
    generator='grocery',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    cuisines=[],
    group_by=[]
) %}

  {% set rows = jstark.catalog_rows(
      generator, as_at, feature_periods, feature_stems, first_day_of_week,
      use_absolute_periods, cuisines
  ) %}

  {% set lines = ['version: 2', '', 'models:', '  - name: ' ~ model_name,
                  '    columns:'] %}
  {#- jstark.resolve_group_by already restricts these to bare identifiers, so
      nothing hostile can reach the escaping below. Escaped anyway: this file
      generates a document a caller pastes into their project, and two
      independent guards on generated output is the right number. -#}
  {% for column in jstark.resolve_group_by(group_by) %}
    {% do lines.append(
        '      - name: ' ~ jstark.yaml_double_quoted(column)
    ) %}
    {% do lines.append('        description: Grouping column.') %}
  {% endfor %}
  {% for row in rows %}
    {% do lines.append('      - name: ' ~ row['feature_name']) %}
    {% do lines.append(
        '        description: ' ~ jstark.yaml_double_quoted(row['description'])
    ) %}
  {% endfor %}

  {{ return(lines | join('\n')) }}
{% endmacro %}


{% macro jstark_generate_schema_yml(
    model_name,
    generator='grocery',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    cuisines=[],
    group_by=[]
) %}
  {#- print, not log, so the output is clean enough to redirect into a file -#}
  {% do print(jstark.schema_yml_text(
      model_name, generator, as_at, feature_periods, feature_stems,
      first_day_of_week, use_absolute_periods, cuisines, group_by
  )) %}
{% endmacro %}
