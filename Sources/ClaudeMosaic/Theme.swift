import SwiftUI

enum MosaicTheme {
    // Status colors
    static let emerald = Color(nsColor: NSColor(srgbRed: 0x34/255, green: 0xD3/255, blue: 0x99/255, alpha: 1))
    static let amber   = Color(nsColor: NSColor(srgbRed: 0xFB/255, green: 0xBF/255, blue: 0x24/255, alpha: 1))
    static let slate   = Color(nsColor: NSColor(srgbRed: 0x6B/255, green: 0x72/255, blue: 0x80/255, alpha: 1))

    // Provider brand colors
    static let claudeOrange = Color(nsColor: NSColor(srgbRed: 0xD9/255, green: 0x77/255, blue: 0x57/255, alpha: 1))
    static let codexGreen   = Color(nsColor: NSColor(srgbRed: 0x10/255, green: 0xA3/255, blue: 0x7F/255, alpha: 1))

    // Adaptive
    static let bg      = Color(NSColor.windowBackgroundColor)
    static let cardBg  = Color(NSColor.controlBackgroundColor)
    static let subtle  = Color(NSColor.separatorColor)
    static let text    = Color(NSColor.labelColor)
    static let textDim = Color(NSColor.secondaryLabelColor)

    static func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .active:  return emerald
        case .pending: return amber
        case .idle:    return slate
        }
    }

    static func providerColor(_ provider: AgentProvider) -> Color {
        switch provider {
        case .claude: return claudeOrange
        case .codex:  return codexGreen
        }
    }

    static func statusGradient(_ status: SessionStatus) -> LinearGradient {
        let base = statusColor(status)
        return LinearGradient(
            colors: [base.opacity(0.2), base.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
