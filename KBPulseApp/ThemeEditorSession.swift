//
//  ThemeEditorSession.swift
//  KBPulseApp
//
//  Owns the open theme document, file selection, dirty state and file
//  intents. The view renders bindings and asks the session to act.
//

import Foundation

final class ThemeEditorSession: ObservableObject {
    let library: ThemeLibrary

    @Published var theme = Theme()
    @Published private(set) var selection = ""
    @Published private(set) var pendingSelection: String?
    @Published private(set) var themes: [String] = []
    @Published var message: String?

    private var savedSnapshot: Data?
    private let onSaved: (String) -> Void
    private let onFilesChanged: () -> Void

    init(library: ThemeLibrary,
         onSaved: @escaping (String) -> Void = { _ in },
         onFilesChanged: @escaping () -> Void = {}) {
        self.library = library
        self.onSaved = onSaved
        self.onFilesChanged = onFilesChanged
    }

    var validationIssues: [ThemeIssue] {
        theme.validate()
    }

    var validationError: String? {
        validationIssues.first?.description
    }

    /// Compares the document with the last loaded or saved snapshot. An empty
    /// selection is never dirty, so clearing the picker cannot prompt.
    var isDirty: Bool {
        guard !selection.isEmpty else { return false }
        return snapshot(of: theme) != savedSnapshot
    }

    func activate(initial name: String) {
        refresh()
        guard selection.isEmpty else { return }
        if themes.contains(name) {
            load(name)
        } else if let first = themes.first {
            load(first)
        }
    }

    func refresh() {
        themes = library.names()
    }

    func requestSelection(_ name: String) {
        guard name != selection else { return }
        if isDirty {
            pendingSelection = name
        } else {
            load(name)
        }
    }

    func cancelPending() {
        pendingSelection = nil
    }

    func discardPending() {
        let target = pendingSelection
        pendingSelection = nil
        load(target ?? "")
    }

    func load(_ name: String) {
        guard !name.isEmpty else {
            reset()
            return
        }
        do {
            theme = try library.load(name)
            selection = name
            pendingSelection = nil
            savedSnapshot = snapshot(of: theme)
        } catch {
            reset()
            message = error.localizedDescription
        }
    }

    func save() {
        guard !selection.isEmpty else { return }
        if let validationError {
            message = validationError
            return
        }
        do {
            try library.write(theme, name: selection)
            savedSnapshot = snapshot(of: theme)
            onSaved(selection)
            message = "Saved \"\(selection).json\"."
        } catch {
            message = error.localizedDescription
        }
    }

    func create(named rawName: String) {
        let name = clean(rawName)
        if let error = nameError(for: name) {
            message = error
            return
        }
        do {
            try library.write(Theme.newTheme(named: name), name: name)
            reloadAfterChange(selecting: name)
        } catch {
            message = error.localizedDescription
        }
    }

    func duplicate(as rawName: String) {
        let name = clean(rawName)
        guard !selection.isEmpty else { return }
        if let error = nameError(for: name) {
            message = error
            return
        }
        if let validationError {
            message = "Fix this theme before duplicating: \(validationError)"
            return
        }
        var copy = theme
        copy.name = name
        do {
            try library.write(copy, name: name)
            reloadAfterChange(selecting: name)
        } catch {
            message = error.localizedDescription
        }
    }

    func deleteSelected() {
        guard !selection.isEmpty else { return }
        do {
            try library.trash(selection)
        } catch {
            message = "Could not delete \"\(selection).json\": \(error.localizedDescription)"
            return
        }
        onFilesChanged()
        refresh()
        load(themes.first ?? "")
    }

    func importTheme(from source: URL) {
        let name = clean(source.deletingPathExtension().lastPathComponent)
        if let error = nameError(for: name) {
            message = error + " Rename the source file and try again."
            return
        }
        do {
            let imported = try ThemeStore.loadTheme(at: source)
            if let error = imported.validate().first?.description {
                message = "That file is not a valid theme: \(error)"
                return
            }
            try library.importTheme(from: source, name: name)
            reloadAfterChange(selecting: name)
        } catch {
            message = error.localizedDescription
        }
    }

    func export(to url: URL) {
        if let validationError {
            message = validationError
            return
        }
        do {
            try library.write(theme, to: url)
            message = "Exported to \(url.path)."
        } catch {
            message = error.localizedDescription
        }
    }

    /// Validates a prospective file name. APFS is case-insensitive by
    /// default, so collisions are checked the same way.
    func nameError(for rawName: String) -> String? {
        let name = clean(rawName)
        if name.isEmpty { return "Enter a theme name." }
        if name.count > 100 { return "Theme names must be 100 characters or fewer." }
        if name.hasPrefix(".") { return "Theme names cannot start with a period." }
        if name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\")) != nil {
            return "Theme names cannot contain /, :, or \\."
        }
        if name.caseInsensitiveCompare("hooks") == .orderedSame {
            return "\"hooks\" is reserved for hooks.json."
        }
        if library.names().contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return "A theme named \"\(name)\" already exists."
        }
        return nil
    }

    private func reloadAfterChange(selecting name: String) {
        onFilesChanged()
        refresh()
        load(name)
    }

    private func reset() {
        theme = Theme()
        selection = ""
        pendingSelection = nil
        savedSnapshot = nil
    }

    private func clean(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snapshot(of theme: Theme) -> Data? {
        try? JSONSerialization.data(withJSONObject: theme.dictionary(),
                                    options: [.sortedKeys])
    }
}
