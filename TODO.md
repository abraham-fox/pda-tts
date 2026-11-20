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
- [x] `--voices` lists installed espeak-ng languages, variants and Windows voices
- [x] espeak settings renamed to `PDA_TTS_ESPEAK_*`, mirroring `PDA_TTS_WIN_*`

## Done (v3)

- [x] Stop speaks who and the state (done, has a question, needs a decision, blocked, failed) instead of a summary
- [x] Who: the session name, else the project and the session's auto-title, else its branch (from the transcript), ticket ids dropped
- [x] The summary stays available as `PDA_TTS_STOP_STYLE=summary`, with a leading "Nik," dropped

## Next

- [ ] Evaluate Jev (TypeSafe AI, multiple-choice model, hosted API) for the Stop state choice: latency, price, and whether replies may leave for a third party
- [ ] Per-event custom messages (e.g. replace "Systems online.")
- [ ] Windows OneCore voices (Microsoft Mark) via Windows.Media.SpeechSynthesis
- [ ] Windows pitch (`PDA_TTS_WIN_PITCH`) through SSML `<prosody pitch>`
- [ ] Serialize speech so two sessions finishing together don't talk over each other
- [ ] Quiet hours (time-based mute)
- [ ] More TTS engines (piper-tts, festival, flite)

## Not Planned

- Desktop notifications (out of scope - use native tools)
- Webhook/Slack/Discord integration (over-engineering for personal use)
- GUI configuration (overkill)
