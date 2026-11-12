//
//  Engine.swift
//  KBPulseApp
//
//  In-process animation engine: loops the active profile's animations on a
//  background thread through the CoreBrightness-backed KBPAnimator.
//
//  Hooks overlay the base loop: a hook calls `overlay(_:)`, which runs its
//  work once on the engine thread, then the breathing loop resumes. Overlays
//  never interleave with animations, so two hooks can't race the brightness
//  value. Reactive mode owns the thread outright; flashes reach it as
//  impulses instead of overlays.
//

import Foundation

final class Engine {
    static let shared = Engine()
    
    // Bumping this ID invalidates the running loop; the loop exits after its
    // current animation and fades the backlight off once.
    private var runID = 0
    private let runIDLock = NSLock()
    private var thread: Thread?
    private var profile: KBPProfile?
    private var reactive: ReactiveMode?
    private var overlay: ((Int) -> Void)?
    private let overlayLock = NSLock()
    // The running reactive engine, so `flash()` can inject impulses. Guarded
    // because flashes arrive from hook threads.
    private var reactiveEngine: ReactiveEngine?
    private let reactiveEngineLock = NSLock()
    private var stopSemaphore: DispatchSemaphore?

    func start(profile: KBPProfile, reactive: ReactiveMode?) {
        stop()
        self.profile = profile
        self.reactive = reactive
        spawn()
    }

    /// One-shot overlay: runs `work` on the engine thread, then the base loop
    /// resumes on its next iteration. No-op while reactive mode is active.
    func overlay(_ work: @escaping (Int) -> Void) {
        reactiveEngineLock.lock()
        let reactive = reactiveEngine
        reactiveEngineLock.unlock()
        guard reactive == nil, profile != nil else { return }
        overlayLock.lock()
        overlay = work
        overlayLock.unlock()
        if thread == nil || thread?.isExecuting != true { spawn() }
    }

    /// A flash: quick brighten, fade back to rest, then resume the base loop.
    /// While a reactive engine is running, the flash is an impulse instead.
    func flash() {
        reactiveEngineLock.lock()
        let reactive = reactiveEngine
        reactiveEngineLock.unlock()
        if let reactive {
            reactive.impulse(amount: 1.0)
            return
        }
        overlay { [weak self] id in
            guard let self else { return }
            KBPAnimator.setBrightness(1, withDuration: 80)
            sleepChunks(0.3, id: id)
            KBPAnimator.setBrightness(0, withDuration: 1000)
        }
    }

    /// Runs a hook action on the engine thread. While reactive mode is active,
    /// non-breathing actions become a flash impulse. Breathing is handled by
    /// the caller as a theme override, so it is a no-op here.
    func perform(_ action: String) {
        guard action != "breathing" else { return }
        reactiveEngineLock.lock()
        let reactive = reactiveEngine
        reactiveEngineLock.unlock()
        if reactive != nil {
            flash()
            return
        }
        switch action {
        case "pulse":
            overlay { [weak self] id in
                guard let self else { return }
                for _ in 0..<2 {
                    KBPAnimator.setBrightness(1, withDuration: 80)
                    sleepChunks(0.08, id: id)
                    KBPAnimator.setBrightness(0, withDuration: 120)
                    sleepChunks(0.12, id: id)
                }
                KBPAnimator.setBrightness(0, withDuration: 800)
            }
        case "hold":
            overlay { [weak self] id in
                guard let self else { return }
                KBPAnimator.setBrightness(1, withDuration: 80)
                sleepChunks(2.08, id: id)
                KBPAnimator.setBrightness(0, withDuration: 1500)
            }
        case "fade":
            overlay { [weak self] id in
                guard let self else { return }
                KBPAnimator.setBrightness(0, withDuration: 2000)
                sleepChunks(3.0, id: id)
            }
        default:
            flash()
        }
    }

    func stop() {
        _ = bumpRunID()
        let sema = stopSemaphore
        stopSemaphore = nil
        // Wait for thread to finish its iteration if it's running
        _ = sema?.wait(timeout: .now() + 5)
        reactiveEngineLock.lock()
        reactiveEngine = nil
        reactiveEngineLock.unlock()
        overlayLock.lock()
        overlay = nil
        overlayLock.unlock()
        thread = nil
        profile = nil
        reactive = nil
    }

    // MARK: - Public API for CLI

    func setTheme(_ name: String) {
        let url = AppState.themesDir.appendingPathComponent("\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let raw = (try? ThemeStore.rawDictionary(at: url)) ?? [:]
        stop()
        start(profile: KBPProfile(fileURL: url), reactive: ReactiveMode(forEngine: raw))
    }

    private func spawn() {
        guard let profile else { return }
        let reactive = self.reactive
        let id = bumpRunID()
        let sema = DispatchSemaphore(value: 0)
        stopSemaphore = sema
        let name = reactive == nil ? "KBPEngine" : "KBPReactiveEngine"
        let thread = Thread(block: { [weak self] in
            defer { sema.signal() }
            self?.run(id: id, profile: profile, reactive: reactive)
        })
        thread.name = name
        self.thread = thread
        thread.start()
    }

    private func run(id: Int, profile: KBPProfile, reactive: ReactiveMode?) {
        while isCurrent(id) {
            // Run a pending overlay once, then fall through to the base loop.
            overlayLock.lock()
            let ov = overlay
            overlay = nil
            overlayLock.unlock()
            if let ov {
                guard isCurrent(id) else { return }
                ov(id)
                continue
            }
            if let reactive {
                guard isCurrent(id) else { return }
                let ran = runReactive(ReactiveEngine(), cfg: reactive, id: id)
                guard isCurrent(id) else { return }
                if ran { return }
                // Tap unavailable (no Accessibility permission, or creation
                // failed): fall back to the theme's animations, or fade off
                // when there are none, then retry reactive mode next pass.
                if profile.animations.isEmpty {
                    KBPAnimator.setBrightness(0, withDuration: 1000)
                    sleepChunks(1.0, id: id)
                    continue
                }
            }
            guard profile.animations.count > 0 else { return }
            for case let animation as KBPAnimation in profile.animations {
                guard isCurrent(id) else { return }
                let brightness = Float(min(1, max(0, animation.brightness.floatValue)))
                let fade = Int32(max(0, animation.fadeDuration.intValue))
                KBPAnimator.setBrightness(brightness, withDuration: fade)
                sleepChunks(max(animation.totalDuration().doubleValue / 1000, 0.05), id: id)
            }
        }
    }

    /// Bumps the run ID and returns the new value; invalidates the running loop.
    private func bumpRunID() -> Int {
        runIDLock.lock()
        runID += 1
        let id = runID
        runIDLock.unlock()
        return id
    }

    private func currentRunID() -> Int {
        runIDLock.lock()
        let id = runID
        runIDLock.unlock()
        return id
    }

    private func isCurrent(_ id: Int) -> Bool {
        currentRunID() == id
    }

    /// Sleeps up to `duration` seconds in 100 ms chunks, stopping early when the
    /// run is invalidated.
    private func sleepChunks(_ duration: Double, id: Int) {
        var remaining = duration
        while remaining > 0, isCurrent(id) {
            Thread.sleep(forTimeInterval: min(remaining, 0.1))
            remaining -= 0.1
        }
    }

    /// Runs `re` and keeps it reachable for `flash()` while it runs.
    private func runReactive(_ re: ReactiveEngine, cfg: ReactiveMode, id: Int) -> Bool {
        reactiveEngineLock.lock()
        reactiveEngine = re
        reactiveEngineLock.unlock()
        defer {
            reactiveEngineLock.lock()
            if reactiveEngine === re { reactiveEngine = nil }
            reactiveEngineLock.unlock()
        }
        // Drain a pending overlay once on the engine thread before the run loop
        // takes over.
        overlayLock.lock()
        let ov = overlay
        overlay = nil
        overlayLock.unlock()
        // A flash queued during stop must not fire after cancellation.
        guard isCurrent(id) else { return false }
        ov?(id)
        return re.run(cfg: cfg, stale: { [weak self] in self?.isCurrent(id) != true })
    }
}