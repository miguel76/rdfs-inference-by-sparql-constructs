#!/bin/sh
# Generates the rewrite rules into output/rewrite-rules.json.
# Requires the dependencies installed with `jqpm install` (see README.md).

cd "$(dirname "$0")" || exit 1

ASYNC_JQ=jq_modules/.bin/async-jq
if [ ! -x "$ASYNC_JQ" ]; then
    echo "Error: $ASYNC_JQ not found: install the dependencies with \`jqpm install\`" >&2
    exit 1
fi

mkdir -p output || { echo "Error: Failed to create output directory" >&2; exit 1; }
"$ASYNC_JQ" -L jq_modules main >output/rewrite-rules.json || { echo "Error: Failed to execute main flow" >&2; exit 1; }
