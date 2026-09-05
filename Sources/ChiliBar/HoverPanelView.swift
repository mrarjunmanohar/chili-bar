import SwiftUI
import ChiliBarCore

/// One row of the hover panel.
struct ZoneRow: Identifiable {
    let id = UUID()
    let label: String
    let time: String
    let dayAndDate: String
    let isWorkingHours: Bool
}

/// The peek panel shown on hover.
///
/// Day and date appear on every row because a zone can already be on tomorrow — the case a
/// bare time silently hides, and the reason this panel exists at all.
struct HoverPanelView: View {
    let rows: [ZoneRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 38, alignment: .leading)

                    Text(row.time)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 44, alignment: .leading)

                    Text(row.dayAndDate)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)

                    WorkingHoursDot(isWorkingHours: row.isWorkingHours)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .fixedSize()
    }
}

/// Filled = reachable now, hollow = outside working hours.
///
/// Colour alone would exclude colourblind users, so the two states differ in fill as well as hue.
struct WorkingHoursDot: View {
    let isWorkingHours: Bool

    var body: some View {
        Group {
            if isWorkingHours {
                Circle().fill(Color.green)
            } else {
                Circle().strokeBorder(Color.secondary, lineWidth: 1.2)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityLabel(isWorkingHours ? "Within working hours" : "Outside working hours")
    }
}
