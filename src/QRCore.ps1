# QRCore.ps1
# Core functions for Universal QR-Code Generator WPF v2.5

function Get-SafeFileName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "QR_Code"
    }

    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $Name = $Name.Replace([string]$char, "_")
    }

    $Name = $Name.Trim().TrimEnd(".")
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return "QR_Code"
    }
    return $Name
}

function Escape-VCardText {
    param([AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return "" }

    $Text = $Text.Replace("\", "\\")
    $Text = $Text.Replace(";", "\;")
    $Text = $Text.Replace(",", "\,")
    $Text = $Text.Replace("`r`n", "\n")
    $Text = $Text.Replace("`n", "\n")
    $Text = $Text.Replace("`r", "\n")
    return $Text
}

function Escape-WifiText {
    param([AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return "" }

    foreach ($char in @("\", ";", ",", ":", '"')) {
        $Text = $Text.Replace($char, "\" + $char)
    }
    return $Text
}


$Script:LocalQrEngineLoaded = $false

function Initialize-LocalQrEngine {
    param(
        [Parameter(Mandatory=$false)]
        [string]$EnginePath = (Join-Path $PSScriptRoot "LocalQrEngine.cs")
    )

    if ($Script:LocalQrEngineLoaded -and ("LocalQr.QrEncoder" -as [type])) {
        return
    }

    if ("LocalQr.QrEncoder" -as [type]) {
        $Script:LocalQrEngineLoaded = $true
        return
    }

    if (-not (Test-Path -LiteralPath $EnginePath)) {
        throw ("Local QR engine source file not found: " + $EnginePath)
    }

    try {
        Add-Type -Path $EnginePath -ErrorAction Stop
        $Script:LocalQrEngineLoaded = $true
    }
    catch {
        throw ("Local QR engine could not be loaded: " + $_.Exception.Message)
    }
}

function New-QrPngLocal {
    param(
        [Parameter(Mandatory=$true)][string]$Data,
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true)][int]$Size,
        [Parameter(Mandatory=$true)][ValidateSet("L","M","Q","H")][string]$Ecc
    )

    Initialize-LocalQrEngine

    if ($Size -lt 200) {
        throw "The requested PNG size is too small for the local QR renderer."
    }

    $result = [LocalQr.QrEncoder]::Encode($Data, $Ecc)
    if ($null -eq $result -or $null -eq $result.Modules) {
        throw "The local QR engine returned no matrix."
    }

    $moduleCount = [int]$result.Modules.GetLength(0)
    $quietZone = 4
    $totalModules = $moduleCount + (2 * $quietZone)
    $modulePixels = [int][Math]::Floor($Size / [double]$totalModules)

    if ($modulePixels -lt 1) {
        throw "The requested PNG size is too small for this QR version."
    }

    $qrPixelSize = $totalModules * $modulePixels
    $offset = [int][Math]::Floor(($Size - $qrPixelSize) / 2.0)

    $bitmap = [System.Drawing.Bitmap]::new(
        $Size,
        $Size,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    )

    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::White)
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

            $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Black)
            try {
                for ($row = 0; $row -lt $moduleCount; $row++) {
                    $col = 0
                    while ($col -lt $moduleCount) {
                        while ($col -lt $moduleCount -and -not [bool]$result.Modules.GetValue($row, $col)) {
                            $col++
                        }

                        if ($col -ge $moduleCount) {
                            break
                        }

                        $runStart = $col
                        while ($col -lt $moduleCount -and [bool]$result.Modules.GetValue($row, $col)) {
                            $col++
                        }

                        $runLength = $col - $runStart
                        $x = $offset + (($quietZone + $runStart) * $modulePixels)
                        $y = $offset + (($quietZone + $row) * $modulePixels)

                        $graphics.FillRectangle(
                            $brush,
                            $x,
                            $y,
                            ($runLength * $modulePixels),
                            $modulePixels
                        )
                    }
                }
            }
            finally {
                $brush.Dispose()
            }
        }
        finally {
            $graphics.Dispose()
        }

        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }

    return [PSCustomObject]@{
        Engine = "local"
        Version = [int]$result.Version
        Mask = [int]$result.Mask
        ModuleCount = $moduleCount
        Ecc = [string]$result.ErrorCorrection
    }
}

function New-QrPngViaApi {
    param(
        [Parameter(Mandatory=$true)][string]$Data,
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true)][int]$Size,
        [Parameter(Mandatory=$true)][ValidateSet("L","M","Q","H")][string]$Ecc,
        [Parameter(Mandatory=$true)][string]$CreateEndpoint
    )

    if ([string]::IsNullOrWhiteSpace($CreateEndpoint)) {
        throw "Es ist kein Create-API-Endpunkt konfiguriert."
    }

    $uri = $null
    if (-not [Uri]::TryCreate($CreateEndpoint, [UriKind]::Absolute, [ref]$uri)) {
        throw ("Ungültiger Create-API-Endpunkt: " + $CreateEndpoint)
    }

    $client = [System.Net.Http.HttpClient]::new()
    try {
        $client.Timeout = [TimeSpan]::FromSeconds(45)

        $pairs = [System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]]::new()
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("data", $Data))
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("size", ($Size.ToString() + "x" + $Size.ToString())))
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("charset-source", "UTF-8"))
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("charset-target", "UTF-8"))
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("ecc", $Ecc))
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("color", "000000"))
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("bgcolor", "FFFFFF"))
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("qzone", "4"))
        $pairs.Add([System.Collections.Generic.KeyValuePair[string,string]]::new("format", "png"))

        $content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
        try {
            $response = $client.PostAsync(
                $CreateEndpoint,
                $content
            ).GetAwaiter().GetResult()

            try {
                if (-not $response.IsSuccessStatusCode) {
                    throw ("QRServer HTTP-Fehler: " + [int]$response.StatusCode + " " + $response.ReasonPhrase)
                }

                $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
                if ($bytes.Length -lt 100) {
                    throw "Die API hat keine plausible PNG-Datei geliefert."
                }

                [System.IO.File]::WriteAllBytes($OutputPath, $bytes)
            }
            finally {
                $response.Dispose()
            }
        }
        finally {
            $content.Dispose()
        }
    }
    finally {
        $client.Dispose()
    }
}

function Add-LogoToQr {
    param(
        [Parameter(Mandatory=$true)][string]$QrPath,
        [Parameter(Mandatory=$true)][string]$LogoPath,
        [Parameter(Mandatory=$true)][double]$LogoPercent,
        [Parameter(Mandatory=$false)][string]$TempDir = ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\temp")))
    )

    if (-not (Test-Path -LiteralPath $QrPath)) {
        throw ("QR-Datei nicht gefunden: " + $QrPath)
    }
    if (-not (Test-Path -LiteralPath $LogoPath)) {
        throw ("Logo-Datei nicht gefunden: " + $LogoPath)
    }

    if (-not (Test-Path -LiteralPath $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }

    $LogoPercent = [Math]::Max(8.0, [Math]::Min(20.0, $LogoPercent))
    $qr = [System.Drawing.Image]::FromFile($QrPath)
    $logo = [System.Drawing.Image]::FromFile($LogoPath)

    try {
        $canvas = [System.Drawing.Bitmap]::new(
            $qr.Width,
            $qr.Height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )

        try {
            $g = [System.Drawing.Graphics]::FromImage($canvas)
            try {
                $g.Clear([System.Drawing.Color]::White)
                $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

                $g.DrawImage(
                    $qr,
                    [System.Drawing.Rectangle]::new(0, 0, $qr.Width, $qr.Height)
                )

                $maxLogoSide = [int][Math]::Round($qr.Width * ($LogoPercent / 100.0))
                $scale = [Math]::Min(
                    $maxLogoSide / [double]$logo.Width,
                    $maxLogoSide / [double]$logo.Height
                )

                $logoW = [int][Math]::Round($logo.Width * $scale)
                $logoH = [int][Math]::Round($logo.Height * $scale)
                $padding = [int][Math]::Max(8, [Math]::Round($qr.Width * 0.018))

                $boxW = $logoW + (2 * $padding)
                $boxH = $logoH + (2 * $padding)
                $boxX = [int](($qr.Width - $boxW) / 2)
                $boxY = [int](($qr.Height - $boxH) / 2)
                $logoX = [int](($qr.Width - $logoW) / 2)
                $logoY = [int](($qr.Height - $logoH) / 2)

                $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
                try {
                    $g.FillRectangle(
                        $brush,
                        [System.Drawing.Rectangle]::new($boxX, $boxY, $boxW, $boxH)
                    )
                }
                finally {
                    $brush.Dispose()
                }

                $g.DrawImage(
                    $logo,
                    [System.Drawing.Rectangle]::new($logoX, $logoY, $logoW, $logoH)
                )
            }
            finally {
                $g.Dispose()
            }

            $temp = Join-Path $TempDir ("qr_logo_" + [guid]::NewGuid().ToString("N") + ".png")
            $canvas.Save($temp, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $canvas.Dispose()
        }
    }
    finally {
        $logo.Dispose()
        $qr.Dispose()
    }

    Move-Item -LiteralPath $temp -Destination $QrPath -Force
}

function Compare-QrPayloadText {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Expected,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Decoded
    )

    # The comparison is intentionally privacy-preserving: it never returns the
    # payload text itself. It only classifies the kind of difference.
    $exp = $Expected.Replace("`r`n","`n").Replace("`r","`n")
    $dec = $Decoded.Replace("`r`n","`n").Replace("`r","`n")

    $result = [ordered]@{
        Exact = $false
        Equivalent = $false
        Category = "ContentDifference"
        Summary = "Decoded text differs from the generated payload"
        ExpectedLength = $exp.Length
        DecodedLength = $dec.Length
        FirstDifferenceIndex = -1
        ExpectedCodePoint = "<end>"
        DecodedCodePoint = "<end>"
    }

    if ($exp -ceq $dec) {
        $result.Exact = $true
        $result.Equivalent = $true
        $result.Category = "Exact"
        $result.Summary = "Exact payload match"
        return [PSCustomObject]$result
    }

    # QRServer-style encoders/readers sometimes add or remove the conventional
    # final line break of a vCard. This does not change the vCard fields.
    $isVCard = $exp.StartsWith("BEGIN:VCARD`n", [System.StringComparison]::Ordinal)
    if ($isVCard) {
        $expOne = if ($exp.EndsWith("`n", [System.StringComparison]::Ordinal)) { $exp.Substring(0, $exp.Length - 1) } else { $exp }
        $decOne = if ($dec.EndsWith("`n", [System.StringComparison]::Ordinal)) { $dec.Substring(0, $dec.Length - 1) } else { $dec }
        if ($expOne -ceq $decOne) {
            $result.Equivalent = $true
            $result.Category = "VCardFinalLineBreak"
            $result.Summary = "vCard fields match; only the final line break differs"
            return [PSCustomObject]$result
        }
    }

    try {
        $expNfc = $exp.Normalize([System.Text.NormalizationForm]::FormC)
        $decNfc = $dec.Normalize([System.Text.NormalizationForm]::FormC)
        if ($expNfc -ceq $decNfc) {
            $result.Category = "UnicodeNormalization"
            $result.Summary = "Text is Unicode-equivalent but uses a different normalization form"
        }
    }
    catch {}

    if ($result.Category -eq "ContentDifference") {
        # Detect the common UTF-8-as-Latin-1 mojibake pattern without logging
        # any payload content.
        try {
            $latin1 = [System.Text.Encoding]::GetEncoding(28591)
            $utf8 = [System.Text.Encoding]::UTF8
            $repairedDecoded = $utf8.GetString($latin1.GetBytes($dec))
            if ($repairedDecoded -ceq $exp) {
                $result.Category = "Utf8DecodedAsLatin1"
                $result.Summary = "The decoded payload appears to interpret UTF-8 bytes as Latin-1"
            }
        }
        catch {}
    }

    if ($result.Category -eq "ContentDifference") {
        try {
            $latin1 = [System.Text.Encoding]::GetEncoding(28591)
            $utf8 = [System.Text.Encoding]::UTF8
            $mojibakeExpected = $latin1.GetString($utf8.GetBytes($exp))
            if ($mojibakeExpected -ceq $dec) {
                $result.Category = "Utf8DecodedAsLatin1"
                $result.Summary = "The decoded payload appears to interpret UTF-8 bytes as Latin-1"
            }
        }
        catch {}
    }

    if ($result.Category -eq "ContentDifference") {
        # Some QR readers guess Big5 when a QR payload contains UTF-8 bytes but
        # no charset information they trust. A characteristic example is the
        # UTF-8 byte pair C3 B6 (ö), which Big5 maps to U+7E79. Detect the
        # transformation over the complete payload so a real content change is
        # never hidden behind this warning.
        try {
            $big5 = [System.Text.Encoding]::GetEncoding(950)
            $utf8 = [System.Text.Encoding]::UTF8
            $big5Interpreted = $big5.GetString($utf8.GetBytes($exp))
            if ($big5Interpreted -ceq $dec) {
                $result.Category = "CharsetAmbiguity"
                $result.Summary = "The online reader interpreted UTF-8 bytes as a different character set (Big5-compatible pattern)"
            }
        }
        catch {}
    }

    if ($result.Category -eq "ContentDifference" -and $exp.Length -ne $dec.Length) {
        $result.Category = "LengthDifference"
        $result.Summary = "Decoded payload length differs from the generated payload"
    }

    $limit = [Math]::Min($exp.Length, $dec.Length)
    $idx = 0
    while ($idx -lt $limit -and $exp[$idx] -ceq $dec[$idx]) { $idx++ }
    if ($idx -eq $limit -and $exp.Length -eq $dec.Length) { $idx = -1 }

    if ($idx -ge 0) {
        $result.FirstDifferenceIndex = $idx
        if ($idx -lt $exp.Length) { $result.ExpectedCodePoint = ("U+{0:X4}" -f [int][char]$exp[$idx]) }
        if ($idx -lt $dec.Length) { $result.DecodedCodePoint = ("U+{0:X4}" -f [int][char]$dec[$idx]) }
    }

    return [PSCustomObject]$result
}

function Test-QrViaApi {
    param(
        [Parameter(Mandatory=$true)][string]$QrPath,
        [Parameter(Mandatory=$true)][string]$ExpectedData,
        [Parameter(Mandatory=$true)][string]$ReadEndpoint,
        [Parameter(Mandatory=$false)][string]$TempDir = ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\temp")))
    )

    if ([string]::IsNullOrWhiteSpace($ReadEndpoint)) {
        throw "Es ist kein Read-API-Endpunkt konfiguriert."
    }

    $uri = $null
    if (-not [Uri]::TryCreate($ReadEndpoint, [UriKind]::Absolute, [ref]$uri)) {
        throw ("Ungültiger Read-API-Endpunkt: " + $ReadEndpoint)
    }

    if (-not (Test-Path -LiteralPath $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }

    $testPath = $QrPath
    $tempUsed = $false
    $fileInfo = Get-Item -LiteralPath $QrPath

    if ($fileInfo.Length -gt 950KB) {
        $source = [System.Drawing.Image]::FromFile($QrPath)
        try {
            $small = [System.Drawing.Bitmap]::new(600, 600)
            try {
                $g = [System.Drawing.Graphics]::FromImage($small)
                try {
                    $g.Clear([System.Drawing.Color]::White)
                    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                    $g.DrawImage($source, [System.Drawing.Rectangle]::new(0,0,600,600))
                }
                finally {
                    $g.Dispose()
                }

                $testPath = Join-Path $TempDir ("qr_test_" + [guid]::NewGuid().ToString("N") + ".png")
                $small.Save($testPath, [System.Drawing.Imaging.ImageFormat]::Png)
                $tempUsed = $true
            }
            finally {
                $small.Dispose()
            }
        }
        finally {
            $source.Dispose()
        }
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($testPath)
        $client = [System.Net.Http.HttpClient]::new()
        try {
            $client.Timeout = [TimeSpan]::FromSeconds(45)
            $multipart = [System.Net.Http.MultipartFormDataContent]::new()

            try {
                $multipart.Add([System.Net.Http.StringContent]::new("json"), "outputformat")

                $fileContent = [System.Net.Http.ByteArrayContent]::new($bytes)
                $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
                $multipart.Add($fileContent, "file", "qrcode.png")

                $response = $client.PostAsync(
                    $ReadEndpoint,
                    $multipart
                ).GetAwaiter().GetResult()

                try {
                    if (-not $response.IsSuccessStatusCode) {
                        throw ("Read-API HTTP-Fehler: " + [int]$response.StatusCode)
                    }

                    $json = ($response.Content.ReadAsStringAsync().GetAwaiter().GetResult()) | ConvertFrom-Json
                    $root = @($json)[0]
                    $symbol = @($root.symbol)[0]

                    if (-not [string]::IsNullOrWhiteSpace([string]$symbol.error)) {
                        return [PSCustomObject]@{
                            Success = $false
                            Exact = $false
                            Equivalent = $false
                            Error = [string]$symbol.error
                            ErrorType = "Decode"
                            Exception = $null
                        }
                    }

                    $decoded = [string]$symbol.data
                    if ($null -eq $decoded) {
                        return [PSCustomObject]@{
                            Success = $false
                            Exact = $false
                            Equivalent = $false
                            Error = "Die Read-API lieferte keinen decodierten Inhalt."
                            ErrorType = "Decode"
                            Exception = $null
                        }
                    }

                    $comparison = Compare-QrPayloadText -Expected $ExpectedData -Decoded $decoded

                    return [PSCustomObject]@{
                        Success = $true
                        Exact = [bool]$comparison.Exact
                        Equivalent = [bool]$comparison.Equivalent
                        MismatchCategory = [string]$comparison.Category
                        MismatchSummary = [string]$comparison.Summary
                        ExpectedLength = [int]$comparison.ExpectedLength
                        DecodedLength = [int]$comparison.DecodedLength
                        FirstDifferenceIndex = [int]$comparison.FirstDifferenceIndex
                        ExpectedCodePoint = [string]$comparison.ExpectedCodePoint
                        DecodedCodePoint = [string]$comparison.DecodedCodePoint
                        Error = $null
                        ErrorType = $null
                        Exception = $null
                    }
                }
                finally {
                    $response.Dispose()
                }
            }
            finally {
                $multipart.Dispose()
            }
        }
        finally {
            $client.Dispose()
        }
    }
    catch {
        # A read test is optional. Network/provider errors are returned as a
        # structured result so an already-created QR code remains successful.
        return [PSCustomObject]@{
            Success = $false
            Exact = $false
            Equivalent = $false
            Error = [string]$_.Exception.Message
            ErrorType = "Transport"
            Exception = $_.Exception
        }
    }
    finally {
        if ($tempUsed -and (Test-Path -LiteralPath $testPath)) {
            Remove-Item -LiteralPath $testPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-WpfBitmapImage {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("Bilddatei nicht gefunden: " + $Path)
    }

    # Do not use UriSource here:
    # WPF may reuse the cached bitmap when the same PNG path is overwritten.
    # Reading the actual file bytes guarantees that every generated QR code
    # refreshes immediately, even when the filename stays unchanged.
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $stream = [System.IO.MemoryStream]::new($bytes)

    try {
        $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.StreamSource = $stream
        $bitmap.EndInit()
        $bitmap.Freeze()
        return $bitmap
    }
    finally {
        $stream.Dispose()
    }
}
