#!/bin/sh
# Usage: ./engine/exec.sh <flow-name>
# Runs flow/<flow-name>.jq and recursively executes the steps it returns.
# Prints the final result (as JSON) on stdout, or the error on stderr
# (exit status 1).

CONFIG='{"engine_path": "engine", "flow_path": "flow"}'

echo "Executing $1" >&2

CMD=$(jq -nc --arg next "$1" '{next: $next}' | jq -rn -f engine/to-shell.jq --argjson config "$CONFIG") || exit 1
echo "Executing command: ${CMD}" >&2
ENVELOPE=$(eval "$CMD")

if printf '%s\n' "$ENVELOPE" | jq -e 'has("error")' >/dev/null; then
    printf '%s\n' "$ENVELOPE" | jq -r '"Error: \(.error | if type == "string" then . else tojson end)"' >&2
    exit 1
fi
printf '%s\n' "$ENVELOPE" | jq '.result'
