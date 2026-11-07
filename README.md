# Barte

Ausgaben mit Freund:innen teilen – einfach und kostenlos. Barte = **Bar** + **Karte**.

<img src="docs/icon/Default.png" width="96" alt="App-Icon: eine diagonal geteilte Karte">

- SwiftUI, Swift 6 (strict concurrency), iOS 26+, MVVM mit `@Observable`, Projekt per XcodeGen
- Backend **Firebase** (Frankfurt): Anmeldung mit Apple (iOS) bzw. Google (später Android), Firestore mit Security Rules (Clients lesen nur), alle Schreibzugriffe über Cloud Functions, Live-Updates über Snapshot-Listener
- Einladen per Link oder Code; alle Eingeladenen tragen selbst Ausgaben ein, auf iPhone und später Android

## Funktionen

| Bereich | Was es kann |
| --- | --- |
| **Gruppen** | Als farbige Karten im Wallet-Stil (Signature-Element), Name, Farbe, Währung pro Gruppe, Personen als einfache Namen (Freund:innen brauchen die App nicht) |
| **Ausgaben** | Betrag, Titel mit automatischem Symbol („Pizza“ → Besteck), wer bezahlt hat, gleichmäßig auf alle oder ausgewählte Personen, Datum, Vorschau des Anteils pro Person |
| **Ausgleichen** | Salden pro Person und die **wenigsten Überweisungen**, mit denen alle quitt sind; „Bezahlt“ verbucht einen Ausgleich |
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
2. `GoogleService-Info.plist` aus der Firebase-Konsole (Projekteinstellungen → Deine Apps → iOS-App `com.iamginsley.barte`) nach `Barte/Resources/` legen (git-ignoriert)
3. `xcodegen generate`, dann `Barte.xcodeproj` öffnen. Signiert wird mit dem Team `2567P974L9` (`Configs/Project.xcconfig`).

Ohne `GoogleService-Info.plist` startet die App mit einem Hinweis; der Demo-Modus funktioniert immer.

### Firebase einrichten

Werkzeug: `cd firebase/functions && npm ci`, danach `npx firebase login` (einmalig, im Browser).

1. **Projekt:** In der [Firebase-Konsole](https://console.firebase.google.com) ein Projekt `barte` anlegen (ohne Google Analytics) und auf den **Blaze-Tarif** stellen (Cloud Functions brauchen ihn; bei Barte-Größe bleibt es im kostenlosen Kontingent). Dann `cd firebase && npx --prefix functions firebase use --add` und das Projekt wählen (schreibt `.firebaserc`).
2. **Firestore:** Datenbank im Produktionsmodus anlegen, Standort **europe-west3 (Frankfurt)** (so steht es in der Datenschutzerklärung).
3. **iOS-App:** In den Projekteinstellungen eine iOS-App mit `com.iamginsley.barte` hinzufügen und `GoogleService-Info.plist` herunterladen (siehe Setup).
4. **Mit Apple anmelden:** Authentication → Sign-in method → Apple aktivieren. Für „Konto löschen“ (Widerruf bei Apple) unter *OAuth code flow configuration* die Services-ID, Team-ID `2567P974L9`, Key-ID und den privaten Schlüssel eines Keys mit „Sign in with Apple“ eintragen (`AuthKey_XXXX.p8`, nie ins Repo).
5. **Mitteilungen:** Im Developer Portal beim Key zusätzlich „Apple Push Notifications service“ aktivieren (oder einen eigenen APNs-Key erstellen), dann:
   ```sh
   cd firebase
   npx --prefix functions firebase functions:secrets:set APNS_PRIVATE_KEY < AuthKey_XXXX.p8
   echo "APNS_KEY_ID=<KeyID>" > functions/.env.<projekt-id>
   ```
   Debug-Builds registrieren sich für die Sandbox, TestFlight und App Store für Production.
6. **Deployen:** `cd firebase && npx --prefix functions firebase deploy --only firestore,functions` (Regeln, Indizes und alle Functions in `europe-west3`)
7. **Google (für Android, später):** Authentication → Sign-in method → Google aktivieren. Das Datenmodell ist dafür schon fertig, die iOS-App bietet nur Apple an.

Einladungslinks zeigen auf `docs/join/` (GitHub Pages). Die Seite zeigt den Code und öffnet die App über `barte://join/<code>`.

### Tests

```sh
xcodebuild test -project Barte.xcodeproj -scheme Barte -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
./scripts/test-firebase.sh                           # Cloud Functions und Security Rules gegen den Firestore-Emulator (brew install node openjdk)
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
  App/            App-Einstieg, AppModel (Anmeldung, Gruppen, Realtime), RootView
  Core/
    Models/       Money, Ledger (Split, Balances, Settlement), SplitGroup, PaymentDetails, ExpenseIcon, Invite, LocalDay
    Repositories/ GroupRepository (Firestore lesen, Cloud Functions schreiben)
    Services/     Backend, AppleReauthentication, Notifications (Push), WidgetSync, Preferences
    Demo/         DemoData, DemoGroupRepository
  Design/         Theme, GroupCard (Signature), BarteLogo, MemberAvatar
  Features/       Auth, Groups, GroupDetail (inkl. Einladen), Join, Expense, SettleUp, Payment, About
  Resources/      Assets (Farb-Tokens), AppIcon.icon, PrivacyInfo
BarteWidgets/     Widget „Saldo“ (klein, mittel, Sperrbildschirm), liest den Snapshot aus der App Group
Shared/           Widget-Snapshot und barte://-Links, in App und Widget
BarteTests/       Swift-Testing-Suites für Geld, Aufteilung, Salden, Vereinfachen, Einladungen, Tage
firebase/         Security Rules, Cloud Functions (functions/src: api, push) und ihre Tests (functions/test)
scripts/          test-firebase.sh
docs/             Datenschutz und Einladungsseite (GitHub Pages), App-Store-Texte, Icon-Vorschau
```

## Design

- Native Listen, Sheets und Navigationsleisten; Liquid Glass kommt vom System, eigenes Glas nur am schwebenden „Ausgabe“-Knopf
- Farben als Tokens im Asset-Katalog, die auf Systemfarben zeigen. Akzent ist Systemblau. Grün und Rot für Salden nutzen Apples Werte für „Kontrast erhöhen“ (≥ 4,5:1)
- Kartenfarben werden pro Farbe so weit abgedunkelt, dass weißer Text in Hell und Dunkel mindestens 4,5:1 erreicht
- System-Schrift, Rounded nur für große Beträge und Titel; Beträge `monospacedDigit`; Dynamic Type überall
- Easter Egg: Tippe in „Über Barte“ ein paar Mal auf das Logo. Und schreib mal „Dackel“ als Ausgabe.

## Datenmodell

- `groups/{id}` mit Name, Währung, Farbe, Einladungscode, den Personen (`members`: Name, optional verknüpft mit einem Konto über `uid`) und `memberUids` für Abfragen und Regeln; `groups/{id}/expenses/{id}` mit Betrag in Cent, `spentOn` als Wandzeit-Tag des eintragenden iPhones, `participantIds`, `splitKind` und `splitValues` in derselben Reihenfolge wie die Beteiligten
- `invites/{code}`, `paymentDetails/{uid}` (PayPal.me, IBAN, Kontoinhaber:in) und `devices/{token}` liest nur der Server; Zahlungsdaten gibt die Function `paymentDetails` nur an Personen aus denselben Gruppen heraus
- Lesen nur über die Security Rules (`firebase/firestore.rules`), Schreiben nur über Cloud Functions wie `createGroup`, `joinGroup`, `saveExpense`, `deleteAccount`. Mitteilungen verschickt der Trigger `notifyOnExpense` direkt über APNs.
- Gerechnet wird in der App (`Ledger.swift`), damit alle Geräte dasselbe Ergebnis zeigen. Eine Android-App muss `Split.equal` und `Split.weighted` genauso umsetzen: Cent-Reste zuerst an die zahlende Person, dann nach der UUID in Großbuchstaben sortiert (bei Anteilen zuerst nach dem größten Rest).

## Datenschutz

Anmeldung mit Apple, Daten bei Google Firebase in Frankfurt, keine Werbung und kein Tracking. Eine Gruppe sehen nur ihre Mitglieder. Siehe [docs/datenschutz.md](docs/datenschutz.md).
