import Foundation

enum HookManager {

    private static let hookPatterns = ["claude-mosaic", "claude-bar", "session-track.sh", "update-status.sh"]
    private static let home = NSHomeDirectory()

    // MARK: - Hook Handler (stdin → state file)

    static func handleHook() {
        guard let data = Optional(FileHandle.standardInput.availableData),
              !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = obj["session_id"] as? String,
              let transcriptPath = obj["transcript_path"] as? String else { return }

        let cwd = (obj["cwd"] as? String) ?? FileManager.default.currentDirectoryPath
        guard let (_, tty) = findClaudeAncestor(pid: getppid()) else { return }

        let hash = projectHash(cwd)
        let ttyShort = tty.replacingOccurrences(of: "/dev/", with: "")
        let stateDir = "\(home)/.claude/claude-mosaic/\(hash)"

        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

        let state = HookSessionState(sessionId: sessionId, transcriptPath: transcriptPath, cwd: cwd)
        if let encoded = try? JSONEncoder().encode(state) {
            try? encoded.write(to: URL(fileURLWithPath: "\(stateDir)/session-\(ttyShort).json"))
        }
    }

    // MARK: - Install / Uninstall

    static func installHook(command: String, settingsPath: String? = nil) {
        let path = settingsPath ?? "\(home)/.claude/settings.json"
        var settings = loadSettings(path: path)

        cleanLegacyHooks(settings: &settings)

        if hookExists(settings: settings, command: command) {
            print("Hook already installed.")
            return
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var sessionStart = hooks["SessionStart"] as? [[String: Any]] ?? []
        sessionStart.append(["hooks": [["type": "command", "command": command]]])
        hooks["SessionStart"] = sessionStart
        settings["hooks"] = hooks

        writeSettings(settings: settings, path: path)
        print("Hook installed: SessionStart → \(command)")
    }

    static func uninstallHooks(settingsPath: String? = nil) {
        let path = settingsPath ?? "\(home)/.claude/settings.json"
        var settings = loadSettings(path: path)

        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        var changed = false
        for eventKey in hooks.keys {
            guard var matchers = hooks[eventKey] as? [[String: Any]] else { continue }
            let before = matchers.count
            matchers = matchers.filter { matcher in
                guard let hookList = matcher["hooks"] as? [[String: Any]] else { return true }
                return hookList.contains { hook in
                    guard let cmd = hook["command"] as? String else { return true }
                    return !hookPatterns.contains(where: { cmd.contains($0) })
                }
            }
            if matchers.count != before {
                hooks[eventKey] = matchers
                changed = true
            }
        }

        if changed {
            settings["hooks"] = hooks
            writeSettings(settings: settings, path: path)
            print("Hooks uninstalled.")
        } else {
            print("No hooks to remove.")
        }
    }

    // MARK: - Helpers

    private static func projectHash(_ cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
           .replacingOccurrences(of: "_", with: "-")
    }

    private static func findClaudeAncestor(pid: pid_t) -> (pid_t, String)? {
        var current = pid
        while current > 1 {
            let comm = Shell.run("ps", "-o", "comm=", "-p", "\(current)").trimmingCharacters(in: .whitespacesAndNewlines)
            if comm == "claude" {
                let tty = Shell.run("ps", "-o", "tty=", "-p", "\(current)").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tty.isEmpty, tty != "??" else { return nil }
                return (current, "/dev/\(tty)")
            }
            guard let ppid = pid_t(Shell.run("ps", "-o", "ppid=", "-p", "\(current)").trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            current = ppid
        }
        return nil
    }

    private static func hookExists(settings: [String: Any], command: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any],
              let sessionStart = hooks["SessionStart"] as? [[String: Any]] else { return false }
        return sessionStart.contains { matcher in
            (matcher["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == command } ?? false
        }
    }

    private static func cleanLegacyHooks(settings: inout [String: Any]) {
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        let legacyPatterns = ["session-track.sh", "update-status.sh"]

        for eventKey in hooks.keys {
            guard var matchers = hooks[eventKey] as? [[String: Any]] else { continue }
            matchers = matchers.filter { matcher in
                guard let hookList = matcher["hooks"] as? [[String: Any]] else { return true }
                return hookList.contains { hook in
                    guard let cmd = hook["command"] as? String else { return true }
                    return !legacyPatterns.contains(where: { cmd.contains($0) })
                }
            }
            hooks[eventKey] = matchers
        }
        settings["hooks"] = hooks
    }

    private static func loadSettings(path: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private static func writeSettings(settings: [String: Any], path: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
