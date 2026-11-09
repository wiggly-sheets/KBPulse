//
//  AgentMonitor.swift
//  KBPulseApp
//
//  Detects coding agents (codex, claude code, opencode, herdr, pi, …) by
//  scanning the live process table. Two transitions matter:
//    running  → "needs attention": backlight switches to the hook theme.
//    exit    → "done": the hook's action fires (flash), then the base theme
//             is restored.
//
//  Agents are CLI tools launched inside a terminal, so they never show up in
//  NSWorkspace.runningApplications — we scan the process table instead.
//

import Foundation

enum AgentMonitor {
    /// Names currently matched in the process table. Empty when no agent runs.
    static var activeAgents: [String] {
        let names = HookStore.monitoredNames()
        guard !names.isEmpty else { return [] }
        let running = scan()
        return names.filter { running.contains($0) }
    }

    /// True when at least one monitored agent process is alive.
    static var isRunning: Bool { !activeAgents.isEmpty }

    // MARK: - Process table scan

    /// Returns the set of executable basenames currently in the process table.
    private static func scan() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-o", "comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return []
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