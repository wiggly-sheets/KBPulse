//
//  CLISymlinkManager.swift
//  KBPulseApp
//
//  Manages the user-facing `kbpulse` symlink in ~/.local/bin so the CLI stays
//  reachable from launchers, keyboard shortcuts, Alfred/Raycast, and the shell.
//  No auth required: ~/.local/bin is user-writable and PATH-friendly on macOS
//  when added to the shell rc (zsh adds it by default on 10.15+).
//

import Foundation

struct CLISymlinkManager {
    /// Bundled CLI path inside the app bundle: KBPulseApp.app/Contents/MacOS/kbpulse
    static let bundledCLIPath: URL = {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/kbpulse")
    }()

    /// Where the user-facing symlink lives.
    static let installDir: URL = {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/bin", isDirectory: true)
    }()

    static let installPath: URL = installDir.appendingPathComponent("kbpulse")

    /// True when a `kbpulse` command resolves on PATH.
    static var isOnPATH: Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["kbpulse"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        return task.terminationStatus == 0
    }

    /// Current installed path, if any. Returns nil when nothing is installed.
    static var installedPath: URL? {
        guard FileManager.default.fileExists(atPath: installPath.path) else { return nil }
        // Resolve symlink to a real file; ignore if it points nowhere.
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: installPath.path) else {
            return nil
        }
        let resolved = URL(fileURLWithPath: dest, relativeTo: installPath.deletingLastPathComponent())
            .resolvingSymlinksInPath()
        return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
    }

    /// Install or refresh the symlink. Returns true on success.
    @discardableResult
    static func install() -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: bundledCLIPath.path) { return false }
        do {
            try fm.createDirectory(at: installDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: installPath.path) {
                try fm.removeItem(at: installPath)
            }
            try fm.createSymbolicLink(at: installPath, withDestinationURL: bundledCLIPath)
            return true
        } catch {
            return false
        }
    }
}