//
//  HapticPlayer.swift
//  KBPulseApp
//
//  Trackpad haptics. Public AppKit taps only work with a finger on the
//  trackpad, so MultitouchSupport is the primary path for background taps.
//

import AppKit
import Foundation

protocol HapticPlayer: AnyObject {
    func tap()
}

/// Private MultitouchSupport taps, with public AppKit as fallback.
/// Off unless the user enables the setting. Rate-limited so a held key
/// cannot buzz the trackpad.
final class SystemHapticPlayer: HapticPlayer {
    private let lock = NSLock()
    private var lastTap = 0.0
    private let minimumInterval = 0.05

    func tap() {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard now - lastTap >= minimumInterval else {
            lock.unlock()
            return
        }
        lastTap = now
        lock.unlock()
        let level = UserDefaults.standard.object(forKey: "hapticsIntensity") as? Double ?? 1.0
        // The usable actuator range starts around half strength, so map the
        // whole slider 0...1 onto 0.5...1.0.
        let intensity = 0.5 + 0.5 * min(1, max(0, level))
        if KBPHapticActuator.tap(withIntensity: Float(intensity)) { return }
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}

final class NoopHapticPlayer: HapticPlayer {
    func tap() {}
}
