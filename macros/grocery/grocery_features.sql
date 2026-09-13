{#
  Public entry point for grocery feature generation.

  Thin by design: it names the generator and forwards everything else, so
  there is exactly one implementation of the parameter handling.

  Usage:
    {{ jstark.grocery_features(
        input=ref('transactions'),
        group_by=['customer'],
        as_at='2022-01-01',
        feature_periods=['3m1', '52w0']
    ) }}
#}

{% macro grocery_features(
    input,
    group_by,
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={}
) %}
  {{ jstark.generate_features(
      input=input,
      group_by=group_by,
      generator='grocery',
      as_at=as_at,
      feature_periods=feature_periods,
      feature_stems=feature_stems,
      first_day_of_week=first_day_of_week,
      use_absolute_periods=use_absolute_periods,
      column_map=column_map
  ) }}
{% endmacro %}
