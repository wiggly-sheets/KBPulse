//
//  SettingsView.swift
//  KBPulseApp
//
//  Settings window: General tab (engine, CLI) + Themes tab (theme editor)
//  + Hooks tab (hooks.json editor).
//

import SwiftUI

/// Formats a cooldown for display without trapping on extreme values.
private func cooldownLabel(_ value: Double) -> String {
    String(format: "%.1f s", value)
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
        .frame(width: 520)
    }

    private var general: some View {
        Form {
            Toggle("Animation engine", isOn: state.engineBinding)
            Picker("Theme", selection: state.themeBinding) {
                ForEach(state.themes, id: \.self) { Text($0).tag($0) }
            }
            CLISection(state: state)
        }
        .formStyle(.grouped)
        .onAppear { state.refreshThemes() }
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
                        .foregroundColor(.secondary)
                }
                ForEach(Array(hooks.enumerated()), id: \.offset) { index, hook in
                    row(index: index, hook: hook)
                }
                HStack {
                    Button("Add hook") { add() }
                        .disabled(loadFailed)
                    Button("Reload") { load() }
                }
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            Section {
                Text("Default hooks are created automatically on first launch. The file lives at ~/Documents/KBPulse/hooks.json and the runtime reads it fresh.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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

    // MARK: - Rows

    private func row(index: Int, hook: Hook) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: enabledBinding(index))
                .labelsHidden()
                .disabled(loadFailed)
                .accessibilityLabel("Enable \(hook.hookType) hook")
            VStack(alignment: .leading, spacing: 2) {
                Text(hook.hookType)
                Text(hook.trigger.isEmpty ? "any" : hook.trigger)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(hook.action)
            Text(hook.theme.isEmpty ? "none" : hook.theme)
                .foregroundColor(.secondary)
            if !HookStore.isAgentType(hook.hookType),
               let cooldown = hook.cooldown, cooldown > 0 {
                Text(cooldownLabel(cooldown))
                    .foregroundColor(.secondary)
            }
            Button("Edit") { edit(index) }
                .disabled(loadFailed)
        }
    }

    private func enabledBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { hooks.indices.contains(index) ? hooks[index].enabled : false },
            set: { enabled in
                guard hooks.indices.contains(index) else { return }
                var updated = hooks
                updated[index].enabled = enabled
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
            TextField("Trigger", text: $draft.trigger)
            if draft.hookType == "agentAttention" || draft.hookType == "agentExit" {
                Text("Executable name, for example claude or codex. Case-insensitive.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            Picker("Action", selection: $draft.action) {
                Text("Flash").tag("flash")
                Text("Breathing").tag("breathing")
            }
            Picker("Theme", selection: $draft.theme) {
                Text("None").tag("")
                ForEach(themes, id: \.self) { Text($0).tag($0) }
            }
            if !HookStore.isAgentType(draft.hookType) {
                Stepper(value: cooldown, in: 0...3600, step: 1) {
                    Text("Cooldown: \(cooldownLabel(min(max(draft.cooldown ?? 0, 0), 3600)))")
                }
            }
            Toggle("Enabled", isOn: $draft.enabled)
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
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
        .frame(width: 420)
    }

    /// Zero in the UI means "no cooldown" in the file.
    private var cooldown: Binding<Double> {
        Binding(
            get: { draft.cooldown ?? 0 },
            set: { draft.cooldown = $0 > 0 ? $0 : nil }
        )
    }
}

private struct CLISection: View {
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
            } else {
                Text("`kbpulse` is not on PATH.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        }
    }

    private var installedLabel: String {
        guard let path = state.cliInstalledPath else { return "not installed" }
        return path.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
