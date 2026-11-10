//
//  SystemEventRuntime.swift
//  KBPulseApp
//
//  Reacts to system events that have public macOS APIs:
//    app launched / app terminated — NSWorkspace notifications
//    sleep / wake               — NSWorkspace notifications
//    file appears in Downloads  — poll the Downloads folder
//
//  Notifications from other apps are NOT observable without a system
//  extension (which needs notarization + entitlements), so that category
//  is intentionally absent. Download *progress* is also not exposed by
//  macOS — we flash when the file lands, which is the moment the user
//  actually cares about.
//
//  All three run on the main thread and only touch AppState/engine bindings;
//  the brightness API is never called directly here.
//

import Cocoa
import Foundation

final class SystemEventRuntime {
    static let shared = SystemEventRuntime()

    private let workspace = NSWorkspace.shared
    private var timer: Timer?
    private var overrideTimer: Timer?
    private var lastDownloads: Set<String> = []
    private var wasAsleep = false
    private weak var state: AppState?

    func start(in state: AppState) {
        self.state = state
        wasAsleep = false
        timer?.invalidate()
        timer = nil
        overrideTimer?.invalidate()
        overrideTimer = nil
        removeObservers()
        // Seed the Downloads file set so we don't flash on files that were
        // already there before KBPulse launched.
        lastDownloads = currentDownloads()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollDownloads()
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(sleepNotification(_:)),
            name: NSWorkspace.willSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(wakeNotification(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        workspace.notificationCenter.addObserver(
            self, selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        overrideTimer?.invalidate()
        overrideTimer = nil
        removeObservers()
        lastDownloads = []
        state?.clearOverride(owner: "system")
    }

    private func removeObservers() {
        DistributedNotificationCenter.default().removeObserver(self)
        workspace.notificationCenter.removeObserver(self)
    }

    // MARK: - Notifications

    @objc private func appLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        fire(hookType: "appLaunched", trigger: app.bundleIdentifier ?? app.localizedName ?? "")
    }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        fire(hookType: "appTerminated", trigger: app.bundleIdentifier ?? app.localizedName ?? "")
    }

    @objc private func sleepNotification(_ notification: Notification) {
        wasAsleep = true
    }

    @objc private func wakeNotification(_ notification: Notification) {
        guard wasAsleep else { return }
        wasAsleep = false
        fire(hookType: "wake", trigger: "")
    }

    // MARK: - Downloads polling

    private func pollDownloads() {
        let now = currentDownloads()
        // A file that exists now but wasn't there two seconds ago is new.
        for name in now where !lastDownloads.contains(name) {
            fire(hookType: "fileDownload", trigger: name)
        }
        lastDownloads = now
    }

    private func currentDownloads() -> Set<String> {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloads else { return [] }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
        return Set(names)
    }

    // MARK: - Firing

    private func fire(hookType: String, trigger: String) {
        guard let state else { return }
        guard let hook = HookStore.hooks(ofType: hookType)
            .first(where: { $0.enabled && matches($0.trigger, trigger) }) else { return }
        switch hook.action {
        case "flash":
            state.engine.flash()
        case "breathing":
            applySystemOverride(theme: hook.theme, in: state)
        default:
            break
        }
    }

    /// Shows the hook theme for 30 s, then drops only the system layer. A newer
    /// system override replaces the previous timer.
    private func applySystemOverride(theme: String, in state: AppState) {
        guard !theme.isEmpty, state.themes.contains(theme) else { return }
        state.applyOverrideTheme(theme, owner: "system")
        overrideTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: false) { [weak self, weak state] _ in
            state?.clearOverride(owner: "system")
            self?.overrideTimer = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        overrideTimer = timer
    }

    /// Substring match on the trigger, case-insensitive. Empty trigger
    /// matches anything (used by sleep/wake, which fire for everyone).
    private func matches(_ pattern: String, _ value: String) -> Bool {
        guard !pattern.isEmpty else { return true }
        return value.localizedCaseInsensitiveContains(pattern)
    }
}