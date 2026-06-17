import SwiftUI
import TfLKit

/// London-bus palette: TfL red roundel red (#DC241F) and white, on a dark
/// panel, deliberately distinct from the amber train board.
private enum BusStyle {
    static let background = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let tflRed = Color(red: 0.863, green: 0.141, blue: 0.122)   // #DC241F
    static let white = Color.white
    static let whiteDim = Color.white.opacity(0.6)
    static let due = Color(red: 1.0, green: 0.82, blue: 0.28)

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct BusBoardView: View {
    let model: BusViewModel

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
        .frame(width: 450)
        .background(BusStyle.background)
        .task {
            // Refresh on open, then every 30 s while the panel stays open.
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await model.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bus.doubledecker.fill")
            Text("Emmanuel Parish Church Bus Arrivals".uppercased())
                .font(BusStyle.font(14, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if model.isDemo {
                Text("DEMO")
                    .font(BusStyle.font(10, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(BusStyle.whiteDim))
                    .foregroundStyle(BusStyle.whiteDim)
            }
            Spacer()
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(BusStyle.font(15, weight: .bold))
            }
        }
        .foregroundStyle(BusStyle.white)
    }

    @ViewBuilder
    private var boardBody: some View {
        // TimelineView re-renders each minute so the "minutes until" column
        // ticks down between the 30 s data refreshes.
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 10) {
                directionSection(title: model.directionALabel, arrivals: model.directionA, now: context.date)
                directionSection(title: model.directionBLabel, arrivals: model.directionB, now: context.date)
            }
        }

        if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(BusStyle.font(11))
                .foregroundStyle(BusStyle.tflRed)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func directionSection(title: String, arrivals: [BusArrival], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(BusStyle.font(11, weight: .bold))
                .foregroundStyle(BusStyle.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BusStyle.tflRed)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            if arrivals.isEmpty {
                Text(model.errorMessage == nil ? "No buses" : "—")
                    .font(BusStyle.font(13))
                    .foregroundStyle(BusStyle.whiteDim)
                    .padding(.vertical, 2)
            } else {
                ForEach(arrivals) { arrival in
                    BusRow(arrival: arrival, now: now)
                }
            }
        }
    }

    private var setupHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NO BUS STOPS CONFIGURED")
                .font(BusStyle.font(12, weight: .bold))
                .foregroundStyle(BusStyle.tflRed)
            Text("""
            1. Get a free app_key at api-portal.tfl.gov.uk
            2. Add a "tfl" block to ~/.config/leaboard/config.json
               (appKey + directionA/directionB stop ids)

            See README.md for details.
            """)
            .font(BusStyle.font(11))
            .foregroundStyle(BusStyle.whiteDim)
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
        .font(BusStyle.font(11))
        .foregroundStyle(BusStyle.whiteDim)
    }
}

private struct BusRow: View {
    let arrival: BusArrival
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            // Route number in a red "blind" badge, fixed width so 2- and
            // 3-character numbers (55, N38) line up.
            Text(arrival.lineName)
                .font(BusStyle.font(15, weight: .heavy))
                .foregroundStyle(BusStyle.white)
                .frame(minWidth: 44)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(BusStyle.tflRed)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(arrival.destination)
                .font(BusStyle.font(13))
                .foregroundStyle(BusStyle.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(minutesText)
                .font(BusStyle.font(13, weight: .semibold))
                .foregroundStyle(isDue ? BusStyle.due : BusStyle.white)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var isDue: Bool { arrival.minutesUntilArrival(at: now) < 1 }

    private var minutesText: String {
        let minutes = arrival.minutesUntilArrival(at: now)
        return minutes < 1 ? "Due" : "\(minutes) min"
    }
}
