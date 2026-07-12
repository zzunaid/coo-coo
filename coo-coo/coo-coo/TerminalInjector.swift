import AppKit

// Tries to send text + Return directly to the user's active terminal session.
// Returns true if injection succeeded, false if the caller should fall back to clipboard.
enum TerminalInjector {

    // Escape a string safe to embed inside an AppleScript double-quoted string.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    static func send(_ text: String) -> Bool {
        let safe = esc(text)

        // 1. iTerm2 — write text goes directly to the pty, no accessibility needed.
        if isRunning("iTerm2") {
            let script = """
            tell application "iTerm2"
                activate
                tell current session of current window
                    write text "\(safe)"
                end tell
            end tell
            """
            if appleScript(script) { return true }
        }

        // 2. Terminal.app — activate then use System Events to keystroke.
        //    macOS will prompt for Accessibility permission on first use.
        if isRunning("Terminal") {
            let script = """
            tell application "Terminal" to activate
            delay 0.15
            tell application "System Events"
                tell process "Terminal"
                    keystroke "\(safe)"
                    key code 36
                end tell
            end tell
            """
            if appleScript(script) { return true }
        }

        // 3. Warp
        if isRunning("Warp") {
            let script = """
            tell application "Warp" to activate
            delay 0.15
            tell application "System Events"
                tell process "Warp"
                    keystroke "\(safe)"
                    key code 36
                end tell
            end tell
            """
            if appleScript(script) { return true }
        }

        // 4. Ghostty
        if isRunning("Ghostty") {
            let script = """
            tell application "Ghostty" to activate
            delay 0.15
            tell application "System Events"
                tell process "Ghostty"
                    keystroke "\(safe)"
                    key code 36
                end tell
            end tell
            """
            if appleScript(script) { return true }
        }

        return false
    }

    private static func isRunning(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == name }
    }

    @discardableResult
    private static func appleScript(_ source: String) -> Bool {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return result != nil && err == nil
    }
}
