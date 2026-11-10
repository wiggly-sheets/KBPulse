//
//  AgentHookRuntime.swift
//  KBPulseApp
//
//  Polls the process table for monitored coding agents and drives a transient
//  theme override, leaving the persisted base theme untouched:
//    agent starts        → switch to an attention hook theme for that agent.
//    agent exits         → re-evaluate the theme for any remaining agents or
//                          clear the override, then fire its exit hook.
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
    private var previousAgents: Set<String> = []
    private weak var state: AppState?

    func start(in state: AppState) {
        self.state = state
        previousAgents = []
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
        previousAgents = []
        state?.clearOverride(owner: "agent")
    }

    // MARK: - Tick

    private func tick() {
        guard let state else { return }
        guard let agents = AgentMonitor.activeAgents else { return }
        let current = Set(agents)
        guard current != previousAgents else { return }
        let exited = previousAgents.subtracting(current).sorted()
        previousAgents = current

        // Reconcile theme first: startEngine() wipes a pending flash overlay.
        if current.isEmpty {
            state.clearOverride(owner: "agent")
        } else {
            applyAttentionHook(active: current)
        }
        for name in exited {
            fireExitHook(for: name)
        }
    }

    // MARK: - Attention (agent alive)

    /// Picks the first sorted active agent with a matching hook theme, so the
    /// result is deterministic when multiple agents run.
    private func applyAttentionHook(active: Set<String>) {
        guard let state else { return }
        for name in active.sorted() {
            guard let hook = HookStore.hooks(ofType: "agentAttention", matching: name)
                .first(where: {
                    $0.action == "breathing" && !$0.theme.isEmpty && state.themes.contains($0.theme)
                }) else { continue }
            state.applyOverrideTheme(hook.theme, owner: "agent")
            return
        }
        state.clearOverride(owner: "agent")
    }

    // MARK: - Exit (agent gone)

    private func fireExitHook(for agent: String) {
        guard let state,
              let hook = HookStore.hooks(ofType: "agentExit", matching: agent).first,
              HookStore.allowedActions(for: "agentExit").contains(hook.action) else { return }
        state.engine.perform(hook.action)
    }
}
