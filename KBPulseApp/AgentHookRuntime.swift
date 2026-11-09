//
//  AgentHookRuntime.swift
//  KBPulseApp
//
//  Polls the process table for monitored coding agents and drives the engine:
//    no agent running        → base theme
//    agent alive             → "needs attention": switch to the attention
//                              hook's theme (or keep the base one if none).
//    agent exits             → fire the exit hook's action (flash), then
//                              restore the base theme.
//
//  Polling is coarse (1 s) — agents don't flicker that fast, and the engine
//  thread does the actual brightness work. The runtime is a singleton on
//  the main thread; it only touches AppState/engine bindings, never the
//  brightness API directly.
//

import Foundation

final class AgentHookRuntime {
    static let shared = AgentHookRuntime()

    private var timer: Timer?
    private var wasRunning = false
    private var baseTheme = ""
    private var baseEngineOn = true
    private weak var state: AppState?

    func start(in state: AppState) {
        self.state = state
        baseTheme = state.selectedTheme
        baseEngineOn = state.engineOn
        wasRunning = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // First tick immediately so the user sees the switch without a 1 s wait.
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if wasRunning {
            restoreBase()
            wasRunning = false
        }
    }

    // MARK: - Tick

    private func tick() {
        guard let state else { return }
        let running = AgentMonitor.isRunning
        if running {
            if !wasRunning {
                // Transition: agent came up. Save the base theme so we can
                // restore it later, then switch to the attention hook's theme.
                baseTheme = state.selectedTheme
                baseEngineOn = state.engineOn
                wasRunning = true
                applyAttentionHook()
            }
            // While running: if the user changed the base theme manually,
            // the attention hook theme wins; otherwise keep current.
            return
        }
        if wasRunning {
            // Transition: the last agent exited. Fire the exit hook, then
            // restore the base theme.
            fireExitHooks()
            restoreBase()
            wasRunning = false
        }
    }

    // MARK: - Attention (agent alive)

    private func applyAttentionHook() {
        guard let hook = HookStore.attentionHooks().first else { return }
        let theme = hook.theme
        guard !theme.isEmpty else { return }
        guard state?.themes.contains(theme) == true else { return }
        state?.selectTheme(theme)
    }

    // MARK: - Exit (agent gone)

    private func fireExitHooks() {
        for hook in HookStore.exitHooks() {
            let action = hook.action
            guard !action.isEmpty else { continue }
            switch action {
            case "flash":
                state?.engine.flash()
            case "breathing":
                let theme = hook.theme
                if !theme.isEmpty,
                   state?.themes.contains(theme) == true {
                    state?.selectTheme(theme)
                }
            default:
                continue
            }
        }
    }

    // MARK: - Restore

    private func restoreBase() {
        guard let state else { return }
        // If the engine was off before the agent ran, turn it off again.
        if !baseEngineOn {
            state.setEngine(false)
            return
        }
        if !baseTheme.isEmpty, state.themes.contains(baseTheme) {
            state.selectTheme(baseTheme)
        }
    }
}