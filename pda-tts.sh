#!/usr/bin/env bash
set -euo pipefail

logfile="$HOME/claude-hooks.log"

# --- Read stdin safely (short timeout, no hang) ---
read_payload_py='
import sys,select,time,os,json
data=""
# wait up to 0.2s for stdin to be ready
r,_,_=select.select([sys.stdin],[],[],0.2)
if r:
    data=sys.stdin.read()
print(data,end="")
'
payload="$(python3 -c "$read_payload_py" || true)"

# Log raw for debugging
{
  echo "----- $(date) -----"
  echo "stdin bytes: ${#payload}"
  if [ -n "$payload" ]; then
    # trim to 500 chars to avoid huge logs
    echo "stdin preview: ${payload:0:500}"
  else
    echo "stdin is EMPTY"
  fi
} >> "$logfile" 2>/dev/null || true

# --- Parse JSON if present ---
parse_py='
import json,sys
try:
    raw=sys.stdin.read()
    data=json.loads(raw) if raw.strip() else {}
except Exception:
    data={}
print(data.get("hook_event_name","Unknown"))
print(data.get("message",""))
'
event="Unknown"
msg=""
if [ -n "$payload" ]; then
  parsed="$(printf '%s' "$payload" | python3 -c "$parse_py" || true)"
  event="$(printf '%s' "$parsed" | sed -n '1p')"
  msg="$(printf  '%s' "$parsed" | sed -n '2p')"
fi

# If still empty, craft reasonable defaults
if [ -z "${msg:-}" ]; then
  case "$event" in
    SessionStart) msg="Systems online." ;;
    Stop)         msg="Task complete." ;;
    Notification) msg="Notification: awaiting your input." ;;
    *)            msg="$event event occurred." ;;
  esac
fi

# Log final line
printf '%s: %s\n' "$event" "$msg" >> "$logfile" 2>/dev/null || true

# --- Speak it (Linux/macOS/Windows fallback) ---
say_it() {
  if command -v espeak-ng >/dev/null 2>&1; then
    espeak-ng -s 180 -p 120 -v en-us+f4 "$1"
  elif command -v say >/dev/null 2>&1; then
    say "$1"
  elif command -v paplay >/dev/null 2>&1 && [ -f "$HOME/pda/notify.wav" ]; then
    paplay "$HOME/pda/notify.wav"
  elif command -v aplay >/dev/null 2>&1 && [ -f "$HOME/pda/notify.wav" ]; then
    aplay  "$HOME/pda/notify.wav"
  elif command -v powershell >/dev/null 2>&1; then
    powershell -c "(New-Object Media.SoundPlayer \"$env:USERPROFILE\\pda\\notify.wav\").PlaySync()"
  else
    echo "No TTS/player available to announce: $1" >&2
  fi
}
say_it "$msg"
