import Foundation

// MARK: - Data Model

enum SessionStatus: String, Codable {
    case active
    case pending
    case idle
}

enum AgentProvider: String, Codable {
    case claude
    case codex
}

enum TerminalApp: String, Codable {
    case iterm2
    case alacritty
    case ghostty
    case terminal
    case unknown
}

struct SessionInfo: Identifiable {
    let id: String
    let tty: String
    let pid: pid_t
    let cwd: String
    let provider: AgentProvider
    let terminal: TerminalApp
    let transcript: String?
    let status: SessionStatus
    let sessionId: String?
    let startTime: Date?

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var ttyShort: String {
        tty.replacingOccurrences(of: "/dev/", with: "")
    }

    var elapsedString: String? {
        guard let start = startTime else { return nil }
        let elapsed = Int(Date().timeIntervalSince(start))
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3600 { return "\(elapsed / 60)m" }
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

// MARK: - Hook State Model

struct HookSessionState: Codable {
    let sessionId: String
    let transcriptPath: String
    var cwd: String = ""

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        transcriptPath = try c.decode(String.self, forKey: .transcriptPath)
        cwd = (try? c.decode(String.self, forKey: .cwd)) ?? ""
    }

    init(sessionId: String, transcriptPath: String, cwd: String) {
        self.sessionId = sessionId
        self.transcriptPath = transcriptPath
        self.cwd = cwd
    }
}

// MARK: - Process Discovery

final class SessionDiscovery {
    static let shared = SessionDiscovery()
    private let home = NSHomeDirectory()

    func discoverAll() -> [SessionInfo] {
        let agentsByTTY = buildAgentsByTTY()
        let terminalMap = buildTerminalMap()

        var claimedTranscripts: Set<String> = []

        struct PendingSession {
            let tty: String
            let agent: AgentProcess
            let cwd: String
            let terminal: TerminalApp
        }
        var pending: [PendingSession] = []
        var sessions: [SessionInfo] = []

        // First pass: resolve hook-based transcripts (precise)
        for (tty, agent) in agentsByTTY.sorted(by: { $0.key < $1.key }) {
            let cwd = getCWD(pid: agent.pid) ?? ""
            let terminal = terminalMap[tty] ?? .unknown

            var transcript: String?
            switch agent.provider {
            case .claude:
                transcript = resolveClaudeTranscriptFromHook(tty: tty, cwd: cwd)
            case .codex:
                transcript = resolveCodexTranscript(cwd: cwd)
            }
            if let t = transcript { claimedTranscripts.insert(t) }

            if transcript != nil {
                let status = TranscriptParser.determineStatus(provider: agent.provider, transcriptPath: transcript)
                sessions.append(SessionInfo(
                    id: tty, tty: tty, pid: agent.pid, cwd: cwd,
                    provider: agent.provider, terminal: terminal,
                    transcript: transcript, status: status,
                    sessionId: loadSessionId(tty: tty, cwd: cwd),
                    startTime: getProcessStartTime(pid: agent.pid)
                ))
            } else {
                pending.append(PendingSession(tty: tty, agent: agent, cwd: cwd, terminal: terminal))
            }
        }

        // Second pass: fallback for sessions without hook state
        for p in pending {
            var transcript: String?
            if p.agent.provider == .claude {
                transcript = resolveClaudeTranscriptFallback(cwd: p.cwd, excluding: claimedTranscripts)
                if let t = transcript { claimedTranscripts.insert(t) }
            }

            let status = TranscriptParser.determineStatus(provider: p.agent.provider, transcriptPath: transcript)
            sessions.append(SessionInfo(
                id: p.tty, tty: p.tty, pid: p.agent.pid, cwd: p.cwd,
                provider: p.agent.provider, terminal: p.terminal,
                transcript: transcript, status: status,
                sessionId: loadSessionId(tty: p.tty, cwd: p.cwd),
                startTime: getProcessStartTime(pid: p.agent.pid)
            ))
        }

        sessions.sort { $0.tty < $1.tty }
        return sessions
    }

    // MARK: - Process Detection

    private struct AgentProcess {
        let pid: pid_t
        let provider: AgentProvider
    }

    private func buildAgentsByTTY() -> [String: AgentProcess] {
        var map: [String: AgentProcess] = [:]

        let all = findPIDs(processName: "claude").map { AgentProcess(pid: $0, provider: .claude) }
            + findPIDs(processName: "codex").map { AgentProcess(pid: $0, provider: .codex) }

        for agent in all {
            guard let tty = getTTY(pid: agent.pid) else { continue }
            let devTTY = "/dev/\(tty)"
            if let existing = map[devTTY], existing.pid > agent.pid { continue }
            map[devTTY] = agent
        }
        return map
    }

    private func getProcessStartTime(pid: pid_t) -> Date? {
        let output = Shell.run("ps", "-o", "lstart=", "-p", "\(pid)").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return fmt.date(from: output)
    }

    private func findPIDs(processName: String) -> [pid_t] {
        Shell.run("pgrep", "-x", processName)
            .split(separator: "\n")
            .compactMap { pid_t(String($0).trimmingCharacters(in: .whitespaces)) }
    }

    private func getTTY(pid: pid_t) -> String? {
        let output = Shell.run("ps", "-o", "tty=", "-p", "\(pid)").trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty || output == "??" ? nil : output
    }

    private func getCWD(pid: pid_t) -> String? {
        let output = Shell.run("lsof", "-p", "\(pid)", "-Fn")
        var foundCWD = false
        for line in output.split(separator: "\n") {
            let s = String(line)
            if s == "fcwd" { foundCWD = true; continue }
            if foundCWD && s.hasPrefix("n") { return String(s.dropFirst()) }
            if s.hasPrefix("f") && s != "fcwd" { foundCWD = false }
        }
        return nil
    }

    // MARK: - Terminal Detection

    private func buildTerminalMap() -> [String: TerminalApp] {
        var map: [String: TerminalApp] = [:]

        for tty in enumerateITerm2TTYs() { map[tty] = .iterm2 }
        for tty in enumerateTTYsViaLsof(processName: "ghostty") where map[tty] == nil { map[tty] = .ghostty }
        for tty in enumerateTTYsViaLsof(processName: "alacritty") where map[tty] == nil { map[tty] = .alacritty }
        for tty in enumerateTTYsViaLsof(processName: "Terminal") where map[tty] == nil { map[tty] = .terminal }

        return map
    }

    private func enumerateITerm2TTYs() -> [String] {
        let script = """
        tell application "System Events"
            if not (exists process "iTerm2") then return ""
        end tell
        tell application "iTerm2"
            set output to ""
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        set output to output & (tty of s) & linefeed
                    end repeat
                end repeat
            end repeat
            return output
        end tell
        """
        return Shell.appleScript(script)
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func enumerateTTYsViaLsof(processName: String) -> [String] {
        var ttys: [String] = []
        for line in Shell.run("lsof", "-c", processName).split(separator: "\n") {
            for field in String(line).split(separator: " ") {
                let s = String(field)
                if s.hasPrefix("/dev/ttys") && !ttys.contains(s) {
                    ttys.append(s)
                }
            }
        }
        return ttys
    }

    // MARK: - Transcript Resolution

    private func projectHash(_ cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
           .replacingOccurrences(of: "_", with: "-")
    }

    private func resolveClaudeTranscriptFromHook(tty: String, cwd: String) -> String? {
        let hash = projectHash(cwd)
        let ttyShort = tty.replacingOccurrences(of: "/dev/", with: "")

        // Try claude-mosaic state
        let stateFile = "\(home)/.claude/claude-mosaic/\(hash)/session-\(ttyShort).json"
        if let path = transcriptFromStateFile(stateFile) { return path }

        // Try claude-bar state (compatibility)
        let barStateFile = "\(home)/.claude/claude-bar/\(hash)/session-\(ttyShort).json"
        if let path = transcriptFromStateFile(barStateFile) { return path }

        return nil
    }

    private func transcriptFromStateFile(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let state = try? JSONDecoder().decode(HookSessionState.self, from: data),
              FileManager.default.fileExists(atPath: state.transcriptPath) else { return nil }
        return state.transcriptPath
    }

    private func resolveClaudeTranscriptFallback(cwd: String, excluding claimed: Set<String>) -> String? {
        let projectDir = "\(home)/.claude/projects/\(projectHash(cwd))"
        return mostRecentJSONL(in: projectDir, excluding: claimed)
    }

    private func resolveCodexTranscript(cwd: String) -> String? {
        let sessionsDir = "\(home)/.codex/sessions"
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: sessionsDir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        // Codex stores sessions in per-project subdirectories named after the cwd.
        // Match by checking if the jsonl path contains the project directory name,
        // or by reading the first line for a cwd field.
        let cwdDirName = URL(fileURLWithPath: cwd).lastPathComponent
        var best: (path: String, date: Date)?
        var fallback: (path: String, date: Date)?

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            guard let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }

            // Check if this transcript belongs to the same project
            let pathStr = url.path
            if pathStr.contains(cwdDirName) || codexTranscriptMatchesCWD(path: pathStr, cwd: cwd) {
                if best == nil || mod > best!.date { best = (pathStr, mod) }
            } else {
                if fallback == nil || mod > fallback!.date { fallback = (pathStr, mod) }
            }
        }
        // Prefer exact match, fall back to most recent only if no match found
        return best?.path ?? fallback?.path
    }

    private func codexTranscriptMatchesCWD(path: String, cwd: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { fh.closeFile() }
        // Read first 4KB to find cwd in initial session metadata
        let data = fh.readData(ofLength: 4096)
        guard let head = String(data: data, encoding: .utf8) else { return false }
        return head.contains(cwd)
    }

    private func mostRecentJSONL(in dir: String, excluding claimed: Set<String> = []) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: dir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return contents
            .filter { $0.pathExtension == "jsonl" && !claimed.contains($0.path) }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }
            .first?.path
    }

    private func loadSessionId(tty: String, cwd: String) -> String? {
        let hash = projectHash(cwd)
        let ttyShort = tty.replacingOccurrences(of: "/dev/", with: "")
        let stateFile = "\(home)/.claude/claude-mosaic/\(hash)/session-\(ttyShort).json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
              let state = try? JSONDecoder().decode(HookSessionState.self, from: data) else { return nil }
        return state.sessionId
    }
}
