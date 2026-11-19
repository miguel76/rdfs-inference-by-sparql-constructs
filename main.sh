#!/bin/sh

mkdir -p output || { echo "Error: Failed to create output directory" >&2; exit 1; }
./engine/exec.sh main >output/rewrite-rules.json || { echo "Error: Failed to execute main flow" >&2; exit 1; }
