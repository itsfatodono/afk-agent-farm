#!/bin/bash
# Usage: inflight.sh <transcript_path> <segment_dir>
# The one list of running work, for both finish-gate.sh and run-farmer.sh, one item per line:
#  - the running background tasks (agents, workflows, shell commands, monitors) the Stop hook
#    saw at the agent's last stop, kept in <segment_dir>/tasks.json by finish-gate.sh. A task
#    finishing wakes the agent, and its next stop rewrites the file. In case that wake never
#    comes, a file older than UA_TASK_MAX seconds counts as empty, so the idle nudges still fire.
#  - unfinished subagents from their meta.json files, which also list a subagent whose parent
#    agent has already finished.
t="${1:-}"; s="${2:-}"
f="$s/tasks.json"
if [[ -n "$s" && -f "$f" ]]; then
  age=$(( $(date +%s) - $(stat -f %m "$f") ))
  (( age <= ${UA_TASK_MAX:-3600} )) && jq -r '.[]? | select(.status=="running")
    | "task \(.description // .type // "task")"' "$f" 2>/dev/null
fi
dir="${t%.jsonl}/subagents"
[[ -n "$t" && -d "$dir" ]] || exit 0
for m in "$dir"/*.meta.json; do
  [[ -f "$m" ]] || continue
  jq -r 'select((.finished|not) and (.stoppedByUser|not)) | "d\(.spawnDepth) \(.description)"' "$m" 2>/dev/null
done
