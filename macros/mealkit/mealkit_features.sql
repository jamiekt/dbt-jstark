{#
  Public entry point for mealkit feature generation.

  Identical to grocery_features except for the generator name and the extra
  `cuisines` parameter, which decides how many per-cuisine counts to emit.

  Usage:
    {{ jstark.mealkit_features(
        input=ref('orders'),
        group_by=['customer'],
        as_at='2022-01-01',
        feature_periods=['3m1'],
        cuisines=['Italian', 'Thai', 'South African']
    ) }}
#}

{% macro mealkit_features(
    input,
    group_by,
    as_at=none,
    feature_periods=none,
    feature_stems=none,
    first_day_of_week=none,
    use_absolute_periods=false,
    column_map={},
    cuisines=[]
) %}
  {{ jstark.generate_features(
      input=input,
      group_by=group_by,
      generator='mealkit',
      as_at=as_at,
      feature_periods=feature_periods,
      feature_stems=feature_stems,
      first_day_of_week=first_day_of_week,
      use_absolute_periods=use_absolute_periods,
      column_map=column_map,
      cuisines=cuisines
  ) }}
{% endmacro %}
