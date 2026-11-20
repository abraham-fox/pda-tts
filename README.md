# pda-tts

A text-to-speech notification hook for [Claude Code](https://claude.ai/claude-code). Get audible notifications when Claude needs your attention or completes a task.

## What it does

This script integrates with Claude Code's hook system to provide voice notifications for:

- **SessionStart**: Announces when a session begins ("Systems online.")
- **Stop**: Says which project finished and what was done, e.g. "my-app: Fixed the parser, tests green." A reply that ends by asking you something gets "Needs your decision." appended.
- **Notification**: Says which project needs you ("my-app needs your permission.", "my-app is waiting for your input."); other notifications are spoken as sent.

The project is the last folder of the session's working directory; a worktree under `<repo>/.claude/worktrees/` speaks the repo's name.

## How it works

1. **Reads stdin**: Uses bash `read -t` to safely read the JSON payload with a timeout (prevents hanging)
2. **Detaches**: Hands the rest to a background process (`setsid`) and returns, because `claude -p` kills its hooks when it exits
3. **Builds the line**: For Stop, `claude -p --model haiku` turns `last_assistant_message` into one spoken line. The call loads no user settings, so it fires no hooks of its own. If the call fails, returns nothing or exceeds `PDA_TTS_SUMMARY_TIMEOUT`, the script speaks the reply's first sentence instead, then "Task complete." as a last resort
4. **Logs events**: Appends one line per event to `~/claude-hooks.log`: event, project, notification type, where the text came from, the transcript path and the spoken text
5. **Speaks the message**: Uses the first available TTS engine:
   - `espeak-ng` (Linux) - preferred, with custom voice settings
   - `say` (macOS)
   - `paplay`/`aplay` with `~/pda/notify.wav` (Linux sound fallback)
   - PowerShell Speech Synthesizer (Windows/WSL)

## Installation

### 1. Install dependencies

**Linux (Debian/Ubuntu):**
```bash
sudo apt install jq espeak-ng
```

**macOS:**
```bash
brew install jq
# say command is built-in
```

**Windows/WSL:** Install jq and either espeak-ng in WSL, or use the PowerShell fallback.

### 2. Install the script

```bash
# Clone the repository
git clone https://github.com/abraham-fox/pda-tts.git

# Create ~/bin if it doesn't exist
mkdir -p ~/bin

# Copy or symlink the script
cp pda-tts/pda-tts.sh ~/bin/
# Or symlink: ln -s "$(pwd)/pda-tts/pda-tts.sh" ~/bin/pda-tts.sh

# Make it executable
chmod +x ~/bin/pda-tts.sh
```

### 3. Configure Claude Code hooks

Add the following to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/bin/pda-tts.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "~/bin/pda-tts.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/bin/pda-tts.sh"
          }
        ]
      }
    ]
  }
}
```

### 4. Test it

```bash
# Run the test suite
./test.sh

# List the voices this machine has
~/bin/pda-tts.sh --voices

# Hear a phrase with the current voice settings
~/bin/pda-tts.sh --say "Hello from PDA"

# Print what your recent real sessions would have said (dry run, calls Haiku)
./replay.sh 5
```

## Configuration

Settings are bash assignments in `~/.config/pda-tts/config`. Start from `config.example`, which explains every setting with its range and the notable voices. `--voices` lists what the machine has installed. Environment variables override the file, so you can try a voice without editing anything:

```bash
PDA_TTS_ESPEAK_VOICE=en-gb+m3 PDA_TTS_ESPEAK_SPEED=160 ~/bin/pda-tts.sh --say "Task complete"
```

`ESPEAK_*` settings apply only to espeak-ng and `WIN_*` only to the Windows voices, so one file can hold both: the Windows engine falls back to espeak-ng with its own settings.

| Variable | Default | Description |
|----------|---------|-------------|
| `PDA_TTS_ENGINE` | `auto` | `auto` tries the engines in the order above; `windows` uses the Windows voices first and falls back to `auto` when PowerShell is missing or fails |
| `PDA_TTS_ESPEAK_VOICE` | `en-us+f4` | espeak-ng `<language>+<variant>`; `--voices` lists both |
| `PDA_TTS_ESPEAK_SPEED` | `180` | Words per minute, 80 to 450 |
| `PDA_TTS_ESPEAK_PITCH` | `120` | 0 to 99; anything above 99 sounds the same as 99 |
| `PDA_TTS_ESPEAK_VOLUME` | `100` | 0 to 200 |
| `PDA_TTS_WIN_VOICE` | `Microsoft Zira Desktop` | Windows voice name from `--voices`; an unknown name keeps the system default |
| `PDA_TTS_WIN_RATE` | `0` | Windows speed, -10 to 10 |
| `PDA_TTS_WIN_VOLUME` | `100` | Windows volume, 0 to 100 |
| `PDA_TTS_SUMMARY_MODEL` | `haiku` | Model for the Stop line; `off` speaks the reply's first sentence |
| `PDA_TTS_SUMMARY_TIMEOUT` | `15` | Seconds to wait for the model |
| `PDA_TTS_MUTE` | (unset) | Silences the script; export it in a cron job to mute that job's headless sessions only |
| `PDA_TTS_LOG` | `~/claude-hooks.log` | Log file location |
| `PDA_TTS_LOG_MAX_BYTES` | `262144` | Past this size the log is cut to its newer half |
| `PDA_TTS_CONFIG` | `~/.config/pda-tts/config` | Config file location |
| `PDA_TTS_DRY_RUN` | (unset) | Prints the message instead of speaking; `voice` prints the engine and its settings |

### Per-event voices

Every voice setting (`ENGINE`, `ESPEAK_VOICE`, `ESPEAK_SPEED`, `ESPEAK_PITCH`, `ESPEAK_VOLUME`, `WIN_VOICE`, `WIN_RATE`, `WIN_VOLUME`) also takes an event suffix: `_STOP`, `_NOTIFICATION` or `_SESSIONSTART`. The suffixed setting wins for that event, wherever each one is set; events without one use the general setting. To hear an event's voice, pass the event after the text:

```bash
~/bin/pda-tts.sh --say "my-app needs your permission." Notification
```

### Example setups

Linux, espeak-ng only:

```bash
PDA_TTS_ESPEAK_VOICE=en-gb+f3
PDA_TTS_ESPEAK_SPEED=170
PDA_TTS_ESPEAK_PITCH=60
```

WSL, Windows voice for everything:

```bash
PDA_TTS_ENGINE=windows
PDA_TTS_WIN_VOICE="Microsoft Zira Desktop"
```

WSL, a voice per kind of message: Zira reports finished work, David asks for input, and espeak announces a new session:

```bash
PDA_TTS_ENGINE=windows
PDA_TTS_WIN_VOICE="Microsoft Zira Desktop"
PDA_TTS_WIN_VOICE_NOTIFICATION="Microsoft David Desktop"
PDA_TTS_WIN_RATE_NOTIFICATION=1
PDA_TTS_ENGINE_SESSIONSTART=auto
PDA_TTS_ESPEAK_VOICE_SESSIONSTART=en-us+klatt
```

### Sound file fallback

If you prefer a notification sound instead of TTS, create `~/pda/notify.wav` and ensure espeak-ng is not installed. The script will fall back to playing the sound file.

### Logging

All events are logged to `~/claude-hooks.log` (or `$PDA_TTS_LOG`). Check this file for debugging:

```bash
tail -f ~/claude-hooks.log
```

## Development

Run tests before committing:

```bash
./test.sh
```

The test suite runs with a stub `claude` and a stub `espeak-ng` in a temp dir, so it never calls a model, makes no sound and does not touch your config or log.

## License

MIT
