{{ jstark.grocery_features(
    input=ref('grocery_transactions'),
    group_by=['customer', 'store'],
    as_at='2022-01-01',
    feature_periods=['3m1', '52w0']
) }}
