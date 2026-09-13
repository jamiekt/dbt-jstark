{#
  Mealkit-specific features.

  register_mealkit_features runs after register_core_features, which for the
  mealkit generator registers only the 10 stems in core_stems_for_mealkit():
  spend and price mean nothing for a business selling recipe boxes at a fixed
  price.
#}

{% macro register_mealkit_features(definitions, ctx) %}
  {% do jstark.register_mealkit_base_features(definitions, ctx) %}
  {% do jstark.register_mealkit_average_features(definitions, ctx) %}
  {% do jstark.register_mealkit_periodic_features(definitions, ctx) %}
  {% do jstark.register_mealkit_cuisine_features(definitions, ctx) %}
{% endmacro %}


{% macro register_mealkit_base_features(definitions, ctx) %}

  {% for spec in [
      {'stem': 'OrderCount', 'aggregator': 'count_distinct', 'column': 'order_id',
       'subject': 'Distinct count of Orders',
       'commentary': 'The number of orders. Typically the dataframe supplied '
           ~ 'to this feature will have many recipes for the same order, '
           ~ 'this feature allows you to determine how many distinct orders '
           ~ 'existed in that collection of orders.'},
      {'stem': 'ApproxOrderCount', 'aggregator': 'approx_count_distinct',
       'column': 'order_id', 'subject': 'Approximate distinct count of Orders',
       'commentary': 'The approximate number of orders. Similar to '
           ~ ('OrderCount_' ~ ctx['period']['mnemonic'] ~ ' ')
           ~ 'except that it uses an approximation algorithm which '
           ~ 'will not be as accurate as '
           ~ ('OrderCount_' ~ ctx['period']['mnemonic'] ~ ' but will be a lot ')
           ~ 'quicker to compute and in many cases will be "close enough".'},
      {'stem': 'RecipeCount', 'aggregator': 'count_distinct', 'column': 'recipe',
       'subject': 'Distinct count of Recipes',
       'commentary': 'The number of recipes. Typically the dataframe supplied '
           ~ 'to this feature will have many recipes for the same order, '
           ~ 'this feature allows you to determine how many distinct recipes '
           ~ 'existed in that collection of recipes.'},
      {'stem': 'ApproxRecipeCount', 'aggregator': 'approx_count_distinct',
       'column': 'recipe', 'subject': 'Approximate distinct count of Recipes',
       'commentary': 'The approximate number of recipes. Similar to '
           ~ ('RecipeCount_' ~ ctx['period']['mnemonic'] ~ ' ')
           ~ 'except that it uses an approximation algorithm which '
           ~ 'will not be as accurate as '
           ~ ('RecipeCount_' ~ ctx['period']['mnemonic'] ~ ' but will be a lot ')
           ~ 'quicker to compute and in many cases will be "close enough".'},
      {'stem': 'AllergenCount', 'aggregator': 'count_distinct', 'column': 'allergen',
       'subject': 'Distinct count of Allergens',
       'commentary': 'The number of allergens. Typically the dataframe supplied '
           ~ 'to this feature will have many recipes for the same allergen, '
           ~ 'this feature allows you to determine how many distinct allergens '
           ~ 'have been ordered.'},
      {'stem': 'CuisineCount', 'aggregator': 'count_distinct', 'column': 'cuisine',
       'subject': 'Distinct count of Cuisines',
       'commentary': 'The number of cuisines. Typically the dataframe supplied '
           ~ 'to this feature will have many recipes for the same cuisine, '
           ~ 'this feature allows you to determine how many distinct cuisines '
           ~ 'have been ordered.'}
  ] %}
    {% do definitions.update({spec['stem']: {
        'stem': spec['stem'],
        'kind': 'base',
        'aggregator': spec['aggregator'],
        'expression': ctx['cols'][spec['column']],
        'default': '0',
        'required_columns': ['event_timestamp', spec['column']],
        'description_subject': spec['subject'],
        'commentary': spec['commentary']
    }}) %}
  {% endfor %}

  {#- the two set-valued features. Registered after the counts so that
      allergen_count sits next to allergens in the output. -#}
  {% for spec in [
      {'stem': 'Allergens', 'column': 'allergen', 'subject': 'Set of Allergens',
       'commentary': 'The set of allergens. Typically the dataframe supplied '
           ~ 'to this feature will have many recipes for the same allergen, '
           ~ 'this feature allows you to determine the set of allergens '
           ~ 'that have been ordered.'},
      {'stem': 'Cuisines', 'column': 'cuisine', 'subject': 'Set of Cuisines',
       'commentary': 'The set of cuisines. Typically the dataframe supplied '
           ~ 'to this feature will have many recipes for the same cuisine, '
           ~ 'this feature allows you to determine the set of cuisines '
           ~ 'that have been ordered.'}
  ] %}
    {% do definitions.update({spec['stem']: {
        'stem': spec['stem'],
        'kind': 'base',
        'aggregator': 'collect_set',
        'expression': ctx['cols'][spec['column']],
        'default': jstark.empty_string_array(),
        'required_columns': ['event_timestamp', spec['column']],
        'description_subject': spec['subject'],
        'commentary': spec['commentary']
    }}) %}
  {% endfor %}

{% endmacro %}
