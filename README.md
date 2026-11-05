# Barte

Ausgaben mit Freund:innen teilen – einfach und kostenlos. Barte = **Bar** + **Karte**.

<img src="docs/icon/Default.png" width="96" alt="App-Icon: eine diagonal geteilte Karte">

- SwiftUI, Swift 6 (strict concurrency), iOS 26+, MVVM mit `@Observable`, Projekt per XcodeGen
- Backend **Supabase**: Anmeldung mit Apple (iOS) bzw. Google (später Android), Postgres mit Row Level Security, alle Schreibzugriffe über SQL-Funktionen, Live-Updates über Realtime
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

1. **Aufteilen** (`Split.equal`): gleich große Anteile, übrige Cent zuerst an die zahlende Person, dann in fester Reihenfolge. Alle Geräte rechnen gleich, und die Summe der Anteile ergibt immer genau den Betrag.
2. **Salden** (`Balances.compute`): Wer bezahlt hat, bekommt den Betrag gutgeschrieben, alle Beteiligten ihren Anteil abgezogen. Die Summe aller Salden ist immer 0.
3. **Vereinfachen** (`Settlement.transfers`): Jede Person mit offenem Saldo braucht mindestens eine Überweisung, und eine Teilgruppe aus k Personen, deren Salden sich zu 0 aufheben, lässt sich mit k − 1 Überweisungen ausgleichen. Das Minimum ist also *n − (größte Anzahl disjunkter Null-Summen-Teilgruppen)*. Barte findet diese Aufteilung exakt mit einer Teilmengen-DP (bis 16 Personen mit offenem Saldo, in Millisekunden) und gleicht jede Teilgruppe aus, indem die größte Schuld mit dem größten Guthaben verrechnet wird. Ab 17 Personen wird nur verrechnet (höchstens n − 1 Überweisungen).

Beispiel aus den Tests: Bei den Salden −8, +6, −2, +3, +4, −3 braucht reines Verrechnen 5 Überweisungen. Barte erkennt, dass sich +3 und −3 direkt aufheben, und kommt mit 4 aus.

Die Tests (`BarteTests/LedgerTests.swift`) vergleichen 300 Zufallsgruppen mit einer Brute-Force-Referenz.

## Setup

1. Xcode 26 oder neuer und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
2. `cp Config.example.xcconfig Config.xcconfig` und Host und Anon Key deines Supabase-Projekts eintragen (die Datei ist git-ignoriert)
3. `xcodegen generate`, dann `Barte.xcodeproj` öffnen. Signiert wird mit dem Team `2567P974L9` (`Configs/Project.xcconfig`).

Ohne `Config.xcconfig` startet die App mit einem Hinweis; der Demo-Modus funktioniert immer.

### Supabase einrichten

1. Projekt auf [supabase.com](https://supabase.com) anlegen, Region **Frankfurt (eu-central-1)** (so steht es in der Datenschutzerklärung)
2. Datenbank: `supabase link --project-ref <ref>`, dann `supabase db push` (spielt `supabase/migrations/` ein)
3. **Mit Apple anmelden:** Authentication → Sign In / Providers → Apple aktivieren, bei *Client IDs* `com.iamginsley.barte` eintragen. Für die native Anmeldung in der App reicht das.
4. **Konto löschen (Apple-Widerruf):** Im Developer Portal einen Key mit „Sign in with Apple“ erstellen (`AuthKey_XXXX.p8`, nie ins Repo), dann:
   ```sh
   supabase secrets set APPLE_TEAM_ID=2567P974L9 APPLE_KEY_ID=<KeyID> APPLE_CLIENT_ID=com.iamginsley.barte APPLE_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
   supabase functions deploy apple-revoke
   ```
5. **Google (für Android, später):** Authentication → Providers → Google aktivieren und die OAuth-Client-IDs aus der Google Cloud Console eintragen. Das Datenmodell ist dafür schon fertig, die iOS-App bietet nur Apple an.

Einladungslinks zeigen auf `docs/join/` (GitHub Pages). Die Seite zeigt den Code und öffnet die App über `barte://join/<code>`.

**Gratis-Tarif:** Supabase pausiert Gratis-Projekte nach etwa einer Woche ohne Zugriffe. Die Daten bleiben erhalten, das Projekt muss dann im Dashboard wieder gestartet werden.

### Tests

```sh
xcodebuild test -project Barte.xcodeproj -scheme Barte -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
./scripts/test-migrations.sh                         # SQL: Migrationen + RLS/RPC-Tests auf lokalem Postgres (brew install postgresql@17)
(cd supabase/functions/apple-revoke && deno test)    # Edge Function
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
    Models/       Money, Ledger (Split, Balances, Settlement), SplitGroup, ExpenseIcon, Invite, LocalDay
    Repositories/ GroupRepository (Supabase)
    Services/     Backend, AppleReauthentication, Preferences
    Demo/         DemoData, DemoGroupRepository
  Design/         Theme, GroupCard (Signature), BarteLogo, MemberAvatar
  Features/       Auth, Groups, GroupDetail (inkl. Einladen), Join, Expense, SettleUp, About
  Resources/      Assets (Farb-Tokens), AppIcon.icon, PrivacyInfo
BarteTests/       Swift-Testing-Suites für Geld, Aufteilung, Salden, Vereinfachen, Einladungen, Tage
supabase/         Migrationen, SQL-Tests, Edge Function apple-revoke
docs/             Datenschutz und Einladungsseite (GitHub Pages), App-Store-Texte, Icon-Vorschau
```

## Design

- Native Listen, Sheets und Navigationsleisten; Liquid Glass kommt vom System, eigenes Glas nur am schwebenden „Ausgabe“-Knopf
- Farben als Tokens im Asset-Katalog, die auf Systemfarben zeigen. Akzent ist Systemblau. Grün und Rot für Salden nutzen Apples Werte für „Kontrast erhöhen“ (≥ 4,5:1)
- Kartenfarben werden pro Farbe so weit abgedunkelt, dass weißer Text in Hell und Dunkel mindestens 4,5:1 erreicht
- System-Schrift, Rounded nur für große Beträge und Titel; Beträge `monospacedDigit`; Dynamic Type überall
- Easter Egg: Tippe in „Über Barte“ ein paar Mal auf das Logo. Und schreib mal „Dackel“ als Ausgabe.

## Datenmodell

- `groups`, `members` (Name, optional verknüpft mit einem Konto über `user_id`), `expenses` (Betrag in Cent, `spent_on` als Wandzeit-Tag des eintragenden iPhones, `participant_ids`)
- Lesen nur über RLS (`is_group_member`), Schreiben nur über SQL-Funktionen wie `create_group`, `join_group`, `save_expense`, `delete_my_account`
- Gerechnet wird in der App (`Ledger.swift`), damit alle Geräte dasselbe Ergebnis zeigen. Eine Android-App muss `Split.equal` genauso umsetzen: Cent-Reste zuerst an die zahlende Person, dann nach der UUID in Großbuchstaben sortiert.

## Datenschutz

Anmeldung mit Apple, Daten bei Supabase in Frankfurt, keine Werbung und kein Tracking. Eine Gruppe sehen nur ihre Mitglieder. Siehe [docs/datenschutz.md](docs/datenschutz.md).
