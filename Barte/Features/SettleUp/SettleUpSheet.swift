import SwiftUI

/// The smart part: the fewest payments that make everyone quitt, plus everyone's balance.
struct SettleUpSheet: View {
    let groupID: UUID

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pending: Transfer?
    @State private var paidCount = 0
    @State private var errorMessage: String?
    @State private var showsPaymentDetails = false

    var body: some View {
        NavigationStack {
            Group {
                if let group = model.group(groupID) {
                    content(group)
                }
            }
            .navigationTitle("Ausgleichen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", role: .close) { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: paidCount)
        .sheet(isPresented: $showsPaymentDetails) { PaymentDetailsSheet() }
        .alert("Nicht verbucht", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func content(_ group: SplitGroup) -> some View {
        let me = model.me(in: group.id)
        let transfers = group.transfers
        let direct = Settlement.directTransferCount(expenses: group.expenses)
        let balances = group.balances
        return List {
            if transfers.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.positive)
                            .symbolEffect(.bounce, value: reduceMotion ? 0 : paidCount)
                        Text("Alle quitt!")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text("Niemand schuldet hier jemandem etwas.")
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .accessibilityElement(children: .combine)
                }
            } else {
                Section {
                    ForEach(transfers, id: \.self) { transfer in
                        TransferRow(
                            transfer: transfer, group: group, me: me,
                            payment: transfer.from == me ? model.payment(for: group.member(transfer.to)) : nil
                        ) { pending = transfer }
                    }
                } header: {
                    Text("Mit \(transfers.count) Überweisungen seid ihr quitt", comment: "With plural variants")
                        .textCase(nil)
                        .font(.subheadline.weight(.semibold))
                } footer: {
                    if direct > transfers.count {
                        Label("Barte hat die Schulden verrechnet: \(transfers.count) statt \(direct) einzelner Rückzahlungen.", systemImage: "sparkles")
                    }
                }

                if transfers.contains(where: { $0.to == me }), model.myPayment == nil {
                    Section {
                        Button {
                            showsPaymentDetails = true
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Zahlungsdaten hinterlegen")
                                    Text("Mit PayPal.me oder IBAN können dir die anderen direkt aus Barte zahlen.")
                                        .font(.footnote)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                            } icon: {
                                Image(systemName: "creditcard")
                            }
                            .frame(minHeight: Theme.minTapSize)
                        }
                    }
                }
            }

            Section("Salden") {
                ForEach(group.members) { member in
                    let balance = balances[member.id] ?? 0
                    HStack(spacing: 12) {
                        MemberAvatar(name: member.name, isMe: member.id == me, size: 30)
                        Text(member.id == me ? String(localized: "\(member.name) (ich)", comment: "My own name in a list of people") : member.name)
                        Spacer()
                        Text(balance == 0 ? String(localized: "quitt", comment: "Balance of zero") : Money.format(balance, currency: group.currency, showsSign: true))
                            .font(.amount)
                            .foregroundStyle(balance.balanceColor)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: transfers)
        .confirmationDialog(
            "Als bezahlt markieren?",
            isPresented: .init(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { transfer in
            Button("Ja, ist bezahlt") { Task { await record(transfer, in: group) } }
        } message: { transfer in
            Text("\(group.name(of: transfer.from, me: me)) → \(group.name(of: transfer.to, me: me)): \(Money.format(transfer.amountCents, currency: group.currency))")
        }
    }

    private func record(_ transfer: Transfer, in group: SplitGroup) async {
        let settlement = Expense(
            // Stored as data; every device shows its own word for settlements.
            id: UUID(), title: "Ausgleich", amountCents: transfer.amountCents, date: .now,
            payerID: transfer.from, participantIDs: [transfer.to], isSettlement: true
        )
        let groupID = group.id
        if let message = await model.run({ try await $0.save(settlement, in: groupID) }) {
            errorMessage = message
        } else {
            paidCount += 1
        }
    }
}

private struct TransferRow: View {
    let transfer: Transfer
    let group: SplitGroup
    let me: UUID?
    /// The recipient's details, when I am the one paying.
    let payment: PaymentDetails?
    let markPaid: () -> Void

    @State private var copied = 0

    var body: some View {
        let from = group.member(transfer.from)?.name ?? "?"
        let to = group.member(transfer.to)?.name ?? "?"
        let involvesMe = transfer.from == me || transfer.to == me
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    MemberAvatar(name: from, isMe: transfer.from == me, size: 28)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.inkSecondary)
                    MemberAvatar(name: to, isMe: transfer.to == me, size: 28)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sentence)
                        .font(involvesMe ? .body.weight(.semibold) : .body)
                    Text(Money.format(transfer.amountCents, currency: group.currency))
                        .font(.amount)
                        .foregroundStyle(transfer.from == me ? Color.negative : transfer.to == me ? Color.positive : Color.inkSecondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button("Bezahlt", action: markPaid)
                    .buttonStyle(.bordered)
                    .frame(minHeight: Theme.minTapSize)
                    .accessibilityLabel("\(from) an \(to) als bezahlt markieren")
            }
            if let payment, !payment.isEmpty {
                payButtons(payment, to: to)
            }
        }
        .padding(.vertical, 2)
        .sensoryFeedback(.success, trigger: copied)
    }

    /// PayPal with the amount filled in, and the bank details to copy.
    private func payButtons(_ payment: PaymentDetails, to name: String) -> some View {
        HStack(spacing: 8) {
            if let url = payment.paypalURL(amountCents: transfer.amountCents, currency: group.currency) {
                Link(destination: url) {
                    Label("PayPal", systemImage: "arrow.up.forward")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("\(name) mit PayPal \(Money.format(transfer.amountCents, currency: group.currency)) zahlen")
            }
            if let iban = payment.iban {
                Menu {
                    Section("\(payment.accountHolder ?? name)\n\(IBAN.formatted(iban))") {
                        Button("IBAN kopieren", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = iban
                            copied += 1
                        }
                        Button("Betrag kopieren", systemImage: "banknote") {
                            UIPasteboard.general.string = Money.editString(transfer.amountCents)
                            copied += 1
                        }
                        if let holder = payment.accountHolder {
                            Button("Name kopieren", systemImage: "person") {
                                UIPasteboard.general.string = holder
                                copied += 1
                            }
                        }
                    }
                } label: {
                    Label("Überweisen", systemImage: "building.columns")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Bankdaten von \(name)")
            }
        }
        .controlSize(.regular)
    }

    private var sentence: String {
        let from = group.member(transfer.from)?.name ?? "?"
        let to = group.member(transfer.to)?.name ?? "?"
        if transfer.from == me { return String(localized: "Du zahlst \(to)") }
        if transfer.to == me { return String(localized: "\(from) zahlt dir") }
        return String(localized: "\(from) zahlt \(to)")
    }
}
