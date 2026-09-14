{{ jstark.generate_features(
    input=ref('jstark_test_input'),
    group_by=['customer'],
    generator='test',
    as_at='2022-01-01',
    feature_periods=['3m1'],
    feature_stems=['TestSpend', 'TestBasketCount', 'TestSpendPerBasket']
) }}
