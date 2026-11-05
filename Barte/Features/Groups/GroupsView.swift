import SwiftUI

/// Home: all groups as a Wallet-style stack of cards.
struct GroupsView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var showsNewGroup = false
    @State private var showsAbout = false
    @State private var showsJoin = false
    @State private var cardWidth: CGFloat = 360
    @State private var appliedLaunchFlags = false
    @Namespace private var zoom
    /// How much of each stacked card peeks out: enough for the name and my balance.
    @ScaledMetric(relativeTo: .title2) private var peek: CGFloat = 84

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if !model.hasLoaded {
                    ProgressView()
                        .controlSize(.large)
                        .padding(.top, 120)
                        .frame(maxWidth: .infinity)
                } else if model.groups.isEmpty {
                    if let error = model.loadError {
                        loadErrorView(error)
                    } else {
                        emptyState
                    }
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        summary
                        stack
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .refreshable { await model.reload() }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("Barte")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Über Barte", systemImage: "info.circle") { showsAbout = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Hinzufügen", systemImage: "plus") {
                        Button("Neue Gruppe", systemImage: "rectangle.stack.badge.plus") { showsNewGroup = true }
                        Button("Mit Code beitreten", systemImage: "person.crop.circle.badge.checkmark") { showsJoin = true }
                    }
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
            .sheet(isPresented: $showsJoin) {
                JoinSheet(code: nil) { id in path = [id] }
            }
            .sheet(item: inviteBinding) { invite in
                JoinSheet(code: invite.code) { id in path = [id] }
            }
            .onAppear {
                applyLaunchFlags()
                openPendingGroup()
            }
            .onChange(of: model.hasLoaded) {
                applyLaunchFlags()
                openPendingGroup()
            }
            .onChange(of: model.pendingGroupID) { openPendingGroup() }
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
            VStack(spacing: 12) {
                Button {
                    showsNewGroup = true
                } label: {
                    Text("Gruppe erstellen")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Mit Code beitreten") { showsJoin = true }
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    private func loadErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Keine Verbindung", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Erneut versuchen") { Task { await model.reload() } }
                .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    private struct PendingInvite: Identifiable {
        let code: String
        var id: String { code }
    }

    /// An invite link that opened the app shows the join sheet.
    private var inviteBinding: Binding<PendingInvite?> {
        Binding(
            get: { model.pendingInviteCode.map(PendingInvite.init(code:)) },
            set: { if $0 == nil { model.pendingInviteCode = nil } }
        )
    }

    /// A notification or the widget asked for a group; open it once the groups are there.
    private func openPendingGroup() {
        guard let id = model.pendingGroupID, model.hasLoaded else { return }
        model.pendingGroupID = nil
        if model.group(id) != nil { path = [id] }
    }

    private func applyLaunchFlags() {
        guard model.isDemo, model.hasLoaded, !appliedLaunchFlags else { return }
        appliedLaunchFlags = true
        if let index = DemoData.argument(after: "-BarteGroup").flatMap(Int.init), model.groups.indices.contains(index) {
            path = [model.groups[index].id]
        }
        switch DemoData.argument(after: "-BarteSheet") {
        case "group" where path.isEmpty: showsNewGroup = true
        case "about" where path.isEmpty: showsAbout = true
        case "join" where path.isEmpty: model.pendingInviteCode = "KROATIEN"
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
