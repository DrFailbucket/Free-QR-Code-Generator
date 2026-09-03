#requires -Version 5.1
<#
    Universal QR-Code Generator
    WPF v2.1
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

$Script:SettingsDir = Join-Path $env:APPDATA "UniversalQRCodeGenerator"
$Script:SettingsFile = Join-Path $Script:SettingsDir "settings.json"

$Script:Settings = [ordered]@{
    OutputDir = (Join-Path $env:USERPROFILE "Downloads")
    QrSize = 1000
    Ecc = "H"
    RunReadTest = $true
    OpenAfterCreate = $false

    # qrserver = built-in default endpoints
    # custom   = user supplied QRServer-compatible endpoints
    Provider = "qrserver"
    CustomCreateEndpoint = "https://api.qrserver.com/v1/create-qr-code/"
    CustomReadEndpoint = "https://api.qrserver.com/v1/read-qr-code/"
}

$Script:OutputDir = $Script:Settings.OutputDir


function Load-AppSettings {
    try {
        if (Test-Path -LiteralPath $Script:SettingsFile) {
            $loaded = Get-Content -LiteralPath $Script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json

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
        # Invalid settings must never prevent the application from starting.
    }

    $Script:OutputDir = $Script:Settings.OutputDir
}

function Save-AppSettings {
    if (-not (Test-Path -LiteralPath $Script:SettingsDir)) {
        New-Item -ItemType Directory -Path $Script:SettingsDir -Force | Out-Null
    }

    $Script:Settings | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $Script:SettingsFile -Encoding UTF8
}

function Update-SettingsSummary {
    $SummarySize.Text = [string]$Script:Settings.QrSize + " px"
    $SummaryEcc.Text = [string]$Script:Settings.Ecc
    $SummaryReadTest.Text = if ($Script:Settings.RunReadTest) { "An" } else { "Aus" }

    switch ($Script:Settings.Provider) {
        "qrserver" { $SummaryProvider.Text = "QRServer" }
        "custom"   { $SummaryProvider.Text = "Benutzerdefiniert" }
        default    { $SummaryProvider.Text = [string]$Script:Settings.Provider }
    }

    $FooterSize.Text = [string]$Script:Settings.QrSize + " px"
    $FooterEcc.Text = "ECC " + [string]$Script:Settings.Ecc

    try {
        $leaf = Split-Path -Leaf $Script:Settings.OutputDir
        if ([string]::IsNullOrWhiteSpace($leaf)) {
            $leaf = $Script:Settings.OutputDir
        }
        $FooterSavePath.Text = $leaf
        $FooterSavePath.ToolTip = $Script:Settings.OutputDir
    }
    catch {
        $FooterSavePath.Text = "Speicherort"
    }
}

function Show-SettingsDialog {
    [xml]$settingsXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Einstellungen"
    Width="680"
    Height="700"
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

        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#F4F7FB"/>
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource InputBg}"/>
            <Setter Property="Foreground" Value="#F4F7FB"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="MinHeight" Value="36"/>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#F5F7FA"/>
            <Setter Property="Foreground" Value="#152033"/>
            <Setter Property="BorderBrush" Value="#6B7C90"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="MinHeight" Value="36"/>
        </Style>

        <Style TargetType="Button">
            <Setter Property="Background" Value="#10243C"/>
            <Setter Property="Foreground" Value="#F4F7FB"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter
                                HorizontalAlignment="Center"
                                VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="Background"
                                        Value="#173252"/>
                                <Setter TargetName="ButtonBorder"
                                        Property="BorderBrush"
                                        Value="#3A5F83"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder"
                                        Property="Opacity"
                                        Value="0.82"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder"
                                        Property="Opacity"
                                        Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#F4F7FB"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>

        <Style x:Key="SettingsCard" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardBg}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
        </Style>
    </Window.Resources>

    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="18"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="16"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel>
            <TextBlock Text="Einstellungen" FontSize="24" FontWeight="SemiBold"/>
            <TextBlock Text="Standardwerte, Speicherort und QR-Dienst."
                       Foreground="{StaticResource Muted}"
                       Margin="0,4,0,0"/>
        </StackPanel>

        <ScrollViewer Grid.Row="2"
                      VerticalScrollBarVisibility="Hidden"
                      HorizontalScrollBarVisibility="Disabled"
                      PanningMode="VerticalOnly">
            <StackPanel>
            <Border Style="{StaticResource SettingsCard}">
                <StackPanel>
                    <TextBlock Text="Speichern" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,11"/>
                    <TextBlock Text="Standard-Speicherort" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/>

                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="10"/>
                            <ColumnDefinition Width="100"/>
                        </Grid.ColumnDefinitions>

                        <TextBox x:Name="SettingsOutputDir"/>
                        <Button x:Name="SettingsBrowse"
                                Grid.Column="2"
                                Content="Auswählen"/>
                    </Grid>

                    <CheckBox x:Name="SettingsOpenAfter"
                              Content="QR-Code nach Erstellung automatisch öffnen"
                              Margin="0,12,0,0"/>
                </StackPanel>
            </Border>

            <Border Style="{StaticResource SettingsCard}">
                <StackPanel>
                    <TextBlock Text="QR-Code" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,11"/>

                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel>
                            <TextBlock Text="Standardgröße" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/>
                            <ComboBox x:Name="SettingsSize">
                                <ComboBoxItem Content="400 px"/>
                                <ComboBoxItem Content="600 px"/>
                                <ComboBoxItem Content="800 px"/>
                                <ComboBoxItem Content="900 px"/>
                                <ComboBoxItem Content="1000 px"/>
                            </ComboBox>
                        </StackPanel>

                        <StackPanel Grid.Column="2">
                            <TextBlock Text="Fehlerkorrektur (ECC)" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/>
                            <ComboBox x:Name="SettingsEcc">
                                <ComboBoxItem Content="L"/>
                                <ComboBoxItem Content="M"/>
                                <ComboBoxItem Content="Q"/>
                                <ComboBoxItem Content="H"/>
                            </ComboBox>
                        </StackPanel>
                    </Grid>

                    <CheckBox x:Name="SettingsReadTest"
                              Content="Automatischen Lesetest nach Erstellung ausführen"
                              Margin="0,14,0,0"/>
                </StackPanel>
            </Border>

            <Border Style="{StaticResource SettingsCard}">
                <StackPanel>
                    <TextBlock Text="QR-Dienst" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,11"/>

                    <TextBlock Text="Provider" Foreground="{StaticResource Muted}" Margin="0,0,0,6"/>
                    <ComboBox x:Name="SettingsProvider">
                        <ComboBoxItem Tag="qrserver" Content="QRServer / goQR.me (Standard)"/>
                        <ComboBoxItem Tag="custom" Content="Benutzerdefiniert (QRServer-kompatibel)"/>
                    </ComboBox>

                    <StackPanel x:Name="CustomProviderPanel"
                                Margin="0,12,0,0"
                                Visibility="Collapsed">
                        <TextBlock Text="Create-API-Endpunkt"
                                   Foreground="{StaticResource Muted}"
                                   Margin="0,0,0,6"/>
                        <TextBox x:Name="SettingsCreateEndpoint"/>

                        <TextBlock Text="Read-API-Endpunkt (für Lesetest)"
                                   Foreground="{StaticResource Muted}"
                                   Margin="0,11,0,6"/>
                        <TextBox x:Name="SettingsReadEndpoint"/>

                        <TextBlock
                            Text="Der benutzerdefinierte Dienst muss dieselben POST-Parameter und Antwortformate wie QRServer unterstützen. Für Anbieter mit anderer API ist ein eigener Provider-Adapter nötig."
                            Foreground="{StaticResource Muted}"
                            TextWrapping="Wrap"
                            FontSize="12"
                            Margin="0,9,0,0"/>
                    </StackPanel>

                    <TextBlock
                        Text="QR-Inhalte werden an den gewählten externen Dienst übertragen."
                        Foreground="#F6C453"
                        TextWrapping="Wrap"
                        FontSize="12"
                        Margin="0,10,0,0"/>
                </StackPanel>
            </Border>
            </StackPanel>
        </ScrollViewer>

        <Grid Grid.Row="4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Button x:Name="SettingsReset"
                    Grid.Column="0"
                    Content="Standardwerte"
                    Width="110"/>

            <StackPanel Grid.Column="2"
                        Orientation="Horizontal"
                        HorizontalAlignment="Right">
                <Button x:Name="SettingsCancel"
                        Content="Abbrechen"
                        Width="100"
                        Margin="0,0,10,0"/>
                <Button x:Name="SettingsSave"
                        Content="Speichern"
                        Width="110"
                        Background="{StaticResource Blue}"
                        BorderBrush="{StaticResource Blue}"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

    try {
        $reader = [System.Xml.XmlNodeReader]::new($settingsXaml)
        $dialog = [Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        Show-AppError (
            "Das Einstellungsfenster konnte nicht geladen werden.`r`n`r`n" +
            $_.Exception.Message
        )
        return
    }

    $dialog.Owner = $Window

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

    $output.Text = [string]$Script:Settings.OutputDir
    $openAfter.IsChecked = [bool]$Script:Settings.OpenAfterCreate
    $readTest.IsChecked = [bool]$Script:Settings.RunReadTest
    $createEndpoint.Text = [string]$Script:Settings.CustomCreateEndpoint
    $readEndpoint.Text = [string]$Script:Settings.CustomReadEndpoint

    foreach ($item in $sizeBox.Items) {
        if ([string]$item.Content -eq ([string]$Script:Settings.QrSize + " px")) {
            $sizeBox.SelectedItem = $item
            break
        }
    }

    foreach ($item in $eccBox.Items) {
        if ([string]$item.Content -eq [string]$Script:Settings.Ecc) {
            $eccBox.SelectedItem = $item
            break
        }
    }

    foreach ($item in $providerBox.Items) {
        if ([string]$item.Tag -eq [string]$Script:Settings.Provider) {
            $providerBox.SelectedItem = $item
            break
        }
    }

    if ($null -eq $sizeBox.SelectedItem) { $sizeBox.SelectedIndex = 4 }
    if ($null -eq $eccBox.SelectedItem) { $eccBox.SelectedIndex = 3 }
    if ($null -eq $providerBox.SelectedItem) { $providerBox.SelectedIndex = 0 }

    $updateProviderPanel = {
        if (
            $null -ne $providerBox.SelectedItem -and
            [string]$providerBox.SelectedItem.Tag -eq "custom"
        ) {
            $customPanel.Visibility = [System.Windows.Visibility]::Visible
        }
        else {
            $customPanel.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }

    $providerBox.Add_SelectionChanged($updateProviderPanel)
    & $updateProviderPanel

    $browse.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Standard-Speicherort auswählen"

        if (Test-Path -LiteralPath $output.Text) {
            $folderDialog.SelectedPath = $output.Text
        }

        if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $output.Text = $folderDialog.SelectedPath
        }
    })

    $reset.Add_Click({
        $output.Text = Join-Path $env:USERPROFILE "Downloads"
        $openAfter.IsChecked = $false
        $sizeBox.SelectedIndex = 4
        $eccBox.SelectedIndex = 3
        $readTest.IsChecked = $true
        $providerBox.SelectedIndex = 0
        $createEndpoint.Text = "https://api.qrserver.com/v1/create-qr-code/"
        $readEndpoint.Text = "https://api.qrserver.com/v1/read-qr-code/"
    })

    $cancel.Add_Click({
        $dialog.DialogResult = $false
        $dialog.Close()
    })

    $save.Add_Click({
        if ([string]::IsNullOrWhiteSpace($output.Text)) {
            Show-AppError "Bitte einen Speicherort auswählen."
            return
        }

        if (-not (Test-Path -LiteralPath $output.Text)) {
            try {
                New-Item -ItemType Directory -Path $output.Text -Force | Out-Null
            }
            catch {
                Show-AppError ("Der Speicherort konnte nicht erstellt werden.`r`n`r`n" + $_.Exception.Message)
                return
            }
        }

        $provider = [string]$providerBox.SelectedItem.Tag

        if ($provider -eq "custom") {
            $createUri = $null
            $readUri = $null

            if (
                [string]::IsNullOrWhiteSpace($createEndpoint.Text) -or
                -not [Uri]::TryCreate($createEndpoint.Text.Trim(), [UriKind]::Absolute, [ref]$createUri)
            ) {
                Show-AppError "Bitte einen gültigen Create-API-Endpunkt eintragen."
                return
            }

            if (
                [bool]$readTest.IsChecked -and
                (
                    [string]::IsNullOrWhiteSpace($readEndpoint.Text) -or
                    -not [Uri]::TryCreate($readEndpoint.Text.Trim(), [UriKind]::Absolute, [ref]$readUri)
                )
            ) {
                Show-AppError "Für den aktivierten Lesetest ist ein gültiger Read-API-Endpunkt erforderlich."
                return
            }
        }

        $sizeText = [string]$sizeBox.SelectedItem.Content
        $Script:Settings.OutputDir = $output.Text.Trim()
        $Script:Settings.QrSize = [int](($sizeText -replace '[^\d]', ''))
        $Script:Settings.Ecc = [string]$eccBox.SelectedItem.Content
        $Script:Settings.RunReadTest = [bool]$readTest.IsChecked
        $Script:Settings.OpenAfterCreate = [bool]$openAfter.IsChecked
        $Script:Settings.Provider = $provider
        $Script:Settings.CustomCreateEndpoint = $createEndpoint.Text.Trim()
        $Script:Settings.CustomReadEndpoint = $readEndpoint.Text.Trim()
        $Script:OutputDir = $Script:Settings.OutputDir

        try {
            Save-AppSettings
        }
        catch {
            Show-AppError ("Die Einstellungen konnten nicht gespeichert werden.`r`n`r`n" + $_.Exception.Message)
            return
        }

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
        "Universal QR-Code Generator - Fehler",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    ) | Out-Null
}

function Show-AppInfo {
    param([string]$Message)
    [System.Windows.MessageBox]::Show(
        $Message,
        "Universal QR-Code Generator",
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
            $TxtModeTitle.Text = "Kontakt / vCard"
            $TxtModeSubtitle.Text = "Erstelle einen QR-Code mit deinen Kontaktdaten (vCard 3.0)."
        }
        "url" {
            $PanelUrl.Visibility = [System.Windows.Visibility]::Visible
            $TxtModeTitle.Text = "Website / URL"
            $TxtModeSubtitle.Text = "Verlinke direkt auf eine Website oder beliebige URL."
        }
        "wifi" {
            $PanelWifi.Visibility = [System.Windows.Visibility]::Visible
            $TxtModeTitle.Text = "WLAN"
            $TxtModeSubtitle.Text = "Erstelle einen QR-Code für einen WLAN-Zugang."
        }
        "text" {
            $PanelText.Visibility = [System.Windows.Visibility]::Visible
            $TxtModeTitle.Text = "Freier Text"
            $TxtModeSubtitle.Text = "Speichere beliebigen Text direkt im QR-Code."
        }
        "email" {
            $PanelEmail.Visibility = [System.Windows.Visibility]::Visible
            $TxtModeTitle.Text = "E-Mail"
            $TxtModeSubtitle.Text = "Öffne beim Scannen eine neue, optional vorausgefüllte E-Mail."
        }
        "phone" {
            $PanelPhone.Visibility = [System.Windows.Visibility]::Visible
            $TxtModeTitle.Text = "Telefonnummer"
            $TxtModeSubtitle.Text = "Starte über den QR-Code direkt einen Telefonanruf."
        }
        "sms" {
            $PanelSms.Visibility = [System.Windows.Visibility]::Visible
            $TxtModeTitle.Text = "SMS"
            $TxtModeSubtitle.Text = "Öffne eine SMS mit Nummer und optional vorausgefülltem Text."
        }
        "geo" {
            $PanelGeo.Visibility = [System.Windows.Visibility]::Visible
            $TxtModeTitle.Text = "Standort / Geo"
            $TxtModeSubtitle.Text = "Speichere Breiten- und Längengrad als Geo-QR-Code."
        }
    }

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
        throw "Bei einer vCard muss mindestens Vorname, Nachname oder Firma ausgefüllt sein."
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
        $firma + "_Kontakt"
    }
    else {
        $displayName + "_Kontakt"
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
                throw "Bitte eine Website / URL eingeben."
            }
            if ($url -notmatch '^[a-zA-Z][a-zA-Z0-9+\-.]*://') {
                $url = "https://" + $url
            }
            return [PSCustomObject]@{
                Data = $url
                VCard = $null
                DefaultName = "Website_QR"
            }
        }

        "wifi" {
            $ssid = $WifiSsid.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($ssid)) {
                throw "Bitte eine WLAN-SSID eingeben."
            }

            $typeText = Get-ComboText $WifiType
            $hidden = if ($WifiHidden.IsChecked) { "true" } else { "false" }
            $ssidEsc = Escape-WifiText $ssid
            $passEsc = Escape-WifiText $WifiPassword.Text

            if ($typeText -eq "Offen") {
                $data = "WIFI:T:nopass;S:" + $ssidEsc + ";H:" + $hidden + ";;"
            }
            elseif ($typeText -eq "WEP") {
                $data = "WIFI:T:WEP;S:" + $ssidEsc + ";P:" + $passEsc + ";H:" + $hidden + ";;"
            }
            else {
                $data = "WIFI:T:WPA;S:" + $ssidEsc + ";P:" + $passEsc + ";H:" + $hidden + ";;"
            }

            return [PSCustomObject]@{
                Data = $data
                VCard = $null
                DefaultName = Get-SafeFileName ($ssid + "_WLAN")
            }
        }

        "text" {
            if ([string]::IsNullOrWhiteSpace($FreeText.Text)) {
                throw "Bitte einen Text eingeben."
            }
            return [PSCustomObject]@{
                Data = $FreeText.Text
                VCard = $null
                DefaultName = "Text_QR"
            }
        }

        "email" {
            $email = $MailTo.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($email)) {
                throw "Bitte eine Empfänger-E-Mail-Adresse eingeben."
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
                DefaultName = "Email_QR"
            }
        }

        "phone" {
            $number = $PhoneValue.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($number)) {
                throw "Bitte eine Telefonnummer eingeben."
            }

            return [PSCustomObject]@{
                Data = "tel:" + $number
                VCard = $null
                DefaultName = "Telefon_QR"
            }
        }

        "sms" {
            $number = $SmsNumber.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($number)) {
                throw "Bitte eine Telefonnummer eingeben."
            }

            return [PSCustomObject]@{
                Data = "SMSTO:" + $number + ":" + $SmsText.Text
                VCard = $null
                DefaultName = "SMS_QR"
            }
        }

        "geo" {
            $lat = $GeoLat.Text.Trim().Replace(",", ".")
            $lon = $GeoLon.Text.Trim().Replace(",", ".")

            if ($lat -notmatch '^-?\d+(\.\d+)?$' -or $lon -notmatch '^-?\d+(\.\d+)?$') {
                throw "Bitte gültige Breiten- und Längengrade eingeben."
            }

            return [PSCustomObject]@{
                Data = "geo:" + $lat + "," + $lon
                VCard = $null
                DefaultName = "Standort_QR"
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

    $VCountry.Text = "Deutschland"
    $UrlValue.Text = "https://"
    $WifiType.SelectedIndex = 0
    $WifiHidden.IsChecked = $false

    if ($null -ne $QrPreview.Source) {
        $QrPreview.Source = $null
    }

    $Script:GeneratedQrPath = $null
    Set-Status "Bereit" "Normal"
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
    $dlg.Title = "Logo auswählen"
    $dlg.Filter = "Bilddateien|*.png;*.jpg;*.jpeg;*.bmp|Alle Dateien|*.*"

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
    Show-AppInfo (
        "Universal QR-Code Generator v2.3.3`r`n`r`n" +
        "PowerShell 5.1 + WPF`r`n`r`n" +
        "QR-Erzeugung: api.qrserver.com`r`n" +
        "Optionaler Lesetest: api.qrserver.com`r`n`r`n" +
        "Datenschutz: QR-Inhalte werden zur Erzeugung an den externen Dienst übertragen."
    )
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
        Show-AppInfo "In dieser Sitzung wurde noch kein QR-Code erstellt."
    }
})

$BtnGenerate.Add_Click({
    try {
        $BtnGenerate.IsEnabled = $false
        Set-Status "QR-Inhalt wird vorbereitet …"

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
        $dlg.Title = "QR-Code speichern"
        $dlg.Filter = "PNG-Bild|*.png"
        $dlg.DefaultExt = ".png"
        $dlg.AddExtension = $true
        $dlg.InitialDirectory = $Script:OutputDir
        $dlg.FileName = $payload.DefaultName + ".png"

        if (-not $dlg.ShowDialog($Window)) {
            Set-Status "Abgebrochen" "Normal"
            return
        }

        $pngPath = $dlg.FileName
        $Script:OutputDir = Split-Path -Parent $pngPath

        Set-Status "QR-Code wird erzeugt …"
        New-QrPngViaApi -Data $payload.Data -OutputPath $pngPath -Size $size -Ecc $ecc -CreateEndpoint $createEndpoint

        if ($useLogoNow) {
            Set-Status "Logo wird eingesetzt …"
            Add-LogoToQr -QrPath $pngPath -LogoPath $Script:LogoPath -LogoPercent ([double]$LogoSize.Value)
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
            Set-Status "Lesbarkeit wird geprüft …"
            $test = Test-QrViaApi -QrPath $pngPath -ExpectedData $payload.Data -ReadEndpoint $readEndpoint

            if (-not $test.Success) {
                Set-Status "QR erstellt – Lesetest fehlgeschlagen" "Warn"
                Show-AppInfo (
                    "Der QR-Code wurde gespeichert, konnte vom automatischen Lesetest aber nicht gelesen werden.`r`n`r`n" +
                    "Bitte zusätzlich mit einem Smartphone testen.`r`n`r`n" +
                    "API-Meldung: " + $test.Error
                )
            }
            elseif (-not $test.Exact) {
                Set-Status "QR erstellt – Rückleseinhalt weicht ab" "Warn"
            }
            else {
                Set-Status "QR-Code erfolgreich erstellt und verifiziert" "Ok"
            }
        }
        else {
            Set-Status "QR-Code erfolgreich erstellt" "Ok"
        }

        if ([bool]$Script:Settings.OpenAfterCreate) {
            Start-Process $pngPath
        }
    }
    catch {
        Set-Status "Fehler beim Erstellen" "Error"
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
Set-Mode "vCard" $NavVCard
Update-LogoPreview
Update-SettingsSummary
Set-Status "Bereit" "Ok"

[void]$Window.ShowDialog()
