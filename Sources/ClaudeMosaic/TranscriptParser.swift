import Foundation

// MARK: - Transcript Parser

enum TranscriptParser {

    /// Determine session status from transcript file.
    static func determineStatus(provider: AgentProvider, transcriptPath: String?) -> SessionStatus {
        guard let path = transcriptPath, !path.isEmpty else { return .idle }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return .idle
        }

        let age = Date().timeIntervalSince(modDate)

        switch provider {
        case .claude:
            return determineClaudeStatus(path: path, fileAge: age)
        case .codex:
            return determineCodexStatus(path: path, fileAge: age)
        }
    }

    // MARK: - Claude Status

    private static func determineClaudeStatus(path: String, fileAge: TimeInterval) -> SessionStatus {
        let tail = readTail(path: path, maxBytes: 65536)
        let (lastRole, hasPendingTool, inPlanMode) = parseClaudeTranscript(tail)

        // Recent file activity → active
        if fileAge < 10 {
            if hasPendingTool { return .pending }
            return .active
        }

        // Pending tool_use
        if hasPendingTool {
            // In plan mode: stay pending (user reviewing plan, no timeout)
            if inPlanMode { return .pending }
            // Grace: if file age < 3s, tool might auto-complete
            if fileAge < 3 { return .active }
            // Timeout: after 120s assume abandoned
            if fileAge > 120 { return .idle }
            return .pending
        }

        // Last message from user → Claude is thinking (API latency)
        if lastRole == "user" {
            return fileAge < 120 ? .active : .idle
        }

        // In plan mode with no pending tool → waiting for user review
        if inPlanMode {
            return .pending
        }

        return .idle
    }

    /// Parse Claude JSONL transcript tail.
    /// Returns (lastRole, hasPendingTool, inPlanMode).
    private static func parseClaudeTranscript(_ content: String) -> (String?, Bool, Bool) {
        var lastRole: String?
        var pendingToolUseIds: Set<String> = []
        var inPlanMode = false

        for line in content.split(separator: "\n") {
            guard let obj = parseJSON(String(line)) else { continue }

            // Track role
            if let role = obj["role"] as? String {
                if role == "user" || role == "assistant" {
                    lastRole = role
                }
            }

            // Track tool_use / tool_result pairing
            if let role = obj["role"] as? String, role == "assistant",
               let content = obj["content"] as? [[String: Any]] {
                for block in content {
                    if let type = block["type"] as? String {
                        if type == "tool_use", let id = block["id"] as? String {
                            pendingToolUseIds.insert(id)
                        }
                    }
                }
            }

            if let role = obj["role"] as? String, role == "user",
               let content = obj["content"] as? [[String: Any]] {
                for block in content {
                    if let type = block["type"] as? String,
                       type == "tool_result",
                       let id = block["tool_use_id"] as? String {
                        pendingToolUseIds.remove(id)
                    }
                }
            }

            // Track plan mode
            if let content = obj["content"] as? [[String: Any]] {
                for block in content {
                    if let type = block["type"] as? String, type == "tool_use",
                       let name = block["name"] as? String {
                        if name == "EnterPlanMode" { inPlanMode = true }
                        if name == "ExitPlanMode" { inPlanMode = false }
                    }
                }
            }
        }

        return (lastRole, !pendingToolUseIds.isEmpty, inPlanMode)
    }

    // MARK: - Codex Status

    private static func determineCodexStatus(path: String, fileAge: TimeInterval) -> SessionStatus {
        let tail = readTail(path: path, maxBytes: 65536)

        // Track escalation call IDs and their completions
        var pendingEscalationIds: Set<String> = []
        var hasPendingCall = false

        for line in tail.split(separator: "\n") {
            guard let obj = parseJSON(String(line)) else { continue }
            guard let type = obj["type"] as? String else { continue }

            if type == "response_item", let payload = obj["payload"] as? [String: Any] {
                let itemType = payload["type"] as? String
                let callId = payload["call_id"] as? String ?? payload["id"] as? String

                if itemType == "function_call" {
                    if let sandbox = payload["sandbox_permissions"] as? String,
                       sandbox == "require_escalated",
                       let id = callId {
                        pendingEscalationIds.insert(id)
                    } else {
                        hasPendingCall = true
                    }
                }

                // function_call_output completes a prior function_call
                if itemType == "function_call_output", let id = callId {
                    pendingEscalationIds.remove(id)
                    hasPendingCall = false
                }
            }
        }

        if !pendingEscalationIds.isEmpty { return .pending }
        if hasPendingCall && fileAge < 10 { return .active }
        if fileAge < 10 { return .active }
        return .idle
    }

    // MARK: - Helpers

    private static func readTail(path: String, maxBytes: Int) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { fh.closeFile() }

        let size = fh.seekToEndOfFile()
        let chunk = min(UInt64(maxBytes), size)
        guard chunk > 0 else { return "" }

        fh.seek(toFileOffset: size - chunk)
        let data = fh.readData(ofLength: Int(chunk))
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func parseJSON(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
