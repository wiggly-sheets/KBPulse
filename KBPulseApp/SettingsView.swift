//
//  SettingsView.swift
//  KBPulseApp
//
//  Settings window: General tab (engine, CLI) + Themes tab (theme editor)
//  + Hooks tab (hooks.json editor).
//

import SwiftUI
import UniformTypeIdentifiers

/// Formats a cooldown for display without trapping on extreme values.
private func cooldownLabel(_ value: Double) -> String {
    String(format: "%.1f s", value)
}

/// Formats time since last fire for display.
private func timeSince(_ date: Date) -> String {
    let diff = -date.timeIntervalSinceNow
    if diff < 60 {
        return "\(Int(diff)) s ago"
    } else if diff < 3600 {
        let minutes = Int(diff / 60)
        return "\(minutes) m ago"
    } else {
        let hours = Int(diff / 3600)
        return "\(hours) h ago"
    }
}

/// Merges diagnostics from both runtimes, preferring non-nil lastFired and summing skipped.
private func mergedDiagnostics(for hook: Hook) -> HookDiagnostics? {
    let sys = SystemEventRuntime.diagnostics(for: hook)
    let agent = AgentHookRuntime.diagnostics(for: hook)
    let lastFired = sys?.lastFired ?? agent?.lastFired
    let skipped = (sys?.skipped ?? 0) + (agent?.skipped ?? 0)
    if lastFired != nil || skipped > 0 {
        return HookDiagnostics(lastFired: lastFired, skipped: skipped)
    }
    return nil
}

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            ThemesTab(state: state)
                .tabItem { Label("Themes", systemImage: "paintpalette") }
            HooksTab(state: state)
                .tabItem { Label("Hooks", systemImage: "bolt") }
        }
        .frame(width: 640)
    }

    private var general: some View {
        Form {
            Toggle("Animation engine", isOn: state.engineBinding)
            Picker("Theme", selection: state.themeBinding) {
                ForEach(state.themes, id: \.self) { Text($0).tag($0) }
            }
            CLIView(state: state)
            Section("Display") {
                Picker("Icon display", selection: $state.iconDisplayMode) {
                    ForEach(AppState.IconDisplayMode.allCases) {
                        Text($0.description).tag($0)
                    }
                }
                .pickerStyle(.menu)
                Text("Choose how to display icons: dock, menu bar, both, or neither.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Accessibility & Runtime") {
                HStack {
                    Label("Accessibility (key events)", systemImage: "accessibility")
                    Spacer()
                    if state.isAccessibilityGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .help("Permission granted — keyboard bumps are active")
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .help("Permission required for typing-reactive mode")
                        Button("Open Privacy Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                HStack {
                    Label("Active agents", systemImage: "terminal")
                    Spacer()
                    if !state.activeAgents.isEmpty {
                        ForEach(state.activeAgents, id: \.self) { agent in
                            Text(agent)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.quaternary))
                                .foregroundStyle(.primary)
                        }
                    } else if state.activeAgents.isEmpty {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                            .help("No agents detected")
                    } else {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                            .help("Scan unavailable")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshThemes() }
    }
}

private struct CLIView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Section("Command line") {
            LabeledContent("Bundled", value: CLISymlinkManager.bundledCLIPath.path)
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Installed", value: installedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.cliOnPATH {
                Text("`kbpulse` is on PATH.")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("`kbpulse` is not on PATH.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.cliInstalledPath == nil {
                Button("Install kbpulse to ~/.local/bin") {
                    state.installCLI()
                }
            } else {
                Button("Reinstall") {
                    state.installCLI()
                }
            }
            Text("The CLI runs the same engine as the app. Use it for scripts, launchers, keyboard shortcuts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installedLabel: String {
        guard let path = state.cliInstalledPath else { return "not installed" }
        return path.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - Hook type categories

private enum HookCategory: String, CaseIterable {
    case agent = "Agent"
    case system = "System"
    case media = "Media"

    static func category(for hookType: String) -> HookCategory {
        switch hookType {
        case "agentAttention", "agentExit":
            return .agent
        case "appLaunched", "appTerminated", "wake", "fileDownload",
             "appFrontmost", "screenLock", "screenUnlock", "idleThreshold":
            return .system
        case "musicVolume", "musicPlayback":
            return .media
        default:
            return .system
        }
    }

    var systemImage: String {
        switch self {
        case .agent: return "terminal.fill"
        case .system: return "gearshape.fill"
        case .media: return "music.note"
        }
    }

    var color: Color {
        switch self {
        case .agent: return .blue
        case .system: return .purple
        case .media: return .orange
        }
    }
}

private struct HooksTab: View {
    @ObservedObject var state: AppState
    @State private var hooks: [Hook] = []
    @State private var error: String?
    @State private var loadFailed = false
    @State private var draft: Hook?
    @State private var editIndex: Int?
    @State private var insertedIndex: Int?
    @State private var showEditor = false

    var body: some View {
        Form {
            Section("Hooks") {
                if hooks.isEmpty && !loadFailed {
                    Text("No hooks configured. Add one below; the file is created if needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(HookCategory.allCases, id: \.self) { category in
                    let categoryHooks = hooksForCategory(category)
                    if !categoryHooks.isEmpty {
                        Section {
                            ForEach(categoryHooks, id: \.0) { globalIndex, hook in
                                row(globalIndex: globalIndex, hook: hook)
                                    .onDrag {
                                        NSItemProvider(object: "\(globalIndex)" as NSString)
                                    }
                                    .onDrop(of: [.text], isTargeted: nil) { providers in
                                        handleDrop(from: providers, toIndex: globalIndex)
                                    }
                            }
                        } header: {
                            Label(category.rawValue, systemImage: category.systemImage)
                                .foregroundStyle(category.color)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
                if !hooks.isEmpty {
                    Button("Reload") { load() }
                        .buttonStyle(.plain)
                }
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Add hook") { add() }
                    .disabled(loadFailed)
                Text("Default hooks are created automatically on first launch. The file lives at ~/Documents/KBPulse/hooks.json and the runtime reads it fresh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            state.refreshThemes()
            load()
        }
        .sheet(isPresented: $showEditor, onDismiss: finishEditing) {
            if let draft {
                HookEditor(
                    hook: draft,
                    themes: state.themes,
                    canDelete: editIndex != nil && insertedIndex == nil,
                    onSave: saveDraft,
                    onDelete: deleteDraft
                )
            }
        }
    }

    private func hooksForCategory(_ category: HookCategory) -> [(Int, Hook)] {
        hooks.enumerated().filter { _, hook in
            HookCategory.category(for: hook.hookType) == category
        }
    }

    // MARK: - Drop handling

    private func handleDrop(from providers: [NSItemProvider], toIndex: Int) -> Bool {
        guard let provider = providers.first else { return false }
        let item = provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil)
        guard let data = item as? Data,
              let itemStr = String(data: data, encoding: .utf8),
              let fromIndex = Int(itemStr),
              fromIndex != toIndex,
              fromIndex >= 0,
              fromIndex < hooks.count else { return false }

        var updated = hooks
        let hook = updated.remove(at: fromIndex)
        updated.insert(hook, at: toIndex)
        if let msg = persist(updated) {
            error = msg
        }
        return true
    }

    // MARK: - Rows

    private func row(globalIndex: Int, hook: Hook) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to reorder")
                .accessibilityLabel("Reorder hook")
            Toggle("", isOn: enabledBinding(globalIndex))
                .labelsHidden()
                .disabled(loadFailed)
                .accessibilityLabel("Enable \(hook.hookType) hook")
            VStack(alignment: .leading, spacing: 3) {
                Text(hook.hookType)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(hook.trigger.isEmpty ? "any" : hook.trigger)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(hook.action)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(hook.theme.isEmpty ? "none" : hook.theme)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !HookStore.isAgentType(hook.hookType),
               let cooldown = hook.cooldown, cooldown > 0 {
                Text(cooldownLabel(cooldown))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let d = mergedDiagnostics(for: hook) {
                if let lastFired = d.lastFired {
                    Text(timeSince(lastFired))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("never")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if d.skipped > 0 {
                    Text("skipped \(d.skipped)×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("Edit") { edit(globalIndex) }
                .disabled(loadFailed)
        }
        .padding(.vertical, 4)
    }

    private func enabledBinding(_ globalIndex: Int) -> Binding<Bool> {
        Binding(
            get: { hooks.indices.contains(globalIndex) ? hooks[globalIndex].enabled : false },
            set: { enabled in
                guard hooks.indices.contains(globalIndex) else { return }
                var updated = hooks
                updated[globalIndex].enabled = enabled
                _ = persist(updated)
            }
        )
    }

    // MARK: - Actions

    private func load() {
        do {
            hooks = try HookStore.loadForEditing()
            error = nil
            loadFailed = false
        } catch let failure {
            hooks = []
            error = failure.localizedDescription
            loadFailed = true
        }
    }

    private func add() {
        guard !loadFailed else { return }
        error = nil
        let hook: Hook
        if state.themes.isEmpty {
            hook = Hook(hookType: "wake", trigger: "", action: "flash", theme: "", enabled: true)
        } else {
            hook = Hook(
                hookType: "agentAttention",
                trigger: "",
                action: "breathing",
                theme: state.themes.first ?? "",
                enabled: true
            )
        }
        hooks.insert(hook, at: 0)
        insertedIndex = 0
        editIndex = 0
        draft = hook
        showEditor = true
    }

    private func edit(_ index: Int) {
        guard !loadFailed, hooks.indices.contains(index) else { return }
        error = nil
        editIndex = index
        insertedIndex = nil
        draft = hooks[index]
        showEditor = true
    }

    private func saveDraft(_ hook: Hook) -> String? {
        var hook = hook
        if HookStore.isAgentType(hook.hookType) {
            hook.trigger = hook.trigger.trimmingCharacters(in: .whitespaces)
            hook.cooldown = nil
        }
        if let message = HookStore.validationError(for: hook, themes: state.themes) {
            return message
        }
        var updated = hooks
        if let index = editIndex {
            guard updated.indices.contains(index) else {
                return "The hook could not be saved because it is no longer in the list. Reload and try again."
            }
            updated[index] = hook
        } else {
            updated.insert(hook, at: 0)
        }
        if let message = persist(updated) {
            return message
        }
        editIndex = nil
        insertedIndex = nil
        return nil
    }

    private func deleteDraft() -> String? {
        if let index = insertedIndex {
            // A pending add is not on disk yet, so Delete acts as Cancel.
            guard hooks.indices.contains(index) else {
                return "The hook being added is no longer in the list."
            }
            hooks.remove(at: index)
            insertedIndex = nil
            editIndex = nil
            return nil
        }
        guard let index = editIndex, hooks.indices.contains(index) else {
            return "The hook could not be deleted because it is no longer in the list. Reload and try again."
        }
        var updated = hooks
        updated.remove(at: index)
        if let message = persist(updated) {
            return message
        }
        editIndex = nil
        insertedIndex = nil
        return nil
    }

    /// Writes `updated` to disk and adopts it only when the write succeeds.
    private func persist(_ updated: [Hook]) -> String? {
        do {
            try HookStore.save(updated)
            hooks = updated
            error = nil
            return nil
        } catch {
            let message = "Could not save hooks.json: \(error.localizedDescription)"
            self.error = message
            return message
        }
    }

    /// Drops an unsaved inserted hook and clears editor state.
    private func finishEditing() {
        draft = nil
        editIndex = nil
        error = nil
        if let index = insertedIndex {
            if hooks.indices.contains(index) {
                hooks.remove(at: index)
            }
            insertedIndex = nil
        }
    }
}

private struct HookEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Hook
    @State private var error: String?
    @State private var saved = false
    let themes: [String]
    let canDelete: Bool
    let onSave: (Hook) -> String?
    let onDelete: () -> String?

    init(
        hook: Hook,
        themes: [String],
        canDelete: Bool,
        onSave: @escaping (Hook) -> String?,
        onDelete: @escaping () -> String?
    ) {
        _draft = State(initialValue: hook)
        self.themes = themes
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        Form {
            Picker("Hook type", selection: $draft.hookType) {
                ForEach(HookStore.hookTypes, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: draft.hookType) { _ in
                let allowed = HookStore.allowedActions(for: draft.hookType)
                if !allowed.contains(draft.action) {
                    draft.action = allowed.first ?? draft.action
                }
            }
            TextField("Trigger", text: $draft.trigger)
                .lineLimit(nil)
            if draft.hookType == "agentAttention" || draft.hookType == "agentExit" {
                Text("Executable name, for example claude or codex. Case-insensitive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if draft.hookType == "musicPlayback" {
                Text("Optional bundle ID to filter by media app (e.g., com.apple.Music). Empty = any media app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if draft.hookType == "appFrontmost" {
                Text("Bundle ID, app name, or glob pattern. Empty = any app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if draft.hookType == "fileDownload" {
                Text("Filename or glob pattern (e.g., *.zip). Empty = any download.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if draft.hookType == "idleThreshold" {
                Text("Seconds (e.g., 300). Empty = default 300s.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if draft.hookType == "musicVolume" {
                Text("Volume threshold 0-100. Empty = disabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Action", selection: $draft.action) {
                ForEach(HookStore.allowedActions(for: draft.hookType), id: \.self) { action in
                    Text(action.capitalized).tag(action)
                }
            }
            Picker("Theme", selection: $draft.theme) {
                Text("None").tag("")
                ForEach(themes, id: \.self) { Text($0).tag($0) }
            }
            if !HookStore.isAgentType(draft.hookType) {
                Stepper(value: cooldown, in: 0...3600, step: 1) {
                    Text("Cooldown: \(cooldownLabel(min(max(draft.cooldown ?? 0, 0), 3600)))")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Enabled", isOn: $draft.enabled)
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                HStack {
                    if canDelete {
                        Button("Delete", role: .destructive) {
                            if let message = onDelete() {
                                error = message
                            } else {
                                dismiss()
                            }
                        }
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Save") {
                        guard !saved else { return }
                        if let message = onSave(draft) {
                            error = message
                        } else {
                            saved = true
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }

    /// Zero in the UI means "no cooldown" in the file.
    private var cooldown: Binding<Double> {
        Binding(
            get: { draft.cooldown ?? 0 },
            set: { draft.cooldown = $0 > 0 ? $0 : nil }
        )
    }
}