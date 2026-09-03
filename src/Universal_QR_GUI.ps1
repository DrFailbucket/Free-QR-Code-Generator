#requires -Version 5.1
<#
    Universal QR-Code Generator
    WPF v2.5
#>

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Windows.Forms

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$CoreFile = Join-Path $ScriptDir "QRCore.ps1"
$XamlFile = Join-Path $ScriptDir "MainWindow.xaml"
$IconFile = Join-Path $ProjectRoot "assets\Universal_QR_GUI.ico"

. $CoreFile

$Script:Mode = "vCard"
$Script:LogoPath = $null
$Script:GeneratedQrPath = $null
$Script:GeneratedQrData = $null

# Debug output is opt-in and enabled only by Universal_QR_GUI_Debug.bat.
# The normal VBS launcher does not set this environment variable and stays quiet.
$Script:DebugMode = ([string]$env:UQRG_DEBUG -eq "1")

function Write-DebugLog {
    param(
        [Parameter(Mandatory=$true)][string]$Component,
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("Info","Ok","Warn","Error")][string]$Level = "Info"
    )

    if (-not $Script:DebugMode) { return }

    $timestamp = Get-Date -Format "HH:mm:ss.fff"
    $prefix = "[{0}] {1,-18}: " -f $timestamp, $Component
    $color = switch ($Level) {
        "Ok"    { "Green" }
        "Warn"  { "Yellow" }
        "Error" { "Red" }
        default { "Cyan" }
    }

    Write-Host -NoNewline $prefix -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor $color
}

function Get-ErrorDiagnostic {
    param($ErrorObject)

    $exception = $null
    if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
        $exception = $ErrorObject.Exception
    }
    elseif ($ErrorObject -is [System.Exception]) {
        $exception = $ErrorObject
    }
    elseif ($null -ne $ErrorObject -and $null -ne $ErrorObject.Exception) {
        $exception = $ErrorObject.Exception
    }

    if ($null -eq $exception) {
        return [PSCustomObject]@{
            Category = "Unknown"
            Summary = "Unknown error"
            Advice = "No exception details were available."
            Technical = [string]$ErrorObject
        }
    }

    $chain = [System.Collections.Generic.List[System.Exception]]::new()
    $cursor = $exception
    $guard = 0
    while ($null -ne $cursor -and $guard -lt 10) {
        $chain.Add($cursor)
        $cursor = $cursor.InnerException
        $guard++
    }

    $technicalParts = @()
    foreach ($item in $chain) {
        $technicalParts += ($item.GetType().FullName + ": " + $item.Message)
    }
    $technical = $technicalParts -join " -> "
    $combined = ($technicalParts -join " | ")

    $category = "Unexpected"
    $summary = "The operation could not be completed because an unexpected Windows or application error occurred"
    $advice = "Try the operation again. If the problem repeats, use the Technical and Location lines when reporting the issue."

    # Prefer structured network status information when an inner exception exposes it.
    foreach ($item in $chain) {
        if ($item.PSObject.Properties.Name -contains "Status") {
            $status = [string]$item.Status
            switch ($status) {
                "NameResolutionFailure" {
                    $category = "DNS"
                    $summary = "Host name could not be resolved (DNS / no network connection)"
                    $advice = "Check Internet/VPN connectivity and DNS resolution, then try again."
                    break
                }
                "ProxyNameResolutionFailure" {
                    $category = "ProxyDNS"
                    $summary = "Configured proxy could not be resolved"
                    $advice = "Check the Windows proxy configuration or disable the proxy for this connection."
                    break
                }
                "ConnectFailure" {
                    $category = "Connection"
                    $summary = "Connection to the online QR service could not be established"
                    $advice = "The PC may be offline, the server may be unreachable, or a firewall/VPN may block the connection."
                    break
                }
                "Timeout" {
                    $category = "Timeout"
                    $summary = "The online QR service did not respond before the timeout"
                    $advice = "Check the network connection and try again. The provider may also be temporarily slow or unavailable."
                    break
                }
                "TrustFailure" {
                    $category = "TLS"
                    $summary = "TLS certificate validation failed"
                    $advice = "Check Windows date/time, certificates, HTTPS inspection, proxy and security software."
                    break
                }
                "SecureChannelFailure" {
                    $category = "TLS"
                    $summary = "A secure TLS connection to the provider could not be established"
                    $advice = "Check TLS/certificate settings, Windows date/time, proxy and security software."
                    break
                }
                "ConnectionClosed" {
                    $category = "ConnectionClosed"
                    $summary = "The remote service closed the connection unexpectedly"
                    $advice = "Retry the request. If it persists, the provider or an intermediate proxy/firewall may be closing the connection."
                    break
                }
                "SendFailure" {
                    $category = "SendFailure"
                    $summary = "The request could not be sent to the online provider"
                    $advice = "Check Internet/VPN connectivity, firewall rules and whether the provider is reachable."
                    break
                }
                "ReceiveFailure" {
                    $category = "ReceiveFailure"
                    $summary = "The connection was made, but the provider response could not be received"
                    $advice = "Retry the request and check whether a proxy/firewall or provider outage is interrupting the response."
                    break
                }
            }
        }

        if ($category -eq "Unexpected" -and ($item.PSObject.Properties.Name -contains "SocketErrorCode")) {
            $socketCode = [string]$item.SocketErrorCode
            switch ($socketCode) {
                "HostNotFound" {
                    $category = "DNS"
                    $summary = "Host name could not be resolved (DNS)"
                    $advice = "Check Internet/VPN connectivity and DNS resolution."
                    break
                }
                "NetworkDown" {
                    $category = "NetworkDown"
                    $summary = "Windows reports that the network is down"
                    $advice = "Reconnect Wi-Fi/Ethernet/VPN before using an online provider or read test."
                    break
                }
                "NetworkUnreachable" {
                    $category = "NetworkUnreachable"
                    $summary = "No network route to the online provider is available"
                    $advice = "Check Wi-Fi/Ethernet/VPN and routing."
                    break
                }
                "ConnectionRefused" {
                    $category = "ConnectionRefused"
                    $summary = "The remote host actively refused the connection"
                    $advice = "The provider endpoint may be unavailable or the port may be blocked."
                    break
                }
                "TimedOut" {
                    $category = "Timeout"
                    $summary = "Network connection timed out"
                    $advice = "Check connectivity and retry later if the provider is slow or unavailable."
                    break
                }
            }
        }
    }

    if ($combined -match "Local QR engine source file not found") {
        $category = "LocalEngineMissing"
        $summary = "Local QR engine file is missing"
        $advice = "Restore src\LocalQrEngine.cs. If online fallback is enabled, the configured fallback provider can still be used."
    }
    elseif ($combined -match "Local QR engine could not be loaded") {
        $category = "LocalEngineLoad"
        $summary = "Local QR engine could not be compiled or loaded"
        $advice = "Check the following technical compiler/loader message. The online fallback may still be used when enabled."
    }
    elseif ($combined -match "(?i)timed out|timeout|Zeitüberschreitung") {
        $category = "Timeout"
        $summary = "The online request timed out"
        $advice = "Check connectivity and retry. The provider may be temporarily unavailable."
    }
    elseif ($combined -match "(?i)certificate|zertifikat|SSL|TLS|secure channel|sicher.*kanal") {
        $category = "TLS"
        $summary = "The secure HTTPS/TLS connection failed"
        $advice = "Check Windows date/time, certificates, proxy/VPN and HTTPS inspection software."
    }
    elseif ($combined -match "(?i)name.*resol|remote.*name|remotename|aufgelöst|DNS|host.*known") {
        $category = "DNS"
        $summary = "The provider host name could not be resolved"
        $advice = "The PC may be offline or DNS may be unavailable. Check Wi-Fi/Ethernet/VPN and DNS."
    }
    elseif ($combined -match "(?i)Fehler beim Senden der Anforderung|error while sending the request|connection|Verbindung") {
        $category = "Connection"
        $summary = "The request could not reach the online QR service"
        $advice = "Check Internet/VPN connectivity, firewall/proxy settings and provider availability."
    }
    elseif ($combined -match "(?i)HTTP-Fehler: 401|HTTP-Fehler: 403") {
        $category = "Authorization"
        $summary = "The online provider rejected the request (HTTP authorization error)"
        $advice = "Check endpoint permissions, authentication requirements and provider configuration."
    }
    elseif ($combined -match "(?i)HTTP-Fehler: 429") {
        $category = "RateLimit"
        $summary = "The online provider rate-limited the request (HTTP 429)"
        $advice = "Wait before retrying or use another provider."
    }
    elseif ($combined -match "(?i)HTTP-Fehler: 5[0-9][0-9]") {
        $category = "ProviderServer"
        $summary = "The online provider returned a server error"
        $advice = "The provider is likely temporarily unavailable. Retry later or use another provider."
    }
    elseif ($combined -match "(?i)HTTP-Fehler: 4[0-9][0-9]") {
        $category = "ProviderRequest"
        $summary = "The online provider rejected the request with an HTTP client error"
        $advice = "Check the configured endpoint and whether the provider still supports the expected QRServer-compatible API."
    }
    elseif ($combined -match "(?i)ConvertFrom-Json|JSON|unexpected character|ungültige.*antwort") {
        $category = "ProviderResponse"
        $summary = "The online provider returned an unexpected or invalid response"
        $advice = "The endpoint may not be QRServer-compatible, or the provider may currently return an error page instead of JSON."
    }
    elseif ($combined -match "(?i)keine plausible PNG|plausible PNG") {
        $category = "ProviderResponse"
        $summary = "The online provider did not return a valid QR PNG image"
        $advice = "Check the create endpoint and provider compatibility."
    }
    elseif ($combined -match "(?i)Ungültiger .*API-Endpunkt|invalid .*endpoint") {
        $category = "Configuration"
        $summary = "The configured API endpoint is invalid"
        $advice = "Open Settings and verify the configured create/read endpoint."
    }
    elseif ($combined -match "(?i)QR payload is too large|payload exceeds.*capacity|version 40") {
        $category = "PayloadTooLarge"
        $summary = "The QR content is too large for the selected error-correction requirements"
        $advice = "Shorten the QR content. For very large payloads, also try a lower ECC level when no logo is used."
    }
    elseif ($combined -match "(?i)PNG size is too small|requested PNG size is too small") {
        $category = "RenderSize"
        $summary = "The selected image size is too small for this QR code"
        $advice = "Increase the QR output size in Settings and try again."
    }
    elseif ($combined -match "(?i)returned no matrix") {
        $category = "LocalEngineResult"
        $summary = "The local QR engine did not return a usable QR matrix"
        $advice = "Retry once. If the error repeats, use the online fallback and report the Technical details."
    }
    elseif ($combined -match "(?i)Parametersatz.*benannten Parametern|parameter set cannot be resolved") {
        $category = "PowerShellCompatibility"
        $summary = "Windows PowerShell could not execute an internal command with the supplied parameters"
        $advice = "This is usually a compatibility/programming issue rather than bad QR data. Report the Technical and Location lines."
    }
    elseif ($combined -match "(?i)Schlüssel darf nicht NULL sein|key cannot be null|Value cannot be null.*key") {
        $category = "InternalState"
        $summary = "The application encountered an invalid internal state while processing the QR image"
        $advice = "Retry the operation. If it repeats, report the Technical and Location lines; your entered QR data is usually not the cause."
    }
    elseif ($combined -match "(?i)generic error occurred in GDI\+|GDI\+|Parameter is not valid.*image|image.*invalid") {
        $category = "ImageProcessing"
        $summary = "Windows could not process or save the QR/logo image"
        $advice = "Check that the logo is a valid PNG/JPG/BMP, the output folder is writable, and the target PNG is not locked by another program."
    }
    elseif ($combined -match "(?i)path too long|Pfad.*zu lang") {
        $category = "PathTooLong"
        $summary = "The selected file path is too long for this Windows/PowerShell operation"
        $advice = "Choose a shorter output folder or filename and try again."
    }
    elseif ($combined -match "(?i)DirectoryNotFound|Verzeichnis.*nicht gefunden|Could not find a part of the path") {
        $category = "FolderMissing"
        $summary = "A required folder could not be found"
        $advice = "Check the application/output folder and make sure the portable project structure is complete."
    }
    elseif ($combined -match "(?i)FileNotFound|Datei.*nicht gefunden|file not found|Bilddatei nicht gefunden|QR-Datei nicht gefunden|Logo-Datei nicht gefunden") {
        $category = "FileMissing"
        $summary = "A required file could not be found"
        $advice = "Check the file path. If this concerns a logo, select the logo again; if it concerns the local engine, restore the complete src folder."
    }
    elseif ($combined -match "(?i)disk full|Datenträger.*voll|not enough space|nicht genügend Speicherplatz") {
        $category = "DiskFull"
        $summary = "Windows could not save the file because the target drive may be full"
        $advice = "Free disk space or select another output location."
    }
    elseif ($combined -match "(?i)Zugriff.*verweigert|access.*denied|UnauthorizedAccess") {
        $category = "FileAccess"
        $summary = "Windows denied access to a required file or folder"
        $advice = "Check write permissions and whether security software is blocking the application directory."
    }
    elseif ($combined -match "(?i)IOException|E/A-Fehler|I/O error") {
        $category = "FileIO"
        $summary = "Windows reported a file read/write error"
        $advice = "Check that the output drive is connected and writable and that the target file is not open or locked by another application."
    }

    return [PSCustomObject]@{
        Category = $category
        Summary = $summary
        Advice = $advice
        Technical = $technical
    }
}

function Write-DebugException {
    param(
        [Parameter(Mandatory=$true)][string]$Component,
        [Parameter(Mandatory=$true)]$ErrorObject
    )

    $diag = Get-ErrorDiagnostic $ErrorObject
    Write-DebugLog $Component ("FAILED [{0}] | {1}" -f $diag.Category, $diag.Summary) "Error"
    Write-DebugLog "What to do" $diag.Advice "Warn"
    Write-DebugLog "Technical" $diag.Technical "Error"
    return $diag
}

# Portable paths: all persistent and temporary app data stays beside the app.
$Script:ConfigDir = Join-Path $ProjectRoot "config"
$Script:SettingsFile = Join-Path $Script:ConfigDir "settings.json"
$Script:LocalesDir = Join-Path $ProjectRoot "locales"
$Script:TempDir = Join-Path $ProjectRoot "temp"
$Script:DefaultOutputDir = Join-Path $ProjectRoot "output"

$Script:Settings = [ordered]@{
    Language = "auto"
    OutputDir = "output"
    QrSize = 1000
    Ecc = "H"
    RunReadTest = $true
    RunOnlineReadTestForLocal = $false
    OpenAfterCreate = $false
    Provider = "local"
    UseOnlineFallback = $true
    FallbackProvider = "qrserver"
    CustomCreateEndpoint = "https://api.qrserver.com/v1/create-qr-code/"
    CustomReadEndpoint = "https://api.qrserver.com/v1/read-qr-code/"
}

$Script:Translations = @{}
$Script:ResolvedLanguage = "en"
$Script:CurrentStatusKey = "status.ready"
$Script:CurrentStatusMode = "Ok"
$Script:CurrentStatusTokens = @{}
$Script:OutputDir = $Script:DefaultOutputDir

function Resolve-PortablePath {
    param([string]$StoredPath)

    if ([string]::IsNullOrWhiteSpace($StoredPath)) {
        return $Script:DefaultOutputDir
    }

    if ([System.IO.Path]::IsPathRooted($StoredPath)) {
        return [System.IO.Path]::GetFullPath($StoredPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $StoredPath))
}

function Convert-ToPortableStoredPath {
    param([string]$FullPath)

    $full = [System.IO.Path]::GetFullPath($FullPath)
    $rootFull = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd("\\")
    $rootPrefix = $rootFull + "\\"

    if ($full.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "."
    }

    if ($full.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($rootPrefix.Length)
    }

    return $full
}

function Ensure-PortableDirectories {
    foreach ($dir in @($Script:ConfigDir, $Script:TempDir, $Script:DefaultOutputDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function Resolve-LanguageSetting {
    param([string]$LanguageSetting)

    if ($LanguageSetting -eq "de") { return "de" }
    if ($LanguageSetting -eq "en") { return "en" }

    try {
        if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq "de") {
            return "de"
        }
    }
    catch {}

    return "en"
}

function Load-Translations {
    param([string]$LanguageSetting)

    $resolved = Resolve-LanguageSetting $LanguageSetting
    $dict = @{}

    # English is the fallback language for incomplete future locale files.
    $baseFile = Join-Path $Script:LocalesDir "en.json"
    if (-not (Test-Path -LiteralPath $baseFile)) {
        throw ("Missing locale file: " + $baseFile)
    }

    $base = Get-Content -LiteralPath $baseFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($prop in $base.PSObject.Properties) {
        $dict[$prop.Name] = [string]$prop.Value
    }

    if ($resolved -ne "en") {
        $localeFile = Join-Path $Script:LocalesDir ($resolved + ".json")
        if (Test-Path -LiteralPath $localeFile) {
            $local = Get-Content -LiteralPath $localeFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $local.PSObject.Properties) {
                $dict[$prop.Name] = [string]$prop.Value
            }
        }
    }

    $Script:Translations = $dict
    $Script:ResolvedLanguage = $resolved
}

function T {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [hashtable]$Tokens = $null
    )

    $text = if ($Script:Translations.ContainsKey($Key)) {
        [string]$Script:Translations[$Key]
    }
    else {
        $Key
    }

    if ($null -ne $Tokens) {
        foreach ($token in $Tokens.Keys) {
            $text = $text.Replace("{" + [string]$token + "}", [string]$Tokens[$token])
        }
    }

    return $text
}

function Apply-LanguageResources {
    param($Target)

    if ($null -eq $Target) { return }

    foreach ($key in $Script:Translations.Keys) {
        $Target.Resources[$key] = [string]$Script:Translations[$key]
    }
}

function Load-AppSettings {
    Ensure-PortableDirectories

    try {
        if (Test-Path -LiteralPath $Script:SettingsFile) {
            $loaded = Get-Content -LiteralPath $Script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json

            if ([string]$loaded.Language -in @("auto","de","en")) {
                $Script:Settings.Language = [string]$loaded.Language
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$loaded.OutputDir)) {
                $Script:Settings.OutputDir = [string]$loaded.OutputDir
            }
            if ($loaded.QrSize -in @(400,600,800,900,1000)) {
                $Script:Settings.QrSize = [int]$loaded.QrSize
            }
            if ([string]$loaded.Ecc -in @("L","M","Q","H")) {
                $Script:Settings.Ecc = [string]$loaded.Ecc
            }
            if ($null -ne $loaded.RunReadTest) {
                $Script:Settings.RunReadTest = [bool]$loaded.RunReadTest
            }
            if ($null -ne $loaded.RunOnlineReadTestForLocal) {
                $Script:Settings.RunOnlineReadTestForLocal = [bool]$loaded.RunOnlineReadTestForLocal
            }
            if ($null -ne $loaded.OpenAfterCreate) {
                $Script:Settings.OpenAfterCreate = [bool]$loaded.OpenAfterCreate
            }
            if ([string]$loaded.Provider -in @("local","qrserver","custom")) {
                $Script:Settings.Provider = [string]$loaded.Provider
            }
            if ($null -ne $loaded.UseOnlineFallback) {
                $Script:Settings.UseOnlineFallback = [bool]$loaded.UseOnlineFallback
            }
            if ([string]$loaded.FallbackProvider -in @("qrserver","custom")) {
                $Script:Settings.FallbackProvider = [string]$loaded.FallbackProvider
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$loaded.CustomCreateEndpoint)) {
                $Script:Settings.CustomCreateEndpoint = [string]$loaded.CustomCreateEndpoint
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$loaded.CustomReadEndpoint)) {
                $Script:Settings.CustomReadEndpoint = [string]$loaded.CustomReadEndpoint
            }
        }
    }
    catch {
        # Invalid local settings never prevent the portable app from starting.
    }

    $Script:OutputDir = Resolve-PortablePath $Script:Settings.OutputDir
    if (-not (Test-Path -LiteralPath $Script:OutputDir)) {
        New-Item -ItemType Directory -Path $Script:OutputDir -Force | Out-Null
    }

    Load-Translations $Script:Settings.Language

    # Create the portable settings file on first launch so all app state
    # is visibly contained inside the project folder.
    if (-not (Test-Path -LiteralPath $Script:SettingsFile)) {
        try { Save-AppSettings } catch {}
    }
}

function Save-AppSettings {
    Ensure-PortableDirectories
    $Script:Settings | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $Script:SettingsFile -Encoding UTF8
}

function Update-SettingsSummary {
    $SummarySize.Text = [string]$Script:Settings.QrSize + " px"
    $SummaryEcc.Text = [string]$Script:Settings.Ecc
    if (-not [bool]$Script:Settings.RunReadTest) {
        $SummaryReadTest.Text = T "common.off"
    }
    elseif ($Script:Settings.Provider -eq "local" -and -not [bool]$Script:Settings.RunOnlineReadTestForLocal) {
        $SummaryReadTest.Text = T "summary.readtestFallbackOnly"
    }
    elseif ($Script:Settings.Provider -eq "local") {
        $SummaryReadTest.Text = T "summary.readtestOnlineAllowed"
    }
    else {
        $SummaryReadTest.Text = T "common.on"
    }

    switch ($Script:Settings.Provider) {
        "local" {
            $SummaryProvider.Text = T "provider.local"
            if ([bool]$Script:Settings.UseOnlineFallback) {
                $fallbackLabel = if ($Script:Settings.FallbackProvider -eq "custom") {
                    T "provider.custom"
                }
                else {
                    T "provider.qrserver"
                }
                $SummaryProvider.ToolTip = T "summary.localFallback" @{ provider = $fallbackLabel }
            }
            else {
                $SummaryProvider.ToolTip = T "summary.localOnly"
            }
        }
        "qrserver" {
            $SummaryProvider.Text = T "provider.qrserver"
            $SummaryProvider.ToolTip = T "settings.externalWarning"
        }
        "custom" {
            $SummaryProvider.Text = T "provider.custom"
            $SummaryProvider.ToolTip = T "settings.externalWarning"
        }
        default {
            $SummaryProvider.Text = [string]$Script:Settings.Provider
            $SummaryProvider.ToolTip = $null
        }
    }

    $wifiNoticeControl = Get-Variable -Name WifiNotice -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $wifiNoticeControl) {
        if ($Script:Settings.Provider -eq "local") {
            if ([bool]$Script:Settings.UseOnlineFallback) {
                $wifiNoticeControl.Text = T "wifi.notice.localFallback"
            }
            else {
                $wifiNoticeControl.Text = T "wifi.notice.local"
            }
        }
        else {
            $wifiNoticeControl.Text = T "wifi.notice.external"
        }
    }

    $FooterSize.Text = [string]$Script:Settings.QrSize + " px"
    $FooterEcc.Text = "ECC " + [string]$Script:Settings.Ecc

    try {
        $leaf = Split-Path -Leaf $Script:OutputDir
        if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = $Script:OutputDir }
        $FooterSavePath.Text = $leaf
        $FooterSavePath.ToolTip = $Script:OutputDir
    }
    catch {
        $FooterSavePath.Text = T "common.location"
    }
}

function Update-ModeText {
    switch ($Script:Mode) {
        "vCard" { $TxtModeTitle.Text = T "mode.vcard.title"; $TxtModeSubtitle.Text = T "mode.vcard.subtitle" }
        "url"   { $TxtModeTitle.Text = T "mode.url.title";   $TxtModeSubtitle.Text = T "mode.url.subtitle" }
        "wifi"  { $TxtModeTitle.Text = T "mode.wifi.title";  $TxtModeSubtitle.Text = T "mode.wifi.subtitle" }
        "text"  { $TxtModeTitle.Text = T "mode.text.title";  $TxtModeSubtitle.Text = T "mode.text.subtitle" }
        "email" { $TxtModeTitle.Text = T "mode.email.title"; $TxtModeSubtitle.Text = T "mode.email.subtitle" }
        "phone" { $TxtModeTitle.Text = T "mode.phone.title"; $TxtModeSubtitle.Text = T "mode.phone.subtitle" }
        "sms"   { $TxtModeTitle.Text = T "mode.sms.title";   $TxtModeSubtitle.Text = T "mode.sms.subtitle" }
        "geo"   { $TxtModeTitle.Text = T "mode.geo.title";   $TxtModeSubtitle.Text = T "mode.geo.subtitle" }
    }
}

function Set-ApplicationLanguage {
    param(
        [string]$LanguageSetting,
        $AdditionalTarget = $null
    )

    $oldCountry = if ($Script:Translations.ContainsKey("defaults.country")) { T "defaults.country" } else { "" }
    $countryControl = Get-Variable -Name VCountry -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $countryWasDefault = $false
    if ($null -ne $countryControl) {
        $countryWasDefault = [string]::IsNullOrWhiteSpace($countryControl.Text) -or $countryControl.Text -eq $oldCountry -or $countryControl.Text -in @("Deutschland","Germany")
    }

    Load-Translations $LanguageSetting

    $mainWindow = Get-Variable -Name Window -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $mainWindow) { Apply-LanguageResources $mainWindow }
    if ($null -ne $AdditionalTarget) { Apply-LanguageResources $AdditionalTarget }

    if ($countryWasDefault -and $null -ne $countryControl) {
        $countryControl.Text = T "defaults.country"
    }

    if ($null -ne (Get-Variable -Name TxtModeTitle -Scope Script -ErrorAction SilentlyContinue)) {
        Update-ModeText
        Update-SettingsSummary
        Refresh-StatusLanguage
    }
}


function Get-OnlineProviderEndpoints {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("qrserver","custom")][string]$Provider
    )

    if ($Provider -eq "custom") {
        return [PSCustomObject]@{
            Provider = "custom"
            DisplayName = (T "provider.custom")
            CreateEndpoint = [string]$Script:Settings.CustomCreateEndpoint
            ReadEndpoint = [string]$Script:Settings.CustomReadEndpoint
        }
    }

    return [PSCustomObject]@{
        Provider = "qrserver"
        DisplayName = (T "provider.qrserver")
        CreateEndpoint = "https://api.qrserver.com/v1/create-qr-code/"
        ReadEndpoint = "https://api.qrserver.com/v1/read-qr-code/"
    }
}

function Show-SettingsDialog {
    $originalLanguageSetting = [string]$Script:Settings.Language

    [xml]$settingsXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="{DynamicResource settings.window.title}"
    Width="680"
    Height="720"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterOwner"
    Background="#07111E"
    Foreground="#F4F7FB"
    FontFamily="Segoe UI">

    <Window.Resources>
        <SolidColorBrush x:Key="CardBg" Color="#0C1C30"/>
        <SolidColorBrush x:Key="Border" Color="#243B56"/>
        <SolidColorBrush x:Key="InputBg" Color="#10243A"/>
        <SolidColorBrush x:Key="Muted" Color="#9CAEC3"/>
        <SolidColorBrush x:Key="Blue" Color="#0788FF"/>
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#F4F7FB"/></Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource InputBg}"/><Setter Property="Foreground" Value="#F4F7FB"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="10,7"/><Setter Property="FontSize" Value="14"/><Setter Property="MinHeight" Value="36"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#F5F7FA"/><Setter Property="Foreground" Value="#152033"/><Setter Property="BorderBrush" Value="#6B7C90"/><Setter Property="Padding" Value="8,6"/><Setter Property="FontSize" Value="14"/><Setter Property="MinHeight" Value="36"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#10243C"/><Setter Property="Foreground" Value="#F4F7FB"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="12,8"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Background" Value="#173252"/><Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#3A5F83"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.82"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
        </Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#F4F7FB"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
        <Style x:Key="SettingsCard" TargetType="Border"><Setter Property="Background" Value="{StaticResource CardBg}"/><Setter Property="BorderBrush" Value="{StaticResource Border}"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CornerRadius" Value="10"/><Setter Property="Padding" Value="16"/><Setter Property="Margin" Value="0,0,0,12"/></Style>
    </Window.Resources>

    <Grid Margin="24">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="18"/><RowDefinition Height="*"/><RowDefinition Height="16"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel>
            <TextBlock Text="{DynamicResource settings.window.title}" FontSize="24" FontWeight="SemiBold"/>
            <TextBlock Text="{DynamicResource settings.subtitle}" Foreground="{StaticResource Muted}" Margin="0,4,0,0"/>
        </StackPanel>

        <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Hidden" HorizontalScrollBarVisibility="Disabled" PanningMode="VerticalOnly">
            <StackPanel>
                <Border Style="{StaticResource SettingsCard}">
                    <StackPanel>
                        <TextBlock Text="{DynamicResource settings.general}" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,11"/>
                        <TextBlock Text="{DynamicResource settings.language}" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/>
                        <ComboBox x:Name="SettingsLanguage">
                            <ComboBoxItem Tag="auto" Content="{DynamicResource settings.language.auto}"/>
                            <ComboBoxItem Tag="de" Content="{DynamicResource settings.language.de}"/>
                            <ComboBoxItem Tag="en" Content="{DynamicResource settings.language.en}"/>
                        </ComboBox>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource SettingsCard}">
                    <StackPanel>
                        <TextBlock Text="{DynamicResource settings.storage}" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,11"/>
                        <TextBlock Text="{DynamicResource settings.output}" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/>
                        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="10"/><ColumnDefinition Width="100"/></Grid.ColumnDefinitions>
                            <TextBox x:Name="SettingsOutputDir"/><Button x:Name="SettingsBrowse" Grid.Column="2" Content="{DynamicResource settings.browse}"/>
                        </Grid>
                        <TextBlock Text="{DynamicResource settings.portableNote}" Foreground="{StaticResource Muted}" FontSize="12" TextWrapping="Wrap" Margin="0,8,0,0"/>
                        <CheckBox x:Name="SettingsOpenAfter" Content="{DynamicResource settings.openAfter}" Margin="0,12,0,0"/>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource SettingsCard}">
                    <StackPanel>
                        <TextBlock Text="{DynamicResource settings.qr}" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,11"/>
                        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <StackPanel><TextBlock Text="{DynamicResource settings.size}" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/><ComboBox x:Name="SettingsSize"><ComboBoxItem Content="400 px"/><ComboBoxItem Content="600 px"/><ComboBoxItem Content="800 px"/><ComboBoxItem Content="900 px"/><ComboBoxItem Content="1000 px"/></ComboBox></StackPanel>
                            <StackPanel Grid.Column="2"><TextBlock Text="{DynamicResource settings.ecc}" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/><ComboBox x:Name="SettingsEcc"><ComboBoxItem Content="L"/><ComboBoxItem Content="M"/><ComboBoxItem Content="Q"/><ComboBoxItem Content="H"/></ComboBox></StackPanel>
                        </Grid>
                        <CheckBox x:Name="SettingsReadTest" Content="{DynamicResource settings.readtest}" Margin="0,14,0,0"/>
                    </StackPanel>
                </Border>

                <Border Style="{StaticResource SettingsCard}">
                    <StackPanel>
                        <TextBlock Text="{DynamicResource settings.service}" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,11"/>
                        <TextBlock Text="{DynamicResource settings.provider}" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/>
                        <ComboBox x:Name="SettingsProvider">
                            <ComboBoxItem Tag="local" Content="{DynamicResource provider.local.full}"/>
                            <ComboBoxItem Tag="qrserver" Content="{DynamicResource provider.qrserver.full}"/>
                            <ComboBoxItem Tag="custom" Content="{DynamicResource provider.custom.full}"/>
                        </ComboBox>

                        <StackPanel x:Name="LocalProviderPanel" Margin="0,12,0,0" Visibility="Collapsed">
                            <TextBlock Text="{DynamicResource settings.localHelp}" Foreground="{StaticResource Muted}" TextWrapping="Wrap" FontSize="12"/>
                            <CheckBox x:Name="SettingsUseFallback" Content="{DynamicResource settings.useFallback}" Margin="0,12,0,0"/>
                            <TextBlock Text="{DynamicResource settings.fallbackProvider}" Foreground="{StaticResource Muted}" Margin="0,10,0,6"/>
                            <ComboBox x:Name="SettingsFallbackProvider">
                                <ComboBoxItem Tag="qrserver" Content="{DynamicResource provider.qrserver.full}"/>
                                <ComboBoxItem Tag="custom" Content="{DynamicResource provider.custom.full}"/>
                            </ComboBox>
                            <CheckBox x:Name="SettingsOnlineReadTestLocal" Content="{DynamicResource settings.onlineReadTestLocal}" Margin="0,12,0,0"/>
                            <TextBlock Text="{DynamicResource settings.onlineReadTestLocalHelp}" Foreground="{StaticResource Muted}" TextWrapping="Wrap" FontSize="12" Margin="0,6,0,0"/>
                        </StackPanel>

                        <StackPanel x:Name="CustomProviderPanel" Margin="0,12,0,0" Visibility="Collapsed">
                            <TextBlock Text="{DynamicResource settings.createEndpoint}" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/><TextBox x:Name="SettingsCreateEndpoint"/>
                            <TextBlock Text="{DynamicResource settings.readEndpoint}" Foreground="{StaticResource Muted}" Margin="0,11,0,6"/><TextBox x:Name="SettingsReadEndpoint"/>
                            <TextBlock Text="{DynamicResource settings.customHelp}" Foreground="{StaticResource Muted}" TextWrapping="Wrap" FontSize="12" Margin="0,9,0,0"/>
                        </StackPanel>

                        <TextBlock x:Name="LocalPrivacyNote" Text="{DynamicResource settings.localPrivacy}" Foreground="#62D9A6" TextWrapping="Wrap" FontSize="12" Margin="0,10,0,0" Visibility="Collapsed"/>
                        <TextBlock x:Name="ExternalPrivacyNote" Text="{DynamicResource settings.externalWarning}" Foreground="#F6C453" TextWrapping="Wrap" FontSize="12" Margin="0,10,0,0" Visibility="Collapsed"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>

        <Grid Grid.Row="4"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Button x:Name="SettingsReset" Grid.Column="0" Content="{DynamicResource common.defaults}" Width="110"/>
            <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="SettingsCancel" Content="{DynamicResource common.cancel}" Width="100" Margin="0,0,10,0"/><Button x:Name="SettingsSave" Content="{DynamicResource common.save}" Width="110" Background="{StaticResource Blue}" BorderBrush="{StaticResource Blue}"/></StackPanel>
        </Grid>
    </Grid>
</Window>
"@

    try {
        $reader = [System.Xml.XmlNodeReader]::new($settingsXaml)
        $dialog = [Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        Show-AppError ((T "error.settingsLoad") + "`r`n`r`n" + $_.Exception.Message)
        return
    }

    $dialog.Owner = $Window
    Apply-LanguageResources $dialog

    $languageBox = $dialog.FindName("SettingsLanguage")
    $output = $dialog.FindName("SettingsOutputDir")
    $browse = $dialog.FindName("SettingsBrowse")
    $openAfter = $dialog.FindName("SettingsOpenAfter")
    $sizeBox = $dialog.FindName("SettingsSize")
    $eccBox = $dialog.FindName("SettingsEcc")
    $readTest = $dialog.FindName("SettingsReadTest")
    $providerBox = $dialog.FindName("SettingsProvider")
    $localPanel = $dialog.FindName("LocalProviderPanel")
    $fallbackCheck = $dialog.FindName("SettingsUseFallback")
    $fallbackProviderBox = $dialog.FindName("SettingsFallbackProvider")
    $onlineReadTestLocal = $dialog.FindName("SettingsOnlineReadTestLocal")
    $customPanel = $dialog.FindName("CustomProviderPanel")
    $localPrivacyNote = $dialog.FindName("LocalPrivacyNote")
    $externalPrivacyNote = $dialog.FindName("ExternalPrivacyNote")
    $createEndpoint = $dialog.FindName("SettingsCreateEndpoint")
    $readEndpoint = $dialog.FindName("SettingsReadEndpoint")
    $reset = $dialog.FindName("SettingsReset")
    $cancel = $dialog.FindName("SettingsCancel")
    $save = $dialog.FindName("SettingsSave")

    $output.Text = $Script:OutputDir
    $openAfter.IsChecked = [bool]$Script:Settings.OpenAfterCreate
    $readTest.IsChecked = [bool]$Script:Settings.RunReadTest
    $fallbackCheck.IsChecked = [bool]$Script:Settings.UseOnlineFallback
    $onlineReadTestLocal.IsChecked = [bool]$Script:Settings.RunOnlineReadTestForLocal
    $createEndpoint.Text = [string]$Script:Settings.CustomCreateEndpoint
    $readEndpoint.Text = [string]$Script:Settings.CustomReadEndpoint

    foreach ($item in $languageBox.Items) { if ([string]$item.Tag -eq [string]$Script:Settings.Language) { $languageBox.SelectedItem = $item; break } }
    foreach ($item in $sizeBox.Items) { if ([string]$item.Content -eq ([string]$Script:Settings.QrSize + " px")) { $sizeBox.SelectedItem = $item; break } }
    foreach ($item in $eccBox.Items) { if ([string]$item.Content -eq [string]$Script:Settings.Ecc) { $eccBox.SelectedItem = $item; break } }
    foreach ($item in $providerBox.Items) { if ([string]$item.Tag -eq [string]$Script:Settings.Provider) { $providerBox.SelectedItem = $item; break } }
    foreach ($item in $fallbackProviderBox.Items) { if ([string]$item.Tag -eq [string]$Script:Settings.FallbackProvider) { $fallbackProviderBox.SelectedItem = $item; break } }
    if ($null -eq $languageBox.SelectedItem) { $languageBox.SelectedIndex = 0 }
    if ($null -eq $sizeBox.SelectedItem) { $sizeBox.SelectedIndex = 4 }
    if ($null -eq $eccBox.SelectedItem) { $eccBox.SelectedIndex = 3 }
    if ($null -eq $providerBox.SelectedItem) { $providerBox.SelectedIndex = 0 }
    if ($null -eq $fallbackProviderBox.SelectedItem) { $fallbackProviderBox.SelectedIndex = 0 }

    $updateProviderPanel = {
        $providerTag = if ($null -ne $providerBox.SelectedItem) { [string]$providerBox.SelectedItem.Tag } else { "local" }
        $fallbackTag = if ($null -ne $fallbackProviderBox.SelectedItem) { [string]$fallbackProviderBox.SelectedItem.Tag } else { "qrserver" }
        $isLocal = $providerTag -eq "local"
        $fallbackEnabled = [bool]$fallbackCheck.IsChecked
        $onlineLocalReadEnabled = [bool]$readTest.IsChecked -and [bool]$onlineReadTestLocal.IsChecked

        $localPanel.Visibility = if ($isLocal) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $localPrivacyNote.Visibility = if ($isLocal) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $externalPrivacyNote.Visibility = if ($isLocal) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }

        $fallbackProviderBox.IsEnabled = $fallbackEnabled
        $onlineReadTestLocal.IsEnabled = [bool]$readTest.IsChecked

        $customNeeded =
            $providerTag -eq "custom" -or
            ($isLocal -and $fallbackTag -eq "custom" -and ($fallbackEnabled -or $onlineLocalReadEnabled))

        $customPanel.Visibility = if ($customNeeded) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
    $providerBox.Add_SelectionChanged($updateProviderPanel)
    $fallbackProviderBox.Add_SelectionChanged($updateProviderPanel)
    $fallbackCheck.Add_Click($updateProviderPanel)
    $onlineReadTestLocal.Add_Click($updateProviderPanel)
    $readTest.Add_Click($updateProviderPanel)
    & $updateProviderPanel

    $languageBox.Add_SelectionChanged({
        if ($null -ne $languageBox.SelectedItem) {
            Set-ApplicationLanguage -LanguageSetting ([string]$languageBox.SelectedItem.Tag) -AdditionalTarget $dialog
        }
    })

    $browse.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = T "dialog.folder.description"
        if (Test-Path -LiteralPath $output.Text) { $folderDialog.SelectedPath = $output.Text }
        if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $output.Text = $folderDialog.SelectedPath }
    })

    $reset.Add_Click({
        $output.Text = $Script:DefaultOutputDir
        $openAfter.IsChecked = $false
        $sizeBox.SelectedIndex = 4
        $eccBox.SelectedIndex = 3
        $readTest.IsChecked = $true
        $onlineReadTestLocal.IsChecked = $false
        $providerBox.SelectedIndex = 0
        $fallbackCheck.IsChecked = $true
        $fallbackProviderBox.SelectedIndex = 0
        $languageBox.SelectedIndex = 0
        $createEndpoint.Text = "https://api.qrserver.com/v1/create-qr-code/"
        $readEndpoint.Text = "https://api.qrserver.com/v1/read-qr-code/"
        & $updateProviderPanel
    })

    $cancel.Add_Click({
        Set-ApplicationLanguage -LanguageSetting $originalLanguageSetting
        $dialog.DialogResult = $false
        $dialog.Close()
    })

    $save.Add_Click({
        if ([string]::IsNullOrWhiteSpace($output.Text)) { Show-AppError (T "error.outputRequired"); return }
        if (-not (Test-Path -LiteralPath $output.Text)) {
            try { New-Item -ItemType Directory -Path $output.Text -Force | Out-Null }
            catch { Show-AppError ((T "error.outputCreate") + "`r`n`r`n" + $_.Exception.Message); return }
        }

        $provider = [string]$providerBox.SelectedItem.Tag
        $fallbackProvider = [string]$fallbackProviderBox.SelectedItem.Tag
        $fallbackEnabled = [bool]$fallbackCheck.IsChecked
        $onlineLocalReadEnabled = [bool]$readTest.IsChecked -and [bool]$onlineReadTestLocal.IsChecked

        $customNeeded =
            $provider -eq "custom" -or
            ($provider -eq "local" -and $fallbackProvider -eq "custom" -and ($fallbackEnabled -or $onlineLocalReadEnabled))

        if ($customNeeded) {
            $createUri = $null; $readUri = $null
            if (($provider -eq "custom" -or $fallbackEnabled) -and ([string]::IsNullOrWhiteSpace($createEndpoint.Text) -or -not [Uri]::TryCreate($createEndpoint.Text.Trim(), [UriKind]::Absolute, [ref]$createUri))) { Show-AppError (T "error.createEndpoint"); return }
            if ([bool]$readTest.IsChecked -and ([string]::IsNullOrWhiteSpace($readEndpoint.Text) -or -not [Uri]::TryCreate($readEndpoint.Text.Trim(), [UriKind]::Absolute, [ref]$readUri))) { Show-AppError (T "error.readEndpoint"); return }
        }

        $sizeText = [string]$sizeBox.SelectedItem.Content
        $Script:Settings.Language = [string]$languageBox.SelectedItem.Tag
        $Script:Settings.OutputDir = Convert-ToPortableStoredPath $output.Text.Trim()
        $Script:Settings.QrSize = [int](($sizeText -replace '[^\d]', ''))
        $Script:Settings.Ecc = [string]$eccBox.SelectedItem.Content
        $Script:Settings.RunReadTest = [bool]$readTest.IsChecked
        $Script:Settings.RunOnlineReadTestForLocal = [bool]$onlineReadTestLocal.IsChecked
        $Script:Settings.OpenAfterCreate = [bool]$openAfter.IsChecked
        $Script:Settings.Provider = $provider
        $Script:Settings.UseOnlineFallback = $fallbackEnabled
        $Script:Settings.FallbackProvider = $fallbackProvider
        $Script:Settings.CustomCreateEndpoint = $createEndpoint.Text.Trim()
        $Script:Settings.CustomReadEndpoint = $readEndpoint.Text.Trim()
        $Script:OutputDir = Resolve-PortablePath $Script:Settings.OutputDir

        try { Save-AppSettings }
        catch { Show-AppError ((T "error.settingsSave") + "`r`n`r`n" + $_.Exception.Message); return }

        Write-DebugLog "Settings" ("Saved | Provider={0}; Fallback={1}; FallbackProvider={2}; ReadTest={3}; OnlineReadForLocal={4}" -f `
            $Script:Settings.Provider,
            $Script:Settings.UseOnlineFallback,
            $Script:Settings.FallbackProvider,
            $Script:Settings.RunReadTest,
            $Script:Settings.RunOnlineReadTestForLocal)

        Set-ApplicationLanguage -LanguageSetting $Script:Settings.Language -AdditionalTarget $dialog
        Update-SettingsSummary
        $dialog.DialogResult = $true
        $dialog.Close()
    })

    [void]$dialog.ShowDialog()
}

function Show-AppError {
    param([string]$Message)
    [System.Windows.MessageBox]::Show(
        $Message,
        (T "dialog.error.title"),
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
}

function Show-AppInfo {
    param([string]$Message)
    [System.Windows.MessageBox]::Show(
        $Message,
        (T "ui.app.title"),
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    ) | Out-Null
}

function Show-AppYesNoWarning {
    param(
        [string]$Message,
        [string]$Title = $null
    )

    if ([string]::IsNullOrWhiteSpace($Title)) {
        $Title = T "ui.app.title"
    }

    return [System.Windows.MessageBox]::Show(
        $Window,
        $Message,
        $Title,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::Yes
    )
}

function Set-Status {
    param(
        [string]$Text,
        [ValidateSet("Normal","Ok","Warn","Error")]
        [string]$Mode = "Normal"
    )

    $StatusText.Text = $Text

    switch ($Mode) {
        "Ok"    { $StatusDot.Fill = [System.Windows.Media.Brushes]::LimeGreen }
        "Warn"  { $StatusDot.Fill = [System.Windows.Media.Brushes]::Goldenrod }
        "Error" { $StatusDot.Fill = [System.Windows.Media.Brushes]::Tomato }
        default { $StatusDot.Fill = [System.Windows.Media.Brushes]::DodgerBlue }
    }

    $Window.Dispatcher.Invoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [action]{}
    )
}

function Set-StatusKey {
    param(
        [string]$Key,
        [ValidateSet("Normal","Ok","Warn","Error")][string]$Mode = "Normal",
        [hashtable]$Tokens = $null
    )
    $Script:CurrentStatusKey = $Key
    $Script:CurrentStatusMode = $Mode
    $Script:CurrentStatusTokens = if ($null -eq $Tokens) { @{} } else { $Tokens }
    Set-Status (T $Key $Script:CurrentStatusTokens) $Mode
}

function Refresh-StatusLanguage {
    if (-not [string]::IsNullOrWhiteSpace($Script:CurrentStatusKey)) {
        Set-Status (T $Script:CurrentStatusKey $Script:CurrentStatusTokens) $Script:CurrentStatusMode
    }
}

function Get-ComboTag {
    param($Combo)
    if ($null -eq $Combo.SelectedItem) { return "" }
    if ($Combo.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) { return [string]$Combo.SelectedItem.Tag }
    return ""
}

function Get-ComboText {
    param($Combo)

    if ($null -eq $Combo.SelectedItem) {
        return ""
    }

    if ($Combo.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) {
        return [string]$Combo.SelectedItem.Content
    }

    return [string]$Combo.SelectedItem
}

function Update-Footer {
    Update-SettingsSummary
}

function Set-NavActive {
    param($ActiveButton)

    foreach ($button in $NavButtons) {
        $button.Background = [System.Windows.Media.Brushes]::Transparent
        $button.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        $button.FontWeight = [System.Windows.FontWeights]::Normal
    }

    $ActiveButton.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(11, 75, 132)
    )
    $ActiveButton.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(7, 136, 255)
    )
    $ActiveButton.FontWeight = [System.Windows.FontWeights]::SemiBold
}

function Set-Mode {
    param(
        [string]$Mode,
        $Button
    )

    $Script:Mode = $Mode

    foreach ($panel in $ModePanels.Values) {
        $panel.Visibility = [System.Windows.Visibility]::Collapsed
    }

    switch ($Mode) {
        "vCard" {
            $PanelVCard.Visibility = [System.Windows.Visibility]::Visible
            
        }
        "url" {
            $PanelUrl.Visibility = [System.Windows.Visibility]::Visible
            
        }
        "wifi" {
            $PanelWifi.Visibility = [System.Windows.Visibility]::Visible
            
        }
        "text" {
            $PanelText.Visibility = [System.Windows.Visibility]::Visible
            
        }
        "email" {
            $PanelEmail.Visibility = [System.Windows.Visibility]::Visible
            
        }
        "phone" {
            $PanelPhone.Visibility = [System.Windows.Visibility]::Visible
            
        }
        "sms" {
            $PanelSms.Visibility = [System.Windows.Visibility]::Visible
            
        }
        "geo" {
            $PanelGeo.Visibility = [System.Windows.Visibility]::Visible
            
        }
    }

    Update-ModeText
    Set-NavActive $Button
    Update-Footer
}

function Build-VCardPayload {
    $vorname = $VFirst.Text.Trim()
    $nachname = $VLast.Text.Trim()
    $firma = $VCompany.Text.Trim()

    if (
        [string]::IsNullOrWhiteSpace($vorname) -and
        [string]::IsNullOrWhiteSpace($nachname) -and
        [string]::IsNullOrWhiteSpace($firma)
    ) {
        throw (T "error.vcardRequired")
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("BEGIN:VCARD")
    $lines.Add("VERSION:3.0")
    $lines.Add("N:" + (Escape-VCardText $nachname) + ";" + (Escape-VCardText $vorname) + ";;;")

    $displayName = ($vorname + " " + $nachname).Trim()
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = $firma
    }
    $lines.Add("FN:" + (Escape-VCardText $displayName))

    if (-not [string]::IsNullOrWhiteSpace($firma)) {
        $lines.Add("ORG:" + (Escape-VCardText $firma))
    }
    if (-not [string]::IsNullOrWhiteSpace($VTitle.Text)) {
        $lines.Add("TITLE:" + (Escape-VCardText $VTitle.Text.Trim()))
    }
    if (-not [string]::IsNullOrWhiteSpace($VMobile.Text)) {
        $lines.Add("TEL;TYPE=CELL:" + (Escape-VCardText $VMobile.Text.Trim()))
    }
    if (-not [string]::IsNullOrWhiteSpace($VPhone.Text)) {
        $lines.Add("TEL;TYPE=WORK,VOICE:" + (Escape-VCardText $VPhone.Text.Trim()))
    }
    if (-not [string]::IsNullOrWhiteSpace($VEmail.Text)) {
        $lines.Add("EMAIL;TYPE=INTERNET:" + (Escape-VCardText $VEmail.Text.Trim()))
    }
    if (-not [string]::IsNullOrWhiteSpace($VWeb.Text)) {
        $web = $VWeb.Text.Trim()
        if ($web -notmatch '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
            $web = "https://" + $web
        }
        $lines.Add("URL:" + $web)
    }

    $hasAddress =
        -not [string]::IsNullOrWhiteSpace($VStreet.Text) -or
        -not [string]::IsNullOrWhiteSpace($VCity.Text) -or
        -not [string]::IsNullOrWhiteSpace($VRegion.Text) -or
        -not [string]::IsNullOrWhiteSpace($VZip.Text) -or
        -not [string]::IsNullOrWhiteSpace($VCountry.Text)

    if ($hasAddress) {
        $lines.Add(
            "ADR;TYPE=WORK:;;" +
            (Escape-VCardText $VStreet.Text.Trim()) + ";" +
            (Escape-VCardText $VCity.Text.Trim()) + ";" +
            (Escape-VCardText $VRegion.Text.Trim()) + ";" +
            (Escape-VCardText $VZip.Text.Trim()) + ";" +
            (Escape-VCardText $VCountry.Text.Trim())
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($VNote.Text)) {
        $lines.Add("NOTE:" + (Escape-VCardText $VNote.Text.Trim()))
    }

    $lines.Add("END:VCARD")
    $vcard = [string]::Join("`r`n", $lines) + "`r`n"

    $name = if (-not [string]::IsNullOrWhiteSpace($firma)) {
        $firma + (T "filename.contactSuffix")
    }
    else {
        $displayName + (T "filename.contactSuffix")
    }

    return [PSCustomObject]@{
        Data = $vcard
        VCard = $vcard
        DefaultName = Get-SafeFileName $name
    }
}

function Build-Payload {
    switch ($Script:Mode) {
        "vCard" {
            return Build-VCardPayload
        }

        "url" {
            $url = $UrlValue.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($url) -or $url -eq "https://") {
                throw (T "error.urlRequired")
            }
            if ($url -notmatch '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
                $url = "https://" + $url
            }
            return [PSCustomObject]@{
                Data = $url
                VCard = $null
                DefaultName = T "filename.website"
            }
        }

        "wifi" {
            $ssid = $WifiSsid.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($ssid)) {
                throw (T "error.wifiRequired")
            }

            $typeText = Get-ComboTag $WifiType
            $hidden = if ($WifiHidden.IsChecked) { "true" } else { "false" }
            $ssidEsc = Escape-WifiText $ssid
            $passEsc = Escape-WifiText $WifiPassword.Text

            if ($typeText -eq "open") {
                $data = "WIFI:T:nopass;S:" + $ssidEsc + ";H:" + $hidden + ";;"
            }
            elseif ($typeText -eq "wep") {
                $data = "WIFI:T:WEP;S:" + $ssidEsc + ";P:" + $passEsc + ";H:" + $hidden + ";;"
            }
            else {
                $data = "WIFI:T:WPA;S:" + $ssidEsc + ";P:" + $passEsc + ";H:" + $hidden + ";;"
            }

            return [PSCustomObject]@{
                Data = $data
                VCard = $null
                DefaultName = Get-SafeFileName ($ssid + (T "filename.wifiSuffix"))
            }
        }

        "text" {
            if ([string]::IsNullOrWhiteSpace($FreeText.Text)) {
                throw (T "error.textRequired")
            }
            return [PSCustomObject]@{
                Data = $FreeText.Text
                VCard = $null
                DefaultName = T "filename.text"
            }
        }

        "email" {
            $email = $MailTo.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($email)) {
                throw (T "error.emailRequired")
            }

            $data = "mailto:" + $email
            $query = [System.Collections.Generic.List[string]]::new()

            if (-not [string]::IsNullOrWhiteSpace($MailSubject.Text)) {
                $query.Add("subject=" + [uri]::EscapeDataString($MailSubject.Text))
            }
            if (-not [string]::IsNullOrWhiteSpace($MailBody.Text)) {
                $query.Add("body=" + [uri]::EscapeDataString($MailBody.Text))
            }
            if ($query.Count -gt 0) {
                $data += "?" + [string]::Join("&", $query)
            }

            return [PSCustomObject]@{
                Data = $data
                VCard = $null
                DefaultName = T "filename.email"
            }
        }

        "phone" {
            $number = $PhoneValue.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($number)) {
                throw (T "error.phoneRequired")
            }

            return [PSCustomObject]@{
                Data = "tel:" + $number
                VCard = $null
                DefaultName = T "filename.phone"
            }
        }

        "sms" {
            $number = $SmsNumber.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($number)) {
                throw (T "error.phoneRequired")
            }

            return [PSCustomObject]@{
                Data = "SMSTO:" + $number + ":" + $SmsText.Text
                VCard = $null
                DefaultName = T "filename.sms"
            }
        }

        "geo" {
            $lat = $GeoLat.Text.Trim().Replace(",", ".")
            $lon = $GeoLon.Text.Trim().Replace(",", ".")

            if ($lat -notmatch '^-?\d+(\.\d+)?$' -or $lon -notmatch '^-?\d+(\.\d+)?$') {
                throw (T "error.geoInvalid")
            }

            return [PSCustomObject]@{
                Data = "geo:" + $lat + "," + $lon
                VCard = $null
                DefaultName = T "filename.geo"
            }
        }
    }
}

function Clear-Inputs {
    $fields = @(
        $VFirst,$VLast,$VCompany,$VTitle,$VMobile,$VPhone,$VEmail,$VWeb,
        $VStreet,$VZip,$VCity,$VRegion,$VNote,
        $WifiSsid,$WifiPassword,$FreeText,$MailTo,$MailSubject,$MailBody,
        $PhoneValue,$SmsNumber,$SmsText,$GeoLat,$GeoLon
    )

    foreach ($field in $fields) {
        $field.Clear()
    }

    $VCountry.Text = T "defaults.country"
    $UrlValue.Text = "https://"
    $WifiType.SelectedIndex = 0
    $WifiHidden.IsChecked = $false

    if ($null -ne $QrPreview.Source) {
        $QrPreview.Source = $null
    }

    $Script:GeneratedQrPath = $null
    $Script:GeneratedQrData = $null
    if ($null -ne $BtnVerifyQr) { $BtnVerifyQr.IsEnabled = $false }
    Set-StatusKey "status.ready" "Normal"
}

function Update-LogoPreview {
    if (
        -not [string]::IsNullOrWhiteSpace($Script:LogoPath) -and
        (Test-Path -LiteralPath $Script:LogoPath)
    ) {
        $LogoPreview.Source = New-WpfBitmapImage $Script:LogoPath
        $LogoEmptyText.Visibility = [System.Windows.Visibility]::Collapsed
        $UseLogo.IsChecked = $true
    }
    else {
        $LogoPreview.Source = $null
        $LogoEmptyText.Visibility = [System.Windows.Visibility]::Visible
        $UseLogo.IsChecked = $false
    }
}

# Load XAML
[xml]$Xaml = Get-Content -LiteralPath $XamlFile -Raw -Encoding UTF8
$Reader = [System.Xml.XmlNodeReader]::new($Xaml)
$Window = [Windows.Markup.XamlReader]::Load($Reader)

# Named controls
$names = @(
    "BtnNew","BtnOpenFolderTop","BtnSettings","BtnInfo",
    "NavVCard","NavUrl","NavWifi","NavText","NavEmail","NavPhone","NavSms","NavGeo",
    "TxtModeTitle","TxtModeSubtitle",
    "PanelVCard","PanelUrl","PanelWifi","PanelText","PanelEmail","PanelPhone","PanelSms","PanelGeo",
    "VFirst","VLast","VCompany","VTitle","VMobile","VPhone","VEmail","VWeb",
    "VStreet","VZip","VCity","VRegion","VCountry","VNote",
    "UrlValue","WifiSsid","WifiPassword","WifiType","WifiHidden","WifiNotice",
    "FreeText","MailTo","MailSubject","MailBody","PhoneValue","SmsNumber","SmsText","GeoLat","GeoLon",
    "QrPreview","UseLogo","LogoSize","LogoSizeText","LogoPreview","LogoEmptyText",
    "BtnChooseLogo","BtnRemoveLogo","SummarySize","SummaryEcc","SummaryReadTest","SummaryProvider","BtnSettingsRight","BtnGenerate","BtnVerifyQr","BtnOpenQr","BtnOpenFolder",
    "StatusDot","StatusText","FooterSize","FooterEcc","FooterSavePath"
)

foreach ($name in $names) {
    Set-Variable -Name $name -Value $Window.FindName($name) -Scope Script
}

$NavButtons = @($NavVCard,$NavUrl,$NavWifi,$NavText,$NavEmail,$NavPhone,$NavSms,$NavGeo)
$ModePanels = @{
    vCard = $PanelVCard
    url = $PanelUrl
    wifi = $PanelWifi
    text = $PanelText
    email = $PanelEmail
    phone = $PanelPhone
    sms = $PanelSms
    geo = $PanelGeo
}

# App icon
if (Test-Path -LiteralPath $IconFile) {
    try {
        $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($IconFile))
    }
    catch {
        # Non-fatal: the GUI still works without a window icon.
    }
}

# Nav events
$NavVCard.Add_Click({ Set-Mode "vCard" $NavVCard })
$NavUrl.Add_Click({ Set-Mode "url" $NavUrl })
$NavWifi.Add_Click({ Set-Mode "wifi" $NavWifi })
$NavText.Add_Click({ Set-Mode "text" $NavText })
$NavEmail.Add_Click({ Set-Mode "email" $NavEmail })
$NavPhone.Add_Click({ Set-Mode "phone" $NavPhone })
$NavSms.Add_Click({ Set-Mode "sms" $NavSms })
$NavGeo.Add_Click({ Set-Mode "geo" $NavGeo })

$LogoSize.Add_ValueChanged({
    $LogoSizeText.Text = [Math]::Round($LogoSize.Value).ToString() + " %"
})

$BtnChooseLogo.Add_Click({
    $dlg = [Microsoft.Win32.OpenFileDialog]::new()
    $dlg.Title = T "dialog.logo.title"
    $dlg.Filter = T "dialog.logo.filter"

    if ($dlg.ShowDialog($Window)) {
        $Script:LogoPath = $dlg.FileName
        Update-LogoPreview
    }
})

$BtnRemoveLogo.Add_Click({
    $Script:LogoPath = $null
    Update-LogoPreview
})

$BtnNew.Add_Click({
    Clear-Inputs
})

$BtnSettings.Add_Click({
    Show-SettingsDialog
})

$BtnSettingsRight.Add_Click({
    Show-SettingsDialog
})

$BtnInfo.Add_Click({
    Show-AppInfo (T "info.about")
})

$BtnOpenFolderTop.Add_Click({
    if (-not (Test-Path -LiteralPath $Script:OutputDir)) {
        New-Item -ItemType Directory -Path $Script:OutputDir -Force | Out-Null
    }
    Start-Process explorer.exe $Script:OutputDir
})

$BtnOpenFolder.Add_Click({
    if (-not (Test-Path -LiteralPath $Script:OutputDir)) {
        New-Item -ItemType Directory -Path $Script:OutputDir -Force | Out-Null
    }
    Start-Process explorer.exe $Script:OutputDir
})

$BtnOpenQr.Add_Click({
    if (
        -not [string]::IsNullOrWhiteSpace($Script:GeneratedQrPath) -and
        (Test-Path -LiteralPath $Script:GeneratedQrPath)
    ) {
        Start-Process $Script:GeneratedQrPath
    }
    else {
        Show-AppInfo (T "info.noQr")
    }
})

$BtnVerifyQr.Add_Click({
    $canTest = (
        -not [string]::IsNullOrWhiteSpace($Script:GeneratedQrPath) -and
        (Test-Path -LiteralPath $Script:GeneratedQrPath) -and
        -not [string]::IsNullOrWhiteSpace($Script:GeneratedQrData)
    )

    if (-not $canTest) {
        Show-AppInfo (T "info.noQr")
        return
    }

    $BtnVerifyQr.IsEnabled = $false
    try {
        $testProvider = if ([string]$Script:Settings.Provider -eq "local") {
            [string]$Script:Settings.FallbackProvider
        }
        else {
            [string]$Script:Settings.Provider
        }

        $testEndpoints = Get-OnlineProviderEndpoints -Provider $testProvider
        Set-StatusKey "status.manualTesting" "Normal" @{ provider = $testEndpoints.DisplayName }
        Write-DebugLog "Manual read test" ("Starting online verification via {0}" -f $testEndpoints.DisplayName)

        $test = Test-QrViaApi `
            -QrPath $Script:GeneratedQrPath `
            -ExpectedData $Script:GeneratedQrData `
            -ReadEndpoint $testEndpoints.ReadEndpoint `
            -TempDir $Script:TempDir

        if ($test.Success -and $test.Exact) {
            Write-DebugLog "Manual read test" "PASS | Exact payload match" "Ok"
            Set-StatusKey "status.manualVerified" "Ok"
            Show-AppInfo (T "info.manualReadSuccess")
        }
        elseif ($test.Success -and [bool]$test.Equivalent) {
            Write-DebugLog "Manual read test" ("PASS [{0}] | {1}" -f $test.MismatchCategory, $test.MismatchSummary) "Ok"
            Write-DebugLog "Comparison" ("ExpectedChars={0}; DecodedChars={1}; no payload text logged" -f $test.ExpectedLength, $test.DecodedLength)
            Set-StatusKey "status.manualVerified" "Ok"
            Show-AppInfo (T "info.manualReadSuccess")
        }
        elseif ($test.Success -and [string]$test.MismatchCategory -eq "CharsetAmbiguity") {
            Write-DebugLog "Manual read test" ("WARNING [CharsetAmbiguity] | " + $test.MismatchSummary) "Warn"
            Write-DebugLog "Comparison" ("ExpectedChars={0}; DecodedChars={1}; FirstDifferenceIndex={2}; Expected={3}; Decoded={4}; no payload text logged" -f $test.ExpectedLength, $test.DecodedLength, $test.FirstDifferenceIndex, $test.ExpectedCodePoint, $test.DecodedCodePoint) "Warn"
            Write-DebugLog "What to do" "The QR image is not necessarily defective. For Unicode content, prefer the local QR engine or verify the code with the target phone/scanner." "Warn"
            Set-StatusKey "status.manualCharsetWarning" "Warn"
            Show-AppInfo (T "info.charsetAmbiguity")
        }
        elseif ($test.Success -and -not $test.Exact) {
            Write-DebugLog "Manual read test" ("MISMATCH [{0}] | {1}" -f $test.MismatchCategory, $test.MismatchSummary) "Warn"
            Write-DebugLog "Comparison" ("ExpectedChars={0}; DecodedChars={1}; FirstDifferenceIndex={2}; Expected={3}; Decoded={4}; no payload text logged" -f $test.ExpectedLength, $test.DecodedLength, $test.FirstDifferenceIndex, $test.ExpectedCodePoint, $test.DecodedCodePoint) "Warn"
            Set-StatusKey "status.manualMismatch" "Warn"
            Show-AppInfo (T "info.manualReadMismatch")
        }
        elseif ([string]$test.ErrorType -eq "Transport") {
            $diag = Get-ErrorDiagnostic $test.Exception
            Write-DebugLog "Manual read test" ("UNAVAILABLE [{0}] | {1}" -f $diag.Category, $diag.Summary) "Warn"
            Write-DebugLog "What to do" $diag.Advice "Warn"
            Write-DebugLog "Technical" $diag.Technical "Error"
            Set-StatusKey "status.manualUnavailable" "Warn"
            Show-AppInfo (T "info.readUnavailable" @{ reason = $diag.Summary; advice = $diag.Advice })
        }
        else {
            Write-DebugLog "Manual read test" ("DECODE FAILED | " + [string]$test.Error) "Warn"
            Set-StatusKey "status.manualFailed" "Warn"
            Show-AppInfo (T "info.manualReadFailed" @{ error = [string]$test.Error })
        }
    }
    catch {
        $diag = Write-DebugException "Manual read test" $_
        Set-StatusKey "status.manualUnavailable" "Warn"
        Show-AppInfo (T "info.readUnavailable" @{ reason = $diag.Summary; advice = $diag.Advice })
    }
    finally {
        $BtnVerifyQr.IsEnabled = (
            -not [string]::IsNullOrWhiteSpace($Script:GeneratedQrPath) -and
            (Test-Path -LiteralPath $Script:GeneratedQrPath) -and
            -not [string]::IsNullOrWhiteSpace($Script:GeneratedQrData)
        )
    }
})

$BtnGenerate.Add_Click({
    try {
        $BtnGenerate.IsEnabled = $false
        Set-StatusKey "status.preparing"

        $payload = Build-Payload
        $size = [int]$Script:Settings.QrSize
        $ecc = [string]$Script:Settings.Ecc

        # The configured provider remains unchanged. For a payload containing
        # non-ASCII / Unicode characters, an online provider can optionally be
        # replaced by a local-first attempt for this generation only.
        $configuredProvider = [string]$Script:Settings.Provider
        $provider = $configuredProvider
        $generationUseOnlineFallback = [bool]$Script:Settings.UseOnlineFallback
        $generationFallbackProvider = [string]$Script:Settings.FallbackProvider
        $unicodeLocalFirst = $false

        if ($provider -ne "local" -and ([string]$payload.Data -match '[^\x00-\x7F]')) {
            $currentOnline = Get-OnlineProviderEndpoints -Provider $provider
            Write-DebugLog "Unicode guard" ("Non-ASCII payload detected | ConfiguredProvider={0}; PayloadLength={1}; no payload text logged" -f $currentOnline.DisplayName, $payload.Data.Length) "Warn"

            $answer = Show-AppYesNoWarning `
                -Title (T "unicodeGuard.title") `
                -Message (T "unicodeGuard.message" @{ provider = $currentOnline.DisplayName })

            if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
                # The user explicitly selected local-first for this generation.
                # If local generation fails, fall back to the provider that was
                # originally selected for direct online generation. Settings are
                # NOT changed or persisted by this one-time choice.
                $unicodeLocalFirst = $true
                $provider = "local"
                $generationUseOnlineFallback = $true
                $generationFallbackProvider = $configuredProvider
                Write-DebugLog "Unicode guard" ("User selected LOCAL-FIRST | Online fallback={0}; setting unchanged" -f $currentOnline.DisplayName) "Ok"
            }
            else {
                Write-DebugLog "Unicode guard" ("User kept DIRECT ONLINE generation via {0}; setting unchanged" -f $currentOnline.DisplayName) "Warn"
            }
        }

        $useLogoNow =
            [bool]$UseLogo.IsChecked -and
            -not [string]::IsNullOrWhiteSpace($Script:LogoPath) -and
            (Test-Path -LiteralPath $Script:LogoPath)

        if ($useLogoNow -and $ecc -ne "H") {
            Write-DebugLog "ECC" ("Logo enabled: overriding configured ECC {0} -> H" -f $ecc) "Warn"
            $ecc = "H"
        }

        $providerDebug = if ($unicodeLocalFirst) {
            "{0} (configured={1}; UnicodeGuard=LocalFirst; fallback={2})" -f $provider, $configuredProvider, $generationFallbackProvider
        }
        else {
            $provider
        }

        Write-DebugLog "Generate" ("Mode={0}; Provider={1}; Size={2}px; ECC={3}; Logo={4}; PayloadLength={5}" -f `
            $Script:Mode, $providerDebug, $size, $ecc, $useLogoNow, $payload.Data.Length)

        $dlg = [Microsoft.Win32.SaveFileDialog]::new()
        $dlg.Title = T "dialog.save.title"
        $dlg.Filter = T "dialog.save.filter"
        $dlg.DefaultExt = ".png"
        $dlg.AddExtension = $true
        $dlg.InitialDirectory = $Script:OutputDir
        $dlg.FileName = $payload.DefaultName + ".png"

        if (-not $dlg.ShowDialog($Window)) {
            Write-DebugLog "Generate" "Cancelled by user" "Warn"
            Set-StatusKey "status.cancelled" "Normal"
            return
        }

        # A confirmed new generation attempt invalidates the previous QR result.
        # This prevents the manual verification button from accidentally testing
        # an older QR after the new generation attempt fails.
        $BtnVerifyQr.IsEnabled = $false
        $Script:GeneratedQrPath = $null
        $Script:GeneratedQrData = $null
        $QrPreview.Source = $null
        $QrPreview.UpdateLayout()

        $pngPath = $dlg.FileName
        $Script:OutputDir = Split-Path -Parent $pngPath
        Write-DebugLog "Output" $pngPath

        $usedFallback = $false
        $localGenerationSucceeded = $false
        $onlineEndpoints = $null

        if ($provider -eq "local") {
            Set-StatusKey "status.generatingLocal"
            Write-DebugLog "Local engine" "Starting local QR generation"

            try {
                $localResult = New-QrPngLocal -Data $payload.Data -OutputPath $pngPath -Size $size -Ecc $ecc
                $localGenerationSucceeded = $true
                Write-DebugLog "Local engine" ("SUCCESS | Version={0}; Mask={1}; Modules={2}; ECC={3}" -f `
                    $localResult.Version, $localResult.Mask, $localResult.ModuleCount, $localResult.Ecc) "Ok"
            }
            catch {
                $localError = $_.Exception.Message
                $localDiag = Get-ErrorDiagnostic $_
                Write-DebugLog "Local engine" ("FAILED [{0}] | {1}" -f $localDiag.Category, $localDiag.Summary) "Warn"
                Write-DebugLog "What to do" $localDiag.Advice "Warn"
                Write-DebugLog "Technical" $localDiag.Technical "Error"

                if (-not $generationUseOnlineFallback) {
                    Write-DebugLog "Fallback" "Disabled - generation stops" "Error"
                    throw (T "error.localGeneration" @{ error = $localError })
                }

                $fallbackProvider = $generationFallbackProvider
                $onlineEndpoints = Get-OnlineProviderEndpoints -Provider $fallbackProvider
                Set-StatusKey "status.fallback" "Warn" @{ provider = $onlineEndpoints.DisplayName }
                Write-DebugLog "Fallback" ("Starting online fallback via {0}" -f $onlineEndpoints.DisplayName) "Warn"

                try {
                    New-QrPngViaApi `
                        -Data $payload.Data `
                        -OutputPath $pngPath `
                        -Size $size `
                        -Ecc $ecc `
                        -CreateEndpoint $onlineEndpoints.CreateEndpoint

                    $usedFallback = $true
                    Write-DebugLog "Fallback" ("SUCCESS via {0}" -f $onlineEndpoints.DisplayName) "Ok"
                }
                catch {
                    $fallbackError = $_.Exception.Message
                    $fallbackDiag = Write-DebugException "Fallback" $_
                    throw (T "error.localAndFallback" @{
                        local = $localError
                        online = $fallbackError
                    })
                }
            }
        }
        else {
            $onlineEndpoints = Get-OnlineProviderEndpoints -Provider $provider
            Set-StatusKey "status.generatingOnline" "Normal" @{ provider = $onlineEndpoints.DisplayName }
            Write-DebugLog "Online provider" ("Starting generation via {0}" -f $onlineEndpoints.DisplayName)

            New-QrPngViaApi `
                -Data $payload.Data `
                -OutputPath $pngPath `
                -Size $size `
                -Ecc $ecc `
                -CreateEndpoint $onlineEndpoints.CreateEndpoint

            Write-DebugLog "Online provider" ("SUCCESS via {0}" -f $onlineEndpoints.DisplayName) "Ok"
        }

        if ($useLogoNow) {
            Set-StatusKey "status.logo"
            Write-DebugLog "Logo" ("Applying logo at {0}%" -f ([double]$LogoSize.Value))
            Add-LogoToQr -QrPath $pngPath -LogoPath $Script:LogoPath -LogoPercent ([double]$LogoSize.Value) -TempDir $Script:TempDir
            Write-DebugLog "Logo" "SUCCESS" "Ok"
        }

        if ($null -ne $payload.VCard) {
            $vcfPath = [System.IO.Path]::ChangeExtension($pngPath, ".vcf")
            [System.IO.File]::WriteAllText(
                $vcfPath,
                $payload.VCard,
                [System.Text.UTF8Encoding]::new($false)
            )
            Write-DebugLog "vCard" ("VCF written | " + $vcfPath) "Ok"
        }

        # Explicitly release the currently displayed bitmap before loading
        # the freshly overwritten PNG. New-WpfBitmapImage itself bypasses
        # the WPF URI cache as well.
        $QrPreview.Source = $null
        $QrPreview.UpdateLayout()
        $QrPreview.Source = New-WpfBitmapImage $pngPath
        $QrPreview.InvalidateVisual()
        $Script:GeneratedQrPath = $pngPath
        $Script:GeneratedQrData = [string]$payload.Data
        $BtnVerifyQr.IsEnabled = $true

        $shouldRunOnlineReadTest = $false
        $readTestEndpoints = $onlineEndpoints

        if ([bool]$Script:Settings.RunReadTest) {
            if ($provider -eq "local") {
                if ($usedFallback) {
                    # The payload has already been sent to the fallback provider,
                    # so the configured read test may run without an additional
                    # privacy boundary.
                    $shouldRunOnlineReadTest = $true
                }
                elseif ($unicodeLocalFirst) {
                    # The user originally selected an online provider and then
                    # explicitly chose the one-time local-first recommendation.
                    # Keep the normal online read-test behavior for that provider.
                    $readTestEndpoints = Get-OnlineProviderEndpoints -Provider $generationFallbackProvider
                    $shouldRunOnlineReadTest = $true
                }
                elseif ([bool]$Script:Settings.RunOnlineReadTestForLocal) {
                    $readTestEndpoints = Get-OnlineProviderEndpoints -Provider ([string]$Script:Settings.FallbackProvider)
                    $shouldRunOnlineReadTest = $true
                }
            }
            else {
                $shouldRunOnlineReadTest = $true
            }
        }

        if ($shouldRunOnlineReadTest) {
            Set-StatusKey "status.testingOnline" "Normal" @{ provider = $readTestEndpoints.DisplayName }
            Write-DebugLog "Read test" ("Starting online verification via {0}" -f $readTestEndpoints.DisplayName)
            $test = Test-QrViaApi `
                -QrPath $pngPath `
                -ExpectedData $payload.Data `
                -ReadEndpoint $readTestEndpoints.ReadEndpoint `
                -TempDir $Script:TempDir

            if (-not $test.Success -and [string]$test.ErrorType -eq "Transport") {
                $diag = Get-ErrorDiagnostic $test.Exception
                Write-DebugLog "Read test" ("UNAVAILABLE [{0}] | {1}" -f $diag.Category, $diag.Summary) "Warn"
                Write-DebugLog "What to do" $diag.Advice "Warn"
                Write-DebugLog "Technical" $diag.Technical "Error"
                Set-StatusKey "status.testUnavailable" "Warn"
                Show-AppInfo (T "info.readUnavailable" @{ reason = $diag.Summary; advice = $diag.Advice })
            }
            elseif (-not $test.Success) {
                Write-DebugLog "Read test" ("DECODE FAILED | " + [string]$test.Error) "Warn"
                Set-StatusKey "status.testFailed" "Warn"
                Show-AppInfo (T "info.readFail" @{ error = $test.Error })
            }
            elseif ([bool]$test.Equivalent) {
                Write-DebugLog "Read test" ("PASS [{0}] | {1}" -f $test.MismatchCategory, $test.MismatchSummary) "Ok"
                Write-DebugLog "Comparison" ("ExpectedChars={0}; DecodedChars={1}; no payload text logged" -f $test.ExpectedLength, $test.DecodedLength)
                if ($usedFallback) {
                    Set-StatusKey "status.successFallbackVerified" "Warn" @{ provider = $onlineEndpoints.DisplayName }
                }
                elseif ($provider -eq "local") {
                    Set-StatusKey "status.successLocalVerified" "Ok"
                }
                else {
                    Set-StatusKey "status.successVerified" "Ok"
                }
            }
            elseif ([string]$test.MismatchCategory -eq "CharsetAmbiguity") {
                Write-DebugLog "Read test" ("WARNING [CharsetAmbiguity] | " + $test.MismatchSummary) "Warn"
                Write-DebugLog "Comparison" ("ExpectedChars={0}; DecodedChars={1}; FirstDifferenceIndex={2}; Expected={3}; Decoded={4}; no payload text logged" -f $test.ExpectedLength, $test.DecodedLength, $test.FirstDifferenceIndex, $test.ExpectedCodePoint, $test.DecodedCodePoint) "Warn"
                Write-DebugLog "What to do" "The QR image is not necessarily defective. For Unicode content, prefer the local QR engine or verify the code with the target phone/scanner." "Warn"
                Set-StatusKey "status.charsetWarning" "Warn"
            }
            elseif (-not $test.Exact) {
                Write-DebugLog "Read test" ("MISMATCH [{0}] | {1}" -f $test.MismatchCategory, $test.MismatchSummary) "Warn"
                Write-DebugLog "Comparison" ("ExpectedChars={0}; DecodedChars={1}; FirstDifferenceIndex={2}; Expected={3}; Decoded={4}; no payload text logged" -f $test.ExpectedLength, $test.DecodedLength, $test.FirstDifferenceIndex, $test.ExpectedCodePoint, $test.DecodedCodePoint) "Warn"
                Set-StatusKey "status.testMismatch" "Warn"
            }
            elseif ($usedFallback) {
                Write-DebugLog "Read test" "PASS | Exact payload match" "Ok"
                Set-StatusKey "status.successFallbackVerified" "Warn" @{ provider = $onlineEndpoints.DisplayName }
            }
            elseif ($provider -eq "local") {
                Write-DebugLog "Read test" "PASS | Exact payload match" "Ok"
                Set-StatusKey "status.successLocalVerified" "Ok"
            }
            else {
                Write-DebugLog "Read test" "PASS | Exact payload match" "Ok"
                Set-StatusKey "status.successVerified" "Ok"
            }
        }
        elseif ($usedFallback) {
            Write-DebugLog "Read test" "Skipped"
            Set-StatusKey "status.successFallback" "Warn" @{ provider = $onlineEndpoints.DisplayName }
        }
        elseif ($localGenerationSucceeded) {
            $skipReason = if (-not [bool]$Script:Settings.RunReadTest) { "disabled" } else { "online test not allowed for local generation" }
            Write-DebugLog "Read test" ("Skipped | " + $skipReason)
            Set-StatusKey "status.successLocal" "Ok"
        }
        else {
            Write-DebugLog "Read test" "Skipped"
            Set-StatusKey "status.success" "Ok"
        }

        Write-DebugLog "Generate" "Completed successfully" "Ok"

        if ([bool]$Script:Settings.OpenAfterCreate) {
            Start-Process $pngPath
        }
    }
    catch {
        $diag = Write-DebugException "Generate" $_
        if ($null -ne $_.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($_.InvocationInfo.PositionMessage)) {
            Write-DebugLog "Location" ($_.InvocationInfo.PositionMessage -replace "`r?`n", " | ") "Error"
        }
        Set-StatusKey "status.error" "Error"
        Show-AppError (T "error.operationFailed" @{ summary = $diag.Summary; advice = $diag.Advice })
    }
    finally {
        $BtnGenerate.IsEnabled = $true
    }
})

# Initial state
Load-AppSettings

if ($Script:DebugMode) {
    Write-DebugLog "Application" "Universal QR-Code Generator v2.5 - debug mode enabled" "Ok"
    Write-DebugLog "PowerShell" ("Version={0}; Edition={1}; CLR={2}" -f `
        $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, [Environment]::Version)
    Write-DebugLog "Project root" $ProjectRoot
    Write-DebugLog "Settings file" $Script:SettingsFile
    Write-DebugLog "Settings" ("Provider={0}; Fallback={1}; FallbackProvider={2}; ReadTest={3}; OnlineReadForLocal={4}" -f `
        $Script:Settings.Provider,
        $Script:Settings.UseOnlineFallback,
        $Script:Settings.FallbackProvider,
        $Script:Settings.RunReadTest,
        $Script:Settings.RunOnlineReadTestForLocal)
    Write-DebugLog "Privacy" "QR payload contents are NOT written to the debug console" "Ok"
}

Apply-LanguageResources $Window
$VCountry.Text = T "defaults.country"
Set-Mode "vCard" $NavVCard
Update-LogoPreview
Update-SettingsSummary
Set-StatusKey "status.ready" "Ok"

[void]$Window.ShowDialog()
Write-DebugLog "Application" "Closed normally" "Ok"
