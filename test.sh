#!/usr/bin/env bash
set -uo pipefail

# Test runner for pda-tts.sh. Never calls the real Claude CLI and never reads the
# user's config or log: claude is a stub and every path points into a temp dir.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/pda-tts.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Stub claude: STUB_MODE=ok|fail|empty|hang; records its args, env and stdin.
cat > "$tmp/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$STUB_DIR/claude-args"
printf 'mute=%s\n' "${PDA_TTS_MUTE:-}" > "$STUB_DIR/claude-env"
cat > "$STUB_DIR/claude-stdin"
case "${STUB_MODE:-ok}" in
  ok)    printf '%s\n' "${STUB_OUT:-Stub summary.}" ;;
  fail)  exit 1 ;;
  empty) exit 0 ;;
  hang)  sleep 30 ;;
esac
STUB
chmod +x "$tmp/bin/claude"

export PDA_TTS_CONFIG=/dev/null
export PDA_TTS_LOG="$tmp/log"
export PDA_TTS_CLAUDE="$tmp/bin/claude"
export PDA_TTS_SUMMARY_MODEL=off
export STUB_DIR="$tmp"
unset PDA_TTS_MUTE PDA_TTS_VOICE PDA_TTS_SPEED PDA_TTS_PITCH PDA_TTS_AMPLITUDE

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

yes_if() { "$@" >/dev/null 2>&1 && echo yes || echo no; }
run() { PDA_TTS_DRY_RUN=1 bash "$SCRIPT"; }

echo "Running pda-tts tests..."
echo

# --- Original contract ---

result=$(echo '{"hook_event_name":"Notification","message":"Hello world"}' | run)
check "Notification with custom message" "Hello world" "$result"

result=$(echo '{"hook_event_name":"Stop","message":"Build finished"}' | run)
check "Stop with custom message" "Build finished" "$result"

result=$(echo '{"hook_event_name":"SessionStart","message":"Welcome back"}' | run)
check "SessionStart with custom message" "Welcome back" "$result"

result=$(echo '{"hook_event_name":"SessionStart"}' | run)
check "SessionStart default message" "Systems online." "$result"

result=$(echo '{"hook_event_name":"Stop"}' | run)
check "Stop default message" "Task complete." "$result"

result=$(echo '{"hook_event_name":"Notification"}' | run)
check "Notification default message" "Awaiting your input." "$result"

result=$(echo '{"hook_event_name":"CustomEvent"}' | run)
check "Unknown event default message" "CustomEvent event occurred." "$result"

result=$(echo '{}' | run)
check "Empty JSON object" "Unknown event occurred." "$result"

result=$(echo '{"hook_event_name":"Stop","message":""}' | run)
check "Empty message field" "Task complete." "$result"

result=$(run < /dev/null)
check "No stdin at all" "Unknown event occurred." "$result"

# --- Stop: what was done ---

stop() { jq -cn --arg cwd "$1" --arg m "$2" '{hook_event_name:"Stop",cwd:$cwd,transcript_path:"/x/t.jsonl",last_assistant_message:$m}'; }

result=$(stop /home/u/my-app 'Nik, I fixed the parser. Tests are green.' | run)
check "Stop: project plus first sentence, greeting dropped" "my-app: I fixed the parser." "$result"

result=$(stop /home/u/my-app $'Nik, I updated `**pda-tts.sh**`.\n\n- item one' | run)
check "Stop: markdown and code ticks stripped" "my-app: I updated pda-tts.sh." "$result"

result=$(stop /home/u/my-app $'Nik, the result:\n\n| a | b |' | run)
check "Stop: sentence cut at the first paragraph" "my-app: the result:" "$result"

long="Nik, $(printf 'word %.0s' {1..40})end."
result=$(stop /home/u/my-app "$long" | run)
check "Stop: fallback capped at 25 words" "my-app: $(printf 'word %.0s' {1..25} | sed 's/ $//')" "$result"

result=$(stop /git/repo/.claude/worktrees/ABC-1-fix 'Done.' | run)
check "Stop: worktree speaks the repo name" "repo: Done." "$result"

result=$(stop /home/u/my-app '' | run)
check "Stop: empty reply falls back to default" "my-app: Task complete." "$result"

# --- Stop: Haiku summary ---

result=$(stop /home/u/my-app 'Nik, I fixed the parser.' | PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=ok STUB_OUT='Parser fixed.' run)
check "Haiku: summary is spoken" "my-app: Parser fixed." "$result"
check "Haiku: model passed" "yes" "$(yes_if grep -qx haiku "$tmp/claude-args")"
check "Haiku: user hooks disabled (no recursion)" "yes" "$(yes_if grep -qx -- --setting-sources "$tmp/claude-args")"
check "Haiku: child is muted" "mute=1" "$(cat "$tmp/claude-env" 2>/dev/null)"
check "Haiku: reply sent on stdin" "yes" "$(yes_if grep -q 'I fixed the parser' "$tmp/claude-stdin")"

result=$(stop /home/u/my-app 'Fixed it.' | PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=ok STUB_OUT=$'Line one\nline two' run)
check "Haiku: multi-line output collapsed" "my-app: Line one line two" "$result"

for mode in fail empty; do
  result=$(stop /home/u/my-app 'Nik, I fixed the parser. More.' | PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=$mode run)
  check "Haiku $mode: falls back to first sentence" "my-app: I fixed the parser." "$result"
done

start=$SECONDS
result=$(stop /home/u/my-app 'Nik, I fixed the parser.' | PDA_TTS_SUMMARY_MODEL=haiku PDA_TTS_SUMMARY_TIMEOUT=1 STUB_MODE=hang run)
check "Haiku hang: falls back to first sentence" "my-app: I fixed the parser." "$result"
check "Haiku hang: gives up within the timeout" "yes" "$( (( SECONDS - start < 5 )) && echo yes || echo no)"

result=$(stop /home/u/my-app 'Nik, I fixed the parser.' | PDA_TTS_SUMMARY_MODEL=haiku PDA_TTS_CLAUDE=/nonexistent/claude run)
check "Haiku missing binary: falls back to first sentence" "my-app: I fixed the parser." "$result"

# --- Notification ---

note() { jq -cn --arg t "$1" --arg m "$2" '{hook_event_name:"Notification",cwd:"/home/u/my-app",notification_type:$t,message:$m}'; }

result=$(note permission_prompt 'Claude needs your permission' | run)
check "Notification: permission names the project" "my-app needs your permission." "$result"

result=$(note idle_prompt 'Claude is waiting for your input' | run)
check "Notification: idle names the project" "my-app is waiting for your input." "$result"

result=$(note auth_success 'Claude Code login successful' | run)
check "Notification: other types keep the message" "my-app: Claude Code login successful" "$result"

# --- Mute ---

rm -f "$tmp/log"
result=$(stop /home/u/my-app 'Done.' | PDA_TTS_MUTE=1 run)
check "Mute: nothing spoken" "" "$result"
check "Mute: nothing logged" "no" "$(yes_if test -e "$tmp/log")"

printf 'PDA_TTS_MUTE=1\n' > "$tmp/config"
result=$(stop /home/u/my-app 'Done.' | PDA_TTS_CONFIG="$tmp/config" run)
check "Mute: config file can mute" "" "$result"

# --- Config precedence ---

printf 'PDA_TTS_SPEED=999\n' > "$tmp/config"
result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_CONFIG="$tmp/config" PDA_TTS_SPEED=111 PDA_TTS_DRY_RUN=voice bash "$SCRIPT")
check "Config: env beats config file" "yes" "$(yes_if grep -q -- '-s 111' <<< "$result")"

result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_CONFIG="$tmp/config" PDA_TTS_DRY_RUN=voice bash "$SCRIPT")
check "Config: config file beats default" "yes" "$(yes_if grep -q -- '-s 999' <<< "$result")"

# --- Log (dry-run logs only when PDA_TTS_LOG is set, as it is here) ---

rm -f "$tmp/log"
stop /home/u/my-app 'Nik, I fixed the parser.' | run >/dev/null
check "Log: one parsed line per event" "1" "$(grep -c 'event=Stop project=my-app' "$tmp/log" 2>/dev/null)"
check "Log: no raw payload" "no" "$(yes_if grep -q 'last_assistant_message' "$tmp/log")"
check "Log: spoken text recorded" "yes" "$(yes_if grep -q '| my-app: I fixed the parser.' "$tmp/log")"

head -c 300000 /dev/zero | tr '\0' 'x' | fold -w 99 > "$tmp/log"
stop /home/u/my-app 'Done.' | PDA_TTS_LOG_MAX_BYTES=50000 run >/dev/null
check "Log: capped by size" "yes" "$( (( $(stat -c %s "$tmp/log") <= 50000 )) && echo yes || echo no)"
check "Log: newest entry kept" "yes" "$(yes_if grep -q 'my-app: Done.' <(tail -n1 "$tmp/log"))"

# --- Real run (not dry): detached worker speaks through a stub espeak-ng ---

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/espeak-args"\n' "$tmp" > "$tmp/bin/espeak-ng"
chmod +x "$tmp/bin/espeak-ng"
start=$SECONDS
stop /home/u/my-app 'Nik, I fixed the parser.' | PATH="$tmp/bin:$PATH" PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=hang PDA_TTS_SUMMARY_TIMEOUT=2 bash "$SCRIPT"
check "Real run: hook returns before the summary finishes" "yes" "$( (( SECONDS - start < 2 )) && echo yes || echo no)"
for _ in {1..50}; do [[ -s "$tmp/espeak-args" ]] && break; sleep 0.1; done
check "Real run: espeak gets the text after --" "-s 180 -p 120 -a 100 -v en-us+f4 -- my-app: I fixed the parser." "$(cat "$tmp/espeak-args" 2>/dev/null)"

rm -f "$tmp/espeak-args" "$tmp/log"
PATH="$tmp/bin:$PATH" PDA_TTS_VOICE=en-gb+m3 bash "$SCRIPT" --say 'Hello there'
check "Audition: --say speaks with the given voice" "-s 180 -p 120 -a 100 -v en-gb+m3 -- Hello there" "$(cat "$tmp/espeak-args" 2>/dev/null)"
check "Audition: nothing logged" "no" "$(yes_if test -e "$tmp/log")"

# --- Summary ---
echo
echo "Results: $passed passed, $failed failed"

[[ $failed -eq 0 ]]
