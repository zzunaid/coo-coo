import AppKit
import SwiftUI
import UserNotifications

enum CompanionState: String, Codable, CaseIterable {
    case idle, thinking, waiting, sleepy, done

    var emoji: String {
        switch self {
        case .idle:     return "🐦"
        case .thinking: return "🐦💭"
        case .waiting:  return "🚨🐦🚨"
        case .sleepy:   return "🐦💤"
        case .done:     return "🐦✓"
        }
    }

    var label: String {
        switch self {
        case .idle:     return "on watch"
        case .thinking: return "thinking..."
        case .waiting:  return "needs you"
        case .sleepy:   return "sleepy..."
        case .done:     return "done"
        }
    }

    var quote: String {
        switch self {
        case .idle:     return "\"hm.\""
        case .thinking: return "\"peck peck peck...\""
        case .waiting:  return "\"COO COO!! OI!! HOOMAN!!\""
        case .sleepy:   return "\"zzz... wake me when... zzz...\""
        case .done:     return "\"done. bread now?\""
        }
    }

    var backgroundColor: Color {
        switch self {
        case .idle:     return Color(nsColor: .controlBackgroundColor)
        case .thinking: return Color(red: 1.00, green: 0.965, blue: 0.902)
        case .waiting:  return Color(red: 1.00, green: 0.902, blue: 0.902)
        case .sleepy:   return Color(red: 0.941, green: 0.914, blue: 1.00)
        case .done:     return Color(red: 0.918, green: 0.953, blue: 0.867)
        }
    }
}

class CompanionStateStore: ObservableObject {
    @Published var state: CompanionState = .idle
    @Published var message: String = ""
    @Published var cwd: String = ""

    // AppDelegate sets this to remove the session when user dismisses.
    var onDismiss: (() -> Void)?

    var displayCwd: String {
        guard !cwd.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = cwd.hasPrefix(home + "/")
            ? "~/" + String(cwd.dropFirst(home.count + 1))
            : cwd
        return URL(fileURLWithPath: path).lastPathComponent
    }

    func dismiss() {
        onDismiss?()
    }

    func transition(to newState: CompanionState, message: String = "") {
        let doSideEffects = newState == .waiting
        if Thread.isMainThread {
            self.state = newState
            self.message = message
        } else {
            DispatchQueue.main.async {
                self.state = newState
                self.message = message
            }
        }
        CooAnalytics.logStateChange(to: newState)
        if doSideEffects {
            DispatchQueue.main.async {
                self.playAlertSound()
                self.sendNotification(message: message)
                CooAnalytics.logAlertFired(character: CharacterID(rawValue: UserDefaults.standard.string(forKey: "selectedCharacter") ?? "pigeon") ?? .pigeon)
            }
        }
    }

    private func playAlertSound() {
        let characterId = UserDefaults.standard.string(forKey: "selectedCharacter") ?? "pigeon"
        let character = CharacterID(rawValue: characterId) ?? .pigeon
        SoundPlayer.shared.play(for: character)
    }

    private func sendNotification(message: String) {
        let characterId = UserDefaults.standard.string(forKey: "selectedCharacter") ?? "pigeon"
        let character = CharacterID(rawValue: characterId) ?? .pigeon
        let content = UNMutableNotificationContent()
        content.title = "\(character.defaultName) needs you"
        content.body = message.isEmpty ? character.quote(for: .waiting) : message
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
