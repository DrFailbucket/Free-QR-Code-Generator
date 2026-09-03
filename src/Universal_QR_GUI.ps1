#requires -Version 5.1
<#
    Universal QR-Code Generator
    WPF v2.4
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
    OpenAfterCreate = $false
    Provider = "qrserver"
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
            if ($null -ne $loaded.OpenAfterCreate) {
                $Script:Settings.OpenAfterCreate = [bool]$loaded.OpenAfterCreate
            }
            if ([string]$loaded.Provider -in @("qrserver","custom")) {
                $Script:Settings.Provider = [string]$loaded.Provider
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
    $SummaryReadTest.Text = if ($Script:Settings.RunReadTest) { T "common.on" } else { T "common.off" }

    switch ($Script:Settings.Provider) {
        "qrserver" { $SummaryProvider.Text = T "provider.qrserver" }
        "custom"   { $SummaryProvider.Text = T "provider.custom" }
        default    { $SummaryProvider.Text = [string]$Script:Settings.Provider }
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
                        <ComboBox x:Name="SettingsProvider"><ComboBoxItem Tag="qrserver" Content="{DynamicResource provider.qrserver.full}"/><ComboBoxItem Tag="custom" Content="{DynamicResource provider.custom.full}"/></ComboBox>
                        <StackPanel x:Name="CustomProviderPanel" Margin="0,12,0,0" Visibility="Collapsed">
                            <TextBlock Text="{DynamicResource settings.createEndpoint}" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/><TextBox x:Name="SettingsCreateEndpoint"/>
                            <TextBlock Text="{DynamicResource settings.readEndpoint}" Foreground="{StaticResource Muted}" Margin="0,11,0,6"/><TextBox x:Name="SettingsReadEndpoint"/>
                            <TextBlock Text="{DynamicResource settings.customHelp}" Foreground="{StaticResource Muted}" TextWrapping="Wrap" FontSize="12" Margin="0,9,0,0"/>
                        </StackPanel>
                        <TextBlock Text="{DynamicResource settings.externalWarning}" Foreground="#F6C453" TextWrapping="Wrap" FontSize="12" Margin="0,10,0,0"/>
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
    $customPanel = $dialog.FindName("CustomProviderPanel")
    $createEndpoint = $dialog.FindName("SettingsCreateEndpoint")
    $readEndpoint = $dialog.FindName("SettingsReadEndpoint")
    $reset = $dialog.FindName("SettingsReset")
    $cancel = $dialog.FindName("SettingsCancel")
    $save = $dialog.FindName("SettingsSave")

    $output.Text = $Script:OutputDir
    $openAfter.IsChecked = [bool]$Script:Settings.OpenAfterCreate
    $readTest.IsChecked = [bool]$Script:Settings.RunReadTest
    $createEndpoint.Text = [string]$Script:Settings.CustomCreateEndpoint
    $readEndpoint.Text = [string]$Script:Settings.CustomReadEndpoint

    foreach ($item in $languageBox.Items) { if ([string]$item.Tag -eq [string]$Script:Settings.Language) { $languageBox.SelectedItem = $item; break } }
    foreach ($item in $sizeBox.Items) { if ([string]$item.Content -eq ([string]$Script:Settings.QrSize + " px")) { $sizeBox.SelectedItem = $item; break } }
    foreach ($item in $eccBox.Items) { if ([string]$item.Content -eq [string]$Script:Settings.Ecc) { $eccBox.SelectedItem = $item; break } }
    foreach ($item in $providerBox.Items) { if ([string]$item.Tag -eq [string]$Script:Settings.Provider) { $providerBox.SelectedItem = $item; break } }
    if ($null -eq $languageBox.SelectedItem) { $languageBox.SelectedIndex = 0 }
    if ($null -eq $sizeBox.SelectedItem) { $sizeBox.SelectedIndex = 4 }
    if ($null -eq $eccBox.SelectedItem) { $eccBox.SelectedIndex = 3 }
    if ($null -eq $providerBox.SelectedItem) { $providerBox.SelectedIndex = 0 }

    $updateProviderPanel = {
        if ($null -ne $providerBox.SelectedItem -and [string]$providerBox.SelectedItem.Tag -eq "custom") { $customPanel.Visibility = [System.Windows.Visibility]::Visible }
        else { $customPanel.Visibility = [System.Windows.Visibility]::Collapsed }
    }
    $providerBox.Add_SelectionChanged($updateProviderPanel)
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
        $providerBox.SelectedIndex = 0
        $languageBox.SelectedIndex = 0
        $createEndpoint.Text = "https://api.qrserver.com/v1/create-qr-code/"
        $readEndpoint.Text = "https://api.qrserver.com/v1/read-qr-code/"
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
        if ($provider -eq "custom") {
            $createUri = $null; $readUri = $null
            if ([string]::IsNullOrWhiteSpace($createEndpoint.Text) -or -not [Uri]::TryCreate($createEndpoint.Text.Trim(), [UriKind]::Absolute, [ref]$createUri)) { Show-AppError (T "error.createEndpoint"); return }
            if ([bool]$readTest.IsChecked -and ([string]::IsNullOrWhiteSpace($readEndpoint.Text) -or -not [Uri]::TryCreate($readEndpoint.Text.Trim(), [UriKind]::Absolute, [ref]$readUri))) { Show-AppError (T "error.readEndpoint"); return }
        }

        $sizeText = [string]$sizeBox.SelectedItem.Content
        $Script:Settings.Language = [string]$languageBox.SelectedItem.Tag
        $Script:Settings.OutputDir = Convert-ToPortableStoredPath $output.Text.Trim()
        $Script:Settings.QrSize = [int](($sizeText -replace '[^\d]', ''))
        $Script:Settings.Ecc = [string]$eccBox.SelectedItem.Content
        $Script:Settings.RunReadTest = [bool]$readTest.IsChecked
        $Script:Settings.OpenAfterCreate = [bool]$openAfter.IsChecked
        $Script:Settings.Provider = $provider
        $Script:Settings.CustomCreateEndpoint = $createEndpoint.Text.Trim()
        $Script:Settings.CustomReadEndpoint = $readEndpoint.Text.Trim()
        $Script:OutputDir = Resolve-PortablePath $Script:Settings.OutputDir

        try { Save-AppSettings }
        catch { Show-AppError ((T "error.settingsSave") + "`r`n`r`n" + $_.Exception.Message); return }

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
    "UrlValue","WifiSsid","WifiPassword","WifiType","WifiHidden",
    "FreeText","MailTo","MailSubject","MailBody","PhoneValue","SmsNumber","SmsText","GeoLat","GeoLon",
    "QrPreview","UseLogo","LogoSize","LogoSizeText","LogoPreview","LogoEmptyText",
    "BtnChooseLogo","BtnRemoveLogo","SummarySize","SummaryEcc","SummaryReadTest","SummaryProvider","BtnSettingsRight","BtnGenerate","BtnOpenQr","BtnOpenFolder",
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

$BtnGenerate.Add_Click({
    try {
        $BtnGenerate.IsEnabled = $false
        Set-StatusKey "status.preparing"

        $payload = Build-Payload
        $size = [int]$Script:Settings.QrSize
        $ecc = [string]$Script:Settings.Ecc
        $provider = [string]$Script:Settings.Provider

        if ($provider -eq "custom") {
            $createEndpoint = [string]$Script:Settings.CustomCreateEndpoint
            $readEndpoint = [string]$Script:Settings.CustomReadEndpoint
        }
        else {
            $createEndpoint = "https://api.qrserver.com/v1/create-qr-code/"
            $readEndpoint = "https://api.qrserver.com/v1/read-qr-code/"
        }

        $useLogoNow =
            [bool]$UseLogo.IsChecked -and
            -not [string]::IsNullOrWhiteSpace($Script:LogoPath) -and
            (Test-Path -LiteralPath $Script:LogoPath)

        if ($useLogoNow -and $ecc -ne "H") {
            $ecc = "H"
        }

        $dlg = [Microsoft.Win32.SaveFileDialog]::new()
        $dlg.Title = T "dialog.save.title"
        $dlg.Filter = T "dialog.save.filter"
        $dlg.DefaultExt = ".png"
        $dlg.AddExtension = $true
        $dlg.InitialDirectory = $Script:OutputDir
        $dlg.FileName = $payload.DefaultName + ".png"

        if (-not $dlg.ShowDialog($Window)) {
            Set-StatusKey "status.cancelled" "Normal"
            return
        }

        $pngPath = $dlg.FileName
        $Script:OutputDir = Split-Path -Parent $pngPath

        Set-StatusKey "status.generating"
        New-QrPngViaApi -Data $payload.Data -OutputPath $pngPath -Size $size -Ecc $ecc -CreateEndpoint $createEndpoint

        if ($useLogoNow) {
            Set-StatusKey "status.logo"
            Add-LogoToQr -QrPath $pngPath -LogoPath $Script:LogoPath -LogoPercent ([double]$LogoSize.Value) -TempDir $Script:TempDir
        }

        if ($null -ne $payload.VCard) {
            $vcfPath = [System.IO.Path]::ChangeExtension($pngPath, ".vcf")
            [System.IO.File]::WriteAllText(
                $vcfPath,
                $payload.VCard,
                [System.Text.UTF8Encoding]::new($false)
            )
        }

        # Explicitly release the currently displayed bitmap before loading
        # the freshly overwritten PNG. New-WpfBitmapImage itself bypasses
        # the WPF URI cache as well.
        $QrPreview.Source = $null
        $QrPreview.UpdateLayout()
        $QrPreview.Source = New-WpfBitmapImage $pngPath
        $QrPreview.InvalidateVisual()
        $Script:GeneratedQrPath = $pngPath

        if ([bool]$Script:Settings.RunReadTest) {
            Set-StatusKey "status.testing"
            $test = Test-QrViaApi -QrPath $pngPath -ExpectedData $payload.Data -ReadEndpoint $readEndpoint -TempDir $Script:TempDir

            if (-not $test.Success) {
                Set-StatusKey "status.testFailed" "Warn"
                Show-AppInfo (T "info.readFail" @{ error = $test.Error })
            }
            elseif (-not $test.Exact) {
                Set-StatusKey "status.testMismatch" "Warn"
            }
            else {
                Set-StatusKey "status.successVerified" "Ok"
            }
        }
        else {
            Set-StatusKey "status.success" "Ok"
        }

        if ([bool]$Script:Settings.OpenAfterCreate) {
            Start-Process $pngPath
        }
    }
    catch {
        Set-StatusKey "status.error" "Error"
        Show-AppError (
            $_.Exception.Message +
            "`r`n`r`n" +
            $_.InvocationInfo.PositionMessage
        )
    }
    finally {
        $BtnGenerate.IsEnabled = $true
    }
})

# Initial state
Load-AppSettings
Apply-LanguageResources $Window
$VCountry.Text = T "defaults.country"
Set-Mode "vCard" $NavVCard
Update-LogoPreview
Update-SettingsSummary
Set-StatusKey "status.ready" "Ok"

[void]$Window.ShowDialog()
