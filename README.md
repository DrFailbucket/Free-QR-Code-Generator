[**English**](README.md) | [Deutsch](README.de.md)

# Free QR Code Generator — Windows Desktop & Web

A free and portable QR code generator for **Windows and the web**. Create QR codes for vCards, Wi-Fi, URLs, text, email, SMS and geo data, with optional custom logos and PNG export.

The Windows desktop version is built with **PowerShell 5.1 + WPF/XAML** and supports fully local / offline QR generation. The browser version provides quick online generation through GitHub Pages.

<p align="center">
  <a href="screenshots/Screenshot1.png">
    <img src="screenshots/Screenshot1.png" width="31%">
  </a>
  &nbsp;
  <a href="screenshots/Screenshot2.png">
    <img src="screenshots/Screenshot2.png" width="31%">
  </a>
  &nbsp;
  <a href="screenshots/Screenshot3.png">
    <img src="screenshots/Screenshot3.png" width="31%">
  </a>
</p>

<p align="center">
  <i>Click a screenshot to view it in full size.</i>
</p>


<p align="center">
  <strong>🌐 Try it now directly in your browser</strong><br><br>
  <a href="https://drfailbucket.github.io/Free-QR-Code-Generator/">
    <strong>Open Web QR Generator →</strong>
  </a>
</p>

The v2 interface is a full WPF redesign of the original WinForms version. QR generation logic is separated from the UI so the application can be styled, extended and maintained without rewriting the complete frontend.

## Web Version

A browser-based version is available through GitHub Pages:

**[Open the Web QR Generator →](https://drfailbucket.github.io/Free-QR-Code-Generator/)**

The web version provides the same core QR types and a similar interface to the Windows desktop application.

It supports:

- Contact / vCard
- Website / URL
- Wi-Fi
- Plain text
- Email
- Phone
- SMS
- Geo coordinates
- Custom logo overlay
- PNG download
- vCard download
- German and English UI
- Automatic or manual online QR verification
- Unicode / charset warnings

The web version intentionally uses the fixed **QRServer / goQR.me API**. There is no custom API configuration and no API key embedded in the page.

QR contents are transmitted to QRServer when a QR code is generated. If online verification is used, the finished QR image is also uploaded to the QRServer reader service.

For sensitive data, offline environments or maximum Unicode reliability, the **Windows desktop version is recommended**. Its local QR engine can generate QR codes entirely on-device and only uses an online provider when explicitly configured or as an optional fallback.

**[Download the latest desktop release →](https://github.com/DrFailbucket/Free-QR-Code-Generator/releases/latest)**

## Features

### QR types

- Contact / vCard 3.0
- Website / URL
- Wi-Fi credentials
- Free text
- Email
- Phone number
- SMS
- Geo coordinates

### General

- Modern dark WPF interface
- German and English UI
- Automatic Windows language detection
- Live language switching without restart
- QR preview
- PNG export
- Automatic `.vcf` export for vCards
- Configurable QR size
- Configurable ECC level
- Optional centered custom logo
- Adjustable logo size from 8–20 %
- Automatic ECC `H` when a logo is used
- Portable configuration
- No installation required
- No external PowerShell modules required

### QR generation providers

- **Local / Offline QR engine**
- **QRServer / goQR.me**
- **Custom QRServer-compatible API**
- Optional online fallback if local generation fails
- Optional automatic online readability test
- Manual **QR-Code online prüfen / Verify QR online** button

## Local / Offline QR engine

v2.5 adds a built-in QR engine in:

```text
src/LocalQrEngine.cs
```

The engine is compiled locally at runtime through Windows PowerShell / .NET and does not require an additional module, package manager or external service.

The local engine supports:

- QR versions 1–40
- Error correction levels `L`, `M`, `Q`, `H`
- automatic QR version selection
- automatic mask selection
- Reed-Solomon error correction
- UTF-8 payloads
- ECI information for Unicode text
- configurable quiet zone
- local PNG generation
- existing logo overlay workflow

When local generation is used successfully, the QR payload does **not** need to be sent to an external generation service.

## Online fallback

The local engine can optionally use an online provider as a fallback.

Example:

```text
Local / Offline
      ↓
generation succeeds
      ↓
QR is created locally
```

If local generation fails and online fallback is enabled:

```text
Local / Offline
      ↓
generation fails
      ↓
configured fallback provider
      ↓
QRServer or custom compatible API
```

The application reports when an online fallback was used.

The online provider is never required for successful local QR generation unless you explicitly enable an online readability test.

## Unicode protection

Some online QR services or QR readers may interpret non-ASCII characters with a different character set.

This can affect content containing characters such as:

- `ä`
- `ö`
- `ü`
- `ß`
- accented characters
- other Unicode characters

If an online generation provider is selected and non-ASCII content is detected, v2.5 can ask whether the QR should be generated **locally first**.

Choosing local-first for that QR:

- does not permanently change the configured provider
- uses the local engine for the current QR
- keeps the configured online provider available as fallback
- improves UTF-8 reliability for Unicode content

The application can also detect known charset ambiguity during an online readability test and reports it as a warning instead of automatically treating the QR image as defective.

## QR readability test

QR verification is separate from QR generation.

You can use:

- automatic online readability testing after generation
- manual verification with the **Verify QR online** button

If a locally generated QR is successful but the online read service is unavailable, the QR generation remains successful.

Example debug result:

```text
Local engine      : SUCCESS
Read test         : UNAVAILABLE [DNS]
Generate          : Completed successfully
```

A failed optional online verification does not invalidate a QR that was already generated locally.

## Debug mode

For troubleshooting, start:

```text
Universal_QR_GUI_Debug.bat
```

The debug launcher provides detailed diagnostic output such as:

```text
Local engine      : SUCCESS | Version=20; Mask=5; Modules=97; ECC=H
Fallback          : SUCCESS via QRServer
Read test         : PASS [Exact] | Exact payload match
```

Network and provider errors are classified where possible, for example:

```text
FAILED [DNS]
FAILED [Connection]
FAILED [Timeout]
FAILED [TLS]
```

The console also provides a human-readable recommendation:

```text
What to do        : Check Internet/VPN connectivity, firewall/proxy settings and provider availability.
```

Technical exception details remain available for troubleshooting.

### Debug privacy

The debug console deliberately does **not** print the QR payload itself.

This prevents values such as:

- Wi-Fi passwords
- contact details
- private URLs
- internal text

from appearing directly in the debug log.

## Project structure

```text
Free-QR-Code-Generator/
├── src/
│   ├── Universal_QR_GUI.ps1
│   ├── MainWindow.xaml
│   ├── QRCore.ps1
│   └── LocalQrEngine.cs
│
├── assets/
│   └── Universal_QR_GUI.ico
│
├── locales/
│   ├── de.json
│   └── en.json
│
├── config/
│   ├── settings.example.json
│   └── settings.json          # created locally, ignored by Git
│
├── screenshots/
│
├── docs/                      # GitHub Pages web version
│   ├── index.html
│   ├── css/
│   ├── js/
│   └── assets/
│
├── output/                    # default QR destination
├── temp/                      # temporary runtime files
│
├── Universal_QR_GUI_Starten.vbs
├── Universal_QR_GUI_Debug.bat
├── README.md
├── README.de.md
├── LICENSE
└── .gitignore
```

## Start

Recommended:

```text
Universal_QR_GUI_Starten.vbs
```

This starts the application without a visible PowerShell console.

For troubleshooting:

```text
Universal_QR_GUI_Debug.bat
```

The debug launcher keeps the PowerShell console visible and enables additional diagnostic output.

## Requirements

- Windows 10 / 11
- Windows PowerShell 5.1 or newer
- WPF / .NET Framework available

No external PowerShell modules are required.

### Internet connection

An Internet connection is **not required for local QR generation**.

Internet access is only required when using:

- QRServer / goQR.me generation
- a custom online QR API
- online fallback
- automatic online readability testing
- manual online QR verification

## Portable operation

The application is designed to be portable and can be copied to another folder or USB drive.

Application data is stored inside the project directory instead of `%APPDATA%`.

Default local folders:

```text
config/
output/
temp/
```

Settings are stored in:

```text
config/settings.json
```

Paths inside the project can be stored relatively so moving the application to another drive does not break the configuration.

Generated output and runtime settings are ignored by Git by default.

## Language

Included languages:

- Deutsch
- English
- Automatic / Windows language detection

Locale files:

```text
locales/de.json
locales/en.json
```

The localization system is designed so additional languages can be added without maintaining a separate XAML interface for every language.

## Logo

No logo is shipped with the project.

Use the logo selector in the application to choose your own:

- PNG
- JPG / JPEG
- BMP

Recommended:

- transparent PNG
- logo size around `16 %`
- error correction `H`

When a logo is enabled, the application automatically uses ECC `H` during generation.

## QR providers

### Local / Offline

Recommended for:

- sensitive data
- Wi-Fi credentials
- vCards
- Unicode content
- offline environments
- portable USB operation

No QR payload needs to leave the computer during generation.

### QRServer / goQR.me

Built-in compatible endpoints:

```text
https://api.qrserver.com/v1/create-qr-code/
```

Read API:

```text
https://api.qrserver.com/v1/read-qr-code/
```

### Custom API

A custom provider can be configured if it uses the same basic HTTP contract as QRServer.

Create endpoint:

- `POST`
- `application/x-www-form-urlencoded`
- compatible fields such as `data`, `size`, `ecc`, `color`, `bgcolor`, `qzone`, `format`

Read endpoint:

- `POST`
- `multipart/form-data`
- image field `file`
- `outputformat=json`
- QRServer-compatible JSON response

An API using a different schema, authentication mechanism or response format needs a provider adapter in `QRCore.ps1`.

## Privacy

### Local generation

When using the local engine without an online read test:

```text
QR payload → local QR engine → PNG
```

The QR content does not need to be sent to an external QR generation service.

### Online generation / fallback

When QRServer, a custom online provider or online fallback is used, the QR payload is transmitted to the configured service.

### Online readability test

When automatic or manual online verification is used, the generated QR image is uploaded to the configured read service.

This is important for sensitive payloads such as:

- Wi-Fi passwords
- personal contact data
- private URLs
- internal notes

The GUI indicates when an online service is used or when an online verification cannot be completed.

## Recommended print settings

- Size: `1000 × 1000 px`
- ECC: `H` with logo
- Logo: around `16 %`
- Quiet zone: `4` modules
- Always test a printed QR code with multiple phones before a large print run

## License

This project is licensed under the MIT License.

See the [LICENSE](LICENSE) file for details.

---

# Version history

## v2.5 — Local / Offline QR engine

- Added built-in local QR generation engine.
- Added `src/LocalQrEngine.cs`.
- Local generation no longer requires an online QR generation provider.
- Supports QR versions 1–40.
- Supports ECC `L`, `M`, `Q`, `H`.
- Added UTF-8 / ECI handling for Unicode content.
- Added automatic mask selection.
- Added optional online fallback when local generation fails.
- QRServer and custom compatible APIs remain available as direct providers.
- Added manual online QR readability testing.
- Automatic online readability testing is now independent from successful local generation.
- A failed optional online read test no longer invalidates an already generated local QR.
- Added Unicode guard for online generation.
- Unicode guard can temporarily use local-first generation without changing the saved provider setting.
- Added charset ambiguity detection for known online-reader encoding mismatches.
- Added detailed debug diagnostics.
- Added network error classification for DNS, connection, timeout, TLS and provider problems.
- Debug output avoids logging QR payload contents.
- Improved user-facing error messages with separate problem, recommendation and technical details.
- Prevented manual verification of an outdated QR after a failed new generation attempt.
- Improved status reporting for local generation, online fallback and verification.

## v2.4 — Portable configuration & languages

- Added German and English UI.
- Language options: `Automatic (Windows)`, `Deutsch`, `English`.
- Language changes are applied live without restarting the application.
- Locale files are stored in `locales/de.json` and `locales/en.json`.
- Future translations can be added without duplicating the UI.
- Removed `%APPDATA%` configuration storage.
- Settings are now stored locally in `config/settings.json`.
- Default output is the portable `output/` directory.
- Paths inside the project are stored relatively, so moving the folder or USB drive does not break them.
- Temporary logo/read-test images use the local `temp/` folder rather than Windows `%TEMP%`.
- `config/settings.json`, generated output and temporary files are excluded from Git by default.

## v2.3.3 hotfix

- Fixed `ArgumentNullException` / `Der Schlüssel darf nicht NULL sein` when refreshing the QR preview.
- The error occurred during `BitmapImage.EndInit()` after generating a QR code.
- Removed `BitmapCreateOptions.IgnoreImageCache` from stream-based image loading.
- QR previews still bypass stale file-URI caching because every preview is loaded from fresh file bytes into a new memory stream.

## v2.3.2 hotfix

- Settings content can be scrolled again with mouse wheel / touchpad.
- The settings scrollbar stays visually hidden to keep the clean UI.
- Settings buttons now use the same rounded WPF style as the main application.
- Added hover, pressed and disabled visual states to settings buttons.

## v2.3.1 hotfix

- Fixed a WPF XAML crash when opening the settings dialog.
- The cause was an invalid `Margin="0,0,auto,0"` value.
- Replaced the settings action row with a proper three-column Grid.
- Added defensive error handling around dynamic settings-XAML loading.
- Added package-time validation for invalid `Margin` and `Padding` values.

## v2.3

- Navigation buttons now use a dedicated left-aligned WPF template.
- Icons and labels have fixed columns and no longer appear centered inside the sidebar.
- Visible scrollbars are hidden in the main UI; mouse-wheel and touchpad scrolling remain available.
- Settings window redesigned into three clean cards without a visible scrollbar.
- Added `Standardwerte` reset button.
- Added editable API endpoints.
- Added QRServer / goQR.me and QRServer-compatible custom provider options.

## v2.2

- Added a dedicated settings dialog.
- Default output directory can be selected and remembered.
- Default QR size can be configured globally.
- Default ECC can be configured globally.
- Automatic readability testing can be enabled / disabled globally.
- Optional automatic opening of the generated QR image.
- Added provider configuration and provider abstraction.
- Simplified the footer and settings summary.

## v2.1 fixes

- Reworked the left QR-type navigation with fixed-width Segoe MDL2 glyphs.
- Fixed clipped / uneven navigation icons.
- Fixed unreadable selected values in WPF ComboBoxes on some Windows themes.
- Fixed QR preview caching when overwriting the same PNG file repeatedly.
- QR preview images are loaded from fresh file bytes instead of a cached file URI.
