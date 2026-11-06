# App Store: Barte

## App Store Connect

In App Store Connect angelegt am 5. November 2026.

| Feld | Wert |
| --- | --- |
| Apple-ID der App | 6831268880 |
| Bundle-ID | com.iamginsley.barte |
| SKU | barte-ios |
| Primäre Sprache | Deutsch |
| Link | https://appstoreconnect.apple.com/apps/6831268880 |

## Texte

**Name:** Barte
**Untertitel (30):** Ausgaben teilen, ganz einfach
**Kategorie:** Finanzen (sekundär: Reisen)
**Preis:** kostenlos, keine In-App-Käufe

**Werbetext (170):**
Urlaub, WG oder Pizza-Abend: Trag ein, wer was bezahlt hat. Barte rechnet aus, wie ihr mit den wenigsten Überweisungen quitt seid.

**Beschreibung:**
Barte teilt Ausgaben in Gruppen, ohne Werbung, kostenlos.

• Gruppen als Karten: für jeden Urlaub, jede WG und jeden Abend eine eigene Karte
• Schnell eingetragen: Betrag, wofür, wer bezahlt hat und für wen
• Fair aufgeteilt: gleichmäßig, nach Anteilen (das Paar zählt doppelt) oder mit festen Beträgen
• Smartes Ausgleichen: Barte verrechnet alle Schulden und zeigt die wenigsten Überweisungen, mit denen alle quitt sind
• Direkt zurückzahlen: per PayPal-Link mit eingetragenem Betrag oder mit kopierter IBAN
• Gemeinsam: Lade Freund:innen per Link oder Code ein, dann tragen alle selbst Ausgaben ein
• Wer die App nicht hat, ist trotzdem dabei, als Name in der Gruppe
• Mitteilungen, wenn jemand etwas einträgt, und ein Widget, das zeigt, was du bekommst oder schuldest
• Eine Währung pro Gruppe, auf den Cent genau
• Privat: Anmeldung mit Apple, keine Werbung, kein Tracking

**Schlüsselwörter (100):** splitten,ausgaben,teilen,gruppe,urlaub,wg,schulden,abrechnung,freunde,reise,kosten,quitt

**Support-URL:** https://github.com/iamginsley/barte
**Datenschutz-URL:** https://iamginsley.github.io/barte/datenschutz
**Copyright:** 2026 Dominik Gintsberger

„Anmeldung erforderlich“ bei den Prüfhinweisen bleibt aus: Die Prüfer:innen melden sich mit ihrer eigenen Apple-ID an.

## Datenschutz-Etiketten

Frage „Erfasst die App Daten?“ → **Ja**. Für alle Datentypen gilt: **mit der Identität verknüpft: ja**, **für Tracking verwendet: nein**, **Zweck: App-Funktionalität**.

| Kategorie in App Store Connect | Datentyp |
| --- | --- |
| Kontaktinformationen | Name (Namen in Gruppen), E-Mail-Adresse (von „Mit Apple anmelden“) |
| Finanzinformationen | Zahlungsinformationen (freiwillig: PayPal.me-Name, IBAN und Kontoinhaber:in, damit andere zurückzahlen können), Andere Finanzinformationen (Beträge der Ausgaben und Ausgleiche) |
| Benutzerinhalte | Andere Benutzerinhalte (Gruppen- und Ausgabentitel) |
| Kennungen | Benutzer-ID |

Der Push-Token des Geräts wird nur für Mitteilungen gespeichert und ist keine Werbe-ID. Nicht erfasst: Standort, Kontakte, Nutzungsdaten, Diagnosedaten, Geräte-ID für Werbung. Das deckt sich mit `Barte/Resources/PrivacyInfo.xcprivacy`.

## Prüfhinweise

> Anmeldung nur mit „Mit Apple anmelden“. Zum Ausprobieren: „+“ → „Neue Gruppe“ → Gruppe mit zwei Namen anlegen → „Ausgabe“ → „Ausgleichen“. Einladen: in einer Gruppe oben auf das Personen-Symbol, dann den Link oder Code teilen; ein zweites Gerät tritt über „+“ → „Mit Code beitreten“ bei. Ausgaben lassen sich gleichmäßig, nach Anteilen oder mit festen Beträgen aufteilen. PayPal.me und IBAN sind freiwillig („Über Barte“ → „Zahlungsdaten“) und erscheinen beim Ausgleichen nur für Personen aus derselben Gruppe. Konto löschen: „Über Barte“ (i-Symbol) → „Konto löschen“.

## Checkliste

- [x] App in App Store Connect angelegt (Name, Bundle-ID, SKU)
- [ ] Build-Nummer in `project.yml` hochzählen, `xcodegen generate`
- [ ] Supabase: Migrationen eingespielt, `apple-revoke` und `notify-group` deployt, Apple- und APNs-Secrets gesetzt (siehe README)
- [ ] Mitteilungen mit zwei iPhones getestet (Ausgabe eintragen, Ausgleich verbuchen, Tipp öffnet die Gruppe)
- [ ] Widget auf dem Homescreen geprüft (klein und mittel, Hell und Dunkel)
- [ ] Einladen und Beitreten mit zwei echten iPhones und zwei Apple-IDs getestet
- [ ] Konto löschen getestet (Apple-ID → Mit Apple anmelden: Barte ist danach verschwunden)
- [ ] TestFlight-Build mit Freund:innen getestet
- [ ] GitHub Pages aktiv (Settings → Pages → `main` / `docs`), Datenschutz-URL erreichbar
- [ ] Screenshots ohne Alpha in 1206 × 2622 (Demo-Modus: `-BarteDemo`, `-BarteGroup 0`, `-BarteSheet settle|expense|invite|join`)
- [x] Texte, Preis und Datenschutz-Etiketten in App Store Connect eingetragen und veröffentlicht
- [ ] Inhaltsrechte („Nein“), Altersfreigabe, Verfügbarkeit und Kontakt für die Prüfung eingetragen
