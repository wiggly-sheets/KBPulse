//
//  KBPulseAppTests.swift
//  KBPulseAppTests
//
//  XCTest targets for ReactiveEngine.brightness() and hook JSON decoding.
//

import XCTest
@testable import KBPulseApp

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
}