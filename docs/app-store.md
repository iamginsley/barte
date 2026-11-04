# App Store: Barte

## Texte

**Name:** Barte
**Untertitel (30):** Ausgaben teilen, ganz einfach
**Kategorie:** Finanzen (sekundär: Reisen)
**Preis:** kostenlos, keine In-App-Käufe

**Werbetext (170):**
Urlaub, WG oder Pizza-Abend: Trag ein, wer was bezahlt hat. Barte rechnet aus, wie ihr mit den wenigsten Überweisungen quitt seid.

**Beschreibung:**
Barte teilt Ausgaben in Gruppen, ohne Konto, ohne Werbung, kostenlos.

• Gruppen als Karten: für jeden Urlaub, jede WG und jeden Abend eine eigene Karte
• Schnell eingetragen: Betrag, wofür, wer bezahlt hat und für wen
• Smartes Ausgleichen: Barte verrechnet alle Schulden und zeigt die wenigsten Überweisungen, mit denen alle quitt sind
• Gemeinsam: Teile eine Gruppe über iCloud, dann können alle selbst Ausgaben eintragen
• Freund:innen ohne iPhone sind trotzdem dabei, als Name in der Gruppe
• Eine Währung pro Gruppe, auf den Cent genau
• Privat: Deine Daten liegen in deiner iCloud, nicht bei uns

**Schlüsselwörter (100):** splitten,ausgaben,teilen,gruppe,urlaub,wg,schulden,abrechnung,freunde,reise,kosten,quitt

**Support-URL:** https://github.com/iamginsley/barte
**Datenschutz-URL:** https://iamginsley.github.io/barte/datenschutz

## Datenschutz-Etiketten

**Keine Daten erfasst.** Barte hat keinen Server; alles liegt in der iCloud der Nutzer:innen (CloudKit), und der Entwickler hat keinen Zugriff darauf. Nach Apples Definition gilt das nicht als Erfassung.

## Prüfhinweise

> Barte braucht kein Konto. Zum Ausprobieren: „+“ → Gruppe mit zwei Namen anlegen → „Ausgabe“ → „Ausgleichen“. Teilen nutzt den iCloud-Teilen-Dialog von Apple und funktioniert, wenn auf dem Gerät eine Apple-ID mit iCloud angemeldet ist.

## Checkliste

- [ ] Build-Nummer in `project.yml` hochzählen, `xcodegen generate`
- [ ] CloudKit-Schema nach Production übernommen (CloudKit Dashboard → Deploy Schema Changes)
- [ ] `aps-environment` wird beim Archivieren automatisch zu `production`
- [ ] Teilen mit zwei echten iPhones und zwei Apple-IDs getestet
- [ ] TestFlight-Build mit Freund:innen getestet
- [ ] GitHub Pages aktiv (Settings → Pages → `main` / `docs`), Datenschutz-URL erreichbar
- [ ] Screenshots ohne Alpha in 1206 × 2622 (Demo-Modus: `-BarteDemo`, `-BarteGroup 0`, `-BarteSheet settle|expense`)
- [ ] Texte und Datenschutz-Etiketten in App Store Connect eingetragen
