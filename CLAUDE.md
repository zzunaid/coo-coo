# Project: CooCoo for Mac

## What this is
A macOS menu bar app that watches Claude Code sessions on this Mac 
and alerts the user when Claude needs input. The mascot is Gerald 
the pigeon — animated, makes a coo sound, lives in the menu bar 
and optionally as a floating widget on screen.

## Key architectural decisions
- **Standalone Mac app** — no phone, no WebSocket, no shared 
  infrastructure with any other project.
- **Uses Claude Code hooks for state detection** — not PTY parsing. 
  The Notification, Stop, PreToolUse, and UserPromptSubmit hooks in 
  ~/.claude/settings.json call a small Python script that sends 
  events to the running Mac app via local TCP (port 47291). 
  UserPromptSubmit exists specifically to clear the "waiting" alert 
  the instant the user replies, instead of lagging until Claude's 
  first tool call or turn end.
- **SwiftUI + AppKit** — SwiftUI for in-app views, AppKit 
  (NSStatusItem, NSPanel) for menu bar and floating widget.
- **No third-party Swift dependencies** if avoidable (Firebase Analytics is an
  existing exception — see `Analytics.swift`).
- **The hook script ships as a bundled app resource, never written to disk at
  runtime.** App Sandbox silently blocks removing `com.apple.quarantine` from
  files the app creates — not just via `removexattr()`, but even via a spawned
  `/usr/bin/xattr` subprocess (Apple's "responsible process" tracking taints
  children of a sandboxed parent too). A quarantined script fails to execute
  non-interactively. Don't reintroduce runtime script-writing to `~/.coocoo/`
  for hook installation — invoke the bundled resource in place instead
  (`HookInstaller.swift`).

## Status

### ✅ Done
- Phase 1: minimum viable pigeon — TCP listener, menu bar icon, popover, floating widget, hook installer
- Phase 2: animated characters — all 6 SwiftUI character views, 12fps animated menu bar icon
- Phase 3: floating overlay window — NSPanel widget with drag, minimize, position persistence
- Phase 4: preferences window — character grid picker, state scrubber preview, sound/widget/login settings, hook installer UI
- Phase 5: multi-character system — all 6 characters selectable, with verified per-character sound profiles (`SoundPlayer.swift`)
- Notification filtering — only `permission_prompt` fires an alert; `idle_prompt` and generic "waiting for input" messages are suppressed (`coocoo-notify.py`)
- Distribution — landing page (`docs/index.html`, GitHub Pages), email capture (Formspree), analytics (GA4/Firebase, reusing the app's Firebase project), MIT `LICENSE`

### ❌ Not started
- APNs iPhone push — requires companion iOS app, Bonjour pairing, JWT-signed APNs

## Spec docs
- `docs/00-overview.md` — architecture, character system, state enum
- `docs/01-macos-app-spec.md` — full macOS app spec with phases
- `docs/characters.json` — character data (we only need Gerald for 
  Phase 1, but the schema is here for later)
- `docs/previews/*.html` — visual references

## Conventions
- Swift 5.9+, target macOS 14 Sonoma minimum
- LSUIElement = YES in Info.plist (no dock icon)
- Use new files over modifying existing ones when possible
- Don't add dependencies without asking
