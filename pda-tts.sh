#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
logfile="${PDA_TTS_LOG:-$HOME/claude-hooks.log}"
dry_run="${PDA_TTS_DRY_RUN:-}"

# --- Read stdin with timeout (don't hang if empty) ---
payload=""
if read -t 0.2 -r payload; then
  # Read any additional lines (for multi-line JSON)
  while read -t 0.1 -r line; do
    payload="$payload$line"
  done
fi

# --- Log raw input for debugging ---
if [[ -z "$dry_run" ]]; then
  {
    echo "----- $(date) -----"
    echo "stdin bytes: ${#payload}"
    if [[ -n "$payload" ]]; then
      echo "stdin preview: ${payload:0:500}"
    else
      echo "stdin is EMPTY"
    fi
  } >> "$logfile" 2>/dev/null || true
fi

# --- Parse JSON with jq (fallback to defaults if missing/invalid) ---
event="Unknown"
msg=""

if [[ -n "$payload" ]] && command -v jq >/dev/null 2>&1; then
  event=$(printf '%s' "$payload" | jq -r '.hook_event_name // "Unknown"' 2>/dev/null) || event="Unknown"
  msg=$(printf '%s' "$payload" | jq -r '.message // ""' 2>/dev/null) || msg=""
fi

# --- Default messages per event type ---
if [[ -z "$msg" ]]; then
  case "$event" in
    SessionStart) msg="Systems online." ;;
    Stop)         msg="Task complete." ;;
    Notification) msg="Awaiting your input." ;;
    *)            msg="$event event occurred." ;;
  esac
fi

# --- Log parsed result ---
if [[ -z "$dry_run" ]]; then
  printf '%s: %s\n' "$event" "$msg" >> "$logfile" 2>/dev/null || true
fi

# --- Speak it (or print in dry-run mode) ---
say_it() {
  local text="$1"

  # Dry-run mode: just print
  if [[ -n "$dry_run" ]]; then
    echo "$text"
    return
  fi

  # TTS engines in order of preference
  if command -v espeak-ng >/dev/null 2>&1; then
    espeak-ng -s 180 -p 120 -v en-us+f4 "$text"
  elif command -v say >/dev/null 2>&1; then
    say "$text"
  elif command -v paplay >/dev/null 2>&1 && [[ -f "$HOME/pda/notify.wav" ]]; then
    paplay "$HOME/pda/notify.wav"
  elif command -v aplay >/dev/null 2>&1 && [[ -f "$HOME/pda/notify.wav" ]]; then
    aplay "$HOME/pda/notify.wav"
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -c "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('$text')"
  else
    echo "No TTS available: $text" >&2
  fi
}

say_it "$msg"
