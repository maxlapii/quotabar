//
//  Views.swift
//  ClaudeStatus
//
//  Menu bar label + dropdown panel.
//

import SwiftUI
import AppKit

// MARK: - Menu bar label

/// The compact label shown in the menu bar:
///
///     [Claude icon] 09% ▯▯▯▯▯ | W 64% | F 80%
///
/// The 5-hour window keeps its block gauge; the weekly (W) and Fable (F)
/// percentages are tinted green / orange / red instead of having gauges.
/// Rounded system font, monospaced digits, tight spacing. Rendered to an image
/// with AppKit because MenuBarExtra flattens SwiftUI text colours in labels.
struct StatusLabelView: View {
    let snapshot: UsageSnapshot?
    let hasError: Bool

    var body: some View {
        Image(nsImage: LabelRenderer.render(snapshot: snapshot, hasError: hasError))
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let s = snapshot else { return "Claude usage unavailable" }
        return "Claude usage: session \(s.fiveHour.percent) percent, week \(s.sevenDay.percent) percent, Fable \(s.fable.percent) percent"
    }
}

/// Shared colour scale for gauges (menu bar and panel).
enum Level {
    static func nsColor(_ utilization: Double) -> NSColor {
        switch utilization {
        case ..<50: return .systemGreen
        case ..<80: return .systemOrange
        default:    return .systemRed
        }
    }
    static func color(_ utilization: Double) -> Color { Color(nsColor: nsColor(utilization)) }
}

/// Draws the menu bar label as a resolution-independent NSImage.
@MainActor
enum LabelRenderer {
    private static let fontSize: CGFloat = 12
    private static let iconSize: CGFloat = 16
    private static let iconGap: CGFloat = 4
    private static let height: CGFloat = 18

    /// SF Rounded with monospaced digits.
    private static let font: NSFont = {
        let base = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        if let rounded = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: rounded, size: fontSize) {
            return f
        }
        return base
    }()

    private static let icon: NSImage? = {
        guard let img = NSImage(named: "claude") else { return nil }
        img.isTemplate = false
        return img
    }()

    static func render(snapshot: UsageSnapshot?, hasError: Bool) -> NSImage {
        let text = attributedText(snapshot: snapshot, hasError: hasError)
        let textSize = text.size()
        let width = iconSize + iconGap + ceil(textSize.width)
        let size = NSSize(width: width, height: height)

        return NSImage(size: size, flipped: false) { rect in
            if let icon {
                let y = (rect.height - iconSize) / 2
                icon.draw(in: NSRect(x: 0, y: y, width: iconSize, height: iconSize),
                          from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                let dot = NSBezierPath(ovalIn: NSRect(x: 3, y: (rect.height - 10) / 2, width: 10, height: 10))
                NSColor(ClaudeIcon.brand).setFill()
                dot.fill()
            }
            let y = (rect.height - textSize.height) / 2
            text.draw(at: NSPoint(x: iconSize + iconGap, y: y))
            return true
        }
    }

    private static func attributedText(snapshot: UsageSnapshot?, hasError: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func append(_ string: String, _ color: NSColor, kern: CGFloat = -0.2) {
            result.append(NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: color, .kern: kern,
            ]))
        }

        let label = NSColor.labelColor
        let separator = NSColor.tertiaryLabelColor
        if let s = snapshot {
            // Percentages are zero-padded to two digits ("09%") so the label
            // keeps a stable width.
            func pct(_ b: UsageBucket) -> String { String(format: "%02d%%", b.percent) }
            // 5h: percentage + block gauge, tinted by level.
            append("\(pct(s.fiveHour)) ", label)
            append(s.fiveHour.blocks, Level.nsColor(s.fiveHour.utilization), kern: 0.3)
            // W and F: tag + percentage, the percentage tinted by level.
            for (tag, bucket) in [("W", s.sevenDay), ("F", s.fable)] {
                append(" | ", separator)
                append("\(tag) ", label)
                append(pct(bucket), Level.nsColor(bucket.utilization))
            }
        } else {
            append("–% ", .secondaryLabelColor)
            append("▯▯▯▯▯", .tertiaryLabelColor, kern: 0.3)
            for tag in ["W", "F"] {
                append(" | ", separator)
                append("\(tag) –%", .secondaryLabelColor)
            }
        }
        if hasError { append(" ⚠︎", .systemYellow) }
        return result
    }
}

/// Claude spark icon in Claude orange. Uses the `claude` image (assets/claude.png
/// or the asset-catalog set) if present, otherwise an SF Symbol fallback.
struct ClaudeIcon: View {
    var size: CGFloat = 16

    /// Loaded once and given an explicit point size. MenuBarExtra renders its
    /// label from the image's own size, so `.frame` alone is not enough.
    @MainActor private static let image: NSImage? = {
        guard let img = NSImage(named: "claude") else { return nil }
        img.isTemplate = false
        img.size = NSSize(width: 16, height: 16)
        return img
    }()

    static let brand = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "sparkle")
                .font(.system(size: size - 3, weight: .bold))
                .foregroundStyle(Self.brand)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Dropdown panel

struct StatusMenuView: View {
    @EnvironmentObject private var service: UsageService
    @StateObject private var loginItem = LoginItem()

    var body: some View {
        // Re-render every 30 s so "ago" and "resets in" stay current.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                header(now: context.date)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider()

                if let error = service.error {
                    ErrorBanner(error: error)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                }

                if let s = service.snapshot {
                    VStack(alignment: .leading, spacing: 10) {
                        GaugeGroup(header: "Current",
                                   rows: [("Session", s.fiveHour)],
                                   resetLabel: "Resets", now: context.date)
                        GaugeGroup(header: "Weekly",
                                   rows: [("All Models", s.sevenDay), (s.fableName, s.fable)],
                                   resetLabel: "Resets", now: context.date)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else if service.error == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading usage…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
                } else {
                    Spacer().frame(height: 10)
                }

                Divider()

                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .frame(width: 340)
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 7) {
            ClaudeIcon(size: 16)
            Text("Usages")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer()
            if let updated = service.lastUpdated {
                Text("Updated \(Fmt.ago(updated, now: now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await service.refresh() }
            } label: {
                HStack(spacing: 5) {
                    if service.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh (3min)")
                }
            }
            .disabled(service.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh now. Usage also refreshes automatically every 3 minutes.")

            Spacer()

            Toggle("Launch at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.set($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            .help(loginItem.errorMessage ?? "Start ClaudeStatus automatically when you log in, independent of Claude Desktop.")
            .onAppear { loginItem.refresh() }

            Spacer()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .controlSize(.small)
    }
}

// MARK: - Gauge group

/// One or more gauge rows followed by a single right-aligned reset line.
/// Rows that reset at the same minute share one line; otherwise each gets its own.
struct GaugeGroup: View {
    let header: String
    let rows: [(title: String, bucket: UsageBucket)]
    let resetLabel: String
    let now: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(header.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 1)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GaugeRow(title: row.title, bucket: row.bucket)
            }
            ForEach(resetLines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var resetLines: [String] {
        let dates = rows.compactMap { $0.bucket.resetsAt }
        guard !dates.isEmpty else { return ["Reset time unavailable"] }
        let sameMinute = dates.allSatisfy { abs($0.timeIntervalSince(dates[0])) < 60 }
        if sameMinute || rows.count == 1 {
            return ["\(resetLabel) \(Fmt.resetPhrase(dates[0], now: now))"]
        }
        return rows.compactMap { row in
            row.bucket.resetsAt.map { "\(row.title) resets \(Fmt.resetPhrase($0, now: now))" }
        }
    }
}

/// Title on the left; gauge and percentage right-aligned.
struct GaugeRow: View {
    let title: String
    let bucket: UsageBucket

    /// Width of the block gauge in the panel (the menu bar uses 5).
    private static let gaugeWidth = 20

    private var gauge: String {
        let filled = Int((min(max(bucket.utilization, 0), 100) / 100 * Double(Self.gaugeWidth)).rounded())
        let clamped = min(max(filled, 0), Self.gaugeWidth)
        return String(repeating: "▮", count: clamped) + String(repeating: "▯", count: Self.gaugeWidth - clamped)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(.body, design: .rounded).weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(gauge)
                .font(.system(size: 12, design: .rounded))
                .kerning(0.5)
                .foregroundStyle(Level.color(bucket.utilization))
                .lineLimit(1)
                .accessibilityLabel("\(bucket.percent) percent used")
            Text("\(bucket.percent)%")
                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Formatting

enum Fmt {
    /// "45 sec", "33 min", "11 h 23 min", "2 d 5 h".
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        if total < 60 { return "\(max(total, 1)) sec" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let restMinutes = minutes % 60
        if hours < 24 { return restMinutes == 0 ? "\(hours) h" : "\(hours) h \(restMinutes) min" }
        let days = hours / 24
        let restHours = hours % 24
        return restHours == 0 ? "\(days) d" : "\(days) d \(restHours) h"
    }

    /// "in 33 min · 10:10 PM", or "shortly" once the time has passed.
    static func resetPhrase(_ reset: Date, now: Date) -> String {
        reset <= now ? "shortly" : "in \(duration(reset.timeIntervalSince(now))) · \(time.string(from: reset))"
    }

    /// "just now", "3 min ago", "1 h 5 min ago".
    static func ago(_ date: Date, now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 45 { return "just now" }
        return duration(interval) + " ago"
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}

// MARK: - Error banner

struct ErrorBanner: View {
    let error: UsageError

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text(error.errorDescription ?? "Unknown error")
                    .font(.callout.weight(.medium))
                if let hint = error.recoverySuggestion {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if error.needsSignIn {
                    Button {
                        SignInHelper.openTerminal()
                    } label: {
                        Label("Sign in via Terminal", systemImage: "terminal")
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Sign-in helper

/// Opens Terminal running `claude` so the user can type /login once.
/// Claude Desktop's own login is passed to its Code tab via the environment
/// and is not readable by other apps; the CLI login lands in the Keychain,
/// which this app reads.
enum SignInHelper {
    @MainActor static func openTerminal() {
        let script = """
        #!/bin/zsh
        clear
        echo "ClaudeStatus: sign in to Claude Code."
        echo "When Claude Code opens, type  /login  and press Return, then finish in the browser."
        echo "Afterwards you can close this window and click Refresh (3min) in the menu bar."
        echo
        if command -v claude >/dev/null 2>&1; then
          exec claude
        elif [ -x /opt/homebrew/bin/claude ]; then
          exec /opt/homebrew/bin/claude
        elif [ -x /usr/local/bin/claude ]; then
          exec /usr/local/bin/claude
        else
          echo "The claude command-line tool is not installed."
          echo "Install it with:  brew install --cask claude-code   (or: npm install -g @anthropic-ai/claude-code)"
          echo "then run this again."
          read -k 1 "?Press any key to close."
        fi
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeStatus-sign-in.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }
}
