{{ jstark.generate_features(
    input=ref('core_transactions'),
    group_by=['customer'],
    generator='core',
    as_at='2022-01-01',
    feature_periods=['3m1']
) }}
