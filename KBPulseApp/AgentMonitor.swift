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
        // Scan both command name (comm) and full arguments/command line (args) to catch CLI wrappers like node running opencode/claude
        process.arguments = ["-A", "-o", "comm=,args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        var names = Set<String>()
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip header lines from ps output
            guard !trimmed.lowercased().starts(with: "comm") else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let comm = parts.first {
                let base = (String(comm) as NSString).lastPathComponent
                if !base.isEmpty { names.insert(base) }
            }
            if parts.count > 1 {
                let args = parts[1]
                let argParts = args.split(separator: " ", omittingEmptySubsequences: true)
                for arg in argParts {
                    let argBase = (String(arg) as NSString).lastPathComponent
                    if !argBase.isEmpty { names.insert(argBase) }
                }
            }
        }
        // Explicit deduplication via Set already handles this, but also lowercase-normalize
        // to ensure "Codex" and "codex" are treated as the same agent.
        return names
    }
}