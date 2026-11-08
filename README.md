# Barte

Ausgaben mit Freund:innen teilen – einfach und kostenlos. Barte = **Bar** + **Karte**.

<img src="docs/icon/Default.png" width="96" alt="App-Icon: eine diagonal geteilte Karte">

- SwiftUI, Swift 6 (strict concurrency), iOS 26+, MVVM mit `@Observable`, Projekt per XcodeGen
- Backend **Nhost** (Frankfurt): Anmeldung mit Apple (iOS) bzw. Google (später Android), Postgres mit Hasura-Rechten, alle Schreibzugriffe über SQL-Funktionen, Live-Updates über GraphQL-Subscriptions. Kein SDK, die App spricht direkt mit Auth, GraphQL und Functions
- Einladen per Link oder Code; alle Eingeladenen tragen selbst Ausgaben ein, auf iPhone und später Android

## Funktionen

| Bereich | Was es kann |
| --- | --- |
| **Gruppen** | Als farbige Karten im Wallet-Stil (Signature-Element), Name, Farbe, Währung pro Gruppe, Personen als einfache Namen (Freund:innen brauchen die App nicht) |
| **Ausgaben** | Betrag, Titel mit automatischem Symbol („Pizza“ → Besteck), wer bezahlt hat, gleichmäßig auf alle oder ausgewählte Personen, Datum, Vorschau des Anteils pro Person |
| **Ausgleichen** | Salden pro Person und die **wenigsten Überweisungen**, mit denen alle quitt sind; „Bezahlt“ verbucht einen Ausgleich |
| **Abschließen** | Wenn alle quitt sind, die Gruppe für alle unter „Abgeschlossen“ ablegen statt löschen; sie bleibt lesbar, zählt nicht mehr in der Übersicht und im Widget und öffnet sich von selbst wieder, sobald jemand eine Ausgabe ändert |
| **Verlauf** | Wer was eingetragen, geändert oder gelöscht hat, mit Vorher/Nachher; nicht änderbar, auch nicht vom Ersteller. Bearbeitete Ausgaben zeigen „bearbeitet“. Mitteilungen bei neuen, geänderten (Betrag, Zahler, Aufteilung) und gelöschten Ausgaben und Ausgleichen, leise beim Abschließen |
| **Einladen** | Link oder Code teilen; wer beitritt, wählt seinen Namen aus der Gruppe (dann gehören die bisherigen Ausgaben zu ihm) oder trägt sich neu ein |
| **Konto** | Mit Apple anmelden, abmelden, Konto löschen inkl. Widerruf bei Apple; Gruppe verlassen oder (als Ersteller:in) für alle löschen |

## Das smarte Rechnen

Alle Beträge sind ganze Cent (`Int`), es gibt keine Rundungsfehler.

1. **Aufteilen** (`Split.equal`, `Split.weighted`): gleich große Anteile, nach Anteilen (ein Paar zählt doppelt) oder mit festen Beträgen pro Person. Bei gleichen Anteilen gehen übrige Cent zuerst an die zahlende Person, dann in fester Reihenfolge; nach Anteilen bekommen die größten Reste je einen Cent, bei Gleichstand genauso. Alle Geräte rechnen gleich, und die Summe der Anteile ergibt immer genau den Betrag.
2. **Salden** (`Balances.compute`): Wer bezahlt hat, bekommt den Betrag gutgeschrieben, alle Beteiligten ihren Anteil abgezogen. Die Summe aller Salden ist immer 0.
3. **Vereinfachen** (`Settlement.transfers`): Jede Person mit offenem Saldo braucht mindestens eine Überweisung, und eine Teilgruppe aus k Personen, deren Salden sich zu 0 aufheben, lässt sich mit k − 1 Überweisungen ausgleichen. Das Minimum ist also *n − (größte Anzahl disjunkter Null-Summen-Teilgruppen)*. Barte findet diese Aufteilung exakt mit einer Teilmengen-DP (bis 16 Personen mit offenem Saldo, in Millisekunden) und gleicht jede Teilgruppe aus, indem die größte Schuld mit dem größten Guthaben verrechnet wird. Ab 17 Personen wird nur verrechnet (höchstens n − 1 Überweisungen).

Beispiel aus den Tests: Bei den Salden −8, +6, −2, +3, +4, −3 braucht reines Verrechnen 5 Überweisungen. Barte erkennt, dass sich +3 und −3 direkt aufheben, und kommt mit 4 aus.

Die Tests (`BarteTests/LedgerTests.swift`) vergleichen 300 Zufallsgruppen mit einer Brute-Force-Referenz.

## Setup

1. Xcode 26 oder neuer und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
2. `xcodegen generate`, dann `Barte.xcodeproj` öffnen. Signiert wird mit dem Team `2567P974L9` (`Configs/Project.xcconfig`).

Subdomain und Region des Nhost-Projekts stehen in `Barte/Core/Services/Backend.swift` (öffentlich, kein Secret). Der Demo-Modus funktioniert ohne Server.

### Nhost einrichten

Projekt `Barte` (Subdomain `uenqaayyhyrekjhojdwn`, Region **Frankfurt, eu-central-1**, so steht es in der Datenschutzerklärung). Alles Serverseitige liegt im Repo und wird per Git ausgerollt:

- `nhost/nhost.toml`: Konfiguration (Apple-Anmeldung, Umgebungsvariablen der Functions)
- `nhost/migrations/`: Tabellen und SQL-Funktionen, `nhost/metadata/`: Hasura-Rechte (Rolle `user`) und die Funktionen als Mutations
- `functions/`: `apple-revoke` (Konto löschen) und `events/group-event` (Mitteilungen, wird nur von Hasura aufgerufen)

1. **Secrets** im Nhost-Dashboard unter *Settings → Secrets* anlegen (nie ins Repo). Im Developer Portal einen Key mit „Sign in with Apple“ **und** „Apple Push Notifications service“ erstellen (`AuthKey_XXXX.p8`):
   - `APPLE_KEY_ID`: die Key ID
   - `APPLE_PRIVATE_KEY`: der Inhalt der `.p8`-Datei

   Für einen eigenen APNs-Key zusätzlich `APNS_KEY_ID` und `APNS_PRIVATE_KEY` als Umgebungsvariablen eintragen; sonst wird der Apple-Key genutzt. Debug-Builds registrieren sich für die Sandbox, TestFlight und App Store für Production.
2. **GitHub verbinden:** *Deployments → Settings → Connect to GitHub*, Repo `iamginsley/barte`, Base Directory `/`, Branch `main`. Jeder Merge nach `main` spielt Konfiguration, Migrationen, Metadaten und Functions ein.
3. **Prüfen** nach dem ersten Deployment: `NHOST_ADMIN_SECRET=… node scripts/test-nhost-api.mjs` legt drei Test-Personen an, prüft Rechte, Fehlermeldungen und Datenformat gegen das echte Projekt und räumt danach auf.
4. **Google (für Android, später):** in `nhost.toml` unter `auth.method.oauth.google` aktivieren. Das Datenmodell ist dafür schon fertig, die iOS-App bietet nur Apple an.

Einladungslinks zeigen auf `docs/join/` (GitHub Pages). Die Seite zeigt den Code und öffnet die App über `barte://join/<code>`.

**Gratis-Tarif:** Nhost pausiert Gratis-Projekte nach einer Woche ohne Zugriffe. Die Daten bleiben erhalten, das Projekt muss dann im Dashboard wieder gestartet werden. Für den Store-Start ist der Pro-Tarif sinnvoll.

### Tests

```sh
xcodebuild test -project Barte.xcodeproj -scheme Barte -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
./scripts/test-migrations.sh                         # SQL: Migrationen + Funktions-Tests auf lokalem Postgres (brew install postgresql@17)
(cd functions && npm install && npm test)            # Nhost Functions apple-revoke und events/group-event (vitest)
NHOST_ADMIN_SECRET=… node scripts/test-nhost-api.mjs # Hasura-Rechte gegen das echte Projekt
```

### Demo-Modus (nur Debug)

Launch-Argumente für Screenshots und Tests, ohne Server, mit Beispieldaten im Speicher:

| Flag | Wirkung |
| --- | --- |
| `-BarteDemo` | Beispielgruppen, angemeldet als Dominik |
| `-BarteEmpty` | zusammen mit `-BarteDemo`: ohne Gruppen starten |
| `-BarteSignedOut` | zusammen mit `-BarteDemo`: Anmeldebildschirm zeigen |
| `-BarteGroup <n>` | n-te Karte öffnen (0 = oberste) |
| `-BarteSheet settle\|expense\|group\|about\|invite\|join` | zusätzlich ein Sheet öffnen (`join` zeigt eine Beispiel-Einladung) |

## Projektstruktur

```
Barte/
  App/            App-Einstieg, AppModel (Anmeldung, Gruppen, Live-Updates), RootView
  Core/
    Models/       Money, Ledger (Split, Balances, Settlement), SplitGroup, PaymentDetails, ExpenseIcon, Invite, LocalDay
    Repositories/ GroupRepository (Nhost)
    Services/     Backend, NhostSession (Anmeldung), NhostAPI (GraphQL, Functions, Subscriptions), AppleReauthentication, Notifications (Push), WidgetSync, Preferences
    Demo/         DemoData, DemoGroupRepository
  Design/         Theme, GroupCard (Signature), BarteLogo, MemberAvatar
  Features/       Auth, Groups, GroupDetail (inkl. Einladen), Join, Expense, SettleUp, Payment, About
  Resources/      Assets (Farb-Tokens), AppIcon.icon, PrivacyInfo
BarteWidgets/     Widget „Saldo“ (klein, mittel, Sperrbildschirm), liest den Snapshot aus der App Group
Shared/           Widget-Snapshot und barte://-Links, in App und Widget
BarteTests/       Swift-Testing-Suites für Geld, Aufteilung, Salden, Vereinfachen, Einladungen, Tage
nhost/            Konfiguration, Migrationen, Hasura-Metadaten, SQL-Tests
functions/        Nhost Functions apple-revoke und events/group-event mit Tests
scripts/          SQL-Tests auf lokalem Postgres, API-Prüfung gegen das echte Projekt
docs/             Datenschutz und Einladungsseite (GitHub Pages), App-Store-Texte, Icon-Vorschau
```

## Design

- Native Listen, Sheets und Navigationsleisten; Liquid Glass kommt vom System, eigenes Glas nur am schwebenden „Ausgabe“-Knopf
- Farben als Tokens im Asset-Katalog, die auf Systemfarben zeigen. Akzent ist Systemblau. Grün und Rot für Salden nutzen Apples Werte für „Kontrast erhöhen“ (≥ 4,5:1)
- Kartenfarben werden pro Farbe so weit abgedunkelt, dass weißer Text in Hell und Dunkel mindestens 4,5:1 erreicht
- System-Schrift, Rounded nur für große Beträge und Titel; Beträge `monospacedDigit`; Dynamic Type überall
- Easter Egg: Tippe in „Über Barte“ ein paar Mal auf das Logo. Und schreib mal „Dackel“ als Ausgabe.

## Datenmodell

- `groups`, `members` (Name, optional verknüpft mit einem Konto über `user_id`), `expenses` (Betrag in Cent, `spent_on` als Wandzeit-Tag des eintragenden iPhones, `participant_ids`, `split_kind` und `split_values` in derselben Reihenfolge wie die Beteiligten)
- `payment_details` (PayPal.me, IBAN, Kontoinhaber:in) sieht nur, wer mit der Person in einer Gruppe ist; `device_tokens` liest nur die Function `events/group-event`
- `group_events`: der Verlauf. Trigger auf `expenses`, `groups` und `members` schreiben jede Änderung mit Vorher/Nachher, Person und Zeit in dieselbe Transaktion; ein weiterer Trigger verbietet Ändern und Löschen (außer zusammen mit der Gruppe). Jeder neue Eintrag löst über einen Hasura-Event-Trigger (`NHOST_WEBHOOK_SECRET`) `events/group-event` aus, das die Mitteilungen verschickt. So kann keine App eine Änderung durchführen, ohne dass die anderen davon erfahren
- Lesen nur über die Hasura-Rechte der Rolle `user` (eigene Gruppen, deren Personen und Ausgaben), Schreiben nur über SQL-Funktionen wie `create_group`, `join_group`, `save_expense`, `delete_my_account`. Hasura reicht die Sitzung als `hasura_session` an die Funktionen weiter; Fehler kommen als SQLSTATE 22000 mit dem Hinweis (z. B. `not_member`) als Meldung in der App an
- Gerechnet wird in der App (`Ledger.swift`), damit alle Geräte dasselbe Ergebnis zeigen. Eine Android-App muss `Split.equal` und `Split.weighted` genauso umsetzen: Cent-Reste zuerst an die zahlende Person, dann nach der UUID in Großbuchstaben sortiert (bei Anteilen zuerst nach dem größten Rest).

## Datenschutz

Anmeldung mit Apple, Daten bei Nhost in Frankfurt, keine Werbung und kein Tracking. Eine Gruppe sehen nur ihre Mitglieder. Siehe [docs/datenschutz.md](docs/datenschutz.md).
