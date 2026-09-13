{#
  The registry: what to compute, and in what order.

  No SQL is emitted here. build_plan resolves the requested feature stems and
  periods into a dependency closure, then levels that closure topologically so
  that Task 9's renderer can emit one CTE per level. Levelling is necessary
  because SQL cannot reference a select-list alias from the same select, and
  jstark has derived features that depend on other derived features.

  A dependency is a [stem, period] pair, not just a stem: BasketPeriods for
  3m1 depends on activity in each of 3m3, 2m2 and 1m1. Those pulled-in
  features are computed but not projected, which is why each plan item carries
  a `requested` flag.
#}

{% macro generators() %}
  {{ return(['core', 'grocery', 'mealkit', 'test']) }}
{% endmacro %}


{% macro catalogue(generator, ctx) %}
  {#
    Built with explicit branches rather than by looking up a macro by name:
    dbt's Jinja does not expose the macro namespace for dynamic dispatch, and
    an explicit list is easier to read anyway.
  #}
  {% set definitions = {} %}

  {% if generator == 'test' %}
    {% do jstark.register_test_features(definitions, ctx) %}
    {{ return(definitions) }}
  {% endif %}

  {% if generator not in jstark.generators() %}
    {% do jstark.raise_error(
        jstark.error_codes()['unknown_generator'],
        "'" ~ generator ~ "' is not a jstark generator; expected one of "
        ~ (jstark.generators() | join(', '))
    ) %}
  {% endif %}

  {#- Tasks 10-12 replace this branch body with real registrations. -#}
  {% do jstark.register_core_features(definitions, ctx, generator) %}
  {% if generator == 'grocery' %}
    {% do jstark.register_grocery_features(definitions, ctx) %}
  {% elif generator == 'mealkit' %}
    {% do jstark.register_mealkit_features(definitions, ctx) %}
  {% endif %}

  {{ return(definitions) }}
{% endmacro %}


{% macro single_unit_periods(feature_period) %}
  {#- 3m1 -> 1m1, 2m2, 3m3: one whole unit each, ascending by offset -#}
  {% set periods = [] %}
  {% for n in range(feature_period['end'], feature_period['start'] + 1) %}
    {% do periods.append(jstark.feature_period(feature_period['uom'], n, n)) %}
  {% endfor %}
  {{ return(periods) }}
{% endmacro %}


{% macro dependency_key(stem, period) %}
  {{ return(jstark.column_name(stem, period)) }}
{% endmacro %}


{% macro ensure_catalogue(generator, period, ctx_args, contexts, catalogues) %}
  {% if period['mnemonic'] not in catalogues %}
    {% set ctx = jstark.feature_context(
        period,
        ctx_args['as_at'],
        ctx_args['first_day_of_week'],
        ctx_args['use_absolute_periods'],
        ctx_args['cols'],
        ctx_args['cuisines']
    ) %}
    {% do contexts.update({period['mnemonic']: ctx}) %}
    {% do catalogues.update({
        period['mnemonic']: jstark.catalogue(generator, ctx)
    }) %}
  {% endif %}
{% endmacro %}


{% macro expand_deps(
    generator, stem, period, ctx_args, contexts, catalogues, resolved,
    requested, depth
) %}
  {#
    Recursive rather than iterative: a `{% set %}` inside a `{% for %}` does
    not survive the loop in Jinja, so accumulation has to happen by mutating
    the `resolved` dict that the caller owns.
  #}
  {% if depth > 20 %}
    {{ exceptions.raise_compiler_error(
        'jstark: feature dependency resolution exceeded 20 levels while '
        ~ 'resolving ' ~ stem ~ ' at ' ~ period['mnemonic']
        ~ '. This usually means a circular dependency.'
    ) }}
  {% endif %}

  {% do jstark.ensure_catalogue(generator, period, ctx_args, contexts, catalogues) %}
  {% set cat = catalogues[period['mnemonic']] %}

  {% if stem not in cat %}
    {% do jstark.raise_error(
        jstark.error_codes()['feature_not_found'],
        "['" ~ stem ~ "'] not found. Valid feature stems for the "
        ~ generator ~ ' generator are: ' ~ (cat.keys() | sort | join(', '))
    ) %}
  {% endif %}

  {% set key = jstark.dependency_key(stem, period) %}

  {% if key in resolved %}
    {% if requested %}
      {% do resolved[key].update({'requested': true}) %}
    {% endif %}
    {{ return('') }}
  {% endif %}

  {#- inserted before recursing so that a cycle terminates here rather than
      recursing forever; the cycle itself is reported by assign_levels -#}
  {% do resolved.update({key: {
      'key': key,
      'stem': stem,
      'period': period,
      'definition': cat[stem],
      'ctx': contexts[period['mnemonic']],
      'requested': requested
  }}) %}

  {% for dep in cat[stem].get('depends_on', []) %}
    {% do jstark.expand_deps(
        generator, dep[0], dep[1], ctx_args, contexts, catalogues, resolved,
        false, depth + 1
    ) %}
  {% endfor %}
{% endmacro %}


{% macro assign_levels(resolved) %}
  {#
    Base features are level 0. A derived feature sits one level below its
    deepest dependency. Repeated passes rather than a recursive walk, because
    the number of levels is tiny (grocery bottoms out at 2) and a pass that
    assigns nothing is exactly the cycle-detection signal.
  #}
  {% set levels = {} %}
  {% for key, item in resolved.items() %}
    {% if item['definition']['kind'] == 'base' %}
      {% do levels.update({key: 0}) %}
    {% endif %}
  {% endfor %}

  {% for _ in range(resolved | length + 1) %}
    {% for key, item in resolved.items() %}
      {% if key not in levels %}
        {% set state = namespace(ready=true, deepest=0) %}
        {% for dep in item['definition'].get('depends_on', []) %}
          {% set dep_key = jstark.dependency_key(dep[0], dep[1]) %}
          {% if dep_key not in levels %}
            {% set state.ready = false %}
          {% elif levels[dep_key] > state.deepest %}
            {% set state.deepest = levels[dep_key] %}
          {% endif %}
        {% endfor %}
        {% if state.ready %}
          {% do levels.update({key: state.deepest + 1}) %}
        {% endif %}
      {% endif %}
    {% endfor %}
  {% endfor %}

  {% if levels | length != resolved | length %}
    {% set stuck = [] %}
    {% for key in resolved %}
      {% if key not in levels %}
        {% do stuck.append(key) %}
      {% endif %}
    {% endfor %}
    {{ exceptions.raise_compiler_error(
        'jstark: circular feature dependency involving ' ~ (stuck | sort | join(', '))
    ) }}
  {% endif %}

  {{ return(levels) }}
{% endmacro %}


{% macro try_build_plan(
    generator, feature_stems, periods, as_at, first_day_of_week,
    use_absolute_periods, cols, cuisines
) %}

  {% set ctx_args = {
      'as_at': as_at,
      'first_day_of_week': first_day_of_week,
      'use_absolute_periods': use_absolute_periods,
      'cols': cols,
      'cuisines': cuisines
  } %}

  {% set contexts = {} %}
  {% set catalogues = {} %}
  {% do jstark.ensure_catalogue(
      generator, periods[0], ctx_args, contexts, catalogues
  ) %}
  {% set available = catalogues[periods[0]['mnemonic']] %}

  {% set requested_stems = feature_stems if feature_stems else [] %}
  {% set missing = [] %}
  {% for stem in requested_stems %}
    {% if stem not in available %}
      {% do missing.append(stem) %}
    {% endif %}
  {% endfor %}
  {% if missing | length > 0 %}
    {{ return({
        'ok': false,
        'error': jstark.error_message(
            jstark.error_codes()['feature_not_found'],
            (missing | sort | string) ~ ' not found. Valid feature stems for the '
            ~ generator ~ ' generator are: '
            ~ (available.keys() | sort | join(', '))
        ),
        'plan': none
    }) }}
  {% endif %}

  {#- catalogue order, not request order, so column order is stable -#}
  {% set target_stems = [] %}
  {% for stem in available %}
    {% if requested_stems | length == 0 or stem in requested_stems %}
      {% do target_stems.append(stem) %}
    {% endif %}
  {% endfor %}

  {% set resolved = {} %}
  {% set requested_items = [] %}
  {% for stem in target_stems %}
    {% for period in periods %}
      {% do jstark.expand_deps(
          generator, stem, period, ctx_args, contexts, catalogues, resolved,
          true, 0
      ) %}
      {% do requested_items.append(resolved[jstark.dependency_key(stem, period)]) %}
    {% endfor %}
  {% endfor %}

  {% set levels = jstark.assign_levels(resolved) %}
  {% set depth = (levels.values() | list | max) if levels else 0 %}

  {% set buckets = [] %}
  {% for level in range(0, depth + 1) %}
    {% set bucket = [] %}
    {% for key, item in resolved.items() %}
      {% if levels[key] == level %}
        {% do item.update({'level': level}) %}
        {% do bucket.append(item) %}
      {% endif %}
    {% endfor %}
    {% do buckets.append(bucket) %}
  {% endfor %}

  {{ return({
      'ok': true,
      'error': none,
      'plan': {'levels': buckets, 'requested': requested_items}
  }) }}

{% endmacro %}


{% macro build_plan(
    generator, feature_stems, periods, as_at, first_day_of_week,
    use_absolute_periods, cols, cuisines
) %}
  {% set result = jstark.try_build_plan(
      generator, feature_stems, periods, as_at, first_day_of_week,
      use_absolute_periods, cols, cuisines
  ) %}
  {% if not result['ok'] %}
    {{ exceptions.raise_compiler_error(result['error']) }}
  {% endif %}
  {{ return(result['plan']) }}
{% endmacro %}


{% macro undeclared_dependencies(plan) %}
  {#
    Guards against a derived feature referencing a column it did not declare
    in depends_on, which would compile to "column not found" at run time on
    one warehouse and silently resolve to something else on another.

    Every derived expression is scanned for identifiers that look like a
    feature column — a name ending in a period mnemonic — and each one must
    appear in that feature's declared dependencies.
  #}
  {% set problems = [] %}
  {% for level in plan['levels'] %}
    {% for item in level %}
      {% if item['definition']['kind'] == 'derived' %}
        {% set declared = [] %}
        {% for dep in item['definition']['depends_on'] %}
          {% do declared.append(jstark.dependency_key(dep[0], dep[1])) %}
        {% endfor %}
        {% set referenced = modules.re.findall(
            '[a-z][a-z0-9_]*_\\d+[dwmqy]\\d+', item['definition']['expression']
        ) %}
        {% for name in referenced %}
          {% if name not in declared %}
            {% do problems.append(item['key'] ~ ' references ' ~ name
                                  ~ ' but does not declare it in depends_on') %}
          {% endif %}
        {% endfor %}
      {% endif %}
    {% endfor %}
  {% endfor %}
  {{ return(problems | unique | list) }}
{% endmacro %}
