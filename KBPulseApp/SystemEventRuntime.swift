//
//  SystemEventRuntime.swift
//  KBPulseApp
//
//  Reacts to system events that have public macOS APIs:
//    app launched / app terminated — NSWorkspace notifications
//    sleep / wake               — NSWorkspace notifications
//    file appears in Downloads  — poll the Downloads folder
//    app frontmost change       — NSWorkspace.didActivateApplicationNotification (debounced)
//    screen lock / unlock       — poll CGSessionCopyCurrentDictionary for CGSSessionScreenIsLocked
//    idle threshold             — poll CGEventSource.secondsSinceLastEventType every 10 s
//    music volume               — poll SystemVolumeClient every 5 s
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
import CoreGraphics
import Darwin
import Foundation

struct HookDiagnostics {
    var lastFired: Date?
    var skipped: Int
}

/// Reads the system-wide Now Playing session. The public MediaPlayer API only
/// exposes the calling app's own session, so KBPulse loads MediaRemote the
/// same way it loads CoreBrightness. If the framework or its symbols are not
/// available, playback hooks simply stay dormant.
private enum MediaRemoteClient {
    private typealias GetInfo = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (CFDictionary?) -> Void
    ) -> Void

    private typealias GetIsPlaying = @convention(c) (
        DispatchQueue,
        @escaping @convention(block) (Bool) -> Void
    ) -> Void

    private enum Key {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
    }

    private static let frameworkHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY)

    private static let getInfo: GetInfo? = {
        guard let frameworkHandle,
              let symbol = dlsym(frameworkHandle, "MRMediaRemoteGetNowPlayingInfo") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetInfo.self)
    }()

    private static let getIsPlaying: GetIsPlaying? = {
        guard let frameworkHandle,
              let symbol = dlsym(frameworkHandle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetIsPlaying.self)
    }()

    static var isAvailable: Bool { getInfo != nil }

    /// Fetches the now-playing dictionary and playback state, then calls
    /// `completion` on the main queue.
    static func fetch(completion: @escaping ([String: Any]?, Bool) -> Void) {
        guard let getInfo else {
            completion(nil, false)
            return
        }
        let callbackQueue = DispatchQueue(label: "com.kbpulse.mediaremote.callback")
        let group = DispatchGroup()
        var info: [String: Any]?
        var isPlaying = false

        group.enter()
        getInfo(callbackQueue) { dictionary in
            info = dictionary as? [String: Any]
            group.leave()
        }

        if let getIsPlaying {
            group.enter()
            getIsPlaying(callbackQueue) { playing in
                isPlaying = playing
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(info, isPlaying)
        }
    }

    static func title(from info: [String: Any]?) -> String {
        info?[Key.title] as? String ?? ""
    }

    static func artist(from info: [String: Any]?) -> String {
        info?[Key.artist] as? String ?? ""
    }

    static func album(from info: [String: Any]?) -> String {
        info?[Key.album] as? String ?? ""
    }
}

final class SystemEventRuntime {
    static let shared = SystemEventRuntime()

    private static let partialDownloadSuffixes = [".crdownload", ".download", ".part", ".tmp", ".filepart", ".opdownload"]

    private let workspace = NSWorkspace.shared
    private var timer: Timer?
    private var overrideTimer: Timer?
    private var lastDownloads: Set<String> = []
    private var lastFired: [Hook: Date] = [:]
    private var wasAsleep = false
    private weak var state: AppState?
    private var diagnostics: [Hook: HookDiagnostics] = [:]
    // New event trackers
    private var frontmostDebounceTimer: Timer?
    private var lastFrontmostApp: String?
    private var screenLockTimer: Timer?
    private var lastScreenLocked = false
    private var idleTimer: Timer?
    private var lastIdleFireByTrigger: [String: Date] = [:]
    private var musicVolumeTimer: Timer?
    private var lastVolumeLevel: Float = 0.0
    // Music playback monitoring
    private var musicPlaybackTimer: Timer?
    private var lastPlaybackIsPlaying = false
    private var lastTrackTitle = ""
    private var lastTrackArtist = ""
    private var lastTrackAlbum = ""
    private var playbackSeeded = false
    private var playbackFetchInFlight = false

    func start(in state: AppState) {
        self.state = state
        wasAsleep = false
        lastFired = [:]
        diagnostics = [:]
        lastFrontmostApp = workspace.frontmostApplication?.bundleIdentifier
        lastScreenLocked = currentScreenIsLocked()
        lastIdleFireByTrigger = [:]
        lastPlaybackIsPlaying = false
        lastTrackTitle = ""
        lastTrackArtist = ""
        lastTrackAlbum = ""
        playbackSeeded = false
        playbackFetchInFlight = false
        timer?.invalidate()
        timer = nil
        overrideTimer?.invalidate()
        overrideTimer = nil
        frontmostDebounceTimer?.invalidate()
        frontmostDebounceTimer = nil
        screenLockTimer?.invalidate()
        screenLockTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil
        musicVolumeTimer?.invalidate()
        musicVolumeTimer = nil
        removeObservers()
        // Seed the Downloads file set so we don't flash on files that were
        // already there before KBPulse launched.
        lastDownloads = currentDownloads()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollDownloads()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        // Sleep/wake are NSWorkspace notifications, not distributed ones.
        // Registering them on DistributedNotificationCenter meant they never
        // fired.
        workspace.notificationCenter.addObserver(
            self, selector: #selector(sleepNotification(_:)),
            name: NSWorkspace.willSleepNotification, object: nil)
        workspace.notificationCenter.addObserver(
            self, selector: #selector(wakeNotification(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)
        workspace.notificationCenter.addObserver(
            self, selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspace.notificationCenter.addObserver(
            self, selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // Poll for screen lock/unlock every 5 s
        screenLockTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollScreenLock()
        }
        if let screenLockTimer { RunLoop.main.add(screenLockTimer, forMode: .common) }
        // Poll for idle threshold every 10 s
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.pollIdle()
        }
        if let idleTimer { RunLoop.main.add(idleTimer, forMode: .common) }
        // Poll for music volume every 5 s
        musicVolumeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollMusicVolume()
        }
        if let musicVolumeTimer { RunLoop.main.add(musicVolumeTimer, forMode: .common) }
        // Seed last volume level
        lastVolumeLevel = SystemVolumeClient.systemOutputVolume()
        // Poll for music playback every 2.5 s
        musicPlaybackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.pollMusicPlayback()
        }
        if let musicPlaybackTimer { RunLoop.main.add(musicPlaybackTimer, forMode: .common) }
        // Seed the initial playback state immediately; the first response is
        // recorded without firing a hook.
        pollMusicPlayback()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        overrideTimer?.invalidate()
        overrideTimer = nil
        frontmostDebounceTimer?.invalidate()
        frontmostDebounceTimer = nil
        screenLockTimer?.invalidate()
        screenLockTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil
        musicVolumeTimer?.invalidate()
        musicVolumeTimer = nil
        musicPlaybackTimer?.invalidate()
        musicPlaybackTimer = nil
        removeObservers()
        lastDownloads = []
        lastFired = [:]
        diagnostics = [:]
        lastFrontmostApp = nil
        lastScreenLocked = false
        lastIdleFireByTrigger = [:]
        lastVolumeLevel = 0.0
        lastPlaybackIsPlaying = false
        lastTrackTitle = ""
        lastTrackArtist = ""
        lastTrackAlbum = ""
        playbackSeeded = false
        playbackFetchInFlight = false
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

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let bundleID = app.bundleIdentifier ?? app.localizedName ?? ""
        // Debounce 200 ms to avoid flicker when apps activate in quick succession
        frontmostDebounceTimer?.invalidate()
        frontmostDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.lastFrontmostApp != bundleID {
                self.lastFrontmostApp = bundleID
                self.fire(hookType: "appFrontmost", trigger: bundleID)
            }
        }
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
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        var names = Set<String>()
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            let name = url.lastPathComponent
            let lower = name.lowercased()
            if Self.partialDownloadSuffixes.contains(where: { lower.hasSuffix($0) }) { continue }
            names.insert(name)
        }
        return names
    }

    // MARK: - Screen lock / unlock polling

    private func currentScreenIsLocked() -> Bool {
        let session = CGSessionCopyCurrentDictionary()
        return (session as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func pollScreenLock() {
        guard state != nil else { return }
        let isLocked = currentScreenIsLocked()
        if isLocked != lastScreenLocked {
            lastScreenLocked = isLocked
            if isLocked {
                fire(hookType: "screenLock", trigger: "")
            } else {
                fire(hookType: "screenUnlock", trigger: "")
            }
        }
    }

    // MARK: - Idle threshold polling

    private func pollIdle() {
        guard state != nil else { return }
        // `~0` is kCGAnyInputEventType: the time since *any* input (keyboard,
        // mouse, trackpad). Tracking only leftMouseDown meant typing never
        // reset the idle timer, so hooks could fire mid-keystroke.
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        let effectiveIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let hooks = HookStore.hooks(ofType: "idleThreshold")
        for hook in hooks {
            let trigger = hook.trigger.trimmingCharacters(in: .whitespaces)
            let threshold = trigger.isEmpty ? 300.0 : (Double(trigger) ?? 300.0)
            if effectiveIdle >= threshold {
                // Fire once per threshold period, tracked per-hook by trigger so
                // separate idle hooks do not share a single cooldown gate.
                let idleKey = hook.hookType + ":" + trigger
                if let last = lastIdleFireByTrigger[idleKey],
                   Date().timeIntervalSince(last) < threshold {
                    continue
                }
                if cooldownElapsed(hook, now: Date()) {
                    fire(hookType: "idleThreshold", trigger: trigger)
                    lastIdleFireByTrigger[idleKey] = Date()
                    break // Only fire one hook per check
                }
            }
        }
    }

    // MARK: - Music volume polling

    private func pollMusicVolume() {
        guard state != nil else { return }
        let currentVolume = SystemVolumeClient.systemOutputVolume()

        // Check for each musicVolume hook
        let hooks = HookStore.hooks(ofType: "musicVolume")
        for hook in hooks {
            let trigger = hook.trigger.trimmingCharacters(in: .whitespaces)
            // Empty trigger means hook is disabled
            guard !trigger.isEmpty else { continue }
            
            // Parse threshold from trigger (0-100)
            guard let threshold = Double(trigger), threshold >= 0, threshold <= 100 else { continue }
            
            // Fire when volume crosses threshold from below
            // lastVolumeLevel is in 0-1 range, threshold is percentage
            let thresholdRatio = Float(threshold / 100.0)
            if lastVolumeLevel < thresholdRatio && currentVolume >= thresholdRatio {
                if cooldownElapsed(hook, now: Date()) {
                    fire(hookType: "musicVolume", trigger: trigger)
                }
            }
        }
        lastVolumeLevel = currentVolume
    }

    // MARK: - Firing

    private func fire(hookType: String, trigger: String) {
        guard let state else { return }
        let now = Date()
        
        // Playback hooks can only match "any player": the public MediaPlayer
        // API does not expose the source app.
        let hooks = HookStore.hooks(ofType: hookType)
        guard let hook = hooks.first(where: { hook in
            let matchesTrigger: Bool
            if hookType == "musicPlayback" {
                // The public MediaPlayer API does not expose the source app,
                // so only an empty trigger ("any player") can ever match.
                matchesTrigger = hook.trigger.trimmingCharacters(in: .whitespaces).isEmpty
            } else {
                matchesTrigger = matches(hook.trigger, trigger)
            }
            return matchesTrigger && cooldownElapsed(hook, now: now)
        }) else { return }
        
        let allowed = HookStore.allowedActions(for: hookType)
        guard allowed.contains(hook.action) else { return }
        switch hook.action {
        case "breathing":
            guard applySystemOverride(theme: hook.theme, in: state) else { return }
        default:
            state.engine.perform(hook.action)
        }
        lastFired[hook] = Date()
        let d = diagnostics[hook]
        diagnostics[hook] = HookDiagnostics(lastFired: now, skipped: d?.skipped ?? 0)
    }

    /// True when the hook has no cooldown or enough time has passed since it
    /// last fired. A hook that is cooling down is skipped so the next matching
    /// hook can take the event.
    private func cooldownElapsed(_ hook: Hook, now: Date) -> Bool {
        guard let cooldown = hook.cooldown, let last = lastFired[hook] else { return true }
        let elapsed = now.timeIntervalSince(last)
        if elapsed >= cooldown {
            return true
        }
        // Track skipped fire due to cooldown
        let d = diagnostics[hook]
        diagnostics[hook] = HookDiagnostics(lastFired: d?.lastFired, skipped: (d?.skipped ?? 0) + 1)
        return false
    }

    /// Shows the hook theme for 30 s, then drops only the system layer. A newer
    /// system override replaces the previous timer.
    private func applySystemOverride(theme: String, in state: AppState) -> Bool {
        guard !theme.isEmpty, state.themes.contains(theme) else { return false }
        state.applyOverrideTheme(theme, owner: "system")
        overrideTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: false) { [weak self, weak state] _ in
            state?.clearOverride(owner: "system")
            self?.overrideTimer = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        overrideTimer = timer
        return true
    }

    // MARK: - Music playback polling

    private func pollMusicPlayback() {
        guard state != nil else { return }
        guard MediaRemoteClient.isAvailable else { return }
        // MediaRemote completes asynchronously; skip a tick rather than queue
        // overlapping requests.
        guard !playbackFetchInFlight else { return }
        playbackFetchInFlight = true
        MediaRemoteClient.fetch { [weak self] info, isPlaying in
            guard let self else { return }
            self.playbackFetchInFlight = false
            self.handlePlayback(info: info, isPlaying: isPlaying)
        }
    }

    private func handlePlayback(info: [String: Any]?, isPlaying: Bool) {
        let currentTitle = MediaRemoteClient.title(from: info)
        let currentArtist = MediaRemoteClient.artist(from: info)
        let currentAlbum = MediaRemoteClient.album(from: info)

        // The first response after launch seeds state without firing, so an
        // already-playing track does not flash on startup.
        guard playbackSeeded else {
            playbackSeeded = true
            lastPlaybackIsPlaying = isPlaying
            lastTrackTitle = currentTitle
            lastTrackArtist = currentArtist
            lastTrackAlbum = currentAlbum
            return
        }

        let stateChanged = isPlaying != lastPlaybackIsPlaying
        let trackChanged = currentTitle != lastTrackTitle
            || currentArtist != lastTrackArtist
            || currentAlbum != lastTrackAlbum

        if stateChanged || trackChanged {
            // Music may be playing through any app. MediaRemote does not
            // reliably expose the source bundle, so an empty trigger matches
            // any player (the editor enforces this).
            let triggerValue = stateChanged
                ? (isPlaying ? "started" : "stopped")
                : "trackChange"
            fire(hookType: "musicPlayback", trigger: triggerValue)
        }

        lastPlaybackIsPlaying = isPlaying
        lastTrackTitle = currentTitle
        lastTrackArtist = currentArtist
        lastTrackAlbum = currentAlbum
    }

    /// Empty trigger matches anything (used by sleep/wake, which fire for
    /// everyone). Patterns with "*" or "?" are globs; otherwise a
    /// case-insensitive substring match.
    private func matches(_ pattern: String, _ value: String) -> Bool {
        guard !pattern.isEmpty else { return true }
        if pattern.contains("*") || pattern.contains("?") {
            return fnmatch(pattern.lowercased(), value.lowercased(), 0) == 0
        }
        return value.localizedCaseInsensitiveContains(pattern)
    }

    static func diagnostics(for hook: Hook) -> HookDiagnostics? {
        shared.diagnostics[hook]
    }
}