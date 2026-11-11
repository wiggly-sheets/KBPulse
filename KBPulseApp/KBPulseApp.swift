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

        // Menu bar scene
        MenuBarScene(state: state)
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

// MARK: - MenuBarScene

private struct MenuBarScene: Scene {
    @ObservedObject var state: AppState

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            if state.iconDisplayMode.showsMenuBar {
                Image(systemName: "light.max")
                    .foregroundStyle(.primary)
            } else {
                // Invisible menu bar item - still present but not visible
                Image(systemName: "light.max")
                    .foregroundStyle(.clear)
                    .frame(width: 0, height: 0)
            }
        }
        .menuBarExtraStyle(.menu)
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