#!/bin/bash
# Stop: runs whenever the main agent wants to stop. In order:
#  1. work still running     → let it stop; their task notifications wake the main agent again
#  2. last message has the completion signal, not in wind-down → mark COMPLETE, close
#  3. threshold first crossed here → wind-down warning
#  4. in wind-down           → have it write the handoff; close once written. The signal
#     counts for nothing here: a context limit is no reason to call the goal done, so a
#     goal that really is done goes through one short segment that confirms it.
#  5. none of the above      → "keep going or emit the signal" (a segment can't end silently)
[[ -n "${UA_SEG_DIR:-}" ]] || exit 0
input=$(cat)
H="$(dirname "$0")"; S="$UA_SEG_DIR"; source "$H/overrides.sh"
SIGNAL='<promise>COMPLETE</promise>'
log() { echo "$(date +%T) stop $*" >> "$S/hooks.log"; }
close() { log "used=$used $1 -> close"; touch "$S/closed"; jq -n --arg r "[unattended] $2" '{continue:false, stopReason:$r}'; exit 0; }
block() {  # block <counter-file> <limit> <log-label> <message>
  local n=$(( $(cat "$S/$1" 2>/dev/null || echo 0) + 1 )); echo $n > "$S/$1"
  if (( n > $2 )); then log "used=$used $3 giving up after $n"; exit 0; fi
  log "used=$used $3 #$n"
  jq -n --arg m "[unattended] $4" '{decision:"block", reason:$m}'; exit 0
}

transcript=$(jq -r .transcript_path <<<"$input"); echo "$transcript" > "$S/transcript"  # run-farmer.sh reads it
used=$("$H/ctx.sh" "$transcript"); used=${used:-0}

# Running work: every running background task in the hook input (agents, workflows, shell
# commands, monitors), plus the subagents' meta.json files, which also list a subagent whose
# parent agent has already finished.
inflight=$( { jq -r '.background_tasks[]? | select(.status=="running")
                | .description // .type // "task"' <<<"$input" 2>/dev/null
              "$H/inflight.sh" "$transcript"; } | sed '/^$/d')
if [[ -n "$inflight" ]]; then
  # Record a threshold crossing now; the warning goes out once the agents are back.
  (( used > UA_SOFT )) && [[ ! -f "$S/wind-down" ]] && touch "$S/wind-down"
  # Agents running means real progress: the continue limit counts stops in a row without any.
  rm -f "$S/continue-blocks"
  log "used=$used wait inflight=$(wc -l <<<"$inflight" | tr -d ' ')"
  exit 0
fi

# Last message: from the hook input when present, else from the transcript (main agent, text only).
last=$(jq -r '.last_assistant_message // empty' <<<"$input")
[[ -n "$last" ]] || last=$(tail -r "$transcript" 2>/dev/null \
  | jq -r 'select(.type=="assistant" and (.isSidechain|not)) | [.message.content[]? | select(.type=="text") | .text] | join("\n") | select(length>0)' 2>/dev/null \
  | head -c 20000)
ref=""; [[ -f "$S/wind-down" ]] && ref="$S/wind-down"; [[ -f "$S/emergency" ]] && ref="$S/emergency"
if [[ -z "$ref" ]] && grep -qF "$SIGNAL" <<<"$last"; then
  touch "$S/COMPLETE"; close "COMPLETE" "Goal complete."
fi

if (( used > UA_SOFT )) && [[ ! -f "$S/wind-down" && ! -f "$S/emergency" ]]; then
  touch "$S/wind-down"
  block warns 1 "WARN at stop" "Context is at ${used} tokens, past the threshold of ${UA_SOFT}. Start no new work. Finish what you have in hand, including running agents, and process their results. When everything is done, end your turn. Handoff instructions will follow."
fi

ref=""; [[ -f "$S/wind-down" ]] && ref="$S/wind-down"; [[ -f "$S/emergency" ]] && ref="$S/emergency"
if [[ -n "$ref" ]]; then
  grep -qF "$SIGNAL" <<<"$last" && log "used=$used signal ignored in wind-down"
  [[ -f "$UA_HANDOFF" && "$UA_HANDOFF" -nt "$ref" ]] && close "handoff ok" "Handoff written, closing this segment."
  block handoff-blocks "${UA_HANDOFF_LIMIT:-5}" "block handoff" "This segment is closing. Read ~/.agents/skills/handoff/SKILL.md and follow it, except save the document to exactly this path instead of \$TMPDIR: $UA_HANDOFF . A new segment will continue from it with the same goal. Reaching the context limit does not end the goal: list every part of it still open, including work that is ready but not started. If you believe the goal is fully done, say so in the handoff with the evidence; the next segment checks it and ends the run. End your turn once it is written."
fi

block continue-blocks "${UA_CONTINUE_LIMIT:-10}" "block continue" "You are running unattended; nobody will answer. If work on the goal remains, don't stop: decide for yourself and carry on. If the goal is fully done, put $SIGNAL on its own line in your last message. Don't invent work."
