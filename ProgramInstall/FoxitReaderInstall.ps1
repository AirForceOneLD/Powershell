<#
Download und Installation der aktuellste Version von Foxit Reader

Idee von: https://github.com/silentinstalls/PowerShell/blob/main/FoxitReader.ps1

Modifiziert von Michael Mayer, Landau i.d.Pfalz, Germany
https://github.com/AirForceOneLD
#>


function Show-ModernMessageBox {
    <#
    .SYNOPSIS
        Zeigt ein anpassbares Nachrichtenfeld im modernen Stil mit einem dunklen Thema an.
    .DESCRIPTION
        Diese Funktion verwendet WPF und XAML, um ein Nachrichtenfeld zu erstellen, das das Aussehen und die Bedienung moderner Windows 10/11 UI-Elemente nachahmt.
        Es handelt sich um einen modalen Dialog, d. h. das Skript hält an, bis der Benutzer auf eine Schaltfläche klickt.
    .PARAMETER Title
        Der Text, der in der Titelleiste des Nachrichtenfelds angezeigt werden soll.
    .PARAMETER Message
        Der Hauptinhalt der Nachricht, die im Dialogfeld angezeigt werden soll.
    .PARAMETER Buttons
        Gibt an, welche Schaltflächen im Meldungsfenster angezeigt werden sollen.
        Gültige Werte sind: 'OK', 'OKCancel', 'YesNo', 'YesNoCancel'.
    .PARAMETER Icon
        Legt fest, welches Symbol neben der Meldung angezeigt werden soll.
        Gültige Werte sind: 'None', 'Information', 'Warning', 'Error', 'Question'.
    .EXAMPLE
        Show-ModernMessageBox -Title "Action Complete" -Message "The script has finished running successfully." -Icon Information
    .EXAMPLE
        $result = Show-ModernMessageBox -Title "Confirm Deletion" -Message "Are you sure you want to delete this file permanently?" -Buttons YesNo -Icon Warning
        if ($result -eq "Yes") { Write-Host "User confirmed deletion." }
    .OUTPUTS
        [string] Der Name der Schaltfläche, auf die der Benutzer geklickt hat ('OK', 'Cancel', 'Yes', 'No'). Gibt $null zurück, wenn das Fenster geschlossen ist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('OK', 'OKCancel', 'YesNo', 'YesNoCancel')]
        [string]$Buttons = 'OK',

        [ValidateSet('None', 'Information', 'Warning', 'Error', 'Question')]
        [string]$Icon = 'None'
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterScreen"
        SizeToContent="WidthAndHeight" MinWidth="350" MaxWidth="600"
        FontFamily="Segoe UI">

    <Window.Resources>
        <!-- Style for the main dialog buttons (e.g., OK, Yes) -->
        <Style x:Key="DialogButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#FF0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="14" />
            <Setter Property="Padding" Value="12,8"/> <!-- CHANGE: Increased vertical padding for taller buttons -->
            <Setter Property="MinWidth" Value="90"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" CornerRadius="4" Background="{TemplateBinding Background}" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#FF1088E4"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#FF005A9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Style for secondary buttons (e.g., Cancel) -->
        <Style x:Key="SecondaryDialogButtonStyle" TargetType="Button" BasedOn="{StaticResource DialogButtonStyle}">
            <Setter Property="Background" Value="#FF505050"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" CornerRadius="4" Background="{TemplateBinding Background}" BorderThickness="{TemplateBinding BorderThickness}" BorderBrush="{TemplateBinding BorderBrush}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#FF606060"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#FF404040"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Style for the 'X' close button in the title bar -->
        <Style x:Key="TitleBarButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#FF404040"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#FF505050"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Border BorderBrush="#444444" BorderThickness="1" CornerRadius="8" Background="#FF202020">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Border x:Name="TitleBar" Grid.Row="0" Height="40" Background="Transparent">
                <Grid>
                    <TextBlock Text="$Title" Foreground="White" FontSize="14" VerticalAlignment="Center" Margin="15,0,0,0" />
                    <Button x:Name="CloseButton" Content="" FontFamily="Segoe MDL2 Assets"
                            Foreground="White" FontSize="12" VerticalAlignment="Center" HorizontalAlignment="Right"
                            Width="40" Height="40" Style="{StaticResource TitleBarButtonStyle}" />
                </Grid>
            </Border>

            <Grid Grid.Row="1" Margin="20,10,20,20">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>

                <TextBlock x:Name="IconTextBlock" Grid.Column="0" Text="" FontFamily="Segoe MDL2 Assets"
                           FontSize="32" VerticalAlignment="Top" Margin="0,8,20,0" />

                <TextBlock Grid.Column="1" Text="$Message" Foreground="#DDFFFFFF" FontSize="16" TextWrapping="Wrap" VerticalAlignment="Center"/>
            </Grid>

            <Border Grid.Row="2" Background="#FF2D2D2D" CornerRadius="0,0,7,7">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="15">
                    <Button x:Name="YesButton" Content="Ja" Width="35" Height="30" Style="{StaticResource DialogButtonStyle}" Margin="0,0,20,0" />
                    <Button x:Name="NoButton" Content="Nein" Width="35" Height="30" Style="{StaticResource DialogButtonStyle}" Margin="0,0,20,0" />
                    <Button x:Name="OKButton" Content="OK" Width="35" Height="30" Style="{StaticResource DialogButtonStyle}" Margin="0,0,20,0" />
                    <Button x:Name="CancelButton" Content="Abbrechen" Width="35" Height="30" Style="{StaticResource SecondaryDialogButtonStyle}" />
                </StackPanel>
            </Border>
        </Grid>
    </Border>
</Window>
"@

    $xmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
    try {
        $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
    } catch {
        Write-Error " ❌ Fehler beim Analysieren von XAML: $($_.Exception.Message)"
        return
    }

    $dialogResult = $null
    $controls = @{}
    'OKButton', 'CancelButton', 'YesButton', 'NoButton', 'CloseButton', 'IconTextBlock', 'TitleBar' | ForEach-Object {
        $controls[$_] = $window.FindName($_)
    }

    $iconMap = @{
        Information = @{ Char = ''; Color = '#0078D4' }
        Warning     = @{ Char = ''; Color = '#F1C40F' }
        Error       = @{ Char = ''; Color = '#C50F1F' }
        Question    = @{ Char = ''; Color = '#0078D4' }
    }

    if ($Icon -ne 'None') {
        $controls.IconTextBlock.Text = [System.Net.WebUtility]::HtmlDecode($iconMap[$Icon].Char)
        $controls.IconTextBlock.Foreground = $iconMap[$Icon].Color
    } else {
        $controls.IconTextBlock.Visibility = 'Collapsed'
    }

    $controls.Values | Where-Object { $_ -is [System.Windows.Controls.Button] } | ForEach-Object { $_.Visibility = 'Collapsed' }
    $controls.CloseButton.Visibility = 'Visible'

    switch ($Buttons) {
        'OK' {
            $controls.OKButton.Visibility = 'Visible'
        }
        'OKCancel' {
            $controls.OKButton.Visibility = 'Visible'; $controls.CancelButton.Visibility = 'Visible'
        }
        'YesNo' {
            $controls.YesButton.Visibility = 'Visible'; $controls.NoButton.Visibility = 'Visible'
        }
        'YesNoCancel' {
            $controls.YesButton.Visibility = 'Visible'; $controls.NoButton.Visibility = 'Visible'; $controls.CancelButton.Visibility = 'Visible'
        }
    }

    $controls.OKButton.add_Click({ $script:dialogResult = 'OK'; $window.Close() })
    $controls.CancelButton.add_Click({ $script:dialogResult = 'Cancel'; $window.Close() })
    $controls.YesButton.add_Click({ $script:dialogResult = 'Yes'; $window.Close() })
    $controls.NoButton.add_Click({ $script:dialogResult = 'No'; $window.Close() })
    $controls.CloseButton.add_Click({ $script:dialogResult = $null; $window.Close() })
    $controls.TitleBar.add_MouseDown({ $window.DragMove() })
    $window.add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq 'Escape') {
                if ($controls.CancelButton.IsVisible) {
                    $script:dialogResult = 'Cancel'
                } else {
                    $script:dialogResult = $null
                }
                $window.Close()
            }
        })

    $window.ShowDialog() | Out-Null
    return $script:dialogResult
}

try {
    # Github API-URL für das App Manifest.
    $apiUrl = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/f/Foxit/FoxitReader'

    # Rufen den Versionsordner ab und filter nur Versionsordner.
    $versions = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'PowerShell' }
    $versionFolders = $versions | Where-Object { $_.type -eq 'dir' }

    # Extrahiere und sortiere die Versionsnummer, um die neueste Version zu erhalten.
    $sortedVersions = $versionFolders | ForEach-Object { $_.name } | Sort-Object { [version]$_ } -Descending -ErrorAction SilentlyContinue
    $latestVersion = $sortedVersions[0]

    Write-Host "`nNeueste Foxit Reader Version: " -NoNewline -ForegroundColor Yellow
    Write-Host "$latestVersion`n" -ForegroundColor Magenta

    # Rufee den Inhalt des Ordners der neuesten Version ab, um die Datei .installer.yaml zu finden.
    $latestApiUrl = "$apiUrl/$latestVersion"
    $latestFiles = Invoke-RestMethod -Uri $latestApiUrl -Headers @{ 'User-Agent' = 'PowerShell' }
    $installerFile = $latestFiles | Where-Object { $_.name -like '*.installer.yaml' }

    # Herunterladen und Parsen des YAML-Inhalts, um die Url der neuesten Installationsdatei zu erhalten.
    $yamlUrl = $installerFile.download_url
    $yamlContent = Invoke-RestMethod -Uri $yamlUrl -Headers @{ 'User-Agent' = 'PowerShell' }
    $null = ($yamlContent -join "`n") -match 'InstallerUrl:\s+(http.*)'
    $installerUrl = $Matches[1]


    Write-Host "`nHerunterladen des Installationsprogramms von: " -NoNewline -ForegroundColor Yellow
    Write-Host "$installerUrl`n" -ForegroundColor Magenta


    # Lade das neueste und aktuellste Installationsprogramm herunter
    $webClient = [System.Net.WebClient]::new()
    $webClient.DownloadFile($installerUrl, "$env:TEMP\FoxitReader-latest.exe")

    # Starte den Installations- oder Aktualisierungsvorgang.
    $installFR = Show-ModernMessageBox -Title 'Foxit Reader Installation' -Message "Der Download der aktuellen Foxit Reader Version ist beendet.`n`nSoll die Version '$latestVersion' installiert werden? " -Icon Question YesNo
    If ($installFR -eq "Yes")
    {
        Start-Process -FilePath "$env:TEMP\FoxitReader-latest.exe" -ArgumentList '/quiet' -Wait
        Write-Host "`n✅ Foxit Reader Installation abgeschlossen.`n" -ForegroundColor Green
    }
    else {
        Show-ModernMessageBox -Title 'Foxit Reader Installation' -Message "Die Installation wurde vom Benutzer nicht zugelassen!`n`nSkript wird beendet" -Icon Information OK
        Exit 0
    }

    # Bereinigen.
    $cleanFR = Show-ModernMessageBox -Title 'Foxit Reader Installation' -Message "Soll die Installionsdatei gelöscht werden?" -Icon Question YesNo
    if ($cleanFR -eq 'Yes') {
        Remove-Item -Path "$env:TEMP\FoxitReader-latest.exe" -Force -ErrorAction SilentlyContinue
        Write-Host "`n✅ Foxit Reader Installationsdatei gelöscht.`n" -ForegroundColor Green
    } else {
        Show-ModernMessageBox -Title 'Foxit Reader Installation' -Message "Die Installationsdatei 'FoxitReader-latest.exe' finden Sie zur weiteren Verwendung`nin Ihrem Temp-Verzeichnis unter`n`n$env:TEMP" -Icon Information OK
        exit 0
    }
}
catch {
    ## Wenn zu irgendeinem Zeitpunkt für irgendeinen Code innerhalb des try-Blocks ein hart terminierender Fehler zurückgegeben wird
    ## PowerShell leitet den Code an den catch-Block um, der in die Konsole schreibt
    ## und beendet die PowerShell-Konsole mit einem 1-Exit-Code.
    [System.Management.Automation.ErrorRecord]$e = $_
    [PSCustomObject]@{
        Typ       = $e.Exception.GetType().FullName
        Ausnahme  = $e.Exception.Message
        Grund     = $e.CategoryInfo.Reason
        Ziel      = $e.CategoryInfo.TargetName
        Skript    = $e.InvocationInfo.ScriptName
        Nachricht = $e.InvocationInfo.PositionMessage
    }
    Write-Warning $_
}


## Wenn der Code innerhalb der try/catch/finally-Blöcke abgeschlossen ist (Fehler oder nicht),
## Beende die PowerShell-Sitzung mit einem Exit-Code von 0
exit 0

# SIG # Begin signature block
# MIIdNAYJKoZIhvcNAQcCoIIdJTCCHSECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDpkrsorQSIgGIu
# v/p61G6e5FSDEZXZzldBPOW2sobtW6CCF30wggQ/MIICJ6ADAgECAhAT5FOc42Tt
# l0nO/PRq5gZDMA0GCSqGSIb3DQEBDQUAMB0xGzAZBgNVBAMMElBvd2VyU2hlbGwg
# Um9vdCBDQTAgFw0yMzAzMzAxNDQ5MzFaGA8yMDYzMDMzMDE0NTkyNlowLzEtMCsG
# A1UEAwwkTWljaGFlbCBNYXllciAoUG93ZXJzaGVsbCBEZXZlbG9wZXIpMIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtpqDfBAlS+JXj5I29IEW/cQy7bZw
# xI3GN3JVFEvdj2zuDvdmhVzsjCRs+RCqCvkdRoE5VYsDTTAgR7BLks+pWXXOjaWQ
# JALP1mBtMBsYkH8IjeHg37GLFi8AyknxVaUInrLtP3FjrpvbFKx+gZnKPFaz8P/D
# lcIdzKF5c8b9agYtXnH817S6ZOUqCbTaxEJaY7c59RQrqb+NahAo4JExOKPwBFDh
# ZiehpNlKeHqyiftR7F/HtG9LMiyVmZj70V6/qMOZUS0NEY6fLNGYnn3JaVzFRLkr
# tUlc0giAzoRx7JEYzHZ8ZYJxAAG5QcQgfR4NIGoE3Ko++DvvvXKIx7e1fQIDAQAB
# o2cwZTAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwHwYDVR0j
# BBgwFoAUhhJ/ox+VW4Sfz6mSjMYGBinLu2YwHQYDVR0OBBYEFLFRTWS7JtI3ft9X
# 7fUpvI9RnspCMA0GCSqGSIb3DQEBDQUAA4ICAQCj4ClDvNK7Q3igvhB1htHukOmH
# giru4nX4WOq9F0dhMGDmAcNltTl3gX9Ym2AWE6wL8UZggBj0HbQnWx66g3Sspypw
# suIo9hNYZAaCJZKN+drH/78pz5egfVrDLwNFslzX4GtEjl+3pfutVl4H1EyTFTPX
# 2pqLSzdlSU3rcruqNJRbsC1xIY3ppyvBFyHwENb9/Ep4lvQVRa/uZBG6y2d5cbCN
# fx68lhOcJpV4qyfffcoPaw70WtuHKInGmizf4KuoISp4wo1r5iWiwLCmF9g9ZQKd
# 7oFMI9qtJV1lHlmpq0QTnjKPUkCja2oQKUvAYyTi9bOPtZpUIRGBvpA0qfGxa8/r
# mGuO6QnBYdHiKa98dLBsQkEuUImHSBzqMko0X8RlbAzdPFUDp3fsW0GlIhBkFiUC
# DBHi5w89vYlAGtWIXMpFkAnSLkCtMFo4v0OkqLMF1O+3prbIlMesPKqGOzD5WMsW
# r0agEgTjCxOphjy1tQF1nIHB2vNhmqdJfUzqQSMQE6wAElaLQEmJjV8qFh1QM+DU
# V8a1e3PVkLutNtFhyAKML5bNG9bxO0qH/3+AId37UBm3EMBy4jl9vf1bY3mAeklD
# P0YwxGDEi+hOYHedL4/5m6UO9jdVb0Px635Yy2lzCBPeJ/gLn3GK5Nc+rf6Y5YnB
# O4IZUD6+C1cxkSaTozCCBY0wggR1oAMCAQICEA6bGI750C3n79tQ4ghAGFowDQYJ
# KoZIhvcNAQEMBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IElu
# YzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQg
# QXNzdXJlZCBJRCBSb290IENBMB4XDTIyMDgwMTAwMDAwMFoXDTMxMTEwOTIzNTk1
# OVowYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UE
# CxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBS
# b290IEc0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAv+aQc2jeu+Rd
# SjwwIjBpM+zCpyUuySE98orYWcLhKac9WKt2ms2uexuEDcQwH/MbpDgW61bGl20d
# q7J58soR0uRf1gU8Ug9SH8aeFaV+vp+pVxZZVXKvaJNwwrK6dZlqczKU0RBEEC7f
# gvMHhOZ0O21x4i0MG+4g1ckgHWMpLc7sXk7Ik/ghYZs06wXGXuxbGrzryc/NrDRA
# X7F6Zu53yEioZldXn1RYjgwrt0+nMNlW7sp7XeOtyU9e5TXnMcvak17cjo+A2raR
# mECQecN4x7axxLVqGDgDEI3Y1DekLgV9iPWCPhCRcKtVgkEy19sEcypukQF8IUzU
# vK4bA3VdeGbZOjFEmjNAvwjXWkmkwuapoGfdpCe8oU85tRFYF/ckXEaPZPfBaYh2
# mHY9WV1CdoeJl2l6SPDgohIbZpp0yt5LHucOY67m1O+SkjqePdwA5EUlibaaRBkr
# fsCUtNJhbesz2cXfSwQAzH0clcOP9yGyshG3u3/y1YxwLEFgqrFjGESVGnZifvaA
# sPvoZKYz0YkH4b235kOkGLimdwHhD5QMIR2yVCkliWzlDlJRR3S+Jqy2QXXeeqxf
# jT/JvNNBERJb5RBQ6zHFynIWIgnffEx1P2PsIV/EIFFrb7GrhotPwtZFX50g/KEe
# xcCPorF+CiaZ9eRpL5gdLfXZqbId5RsCAwEAAaOCATowggE2MA8GA1UdEwEB/wQF
# MAMBAf8wHQYDVR0OBBYEFOzX44LScV1kTN8uZz/nupiuHA9PMB8GA1UdIwQYMBaA
# FEXroq/0ksuCMS1Ri6enIZ3zbcgPMA4GA1UdDwEB/wQEAwIBhjB5BggrBgEFBQcB
# AQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBDBggr
# BgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNz
# dXJlZElEUm9vdENBLmNydDBFBgNVHR8EPjA8MDqgOKA2hjRodHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMBEGA1UdIAQK
# MAgwBgYEVR0gADANBgkqhkiG9w0BAQwFAAOCAQEAcKC/Q1xV5zhfoKN0Gz22Ftf3
# v1cHvZqsoYcs7IVeqRq7IviHGmlUIu2kiHdtvRoU9BNKei8ttzjv9P+Aufih9/Jy
# 3iS8UgPITtAq3votVs/59PesMHqai7Je1M/RQ0SbQyHrlnKhSLSZy51PpwYDE3cn
# RNTnf+hZqPC/Lwum6fI0POz3A8eHqNJMQBk1RmppVLC4oVaO7KTVPeix3P0c2PR3
# WlxUjG/voVA9/HYJaISfb8rbII01YBwCA8sgsKxYoA5AY8WYIsGyWfVVa88nq2x2
# zm8jLfR+cWojayL/ErhULSd+2DrZ8LaHlv1b0VysGMNNn3O3AamfV6peKOK5lDCC
# BrQwggScoAMCAQICEA3HrFcF/yGZLkBDIgw6SYYwDQYJKoZIhvcNAQELBQAwYjEL
# MAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3
# LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0
# MB4XDTI1MDUwNzAwMDAwMFoXDTM4MDExNDIzNTk1OVowaTELMAkGA1UEBhMCVVMx
# FzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVz
# dGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALR4MdMKmEFyvjxGwBysddujRmh0
# tFEXnU2tjQ2UtZmWgyxU7UNqEY81FzJsQqr5G7A6c+Gh/qm8Xi4aPCOo2N8S9SLr
# C6Kbltqn7SWCWgzbNfiR+2fkHUiljNOqnIVD/gG3SYDEAd4dg2dDGpeZGKe+42DF
# UF0mR/vtLa4+gKPsYfwEu7EEbkC9+0F2w4QJLVSTEG8yAR2CQWIM1iI5PHg62IVw
# xKSpO0XaF9DPfNBKS7Zazch8NF5vp7eaZ2CVNxpqumzTCNSOxm+SAWSuIr21Qomb
# +zzQWKhxKTVVgtmUPAW35xUUFREmDrMxSNlr/NsJyUXzdtFUUt4aS4CEeIY8y9Ia
# aGBpPNXKFifinT7zL2gdFpBP9qh8SdLnEut/GcalNeJQ55IuwnKCgs+nrpuQNfVm
# UB5KlCX3ZA4x5HHKS+rqBvKWxdCyQEEGcbLe1b8Aw4wJkhU1JrPsFfxW1gaou30y
# Z46t4Y9F20HHfIY4/6vHespYMQmUiote8ladjS/nJ0+k6MvqzfpzPDOy5y6gqzti
# T96Fv/9bH7mQyogxG9QEPHrPV6/7umw052AkyiLA6tQbZl1KhBtTasySkuJDpsZG
# Kdlsjg4u70EwgWbVRSX1Wd4+zoFpp4Ra+MlKM2baoD6x0VR4RjSpWM8o5a6D8bpf
# m4CLKczsG7ZrIGNTAgMBAAGjggFdMIIBWTASBgNVHRMBAf8ECDAGAQH/AgEAMB0G
# A1UdDgQWBBTvb1NK6eQGfHrK4pBW9i/USezLTjAfBgNVHSMEGDAWgBTs1+OC0nFd
# ZEzfLmc/57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUH
# AwgwdwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdp
# Y2VydC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0
# dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3Js
# MCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsF
# AAOCAgEAF877FoAc/gc9EXZxML2+C8i1NKZ/zdCHxYgaMH9Pw5tcBnPw6O6FTGNp
# oV2V4wzSUGvI9NAzaoQk97frPBtIj+ZLzdp+yXdhOP4hCFATuNT+ReOPK0mCefSG
# +tXqGpYZ3essBS3q8nL2UwM+NMvEuBd/2vmdYxDCvwzJv2sRUoKEfJ+nN57mQfQX
# wcAEGCvRR2qKtntujB71WPYAgwPyWLKu6RnaID/B0ba2H3LUiwDRAXx1Neq9ydOa
# l95CHfmTnM4I+ZI2rVQfjXQA1WSjjf4J2a7jLzWGNqNX+DF0SQzHU0pTi4dBwp9n
# EC8EAqoxW6q17r0z0noDjs6+BFo+z7bKSBwZXTRNivYuve3L2oiKNqetRHdqfMTC
# W/NmKLJ9M+MtucVGyOxiDf06VXxyKkOirv6o02OoXN4bFzK0vlNMsvhlqgF2puE6
# FndlENSmE+9JGYxOGLS/D284NHNboDGcmWXfwXRy4kbu4QFhOm0xJuF2EZAOk5eC
# khSxZON3rGlHqhpB/8MluDezooIs8CVnrpHMiD2wL40mm53+/j7tFaxYKIqL0Q4s
# sd8xHZnIn/7GELH3IdvG2XlM9q7WP/UwgOkw/HQtyRN62JK4S1C8uw3PdBunvAZa
# psiI5YKdvlarEvf8EA+8hcpSM9LHJmyrxaFtoza2zNaQ9k+5t1wwggbtMIIE1aAD
# AgECAhAKgO8YS43xBYLRxHanlXRoMA0GCSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYT
# AlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQg
# VHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEw
# HhcNMjUwNjA0MDAwMDAwWhcNMzYwOTAzMjM1OTU5WjBjMQswCQYDVQQGEwJVUzEX
# MBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFNIQTI1
# NiBSU0E0MDk2IFRpbWVzdGFtcCBSZXNwb25kZXIgMjAyNSAxMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEA0EasLRLGntDqrmBWsytXum9R/4ZwCgHfyjfM
# GUIwYzKomd8U1nH7C8Dr0cVMF3BsfAFI54um8+dnxk36+jx0Tb+k+87H9WPxNyFP
# JIDZHhAqlUPt281mHrBbZHqRK71Em3/hCGC5KyyneqiZ7syvFXJ9A72wzHpkBaMU
# Ng7MOLxI6E9RaUueHTQKWXymOtRwJXcrcTTPPT2V1D/+cFllESviH8YjoPFvZSjK
# s3SKO1QNUdFd2adw44wDcKgH+JRJE5Qg0NP3yiSyi5MxgU6cehGHr7zou1znOM8o
# dbkqoK+lJ25LCHBSai25CFyD23DZgPfDrJJJK77epTwMP6eKA0kWa3osAe8fcpK4
# 0uhktzUd/Yk0xUvhDU6lvJukx7jphx40DQt82yepyekl4i0r8OEps/FNO4ahfvAk
# 12hE5FVs9HVVWcO5J4dVmVzix4A77p3awLbr89A90/nWGjXMGn7FQhmSlIUDy9Z2
# hSgctaepZTd0ILIUbWuhKuAeNIeWrzHKYueMJtItnj2Q+aTyLLKLM0MheP/9w6Ct
# juuVHJOVoIJ/DtpJRE7Ce7vMRHoRon4CWIvuiNN1Lk9Y+xZ66lazs2kKFSTnnkrT
# 3pXWETTJkhd76CIDBbTRofOsNyEhzZtCGmnQigpFHti58CSmvEyJcAlDVcKacJ+A
# 9/z7eacCAwEAAaOCAZUwggGRMAwGA1UdEwEB/wQCMAAwHQYDVR0OBBYEFOQ7/PIx
# 7f391/ORcWMZUEPPYYzoMB8GA1UdIwQYMBaAFO9vU0rp5AZ8esrikFb2L9RJ7MtO
# MA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDCBlQYIKwYB
# BQUHAQEEgYgwgYUwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNv
# bTBdBggrBgEFBQcwAoZRaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVDQTEuY3J0
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdp
# Q2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNy
# bDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQEL
# BQADggIBAGUqrfEcJwS5rmBB7NEIRJ5jQHIh+OT2Ik/bNYulCrVvhREafBYF0RkP
# 2AGr181o2YWPoSHz9iZEN/FPsLSTwVQWo2H62yGBvg7ouCODwrx6ULj6hYKqdT8w
# v2UV+Kbz/3ImZlJ7YXwBD9R0oU62PtgxOao872bOySCILdBghQ/ZLcdC8cbUUO75
# ZSpbh1oipOhcUT8lD8QAGB9lctZTTOJM3pHfKBAEcxQFoHlt2s9sXoxFizTeHihs
# QyfFg5fxUFEp7W42fNBVN4ueLaceRf9Cq9ec1v5iQMWTFQa0xNqItH3CPFTG7aEQ
# JmmrJTV3Qhtfparz+BW60OiMEgV5GWoBy4RVPRwqxv7Mk0Sy4QHs7v9y69NBqycz
# 0BZwhB9WOfOu/CIJnzkQTwtSSpGGhLdjnQ4eBpjtP+XB3pQCtv4E5UCSDag6+iX8
# MmB10nfldPF9SVD7weCC3yXZi/uuhqdwkgVxuiMFzGVFwYbQsiGnoa9F5AaAyBjF
# BtXVLcKtapnMG3VH3EmAp/jsJ3FVF3+d1SVDTmjFjLbNFZUWMXuZyvgLfgyPehwJ
# VxwC+UpX2MSey2ueIu9THFVkT+um1vshETaWyQo8gmBto/m3acaP9QsuLj3FNwFl
# Txq25+T4QwX9xa6ILs84ZPvmpovq90K8eWyG2N01c4IhSOxqt81nMYIFDTCCBQkC
# AQEwMTAdMRswGQYDVQQDDBJQb3dlclNoZWxsIFJvb3QgQ0ECEBPkU5zjZO2XSc78
# 9GrmBkMwDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKA
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYK
# KwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgnCmMzQJq5qTSgwxQkyvdOjmhRIA2
# lMxoXeEkkeas4YgwDQYJKoZIhvcNAQEBBQAEggEAGTxaVYuc0fm5fK6l2UwBr5M6
# xgA2WGZESAuzxFXSaSEDHAz3u4ICFUwWgoJKZb3Qb7TEeX1fkyIGFIait2HRxljJ
# m85RPqarcWhWzRlaBJUHI/WrnCnGrFjccbXLkZpUo9ie9PR1eekIdWPObRm6w20I
# 7ejk2UKlgjvFGCv2OrMjFaxJ10+Pbd1y5RxxelRpSj7PvTox3BuJ2B+m1BwcUCoz
# Iwnh7/aJmfYzcb8XWJuGkIU78WkHj43zsmNK3MZq1krPwjBmqxQJtpk+Os3a/dnf
# kHHXk8AFPK5EQYpBd6gnM4SZ+PXVsIoxPM7SDpzU5uSZfaf7vn0Q4LGwVmXDt6GC
# AyYwggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcw
# FQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3Rl
# ZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhL
# jfEFgtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZI
# hvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNTA3MjExNjAwNDZaMC8GCSqGSIb3DQEJ
# BDEiBCDVVb4CcwqcevO7/Mku1mDClniqm+v4TPOZf/yxLHyJ9TANBgkqhkiG9w0B
# AQEFAASCAgB+XzJ8488MSrw/qENCqe7owT8TrPZOkydnV+S+lZqnRWQrudNBP0Qq
# /DUKy7vUpEagAATVbkqODPE5FwNZvIBtO3dhr4IL1d7DOnnWARh9AGa0fEj67xBm
# g9rA+IY5P55nUbazLAtlLuUINiVLyl+1YWc1FLUizp6H7TMMom5hUvyHqOIdCHQz
# qmOE91b/VyAeYW9LeeGgjerTp6O0xdYatxNaTg5ero6VSQp9c4HBKo+4eq6lKBlj
# ztyZQWogMKcNO9vVvVIa/ozCYC4NTbpUa3eRYJ8CgeNBg/f1nFmRrv+zvw9dl8CI
# Xt6AWPipsgpXQT5UObMvFt6LBXxrVg1e/bn9oMuAn5xAiut2TOtaJyImZJgS+w25
# dUpKNCx+3t1ixUDaxL41lkgePcfbUkcPZnYubdTUvUfpxDlFQcUSvN8xHdPFfI4t
# h0/ww788aWa10GceG7zSlkUnU/VN8YGzx+cERpUfC0dLupc8JXiSMWR8BRrFktMG
# hzQFJNi9zMSGn8nDKSOqgvAA1LyYZPABhBHK7z7lRui4dnDfp9Zbr+lGnIQVzPBm
# MrJOjR8R0qYtEuHEaz3GpY3oNCa+vqLARkEsRkzjbLJTyWW+lxQ0Wn2APjjKUqKk
# VssWGUkL2pS+DoKi/F5qCCKo4msnym3CEXZ+nuXvzDfO6MunENsH7w==
# SIG # End signature block
