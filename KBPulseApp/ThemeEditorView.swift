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

struct ThemesTab: View {
    @ObservedObject var state: AppState
    @StateObject private var session: ThemeEditorSession
    @ObservedObject private var preview: PreviewSession
    @State private var newName = ""
    @State private var showNew = false
    @State private var showDuplicate = false
    @State private var showDelete = false
    @State private var showBrightnessCurve = false

    init(state: AppState) {
        self.state = state
        _session = StateObject(wrappedValue: ThemeEditorSession(
            library: ThemeLibrary(root: AppState.themesDir),
            onSaved: { state.themeEdited($0) },
            onFilesChanged: { state.themeFilesChanged() }
        ))
        _preview = ObservedObject(wrappedValue: state.preview)
    }

    var body: some View {
        Form {
            Section {
                ThemeIdentityCard(theme: session.theme)
            }
            Section("Theme file") {
                Picker("File", selection: Binding(
                    get: { session.selection },
                    set: { session.requestSelection($0) }
                )) {
                    ForEach(session.themes, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("New theme name", text: $newName)
                        .lineLimit(nil)
                    Button("New…") { showNew = true }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .kbGlassButtonStyle()
                    Button("Duplicate") { showDuplicate = true }
                        .disabled(session.selection.isEmpty || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .kbGlassButtonStyle()
                }
                HStack {
                    Button("Import…") { importPanel() }
                        .kbGlassButtonStyle()
                    Button("Export…") { exportPanel() }.disabled(session.selection.isEmpty)
                        .kbGlassButtonStyle()
                    Button("Delete…") { showDelete = true }
                        .disabled(session.selection.isEmpty)
                        .kbGlassButtonStyle()
                    Spacer()
                    Button("Save") { save() }.disabled(session.selection.isEmpty)
                        .kbGlassButtonStyle(prominent: true)
                }
            }
            Section("Details") {
                TextField("Name", text: $session.theme.name)
                TextField("Description", text: $session.theme.comment, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Author", text: $session.theme.author)
                TextField("Version", text: $session.theme.version)
                TextField("Homepage", text: $session.theme.homepage)
                TextField("Preview Image URL", text: $session.theme.previewImageURL)
            }
            Section("Animations") {
                if session.theme.animations.isEmpty {
                    Text("This theme has no animations.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(session.theme.animations.enumerated()), id: \.element.id) { index, _ in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Animation name", text: $session.theme.animations[index].name)
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
                            .disabled(index == session.theme.animations.count - 1)
                            .help("Move animation down")
                            Button(role: .destructive) {
                                session.theme.animations.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete animation")
                        }
                        TextField("Description", text: $session.theme.animations[index].comment, axis: .vertical)
                            .lineLimit(2...5)
                        doubleField("Brightness (0-1)", $session.theme.animations[index].brightness)
                        doubleField("Fade Duration (ms)", $session.theme.animations[index].fadeDuration)
                        doubleField("Delay (ms)", $session.theme.animations[index].delay)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .kbGlassSurface(cornerRadius: 10)
                }
                Button("Add animation") {
                    session.theme.animations.append(Theme.Animation(
                        name: "New Animation", comment: "", brightness: 0.5,
                        fadeDuration: 500, delay: 0
                    ))
                }
                .kbGlassButtonStyle()
                .help("Adds a new animation to the end of the list")
            }
            Section("Live Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(previewButtonTitle) { previewTheme() }
                            .disabled(session.selection.isEmpty
                                      || session.validationError != nil
                                      || isPreviewing)
                            .kbGlassButtonStyle()
                        Button("Show brightness curve") { showBrightnessCurve.toggle() }
                            .kbGlassButtonStyle()
                    }
                    if isPreviewing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Playing preview…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel") { state.cancelPreview() }
                                .kbGlassButtonStyle()
                        }
                    }
                    if case .failed(let message) = preview.state {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if showBrightnessCurve {
                        if session.theme.reactive?.enabled == true && session.theme.animations.isEmpty {
                            Text("Reactive themes have no fixed timeline.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            BrightnessCurveView(animations: session.theme.animations)
                                .frame(height: 150)
                                .padding(.vertical, 8)
                        }
                    }
                    Text("Plays the current editor contents, including unsaved edits, then returns to the selected theme. Animation themes play their full timeline; reactive themes play for 10 seconds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Typing reactions") {
                Toggle("Typing reactions", isOn: Binding(
                    get: { session.theme.reactive != nil },
                    set: { enabled in
                        session.theme.reactive = enabled
                            ? (session.theme.reactive ?? ReactiveMode())
                            : nil
                    }
                ))
                if let reactive = Binding($session.theme.reactive) {
                    Toggle("Enabled", isOn: reactive.enabled)
                    doubleField("Bump (0-1)", reactive.bump)
                    doubleField("Decay Duration (ms)", reactive.decay)
                    doubleField("Resting brightness (0-1)", reactive.floor)
                    doubleField("Space bump (0-1)", reactive.spaceBump)
                    doubleField("Enter bump (0-1)", reactive.enterBump)
                    doubleField("Modifier bump (0-1)", reactive.modifierBump)
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
            if session.theme.reactive != nil {
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
            if let validationError = session.validationError {
                Section("Validation") {
                    Text(validationError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            state.refreshThemes()
            session.activate(initial: state.selectedTheme)
        }
        .onDisappear { state.cancelPreview() }
        .alert("New theme", isPresented: $showNew) {
            TextField("Theme name", text: $newName)
            Button("Create") { session.create(named: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates \(newName.isEmpty ? "a new theme" : "\"\(newName).json\"").")
        }
        .alert("Duplicate theme", isPresented: $showDuplicate) {
            TextField("New theme name", text: $newName)
            Button("Duplicate") { session.duplicate(as: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a copy of \"\(session.selection).json\" named \"\(newName).json\".")
        }
        .alert("Delete theme", isPresented: $showDelete) {
            Button("Move to Trash", role: .destructive) { session.deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move \"\(session.selection).json\" to the Trash? This cannot be undone from KBPulse.")
        }
        .alert("KBPulse", isPresented: Binding(
            get: { session.message != nil },
            set: { if !$0 { session.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.message ?? "")
        }
        .alert("Unsaved changes", isPresented: Binding(
            get: { session.pendingSelection != nil },
            set: { if !$0 { session.cancelPending() } }
        )) {
            Button("Discard Changes", role: .destructive) {
                session.discardPending()
            }
            Button("Cancel", role: .cancel) {
                session.cancelPending()
            }
        } message: {
            Text("You have unsaved edits in \(session.selection). Save or discard them before switching themes.")
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

    // MARK: - Actions

    private func moveAnimation(_ index: Int, by offset: Int) {
        let target = index + offset
        guard session.theme.animations.indices.contains(index),
              session.theme.animations.indices.contains(target) else { return }
        session.theme.animations.swapAt(index, target)
    }

    private func save() {
        // End editing first so the focused field writes its latest text into
        // the document before validation and the write.
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async { [self] in
            session.save()
        }
    }

    // MARK: - File panels

    private func importPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let src = panel.url else { return }
        session.importTheme(from: src)
    }

    private func exportPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = session.selection.isEmpty ? session.theme.name : session.selection
        panel.directoryURL = AppState.themesDir
        guard panel.runModal() == .OK, let url = panel.url else { return }
        session.export(to: url)
    }

    private var isPreviewing: Bool {
        if case .playing = preview.state { return true }
        return false
    }

    private var previewButtonTitle: String {
        session.theme.reactive?.enabled == true ? "Test this theme (10s)" : "Test this theme"
    }

    private func previewTheme() {
        if let validationError = session.validationError {
            session.message = validationError
            return
        }
        state.previewTheme(session.theme)
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

private struct ThemeIdentityCard: View {
    let theme: Theme

    private var previewURL: URL? {
        let trimmed = theme.previewImageURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else {
            return nil
        }
        return url
    }

    private var homepageURL: URL? {
        let trimmed = theme.homepage.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else {
            return nil
        }
        return url
    }

    private var details: [String] {
        [theme.author, theme.version].filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let previewURL {
                AsyncImage(url: previewURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().controlSize(.small)
                    case .failure:
                        placeholder("exclamationmark.triangle")
                    @unknown default:
                        placeholder("photo")
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(theme.name.isEmpty ? "Untitled theme" : theme.name)
                    .font(.title3.bold())
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !theme.comment.isEmpty {
                    Text(theme.comment)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let homepageURL {
                    Button("Open Homepage") { NSWorkspace.shared.open(homepageURL) }
                        .buttonStyle(.link)
                        .help(homepageURL.absoluteString)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func placeholder(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }
}

private struct BrightnessCurveView: View {
    let animations: [Theme.Animation]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let timeline = ThemeTimeline(animations: animations)
            let totalDuration = max(timeline.duration, 1)

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
                    path.move(to: CGPoint(x: 0, y: height))

                    for step in timeline.steps {
                        let fadeX = width * CGFloat(step.fadeEnd) / CGFloat(totalDuration)
                        let y = height * (1 - CGFloat(step.brightness))
                        path.addLine(to: CGPoint(x: fadeX, y: y))

                        let delayX = width * CGFloat(step.endTime) / CGFloat(totalDuration)
                        path.addLine(to: CGPoint(x: delayX, y: y))
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)

                // Key points mark the end of each fade.
                let keyPoints: [(x: CGFloat, y: CGFloat)] = timeline.steps.map { step in
                    (
                        width * CGFloat(step.fadeEnd) / CGFloat(totalDuration),
                        height * (1 - CGFloat(step.brightness))
                    )
                }
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
