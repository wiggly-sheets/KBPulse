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

    func save(to url: URL) throws {
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
        try ThemeStore.write(dict, to: url)
    }
}

struct ThemesTab: View {
    @ObservedObject var state: AppState
    @StateObject private var doc = ThemeDoc()
    @State private var selected = ""
    @State private var newName = ""
    @State private var showDuplicate = false
    @State private var message: String?
    @State private var permissionGranted = ReactiveEngine.isAccessibilityGranted(prompt: false)

    var body: some View {
        Form {
            Section("Theme file") {
                Picker("File", selection: $selected) {
                    ForEach(state.themes, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("Name for the copy", text: $newName)
                    Button("Duplicate") { showDuplicate = true }
                        .disabled(selected.isEmpty || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Button("Import…") { importPanel() }
                    Button("Export…") { exportPanel() }.disabled(selected.isEmpty)
                    Spacer()
                    Button("Save") { save() }.disabled(selected.isEmpty)
                }
            }
            Section("Details") {
                TextField("Name", text: $doc.name)
                TextField("Description", text: $doc.comment)
            }
            Section("Animations") {
                if doc.animations.isEmpty {
                    Text("This theme has no animations.").foregroundColor(.secondary)
                }
                ForEach($doc.animations) { $anim in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Animation name", text: $anim.name).font(.headline)
                        doubleField("Brightness", $anim.brightness)
                        intField("Fade Duration (ms)", $anim.fade)
                        intField("Delay (ms)", $anim.delay)
                    }
                    .padding(.vertical, 2)
                }
            }
            Section("Preview") {
                Button("Test this theme (10s)") {
                    let url = AppState.themesDir.appendingPathComponent("\(selected).json")
                    state.engine.stop()
                    let profile = KBPProfile(fileURL: url)
                    state.engine.start(profile: profile, reactive: doc.reactive.enabled ? doc.reactive : nil)
                }
                .disabled(selected.isEmpty || doc.animations.isEmpty)
                Text("Temporarily applies the theme for 10 seconds.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Section("Typing reactions") {
                Toggle("Typing reactions", isOn: $doc.hasReactive)
                if doc.hasReactive {
                    Toggle("Enabled", isOn: $doc.reactive.enabled)
                    doubleField("Bump", $doc.reactive.bump)
                    intField("Decay Duration (ms)", $doc.reactive.decay)
                    doubleField("Resting brightness", $doc.reactive.floor)
                    doubleField("Space bump", $doc.reactive.spaceBump)
                    doubleField("Enter bump", $doc.reactive.enterBump)
                    doubleField("Modifier bump", $doc.reactive.modifierBump)
                    Text("While enabled, this theme reacts to keystrokes instead of running its animation loop.")
                        .font(.footnote).foregroundColor(.secondary)
                } else {
                    Text("Reacts to keystrokes instead of running the animation loop. Save removes this section when toggled off.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            if doc.hasReactive {
                Section("Accessibility permission") {
                    HStack {
                        Text("Keystroke access")
                        Spacer()
                        Text(permissionGranted ? "Granted" : "Required")
                            .foregroundColor(permissionGranted ? .secondary : .orange)
                    }
                    if !permissionGranted {
                        Button("Enable typing reactions") { openAccessibilitySettings() }
                        Text("Typing-reactive themes need Accessibility permission to observe keystrokes. Without it they rest at zero brightness.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if selected.isEmpty { selected = state.selectedTheme }
            loadSelected()
            permissionGranted = ReactiveEngine.isAccessibilityGranted(prompt: false)
        }
        .onChange(of: selected) { _ in loadSelected() }
        .alert("Duplicate theme", isPresented: $showDuplicate) {
            TextField("New theme name", text: $newName)
            Button("Duplicate") { duplicate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a copy of \"\(selected).json\" named \"\(newName).json\".")
        }
        .alert("KBPulse", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
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

    private func loadSelected() {
        guard !selected.isEmpty else { return }
        do {
            try doc.load(from: AppState.themesDir.appendingPathComponent("\(selected).json"))
        } catch {
            // Broken file: keep the editor empty rather than risking stale
            // contents of a previously loaded theme being saved on top.
            doc.reset()
            message = error.localizedDescription
        }
    }

    private func save() {
        do {
            try doc.save(to: AppState.themesDir.appendingPathComponent("\(selected).json"))
            state.themeEdited(selected)
            message = "Saved \"\(selected).json\"."
        } catch {
            message = error.localizedDescription
        }
    }

    private func duplicate() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !selected.isEmpty else { return }
        guard !state.themes.contains(name) else {
            message = "A theme named \"\(name)\" already exists."
            return
        }
        var dict = doc.raw
        dict["Name"] = name
        do {
            try ThemeStore.write(dict, to: AppState.themesDir.appendingPathComponent("\(name).json"))
            state.refreshThemes()
            selected = name
        } catch {
            message = error.localizedDescription
        }
    }

    private func importPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let src = panel.url else { return }
        let name = src.deletingPathExtension().lastPathComponent
        guard !state.themes.contains(name) else {
            message = "A theme named \"\(name)\" already exists. Rename the source file and try again."
            return
        }
        do {
            try FileManager.default.copyItem(at: src, to: AppState.themesDir.appendingPathComponent("\(name).json"))
            state.refreshThemes()
            selected = name
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = selected.isEmpty ? doc.name : selected
        panel.directoryURL = AppState.themesDir
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Exports the current in-editor state, including unsaved edits.
            try doc.save(to: url)
            message = "Exported to \(url.path)."
        } catch {
            message = error.localizedDescription
        }
    }

    private func openAccessibilitySettings() {
        _ = ReactiveEngine.isAccessibilityGranted(prompt: true) // system prompt + refresh
        if !ReactiveEngine.isAccessibilityGranted(prompt: false), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        permissionGranted = ReactiveEngine.isAccessibilityGranted(prompt: false)
    }
}
