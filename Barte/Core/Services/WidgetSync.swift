import Foundation
import WidgetKit

/// Builds the widget snapshot from the groups and hands it to the widget.
enum WidgetSync {
    static func update(groups: [SplitGroup], userID: UUID?) {
        let snapshot = makeSnapshot(groups: groups, userID: userID)
        // Realtime reloads often; only wake the widget when something it shows changed.
        if let old = WidgetStore.read(), old.totals == snapshot.totals, old.groups == snapshot.groups { return }
        WidgetStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetStore.write(nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func makeSnapshot(groups: [SplitGroup], userID: UUID?, now: Date = .now) -> WidgetSnapshot {
        let open = groups.compactMap { group -> WidgetSnapshot.Group? in
            let balance = group.balance(of: group.me(userID: userID))
            guard balance != 0 else { return nil }
            return .init(id: group.id, name: group.name, color: group.color.rawValue, currency: group.currency, balance: balance)
        }
        let totals = Dictionary(grouping: open, by: \.currency)
            .map { WidgetSnapshot.Total(currency: $0.key, cents: $0.value.reduce(0) { $0 + $1.balance }) }
            .filter { $0.cents != 0 }
            .sorted { (abs($0.cents), $1.currency) > (abs($1.cents), $0.currency) }
        let largest = open.sorted { (abs($0.balance), $1.name) > (abs($1.balance), $0.name) }
        return WidgetSnapshot(updatedAt: now, totals: totals, groups: Array(largest.prefix(4)))
    }
}
