import SwiftUI

/// Home: all groups as a Wallet-style stack of cards.
struct GroupsView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var showsNewGroup = false
    @State private var showsAbout = false
    @State private var cardWidth: CGFloat = 360
    @State private var appliedLaunchFlags = false
    @Namespace private var zoom
    /// How much of each stacked card peeks out: enough for the name and my balance.
    @ScaledMetric(relativeTo: .title2) private var peek: CGFloat = 84

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if model.groups.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        summary
                        stack
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("Barte")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Über Barte", systemImage: "info.circle") { showsAbout = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Neue Gruppe", systemImage: "plus") { showsNewGroup = true }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                GroupDetailView(groupID: id)
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
            .sheet(isPresented: $showsNewGroup) {
                GroupEditorSheet(group: nil) { id in path = [id] }
            }
            .sheet(isPresented: $showsAbout) { AboutView() }
            .onAppear(perform: applyLaunchFlags)
        }
    }

    // MARK: Stack

    private var stack: some View {
        let cardHeight = cardWidth / Theme.cardAspectRatio
        // Later cards draw on top, so each card covers all but the top strip of the one before.
        return VStack(spacing: min(0, peek - cardHeight)) {
            ForEach(model.groups) { group in
                NavigationLink(value: group.id) {
                    GroupCard(group: group, me: model.me(in: group.id))
                        .matchedTransitionSource(id: group.id, in: zoom) { source in
                            source.clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                        }
                }
                .buttonStyle(CardButtonStyle())
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardWidth = $0 }
    }

    /// One line per currency: what I get or owe across all groups.
    @ViewBuilder
    private var summary: some View {
        let totals = Dictionary(grouping: model.groups, by: \.currency)
            .mapValues { groups in groups.reduce(0) { $0 + $1.balance(of: model.me(in: $1.id)) } }
            .filter { $0.value != 0 }
            .sorted { $0.key < $1.key }
        if totals.isEmpty {
            Label("Du bist überall quitt", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.positive)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(totals, id: \.key) { currency, total in
                    HStack(spacing: 6) {
                        Text(total > 0 ? "Insgesamt bekommst du" : "Insgesamt schuldest du")
                            .foregroundStyle(Color.inkSecondary)
                        Text(Money.format(abs(total), currency: currency))
                            .font(.amount)
                            .foregroundStyle(total.balanceColor)
                    }
                    .font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            BarteLogo(size: 120)
                .padding(.top, 60)
            VStack(spacing: 8) {
                Text("Noch keine Gruppen")
                    .font(.title2.weight(.bold))
                Text("Leg eine Gruppe an – für den Urlaub, die WG oder den Pizza-Abend. Barte rechnet aus, wer wem wie viel zahlt.")
                    .font(.body)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showsNewGroup = true
            } label: {
                Text("Gruppe erstellen")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    private func applyLaunchFlags() {
        guard model.isDemo, !appliedLaunchFlags else { return }
        appliedLaunchFlags = true
        if let index = DemoData.argument(after: "-BarteGroup").flatMap(Int.init), model.groups.indices.contains(index) {
            path = [model.groups[index].id]
        }
        switch DemoData.argument(after: "-BarteSheet") {
        case "group" where path.isEmpty: showsNewGroup = true
        case "about" where path.isEmpty: showsAbout = true
        default: break
        }
    }
}

/// Cards sink in slightly when pressed.
struct CardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
