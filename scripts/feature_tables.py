"""Renders the feature reference tables that README.md embeds via cog.

The rows come from the macros themselves — jstark_generate_feature_reference
runs inside dbt and prints markdown — so the documented features cannot drift
from the implemented ones. CI runs cog in --check mode and fails on a stale
README; see .github/workflows/build.yml.

Regenerate with:
    uv run cog -r -I scripts README.md
"""

import json
import subprocess
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent / "integration_tests"


def feature_table(generator):
    """The markdown table for one generator, as a string with no trailing newline.

    Assumes dbt is on PATH, which it is when cog runs under `uv run`.
    """
    # --quiet is a global flag, so it precedes the subcommand.
    completed = subprocess.run(
        [
            "dbt", "--quiet", "run-operation",
            "jstark_generate_feature_reference",
            "--profiles-dir", ".",
            "--args", json.dumps({"generator": generator}),
        ],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        check=True,
    )

    # Keeping only the lines starting with '|' discards whatever else dbt
    # decides to log. An empty result means the macro printed nothing, which
    # would otherwise silently blank the table in the README.
    rows = [line for line in completed.stdout.splitlines() if line.startswith("|")]
    if not rows:
        raise RuntimeError(
            f"jstark_generate_feature_reference produced no table rows for the "
            f"{generator} generator.\nstdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )
    return "\n".join(rows)
