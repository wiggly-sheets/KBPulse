//
//  ThemeStore.swift
//  KBPulseApp
//
//  Raw JSON read/write for theme files in ~/Documents/KBPulse/, plus the
//  typing-reactions ("Reactive") section that rides alongside Animations.
//  Reads/writes the whole dictionary so unknown keys survive a round trip
//  (KBPProfile's writer would drop them).
//

import Foundation

/// Config for typing-reactive themes. While active, the engine runs this
/// instead of the theme's animation loop.
struct ReactiveMode {
    var enabled = true
    var bump = 0.7          // brightness added on a normal keydown [0, 1]
    var decay = 400         // ms from bump back down to floor
    var floor = 0.0         // resting brightness
    var spaceBump = 0.9     // distinct bump for space
    var enterBump = 0.9     // distinct bump for return / keypad enter
    var modifierBump = 0.5  // distinct bump for modifier press

    /// Nil when the theme has no usable reactive section (missing or
    /// disabled): the engine then runs the breathing loop as before.
    init?(forEngine raw: [String: Any]) {
        guard let section = raw["Reactive"] as? [String: Any],
              (section["Enabled"] as? Bool) ?? true else { return nil }
        self.init(section: section)
    }

    /// Parses a section for editing; missing fields keep defaults. Values are
    /// clamped so a hand-edited file cannot drive the backlight out of range.
    init(section: [String: Any] = [:]) {
        if let v = section["Enabled"] as? Bool { enabled = v }
        if let v = section["Bump"] as? Double { bump = min(max(v, 0), 1) }
        if let v = section["Decay Duration"] as? Int { decay = max(v, 0) }
        if let v = section["Floor"] as? Double { floor = min(max(v, 0), 1) }
        if let v = section["Space Bump"] as? Double { spaceBump = min(max(v, 0), 1) }
        if let v = section["Enter Bump"] as? Double { enterBump = min(max(v, 0), 1) }
        if let v = section["Modifier Bump"] as? Double { modifierBump = min(max(v, 0), 1) }
    }

    func dictionary() -> [String: Any] {
        ["Enabled": enabled,
         "Bump": min(max(bump, 0), 1),
         "Decay Duration": max(decay, 0),
         "Floor": min(max(floor, 0), 1),
         "Space Bump": min(max(spaceBump, 0), 1),
         "Enter Bump": min(max(enterBump, 0), 1),
         "Modifier Bump": min(max(modifierBump, 0), 1)]
    }
}

enum ThemeStore {
    /// Loads a theme file validated as JSON; throws on missing or invalid JSON.
    static func rawDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw NSError(domain: "ThemeStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) is not a JSON object."])
        }
        return dict
    }

    /// Basic schema check for imported files. Returns a user-facing problem,
    /// or nil when the dictionary can be loaded as a theme.
    static func validateTheme(_ dict: [String: Any]) -> String? {
        guard let name = dict["Name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "it has no non-empty \"Name\"."
        }
        let animations = dict["Animations"] as? [[String: Any]]
        let reactive = dict["Reactive"] as? [String: Any]
        if animations == nil && reactive == nil {
            return "it has neither an \"Animations\" array nor a \"Reactive\" section."
        }
        let reactiveEnabled = (reactive?["Enabled"] as? Bool) ?? (reactive != nil)
        if (animations?.isEmpty ?? true) && !reactiveEnabled {
            return "it has no animations and typing reactions are not enabled."
        }
        for (index, animation) in (animations ?? []).enumerated() {
            guard let brightness = animation["Brightness"] as? NSNumber else {
                return "animation \(index + 1) has no numeric \"Brightness\"."
            }
            let value = brightness.doubleValue
            guard value >= 0, value <= 1 else {
                return "animation \(index + 1) brightness must be between 0 and 1."
            }
            if let fade = animation["Fade Duration"] as? NSNumber, fade.doubleValue < 0 {
                return "animation \(index + 1) has a negative fade duration."
            }
            if let delay = animation["Delay"] as? NSNumber, delay.doubleValue < 0 {
                return "animation \(index + 1) has a negative delay."
            }
        }
        return nil
    }

    /// Validates and writes atomically. Assumes caller holds the in-memory
    /// copy for rollback; the caller's copy is untouched on failure.
    static func write(_ dict: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(dict) else {
            throw NSError(domain: "ThemeStore", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Theme is not valid JSON."])
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// Creates Pulse.json, a typing-reactive example theme, if missing.
    static func createReactiveExampleIfMissing() {
        let url = AppState.themesDir.appendingPathComponent("Pulse.json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let theme: [String: Any] = [
            "Name": "Pulse (reactive)",
            "Version": "1.0.0",
            "Description": "Lights up on each keypress and fades back down. Runs instead of the breathing loop.",
            "Author": "EthanRDoesMC",
            "Homepage": "",
            "Preview Image URL": " ",
            "Animations": [],
            "Reactive": ReactiveMode().dictionary(),
        ]
        try? ThemeStore.write(theme, to: url)
    }
}
