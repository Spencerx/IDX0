import AppKit
import SwiftUI

struct KeyboardSettingsTab: View {
    @ObservedObject var sessionService: SessionService

    var body: some View {
        ScrollView {
            KeyboardSettingsContent(sessionService: sessionService)
                .padding(14)
        }
    }
}

struct InlineKeyboardSettings: View {
    @ObservedObject var sessionService: SessionService

    var body: some View {
        KeyboardSettingsContent(sessionService: sessionService)
    }
}

private struct KeyboardSettingsContent: View {
    @ObservedObject var sessionService: SessionService
    @Environment(\.themeColors) private var tc

    @State private var validationMessage: String?

    private let registry = ShortcutRegistry.shared
    private let validator = ShortcutValidator()

    private var remappableDescriptors: [ShortcutDescriptor] {
        registry.descriptors.filter { $0.remappable }
    }

    private var activeConflicts: [ShortcutConflict] {
        validator.conflicts(for: sessionService.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingSectionHeader(title: "Profile")

            SettingRowView(label: "Keybinding Mode", caption: "Select a keybinding profile. Choose Custom to define your own bindings.") {
                ThemedPicker(
                    options: KeybindingMode.allCases.map { ($0.displayName, $0) },
                    selection: Binding(
                        get: { sessionService.settings.keybindingMode },
                        set: { mode in
                            applySettingsMutation { settings in
                                settings.keybindingMode = mode
                            }
                        }
                    )
                )
            }

            SettingRowView(label: "Modifier Key", caption: "The primary modifier key used for shortcuts.") {
                ThemedPicker(
                    options: ModKeySetting.allCases.map { ($0.displayName, $0) },
                    selection: Binding(
                        get: { sessionService.settings.modKeySetting },
                        set: { value in
                            applySettingsMutation { settings in
                                settings.modKeySetting = value
                            }
                        }
                    )
                )
            }

            SettingDivider()
            SettingSectionHeader(title: "Custom Bindings")

            HStack(spacing: 8) {
                Button {
                    applySettingsMutation { settings in
                        let sourceMode: KeybindingMode = settings.keybindingMode == .custom ? .both : settings.keybindingMode
                        settings.customKeybindings = registry.resetBindingsForMode(sourceMode, modSetting: settings.modKeySetting)
                        settings.keybindingMode = .custom
                    }
                } label: {
                    Text("Reset To Profile Defaults")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tc.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(tc.surface0, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(tc.surface2.opacity(0.5), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    applySettingsMutation { settings in
                        settings.customKeybindings = [:]
                    }
                } label: {
                    Text("Clear All")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tc.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(tc.surface0, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(tc.surface2.opacity(0.5), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(remappableDescriptors, id: \.id) { descriptor in
                    bindingRow(descriptor: descriptor)
                }
            }
            .padding(.top, 8)

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(.top, 8)
            }

            if !activeConflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeConflicts, id: \.id) { conflict in
                        Text(conflict.message)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.red.opacity(0.8))
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func bindingRow(descriptor: ShortcutDescriptor) -> some View {
        let activeLabel = registry.displayLabel(for: descriptor.id, settings: sessionService.settings) ?? "Unassigned"
        let customBinding = sessionService.settings.customKeybindings[descriptor.id.rawValue]

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tc.primaryText)
                    Text(descriptor.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(tc.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                ShortcutCaptureButton(
                    title: customBinding?.displayString ?? "Set Binding",
                    hasCustomBinding: customBinding != nil,
                    onCapture: { captured in
                        applySettingsMutation { settings in
                            if let captured {
                                settings.customKeybindings[descriptor.id.rawValue] = captured
                            } else {
                                settings.customKeybindings.removeValue(forKey: descriptor.id.rawValue)
                            }
                        }
                    }
                )
            }

            Text("Active: \(activeLabel)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(tc.tertiaryText)
        }
        .padding(.vertical, 8)

        Rectangle()
            .fill(tc.surface0)
            .frame(height: 1)
    }

    private func applySettingsMutation(_ mutate: (inout AppSettings) -> Void) {
        var candidate = sessionService.settings
        mutate(&candidate)

        let conflicts = validator.conflicts(for: candidate)
        guard conflicts.isEmpty else {
            validationMessage = conflicts[0].message
            return
        }

        validationMessage = nil
        sessionService.saveSettings { settings in
            mutate(&settings)
        }
    }
}

private struct ShortcutCaptureButton: View {
    let title: String
    let hasCustomBinding: Bool
    let onCapture: (KeyChord?) -> Void
    @Environment(\.themeColors) private var tc

    @State private var isCapturing = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if isCapturing {
                    stopCapture()
                } else {
                    beginCapture()
                }
            } label: {
                Text(isCapturing ? "Press Shortcut..." : title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isCapturing ? tc.accent : tc.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(tc.surface0, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isCapturing ? tc.accent.opacity(0.5) : tc.surface2.opacity(0.5), lineWidth: isCapturing ? 1 : 0.5)
                    )
            }
            .buttonStyle(.plain)

            if hasCustomBinding {
                Button {
                    onCapture(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(tc.tertiaryText)
                        .frame(width: 22, height: 22)
                        .background(tc.surface0, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear {
            stopCapture()
        }
    }

    private func beginCapture() {
        stopCapture()
        isCapturing = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopCapture()
                return nil
            }

            guard let chord = KeyChord.from(event: event) else {
                return nil
            }

            stopCapture()
            onCapture(chord)
            return nil
        }
    }

    private func stopCapture() {
        isCapturing = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
