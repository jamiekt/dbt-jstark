{#
  Feature metadata as data.

  jstark attaches a metadata dict to every Spark column. SQL has nowhere to
  put that, so instead the same information is available two ways: as a
  relation (feature_catalog) and as a schema.yml fragment (see
  generate_schema_yml.sql).

  The parameters are deliberately identical to the generator entry points, so
  a caller can copy the arguments from their model into a catalogue query and
  get a description of exactly the columns that model produces.
#}

{% macro sql_string(value) %}
  {{ return("'" ~ (value | string | replace("'", "''")) ~ "'") }}
{% endmacro %}


{#
  Which input columns a feature ultimately needs.

  Base features declare their own. Derived features declare none, because
  their expression references other features rather than input columns, so
  theirs is the union of everything they reach transitively.

  plan['levels'] is already topologically ordered — assign_levels puts every
  feature strictly below its deepest dependency — so a single pass in level
  order suffices. By the time a feature is reached, every closure it reads is
  already complete, which is why there is no fixpoint loop here.

  The `| list` copy matters: definitions are shared across the plan, so
  appending to a definition's own required_columns list would corrupt it for
  every other feature that reads it.
#}
{% macro required_columns_closure(plan) %}

  {% set closure = {} %}
  {% for level in plan['levels'] %}
    {% for item in level %}
      {% set columns = item['definition'].get('required_columns', []) | list %}
      {% for dep in item['definition'].get('depends_on', []) %}
        {% set dep_key = jstark.dependency_key(dep[0], dep[1]) %}
        {% for column in closure.get(dep_key, []) %}
          {% if column not in columns %}
            {% do columns.append(column) %}
          {% endif %}
        {% endfor %}
      {% endfor %}
      {% do closure.update({item['key']: columns}) %}
    {% endfor %}
  {% endfor %}

  {{ return(closure) }}
{% endmacro %}


{% macro catalog_rows(
    generator='grocery',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    cuisines=[]
) %}

  {% set cols = jstark.resolve_columns() %}
  {% set resolved_as_at = jstark.resolve_as_at(as_at) %}
  {% set periods = jstark.parse_feature_periods(feature_periods) %}
  {% set plan = jstark.build_plan(
      generator, feature_stems or [], periods, resolved_as_at,
      first_day_of_week, use_absolute_periods, cols, cuisines
  ) %}
  {% set closure = jstark.required_columns_closure(plan) %}

  {% set rows = [] %}
  {% for item in plan['requested'] %}
    {% set definition = item['definition'] %}
    {% set period = item['period'] %}
    {% set ctx = item['ctx'] %}
    {% set start_date = jstark.date_string(ctx['start_date']) %}
    {% set end_date = jstark.date_string(ctx['end_date']) %}
    {% set subject = definition['description_subject'] %}
    {#- ctx['first_day_of_week'], not the raw parameter: feature_context
        defaults it to Monday, and absolute labelling needs a real day.
        generate_features passes the same resolved value, so the two
        agree on the column name they produce. -#}
    {% do rows.append({
        'feature_name': jstark.public_column_name(
            definition['stem'], period, use_absolute_periods,
            resolved_as_at, ctx['first_day_of_week']
        ),
        'stem': definition['stem'],
        'period_mnemonic': period['mnemonic'],
        'period_unit': jstark.period_unit_name(period['uom']),
        'start_date': start_date,
        'end_date': end_date,
        'description_subject': subject,
        'description': subject ~ ' between ' ~ start_date ~ ' and ' ~ end_date,
        'commentary': definition['commentary'],
        'required_columns': closure.get(item['key'], []) | sort | join(','),
        'kind': definition['kind']
    }) %}
  {% endfor %}

  {{ return(rows) }}
{% endmacro %}


{% macro feature_catalog(
    generator='grocery',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    cuisines=[]
) %}
{%- set rows = jstark.catalog_rows(
    generator, as_at, feature_periods, feature_stems, first_day_of_week,
    use_absolute_periods, cuisines
) -%}
{%- for row in rows %}
{% if not loop.first %}union all
{% endif %}select
    {{ jstark.sql_string(row['feature_name']) }} as feature_name,
    {{ jstark.sql_string(row['stem']) }} as stem,
    {{ jstark.sql_string(row['period_mnemonic']) }} as period_mnemonic,
    {{ jstark.sql_string(row['period_unit']) }} as period_unit,
    cast({{ jstark.sql_string(row['start_date']) }} as date) as start_date,
    cast({{ jstark.sql_string(row['end_date']) }} as date) as end_date,
    {{ jstark.sql_string(row['description']) }} as description,
    {{ jstark.sql_string(row['commentary']) }} as commentary,
    {{ jstark.sql_string(row['required_columns']) }} as required_columns,
    {{ jstark.sql_string(row['kind']) }} as kind
{% endfor -%}
{% endmacro %}
