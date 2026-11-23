//
//  HapticPlayer.swift
//  KBPulseApp
//
//  Trackpad haptics. The public API provides short taps only; continuous
//  waveforms would need the private MultitouchSupport actuator.
//

import AppKit
import Foundation

protocol HapticPlayer: AnyObject {
    func tap()
}

/// Public AppKit haptics. Off unless the user enables the setting.
/// Rate-limited so a held key cannot buzz the trackpad.
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
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
}

final class NoopHapticPlayer: HapticPlayer {
    func tap() {}
}
