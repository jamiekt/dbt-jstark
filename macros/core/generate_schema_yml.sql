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

{% macro schema_yml_text(
    model_name,
    generator='grocery',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={},
    cuisines=[],
    group_by=[]
) %}

  {% set rows = jstark.catalog_rows(
      generator, as_at, feature_periods, feature_stems, first_day_of_week,
      use_absolute_periods, column_map, cuisines
  ) %}

  {% set lines = ['version: 2', '', 'models:', '  - name: ' ~ model_name,
                  '    columns:'] %}
  {% for column in group_by %}
    {% do lines.append('      - name: ' ~ column) %}
    {% do lines.append('        description: Grouping column.') %}
  {% endfor %}
  {% for row in rows %}
    {% do lines.append('      - name: ' ~ row['feature_name']) %}
    {#- double-quoted YAML with embedded quotes escaped, so a description
        containing a colon or a quote cannot break the output -#}
    {% do lines.append(
        '        description: "'
        ~ (row['description'] | replace('\\', '\\\\') | replace('"', '\\"'))
        ~ '"'
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
    column_map={},
    cuisines=[],
    group_by=[]
) %}
  {#- print, not log, so the output is clean enough to redirect into a file -#}
  {% do print(jstark.schema_yml_text(
      model_name, generator, as_at, feature_periods, feature_stems,
      first_day_of_week, use_absolute_periods, column_map, cuisines, group_by
  )) %}
{% endmacro %}
