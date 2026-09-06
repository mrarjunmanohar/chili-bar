import SwiftUI
import ChiliBarCore

/// A zone being edited. Fields are strings so a half-typed value doesn't have to be valid.
struct EditableZone: Identifiable, Equatable {
    let id = UUID()
    var label: String = ""
    var timeZoneID: String = TimeZone.current.identifier
    var opens: String = "09:00"
    var closes: String = "17:00"
    /// Empty means "uses its own hours".
    var hoursIn: String = ""

    init() {}

    init(_ zone: Zone) {
        label = zone.label
        timeZoneID = zone.timeZone.identifier
        opens = zone.opensAt.description
        closes = zone.closesAt.description
        hoursIn = zone.hoursTimeZoneOverride?.identifier ?? ""
    }

    /// Nil when a field doesn't parse, which is what blocks saving.
    var zone: Zone? {
        guard !label.isEmpty,
              let opensAt = TimeOfDay(opens),
              let closesAt = TimeOfDay(closes)
        else { return nil }

        var reference: TimeZone?
        if !hoursIn.isEmpty {
            guard let zone = TimeZone(identifier: hoursIn) else { return nil }
            reference = zone
        }

        return Zone(label: label, timeZoneID: timeZoneID, opensAt: opensAt, closesAt: closesAt, hoursIn: reference)
    }
}

struct SettingsView: View {
    @State private var work: Double
    @State private var rest: Double
    @State private var warning: Double
    @State private var rotation: Double
    @State private var zones: [EditableZone]
    @State private var saveError: String?

    private let onSave: (TimerSettings, [Zone]) throws -> Void
    private let onClose: () -> Void

    private static let timeZoneIDs = TimeZone.knownTimeZoneIdentifiers.sorted()

    init(
        settings: TimerSettings,
        zones: [Zone],
        onSave: @escaping (TimerSettings, [Zone]) throws -> Void,
        onClose: @escaping () -> Void
    ) {
        _work = State(initialValue: settings.workLength / 60)
        _rest = State(initialValue: settings.defaultRestLength / 60)
        _warning = State(initialValue: settings.warningLead / 60)
        _rotation = State(initialValue: settings.rotationSeconds)
        _zones = State(initialValue: zones.map(EditableZone.init))
        self.onSave = onSave
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    timerSection
                    Divider()
                    zonesSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
    }

    // MARK: - Timer

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer").font(.headline)

            numberRow("Focus session", value: $work, range: 1...180, unit: "minutes")
            numberRow("Default break", value: $rest, range: 1...120, unit: "minutes")
            numberRow("Warn before the end", value: $warning, range: 0...60, unit: "minutes")
            numberRow("Rotate clocks every", value: $rotation, range: 1...60, unit: "seconds")

            if warning * 2 > work {
                Label(
                    "The warning is more than half the session, so it fires almost immediately.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func numberRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String
    ) -> some View {
        HStack {
            Text(title).frame(width: 170, alignment: .leading)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            Stepper("", value: value, in: range).labelsHidden()
            Text(unit).foregroundStyle(.secondary).font(.callout)
            Spacer()
        }
    }

    // MARK: - Zones

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("World clock").font(.headline)
                Spacer()
                Button {
                    zones.append(EditableZone())
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            Text("Order here is the order they rotate through in the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($zones) { $zone in
                zoneEditor($zone)
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func zoneEditor(_ zone: Binding<EditableZone>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Label", text: zone.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                Picker("", selection: zone.timeZoneID) {
                    ForEach(Self.timeZoneIDs, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()

                Spacer(minLength: 4)

                Button {
                    move(zone.wrappedValue, by: -1)
                } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)

                Button {
                    move(zone.wrappedValue, by: 1)
                } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)

                Button(role: .destructive) {
                    zones.removeAll { $0.id == zone.wrappedValue.id }
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                Text("Works").font(.callout).foregroundStyle(.secondary)
                timeField(zone.opens)
                Text("to").font(.callout).foregroundStyle(.secondary)
                timeField(zone.closes)

                Picker("on", selection: zone.hoursIn) {
                    Text("their own clock").tag("")
                    ForEach(Self.timeZoneIDs, id: \.self) { Text($0 + "'s clock").tag($0) }
                }
                .frame(maxWidth: 230)
            }

            // The single most confusing thing in this app, spelled out where it's decided.
            if !zone.wrappedValue.hoursIn.isEmpty {
                Text("Their clock shows local time; the dot follows \(zone.wrappedValue.hoursIn) hours, including its daylight saving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let z = zone.wrappedValue.zone, z.isOvernight {
                Text("Overnight shift — counts as the day it starts on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeField(_ text: Binding<String>) -> some View {
        TextField("HH:mm", text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .foregroundStyle(TimeOfDay(text.wrappedValue) == nil ? Color.red : Color.primary)
    }

    private func move(_ zone: EditableZone, by offset: Int) {
        guard let index = zones.firstIndex(of: zone) else { return }
        let target = index + offset
        guard zones.indices.contains(target) else { return }
        zones.swapAt(index, target)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Spacer()
            Button("Close", action: onClose)
            Button("Save", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func save() {
        // Refuse rather than silently dropping a row the user is mid-way through typing.
        let parsed = zones.map(\.zone)
        guard !parsed.contains(where: { $0 == nil }) else {
            saveError = "Check the highlighted rows — a label or time isn't valid."
            return
        }

        let settings = TimerSettings(
            workLength: work * 60,
            defaultRestLength: rest * 60,
            warningLead: warning * 60,
            rotationSeconds: rotation
        )

        do {
            try onSave(settings, parsed.compactMap { $0 })
            saveError = nil
            onClose()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
