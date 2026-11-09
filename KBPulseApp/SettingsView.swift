//
//  SettingsView.swift
//  KBPulseApp
//
//  Settings window: General tab (engine, hooks stub) + Themes tab (editor).
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            ThemesTab(state: state)
                .tabItem { Label("Themes", systemImage: "paintpalette") }
        }
        .frame(width: 460)
    }

    private var general: some View {
        Form {
            Toggle("Animation engine", isOn: state.engineBinding)
            Picker("Theme", selection: state.themeBinding) {
                ForEach(state.themes, id: \.self) { Text($0).tag($0) }
            }
            CLISection(state: state)
            Section("Hooks") {
                if HookStore.load().isEmpty {
                    Text("No hooks configured. The default agent hooks are created automatically when hooks.json is first written.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(HookStore.load(), id: \.self) { hook in
                    HStack {
                        Text(hook.hookType)
                        Spacer()
                        Text(hook.trigger.isEmpty ? "any" : hook.trigger)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(hook.action)
                            .foregroundColor(.secondary)
                    }
                }
                Text("Hooks watch for coding agents (codex, claude, opencode, herdr, pi), Mac wake from sleep, and new files in Downloads. Triggers and actions can be customized in ~/Documents/KBPulse/hooks.json.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshThemes() }
    }
}

private struct CLISection: View {
    @ObservedObject var state: AppState

    var body: some View {
        Section("Command line") {
            LabeledContent("Bundled", value: CLISymlinkManager.bundledCLIPath.path)
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Installed", value: installedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.cliOnPATH {
                Text("`kbpulse` is on PATH.")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else {
                Text("`kbpulse` is not on PATH.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if state.cliInstalledPath == nil {
                Button("Install kbpulse to ~/.local/bin") {
                    state.installCLI()
                }
            } else {
                Button("Reinstall") {
                    state.installCLI()
                }
            }
            Text("The CLI runs the same engine as the app. Use it for scripts, launchers, keyboard shortcuts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var installedLabel: String {
        guard let path = state.cliInstalledPath else { return "not installed" }
        return path.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
