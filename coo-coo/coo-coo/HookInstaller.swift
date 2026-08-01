import Foundation

enum HookInstaller {

    enum Status: Equatable {
        case installed        // settings.json hooks point at the bundled script
        case notInstalled     // settings.json missing some/all hooks
        case error(String)

        var label: String {
            switch self {
            case .installed:       return "Installed"
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

    private static var settingsURL: URL {
        realHomeURL.appendingPathComponent(".claude/settings.json")
    }

    // The hook script ships as a bundled resource and is invoked in place via
    // `python3 <path>` — never copied out to a standalone file. A file *written*
    // by this app at runtime inherits com.apple.quarantine from the app's own
    // sandboxed process, and that can't be stripped from inside the sandbox: not
    // via removexattr (silently ignored) and not even via a spawned /usr/bin/xattr
    // subprocess (fails with EPERM — Apple's "responsible process" tracking taints
    // children of a sandboxed parent too). A quarantined script fails to execute
    // non-interactively, since there's no Finder dialog to approve it, so every
    // hook call would silently fail. A script that's just read as a data argument
    // by the system's own /usr/bin/python3 was never independently quarantined —
    // this sidesteps the restriction instead of fighting it.
    private static var scriptPath: String? {
        Bundle.main.path(forResource: "coocoo-notify", ofType: "py")
    }

    // MARK: - Status check

    static func currentStatus() -> Status {
        guard let scriptPath else { return .error("Bundled hook script missing") }
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return .notInstalled
        }
        let needed = ["Notification", "Stop", "PreToolUse", "UserPromptSubmit"]
        let allPresent = needed.allSatisfy { name in
            hookCommand(in: hooks, for: name)?.contains(scriptPath) == true
        }
        return allPresent ? .installed : .notInstalled
    }

    private static func hookCommand(in hooks: [String: Any], for name: String) -> String? {
        guard let groups = hooks[name] as? [[String: Any]] else { return nil }
        for group in groups {
            guard let innerHooks = group["hooks"] as? [[String: Any]] else { continue }
            for h in innerHooks {
                if let command = h["command"] as? String { return command }
            }
        }
        return nil
    }

    // MARK: - Install

    @discardableResult
    static func install() -> Status {
        guard scriptPath != nil else { return .error("Bundled hook script missing") }
        do {
            try patchSettings()
        } catch {
            return .error("Can't update settings.json: \(error.localizedDescription)")
        }
        return .installed
    }

    // MARK: - settings.json patch

    private static func patchSettings() throws {
        guard let scriptPath else { return }
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
        // UserPromptSubmit fires the instant the user submits their reply — before
        // Claude has generated anything. Without it, the icon stays stuck on
        // "waiting" until Claude's first tool call (PreToolUse) or the turn ends
        // (Stop), which can lag several seconds behind the user's own action.
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks["Notification"]     = hookEntry("waiting", scriptPath: scriptPath)
        hooks["Stop"]             = hookEntry("done", scriptPath: scriptPath)
        hooks["PreToolUse"]       = hookEntry("thinking", scriptPath: scriptPath)
        hooks["UserPromptSubmit"] = hookEntry("thinking", scriptPath: scriptPath)
        root["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL)
    }

    // `; exit 0` is load-bearing: Claude Code treats a non-zero exit from a
    // UserPromptSubmit/PreToolUse hook as "block this operation." If the
    // bundled script is ever missing (mid-rebuild, moved app, bad install) or
    // throws, python3 itself exits non-zero — which would otherwise stop the
    // user from submitting prompts at all just because CooCoo, a notifier,
    // isn't healthy. CooCoo must never be able to block Claude Code.
    private static func hookEntry(_ state: String, scriptPath: String) -> [[String: Any]] {
        [["hooks": [["type": "command",
                     "command": "/usr/bin/python3 \"\(scriptPath)\" \(state); exit 0"]]]]
    }
}
