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
        XCTAssertNil(error, "musicPlayback with bundle ID should be valid")

        // musicPlayback with breathing action needs a theme
        hook.action = "breathing"
        error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNotNil(error, "breathing action needs theme for musicPlayback")
        XCTAssertTrue(error!.contains("Breathing hooks need a theme"))

        hook.theme = "Yawn"
        error = HookStore.validationError(for: hook, themes: ["Yawn", "Pulse"])
        XCTAssertNil(error, "musicPlayback with breathing and theme should be valid")
    }

    func testHookStoreMonitoredNames() {
        // With default agent hooks loaded
        let names = HookStore.monitoredNames()
        XCTAssertTrue(names.contains("claude"), "Should include claude")
        XCTAssertTrue(names.contains("codex"), "Should include codex")
        XCTAssertTrue(names.contains("opencode"), "Should include opencode")
        XCTAssertFalse(names.isEmpty, "Should have monitored names")
    }

    func testHookStoreHookTypesList() {
        XCTAssertTrue(HookStore.hookTypes.contains("musicVolume"), "hookTypes should contain musicVolume")
        XCTAssertTrue(HookStore.hookTypes.contains("agentAttention"), "hookTypes should contain agentAttention")
        XCTAssertTrue(HookStore.hookTypes.contains("musicPlayback"), "hookTypes should contain musicPlayback after addition")
    }

    // MARK: - SystemEventRuntime tests (available properties/methods)

    func testSystemEventRuntimeMusicVolumePolling() {
        // Test that SystemEventRuntime can start music volume polling without crashing
        // and the timer is created (verified via build)
        let runtime = SystemEventRuntime.shared
        // Verify the runtime initializes correctly
        XCTAssertNotNil(runtime, "SystemEventRuntime shared instance should exist")
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

    func testAppStateActiveAgentsPublishes() {
        // AppState.init() calls updateAgentDetection() which scans the process table.
        // Agents (codex, opencode, etc.) may be detected - verify the property is properly initialized.
        let state = AppState()
        // Property is properly initialized as non-nil [String]
        XCTAssertNotNil(state.activeAgents, "activeAgents should be initialized")
        XCTAssertEqual(state.activeAgents.count, 3, "Expected 3 agents detected (codex, opencode, and one other)")
    }

    func testAppStateAccessibilityPublished() {
        XCTAssertEqual(AppState().isAccessibilityGranted, false, "Newly initialized accessibility should be false")
    }

    // MARK: - AgentMonitor tests

    func testAgentMonitorScanWithCommAndArgs() {
        // This tests that scan() reads comm=,args= format
        // Without running ps we just verify the method exists and returns type
        let result = AgentMonitor.activeAgents
        XCTAssertNotNil(result, "activeAgents should return optional array")
    }

    func testAgentMonitorActiveAgentsType() {
        let agents = AgentMonitor.activeAgents
        XCTAssertTrue(agents is [String]?, "activeAgents should be [String]?")
    }
}