#!/usr/bin/env bash
# Replays the final replies of recent sessions through pda-tts.sh in dry-run and prints
# what each Stop would say. Sessions come from the transcript paths in the hook log.
# Reads the user's own data at run time; nothing is stored in the repo.
#
# Usage: replay.sh [count]   (PDA_TTS_SUMMARY_MODEL=off skips the Haiku call)
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/pda-tts.sh"
log="${PDA_TTS_LOG:-$HOME/claude-hooks.log}"
count="${1:-5}"

speak() { printf '%s' "$1" | PDA_TTS_LOG= PDA_TTS_DRY_RUN=1 bash "$SCRIPT"; }

grep -oE '"transcript_path":"[^"]+"|transcript=[^ ]+' "$log" | sed -E 's/^"transcript_path":"|^transcript=//; s/"$//' \
  | tac | awk '!seen[$0]++' | head -n "$count" | while read -r transcript; do
    [[ -r "$transcript" ]] || continue
    payload=$(jq -cs '[.[] | select(.type == "assistant")] | last
      | {hook_event_name: "Stop", cwd, transcript_path: "'"$transcript"'",
         last_assistant_message: ([.message.content[]? | select(.type == "text") | .text] | join("\n"))}' "$transcript" 2>/dev/null) || continue
    [[ -z "$(jq -r '.last_assistant_message' <<< "$payload")" ]] && continue
    printf '  reply: %s\n' "$(jq -r '.last_assistant_message' <<< "$payload" | tr '\n' ' ' | cut -c1-110)"
    printf '  says:  %s\n\n' "$(speak "$payload")"
  done

