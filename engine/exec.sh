#!/bin/sh

echo "Executing $1"

CMD=$(echo '{"next": "'$1'"}' | jq -f engine/to-shell.jq -r --argjson config '{"engine_path": "engine", "flow_path": "flow"}')
echo "Executing command: ${CMD}"
$("${CMD}")