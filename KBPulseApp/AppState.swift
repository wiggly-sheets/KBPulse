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
import AppKit

final class AppState: ObservableObject {
    enum IconDisplayMode: String, CaseIterable, Identifiable {
        case dockOnly = "dock"
        case menuBarOnly = "menu"
        case both = "both"
        case none = "none"
        
        var id: String { rawValue }
        var description: String {
            switch self {
            case .dockOnly: return "Dock only"
            case .menuBarOnly: return "Menu bar only"
            case .both: return "Both"
            case .none: return "Neither"
            }
        }
        var showsMenuBar: Bool {
            switch self {
            case .menuBarOnly, .both: return true
            case .dockOnly, .none: return false
            }
        }
        var showsDock: Bool {
            switch self {
            case .dockOnly, .both: return true
            case .menuBarOnly, .none: return false
            }
        }
    }
    
    @Published var iconDisplayMode: IconDisplayMode = .menuBarOnly {
        didSet {
            UserDefaults.standard.set(iconDisplayMode.rawValue, forKey: "iconDisplayMode")
            applyActivationPolicy()
        }
    }

    /// Tracks whether the app has Accessibility permission for key-event capture.
    @Published private(set) var isAccessibilityGranted = false

    /// Lists basenames of active coding agents detected in the process table.
    @Published private(set) var activeAgents: [String] = []
    /// False when the process-table scan itself failed, as opposed to simply
    /// finding no agents. The Settings UI distinguishes the two.
    @Published private(set) var agentScanAvailable = true

    /// True when at least one system runtime timer is actively firing hooks.
    @Published private(set) var hasSystemActivity = false
    
    @Published var themes: [String] = []
    @Published private(set) var engineOn = true
    @Published private(set) var selectedTheme = ""
    /// Transient hook theme layered over the persisted base theme. Never saved.
    @Published private(set) var overrideTheme: String?
    @Published private(set) var cliInstalledPath: URL?
    @Published private(set) var cliOnPATH = false
    /// Non-nil when the last login-item change failed.
    @Published private(set) var loginItemError: String?

    let engine = Engine()

    /// Polling timer for agent detection updates.
    private var agentPollTimer: Timer?

    /// Hook theme per owner (`agent`, `system`), newest application wins.
    private var overrides: [String: String] = [:]
    private var overrideOrder: [String] = []

    /// Active temporary theme preview (see `previewTheme`). The temp file is
    /// deleted when the preview ends.
    private var previewWorkItem: DispatchWorkItem?
    private var previewTempURL: URL?
    private var previewPreviousTheme = ""
    private var previewEngineWasOn = false

    static let themesDir: URL = {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSHomeDirectory())
        }
        return dir.appendingPathComponent("KBPulse", isDirectory: true)
    }()

    init() {
        KBPPulseManager.loadPrivateFrameworks()
        // If a previous run crashed or was force-quit before restoring the
        // user's keyboard settings, put them back before taking control again.
        KBPPulseManager.restoreOrphanedSettings()
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            // Activation policy cannot be set reliably before the app launches.
            self?.applyActivationPolicy()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.stopPreview()
            self?.engine.stop()
            KBPPulseManager.restoreBacklightSettings()
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.ethanrdoesmc.kbpulse.command"),
            object: nil, queue: nil
        ) { [weak self] note in
            guard let self, let command = note.userInfo?["command"] as? String else { return }
            DispatchQueue.main.async {
                self.handleCLICommand(command, profile: note.userInfo?["profile"] as? String)
            }
        }
        try? FileManager.default.createDirectory(at: Self.themesDir, withIntermediateDirectories: true)
        HookStore.ensureFile()
        if !FileManager.default.fileExists(atPath: Self.themesDir.appendingPathComponent("Yawn.json").path) {
            KBPProfile.createYawnJSON()
        }
        ThemeStore.createReactiveExampleIfMissing()
        let defaults = UserDefaults.standard
        engineOn = defaults.object(forKey: "engineEnabled") as? Bool ?? true
        iconDisplayMode = IconDisplayMode(rawValue: defaults.string(forKey: "iconDisplayMode") ?? "menu") ?? .menuBarOnly
        refreshThemes()
        refreshCLIStatus()
        updateAccessibilityStatus()
        updateAgentDetection()
        startAccessibilityPolling()
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

    /// Updates the accessibility-granted state exposed to the UI.
    func updateAccessibilityStatus() {
        let granted = ReactiveEngine.isAccessibilityGranted(prompt: false)
        if granted != isAccessibilityGranted { isAccessibilityGranted = granted }
    }

    /// Scans the process table and publishes active agent basenames.
    func updateAgentDetection() {
        if let agents = AgentMonitor.activeAgents {
            if activeAgents != agents { activeAgents = agents }
            if !agentScanAvailable { agentScanAvailable = true }
        } else {
            // nil means scan failed; show empty so the UI displays "unavailable".
            if !activeAgents.isEmpty { activeAgents = [] }
            if agentScanAvailable { agentScanAvailable = false }
        }
    }

    func installCLI() {
        if CLISymlinkManager.install() {
            cliInstalledPath = CLISymlinkManager.installedPath
            cliOnPATH = CLISymlinkManager.isOnPATH
        }
    }

    /// Starts periodic polling for accessibility status and agent detection.
    private func startAccessibilityPolling() {
        agentPollTimer?.invalidate()
        agentPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateAccessibilityStatus()
            self?.updateAgentDetection()
        }
    }

    func refreshThemes() {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: Self.themesDir.path)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != "hooks.json" }
            .map { String($0.dropLast(5)) }
            .sorted()
        themes = names
        let saved = UserDefaults.standard.string(forKey: "selectedTheme")
        selectedTheme = names.contains(saved ?? "\u{0}") ? (saved ?? "") : (names.first ?? "")
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
        stopPreview()
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
        stopPreview()
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

    // MARK: - CLI relay

    /// Handles a command posted by the `kbpulse` CLI over a distributed
    /// notification. Unknown or missing profile names are ignored.
    private func handleCLICommand(_ command: String, profile: String?) {
        switch command {
        case "set":
            guard let profile, themes.contains(profile) else { return }
            if !engineOn { setEngine(true) }
            selectTheme(profile)
        case "off":
            setEngine(false)
        case "flash":
            guard engineOn else { return }
            engine.flash()
        default:
            break
        }
    }

    // MARK: - Launch at login

    var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLoginItem(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Could not \(on ? "enable" : "disable") launch at login: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    // MARK: - Private

    /// Applies dock visibility for the current mode. Call on the main thread.
    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = iconDisplayMode.showsDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    private func startEngine(for requestedTheme: String? = nil) {
        // Any real engine switch supersedes a temporary preview.
        discardPreviewBookkeeping()
        let theme = requestedTheme ?? effectiveTheme
        guard !theme.isEmpty else { return }
        let url = Self.themesDir.appendingPathComponent("\(theme).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let raw = (try? ThemeStore.rawDictionary(at: url)) ?? [:]
        engine.start(profile: KBPProfile(fileURL: url), reactive: ReactiveMode(forEngine: raw))
    }

    // MARK: - Temporary theme preview

    /// Plays a theme file for `duration` seconds without changing the persisted
    /// selection, then restores whatever was playing before. The file is
    /// deleted when the preview ends.
    func previewTheme(fileURL: URL, reactive: ReactiveMode?, duration: TimeInterval = 10) {
        stopPreview()
        previewTempURL = fileURL
        previewPreviousTheme = effectiveTheme
        previewEngineWasOn = engineOn
        engine.stop()
        engine.start(profile: KBPProfile(fileURL: fileURL), reactive: reactive)
        let item = DispatchWorkItem { [weak self] in
            self?.finishPreview(restore: true)
        }
        previewWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    /// Ends a preview and returns to the previous state.
    func cancelPreview() {
        finishPreview(restore: true)
    }

    /// Ends a preview without restoring (used when another action already
    /// takes ownership of the engine).
    func stopPreview() {
        finishPreview(restore: false)
    }

    private func finishPreview(restore: Bool) {
        guard let temp = previewTempURL else { return }
        let shouldRestore = restore && previewEngineWasOn && !previewPreviousTheme.isEmpty
        let previousTheme = previewPreviousTheme
        previewTempURL = nil
        previewWorkItem?.cancel()
        previewWorkItem = nil
        previewPreviousTheme = ""
        previewEngineWasOn = false
        try? FileManager.default.removeItem(at: temp)
        if shouldRestore {
            startEngine(for: previousTheme)
        } else {
            engine.stop()
        }
    }

    /// Forgets a preview without stopping the engine. Used when a new engine
    /// start has already replaced the previewed theme.
    private func discardPreviewBookkeeping() {
        previewWorkItem?.cancel()
        previewWorkItem = nil
        if let temp = previewTempURL {
            try? FileManager.default.removeItem(at: temp)
        }
        previewTempURL = nil
        previewPreviousTheme = ""
        previewEngineWasOn = false
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
        stopPreview()
        refreshThemes()
        if engineOn, effectiveTheme == name { startEngine() }
    }

    /// Re-reads the theme directory after files were added or removed and
    /// restarts the loop so a deleted theme cannot keep playing from memory.
    func themeFilesChanged() {
        stopPreview()
        refreshThemes()
        if engineOn { startEngine() }
    }
}
