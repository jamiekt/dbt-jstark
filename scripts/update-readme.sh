#!/usr/bin/env bash
# Regenerates the feature tables in README.md from the macros themselves, so
# the documented features cannot drift from the implemented ones. CI runs this
# and fails if it produces a diff.
set -euo pipefail

cd "$(dirname "$0")/.."
readme="README.md"

for generator in grocery mealkit; do
    table="$(mktemp)"
    # --quiet is a global flag, so it goes before the subcommand. grep '^|'
    # keeps only the table, whatever else dbt decides to log.
    (cd integration_tests && uv run dbt --quiet run-operation \
        jstark_generate_feature_reference --profiles-dir . \
        --args "{\"generator\": \"${generator}\"}") \
        | grep '^|' > "${table}"

    updated="$(mktemp)"
    awk -v gen="${generator}" -v table="${table}" '
        $0 == "<!-- BEGIN GENERATED " gen " -->" { print; skip = 1
            while ((getline line < table) > 0) print line
            next }
        $0 == "<!-- END GENERATED " gen " -->" { skip = 0 }
        !skip { print }
    ' "${readme}" > "${updated}"
    mv "${updated}" "${readme}"
    rm -f "${table}"
done

echo "README.md feature tables regenerated."
