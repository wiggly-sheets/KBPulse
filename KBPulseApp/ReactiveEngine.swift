//
//  ReactiveEngine.swift
//  KBPulseApp
//
//  Typing-reactive mode: a listen-only CGEventTap on the engine thread records
//  keydowns, and a 60 Hz timer applies a bump-and-decay brightness envelope.
//  Requires Accessibility permission; without it the theme simply rests at
//  zero brightness (degraded, no breathing fallback).
//

import ApplicationServices
import Foundation

final class ReactiveEngine {
    // Mutable state shared between the tap callback and the decay timer.
    private final class State {
        let lock = NSLock()
        var cfg = ReactiveMode()
        var amount = 0.0     // bump magnitude of the last keystroke
        var timestamp = 0.0  // last keystroke time, ms since boot
        var hasEvent = false
    }

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var timer: CFRunLoopTimer?
    private var state: State?
    private var stale: (() -> Bool)?

    static func isAccessibilityGranted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary)
    }

    /// Envelope: instant bump, linear decay from `floor + amount` down to
    /// `floor` over `decay` ms. Pure function so it can be tested standalone.
    static func brightness(elapsedMS: Double, amount: Double, floor: Double, decay: Double) -> Double {
        guard amount > 0, decay > 0, elapsedMS >= 0, elapsedMS < decay else { return floor }
        return min(1, floor + amount * (1 - elapsedMS / decay))
    }

    /// Blocks the calling thread (must have a run loop) until `stale()` turns
    /// true, then tears down the tap and fades the backlight to rest.
    /// Returns false when the tap could not run (no Accessibility permission,
    /// or tap creation failed): the caller leaves the backlight resting off.
    func run(cfg: ReactiveMode, stale: @escaping () -> Bool) -> Bool {
        self.stale = stale
        guard Self.isAccessibilityGranted(prompt: false) else { return false }

        let s = State()
        s.lock.lock()
        s.cfg = cfg
        s.lock.unlock()
        state = s
        // Retained for refcon; released in teardown below.
        let refcon = UnsafeMutableRawPointer(Unmanaged.passRetained(s).toOpaque())

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: Self.tapCallback, userInfo: refcon) else {
            Unmanaged<State>.fromOpaque(refcon).release()
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        CGEvent.tapEnable(tap: tap, enable: true)

        timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 1.0 / 60.0, 0, 0) { [weak self] _ in
            self?.tick()
        }
        if let timer { CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode) }

        CFRunLoopRun()

        // Teardown: the run loop stopped because the run became stale.
        if let timer { CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer, .defaultMode) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode) }
        CGEvent.tapEnable(tap: tap, enable: false)
        self.tap = nil
        tapSource = nil
        timer = nil
        state = nil
        Unmanaged<State>.fromOpaque(refcon).release()
        // Resting state, matching the breathing loop's shutdown fade.
        KBPAnimator.setBrightness(Float(min(1, cfg.floor)), withDuration: 2500)
        return true
    }

    private func tick() {
        guard let stale = self.stale, !stale() else { CFRunLoopStop(CFRunLoopGetCurrent()); return }
        guard let s = state else { CFRunLoopStop(CFRunLoopGetCurrent()); return }
        s.lock.lock()
        let cfg = s.cfg
        let amount = s.amount
        let timestamp = s.timestamp
        let hasEvent = s.hasEvent
        s.lock.unlock()
        guard hasEvent else { return } // nothing struck yet; leave backlight down
        let elapsed = ProcessInfo.processInfo.systemUptime * 1000 - timestamp
        KBPAnimator.setBrightness(Float(Self.brightness(elapsedMS: elapsed, amount: amount, floor: cfg.floor, decay: Double(cfg.decay))), withDuration: 0)
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
        guard let refcon else { return nil }
        let s = Unmanaged<State>.fromOpaque(refcon).takeUnretainedValue()
        s.lock.lock()
        defer { s.lock.unlock() }
        switch type {
        case .keyDown:
            // Autorepeats fire continuously while a key is held; they would
            // pin the brightness at max, so they don't count as new bumps.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return nil }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            switch code {
            case 49: s.amount = s.cfg.spaceBump      // kVK_Space
            case 36, 76: s.amount = s.cfg.enterBump  // kVK_Return, keypad enter
            default: s.amount = s.cfg.bump
            }
        case .flagsChanged:
            // Fires on press and release; a release that leaves nothing held
            // has empty flags and doesn't count as a bump.
            guard event.flags.rawValue != 0 else { return nil }
            s.amount = s.cfg.modifierBump
        default:
            return nil
        }
        s.timestamp = ProcessInfo.processInfo.systemUptime * 1000
        s.hasEvent = true
        return nil
    }
}
