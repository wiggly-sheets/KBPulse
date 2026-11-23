//
//  ThemeLibrary.swift
//  KBPulseApp
//
//  One filesystem seam for theme documents. Tests point it at a temporary
//  directory; production points it at Application Support.
//

import Foundation

struct ThemeLibrary {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    func url(for name: String) -> URL {
        root.appendingPathComponent("\(name).json")
    }

    func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != "hooks.json" }
            .map { String($0.dropLast(5)) }
            .sorted()
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    func load(_ name: String) throws -> Theme {
        try ThemeStore.loadTheme(at: url(for: name))
    }

    func write(_ theme: Theme, name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ThemeStore.write(theme, to: url(for: name))
    }

    func write(_ theme: Theme, to url: URL) throws {
        try ThemeStore.write(theme, to: url)
    }

    func importTheme(from source: URL, name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url(for: name))
    }

    func trash(_ name: String) throws {
        try FileManager.default.trashItem(at: url(for: name), resultingItemURL: nil)
    }
}
