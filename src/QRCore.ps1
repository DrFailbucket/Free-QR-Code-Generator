# QRCore.ps1
# Core functions for Universal QR-Code Generator WPF v2

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
                            Error = [string]$symbol.error
                        }
                    }

                    $decoded = [string]$symbol.data
                    if ($null -eq $decoded) {
                        return [PSCustomObject]@{
                            Success = $false
                            Exact = $false
                            Error = "Die Read-API lieferte keinen decodierten Inhalt."
                        }
                    }

                    $normExpected = $ExpectedData.Replace("`r`n","`n").Replace("`r","`n")
                    $normDecoded = $decoded.Replace("`r`n","`n").Replace("`r","`n")

                    return [PSCustomObject]@{
                        Success = $true
                        Exact = ($normExpected -ceq $normDecoded)
                        Error = $null
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
