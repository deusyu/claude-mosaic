# Claude Mosaic

macOS menu bar app for monitoring [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://openai.com/index/introducing-codex/) sessions.

Each running session appears as a colored tile in the menu bar — green for active, amber for pending input, gray for idle. Click to open the panel, click a tile to jump to the terminal.

![mosaic](https://img.shields.io/badge/macOS-13%2B-blue)

## Features

- **Mosaic grid** in the menu bar — one tile per session, overflow fades to ghost tiles
- **Session discovery** — finds Claude/Codex processes via `pgrep`, resolves TTY, CWD, and transcript
- **Status detection** — parses JSONL transcripts to determine active/pending/idle state
- **Pending alerts** — plays a sound and flashes the dock icon when a session needs input
- **Terminal focusing** — click a tile to switch to the right iTerm2/Ghostty/Alacritty/Terminal.app window
- **Hook integration** — `SessionStart` hook maps each TTY to its transcript for precise multi-session tracking
- **Auto setup** — registers login item and hooks on first launch, no manual config needed
- **Dark/light mode** — adaptive colors via system `NSColor`
- **Provider branding** — Claude (#D97757) and Codex (#10A37F) with distinct colors

## Install

### From release (recommended)

Download the `.dmg` from [Releases](https://github.com/deusyu/claude-mosaic/releases), open it, and drag `ClaudeMosaic.app` to Applications. Launch the app — it auto-configures hooks and login item.

### From source

```bash
./install.sh
```

This builds the Swift package, creates a `.app` bundle, and launches it. The app auto-registers as a login item and installs the `SessionStart` hook.

## Uninstall

```bash
./uninstall.sh
```

## CLI

```
claude-mosaic                   Launch menu bar app
claude-mosaic poll              Discover sessions, print JSON
claude-mosaic hook              SessionStart hook handler (stdin)
claude-mosaic focus             Focus terminal window
claude-mosaic demo [N]          Demo mode with N sessions
claude-mosaic hooks-install     Register hook in settings.json
claude-mosaic hooks-uninstall   Remove hooks from settings.json
claude-mosaic unregister        Remove login item registration
```

## How it works

```
pgrep claude/codex
    → ps (TTY)
    → lsof (CWD)
    → hook state file or fallback transcript resolution
    → JSONL tail parsing for status
    → menu bar tile grid
```

**Transcript resolution** uses a two-pass approach:
1. **Hook-based (precise)** — `SessionStart` hook writes a state file mapping each TTY to its transcript path
2. **Fallback** — picks the most recent unclaimed `.jsonl` in the project directory, with an exclusion set to prevent sharing

**Status detection** reads the last 64KB of the transcript JSONL:
- Claude: tracks `tool_use`/`tool_result` pairing, plan mode, last message role
- Codex: tracks `function_call`/`function_call_output` pairing, escalation requests

## Project structure

```
Sources/ClaudeMosaic/
  App.swift              CLI entry point, AppDelegate, polling, menu bar icon
  Views.swift            SwiftUI views: panel, tiles, badges, logo
  Theme.swift            Colors and gradients
  SessionDiscovery.swift Data models, process discovery, transcript resolution
  TranscriptParser.swift JSONL status parsing for Claude and Codex
  TerminalFocus.swift    AppleScript terminal window focusing
  HookManager.swift      Hook install/uninstall/handler
  AutoSetup.swift        First-launch setup: login item + hooks
  Shell.swift            Shared shell and AppleScript helpers
```

## Requirements

- macOS 13+
- Swift 5.9+
- Claude Code or Codex running in a terminal

## License

MIT
