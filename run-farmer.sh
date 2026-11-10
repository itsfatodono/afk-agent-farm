#!/bin/bash
#: Unattended chief-of-staff loop. Runs until the agent emits <promise>COMPLETE</promise>.
#: Each segment is a normal interactive Claude Code session in a herdr pane next to this
#: one, so you can watch it, click into its agents and type to it at any time. When the
#: context fills up, the hooks have it write a handoff; this script then exits that session
#: and opens a fresh one in the same pane that continues from the handoff.
#:
#: Run it inside herdr. The prompt is afk.prompt.md with {{INPUT}} replaced by your input.
#:
#: Usage:
#:   ./run-farmer.sh "S09 S10 S12"     fill {{INPUT}} from the arguments
#:   ./run-farmer.sh                   paste the input, then Ctrl-D
#:   ./run-farmer.sh -h | --help       show this help
#:
#: Settings: config.sh next to this script, each key explained there. CONFIG=<file> picks
#: another file; an environment variable of the same name overrides a key for one run,
#: e.g. SOFT=600000 ./run-farmer.sh ... (CLAUDE_ARGS space-separated there).
#:
#: Talking to it: type in the agent pane, or click into its agents there. This window
#: only takes /soft N and /hard N (new thresholds, live, for the rest of the run) and /status.
#: Ctrl-C stops this loop only. The session keeps running with the unattended hooks;
#: press Esc or type /exit in its pane to stop it.
#:
#: Logs: runs/<project>-<timestamp>-<pid>/ next to this script (run.log, and per segment:
#: hooks.log, handoff.md, settings.json, transcript = path of the session transcript).
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n 's/^#: \{0,1\}//p' "$0"; exit 0
fi
[[ "${HERDR_ENV:-}" == 1 ]] || { echo "Run this inside a herdr pane." >&2; exit 1; }

if [[ -z "${UA_CAFF:-}" ]] && command -v caffeinate >/dev/null; then
  UA_CAFF=1 exec caffeinate -i "$0" "$@"
fi

CONFIG=${CONFIG:-$HERE/config.sh}
[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 1; }
# Trial run in a subshell first: bash 3.2's `bash -n` misses some errors (an unclosed "(").
err=$(bash -c 'source "$1" >/dev/null' _ "$CONFIG" 2>&1) && [[ -z "$err" ]] \
  || { echo "Error in $CONFIG: ${err:-it exited non-zero}" >&2; exit 1; }
NUMS=(SOFT HARD MAX_SEGMENTS MAX_RETRIES RETRY_WAIT STALL MAX_NUDGES POLL CONTINUE_LIMIT HANDOFF_LIMIT TASK_MAX)
# An environment variable with a key's name wins over the config: save those, source, restore.
OVR=()
for k in "${NUMS[@]}" MODEL EFFORT MASTER CLAUDE_ARGS; do
  [[ -n "${!k+x}" ]] && OVR+=("$k=${!k}")
done
source "$CONFIG"
for kv in ${OVR[@]+"${OVR[@]}"}; do
  k=${kv%%=*}; v=${kv#*=}
  if [[ "$k" == CLAUDE_ARGS ]]; then read -r -a CLAUDE_ARGS <<<"$v"; else printf -v "$k" '%s' "$v"; fi
done
for k in "${NUMS[@]}"; do
  [[ -n "${!k+x}" ]] || { echo "$k missing in $CONFIG" >&2; exit 1; }
  [[ "${!k}" =~ ^[0-9]+$ ]] || { echo "$k must be a whole number, got: ${!k}" >&2; exit 1; }
done
for k in MODEL EFFORT MASTER; do
  [[ -n "${!k+x}" ]] || { echo "$k missing in $CONFIG" >&2; exit 1; }
done
[[ -n "$MASTER" && "$MASTER" != /* ]] && MASTER="$HERE/$MASTER"
EXTRA=(${CLAUDE_ARGS[@]+"${CLAUDE_ARGS[@]}"})
SIGNAL='<promise>COMPLETE</promise>'

if (( $# > 0 )); then INPUT="$*"; else
  if [[ -n "$MASTER" ]]; then echo "Input for {{INPUT}} in $(basename "$MASTER"), then Ctrl-D:" >&2
  else echo "Paste the prompt, then Ctrl-D:" >&2; fi
  INPUT=$(cat)
fi
[[ -n "${INPUT//[[:space:]]/}" ]] || { echo "Empty input." >&2; exit 1; }
if [[ -n "$MASTER" ]]; then
  [[ -f "$MASTER" ]] || { echo "Master prompt not found: $MASTER" >&2; exit 1; }
  TEMPLATE=$(cat "$MASTER")
  [[ "$TEMPLATE" == *"{{INPUT}}"* ]] || { echo "No {{INPUT}} placeholder in $MASTER" >&2; exit 1; }
  PROMPT="${TEMPLATE%%\{\{INPUT\}\}*}${INPUT}${TEMPLATE#*\{\{INPUT\}\}}"
else
  PROMPT="$INPUT"
fi

RUN_DIR="$HERE/runs/$(basename "$PWD")-$(date +%Y%m%d-%H%M%S)-$$"; mkdir -p "$RUN_DIR"
printf '%s\n' "$PROMPT" > "$RUN_DIR/prompt.txt"
echo "run: $RUN_DIR" >&2
say() { echo "$(date '+%F %T') $*" | tee -a "$RUN_DIR/run.log" >&2; }
notify() { herdr notification show "afk-farmer" --body "$1" --sound request >/dev/null 2>&1; }

NAME="afk$$"   # herdr agent name: [a-z][a-z0-9_-]{0,31}, unique among live agents
PANE=""        # the agent pane; reused across segments
trap 'say "loop stopped${PANE:+; the session in pane $PANE keeps running, press Esc or /exit there to stop it}"; exit 130' INT TERM

status() {
  local seg; seg=$(ls -d "$RUN_DIR"/seg-* 2>/dev/null | tail -1)
  echo "run:   $RUN_DIR"
  echo "soft:  $(cat "$RUN_DIR/soft" 2>/dev/null || echo "$SOFT")"
  echo "hard:  $(cat "$RUN_DIR/hard" 2>/dev/null || echo "$HARD")"
  [[ -n "$seg" ]] && echo "last:  $(basename "$seg"): $(tail -1 "$seg/hooks.log" 2>/dev/null)"
}
if [[ -t 0 ]]; then
  ( while IFS= read -r line; do
      read -r -a w <<<"$line"
      case "${w[0]:-}" in
        "") ;;
        /soft|/hard)
          if [[ "${w[1]:-}" =~ ^[0-9]+$ ]]; then  # atomic write: the hooks never see half a file
            printf '%s\n' "${w[1]}" > "$RUN_DIR/.${w[0]#/}.tmp" && mv "$RUN_DIR/.${w[0]#/}.tmp" "$RUN_DIR/${w[0]#/}"
            say "user set ${w[0]#/}=${w[1]}"
          else echo "${w[0]} needs a number." >&2; fi ;;
        /status)     status >&2 ;;
        *)           echo "To talk to the agent, type in its pane${PANE:+ ($PANE)}. Here: /soft N, /hard N, /status." >&2 ;;
      esac
    done ) < /dev/tty &
  reader=$!
  trap 'kill $reader 2>/dev/null' EXIT
fi

q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }  # single-quote for the hook's shell
pane_agent() { herdr pane get "$PANE" 2>/dev/null | jq -r '.result.pane.agent // empty'; }
pane_status() { herdr pane get "$PANE" 2>/dev/null | jq -r '.result.pane.agent_status // "unknown"'; }
# Error code of the main session's last assistant entry, if it was an API error; else empty.
last_api_error() {
  [[ -f "$1" ]] || return 0
  tail -r "$1" 2>/dev/null \
    | jq -c 'select(.type=="assistant" and (.isSidechain|not)) | {e: .isApiErrorMessage, c: .error}' 2>/dev/null \
    | head -1 | jq -r 'select(.e==true) | .c // "unknown"' 2>/dev/null
}

# Each segment gets its own settings file; the hooks' environment is baked into the
# commands because the pane's shell, and so claude, outlives the segment.
write_settings() {
  local envp="UA_SEG_DIR=$(q "$UA_SEG_DIR") UA_HANDOFF=$(q "$UA_HANDOFF") UA_SOFT=$SOFT UA_HARD=$HARD"
  envp+=" UA_CONTINUE_LIMIT=$CONTINUE_LIMIT UA_HANDOFF_LIMIT=$HANDOFF_LIMIT"
  envp+=" UA_TASK_MAX=$TASK_MAX"
  jq -n --arg post "$envp $(q "$HERE/soft-warn.sh")" --arg stop "$envp $(q "$HERE/finish-gate.sh")" \
    '{hooks: {PostToolUse: [{hooks: [{type: "command", command: $post}]}],
              Stop:        [{hooks: [{type: "command", command: $stop}]}]}}' > "$UA_SEG_DIR/settings.json"
}

start_session() {
  if [[ -z "$PANE" ]]; then
    PANE=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus 2>/dev/null | jq -r '.result.pane.pane_id // empty')
    [[ -n "$PANE" ]] || { say "couldn't create a pane"; return 1; }
    say "agent pane: $PANE"
  fi
  local out try
  for try in 1 2 3; do  # a fresh pane's shell may not be at its prompt yet
    sleep 2
    out=$(herdr agent start "$NAME" --kind claude --pane "$PANE" --timeout 120000 -- \
      --settings "$UA_SEG_DIR/settings.json" --permission-mode bypassPermissions \
      --model "$MODEL" --effort "$EFFORT" ${EXTRA[@]+"${EXTRA[@]}"} 2>&1) && break
    out=""
  done
  [[ -n "$out" ]] || { say "claude didn't start in $PANE"; return 1; }
  herdr agent prompt "$NAME" "$1" >/dev/null 2>&1 || { say "couldn't send the prompt"; return 1; }
}

end_session() {
  herdr agent wait "$NAME" --until idle --until done --timeout 120000 >/dev/null 2>&1
  herdr agent prompt "$NAME" "/exit" >/dev/null 2>&1
  local i; for i in $(seq 1 30); do [[ -z "$(pane_agent)" ]] && return 0; sleep 1; done
  say "claude didn't exit, closing pane $PANE"
  herdr pane close "$PANE" >/dev/null 2>&1; PANE=""
}

prev=""
export UA_TASK_MAX=$TASK_MAX  # inflight.sh, called from this loop
for (( seg=1; seg<=MAX_SEGMENTS; seg++ )); do
  export UA_SEG_DIR="$RUN_DIR/seg-$(printf %02d $seg)"; mkdir -p "$UA_SEG_DIR"
  export UA_HANDOFF="$UA_SEG_DIR/handoff.md"
  write_settings
  p="$PROMPT"
  [[ -n "$prev" ]] && p+=$'\n\n---\n'"[unattended] This is a continuation segment. The previous segment's handoff is at $prev . Read it first and continue from there."
  say "segment $seg started"
  start_session "$p" || { notify "segment $seg failed to start"; exit 1; }

  idle_since=""; nudges=0; api_fails=0; told_blocked=""; gave_up=""
  while :; do
    sleep "$POLL"
    if [[ -f "$UA_SEG_DIR/COMPLETE" ]]; then
      say "goal complete ($SIGNAL); the session stays open in $PANE"; notify "goal complete"; exit 0
    fi
    [[ -f "$UA_SEG_DIR/closed" ]] && break
    if [[ -z "$(pane_agent)" ]]; then
      say "claude exited without a handoff (closed by hand, or crashed), stopping"; notify "claude exited without a handoff"; exit 2
    fi
    st=$(pane_status)
    if [[ "$st" == blocked ]]; then
      [[ -z "$told_blocked" ]] && { say "session is waiting on a dialog in $PANE, answer it there"; notify "waiting on a dialog in $PANE"; told_blocked=1; }
      idle_since=""; continue
    fi
    told_blocked=""
    [[ "$st" == working ]] && { idle_since=""; continue; }

    # idle: fine while agents run, the session wakes when they report back
    t=$(cat "$UA_SEG_DIR/transcript" 2>/dev/null)
    [[ -n "$("$HERE/inflight.sh" "$t" "$UA_SEG_DIR")" ]] && { idle_since=""; nudges=0; gave_up=""; continue; }
    [[ -n "$idle_since" ]] || idle_since=$(date +%s)
    (( $(date +%s) - idle_since >= STALL )) || continue
    idle_since=""

    err=$(last_api_error "$t")
    if [[ -n "$err" ]]; then
      if (( ++api_fails > MAX_RETRIES )); then
        say "API errors $api_fails times in a row ($err), stopping; the session stays open in $PANE"; notify "stopped after repeated API errors ($err)"; exit 1
      fi
      say "API error ($err), retrying in ${RETRY_WAIT}s ($api_fails/$MAX_RETRIES)"
      sleep "$RETRY_WAIT"
      msg="[unattended] Your last request failed with an API error ($err). Continue where you left off."
    else
      api_fails=0
      if (( ++nudges > MAX_NUDGES )); then
        [[ -z "$gave_up" ]] && { say "still idle after $MAX_NUDGES nudges, leaving it to you in $PANE"; notify "idle, needs you in $PANE"; gave_up=1; }
        continue
      fi
      say "idle ${STALL}s with no agents running, nudging ($nudges/$MAX_NUDGES)"
      if [[ -f "$UA_SEG_DIR/wind-down" || -f "$UA_SEG_DIR/emergency" ]]; then
        # Wind-down: the only way out is the handoff; offering the signal here ended a run
        # with ready work untouched (2026-11-10).
        msg="[unattended] You've been idle for a while with no agents running. If you're waiting on a background task, check on it and process its result. Then end your turn; the handoff instructions follow."
      else
        msg="[unattended] You've been idle for a while with no agents running. If you're waiting on a background task, check on it. Otherwise carry on with the goal; if it's fully done, put $SIGNAL on its own line in your last message."
      fi
    fi
    herdr agent prompt "$NAME" "$msg" >/dev/null 2>&1 || say "couldn't send the nudge"
  done

  say "segment $seg ended with a handoff"
  prev="$UA_HANDOFF"
  end_session
done
say "MAX_SEGMENTS reached"; notify "MAX_SEGMENTS reached"
