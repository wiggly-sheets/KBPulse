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

    /// Parses a section for editing; missing fields keep defaults.
    init(section: [String: Any] = [:]) {
        if let v = section["Enabled"] as? Bool { enabled = v }
        if let v = section["Bump"] as? Double { bump = v }
        if let v = section["Decay Duration"] as? Int { decay = v }
        if let v = section["Floor"] as? Double { floor = v }
        if let v = section["Space Bump"] as? Double { spaceBump = v }
        if let v = section["Enter Bump"] as? Double { enterBump = v }
        if let v = section["Modifier Bump"] as? Double { modifierBump = v }
    }

    func dictionary() -> [String: Any] {
        ["Enabled": enabled, "Bump": bump, "Decay Duration": decay, "Floor": floor,
         "Space Bump": spaceBump, "Enter Bump": enterBump, "Modifier Bump": modifierBump]
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
