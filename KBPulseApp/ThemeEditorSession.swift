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
    @Published private(set) var displayNames: [String: String] = [:]
    @Published var message: String?

    private var savedSnapshot: Data?
    private let onSaved: (String, String?) -> Void
    private let onFilesChanged: () -> Void

    init(library: ThemeLibrary,
         onSaved: @escaping (String, String?) -> Void = { _, _ in },
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

    /// Registers one undoable structural edit. Text editing keeps its own
    /// native undo through the window's undo manager.
    func performStructuralEdit(named actionName: String,
                               undoManager: UndoManager?,
                               _ edit: () -> Void) {
        let before = theme
        edit()
        let after = theme
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.theme = before
            undoManager.registerUndo(withTarget: target) { target in
                target.theme = after
            }
            undoManager.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
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
        displayNames = themes.reduce(into: [:]) { result, name in
            let theme = try? library.load(name)
            let display = theme?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            result[name] = display.isEmpty ? name : display
        }
    }

    func displayName(for name: String) -> String {
        if name == selection {
            let display = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return display.isEmpty ? name : display
        }
        return displayNames[name] ?? name
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
        let requestedName = clean(theme.name)
        if let error = nameError(for: requestedName, excluding: selection) {
            message = error
            return
        }
        do {
            let previousName = selection
            let renamed = requestedName != previousName
            if renamed {
                try library.replace(previousName, with: theme, renamedTo: requestedName)
            } else {
                try library.write(theme, name: previousName)
            }
            selection = requestedName
            refresh()
            savedSnapshot = snapshot(of: theme)
            onSaved(selection, renamed ? previousName : nil)
            message = "Saved \"\(selection).json\"."
        } catch {
            message = error.localizedDescription
        }
    }

    func create(named rawName: String, template: ThemeTemplate = .fade) {
        let name = clean(rawName)
        if let error = nameError(for: name) {
            message = error
            return
        }
        do {
            try library.write(template.theme(named: name), name: name)
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
        deleteTheme(named: selection)
    }

    func deleteTheme(named name: String, undoManager: UndoManager? = nil) {
        let deleted: Theme
        do {
            deleted = try library.load(name)
            try library.trash(name)
        } catch {
            message = "Could not delete \"\(name).json\": \(error.localizedDescription)"
            return
        }
        undoManager?.registerUndo(withTarget: self) { target in
            if !target.library.exists(name) {
                do {
                    try target.library.write(deleted, name: name)
                } catch {
                    target.message = "Could not restore \"\(name).json\": \(error.localizedDescription)"
                    return
                }
            }
            target.onFilesChanged()
            target.refresh()
            target.load(name)
            undoManager?.registerUndo(withTarget: target) { target in
                target.deleteTheme(named: name, undoManager: undoManager)
            }
            undoManager?.setActionName("Delete Theme")
        }
        undoManager?.setActionName("Delete Theme")
        onFilesChanged()
        refresh()
        if selection == name {
            load(themes.first ?? "")
        }
    }

    func duplicateTheme(named name: String) {
        guard !isDirty else {
            message = "Save or discard changes before duplicating another theme."
            return
        }
        do {
            var copy = try library.load(name)
            let newName = uniqueCopyName(for: displayName(for: name))
            copy.name = newName
            try library.write(copy, name: newName)
            reloadAfterChange(selecting: newName)
        } catch {
            message = error.localizedDescription
        }
    }

    private func uniqueCopyName(for base: String) -> String {
        let existing = Set(library.names().map { $0.lowercased() })
        var candidate = "\(base) Copy"
        var number = 2
        while existing.contains(candidate.lowercased()) {
            candidate = "\(base) Copy \(number)"
            number += 1
        }
        return candidate
    }

    func installBundled(_ bundled: BundledTheme) {
        if isDirty {
            message = "Save or discard your current edits before adding a bundled theme."
            return
        }
        let name = clean(bundled.theme.name)
        if let error = nameError(for: name) {
            message = error
            return
        }
        do {
            try library.write(bundled.theme, name: name)
            reloadAfterChange(selecting: name)
        } catch {
            message = error.localizedDescription
        }
    }

    func importTheme(from source: URL) {
        let name = clean(source.deletingPathExtension().lastPathComponent)
        if let error = nameError(for: name) {
            message = error + " Rename the source file and try again."
            return
        }
        do {
            let imported = try ThemeStore.loadTheme(at: source)
            let issues = imported.validate()
            guard issues.isEmpty else {
                let details = issues.map(\.description).joined(separator: "\n")
                message = "That file is not a valid theme:\n\(details)"
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
    func nameError(for rawName: String, excluding current: String? = nil) -> String? {
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
        let otherNames = library.names().filter { $0 != current }
        if otherNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
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
