import Foundation

struct BundledTheme: Identifiable {
    enum Kind {
        case standard
        case reactive
    }

    let id: String
    let kind: Kind
    let summary: String
    let theme: Theme
}

enum BundledThemes {
    static let all: [BundledTheme] = standard + reactive

    private static func animation(_ name: String,
                                  _ brightness: Double,
                                  _ fade: Double,
                                  _ delay: Double) -> [String: Any] {
        [
            "Name": name,
            "Brightness": brightness,
            "Fade Duration": fade,
            "Delay": delay
        ]
    }

    private static func standard(_ name: String,
                                 _ summary: String,
                                 _ animations: [[String: Any]],
                                 haptics: Bool = false) -> BundledTheme {
        var dictionary: [String: Any] = [
            "Name": name,
            "Description": summary,
            "Author": "KBPulse",
            "Version": "1.0.0",
            "Animations": animations
        ]
        if haptics { dictionary["Haptics"] = true }
        return BundledTheme(id: name, kind: .standard, summary: summary,
                            theme: Theme(dictionary: dictionary))
    }

    private static func reactive(_ name: String,
                                 _ summary: String,
                                 bump: Double,
                                 decay: Double,
                                 floor: Double,
                                 space: Double,
                                 enter: Double,
                                 modifier: Double,
                                 haptics: Bool = false) -> BundledTheme {
        let section: [String: Any] = [
            "Enabled": true,
            "Bump": bump,
            "Decay Duration": decay,
            "Floor": floor,
            "Space Bump": space,
            "Enter Bump": enter,
            "Modifier Bump": modifier
        ]
        var dictionary: [String: Any] = [
            "Name": name,
            "Description": summary,
            "Author": "KBPulse",
            "Version": "1.0.0",
            "Animations": [],
            "Reactive": section
        ]
        if haptics { dictionary["Haptics"] = true }
        return BundledTheme(id: name, kind: .reactive, summary: summary,
                            theme: Theme(dictionary: dictionary))
    }

    private static let standard: [BundledTheme] = [
        standard("Sunrise", "A slow dawn that holds, then settles into a warm glow.", [
            animation("Dawn", 1.0, 8000, 4000),
            animation("Settle", 0.15, 6000, 2000)
        ]),
        standard("Heartbeat", "Two quick thumps, then a quiet pause.", [
            animation("First thump", 0.85, 80, 120),
            animation("First release", 0.25, 120, 80),
            animation("Second thump", 0.9, 90, 250),
            animation("Rest", 0.1, 400, 800)
        ], haptics: true),
        standard("Sonar", "One bright ping and a long, dark echo.", [
            animation("Ping", 0.9, 40, 50),
            animation("Echo", 0.1, 2200, 1800)
        ]),
        standard("Lightning", "A sharp double flash, then darkness.", [
            animation("First strike", 1.0, 30, 60),
            animation("Afterglow", 0.2, 50, 80),
            animation("Second strike", 1.0, 30, 40),
            animation("Blackout", 0.0, 500, 2500)
        ], haptics: true),
        standard("Morse", "KBP in Morse code: dash-dot-dash, dash-dot-dot-dot, dot-dash-dash-dot.", morseSteps(),
                 haptics: true),
        standard("Metronome", "A four-beat bar with a strong downbeat.", [
            animation("Downbeat", 1.0, 50, 80),
            animation("Offbeat", 0.2, 50, 0),
            animation("Beat", 0.6, 50, 80),
            animation("Offbeat", 0.2, 50, 0),
            animation("Beat", 0.6, 50, 80),
            animation("Offbeat", 0.2, 50, 0),
            animation("Weak beat", 0.4, 50, 200)
        ], haptics: true),
        standard("Ticker", "A steady two-tap rhythm, like quiet typing.", [
            animation("Tick", 0.5, 30, 70),
            animation("Tick", 0.5, 30, 370)
        ]),
        standard("Ember", "A low glow that breathes instead of pulsing.", [
            animation("Glow", 0.35, 3000, 2000),
            animation("Cool", 0.12, 3000, 1500)
        ]),
        standard("On Air", "A recording light that blinks between bright and half-lit.", [
            animation("On", 0.9, 200, 5000),
            animation("Dip", 0.5, 150, 100),
            animation("On", 0.9, 200, 5000),
            animation("Dip", 0.5, 150, 100)
        ]),
        standard("Rain", "Twenty short droplets with uneven gaps.", rainSteps()),
        standard("Tide", "A slow swell that holds, then retreats.", [
            animation("Swell", 0.6, 4000, 1000),
            animation("Retreat", 0.2, 3000, 3000)
        ]),
        standard("Nightlight", "Barely-there light for late nights.", [
            animation("Dim", 0.15, 5000, 10000),
            animation("Off", 0.0, 5000, 5000)
        ]),
        standard("Disco", "A fast alternating strobe. Off by default.", (0..<8).map { index in
            animation(index.isMultiple(of: 2) ? "Flash" : "Dark",
                      index.isMultiple(of: 2) ? 1.0 : 0.0,
                      120, 130)
        })
    ]

    private static let reactive: [BundledTheme] = [
        reactive("Typewriter", "Crisp and quiet, like a mechanical key.", bump: 0.35, decay: 90, floor: 0.05,
                 space: 0.5, enter: 0.6, modifier: 0.2),
        reactive("Thunder", "Every key lands as a deep clap.", bump: 1.0, decay: 900, floor: 0.0,
                 space: 1.0, enter: 1.0, modifier: 0.7, haptics: true),
        reactive("Ember Keys", "Keys leave a warm glow behind.", bump: 0.5, decay: 1200, floor: 0.2,
                 space: 0.7, enter: 0.8, modifier: 0.4),
        reactive("Neon", "Instant, bright flickers with a lit floor.", bump: 0.9, decay: 60, floor: 0.15,
                 space: 1.0, enter: 1.0, modifier: 0.6),
        reactive("Shortcut", "Letters whisper. Shortcut keys shout.", bump: 0.15, decay: 150, floor: 0.0,
                 space: 0.4, enter: 0.5, modifier: 1.0),
        reactive("Long Echo", "Dense typing turns into a wash of light.", bump: 0.6, decay: 2500, floor: 0.0,
                 space: 0.8, enter: 0.8, modifier: 0.5),
        reactive("Whisper", "Almost invisible, for dark rooms.", bump: 0.2, decay: 1800, floor: 0.02,
                 space: 0.35, enter: 0.4, modifier: 0.15),
        reactive("Drum Kit", "Space and Enter hit hard. Letters keep time.", bump: 0.3, decay: 200, floor: 0.1,
                 space: 1.0, enter: 0.9, modifier: 0.7, haptics: true),
        reactive("Deep Work", "Low, steady, and out of the way.", bump: 0.25, decay: 500, floor: 0.12,
                 space: 0.4, enter: 0.5, modifier: 0.3),
        reactive("Midnight", "A dark floor with bright Enter keys.", bump: 0.5, decay: 700, floor: 0.0,
                 space: 0.7, enter: 0.9, modifier: 0.4)
    ]

    private static func morseSteps() -> [[String: Any]] {
        var steps: [[String: Any]] = []

        func pulse(_ isLong: Bool) {
            steps.append(animation(isLong ? "Dash" : "Dot", 0.9, 20, isLong ? 340 : 100))
        }

        func gap(_ isLong: Bool) {
            steps.append(animation("Gap", 0.0, 20, isLong ? 340 : 100))
        }

        // K: -.-
        pulse(true); gap(false); pulse(false); gap(false); pulse(true); gap(true)
        // B: -...
        pulse(true); gap(false); pulse(false); gap(false); pulse(false); gap(false); pulse(false); gap(true)
        // P: .--.
        pulse(false); gap(false); pulse(true); gap(false); pulse(true); gap(false); pulse(false); gap(true)
        return steps
    }

    private static func rainSteps() -> [[String: Any]] {
        let levels = [0.45, 0.7, 0.55, 0.8, 0.35, 0.65, 0.5, 0.75, 0.4, 0.6,
                      0.8, 0.45, 0.7, 0.55, 0.85, 0.5, 0.65, 0.4, 0.75, 0.6]
        let holds = [120.0, 420, 180, 650, 90, 300, 510, 140, 380, 220,
                     600, 110, 460, 250, 90, 540, 160, 330, 480, 200]
        return levels.enumerated().map { index, level in
            animation("Drop \(index + 1)", level, 40, holds[index])
        }
    }
}
