import SwiftUI
import AppKit

class FloatingStore: ObservableObject {
    @Published var state: CompanionState = .idle
    @Published var message: String = ""
    // Sessions other than the one currently shown — the widget is a single
    // card and can only display one session at a time.
    @Published var otherCount: Int = 0
}

extension Notification.Name {
    static let coocooWidgetResized = Notification.Name("coocoo.widgetResized")
    static let coocooOpenTerminal = Notification.Name("coocoo.openTerminal")
}

struct FloatingWidgetView: View {
    @ObservedObject var store: FloatingStore
    @AppStorage("selectedCharacter") private var selectedCharacter = "pigeon"
    @AppStorage("widgetMinimized") private var isMinimized = false

    private var character: CharacterID {
        CharacterID(rawValue: selectedCharacter) ?? .pigeon
    }

    var body: some View {
        Group {
            if isMinimized {
                miniBody
            } else {
                expandedBody
            }
        }
        .onChange(of: isMinimized) { _, _ in
            NotificationCenter.default.post(name: .coocooWidgetResized, object: nil)
        }
        .animation(.spring(duration: 0.3), value: isMinimized)
    }

    // MARK: - Mini (small circle, tap to expand)

    private var miniBody: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let pulse = store.state == .waiting
                ? (1 - cos(2 * .pi * t / 1.2)) / 2 : 0.0

            CharacterView(character: character, state: store.state)
                .frame(width: 44, height: 44)
                .background(Circle().fill(store.state.backgroundColor))
                .clipShape(Circle())
                .shadow(
                    color: store.state == .waiting
                        ? .orange.opacity(0.2 + 0.2 * pulse) : .black.opacity(0.2),
                    radius: store.state == .waiting ? 6 + 5 * pulse : 6,
                    y: 3
                )
                .overlay(alignment: .topTrailing) {
                    if store.otherCount > 0 {
                        otherSessionsBadge(size: 14, fontSize: 8)
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .padding(14)
        .onTapGesture { isMinimized = false }
    }

    // Small "+N" pill for other sessions the single-card widget can't show
    // at the same time as the one currently displayed.
    private func otherSessionsBadge(size: CGFloat, fontSize: CGFloat) -> some View {
        Text("+\(store.otherCount)")
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, size > 14 ? 6 : 2)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .help("\(store.otherCount) other session\(store.otherCount == 1 ? "" : "s") active")
    }

    // MARK: - Expanded

    private var expandedBody: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let pulse = store.state == .waiting
                ? (1 - cos(2 * .pi * t / 1.2)) / 2 : 0.0

            card(pulse: pulse)
        }
    }

    private func card(pulse: Double) -> some View {
        VStack(spacing: 0) {
            // Minimize row
            HStack {
                if store.otherCount > 0 {
                    otherSessionsBadge(size: 16, fontSize: 9)
                        .padding(.leading, 10)
                }
                Spacer()
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .onTapGesture { isMinimized = true }
            }

            // Character — tap to jump to this session's terminal
            VStack(spacing: 0) {
                CharacterView(character: character, state: store.state)
                    .frame(width: 80, height: 80)

                Spacer().frame(height: 6)

                // Labels
                Text(character.defaultName)
                    .font(.system(size: 10, weight: .semibold))

                Text(store.state.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                if !store.message.isEmpty {
                    Text(store.message)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .coocooOpenTerminal, object: nil)
            }

            Spacer().frame(height: 14)
        }
        .frame(width: 120)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(store.state.backgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(
            color: store.state == .waiting
                ? .orange.opacity(0.18 + 0.22 * pulse) : .black.opacity(0.18),
            radius: store.state == .waiting ? 10 + 6 * pulse : 10,
            y: 4
        )
        .padding(22)
        .animation(.easeInOut(duration: 0.3), value: store.state)
    }
}
