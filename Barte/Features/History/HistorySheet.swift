import SwiftUI

/// The whole group's history, from the ⋯ menu.
struct HistorySheet: View {
    let group: SplitGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HistoryList(group: group, subjectID: nil)
                .navigationTitle("Verlauf")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig", role: .confirm) { dismiss() }
                    }
                }
        }
    }
}

/// What happened in a group, newest first, by day. With `subjectID`, only one expense.
/// Nobody can change or delete these entries, so edits and deletions stay visible to everyone.
struct HistoryList: View {
    let group: SplitGroup
    let subjectID: UUID?

    @Environment(AppModel.self) private var model
    @State private var events: [GroupEvent]?
    @State private var loadError: String?
    @State private var restoring: UUID?
    @State private var restoreError: String?

    var body: some View {
        List {
            if let events {
                if events.isEmpty {
                    ContentUnavailableView {
                        Label("Noch kein Verlauf", systemImage: "clock")
                    } description: {
                        Text(subjectID == nil
                             ? String(localized: "Ab jetzt steht hier, wer was eingetragen, geändert oder gelöscht hat.")
                             : String(localized: "Diese Ausgabe wurde eingetragen, bevor es den Verlauf gab."))
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(Self.days(of: events), id: \.title) { day in
                        Section(day.title) {
                            ForEach(day.events) { event in
                                HistoryRow(event: event, wording: event.text(in: group, userID: model.userID), tint: group.color.tint,
                                           restore: restorable.contains(event.id) && !group.isClosed ? { Task { await restore(event) } } : nil,
                                           isRestoring: restoring == event.id)
                            }
                        }
                    }
                }
            } else if let loadError {
                ContentUnavailableView {
                    Label("Keine Verbindung", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Erneut versuchen") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .refreshable { await load() }
        .task { await load() }
        // Someone else changing something while this is open shows up here too.
        .onChange(of: group) { Task { await load() } }
        .alert("Wiederherstellen hat nicht geklappt", isPresented: Binding(get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreError ?? "")
        }
    }

    /// Only the newest deletion of something that is still gone can bring it back.
    private var restorable: Set<UUID> {
        var seen = Set<UUID>(), result = Set<UUID>()
        for event in events ?? [] {
            guard let subject = event.subjectID, seen.insert(subject).inserted else { continue }
            if event.restoredExpense(in: group) != nil { result.insert(event.id) }
        }
        return result
    }

    /// Saves the deleted expense again under its old id; the history then shows who brought it back.
    private func restore(_ event: GroupEvent) async {
        guard let expense = event.restoredExpense(in: group), restoring == nil else { return }
        restoring = event.id
        let groupID = group.id
        restoreError = await model.run { try await $0.save(expense, in: groupID) }
        restoring = nil
        await load()
    }

    private func load() async {
        guard let repository = model.repository else { return }
        do {
            events = try await repository.fetchHistory(groupID: group.id, subjectID: subjectID)
            loadError = nil
        } catch {
            loadError = UserFacingError(error).message
        }
    }

    struct Day { let title: String; let events: [GroupEvent] }

    static func days(of events: [GroupEvent], now: Date = .now) -> [Day] {
        let calendar = Calendar.current
        var result: [Day] = []
        for event in events {
            let title = calendar.isDateInToday(event.createdAt) ? String(localized: "Heute")
                : calendar.isDateInYesterday(event.createdAt) ? String(localized: "Gestern")
                : event.createdAt.formatted(calendar.isDate(event.createdAt, equalTo: now, toGranularity: .year)
                    ? .dateTime.weekday(.wide).day().month(.wide)
                    : .dateTime.day().month(.wide).year())
            if result.last?.title == title {
                result[result.count - 1] = Day(title: title, events: result[result.count - 1].events + [event])
            } else {
                result.append(Day(title: title, events: [event]))
            }
        }
        return result
    }
}

private struct HistoryRow: View {
    let event: GroupEvent
    let wording: GroupEvent.Wording
    /// The group's card color, dark enough for white symbols.
    let tint: Color
    /// Brings a deleted expense back; nil when that isn't possible.
    let restore: (() -> Void)?
    let isRestoring: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(event.isNotable ? Color.white : Color.inkSecondary)
                .frame(width: 30, height: 30)
                .background(event.isNotable ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(wording.headline)
                    .font(.body)
                ForEach(wording.details, id: \.self) { line in
                    Text(line)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                }
                if let restore {
                    Button("Wiederherstellen", systemImage: "arrow.uturn.backward", action: restore)
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.borderless)
                        .disabled(isRestoring)
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
            Spacer(minLength: 8)
            Text(event.createdAt.formatted(.dateTime.hour().minute()))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let restore { Button("Wiederherstellen", action: restore) }
        }
    }
}
