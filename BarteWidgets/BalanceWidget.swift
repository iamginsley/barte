import SwiftUI
import WidgetKit

/// "Du bekommst 42 €": my balance across all groups, and on the medium size the groups behind it.
struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.balanceKind, provider: SnapshotProvider()) { entry in
            BalanceWidgetView(entry: entry)
                .containerBackground(Color.card, for: .widget)
                .widgetURL(BarteLink.home)
        }
        .configurationDisplayName("Saldo")
        .description("Was du insgesamt bekommst oder schuldest.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct BalanceWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryInline:
                Label(Self.sentence(snapshot.totals.first), systemImage: "rectangle.stack.fill")
            case .accessoryRectangular:
                rectangular(snapshot)
            case .systemMedium:
                HStack(alignment: .top, spacing: 16) {
                    total(snapshot)
                    groups(snapshot)
                }
            default:
                total(snapshot)
            }
        } else {
            signedOut
        }
    }

    // MARK: Pieces

    private func total(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            if let first = snapshot.totals.first {
                Text(first.cents > 0 ? "Du bekommst" : "Du schuldest")
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
                Text(Money.format(abs(first.cents), currency: first.currency))
                    .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(first.cents > 0 ? Color.positive : Color.negative)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                if snapshot.totals.count > 1 {
                    Text(snapshot.totals.count == 2 ? "und 1 weitere Währung" : "und \(snapshot.totals.count - 1) weitere Währungen")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(Color.positive)
                    .widgetAccentable()
                Text("Überall quitt")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(Color.accentColor)
                .widgetAccentable()
            Text("Barte")
                .foregroundStyle(Color.ink)
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func groups(_ snapshot: WidgetSnapshot) -> some View {
        if snapshot.groups.isEmpty {
            Text("Niemand schuldet hier jemandem etwas.")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.groups.prefix(3)) { group in
                    Link(destination: BarteLink.group(group.id)) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Self.cardColor(group.color))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(group.name)
                                    .font(.caption)
                                    .foregroundStyle(Color.inkSecondary)
                                    .lineLimit(1)
                                Text(Money.format(group.balance, currency: group.currency, showsSign: true))
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(group.balance > 0 ? Color.positive : Color.negative)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Barte", systemImage: "rectangle.stack.fill")
                .font(.headline)
                .widgetAccentable()
            Text(Self.sentence(snapshot.totals.first))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signedOut: some View {
        Group {
            switch family {
            case .accessoryInline, .accessoryRectangular:
                Label("Barte", systemImage: "rectangle.stack.fill")
            default:
                VStack(alignment: .leading, spacing: 6) {
                    header
                    Spacer(minLength: 0)
                    Text("Öffne Barte, um deinen Saldo hier zu sehen.")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Helpers

    static func sentence(_ total: WidgetSnapshot.Total?) -> String {
        guard let total else { return String(localized: "Überall quitt") }
        let amount = Money.format(abs(total.cents), currency: total.currency)
        return total.cents > 0 ? String(localized: "Du bekommst \(amount)") : String(localized: "Du schuldest \(amount)")
    }

    /// Same order as CardColor in the app.
    static func cardColor(_ index: Int) -> Color {
        let names = ["CardBlue", "CardIndigo", "CardPurple", "CardPink", "CardRed", "CardOrange", "CardGreen", "CardTeal", "CardGraphite"]
        return Color(names.indices.contains(index) ? names[index] : names[0])
    }
}

#Preview("Klein", as: .systemSmall) {
    BalanceWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview("Mittel", as: .systemMedium) {
    BalanceWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}
