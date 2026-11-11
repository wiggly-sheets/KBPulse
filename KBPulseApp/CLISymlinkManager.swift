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

/// Result of a symlink install attempt.
enum CLIInstallResult {
    /// Already installed and pointing at the bundled path; no-op success.
    case alreadyInstalled(URL)
    /// Symlink created successfully.
    case installed(URL)
    /// Bundled binary not found.
    case missingBundledCLI
    /// Existing item is not our symlink — refusing to overwrite user data.
    case protectedFile(URL)
    /// An error occurred.
    case failure(String)

    var isSuccess: Bool {
        switch self {
        case .alreadyInstalled, .installed: return true
        case .missingBundledCLI, .protectedFile, .failure: return false
        }
    }

    var message: String? {
        switch self {
        case .alreadyInstalled(let url):
            return "kbpulse is already installed at \(url.path)"
        case .installed(let url):
            return "Installed kbpulse at \(url.path)"
        case .missingBundledCLI:
            return "Bundled CLI not found"
        case .protectedFile(let url):
            return "Refused to replace \(url.path) — it is not our symlink"
        case .failure(let detail):
            return "Install failed: \(detail)"
        }
    }
}

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
        switch installWithStatus() {
        case .alreadyInstalled, .installed: return true
        case .missingBundledCLI, .protectedFile, .failure: return false
        }
    }

    /// Install or refresh the symlink. Returns rich status on success/failure.
    @discardableResult
    static func installWithStatus() -> CLIInstallResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: bundledCLIPath.path) else {
            return .missingBundledCLI
        }
        do {
            try fm.createDirectory(at: installDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: installPath.path) {
                // Only remove if it is already our symlink (or dangling toward us).
                if let existingDest = try? fm.destinationOfSymbolicLink(atPath: installPath.path) {
                    if existingDest == bundledCLIPath.path {
                        try fm.removeItem(at: installPath)
                    } else {
                        // Existing symlink points elsewhere — refuse to overwrite.
                        return .protectedFile(installPath)
                    }
                } else {
                    // Not a symlink at all — likely a user file; refuse to overwrite.
                    return .protectedFile(installPath)
                }
            }
            try fm.createSymbolicLink(at: installPath, withDestinationURL: bundledCLIPath)
            return .installed(installPath)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}