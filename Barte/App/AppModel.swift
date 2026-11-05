import Foundation
import Observation
import Supabase

/// An error with a message ready for an alert.
struct UserFacingError: Error {
    let message: String

    init(_ error: Error) {
        message = BarteError.from(error).errorDescription ?? "Das hat nicht geklappt."
    }
}

/// App-wide state: sign-in, the list of groups and an invite waiting to be opened.
/// Groups are refetched after every write and whenever the server reports a change.
@Observable
@MainActor
final class AppModel {
    enum Phase: Equatable {
        case launching
        case notConfigured
        case signedOut
        case ready
    }

    private(set) var phase: Phase = .launching
    private(set) var groups: [SplitGroup] = []
    /// How people want to be paid, by user id.
    private(set) var payments: [UUID: PaymentDetails] = [:]
    private(set) var userID: UUID?
    /// False until the first fetch finished, so the empty state doesn't flash.
    private(set) var hasLoaded = false
    private(set) var loadError: String?
    /// Set when an invite link opens the app; GroupsView shows the join sheet.
    var pendingInviteCode: String?
    /// Set when a notification or widget opens a group; GroupsView navigates there.
    var pendingGroupID: UUID?

    let isDemo: Bool
    let client: SupabaseClient?
    let repository: GroupRepository?
    private let notifier: GroupNotifier?

    private var authTask: Task<Void, Never>?
    private var changesTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    init(client: SupabaseClient? = Backend.client) {
        if DemoData.isEnabled {
            Preferences.useDemoDefaults()
            Preferences.myName = "Dominik"
            self.client = nil
            self.repository = DemoGroupRepository()
            self.notifier = nil
            self.isDemo = true
            return
        }
        self.client = client
        self.repository = client.map(SupabaseGroupRepository.init(client:))
        self.notifier = client.map(GroupNotifier.init(client:))
        self.isDemo = false
    }

    // MARK: Lifecycle

    func start() {
        if isDemo {
            if DemoData.has("-BarteSignedOut") {
                phase = .signedOut
            } else {
                signedIn(as: DemoData.userID)
            }
            return
        }
        guard let client else {
            phase = .notConfigured
            return
        }
        guard authTask == nil else { return }
        authTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session, !session.isExpired {
                        if self.userID != session.user.id { self.signedIn(as: session.user.id) }
                    } else if event == .initialSession {
                        self.signedOut()
                    }
                case .signedOut, .userDeleted:
                    self.signedOut()
                default:
                    break
                }
            }
        }
    }

    /// Used by the demo sign-in button.
    func signInDemo() {
        signedIn(as: DemoData.userID)
    }

    private func signedIn(as id: UUID) {
        userID = id
        phase = .ready
        Task { await reload() }
        if !isDemo {
            Task {
                await PushToken.register(client: client)
                await Notifications.registerForPushIfAllowed()
            }
        }
        changesTask?.cancel()
        guard let repository else { return }
        changesTask = Task { [weak self] in
            for await _ in repository.changes() {
                self?.scheduleReload()
            }
        }
    }

    private func signedOut() {
        changesTask?.cancel()
        changesTask = nil
        userID = nil
        groups = []
        payments = [:]
        WidgetSync.clear()
        hasLoaded = false
        phase = .signedOut
    }

    // MARK: Data

    func reload() async {
        guard let repository, userID != nil else { return }
        do {
            async let fetchedGroups = repository.fetchGroups()
            // Payment details are a nice-to-have: groups still load without them.
            async let fetchedPayments = try? repository.fetchPaymentDetails()
            groups = try await fetchedGroups
            if let fetched = await fetchedPayments { payments = fetched }
            loadError = nil
            WidgetSync.update(groups: groups, userID: userID)
        } catch is CancellationError {
            return
        } catch {
            loadError = BarteError.from(error).errorDescription
        }
        hasLoaded = true
    }

    /// Several changes often arrive at once (an expense and its group); fetch once for all of them.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    /// Runs a write and refreshes. Returns a message for the UI if it failed.
    @discardableResult
    func run(_ work: @Sendable (GroupRepository) async throws -> Void) async -> String? {
        switch await runReturning(work) {
        case .success: nil
        case .failure(let failure): failure.message
        }
    }

    /// Like `run`, for writes that return something (a new group's id).
    func runReturning<T: Sendable>(_ work: @Sendable (GroupRepository) async throws -> T) async -> Result<T, UserFacingError> {
        guard let repository else { return .failure(UserFacingError(BarteError.notSignedIn)) }
        do {
            let value = try await work(repository)
            await reload()
            return .success(value)
        } catch {
            await reload()
            return .failure(UserFacingError(error))
        }
    }

    func group(_ id: UUID) -> SplitGroup? { groups.first { $0.id == id } }

    func me(in groupID: UUID) -> UUID? { group(groupID)?.me(userID: userID) }

    /// How this member wants to be paid, if they use the app and set it up.
    func payment(for member: Member?) -> PaymentDetails? {
        member?.userID.flatMap { payments[$0] }
    }

    var myPayment: PaymentDetails? { userID.flatMap { payments[$0] } }

    // MARK: Links

    func open(_ url: URL) {
        if let code = InviteLink.code(from: url) {
            pendingInviteCode = code
        } else if let id = BarteLink.groupID(from: url) {
            pendingGroupID = id
        }
    }

    // MARK: Notifications

    /// Pushes a new expense or payback to the others in the group, if anyone else there uses the app.
    func notify(_ kind: GroupNotifier.Kind, expenseID: UUID, in groupID: UUID) {
        guard let notifier, group(groupID)?.isShared == true else { return }
        notifier.send(kind, expenseID: expenseID)
    }

    // MARK: Account

    func signOut() async {
        if isDemo {
            signedOut()
            return
        }
        await PushToken.unregister(client: client)
        try? await client?.auth.signOut()
    }

    /// Confirms with Apple first; cancelling there throws AppleReauthentication.Failure.canceled.
    func deleteAccount() async throws {
        guard let repository else { return }
        let code = isDemo ? "demo" : try await AppleReauthentication().authorizationCode()
        try await repository.deleteAccount(appleAuthorizationCode: code)
        signedOut()
    }
}
