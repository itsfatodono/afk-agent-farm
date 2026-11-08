#!/bin/bash
# Usage: inflight.sh <transcript_path>
# Fallback for hooks whose input lacks `background_tasks`: lists unfinished subagents
# from their meta.json files, one per line.
dir="${1%.jsonl}/subagents"
[[ -d "$dir" ]] || exit 0
for m in "$dir"/*.meta.json; do
  [[ -f "$m" ]] || continue
  jq -r 'select((.finished|not) and (.stoppedByUser|not)) | "d\(.spawnDepth) \(.description)"' "$m" 2>/dev/null
done
