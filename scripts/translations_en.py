"""English strings for Barte's String Catalogs. German is the source language.

Run `python3 scripts/translations_en.py` after Xcode added new keys to a catalog: it fills in
English (and the German plural variants) for every key listed here and reports keys without English.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    ROOT / "Barte/Resources/Localizable.xcstrings",
    ROOT / "Barte/Resources/Demo.xcstrings",
    ROOT / "BarteWidgets/Localizable.xcstrings",
]

# Keys with a single number: {"one": …, "other": …} per language.
PLURALS = {
    "%lld neue Nachrichten": {
        "de": {"one": "%lld neue Nachricht", "other": "%lld neue Nachrichten"},
        "en": {"one": "%lld new message", "other": "%lld new messages"},
    },
    "%lld Personen": {
        "de": {"one": "%lld Person", "other": "%lld Personen"},
        "en": {"one": "%lld person", "other": "%lld people"},
    },
    "%lld Überweisungen": {
        "de": {"one": "%lld Überweisung", "other": "%lld Überweisungen"},
        "en": {"one": "%lld transfer", "other": "%lld transfers"},
    },
    "Mit %lld Überweisungen seid ihr quitt": {
        "de": {"one": "Mit %lld Überweisung seid ihr quitt", "other": "Mit %lld Überweisungen seid ihr quitt"},
        "en": {"one": "%lld transfer and you're all square", "other": "%lld transfers and you're all square"},
    },
    "und %lld weitere Währungen": {
        "de": {"one": "und %lld weitere Währung", "other": "und %lld weitere Währungen"},
        "en": {"one": "and %lld other currency", "other": "and %lld other currencies"},
    },
}

# Keys with a number and more arguments: (format with %#@n@, {"one": …, "other": …}) per language.
SUBSTITUTIONS = {
    "%lld Anteile, %@": {
        "de": ("%#@shares@, %2$@", {"one": "%arg Anteil", "other": "%arg Anteile"}),
        "en": ("%#@shares@, %2$@", {"one": "%arg share", "other": "%arg shares"}),
    },
    "%lld Anteile, etwa %@ pro Anteil. Ein Paar zählt zum Beispiel doppelt.": {
        "de": ("%#@shares@, etwa %2$@ pro Anteil. Ein Paar zählt zum Beispiel doppelt.", {"one": "%arg Anteil", "other": "%arg Anteile"}),
        "en": ("%#@shares@, about %2$@ per share. A couple counts double, for example.", {"one": "%arg share", "other": "%arg shares"}),
    },
}

EN = {
    # Formats that read the same
    "%@": "%@", "%@\n%@": "%1$@\n%2$@", "%@ (%@)": "%1$@ (%2$@)", "%@ · %@": "%1$@ · %2$@",
    "%@ → %@: %@": "%1$@ → %2$@: %3$@", "%lld": "%lld", "%lld×": "%lld×", "+%lld": "+%lld", "99+": "99+",
    "–": "–", "„%@“": "“%@”", "Barte": "Barte", "Chat": "Chat", "IBAN": "IBAN", "OK": "OK", "PayPal": "PayPal",
    "paypal.me/": "paypal.me/", "Indigo": "Indigo", "Orange": "Orange", "Pink": "Pink",

    # Sign-in: the German line explains the name (Bar + Karte); English gets its own pun.
    "Bar oder mit Karte? Egal, Barte rechnet.": "Cash or card? Barte does the math.",
    "Eine Karte pro Urlaub, WG oder Pizza-Abend.": "One card per trip, flat share or pizza night.",
    "Lade Freund:innen per Link ein, dann tragen alle selbst ein.": "Invite friends with a link, and everyone adds their own expenses.",
    "Barte findet die wenigsten Überweisungen, mit denen ihr quitt seid.": "Barte finds the fewest transfers to get you all square.",
    "Mit Apple anmelden": "Sign in with Apple",
    "Kostenlos und ohne Werbung. [Datenschutz](%@)": "Free and without ads. [Privacy](%@)",
    "Die Anmeldung mit Apple hat nicht geklappt. Versuch es noch einmal.": "Signing in with Apple didn't work. Please try again.",
    "Apple hat die Bestätigung nicht geliefert. Versuch es noch einmal.": "Apple didn't send the confirmation. Please try again.",

    # Groups
    "Noch keine Gruppen": "No groups yet",
    "Leg eine Gruppe an – für den Urlaub, die WG oder den Pizza-Abend. Barte rechnet aus, wer wem wie viel zahlt.":
        "Create a group for a trip, your flat share or pizza night. Barte works out who owes whom how much.",
    "Gruppe erstellen": "Create Group", "Neue Gruppe": "New Group", "Gruppe bearbeiten": "Edit Group",
    "Gruppe suchen": "Search Groups", "Gruppe öffnen": "Open Group", "Gruppe nicht gefunden": "Group not found",
    "Mit Code beitreten": "Join with Code", "Abgeschlossen": "Closed", "Abgeschlossen am %@": "Closed on %@", "am %@": "on %@",
    "Aufgeklappt": "Expanded", "Zugeklappt": "Collapsed", "Zeigt Gruppen, die erledigt sind": "Shows groups that are done",
    "Insgesamt bekommst du": "In total, you get", "Insgesamt schuldest du": "In total, you owe", "Du bist überall quitt": "You're square everywhere",
    "Noch keine Ausgaben": "No expenses yet", "Wer bist du?": "Who are you?", "Du bekommst": "You get", "Du schuldest": "You owe",
    "Du bist quitt": "You're square", "Gesamt": "Total", "geteilt": "shared",
    "Name, z. B. Skiurlaub": "Name, e.g. Ski Trip", "Name": "Name", "Währung": "Currency", "Wer ist dabei?": "Who's in?",
    "Person hinzufügen": "Add Person", "Hinzufügen": "Add", "Erstellen": "Create", "Sichern": "Save", "Abbrechen": "Cancel",
    "Fertig": "Done", "Löschen": "Delete", "Verlassen": "Leave", "Mehr": "More", "nutzt Barte": "uses Barte",
    "Freund:innen brauchen die App nicht. Lade sie später mit einem Link ein, dann tragen alle selbst Ausgaben ein.":
        "Friends don't need the app. Invite them later with a link, and everyone adds their own expenses.",
    "Wer Barte nutzt, heißt überall wie im eigenen Konto. Personen, die in Ausgaben vorkommen oder Barte nutzen, lassen sich nicht entfernen.":
        "People who use Barte have the name from their own account everywhere. People who appear in expenses or use Barte can't be removed.",
    "Nicht gesichert": "Not Saved", "Das hat nicht geklappt": "That Didn't Work", "Das hat nicht geklappt.": "That didn't work.",
    "Keine Verbindung": "No Connection", "Erneut versuchen": "Try Again",
    "Blau": "Blue", "Lila": "Purple", "Rot": "Red", "Grün": "Green", "Türkis": "Teal", "Graphit": "Graphite",

    # Group detail
    "Neue Ausgabe": "New Expense", "Ausgabe": "Expense", "Ausgleichen": "Settle Up", "Ausgleich": "Settlement",
    "Verlauf": "History", "Einladen": "Invite", "Freund:innen einladen": "Invite Friends",
    "Gruppe abschließen": "Close Group", "Abschließen": "Close", "Wieder öffnen": "Reopen",
    "Legt die Gruppe für alle unter „Abgeschlossen“ ab": "Moves the group to “Closed” for everyone",
    "Abschließen geht erst, wenn alle quitt sind.": "You can only close the group once everyone is square.",
    "Gruppe verlassen": "Leave Group", "Gruppe verlassen?": "Leave Group?",
    "Die Gruppe verschwindet bei dir. Die anderen behalten sie, dein Name bleibt in den Ausgaben stehen.":
        "The group disappears for you. The others keep it, and your name stays on the expenses.",
    "Du bist die letzte Person mit Barte in dieser Gruppe. Wenn du gehst, wird sie mit allen Ausgaben gelöscht.":
        "You're the last person using Barte in this group. If you leave, it will be deleted with all its expenses.",
    "Du kannst die Gruppe erst verlassen, wenn du quitt bist. Sonst bliebe offen, wer wem etwas schuldet.":
        "You can only leave the group once you're square. Otherwise nobody could tell who owes whom.",
    "%@ ist der Gruppe beigetreten": "%@ joined the group", "Du bist der Gruppe beigetreten": "You joined the group",
    "%@ ist beigetreten und hat „%@“ übernommen": "%@ joined and took over “%@”",
    "Du bist beigetreten und hast „%@“ übernommen": "You joined and took over “%@”",
    "%@ hat die Gruppe verlassen": "%@ left the group", "Du hast die Gruppe verlassen": "You left the group",
    "Erinnern": "Remind", "Erinnert": "Reminded", "Nicht erinnert": "Couldn't Remind",
    "%@ erinnern": "Remind %@", "%@ erinnert": "%@ reminded", "%@ eine Erinnerung schicken": "Send %@ a reminder",
    "Schickt %@ eine Mitteilung. Geht einmal am Tag.": "Sends %@ a notification. Once a day.",
    "Du hast heute schon erinnert. Morgen geht es wieder.": "You already sent a reminder today. You can send another tomorrow.",
    "Hier ist nichts mehr offen. Vielleicht hat schon jemand gezahlt?": "Nothing is open here anymore. Maybe someone already paid?",
    "Diese Person nutzt Barte nicht. Schick ihr die Erinnerung lieber als Nachricht.":
        "This person doesn't use Barte. Send them the reminder as a message instead.",
    "Hallo %@, kleine Erinnerung: Für „%@“ sind noch %@ an mich offen.": "Hi %@, just a quick reminder: you still owe me %3$@ for “%2$@”.",
    "Per PayPal: %@": "Via PayPal: %@",
    "Wiederherstellen": "Restore", "Wiederherstellen hat nicht geklappt": "Couldn't Restore",
    "Tippe auf „Ausgabe“, wenn jemand etwas für die Gruppe bezahlt hat.": "Tap “Expense” when someone paid for something for the group.",
    "Alle sind quitt": "Everyone's square", "Noch nichts auszugleichen": "Nothing to settle yet",
    "von dir · %@": "by you · %@", "von %@ · %@": "by %1$@ · %2$@", "bearbeitet": "edited",
    "du bekommst %@": "you get %@", "nur für dich": "just for you", "dein Anteil %@": "your share %@", "nicht beteiligt": "not involved",
    "Du": "You", "Unbekannt": "Unknown",

    # Expense editor
    "Wofür?": "What for?", "Betrag": "Amount", "Bezahlt von": "Paid by", "Datum": "Date", "Aufgeteilt auf": "Split between",
    "Aufteilung": "Split", "Gleich": "Equally", "Anteile": "Shares", "Beträge": "Amounts", "Alle": "All", "Keine": "None",
    "Rest": "Rest", "Rest auf %@": "Rest to %@", "Betrag für %@": "Amount for %@", "%@ (ich)": "%@ (me)",
    "Wähle mindestens eine Person aus.": "Pick at least one person.",
    "Je %@ pro Person": "%@ per person",
    "Je etwa %@ pro Person, Cent-Reste trägt die zahlende Person": "About %@ per person, the person who paid takes the leftover cents",
    "Passt genau.": "Adds up exactly.", "Noch %@ zu verteilen.": "%@ left to split.", "%@ zu viel verteilt.": "%@ too much split.",
    "Ausgabe löschen": "Delete Expense", "Ausgabe löschen?": "Delete Expense?", "Ausgleich löschen?": "Delete Settlement?",
    "%@ → %@, %@. Die Salden werden neu berechnet.": "%1$@ → %2$@, %3$@. Balances will be recalculated.",
    "Verlauf · bearbeitet": "History · edited", "Im Chat ansprechen": "Bring Up in Chat",
    "Jede Änderung bleibt für alle in der Gruppe sichtbar.": "Every change stays visible to everyone in the group.",

    # Settle up
    "Salden": "Balances", "quitt": "square", "Alle quitt!": "All square!", "Bezahlt": "Paid",
    "Als bezahlt markieren?": "Mark as Paid?", "Ja, ist bezahlt": "Yes, It's Paid", "Nicht verbucht": "Not Recorded",
    "%@ an %@ als bezahlt markieren": "Mark %1$@ to %2$@ as paid",
    "Barte hat die Schulden verrechnet: %lld statt %lld einzelner Rückzahlungen.":
        "Barte netted out the debts: %1$lld instead of %2$lld separate paybacks.",
    "Du zahlst %@": "You pay %@", "%@ zahlt dir": "%@ pays you", "%@ zahlt %@": "%1$@ pays %2$@",
    "%@ mit PayPal %@ zahlen": "Pay %1$@ %2$@ with PayPal", "Überweisen": "Bank Transfer", "Überweisung": "Bank Transfer",
    "Bankdaten von %@": "Bank details of %@", "IBAN kopieren": "Copy IBAN", "Name kopieren": "Copy Name",
    "Betrag kopieren": "Copy Amount", "Kopieren": "Copy", "Kopiert": "Copied",

    # Payment details
    "Zahlungsdaten": "Payment Details", "Zahlungsdaten hinterlegen": "Add Payment Details", "PayPal.me-Name": "PayPal.me Name",
    "deinname": "yourname", "Kontoinhaber:in": "Account Holder",
    "Wer dir etwas schuldet, öffnet PayPal mit dem Betrag schon eingetragen.": "Whoever owes you money opens PayPal with the amount already filled in.",
    "Der Name muss zum Konto passen, sonst warnt die Bank bei der Überweisung.": "The name has to match the account, or the bank will warn about the transfer.",
    "Sehen nur Personen, mit denen du in einer Gruppe bist. Barte zeigt die Daten beim Ausgleichen, wenn dir jemand Geld schuldet.":
        "Only people you share a group with can see this. Barte shows it when someone who owes you money settles up.",
    "Mit PayPal.me oder IBAN können dir die anderen direkt aus Barte zahlen.": "With PayPal.me or an IBAN, the others can pay you right from Barte.",
    "Nur Buchstaben und Zahlen, so wie hinter paypal.me/.": "Only letters and numbers, as after paypal.me/.",
    "Diese IBAN stimmt nicht. Prüf sie noch einmal.": "This IBAN isn't right. Please check it again.",

    # Invite and join
    "Link senden": "Send Link", "Link kopieren": "Copy Link", "Link prüfen": "Check Link", "Einladungscode": "Invite Code",
    "Wer den Link öffnet, meldet sich an und ist dabei. Alle tragen dann selbst Ausgaben ein.":
        "Whoever opens the link signs in and is in. Then everyone adds their own expenses.",
    "Wer den Link öffnet, wählt einen Namen aus der Gruppe (%@) und trägt dann selbst Ausgaben ein.":
        "Whoever opens the link picks a name from the group (%@) and then adds their own expenses.",
    "Komm in meine Gruppe „%@“ bei Barte, dann tragen wir alle Ausgaben gemeinsam ein. Code: %@":
        "Join my group “%1$@” on Barte so we can all add our expenses together. Code: %2$@",
    "Code, z. B. SKI2FUN7": "Code, e.g. SKI2FUN7", "Beitreten": "Join",
    "Den Code findest du in der Einladung. Ein eingefügter Link geht auch.": "You'll find the code in the invite. A pasted link works too.",
    "Das sieht nicht nach einem Einladungscode aus.": "That doesn't look like an invite code.",
    "Diese Gruppe ist bereits in deinem Stapel.": "This group is already in your stack.", "Du bist schon dabei": "You're Already In",
    "Schon mit Barte dabei": "Already using Barte", "Nicht dabei? Dein Name": "Not listed? Your name", "Nicht dabei: neu als %@": "Not listed: join as %@",
    "Hat dich jemand schon eingetragen, wähle diesen Eintrag: Die Ausgaben gehören dann zu dir, und er heißt ab jetzt wie dein Konto.":
        "If someone already added you, pick that entry: its expenses become yours, and it takes your account name from now on.",

    # Chat
    "Nachricht": "Message", "Senden": "Send", "Antworten": "Reply", "Nachricht gelöscht": "Message deleted",
    "Du hast eine Nachricht gelöscht": "You deleted a message", "%@ hat eine Nachricht gelöscht": "%@ deleted a message",
    "Wird gesendet …": "Sending …", "Nicht gesendet · Erneut senden": "Not sent · Send again", "Erneut senden": "Send Again",
    "Verwerfen": "Discard", "Melden": "Report", "Ohne Bezug": "No Reference", "Öffnet die Ausgabe": "Opens the expense",
    "Stumm": "Muted", "Stummschalten": "Mute", "Mitteilungen an": "Notifications on", "Mitteilungen einschalten": "Turn On Notifications",
    "Noch schreibt niemand mit": "Nobody's chatting yet", "die anderen": "the others",
    "Lade jemanden in „%@“ ein, dann könnt ihr hier schreiben. Neue und geänderte Ausgaben erscheinen automatisch dazwischen.":
        "Invite someone to “%@”, then you can chat here. New and changed expenses show up in between automatically.",
    "Lade %@ ein, dann könnt ihr hier schreiben und bekommt Mitteilungen. Neue und geänderte Ausgaben erscheinen automatisch dazwischen.":
        "Invite %@, then you can chat here and get notifications. New and changed expenses show up in between automatically.",
    "Hier klärt ihr, was in „%@“ offen ist. Neue, geänderte und gelöschte Ausgaben erscheinen automatisch dazwischen.":
        "Sort out what's open in “%@” here. New, changed and deleted expenses show up in between automatically.",
    "zu „%@“": "about “%@”", "Zu „%@“, %@": "About “%1$@”, %2$@",
    "Heute": "Today", "Gestern": "Yesterday",

    # History
    "Noch kein Verlauf": "No History Yet",
    "Ab jetzt steht hier, wer was eingetragen, geändert oder gelöscht hat.": "From now on, this shows who added, changed or deleted what.",
    "Diese Ausgabe wurde eingetragen, bevor es den Verlauf gab.": "This expense was added before there was a history.",
    "Jemand": "Someone", "jemanden": "someone", "Entfernte Person": "Removed person", "alle": "everyone",
    "%@ · bezahlt von %@": "%1$@ · paid by %2$@", "für %@": "for %@",
    "Du hast %@ eingetragen": "You added %@", "%@ hat %@ eingetragen": "%1$@ added %2$@",
    "Du hast %@ gelöscht": "You deleted %@", "%@ hat %@ gelöscht": "%1$@ deleted %2$@",
    "Du hast einen Ausgleich verbucht": "You recorded a settlement", "%@ hat einen Ausgleich verbucht": "%@ recorded a settlement",
    "Du hast einen Ausgleich gelöscht": "You deleted a settlement", "%@ hat einen Ausgleich gelöscht": "%@ deleted a settlement",
    "Du hast eine Ausgabe geändert": "You changed an expense", "%@ hat eine Ausgabe geändert": "%@ changed an expense",
    "Du hast %@ geändert": "You changed %@", "%@ hat %@ geändert": "%1$@ changed %2$@",
    "Du hast die Gruppe bearbeitet": "You edited the group", "%@ hat die Gruppe bearbeitet": "%@ edited the group",
    "Du hast die Gruppe abgeschlossen": "You closed the group", "%@ hat die Gruppe abgeschlossen": "%@ closed the group",
    "Du hast die Gruppe wieder geöffnet": "You reopened the group", "%@ hat die Gruppe wieder geöffnet": "%@ reopened the group",
    "Du hast %@ hinzugefügt": "You added %@", "%@ hat %@ hinzugefügt": "%1$@ added %2$@",
    "Du hast %@ in %@ umbenannt": "You renamed %1$@ to %2$@", "%@ hat %@ in %@ umbenannt": "%1$@ renamed %2$@ to %3$@",
    "Du hast %@ entfernt": "You removed %@", "%@ hat %@ entfernt": "%1$@ removed %2$@",
    "Du hast etwas geändert": "You changed something", "%@ hat etwas geändert": "%@ changed something",
    "Titel: %@ → %@": "Title: %1$@ → %2$@", "Betrag: %@ → %@": "Amount: %1$@ → %2$@", "Bezahlt von: %@ → %@": "Paid by: %1$@ → %2$@",
    "Für: %@ → %@": "For: %1$@ → %2$@", "Aufteilung: %@ → %@": "Split: %1$@ → %2$@", "Datum: %@ → %@": "Date: %1$@ → %2$@",
    "Name: %@ → %@": "Name: %1$@ → %2$@", "Währung: %@ → %@": "Currency: %1$@ → %2$@",
    "nach Anteilen": "by shares", "feste Beträge": "fixed amounts", "gleichmäßig": "equally",

    # About
    "Über Barte": "About Barte", "Ausgaben teilen, ohne Rechnerei.": "Share expenses, skip the math.",
    # The name is only explained in German; elsewhere the easter egg keeps the pun.
    "Bar + Karte = Barte. Jetzt aber zurück zum Ausgleichen!": "Cash or card, Barte does the math. Now back to settling up!",
    "Dein Name": "Your Name", "So heißt du in allen Gruppen. Änderst du ihn, ändert er sich überall.":
        "This is your name in every group. Change it, and it changes everywhere.",
    "Mit PayPal.me oder IBAN können dir andere beim Ausgleichen direkt zahlen. Mitteilungen sagen dir, wenn jemand eine Ausgabe einträgt oder dir etwas zurückzahlt.":
        "With PayPal.me or an IBAN, others can pay you directly when settling up. Notifications tell you when someone adds an expense or pays you back.",
    "Mitteilungen erlauben": "Allow Notifications", "Mitteilungen in Einstellungen erlauben": "Allow Notifications in Settings",
    "Mitteilungen sind an": "Notifications are on", "Anpassen": "Adjust",
    "So rechnet Barte": "How Barte Does the Math",
    "Jede Ausgabe wird auf die ausgewählten Personen verteilt: gleichmäßig, nach Anteilen oder mit festen Beträgen, immer auf den Cent genau.":
        "Every expense is split between the people you pick: equally, by shares or with fixed amounts, always down to the cent.",
    "Daraus ergibt sich für alle ein Saldo: Wer mehr bezahlt hat, bekommt Geld, wer weniger bezahlt hat, schuldet.":
        "That gives everyone a balance: whoever paid more gets money back, whoever paid less owes.",
    "Barte sucht dann die wenigsten Überweisungen, mit denen alle quitt sind. Statt dass jede:r jeder:m etwas zahlt, reichen oft ein, zwei Überweisungen.":
        "Barte then finds the fewest transfers that get everyone square. Instead of everyone paying everyone, one or two transfers are often enough.",
    "Konto": "Account", "Abmelden": "Sign Out", "Abmelden?": "Sign Out?", "Konto löschen": "Delete Account",
    "Konto endgültig löschen?": "Delete Account Permanently?", "Konto nicht gelöscht": "Account Not Deleted",
    "Angemeldet mit deiner Apple-ID.": "Signed in with your Apple Account.",
    "Deine Gruppen bleiben erhalten. Melde dich wieder mit deiner Apple-ID an, um sie zu sehen.":
        "Your groups stay. Sign in again with your Apple Account to see them.",
    "Du bestätigst gleich mit deiner Apple-ID. Danach wird dein Konto sofort gelöscht und Barte von deiner Apple-ID getrennt. Gruppen, in denen sonst niemand Barte nutzt, werden mitgelöscht. In geteilten Gruppen bleibt dein Name bei den Ausgaben stehen. Das lässt sich nicht rückgängig machen.":
        "You'll confirm with your Apple Account next. Your account is then deleted right away and Barte is disconnected from your Apple Account. Groups where nobody else uses Barte are deleted too. In shared groups, your name stays on the expenses. This can't be undone.",
    "Datenschutz": "Privacy", "Feedback senden": "Send Feedback",
    "Barte ist kostenlos und ohne Werbung. Deine Gruppen sehen nur die Personen, die du einlädst.\n\nVersion %@":
        "Barte is free and without ads. Only the people you invite can see your groups.\n\nVersion %@",

    # Errors
    "Du bist nicht mehr angemeldet. Bitte melde dich erneut an.": "You're no longer signed in. Please sign in again.",
    "Keine Verbindung. Prüf dein Internet und versuch es noch einmal.": "No connection. Check your internet and try again.",
    "Die Verbindung zu deiner Apple-ID konnte nicht getrennt werden. Dein Konto ist noch da. Versuch es gleich noch einmal.":
        "Barte couldn't be disconnected from your Apple Account. Your account is still there. Please try again in a moment.",
    "Diesen Einladungscode gibt es nicht. Vielleicht wurde ein neuer Link erstellt?": "This invite code doesn't exist. Maybe a new link was created?",
    "Diesen Namen hat schon jemand anderes gewählt.": "Someone else already picked this name.",
    "Diese Person kommt in Ausgaben vor und kann nicht entfernt werden.": "This person appears in expenses and can't be removed.",
    "Diese Person nutzt Barte selbst. Nur sie kann ihren Namen ändern oder die Gruppe verlassen.":
        "This person uses Barte themselves. Only they can change their name or leave the group.",
    "Du bist nicht mehr in dieser Gruppe.": "You're no longer in this group.",
    "Jemand aus dieser Ausgabe ist nicht mehr in der Gruppe.": "Someone in this expense is no longer in the group.",
    "Bitte gib einen Namen ein.": "Please enter a name.", "Die Beträge ergeben nicht die Summe der Ausgabe.": "The amounts don't add up to the expense.",
    "Das sieht nicht nach einem PayPal.me-Namen aus.": "That doesn't look like a PayPal.me name.", "Bitte prüfe die IBAN.": "Please check the IBAN.",
    "Das hat nicht geklappt. Versuch es noch einmal.": "That didn't work. Please try again.",

    # Widget
    "Saldo": "Balance", "Was du insgesamt bekommst oder schuldest.": "What you get or owe in total.",
    "Du bekommst %@": "You get %@", "Du schuldest %@": "You owe %@", "Überall quitt": "Square everywhere",
    "Niemand schuldet hier jemandem etwas.": "Nobody owes anybody anything here.",
    "Öffne Barte, um deinen Saldo hier zu sehen.": "Open Barte to see your balance here.",
    "Skiurlaub": "Ski Trip", "WG": "Flat Share", "Pizza-Abende": "Pizza Nights",

    # Demo (Demo.xcstrings): sample content for screenshots
    "Skiurlaub Saalbach": "Ski Trip Saalbach", "Tanken": "Gas", "Taxi zum Lift": "Taxi to the Lift", "Pizza": "Pizza",
    "Hüttengaudi": "Hut Party", "Abendessen Alpenrose": "Dinner Alpenrose", "Einkauf Spar": "Groceries Spar",
    "Skipässe": "Ski Passes", "Skischule Kinder": "Ski School Kids", "Chalet": "Chalet", "WG Leopoldstraße": "Flat Leopoldstraße",
    "Putzmittel dm": "Cleaning Supplies dm", "Internet": "Internet", "Strom Oktober": "Electricity October",
    "Fish & Chips": "Fish & Chips", "Tube": "Tube", "Hotel Shoreditch": "Hotel Shoreditch", "Pizzeria Da Mario": "Pizzeria Da Mario",
    "Roadtrip Kroatien": "Road Trip Croatia", "%@ Beispiel": "%@ Example", "Ich": "Me",
    "Skipässe sind gezahlt, hab sie für alle eingetragen 🎿": "Ski passes are paid, I added them for everyone 🎿",
    "Hab den Spar-Bon korrigiert, da waren 10 € Pfand dabei, die ich zurückbekommen hab.":
        "Fixed the Spar receipt, it had a €10 bottle deposit I got back.",
    "Passt, danke!": "Great, thanks!", "Wer hat noch Bargeld für die Hütte?": "Who still has cash for the hut?",
    "Ich, so 50 €": "Me, about €50", "Die Stromrechnung ist da, ich trag sie gleich ein.": "The electricity bill is here, I'll add it now.",
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural(forms):
    return {"variations": {"plural": {k: unit(v) for k, v in forms.items()}}}


def substitution(fmt, forms):
    return {
        "stringUnit": {"state": "translated", "value": fmt},
        "substitutions": {"shares": {"argNum": 1, "formatSpecifier": "lld", "variations": {"plural": {k: unit(v) for k, v in forms.items()}}}},
    }


missing = []
for path in CATALOGS:
    catalog = json.loads(path.read_text())
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        locs = entry.setdefault("localizations", {})
        if key in PLURALS:
            for lang, forms in PLURALS[key].items():
                locs[lang] = plural(forms)
        elif key in SUBSTITUTIONS:
            for lang, (fmt, forms) in SUBSTITUTIONS[key].items():
                locs[lang] = substitution(fmt, forms)
        elif key in EN:
            locs["en"] = unit(EN[key])
        else:
            missing.append(f"{path.name}: {key!r}")
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True) + "\n")

if missing:
    print("No English for:\n  " + "\n  ".join(missing))
    sys.exit(1)
print("All keys have English.")
