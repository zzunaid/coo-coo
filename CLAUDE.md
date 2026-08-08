# Project: CooCoo for Mac

## What this is
A macOS menu bar app that watches Claude Code sessions on this Mac 
and alerts the user when Claude needs input. The mascot is Gerald 
the pigeon — animated, makes a coo sound, lives in the menu bar 
and optionally as a floating widget on screen.

## Key architectural decisions
- **Standalone Mac app today** — no phone, no WebSocket, no shared
  infrastructure with any other project. A companion iOS/watchOS app is a
  real but deliberately-deferred P2 idea — see Roadmap below — not a
  contradiction of this line; it just hasn't been started.
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

### Roadmap

**P0 — nothing currently staged.** (Was: session crash-leak reap + floating
widget multi-session fix — both shipped in `v1.2.2`. P0 means "committed
locally, not yet released"; empty until the next batch exists.)

**P1 — near-term, builds on what's shipped, contained scope**
- **Auto-updates — in progress.** Went with Sparkle over the lightweight
  custom-check alternative. CooCoo is sandboxed
  (`com.apple.security.app-sandbox = YES`), so this isn't just adding the
  package — Sparkle's sandboxed-app support needs two additional XPC
  Service targets (Installer, Downloader) that do the actual privileged
  install step out-of-process, since a sandboxed app can't replace its own
  bundle directly. Steps: (1) user adds the Sparkle SPM package + the two
  XPC targets in Xcode — can't be done by hand-editing project.pbxproj
  safely; (2) Claude writes the updater integration code, Info.plist keys,
  "Check for Updates…" menu item; (3) generate an EdDSA signing key pair,
  private key stays out of the repo, public key gets embedded; (4) host an
  `appcast.xml` on GitHub Pages alongside the landing page, fold "sign the
  DMG + update the appcast" into the release process below once that
  exists.
- Notification content image: one consistent generic image (not
  per-character) attached to every notification. A per-character version
  was built and verified working, then reverted — the user didn't like how
  it looked. Simpler version: one static asset, not rendered per character.
- Better "Walk" alert-style animations — richer motion for the existing
  Walk alert style (see `AlertPerformance.swift` / the "Alert Style (Walk /
  Hang)" section of `AppDelegate.swift`)
- **Remove Firebase Analytics** (`Analytics.swift`, `GoogleService-Info.plist`,
  the Firebase SPM packages) — it's the one exception to "no third-party
  Swift dependencies" (see Key architectural decisions above). Not a
  contradiction of the Growth section below — growth here means visibility
  (README, GitHub, posting where users already are), not usage tracking, so
  dropping Firebase and pursuing growth are independent decisions. "Review
  GA4/Firebase analytics for usage" was considered and dropped for this
  reason — moot once Firebase Analytics is gone.

**P2 — big bet, long horizon, real but not started**
- iOS companion app (Live Activity, Dynamic Island, push notifications —
  the alert follows you off your Mac)
- watchOS companion/complication
- WidgetKit home-screen/lock-screen widgets
- Real cost, not just unstarted work: Apple Developer Program enrollment
  ($99/yr, currently unnecessary since the Mac app distributes outside the
  App Store), APNs infrastructure, App Store review, and 2-3 more
  codebases to maintain forever. This is why it's P2, not P0/P1 — see Key
  architectural decisions above.

**Growth — separate axis from P0/P1/P2 above, tiered by effort not priority.**
For a tool this narrow (Claude Code users, Mac only), growth is about
visibility to an audience that already exists, not broad marketing.

- *Highest-leverage, cheapest:*
  - Reddit post — copy drafted, video ready
    (`~/Desktop/coocoo-demo-social.mp4`), not yet posted. r/ClaudeAI has a
    "Built with Claude" flair that fits, but gates Showcase posts on a
    minimum account karma — check current karma before posting, or post to
    r/macapps / r/SideProject first (no karma gate) while building karma
    there in parallel
  - GitHub repo polish: topics/tags (`claude-code`, `macos`,
    `menu-bar-app`), a punchy one-line description, a license badge — not
    yet done
- *Medium effort:*
  - Homebrew cask (`brew install --cask coocoo`) — doesn't drive discovery,
    lowers friction for people who already found it
  - Get listed in any "awesome-claude-code" / Claude Code resource lists on
    GitHub
- *Lower priority for this project's shape:*
  - Landing page SEO — traffic will come from GitHub/social, not search,
    for a tool like this

## Spec docs
- `docs/00-overview.md` — architecture, character system, state enum
- `docs/01-macos-app-spec.md` — full macOS app spec with phases
- `docs/characters.json` — character data (we only need Gerald for 
  Phase 1, but the schema is here for later)
- `docs/previews/*.html` — visual references

**Note on scope**: these spec docs describe a larger cross-platform vision
(companion iOS app, APNs push, Bonjour pairing, Dynamic Island/Live
Activities) from before the project was deliberately scoped down to a
standalone Mac app (see Key architectural decisions above). That direction
is back on the table as the P2 item in the Roadmap above, but a real iOS
spec doc was never actually written — `02-ios-rn-app-spec.md`, referenced
in `00-overview.md`'s project structure, doesn't exist. Don't assume it's
fleshed out; treat the iOS/Watch/widget vision as a diagram and a few
paragraphs, not a ready-to-build spec.

## Conventions
- Swift 5.9+, target macOS 14 Sonoma minimum
- LSUIElement = YES in Info.plist (no dock icon)
- Use new files over modifying existing ones when possible
- Don't add dependencies without asking

## Checking whether the running app is current
The real, user-facing install is `/Applications/CooCoo.app` — not the Xcode
DerivedData build, which is a separate debug artifact and often stale. Note
the capitalization: the Xcode scheme/product is `coo-coo.app` (lowercase,
matches the target name), but the release DMG's staged folder is named
`CooCoo.app`, so that's the name Finder gives it when a user drags it to
Applications. Don't assume lowercase — check both if unsure (`ls /Applications
| grep -i coo-coo`). The bundle executable inside stays `coo-coo` either way.
- Version/build: `defaults read /Applications/CooCoo.app/Contents/Info.plist
  CFBundleShortVersionString` (and `CFBundleVersion`), compare against
  `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in
  `coo-coo/coo-coo.xcodeproj/project.pbxproj` and against `git log -1`.
- Running/healthy: `ps aux | grep coo-coo` and `lsof -i :47291 -sTCP:LISTEN`
  (the hook TCP port).
- Functional test: pipe a fake event through the real hook script, e.g.
  `python3 hooks/coocoo-notify.py <<< '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}'`
  — exit 0 means it reached the app over TCP.
- Hook wiring: `~/.claude/settings.json` hook commands should point at
  `/Applications/CooCoo.app/Contents/Resources/coocoo-notify.py` and every
  command should end in `; exit 0` — CooCoo must never be able to block
  Claude Code just because its own script is missing or erroring (see
  `HookInstaller.swift`). If a terminal session shows a hook error pointing
  somewhere stale (e.g. an old `~/Desktop/coo-coo.app` path), that session
  just started before a path fix and needs a restart — it's not an app bug.

## Release process
1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in
   `coo-coo.xcodeproj/project.pbxproj`, commit.
2. Tag `vX.Y.0` at that commit.
3. Build the DMG, name it `CooCoo-vX.Y.0.dmg` (note: `v1.0.0`'s asset was
   just `CooCoo.dmg` — inconsistent, but every release since follows the
   `CooCoo-vX.Y.0.dmg` pattern). Xcode's Organizer (Product → Archive →
   Distribute App → Export Notarized App) only exports the notarized
   `coo-coo.app` itself — it does **not** build a DMG. That's a separate
   packaging step, done by hand from a Terminal:
   ```
   # stage: rename the exported app, add the Applications shortcut + volume icon
   mkdir -p /tmp/dmg-stage
   cp -R <path-to-exported>/coo-coo.app /tmp/dmg-stage/CooCoo.app   # capitalized
   ln -s /Applications /tmp/dmg-stage/Applications
   cp <old-release-dmg-mounted>/.VolumeIcon.icns /tmp/dmg-stage/    # reuse existing icon/layout

   # build a writable image, set the custom volume icon flag, then compress
   hdiutil create -volname CooCoo -srcfolder /tmp/dmg-stage -ov -format UDRW -size 100m /tmp/CooCoo-tmp.dmg
   hdiutil attach /tmp/CooCoo-tmp.dmg -mountpoint /tmp/coocoo-mount -nobrowse -noautoopen
   SetFile -a C /tmp/coocoo-mount        # marks the volume as having a custom icon
   hdiutil detach /tmp/coocoo-mount -quiet
   hdiutil convert /tmp/CooCoo-tmp.dmg -format UDZO -imagekey zlib-level=9 -o CooCoo-vX.Y.0.dmg
   ```
   The volume icon/`.DS_Store` can be lifted from mounting any previous
   release's DMG — the layout (volume named `CooCoo`, containing `CooCoo.app`
   + an `Applications` symlink) hasn't changed since `v1.0.0`. Verify with
   `spctl -a -vvv -t install CooCoo-vX.Y.0.dmg` (or the mounted `.app` inside)
   before shipping — should say `source=Notarized Developer ID`.
4. `gh release create vX.Y.0 <dmg> --title "CooCoo vX.Y.0" --notes "..."`.
5. **Update the download links** — this step has been missed before.
   Three places hardcode the release tag/filename and must all be bumped
   together:
   - `README.md` — "Grab the DMG directly" link
   - `docs/index.html` — footer "Releases" link AND the `DOWNLOAD_URL` JS
     variable (this one also embeds the asset filename, not just the tag)
   - Push to `master` — GitHub Pages (`https://zzunaid.github.io/coo-coo/`)
     rebuilds from `docs/index.html` automatically within a minute or two.
