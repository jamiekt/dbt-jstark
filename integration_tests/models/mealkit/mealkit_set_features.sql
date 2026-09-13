{{ jstark.mealkit_features(
    input=ref('mealkit_orders'),
    group_by=['customer'],
    as_at='2022-01-01',
    feature_periods=['3m1'],
    feature_stems=['Allergens', 'Cuisines']
) }}
