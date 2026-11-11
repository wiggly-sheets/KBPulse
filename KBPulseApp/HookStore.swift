//
//  HookStore.swift
//  KBPulseApp
//
//  Reads/writes ~/Documents/KBPulse/hooks.json. Settings exposes an editor
//  for this file on its Hooks tab. AgentHookRuntime reacts to coding-agent
//  detection and SystemEventRuntime reacts to app launches/terminations,
//  wake, files landing in Downloads, app frontmost changes, screen lock/
//  unlock, idle threshold, and music volume. See the hookType list below for
//  every event class.
//
//  Schema:
//    [ { "hookType": "…", "trigger": "…", "action": "…", "theme": "…",
//        "enabled": true, "cooldown": 2 } ]
//
//    cooldown — optional seconds before the same hook fires again. The key
//               is optional; older files without it decode normally.
//
//    hookType — event class that fired.
//              "agentAttention"  — a monitored agent process is alive and
//                                  waiting for input. Backlight switches to
//                                  its theme while it runs.
//              "agentExit"       — a monitored agent process just exited.
//                                  Supports "flash", then the base theme is
//                                  restored.
//              "appLaunched"     — a foreground app was launched.
//              "appTerminated"   — an app is quitting.
//              "wake"            — the Mac woke from sleep.
//              "fileDownload"    — a new file appeared in Downloads.
//              "appFrontmost"    — a different app became frontmost.
//              "screenLock"      — the screen was locked.
//              "screenUnlock"    — the screen was unlocked.
//              "idleThreshold"   — the system was idle longer than the
//                                  trigger threshold (seconds).
//              "musicVolume"     — system output volume crossed the trigger
//                                  threshold (0-100%). Empty trigger disables.
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
//              appFrontmost: bundle identifier or localised name, substring
//                      match (or glob with "*"/"?"). Empty matches any app.
//              screenLock/screenUnlock: trigger must be empty.
//              idleThreshold: numeric seconds (e.g. "300"). Empty uses
//                      default 300 s. Non-numeric rejected.
//              musicVolume: percentage 0-100 as string, or empty for off.
//    action   — engine behavior while the hook fires.
//              "flash"   — quick brighten, fade back to rest, restore theme.
//              "pulse"   — two quick brighten/dim beats, then fade out.
//              "hold"    — brighten, hold 2 s, fade out.
//              "fade"    — fade out and hold dark for 1 s.
//              "breathing" — switch to the hook theme (agent while it runs,
//                            system event for 30 seconds).
//              "agentExit" allows flash, pulse, hold, and fade.
//              "agentAttention" allows breathing only.
//              All new system events allow all actions.
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

    init(hookType: String, trigger: String = "", action: String = "",
         theme: String = "", enabled: Bool = false, cooldown: Double? = nil) {
        self.hookType = hookType
        self.trigger = trigger
        self.action = action
        self.theme = theme
        self.enabled = enabled
        self.cooldown = cooldown
    }

    // Decode with defaults for missing or wrong-type keys, so one malformed
    // field in one hook does not fail the whole file. Wrong types yield the
    // field default instead of throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hookType = (try? c.decodeIfPresent(String.self, forKey: .hookType)) ?? ""
        trigger = (try? c.decodeIfPresent(String.self, forKey: .trigger)) ?? ""
        action = (try? c.decodeIfPresent(String.self, forKey: .action)) ?? ""
        theme = (try? c.decodeIfPresent(String.self, forKey: .theme)) ?? ""
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        cooldown = try? c.decodeIfPresent(Double.self, forKey: .cooldown)
    }
}

enum HookStore {
    static var fileURL: URL { AppState.themesDir.appendingPathComponent("hooks.json") }

    enum LoadError: LocalizedError {
        case read(String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .read(let detail):
                return "Could not read hooks.json: \(detail)"
            case .decode(let detail):
                return "Could not decode hooks.json: \(detail)"
            }
        }
    }

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

    /// Writes the full hook list back to hooks.json.
    static func save(_ hooks: [Hook]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(hooks)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Hook types documented in the header comment, in menu order.
    static let hookTypes = [
        "agentAttention", "agentExit", "appLaunched",
        "appTerminated", "wake", "fileDownload",
        "appFrontmost", "screenLock", "screenUnlock", "idleThreshold",
        "musicVolume", "musicPlayback",
    ]

    /// User-friendly display names for hook types.
    static let hookTypeDisplayNames: [String: String] = [
        "agentAttention": "Agent Attention",
        "agentExit": "Agent Exit",
        "appLaunched": "App Launched",
        "appTerminated": "App Terminated",
        "wake": "Wake from Sleep",
        "fileDownload": "File Downloaded",
        "appFrontmost": "App Became Frontmost",
        "screenLock": "Screen Locked",
        "screenUnlock": "Screen Unlocked",
        "idleThreshold": "Idle Threshold Reached",
        "musicVolume": "Volume Changed",
        "musicPlayback": "Playback Changed",
    ]

    /// All supported actions.
    static let actions = ["flash", "pulse", "hold", "fade", "breathing"]

    /// Returns the actions allowed for a hook type.
    static func allowedActions(for hookType: String) -> [String] {
        switch hookType {
        case "agentAttention": return ["breathing"]
        case "agentExit": return ["flash", "pulse", "hold", "fade"]
        case "appFrontmost", "screenLock", "screenUnlock", "idleThreshold", "musicVolume", "musicPlayback": return actions
        default: return actions
        }
    }

    /// True for hook types that match a coding-agent executable.
    static func isAgentType(_ hookType: String) -> Bool {
        hookType == "agentAttention" || hookType == "agentExit"
    }

    /// Returns a user-facing problem with `hook`, or nil when it is valid.
    static func validationError(for hook: Hook, themes: [String]) -> String? {
        guard hookTypes.contains(hook.hookType) else {
            return "Unknown hook type \"\(hook.hookType)\"."
        }
        let allowed = allowedActions(for: hook.hookType)
        guard allowed.contains(hook.action) else {
            return "Action must be one of \(allowed.joined(separator: ", "))."
        }
        if hook.hookType == "agentAttention" && hook.action != "breathing" {
            return "Agent attention hooks must use the breathing action."
        }
        if isAgentType(hook.hookType) {
            let trigger = hook.trigger.trimmingCharacters(in: .whitespaces)
            if trigger.isEmpty {
                return "Agent hooks need a trigger (the executable name)."
            }
            if trigger.contains("/") {
                return "Agent trigger must be an executable name, not a path."
            }
        }
        if hook.hookType == "wake"
            && !hook.trigger.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Wake hooks must have an empty trigger."
        }
        if hook.hookType == "screenLock" || hook.hookType == "screenUnlock" {
            if !hook.trigger.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Screen lock/unlock hooks must have an empty trigger."
            }
        }
        if hook.hookType == "idleThreshold" {
            let trigger = hook.trigger.trimmingCharacters(in: .whitespaces)
            if !trigger.isEmpty {
                guard let value = Double(trigger), value > 0 else {
                    return "Idle threshold trigger must be a positive number of seconds, or empty for default (300 s)."
                }
            }
        }
        if hook.hookType == "appFrontmost" {
            // Any trigger is valid (bundle ID, name, glob, or empty for any app)
        }
        if hook.hookType == "musicVolume" {
            let trigger = hook.trigger.trimmingCharacters(in: .whitespaces)
            if !trigger.isEmpty {
                guard let threshold = Double(trigger), threshold >= 0, threshold <= 100 else {
                    return "Music volume trigger must be a number between 0 and 100, or empty for off."
                }
            }
        }
        if hook.hookType == "musicPlayback" {
            // Trigger is optional bundle ID for filtering (empty = any media app)
            let trigger = hook.trigger.trimmingCharacters(in: .whitespaces)
            // No validation needed - empty or bundle ID are both valid
        }
        if hook.action == "breathing" {
            guard !hook.theme.isEmpty else {
                return "Breathing hooks need a theme."
            }
            guard themes.contains(hook.theme) else {
                return "Theme \"\(hook.theme)\" does not exist."
            }
        }
        if let cooldown = hook.cooldown, !cooldown.isFinite || cooldown < 0 {
            return "Cooldown must be a finite number of seconds, zero or more."
        }
        return nil
    }

    /// All enabled hooks, or [] when the file is missing/invalid.
    /// Per-field lenient decoding keeps the rest of the file usable when one
    /// hook has a wrong-typed field.
    static func load() -> [Hook] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Hook].self, from: data)) ?? []
    }

    /// Like `load()`, but reports read and decode failures so the editor can
    /// refuse to overwrite a file it could not understand. A missing file
    /// returns [].
    static func loadForEditing() throws -> [Hook] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError.read(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode([Hook].self, from: data)
        } catch {
            throw LoadError.decode(error.localizedDescription)
        }
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
        let names = load()
            .filter { $0.enabled && isAgentType($0.hookType) }
            .map(\.trigger)
            .filter { !$0.isEmpty }
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