#!/bin/bash
# Usage: ctx.sh <transcript_path>
# Prints the main session's current context size in tokens (input of its last model call, cache included).
# Subagent (sidechain) entries are ignored. macOS has no `tac`, so `tail -r` is used.
tail -r "$1" 2>/dev/null \
  | jq -c 'select(.type=="assistant" and .message.usage? and (.isSidechain|not)) | .message.usage' 2>/dev/null \
  | head -1 \
  | jq '(.input_tokens//0)+(.cache_read_input_tokens//0)+(.cache_creation_input_tokens//0)' 2>/dev/null
