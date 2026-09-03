# Universal QR-Code Generator — WPF v2.3.2

A lightweight Windows desktop GUI for creating QR codes with **PowerShell 5.1 + WPF/XAML**.

The v2 interface is a full WPF redesign of the original WinForms version. The QR engine is separated from the UI so the application can be styled and extended without rewriting the QR logic.

## Features

- Contact / vCard 3.0
- Website / URL
- Wi-Fi credentials
- Free text
- Email
- Phone number
- SMS
- Geo coordinates
- Modern dark WPF interface
- QR preview
- Optional centered custom logo
- Adjustable logo size (8–20 %)
- Automatic ECC H when a logo is used
- PNG export
- Automatic `.vcf` export for vCards
- Configurable output size
- Optional automatic QR readability test
- No logo bundled or selected by default

## Project structure

```text
Universal_QR_Code_Generator_WPF_v2/
├── src/
│   ├── Universal_QR_GUI.ps1
│   ├── MainWindow.xaml
│   └── QRCore.ps1
├── assets/
│   └── Universal_QR_GUI.ico
├── screenshots/
├── Universal_QR_GUI_Starten.vbs
├── Universal_QR_GUI_Debug.bat
├── README.md
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

The debug launcher keeps the PowerShell console visible.

## Requirements

- Windows 10 / 11
- Windows PowerShell 5.1 or newer
- WPF / .NET Framework available
- Internet connection for QR generation and the optional read test

No external PowerShell modules are required.

## Logo

No logo is shipped with the project.

Click **Logo wählen** to select your own PNG, JPG, JPEG or BMP image.

Recommended:

- transparent PNG
- logo size around `16 %`
- error correction `H`

When a logo is enabled, the application automatically switches ECC to `H` during generation.

## QR service

QR generation currently uses:

```text
https://api.qrserver.com/v1/create-qr-code/
```

The optional read test uses:

```text
https://api.qrserver.com/v1/read-qr-code/
```

## Privacy

QR content is sent to the external QRServer service for generation.

If the readability test is enabled, the generated QR image is also uploaded to the service.

This is important for sensitive payloads such as:

- Wi-Fi passwords
- personal contact data
- private URLs
- internal notes

A future version could replace the API with a fully local QR encoder.

## Recommended print settings

- Size: `1000 × 1000 px`
- ECC: `H` with logo
- Logo: around `16 %`
- Quiet zone: `4` modules
- Always test a printed QR code with multiple phones before a large print run

## License

This project is licensed under the MIT License.  
See the [LICENSE](LICENSE) file for details.


## v2.1 fixes

- Reworked the left QR-type navigation with fixed-width Segoe MDL2 glyphs.
- Fixed clipped / uneven navigation icons.
- Fixed unreadable selected values in WPF ComboBoxes on Windows themes that render a light selection field.
- Fixed QR preview caching when overwriting the same PNG file repeatedly.
- QR preview images are now loaded from fresh file bytes instead of a cached file URI.


## v2.2

- Added a dedicated settings dialog.
- Default output directory can now be selected and is remembered.
- Default QR size can be configured globally.
- Default ECC can be configured globally.
- Automatic readability test can be enabled / disabled globally.
- Optional automatic opening of the generated QR image.
- Added a QR provider setting and provider abstraction.
- QRServer / goQR.me is currently the only implemented provider.
- Application settings are persisted in:

```text
%APPDATA%\UniversalQRCodeGenerator\settings.json
```

- Simplified the footer: the current QR type and API provider are no longer shown there.
- The right-hand settings area now shows a compact summary and links to the settings dialog.


## v2.3

- Navigation buttons now use a dedicated left-aligned WPF template.
- Icons and labels have fixed columns and no longer appear centered inside the sidebar.
- Visible scrollbars are hidden in the main UI; mouse-wheel and touchpad scrolling remain available.
- Settings window redesigned into three clean cards without a visible scrollbar.
- Added `Standardwerte` reset button.
- Added editable API endpoints.
- Provider options:
  - `QRServer / goQR.me (Standard)`
  - `Benutzerdefiniert (QRServer-kompatibel)`
- Custom provider settings include:
  - Create API endpoint
  - Read API endpoint
- No PowerShell source edit is needed to change compatible API endpoints.

### Custom API compatibility

The custom provider currently expects the same HTTP contract as QRServer:

**Create endpoint**
- `POST`
- `application/x-www-form-urlencoded`
- fields such as `data`, `size`, `ecc`, `color`, `bgcolor`, `qzone`, `format`

**Read endpoint**
- `POST`
- `multipart/form-data`
- image field `file`
- `outputformat=json`
- QRServer-compatible JSON response

An API using a different schema, authentication mechanism or response format needs a provider adapter in `QRCore.ps1`.


## v2.3.1 hotfix

- Fixed a WPF XAML crash when opening the settings dialog.
- The cause was an invalid `Margin="0,0,auto,0"` value.
- Replaced the settings action row with a proper three-column Grid.
- Added defensive error handling around dynamic settings-XAML loading.
- Added package-time validation for invalid `Margin` and `Padding` values.


## v2.3.2 hotfix

- Settings content can be scrolled again with mouse wheel / touchpad.
- The settings scrollbar stays visually hidden to keep the clean UI.
- Settings buttons now use the same rounded WPF style as the main application.
- Added hover, pressed and disabled visual states to settings buttons.
