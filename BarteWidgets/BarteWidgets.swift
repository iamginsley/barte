import SwiftUI
import WidgetKit

@main
struct BarteWidgets: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// The data only changes when the app writes a new snapshot and reloads the timeline.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? (WidgetStore.read() ?? .sample) : WidgetStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: WidgetStore.read())], policy: .never))
    }
}

extension WidgetSnapshot {
    static let sample = WidgetSnapshot(
        updatedAt: .now,
        totals: [.init(currency: "EUR", cents: 4200)],
        groups: [
            .init(id: UUID(), name: "Skiurlaub", color: 0, currency: "EUR", balance: 6550),
            .init(id: UUID(), name: "WG", color: 1, currency: "EUR", balance: -2590),
            .init(id: UUID(), name: "Pizza-Abende", color: 5, currency: "EUR", balance: 240),
        ]
    )
}
