{{ jstark.grocery_features(
    input=ref('grocery_transactions'),
    group_by=['customer'],
    as_at='2022-01-01',
    feature_periods=['3m1'],
    feature_stems=[
        'BasketCount', 'ApproxBasketCount', 'StoreCount', 'ChannelCount',
        'AvgGrossSpendPerBasket', 'AvgQuantityPerBasket', 'AvgDiscountPerBasket',
        'AvgPurchaseCycle', 'CyclesSinceLastPurchase', 'BasketPeriods',
        'AvgBasket', 'RecencyWeightedBasket90', 'RecencyWeightedBasket95',
        'RecencyWeightedBasket99', 'RecencyWeightedApproxBasket90',
        'RecencyWeightedApproxBasket95', 'RecencyWeightedApproxBasket99'
    ]
) }}
