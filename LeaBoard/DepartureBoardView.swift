import SwiftUI
import DarwinKit

/// UK departure-board palette: amber-on-black dot matrix.
private enum BoardStyle {
    static let background = Color(red: 0.06, green: 0.05, blue: 0.03)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.11)
    static let amberDim = amber.opacity(0.55)
    static let delayed = Color(red: 1.0, green: 0.42, blue: 0.18)
    static let cancelled = Color(red: 1.0, green: 0.23, blue: 0.19)

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct DepartureBoardView: View {
    let model: DeparturesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.needsSetup {
                setupHelp
            } else {
                boardBody
            }
            footer
        }
        .padding(14)
        .frame(width: 420)
        .background(BoardStyle.background)
        .task {
            // Refresh on open, then every 60 s while the panel stays open.
            // The task is cancelled when the panel closes.
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await model.refresh()
            }
        }
    }

    private var header: some View {
        HStack {
            Text(model.stationName.uppercased())
                .font(BoardStyle.font(15, weight: .bold))
            if model.isDemo {
                Text("DEMO")
                    .font(BoardStyle.font(10, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(BoardStyle.amberDim))
                    .foregroundStyle(BoardStyle.amberDim)
            }
            Spacer()
            Text(Date.now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(BoardStyle.font(15, weight: .bold))
        }
        .foregroundStyle(BoardStyle.amber)
    }

    @ViewBuilder
    private var boardBody: some View {
        directionSection(title: BoardDirection.stratford.displayName, departures: model.stratford)
        directionSection(title: BoardDirection.tottenhamHale.displayName, departures: model.northbound)

        if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(BoardStyle.font(11))
                .foregroundStyle(BoardStyle.cancelled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func directionSection(title: String, departures: [Departure]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(BoardStyle.font(11, weight: .semibold))
                .foregroundStyle(BoardStyle.amberDim)
            Divider().overlay(BoardStyle.amberDim)
            if departures.isEmpty {
                Text(model.errorMessage == nil ? "No departures" : "--")
                    .font(BoardStyle.font(13))
                    .foregroundStyle(BoardStyle.amberDim)
                    .padding(.vertical, 2)
            } else {
                ForEach(departures) { departure in
                    DepartureRow(departure: departure)
                }
            }
        }
    }

    private var setupHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NO API KEY CONFIGURED")
                .font(BoardStyle.font(12, weight: .bold))
                .foregroundStyle(BoardStyle.cancelled)
            Text("""
            1. Subscribe to "Live Departure Board" on raildata.org.uk
            2. Copy config.example.json to ~/.config/leaboard/config.json
            3. Paste your consumer key into "apiKey"

            See README.md for details.
            """)
            .font(BoardStyle.font(11))
            .foregroundStyle(BoardStyle.amberDim)
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let lastUpdated = model.lastUpdated {
                Text("Updated \(lastUpdated, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))")
            } else {
                Text(model.isLoading ? "Loading…" : "Not updated yet")
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
            .help("Refresh now")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit LeaBoard")
        }
        .font(BoardStyle.font(11))
        .foregroundStyle(BoardStyle.amberDim)
    }
}

private struct DepartureRow: View {
    let departure: Departure

    var body: some View {
        HStack(spacing: 8) {
            Text(departure.scheduled)
                .foregroundStyle(primaryColor)
            Text(departure.destination)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(departure.isCancelled, color: BoardStyle.cancelled)
                .foregroundStyle(primaryColor)
            Spacer(minLength: 4)
            // Fixed-width columns so platforms stay aligned regardless of
            // how wide the status text is ("On time" vs "Exp 11:29").
            Text(departure.platform.map { "Plat \($0)" } ?? "–")
                .foregroundStyle(BoardStyle.amberDim)
                .frame(width: 56, alignment: .leading)
            Text(statusText)
                .foregroundStyle(statusColor)
                .frame(width: 74, alignment: .trailing)
        }
        .font(BoardStyle.font(13))
        .help(tooltip)
    }

    private var statusText: String {
        if departure.isCancelled { return "Cancelled" }
        if departure.expected.caseInsensitiveCompare("On time") == .orderedSame { return "On time" }
        if departure.expected.caseInsensitiveCompare("Delayed") == .orderedSame { return "Delayed" }
        return "Exp \(departure.expected)"
    }

    private var primaryColor: Color {
        departure.isCancelled ? BoardStyle.cancelled : BoardStyle.amber
    }

    private var statusColor: Color {
        if departure.isCancelled { return BoardStyle.cancelled }
        if departure.isDelayed { return BoardStyle.delayed }
        return BoardStyle.amber
    }

    private var tooltip: String {
        var parts = [departure.operatorName]
        if let via = departure.via { parts.append(via) }
        if let reason = departure.reason { parts.append(reason) }
        return parts.filter { !$0.isEmpty }.joined(separator: " — ")
    }
}
