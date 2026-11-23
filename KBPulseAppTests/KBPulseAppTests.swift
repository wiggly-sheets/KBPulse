//
//  KBPulseAppTests.swift
//  KBPulseAppTests
//
//  XCTest targets for ReactiveEngine.brightness() and hook JSON decoding.
//

import XCTest
@testable import KBPulse

final class KBPulseAppTests: XCTestCase {

    // MARK: - ReactiveEngine.brightness() tests

    func testBrightnessRestingState() {
        // When amount is 0, should return floor
        let result = ReactiveEngine.brightness(elapsedMS: 100, amount: 0, floor: 0.3, decay: 400)
        XCTAssertEqual(result, 0.3, accuracy: 0.001)
    }

    func testBrightnessZeroDecay() {
        // When decay is 0, brightness should stay at floor
        let result = ReactiveEngine.brightness(elapsedMS: 100, amount: 0.7, floor: 0.1, decay: 0)
        XCTAssertEqual(result, 0.1, accuracy: 0.001)
    }

    func testBrightnessNegativeElapsed() {
        // Negative elapsed should return floor
        let result = ReactiveEngine.brightness(elapsedMS: -10, amount: 0.7, floor: 0.2, decay: 400)
        XCTAssertEqual(result, 0.2, accuracy: 0.001)
    }

    func testBrightnessBeforeDecayCompletes() {
        // Within decay period: brightness = floor + amount * (1 - elapsed/decay)
        // elapsed = 200, decay = 400, amount = 0.7, floor = 0.1
        // result = 0.1 + 0.7 * (1 - 200/400) = 0.1 + 0.7 * 0.5 = 0.45
        let result = ReactiveEngine.brightness(elapsedMS: 200, amount: 0.7, floor: 0.1, decay: 400)
        XCTAssertEqual(result, 0.45, accuracy: 0.001)
    }

    func testBrightnessAtDecayStart() {
        // At start of decay (elapsed = 0): brightness = floor + amount
        let result = ReactiveEngine.brightness(elapsedMS: 0, amount: 0.7, floor: 0.1, decay: 400)
        XCTAssertEqual(result, 0.8, accuracy: 0.001)
    }

    func testBrightnessCappedAtOne() {
        // Result capped at 1.0
        let result = ReactiveEngine.brightness(elapsedMS: 10, amount: 0.9, floor: 0.5, decay: 400)
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    func testBrightnessAfterDecayCompletes() {
        // After decay period, returns floor
        let result = ReactiveEngine.brightness(elapsedMS: 500, amount: 0.7, floor: 0.2, decay: 400)
        XCTAssertEqual(result, 0.2, accuracy: 0.001)
    }

    // MARK: - Hook JSON decoding tests

    func testHookDecodingMinimal() throws {
        let json = """
        [
            {
                "hookType": "wake",
                "trigger": "",
                "action": "flash",
                "theme": "",
                "enabled": true
            }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let hooks = try decoder.decode([Hook].self, from: json)

        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0].hookType, "wake")
        XCTAssertEqual(hooks[0].trigger, "")
        XCTAssertEqual(hooks[0].action, "flash")
        XCTAssertEqual(hooks[0].theme, "")
        XCTAssertTrue(hooks[0].enabled)
        XCTAssertNil(hooks[0].cooldown)
    }

    func testHookDecodingWithCooldown() throws {
        let json = """
        [
            {
                "hookType": "fileDownload",
                "trigger": "*.zip",
                "action": "flash",
                "theme": "",
                "enabled": true,
                "cooldown": 2.5
            }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let hooks = try decoder.decode([Hook].self, from: json)

        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0].hookType, "fileDownload")
        XCTAssertEqual(hooks[0].trigger, "*.zip")
        XCTAssertEqual(hooks[0].cooldown, 2.5)
    }

    func testHookDecodingAgentAttention() throws {
        let json = """
        [
            {
                "hookType": "agentAttention",
                "trigger": "claude",
                "action": "breathing",
                "theme": "Yawn",
                "enabled": true
            }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let hooks = try decoder.decode([Hook].self, from: json)

        XCTAssertEqual(hooks.count, 1)
        XCTAssertEqual(hooks[0].hookType, "agentAttention")
        XCTAssertEqual(hooks[0].trigger, "claude")
        XCTAssertEqual(hooks[0].action, "breathing")
        XCTAssertEqual(hooks[0].theme, "Yawn")
    }

    func testHookDecodingMultiple() throws {
        let json = """
        [
            {
                "hookType": "wake",
                "trigger": "",
                "action": "flash",
                "theme": "",
                "enabled": true
            },
            {
                "hookType": "agentAttention",
                "trigger": "opencode",
                "action": "breathing",
                "theme": "Pulse",
                "enabled": false
            }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let hooks = try decoder.decode([Hook].self, from: json)

        XCTAssertEqual(hooks.count, 2)
        XCTAssertEqual(hooks[0].enabled, true)
        XCTAssertEqual(hooks[1].enabled, false)
    }

    func testHookDecodingInvalidJSON() {
        let json = "not valid json".data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode([Hook].self, from: json))
    }

    func testHookDecodingMissingRequiredField() throws {
        let json = """
        [
            {
                "hookType": "wake"
            }
        ]
        """.data(using: .utf8)!

        // Missing required fields - decoder should fail or use defaults
        let decoder = JSONDecoder()
        // Decoding should succeed but use default values for missing fields
        let hooks = try decoder.decode([Hook].self, from: json)
        XCTAssertEqual(hooks.count, 1)
        // String and Bool have defaults in DecodingKeyedContainer
        XCTAssertEqual(hooks[0].trigger, "")
        XCTAssertEqual(hooks[0].action, "")
        XCTAssertEqual(hooks[0].theme, "")
    }

    // MARK: - HookStore tests

    func testHookStoreAllowedActions() {
        // agentAttention only allows breathing
        let allowed = HookStore.allowedActions(for: "agentAttention")
        XCTAssertEqual(allowed, ["breathing"])

        // agentExit allows flash, pulse, hold, fade
        let allowedExit = HookStore.allowedActions(for: "agentExit")
        XCTAssertEqual(allowedExit, ["flash", "pulse", "hold", "fade"])

        // musicVolume allows all actions
        let allowedVol = HookStore.allowedActions(for: "musicVolume")
        XCTAssertEqual(allowedVol, ["flash", "pulse", "hold", "fade", "breathing"])

        // appFrontmost allows all actions
        let allowedFront = HookStore.allowedActions(for: "appFrontmost")
        XCTAssertEqual(allowedFront, ["flash", "pulse", "hold", "fade", "breathing"])
    }

    func testHookStoreValidationMusicVolume() {
        // musicVolume with valid threshold trigger
        var hook = Hook(hookType: "musicVolume", trigger: "80", action: "flash", theme: "", enabled: true)
        var error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNil(error, "Valid musicVolume should have no error")

        // musicVolume with invalid threshold
        hook.trigger = "150"
        error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNotNil(error, "Volume > 100 should fail")

        hook.trigger = "-5"
        error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNotNil(error, "Negative volume should fail")

        hook.trigger = ""
        error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        // Empty trigger should be valid for musicVolume (disabled)
        XCTAssertNil(error, "Empty trigger should be valid")
    }

    func testHookStoreValidationMusicPlaybackNew() {
        // New musicPlayback hook type validation
        var hook = Hook(hookType: "musicPlayback", trigger: "", action: "flash", theme: "", enabled: true)
        var error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNil(error, "musicPlayback with empty trigger should be valid")

        hook.trigger = "com.apple.iTunes"
        error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNotNil(error, "A non-empty playback trigger can never match")

        // musicPlayback with breathing action needs a theme
        hook.trigger = ""
        hook.action = "breathing"
        error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNotNil(error, "breathing action needs theme for musicPlayback")
        XCTAssertTrue(error!.contains("Breathing hooks need a theme"))

        hook.theme = "Yawn"
        error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNil(error, "musicPlayback with breathing and theme should be valid")
    }

    func testHookStoreMonitoredNames() {
        // Test the from-hooks overload with a small hand-built array.
        let sampleHooks = [
            Hook(hookType: "agentAttention", trigger: "claude", action: "breathing", theme: "Yawn", enabled: true),
            Hook(hookType: "musicVolume", trigger: "80", action: "flash", theme: "", enabled: true),
            Hook(hookType: "agentAttention", trigger: "opencode", action: "breathing", theme: "Pulse", enabled: true),
        ]
        let names = HookStore.monitoredNames(from: sampleHooks)
        XCTAssertTrue(names.contains("claude"), "Should include claude")
        XCTAssertTrue(names.contains("opencode"), "Should include opencode")
        XCTAssertFalse(names.contains("80"), "Should not include music volume trigger")
        XCTAssertFalse(names.isEmpty, "Should have monitored names")
    }

    func testHookStoreHookTypesList() {
        XCTAssertTrue(HookStore.hookTypes.contains("musicVolume"), "hookTypes should contain musicVolume")
        XCTAssertTrue(HookStore.hookTypes.contains("agentAttention"), "hookTypes should contain agentAttention")
        XCTAssertTrue(HookStore.hookTypes.contains("musicPlayback"), "hookTypes should contain musicPlayback after addition")
    }

    // MARK: - AppState tests

    func testAppStateIconDisplayModes() {
        let allCases = AppState.IconDisplayMode.allCases
        XCTAssertEqual(allCases.count, 4, "Should have 4 display modes")
        XCTAssertTrue(allCases.contains(.dockOnly))
        XCTAssertTrue(allCases.contains(.menuBarOnly))
        XCTAssertTrue(allCases.contains(.both))
        XCTAssertTrue(allCases.contains(.none))
    }

    func testAppStateShowsMenuBar() {
        // menuBarOnly and both show menu bar
        XCTAssertTrue(AppState.IconDisplayMode.menuBarOnly.showsMenuBar)
        XCTAssertTrue(AppState.IconDisplayMode.both.showsMenuBar)

        // dockOnly and none hide menu bar
        XCTAssertFalse(AppState.IconDisplayMode.dockOnly.showsMenuBar)
        XCTAssertFalse(AppState.IconDisplayMode.none.showsMenuBar)
    }

    func testAppStateShowsDock() {
        // dockOnly and both show dock
        XCTAssertTrue(AppState.IconDisplayMode.dockOnly.showsDock)
        XCTAssertTrue(AppState.IconDisplayMode.both.showsDock)

        // menuBarOnly and none hide dock
        XCTAssertFalse(AppState.IconDisplayMode.menuBarOnly.showsDock)
        XCTAssertFalse(AppState.IconDisplayMode.none.showsDock)
    }

    func testAppStateIconDisplayModeRawValues() {
        // Raw values are the persisted UserDefaults format; changing one breaks saved settings.
        XCTAssertEqual(AppState.IconDisplayMode.dockOnly.rawValue, "dock")
        XCTAssertEqual(AppState.IconDisplayMode.menuBarOnly.rawValue, "menu")
        XCTAssertEqual(AppState.IconDisplayMode.both.rawValue, "both")
        XCTAssertEqual(AppState.IconDisplayMode.none.rawValue, "none")

        // Mistyped names must not resolve to a mode.
        XCTAssertNil(AppState.IconDisplayMode(rawValue: "menuBarOnly"))
        XCTAssertNil(AppState.IconDisplayMode(rawValue: "dockOnly"))
    }

    // MARK: - Trigger validation regression tests

    func testEmptyTriggerAllowedForEventHooks() {
        // These hooks legitimately use an empty trigger. The hook editor used
        // to reject them with a generic "trigger must not be empty" check.
        let types = ["wake", "screenLock", "screenUnlock", "fileDownload",
                     "appFrontmost", "idleThreshold", "musicVolume", "musicPlayback"]
        for type in types {
            let hook = Hook(hookType: type, trigger: "", action: "flash",
                            theme: "", enabled: true)
            XCTAssertNil(HookStore.validationError(for: hook, themes: ["Yawn"]),
                         "\(type) should allow an empty trigger")
        }
    }

    func testAgentHooksRequireTrigger() {
        let hook = Hook(hookType: "agentExit", trigger: "   ", action: "flash",
                        theme: "", enabled: true)
        XCTAssertNotNil(HookStore.validationError(for: hook, themes: ["Yawn"]))
    }

    func testBreathingHookRequiresExistingTheme() {
        let hook = Hook(hookType: "appFrontmost", trigger: "", action: "breathing",
                        theme: "Missing", enabled: true)
        let error = HookStore.validationError(for: hook, themes: ["Yawn"])
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("does not exist"))
    }

    // MARK: - Theme import validation

    func testThemeValidationAcceptsMinimalTheme() {
        let theme: [String: Any] = [
            "Name": "Test",
            "Animations": [
                ["Name": "Fade", "Brightness": 1.0, "Fade Duration": 1000, "Delay": 0],
            ],
        ]
        XCTAssertNil(ThemeStore.validateTheme(theme))
    }

    func testThemeValidationRejectsNonThemeJSON() {
        XCTAssertNotNil(ThemeStore.validateTheme(["name": "package.json"]))
        XCTAssertNotNil(ThemeStore.validateTheme(["Name": "No Content"]))
        XCTAssertNotNil(ThemeStore.validateTheme([
            "Name": "Bad Brightness",
            "Animations": [["Brightness": 2.0]],
        ]))
    }

    func testReactiveModeKeepsValuesForValidation() {
        let theme = Theme(dictionary: [
            "Name": "Bad Reactive",
            "Reactive": [
                "Bump": 4.0,
                "Floor": -1.0,
                "Decay Duration": -50,
                "Space Bump": 3.0,
            ],
        ])
        XCTAssertEqual(theme.reactive?.bump, 4.0)
        XCTAssertEqual(theme.reactive?.floor, -1.0)
        XCTAssertEqual(theme.reactive?.decay, -50)
        XCTAssertEqual(theme.reactive?.spaceBump, 3.0)
        XCTAssertFalse(theme.validate().isEmpty)
    }

    func testThemePreservesUnknownKeysAndFractionalDurations() throws {
        let theme = Theme(dictionary: [
            "Name": "Test",
            "Custom": ["nested": true],
            "Animations": [[
                "Name": "Fade",
                "Brightness": 1,
                "Fade Duration": 1000.5,
                "Delay": 0.25,
                "Animation Extra": "kept",
            ]],
        ])
        XCTAssertEqual(theme.animations.first?.fadeDuration, 1000.5)
        XCTAssertEqual(theme.animations.first?.delay, 0.25)
        let roundTrip = Theme(dictionary: theme.dictionary())
        XCTAssertEqual(roundTrip.unknown["Custom"] as? [String: Bool], ["nested": true])
        XCTAssertEqual(roundTrip.animations.first?.unknown["Animation Extra"] as? String, "kept")
        XCTAssertEqual(roundTrip.animations.first?.fadeDuration, 1000.5)
    }

    func testThemeValidationRequiresAnimationNamesAndValidURLs() {
        let theme = Theme(dictionary: [
            "Name": "Test",
            "Homepage": "example.com",
            "Animations": [["Brightness": 1, "Fade Duration": 100, "Delay": 0]],
        ])
        let issues = theme.validate()
        XCTAssertTrue(issues.contains { $0.path == "Homepage" })
        XCTAssertTrue(issues.contains { $0.path == "Animations[0]" })
    }

    // MARK: - Theme editor session

    private func makeThemeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KBPulseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var first = Theme.defaultYawn
        first.name = "Yawn"
        try ThemeStore.write(first, to: dir.appendingPathComponent("Yawn.json"))
        var second = Theme.defaultYawn
        second.name = "Second"
        try ThemeStore.write(second, to: dir.appendingPathComponent("Second.json"))
        return dir
    }

    func testEditorSessionDirtyStateUsesSavedSnapshot() throws {
        let dir = try makeThemeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = ThemeEditorSession(library: ThemeLibrary(root: dir))

        session.activate(initial: "Yawn")
        XCTAssertEqual(session.selection, "Yawn")
        XCTAssertFalse(session.isDirty)

        session.theme.comment = "Edited description"
        XCTAssertTrue(session.isDirty)

        session.save()
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(try ThemeStore.loadTheme(at: dir.appendingPathComponent("Yawn.json")).comment,
                       "Edited description")
    }

    func testEditorSessionSaveRenamesFileAndReportsOldName() throws {
        let dir = try makeThemeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var savedOldName: String?
        let session = ThemeEditorSession(
            library: ThemeLibrary(root: dir),
            onSaved: { _, oldName in savedOldName = oldName }
        )

        session.activate(initial: "Yawn")
        session.theme.name = "Renamed"
        session.save()

        XCTAssertEqual(session.selection, "Renamed")
        XCTAssertEqual(savedOldName, "Yawn")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Yawn.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Renamed.json").path))
        XCTAssertEqual(try ThemeStore.loadTheme(at: dir.appendingPathComponent("Renamed.json")).name,
                       "Renamed")
    }

    func testEditorSessionRejectsRenameCollision() throws {
        let dir = try makeThemeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = ThemeEditorSession(library: ThemeLibrary(root: dir))

        session.activate(initial: "Yawn")
        session.theme.name = "Second"
        session.save()

        XCTAssertEqual(session.selection, "Yawn")
        XCTAssertEqual(try ThemeStore.loadTheme(at: dir.appendingPathComponent("Yawn.json")).name,
                       "Yawn")
        XCTAssertTrue(session.message?.contains("already exists") == true)
    }

    func testEditorSessionBlocksSelectionUntilDiscarded() throws {
        let dir = try makeThemeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = ThemeEditorSession(library: ThemeLibrary(root: dir))

        session.activate(initial: "Yawn")
        session.theme.name = "Changed"
        session.requestSelection("Second")

        XCTAssertEqual(session.selection, "Yawn")
        XCTAssertEqual(session.pendingSelection, "Second")

        session.discardPending()
        XCTAssertEqual(session.selection, "Second")
        XCTAssertNil(session.pendingSelection)
        XCTAssertFalse(session.isDirty)
    }

    func testEditorSessionCreatesAndSelectsNewTheme() throws {
        let dir = try makeThemeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = ThemeEditorSession(library: ThemeLibrary(root: dir))

        session.activate(initial: "Yawn")
        session.create(named: "Fresh")

        XCTAssertEqual(session.selection, "Fresh")
        XCTAssertFalse(session.isDirty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Fresh.json").path))
        XCTAssertEqual(session.themes, ["Fresh", "Second", "Yawn"])
    }

    // MARK: - Preview session

    func testPreviewSessionPlaysInMemoryAndRestores() {
        let player = FakePreviewPlayer()
        var restores = 0
        let session = PreviewSession(player: player, restore: { restores += 1 })
        let expectation = expectation(description: "preview finished")

        session.play(theme: .defaultYawn, duration: 0.01)
        XCTAssertEqual(player.playCount, 1)
        XCTAssertEqual(session.state, .playing(themeName: "Yawn (default)"))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(player.stops, 1)
        XCTAssertEqual(restores, 1)
        XCTAssertEqual(session.state, .idle)
    }

    func testPreviewSessionCancelRestoresImmediately() {
        let player = FakePreviewPlayer()
        var restores = 0
        let session = PreviewSession(player: player, restore: { restores += 1 })

        session.play(theme: .defaultYawn, duration: 10)
        session.cancel()

        XCTAssertEqual(player.stops, 1)
        XCTAssertEqual(restores, 1)
        XCTAssertEqual(session.state, .idle)
    }

    func testPreviewSessionRejectsInvalidTheme() {
        let player = FakePreviewPlayer()
        let session = PreviewSession(player: player, restore: {})

        var theme = Theme.defaultYawn
        theme.name = ""
        session.play(theme: theme)

        XCTAssertEqual(player.playCount, 0)
        guard case .failed = session.state else {
            return XCTFail("Expected failed state")
        }
    }

    func testTimelineFadesThenHolds() {
        let timeline = ThemeTimeline(animations: [
            Theme.Animation(name: "In", brightness: 1, fadeDuration: 100, delay: 50),
            Theme.Animation(name: "Out", brightness: 0, fadeDuration: 200, delay: 0),
        ])

        XCTAssertEqual(timeline.duration, 350)
        XCTAssertEqual(timeline.brightness(at: 0), 0)
        XCTAssertEqual(timeline.brightness(at: 50), 0.5)
        XCTAssertEqual(timeline.brightness(at: 100), 1)
        XCTAssertEqual(timeline.brightness(at: 150), 1)
        XCTAssertEqual(timeline.brightness(at: 250), 0.5)
        XCTAssertEqual(timeline.brightness(at: 350), 0)
    }

    func testTimelineKeepsFractionalDurations() {
        let timeline = ThemeTimeline(animations: [
            Theme.Animation(name: "Slow", brightness: 1, fadeDuration: 1000.5, delay: 0.25),
        ])

        XCTAssertEqual(timeline.duration, 1000.75)
        XCTAssertEqual(timeline.steps.first?.fadeDuration, 1000.5)
    }

    // MARK: - Editor import and names

    func testEditorSessionImportsValidTheme() throws {
        let dir = try makeThemeDirectory()
        let sources = FileManager.default.temporaryDirectory
            .appendingPathComponent("KBPulseSources-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: sources)
        }

        var imported = Theme.defaultYawn
        imported.name = "Imported"
        let source = sources.appendingPathComponent("Imported.json")
        try ThemeStore.write(imported, to: source)

        let session = ThemeEditorSession(library: ThemeLibrary(root: dir))
        session.activate(initial: "Yawn")
        session.importTheme(from: source)

        XCTAssertEqual(session.selection, "Imported")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Imported.json").path))
        XCTAssertEqual(session.theme.name, "Imported")
    }

    func testEditorSessionImportListsEveryIssue() throws {
        let dir = try makeThemeDirectory()
        let sources = FileManager.default.temporaryDirectory
            .appendingPathComponent("KBPulseSources-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: sources)
        }

        let source = sources.appendingPathComponent("Broken.json")
        try ThemeStore.write([
            "Name": "",
            "Homepage": "example.com",
            "Animations": [[
                "Brightness": 2,
                "Fade Duration": -1,
                "Delay": 0,
            ]],
        ], to: source)

        let session = ThemeEditorSession(library: ThemeLibrary(root: dir))
        session.activate(initial: "Yawn")
        session.importTheme(from: source)

        let message = try XCTUnwrap(session.message)
        XCTAssertTrue(message.contains("Homepage"))
        XCTAssertTrue(message.contains("Animations[0]"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Broken.json").path))
    }

    func testEditorSessionRejectsNameCollisionsAndReservedHooks() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KBPulseTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try? ThemeStore.write(Theme.defaultYawn, to: dir.appendingPathComponent("Yawn.json"))
        let session = ThemeEditorSession(library: ThemeLibrary(root: dir))
        XCTAssertNotNil(session.nameError(for: "hooks"))
        XCTAssertNotNil(session.nameError(for: "yawn"))
        XCTAssertNil(session.nameError(for: "Fresh"))
    }

    func testThemeTemplatesProduceValidThemes() {
        for template in ThemeTemplate.allCases {
            let theme = template.theme(named: "Template")
            XCTAssertTrue(theme.validate().isEmpty, "\(template) should be valid")
        }
    }

    func testEditorSessionCreatesReactiveTemplate() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KBPulseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = ThemeEditorSession(library: ThemeLibrary(root: dir))
        session.create(named: "Keys", template: .reactive)

        XCTAssertEqual(session.selection, "Keys")
        XCTAssertNotNil(session.theme.reactive)
        XCTAssertTrue(session.theme.animations.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Keys.json").path))
    }
}

private final class FakePreviewPlayer: PreviewPlayer {
    var playCount = 0
    var stops = 0

    func play(theme: Theme, reactive: ReactiveMode?) {
        playCount += 1
    }

    func stop() {
        stops += 1
    }
}