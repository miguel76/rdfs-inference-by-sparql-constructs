#!/bin/sh
# Usage: ./engine/exec.sh <filter>
# Calls <filter> (resolved like a `call` reference: "main" is
# $FLOW_PATH/main.jq, "./x" is relative to the current directory) with null
# input and recursively executes the steps it returns.
# Prints the final result (as JSON) on stdout, or the error on stderr
# (exit status 1).
#
# Configuration (environment variables, relative to the current directory):
#   FLOW_PATH  root for filter references (default: flow)
#   DATA_PATH  root for data file references (default: .)

ENGINE_PATH=$(cd "$(dirname "$0")" && pwd) || exit 1
FLOW_PATH=$(cd "${FLOW_PATH:-flow}" && pwd) || exit 1
DATA_PATH=$(cd "${DATA_PATH:-.}" && pwd) || exit 1

CONFIG=$(jq -nc --arg engine_path "$ENGINE_PATH" --arg flow_path "$FLOW_PATH" --arg data_path "$DATA_PATH" \
    '{engine_path: $engine_path, flow_path: $flow_path, data_path: $data_path}') || exit 1

CMD=$(jq -nc --arg call "$1" '{call: $call}' |
    jq -rn -L "$ENGINE_PATH/lib" -f "$ENGINE_PATH/to-shell.jq" --argjson config "$CONFIG" --arg base "$PWD") || exit 1
ENVELOPE=$(__in=null; eval "$CMD")

if printf '%s\n' "$ENVELOPE" | jq -e 'has("error")' >/dev/null; then
    printf '%s\n' "$ENVELOPE" | jq -r '"Error: \(.error | if type == "string" then . else tojson end)"' >&2
    exit 1
fi
printf '%s\n' "$ENVELOPE" | jq '.result'
