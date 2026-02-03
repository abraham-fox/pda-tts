# pda-tts

A text-to-speech notification hook for [Claude Code](https://claude.ai/claude-code). Get audible notifications when Claude needs your attention or completes a task.

## What it does

This script integrates with Claude Code's hook system to provide voice notifications for:

- **SessionStart**: Announces when a session begins ("Systems online.")
- **Stop**: Announces when Claude finishes a task ("Task complete.")
- **Notification**: Announces when Claude needs your input ("Awaiting your input.")

The script reads the JSON payload from Claude Code, extracts the event type and message, and speaks it using your system's text-to-speech engine.

## How it works

1. **Reads stdin**: Uses bash `read -t` to safely read the JSON payload with a timeout (prevents hanging)
2. **Parses JSON**: Uses `jq` to extract `hook_event_name` and `message` fields
3. **Generates fallback messages**: If no message is provided, uses sensible defaults based on event type
4. **Logs events**: Writes to `~/claude-hooks.log` for debugging (configurable via `PDA_TTS_LOG`)
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

# Or test manually with a sample payload
echo '{"hook_event_name":"Notification","message":"Hello from PDA"}' | ~/bin/pda-tts.sh

# Test without payload (uses default message)
~/bin/pda-tts.sh
```

## Configuration

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PDA_TTS_LOG` | `~/claude-hooks.log` | Log file location |
| `PDA_TTS_DRY_RUN` | (unset) | If set, prints message instead of speaking |

### Voice settings (espeak-ng)

The script uses these espeak-ng settings by default:
- `-s 180` - Speed (words per minute)
- `-p 120` - Pitch
- `-v en-us+f4` - Voice variant

To customize, edit the `say_it()` function in the script.

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

The test suite uses dry-run mode (`PDA_TTS_DRY_RUN=1`) to verify message parsing without triggering TTS.

## License

MIT
