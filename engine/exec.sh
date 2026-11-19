#!/usr/bin/env bash
# Usage: ./engine/exec.sh <flow-name>
# Runs flow/<flow-name>.jq and recursively executes the steps it returns.
#
# Error handling: the generated scripts are pipelines nested in subshells and
# command substitutions, so we need all of
#   -e              stop at the first failing command
#   -o pipefail     a pipeline fails if any of its stages fails
#   inherit_errexit -e also applies inside $( ... )
# Shell options are inherited by the subshells the generated script creates.
set -eo pipefail
shopt -s inherit_errexit

CONFIG='{"engine_path": "engine", "flow_path": "flow"}'

echo "Executing $1" >&2

CMD=$(jq -n --arg next "$1" '{next: $next}' | jq -r -f engine/to-shell.jq --argjson config "$CONFIG")
echo "Executing command: ${CMD}" >&2
eval "$CMD"
