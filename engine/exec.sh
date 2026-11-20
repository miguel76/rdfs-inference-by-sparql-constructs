#!/bin/sh
# Usage: ./engine/exec.sh [options] <filter>
# Calls <filter> (resolved like a `call` reference: "main" is
# $FLOW_PATH/main.jq, "./x" is relative to the current directory) and
# recursively executes the steps it returns.
# Prints the final result (as JSON) on stdout, or the error on stderr
# (exit status 1).
#
# Options:
#   --input JSON   input of the filter (default: null)
#   --stdin        read the input of the filter (one JSON value) from stdin
#   --args JSON    object of named arguments for the filter (as `args` in a
#                  call step)
#
# Configuration (environment variables, relative to the current directory):
#   FLOW_PATH  root for filter references (default: flow)
#   DATA_PATH  root for data file references (default: .)

usage() {
    echo "Usage: $0 [--input JSON | --stdin] [--args JSON] <filter>" >&2
    exit 1
}

INPUT=null
ARGS=null
while [ $# -gt 0 ]; do
    case "$1" in
        --input) [ $# -ge 2 ] || usage; INPUT=$2; shift 2 ;;
        --stdin) INPUT=$(cat) || exit 1; shift ;;
        --args) [ $# -ge 2 ] || usage; ARGS=$2; shift 2 ;;
        -*) usage ;;
        *) break ;;
    esac
done
[ $# -eq 1 ] || usage

ENGINE_PATH=$(cd "$(dirname "$0")" && pwd) || exit 1
FLOW_PATH=$(cd "${FLOW_PATH:-flow}" && pwd) || exit 1
DATA_PATH=$(cd "${DATA_PATH:-.}" && pwd) || exit 1

CONFIG=$(jq -nc --arg engine_path "$ENGINE_PATH" --arg flow_path "$FLOW_PATH" --arg data_path "$DATA_PATH" \
    '{engine_path: $engine_path, flow_path: $flow_path, data_path: $data_path}') || exit 1

# the input goes to jq on stdin (it may be large), and must be one JSON value
STEP=$(printf '%s\n' "$INPUT" | jq -sc --arg call "$1" --argjson args "$ARGS" '
    if length != 1 then error("the input must be exactly one JSON value, got \(length)") else .[0] end |
    {call: $call, input: .} + (if $args == null then {} else {args: $args} end)') || usage

CMD=$(printf '%s\n' "$STEP" |
    jq -rn -L "$ENGINE_PATH/lib" -f "$ENGINE_PATH/to-shell.jq" --argjson config "$CONFIG" --arg base "$PWD") || exit 1
ENVELOPE=$(__in=null; eval "$CMD")

if printf '%s\n' "$ENVELOPE" | jq -e 'has("error")' >/dev/null; then
    printf '%s\n' "$ENVELOPE" | jq -r '"Error: \(.error | if type == "string" then . else tojson end)"' >&2
    exit 1
fi
printf '%s\n' "$ENVELOPE" | jq '.result'
