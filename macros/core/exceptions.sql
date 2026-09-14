{#
  Named compile-time errors.

  Every error jstark raises goes through raise_error so that the message
  format is uniform and so that L1 tests can assert on the exact text
  without needing try/except (which Jinja does not have).
#}

{% macro error_codes() %}
  {{ return({
      'mnemonic_is_invalid': 'feature_period_mnemonic_is_invalid',
      'end_greater_than_start': 'feature_period_end_greater_than_start',
      'feature_not_found': 'feature_not_found',
      'invalid_first_day_of_week': 'invalid_first_day_of_week',
      'unknown_aggregator': 'unknown_aggregator',
      'as_at_is_not_a_date': 'as_at_is_not_a_date',
      'unknown_generator': 'unknown_generator',
      'duplicate_column_name': 'duplicate_column_name',
      'invalid_cuisine': 'invalid_cuisine',
      'invalid_group_by': 'invalid_group_by',
      'unsupported_adapter': 'unsupported_adapter'
  }) }}
{% endmacro %}


{% macro unsupported_adapter_detail(macro_name, adapter_type) %}
  {#
    The detail for a dispatched macro whose default__ cannot be written
    portably. Shared by every such default__ so the wording, and the
    instruction it gives, stay identical; and separate from the raise so an
    L1 assertion can pin the text for an adapter that is not the one running.
  #}
  {{ return(
      "no " ~ adapter_type ~ '__' ~ macro_name ~ ' is defined and there is no '
      ~ 'portable default for it. Add ' ~ adapter_type ~ '__' ~ macro_name
      ~ ' to macros/core/adapters/' ~ macro_name ~ '.sql. jstark stops here '
      ~ "rather than emitting another warehouse's dialect, which would fail "
      ~ 'as an unexplained syntax error instead.'
  ) }}
{% endmacro %}


{% macro error_message(code, detail) %}
  {{ return('jstark: ' ~ code ~ ': ' ~ detail) }}
{% endmacro %}


{% macro raise_error(code, detail) %}
  {{ exceptions.raise_compiler_error(jstark.error_message(code, detail)) }}
{% endmacro %}
