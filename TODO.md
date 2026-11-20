# pda-tts Development Roadmap

## Current Functionality (v1)

- [x] Reads JSON payload from Claude Code hooks via stdin
- [x] Parses `hook_event_name` and `message` fields using `jq`
- [x] Speaks messages using TTS (espeak-ng, macOS say, sound file fallback, PowerShell)
- [x] Default messages per event type (SessionStart, Stop, Notification)
- [x] Logging to `~/claude-hooks.log` (configurable via `PDA_TTS_LOG`)
- [x] Dry-run mode for testing (`PDA_TTS_DRY_RUN=1`)
- [x] Test suite (`test.sh`)

## Done (v2)

- [x] Stop speaks the project and a Haiku one-liner of the final reply, falling back to its first sentence
- [x] Notification names the project waiting for input or permission
- [x] Config file `~/.config/pda-tts/config` (bash assignments, `config.example` in the repo); env overrides it
- [x] Voice settings: espeak-ng voice, speed, pitch, volume; Windows voice, rate, volume
- [x] Windows engine (`PDA_TTS_ENGINE=windows`, System.Speech via PowerShell)
- [x] Per-event voice overrides (`_STOP`, `_NOTIFICATION`, `_SESSIONSTART` suffixes)
- [x] Mute (`PDA_TTS_MUTE=1`, env or config)
- [x] Message truncation (summary under 15 words, fallback capped at 25)
- [x] Background TTS (detached worker, survives `claude -p` exit)
- [x] Log: one parsed line per event, capped by size
- [x] `--say "text" [Event]` to audition voices; `replay.sh` to preview real sessions

## Next

- [ ] Per-event custom messages (e.g. replace "Systems online.")
- [ ] Windows OneCore voices (Microsoft Mark) via Windows.Media.SpeechSynthesis
- [ ] Serialize speech so two sessions finishing together don't talk over each other
- [ ] Quiet hours (time-based mute)
- [ ] More TTS engines (piper-tts, festival, flite)

## Not Planned

- Desktop notifications (out of scope - use native tools)
- Webhook/Slack/Discord integration (over-engineering for personal use)
- GUI configuration (overkill)
