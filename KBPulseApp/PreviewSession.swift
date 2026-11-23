//
//  PreviewSession.swift
//  KBPulseApp
//
//  Owns temporary theme playback: engine takeover, cancellation, restore and
//  published state. The editor previews an in-memory Theme, never a temp file.
//

import Foundation

protocol PreviewPlayer {
    func play(theme: Theme, reactive: ReactiveMode?)
    func stop()
}

struct EnginePreviewPlayer: PreviewPlayer {
    let engine: Engine

    func play(theme: Theme, reactive: ReactiveMode?) {
        engine.stop()
        engine.start(profile: KBPProfile(dictionary: theme.dictionary()), reactive: reactive)
    }

    func stop() {
        engine.stop()
    }
}

final class PreviewSession: ObservableObject {
    enum State: Equatable {
        case idle
        case playing(themeName: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let player: PreviewPlayer
    private let restore: () -> Void
    private var workItem: DispatchWorkItem?

    init(player: PreviewPlayer, restore: @escaping () -> Void) {
        self.player = player
        self.restore = restore
    }

    deinit {
        workItem?.cancel()
    }

    /// Plays the current editor contents. Animations play their full timeline;
    /// reactive-only themes use ten seconds because they have no fixed end.
    func play(theme: Theme, duration: TimeInterval? = nil) {
        if let issue = theme.validate().first {
            finish(restoring: false)
            state = .failed(issue.description)
            return
        }

        finish(restoring: false)
        let reactive = theme.reactive?.enabled == true ? theme.reactive : nil
        let timelineSeconds = ThemeTimeline(animations: theme.animations).duration / 1000
        let seconds = duration ?? (reactive != nil ? 10 : max(timelineSeconds, 1))

        player.play(theme: theme, reactive: reactive)
        state = .playing(themeName: theme.name)

        let item = DispatchWorkItem { [weak self] in
            self?.finish(restoring: true)
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Ends a preview and returns to the theme that was playing before it.
    func cancel() {
        finish(restoring: true)
    }

    /// Ends a preview without restoring. Used when another action takes over
    /// the engine or the app is terminating.
    func stop() {
        finish(restoring: false)
    }

    func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    private func finish(restoring: Bool) {
        workItem?.cancel()
        workItem = nil
        guard case .playing = state else { return }
        player.stop()
        state = .idle
        if restoring { restore() }
    }
}
