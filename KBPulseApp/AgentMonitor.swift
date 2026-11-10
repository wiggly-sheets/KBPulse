//
//  AgentMonitor.swift
//  KBPulseApp
//
//  Detects coding agents (codex, claude code, opencode, herdr, pi, …) by
//  scanning the live process table. Two transitions matter:
//    running  → "needs attention": backlight switches to a hook theme override.
//    exit     → "done": the hook's action fires (flash), then the base theme
//               applies again or the remaining agent keeps its override.
//
//  Agents are CLI tools launched inside a terminal, so they never show up in
//  NSWorkspace.runningApplications — we scan the process table instead.
//

import Foundation

enum AgentMonitor {
    /// Basenames currently matched in the process table. Empty when no agent
    /// runs; nil when the process-table scan failed.
    static var activeAgents: [String]? {
        let names = Set(HookStore.monitoredNames().map { $0.lowercased() })
        guard !names.isEmpty else { return [] }
        guard let scanned = scan() else { return nil }
        return scanned.filter { names.contains($0.lowercased()) }.sorted()
    }

    // MARK: - Process table scan

    /// Returns the set of executable basenames currently in the process table,
    /// or nil when `ps` could not be run or its output could not be read.
    private static func scan() -> Set<String>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Drain stdout before waiting: a full pipe buffer would block exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        var names = Set<String>()
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Full paths from ps (e.g. /opt/homebrew/bin/codex); keep the basename.
            let base = (trimmed as NSString).lastPathComponent
            if !base.isEmpty { names.insert(base) }
        }
        return names
    }
}