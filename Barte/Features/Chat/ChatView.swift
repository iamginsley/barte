import SwiftUI

/// A group's chat. The history runs through it as small lines, so a question sits right below the
/// change it is about. Own messages are in the group's card color.
struct ChatView: View {
    let groupID: UUID
    /// Off when the chat is opened from an expense, so tapping it doesn't stack another editor.
    var opensExpenses = true

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var chat: ChatModel
    @State private var openedExpense: Expense?
    @State private var didAppear = false
    @State private var showsInvite = false
    @FocusState private var composerFocused: Bool

    init(groupID: UUID, reference: Expense? = nil, opensExpenses: Bool = true) {
        self.groupID = groupID
        self.opensExpenses = opensExpenses
        _chat = State(initialValue: ChatModel(groupID: groupID, reference: reference))
    }

    var body: some View {
        if let group = app.group(groupID) {
            content(group)
        } else {
            ContentUnavailableView("Gruppe nicht gefunden", systemImage: "rectangle.on.rectangle.slash")
        }
    }

    private func content(_ group: SplitGroup) -> some View {
        let entries = chat.entries(userID: app.userID)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if group.isShared { intro(group) } else { lonely(group) }
                if !chat.hasLoaded {
                    ProgressView().padding(.vertical, 24)
                } else if let error = chat.loadError, entries.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Verbindung", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Erneut versuchen") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                }
                ForEach(entries) { entry in
                    row(entry, group)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .contentShape(.rect)
            .onTapGesture { composerFocused = false }
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.surface.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) { if group.isShared { composer(group) } }
        .navigationTitle("Chat")
        .navigationSubtitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if group.isShared {
            ToolbarItem(placement: .topBarTrailing) {
                Button(group.chatMuted ? String(localized: "Mitteilungen einschalten") : String(localized: "Stummschalten"),
                       systemImage: group.chatMuted ? "bell.slash" : "bell") {
                    Task { await toggleMute(group) }
                }
                .accessibilityValue(group.chatMuted ? String(localized: "Stumm") : String(localized: "Mitteilungen an"))
            }
            }
        }
        .task { await load() }
        .task(id: groupID) {
            guard let repository = app.repository else { return }
            for await _ in repository.chatChanges(groupID: groupID) {
                await load()
            }
        }
        .onAppear {
            app.visibleChatGroupID = groupID
            guard !didAppear else { return }
            didAppear = true
            if chat.reference != nil { composerFocused = true }
        }
        .onDisappear {
            if app.visibleChatGroupID == groupID { app.visibleChatGroupID = nil }
        }
        .sheet(isPresented: $showsInvite) { InviteSheet(groupID: group.id) }
        .sheet(item: $openedExpense) { ExpenseEditorSheet(group: group, expense: $0, me: group.me(userID: app.userID)) }
        .alert("Das hat nicht geklappt", isPresented: .init(get: { chat.actionError != nil }, set: { if !$0 { chat.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(chat.actionError ?? "")
        }
    }

    // MARK: Pieces

    private func intro(_ group: SplitGroup) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(group.color.tint)
                .accessibilityHidden(true)
            Text("Hier klärt ihr, was in „\(group.name)“ offen ist. Neue, geänderte und gelöschte Ausgaben erscheinen automatisch dazwischen.")
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    /// Nobody else in the group uses the app yet: nothing to write to, so the way there instead.
    private func lonely(_ group: SplitGroup) -> some View {
        let others = group.members.filter { $0.userID != app.userID }.map(\.name)
        let names = others.count <= 2 ? others.formatted(.list(type: .and)) : String(localized: "die anderen", comment: "Chat: invite the others (more than two people)")
        return VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.largeTitle)
                .foregroundStyle(group.color.tint)
                .accessibilityHidden(true)
            Text("Noch schreibt niemand mit")
                .font(.title3.weight(.semibold))
            Text(others.isEmpty
                 ? String(localized: "Lade jemanden in „\(group.name)“ ein, dann könnt ihr hier schreiben. Neue und geänderte Ausgaben erscheinen automatisch dazwischen.")
                 : String(localized: "Lade \(names) ein, dann könnt ihr hier schreiben und bekommt Mitteilungen. Neue und geänderte Ausgaben erscheinen automatisch dazwischen."))
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Einladen", systemImage: "person.crop.circle.badge.plus") { showsInvite = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(_ entry: ChatTimeline.Entry, _ group: SplitGroup) -> some View {
        switch entry {
        case .day(let title):
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 18)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
        case .event(let event):
            EventLine(event: event, wording: event.text(in: group, userID: app.userID), expense: expense(event.subjectID, in: group)) {
                openedExpense = $0
            }
        case .message(let bubble):
            MessageRow(
                bubble: bubble,
                group: group,
                expense: expense(bubble.message.expenseID, in: group),
                showsNames: group.members.filter(\.usesApp).count > 2,
                onOpenExpense: { openedExpense = $0 },
                onRetry: { Task { await withRepository { await chat.retry(bubble.message.id, $0) } } },
                onDiscard: { chat.discard(bubble.message.id) },
                onDelete: { Task { await withRepository { await chat.delete(bubble.message.id, $0) } } },
                onReport: { report(bubble.message, in: group) }
            )
        }
    }

    private func composer(_ group: SplitGroup) -> some View {
        @Bindable var chat = chat
        return VStack(alignment: .leading, spacing: 8) {
            if let reference = chat.reference {
                HStack(spacing: 8) {
                    ReferenceLabel(expense: reference, group: group, onTint: false)
                    Spacer(minLength: 0)
                    Button("Ohne Bezug", systemImage: "xmark.circle.fill") { chat.reference = nil }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: Theme.minTapSize, height: Theme.minTapSize)
                }
                .padding(.leading, 14)
                .glassEffect(.regular, in: .capsule)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Nachricht", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: Theme.minTapSize)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
                    .onChange(of: chat.draft) { _, text in
                        if text.count > ChatMessage.maxLength { chat.draft = String(text.prefix(ChatMessage.maxLength)) }
                    }
                Button {
                    Task { await send(group) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(group.color.tint)
                .disabled(!chat.canSend)
                .accessibilityLabel("Senden")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: Actions

    private func expense(_ id: UUID?, in group: SplitGroup) -> Expense? {
        guard opensExpenses, let id else { return nil }
        return group.expenses.first { $0.id == id }
    }

    private func withRepository(_ work: (GroupRepository) async -> Void) async {
        guard let repository = app.repository else { return }
        await work(repository)
    }

    private func load() async {
        await withRepository { await chat.load($0) }
        if chat.takeUnreadMark(userID: app.userID) || (app.group(groupID)?.unreadMessages ?? 0) > 0 {
            await app.markChatRead(groupID)
        }
    }

    private func send(_ group: SplitGroup) async {
        await withRepository { await chat.send($0, userID: app.userID, memberID: group.me(userID: app.userID)) }
    }

    private func toggleMute(_ group: SplitGroup) async {
        if let message = await app.setChatMuted(!group.chatMuted, groupID: group.id) { chat.actionError = message }
    }

    /// Opens a prepared email; the address is the contact from the privacy policy.
    private func report(_ message: ChatMessage, in group: SplitGroup) {
        var mail = URLComponents()
        mail.scheme = "mailto"
        mail.path = "dominik.gintsberger@outlook.de"
        mail.queryItems = [
            URLQueryItem(name: "subject", value: "Nachricht in Barte melden"),
            URLQueryItem(name: "body", value: """
                Gruppe: \(group.name)
                Nachricht-ID: \(message.id.uuidString.lowercased())
                Text: \(message.body ?? "")

                Was ist das Problem?
                """),
        ]
        if let url = mail.url { openURL(url) }
    }
}

// MARK: - Rows

/// One message: a bubble, the author's name and avatar for others, and the time after a run.
private struct MessageRow: View {
    let bubble: ChatTimeline.Bubble
    let group: SplitGroup
    let expense: Expense?
    let showsNames: Bool
    let onOpenExpense: (Expense) -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 28

    private var message: ChatMessage { bubble.message }
    private var authorName: String {
        message.memberID.flatMap { group.member($0)?.name } ?? String(localized: "Entfernte Person")
    }

    var body: some View {
        VStack(alignment: bubble.isMine ? .trailing : .leading, spacing: 3) {
            if bubble.startsRun && !bubble.isMine && showsNames {
                Text(authorName)
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.leading, avatarSize + 8 + 12)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if bubble.isMine {
                    Spacer(minLength: 52)
                } else if bubble.endsRun {
                    MemberAvatar(name: authorName, size: avatarSize)
                } else {
                    Color.clear.frame(width: avatarSize, height: 1)
                }
                content
                if !bubble.isMine { Spacer(minLength: 52) }
            }
            footer
        }
        .padding(.top, bubble.startsRun ? 10 : 2)
        .frame(maxWidth: .infinity, alignment: bubble.isMine ? .trailing : .leading)
    }

    @ViewBuilder
    private var content: some View {
        if message.isDeleted {
            Text("Nachricht gelöscht")
                .italic()
                .foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.inkSecondary.opacity(0.35)))
                .accessibilityLabel(bubble.isMine ? "Du hast eine Nachricht gelöscht" : "\(authorName) hat eine Nachricht gelöscht")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let expense {
                    Button { onOpenExpense(expense) } label: {
                        ReferenceLabel(expense: expense, group: group, onTint: bubble.isMine)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Öffnet die Ausgabe")
                }
                Text(message.body ?? "")
                    .font(.body)
            }
            .foregroundStyle(bubble.isMine ? Color.white : Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bubble.isMine ? group.color.tint : Color.card, in: .rect(cornerRadius: 18, style: .continuous))
            .opacity(bubble.delivery == .sending ? 0.6 : 1)
            .contentShape(.contextMenuPreview, .rect(cornerRadius: 18, style: .continuous))
            .contextMenu { menu }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let body = message.body {
            Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = body }
        }
        if bubble.delivery == .failed {
            Button("Erneut senden", systemImage: "arrow.clockwise", action: onRetry)
            Button("Verwerfen", systemImage: "trash", role: .destructive, action: onDiscard)
        } else if bubble.isMine && bubble.delivery == .sent {
            Button("Löschen", systemImage: "trash", role: .destructive, action: onDelete)
        } else if !bubble.isMine {
            Button("Melden", systemImage: "exclamationmark.bubble", action: onReport)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch bubble.delivery {
        case .sending:
            Text("Wird gesendet …")
                .font(.caption2)
                .foregroundStyle(Color.inkSecondary)
        case .failed:
            Button(action: onRetry) {
                Label("Nicht gesendet · Erneut senden", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.negative)
                    .frame(minHeight: Theme.minTapSize)
            }
            .buttonStyle(.plain)
        case .sent:
            if bubble.endsRun {
                Text(message.createdAt.formatted(.dateTime.hour().minute()))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.leading, bubble.isMine ? 0 : avatarSize + 8 + 4)
                    .padding(.trailing, bubble.isMine ? 4 : 0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var accessibilityText: String {
        var parts = [bubble.isMine ? String(localized: "Du", comment: "VoiceOver: author of my own chat message") : authorName]
        if let expense { parts.append(String(localized: "zu „\(expense.title)“", comment: "VoiceOver: a chat message about an expense")) }
        parts.append(message.body ?? "")
        parts.append(message.createdAt.formatted(.dateTime.hour().minute()))
        return parts.joined(separator: ", ")
    }
}

/// A history entry in the chat: one quiet, centered line. Edits and deletions read a bit stronger.
private struct EventLine: View {
    let event: GroupEvent
    let wording: GroupEvent.Wording
    let expense: Expense?
    let onOpen: (Expense) -> Void

    /// Edits show what changed; added and deleted expenses just their amount (the details are a tap away).
    private var detail: [String] {
        guard let first = wording.details.first else { return [] }
        switch event.kind {
        case .expenseAdded, .expenseDeleted: return [first.components(separatedBy: " · ").first ?? first]
        default: return [first]
        }
    }

    var body: some View {
        let line = HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: event.symbol)
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
            Text(([wording.headline] + detail).joined(separator: " · "))
                .multilineTextAlignment(.center)
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(event.isNotable ? Color.ink : Color.inkSecondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)

        if let expense {
            Button { onOpen(expense) } label: { line }
                .buttonStyle(.plain)
                .accessibilityHint("Öffnet die Ausgabe")
        } else {
            line
        }
    }
}

/// "Einkauf Spar · 186,40 €" with the expense's icon, inside a bubble or above the text field.
private struct ReferenceLabel: View {
    let expense: Expense
    let group: SplitGroup
    /// On the group-colored bubble of own messages.
    let onTint: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ExpenseIcon.symbol(for: expense.title, isSettlement: expense.isSettlement))
                .font(.caption.weight(.semibold))
                .foregroundStyle(onTint ? Color.white : group.color.tint)
                .accessibilityHidden(true)
            Text("\(expense.isSettlement ? "Ausgleich" : expense.title) · \(Money.format(expense.amountCents, currency: group.currency))")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(onTint ? Color.white : Color.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(onTint ? AnyShapeStyle(.white.opacity(0.2)) : AnyShapeStyle(Color.surface), in: .rect(cornerRadius: 9, style: .continuous))
        .accessibilityLabel("Zu „\(expense.title)“, \(Money.format(expense.amountCents, currency: group.currency))")
    }
}
