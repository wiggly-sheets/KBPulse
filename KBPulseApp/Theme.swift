//
//  Theme.swift
//  KBPulseApp
//
//  The theme document: one tolerant decoder, one strict validator and one
//  encoder. Unknown keys survive a round trip at both the theme and animation
//  level. Durations are milliseconds and stay fractional until playback.
//

import Foundation

struct ThemeIssue: Equatable {
    let path: String
    let message: String

    var description: String {
        path.isEmpty ? message : "\(path): \(message)"
    }
}

struct Theme {
    static let knownKeys: Set<String> = [
        "Name", "Description", "Author", "Version", "Homepage",
        "Preview Image URL", "Animations", "Reactive",
    ]

    var name = ""
    var comment = ""
    var author = ""
    var version = ""
    var homepage = ""
    var previewImageURL = ""
    var animations: [Animation] = []
    var reactive: ReactiveMode?
    var unknown: [String: Any] = [:]
    var present: Set<String> = []

    struct Animation: Identifiable {
        static let knownKeys: Set<String> = [
            "Name", "Description", "Brightness", "Fade Duration", "Delay",
        ]

        let id = UUID()
        var name = ""
        var comment = ""
        var brightness = 0.0
        var fadeDuration = 0.0
        var delay = 0.0
        var unknown: [String: Any] = [:]
        var present: Set<String> = []

        init(name: String = "", comment: String = "", brightness: Double = 0,
             fadeDuration: Double = 0, delay: Double = 0,
             unknown: [String: Any] = [:], present: Set<String> = []) {
            self.name = name
            self.comment = comment
            self.brightness = brightness
            self.fadeDuration = fadeDuration
            self.delay = delay
            self.unknown = unknown
            self.present = present
        }

        init(dictionary: [String: Any]) {
            name = Self.string(dictionary["Name"]) ?? ""
            comment = Self.string(dictionary["Description"]) ?? ""
            brightness = Self.number(dictionary["Brightness"]) ?? 0
            fadeDuration = Self.number(dictionary["Fade Duration"]) ?? 0
            delay = Self.number(dictionary["Delay"]) ?? 0
            present = Set(dictionary.keys).intersection(Self.knownKeys)
            var extra: [String: Any] = [:]
            for (key, value) in dictionary where !Self.knownKeys.contains(key) {
                extra[key] = value
            }
            unknown = extra
        }

        func dictionary() -> [String: Any] {
            var dict = unknown
            dict["Name"] = name
            if !comment.isEmpty || present.contains("Description") {
                dict["Description"] = comment
            }
            dict["Brightness"] = brightness
            dict["Fade Duration"] = fadeDuration
            dict["Delay"] = delay
            return dict
        }

        private static func string(_ value: Any?) -> String? {
            value as? String
        }

        private static func number(_ value: Any?) -> Double? {
            (value as? NSNumber)?.doubleValue
        }
    }

    init() {}

    init(dictionary: [String: Any]) {
        name = Self.string(dictionary["Name"]) ?? ""
        comment = Self.string(dictionary["Description"]) ?? ""
        author = Self.string(dictionary["Author"]) ?? ""
        version = Self.string(dictionary["Version"]) ?? ""
        homepage = Self.string(dictionary["Homepage"]) ?? ""
        previewImageURL = Self.string(dictionary["Preview Image URL"]) ?? ""
        animations = ((dictionary["Animations"] as? [[String: Any]]) ?? [])
            .map(Animation.init(dictionary:))
        if let section = dictionary["Reactive"] as? [String: Any] {
            reactive = ReactiveMode(section: section)
        }
        present = Set(dictionary.keys).intersection(Self.knownKeys)
        var extra: [String: Any] = [:]
        for (key, value) in dictionary where !Self.knownKeys.contains(key) {
            extra[key] = value
        }
        unknown = extra
    }

    func validate() -> [ThemeIssue] {
        var issues: [ThemeIssue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ThemeIssue(path: "Name", message: "Theme name is required."))
        }
        if animations.isEmpty && reactive?.enabled != true {
            issues.append(ThemeIssue(
                path: "Animations",
                message: "Add at least one animation, or enable typing reactions."))
        }
        for (label, value) in [("Homepage", homepage), ("Preview Image URL", previewImageURL)] {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, URL(string: trimmed)?.scheme == nil {
                issues.append(ThemeIssue(
                    path: label,
                    message: "\(label) must be a valid URL, or empty."))
            }
        }
        for (index, animation) in animations.enumerated() {
            let path = "Animations[\(index)]"
            if animation.name.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ThemeIssue(path: path, message: "Animation \(index + 1) needs a name."))
            }
            if animation.brightness < 0 || animation.brightness > 1 {
                issues.append(ThemeIssue(
                    path: path,
                    message: "Animation \(index + 1) brightness must be 0-1."))
            }
            if animation.fadeDuration < 0 {
                issues.append(ThemeIssue(
                    path: path,
                    message: "Animation \(index + 1) fade duration must be at least 0."))
            }
            if animation.delay < 0 {
                issues.append(ThemeIssue(
                    path: path,
                    message: "Animation \(index + 1) delay must be at least 0."))
            }
        }
        if let reactive {
            let unitValues: [(String, Double)] = [
                ("Bump", reactive.bump),
                ("Floor", reactive.floor),
                ("Space bump", reactive.spaceBump),
                ("Enter bump", reactive.enterBump),
                ("Modifier bump", reactive.modifierBump),
            ]
            for (label, value) in unitValues where value < 0 || value > 1 {
                issues.append(ThemeIssue(
                    path: "Reactive",
                    message: "Reactive \(label.lowercased()) must be 0-1."))
            }
            if reactive.decay < 0 {
                issues.append(ThemeIssue(
                    path: "Reactive",
                    message: "Reactive decay must be at least 0."))
            }
        }
        return issues
    }

    func dictionary() -> [String: Any] {
        var dict = unknown
        dict["Name"] = name
        for (key, value) in [
            ("Description", comment),
            ("Author", author),
            ("Version", version),
            ("Homepage", homepage),
            ("Preview Image URL", previewImageURL),
        ] where !value.isEmpty || present.contains(key) {
            dict[key] = value
        }
        dict["Animations"] = animations.map { $0.dictionary() }
        if let reactive {
            dict["Reactive"] = reactive.dictionary()
        } else {
            dict.removeValue(forKey: "Reactive")
        }
        return dict
    }

    static let defaultYawn: Theme = {
        var theme = Theme()
        theme.name = "Yawn (default)"
        theme.version = "1.0.0"
        theme.comment = "A calm, breath-like animation that somewhat resembles the sleep indicator on older MacBooks."
        theme.author = "EthanRDoesMC"
        theme.homepage = "https://ethanrdoesmc.com/"
        theme.previewImageURL = " "
        theme.animations = [
            Animation(name: "Fade In", comment: "Fades the keyboard to full brightness",
                      brightness: 1, fadeDuration: 2500, delay: 0),
            Animation(name: "Fade Out", comment: "Fades the keyboard to off",
                      brightness: 0, fadeDuration: 2500, delay: 0),
        ]
        return theme
    }()

    static let reactiveExample: Theme = {
        var theme = Theme()
        theme.name = "Pulse (reactive)"
        theme.version = "1.0.0"
        theme.comment = "Lights up on each keypress and fades back down. Runs instead of the breathing loop."
        theme.author = "EthanRDoesMC"
        theme.previewImageURL = " "
        theme.reactive = ReactiveMode()
        return theme
    }()

    static func newTheme(named name: String) -> Theme {
        var theme = defaultYawn
        theme.name = name
        theme.comment = ""
        theme.author = ""
        theme.homepage = ""
        theme.previewImageURL = ""
        theme.animations = theme.animations.map { animation in
            var animation = animation
            animation.fadeDuration = 1000
            return animation
        }
        return theme
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

/// Starting points for a new theme. The sheet shows one curve for each.
enum ThemeTemplate: String, CaseIterable, Identifiable {
    case blank
    case fade
    case pulse
    case reactive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: "Blank"
        case .fade: "Fade In / Out"
        case .pulse: "Pulse"
        case .reactive: "Typing Reactions"
        }
    }

    var summary: String {
        switch self {
        case .blank:
            "One steady animation. Build the rest yourself."
        case .fade:
            "Fade to full brightness, then back to off."
        case .pulse:
            "A quick flash with a slower fade back down."
        case .reactive:
            "Keystrokes light the keyboard instead of a timeline."
        }
    }

    var systemImage: String {
        switch self {
        case .blank: "square.dashed"
        case .fade: "circle.lefthalf.filled"
        case .pulse: "waveform.path.ecg"
        case .reactive: "keyboard"
        }
    }

    func theme(named name: String) -> Theme {
        switch self {
        case .blank:
            var theme = Theme()
            theme.name = name
            theme.animations = [
                Theme.Animation(name: "Steady", comment: "",
                                brightness: 0.5, fadeDuration: 500, delay: 1000),
            ]
            return theme
        case .fade:
            return Theme.newTheme(named: name)
        case .pulse:
            var theme = Theme.newTheme(named: name)
            theme.animations = [
                Theme.Animation(name: "Pulse Up", comment: "",
                                brightness: 1, fadeDuration: 120, delay: 60),
                Theme.Animation(name: "Pulse Down", comment: "",
                                brightness: 0, fadeDuration: 300, delay: 600),
            ]
            return theme
        case .reactive:
            var theme = Theme()
            theme.name = name
            theme.reactive = ReactiveMode()
            return theme
        }
    }
}

/// Config for typing-reactive themes. While active, the engine runs this
/// instead of the theme's animation loop. Values are kept as written so the
/// validator can report bad files; playback clamps them.
struct ReactiveMode {
    var enabled = true
    var bump = 0.7          // brightness added on a normal keydown [0, 1]
    var decay = 400.0       // ms from bump back down to floor
    var floor = 0.0         // resting brightness
    var spaceBump = 0.9     // distinct bump for space
    var enterBump = 0.9     // distinct bump for return / keypad enter
    var modifierBump = 0.5  // distinct bump for modifier press

    /// Nil when the theme has no usable reactive section (missing or
    /// disabled): the engine then runs the animation loop as before.
    init?(forEngine raw: [String: Any]) {
        guard let section = raw["Reactive"] as? [String: Any],
              (section["Enabled"] as? Bool) ?? true else { return nil }
        self.init(section: section)
    }

    init(section: [String: Any] = [:]) {
        if let value = section["Enabled"] as? Bool { enabled = value }
        if let value = Self.number(section["Bump"]) { bump = value }
        if let value = Self.number(section["Decay Duration"]) { decay = value }
        if let value = Self.number(section["Floor"]) { floor = value }
        if let value = Self.number(section["Space Bump"]) { spaceBump = value }
        if let value = Self.number(section["Enter Bump"]) { enterBump = value }
        if let value = Self.number(section["Modifier Bump"]) { modifierBump = value }
    }

    func dictionary() -> [String: Any] {
        ["Enabled": enabled,
         "Bump": bump,
         "Decay Duration": decay,
         "Floor": floor,
         "Space Bump": spaceBump,
         "Enter Bump": enterBump,
         "Modifier Bump": modifierBump]
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// Maps a vertical position in the curve to a bump amount. The top of
    /// the curve is 1, the floor line is 0.
    static func bump(forVerticalFraction fraction: Double, floor: Double) -> Double {
        let floor = min(1, max(0, floor))
        let fraction = min(1, max(0, fraction))
        return min(1, max(0, (1 - fraction - floor) / max(0.01, 1 - floor)))
    }
}
