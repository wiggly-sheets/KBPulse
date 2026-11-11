//
//  KBPulseApp.swift
//  KBPulseApp
//

import SwiftUI

@main
struct KBPulseApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: "keyboard")
                .foregroundStyle(.primary)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        Toggle("Animation engine", isOn: state.engineBinding)
        Picker("Themes", selection: state.themeBinding) {
            ForEach(state.themes, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.inline)
        Toggle("Launch at login", isOn: Binding(
            get: { state.isLoginItemEnabled },
            set: { state.setLoginItem($0) }
        ))
        Divider()
        Button("Settings…") {
            // SettingsLink/@Environment(\.openSettings) need macOS 14; this selector works on 13.
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Button("Quit KBPulse") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
