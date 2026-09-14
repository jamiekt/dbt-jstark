{#
  Probes for the run-date fallback warning in jstark.resolve_as_at.

  These are NOT part of the L1 suite, and they are not assertions. A Jinja
  macro cannot observe exceptions.warn having been called, so the guard in
  resolve_as_at that decides whether to warn cannot be covered from inside
  the suite: deleting the guard leaves every L1 assertion green.

  Instead these two macros are driven from outside by
  integration_tests/check_as_at_warning.sh, which runs each under
  `dbt --warn-error` — which promotes the warning to a compilation error and
  so makes it observable as a process exit code. The script asserts that the
  no-as_at case FAILS and the explicit-as_at case SUCCEEDS, which pins the
  guard in both directions.
#}

{% macro jstark_probe_as_at_warning() %}
  {% do jstark.resolve_as_at(none) %}
  {% do log('jstark probe: resolve_as_at(none) returned without warning', info=true) %}
{% endmacro %}


{% macro jstark_probe_as_at_no_warning() %}
  {% do jstark.resolve_as_at(modules.datetime.date(2022, 1, 1)) %}
  {% do log('jstark probe: resolve_as_at(explicit) returned without warning', info=true) %}
{% endmacro %}
