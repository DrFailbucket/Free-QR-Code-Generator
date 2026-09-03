# GitHub Pages Web v1 — Testhinweise

## Ziel

Diese erste Web-Version nutzt **ausschließlich QRServer / goQR.me**.

- keine Custom-API
- kein API-Key
- keine externe JS-Bibliothek
- Logo-Overlay lokal im Browser
- optionale Online-Prüfung über QRServer
- QR-Inhalte werden nicht in Console/Debug-Ausgaben geschrieben

## Lokaler Test

Für einen realistischen Browser-Test sollte die Seite über HTTP statt direkt über `file://` geöffnet werden.

Einfachste Varianten:

- VS Code + Erweiterung **Live Server**
- Python, falls installiert:

```powershell
cd docs
python -m http.server 8000
```

Danach:

```text
http://localhost:8000
```

## Testreihenfolge

1. URL ohne Sonderzeichen erzeugen
2. PNG herunterladen und mit Smartphone scannen
3. Logo aktivieren und erneut erzeugen
4. vCard erzeugen + `.vcf` herunterladen
5. WLAN testen
6. Umlaut / `ß` testen und Unicode-Warnung prüfen
7. manuellen Online-Lesetest ausführen
8. automatischen Lesetest in Einstellungen an/aus schalten
9. Internet kurz deaktivieren und verständliche Fehlermeldung prüfen

## CORS

GitHub Pages hat kein Backend. Deshalb müssen Browserzugriffe auf QRServer von dessen CORS-Konfiguration erlaubt werden.

Die App erkennt Browser-Netzwerk/CORS-Fehler und zeigt eine verständliche Meldung. Browser geben aus Sicherheitsgründen häufig nicht preis, ob die Ursache DNS, TLS, Firewall oder CORS war.

Wenn **Erzeugung**, **Canvas/Logo** oder **Read API** im Browser an CORS scheitern, muss dieser Teil separat angepasst werden. Es wird bewusst kein offener CORS-Proxy verwendet, da dadurch QR-Inhalte über einen weiteren Drittanbieter laufen würden.


## RC-Polish

Vor dem ersten GitHub-Pages-Test wurden zusätzlich eingebaut:

- Formulardaten bleiben bei Sprach- und Einstellungswechsel erhalten.
- Formulardaten werden ausschließlich im Arbeitsspeicher gehalten und nicht in `localStorage` gespeichert.
- Ändert man Eingabedaten nach einer erfolgreichen Erzeugung, wird der alte QR nicht länger als aktuelles Ergebnis behandelt.
- Dasselbe gilt bei Änderung von Logo, Logo-Größe, PNG-Größe oder ECC.
- Der `Neu`-Button leert bewusst nur das aktuell geöffnete Formular.
- Der Unicode-Hinweis verweist deutlicher auf die lokale Desktop-Engine.
