import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("cooOnInput") private var soundOnAlert = true
    @AppStorage("soundVolume") private var soundVolume = 0.8
    @AppStorage("doneTimeout") private var doneTimeout = 30.0
    @AppStorage("showFloatingWidget") private var showFloatingWidget = false
    @AppStorage("selectedCharacter") private var selectedCharacter = "pigeon"
    @AppStorage("alertStyle") private var alertStyle = "shake"
    @AppStorage("extendedMode") private var extendedMode = false
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var previewState: CompanionState = .idle

    private var selectedCharacterID: CharacterID {
        CharacterID(rawValue: selectedCharacter) ?? .pigeon
    }

    var body: some View {
        Form {
            // ── Character ──────────────────────────────────────────────────
            Section("Companion") {
                VStack(spacing: 10) {
                    CharacterView(character: selectedCharacterID, state: previewState)
                        .frame(width: 96, height: 96)

                    HStack(spacing: 4) {
                        ForEach(CompanionState.allCases, id: \.self) { s in
                            Text(s.label)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    previewState == s
                                        ? s.backgroundColor
                                        : Color(nsColor: .controlBackgroundColor)
                                )
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(
                                    previewState == s ? Color.primary.opacity(0.25) : Color.primary.opacity(0.08),
                                    lineWidth: 0.5
                                ))
                                .onTapGesture { previewState = s }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(CharacterID.allCases) { char in
                        characterCard(char)
                    }
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8))
            }

            // ── General ────────────────────────────────────────────────────
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else        { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }
            }

            // ── Alerts ─────────────────────────────────────────────────────
            Section("Alerts") {
                Toggle("Sound on alert", isOn: $soundOnAlert)
                if soundOnAlert {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.1").foregroundStyle(.secondary)
                        Slider(value: $soundVolume, in: 0...1)
                        Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
                        Button("Test") {
                            SoundPlayer.shared.play(for: selectedCharacterID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                Picker("Hide done after", selection: $doneTimeout) {
                    Text("15 s").tag(15.0)
                    Text("30 s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("Never").tag(0.0)
                }
                .pickerStyle(.segmented)

                Picker("Alert style", selection: $alertStyle) {
                    Text("Shake").tag("shake")
                    Text("Walk").tag("walk")
                }
                .pickerStyle(.segmented)
            }

            // ── Widget ─────────────────────────────────────────────────────
            Section("Widget") {
                Toggle("Show floating widget", isOn: $showFloatingWidget)
                    .onChange(of: showFloatingWidget) { _, show in
                        NotificationCenter.default.post(name: .coocooToggleWidget, object: show)
                    }
                Toggle("Extended mode", isOn: $extendedMode)
                Text("Shows the project name and more task detail (the actual command or file, a snippet of Claude's last message) in the widget and popover, instead of just a generic status.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onChange(of: selectedCharacter) { _, _ in
            NotificationCenter.default.post(name: .coocooCharacterChanged, object: nil)
        }
    }

    // MARK: - Character card

    @ViewBuilder
    private func characterCard(_ char: CharacterID) -> some View {
        let isSelected = char.rawValue == selectedCharacter
        VStack(spacing: 4) {
            CharacterView(character: char, state: previewState)
                .frame(width: 60, height: 60)
            Text(char.defaultName)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? char.menuBarColors.backgroundColor : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .onTapGesture { selectedCharacter = char.rawValue }
    }
}

private extension CharacterID.MenuBarColors {
    var backgroundColor: Color { Color(hex: body).opacity(0.15) }
}
