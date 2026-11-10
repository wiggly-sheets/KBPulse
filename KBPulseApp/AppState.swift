//
//  AppState.swift
//  KBPulseApp
//
//  Shared state for the menu bar dropdown and Settings window: theme list,
//  engine on/off, selected theme (persisted), transient hook override, plus
//  login-item registration.
//

import Foundation
import ServiceManagement
import SwiftUI

final class AppState: ObservableObject {
    @Published var themes: [String] = []
    @Published private(set) var engineOn = true
    @Published private(set) var selectedTheme = ""
    /// Transient hook theme layered over the persisted base theme. Never saved.
    @Published private(set) var overrideTheme: String?
    @Published private(set) var cliInstalledPath: URL?
    @Published private(set) var cliOnPATH = false

    let engine = Engine()

    /// Hook theme per owner (`agent`, `system`), newest application wins.
    private var overrides: [String: String] = [:]
    private var overrideOrder: [String] = []

    static let themesDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("KBPulse", isDirectory: true)

    init() {
        KBPPulseManager.loadPrivateFrameworks()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            self.engine.stop()
            KBPPulseManager.restoreBacklightSettings()
        }
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
            KBPPulseManager.modifyBacklightSettings()
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
        pruneOverrides()
    }

    // MARK: - Bindings shared by menu and Settings window

    var effectiveTheme: String { overrideTheme ?? selectedTheme }

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
            KBPPulseManager.modifyBacklightSettings()
            startEngine()
            AgentHookRuntime.shared.start(in: self)
            SystemEventRuntime.shared.start(in: self)
        } else {
            SystemEventRuntime.shared.stop()
            AgentHookRuntime.shared.stop()
            engine.stop()
            KBPPulseManager.restoreBacklightSettings()
        }
    }

    /// User action: picks the persisted base theme and drops any hook override.
    func selectTheme(_ name: String) {
        guard themes.contains(name) else { return }
        guard name != selectedTheme || overrideTheme != nil else { return }
        overrides.removeAll()
        overrideOrder.removeAll()
        overrideTheme = nil
        selectedTheme = name
        UserDefaults.standard.set(name, forKey: "selectedTheme")
        if engineOn { startEngine() }
    }

    /// Applies a transient hook theme. `owner` lets one hook layer clear
    /// only its own override without disturbing another layer's.
    func applyOverrideTheme(_ name: String, owner: String) {
        guard themes.contains(name), overrides[owner] != name else { return }
        overrides[owner] = name
        overrideOrder.removeAll { $0 == owner }
        overrideOrder.append(owner)
        updateOverrideTheme()
    }

    func clearOverride(owner: String) {
        guard overrides.removeValue(forKey: owner) != nil else { return }
        overrideOrder.removeAll { $0 == owner }
        updateOverrideTheme()
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
        let url = Self.themesDir.appendingPathComponent("\(effectiveTheme).json")
        let raw = (try? ThemeStore.rawDictionary(at: url)) ?? [:]
        engine.start(profile: KBPProfile(fileURL: url), reactive: ReactiveMode(forEngine: raw))
    }

    private func updateOverrideTheme() {
        let before = effectiveTheme
        overrideTheme = overrideOrder.last.flatMap { overrides[$0] }
        if engineOn, effectiveTheme != before { startEngine() }
    }

    /// Drops overrides whose theme file disappeared.
    private func pruneOverrides() {
        let stale = overrides.filter { !themes.contains($0.value) }.map(\.key)
        guard !stale.isEmpty else { return }
        for owner in stale {
            overrides.removeValue(forKey: owner)
            overrideOrder.removeAll { $0 == owner }
        }
        updateOverrideTheme()
    }

    /// Restarts the loop with a fresh profile after the theme file was saved.
    func themeEdited(_ name: String) {
        refreshThemes()
        if engineOn, effectiveTheme == name { startEngine() }
    }
}
