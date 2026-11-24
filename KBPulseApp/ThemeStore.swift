//
//  ThemeStore.swift
//  KBPulseApp
//
//  File I/O for theme documents. Schema rules live in Theme.swift so the
//  editor, importer and CLI-facing checks use the same decoder and validator.
//

import Foundation

enum ThemeLocations {
    static let themesDir: URL = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSHomeDirectory())
        }
        return dir.appendingPathComponent("KBPulse", isDirectory: true)
    }()
}

enum ThemeStore {
    /// Loads a theme file. Throws on missing or invalid JSON.
    static func rawDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw NSError(domain: "ThemeStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) is not a JSON object."])
        }
        return dict
    }

    static func loadTheme(at url: URL) throws -> Theme {
        Theme(dictionary: try rawDictionary(at: url))
    }

    /// First user-facing problem, or nil when the dictionary is a valid theme.
    static func validateTheme(_ dict: [String: Any]) -> String? {
        Theme(dictionary: dict).validate().first?.description
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

    static func write(_ theme: Theme, to url: URL) throws {
        try write(theme.dictionary(), to: url)
    }

    /// Creates Pulse.json, a typing-reactive example theme, if missing.
    static func createReactiveExampleIfMissing(in directory: URL = ThemeLocations.themesDir) {
        let url = directory.appendingPathComponent("Pulse.json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? write(Theme.reactiveExample, to: url)
    }

    /// Creates Yawn.json from the one built-in default theme if missing.
    static func createDefaultYawnIfMissing(in directory: URL = ThemeLocations.themesDir) {
        let url = directory.appendingPathComponent("Yawn.json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? write(Theme.defaultYawn, to: url)
    }

    /// Seeds the starter themes exactly once. A deleted starter stays deleted.
    static func seedInitialThemesIfNeeded(in directory: URL = ThemeLocations.themesDir,
                                          defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "themesSeeded") else { return }
        let names = ThemeLibrary(root: directory).names()
        if names.isEmpty {
            createDefaultYawnIfMissing(in: directory)
            createReactiveExampleIfMissing(in: directory)
        }
        defaults.set(true, forKey: "themesSeeded")
    }
}
