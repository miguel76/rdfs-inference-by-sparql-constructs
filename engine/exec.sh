#!/bin/sh
# Usage: ./engine/exec.sh <flow-name>
# Runs flow/<flow-name>.jq and recursively executes the steps it returns.

CONFIG='{"engine_path": "engine", "flow_path": "flow"}'

echo "Executing $1" >&2

CMD=$(jq -n --arg next "$1" '{next: $next}' | jq -r -f engine/to-shell.jq --argjson config "$CONFIG") || exit 1
echo "Executing command: ${CMD}" >&2
eval "$CMD"
