//
//  ThemeEditorView.swift
//  KBPulseApp
//
//  Themes tab of the Settings window: edit, duplicate, import and export
//  theme JSON files. Form fields map 1:1 to the Theme/ReactiveMode
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
    @State private var showNewSheet = false
    @State private var showDuplicate = false
    @State private var deleteTarget: String?
    @State private var detailSection: DetailSection = .design
    @Environment(\.undoManager) private var undoManager
    @State private var searchText = ""
    @State private var isDropTargeted = false

    init(state: AppState) {
        self.state = state
        _session = StateObject(wrappedValue: ThemeEditorSession(
            library: ThemeLibrary(root: AppState.themesDir),
            onSaved: { name, oldName in
                if let oldName {
                    state.themeRenamed(from: oldName, to: name)
                } else {
                    state.themeEdited(name)
                }
            },
            onFilesChanged: { state.themeFilesChanged() }
        ))
        _preview = ObservedObject(wrappedValue: state.preview)
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
            detail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            state.refreshThemes()
            session.activate(initial: state.selectedTheme)
        }
        .onDisappear { state.cancelPreview() }
        .sheet(isPresented: $showNewSheet) {
            NewThemeSheet { name, template in
                session.create(named: name, template: template)
                showNewSheet = false
            } onCancel: {
                showNewSheet = false
            }
        }
        .alert("Duplicate theme", isPresented: $showDuplicate) {
            TextField("New theme name", text: $newName)
            Button("Duplicate") { session.duplicate(as: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a copy of \"\(session.selection).json\" named \"\(newName).json\".")
        }
        .alert("Delete theme", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Move to Trash", role: .destructive) {
                if let target = deleteTarget {
                    session.deleteTheme(named: target, undoManager: undoManager)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Move \"\(deleteTarget ?? "").json\" to the Trash? This cannot be undone from KBPulse.")
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

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search themes", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if session.themes.isEmpty {
                ContentUnavailableView(
                    "No Themes",
                    systemImage: "paintpalette",
                    description: Text("Create or import a theme to start editing.")
                )
            } else if visibleThemes.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: selectionBinding) {
                    ForEach(visibleThemes, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: "paintpalette")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.displayName(for: name))
                                    .lineLimit(1)
                                if session.displayName(for: name) != name {
                                    Text(name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            if name == state.selectedTheme {
                                Image(systemName: "keyboard")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help("Active theme")
                            }
                            if name == session.selection && session.isDirty {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 6, height: 6)
                                    .help("Unsaved changes")
                            }
                        }
                        .tag(name)
                        .contextMenu {
                            Button("Activate") { state.selectTheme(name) }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([
                                    session.library.url(for: name),
                                ])
                            }
                            Divider()
                            Button("Duplicate") { session.duplicateTheme(named: name) }
                            Button("Delete…", role: .destructive) { deleteTarget = name }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            HStack {
                Menu {
                    Button("New Theme…") { beginNew() }
                    Button("Import Theme…") { importPanel() }
                } label: {
                    Label("Add Theme", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .dropDestination(for: URL.self) { urls, _ in
            importDropped(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var visibleThemes: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return session.themes }
        return session.themes.filter { name in
            session.displayName(for: name).localizedCaseInsensitiveContains(query)
                || name.localizedCaseInsensitiveContains(query)
        }
    }

    private func importDropped(_ urls: [URL]) -> Bool {
        let files = urls.filter { $0.pathExtension.lowercased() == "json" }
        guard !files.isEmpty else { return false }
        for file in files {
            session.importTheme(from: file)
        }
        return true
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { session.selection.isEmpty ? nil : session.selection },
            set: { name in
                guard let name, name != session.selection else { return }
                session.requestSelection(name)
            }
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if session.selection.isEmpty {
            ContentUnavailableView(
                "Choose a Theme",
                systemImage: "paintpalette",
                description: Text("Select a theme in the sidebar, or add a new one.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    Picker("Section", selection: $detailSection) {
                        ForEach(DetailSection.allCases) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if detailSection == .info {
                Section {
                    ThemeIdentityCard(theme: session.theme)
                }
                Section("Details") {
                    TextField("Name", text: $session.theme.name)
                    if let issue = issue("Name") { InlineIssue(issue: issue) }
                    TextField("Description", text: $session.theme.comment, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Author", text: $session.theme.author)
                    TextField("Version", text: $session.theme.version)
                    TextField("Homepage", text: $session.theme.homepage)
                    if let issue = issue("Homepage") { InlineIssue(issue: issue) }
                    TextField("Preview Image URL", text: $session.theme.previewImageURL)
                    if let issue = issue("Preview Image URL") { InlineIssue(issue: issue) }
                }
                }
                if detailSection == .design {
                Section("Animations") {
                    if let issue = issue("Animations") { InlineIssue(issue: issue) }
                    if session.theme.animations.isEmpty {
                        Text("This theme has no animations.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(session.theme.animations.enumerated()), id: \.element.id) { index, _ in
                        AnimationEditorCard(
                            animation: $session.theme.animations[index],
                            canMoveUp: index > 0,
                            canMoveDown: index < session.theme.animations.count - 1,
                            onMoveUp: { moveAnimation(index, by: -1) },
                            onMoveDown: { moveAnimation(index, by: 1) },
                            onDuplicate: { duplicateAnimation(index) },
                            onInsertAfter: { insertAnimation(after: index) },
                            onDelete: {
                                session.performStructuralEdit(named: "Delete Animation", undoManager: undoManager) {
                                    session.theme.animations.remove(at: index)
                                }
                            },
                            issues: animationIssues(index),
                            onDropAnimation: { id in
                                moveAnimation(id: id, onto: index)
                                return true
                            }
                        )
                    }
                    Button("Add Animation") {
                        session.performStructuralEdit(named: "Add Animation", undoManager: undoManager) {
                            session.theme.animations.append(Theme.Animation(
                                name: "New Animation", comment: "", brightness: 0.5,
                                fadeDuration: 500, delay: 0
                            ))
                        }
                    }
                    .kbGlassButtonStyle()
                    .help("Adds a new animation to the end of the list")
                }
                Section("Haptics") {
                    Toggle("Haptics for this theme", isOn: $session.theme.haptics)
                    Text("Taps the trackpad at each animation beat or typing bump. Only plays when the global Trackpad haptics switch is on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Live Preview") {
                    if !session.validationIssues.isEmpty {
                        Text("Preview is blocked until the highlighted issues are fixed.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
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
                    if session.theme.reactive?.enabled == true && session.theme.animations.isEmpty {
                        Text("Reactive themes have no fixed timeline.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        BrightnessCurveView(animations: session.theme.animations)
                            .frame(height: 150)
                            .padding(.vertical, 4)
                    }
                    Text("Preview plays the current editor contents, including unsaved edits, then returns to the active theme. Animation themes play their full timeline; reactive themes play for 10 seconds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                }
                if detailSection == .reactions {
                Section("Typing Reactions") {
                    Toggle("Typing reactions", isOn: Binding(
                        get: { session.theme.reactive != nil },
                        set: { enabled in
                            session.theme.reactive = enabled
                                ? (session.theme.reactive ?? ReactiveMode())
                                : nil
                        }
                    ))
                    if session.theme.reactive != nil {
                        Toggle("Enabled", isOn: reactiveBinding(\.enabled, default: true))
                        UnitSlider(label: "Bump", value: reactiveBinding(\.bump, default: 0.7))
                        UnitSlider(label: "Resting brightness", value: reactiveBinding(\.floor, default: 0))
                        MillisecondSlider(label: "Decay duration", value: reactiveBinding(\.decay, default: 400))
                        DisclosureGroup("Key amounts") {
                            UnitSlider(label: "Space", value: reactiveBinding(\.spaceBump, default: 0.9))
                            UnitSlider(label: "Enter", value: reactiveBinding(\.enterBump, default: 0.9))
                            UnitSlider(label: "Modifier", value: reactiveBinding(\.modifierBump, default: 0.5))
                        }
                        ReactionCurveView(reactive: $session.theme.reactive)
                        ForEach(reactionIssues, id: \.description) { issue in
                            InlineIssue(issue: issue)
                        }
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
                }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .top, spacing: 0) { detailHeader }
        }
    }

    private var detailHeader: some View {
        let displayName = session.displayName(for: session.selection)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                if displayName != session.selection {
                    Text(session.selection)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if session.isDirty {
                Text("Edited")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !session.validationIssues.isEmpty {
                Text("\(session.validationIssues.count) issue\(session.validationIssues.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                previewTheme()
            } label: {
                Label("Preview", systemImage: "play.fill")
            }
            .disabled(session.validationError != nil || isPreviewing)
            .kbGlassButtonStyle()
            Menu {
                Button("Undo") { undoManager?.undo() }
                    .disabled(!(undoManager?.canUndo ?? false))
                Button("Redo") { undoManager?.redo() }
                    .disabled(!(undoManager?.canRedo ?? false))
                Divider()
                Button("Duplicate…") { beginDuplicate() }
                Button("Export…") { exportPanel() }
                Divider()
                Button("Delete…", role: .destructive) { deleteTarget = session.selection }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Theme actions")
            Button("Save") { save() }
                .disabled(!session.isDirty)
                .keyboardShortcut("s", modifiers: .command)
                .kbGlassButtonStyle(prominent: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func reactiveBinding<T>(_ keyPath: WritableKeyPath<ReactiveMode, T>,
                                   default defaultValue: T) -> Binding<T> {
        Binding(
            get: { session.theme.reactive?[keyPath: keyPath] ?? defaultValue },
            set: { session.theme.reactive?[keyPath: keyPath] = $0 }
        )
    }

    private func issue(_ path: String) -> ThemeIssue? {
        session.validationIssues.first { $0.path == path }
    }

    private func animationIssues(_ index: Int) -> [ThemeIssue] {
        session.validationIssues.filter { $0.path == "Animations[\(index)]" }
    }

    private var reactionIssues: [ThemeIssue] {
        session.validationIssues.filter { $0.path == "Reactive" }
    }

    private func beginNew() {
        showNewSheet = true
    }

    private func beginDuplicate() {
        newName = "\(session.selection) Copy"
        showDuplicate = true
    }

    private func moveAnimation(_ index: Int, by offset: Int) {
        let target = index + offset
        guard session.theme.animations.indices.contains(index),
              session.theme.animations.indices.contains(target) else { return }
        session.performStructuralEdit(named: "Move Animation", undoManager: undoManager) {
            session.theme.animations.swapAt(index, target)
        }
    }

    private func duplicateAnimation(_ index: Int) {
        guard session.theme.animations.indices.contains(index) else { return }
        let source = session.theme.animations[index]
        let copy = Theme.Animation(
            name: source.name.isEmpty ? "Animation Copy" : "\(source.name) Copy",
            comment: source.comment,
            brightness: source.brightness,
            fadeDuration: source.fadeDuration,
            delay: source.delay,
            unknown: source.unknown,
            present: source.present
        )
        session.performStructuralEdit(named: "Duplicate Animation", undoManager: undoManager) {
            session.theme.animations.insert(copy, at: index + 1)
        }
    }

    private func insertAnimation(after index: Int) {
        guard session.theme.animations.indices.contains(index) else { return }
        session.performStructuralEdit(named: "Insert Animation", undoManager: undoManager) {
            session.theme.animations.insert(
                Theme.Animation(name: "New Animation", comment: "", brightness: 0.5,
                                fadeDuration: 500, delay: 0),
                at: index + 1
            )
        }
    }

    private func moveAnimation(id: UUID, onto index: Int) {
        guard let source = session.theme.animations.firstIndex(where: { $0.id == id }),
              source != index else { return }
        session.performStructuralEdit(named: "Move Animation", undoManager: undoManager) {
            let animation = session.theme.animations.remove(at: source)
            let target = source < index ? index - 1 : index
            session.theme.animations.insert(animation, at: max(0, min(target, session.theme.animations.count)))
        }
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

private struct NewThemeSheet: View {
    let onCreate: (String, ThemeTemplate) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var template: ThemeTemplate = .fade
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Theme")
                    .font(.title2.bold())
                Text("Pick a starting point. You can edit every field after creating it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("Theme name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)

            VStack(alignment: .leading, spacing: 8) {
                Text("Template")
                    .font(.headline)
                Picker("Template", selection: $template) {
                    ForEach(ThemeTemplate.allCases) { template in
                        Label(template.title, systemImage: template.systemImage)
                            .tag(template)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(template.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if template == .reactive {
                    Label("Keystroke-driven", systemImage: "keyboard")
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    BrightnessCurveView(animations: template.theme(named: trimmedName).animations)
                        .frame(height: 64)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onCreate(trimmedName, template)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { nameFocused = true }
    }
}

private struct AnimationEditorCard: View {
    @Binding var animation: Theme.Animation
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDuplicate: () -> Void
    let onInsertAfter: () -> Void
    let onDelete: () -> Void
    let issues: [ThemeIssue]
    let onDropAnimation: (UUID) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .help("Drag to reorder")
                    .draggable(animation.id.uuidString)
                TextField("", text: $animation.name, prompt: Text("Animation name"))
                    .labelsHidden()
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help("Move animation up")
                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help("Move animation down")
                Menu {
                    Button("Duplicate") { onDuplicate() }
                    Button("Insert After") { onInsertAfter() }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Animation actions")
            }
            AnimationTimelineStrip(animation: animation)
            TextField("Description", text: $animation.comment, axis: .vertical)
                .lineLimit(2...4)
            UnitSlider(label: "Brightness", value: $animation.brightness)
            HStack(spacing: 16) {
                MillisecondField(label: "Fade", value: $animation.fadeDuration)
                MillisecondField(label: "Hold after fade", value: $animation.delay)
            }
            ForEach(issues, id: \.description) { issue in
                InlineIssue(issue: issue)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .kbGlassSurface(cornerRadius: 10)
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let id = UUID(uuidString: first) else { return false }
            return onDropAnimation(id)
        }
    }
}

private struct InlineIssue: View {
    let issue: ThemeIssue

    var body: some View {
        Label(issue.message, systemImage: "exclamationmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct UnitSlider: View {
    let label: String
    @Binding var value: Double

    private var percent: Binding<Int> {
        Binding(
            get: { Int((value * 100).rounded()) },
            set: { value = min(max(Double($0) / 100, 0), 1) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                Spacer()
                TextField("", value: percent, format: .number)
                    .labelsHidden()
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...1)
        }
    }
}

private struct MillisecondField: View {
    let label: String
    @Binding var value: Double

    private let presets: [Double] = [0, 100, 250, 500, 1000, 2500]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Menu {
                ForEach(presets, id: \.self) { preset in
                    Button("\(Int(preset)) ms") { value = preset }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(label)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose a duration preset")
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .labelsHidden()
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
                Text("ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("", value: $value, in: 0...60000, step: 50)
                    .labelsHidden()
            }
        }
    }
}

private struct MillisecondSlider: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value.rounded())) ms")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...5000, step: 25)
        }
    }
}

private struct AnimationTimelineStrip: View {
    let animation: Theme.Animation

    var body: some View {
        GeometryReader { geometry in
            let total = max(animation.fadeDuration + animation.delay, 1)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35 + 0.65 * min(max(animation.brightness, 0), 1)))
                    .frame(width: geometry.size.width * CGFloat(animation.fadeDuration / total))
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: geometry.size.width * CGFloat(animation.delay / total))
            }
            .clipShape(Capsule())
            .background(Capsule().fill(.quaternary))
        }
        .frame(height: 8)
        .help("Accent is fade; gray is hold after fade. Opacity reflects target brightness.")
    }
}

private struct ReactionCurveView: View {
    @Binding var reactive: ReactiveMode?
    @State private var testLabel: String?
    @State private var testProgress = 0.0
    @State private var testTask: Task<Void, Never>?
    @State private var activeBumpLabel: String?

    private var current: ReactiveMode { reactive ?? ReactiveMode() }

    private var entries: [(label: String, value: Double, color: Color)] {
        [
            ("Space", current.spaceBump, .blue),
            ("Enter", current.enterBump, .green),
            ("Modifier", current.modifierBump, .orange),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let floor = clamped(current.floor)
                let floorY = height * (1 - CGFloat(floor))
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: floorY))
                        path.addLine(to: CGPoint(x: width, y: floorY))
                    }
                    .stroke(Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    ForEach(entries.indices, id: \.self) { index in
                        let entry = entries[index]
                        let top = min(1, floor + max(entry.value, 0))
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: height * (1 - CGFloat(top))))
                            path.addLine(to: CGPoint(x: width, y: floorY))
                        }
                        .stroke(entry.color, lineWidth: 2)

                        Circle()
                            .fill(entry.color)
                            .frame(width: 12, height: 12)
                            .position(x: 8 + CGFloat(index) * 12,
                                      y: height * (1 - CGFloat(top)))
                    }

                    if let testLabel,
                       let entry = entries.first(where: { $0.label == testLabel }) {
                        let top = min(1, floor + max(entry.value, 0))
                        let value = top + (floor - top) * testProgress
                        Circle()
                            .fill(entry.color)
                            .frame(width: 7, height: 7)
                            .position(x: width * testProgress,
                                      y: height * (1 - CGFloat(value)))
                    }
                }
                .coordinateSpace(name: "reaction-curve")
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0,
                                coordinateSpace: .named("reaction-curve"))
                        .onChanged { value in
                            if activeBumpLabel == nil {
                                activeBumpLabel = nearestEntry(to: value.startLocation,
                                                               size: geometry.size).label
                            }
                            guard let activeBumpLabel else { return }
                            let fraction = Double(value.location.y / height)
                            updateBump(activeBumpLabel,
                                       to: ReactiveMode.bump(forVerticalFraction: fraction,
                                                             floor: floor))
                        }
                        .onEnded { _ in activeBumpLabel = nil }
                )
            }
            .frame(height: 80)
            .kbGlassSurface(cornerRadius: 8)

            HStack(spacing: 12) {
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    Label(entry.label, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(entry.color)
                }
                Spacer()
                Text("\(Int(current.decay.rounded())) ms decay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    Button("Test \(entry.label)") { runTest(entry) }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
                Spacer()
            }

            Text("Drag an endpoint to set its bump. Test simulates one keystroke.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func nearestEntry(to point: CGPoint, size: CGSize) -> (label: String, value: Double, color: Color) {
        let floor = clamped(current.floor)
        let closest = entries.enumerated().min { lhs, rhs in
            distance(lhs.element, index: lhs.offset, from: point, floor: floor, height: size.height)
                < distance(rhs.element, index: rhs.offset, from: point, floor: floor, height: size.height)
        }
        return closest?.element ?? entries[0]
    }

    private func distance(_ entry: (label: String, value: Double, color: Color),
                          index: Int,
                          from point: CGPoint,
                          floor: Double,
                          height: CGFloat) -> CGFloat {
        let top = min(1, floor + max(entry.value, 0))
        let x = 8 + CGFloat(index) * 12
        let y = height * (1 - CGFloat(top))
        return hypot(point.x - x, point.y - y)
    }

    private func updateBump(_ label: String, to value: Double) {
        guard var updated = reactive else { return }
        let bump = clamped(value)
        switch label {
        case "Space": updated.spaceBump = bump
        case "Enter": updated.enterBump = bump
        case "Modifier": updated.modifierBump = bump
        default: break
        }
        reactive = updated
    }

    private func runTest(_ entry: (label: String, value: Double, color: Color)) {
        testTask?.cancel()
        testLabel = entry.label
        testProgress = 0
        let duration = min(max(current.decay, 0) / 1000, 60)
        withAnimation(.linear(duration: duration)) { testProgress = 1 }
        testTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(duration, 0.1) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            testLabel = nil
            testProgress = 0
        }
    }
}

private enum DetailSection: String, CaseIterable, Identifiable {
    case design = "Design"
    case reactions = "Reactions"
    case info = "Info"

    var id: String { rawValue }
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
