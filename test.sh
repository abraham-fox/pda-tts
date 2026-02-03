#!/usr/bin/env bash
set -uo pipefail

# Test runner for pda-tts.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/pda-tts.sh"

passed=0
failed=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "✓ $name"
    ((passed++)) || true
  else
    echo "✗ $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    ((failed++)) || true
  fi
}

echo "Running pda-tts tests..."
echo

# --- Test cases ---

result=$(echo '{"hook_event_name":"Notification","message":"Hello world"}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "Notification with custom message" "Hello world" "$result"

result=$(echo '{"hook_event_name":"Stop","message":"Build finished"}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "Stop with custom message" "Build finished" "$result"

result=$(echo '{"hook_event_name":"SessionStart","message":"Welcome back"}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "SessionStart with custom message" "Welcome back" "$result"

result=$(echo '{"hook_event_name":"SessionStart"}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "SessionStart default message" "Systems online." "$result"

result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "Stop default message" "Task complete." "$result"

result=$(echo '{"hook_event_name":"Notification"}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "Notification default message" "Awaiting your input." "$result"

result=$(echo '{"hook_event_name":"CustomEvent"}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "Unknown event default message" "CustomEvent event occurred." "$result"

result=$(echo '{}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "Empty JSON object" "Unknown event occurred." "$result"

result=$(echo '{"hook_event_name":"Stop","message":""}' | PDA_TTS_DRY_RUN=1 bash "$SCRIPT")
check "Empty message field" "Task complete." "$result"

result=$(PDA_TTS_DRY_RUN=1 bash "$SCRIPT" < /dev/null)
check "No stdin at all" "Unknown event occurred." "$result"

# --- Summary ---
echo
echo "Results: $passed passed, $failed failed"

[[ $failed -eq 0 ]]
