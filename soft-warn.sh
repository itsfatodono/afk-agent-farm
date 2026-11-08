#!/bin/bash
# PostToolUse: once the context crosses a threshold, tell the main agent to wind down.
# It never interrupts work; it only adds a message to the context.
[[ -n "${UA_SEG_DIR:-}" ]] || exit 0
input=$(cat)
H="$(dirname "$0")"; source "$H/overrides.sh"
# Skip tool calls made by subagents; the warning is for the main agent only.
[[ -n "$(jq -r '.agent_id // empty' <<<"$input")" ]] && exit 0
transcript=$(jq -r .transcript_path <<<"$input"); echo "$transcript" > "$UA_SEG_DIR/transcript"  # run-farmer.sh reads it
used=$("$H/ctx.sh" "$transcript"); used=${used:-0}
echo "$(date +%T) post used=$used" >> "$UA_SEG_DIR/hooks.log"

msg=""
if (( used > UA_HARD )) && [[ ! -f "$UA_SEG_DIR/emergency" ]]; then
  touch "$UA_SEG_DIR/emergency"
  msg="[unattended] Context is at ${used} tokens, past the emergency threshold of ${UA_HARD}. Start no new work. Tell your running agents to stop where they are and save their work as WIP, wait for their reports, then end your turn. Handoff instructions will follow."
elif (( used > UA_SOFT )) && [[ ! -f "$UA_SEG_DIR/wind-down" ]]; then
  touch "$UA_SEG_DIR/wind-down"
  msg="[unattended] Context is at ${used} tokens, past the threshold of ${UA_SOFT}. Start no new work. Finish what you have in hand, including running agents, and process their results. When everything is done, end your turn. Handoff instructions will follow."
fi
[[ -n "$msg" ]] || exit 0
echo "$(date +%T) WARN ${msg:0:70}" >> "$UA_SEG_DIR/hooks.log"
jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
