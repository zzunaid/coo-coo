# CooCoo — macOS App Specification

> Read `00-overview.md` first. This document is the implementation spec for the macOS app.

## Goal

A SwiftUI menu bar app that:
1. Listens for state events from Claude Code hooks
2. Shows an animated companion in the menu bar
3. Provides an always-on-top floating widget on the screen
4. Sends push notifications to the paired iPhone via APNs
5. Has a preferences window for customization

## Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI for in-app, AppKit (`NSStatusItem`, `NSPanel`) for menu bar + floating widget
- **Min target**: macOS 14 (Sonoma) — needed for interactive widgets and modern SwiftUI APIs
- **Networking**: Foundation's `URLSession` for APNs, Apple's `Network.framework` for local TCP listener
- **No third-party deps** if avoidable. If you need a Lottie player, use [`lottie-spm`](https://github.com/airbnb/lottie-spm) via SPM.

---

## Project structure

```
CooCoo/
├── CooCooApp.swift              — entry point, NSApplicationDelegate
├── AppDelegate.swift            — menu bar setup, lifecycle
├── State/
│   ├── CompanionState.swift     — state enum + ObservableObject store
│   ├── Character.swift          — character model
│   └── Characters.swift         — loads characters.json
├── Watcher/
│   ├── HookListener.swift       — TCP listener on :47291
│   └── APNsPusher.swift         — pushes state to iPhone
├── UI/
│   ├── MenuBarIcon.swift        — animated companion in menu bar
│   ├── PopoverView.swift        — dropdown shown when icon clicked
│   ├── FloatingWidget.swift     — always-on-top NSPanel
│   ├── PreferencesView.swift    — main app window
│   └── Characters/
│       ├── CharacterView.swift  — renders any character at any state
│       ├── PigeonView.swift     — Gerald
│       ├── DogView.swift        — BooBoo
│       ├── CatView.swift        — Mr. Whiskers
│       ├── FrogView.swift       — Kermit Jr.
│       ├── RaccoonView.swift    — Bandit
│       └── DuckView.swift       — Quackers
├── Pairing/
│   ├── PairingManager.swift     — generates code, manages iPhone link
│   └── BonjourAdvertiser.swift  — local network discovery
├── Sounds/
│   ├── coo.caf, bark.caf, ...
└── Resources/
    └── characters.json
```

---

## Phase 1: minimum viable pigeon (start here)

**Goal**: get Gerald in the menu bar reacting to terminal state.

### 1.1 Hide the dock icon
In `Info.plist`, set `LSUIElement = YES`.

### 1.2 App lifecycle (`CooCooApp.swift` + `AppDelegate.swift`)

```swift
@main
struct CooCooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { PreferencesView().environmentObject(delegate.state) }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let state = CompanionStateStore()
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var floatingWindow: FloatingWindow?
    var hookListener: HookListener!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        setupFloatingWidget()
        startHookListener()
    }
}
```

### 1.3 State store (`CompanionState.swift`)

```swift
enum CompanionState: String, Codable {
    case idle, thinking, waiting, sleepy, done
}

class CompanionStateStore: ObservableObject {
    @Published var state: CompanionState = .idle
    @Published var message: String = ""
    @Published var lastUpdate: Date = Date()
    @Published var character: Character = Characters.default

    func transition(to newState: CompanionState, message: String = "") {
        DispatchQueue.main.async {
            self.state = newState
            self.message = message.isEmpty ? self.character.voice[newState]! : message
            self.lastUpdate = Date()
            if newState == .waiting {
                self.playAlertSound()
                APNsPusher.shared.send(state: newState, message: self.message)
            }
        }
    }

    private func playAlertSound() {
        guard let url = Bundle.main.url(forResource: character.sound, withExtension: "caf") else { return }
        NSSound(contentsOf: url, byReference: false)?.play()
    }
}
```

### 1.4 TCP listener (`HookListener.swift`)

Listens on `localhost:47291`. Receives JSON like `{"state":"waiting","message":"proceed?"}` and updates the state store.

```swift
class HookListener {
    let port: NWEndpoint.Port = 47291
    var listener: NWListener?
    let store: CompanionStateStore

    init(store: CompanionStateStore) { self.store = store }

    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            listener = try NWListener(using: params, on: port)
            listener?.newConnectionHandler = { conn in self.handle(conn) }
            listener?.start(queue: .global())
        } catch { print("listener failed: \(error)") }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stateStr = json["state"] as? String,
                  let state = CompanionState(rawValue: stateStr) else {
                conn.cancel(); return
            }
            let msg = json["message"] as? String ?? ""
            self.store.transition(to: state, message: msg)
            conn.cancel()
        }
    }
}
```

### 1.5 Menu bar icon (`MenuBarIcon.swift`)

The menu bar icon should show an animated mini-Gerald. Approach: render the SVG character to an `NSImage` periodically, OR — simpler — use emoji that swaps per state for v1.

**V1 (emoji approach)**:
```swift
func refreshMenuBarIcon(state: CompanionState) {
    let title: String
    switch state {
    case .idle:     title = "🐦"
    case .thinking: title = "🐦💭"
    case .waiting:  title = "🚨🐦🚨"
    case .sleepy:   title = "🐦💤"
    case .done:     title = "🐦✓"
    }
    statusItem.button?.title = title
}
```

**V2 (animated SVG approach)**: Use a small `NSHostingView<CharacterView>` and capture it to an `NSImage` every frame. Or ship a sprite sheet `.gif` per state and use `NSImage.animated`.

### 1.6 Floating widget (`FloatingWidget.swift`)

An `NSPanel` subclass that:
- Floats above all windows (`level = .floating`)
- Is borderless and transparent (`styleMask = [.borderless]`, `isOpaque = false`)
- Lives across all spaces (`collectionBehavior = [.canJoinAllSpaces, .stationary]`)
- Can be dragged (`isMovableByWindowBackground = true`)
- Persists position across launches (save to UserDefaults)
- Contains an `NSHostingView<FloatingWidgetView>` with animated character + message text

See the floating-widget design in `coocoo-design-system.html` (section 3). Key visual states:
- **Idle**: white background, subtle drop shadow
- **Thinking**: warm yellow background
- **Waiting**: red background, pulsing shadow animation, shake animation on the character
- **Sleepy**: lavender background
- **Done**: green background

### 1.7 Claude Code hook script

Ship this Python file in the app bundle. Installer copies it to `~/.coocoo/hooks/coocoo-notify.py` and patches `~/.claude/settings.json`.

```python
#!/usr/bin/env python3
import json, socket, sys

PORT = 47291

def main():
    state = sys.argv[1] if len(sys.argv) > 1 else "idle"
    try:
        ctx = json.loads(sys.stdin.read() or "{}")
        msg = ctx.get("message", "") if state == "waiting" else ""
        if state == "thinking":
            tool = ctx.get("tool_name", "")
            msg = f"Using {tool}..." if tool else "Working..."
    except: msg = ""

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(("127.0.0.1", PORT))
            s.sendall(json.dumps({"state": state, "message": msg}).encode())
    except: pass

if __name__ == "__main__":
    main()
```

Hook config to inject into `~/.claude/settings.json`:
```json
{
  "hooks": {
    "Notification": [{"hooks": [{"type": "command", "command": "~/.coocoo/hooks/coocoo-notify.py waiting"}]}],
    "Stop":         [{"hooks": [{"type": "command", "command": "~/.coocoo/hooks/coocoo-notify.py done"}]}],
    "PreToolUse":   [{"hooks": [{"type": "command", "command": "~/.coocoo/hooks/coocoo-notify.py thinking"}]}]
  }
}
```

**Phase 1 acceptance**: Run `claude` in a terminal. When Claude asks for permission, the menu bar emoji changes to 🚨🐦🚨, the floating widget turns red, and a coo sound plays. Done. Ship it.

---

## Phase 2: animated characters

Replace the emoji menu bar icon with real animated SVG characters. Implement all 6 characters as SwiftUI views.

### 2.1 Character data

Bundle `characters.json` (see overview). Load on startup:

```swift
enum Characters {
    static let all: [Character] = loadFromBundle("characters.json")
    static let `default` = all.first { $0.id == "pigeon" }!
}
```

### 2.2 Character views

Each character is a SwiftUI `View` that takes a state. Translate the SVG drawings from `coocoo-design-system.html` to SwiftUI `Shape`s and `Path`s. Example for the pigeon body:

```swift
struct PigeonBody: View {
    @State private var breatheScale: CGFloat = 1.0

    var body: some View {
        Ellipse()
            .fill(Color(hex: "8aa0b2"))
            .frame(width: 124, height: 100)
            .scaleEffect(x: 1, y: breatheScale)
            .onAppear {
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    breatheScale = 1.04
                }
            }
    }
}
```

### 2.3 Animation timing reference

Pull exact timings from `coocoo-design-system.html`. Key ones:
- `belly-breathe`: 3.2s in idle, 1.8s in thinking, 4s in sleepy
- `blink`: 4.5s loop, 0.1s closure
- `shake`: 0.35s in waiting
- `wing-flap`: 0.25s in waiting
- `pupil-dart`: 5s in idle, 0.4s in waiting

---

## Phase 3: APNs push to iPhone

### 3.1 Pairing (Phase 3a)

On first launch of both apps:
1. Mac generates a 4-character code (e.g., `7H2K`)
2. Mac advertises via Bonjour: `_coocoo._tcp` on local network
3. iPhone finds it, exchanges pairing code over a quick TCP handshake
4. iPhone sends its APNs device token to Mac
5. Mac stores token in Keychain
6. Both devices show "✓ Paired"

### 3.2 APNs push (Phase 3b)

Mac sends push notification directly via APNs HTTP/2 API:

```swift
class APNsPusher {
    static let shared = APNsPusher()
    private let session = URLSession.shared

    func send(state: CompanionState, message: String) {
        guard let token = Keychain.iPhoneToken else { return }
        let url = URL(string: "https://api.push.apple.com/3/device/\(token)")!

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("com.coocoo.ios", forHTTPHeaderField: "apns-topic")
        req.setValue("alert", forHTTPHeaderField: "apns-push-type")

        // For Live Activity, content-state goes in aps.content-state
        let payload: [String: Any] = [
            "aps": [
                "alert": ["title": "🚨 CooCoo!", "body": message],
                "sound": "coo.caf",
                "content-state": ["state": state.rawValue, "message": message]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        // JWT auth required — see Apple docs for the auth token signing
        req.setValue("bearer \(generateJWT())", forHTTPHeaderField: "authorization")

        session.dataTask(with: req).resume()
    }
}
```

You'll need to sign up for an Apple Developer account, create an APNs Auth Key (`.p8`), and use it to sign JWT tokens for each request. Documentation: [Apple Push Notification Service](https://developer.apple.com/documentation/usernotifications/sending_notification_requests_to_apns).

---

## Phase 4: preferences window

A standard Mac preferences window with these sections (see `coocoo-app-screens.html` section 02 for visual reference):

- **Character**: dropdown to pick character + rename
- **Floating widget**: toggle show/hide, pulse red toggle
- **Sound**: toggle coo + system sound
- **Claude Code hooks**: status indicator + reinstall button
- **iPhone sync**: paired status + show pairing code button

---

## Build & ship

### Signing & sandbox

Required entitlements (in `CooCoo.entitlements`):
- `com.apple.security.app-sandbox`: YES
- `com.apple.security.network.server`: YES (for local TCP listener)
- `com.apple.security.network.client`: YES (for APNs)

### Installer

Distribute as a `.dmg` containing the `.app` bundle. The first launch should:
1. Prompt to install Claude Code hooks (copies script to `~/.coocoo/hooks/`, patches `~/.claude/settings.json`)
2. Walk through pairing with iPhone if iOS app is installed (Bonjour-discovered)

### Distribution

For v1, distribute outside the Mac App Store (developer ID signed + notarized). The local TCP server is technically allowed in the sandbox but reviewers may push back. For wider distribution, switch to a local Unix socket (`/tmp/coocoo.sock`) which is sandbox-friendly.

---

## Acceptance criteria

**Phase 1 ships when**:
- [ ] App launches, menu bar shows 🐦 (no dock icon)
- [ ] Click 🐦 → popover shows
- [ ] `echo '{"state":"waiting"}' | nc 127.0.0.1 47291` makes the icon flash 🚨🐦🚨 and plays coo sound
- [ ] Floating widget appears, can be dragged, persists across spaces
- [ ] Real Claude Code session triggers all 4 states correctly

**Phase 2 ships when**:
- [ ] Menu bar shows animated SVG character (not emoji)
- [ ] All 6 characters implemented as SwiftUI views
- [ ] All 5 states animate per the design system

**Phase 3 ships when**:
- [ ] Pairing flow works on local network
- [ ] iPhone receives APNs push when Mac state changes
- [ ] Live Activity updates within 2s of state change

---

## Reference materials

- `coocoo-design-system.html` — full visual reference, every state on every surface
- `coocoo-characters.html` — all 6 characters animated
- `coocoo-app-screens.html` — preferences window mockup
- `characters.json` — character data
