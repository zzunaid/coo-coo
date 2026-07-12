import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var store: CompanionStateStore
    @AppStorage("selectedCharacter") private var selectedCharacter = "pigeon"

    private var character: CharacterID {
        CharacterID(rawValue: selectedCharacter) ?? .pigeon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 10) {
                CharacterView(character: character, state: store.state)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.defaultName)
                        .font(.system(size: 11, weight: .bold))
                    Text(store.state.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if !store.displayCwd.isEmpty {
                        Text(store.displayCwd)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if store.state != .idle {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .help("Dismiss this session")
                        .onTapGesture { store.dismiss() }
                }
            }
            .padding(.bottom, 10)

            Divider()

            // Message
            Text(store.message.isEmpty ? character.quote(for: store.state) : store.message)
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(Color(hex: "444444"))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)

            Divider()

            // Footer
            HStack {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .help("Preferences")
                    .onTapGesture {
                        NotificationCenter.default.post(name: .coocooShowPreferences, object: nil)
                    }
                Spacer()
                Text("Quit")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .onTapGesture { NSApp.terminate(nil) }
            }
            .padding(.top, 8)
        }
        .padding(14)
        .frame(width: 240)
        .background(store.state.backgroundColor)
        .animation(.easeInOut(duration: 0.25), value: store.state)
    }
}
