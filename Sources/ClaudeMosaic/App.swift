import SwiftUI
import AppKit

// MARK: - Main Entry Point

@main
struct ClaudeMosaicApp {
    static func main() {
        let args = CommandLine.arguments

        if args.count > 1 {
            switch args[1] {
            case "poll":
                printSessionsJSON()
            case "hook":
                HookManager.handleHook()
            case "hooks-install":
                let cmd = flagValue(flag: "--command", args: args) ?? "\(args[0]) hook"
                let settings = flagValue(flag: "--settings", args: args)
                HookManager.installHook(command: cmd, settingsPath: settings)
            case "hooks-uninstall":
                let settings = flagValue(flag: "--settings", args: args)
                HookManager.uninstallHooks(settingsPath: settings)
            case "unregister":
                AutoSetup.unregisterLoginItem()
                print("Login item unregistered.")
            case "focus":
                let terminal = flagValue(flag: "--terminal", args: args) ?? "unknown"
                let tty = flagValue(flag: "--tty", args: args) ?? ""
                let cwd = flagValue(flag: "--cwd", args: args) ?? ""
                let session = SessionInfo(
                    id: tty, tty: tty, pid: 0, cwd: cwd,
                    provider: .claude,
                    terminal: TerminalApp(rawValue: terminal) ?? .unknown,
                    transcript: nil, status: .idle, sessionId: nil, startTime: nil
                )
                TerminalFocus.focus(session: session)
            case "demo":
                launchApp(demo: true, demoCount: args.count > 2 ? Int(args[2]) : nil)
            case "test-notify":
                NSSound(named: "Glass")?.play()
                print("Sound played!")
                Thread.sleep(forTimeInterval: 1)
            default:
                printUsage()
            }
            return
        }

        launchApp(demo: false, demoCount: nil)
    }

    private static func launchApp(demo: Bool, demoCount: Int?) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MosaicAppDelegate()
        delegate.demoMode = demo
        if let n = demoCount, n > 0 { delegate.demoCount = n }
        app.delegate = delegate
        app.run()
    }

    private static func printSessionsJSON() {
        let sessions = SessionDiscovery.shared.discoverAll()
        let output = sessions.map { s -> [String: Any] in
            var d: [String: Any] = [
                "tty": s.tty, "pid": s.pid, "cwd": s.cwd,
                "provider": s.provider.rawValue,
                "terminal": s.terminal.rawValue,
                "status": s.status.rawValue,
            ]
            if let t = s.transcript { d["transcript"] = t }
            if let sid = s.sessionId { d["session_id"] = sid }
            if let e = s.elapsedString { d["elapsed"] = e }
            return d
        }
        if let data = try? JSONSerialization.data(withJSONObject: output, options: []),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    private static func flagValue(flag: String, args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func printUsage() {
        print("""
        claude-mosaic — Menu bar monitor for Claude Code sessions

        USAGE:
            claude-mosaic              Launch menu bar app
            claude-mosaic poll         Discover sessions, print JSON
            claude-mosaic hook         SessionStart hook handler (stdin)
            claude-mosaic focus        Focus terminal window
            claude-mosaic demo [N]     Demo mode with N sessions
            claude-mosaic hooks-install   Register hook in settings.json
            claude-mosaic hooks-uninstall Remove hooks from settings.json
        """)
    }
}

// MARK: - Observable Store

class SessionStore: ObservableObject {
    @Published var sessions: [SessionInfo] = []
}

// MARK: - App Delegate

class MosaicAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var pollTimer: Timer?
    var animTimer: Timer?
    let store = SessionStore()
    var demoMode = false
    var demoCount: Int?
    var previousStatuses: [String: SessionStatus] = [:]

    var sessions: [SessionInfo] {
        get { store.sessions }
        set { store.sessions = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AutoSetup.ensureSetup()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = false

        if let button = statusItem.button {
            button.action = #selector(showMenu)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        pollAndUpdate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollAndUpdate()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    // MARK: - Polling

    func pollAndUpdate() {
        if demoMode {
            if let n = demoCount {
                let all = Self.demoSessions
                sessions = (0..<n).map { i in
                    let base = all[i % all.count]
                    return SessionInfo(
                        id: "/dev/ttys\(String(format: "%03d", i))",
                        tty: "/dev/ttys\(String(format: "%03d", i))",
                        pid: pid_t(1000 + i), cwd: base.cwd,
                        provider: base.provider, terminal: base.terminal,
                        transcript: nil, status: base.status,
                        sessionId: "demo-\(i)", startTime: base.startTime
                    )
                }
            } else {
                sessions = Self.demoSessions
            }
            updateUI()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SessionDiscovery.shared.discoverAll()
            DispatchQueue.main.async {
                self?.sessions = result
                self?.updateUI()
            }
        }
    }

    static let demoSessions: [SessionInfo] = [
        SessionInfo(id: "/dev/ttys001", tty: "/dev/ttys001", pid: 1001,
                    cwd: "/Users/demo/my-app", provider: .claude, terminal: .iterm2,
                    transcript: nil, status: .active, sessionId: "demo-1",
                    startTime: Date().addingTimeInterval(-185)),
        SessionInfo(id: "/dev/ttys002", tty: "/dev/ttys002", pid: 2002,
                    cwd: "/Users/demo/api-server", provider: .claude, terminal: .iterm2,
                    transcript: nil, status: .pending, sessionId: "demo-2",
                    startTime: Date().addingTimeInterval(-4520)),
        SessionInfo(id: "/dev/ttys003", tty: "/dev/ttys003", pid: 3003,
                    cwd: "/Users/demo/frontend", provider: .codex, terminal: .ghostty,
                    transcript: nil, status: .idle, sessionId: "demo-3",
                    startTime: Date().addingTimeInterval(-720)),
        SessionInfo(id: "/dev/ttys004", tty: "/dev/ttys004", pid: 4004,
                    cwd: "/Users/demo/ml-pipeline", provider: .claude, terminal: .alacritty,
                    transcript: nil, status: .active, sessionId: "demo-4",
                    startTime: Date().addingTimeInterval(-45)),
        SessionInfo(id: "/dev/ttys005", tty: "/dev/ttys005", pid: 5005,
                    cwd: "/Users/demo/docs", provider: .codex, terminal: .terminal,
                    transcript: nil, status: .pending, sessionId: "demo-5",
                    startTime: Date().addingTimeInterval(-10800)),
        SessionInfo(id: "/dev/ttys006", tty: "/dev/ttys006", pid: 6006,
                    cwd: "/Users/demo/infra", provider: .claude, terminal: .iterm2,
                    transcript: nil, status: .active, sessionId: "demo-6",
                    startTime: Date().addingTimeInterval(-600)),
        SessionInfo(id: "/dev/ttys007", tty: "/dev/ttys007", pid: 7007,
                    cwd: "/Users/demo/mobile", provider: .claude, terminal: .iterm2,
                    transcript: nil, status: .idle, sessionId: "demo-7",
                    startTime: Date().addingTimeInterval(-1800)),
        SessionInfo(id: "/dev/ttys008", tty: "/dev/ttys008", pid: 8008,
                    cwd: "/Users/demo/data", provider: .codex, terminal: .ghostty,
                    transcript: nil, status: .active, sessionId: "demo-8",
                    startTime: Date().addingTimeInterval(-90)),
        SessionInfo(id: "/dev/ttys009", tty: "/dev/ttys009", pid: 9009,
                    cwd: "/Users/demo/tests", provider: .claude, terminal: .iterm2,
                    transcript: nil, status: .pending, sessionId: "demo-9",
                    startTime: Date().addingTimeInterval(-300)),
    ]

    // MARK: - UI Updates

    func updateUI() {
        if sessions.isEmpty {
            statusItem.isVisible = false
            stopAnimation()
            previousStatuses.removeAll()
            return
        }

        for session in sessions {
            let prev = previousStatuses[session.tty]
            if session.status == .pending && prev != nil && prev != .pending {
                NSSound(named: "Glass")?.play()
                NSApp.requestUserAttention(.informationalRequest)
            }
            previousStatuses[session.tty] = session.status
        }

        statusItem.isVisible = true
        updateIcon()

        let needsAnim = sessions.contains { $0.status == .pending || $0.status == .idle }
        if needsAnim { startAnimation() } else { stopAnimation() }
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem()
        let rows = max((sessions.count + 1) / 2, 1)
        let gridHeight = CGFloat(rows) * 64
        let totalHeight = min(36 + gridHeight + 28, 460)
        let view = NSHostingView(rootView: MosaicPanelView(
            store: store,
            onFocus: { session in
                menu.cancelTracking()
                TerminalFocus.focus(session: session)
            },
            onQuit: {
                menu.cancelTracking()
                NSApplication.shared.terminate(nil)
            }
        ))
        view.frame = NSRect(x: 0, y: 0, width: 320, height: totalHeight)
        item.view = view
        menu.addItem(item)
        return menu
    }

    @objc func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }


    // MARK: - Menu Bar Icon

    func updateIcon() {
        guard let button = statusItem.button else { return }

        let count = sessions.count
        let maxTiles = 6
        let hasOverflow = count > maxTiles
        let shown = min(count, maxTiles)
        let rows = shown <= 3 ? 1 : 2
        let cols = (shown + rows - 1) / rows

        let tileSize: CGFloat = 6
        let gap: CGFloat = 1.5
        let radius: CGFloat = 1.2

        let gridW = CGFloat(cols) * tileSize + CGFloat(max(cols - 1, 0)) * gap
        let gridH = CGFloat(rows) * tileSize + CGFloat(max(rows - 1, 0)) * gap
        let overflowW: CGFloat = hasOverflow ? tileSize + gap : 0
        let w = gridW + 4 + overflowW
        let h: CGFloat = 22

        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { [self] rect in
            let startY = (rect.height - gridH) / 2
            let startX: CGFloat = 2

            for i in 0..<shown {
                let session = sessions[i]
                let col = i / rows
                let row = i % rows
                let x = startX + CGFloat(col) * (tileSize + gap)
                let y = startY + CGFloat(rows - 1 - row) * (tileSize + gap)

                let color = Self.nsColorForStatus(session.status)
                let alpha = alphaForStatus(session.status)

                let tileRect = NSRect(x: x, y: y, width: tileSize, height: tileSize)
                let path = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)
                color.withAlphaComponent(alpha).setFill()
                path.fill()
            }

            if hasOverflow {
                let overflowX = startX + CGFloat(cols) * (tileSize + gap)
                let ghostColor = NSColor.gray.withAlphaComponent(0.35)
                for row in 0..<rows {
                    let y = startY + CGFloat(rows - 1 - row) * (tileSize + gap)
                    let tileRect = NSRect(x: overflowX, y: y, width: tileSize, height: tileSize)
                    let path = NSBezierPath(roundedRect: tileRect, xRadius: radius, yRadius: radius)
                    ghostColor.setFill()
                    path.fill()
                }
            }

            return true
        }
        img.isTemplate = false
        button.image = img
    }

    static func nsColorForStatus(_ status: SessionStatus) -> NSColor {
        switch status {
        case .active:  return NSColor(srgbRed: 0x34/255, green: 0xD3/255, blue: 0x99/255, alpha: 1)
        case .pending: return NSColor(srgbRed: 0xFB/255, green: 0xBF/255, blue: 0x24/255, alpha: 1)
        case .idle:    return NSColor(srgbRed: 0x6B/255, green: 0x72/255, blue: 0x80/255, alpha: 1)
        }
    }

    func alphaForStatus(_ status: SessionStatus) -> CGFloat {
        guard status != .active else { return 1.0 }
        guard animTimer != nil else { return 0.85 }
        let period: Double = 3.0
        let t = Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return CGFloat(0.35 + 0.5 * (0.5 + 0.5 * sin(t * 2 * .pi)))
    }

    // MARK: - Animation

    func startAnimation() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.updateIcon()
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
