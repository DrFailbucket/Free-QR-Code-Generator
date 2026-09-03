(() => {
  const de = {
    "header.title":"Universal QR-Code Generator",
    "header.subtitle":"QR-Codes schnell, einfach und professionell erstellen.",
    "header.new":"＋ Neu","header.settings":"⚙ Einstellungen","header.info":"ⓘ Info",
    "sidebar.heading":"QR-CODE TYP",
    "nav.vcard":"Kontakt / vCard","nav.url":"Website / URL","nav.wifi":"WLAN","nav.text":"Freier Text",
    "nav.email":"E-Mail","nav.phone":"Telefonnummer","nav.sms":"SMS","nav.geo":"Standort / Geo",
    "privacy.onlineBadge":"Online-Erzeugung",
    "privacy.onlineShort":"QR-Inhalte werden erst beim Klick auf „QR erstellen“ an QRServer übertragen.",
    "preview.title":"QR-Code Vorschau","preview.empty":"Noch kein QR-Code erstellt","preview.useLogo":"Logo verwenden","preview.logoSize":"Logo-Größe",
    "logo.chooseLabel":"Logo-Datei","logo.none":"Kein Logo ausgewählt",
    "summary.title":"Aktuelle Einstellungen","summary.size":"PNG-Größe","summary.ecc":"Fehlerkorrektur","summary.readtest":"Lesetest","summary.provider":"QR-Dienst","summary.openSettings":"⚙ Einstellungen öffnen",
    "action.generate":"▦ QR ERSTELLEN","action.download":"⬇ PNG herunterladen","action.verify":"✓ QR online prüfen","action.vcf":"⬇ vCard herunterladen",
    "status.ready":"Bereit","status.preparing":"QR-Inhalt wird vorbereitet …","status.generating":"QR-Code wird über QRServer erzeugt …","status.logo":"Logo wird eingesetzt …",
    "status.testing":"QR-Code wird online geprüft …","status.success":"QR-Code erfolgreich erstellt","status.verified":"QR-Code erstellt und exakt verifiziert",
    "status.warnCharset":"QR erstellt – Online-Reader interpretiert Sonderzeichen anders","status.testUnavailable":"QR erstellt – Online-Prüfung nicht verfügbar",
    "status.error":"Fehler","status.changed":"Eingabe geändert – QR-Code bitte neu erstellen","common.on":"An","common.off":"Aus","common.cancel":"Abbrechen","common.continue":"Trotzdem fortfahren","common.close":"Schließen","common.save":"Speichern",
    "mode.vcard.title":"Kontakt / vCard","mode.vcard.subtitle":"Erstelle einen QR-Code mit deinen Kontaktdaten (vCard 3.0).",
    "mode.url.title":"Website / URL","mode.url.subtitle":"Verlinke direkt auf eine Website oder beliebige URL.",
    "mode.wifi.title":"WLAN","mode.wifi.subtitle":"Erstelle einen QR-Code für einen WLAN-Zugang.",
    "mode.text.title":"Freier Text","mode.text.subtitle":"Speichere beliebigen Text direkt im QR-Code.",
    "mode.email.title":"E-Mail","mode.email.subtitle":"Öffne beim Scannen eine neue, optional vorausgefüllte E-Mail.",
    "mode.phone.title":"Telefonnummer","mode.phone.subtitle":"Starte über den QR-Code direkt einen Telefonanruf.",
    "mode.sms.title":"SMS","mode.sms.subtitle":"Öffne eine SMS mit Nummer und optional vorausgefülltem Text.",
    "mode.geo.title":"Standort / Geo","mode.geo.subtitle":"Speichere Breiten- und Längengrad als Geo-QR-Code.",
    "vcard.contact":"Kontaktdaten","vcard.first":"Vorname","vcard.last":"Nachname","vcard.company":"Firma / Organisation","vcard.title":"Position / Tätigkeit",
    "vcard.mobile":"Mobilnummer","vcard.phone":"Weitere Telefonnummer","vcard.email":"E-Mail","vcard.website":"Website","vcard.address":"Adresse (optional)",
    "vcard.street":"Straße / Hausnummer","vcard.zip":"PLZ","vcard.city":"Ort","vcard.region":"Bundesland / Region","vcard.country":"Land","vcard.note":"Notiz / Zusatzinfo (optional)",
    "url.target":"Zieladresse","wifi.ssid":"WLAN-Name / SSID","wifi.password":"Passwort","wifi.encryption":"Verschlüsselung","wifi.wpa":"WPA / WPA2 / WPA3","wifi.wep":"WEP","wifi.open":"Offen","wifi.hidden":"Versteckte SSID",
    "wifi.notice":"Datenschutz: SSID und Passwort werden erst beim Erzeugen an QRServer übertragen.",
    "text.value":"Text","email.to":"Empfänger","email.subject":"Betreff (optional)","email.body":"Nachricht (optional)",
    "phone.number":"Telefonnummer, idealerweise international (+49 …)","sms.number":"Telefonnummer","sms.message":"Vorgefertigte Nachricht (optional)",
    "geo.lat":"Breitengrad / Latitude","geo.lon":"Längengrad / Longitude",
    "settings.title":"Einstellungen","settings.language":"Sprache","settings.auto":"Automatisch (Browser)","settings.de":"Deutsch","settings.en":"English",
    "settings.size":"Standardgröße","settings.ecc":"Fehlerkorrektur (ECC)","settings.autoread":"Nach Erstellung automatisch online prüfen",
    "settings.note":"Einstellungen werden nur lokal im Browser gespeichert. QR-Inhalte und Passwörter werden nicht gespeichert.",
    "info.title":"Über die Web-Version",
    "info.body":"Diese GitHub-Pages-Version erzeugt QR-Codes ausschließlich über die feste QRServer/goQR.me-API. Es gibt keine Custom-API und keinen API-Schlüssel im Quellcode. Das Logo wird lokal im Browser in das erzeugte PNG eingesetzt. Eine Online-Prüfung ist optional und lädt das fertige QR-Bild an den QRServer-Lesedienst hoch.",
    "unicode.title":"Sonderzeichen erkannt",
    "unicode.body":"Der QR-Inhalt enthält Umlaute oder andere Unicode-Zeichen. Manche Online-QR-Reader können den Zeichensatz unterschiedlich interpretieren. Die Web-Version verwendet ausschließlich QRServer. Der QR kann trotzdem korrekt funktionieren, sollte aber mit dem Zielgerät getestet werden. Für maximale Unicode-Zuverlässigkeit empfiehlt sich die Desktop-Version: Dort erzeugt die lokale QR-Engine den Code vollständig auf dem Gerät und verwendet die Online-API nur optional als Fallback.",
    "verify.title":"Online-Prüfung",
    "verify.exact":"Der QR-Code wurde erfolgreich gelesen. Der zurückgelesene Inhalt stimmt exakt überein.",
    "verify.charset":"Der QR-Code wurde gelesen, aber der Online-Reader hat Unicode-Zeichen offenbar mit einem anderen Zeichensatz interpretiert. Der QR ist dadurch nicht automatisch defekt. Bitte zusätzlich mit dem Zielgerät prüfen.",
    "verify.mismatch":"Der QR-Code wurde gelesen, aber der zurückgelesene Inhalt weicht vom erzeugten Inhalt ab. Bitte mit einem Smartphone oder Zielscanner prüfen.",
    "verify.failed":"Der Online-Lesedienst konnte den QR-Code nicht decodieren.",
    "error.required":"Bitte die erforderlichen Felder ausfüllen.",
    "error.logo":"Das Logo konnte nicht verarbeitet werden. Bitte PNG, JPG oder BMP verwenden.",
    "error.api":"QRServer konnte den QR-Code nicht erzeugen.",
    "error.network":"Der Online-Dienst konnte nicht erreicht werden. Prüfe Internet/VPN, Firewall und ob api.qrserver.com erreichbar ist. Browser melden CORS- und Netzwerkfehler aus Sicherheitsgründen oft identisch.",
    "error.http":"Der Online-Dienst hat mit HTTP {status} geantwortet.",
    "error.timeout":"Die Anfrage an den Online-Dienst hat zu lange gedauert.",
    "error.read":"Der Online-Lesetest konnte nicht durchgeführt werden.",
    "filename.website":"Website_QR","filename.text":"Text_QR","filename.email":"Email_QR","filename.phone":"Telefon_QR","filename.sms":"SMS_QR","filename.geo":"Standort_QR"
  };
  const en = {
    "header.title":"Universal QR-Code Generator",
    "header.subtitle":"Create QR codes quickly, easily and professionally.",
    "header.new":"＋ New","header.settings":"⚙ Settings","header.info":"ⓘ Info",
    "sidebar.heading":"QR CODE TYPE",
    "nav.vcard":"Contact / vCard","nav.url":"Website / URL","nav.wifi":"Wi-Fi","nav.text":"Plain text",
    "nav.email":"Email","nav.phone":"Phone number","nav.sms":"SMS","nav.geo":"Location / Geo",
    "privacy.onlineBadge":"Online generation",
    "privacy.onlineShort":"QR contents are sent to QRServer only after you click “Create QR”.",
    "preview.title":"QR Code Preview","preview.empty":"No QR code created yet","preview.useLogo":"Use logo","preview.logoSize":"Logo size",
    "logo.chooseLabel":"Logo file","logo.none":"No logo selected",
    "summary.title":"Current settings","summary.size":"PNG size","summary.ecc":"Error correction","summary.readtest":"Read test","summary.provider":"QR service","summary.openSettings":"⚙ Open settings",
    "action.generate":"▦ CREATE QR","action.download":"⬇ Download PNG","action.verify":"✓ Verify QR online","action.vcf":"⬇ Download vCard",
    "status.ready":"Ready","status.preparing":"Preparing QR content …","status.generating":"Generating QR via QRServer …","status.logo":"Applying logo …",
    "status.testing":"Verifying QR online …","status.success":"QR code created successfully","status.verified":"QR created and verified exactly",
    "status.warnCharset":"QR created – online reader interpreted special characters differently","status.testUnavailable":"QR created – online verification unavailable",
    "status.error":"Error","status.changed":"Input changed – please create the QR code again","common.on":"On","common.off":"Off","common.cancel":"Cancel","common.continue":"Continue anyway","common.close":"Close","common.save":"Save",
    "mode.vcard.title":"Contact / vCard","mode.vcard.subtitle":"Create a QR code containing contact details (vCard 3.0).",
    "mode.url.title":"Website / URL","mode.url.subtitle":"Link directly to a website or any URL.",
    "mode.wifi.title":"Wi-Fi","mode.wifi.subtitle":"Create a QR code for Wi-Fi access.",
    "mode.text.title":"Plain text","mode.text.subtitle":"Store arbitrary text directly in the QR code.",
    "mode.email.title":"Email","mode.email.subtitle":"Open a new, optionally pre-filled email when scanned.",
    "mode.phone.title":"Phone number","mode.phone.subtitle":"Start a phone call directly from the QR code.",
    "mode.sms.title":"SMS","mode.sms.subtitle":"Open an SMS with number and optional pre-filled text.",
    "mode.geo.title":"Location / Geo","mode.geo.subtitle":"Store latitude and longitude as a geo QR code.",
    "vcard.contact":"Contact details","vcard.first":"First name","vcard.last":"Last name","vcard.company":"Company / Organization","vcard.title":"Position / Title",
    "vcard.mobile":"Mobile number","vcard.phone":"Additional phone number","vcard.email":"Email","vcard.website":"Website","vcard.address":"Address (optional)",
    "vcard.street":"Street / Number","vcard.zip":"Postal code","vcard.city":"City","vcard.region":"State / Region","vcard.country":"Country","vcard.note":"Note / Additional info (optional)",
    "url.target":"Target URL","wifi.ssid":"Wi-Fi name / SSID","wifi.password":"Password","wifi.encryption":"Encryption","wifi.wpa":"WPA / WPA2 / WPA3","wifi.wep":"WEP","wifi.open":"Open","wifi.hidden":"Hidden SSID",
    "wifi.notice":"Privacy: SSID and password are sent to QRServer only when generating the QR code.",
    "text.value":"Text","email.to":"Recipient","email.subject":"Subject (optional)","email.body":"Message (optional)",
    "phone.number":"Phone number, preferably international (+49 …)","sms.number":"Phone number","sms.message":"Pre-filled message (optional)",
    "geo.lat":"Latitude","geo.lon":"Longitude",
    "settings.title":"Settings","settings.language":"Language","settings.auto":"Automatic (browser)","settings.de":"Deutsch","settings.en":"English",
    "settings.size":"Default size","settings.ecc":"Error correction (ECC)","settings.autoread":"Automatically verify online after generation",
    "settings.note":"Settings are stored only in your browser. QR contents and passwords are not stored.",
    "info.title":"About the web version",
    "info.body":"This GitHub Pages version generates QR codes exclusively through the fixed QRServer/goQR.me API. There is no custom API and no API key in the source. Logos are composited locally in your browser. Online verification is optional and uploads the final QR image to the QRServer reader service.",
    "unicode.title":"Special characters detected",
    "unicode.body":"The QR content contains umlauts or other Unicode characters. Some online QR readers may interpret the character set differently. This web version uses QRServer only. The QR may still work correctly, but should be tested with the intended device. For maximum Unicode reliability, the desktop version is recommended: its local QR engine generates the code entirely on-device and uses the online API only as an optional fallback.",
    "verify.title":"Online verification",
    "verify.exact":"The QR code was read successfully and the returned content matches exactly.",
    "verify.charset":"The QR code was read, but the online reader appears to have interpreted Unicode characters using a different character set. This does not automatically mean the QR is defective. Please also test with the intended device.",
    "verify.mismatch":"The QR code was read, but the returned content differs from the generated content. Please verify with a phone or target scanner.",
    "verify.failed":"The online reader could not decode the QR code.",
    "error.required":"Please fill in the required fields.",
    "error.logo":"The logo could not be processed. Please use PNG, JPG or BMP.",
    "error.api":"QRServer could not generate the QR code.",
    "error.network":"The online service could not be reached. Check Internet/VPN, firewall and whether api.qrserver.com is reachable. Browsers often report CORS and network failures identically for security reasons.",
    "error.http":"The online service returned HTTP {status}.",
    "error.timeout":"The online request timed out.",
    "error.read":"The online read test could not be completed.",
    "filename.website":"Website_QR","filename.text":"Text_QR","filename.email":"Email_QR","filename.phone":"Phone_QR","filename.sms":"SMS_QR","filename.geo":"Location_QR"
  };

  window.I18N = {
    dictionaries:{de,en},
    detect(){
      const stored = localStorage.getItem("qrweb.language") || "auto";
      if(stored === "de" || stored === "en") return stored;
      return (navigator.language || "en").toLowerCase().startsWith("de") ? "de" : "en";
    },
    current:"de",
    set(lang){
      this.current = lang === "de" ? "de" : "en";
      document.documentElement.lang = this.current;
      document.querySelectorAll("[data-i18n]").forEach(el => {
        const key = el.dataset.i18n;
        if(this.dictionaries[this.current][key]) el.textContent = this.dictionaries[this.current][key];
      });
    },
    t(key, tokens={}){
      let value = this.dictionaries[this.current][key] || key;
      for(const [k,v] of Object.entries(tokens)) value = value.replaceAll(`{${k}}`, String(v));
      return value;
    }
  };
})();
