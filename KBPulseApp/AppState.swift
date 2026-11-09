//
//  AppState.swift
//  KBPulseApp
//
//  Shared state for the menu bar dropdown and Settings window: theme list,
//  engine on/off, selected theme (persisted), plus login-item registration.
//

import Foundation
import ServiceManagement
import SwiftUI

final class AppState: ObservableObject {
    @Published var themes: [String] = []
    @Published private(set) var engineOn = true
    @Published private(set) var selectedTheme = ""
    @Published private(set) var cliInstalledPath: URL?
    @Published private(set) var cliOnPATH = false

    let engine = Engine()

    static let themesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KBPulse", isDirectory: true)

    init() {
        KBPPulseManager.configure()
        try? FileManager.default.createDirectory(at: Self.themesDir, withIntermediateDirectories: true)
        HookStore.ensureFile()
        if !FileManager.default.fileExists(atPath: Self.themesDir.appendingPathComponent("Yawn.json").path) {
            KBPProfile.createYawnJSON()
        }
        ThemeStore.createReactiveExampleIfMissing()
        let defaults = UserDefaults.standard
        engineOn = defaults.object(forKey: "engineEnabled") as? Bool ?? true
        refreshThemes()
        refreshCLIStatus()
        if engineOn {
            startEngine()
            AgentHookRuntime.shared.start(in: self)
            SystemEventRuntime.shared.start(in: self)
        }
    }

    func refreshCLIStatus() {
        cliInstalledPath = CLISymlinkManager.installedPath
        cliOnPATH = CLISymlinkManager.isOnPATH
    }

    func installCLI() {
        if CLISymlinkManager.install() {
            cliInstalledPath = CLISymlinkManager.installedPath
            cliOnPATH = CLISymlinkManager.isOnPATH
        }
    }

    func refreshThemes() {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: Self.themesDir.path)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != "hooks.json" }
            .map { String($0.dropLast(5)) }
            .sorted()
        themes = names
        let saved = UserDefaults.standard.string(forKey: "selectedTheme")
        selectedTheme = names.contains(saved ?? " ") ? saved! : (names.first ?? saved ?? "")
        if selectedTheme != saved {
            UserDefaults.standard.set(selectedTheme, forKey: "selectedTheme")
        }
    }

    // MARK: - Bindings shared by menu and Settings window

    var engineBinding: Binding<Bool> {
        Binding(get: { self.engineOn }, set: { self.setEngine($0) })
    }

    var themeBinding: Binding<String> {
        Binding(get: { self.selectedTheme }, set: { self.selectTheme($0) })
    }

    func setEngine(_ on: Bool) {
        guard on != engineOn else { return }
        engineOn = on
        UserDefaults.standard.set(on, forKey: "engineEnabled")
        if on {
            startEngine()
            AgentHookRuntime.shared.start(in: self)
            SystemEventRuntime.shared.start(in: self)
        } else {
            SystemEventRuntime.shared.stop()
            AgentHookRuntime.shared.stop()
            engine.stop()
        }
    }

    func selectTheme(_ name: String) {
        guard name != selectedTheme, themes.contains(name) else { return }
        selectedTheme = name
        UserDefaults.standard.set(name, forKey: "selectedTheme")
        if engineOn { startEngine() }
    }

    // MARK: - Launch at login

    var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLoginItem(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        objectWillChange.send()
    }

    // MARK: - Private

    private func startEngine() {
        let url = Self.themesDir.appendingPathComponent("\(selectedTheme).json")
        let raw = (try? ThemeStore.rawDictionary(at: url)) ?? [:]
        engine.start(profile: KBPProfile(fileURL: url), reactive: ReactiveMode(forEngine: raw))
    }

    /// Restarts the loop with a fresh profile after the theme file was saved.
    func themeEdited(_ name: String) {
        refreshThemes()
        if engineOn, selectedTheme == name { startEngine() }
    }
}
