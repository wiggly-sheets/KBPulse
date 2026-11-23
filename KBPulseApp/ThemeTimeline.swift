import Foundation

struct ThemeTimeline: Equatable {
    struct Step: Equatable {
        let brightness: Double
        let fadeDuration: Double
        let delay: Double
        let startTime: Double

        var fadeEnd: Double { startTime + fadeDuration }
        var endTime: Double { fadeEnd + delay }
    }

    let steps: [Step]

    var duration: Double { steps.last?.endTime ?? 0 }

    /// Haptic taps land when each fade starts.
    var accentTimes: [Double] { steps.map(\.startTime) }

    init(animations: [Theme.Animation]) {
        self.init(
            brightness: animations.map(\.brightness),
            fadeDurations: animations.map(\.fadeDuration),
            delays: animations.map(\.delay)
        )
    }

    init(brightness: [Double], fadeDurations: [Double], delays: [Double]) {
        let count = min(brightness.count, fadeDurations.count, delays.count)
        var time = 0.0
        var steps: [Step] = []
        steps.reserveCapacity(count)
        for index in 0..<count {
            let fade = max(0, fadeDurations[index])
            let delay = max(0, delays[index])
            steps.append(Step(
                brightness: brightness[index],
                fadeDuration: fade,
                delay: delay,
                startTime: time
            ))
            time += fade + delay
        }
        self.steps = steps
    }

    /// Brightness at a time in milliseconds, assuming playback starts at 0.
    func brightness(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        var current = 0.0
        for step in steps {
            if time < step.startTime { return current }
            if time < step.fadeEnd {
                let progress = step.fadeDuration > 0
                    ? (time - step.startTime) / step.fadeDuration
                    : 1
                return current + (step.brightness - current) * min(1, max(0, progress))
            }
            current = step.brightness
            if time < step.endTime { return current }
        }
        return current
    }
}
