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
//  value. Reactive mode owns the thread outright and ignores overlays.
//

import Foundation

final class Engine {
    // Bumping this ID invalidates the running loop; the loop exits after its
    // current animation and fades the backlight off once.
    private var runID = 0
    private var thread: Thread?
    private var profile: KBPProfile?
    private var reactive: ReactiveMode?
    private var overlay: (() -> Void)?
    private let overlayLock = NSLock()
    private var stopSemaphore: DispatchSemaphore?

    func start(profile: KBPProfile, reactive: ReactiveMode?) {
        stop()
        self.profile = profile
        self.reactive = reactive
        spawn()
    }

    /// One-shot overlay: runs `work` on the engine thread, then the base loop
    /// resumes on its next iteration. No-op while reactive mode is active.
    func overlay(_ work: @escaping () -> Void) {
        guard reactive == nil else { return }
        overlayLock.lock()
        overlay = work
        overlayLock.unlock()
        if thread == nil || thread?.isExecuting != true { spawn() }
    }

    /// A flash: quick brighten, fade back to rest, then resume the base loop.
    func flash() {
        overlay { [weak self] in
            guard let self else { return }
            KBPAnimator.setBrightness(1, withDuration: 80)
            Thread.sleep(forTimeInterval: 0.3)
            KBPAnimator.setBrightness(0, withDuration: 1000)
        }
    }

    func stop() {
        runID += 1
        let sema = stopSemaphore
        stopSemaphore = nil
        // Wait for thread to finish its iteration if it's running
        _ = sema?.wait(timeout: .now() + 5)
        overlayLock.lock()
        overlay = nil
        overlayLock.unlock()
        thread = nil
        profile = nil
        reactive = nil
    }

    private func spawn() {
        guard profile != nil else { return }
        runID += 1
        let id = runID
        let sema = DispatchSemaphore(value: 0)
        stopSemaphore = sema
        let name = reactive == nil ? "KBPEngine" : "KBPReactiveEngine"
        let thread = Thread(block: { [weak self] in
            defer { sema.signal() }
            self?.run(id: id)
        })
        thread.name = name
        self.thread = thread
        thread.start()
    }

    private func run(id: Int) {
        guard let p = profile else { return }
        run(id: id, profile: p)
    }

    private func run(id: Int, profile: KBPProfile) {
        while id == runID {
            // Run a pending overlay once, then fall through to the base loop.
            overlayLock.lock()
            let ov = overlay
            overlay = nil
            overlayLock.unlock()
            if let ov {
                guard id == runID else { return }
                ov()
                continue
            }
            if let reactive {
                guard id == runID else { return }
                _ = ReactiveEngine().run(cfg: reactive, stale: { [weak self] in self?.runID != id })
                return
            }
            guard profile.animations.count > 0 else { return }
            for case let animation as KBPAnimation in profile.animations {
                guard id == runID else { return }
                KBPAnimator.setBrightness(animation.brightness.floatValue,
                                          withDuration: Int32(animation.fadeDuration.intValue))
                Thread.sleep(forTimeInterval: animation.totalDuration().doubleValue / 1000)
            }
        }
        // Resting state when disabled or the theme switched: fade to off.
    }
}