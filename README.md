# Barte

Ausgaben mit Freund:innen teilen – einfach, kostenlos, ohne Konto. Barte = **Bar** + **Karte**.

<img src="docs/icon/Default.png" width="96" alt="App-Icon: eine diagonal geteilte Karte">

- SwiftUI, Swift 6 (strict concurrency), iOS 26+, MVVM mit `@Observable`, Projekt per XcodeGen
- Daten in Core Data, synchronisiert über **iCloud (CloudKit)**: kein eigener Server, keine Anmeldung
- Gruppen teilen über Apples Teilen-Dialog (Nachrichten, Link); alle Eingeladenen können selbst Ausgaben eintragen

## Funktionen

| Bereich | Was es kann |
| --- | --- |
| **Gruppen** | Als farbige Karten im Wallet-Stil (Signature-Element), Name, Farbe, Währung pro Gruppe, Personen als einfache Namen (Freund:innen brauchen die App nicht) |
| **Ausgaben** | Betrag, Titel mit automatischem Symbol („Pizza“ → Besteck), wer bezahlt hat, gleichmäßig auf alle oder ausgewählte Personen, Datum, Vorschau des Anteils pro Person |
| **Ausgleichen** | Salden pro Person und die **wenigsten Überweisungen**, mit denen alle quitt sind; „Bezahlt“ verbucht einen Ausgleich |
| **Teilen** | Gruppe per iCloud teilen, Personen verwalten, Gruppe verlassen; jedes iPhone merkt sich, wer „ich“ bin |

## Das smarte Rechnen

Alle Beträge sind ganze Cent (`Int`), es gibt keine Rundungsfehler.

1. **Aufteilen** (`Split.equal`): gleich große Anteile, übrige Cent zuerst an die zahlende Person, dann in fester Reihenfolge. Alle Geräte rechnen gleich, und die Summe der Anteile ergibt immer genau den Betrag.
2. **Salden** (`Balances.compute`): Wer bezahlt hat, bekommt den Betrag gutgeschrieben, alle Beteiligten ihren Anteil abgezogen. Die Summe aller Salden ist immer 0.
3. **Vereinfachen** (`Settlement.transfers`): Jede Person mit offenem Saldo braucht mindestens eine Überweisung, und eine Teilgruppe aus k Personen, deren Salden sich zu 0 aufheben, lässt sich mit k − 1 Überweisungen ausgleichen. Das Minimum ist also *n − (größte Anzahl disjunkter Null-Summen-Teilgruppen)*. Barte findet diese Aufteilung exakt mit einer Teilmengen-DP (bis 16 Personen mit offenem Saldo, in Millisekunden) und gleicht jede Teilgruppe aus, indem die größte Schuld mit dem größten Guthaben verrechnet wird. Ab 17 Personen wird nur verrechnet (höchstens n − 1 Überweisungen).

Beispiel aus den Tests: Bei den Salden −8, +6, −2, +3, +4, −3 braucht reines Verrechnen 5 Überweisungen. Barte erkennt, dass sich +3 und −3 direkt aufheben, und kommt mit 4 aus.

Die Tests (`BarteTests/LedgerTests.swift`) vergleichen 300 Zufallsgruppen mit einer Brute-Force-Referenz.

## Setup

1. Xcode 26 oder neuer und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
2. `xcodegen generate`, dann `Barte.xcodeproj` öffnen
3. Signiert wird mit dem Team `2567P974L9` (`Configs/Project.xcconfig`). Xcode legt die App-ID und den iCloud-Container `iCloud.com.iamginsley.barte` beim ersten Build automatisch an. Falls nicht: im [Developer Portal](https://developer.apple.com/account/resources/identifiers/list/cloudContainer) den Container anlegen und unter *Signing & Capabilities* auswählen.
4. **CloudKit-Schema:** Einmal in Debug mit dem Launch-Argument `-BarteInitSchema` auf einem Gerät mit iCloud starten. Das legt das Schema in der Development-Umgebung an. Vor dem ersten TestFlight-Build im [CloudKit Dashboard](https://icloud.developer.apple.com) unter *Schema → Deploy Schema Changes* nach Production übernehmen.
5. Teilen testest du am besten mit zwei echten iPhones und zwei Apple-IDs. Im Simulator braucht es eine angemeldete Apple-ID.

### Tests

```sh
xcodebuild test -project Barte.xcodeproj -scheme Barte -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Demo-Modus (nur Debug)

Launch-Argumente für Screenshots und Tests, mit einem In-Memory-Store und Beispieldaten:

| Flag | Wirkung |
| --- | --- |
| `-BarteDemo` | Beispielgruppen, „ich“ ist Dominik |
| `-BarteEmpty` | zusammen mit `-BarteDemo`: ohne Gruppen starten |
| `-BarteGroup <n>` | n-te Karte öffnen (0 = oberste) |
| `-BarteSheet settle\|expense\|group\|about` | zusätzlich ein Sheet öffnen |

## Projektstruktur

```
Barte/
  App/            App-Einstieg, AppModel, AppDelegate (Push, angenommene Einladungen)
  Core/
    Models/       Money, Ledger (Split, Balances, Settlement), SplitGroup, ExpenseIcon
    Repositories/ GroupRepository (Core Data ↔ Werte)
    Services/     Persistence (CloudKit-Stores), SharingPresenter, Identity
    Demo/         DemoData
  Design/         Theme, GroupCard (Signature), BarteLogo, MemberAvatar
  Features/       Groups, GroupDetail, Expense, SettleUp, About
  Resources/      Assets (Farb-Tokens), AppIcon.icon, Core-Data-Modell, PrivacyInfo
BarteTests/       Swift-Testing-Suites für Geld, Aufteilung, Salden, Vereinfachen
docs/             Datenschutz (GitHub Page), App-Store-Texte, Icon-Vorschau
```

## Design

- Native Listen, Sheets und Navigationsleisten; Liquid Glass kommt vom System, eigenes Glas nur am schwebenden „Ausgabe“-Knopf
- Farben als Tokens im Asset-Katalog, die auf Systemfarben zeigen. Akzent ist Systemblau. Grün und Rot für Salden nutzen Apples Werte für „Kontrast erhöhen“ (≥ 4,5:1)
- Kartenfarben werden pro Farbe so weit abgedunkelt, dass weißer Text in Hell und Dunkel mindestens 4,5:1 erreicht
- System-Schrift, Rounded nur für große Beträge und Titel; Beträge `monospacedDigit`; Dynamic Type überall
- Easter Egg: Tippe in „Über Barte“ ein paar Mal auf das Logo. Und schreib mal „Dackel“ als Ausgabe.

## Datenschutz

Barte hat keinen Server und sammelt nichts. Gruppen liegen in der iCloud der Person, die sie erstellt, und sind nur für eingeladene Personen sichtbar. Siehe [docs/datenschutz.md](docs/datenschutz.md).
