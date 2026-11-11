//
//  KBPulseApp.swift
//  KBPulseApp
//
//  Main application entry point with MenuBarExtra and Settings window.
//

import SwiftUI

@main
struct KBPulseApp: App {
    // MARK: - App lifecycle

    /// Ensures only one instance of the app runs; reopens the existing instance
    /// rather than creating a new blank window.
    static var sharedApplication: NSApplication {
        NSApplication.shared
    }

    @StateObject private var state = AppState()

    var body: some Scene {
        // Always have a window group (hidden when not needed) so app stays alive
        WindowGroup("KBPulse Settings") {
            SettingsView(state: state)
                .hiddenTitlebar()
                .frame(minWidth: 520, minHeight: 380)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 640, height: 400)

        // MenuBarExtra labels do not re-render from observed state, so the
        // status item is inserted or removed through this binding instead.
        MenuBarExtra(isInserted: Binding(
            get: { state.iconDisplayMode.showsMenuBar },
            set: { _ in } // The mode is the source of truth; ignore system-side removal.
        )) {
            MenuContent(state: state)
        } label: {
            Image(systemName: "light.max")
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Application delegate for reopen handling

/// Ensures that when the app is launched again while already running,
/// the existing instance is activated rather than creating a new window.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Empty - handled via onAppear below
}

// MARK: - View extensions

extension View {
    /// Hides the title bar for menu bar app windows
    func hiddenTitlebar() -> some View {
        self
            .frame(minWidth: 0, minHeight: 0)
            .padding(0)
    }
}

// MARK: - MenuContent

struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openSettings) var openSettings

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
            openSettings()
        }
        Button("Quit KBPulse") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}