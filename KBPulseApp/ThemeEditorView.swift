//
//  ThemeEditorView.swift
//  KBPulseApp
//
//  Themes tab of the Settings window: edit, duplicate, import and export
//  theme JSON files. Form fields map 1:1 to the KBPProfile/ReactiveMode
//  schema (Name, Description, Brightness, Fade Duration, Delay, Reactive);
//  unknown keys in the file are preserved verbatim through saves.
//

import SwiftUI
import UniformTypeIdentifiers

// Editable model for one theme file. Loaded once per selection; saving
// merges edits back over the raw dictionary, so broken edits simply fail
// validation and the in-memory copy stays intact.
final class ThemeDoc: ObservableObject {
    @Published var name = ""
    @Published var author = ""
    @Published var version = ""
    @Published var homepage = ""
    @Published var previewImageURL = ""
    @Published var comment = ""
    @Published var animations: [AnimDoc] = []
    @Published var hasReactive = false
    @Published var reactive = ReactiveMode()
    private(set) var raw: [String: Any] = [:]

    struct AnimDoc: Identifiable {
        var id = UUID()
        var name = ""
        var comment = ""
        var brightness = 0.0
        var fade = 0
        var delay = 0
    }

    func load(from url: URL) throws {
        let dict = try ThemeStore.rawDictionary(at: url)
        raw = dict
        name = dict["Name"] as? String ?? ""
        author = dict["Author"] as? String ?? ""
        version = dict["Version"] as? String ?? ""
        homepage = dict["Homepage"] as? String ?? ""
        previewImageURL = dict["Preview Image URL"] as? String ?? ""
        comment = dict["Description"] as? String ?? ""
        animations = ((dict["Animations"] as? [[String: Any]]) ?? []).map {
            AnimDoc(name: $0["Name"] as? String ?? "",
                    comment: $0["Description"] as? String ?? "",
                    brightness: $0["Brightness"] as? Double ?? 0,
                    fade: $0["Fade Duration"] as? Int ?? 0,
                    delay: $0["Delay"] as? Int ?? 0)
        }
        if let section = dict["Reactive"] as? [String: Any] {
            hasReactive = true
            reactive = ReactiveMode(section: section)
        } else {
            hasReactive = false
            reactive = ReactiveMode()
        }
    }

    func reset() {
        raw = [:]
        name = ""
        author = ""
        version = ""
        homepage = ""
        previewImageURL = ""
        comment = ""
        animations = []
        hasReactive = false
        reactive = ReactiveMode()
    }

    /// The full JSON for the current editor state, merging edits over the
    /// original file so unknown keys survive. Also used for previews.
    func dictionary() -> [String: Any] {
        var dict = raw
        dict["Name"] = name
        dict["Description"] = comment
        dict["Author"] = author
        dict["Version"] = version
        dict["Homepage"] = homepage
        dict["Preview Image URL"] = previewImageURL
        dict["Animations"] = animations.map {
            ["Name": $0.name, "Description": $0.comment,
             "Brightness": min(max($0.brightness, 0), 1),
             "Fade Duration": max($0.fade, 0),
             "Delay": max($0.delay, 0)] as [String: Any]
        }
        if hasReactive {
            dict["Reactive"] = reactive.dictionary()
        } else {
            dict.removeValue(forKey: "Reactive")
        }
        return dict
    }

    func save(to url: URL) throws {
        try ThemeStore.write(dictionary(), to: url)
    }

    func validate() -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Theme name is required"
        }
        if animations.isEmpty && !(hasReactive && reactive.enabled) {
            return "Add at least one animation, or enable typing reactions."
        }
        for (label, value) in [("Homepage", homepage), ("Preview Image URL", previewImageURL)] {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, URL(string: trimmed)?.scheme == nil {
                return "\(label) must be a valid URL, or empty."
            }
        }
        for (i, anim) in animations.enumerated() {
            if anim.name.trimmingCharacters(in: .whitespaces).isEmpty {
                return "Animation \(i + 1) needs a name"
            }
            if anim.brightness < 0 || anim.brightness > 1 {
                return "Animation \(i + 1) brightness must be 0-1"
            }
            if anim.fade < 0 {
                return "Animation \(i + 1) fade duration must be ≥ 0"
            }
            if anim.delay < 0 {
                return "Animation \(i + 1) delay must be ≥ 0"
            }
        }
        if hasReactive {
            let unitValues: [(String, Double)] = [
                ("Bump", reactive.bump),
                ("Floor", reactive.floor),
                ("Space bump", reactive.spaceBump),
                ("Enter bump", reactive.enterBump),
                ("Modifier bump", reactive.modifierBump),
            ]
            for (label, value) in unitValues where value < 0 || value > 1 {
                return "Reactive \(label.lowercased()) must be 0-1."
            }
            if reactive.decay < 0 {
                return "Reactive decay must be ≥ 0."
            }
        }
        return nil
    }
}

struct ThemesTab: View {
    @ObservedObject var state: AppState
    @StateObject private var doc = ThemeDoc()
    @State private var selected = ""
    @State private var loadedSelection = ""
    @State private var newName = ""
    @State private var showNew = false
    @State private var showDuplicate = false
    @State private var showDelete = false
    @State private var message: String?
    @State private var showBrightnessCurve = false
    @State private var isDirty = false
    @State private var isLoadingDoc = false
    @State private var showDiscardAlert = false
    @State private var pendingSelection = ""

    var body: some View {
        Form {
            Section("Theme file") {
                Picker("File", selection: $selected) {
                    ForEach(state.themes, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("New theme name", text: $newName)
                        .lineLimit(nil)
                    Button("New…") { showNew = true }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .kbGlassButtonStyle()
                    Button("Duplicate") { showDuplicate = true }
                        .disabled(selected.isEmpty || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .kbGlassButtonStyle()
                }
                HStack {
                    Button("Import…") { importPanel() }
                        .kbGlassButtonStyle()
                    Button("Export…") { exportPanel() }.disabled(selected.isEmpty)
                        .kbGlassButtonStyle()
                    Button("Delete…") { showDelete = true }
                        .disabled(selected.isEmpty)
                        .kbGlassButtonStyle()
                    Spacer()
                    Button("Save") { save() }.disabled(selected.isEmpty)
                        .kbGlassButtonStyle(prominent: true)
                }
            }
            Section("Details") {
                TextField("Name", text: $doc.name)
                    .lineLimit(nil)
                TextField("Description", text: $doc.comment)
                    .lineLimit(nil)
                TextField("Author", text: $doc.author)
                    .lineLimit(nil)
                TextField("Version", text: $doc.version)
                    .lineLimit(nil)
                TextField("Homepage", text: $doc.homepage)
                    .lineLimit(nil)
                TextField("Preview Image URL", text: $doc.previewImageURL)
                    .lineLimit(nil)
            }
            Section("Animations") {
                if doc.animations.isEmpty {
                    Text("This theme has no animations.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(doc.animations.enumerated()), id: \.element.id) { index, _ in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Animation name", text: $doc.animations[index].name)
                                .font(.headline)
                                .lineLimit(nil)
                            Spacer()
                            Button {
                                moveAnimation(index, by: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help("Move animation up")
                            Button {
                                moveAnimation(index, by: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == doc.animations.count - 1)
                            .help("Move animation down")
                            Button(role: .destructive) {
                                doc.animations.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete animation")
                        }
                        TextField("Description", text: $doc.animations[index].comment)
                            .lineLimit(nil)
                        doubleField("Brightness (0-1)", $doc.animations[index].brightness)
                        intField("Fade Duration (ms)", $doc.animations[index].fade)
                        intField("Delay (ms)", $doc.animations[index].delay)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .kbGlassSurface(cornerRadius: 10)
                }
                Button("Add animation") {
                    doc.animations.append(ThemeDoc.AnimDoc(name: "New Animation", comment: "", brightness: 0.5, fade: 500, delay: 0))
                }
                .kbGlassButtonStyle()
                .help("Adds a new animation to the end of the list")
            }
            Section("Live Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Test this theme (10s)") { previewTheme() }
                            .disabled(selected.isEmpty || doc.validate() != nil)
                            .kbGlassButtonStyle()
                        Button("Show brightness curve") { showBrightnessCurve.toggle() }
                            .kbGlassButtonStyle()
                    }
                    if showBrightnessCurve {
                        BrightnessCurveView(animations: doc.animations)
                            .frame(height: 150)
                            .padding(.vertical, 8)
                    }
                    Text("Plays the current editor contents, including unsaved edits, for 10 seconds, then returns to the selected theme.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Typing reactions") {
                Toggle("Typing reactions", isOn: $doc.hasReactive)
                if doc.hasReactive {
                    Toggle("Enabled", isOn: $doc.reactive.enabled)
                    doubleField("Bump (0-1)", $doc.reactive.bump)
                    intField("Decay Duration (ms)", $doc.reactive.decay)
                    doubleField("Resting brightness (0-1)", $doc.reactive.floor)
                    doubleField("Space bump (0-1)", $doc.reactive.spaceBump)
                    doubleField("Enter bump (0-1)", $doc.reactive.enterBump)
                    doubleField("Modifier bump (0-1)", $doc.reactive.modifierBump)
                    Text("While enabled, this theme reacts to keystrokes instead of running its animation loop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Reacts to keystrokes instead of running the animation loop. Save removes this section when toggled off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if doc.hasReactive {
                Section("Accessibility permission") {
                    HStack {
                        Text("Keystroke access")
                        Spacer()
                        Text(state.isAccessibilityGranted ? "Granted" : "Required")
                            .foregroundStyle(state.isAccessibilityGranted ? Color.secondary : Color.yellow)
                    }
                    if !state.isAccessibilityGranted {
                        Button("Enable typing reactions") { openAccessibilitySettings() }
                            .kbGlassButtonStyle()
                        Text("Typing-reactive themes need Accessibility permission to observe keystrokes. Without it they rest at zero brightness.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            // Validation status
            if let validationError = doc.validate() {
                Section("Validation") {
                    Text(validationError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        // Programmatic loads also emit objectWillChange; ignore those so
        // loading a file does not immediately mark it dirty.
        .onReceive(doc.objectWillChange) { _ in
            if !isLoadingDoc { isDirty = true }
        }
        .onAppear {
            state.refreshThemes()
            if selected.isEmpty { selected = state.selectedTheme }
            if loadedSelection.isEmpty { loadSelected(selected) }
        }
        .onChange(of: selected) { _, newValue in
            selectionChanged(to: newValue)
        }
        .onDisappear { state.cancelPreview() }
        .alert("New theme", isPresented: $showNew) {
            TextField("Theme name", text: $newName)
            Button("Create") { createNewTheme() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates \(newName.isEmpty ? "a new theme" : "\"\(newName).json\"").")
        }
        .alert("Duplicate theme", isPresented: $showDuplicate) {
            TextField("New theme name", text: $newName)
            Button("Duplicate") { duplicate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a copy of \"\(selected).json\" named \"\(newName).json\".")
        }
        .alert("Delete theme", isPresented: $showDelete) {
            Button("Move to Trash", role: .destructive) { deleteSelectedTheme() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move \"\(selected).json\" to the Trash? This cannot be undone from KBPulse.")
        }
        .alert("KBPulse", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .alert("Unsaved changes", isPresented: $showDiscardAlert) {
            Button("Discard Changes", role: .destructive) {
                discardAndLoadPending()
            }
            Button("Cancel", role: .cancel) {
                selected = loadedSelection
                pendingSelection = ""
            }
        } message: {
            Text("You have unsaved edits in \(loadedSelection.isEmpty ? selected : loadedSelection). Save or discard them before switching themes.")
        }
    }

    // MARK: - Field helpers

    private func doubleField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }

    private func intField(_ label: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.grouping(.never))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    private func loadSelected(_ name: String) {
        guard !name.isEmpty else {
            doc.reset()
            loadedSelection = ""
            isDirty = false
            return
        }
        isLoadingDoc = true
        defer {
            isLoadingDoc = false
            isDirty = false
        }
        do {
            try doc.load(from: AppState.themesDir.appendingPathComponent("\(name).json"))
        } catch {
            // Broken file: keep the editor empty rather than risking stale
            // contents of a previously loaded theme being saved on top.
            doc.reset()
            message = error.localizedDescription
        }
        loadedSelection = name
    }

    private func selectionChanged(to newValue: String) {
        guard newValue != loadedSelection else { return }
        if isDirty {
            pendingSelection = newValue
            selected = loadedSelection
            showDiscardAlert = true
        } else {
            loadSelected(newValue)
        }
    }

    private func discardAndLoadPending() {
        isDirty = false
        let target = pendingSelection
        pendingSelection = ""
        guard !target.isEmpty else {
            selected = loadedSelection
            return
        }
        selected = target
        loadSelected(target)
    }

    private func moveAnimation(_ index: Int, by offset: Int) {
        let target = index + offset
        guard doc.animations.indices.contains(index),
              doc.animations.indices.contains(target) else { return }
        doc.animations.swapAt(index, target)
    }

    private func save() {
        if let validationError = doc.validate() {
            message = validationError
            return
        }
        do {
            try doc.save(to: AppState.themesDir.appendingPathComponent("\(selected).json"))
            state.themeEdited(selected)
            message = "Saved \"\(selected).json\"."
            isDirty = false
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - Creating, duplicating, importing, deleting

    /// Validates a prospective file name. APFS is case-insensitive by
    /// default, so collisions are checked the same way.
    private func nameError(for rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a theme name." }
        if name.count > 100 { return "Theme names must be 100 characters or fewer." }
        if name.hasPrefix(".") { return "Theme names cannot start with a period." }
        if name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\")) != nil {
            return "Theme names cannot contain /, :, or \\."
        }
        if name.caseInsensitiveCompare("hooks") == .orderedSame {
            return "\"hooks\" is reserved for hooks.json."
        }
        if state.themes.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return "A theme named \"\(name)\" already exists."
        }
        return nil
    }

    private func createNewTheme() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = nameError(for: name) {
            message = error
            return
        }
        let theme: [String: Any] = [
            "Name": name,
            "Version": "1.0.0",
            "Description": "",
            "Author": "",
            "Homepage": "",
            "Preview Image URL": "",
            "Animations": [
                ["Name": "Fade In", "Description": "", "Brightness": 1.0,
                 "Fade Duration": 1000, "Delay": 0],
                ["Name": "Fade Out", "Description": "", "Brightness": 0.0,
                 "Fade Duration": 1000, "Delay": 0],
            ],
        ]
        do {
            try ThemeStore.write(theme, to: AppState.themesDir.appendingPathComponent("\(name).json"))
            state.themeFilesChanged()
            isDirty = false
            selected = name
            loadSelected(name)
            newName = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func duplicate() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }
        if let error = nameError(for: name) {
            message = error
            return
        }
        if let validationError = doc.validate() {
            message = "Fix this theme before duplicating: \(validationError)"
            return
        }
        var dict = doc.dictionary()
        dict["Name"] = name
        do {
            try ThemeStore.write(dict, to: AppState.themesDir.appendingPathComponent("\(name).json"))
            state.themeFilesChanged()
            isDirty = false
            selected = name
            loadSelected(name)
            newName = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteSelectedTheme() {
        guard !selected.isEmpty else { return }
        let url = AppState.themesDir.appendingPathComponent("\(selected).json")
        do {
            // Move to the Trash so an accidental click is recoverable.
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            message = "Could not delete \"\(selected).json\": \(error.localizedDescription)"
            return
        }
        isDirty = false
        state.themeFilesChanged()
        let next = state.themes.first ?? ""
        selected = next
        loadSelected(next)
    }

    private func importPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let name = src.deletingPathExtension().lastPathComponent
        if let error = nameError(for: name) {
            message = error + " Rename the source file and try again."
            return
        }
        do {
            let dict = try ThemeStore.rawDictionary(at: src)
            if let themeError = ThemeStore.validateTheme(dict) {
                message = "That file is not a valid theme: \(themeError)"
                return
            }
            try FileManager.default.copyItem(
                at: src,
                to: AppState.themesDir.appendingPathComponent("\(name).json"))
            state.themeFilesChanged()
            isDirty = false
            selected = name
            loadSelected(name)
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = selected.isEmpty ? doc.name : selected
        panel.directoryURL = AppState.themesDir
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let validationError = doc.validate() {
            message = validationError
            return
        }
        do {
            // Exports the current in-editor state, including unsaved edits.
            try doc.save(to: url)
            message = "Exported to \(url.path)."
        } catch {
            message = error.localizedDescription
        }
    }

    private func previewTheme() {
        if let validationError = doc.validate() {
            message = validationError
            return
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("KBPulsePreview-\(UUID().uuidString).json")
        do {
            try ThemeStore.write(doc.dictionary(), to: temp)
        } catch {
            message = error.localizedDescription
            return
        }
        let reactive: ReactiveMode? = (doc.hasReactive && doc.reactive.enabled) ? doc.reactive : nil
        state.previewTheme(fileURL: temp, reactive: reactive)
    }

    private func openAccessibilitySettings() {
        _ = ReactiveEngine.isAccessibilityGranted(prompt: true) // system prompt
        state.updateAccessibilityStatus()
        if !state.isAccessibilityGranted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct BrightnessCurveView: View {
    let animations: [ThemeDoc.AnimDoc]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let totalDuration = max(animations.reduce(0) { $0 + $1.fade + $1.delay }, 1)
            
            ZStack {
                // Background grid
                Path { path in
                    for i in 0...4 {
                        let y = height * CGFloat(i) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    for i in 0...10 {
                        let x = width * CGFloat(i) / 10
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)

                // Brightness curve
                Path { path in
                    var x: CGFloat = 0
                    var y = height * (1 - CGFloat(animations.first?.brightness ?? 0))
                    path.move(to: CGPoint(x: x, y: y))

                    for anim in animations {
                        // Delay segment (flat)
                        if anim.delay > 0 {
                            let delayX = width * CGFloat(anim.delay) / CGFloat(totalDuration)
                            x += delayX
                            path.addLine(to: CGPoint(x: x, y: y))
                        }

                        // Fade segment (ramp to brightness)
                        if anim.fade > 0 {
                            let fadeX = width * CGFloat(anim.fade) / CGFloat(totalDuration)
                            x += fadeX
                            y = height * (1 - CGFloat(anim.brightness))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)

                // Key points
                let keyPoints: [(x: CGFloat, y: CGFloat)] = {
                    var points: [(CGFloat, CGFloat)] = []
                    var currentTime = 0
                    for i in animations.indices {
                        let anim = animations[i]
                        var x: CGFloat = 0
                        for j in 0..<i {
                            currentTime += animations[j].delay + animations[j].fade
                        }
                        currentTime += anim.delay
                        x = width * CGFloat(currentTime) / CGFloat(totalDuration)
                        let y = height * (1 - CGFloat(anim.brightness))
                        points.append((x, y))
                    }
                    return points
                }()
                ForEach(keyPoints.indices, id: \.self) { i in
                    let point = keyPoints[i]
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .position(x: point.x, y: point.y)
                }
            }
        }
        .kbGlassSurface(cornerRadius: 8)
    }
}
