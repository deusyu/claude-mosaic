import Foundation

enum TerminalFocus {

    static func focus(session: SessionInfo) {
        switch session.terminal {
        case .iterm2:   focusITerm2(tty: session.tty)
        case .alacritty: focusAlacritty(cwd: session.cwd)
        case .ghostty:  focusGhostty(cwd: session.cwd)
        case .terminal: focusTerminalApp(tty: session.tty)
        case .unknown:  focusITerm2(tty: session.tty)
        }
    }

    private static func focusITerm2(tty: String) {
        Shell.appleScript("""
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            tell w to select t
                            tell t to select s
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """)
    }

    private static func focusAlacritty(cwd: String) {
        focusByWindowTitle(process: "Alacritty", cwd: cwd)
    }

    private static func focusGhostty(cwd: String) {
        focusByWindowTitle(process: "ghostty", cwd: cwd)
    }

    /// Match window title against full cwd first, then basename as fallback.
    private static func focusByWindowTitle(process: String, cwd: String) {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        Shell.appleScript("""
        tell application "System Events"
            set wins to every window of process "\(process)"
            -- First pass: match full path
            repeat with w in wins
                if name of w contains "\(cwd)" then
                    perform action "AXRaise" of w
                    set frontmost of process "\(process)" to true
                    return
                end if
            end repeat
            -- Second pass: match basename
            repeat with w in wins
                if name of w contains "\(dirName)" then
                    perform action "AXRaise" of w
                    set frontmost of process "\(process)" to true
                    return
                end if
            end repeat
            set frontmost of process "\(process)" to true
        end tell
        """)
    }

    private static func focusTerminalApp(tty: String) {
        Shell.appleScript("""
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
            activate
        end tell
        """)
    }
}
