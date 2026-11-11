//
//  KBPulseApp.swift
//  KBPulseApp
//
//

import SwiftUI
import AppKit

@main
struct KBPulseApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        if state.iconDisplayMode.showsMenuBar {
            MenuBarExtra {
                MenuContent(state: state)
            } label: {
                Image(systemName: "light.max")
                    .foregroundStyle(.primary)
            }
            .menuBarExtraStyle(.menu)
        } else {
            Empty()
        }

        Settings {
            SettingsView(state: state)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        updateActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillResignActive(_ notification: Notification) {
        updateActivationPolicy()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updateActivationPolicy()
        DispatchQueue.main.async {
            self.showSettingsWindow()
        }
    }

    private func showSettingsWindow() {
        NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
    }

    private func updateActivationPolicy() {
        let mode = UserDefaults.standard.string(forKey: "iconDisplayMode") ?? "menu"
        if AppState.IconDisplayMode(rawValue: mode)?.showsDock == true {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
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
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Button("Quit KBPulse") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}