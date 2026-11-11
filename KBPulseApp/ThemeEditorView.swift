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
    
    func validate() -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Theme name is required"
        }
        if animations.isEmpty && !hasReactive {
            return "At least one animation or reactive mode is required"
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
            if reactive.bump < 0 || reactive.bump > 1 {
                return "Reactive bump must be 0-1"
            }
            if reactive.decay < 0 {
                return "Reactive decay must be ≥ 0"
            }
            if reactive.floor < 0 || reactive.floor > 1 {
                return "Reactive floor must be 0-1"
            }
        }
        return nil
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
    @State private var showBrightnessCurve = false
    @State private var isDirty = false
    @State private var previousEffectiveTheme: String?
    @State private var previousReactiveMode: ReactiveMode?
    @State private var showDiscardAlert = false
    @State private var pendingSelection = ""

    var body: some View {
        Form {
            Section("Theme file") {
                Picker("File", selection: $selected) {
                    ForEach(state.themes, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("Name for the copy", text: $newName)
                        .lineLimit(nil)
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
                    .lineLimit(nil)
                TextField("Description", text: $doc.comment)
                    .lineLimit(nil)
            }
            Section("Animations") {
                if doc.animations.isEmpty {
                    Text("This theme has no animations.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach($doc.animations) { $anim in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Animation name", text: $anim.name)
                            .font(.headline)
                            .lineLimit(nil)
                        doubleField("Brightness (0-1)", $anim.brightness)
                        intField("Fade Duration (ms)", $anim.fade)
                        intField("Delay (ms)", $anim.delay)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
                }
                Button("Add animation") {
                    doc.animations.append(ThemeDoc.AnimDoc(name: "New Animation", comment: "", brightness: 0.5, fade: 500, delay: 0))
                }
                .buttonStyle(.bordered)
                .help("Adds a new animation to the end of the list")
            }
            Section("Live Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Test this theme (10s)") {
                            let url = AppState.themesDir.appendingPathComponent("\(selected).json")
                            state.engine.stop()
                            let profile = KBPProfile(fileURL: url)
                            let prevTheme = state.effectiveTheme
                            var prevReactive: ReactiveMode?
                            if let prevTheme {
                                let prevURL = AppState.themesDir.appendingPathComponent("\(prevTheme).json")
                                if let raw = try? ThemeStore.rawDictionary(at: prevURL) {
                                    prevReactive = ReactiveMode(forEngine: raw)
                                }
                            }
                            previousEffectiveTheme = prevTheme
                            previousReactiveMode = prevReactive
                            state.engine.start(profile: profile, reactive: doc.reactive.enabled ? doc.reactive : nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [previousEffectiveTheme, previousReactiveMode] in
                                guard let effectiveTheme = previousEffectiveTheme else { return }
                                let url = AppState.themesDir.appendingPathComponent("\(effectiveTheme).json")
                                let raw = (try? ThemeStore.rawDictionary(at: url)) ?? [:]
                                state.engine.start(profile: KBPProfile(fileURL: url), reactive: previousReactiveMode.flatMap { $0 })
                            }
                        }
                        .disabled(selected.isEmpty || (doc.animations.isEmpty && !doc.hasReactive))
                        Button("Show brightness curve") { showBrightnessCurve.toggle() }
                            .buttonStyle(.bordered)
                    }
                    if showBrightnessCurve {
                        BrightnessCurveView(animations: doc.animations)
                            .frame(height: 150)
                            .padding(.vertical, 8)
                    }
                    Text("Temporarily applies the theme for 10 seconds.")
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
                        Text(permissionGranted ? "Granted" : "Required")
                            .foregroundStyle(permissionGranted ? Color.secondary : Color.yellow)
                    }
                    if !permissionGranted {
                        Button("Enable typing reactions") { openAccessibilitySettings() }
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
        .onChange(of: doc.name) { _ in isDirty = true }
        .onReceive(doc.objectWillChange) { _ in isDirty = true }
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
        .alert("Unsaved changes", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                isDirty = false
                loadSelectedForPending()
            }
            Button("Cancel", role: .cancel) {
                selected = pendingSelection.isEmpty ? (doc.name.isEmpty ? "" : doc.name) : pendingSelection
                pendingSelection = ""
            }
        } message: {
            Text("You have unsaved edits in \(doc.name.isEmpty ? selected : doc.name). Save or discard them before switching themes.")
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
        if isDirty {
            pendingSelection = selected
            showDiscardAlert = true
            return
        }
        do {
            try doc.load(from: AppState.themesDir.appendingPathComponent("\(selected).json"))
            isDirty = false
        } catch {
            // Broken file: keep the editor empty rather than risking stale
            // contents of a previously loaded theme being saved on top.
            doc.reset()
            message = error.localizedDescription
            isDirty = false
        }
    }
    
    private func loadSelectedForPending() {
        guard !pendingSelection.isEmpty else { return }
        do {
            try doc.load(from: AppState.themesDir.appendingPathComponent("\(pendingSelection).json"))
            isDirty = false
            selected = pendingSelection
            pendingSelection = ""
        } catch {
            doc.reset()
            message = error.localizedDescription
            isDirty = false
            pendingSelection = ""
        }
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

    private func duplicate() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !selected.isEmpty else { return }
        // Case-insensitive collision check — APFS is case-insensitive by default
        let exists = state.themes.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        guard !exists else {
            message = "A theme named \"\(name)\" already exists."
            return
        }
        var dict = doc.raw
        dict["Name"] = name
        guard !dict.isEmpty else {
            message = "Cannot duplicate a theme that failed to load."
            return
        }
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

    private func openAccessibilitySettings() {
        _ = ReactiveEngine.isAccessibilityGranted(prompt: true) // system prompt + refresh
        if !ReactiveEngine.isAccessibilityGranted(prompt: false), let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        permissionGranted = ReactiveEngine.isAccessibilityGranted(prompt: false)
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
                    var currentTime = 0
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
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
    }
}
