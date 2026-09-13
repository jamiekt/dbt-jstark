#!/usr/bin/env bash
#
# Checks that jstark.resolve_as_at warns when it falls back to the run date,
# and stays silent when as_at was supplied.
#
# This lives outside the L1 macro suite because a Jinja macro cannot observe
# that exceptions.warn was called, so the guard deciding whether to warn is
# invisible to every assertion in the suite. Promoting the warning to an error
# turns "did it warn?" into a process exit code this script can assert on.
# See probe_as_at_warning.sql.
#
# Only JinjaLogWarning is promoted, not every warning: a bare --warn-error also
# fails on unrelated project warnings (e.g. unused config paths), which would
# make this check pass for the wrong reason. The probes call nothing else that
# warns, so a JinjaLogWarning here can only be the run-date fallback.
#
# Can be run from anywhere; it cd's to its own directory.

set -uo pipefail

cd "$(dirname "$0")" || exit 1

PROMOTE='{"error": ["JinjaLogWarning"]}'

fail() { echo "FAIL: $1" >&2; exit 1; }

echo "1/2: resolve_as_at(none) must warn (so must fail with the warning promoted)"
output=$(uv run dbt --warn-error-options "$PROMOTE" \
    run-operation jstark_probe_as_at_warning --profiles-dir . 2>&1)
if [ $? -eq 0 ]; then
    echo "$output" >&2
    fail "resolve_as_at(none) did NOT warn about the run-date fallback.
The guard in macros/core/context.sql that emits this warning has been removed,
disabled, or inverted. Users would silently get irreproducible features."
fi
if ! grep -q 'no as_at was supplied' <<< "$output"; then
    echo "$output" >&2
    fail "the run failed, but not with the run-date fallback warning.
Something else is broken; fix that before trusting this check."
fi
echo "     ok - warned, and the message names the cause"

echo "2/2: resolve_as_at(explicit date) must NOT warn"
output=$(uv run dbt --warn-error-options "$PROMOTE" \
    run-operation jstark_probe_as_at_no_warning --profiles-dir . 2>&1)
if [ $? -ne 0 ]; then
    echo "$output" >&2
    fail "resolve_as_at(an explicit date) emitted a warning.
The guard is firing when it should not: anyone passing as_at would be told
their features are irreproducible when they are not."
fi
echo "     ok - silent"

echo "as_at warning checks passed."
