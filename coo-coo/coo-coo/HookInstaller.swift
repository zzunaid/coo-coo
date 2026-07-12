import Foundation

enum HookInstaller {

    enum Status: Equatable {
        case installed        // script present + all 3 hooks in settings.json
        case partial          // script present but settings.json missing some hooks
        case notInstalled     // script missing
        case error(String)

        var label: String {
            switch self {
            case .installed:       return "Installed"
            case .partial:         return "Partially installed"
            case .notInstalled:    return "Not installed"
            case .error(let msg):  return "Error: \(msg)"
            }
        }

        var isOK: Bool { self == .installed }
    }

    // MARK: - Paths

    // In a sandboxed app, FileManager.homeDirectoryForCurrentUser returns the
    // container path, not the real home. Claude Code reads from the real home,
    // so we use getpwuid() to get the actual /Users/<name> path.
    private static var realHomeURL: URL {
        URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir))
    }

    private static var hookDir: URL {
        realHomeURL.appendingPathComponent(".coocoo/hooks")
    }
    private static var scriptURL: URL {
        hookDir.appendingPathComponent("coocoo-notify.py")
    }
    private static var settingsURL: URL {
        realHomeURL.appendingPathComponent(".claude/settings.json")
    }

    // MARK: - Status check

    static func currentStatus() -> Status {
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptURL.path) else { return .notInstalled }

        // Check that all 3 hooks are present in settings.json
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return .partial
        }
        let needed = ["Notification", "Stop", "PreToolUse"]
        let allPresent = needed.allSatisfy { hooks[$0] != nil }
        return allPresent ? .installed : .partial
    }

    // MARK: - Install

    @discardableResult
    static func install() -> Status {
        let fm = FileManager.default

        // 1. Create ~/.coocoo/hooks/
        do {
            try fm.createDirectory(at: hookDir, withIntermediateDirectories: true)
        } catch {
            return .error("Can't create ~/.coocoo/hooks: \(error.localizedDescription)")
        }

        // 2. Write the Python script
        guard let scriptData = hookScript.data(using: .utf8) else {
            return .error("Internal: bad script encoding")
        }
        do {
            try scriptData.write(to: scriptURL)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            // Files created by this process can inherit com.apple.quarantine if the
            // app bundle was ever launched from a quarantined location. A quarantined
            // script fails to execute non-interactively (no Finder dialog to approve
            // it), so Claude Code's hook calls silently fail. Strip it unconditionally.
            removexattr(scriptURL.path, "com.apple.quarantine", 0)
        } catch {
            return .error("Can't write script: \(error.localizedDescription)")
        }

        // 3. Patch ~/.claude/settings.json
        do {
            try patchSettings()
        } catch {
            return .error("Can't update settings.json: \(error.localizedDescription)")
        }

        return .installed
    }

    // Strips quarantine from an already-installed script. Safe to call anytime —
    // no-ops if the script is missing or already clean.
    static func repairQuarantine() {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return }
        removexattr(scriptURL.path, "com.apple.quarantine", 0)
    }

    // MARK: - settings.json patch

    private static func patchSettings() throws {
        let fm = FileManager.default

        // Create ~/.claude/ if needed
        let claudeDir = settingsURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: claudeDir.path) {
            try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        }

        // Read existing or start fresh
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        // Merge hooks — preserve any existing non-CooCoo hooks
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks["Notification"] = hookEntry("waiting")
        hooks["Stop"]         = hookEntry("done")
        hooks["PreToolUse"]   = hookEntry("thinking")
        root["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL)
    }

    private static func hookEntry(_ state: String) -> [[String: Any]] {
        [["hooks": [["type": "command",
                     "command": "~/.coocoo/hooks/coocoo-notify.py \(state)"]]]]
    }

    // MARK: - Embedded script

    private static let hookScript = #"""
#!/usr/bin/env python3
"""
CooCoo hook script — called by Claude Code hooks to notify the menu bar app.
Usage: coocoo-notify.py <state>
  state: idle | thinking | waiting | done
Stdin: JSON context from Claude Code (tool name, message, etc.)
"""
import json
import os
import socket
import sys
from datetime import datetime

PORT = 47291
LOG = os.path.expanduser("~/.coocoo/hook.log")

# Keywords that indicate Claude is genuinely blocking for user input.
BLOCKING_KEYWORDS = ("permission", "approve", "allow", "confirm", "y/n", "[y", "(y/", "proceed", "continue")


def log(state, ctx, sent):
    try:
        with open(LOG, "a") as f:
            f.write(f"{datetime.now().isoformat()} [{state}] sent={sent} payload={json.dumps(ctx)}\n")
    except Exception:
        pass


def is_blocking_notification(msg: str) -> bool:
    low = msg.lower()
    return any(kw in low for kw in BLOCKING_KEYWORDS)


def main():
    state = sys.argv[1] if len(sys.argv) > 1 else "idle"

    try:
        raw = sys.stdin.read() or "{}"
        ctx = json.loads(raw)
    except Exception:
        ctx = {}

    if state == "waiting":
        msg = ctx.get("message", "")
        notification_type = ctx.get("notification_type", "")
        # idle_prompt fires when Claude finishes a turn — not actionable for the user.
        # permission_prompt fires when Claude needs the user to approve a tool call.
        if notification_type == "idle_prompt":
            log(state, ctx, sent=False)
            return
        if notification_type != "permission_prompt":
            stripped = msg.lower().strip().rstrip(".…")
            generic = stripped in ("claude is waiting for your input", "claude is waiting", "")
            if generic or (msg and not is_blocking_notification(msg)):
                log(state, ctx, sent=False)
                return
        msg = msg if msg else ""
    elif state == "thinking":
        tool = ctx.get("tool_name", "")
        msg = f"Using {tool}…" if tool else "Working…"
    else:
        msg = ""

    session_id = ctx.get("session_id", "")
    cwd = ctx.get("cwd", "")
    payload = json.dumps({"state": state, "message": msg, "session_id": session_id, "cwd": cwd}).encode()

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(("127.0.0.1", PORT))
            s.sendall(payload)
        log(state, ctx, sent=True)
    except Exception:
        log(state, ctx, sent=False)


if __name__ == "__main__":
    main()
"""#
}
