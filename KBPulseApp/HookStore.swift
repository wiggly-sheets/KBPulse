//
//  HookStore.swift
//  KBPulseApp
//
//  Reads/writes ~/Documents/KBPulse/hooks.json. Hook *storage* is wired up;
//  AgentHookRuntime reacts to coding-agent detection and SystemEventRuntime
//  reacts to app launches/terminations, wake, and files landing in Downloads.
//  See the hookType list below for every event class.
//
//  Schema:
//    [ { "hookType": "…", "trigger": "…", "action": "…", "theme": "…",
//        "enabled": true, "cooldown": 2 } ]
//
//    cooldown — optional seconds before the same hook fires again. The key
//               is optional; older files without it decode normally.
//
//    hookType — event class that fired.
//              "agentAttention" — a monitored agent process is alive and
//                                 waiting for input. Backlight switches to
//                                 its theme while it runs.
//              "agentExit"      — a monitored agent process just exited.
//                                 Supports "flash", then the base theme is
//                                 restored.
//              "appLaunched"    — a foreground app was launched.
//              "appTerminated"  — an app is quitting.
//              "wake"           — the Mac woke from sleep.
//              "fileDownload"   — a new file appeared in Downloads.
//    trigger  — matcher for the event.
//              Agents: executable basename, exact case-insensitive match.
//              Apps:  bundle identifier or localised name, substring
//                      match. Empty trigger matches anything (used by
//                      sleep/wake, which fire for everyone).
//              fileDownload: filename, substring match, or a glob such as
//                      "*.zip" when the pattern contains "*" or "?".
//                      Downloads ignores folders, hidden files, and partial
//                      download suffixes (.crdownload, .download, .part,
//                      .tmp, .filepart, .opdownload).
//    action   — engine behavior while the hook fires.
//              "flash"   — quick brighten, fade back to rest, restore theme.
//                            The only action for "agentExit".
//              "breathing" — switch to the hook theme (agent while it runs,
//                            system event for 30 seconds).
//    theme    — profile to switch to while the hook fires; empty string
//               keeps the current one.
//    enabled  — whether the hook runs.
//
//  What is NOT observable without a system extension: notifications from
//  other apps, and download *progress*. "fileDownload" fires when the
//  file lands — the moment the user actually cares about.
//

import Foundation

struct Hook: Codable, Hashable {
    var hookType: String
    var trigger: String
    var action: String
    var theme: String
    var enabled: Bool
    var cooldown: Double?
}

enum HookStore {
    static var fileURL: URL { AppState.themesDir.appendingPathComponent("hooks.json") }

    /// Creates hooks.json with the default agent hooks if none exists, so a
    /// fresh install reacts to coding agents out of the box.
    static func ensureFile() {
        let url = fileURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let defaults: [Hook] = [
            // Coding agents: attention while alive, flash on exit.
            .init(hookType: "agentAttention", trigger: "claude", action: "breathing", theme: "Yawn", enabled: true),
            .init(hookType: "agentAttention", trigger: "codex", action: "breathing", theme: "Yawn", enabled: true),
            .init(hookType: "agentAttention", trigger: "opencode", action: "breathing", theme: "Yawn", enabled: true),
            .init(hookType: "agentAttention", trigger: "herdr", action: "breathing", theme: "Yawn", enabled: true),
            .init(hookType: "agentAttention", trigger: "pi", action: "breathing", theme: "Yawn", enabled: true),
            .init(hookType: "agentExit", trigger: "claude", action: "flash", theme: "", enabled: true),
            .init(hookType: "agentExit", trigger: "codex", action: "flash", theme: "", enabled: true),
            .init(hookType: "agentExit", trigger: "opencode", action: "flash", theme: "", enabled: true),
            .init(hookType: "agentExit", trigger: "herdr", action: "flash", theme: "", enabled: true),
            .init(hookType: "agentExit", trigger: "pi", action: "flash", theme: "", enabled: true),
            // System events.
            .init(hookType: "wake", trigger: "", action: "flash", theme: "", enabled: true),
            .init(hookType: "fileDownload", trigger: "", action: "flash", theme: "", enabled: true, cooldown: 2),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(defaults) else {
            try? Data("[]".utf8).write(to: url, options: .atomic)
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    /// All enabled hooks, or [] when the file is missing/invalid.
    static func load() -> [Hook] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Hook].self, from: data) else {
            return []
        }
        return list
    }

    /// All enabled agent-exit hooks (fire once, transient).
    static func exitHooks() -> [Hook] {
        load().filter { $0.enabled && $0.hookType == "agentExit" }
    }

    /// All enabled agent-attention hooks (fire while an agent runs).
    static func attentionHooks() -> [Hook] {
        load().filter { $0.enabled && $0.hookType == "agentAttention" }
    }

    /// Every trigger basename across enabled agent hooks, used to populate
    /// the process-table scan.
    static func monitoredNames() -> [String] {
        let names = (exitHooks().map(\.trigger) + attentionHooks().map(\.trigger)).filter { !$0.isEmpty }
        return Array(Set(names)).sorted()
    }

    /// Hooks of one event class, used by SystemEventRuntime.
    static func hooks(ofType type: String) -> [Hook] {
        load().filter { $0.enabled && $0.hookType == type }
    }

    /// Hooks of one event class whose trigger matches `name` exactly,
    /// ignoring case. Agent triggers are executable basenames.
    static func hooks(ofType type: String, matching name: String) -> [Hook] {
        hooks(ofType: type).filter { $0.trigger.caseInsensitiveCompare(name) == .orderedSame }
    }
}