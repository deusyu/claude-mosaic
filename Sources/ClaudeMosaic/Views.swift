import SwiftUI

// MARK: - Main Panel

struct MosaicPanelView: View {
    @ObservedObject var store: SessionStore
    let onFocus: (SessionInfo) -> Void
    let onQuit: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    MosaicLogoView()
                    Text("Mosaic")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(MosaicTheme.text)
                }

                Spacer()

                HStack(spacing: 6) {
                    let counts = statusCounts
                    if counts.active > 0 {
                        StatusBadge(count: counts.active, status: .active)
                    }
                    if counts.pending > 0 {
                        StatusBadge(count: counts.pending, status: .pending)
                    }
                    if counts.idle > 0 {
                        StatusBadge(count: counts.idle, status: .idle)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if store.sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 28))
                        .foregroundColor(MosaicTheme.subtle)
                    Text("No sessions")
                        .font(.system(size: 12))
                        .foregroundColor(MosaicTheme.textDim)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(store.sessions) { session in
                            MosaicTile(session: session)
                                .onTapGesture { onFocus(session) }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }

            HStack {
                Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(MosaicTheme.textDim)
                Spacer()
                Button(action: onQuit) {
                    Text("Quit ⌘Q")
                        .font(.system(size: 10))
                        .foregroundColor(MosaicTheme.textDim)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    private var statusCounts: (active: Int, pending: Int, idle: Int) {
        var a = 0, p = 0, i = 0
        for s in store.sessions {
            switch s.status {
            case .active: a += 1
            case .pending: p += 1
            case .idle: i += 1
            }
        }
        return (a, p, i)
    }
}

// MARK: - Mini Mosaic Logo

struct MosaicLogoView: View {
    var body: some View {
        VStack(spacing: 1.5) {
            HStack(spacing: 1.5) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(MosaicTheme.emerald)
                    .frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1)
                    .fill(MosaicTheme.amber)
                    .frame(width: 5, height: 5)
            }
            HStack(spacing: 1.5) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(MosaicTheme.slate)
                    .frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1)
                    .fill(MosaicTheme.emerald)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let count: Int
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(MosaicTheme.statusColor(status))
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(MosaicTheme.statusColor(status))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(MosaicTheme.statusColor(status).opacity(0.12))
        .cornerRadius(4)
    }
}

// MARK: - Mosaic Tile

struct MosaicTile: View {
    let session: SessionInfo
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MosaicTheme.text)
                    .lineLimit(1)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(MosaicTheme.statusColor(session.status))
                    .frame(width: 7, height: 7)
            }

            HStack(spacing: 0) {
                Text(session.provider.rawValue.capitalized)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(MosaicTheme.providerColor(session.provider))
                Spacer()
                if let elapsed = session.elapsedString {
                    Text(elapsed)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(MosaicTheme.textDim)
                }
            }
        }
        .padding(8)
        .frame(height: 56)
        .background(
            ZStack {
                MosaicTheme.cardBg
                MosaicTheme.statusGradient(session.status)
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHovered
                        ? MosaicTheme.statusColor(session.status).opacity(0.5)
                        : MosaicTheme.subtle.opacity(0.4),
                    lineWidth: isHovered ? 1.5 : 0.5
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
    }
}
