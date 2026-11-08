#!/bin/bash
# Sourced by the hooks. Live overrides read from the run directory, so a running run can be
# steered without restarting it (run-farmer.sh's /soft and /hard write these):
#   <run>/soft, <run>/hard   new thresholds (a number); replace UA_SOFT / UA_HARD
R="$(dirname "$UA_SEG_DIR")"
if [[ -f "$R/soft" ]]; then v=$(tr -dc 0-9 < "$R/soft"); [[ -n "$v" ]] && UA_SOFT=$v; fi
if [[ -f "$R/hard" ]]; then v=$(tr -dc 0-9 < "$R/hard"); [[ -n "$v" ]] && UA_HARD=$v; fi
