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
unset PDA_TTS_STOP_STYLE PDA_TTS_MUTE PDA_TTS_ESPEAK_VOICE PDA_TTS_ESPEAK_SPEED PDA_TTS_ESPEAK_PITCH PDA_TTS_ESPEAK_VOLUME PDA_TTS_ENGINE PDA_TTS_WIN_VOICE PDA_TTS_WIN_RATE PDA_TTS_WIN_VOLUME

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
check "Stop default message" "Done." "$result"

result=$(echo '{"hook_event_name":"Notification"}' | run)
check "Notification default message" "Awaiting your input." "$result"

result=$(echo '{"hook_event_name":"CustomEvent"}' | run)
check "Unknown event default message" "CustomEvent event occurred." "$result"

result=$(echo '{}' | run)
check "Empty JSON object" "Unknown event occurred." "$result"

result=$(echo '{"hook_event_name":"Stop","message":""}' | run)
check "Empty message field" "Done." "$result"

result=$(run < /dev/null)
check "No stdin at all" "Unknown event occurred." "$result"

# --- Stop, summary style: what was done ---

export PDA_TTS_STOP_STYLE=summary

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

long_reply="Nik, I wrote the plan. $(printf 'filler %.0s' {1..2000}) Want me to go ahead?"
stop /home/u/my-app "$long_reply" | PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=ok run >/dev/null
check "Haiku: long reply keeps its head" "yes" "$(yes_if grep -q 'I wrote the plan' "$tmp/claude-stdin")"
check "Haiku: long reply keeps its closing question" "yes" "$(yes_if grep -q 'Want me to go ahead' "$tmp/claude-stdin")"

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

result=$(stop /home/u/my-app 'Fixed it.' | PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=ok STUB_OUT='Nik, parser fixed.' run)
check "Haiku: greeting dropped from the summary" "my-app: parser fixed." "$result"
check "Haiku: summary prompt used" "yes" "$(yes_if grep -q 'spoken status line' "$tmp/claude-args")"

unset PDA_TTS_STOP_STYLE

# --- Stop, status style (the default): who and what state ---

repo() { mkdir -p "$tmp/repos/$1" && git init -q -b "$2" "$tmp/repos/$1" && printf '%s' "$tmp/repos/$1"; }
title() { printf '{"type":"user"}\n' > "$tmp/t.jsonl"; for t in "$@"; do jq -cn --arg t "$t" '{type:"custom-title",customTitle:$t}' >> "$tmp/t.jsonl"; done; }
stopt() { jq -cn --arg cwd "$1" --arg m "$2" --arg t "${3:-/x/t.jsonl}" '{hook_event_name:"Stop",cwd:$cwd,transcript_path:$t,last_assistant_message:$m}'; }

ws=$(repo webshop-services SUP-23660-skip-unchanged-model-ratings)
result=$(stopt "$ws" 'Nik, I fixed it.' | run)
check "Status: branch words without the ticket" "webshop-services, skip unchanged model ratings: done." "$result"

result=$(stopt "$(repo app1 feature/ABC-12_add_thing)" 'Done.' | run)
check "Status: branch path and underscores dropped" "app1, add thing: done." "$result"

result=$(stopt "$(repo app2 main)" 'Done.' | run)
check "Status: default branch adds nothing" "app2: done." "$result"

result=$(stopt "$(repo app3 SUP-1)" 'Done.' | run)
check "Status: ticket-only branch adds nothing" "app3: done." "$result"

result=$(stopt "$(repo app4 one-two-three-four-five-six-seven-eight)" 'Done.' | run)
check "Status: branch capped at six words" "app4, one two three four five six: done." "$result"

title first review-inbox
result=$(stopt "$ws" 'Done.' "$tmp/t.jsonl" | run)
check "Status: latest session name beats project and branch" "review-inbox: done." "$result"

result=$(stopt "$ws" 'Nik, the plan is ready.

Go?' | run)
check "Status fallback: closing question" "webshop-services, skip unchanged model ratings: has a question." "$result"

result=$(stopt /home/u/my-app $'Nik, plan below.\n\n**Want me to push?**\n' | run)
check "Status fallback: question in markdown" "my-app: has a question." "$result"

result=$(stopt /home/u/my-app 'Is it fixed? Yes, all green.' | run)
check "Status fallback: earlier question mark ignored" "my-app: done." "$result"

result=$(stopt /home/u/my-app '' | run)
check "Status: empty reply is done" "my-app: done." "$result"

for pair in done:done question:"has a question" decision:"needs a decision" blocked:blocked failed:failed ' Decision.':"needs a decision"; do
  result=$(stopt /home/u/my-app 'Fixed it.' | PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=ok STUB_OUT="${pair%%:*}" run)
  check "Status Haiku: '${pair%%:*}' is spoken as '${pair#*:}'" "my-app: ${pair#*:}." "$result"
done
check "Status Haiku: status prompt used" "yes" "$(yes_if grep -q 'exactly one word' "$tmp/claude-args")"
check "Status Haiku: log tags the source" "yes" "$(yes_if grep -q 'source=haiku' <(tail -n1 "$tmp/log"))"

result=$(stopt /home/u/my-app 'Nik, done. Push?' | PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=ok STUB_OUT='Nik, it needs a decision. Needs your decision.' run)
check "Status Haiku: free text falls back, no name spoken" "my-app: has a question." "$result"
check "Status Haiku: log tags the fallback" "yes" "$(yes_if grep -q 'source=heuristic' <(tail -n1 "$tmp/log"))"

result=$(stopt /home/u/my-app 'Push?' | PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=fail run)
check "Status Haiku fail: falls back" "my-app: has a question." "$result"

result=$(stopt "$ws" 'Done.' | PDA_TTS_STOP_STYLE=summary run)
check "Summary style: branch words in front too" "webshop-services, skip unchanged model ratings: Done." "$result"

result=$(jq -cn --arg cwd "$ws" '{hook_event_name:"Notification",cwd:$cwd,notification_type:"permission_prompt",message:"x"}' | run)
check "Notification: permission names project and branch" "webshop-services, skip unchanged model ratings: needs your permission." "$result"

result=$(jq -cn --arg t "$tmp/t.jsonl" '{hook_event_name:"Notification",cwd:"/home/u/my-app",transcript_path:$t,notification_type:"idle_prompt",message:"x"}' | run)
check "Notification: idle names the session" "review-inbox: waiting for your input." "$result"

# --- Notification ---

note() { jq -cn --arg t "$1" --arg m "$2" '{hook_event_name:"Notification",cwd:"/home/u/my-app",notification_type:$t,message:$m}'; }

result=$(note permission_prompt 'Claude needs your permission' | run)
check "Notification: permission names the project" "my-app: needs your permission." "$result"

result=$(note idle_prompt 'Claude is waiting for your input' | run)
check "Notification: idle names the project" "my-app: waiting for your input." "$result"

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

printf 'PDA_TTS_ESPEAK_SPEED=999\n' > "$tmp/config"
result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_CONFIG="$tmp/config" PDA_TTS_ESPEAK_SPEED=111 PDA_TTS_DRY_RUN=voice bash "$SCRIPT")
check "Config: env beats config file" "yes" "$(yes_if grep -q -- '-s 111' <<< "$result")"

result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_CONFIG="$tmp/config" PDA_TTS_DRY_RUN=voice bash "$SCRIPT")
check "Config: config file beats default" "yes" "$(yes_if grep -q -- '-s 999' <<< "$result")"

# --- Log (dry-run logs only when PDA_TTS_LOG is set, as it is here) ---

rm -f "$tmp/log"
stop /home/u/my-app 'Nik, I fixed the parser.' | run >/dev/null
check "Log: one parsed line per event" "1" "$(grep -c 'event=Stop project=my-app' "$tmp/log" 2>/dev/null)"
check "Log: no raw payload" "no" "$(yes_if grep -q 'last_assistant_message' "$tmp/log")"
check "Log: spoken text recorded" "yes" "$(yes_if grep -q '| my-app: done.' "$tmp/log")"

head -c 300000 /dev/zero | tr '\0' 'x' | fold -w 99 > "$tmp/log"
stop /home/u/my-app 'Done.' | PDA_TTS_LOG_MAX_BYTES=50000 run >/dev/null
check "Log: capped by size" "yes" "$( (( $(stat -c %s "$tmp/log") <= 50000 )) && echo yes || echo no)"
check "Log: newest entry kept" "yes" "$(yes_if grep -q 'my-app: done.' <(tail -n1 "$tmp/log"))"

# --- Real run (not dry): detached worker speaks through a stub espeak-ng ---

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/espeak-args"\n' "$tmp" > "$tmp/bin/espeak-ng"
chmod +x "$tmp/bin/espeak-ng"
start=$SECONDS
stop /home/u/my-app 'Nik, I fixed the parser.' | PATH="$tmp/bin:$PATH" PDA_TTS_SUMMARY_MODEL=haiku STUB_MODE=hang PDA_TTS_SUMMARY_TIMEOUT=2 bash "$SCRIPT"
check "Real run: hook returns before the summary finishes" "yes" "$( (( SECONDS - start < 2 )) && echo yes || echo no)"
for _ in {1..50}; do [[ -s "$tmp/espeak-args" ]] && break; sleep 0.1; done
check "Real run: espeak gets the text after --" "-s 180 -p 120 -a 100 -v en-us+f4 -- my-app: done." "$(cat "$tmp/espeak-args" 2>/dev/null)"

rm -f "$tmp/espeak-args" "$tmp/log"
PATH="$tmp/bin:$PATH" PDA_TTS_ESPEAK_VOICE=en-gb+m3 bash "$SCRIPT" --say 'Hello there'
check "Audition: --say speaks with the given voice" "-s 180 -p 120 -a 100 -v en-gb+m3 -- Hello there" "$(cat "$tmp/espeak-args" 2>/dev/null)"
check "Audition: nothing logged" "no" "$(yes_if test -e "$tmp/log")"

# --- Windows engine (stub powershell.exe) ---

cat > "$tmp/bin/powershell.exe" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == *GetInstalledVoices* ]] && { printf 'Microsoft Zira Desktop\r\nMicrosoft David Desktop\r\n'; exit 0; }
{ printf 'args=%s\n' "$*"; printf 'text=%s\nvoice=%s\nrate=%s\nvolume=%s\nwslenv=%s\n' \
    "${PDA_TTS_TEXT:-}" "${PDA_TTS_WIN_VOICE:-}" "${PDA_TTS_WIN_RATE:-}" "${PDA_TTS_WIN_VOLUME:-}" "${WSLENV:-}"; } > "$STUB_DIR/ps-out"
STUB
chmod +x "$tmp/bin/powershell.exe"
export PDA_TTS_POWERSHELL="$tmp/bin/powershell.exe"

rm -f "$tmp/ps-out" "$tmp/espeak-args"
PATH="$tmp/bin:$PATH" PDA_TTS_ENGINE=windows PDA_TTS_WIN_VOICE='Microsoft David Desktop' PDA_TTS_WIN_RATE=2 bash "$SCRIPT" --say "It's done"
check "Windows: text passed through env, apostrophe intact" "text=It's done" "$(grep '^text=' "$tmp/ps-out" 2>/dev/null)"
check "Windows: voice passed" "voice=Microsoft David Desktop" "$(grep '^voice=' "$tmp/ps-out" 2>/dev/null)"
check "Windows: rate passed" "rate=2" "$(grep '^rate=' "$tmp/ps-out" 2>/dev/null)"
check "Windows: volume default" "volume=100" "$(grep '^volume=' "$tmp/ps-out" 2>/dev/null)"
check "Windows: env shared with Windows" "yes" "$(yes_if grep -q 'PDA_TTS_TEXT' <(grep '^wslenv=' "$tmp/ps-out"))"
check "Windows: text not on the command line" "no" "$(yes_if grep -q "It's done" <(grep '^args=' "$tmp/ps-out"))"
check "Windows: espeak not used" "no" "$(yes_if test -e "$tmp/espeak-args")"

rm -f "$tmp/ps-out" "$tmp/espeak-args"
PATH="$tmp/bin:$PATH" PDA_TTS_ENGINE=windows PDA_TTS_POWERSHELL=/nonexistent/powershell.exe bash "$SCRIPT" --say 'Fallback'
check "Windows missing: falls back to espeak" "yes" "$(yes_if grep -q -- '-- Fallback' "$tmp/espeak-args")"

result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_ENGINE=windows PDA_TTS_DRY_RUN=voice bash "$SCRIPT")
check "Windows: dry-run voice shows the engine" "windows voice=Microsoft Zira Desktop rate=0 volume=100 -- Done." "$result"

# --- Per-event voices ---

dryv() { PDA_TTS_DRY_RUN=voice bash "$SCRIPT"; }

result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_ENGINE=windows PDA_TTS_WIN_VOICE_STOP='Microsoft David Desktop' dryv)
check "Per-event: Stop uses its own Windows voice" "windows voice=Microsoft David Desktop rate=0 volume=100 -- Done." "$result"

result=$(echo '{"hook_event_name":"Notification"}' | PDA_TTS_ENGINE=windows PDA_TTS_WIN_VOICE_STOP='Microsoft David Desktop' dryv)
check "Per-event: other events keep the general voice" "windows voice=Microsoft Zira Desktop rate=0 volume=100 -- Awaiting your input." "$result"

result=$(echo '{"hook_event_name":"Notification"}' | PDA_TTS_ENGINE_NOTIFICATION=windows PDA_TTS_WIN_RATE_NOTIFICATION=3 dryv)
check "Per-event: engine and rate per event" "windows voice=Microsoft Zira Desktop rate=3 volume=100 -- Awaiting your input." "$result"

result=$(echo '{"hook_event_name":"SessionStart"}' | PDA_TTS_ENGINE_NOTIFICATION=windows PDA_TTS_ESPEAK_SPEED_SESSIONSTART=140 PDA_TTS_ESPEAK_VOICE_SESSIONSTART=en-gb+m3 PDA_TTS_ESPEAK_VOLUME_SESSIONSTART=150 dryv)
check "Per-event: espeak settings per event" "espeak-ng -s 140 -p 120 -a 150 -v en-gb+m3 -- Systems online." "$result"

printf 'PDA_TTS_ENGINE=windows\nPDA_TTS_WIN_VOICE_STOP="Microsoft David Desktop"\n' > "$tmp/config"
result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_CONFIG="$tmp/config" PDA_TTS_WIN_VOICE='Other' dryv)
check "Per-event: config per-event beats env general" "windows voice=Microsoft David Desktop rate=0 volume=100 -- Done." "$result"

result=$(echo '{"hook_event_name":"Weird-Event.1"}' | PDA_TTS_ENGINE=windows dryv)
check "Per-event: odd event name is harmless" "windows voice=Microsoft Zira Desktop rate=0 volume=100 -- Weird-Event.1 event occurred." "$result"

rm -f "$tmp/ps-out"
PATH="$tmp/bin:$PATH" PDA_TTS_ENGINE=windows PDA_TTS_WIN_VOICE_NOTIFICATION='Microsoft David Desktop' bash "$SCRIPT" --say 'Hi' Notification
check "Audition: --say with an event uses that event's voice" "voice=Microsoft David Desktop" "$(grep '^voice=' "$tmp/ps-out" 2>/dev/null)"

# --- Old espeak names no longer apply ---

result=$(echo '{"hook_event_name":"Stop"}' | PDA_TTS_SPEED=111 PDA_TTS_VOICE=en-gb+m3 dryv)
check "Rename: old espeak names are ignored" "espeak-ng -s 180 -p 120 -a 100 -v en-us+f4 -- Done." "$result"

# --- --voices lists what is installed ---

mkdir -p "$tmp/edata/voices/!v" && touch "$tmp/edata/voices/!v/f1" "$tmp/edata/voices/!v/m3"
cat > "$tmp/bin/espeak-ng" <<STUB
#!/usr/bin/env bash
case "\$1" in
  --version) echo "eSpeak NG text-to-speech: 1.52.0  Data at: $tmp/edata" ;;
  --voices=en) printf 'Pty Language Age/Gender VoiceName File Other\n 2 en-gb --/M English gmw/en\n 2 en-us --/M English gmw/en-US\n 5 variant --/F Annie !v/Annie\n' ;;
  *) printf '%s\n' "\$*" > "$tmp/espeak-args" ;;
esac
STUB
result=$(PATH="$tmp/bin:$PATH" bash "$SCRIPT" --voices)
check "Voices: espeak languages listed" "yes" "$(yes_if grep -qx '  languages: en-gb, en-us' <<< "$result")"
check "Voices: espeak variants listed" "yes" "$(yes_if grep -qx '  variants:  f1, m3' <<< "$result")"
check "Voices: Windows voices listed" "yes" "$(yes_if grep -qx '  Microsoft David Desktop' <<< "$result")"
check "Voices: setting names shown" "yes" "$(grep -q 'PDA_TTS_ESPEAK_VOICE' <<< "$result" && grep -q 'PDA_TTS_WIN_VOICE' <<< "$result" && echo yes || echo no)"

result=$(PATH="$tmp/bin:$PATH" PDA_TTS_POWERSHELL=/nonexistent/powershell.exe bash "$SCRIPT" --voices)
check "Voices: no PowerShell says so" "yes" "$(yes_if grep -q 'not available' <<< "$result")"

# --- Summary ---
echo
echo "Results: $passed passed, $failed failed"

[[ $failed -eq 0 ]]
