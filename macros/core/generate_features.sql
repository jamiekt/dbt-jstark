{#
  SQL emission.

  One CTE for the input, one for the base aggregates, one per derived level,
  then a projection that keeps only what was requested. Derived levels get
  their own CTEs because SQL cannot reference a select-list alias from the
  same select, and jstark has derived features built on other derived ones.

  Internal column names always carry the period mnemonic. The final
  projection is the only place a name changes, which is where absolute period
  labels are applied.
#}

{% macro render_feature(item) %}
  {% set definition = item['definition'] %}

  {% if definition['kind'] == 'base' %}
    {% set expression = jstark.aggregate_sql(
        definition['aggregator'], definition['expression'], item['ctx']['window']
    ) %}
  {% else %}
    {% set expression = definition['expression'] %}
  {% endif %}

  {#- a 'null' default adds nothing, so it is left off rather than emitted
      as a redundant coalesce(x, null) -#}
  {% if definition['default'] == 'null' %}
    {{ return(expression) }}
  {% endif %}
  {{ return('coalesce(' ~ expression ~ ', ' ~ definition['default'] ~ ')') }}
{% endmacro %}


{% macro generate_features(
    input,
    group_by,
    generator='core',
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    cuisines=[]
) %}

  {% set resolved_as_at = jstark.resolve_as_at(as_at) %}
  {% set periods = jstark.parse_feature_periods(feature_periods) %}
  {% set cols = jstark.resolve_columns() %}
  {#- bare column names only, and no repeats; see try_resolve_group_by in
      macros/core/context.sql for why an expression cannot work here -#}
  {% set group_by_columns = jstark.resolve_group_by(group_by) %}

  {% set plan = jstark.build_plan(
      generator, feature_stems, periods, resolved_as_at, first_day_of_week,
      use_absolute_periods, cols, cuisines
  ) %}

  {% set levels = plan['levels'] %}
  {% set group_by_sql = group_by_columns | join(', ') %}

with jstark_input as (
    {% if input is string %}
    {{ input }}
    {% else %}
    select * from {{ input }}
    {% endif %}
),

jstark_base as (
    select
        {% for column in group_by_columns %}
        {{ column }},
        {% endfor %}
        {% for item in levels[0] %}
        {{ jstark.render_feature(item) }} as {{ item['key'] }}
        {{- ',' if not loop.last }}
        {% endfor %}
    from jstark_input
    {% if group_by_columns | length > 0 %}
    group by {{ group_by_sql }}
    {% endif %}
)

  {%- set last_cte = namespace(name='jstark_base') %}
  {% for level in levels %}
    {% if not loop.first %}
,

jstark_derived_{{ loop.index0 }} as (
    select
        *,
        {% for item in level %}
        {{ jstark.render_feature(item) }} as {{ item['key'] }}
        {{- ',' if not loop.last }}
        {% endfor %}
    from {{ last_cte.name }}
)
      {%- set last_cte.name = 'jstark_derived_' ~ loop.index0 %}
    {% endif %}
  {% endfor %}

select
    {% for column in group_by_columns %}
    {{ column }},
    {% endfor %}
    {% for item in plan['requested'] %}
    {%- set public = jstark.public_column_name(
        item['stem'], item['period'], use_absolute_periods, resolved_as_at,
        item['ctx']['first_day_of_week']
    ) %}
    {{ item['key'] }}{{ ' as ' ~ public if public != item['key'] else '' }}
    {{- ',' if not loop.last }}
    {% endfor %}
from {{ last_cte.name }}

{% endmacro %}
