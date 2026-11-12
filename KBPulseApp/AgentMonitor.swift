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
    private static let refreshQueue = DispatchQueue(label: "com.kbpulse.agentmonitor")
    private static let cacheLock = NSLock()
    private static var _cachedScanResult: Set<String>? = nil
    private static var _cacheDate: Date?
    private static var _scanInFlight = false

    /// How long a cached scan is considered fresh. Reads older than this kick
    /// off a background refresh and keep serving the previous result.
    private static let maxCacheAge: TimeInterval = 1.5

    static var activeAgents: [String]? {
        let names = Set(HookStore.monitoredNames().map { $0.lowercased() })
        guard !names.isEmpty else { return [] }

        cacheLock.lock()
        let needsInitialScan = _cachedScanResult == nil
        cacheLock.unlock()

        if needsInitialScan {
            // First read after launch blocks once so the UI has data. Later
            // reads never block: they use the cache and refresh in the
            // background when stale.
            let fresh = scan()
            cacheLock.lock()
            if let fresh {
                _cachedScanResult = fresh
                _cacheDate = Date()
            }
            cacheLock.unlock()
        } else {
            refreshIfStale()
        }

        cacheLock.lock()
        let scanned = _cachedScanResult
        cacheLock.unlock()
        guard let scanned else { return nil }
        return scanned.filter { names.contains($0.lowercased()) }.sorted()
    }

    /// Runs a fresh `ps` scan on a background queue and caches the result so
    /// future `activeAgents` reads do not block the caller's thread.
    /// Coalesces concurrent requests so a slow scan cannot queue up work.
    static func refreshAsync() {
        cacheLock.lock()
        guard !_scanInFlight else {
            cacheLock.unlock()
            return
        }
        _scanInFlight = true
        cacheLock.unlock()

        refreshQueue.async {
            let fresh = scan()
            cacheLock.lock()
            if let fresh {
                _cachedScanResult = fresh
                _cacheDate = Date()
            }
            _scanInFlight = false
            cacheLock.unlock()
        }
    }

    private static func refreshIfStale() {
        cacheLock.lock()
        let age = _cacheDate.map { Date().timeIntervalSince($0) } ?? .infinity
        cacheLock.unlock()
        if age > maxCacheAge {
            refreshAsync()
        }
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
                if !base.isEmpty { names.insert(base.lowercased()) }
            }
            if parts.count > 1 {
                let args = parts[1]
                let argParts = args.split(separator: " ", omittingEmptySubsequences: true)
                for arg in argParts {
                    let argBase = (String(arg) as NSString).lastPathComponent
                    if !argBase.isEmpty { names.insert(argBase.lowercased()) }
                }
            }
        }
        return names
    }
}