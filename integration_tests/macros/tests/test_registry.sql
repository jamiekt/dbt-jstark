{% macro jstark_test_registry(results) %}

  {% set d = modules.datetime.date %}
  {% set as_at = d(2022, 1, 1) %}
  {% set cols = jstark.resolve_columns({}) %}

  {# --- single_unit_periods expands a window into whole units --- #}
  {% do jstark_assert_equal(
      results, 'single_unit_periods(3m1)',
      jstark.single_unit_periods(jstark.parse_feature_period('3m1'))
        | map(attribute='mnemonic') | list,
      ['1m1', '2m2', '3m3']
  ) %}
  {% do jstark_assert_equal(
      results, 'single_unit_periods(0d0)',
      jstark.single_unit_periods(jstark.parse_feature_period('0d0'))
        | map(attribute='mnemonic') | list,
      ['0d0']
  ) %}
  {% do jstark_assert_equal(
      results, 'single_unit_periods(2w0)',
      jstark.single_unit_periods(jstark.parse_feature_period('2w0'))
        | map(attribute='mnemonic') | list,
      ['0w0', '1w1', '2w2']
  ) %}

  {# --- the test catalogue is the fixture the rest of this group uses --- #}
  {% set ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  ) %}
  {% set cat = jstark.catalogue('test', ctx) %}
  {% do jstark_assert_equal(
      results, 'test catalogue stems',
      cat.keys() | list, ['TestSpend', 'TestBasketCount', 'TestSpendPerBasket',
                          'TestSpendPerBasketPerBasket', 'TestActiveMonths']
  ) %}
  {% do jstark_assert_equal(
      results, 'TestSpend is base', cat['TestSpend']['kind'], 'base'
  ) %}
  {% do jstark_assert_equal(
      results, 'TestSpendPerBasket is derived',
      cat['TestSpendPerBasket']['kind'], 'derived'
  ) %}

  {# --- generators are enumerated in one place --- #}
  {% do jstark_assert_equal(
      results, 'generators()',
      jstark.generators(), ['core', 'grocery', 'mealkit', 'test']
  ) %}

  {# --- an unknown stem names the valid ones --- #}
  {% set bad = jstark.try_build_plan(
      'test', ['NoSuchFeature'], [jstark.parse_feature_period('3m1')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(results, 'unknown stem ok', bad['ok'], false) %}
  {% do jstark_assert_equal(
      results, 'unknown stem error', bad['error'],
      jstark.error_message(
          jstark.error_codes()['feature_not_found'],
          "['NoSuchFeature'] not found. Valid feature stems for the test "
          ~ 'generator are: TestActiveMonths, TestBasketCount, TestSpend, '
          ~ 'TestSpendPerBasket, TestSpendPerBasketPerBasket'
      )
  ) %}

  {# --- a base-only request produces one level --- #}
  {% set plan = jstark.build_plan(
      'test', ['TestSpend'], [jstark.parse_feature_period('3m1')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(results, 'base-only levels', plan['levels'] | length, 1) %}
  {% do jstark_assert_equal(
      results, 'base-only level 0 keys',
      plan['levels'][0] | map(attribute='key') | list, ['test_spend_3m1']
  ) %}
  {% do jstark_assert_equal(
      results, 'base-only requested',
      plan['requested'] | map(attribute='key') | list, ['test_spend_3m1']
  ) %}

  {# --- a two-deep derived chain produces three levels, and pulls in
         dependencies the caller never asked for --- #}
  {% set plan2 = jstark.build_plan(
      'test', ['TestSpendPerBasketPerBasket'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(results, 'chain levels', plan2['levels'] | length, 3) %}
  {% do jstark_assert_equal(
      results, 'chain level 0',
      plan2['levels'][0] | map(attribute='key') | sort | list,
      ['test_basket_count_3m1', 'test_spend_3m1']
  ) %}
  {% do jstark_assert_equal(
      results, 'chain level 1',
      plan2['levels'][1] | map(attribute='key') | list, ['test_spend_per_basket_3m1']
  ) %}
  {% do jstark_assert_equal(
      results, 'chain level 2',
      plan2['levels'][2] | map(attribute='key') | list,
      ['test_spend_per_basket_per_basket_3m1']
  ) %}
  {% do jstark_assert_equal(
      results, 'chain requested is only what was asked for',
      plan2['requested'] | map(attribute='key') | list,
      ['test_spend_per_basket_per_basket_3m1']
  ) %}
  {% do jstark_assert_equal(
      results, 'pulled-in dependencies are not requested',
      plan2['levels'][0] | selectattr('requested') | list | length, 0
  ) %}

  {# --- a cross-period dependency pulls in sub-period base features --- #}
  {% set plan3 = jstark.build_plan(
      'test', ['TestActiveMonths'], [jstark.parse_feature_period('3m1')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'cross-period level 0',
      plan3['levels'][0] | map(attribute='key') | sort | list,
      ['test_basket_count_1m1', 'test_basket_count_2m2', 'test_basket_count_3m3']
  ) %}
  {% do jstark_assert_equal(
      results, 'cross-period level 1',
      plan3['levels'][1] | map(attribute='key') | list, ['test_active_months_3m1']
  ) %}
  {% do jstark_assert_equal(
      results, 'cross-period dependency contexts differ',
      plan3['levels'][0][0]['ctx']['period']['mnemonic'] !=
        plan3['levels'][1][0]['ctx']['period']['mnemonic'],
      true
  ) %}

  {# --- a shared dependency is computed once, not twice --- #}
  {% set plan4 = jstark.build_plan(
      'test', ['TestSpendPerBasket', 'TestSpendPerBasketPerBasket'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'shared dependency deduplicated',
      plan4['levels'][0] | map(attribute='key') | sort | list,
      ['test_basket_count_3m1', 'test_spend_3m1']
  ) %}
  {% do jstark_assert_equal(
      results, 'a dependency that is also requested is marked requested',
      plan4['levels'][1] | selectattr('requested') | map(attribute='key') | list,
      ['test_spend_per_basket_3m1']
  ) %}

  {# --- requested order is stem-outer, period-inner --- #}
  {% set plan5 = jstark.build_plan(
      'test', ['TestSpend', 'TestBasketCount'],
      [jstark.parse_feature_period('3m1'), jstark.parse_feature_period('0d0')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'requested order',
      plan5['requested'] | map(attribute='key') | list,
      ['test_spend_3m1', 'test_spend_0d0',
       'test_basket_count_3m1', 'test_basket_count_0d0']
  ) %}

  {# --- an empty feature_stems means every feature, in catalogue order --- #}
  {% set plan6 = jstark.build_plan(
      'test', [], [jstark.parse_feature_period('3m1')],
      as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'no feature_stems means all of them, in catalogue order',
      plan6['requested'] | map(attribute='stem') | list,
      ['TestSpend', 'TestBasketCount', 'TestSpendPerBasket',
       'TestSpendPerBasketPerBasket', 'TestActiveMonths']
  ) %}

  {# --- feature_stems order does not affect column order --- #}
  {% set plan7 = jstark.build_plan(
      'test', ['TestBasketCount', 'TestSpend'],
      [jstark.parse_feature_period('3m1')], as_at, 'Monday', false, cols, []
  ) %}
  {% do jstark_assert_equal(
      results, 'column order follows the catalogue, not the request',
      plan7['requested'] | map(attribute='stem') | list,
      ['TestSpend', 'TestBasketCount']
  ) %}

  {# --- every derived expression only references declared dependencies --- #}
  {% do jstark_assert_equal(
      results, 'derived expressions declare their dependencies',
      jstark.undeclared_dependencies(plan6), []
  ) %}

  {#- The assertion above passes just as happily if undeclared_dependencies is
      broken and always returns []. These two pin it from the other side: it must
      report a genuine undeclared reference, and must NOT report a quoted literal
      that merely looks like a feature column. -#}
  {% set undeclared_plan = {'levels': [[{
      'key': 'fake_3m1',
      'definition': {
          'kind': 'derived',
          'depends_on': [],
          'expression': 'test_spend_3m1 + 1'
      }
  }]]} %}
  {% do jstark_assert_equal(
      results, 'undeclared_dependencies reports an undeclared reference',
      jstark.undeclared_dependencies(undeclared_plan),
      ['fake_3m1 references test_spend_3m1 but does not declare it in depends_on']
  ) %}

  {% set literal_plan = {'levels': [[{
      'key': 'fake_3m1',
      'definition': {
          'kind': 'derived',
          'depends_on': [],
          'expression': "case when promo_code = 'promo_5d1' then 1 else 0 end"
      }
  }]]} %}
  {% do jstark_assert_equal(
      results, 'undeclared_dependencies ignores quoted literals',
      jstark.undeclared_dependencies(literal_plan), []
  ) %}

  {# --- the core catalogue is complete and in a fixed order --- #}
  {% set core_ctx = jstark.feature_context(
      jstark.parse_feature_period('3m1'), as_at, 'Monday', false, cols, []
  ) %}
  {% set core_cat = jstark.catalogue('core', core_ctx) %}
  {% do jstark_assert_equal(
      results, 'core catalogue',
      core_cat.keys() | list,
      ['Count', 'CustomerCount', 'ApproxCustomerCount', 'ProductCount',
       'ApproxProductCount', 'Quantity', 'Discount', 'GrossSpend', 'NetSpend',
       'MinGrossSpend', 'MaxGrossSpend', 'MinNetSpend', 'MaxNetSpend',
       'MinGrossPrice', 'MaxGrossPrice', 'MinNetPrice', 'MaxNetPrice',
       'RecencyDays', 'EarliestPurchaseDate', 'MostRecentPurchaseDate']
  ) %}

  {# --- every core feature is a base feature, and every one is fully specified --- #}
  {% for stem, definition in core_cat.items() %}
    {% do jstark_assert_equal(
        results, stem ~ ' is base', definition['kind'], 'base'
    ) %}
    {% do jstark_assert_true(
        results, stem ~ ' has a valid aggregator',
        definition['aggregator'] in jstark.aggregators()
    ) %}
    {% do jstark_assert_true(
        results, stem ~ ' has an expression', definition['expression']
    ) %}
    {% do jstark_assert_true(
        results, stem ~ ' has a default', definition['default']
    ) %}
    {% do jstark_assert_true(
        results, stem ~ ' has a description_subject', definition['description_subject']
    ) %}
    {% do jstark_assert_true(
        results, stem ~ ' has commentary', definition['commentary']
    ) %}
    {% do jstark_assert_true(
        results, stem ~ ' requires event_timestamp',
        'event_timestamp' in definition['required_columns']
    ) %}
    {% for column in definition['required_columns'] %}
      {% do jstark_assert_true(
          results, stem ~ ' requires only canonical columns (' ~ column ~ ')',
          column in jstark.canonical_columns()
      ) %}
    {% endfor %}
  {% endfor %}

  {# --- the min/max default asymmetry is deliberate parity with jstark --- #}
  {% do jstark_assert_equal(
      results, 'MinGrossSpend default', core_cat['MinGrossSpend']['default'], '0.0'
  ) %}
  {% do jstark_assert_equal(
      results, 'MaxGrossSpend default', core_cat['MaxGrossSpend']['default'], 'null'
  ) %}

  {# --- Quantity sums as an integer, Discount as a float --- #}
  {% do jstark_assert_equal(
      results, 'Quantity default', core_cat['Quantity']['default'], '0'
  ) %}
  {% do jstark_assert_equal(
      results, 'Discount default', core_cat['Discount']['default'], '0.0'
  ) %}

  {#- CONTROLLER CORRECTION (do not restore the original): the brief here
      originally asserted core_cat['RecencyDays']['expression'] equalled a
      dbt.datediff(...) call with the same three arguments the implementation
      passes. That is tautological — reversing the argument order changes both
      sides identically, so the assertion passes while every recency value comes
      out negative. It cannot be repaired by pinning a literal string either,
      because dbt.datediff renders differently per adapter and this suite must
      pass on BigQuery too. The direction is instead pinned by the L2 unit test
      core_features_values, which expects recency_days_3m1 = 1; a reversal makes
      it -1. Assert only what is adapter-independent here. -#}
  {% do jstark_assert_true(
      results, 'RecencyDays expression mentions as_at, not just the event date',
      "date '2022-01-01'" in core_cat['RecencyDays']['expression']
  ) %}

  {#- Four core commentary strings are assembled from jstark's f-string
      concatenation rather than copied whole, because jstark interpolates
      self.feature_period.mnemonic into them. Only truthiness was pinned for
      these ('... has commentary' in the loop above), so a wrong splice
      position, wrong surrounding wording, or a reverted f-string placeholder
      would pass silently. These four are written out as whole literals (using
      core_ctx's own mnemonic, '3m1') rather than rebuilt via
      ctx['period']['mnemonic'] concatenation, so this cannot pass vacuously by
      mirroring the implementation's own assembly. Typos and spacing artefacts
      from jstark's source (double space, no space after a full stop) are
      preserved exactly, as in the definitions themselves. -#}
  {% do jstark_assert_equal(
      results, 'ApproxCustomerCount commentary interpolates the period mnemonic',
      core_cat['ApproxCustomerCount']['commentary'],
      'The approximate number of customers. Similar to CustomerCount_3m1 '
      ~ 'except that it uses an approximation algorithm which '
      ~ 'will not be as accurate as CustomerCount_3m1 but will be a lot '
      ~ 'quicker to compute and in many cases will be "close enough".'
  ) %}
  {% do jstark_assert_equal(
      results, 'ApproxProductCount commentary interpolates the period mnemonic',
      core_cat['ApproxProductCount']['commentary'],
      'The approximate number of products. Similar to ProductCount_3m1 '
      ~ 'except that it uses an approximation algorithm which '
      ~ 'will not be as accurate as ProductCount_3m1 but will be a lot '
      ~ 'quicker to compute and in many cases will be "close enough".'
  ) %}
  {% do jstark_assert_equal(
      results, 'RecencyDays commentary interpolates the period mnemonic',
      core_cat['RecencyDays']['commentary'],
      'This could be particularly useful (for example) in a grocery retailer '
      ~ 'for determining when a customer most recently bought a product or '
      ~ ' when a product was most recently bought in a store'
      ~ 'Also note that this is very similar to '
      ~ 'MostRecentPurchaseDate_3m1 '
      ~ 'so consider which of these '
      ~ 'features is most useful to you.'
  ) %}
  {% do jstark_assert_equal(
      results, 'MostRecentPurchaseDate commentary interpolates the period mnemonic',
      core_cat['MostRecentPurchaseDate']['commentary'],
      'It is useful to be able to see when something was most recently '
      ~ 'purchased.For example, grouping by Store and filtering where '
      ~ 'MostRecentPurchaseDate is more than 2 days ago could be a useful '
      ~ 'indicator of things which might not be available for purchase.'
      ~ 'Also note that this is very similar to '
      ~ 'RecencyDays_3m1 so consider which of these '
      ~ 'features is most useful to you.'
  ) %}

  {#- Mandated by the Task 9 ruling: every generator's full catalogue must have
      this assertion, or the guard is unarmed for that generator. Core is all
      base features today, so it has nothing to find; it is asserted anyway so
      the coverage exists the moment a derived core feature is added. -#}
  {% do jstark_assert_equal(
      results, 'core derived expressions declare their dependencies',
      jstark.undeclared_dependencies(jstark.build_plan(
          'core', [], [jstark.parse_feature_period('3m1')],
          as_at, 'Monday', false, cols, []
      )),
      []
  ) %}

  {# --- mealkit takes only 10 of the core features --- #}
  {% do jstark_assert_equal(
      results, 'core_stems_for_mealkit',
      jstark.core_stems_for_mealkit(),
      ['Count', 'CustomerCount', 'ApproxCustomerCount', 'ProductCount',
       'ApproxProductCount', 'Quantity', 'Discount', 'RecencyDays',
       'EarliestPurchaseDate', 'MostRecentPurchaseDate']
  ) %}

{% endmacro %}
