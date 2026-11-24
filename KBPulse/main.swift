//
//  main.swift
//  kbpulse
//
//  Command-line entry point. Theme listing and validation use the same Theme
//  module and Application Support directory as the app.
//

import AppKit
import Foundation

private let bundleIdentifier = "com.ethanrdoesmc.kbpulseapp"

private func usage() {
    print("Usage: kbpulse [set <profile> | flash | off | list | validate <file> | help]")
    print("Run without a command to animate the default profile directly.")
}

private func handleCommand(_ command: String, _ argument: String?) -> Int32 {
    switch command {
    case "help", "-h", "--help":
        usage()
        return 0
    case "list":
        for name in ThemeLibrary(root: ThemeLocations.themesDir).names() {
            print(name)
        }
        return 0
    case "validate":
        guard let argument else {
            print("Usage: kbpulse validate <file>")
            return 1
        }
        let url = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
        do {
            let theme = try ThemeStore.loadTheme(at: url)
            let issues = theme.validate()
            guard issues.isEmpty else {
                for issue in issues {
                    print(issue.description)
                }
                return 1
            }
            print("Valid theme.")
            return 0
        } catch {
            print("Invalid theme: \(error.localizedDescription)")
            return 1
        }
    case "set", "flash", "off":
        if command == "set" && argument == nil {
            print("Usage: kbpulse set <profile>")
            return 1
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
            print("KBPulseApp is not running — launch it first")
            return 1
        }
        var userInfo: [String: String] = ["command": command]
        if let argument { userInfo["profile"] = argument }
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.ethanrdoesmc.kbpulse.command"),
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        print("Sent '\(command)' command to KBPulseApp")
        return 0
    default:
        usage()
        return 1
    }
}

private func animateDefaultProfile() -> Never {
    print("KBPulse by EthanRDoesMC")
    KBPPulseManager.configure()
    print("Animating keyboard. Press ctrl-c or close terminal to stop.")

    let url = ThemeLocations.themesDir.appendingPathComponent("Yawn.json")
    guard let theme = try? ThemeStore.loadTheme(at: url) else {
        print("No Yawn.json found. Create or select a theme in KBPulse.")
        exit(1)
    }
    let timeline = ThemeTimeline(animations: theme.animations)
    var interval = timeline.duration / 1000
    if interval <= 0 { interval = 1.0 }

    Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
        for step in timeline.steps {
            let brightness = Float(min(1, max(0, step.brightness)))
            let fade = Int32(max(0, step.fadeDuration.rounded()))
            KBPAnimator.setBrightness(brightness, withDuration: fade)
            Thread.sleep(forTimeInterval: max((step.fadeDuration + step.delay) / 1000, 0.001))
        }
    }

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    signal(SIGHUP, SIG_IGN)
    let sources = [SIGINT, SIGTERM, SIGHUP].map { signalNumber in
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler {
            KBPPulseManager.restoreBacklightSettings()
            exit(0)
        }
        source.resume()
        return source
    }
    _ = sources

    RunLoop.current.run()
    exit(0)
}

let arguments = CommandLine.arguments
if arguments.count > 1 {
    exit(handleCommand(arguments[1], arguments.count > 2 ? arguments[2] : nil))
}
animateDefaultProfile()
