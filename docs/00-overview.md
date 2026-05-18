# CooCoo — Project Specification

## What is CooCoo?

A cross-platform notification companion for Claude Code users. An animated animal mascot (Gerald the pigeon by default, or one of 5 other characters) watches your Claude Code sessions and alerts you when Claude needs input — through a Mac menu bar app, an iOS app, Dynamic Island, Live Activities, push notifications, and an always-on-top floating widget.

**Tagline**: *"the pigeon that watches Claude so you don't have to"*

---

## System architecture

```
┌─────────────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ Claude Code             │     │ CooCoo Mac App   │     │ CooCoo iOS App   │
│ (user's terminal)       │     │ (menu bar daemon)│     │ (RN app)         │
├─────────────────────────┤     ├──────────────────┤     ├──────────────────┤
│ - Notification hook     │────▶│ - TCP listener   │────▶│ - Live Activity  │
│ - Stop hook             │     │ - Status manager │     │ - Dynamic Island │
│ - PreToolUse hook       │     │ - Menu bar icon  │     │ - Home widget    │
└─────────────────────────┘     │ - Floating widget│     │ - Push notifs    │
                                │ - APNs pusher    │     │ - In-app UI      │
                                └──────────────────┘     └──────────────────┘
                                          │                       ▲
                                          │                       │
                                          └──── APNs (Apple) ─────┘
```

### Data flow

1. User runs `claude` in their terminal
2. When Claude needs input, Claude Code fires the `Notification` hook
3. Hook script (Python) calls `localhost:47291` on the Mac with a JSON payload like `{"state": "waiting", "message": "proceed? [y/n]"}`
4. Mac daemon updates its internal state
5. Mac UI updates instantly: menu bar icon, floating widget, popover
6. Mac daemon sends APNs push to paired iPhone with the new state
7. iOS app receives push, updates Live Activity / Dynamic Island, sends local notification

### State enum (used everywhere)

```typescript
type CompanionState =
  | "idle"      // No activity, just watching
  | "thinking"  // Claude is working (PreToolUse fired)
  | "waiting"   // Claude needs user input (Notification fired) ← the important one
  | "sleepy"    // Long task running (>30s in thinking state)
  | "done"      // Task complete (Stop fired)
```

---

## Character system

There are **6 preset characters**, each with unique designs, sounds, and voice. Users pick one and can rename it. The character data is shared between Mac and iOS apps via the same JSON schema.

### Character schema (TypeScript)

```typescript
interface Character {
  id: string;              // "pigeon" | "dog" | "cat" | "frog" | "raccoon" | "duck"
  defaultName: string;     // "Gerald", "BooBoo", etc.
  appBrandName: string;    // "CooCoo", "BorkBork", etc. - shown in notif titles
  species: string;         // for the SVG/Lottie renderer
  sound: "coo" | "bark" | "meow" | "ribbit" | "chitter" | "quack";
  colors: {
    primary: string;
    secondary: string;
    accent: string;
    heroBg: [string, string]; // gradient
    notifBg: string;
  };
  voice: {                 // dialogue per state
    idle: string;
    thinking: string;
    waiting: string;
    sleepy: string;
    done: string;
  };
  personality: string;     // one-liner description for the picker
}
```

### The 6 characters

See `characters.json` (separate file) for full data.

| ID | Name | App brand | Sound | Vibe |
|---|---|---|---|---|
| pigeon | Gerald | CooCoo | coo | Grumpy, demands bread |
| dog | BooBoo | BorkBork | bork | Enthusiastic, treats-obsessed |
| cat | Mr. Whiskers | Meowmeow | meow | Aloof, judgmental |
| frog | Kermit Jr. | RibbitRibbit | ribbit | Zen, chill |
| raccoon | Bandit | TrashGoblin | chitter | Chaotic, sneaky |
| duck | Quackers | QuackQuack | quack | Loud, opinionated |

---

## Animation system

Each character has **5 states**, each with its own animation. Animations are:

- **Continuous** (always on): breathing, blinking, idle pupil dart
- **State-specific**: shake on waiting, peck on thinking, sleep-zzz on sleepy, happy bob on done
- **Triggered**: wings flap out instantly on waiting transition

### Recommended implementations

| Platform | Recommended approach |
|----------|---------------------|
| iOS (React Native) | Lottie via `lottie-react-native` — export one Lottie JSON per character |
| iOS (native widgets/Live Activity) | SwiftUI with `withAnimation` for transitions, `TimelineView` for breathing |
| macOS | SwiftUI for in-app, NSView with CAAnimation for menu bar icon |

### Animation keyframes (CSS reference)

```css
@keyframes belly-breathe { 0%,100% { ry: 50; } 50% { ry: 52; } }
@keyframes bob { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-4px); } }
@keyframes shake { 0%,100% { transform: rotate(0); } 20% { transform: rotate(-12deg); } 40% { transform: rotate(12deg); } 60% { transform: rotate(-10deg); } 80% { transform: rotate(10deg); } }
@keyframes blink { 0%,92%,100% { transform: scaleY(1); } 94%,98% { transform: scaleY(0.05); } }
@keyframes pupil-dart { 0%,30%,60%,100% { transform: translate(0,0); } 40% { transform: translate(-2px,1px); } 70% { transform: translate(2px,-1px); } }
```

See `coocoo-design-system.html` for the canonical reference of every animation on every state.

---

## Sound system

Each character has a unique alert sound generated via Web Audio (for the HTML preview) or shipped as `.caf` files. Use the following pitch/timbre profiles when synthesizing or commissioning real audio:

| Sound | Waveform | Frequency | Duration | Notes |
|-------|----------|-----------|----------|-------|
| coo | sine | 380→323 Hz | 0.5s × 2 | Soft, downward pitch bend, two-note |
| bark | square | 250→200 Hz | 0.15s × 3 | Sharp, triple-fire |
| meow | sawtooth | 600→840→480 Hz | 0.7s | Up-down pitch bend |
| ribbit | square | 180→234 Hz | 0.2s × 2 | Bouncy, doubled |
| chitter | triangle | 800±100 Hz random | 0.06s × 6 | Rapid burst |
| quack | sawtooth | 320→224 Hz | 0.15s × 2 | Nasal, two-note |

For production: ship `.caf` (macOS/iOS native audio format), 200-700ms each, peak volume normalized to -3dBFS, with a fade-out tail to prevent clipping.

---

## Pairing flow (Mac ↔ iOS)

1. User installs both apps
2. Mac app generates a 4-character pairing code (e.g., `7H2K`) shown in Preferences
3. User enters code in iOS app *OR* scans QR code from Mac
4. iOS app sends its APNs device token + pairing code to a small relay service (or Mac app via local network discovery on same WiFi for v1)
5. Mac app stores APNs token, can now push notifications directly via APNs HTTP/2 API

**For v1 (simpler)**: Both devices on same WiFi network. Mac app advertises via Bonjour. iOS finds it and exchanges pairing code over local TCP. No relay service needed. Push notifications still go through Apple's APNs (Mac app calls APNs directly with stored token).

**For v2**: Add a small relay service so devices don't need to be on the same network for pairing.

---

## Shared assets

### Logo / app icon variants
- **Classic Gerald** (pigeon on warm yellow) — default
- **OO = eyes** (wordmark with pigeon eyes as the O's) — alternative
- **Per-character variants** — when user switches character, app icon swaps too (iOS supports alternate app icons via `setAlternateIconName`)

### Brand colors
```
--bg: #f5f0e6        (warm cream — main background)
--accent: #378ADD    (blue — interactive)
--danger: #e24b4a    (red — waiting state)
--warn: #f4a261      (orange — thinking state)
--success: #97c459   (green — done state)
--sleep: #7F77DD     (purple — sleepy state)
```

### Typography
- **iOS**: SF Pro Display (system)
- **macOS**: SF Pro (system)
- All character names use **bold/black** weight, dialogue uses **italic** for personality

---

## Project structure

This spec ships as 3 documents:

1. `00-overview.md` (this file) — shared concepts, character data, architecture
2. `01-macos-app-spec.md` — full macOS app spec for Claude Code
3. `02-ios-rn-app-spec.md` — full iOS React Native app spec for Claude Code
4. `characters.json` — canonical character data, drop into both projects

Each spec is self-contained: open one with Claude Code, get a working app.

---

## Quick start: hand this to Claude Code

```
> /clear
> Read 00-overview.md and 01-macos-app-spec.md from the project root.
> Then scaffold the Swift project and implement Phase 1.
```

Same flow for iOS:
```
> /clear
> Read 00-overview.md and 02-ios-rn-app-spec.md.
> Then scaffold the React Native project and implement Phase 1.
```
