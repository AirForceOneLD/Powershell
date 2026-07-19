#Requires -Version 5.1

<#
.SYNOPSIS
    Windows Restore Tool v4.3
    Restores Windows to factory default settings after debloat scripts,
    privacy.sexy tweaks, group policy modifications, and registry changes.

.DESCRIPTION
    One-click tool to fix Windows PCs broken by debloat/privacy scripts.
    Features: pre-scan diagnostics, preset fix modes, and detailed reporting.
    Run with Administrator privileges. Creates a detailed log on your Desktop.

.NOTES

    Requires: Administrator privileges

    Idee von:   https://github.com/SysAdminDoc/Restore-WindowsDefaults

    Modifiziert von Michael Mayer, Landau i.d.Pfalz, Germany
    https://github.com/AirForceOneLD
#>


#>

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:Version = '4.3.0'
$script:LogPath = "$env:USERPROFILE\Desktop\$env:COMPUTERNAME-WindowsRestore_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:ChangesCount = 0
$script:ErrorsCount = 0
$script:SkippedCount = 0
# Per-category result tracking: key = category name, value = @{Status; Details; Changed; Errors}
$script:CategoryResults = [ordered]@{}
$script:CurrentCategory = ''


# ============================================================================
# SELF-ELEVATION (Forces Windows PowerShell 5.1 for WPF/Appx compatibility)
# ============================================================================

# PowerShell 7+ has broken Appx module and WPF quirks - force Windows PowerShell 5.1
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process $ps5 -Verb RunAs -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy RemoteSigned -File `"$PSCommandPath`""
    exit
}
# Self-elevate if not admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy RemoteSigned -File `"$PSCommandPath`""
    exit
}

# ============================================================================
# ASSEMBLY LOADING
# ============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ============================================================================
# HELPERS
# ============================================================================

# Safe wrapper for Get-AppxPackage (never throws, returns $null on failure)
function Get-AppxPackageSafe {
    param([string]$Name, [switch]$AllUsers)
    try {
        if ($AllUsers) {
            return @(Get-AppxPackage -AllUsers $Name -EA Stop)
        } else {
            return (Get-AppxPackage $Name -EA Stop)
        }
    } catch {
        return $null
    }
}

# ============================================================================
# LOGGING WITH RESULT TRACKING
# ============================================================================

$script:ConsoleBox = $null
$script:ConsoleWindow = $null

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Section')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logFull = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $script:LogPath -Value $logFull -ErrorAction SilentlyContinue

    # Track per-category stats
    if ($script:CurrentCategory -and $script:CategoryResults.Contains($script:CurrentCategory)) {
        switch ($Level) {
            'Success' {
                $script:CategoryResults[$script:CurrentCategory].Changed++
            }
            'Error' {
                $script:CategoryResults[$script:CurrentCategory].Errors++; $script:ErrorsCount++
            }
        }
    } elseif ($Level -eq 'Error') {
        $script:ErrorsCount++
    }

    switch ($Level) {
        'Success' {
            Write-Host $logFull -ForegroundColor Green
        }
        'Warning' {
            Write-Host $logFull -ForegroundColor Yellow
        }
        'Error' {
            Write-Host $logFull -ForegroundColor Red
        }
        'Section' {
            Write-Host $logFull -ForegroundColor Magenta
        }
        default {
            Write-Host $logFull -ForegroundColor Cyan
        }
    }

    # Push to GUI console
    if ($script:ConsoleBox -and $script:ConsoleWindow) {
        try {
            $colorMap = @{ Success = '#6BCB77'; Warning = '#FFD93D'; Error = '#FF6B6B'; Section = '#BB86FC'; Info = '#8BB4CC' }
            $color = $colorMap[$Level]; if (!$color) {
                $color = '#8BB4CC'
            }
            $prefix = switch ($Level) {
                'Success' {
                    ' + '
                }; 'Warning' {
                    ' ! '
                }; 'Error' {
                    ' X '
                }; 'Section' {
                    '>> '
                }; default {
                    ' . '
                }
            }
            $doc = $script:ConsoleBox.Document
            $para = New-Object System.Windows.Documents.Paragraph
            $para.Margin = [System.Windows.Thickness]::new(0)
            $para.LineHeight = 1
            $tsRun = New-Object System.Windows.Documents.Run("[$timestamp] ")
            $tsRun.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#555566')
            $para.Inlines.Add($tsRun) | Out-Null
            $pfxRun = New-Object System.Windows.Documents.Run($prefix)
            $pfxRun.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
            $pfxRun.FontWeight = [System.Windows.FontWeights]::SemiBold
            $para.Inlines.Add($pfxRun) | Out-Null
            $msgRun = New-Object System.Windows.Documents.Run($Message)
            $msgRun.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
            $para.Inlines.Add($msgRun) | Out-Null
            $doc.Blocks.Add($para) | Out-Null
            $script:ConsoleBox.ScrollToEnd()
            $script:ConsoleWindow.Dispatcher.Invoke([action] {}, 'Render')
        } catch {
        }
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Remove-RegistryValue {
    param([string]$Path, [string]$Name, [switch]$Silent)
    try {
        if (Test-Path $Path) {
            $current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $current.$Name) {
                Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
                if (-not $Silent) {
                    Write-Log "Gelöscht: $Path\$Name" -Level Success
                }
                $script:ChangesCount++
                return $true
            }
        }
    } catch {
        if (-not $Silent) {
            Write-Log "Das Entfernen von $Path\$Name ist fehlgeschlagen - $($_.Exception.Message)" -Level Warning
        }
    }
    return $false
}

function Set-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [switch]$Silent)
    try {
        if (!(Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        if (-not $Silent) {
            Write-Log "Festgelegt: $Path\$Name = $Value" -Level Success
        }
        $script:ChangesCount++
        return $true
    } catch {
        if (-not $Silent) {
            Write-Log "$Path\$Name konnte nicht festgelegt werden - $($_.Exception.Message)" -Level Warning
        }
    }
    return $false
}

function Remove-RegistryKey {
    param([string]$Path, [switch]$Silent)
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            if (-not $Silent) {
                Write-Log "Schlüssel entfernt: $Path" -Level Success
            }
            $script:ChangesCount++
            return $true
        }
    } catch {
        if (-not $Silent) {
            Write-Log "Schlüssel $Path konnte nicht entfernt werden - $($_.Exception.Message)" -Level Warning
        }
    }
    return $false
}

function Restore-ServiceStartup {
    param([string]$ServiceName, [string]$StartupType, [switch]$Silent)
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc) {
            Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction Stop
            if (-not $Silent) {
                Write-Log "Der Dienst $ServiceName ist auf $StartupType festgelegt" -Level Success
            }
            $script:ChangesCount++
            return $true
        }
    } catch {
        if (-not $Silent) {
            Write-Log "Konfiguration des Dienstes $ServiceName ist fehlgeschlagen. - $($_.Exception.Message)" -Level Warning
        }
    }
    return $false
}

function Enable-ScheduledTaskSafe {
    param([string]$TaskPath, [string]$TaskName, [switch]$Silent)
    try {
        $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Enable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
            if (-not $Silent) {
                Write-Log "Aktivierte Aufgabe: $TaskPath$TaskName" -Level Success
            }
            $script:ChangesCount++
            return $true
        }
    } catch {
        if (-not $Silent) {
            Write-Log "Die Aktivierung der Aufgabe $TaskPath$TaskName ist fehlgeschlagen - $($_.Exception.Message)" -Level Warning
        }
    }
    return $false
}
# ============================================================================
# CATEGORY 1: PRIVACY & TELEMETRY (COMPREHENSIVE)
# ============================================================================

# ============================================================================
# RESTORATION FUNCTIONS - COMPREHENSIVE v3.1
# Covers: privacy.sexy, debloat scripts, group policies, registry tweaks
# ============================================================================

function Restore-PrivacyTelemetry {
    Write-Log '=== DATENSCHUTZ UND TELEMETRIE (UMFASSEND) ===' -Level Section

    # ---- CapabilityAccessManager ConsentStore (restore ALL to Allow) ----
    Write-Log 'Zugriffsberechtigungen für App-Funktionen wiederherstellen...' -Level Info
    @(
        'documentsLibrary', 'picturesLibrary', 'videosLibrary', 'musicLibrary',
        'broadFileSystemAccess', 'phoneCallHistory', 'phoneCall', 'chat',
        'bluetooth', 'bluetoothSync', 'activity', 'appointments', 'contacts',
        'email', 'userDataTasks', 'userNotificationListener', 'radios',
        'userAccountInformation', 'webcam', 'microphone', 'location',
        'appDiagnostics', 'gazeInput', 'graphicsCaptureProgrammatic',
        'graphicsCaptureWithoutBorder', 'humanInterfaceDevice', 'humanPresence',
        'backgroundSpatialPerception', 'spatialPerception'
    ) | ForEach-Object {
        Set-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$_" -Name 'Value' -Value 'Allow' -Type 'String' -Silent
    }
    $script:ChangesCount++

    # ---- AppPrivacy GPO (remove ALL forced deny/allow) ----
    Write-Log 'AppPrivacy Gruppenrichtlinien entfernen...' -Level Info
    @(
        'LetAppsAccessCallHistory', 'LetAppsAccessPhone', 'LetAppsAccessMessaging',
        'LetAppsSyncWithDevices', 'LetAppsAccessTrustedDevices', 'LetAppsAccessMotion',
        'LetAppsAccessCamera', 'LetAppsAccessMicrophone', 'LetAppsAccessLocation',
        'LetAppsAccessAccountInfo', 'LetAppsAccessContacts', 'LetAppsAccessCalendar',
        'LetAppsAccessEmail', 'LetAppsAccessTasks', 'LetAppsAccessRadios',
        'LetAppsAccessNotifications', 'LetAppsGetDiagnosticInfo', 'LetAppsAccessGazeInput',
        'LetAppsRunInBackground', 'LetAppsActivateWithVoice', 'LetAppsActivateWithVoiceAboveLock',
        'LetAppsAccessBackgroundSpatialPerception', 'LetAppsAccessGraphicsCaptureProgrammatic',
        'LetAppsAccessGraphicsCaptureWithoutBorder', 'LetAppsAccessHumanPresence'
    ) | ForEach-Object {
        $base = $_
        Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name $base -Silent
        Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name "${base}_UserInControlOfTheseApps" -Silent
        Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name "${base}_ForceAllowTheseApps" -Silent
        Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name "${base}_ForceDenyTheseApps" -Silent
    }
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Silent
    $script:ChangesCount++

    # ---- Legacy DeviceAccess GUIDs (pre-1903) ----
    Write-Log 'Wiederherstellung der Zugriffseinstellungen für ältere Geräte...' -Level Info
    @(
        'LooselyCoupled',
        '{C1D23ACC-752B-43E5-8448-8D0E519CD6D6}',
        '{2EEF81BE-33FA-4800-9670-1CD474972C3F}',
        '{52079E78-A92B-413F-B213-E8FE35712E72}',
        '{7D7E8402-7C54-4821-A34E-AEEFD62DED93}',
        '{D89823BA-7180-4B81-B50C-7E471E6121A3}',
        '{8BC668CF-7728-45BD-93F8-CF2B3B41D7AB}',
        '{9231CB4C-BF57-4AF3-8C55-FDA7BFCC04C5}',
        '{E6AD100E-5F4E-44CD-BE0F-2265D88D14F5}',
        '{2297E4E2-5DBE-466D-A12B-0F8286F0D9CA}',
        '{E390DF20-07DF-446D-B962-F5C953062741}',
        '{992AFA70-6F47-4148-B3E9-3003349C1548}',
        '{21157C1F-2651-4CC1-90CA-1F28B02263F6}',
        '{BFA794E4-F964-4FDB-90F6-51056BFE4B44}',
        '{E5323777-F976-4f5b-9B55-B94699C46E44}',
        '{A8804298-2D5F-42E3-9531-9C8C39EB29CE}'
    ) | ForEach-Object {
        Remove-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\$_" -Name 'Value' -Silent
    }

    # ---- Telemetry & Diagnostics ----
    Write-Log 'Telemetrie- und Diagnoseeinstellungen wiederherstellen...' -Level Info
    # DataCollection policies
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'MaxTelemetryAllowed' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'DoNotShowFeedbackNotifications' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowDeviceNameInTelemetry' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowCommercialDataPipeline' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'MicrosoftEdgeDataOptIn' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowDesktopAnalyticsProcessing' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowUpdateComplianceProcessing' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowWUfBCloudProcessing' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'LimitEnhancedDiagnosticDataWindowsAnalytics' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'DisableOneSettingsDownloads' -Silent

    # SQM Client
    Remove-RegistryValue -Path 'HKLM:\Software\Microsoft\SQMClient\Windows' -Name 'CEIPEnable' -Silent
    Remove-RegistryValue -Path 'HKLM:\Software\Policies\Microsoft\SQMClient\Windows' -Name 'CEIPEnable' -Silent
    Remove-RegistryValue -Path 'HKLM:\Software\Microsoft\SQMClient' -Name 'MSFTInternal' -Silent

    # VS/CEIP SQM
    @('14.0', '15.0', '16.0', '17.0') | ForEach-Object {
        Remove-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\VSCommon\$_\SQM" -Name 'OptIn' -Silent
        Remove-RegistryValue -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\VSCommon\$_\SQM" -Name 'OptIn' -Silent
    }

    # License telemetry
    Remove-RegistryValue -Path 'HKLM:\Software\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform' -Name 'NoGenTicket' -Silent

    # Customer Experience
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' -Name 'PreventDeviceMetadataFromNetwork' -Silent

    # TIPC (text input telemetry)
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Input\TIPC' -Name 'Enabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Input\TIPC' -Name 'Enabled' -Silent

    # Input personalization
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' -Name 'HarvestContacts' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings' -Name 'AcceptedPrivacyPolicy' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' -Silent

    # Handwriting error reports
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' -Silent

    # Advertising ID
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' -Silent

    # Feedback
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' -Name 'NumberOfSIUFInPeriod' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' -Name 'PeriodInNanoSeconds' -Silent

    # Privacy consent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name 'DisablePrivacyExperience' -Silent

    # App Compatibility / Telemetry collector
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Silent
    Remove-RegistryKey -Path 'HKLM:\Software\Policies\Microsoft\Windows\AppCompat' -Silent

    # IFEO blocks on telemetry executables (remove debugger redirects)
    @('CompatTelRunner.exe', 'DeviceCensus.exe', 'upfc.exe') | ForEach-Object {
        Remove-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$_" -Silent
    }

    # Restore CompatTelRunner.exe and DeviceCensus.exe if renamed to .OLD
    @("$env:SystemRoot\System32\CompatTelRunner.exe", "$env:SystemRoot\System32\DeviceCensus.exe") | ForEach-Object {
        $oldPath = "$_.OLD"
        if ((Test-Path $oldPath) -and !(Test-Path $_)) {
            try {
                Rename-Item -Path $oldPath -NewName (Split-Path $_ -Leaf) -Force -EA Stop; $script:ChangesCount++
            } catch {
            }
        }
    }

    # Bluetooth telemetry
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowBuildPreview' -Silent

    # Disk diagnostics
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WDI\{9c5a40da-b965-4fc3-8781-88dd50a6299d}' -Name 'ScenarioExecutionEnabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WDI\{29689E29-2CE9-4751-B4FC-8EFF5066E3FD}' -Name 'ScenarioExecutionEnabled' -Silent

    # Experimentation
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\System\AllowExperimentation' -Name 'value' -Silent

    # Location sensor overrides
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' -Name 'SensorPermissionState' -Silent

    # Location/sensors policy
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Silent

    # Location service configuration
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' -Name 'Status' -Silent

    # Wi-Fi Sense
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' -Name 'value' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' -Name 'value' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' -Name 'AutoConnectAllowedOEM' -Silent

    # Website Language List access
    Remove-RegistryValue -Path 'HKCU:\Control Panel\International\User Profile' -Name 'HttpAcceptLanguageOptOut' -Silent

    # Activity Feed / Timeline
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Silent

    # App launch tracking
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackProgs' -Silent

    # Maps auto-download
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Maps' -Silent

    # Game DVR/screen recording
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Silent
    Remove-RegistryValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Silent

    # DRM internet access
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WMDRM' -Silent

    # Cloud speech recognition
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' -Name 'HasAccepted' -Silent
    Remove-RegistryValue -Path 'HKLM:\Software\Microsoft\Speech_OneCore\Preferences' -Name 'ModelDownloadAllowed' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Speech_OneCore\Preferences' -Name 'VoiceActivationOn' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps' -Name 'AgentActivationEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps' -Name 'AgentActivationOnLockScreenEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps' -Name 'AgentActivationLastUsed' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps' -Name 'ActiveAboveLockLastUsed' -Silent

    # Recall
    Remove-RegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -Silent

    # Restore DiagTrack / diagnostics services
    @(
        @{N = 'DiagTrack'; T = 'Automatic' },
        @{N = 'dmwappushservice'; T = 'Manual' },
        @{N = 'diagnosticshub.standardcollector.service'; T = 'Manual' },
        @{N = 'diagsvc'; T = 'Manual' },
        @{N = 'PcaSvc'; T = 'Manual' },
        @{N = 'wercplsupport'; T = 'Manual' },
        @{N = 'wersvc'; T = 'Manual' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }

    # Restore telemetry scheduled tasks
    @(
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'Microsoft Compatibility Appraiser' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'ProgramDataUpdater' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'AitAgent' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'StartupAppTask' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'PcaPatchDbTask' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'SdbinstMergeDbTask' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'MareBackup' },
        @{P = '\Microsoft\Windows\Autochk\'; N = 'Proxy' },
        @{P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' },
        @{P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip' },
        @{P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'KernelCeipTask' },
        @{P = '\Microsoft\Windows\Device Information\'; N = 'Device' },
        @{P = '\Microsoft\Windows\Device Information\'; N = 'Device User' },
        @{P = '\Microsoft\Windows\DiskDiagnostic\'; N = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        @{P = '\Microsoft\Windows\DiskDiagnostic\'; N = 'Microsoft-Windows-DiskDiagnosticResolver' },
        @{P = '\Microsoft\Windows\Feedback\Siuf\'; N = 'DmClient' },
        @{P = '\Microsoft\Windows\Feedback\Siuf\'; N = 'DmClientOnScenarioDownload' },
        @{P = '\Microsoft\Windows\PI\'; N = 'Sqm-Tasks' },
        @{P = '\Microsoft\Windows\NetTrace\'; N = 'GatherNetworkInfo' }
    ) | ForEach-Object { Enable-ScheduledTaskSafe -TaskPath $_.P -TaskName $_.N -Silent }

    Write-Log 'Datenschutz und Telemetrie: Abgeschlossen' -Level Success
}

function Restore-CopilotCortanaAI {
    Write-Log '=== COPILOT, CORTANA & KI ===' -Level Section

    # ---- Copilot ----
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowCopilotButton' -Silent

    # ---- Cortana (comprehensive) ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Experience\AllowCortana' -Name 'value' -Silent
    # Cortana policies
    @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search',
        'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    ) | ForEach-Object {
        Remove-RegistryValue -Path $_ -Name 'AllowCortana' -Silent
        Remove-RegistryValue -Path $_ -Name 'AllowCortanaAboveLock' -Silent
        Remove-RegistryValue -Path $_ -Name 'AllowSearchToUseLocation' -Silent
        Remove-RegistryValue -Path $_ -Name 'ConnectedSearchUseWeb' -Silent
        Remove-RegistryValue -Path $_ -Name 'ConnectedSearchUseWebOverMeteredConnections' -Silent
        Remove-RegistryValue -Path $_ -Name 'DisableWebSearch' -Silent
        Remove-RegistryValue -Path $_ -Name 'AllowCloudSearch' -Silent
        Remove-RegistryValue -Path $_ -Name 'EnableDynamicContentInWSB' -Silent
    }
    # Cortana user settings
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'VoiceShortcut' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'CanCortanaBeEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'DeviceHistoryEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaConsent' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'HasAboveLockTips' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'HistoryViewEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'IsAssignedAccess' -Silent

    # Cortana indexing settings
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowIndexingEncryptedStoresOrItems' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AlwaysUseAutoLangDetection' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'PreventRemoteQueries' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'PreventUnindexedItemsInSearchResults' -Silent

    Write-Log 'Copilot, Cortana & KI: Abgeschlossen' -Level Success
}

function Restore-BingSearchWidgets {
    Write-Log '=== BING SUCHE & WIDGETS ===' -Level Section

    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchSpokenEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaConsent' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' -Name 'IsAADCloudSearchEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' -Name 'IsMSACloudSearchEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' -Name 'IsDeviceSearchHistoryEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' -Name 'IsDynamicSearchBoxEnabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Silent

    # Widgets / Web Experience Pack
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Silent

    # Windows search highlights
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'EnableDynamicContentInWSB' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' -Name 'IsDynamicSearchBoxEnabled' -Silent

    Write-Log 'Bing Suche & Widgets: Abgeschlossen' -Level Success
}

function Restore-TaskbarUI {
    Write-Log '=== TASKBAR & UI ===' -Level Section

    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowTaskViewButton' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarMn' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAl' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowCopilotButton' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People' -Name 'PeopleBand' -Silent
    # Meet Now
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideSCAMeetNow' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideSCAMeetNow' -Silent

    Write-Log 'Taskbar & UI: Abgeschlossen' -Level Success
}

function Restore-ExplorerSettings {
    Write-Log '=== EXPLORER EINSTELLUNGEN ===' -Level Section

    # This PC folder restores (remove registry deletions that hid folders)
    @(
        '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}',  # Desktop
        '{d3162b92-9365-467a-956b-92703aca08af}',    # Documents
        '{088e3905-0323-4b02-9826-5d99428e115f}',    # Downloads
        '{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}',    # Music
        '{24ad3ad4-a569-4530-98e1-ab02f9417aa8}',    # Pictures
        '{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}',    # Videos
        '{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}'     # 3D Objects
    ) | ForEach-Object {
        $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\$_"
        if (!(Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force -EA 0 | Out-Null; $script:ChangesCount++
        }
    }
    # FolderDescriptions PropertyBag (restore ThisPCPolicy to Show)
    @(
        '0ddd015d-b06c-45d5-8c4c-f59713854639',  # Documents
        '35286a68-3c57-41a1-bbb1-0eae73d76c95',   # Videos
        '7d83ee9b-2244-4e70-b1f5-5393042af1e4',   # Downloads
        'a0c69a99-21c8-4671-8703-7934162fcf1d',    # Music
        'f42ee2d3-909f-4907-8871-4c22fc0bf756'     # Pictures
    ) | ForEach-Object {
        Set-RegistryValue -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\{$_}\PropertyBag" -Name 'ThisPCPolicy' -Value 'Show' -Type 'String' -Silent
        Set-RegistryValue -Path "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\{$_}\PropertyBag" -Name 'ThisPCPolicy' -Value 'Show' -Type 'String' -Silent
    }

    # Explorer policies
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoNewAppAlert' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'NoNewAppAlert' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackDocs' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'LaunchTo' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Silent

    # Recent documents
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoRecentDocsHistory' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'ClearRecentDocsOnExit' -Silent

    # Sync provider notifications
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Silent

    # Internet file association / web publishing
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoInternetOpenWith' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoOnlinePrintsWizard' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoPublishingWizard' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoWebServices' -Silent

    Write-Log 'Explorer Einstellungen: Abgeschlossen' -Level Success
}

function Restore-StartMenuSettings {
    Write-Log '=== START MENU ===' -Level Section
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_TrackProgs' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_IrisRecommendations' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_AccountNotifications' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_Layout' -Silent
    Write-Log 'Start Menu: Abgeschlossen' -Level Success
}

function Restore-ThemeSettings {
    Write-Log '=== THEME & PERSONALIZATION ===' -Level Section
    # Windows Tips
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Silent
    Remove-RegistryKey -Path 'HKLM:\Software\Policies\Microsoft\Windows\CloudContent' -Silent
    # Content Delivery Manager
    @(
        'SubscribedContent-338387Enabled', 'SubscribedContent-338389Enabled',
        'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled',
        'SubscribedContent-353696Enabled', 'SubscribedContent-310093Enabled',
        'SubscribedContent-338388Enabled', 'SubscribedContent-314563Enabled',
        'SubscribedContent-353698Enabled', 'RotatingLockScreenEnabled',
        'RotatingLockScreenOverlayEnabled', 'SilentInstalledAppsEnabled',
        'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled',
        'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled',
        'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled',
        'FeatureManagementEnabled', 'RemediationRequired'
    ) | ForEach-Object {
        Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name $_ -Silent
    }
    # Suggested content in Settings
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338393Enabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-353694Enabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-353696Enabled' -Silent
    # Spotlight / lock screen
    Remove-RegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightFeatures' -Silent
    # Camera on/off OSD
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\OEM\Device\Capture' -Name 'NoPhysicalCameraLED' -Silent

    Write-Log 'Theme & Personalization: Abgeschlossen' -Level Success
}

function Restore-ContentDeliveryManager {
    Write-Log '=== INHALTSBEREITSTELLUNG / WERBUNG ===' -Level Section
    @(
        'SubscribedContent-338387Enabled', 'SubscribedContent-338389Enabled',
        'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled',
        'SubscribedContent-353696Enabled', 'SubscribedContent-310093Enabled',
        'SubscribedContent-338388Enabled', 'SubscribedContent-314563Enabled',
        'SubscribedContent-353698Enabled', 'RotatingLockScreenEnabled',
        'RotatingLockScreenOverlayEnabled', 'SilentInstalledAppsEnabled',
        'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled',
        'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled',
        'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled',
        'FeatureManagementEnabled', 'RemediationRequired'
    ) | ForEach-Object {
        Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name $_ -Silent
    }
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Silent
    Remove-RegistryKey -Path 'HKLM:\Software\Policies\Microsoft\Windows\CloudContent' -Silent
    Write-Log 'Inhaltsbereitstellung: Abgeschlossen' -Level Success
}

function Restore-BluetoothSettings {
    Write-Log '=== BLUETOOTH ===' -Level Section
    @(
        @{N = 'bthserv'; T = 'Manual' },
        @{N = 'BTAGService'; T = 'Manual' },
        @{N = 'BthAvctpSvc'; T = 'Manual' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }
    Write-Log 'Bluetooth: Abgeschlossen' -Level Success
}

function Restore-NotificationSettings {
    Write-Log '=== BENACHRICHTIGUNGEN ===' -Level Section
    Remove-RegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'NoToastApplicationNotification' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings' -Name 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'LockScreenToastEnabled' -Silent
    # Live tiles
    Remove-RegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'NoCloudApplicationNotification' -Silent
    # App suggestions (Look for app in Store)
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost' -Name 'EnableWebContentEvaluation' -Silent

    Write-Log 'BENACHRICHTIGUNGEN: Abgeschlossen' -Level Success
}

function Restore-OOBESettings {
    Write-Log '=== OOBE & SETUP ===' -Level Section
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name 'DisablePrivacyExperience' -Silent
    # Reserved storage
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' -Name 'ShippedWithReserves' -Silent
    # NTP server restore
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name 'NtpServer' -Value 'time.windows.com,0x9' -Type 'String' -Silent
    Write-Log 'OOBE & Setup: Abgeschlossen' -Level Success
}

function Restore-DefenderSettings {
    Write-Log '=== WINDOWS DEFENDER (UMFASSEND) ===' -Level Section

    # ---- Remove ALL Defender group policies ----
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Antimalware' -Silent

    # ---- Individual policy reversals (extensive - every known GPO value) ----
    $defBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    @(
        @{P = $defBase; N = 'DisableAntiSpyware' },
        @{P = $defBase; N = 'DisableAntiVirus' },
        @{P = $defBase; N = 'DisableRoutinelyTakingAction' },
        @{P = $defBase; N = 'ServiceKeepAlive' },
        @{P = $defBase; N = 'AllowFastServiceStartup' },
        @{P = $defBase; N = 'PUAProtection' },
        @{P = $defBase; N = 'RandomizeScheduleTaskTimes' },
        @{P = "$defBase\Real-Time Protection"; N = 'DisableRealtimeMonitoring' },
        @{P = "$defBase\Real-Time Protection"; N = 'DisableBehaviorMonitoring' },
        @{P = "$defBase\Real-Time Protection"; N = 'DisableOnAccessProtection' },
        @{P = "$defBase\Real-Time Protection"; N = 'DisableScanOnRealtimeEnable' },
        @{P = "$defBase\Real-Time Protection"; N = 'DisableIOAVProtection' },
        @{P = "$defBase\Real-Time Protection"; N = 'DisableIntrusionPreventionSystem' },
        @{P = "$defBase\Real-Time Protection"; N = 'DisableRawWriteNotification' },
        @{P = "$defBase\Real-Time Protection"; N = 'DisableInformationProtectionControl' },
        @{P = "$defBase\Real-Time Protection"; N = 'RealtimeScanDirection' },
        @{P = "$defBase\Real-Time Protection"; N = 'LocalSettingOverrideDisableRealtimeMonitoring' },
        @{P = "$defBase\Real-Time Protection"; N = 'IOAVMaxSize' },
        @{P = "$defBase\Spynet"; N = 'SpyNetReporting' },
        @{P = "$defBase\Spynet"; N = 'SubmitSamplesConsent' },
        @{P = "$defBase\Spynet"; N = 'DisableBlockAtFirstSeen' },
        @{P = "$defBase\Spynet"; N = 'LocalSettingOverrideSpynetReporting' },
        @{P = "$defBase\MpEngine"; N = 'MpEnablePus' },
        @{P = "$defBase\MpEngine"; N = 'MpCloudBlockLevel' },
        @{P = "$defBase\MpEngine"; N = 'MpBafsExtendedTimeout' },
        @{P = "$defBase\MpEngine"; N = 'EnableFileHashComputation' },
        @{P = "$defBase\Reporting"; N = 'DisableEnhancedNotifications' },
        @{P = "$defBase\Reporting"; N = 'DisableGenericRePorts' },
        @{P = "$defBase\Scan"; N = 'DisableArchiveScanning' },
        @{P = "$defBase\Scan"; N = 'DisableRemovableDriveScanning' },
        @{P = "$defBase\Scan"; N = 'DisableEmailScanning' },
        @{P = "$defBase\Scan"; N = 'DisableScanningMappedNetworkDrivesForFullScan' },
        @{P = "$defBase\Scan"; N = 'DisableScanningNetworkFiles' },
        @{P = "$defBase\Scan"; N = 'DisablePackedExeScanning' },
        @{P = "$defBase\Scan"; N = 'DisableReparsePointScanning' },
        @{P = "$defBase\Scan"; N = 'DisableHeuristics' },
        @{P = "$defBase\Scan"; N = 'DisableScanOnUpdate' },
        @{P = "$defBase\Scan"; N = 'DisableCatchupFullScan' },
        @{P = "$defBase\Scan"; N = 'DisableCatchupQuickScan' },
        @{P = "$defBase\Scan"; N = 'DisableRestorePoint' },
        @{P = "$defBase\Scan"; N = 'CheckForSignaturesBeforeRunningScan' },
        @{P = "$defBase\Scan"; N = 'ScanParameters' },
        @{P = "$defBase\Scan"; N = 'ScheduleDay' },
        @{P = "$defBase\Scan"; N = 'ScheduleTime' },
        @{P = "$defBase\Scan"; N = 'ScheduleQuickScanTime' },
        @{P = "$defBase\Scan"; N = 'AvgCPULoadFactor' },
        @{P = "$defBase\Scan"; N = 'LowCpuPriority' },
        @{P = "$defBase\Scan"; N = 'ScanOnlyIfIdle' },
        @{P = "$defBase\Scan"; N = 'PurgeItemsAfterDelay' },
        @{P = "$defBase\Scan"; N = 'MissedScheduledScanCountBeforeCatchup' },
        @{P = "$defBase\Scan"; N = 'ArchiveMaxDepth' },
        @{P = "$defBase\Scan"; N = 'ArchiveMaxSize' },
        @{P = "$defBase\Signature Updates"; N = 'ForceUpdateFromMU' },
        @{P = "$defBase\Signature Updates"; N = 'UpdateOnStartUp' },
        @{P = "$defBase\Signature Updates"; N = 'SignatureUpdateInterval' },
        @{P = "$defBase\Signature Updates"; N = 'ScheduleDay' },
        @{P = "$defBase\Signature Updates"; N = 'ScheduleTime' },
        @{P = "$defBase\Signature Updates"; N = 'ASSignatureDue' },
        @{P = "$defBase\Signature Updates"; N = 'AVSignatureDue' },
        @{P = "$defBase\Signature Updates"; N = 'SignatureUpdateCatchupInterval' },
        @{P = "$defBase\Signature Updates"; N = 'DisableUpdateOnStartupWithoutEngine' },
        @{P = "$defBase\Signature Updates"; N = 'SignatureDisableNotification' },
        @{P = "$defBase\Signature Updates"; N = 'FallbackOrder' },
        @{P = "$defBase\Signature Updates"; N = 'DefinitionUpdateFileSharesSources' },
        @{P = "$defBase\Signature Updates"; N = 'SignatureFirstAuGracePeriod' },
        @{P = "$defBase\Windows Defender Exploit Guard\ASR"; N = 'ExploitGuard_ASR_Rules' },
        @{P = "$defBase\Windows Defender Exploit Guard\Network Protection"; N = 'EnableNetworkProtection' },
        @{P = "$defBase\Windows Defender Exploit Guard\Controlled Folder Access"; N = 'EnableControlledFolderAccess' },
        @{P = "$defBase\Features"; N = 'TamperProtection' },
        @{P = "$defBase\UX Configuration"; N = 'Notification_Suppress' },
        @{P = "$defBase\UX Configuration"; N = 'UILockdown' },
        @{P = "$defBase\Remediation"; N = 'Scan_ScheduleDay' },
        @{P = "$defBase\Remediation"; N = 'LocalSettingOverrideScan_ScheduleDay' },
        @{P = "$defBase\Quarantine"; N = 'PurgeItemsAfterDelay' },
        @{P = "$defBase\Quarantine"; N = 'LocalPurgeItemsAfterDelay' }
    ) | ForEach-Object { Remove-RegistryValue -Path $_.P -Name $_.N -Silent }

    # ---- User-level Defender overrides ----
    @('DisableAntiSpyware', 'DisableAntiVirus', 'PassiveMode') | ForEach-Object {
        Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender' -Name $_ -Silent
    }
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection' -Name 'DisableRealtimeMonitoring' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Features' -Name 'TamperProtection' -Silent

    # ---- Remove exclusions added by debloat scripts ----
    @('Paths', 'Extensions', 'Processes', 'TemporaryPaths', 'IpAddresses') | ForEach-Object {
        Remove-RegistryKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\$_" -Silent
    }
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions' -Silent

    # ---- IFEO blocks (remove debugger redirects that block Defender EXEs) ----
    Write-Log 'Entfernen von Sperren für die Ausführung von Bilddateien in Defender...' -Level Info
    @(
        'MsMpEng.exe', 'NisSrv.exe', 'MpCmdRun.exe', 'MpCopyAccelerator.exe',
        'MpDefenderCoreService.exe', 'MpDlpCmd.exe', 'MpDlpService.exe',
        'ConfigSecurityPolicy.exe', 'SecurityHealthHost.exe', 'SecurityHealthService.exe',
        'SgrmBroker.exe', 'SgrmLpac.exe', 'smartscreen.exe'
    ) | ForEach-Object {
        Remove-RegistryKey -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$_" -Silent
    }
    $script:ChangesCount++

    # ---- Restore renamed Defender EXEs (.OLD files) ----
    Write-Log 'Prüfung auf umbenannte Defender-Ausführungsdateien...' -Level Info
    $defenderPaths = @(
        "$env:ProgramFiles\Windows Defender",
        "$env:ProgramFiles\Windows Defender Advanced Threat Protection",
        "$env:ProgramData\Microsoft\Windows Defender\Platform"
    )
    foreach ($dp in $defenderPaths) {
        if (Test-Path $dp) {
            Get-ChildItem -Path $dp -Filter '*.OLD' -Recurse -EA 0 | ForEach-Object {
                $newName = $_.FullName -replace '\.OLD$', ''
                if (!(Test-Path $newName)) {
                    try {
                        Rename-Item -Path $_.FullName -NewName (Split-Path $newName -Leaf) -Force -EA Stop
                        Write-Log "Wiederhergestellt: $($_.Name)" -Level Success; $script:ChangesCount++
                    } catch {
                        Write-Log "$($_.Name) konnte nicht wiederhergestellt werden: $($_.Exception.Message)" -Level Warning
                    }
                }
            }
        }
    }

    # ---- Restore Defender services (comprehensive) ----
    Write-Log 'Defender Dienste wiederherstellen...' -Level Info
    @(
        @{N = 'WinDefend'; T = 'Automatic' },
        @{N = 'WdNisSvc'; T = 'Manual' },
        @{N = 'WdFilter'; T = 'Boot' },
        @{N = 'WdBoot'; T = 'Boot' },
        @{N = 'WdNisDrv'; T = 'Manual' },
        @{N = 'SecurityHealthService'; T = 'Manual' },
        @{N = 'wscsvc'; T = 'Automatic' },
        @{N = 'Sense'; T = 'Manual' },
        @{N = 'SgrmAgent'; T = 'Manual' },
        @{N = 'SgrmBroker'; T = 'Automatic' },
        @{N = 'MsSecCore'; T = 'Manual' },
        @{N = 'MsSecFlt'; T = 'Boot' },
        @{N = 'MsSecWfp'; T = 'Boot' },
        @{N = 'MDDlpSvc'; T = 'Manual' },
        @{N = 'webthreatdefsvc'; T = 'Manual' },
        @{N = 'webthreatdefusersvc'; T = 'Manual' }
    ) | ForEach-Object {
        Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent
        # Boot/System drivers: also fix via registry Start value
        if ($_.T -eq 'Boot') {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($_.N)"
            if (Test-Path $regPath) {
                Set-ItemProperty -Path $regPath -Name 'Start' -Value 0 -Force -EA 0
            }
        }
    }

    # ---- ETW / Event Log providers ----
    Set-RegistryValue -Path 'HKLM:\System\CurrentControlSet\Control\WMI\Autologger\DefenderApiLogger' -Name 'Start' -Value 1 -Silent
    Set-RegistryValue -Path 'HKLM:\System\CurrentControlSet\Control\WMI\Autologger\DefenderAuditLogger' -Name 'Start' -Value 1 -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Windows Defender/Operational' -Name 'Enabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Windows Defender/WHC' -Name 'Enabled' -Silent

    # ---- AMSI (re-enable) ----
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows Script Host\Settings' -Name 'Enabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\AMSI\Providers' -Name 'ForceDisable' -Silent

    # ---- Scheduled Tasks ----
    @(
        'Windows Defender Cache Maintenance', 'Windows Defender Cleanup',
        'Windows Defender Scheduled Scan', 'Windows Defender Verification',
        'Windows Defender ExploitGuard MDM Refresh'
    ) | ForEach-Object { Enable-ScheduledTaskSafe -TaskPath '\Microsoft\Windows\Windows Defender\' -TaskName $_ -Silent }

    # ---- Security Center notifications ----
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center' -Silent

    # ---- Restore Security Health tray ----
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'SecurityHealth' -Value '%ProgramFiles%\Windows Defender\MSASCuiL.exe' -Type 'ExpandString' -Silent

    # ---- Malicious Software Removal Tool ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MRT' -Name 'DontReportInfectionInformation' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MRT' -Name 'DontOfferThroughWUAU' -Silent

    # ---- Start WinDefend if stopped ----
    try {
        $def = Get-Service -Name 'WinDefend' -EA 0
        if ($def -and $def.Status -eq 'Stopped') {
            Start-Service -Name 'WinDefend' -EA 0
            Write-Log 'WinDefend-Dienst gestartet' -Level Success
        }
    } catch {
        Write-Log 'WinDefend konnte nicht gestartet werden – Neustart erforderlich' -Level Warning
    }

    # ---- Force signature update ----
    try {
        $mpCmd = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
        if (Test-Path $mpCmd) {
            Start-Process -FilePath $mpCmd -ArgumentList '-SignatureUpdate' -NoNewWindow -Wait -EA 0
            Write-Log 'Aktualisierung der Defender-Signatur ausgelöst' -Level Success
        }
    } catch {
        Write-Log 'Die Signaturaktualisierung konnte nicht ausgelöst werden' -Level Warning
    }

    Write-Log 'Windows Defender: Abgeschlossen' -Level Success
}

function Restore-SmartScreenSettings {
    Write-Log '=== SMARTSCREEN (UMFASSEND) ===' -Level Section

    # IFEO block on smartscreen.exe
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\smartscreen.exe' -Silent

    # SmartScreen policies
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'SmartScreenEnabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableSmartScreen' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'ShellSmartScreenLevel' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'ConfigureAppInstallControl' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'ConfigureAppInstallControlEnabled' -Silent

    # SmartScreen for Store apps
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost' -Name 'EnableWebContentEvaluation' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost' -Name 'PreventOverride' -Silent

    # Edge SmartScreen
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'SmartScreenEnabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'SmartScreenPuaEnabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'PreventSmartScreenPromptOverride' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'PreventSmartScreenPromptOverrideForFiles' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'SmartScreenDnsRequestsEnabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'SmartScreenForTrustedDownloadsEnabled' -Silent

    # Edge Legacy SmartScreen
    Remove-RegistryValue -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\PhishingFilter' -Name 'EnabledV9' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\PhishingFilter' -Name 'PreventOverride' -Silent

    # IE SmartScreen
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\PhishingFilter' -Name 'EnabledV9' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\PhishingFilter' -Name 'PreventOverride' -Silent

    # Enhanced Phishing Protection
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WTDS\Components' -Silent

    # Restore SmartScreen EXE if renamed
    $ssPath = "$env:SystemRoot\System32\smartscreen.exe"
    if ((Test-Path "$ssPath.OLD") -and !(Test-Path $ssPath)) {
        try {
            Rename-Item -Path "$ssPath.OLD" -NewName 'smartscreen.exe' -Force -EA Stop; $script:ChangesCount++
        } catch {
        }
    }

    Write-Log 'SmartScreen: Abgeschlossen' -Level Success
}

function Restore-FirewallSettings {
    Write-Log '=== WINDOWS FIREWALL (UMFASSEND) ===' -Level Section

    # ---- Firewall registry (all profiles) ----
    @('DomainProfile', 'PublicProfile', 'StandardProfile') | ForEach-Object {
        Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\$_" -Name 'EnableFirewall' -Value 1 -Silent
        Remove-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\$_" -Name 'DoNotAllowExceptions' -Silent
    }

    # ---- Firewall policies ----
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall' -Silent

    # ---- Firewall services ----
    @(
        @{N = 'MpsSvc'; T = 'Automatic' },
        @{N = 'mpsdrv'; T = 'Manual' },
        @{N = 'BFE'; T = 'Automatic' },
        @{N = 'SharedAccess'; T = 'Manual' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }

    # ---- WFP callout driver ----
    Restore-ServiceStartup -ServiceName 'MsSecWfp' -StartupType 'Boot' -Silent

    # ---- Enable firewall via netsh ----
    try {
        Start-Process -FilePath 'netsh' -ArgumentList 'advfirewall set allprofiles state on' -NoNewWindow -Wait -EA 0
        Write-Log 'Firewall über netsh aktiviert' -Level Success
        $script:ChangesCount++
    } catch {
        Write-Log 'Die Firewall konnte über netsh nicht aktiviert werden.' -Level Warning
    }

    # ---- Windows Security Firewall section ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Firewall and network protection' -Name 'UILockdown' -Silent

    Write-Log 'Windows Firewall: Abgeschlossen' -Level Success
}

function Restore-WindowsSecurityUI {
    Write-Log '=== WINDOWS-SICHERHEITS-BENUTZEROBERFLÄCHE ===' -Level Section

    # ---- Security Center sections (re-enable all hidden sections) ----
    @(
        'Virus and threat protection',
        'Firewall and network protection',
        'App and browser control',
        'Device security',
        'Device performance and health',
        'Family options',
        'Account protection'
    ) | ForEach-Object {
        Remove-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\$_" -Name 'UILockdown' -Silent
    }
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security' -Name 'DisableClearTpmButton' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security' -Name 'HideSecureBoot' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security' -Name 'HideTPMTroubleshooting' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Device security' -Name 'DisableTpmFirmwareUpdateWarning' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center' -Silent

    # ---- Security and Maintenance notifications ----
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance' -Name 'Enabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance' -Name 'Enabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'DisableNotificationCenter' -Silent

    # ---- Defender notification settings ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\UX Configuration' -Name 'Notification_Suppress' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Reporting' -Name 'DisableEnhancedNotifications' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name 'UILockdown' -Silent

    # ---- Restore "Scan with Defender" context menu ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -Name '{09A47860-11B0-4DA5-AFA5-26D86198A780}' -Silent

    # ---- Security Health Agent ----
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService' -Name 'Start' -Silent

    # ---- VBS / Device Guard (restore defaults, don't force enable) ----
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'EnableVirtualizationBasedSecurity' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' -Name 'RequirePlatformSecurityFeatures' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled' -Silent

    Write-Log 'WINDOWS-SICHERHEITS-BENUTZEROBERFLÄCHE: Abgeschlossen' -Level Success
}

function Restore-WindowsUpdateSettings {
    Write-Log '=== WINDOWS UPDATE (VOLLSTÄNDIGE REPARATUR) ===' -Level Section

    # ---- Remove ALL WU policies ----
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' -Silent

    # ---- AU policy reversals ----
    @('NoAutoUpdate', 'AUOptions', 'AutoInstallMinorUpdates', 'NoAutoRebootWithLoggedOnUsers',
        'RebootRelaunchTimeout', 'RebootRelaunchTimeoutEnabled', 'RebootWarningTimeout',
        'RebootWarningTimeoutEnabled', 'ScheduledInstallDay', 'ScheduledInstallTime', 'UseWUServer',
        'AlwaysAutoRebootAtScheduledTime', 'AlwaysAutoRebootAtScheduledTimeMinutes',
        'IncludeRecommendedUpdates', 'AutomaticMaintenanceEnabled', 'DetectionFrequency',
        'DetectionFrequencyEnabled', 'RescheduleWaitTime', 'RescheduleWaitTimeEnabled'
    ) | ForEach-Object { Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name $_ -Silent }

    # ---- WU base policies ----
    @('WUServer', 'WUStatusServer', 'UpdateServiceUrlAlternate', 'DisableWindowsUpdateAccess',
        'SetDisableUXWUAccess', 'ExcludeWUDriversInQualityUpdate', 'ManagePreviewBuilds',
        'ManagePreviewBuildsPolicyValue', 'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays',
        'BranchReadinessLevel', 'DeferQualityUpdates', 'DeferQualityUpdatesPeriodInDays',
        'TargetReleaseVersion', 'TargetReleaseVersionInfo', 'ProductVersion',
        'SetPolicyDrivenUpdateSourceForFeatureUpdates', 'SetPolicyDrivenUpdateSourceForQualityUpdates',
        'SetPolicyDrivenUpdateSourceForDriverUpdates', 'SetPolicyDrivenUpdateSourceForOtherUpdates',
        'DisableDualScan', 'DoNotEnforceEnterpriseTLSCertPinningForUpdateDetection',
        'SetProxyBehaviorForUpdateDetection', 'AllowAutoWindowsUpdateDownloadOverMeteredNetwork',
        'SetAutoRestartNotificationDisable', 'SetEDURestart', 'SetRestartWarningSchd',
        'SetUpdateNotificationLevel', 'ConfigureDeadlineForFeatureUpdates',
        'ConfigureDeadlineForQualityUpdates', 'ConfigureDeadlineGracePeriod',
        'ConfigureDeadlineNoAutoReboot', 'DoNotConnectToWindowsUpdateInternetLocations',
        'SetPolicyDrivenUpdateSourceForFeatureUpdates', 'SetPolicyDrivenUpdateSourceForQualityUpdates',
        'SetPolicyDrivenUpdateSourceForDriverUpdates', 'SetPolicyDrivenUpdateSourceForOtherUpdates'
    ) | ForEach-Object { Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name $_ -Silent }

    # ---- UX Settings ----
    @('ActiveHoursStart', 'ActiveHoursEnd', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime',
        'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime', 'PauseUpdatesStartTime',
        'PauseUpdatesExpiryTime', 'FlightSettingsMaxPauseDays', 'IsExpedited', 'LastActiveHoursState'
    ) | ForEach-Object { Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -Name $_ -Silent }

    # ---- PolicyManager update policies ----
    @('Pause', 'PauseFeatureUpdates', 'PauseQualityUpdates', 'RequireDeferUpgrade',
        'DeferFeatureUpdatesPeriodInDays', 'DeferQualityUpdatesPeriodInDays',
        'ExcludeWUDriversInQualityUpdate', 'ConfigureDeadlineForFeatureUpdates',
        'ConfigureDeadlineForQualityUpdates'
    ) | ForEach-Object {
        Remove-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Update\$_" -Name 'value' -Silent
    }

    # ---- WU driver search ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'SearchOrderConfig' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'DontSearchWindowsUpdate' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' -Silent

    # ---- Delivery Optimization ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' -Name 'DODownloadMode' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization' -Name 'SystemSettingsDownloadMode' -Silent
    Remove-RegistryValue -Path 'HKU:\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings' -Name 'DownloadMode' -Silent

    # ---- WSUS/SCCM cleanup ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -Name 'AUOptions' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -Name 'EnableFeaturedSoftware' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -Name 'IncludeRecommendedUpdates' -Silent

    # ---- IFEO blocks on WU executables ----
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\WaaSMedicAgent.exe' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\upfc.exe' -Silent

    # ---- UpdatePolicy ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings' -Name 'PausedQualityDate' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings' -Name 'PausedFeatureDate' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState' -Name 'PausedQualityDate' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\PolicyState' -Name 'PausedFeatureDate' -Silent

    # ---- Restore WU services ----
    @(
        @{N = 'wuauserv'; T = 'Manual' },
        @{N = 'WaaSMedicSvc'; T = 'Manual' },
        @{N = 'UsoSvc'; T = 'Automatic' },
        @{N = 'DoSvc'; T = 'Automatic' },
        @{N = 'BITS'; T = 'Manual' },
        @{N = 'TrustedInstaller'; T = 'Manual' },
        @{N = 'InstallService'; T = 'Manual' },
        @{N = 'msiserver'; T = 'Manual' },
        @{N = 'CryptSvc'; T = 'Automatic' },
        @{N = 'AppReadiness'; T = 'Manual' },
        @{N = 'uhssvc'; T = 'Manual' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }

    # ---- Start critical services ----
    @('CryptSvc', 'BITS', 'wuauserv') | ForEach-Object {
        try {
            $s = Get-Service -Name $_ -EA 0; if ($s -and $s.Status -eq 'Stopped') {
                Start-Service -Name $_ -EA 0
            }
        } catch {
        }
    }

    # ---- Restore WU scheduled tasks (exhaustive) ----
    @(
        @{P = '\Microsoft\Windows\WindowsUpdate\'; N = 'Scheduled Start' },
        @{P = '\Microsoft\Windows\WindowsUpdate\'; N = 'sih' },
        @{P = '\Microsoft\Windows\WindowsUpdate\'; N = 'sihboot' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan Static Task' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'USO_UxBroker' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Report policies' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Maintenance Work' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Work' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Wake To Work' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'UpdateModelTask' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Refresh Settings' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot_AC' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot_Battery' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'RestoreDevice' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'ScanForUpdates' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'ScanForUpdatesAsUser' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'SmartRetry' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'WakeUpAndContinueUpdates' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'WakeUpAndScanForUpdates' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Start Oobe Expedite Work' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'StartOobeAppsScan_LicenseAccepted' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'StartOobeAppsScan_OobeAppReady' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'StartOobeAppsScanAfterUpdate' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'UUS Failover Task' },
        @{P = '\Microsoft\Windows\WaaSMedic\'; N = 'PerformRemediation' },
        @{P = '\Microsoft\Windows\Servicing\'; N = 'StartComponentCleanup' }
    ) | ForEach-Object { Enable-ScheduledTaskSafe -TaskPath $_.P -TaskName $_.N -Silent }

    # ---- Reset SoftwareDistribution and catroot2 ----
    Write-Log 'Zurücksetzen der Windows Update Komponentenspeicher...' -Level Info
    try {
        @('wuauserv', 'BITS', 'CryptSvc', 'msiserver') | ForEach-Object { Stop-Service -Name $_ -Force -EA 0 }
        $sdPath = "$env:SystemRoot\SoftwareDistribution"
        $sdBak = "$env:SystemRoot\SoftwareDistribution.bak"
        if (Test-Path $sdPath) {
            if (Test-Path $sdBak) {
                Remove-Item -Path $sdBak -Recurse -Force -EA 0
            }
            try {
                Rename-Item -Path $sdPath -NewName 'SoftwareDistribution.bak' -Force -EA Stop
                Write-Log 'SoftwareDistribution wurde in .bak umbenannt.' -Level Success; $script:ChangesCount++
            } catch {
                Write-Log 'SoftwareDistribution wird verwendet – wird nach dem Neustart zurückgesetzt.' -Level Warning
            }
        }
        $crPath = "$env:SystemRoot\System32\catroot2"
        $crBak = "$env:SystemRoot\System32\catroot2.bak"
        if (Test-Path $crPath) {
            if (Test-Path $crBak) {
                Remove-Item -Path $crBak -Recurse -Force -EA 0
            }
            try {
                Rename-Item -Path $crPath -NewName 'catroot2.bak' -Force -EA Stop
                Write-Log 'catroot2 in .bak umbenannt' -Level Success; $script:ChangesCount++
            } catch {
                Write-Log 'catroot2 in use - will reset after reboot' -Level Warning
            }
        }
        @('CryptSvc', 'BITS', 'wuauserv') | ForEach-Object { Start-Service -Name $_ -EA 0 }
    } catch {
        Write-Log 'Teilweises Zurücksetzen der Komponente – Neustart empfohlen' -Level Warning
    }

    # ---- Re-register WU DLLs ----
    Write-Log 'Re-registering Windows Update DLLs...' -Level Info
    @('atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll', 'jscript.dll', 'vbscript.dll',
        'scrrun.dll', 'msxml.dll', 'msxml3.dll', 'msxml6.dll', 'actxprxy.dll', 'softpub.dll', 'wintrust.dll',
        'dssenh.dll', 'rsaenh.dll', 'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll', 'oleaut32.dll',
        'ole32.dll', 'shell32.dll', 'initpki.dll', 'wuapi.dll', 'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll',
        'wups.dll', 'wups2.dll', 'wuweb.dll', 'qmgr.dll', 'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll', 'wuwebv.dll'
    ) | ForEach-Object {
        $dll = "$env:SystemRoot\System32\$_"
        if (Test-Path $dll) {
            Start-Process -FilePath 'regsvr32.exe' -ArgumentList "/s `"$dll`"" -NoNewWindow -Wait -EA 0
        }
    }
    Write-Log 'WU DLLs erneut registriert' -Level Success; $script:ChangesCount++

    # ---- Winsock and proxy reset ----
    Start-Process -FilePath 'netsh' -ArgumentList 'winsock reset' -NoNewWindow -Wait -EA 0
    Start-Process -FilePath 'netsh' -ArgumentList 'winhttp reset proxy' -NoNewWindow -Wait -EA 0
    Write-Log 'Winsock und proxy reset' -Level Success; $script:ChangesCount++

    # ---- Settings visibility ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'SettingsPageVisibility' -Silent

    # ---- Zone information / attachments ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments' -Name 'SaveZoneInformation' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments' -Name 'SaveZoneInformation' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments' -Name 'ScanWithAntiVirus' -Silent

    # ---- Trigger WU scan ----
    try {
        Start-Process -FilePath 'UsoClient.exe' -ArgumentList 'StartScan' -NoNewWindow -Wait -EA 0
        Write-Log 'Windows Update Suche gestartet' -Level Success
    } catch {
        Write-Log 'WU-Scan konnte nicht gestartet werden – dies erfolgt nach dem Neustart.' -Level Warning
    }

    Write-Log 'Windows Update: Abgeschlossen (Neustart empfohlen)' -Level Success
}

function Restore-EdgeSettings {
    Write-Log '=== MICROSOFT EDGE (UMFASSEND) ===' -Level Section

    # Remove all Edge policies (massive list)
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Silent
    Remove-RegistryKey -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Edge' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Silent
    Remove-RegistryKey -Path 'HKCU:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Silent

    # Edge (Legacy)
    Remove-RegistryValue -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main' -Name 'DoNotTrack' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\FlipAhead' -Name 'FPEnabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\ServiceUI' -Name 'ShowSearchHistory' -Silent

    # Edge update IFEO
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MicrosoftEdgeUpdate.exe' -Silent

    # Edge update services
    @(
        @{N = 'edgeupdate'; T = 'Automatic' },
        @{N = 'edgeupdatem'; T = 'Manual' },
        @{N = 'MicrosoftEdgeElevationService'; T = 'Manual' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }

    # Edge update scheduled tasks
    Get-ScheduledTask -TaskName 'MicrosoftEdgeUpdate*' -EA 0 | ForEach-Object {
        Enable-ScheduledTask -InputObject $_ -EA 0 | Out-Null; $script:ChangesCount++
    }

    Write-Log 'Edge: Abgeschlossen' -Level Success
}

function Restore-ChromeSettings {
    Write-Log '=== CHROME & GOOGLE ===' -Level Section
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Silent
    Remove-RegistryKey -Path 'HKCU:\SOFTWARE\Policies\Google\Chrome' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Google\Update' -Silent
    # Software Reporter Tool IFEO
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\software_reporter_tool.exe' -Silent
    # Google update services
    @(
        @{N = 'gupdate'; T = 'Automatic' },
        @{N = 'gupdatem'; T = 'Manual' },
        @{N = 'GoogleChromeElevationService'; T = 'Manual' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }
    # Google update tasks
    Get-ScheduledTask -TaskName 'GoogleUpdate*' -EA 0 | ForEach-Object {
        Enable-ScheduledTask -InputObject $_ -EA 0 | Out-Null; $script:ChangesCount++
    }
    Write-Log 'Chrome & Google: Abgeschlossen' -Level Success
    # Also restore Firefox
    Restore-FirefoxSettings
}

function Restore-FirefoxSettings {
    Write-Log '=== FIREFOX ===' -Level Section
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -Silent
    Remove-RegistryKey -Path 'HKCU:\SOFTWARE\Policies\Mozilla\Firefox' -Silent
    Write-Log 'Firefox: Abgeschlossen' -Level Success
}

function Restore-OfficeSettings {
    Write-Log '=== MICROSOFT OFFICE ===' -Level Section
    @('15.0', '16.0') | ForEach-Object {
        Remove-RegistryValue -Path "HKCU:\Software\Microsoft\Office\$_\Common\General" -Name 'ShownFirstRunOptin' -Silent
        Remove-RegistryValue -Path "HKCU:\Software\Microsoft\Office\$_\Common" -Name 'QMEnable' -Silent
        Remove-RegistryValue -Path "HKCU:\Software\Microsoft\Office\$_\Common" -Name 'UpdateReliabilityData' -Silent
        Remove-RegistryValue -Path "HKCU:\Software\Microsoft\Office\$_\Common\Feedback" -Name 'Enabled' -Silent
        Remove-RegistryValue -Path "HKCU:\Software\Microsoft\Office\$_\Common\ClientTelemetry" -Name 'DisableTelemetry' -Silent
        Remove-RegistryValue -Path "HKCU:\Software\Microsoft\Office\$_\Outlook\Options\Mail" -Name 'EnableLogging' -Silent
        Remove-RegistryValue -Path "HKCU:\Software\Microsoft\Office\$_\Word\Options" -Name 'EnableLogging' -Silent
    }
    # Office telemetry agent task
    Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'OfficeTelemetryAgentFallBack*' -EA 0 | ForEach-Object {
        Enable-ScheduledTask -InputObject $_ -EA 0 | Out-Null
    }
    Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'OfficeTelemetryAgentLogOn*' -EA 0 | ForEach-Object {
        Enable-ScheduledTask -InputObject $_ -EA 0 | Out-Null
    }
    # Subscription heartbeat
    Get-ScheduledTask -TaskPath '\Microsoft\Office\' -TaskName 'Office*' -EA 0 | ForEach-Object {
        Enable-ScheduledTask -InputObject $_ -EA 0 | Out-Null
    }
    Write-Log 'Office: Abgeschlossen' -Level Success
}

function Restore-NetworkSettings {
    Write-Log '=== NETZWERKVERBINDUNG ===' -Level Section

    # ---- NCSI (Network Connectivity Status Indicator) ----
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet' -Name 'EnableActiveProbing' -Silent

    # ---- Restore NCSI EXE if renamed ----
    $ncsiPath = "$env:SystemRoot\System32\NCSI.dll"
    if ((Test-Path "$ncsiPath.OLD") -and !(Test-Path $ncsiPath)) {
        try {
            Rename-Item "$ncsiPath.OLD" -NewName 'NCSI.dll' -Force -EA Stop
        } catch {
        }
    }

    # ---- NLA and network services ----
    @(
        @{N = 'NlaSvc'; T = 'Automatic' },
        @{N = 'netprofm'; T = 'Manual' },
        @{N = 'Dnscache'; T = 'Automatic' },
        @{N = 'WinHttpAutoProxySvc'; T = 'Manual' },
        @{N = 'LanmanServer'; T = 'Automatic' },
        @{N = 'LanmanWorkstation'; T = 'Automatic' },
        @{N = 'lmhosts'; T = 'Manual' },
        @{N = 'iphlpsvc'; T = 'Automatic' },
        @{N = 'SSDPSRV'; T = 'Manual' },
        @{N = 'upnphost'; T = 'Manual' },
        @{N = 'Dhcp'; T = 'Automatic' },
        @{N = 'WlanSvc'; T = 'Automatic' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }

    # ---- Admin shares ----
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters' -Name 'AutoShareServer' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters' -Name 'AutoShareWks' -Silent

    Write-Log 'NETZWERKVERBINDUNG: Abgeschlossen' -Level Success
}

function Restore-HostsFile {
    Write-Log '=== HOSTS DATEI BEREINIGEN ===' -Level Section

    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (!(Test-Path $hostsPath)) {
        Write-Log 'Hosts Datei wurde nicht gefunden' -Level Warning; return
    }

    try {
        $content = [System.IO.File]::ReadAllText($hostsPath, [System.Text.Encoding]::UTF8)
        $originalLen = $content.Length

        # Remove all privacy.sexy managed entries
        $content = $content -replace '(?m)^0\.0\.0\.0\t[^\r\n]+# managed by privacy\.sexy\r?\n?', ''
        $content = $content -replace '(?m)^::1\t[^\r\n]+# managed by privacy\.sexy\r?\n?', ''

        # Also remove common debloat script host blocks (0.0.0.0 entries for MS telemetry)
        $knownBlockedDomains = @(
            'vortex-win.data.microsoft.com', 'v10.events.data.microsoft.com',
            'v10c.events.data.microsoft.com', 'v10.vortex-win.data.microsoft.com',
            'watson.telemetry.microsoft.com', 'settings-win.data.microsoft.com',
            'settings.data.microsoft.com', 'telecommand.telemetry.microsoft.com',
            'self.events.data.microsoft.com', 'umwatson.events.data.microsoft.com',
            'functional.events.data.microsoft.com', 'oca.telemetry.microsoft.com',
            'eu-v10c.events.data.microsoft.com', 'us-v10c.events.data.microsoft.com'
        )
        foreach ($domain in $knownBlockedDomains) {
            $content = $content -replace "(?m)^0\.0\.0\.0\s+$([regex]::Escape($domain))\s*.*\r?\n?", ''
            $content = $content -replace "(?m)^::1\s+$([regex]::Escape($domain))\s*.*\r?\n?", ''
            $content = $content -replace "(?m)^127\.0\.0\.1\s+$([regex]::Escape($domain))\s*.*\r?\n?", ''
        }

        # Clean up excessive blank lines
        $content = $content -replace '(\r?\n){3,}', "`r`n`r`n"

        if ($content.Length -ne $originalLen) {
            [System.IO.File]::WriteAllText($hostsPath, $content, [System.Text.Encoding]::UTF8)
            Write-Log 'Gesperrte Host-Einträge aus der Hosts-Datei entfernt' -Level Success
            $script:ChangesCount++
        } else {
            Write-Log 'In der Hosts-Datei wurden keine gesperrten Einträge gefunden' -Level Info
        }
    } catch {
        Write-Log "Hosts Datei konnte nicht geändert werden: $($_.Exception.Message)" -Level Warning
    }

    # ---- Flush DNS cache ----
    try {
        Start-Process -FilePath 'ipconfig' -ArgumentList '/flushdns' -NoNewWindow -Wait -EA 0
        Write-Log 'DNS-Cache geleert' -Level Success
    } catch {
    }

    Write-Log 'Bereinigung der Hosts-Datei: Abgeschlossen' -Level Success
}

function Restore-GamingSettings {
    Write-Log '=== GAMING & XBOX ===' -Level Section
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Silent
    Remove-RegistryValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Silent
    @(
        @{N = 'XblAuthManager'; T = 'Manual' },
        @{N = 'XblGameSave'; T = 'Manual' },
        @{N = 'XboxGipSvc'; T = 'Manual' },
        @{N = 'XboxNetApiSvc'; T = 'Manual' },
        @{N = 'GamingServices'; T = 'Manual' },
        @{N = 'GamingServicesNet'; T = 'Manual' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }
    Write-Log 'Gaming & Xbox: Abgeschlossen' -Level Success
}

function Restore-BiometricsSettings {
    Write-Log '=== BIOMETRICS ===' -Level Section
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics\Credential Provider' -Silent
    Restore-ServiceStartup -ServiceName 'WbioSrvc' -StartupType 'Manual' -Silent
    Write-Log 'Biometrics: Abgeschlossen' -Level Success
}

function Restore-ClipboardSettings {
    Write-Log '=== CLIPBOARD ===' -Level Section
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'AllowClipboardHistory' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'AllowCrossDeviceClipboard' -Silent
    # Clipboard service
    @('cbdhsvc', 'cbdhsvc_*') | ForEach-Object {
        $svc = Get-Service -Name $_ -EA 0
        if ($svc) {
            Restore-ServiceStartup -ServiceName $svc.Name -StartupType 'Automatic' -Silent
        }
    }
    Write-Log 'Clipboard: Abgeschlossen' -Level Success
}

function Restore-ErrorReporting {
    Write-Log '=== FEHLERMELDUNGEN ===' -Level Section
    Remove-RegistryKey -Path 'HKLM:\Software\Policies\Microsoft\Windows\Windows Error Reporting' -Silent
    Remove-RegistryValue -Path 'HKLM:\Software\Microsoft\Windows\Windows Error Reporting' -Name 'Disabled' -Silent
    Remove-RegistryValue -Path 'HKLM:\Software\Microsoft\Windows\Windows Error Reporting\Consent' -Name 'DefaultConsent' -Silent
    Remove-RegistryValue -Path 'HKLM:\Software\Microsoft\Windows\Windows Error Reporting\Consent' -Name 'DefaultOverrideBehavior' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name 'DontSendAdditionalData' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name 'LoggingDisabled' -Silent
    Restore-ServiceStartup -ServiceName 'wersvc' -StartupType 'Manual' -Silent
    Restore-ServiceStartup -ServiceName 'wercplsupport' -StartupType 'Manual' -Silent
    Write-Log 'FEHLERMELDUNGEN: Abgeschlossen' -Level Success
}

function Restore-SecurityProtocols {
    Write-Log '=== SICHERHEITSPROTOKOLLE ===' -Level Section
    Write-Log 'Hinweis: Änderungen an Sicherheitsprotokollen werden unverändert belassen (Härtung), sofern nicht ausdrücklich anders gewünscht.' -Level Info
    # These are SECURITY HARDENING changes - we restore the registry keys but don't weaken security
    # Only restore things that might break functionality

    # ---- LSA protections (restore defaults, not weaken) ----
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\LSA' -Name 'RestrictAnonymousSAM' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\LSA' -Name 'RestrictAnonymous' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\LSA' -Name 'NoLMHash' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\LSA' -Name 'LmCompatibilityLevel' -Silent

    # ---- Admin shares (restore) ----
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters' -Name 'RestrictNullSessAccess' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters' -Name 'AutoShareServer' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters' -Name 'AutoShareWks' -Silent

    # ---- Remote Assistance ----
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name 'fAllowToGetHelp' -Silent

    # ---- Windows Connect Now ----
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WCN\Registrars' -Silent

    # ---- SMBv1 driver (restore if disabled) ----
    Restore-ServiceStartup -ServiceName 'mrxsmb10' -StartupType 'Manual' -Silent

    Write-Log 'SICHERHEITSPROTOKOLLE: Abgeschlossen' -Level Success
}

function Restore-RemoteDesktopSettings {
    Write-Log '=== REMOTE DESKTOP ===' -Level Section
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Silent
    @(
        @{N = 'TermService'; T = 'Manual' },
        @{N = 'UmRdpService'; T = 'Manual' },
        @{N = 'SessionEnv'; T = 'Manual' }
    ) | ForEach-Object { Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent }
    Write-Log 'Remote Desktop: Abgeschlossen' -Level Success
}

function Restore-AccessibilitySettings {
    Write-Log '=== BARRIEREFREIHEIT ===' -Level Section
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DisableCAD' -Silent
    Restore-ServiceStartup -ServiceName 'TabletInputService' -StartupType 'Manual' -Silent
    Write-Log 'BARRIEREFREIHEIT: Abgeschlossen' -Level Success
}

function Restore-InputSettings {
    Write-Log '=== EINGABE ===' -Level Section
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' -Name 'HarvestContacts' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings' -Name 'AcceptedPrivacyPolicy' -Silent
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' -Silent
    Write-Log 'Eingabe: Abgeschlossen' -Level Success
}

function Restore-PowerSettings {
    Write-Log '=== POWER & RUHEZUSTAND ===' -Level Section
    # Restore hibernation if it was disabled
    try {
        Start-Process -FilePath 'powercfg' -ArgumentList '/hibernate on' -NoNewWindow -Wait -EA 0
        Write-Log 'Ruhezustand wieder aktiviert' -Level Success
        $script:ChangesCount++
    } catch {
        Write-Log 'Der Ruhezustand konnte nicht wieder aktiviert werden' -Level Warning
    }
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -Silent
    Write-Log 'Power: Abgeschlossen' -Level Success
}

function Restore-MemoryPerformance {
    Write-Log '=== SPEICHER & LEISTUNG ===' -Level Section
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name 'ClearPageFileAtShutdown' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name 'EnablePrefetcher' -Silent
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name 'EnableSuperfetch' -Silent
    # SideBySide configuration
    Remove-RegistryValue -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\SideBySide\Configuration' -Name 'DisableResetbase' -Silent
    Write-Log 'Speicher und Leistung: Abgeschlossen' -Level Success
}

function Restore-StorageSettings {
    Write-Log '=== SPEICHER ===' -Level Section
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\StorageSense' -Name 'AllowStorageSenseGlobal' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' -Name 'ShippedWithReserves' -Silent
    Write-Log 'Speicher: Abgeschlossen' -Level Success
}

function Restore-PrintingSettings {
    Write-Log '=== DRUCKEN ===' -Level Section
    Restore-ServiceStartup -ServiceName 'Spooler' -StartupType 'Automatic' -Silent
    Restore-ServiceStartup -ServiceName 'PrintNotify' -StartupType 'Manual' -Silent
    Write-Log 'Drucken: Abgeschlossen' -Level Success
}

function Restore-UACSettings {
    Write-Log '=== UAC & SICHERHEITSRICHTLINIEN ===' -Level Section
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorUser' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'PromptOnSecureDesktop' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableInstallerDetection' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableSecureUIAPaths' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'FilterAdministratorToken' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableVirtualization' -Silent
    # Windows Installer elevated privileges
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer' -Name 'AlwaysInstallElevated' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer' -Name 'AlwaysInstallElevated' -Silent
    # CMD disable
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'DisableCMD' -Silent
    # Lock screen
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreenCamera' -Silent
    Write-Log 'UAC: Abgeschlossen' -Level Success
}

function Restore-OneDriveSettings {
    Write-Log '=== ONEDRIVE ===' -Level Section
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -Silent
    Set-RegistryValue -Path 'HKCU:\SOFTWARE\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' -Name 'System.IsPinnedToNameSpaceTree' -Value 1 -Silent
    Set-RegistryValue -Path 'HKCU:\SOFTWARE\Classes\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' -Name 'System.IsPinnedToNameSpaceTree' -Value 1 -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -Name 'OneDrive' -Silent
    Set-RegistryValue -Path 'HKCU:\Environment' -Name 'OneDrive' -Value '%USERPROFILE%\OneDrive' -Type 'ExpandString' -Silent
    Get-ScheduledTask -TaskPath '\' -TaskName 'OneDrive*' -EA 0 | ForEach-Object {
        Enable-ScheduledTask -InputObject $_ -EA 0 | Out-Null; $script:ChangesCount++
    }
    Write-Log 'OneDrive: Abgeschlossen' -Level Success
}

function Restore-SyncSettings {
    Write-Log '=== SYNC ===' -Level Section
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync' -Silent
    # Individual sync group overrides
    @('Credentials', 'Language') | ForEach-Object {
        Remove-RegistryValue -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\SettingSync\Groups\$_" -Name 'Enabled' -Silent
    }
    # Sync services
    @('OneSyncSvc', 'OneSyncSvc_*') | ForEach-Object {
        $svc = Get-Service -Name $_ -EA 0
        if ($svc) {
            Restore-ServiceStartup -ServiceName $svc.Name -StartupType 'Automatic' -Silent
        }
    }
    Write-Log 'Sync: Abgeschlossen' -Level Success
}

function Restore-WindowsInsiderSettings {
    Write-Log '=== INSIDER ===' -Level Section
    Remove-RegistryKey -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\UI\Visibility' -Name 'HideInsiderPage' -Silent
    Restore-ServiceStartup -ServiceName 'wisvc' -StartupType 'Manual' -Silent
    Write-Log 'Insider: Abgeschlossen' -Level Success
}

function Restore-ContextMenus {
    Write-Log '=== KONTEXTMENÜS ===' -Level Section
    Remove-RegistryKey -Path 'HKCU:\SOFTWARE\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -Name '{7AD84985-87B4-4a16-BE58-8B72A5B390F7}' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -Name '{1d27f844-3a1f-4410-85ac-14651078412d}' -Silent
    Write-Log 'Kontextmenüs: Abgeschlossen' -Level Success
}

function Restore-NvidiaTelemetry {
    Write-Log '=== NVIDIA TELEMETRIE ===' -Level Section
    # Nvidia telemetry tasks
    @('NvTmMon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
        'NvTmRep_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}',
        'NvTmRepOnLogon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}'
    ) | ForEach-Object {
        Enable-ScheduledTaskSafe -TaskPath '\' -TaskName $_ -Silent
    }
    Restore-ServiceStartup -ServiceName 'NvTelemetryContainer' -StartupType 'Automatic' -Silent
    # Nvidia driver telemetry registry
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\Startup' -Name 'SendTelemetryData' -Silent
    Remove-RegistryValue -Path 'HKLM:\Software\Nvidia Corporation\NvControlPanel2\Client' -Name 'OptInOrOutPreference' -Silent
    Write-Log 'Nvidia: Abgeschlossen' -Level Success
}

function Restore-ThirdPartyServices {
    Write-Log '=== THIRD-PARTY DIENSTE ===' -Level Section
    @(
        @{N = 'AdobeARMservice'; T = 'Automatic'; Opt = $true },
        @{N = 'adobeupdateservice'; T = 'Automatic'; Opt = $true },
        @{N = 'dbupdate'; T = 'Automatic'; Opt = $true },
        @{N = 'dbupdatem'; T = 'Automatic'; Opt = $true },
        @{N = 'WMPNetworkSvc'; T = 'Manual'; Opt = $false },
        @{N = 'Razer Game Scanner Service'; T = 'Manual'; Opt = $true },
        @{N = 'LogiRegistryService'; T = 'Automatic'; Opt = $true },
        @{N = 'VSStandardCollectorService150'; T = 'Manual'; Opt = $true }
    ) | ForEach-Object {
        $svc = Get-Service -Name $_.N -EA 0
        if ($svc -or !$_.Opt) {
            Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent
        }
    }
    # Adobe update task
    Get-ScheduledTask -TaskName 'Adobe Acrobat Update Task' -EA 0 | ForEach-Object {
        Enable-ScheduledTask -InputObject $_ -EA 0 | Out-Null
    }
    # Dropbox tasks
    Get-ScheduledTask -TaskName 'DropboxUpdate*' -EA 0 | ForEach-Object {
        Enable-ScheduledTask -InputObject $_ -EA 0 | Out-Null
    }
    # CCleaner
    Remove-RegistryValue -Path 'HKCU:\Software\Piriform\CCleaner' -Name 'Monitoring' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Piriform\CCleaner' -Name 'HelpImproveCCleaner' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Piriform\CCleaner' -Name 'SystemMonitoring' -Silent
    Write-Log 'Third-Party Dienste: Abgeschlossen' -Level Success
}

function Restore-MiscPolicies {
    Write-Log '=== VERSCHIEDENE RICHTLINIEN UND EINSTELLUNGEN ===' -Level Section

    # ---- Snipping Tool ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\TabletPC' -Name 'DisableSnippingTool' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'DisabledHotkeys' -Silent
    Remove-RegistryValue -Path 'HKCU:\Control Panel\Keyboard' -Name 'PrintScreenKeyForSnippingEnabled' -Silent

    # ---- Copilot auto-launch ----
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowCopilotButton' -Silent

    # ---- Retail Demo ----
    Restore-ServiceStartup -ServiceName 'RetailDemo' -StartupType 'Manual' -Silent

    # ---- Microsoft Account Sign-in Assistant ----
    Restore-ServiceStartup -ServiceName 'wlidsvc' -StartupType 'Manual' -Silent

    # ---- Downloaded Maps Manager ----
    Restore-ServiceStartup -ServiceName 'MapsBroker' -StartupType 'Automatic' -Silent

    # ---- User Data services ----
    @('UserDataSvc', 'UserDataSvc_*', 'UnistoreSvc', 'UnistoreSvc_*') | ForEach-Object {
        $svc = Get-Service -Name $_ -EA 0
        if ($svc) {
            Restore-ServiceStartup -ServiceName $svc.Name -StartupType 'Manual' -Silent
        }
    }

    # ---- Messaging Service ----
    @('MessagingService', 'MessagingService_*') | ForEach-Object {
        $svc = Get-Service -Name $_ -EA 0
        if ($svc) {
            Restore-ServiceStartup -ServiceName $svc.Name -StartupType 'Manual' -Silent
        }
    }

    # ---- Push Notifications ----
    @(
        @{N = 'WpnService'; T = 'Automatic' },
        @{N = 'WpnUserService'; T = 'Automatic' }
    ) | ForEach-Object {
        $svc = Get-Service -Name $_.N -EA 0
        if ($svc) {
            Restore-ServiceStartup -ServiceName $_.N -StartupType $_.T -Silent
        }
        # Also wildcard versions
        $wc = Get-Service -Name "$($_.N)_*" -EA 0
        if ($wc) {
            Restore-ServiceStartup -ServiceName $wc.Name -StartupType $_.T -Silent
        }
    }

    # ---- Shadow Copy (Volume Snapshot) ----
    Restore-ServiceStartup -ServiceName 'VSS' -StartupType 'Manual' -Silent

    # ---- Location Service ----
    Restore-ServiceStartup -ServiceName 'lfsvc' -StartupType 'Manual' -Silent

    # ---- DEP (Data Execution Prevention) - restore default ----
    try {
        Start-Process -FilePath 'bcdedit' -ArgumentList '/set {current} nx OptIn' -NoNewWindow -Wait -EA 0
        Write-Log 'DEP wurde auf OptIn zurückgesetzt' -Level Success
    } catch {
    }

    # ---- AutoPlay/AutoRun ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveTypeAutoRun' -Silent
    Remove-RegistryValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Silent

    # ---- Steps Recorder (restore if renamed) ----
    $psrPath = "$env:SystemRoot\System32\psr.exe"
    if ((Test-Path "$psrPath.OLD") -and !(Test-Path $psrPath)) {
        try {
            Rename-Item "$psrPath.OLD" -NewName 'psr.exe' -Force -EA Stop
        } catch {
        }
    }

    Write-Log 'Sonstige Richtlinien: Abgeschlossen' -Level Success
}

function Restore-Services {
    Write-Log '=== WICHTIGSTE WINDOWS DIENSTE ===' -Level Section
    $servicesToRestore = @{
        'wscsvc' = 'Automatic'; 'MpsSvc' = 'Automatic'; 'BFE' = 'Automatic'
        'TrkWks' = 'Automatic'; 'iphlpsvc' = 'Automatic'; 'lmhosts' = 'Manual'; 'NlaSvc' = 'Automatic'
        'Dnscache' = 'Automatic'; 'WinHttpAutoProxySvc' = 'Manual'; 'LanmanServer' = 'Automatic'
        'LanmanWorkstation' = 'Automatic'; 'SSDPSRV' = 'Manual'; 'upnphost' = 'Manual'; 'netprofm' = 'Manual'
        'bthserv' = 'Manual'; 'BTAGService' = 'Manual'; 'BthAvctpSvc' = 'Manual'
        'TermService' = 'Manual'; 'UmRdpService' = 'Manual'; 'SessionEnv' = 'Manual'; 'RemoteRegistry' = 'Disabled'
        'Audiosrv' = 'Automatic'; 'AudioEndpointBuilder' = 'Automatic'
        'Spooler' = 'Automatic'; 'PrintNotify' = 'Manual'
        'PhoneSvc' = 'Manual'; 'TapiSrv' = 'Manual'; 'SmsRouter' = 'Manual'
        'XblAuthManager' = 'Manual'; 'XblGameSave' = 'Manual'; 'XboxGipSvc' = 'Manual'; 'XboxNetApiSvc' = 'Manual'
        'GamingServices' = 'Manual'; 'GamingServicesNet' = 'Manual'
        'wlidsvc' = 'Manual'; 'MapsBroker' = 'Automatic'; 'lfsvc' = 'Manual'; 'VSS' = 'Manual'
        'WalletService' = 'Manual'; 'WpcMonSvc' = 'Manual'; 'WbioSrvc' = 'Manual'
        'TabletInputService' = 'Manual'; 'Fax' = 'Manual'; 'WMPNetworkSvc' = 'Manual'; 'icssvc' = 'Manual'
        'wisvc' = 'Manual'; 'CDPSvc' = 'Automatic'; 'ShellHWDetection' = 'Automatic'
        'Themes' = 'Automatic'; 'FontCache' = 'Automatic'; 'EventLog' = 'Automatic'; 'Schedule' = 'Automatic'
        'Power' = 'Automatic'; 'ProfSvc' = 'Automatic'; 'gpsvc' = 'Automatic'; 'Winmgmt' = 'Automatic'
        'CryptSvc' = 'Automatic'; 'Dhcp' = 'Automatic'; 'RpcSs' = 'Automatic'; 'SamSs' = 'Automatic'
        'WpnService' = 'Automatic'; 'W32Time' = 'Manual'; 'WlanSvc' = 'Automatic'; 'RetailDemo' = 'Manual'
    }
    $counter = 0
    foreach ($svc in $servicesToRestore.GetEnumerator()) {
        $counter++; Restore-ServiceStartup -ServiceName $svc.Key -StartupType $svc.Value -Silent
    }
    Write-Log "Dienste: $counter verarbeitet" -Level Success
}

function Restore-ScheduledTasks {
    Write-Log '=== GEPLANTE AUFGABEN ===' -Level Section
    $tasksToEnable = @(
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'Microsoft Compatibility Appraiser' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'ProgramDataUpdater' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'StartupAppTask' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'PcaPatchDbTask' },
        @{P = '\Microsoft\Windows\Autochk\'; N = 'Proxy' },
        @{P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' },
        @{P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip' },
        @{P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'KernelCeipTask' },
        @{P = '\Microsoft\Windows\Defrag\'; N = 'ScheduledDefrag' },
        @{P = '\Microsoft\Windows\Device Information\'; N = 'Device' },
        @{P = '\Microsoft\Windows\Device Information\'; N = 'Device User' },
        @{P = '\Microsoft\Windows\DiskDiagnostic\'; N = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        @{P = '\Microsoft\Windows\DiskFootprint\'; N = 'Diagnostics' },
        @{P = '\Microsoft\Windows\DiskFootprint\'; N = 'StorageSense' },
        @{P = '\Microsoft\Windows\Feedback\Siuf\'; N = 'DmClient' },
        @{P = '\Microsoft\Windows\Feedback\Siuf\'; N = 'DmClientOnScenarioDownload' },
        @{P = '\Microsoft\Windows\Maps\'; N = 'MapsToastTask' },
        @{P = '\Microsoft\Windows\Maps\'; N = 'MapsUpdateTask' },
        @{P = '\Microsoft\Windows\PI\'; N = 'Sqm-Tasks' },
        @{P = '\Microsoft\Windows\Power Efficiency Diagnostics\'; N = 'AnalyzeSystem' },
        @{P = '\Microsoft\Windows\RemoteAssistance\'; N = 'RemoteAssistanceTask' },
        @{P = '\Microsoft\Windows\Servicing\'; N = 'StartComponentCleanup' },
        @{P = '\Microsoft\Windows\SettingSync\'; N = 'NetworkStateChangeTask' },
        @{P = '\Microsoft\Windows\SettingSync\'; N = 'BackgroundUploadTask' },
        @{P = '\Microsoft\Windows\SettingSync\'; N = 'BackupTask' },
        @{P = '\Microsoft\Windows\Windows Defender\'; N = 'Windows Defender Cache Maintenance' },
        @{P = '\Microsoft\Windows\Windows Defender\'; N = 'Windows Defender Cleanup' },
        @{P = '\Microsoft\Windows\Windows Defender\'; N = 'Windows Defender Scheduled Scan' },
        @{P = '\Microsoft\Windows\Windows Defender\'; N = 'Windows Defender Verification' },
        @{P = '\Microsoft\Windows\Windows Defender\'; N = 'Windows Defender ExploitGuard MDM Refresh' },
        @{P = '\Microsoft\Windows\WindowsUpdate\'; N = 'Scheduled Start' },
        @{P = '\Microsoft\Windows\WindowsUpdate\'; N = 'sih' },
        @{P = '\Microsoft\Windows\WindowsUpdate\'; N = 'sihboot' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan Static Task' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'USO_UxBroker' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Report policies' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Maintenance Work' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Work' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Wake To Work' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'UpdateModelTask' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Refresh Settings' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot_AC' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Reboot_Battery' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'RestoreDevice' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'ScanForUpdates' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'ScanForUpdatesAsUser' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'SmartRetry' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'WakeUpAndContinueUpdates' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'WakeUpAndScanForUpdates' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Start Oobe Expedite Work' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'StartOobeAppsScan_LicenseAccepted' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'StartOobeAppsScan_OobeAppReady' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'StartOobeAppsScanAfterUpdate' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'UUS Failover Task' },
        @{P = '\Microsoft\Windows\WaaSMedic\'; N = 'PerformRemediation' },
        @{P = '\Microsoft\Windows\Maintenance\'; N = 'WinSAT' },
        @{P = '\Microsoft\Windows\NetTrace\'; N = 'GatherNetworkInfo' },
        @{P = '\Microsoft\Windows\Diagnosis\'; N = 'Scheduled' },
        @{P = '\Microsoft\Windows\Diagnosis\'; N = 'RecommendedTroubleshootingScanner' },
        @{P = '\Microsoft\Windows\Clip\'; N = 'License Validation' },
        @{P = '\Microsoft\Windows\File Classification Infrastructure\'; N = 'Property Definition Sync' },
        @{P = '\Microsoft\Windows\Management\Provisioning\'; N = 'Logon' },
        @{P = '\Microsoft\Windows\CloudExperienceHost\'; N = 'CreateObjectTask' },
        @{P = '\Microsoft\Windows\Windows Error Reporting\'; N = 'QueueReporting' }
    ) | ForEach-Object { Enable-ScheduledTaskSafe -TaskPath $_.P -TaskName $_.N -Silent }

    Write-Log 'Geplante Aufgaben: Abgeschlossen' -Level Success
}

function Restore-CryptoProtocols {
    Write-Log '=== KRYPTOPROTOKOLLE & SCHANNEL ===' -Level Section

    # ---- SCHANNEL Protocol Defaults (remove all explicit Enabled/DisabledByDefault overrides) ----
    # Restoring to Windows defaults means removing explicit registry entries
    # Windows will use its built-in defaults (TLS 1.2/1.3 enabled, SSL 2.0/3.0/TLS 1.0/1.1 disabled)
    Write-Log 'Wiederherstellen der SHANNEL-Protokolleinstellungen auf die Windows-Standardeinstellungen...' -Level Info
    $schBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL'

    # Protocols - remove all explicit overrides (let Windows manage defaults)
    @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1', 'TLS 1.2', 'TLS 1.3', 'DTLS 1.0', 'DTLS 1.2') | ForEach-Object {
        $proto = $_
        @('Client', 'Server') | ForEach-Object {
            $path = "$schBase\Protocols\$proto\$_"
            Remove-RegistryValue -Path $path -Name 'Enabled' -Silent
            Remove-RegistryValue -Path $path -Name 'DisabledByDefault' -Silent
        }
    }
    $script:ChangesCount++

    # ---- Ciphers (remove explicit disable overrides, let Windows manage) ----
    Write-Log 'Verschlüsselungseinstellungen werden wiederhergestellt...' -Level Info
    @(
        'DES 56/56', 'NULL', 'RC2 128/128', 'RC2 40/128', 'RC2 56/128',
        'RC4 128/128', 'RC4 40/128', 'RC4 56/128', 'RC4 64/128',
        'Triple DES 168', 'Triple DES 168/168'
    ) | ForEach-Object {
        $cipherPath = "$schBase\Ciphers\$_"
        Remove-RegistryValue -Path $cipherPath -Name 'Enabled' -Silent
        if (Test-Path $cipherPath) {
            $props = (Get-Item $cipherPath -EA 0).Property
            if (!$props -or $props.Count -eq 0) {
                Remove-Item -Path $cipherPath -Force -EA 0
            }
        }
    }

    # ---- Hashes ----
    Write-Log 'Einstellungen des Hash-Algorithmus wiederherstellen...' -Level Info
    @('MD5', 'SHA') | ForEach-Object {
        $hashPath = "$schBase\Hashes\$_"
        Remove-RegistryValue -Path $hashPath -Name 'Enabled' -Silent
        if (Test-Path $hashPath) {
            $props = (Get-Item $hashPath -EA 0).Property
            if (!$props -or $props.Count -eq 0) {
                Remove-Item -Path $hashPath -Force -EA 0
            }
        }
    }

    # ---- Key Exchange Algorithms (remove minimum key length overrides) ----
    Write-Log 'Wiederherstellen der Schlüsselaustauscheinstellungen...' -Level Info
    @('Diffie-Hellman', 'PKCS') | ForEach-Object {
        $kePath = "$schBase\KeyExchangeAlgorithms\$_"
        Remove-RegistryValue -Path $kePath -Name 'ClientMinKeyBitLength' -Silent
        Remove-RegistryValue -Path $kePath -Name 'ServerMinKeyBitLength' -Silent
    }

    # ---- SCHANNEL base settings ----
    Remove-RegistryValue -Path $schBase -Name 'AllowInsecureRenegoClients' -Silent
    Remove-RegistryValue -Path $schBase -Name 'AllowInsecureRenegoServers' -Silent
    Remove-RegistryValue -Path $schBase -Name 'DisableRenegoOnClient' -Silent
    Remove-RegistryValue -Path $schBase -Name 'DisableRenegoOnServer' -Silent
    Remove-RegistryValue -Path $schBase -Name 'UseScsvForTls' -Silent

    # ---- .NET Framework Strong Crypto (remove forced overrides) ----
    Write-Log 'Wiederherstellen der .NET Framework-Kryptoeinstellungen...' -Level Info
    @(
        'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727',
        'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
    ) | ForEach-Object {
        Remove-RegistryValue -Path $_ -Name 'SchUseStrongCrypto' -Silent
        Remove-RegistryValue -Path $_ -Name 'SystemDefaultTlsVersions' -Silent
    }

    # ---- WinRM basic auth (remove policy override) ----
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client' -Name 'AllowBasic' -Silent
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service' -Name 'AllowBasic' -Silent

    # ---- NetBIOS (restore to default DHCP-controlled) ----
    Write-Log 'NetBIOS auf Standard wiederherstellen (DHCP-gesteuert).)...' -Level Info
    try {
        $key = 'HKLM:\SYSTEM\CurrentControlSet\services\NetBT\Parameters\Interfaces'
        if (Test-Path $key) {
            Get-ChildItem $key -EA 0 | ForEach-Object {
                Set-ItemProperty -Path "$key\$($_.PSChildName)" -Name 'NetbiosOptions' -Value 0 -Force -EA 0
            }
            $script:ChangesCount++
        }
    } catch {
        Write-Log 'Die NetBIOS-Einstellungen konnten nicht wiederhergestellt werden' -Level Warning
    }

    # ---- SEHOP (Structured Exception Handler Overwrite Protection) ----
    Remove-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' -Name 'DisableExceptionChainValidation' -Silent

    Write-Log 'Kryptoprotokolle: Abgeschlossen' -Level Success
    # Also handle related security protocol settings
    Restore-SecurityProtocols
}

function Restore-WindowsFeatures {
    Write-Log '=== OPTIONALE WINDOWS FUNKTIONEN ===' -Level Section
    Write-Log 'Erneutes Aktivieren optionaler Windows Funktionen (dies kann mehrere Minuten dauern)...' -Level Info

    # Features that are enabled by default on a fresh Windows install
    $defaultEnabledFeatures = @(
        'MicrosoftWindowsPowerShellV2',
        'MicrosoftWindowsPowerShellV2Root',
        'WCF-TCP-PortSharing45',
        'SmbDirect',
        'Printing-Foundation-Features',
        'Printing-PrintToPDFServices-Features',
        'Printing-XPSServices-Features',
        'SearchEngine-Client-Package',
        'MediaPlayback',
        'WindowsMediaPlayer',
        'WorkFolders-Client'
    )

    # Features disabled by default (skip restoring these - they were disabled for security)
    $defaultDisabledFeatures = @(
        'SMB1Protocol', 'SMB1Protocol-Client', 'SMB1Protocol-Server',
        'TelnetClient', 'TFTP', 'DirectPlay', 'LegacyComponents',
        'FaxServicesClientPackage',
        'Internet-Explorer-Optional-amd64', 'Internet-Explorer-Optional-x64',
        'Xps-Foundation-Xps-Viewer', 'ScanManagementConsole',
        'Printing-Foundation-InternetPrinting-Client',
        'Printing-Foundation-LPDPrintService', 'Printing-Foundation-LPRPortMonitor'
    )

    foreach ($feature in $defaultEnabledFeatures) {
        try {
            $f = Get-WindowsOptionalFeature -FeatureName $feature -Online -EA Stop
            if ($f -and $f.State -ne 'Enabled') {
                Write-Log "Funktion erneut aktivierene: $feature" -Level Info
                Enable-WindowsOptionalFeature -FeatureName $feature -Online -NoRestart -LogLevel Errors -WarningAction SilentlyContinue -EA Stop | Out-Null
                Write-Log "Aktiviert: $feature" -Level Success
                $script:ChangesCount++
            }
        } catch {
            Write-Log "$feature konnte nicht aktiviert werden: $($_.Exception.Message)" -Level Warning
        }
    }

    Write-Log 'Hinweis: Sicherheitsfunktionen (SMB1, Telnet, TFTP, DirectPlay) wurden absichtlich deaktiviert' -Level Info
    Write-Log 'Windows Funktionen: Abgeschlossen' -Level Success
}

function Restore-AppxPackages {
    Write-Log '=== APPX PAKET WIEDERHERSTELLUNG ===' -Level Section
    Write-Log 'Es wird versucht, entfernte Windows Store Apps erneut zu installieren...' -Level Info

    # Core Windows packages that should be present on a stock install
    $corePackages = @(
        @{N = 'Microsoft.WindowsStore'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.StorePurchaseApp'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.DesktopAppInstaller'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.WindowsCalculator'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.Photos'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.WindowsCamera'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.WindowsAlarms'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.WindowsSoundRecorder'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.WindowsMaps'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.WindowsFeedbackHub'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.GetHelp'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Getstarted'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.MSPaint'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.People'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.ScreenSketch'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.MicrosoftStickyNotes'; P = '8wekyb3d8bbwe' },
        @{N = 'Microsoft.MicrosoftOfficeHub'; P = 'cw5n1h2txyewy' },
        @{N = 'microsoft.windowscommunicationsapps'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.YourPhone'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.HEIFImageExtension'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.VP9VideoExtensions'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.WebMediaExtensions'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.WebpImageExtension'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.RawImageExtension'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.HEVCVideoExtension'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Xbox.TCUI'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.XboxIdentityProvider'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.XboxGamingOverlay'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.XboxGameOverlay'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.XboxSpeechToTextOverlay'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.GamingApp'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.BingWeather'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.BingNews'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.ZuneMusic'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.ZuneVideo'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Todos'; P = 'cw5n1h2txyewy' }
    )

    # Critical system packages (must be present for Windows to function)
    $systemPackages = @(
        @{N = 'Microsoft.Windows.SecHealthUI'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.SecHealthUI'; P = '8wekyb3d8bbwe' },
        @{N = 'Microsoft.AAD.BrokerPlugin'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.AccountsControl'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.CloudExperienceHost'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.ContentDeliveryManager'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.Search'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.ShellExperienceHost'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.PeopleExperienceHost'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.CredDialogHost'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.BioEnrollment'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.LockApp'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.ECApp'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.AsyncTextService'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Win32WebViewHost'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.PPIProjection'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.Apprep.ChxApp'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.CapturePicker'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.OOBENetworkCaptivePortal'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.OOBENetworkConnectionFlow'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.PinningConfirmationDialog'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.ParentalControls'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.XboxGameCallableUI'; P = 'cw5n1h2txyewy' },
        @{N = 'NcsiUwpApp'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.PrintQueueActionCenter'; P = 'cw5n1h2txyewy' },
        @{N = 'MicrosoftWindows.Client.CBS'; P = 'cw5n1h2txyewy' },
        @{N = 'MicrosoftWindows.UndockedDevKit'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.SecondaryTileExperience'; P = 'cw5n1h2txyewy' },
        @{N = 'Microsoft.Windows.XGpuEjectDialog'; P = 'cw5n1h2txyewy' }
    )

    $allPackages = $systemPackages + $corePackages
    $installed = 0; $failed = 0; $skipped = 0

    foreach ($pkg in $allPackages) {
        $name = $pkg.N
        $pub = $pkg.P

        # Check if already installed
        if (Get-AppxPackageSafe -Name $name) {
            $skipped++; continue
        }

        # Method 1: Try manifest from another user profile
        $otherPkgs = @(Get-AppxPackageSafe -Name $name -AllUsers)
        $success = $false
        if ($otherPkgs) {
            foreach ($op in $otherPkgs) {
                if ($op.InstallLocation -and (Test-Path "$($op.InstallLocation)\AppxManifest.xml")) {
                    try {
                        Add-AppxPackage -DisableDevelopmentMode -Register "$($op.InstallLocation)\AppxManifest.xml" -EA Stop
                        $installed++; $success = $true
                        Write-Log "Neu installiert: $name (manifest)" -Level Success
                        break
                    } catch {
                    }
                }
            }
        }
        if ($success) {
            continue
        }

        # Method 2: Try package family name
        $familyName = "${name}_${pub}"
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage $familyName -EA Stop
            $installed++
            Write-Log "Neu installiert: $name (family)" -Level Success
            continue
        } catch {
        }

        $failed++
        Write-Log "Konnte nicht neu installiert werden: $name (möglicherweise Store oder Windows Update erforderlich)" -Level Warning
    }

    Write-Log "AppX Pakete: $installed neu installiert, $skipped bereits vorhanden, $failed nicht verfügbar" -Level Success
    $script:ChangesCount += $installed
}

function Restore-EnvironmentVariables {
    Write-Log '=== UMGEBUNGSVARIABLEN ===' -Level Section

    # Remove telemetry opt-out variables (restore to default = telemetry enabled)
    @('DOTNET_CLI_TELEMETRY_OPTOUT', 'POWERSHELL_TELEMETRY_OPTOUT') | ForEach-Object {
        $val = [System.Environment]::GetEnvironmentVariable($_, 'User')
        if ($null -ne $val) {
            [System.Environment]::SetEnvironmentVariable($_, $null, 'User')
            Write-Log "Benutzerumgebungsvariable entfernt: $_" -Level Success
            $script:ChangesCount++
        }
        $val = [System.Environment]::GetEnvironmentVariable($_, 'Machine')
        if ($null -ne $val) {
            [System.Environment]::SetEnvironmentVariable($_, $null, 'Machine')
            Write-Log "Maschinenumgebungsvariable entfernt: $_" -Level Success
            $script:ChangesCount++
        }
    }

    Write-Log 'Umgebungsvariablen: Abgeschlossen' -Level Success
}

function Restore-BackgroundApps {
    Write-Log '=== HINTERGRUND APPS ===' -Level Section
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'Migrated' -Silent
    Remove-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BackgroundAppGlobalToggle' -Silent
    # Group Policy
    Remove-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name 'LetAppsRunInBackground' -Silent
    Write-Log 'Hintergrund Apps: Abgeschlossen' -Level Success
}


# ============================================================================
# PRE-SCAN DIAGNOSTICS ENGINE (with detailed per-item findings)
# ============================================================================

function Get-SystemHealthReport {
    $report = [ordered]@{}
    $addCat = {
        param($name, $fn, $issues, $details, $sev, $keys)
        if (!$details -or $details.Count -eq 0) {
            $details = $issues
        }
        $report[$name] = @{
            FriendlyName = $fn; Issues = [array]$issues; Details = [array]$details
            Severity = $sev; IssueCount = ([array]$issues).Count; FixKeys = $keys
        }
    }

    # --- Windows Defender ---
    $issues = @(); $details = @()
    $defPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    if ((Get-ItemProperty $defPol -Name 'DisableAntiSpyware' -EA 0).DisableAntiSpyware -eq 1) {
        $issues += 'Antivirus durch Richtlinie deaktiviert'; $details += 'Richtlinie: DisableAntiSpyware = 1'
    }
    if ((Get-ItemProperty "$defPol\Real-Time Protection" -Name 'DisableRealtimeMonitoring' -EA 0).DisableRealtimeMonitoring -eq 1) {
        $issues += 'Echtzeitschutz aus'; $details += 'Richtlinie: DisableRealtimeMonitoring = 1'
    }
    $svc = Get-Service 'WinDefend' -EA 0
    if ($svc -and $svc.StartType -eq 'Disabled') {
        $issues += 'Defender Dienst deaktiviert'; $details += 'Dienst: WinDefend (Windows Defender) = Disabled'
    }
    if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MsMpEng.exe' -Name 'Debugger' -EA 0).Debugger) {
        $issues += 'Defender vom IFEO-Debugger blockiert'; $details += 'IFEO: MsMpEng.exe verfügt über eine Debugger-Umleitung'
    }
    $renamedExes = @(Get-ChildItem "$env:ProgramFiles\Windows Defender" -Filter '*.exe.OLD' -EA 0)
    if ($renamedExes.Count) {
        $issues += "$($renamedExes.Count) Defender EXEs umbenannt"; $details += ($renamedExes | ForEach-Object { "Umbenannt: $($_.Name)" })
    }
    & $addCat 'Defender' 'Windows Defender' $issues $details $(if ($issues.Count) {
            'Critical'
        } else {
            'OK'
        }) @('chkDefender')

    # --- Firewall ---
    $issues = @(); $details = @()
    $svc = Get-Service 'MpsSvc' -EA 0
    if ($svc -and $svc.StartType -eq 'Disabled') {
        $issues += 'Firewall Dienst deaktiviert'; $details += 'Dienst: MpsSvc (Windows Firewall) = Disabled'
    }
    @('DomainProfile', 'PublicProfile', 'StandardProfile') | ForEach-Object {
        $v = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\$_" -Name 'EnableFirewall' -EA 0).EnableFirewall
        if ($v -eq 0) {
            $issues += "$_ Firewall aus"; $details += "Firewall: $_ EnableFirewall = 0"
        }
    }
    & $addCat 'Firewall' 'Windows Firewall' $issues $details $(if ($issues.Count) {
            'Critical'
        } else {
            'OK'
        }) @('chkFirewall')

    # --- SmartScreen ---
    $issues = @(); $details = @()
    if ((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableSmartScreen' -EA 0).EnableSmartScreen -eq 0) {
        $issues += 'SmartScreen durch Richtlinie deaktiviert'; $details += 'Richtlinie: EnableSmartScreen = 0'
    }
    if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\smartscreen.exe' -Name 'Debugger' -EA 0).Debugger) {
        $issues += 'Ausführbare SmartScreen-Datei blockiert'; $details += 'IFEO: smartscreen.exe verfügt über eine Debugger-Umleitung'
    }
    & $addCat 'SmartScreen' 'SmartScreen' $issues $details $(if ($issues.Count) {
            'Critical'
        } else {
            'OK'
        }) @('chkSmartScreen')

    # --- Security UI ---
    $issues = @(); $details = @()
    $secUIPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center'
    @('Virus and threat protection', 'Firewall and network protection', 'App and browser control', 'Device security', 'Device performance and health', 'Family options', 'Account protection') | ForEach-Object {
        if ((Get-ItemProperty "$secUIPath\$_" -Name 'UILockdown' -EA 0).UILockdown -eq 1) {
            $issues += "$_ ausgeblendet"; $details += "Abschnitt ausgeblendet: $_"
        }
    }
    if (!(Get-AppxPackageSafe -Name 'Microsoft.SecHealthUI') -and !(Get-AppxPackageSafe -Name 'Microsoft.Windows.SecHealthUI')) {
        $issues += 'Windows-Sicherheits-App entfernt'; $details += 'AppX: SecHealthUI Paket fehlt'
    }
    & $addCat 'SecurityUI' 'Windows Sicherheitsanwendung' $issues $details $(if ($issues.Count) {
            'High'
        } else {
            'OK'
        }) @('chkSecurityUI')

    # --- Windows Update ---
    $issues = @(); $details = @()
    $wuSvcs = [ordered]@{ 'wuauserv' = 'Windows Update'; 'DoSvc' = 'Delivery Optimization'; 'WaaSMedicSvc' = 'Update Health'; 'UsoSvc' = 'Update Orchestrator'; 'BITS' = 'Background Transfer' }
    foreach ($s in $wuSvcs.GetEnumerator()) {
        $svc = Get-Service $s.Key -EA 0
        if ($svc -and $svc.StartType -eq 'Disabled') {
            $issues += "$($s.Value) deaktiviert"; $details += "Dienst: $($s.Key) ($($s.Value)) = Deaktiviert"
        }
    }
    if ((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -Name 'NoAutoUpdate' -EA 0).NoAutoUpdate -eq 1) {
        $issues += 'Automatische Aktualisierung durch Richtlinie blockiert'; $details += 'Richtlinie: NoAutoUpdate = 1'
    }
    & $addCat 'WindowsUpdate' 'Windows Update' $issues $details $(if ($issues.Count) {
            'High'
        } else {
            'OK'
        }) @('chkWindowsUpdate')

    # --- UAC ---
    $issues = @(); $details = @()
    $lua = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA' -EA 0).EnableLUA
    if ($lua -eq 0) {
        $issues += 'UAC vollständig deaktiviert'; $details += 'Richtlinie: EnableLUA = 0 (Keine Admin-Eingabeaufforderungen)'
    }
    & $addCat 'UAC' 'Benutzerkontensteuerung' $issues $details $(if ($issues.Count) {
            'High'
        } else {
            'OK'
        }) @('chkUAC')

    # --- Network ---
    $issues = @(); $details = @()
    $svc = Get-Service 'NlaSvc' -EA 0
    if ($svc -and $svc.StartType -eq 'Disabled') {
        $issues += 'Netzwerkerkennung deaktiviert'; $details += 'Dienst: NlaSvc (Netzwerkstandorterkennung) = Deaktiviert'
    }
    if ((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' -Name 'NoActiveProbe' -EA 0).NoActiveProbe -eq 1) {
        $issues += 'Internetverbindungstest deaktiviert'; $details += 'Richtlinie: NCSI NoActiveProbe = 1'
    }
    $dnsSvc = Get-Service 'Dnscache' -EA 0
    if ($dnsSvc -and $dnsSvc.StartType -eq 'Disabled') {
        $issues += 'DNS Client deaktiviert'; $details += 'Dienst: Dnscache (DNS Client) = Deaktiviert'
    }
    & $addCat 'Network' 'Netzwerkkonnektivität' $issues $details $(if ($issues.Count) {
            'High'
        } else {
            'OK'
        }) @('chkNetwork')

    # --- Hosts File ---
    $issues = @(); $details = @()
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Test-Path $hostsPath) {
        $hContent = [System.IO.File]::ReadAllLines($hostsPath)
        $blocked = @($hContent | Where-Object { $_ -match '^0\.0\.0\.0\s' -or $_ -match '^::1?\s' })
        if ($blocked.Count -gt 5) {
            $issues += "$($blocked.Count) Domänen in der Hosts-Datei blockiert"
            $details += ($blocked | Select-Object -First 15 | ForEach-Object { "Blockiert: $($_ -replace '^\S+\s+','')" })
            if ($blocked.Count -gt 15) {
                $details += "... und $($blocked.Count -15) mehr"
            }
        }
    }
    & $addCat 'HostsFile' 'Hosts Datei' $issues $details $(if ($issues.Count) {
            'Medium'
        } else {
            'OK'
        }) @('chkHostsFile')

    # --- Services (comprehensive) ---
    $issues = @(); $details = @()
    $criticalSvcs = [ordered]@{
        'Spooler' = 'Print Spooler'; 'Audiosrv' = 'Windows Audio'; 'AudioEndpointBuilder' = 'Audio Endpoint Builder'
        'Themes' = 'Themes'; 'EventLog' = 'Event Log'; 'bthserv' = 'Bluetooth Support'
        'WSearch' = 'Windows Search'; 'SysMain' = 'SysMain (Superfetch)'; 'TabletInputService' = 'Touch Keyboard'
        'lfsvc' = 'Geolocation'; 'WbioSrvc' = 'Windows Biometric'; 'XblAuthManager' = 'Xbox Live Auth'
        'WpnService' = 'Push Notifications'; 'TrkWks' = 'Distributed Link Tracking'
        'TokenBroker' = 'Web Account Manager'; 'LanmanWorkstation' = 'Workstation'
        'Dnscache' = 'DNS Client'; 'DPS' = 'Diagnostic Policy'; 'PcaSvc' = 'Program Compatibility'
        'WerSvc' = 'Windows Error Reporting'; 'seclogon' = 'Secondary Logon'; 'Schedule' = 'Task Scheduler'
        'DiagTrack' = 'Connected User Experiences'; 'dmwappushservice' = 'WAP Push Service'
    }
    foreach ($s in $criticalSvcs.GetEnumerator()) {
        $svc = Get-Service $s.Key -EA 0
        if ($svc -and $svc.StartType -eq 'Disabled') {
            $details += "$($s.Value) ($($s.Key))"
        }
    }
    if ($details.Count -gt 5) {
        $issues += "$($details.Count) Systemdienste deaktiviert"
    } elseif ($details.Count -gt 0) {
        $issues += "$($details.Count) Dienst(e) deaktiviert"
    }
    & $addCat 'Services' 'Systemdienste' $issues $details $(if ($details.Count -gt 5) {
            'High'
        } elseif ($details.Count) {
            'Medium'
        } else {
            'OK'
        }) @('chkServices', 'chk3rdParty')

    # --- Privacy/Telemetry ---
    $issues = @(); $details = @()
    $svc = Get-Service 'DiagTrack' -EA 0
    if ($svc -and $svc.StartType -eq 'Disabled') {
        $details += 'Dienst: DiagTrack (Diagnostics) = Deaktiviert'
    }
    $tel = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -EA 0).AllowTelemetry
    if ($null -ne $tel -and $tel -eq 0) {
        $details += 'Richtlinie: AllowTelemetry = 0 (Telemetrie vollständig blockiert)'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy') {
        $privPols = @((Get-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -EA 0).Property)
        if ($privPols.Count -gt 0) {
            $details += "AppPrivacy: $($privPols.Count) Richtlinien, die App-Berechtigungen erzwingen"
        }
    }
    $bg = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -EA 0).GlobalUserDisabled
    if ($bg -eq 1) {
        $details += 'Hintergrund-Apps global deaktiviert'
    }
    $camPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
    @('microphone', 'webcam', 'location', 'contacts', 'appointments', 'phoneCall', 'radios', 'bluetooth', 'broadFileSystemAccess') | ForEach-Object {
        $v = (Get-ItemProperty "$camPath\$_" -Name 'Value' -EA 0).Value
        if ($v -eq 'Deny') {
            $details += "Funktion blockiert: $_"
        }
    }
    if ($details.Count -gt 3) {
        $issues += "$($details.Count) Datenschutzbeschränkungen erkannt"
    } elseif ($details.Count -gt 0) {
        $issues += "$($details.Count) Datenschutzänderung(en)"
    }
    & $addCat 'Privacy' 'Datenschutz und Diagnose' $issues $details $(if ($details.Count -gt 3) {
            'Medium'
        } elseif ($details.Count) {
            'Low'
        } else {
            'OK'
        }) @('chkPrivacy', 'chkBgApps', 'chkEnvVars')

    # --- Store/Apps ---
    $issues = @(); $details = @()
    $appChecks = [ordered]@{
        'Microsoft.WindowsStore' = 'Microsoft Store'; 'Microsoft.WindowsCalculator' = 'Calculator'
        'Microsoft.Windows.Photos' = 'Photos'; 'Microsoft.DesktopAppInstaller' = 'App Installer (winget)'
    }
    foreach ($a in $appChecks.GetEnumerator()) {
        if (!(Get-AppxPackageSafe -Name $a.Key)) {
            $issues += "$($a.Value) entfernt"; $details += "Fehlen: $($a.Key)"
        }
    }
    & $addCat 'StoreApps' 'Windowsanwendungen' $issues $details $(if ($issues.Count) {
            'Medium'
        } else {
            'OK'
        }) @('chkAppx')

    # --- Crypto ---
    $issues = @(); $details = @()
    $schBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
    @('TLS 1.2', 'TLS 1.3') | ForEach-Object {
        if ((Get-ItemProperty "$schBase\$_\Client" -Name 'Enabled' -EA 0).Enabled -eq 0) {
            $issues += "$_ Client deaktiviert"; $details += "Protokoll: $_ Client aktiviert = 0"
        }
    }
    @('SSL 2.0', 'SSL 3.0', 'TLS 1.0', 'TLS 1.1') | ForEach-Object {
        if (Test-Path "$schBase\$_\Client") {
            $details += "Vorliegende Protokollüberschreibung: $_ Client"
        }
        if (Test-Path "$schBase\$_\Server") {
            $details += "Vorliegende Protokollüberschreibung: $_ Server"
        }
    }
    if ($details.Count -gt 0 -and $issues.Count -eq 0) {
        $issues += "$($details.Count) Protokollüberschreibungen erkannt"
    }
    & $addCat 'Crypto' 'Sicherheitsprotokolle' $issues $details $(if ($issues | Where-Object { $_ -match 'disabled' }) {
            'High'
        } elseif ($issues.Count) {
            'Low'
        } else {
            'OK'
        }) @('chkCrypto')

    # --- Browsers ---
    $issues = @(); $details = @()
    if (Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge') {
        $ep = @((Get-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -EA 0).Property)
        if ($ep.Count -gt 2) {
            $issues += "Edge: $($ep.Count) Richtlinien"; $details += ($ep | Select-Object -First 10 | ForEach-Object { "Edge policy: $_" })
        }
    }
    if (Test-Path 'HKLM:\SOFTWARE\Policies\Google\Chrome') {
        $cp = @((Get-Item 'HKLM:\SOFTWARE\Policies\Google\Chrome' -EA 0).Property)
        if ($cp.Count -gt 2) {
            $issues += "Chrome: $($cp.Count) Richtlinien"; $details += ($cp | Select-Object -First 10 | ForEach-Object { "Chrome policy: $_" })
        }
    }
    if (Test-Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox') {
        $issues += 'Firefox hat Richtlinien'; $details += 'Firefox Gruppenrichtlinien erkannt'
    }
    & $addCat 'Browsers' 'Browsereinstellungen' $issues $details $(if ($issues.Count) {
            'Low'
        } else {
            'OK'
        }) @('chkEdge', 'chkChrome')

    # --- Taskbar/Explorer/UI ---
    $issues = @(); $details = @()
    $exp = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    if ((Get-ItemProperty $exp -Name 'TaskbarDa' -EA 0).TaskbarDa -eq 0) {
        $details += 'Taskleiste: Widgets ausgeblendet'
    }
    if ((Get-ItemProperty $exp -Name 'ShowTaskViewButton' -EA 0).ShowTaskViewButton -eq 0) {
        $details += 'Taskleiste: Aufgabenansicht ausgeblendet'
    }
    if ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -EA 0).SearchboxTaskbarMode -eq 0) {
        $details += 'Taskleiste: Suchleiste ausgeblendet'
    }
    $shellFolders = @(
        @{G = '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}'; N = 'Desktop' }, @{G = '{d3162b92-9365-467a-956b-92703aca08af}'; N = 'Documents' },
        @{G = '{088e3905-0323-4b02-9826-5d99428e115f}'; N = 'Downloads' }, @{G = '{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}'; N = 'Music' }
    )
    foreach ($f in $shellFolders) {
        if (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\$($f.G)")) {
            $details += "Explorer: $($f.N) Ordner von diesem PC entfernt"
        }
    }
    if ($details.Count -gt 0) {
        $issues += "$($details.Count) UI Anpassungen erkannt"
    }
    & $addCat 'UI' 'Taskleiste und Explorer' $issues $details $(if ($details.Count -gt 3) {
            'Medium'
        } elseif ($details.Count) {
            'Low'
        } else {
            'OK'
        }) @('chkTaskbar', 'chkExplorer', 'chkStartMenu', 'chkContextMenus')

    # --- OneDrive ---
    $issues = @(); $details = @()
    if ((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -Name 'DisableFileSyncNGSC' -EA 0).DisableFileSyncNGSC -eq 1) {
        $issues += 'OneDrive sync blockiert'; $details += 'Richtlinie: DisableFileSyncNGSC = 1'
    }
    & $addCat 'OneDrive' 'OneDrive' $issues $details $(if ($issues.Count) {
            'Low'
        } else {
            'OK'
        }) @('chkOneDrive')

    # --- Scheduled Tasks ---
    $issues = @(); $details = @()
    $taskChecks = @(
        @{P = '\Microsoft\Windows\WindowsUpdate\'; N = 'Scheduled Start' },
        @{P = '\Microsoft\Windows\Defrag\'; N = 'ScheduledDefrag' },
        @{P = '\Microsoft\Windows\DiskDiagnostic\'; N = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        @{P = '\Microsoft\Windows\Diagnosis\'; N = 'Scheduled' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'Microsoft Compatibility Appraiser' }
    )
    foreach ($tc in $taskChecks) {
        try {
            $t = Get-ScheduledTask -TaskPath $tc.P -TaskName $tc.N -EA Stop
            if ($t.State -eq 'Disabled') {
                $details += "Disabled: $($tc.N)"
            }
        } catch {
        }
    }
    if ($details.Count -gt 0) {
        $issues += "$($details.Count) Wartungsaufgaben deaktiviert"
    }
    & $addCat 'Tasks' 'Geplante Aufgaben' $issues $details $(if ($details.Count -gt 2) {
            'Medium'
        } elseif ($details.Count) {
            'Low'
        } else {
            'OK'
        }) @('chkTasks')

    # --- Windows Features ---
    $issues = @(); $details = @()
    try {
        @('MicrosoftWindowsPowerShellV2Root', 'Printing-PrintToPDFServices-Features', 'SearchEngine-Client-Package', 'MediaPlayback', 'WindowsMediaPlayer') | ForEach-Object {
            $feat = Get-WindowsOptionalFeature -Online -FeatureName $_ -EA Stop
            if ($feat.State -eq 'Disabled') {
                $details += "Disabled: $_ ($($feat.DisplayName))"
            }
        }
    } catch {
    }
    if ($details.Count -gt 0) {
        $issues += "$($details.Count) Windows Funktionen deaktiviert"
    }
    & $addCat 'Features' 'Windows Funktionen' $issues $details $(if ($details.Count) {
            'Medium'
        } else {
            'OK'
        }) @('chkFeatures')

    return $report
}

# ============================================================================
# PRE-SCAN QUICK SUMMARY (counts for disabled services, tasks, missing AppX, modified registry)
# ============================================================================

function Get-QuickScanSummary {
    $summary = [ordered]@{
        DisabledServices = 0
        DisabledTasks    = 0
        MissingAppx      = 0
        ModifiedRegistry = 0
        ServiceNames     = @()
        TaskNames        = @()
        AppxNames        = @()
        RegistryDetails  = @()
    }

    # Count disabled services that should be running
    $defaultSvcs = @(
        'WinDefend', 'MpsSvc', 'BFE', 'wuauserv', 'UsoSvc', 'DoSvc', 'BITS', 'CryptSvc',
        'Spooler', 'Audiosrv', 'AudioEndpointBuilder', 'NlaSvc', 'Dnscache', 'Themes',
        'EventLog', 'Schedule', 'WpnService', 'DiagTrack', 'bthserv', 'WSearch', 'SysMain',
        'PcaSvc', 'wersvc', 'wscsvc', 'WlanSvc', 'Dhcp', 'TrkWks', 'Power', 'ProfSvc', 'Winmgmt'
    )
    foreach ($sn in $defaultSvcs) {
        $svc = Get-Service -Name $sn -EA 0
        if ($svc -and $svc.StartType -eq 'Disabled') {
            $summary.DisabledServices++
            $summary.ServiceNames += $sn
        }
    }

    # Count disabled scheduled tasks
    $taskChecks = @(
        @{P = '\Microsoft\Windows\WindowsUpdate\'; N = 'Scheduled Start' },
        @{P = '\Microsoft\Windows\Windows Defender\'; N = 'Windows Defender Scheduled Scan' },
        @{P = '\Microsoft\Windows\Defrag\'; N = 'ScheduledDefrag' },
        @{P = '\Microsoft\Windows\DiskDiagnostic\'; N = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
        @{P = '\Microsoft\Windows\Diagnosis\'; N = 'Scheduled' },
        @{P = '\Microsoft\Windows\Application Experience\'; N = 'Microsoft Compatibility Appraiser' },
        @{P = '\Microsoft\Windows\UpdateOrchestrator\'; N = 'Schedule Scan' },
        @{P = '\Microsoft\Windows\Servicing\'; N = 'StartComponentCleanup' },
        @{P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' }
    )
    foreach ($tc in $taskChecks) {
        try {
            $t = Get-ScheduledTask -TaskPath $tc.P -TaskName $tc.N -EA Stop
            if ($t.State -eq 'Disabled') {
                $summary.DisabledTasks++
                $summary.TaskNames += $tc.N
            }
        } catch {
        }
    }

    # Count missing AppX packages
    $coreAppx = @(
        'Microsoft.WindowsStore', 'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos',
        'Microsoft.DesktopAppInstaller', 'Microsoft.WindowsCamera', 'Microsoft.WindowsAlarms',
        'Microsoft.MSPaint', 'Microsoft.GetHelp', 'Microsoft.People',
        'Microsoft.MicrosoftOfficeHub', 'Microsoft.WindowsFeedbackHub'
    )
    foreach ($pkg in $coreAppx) {
        if (!(Get-AppxPackageSafe -Name $pkg)) {
            $summary.MissingAppx++
            $summary.AppxNames += $pkg
        }
    }

    # Count modified registry keys (key policy paths that shouldn't exist on stock Windows)
    $regChecks = @(
        @{P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; N = 'DisableAntiSpyware' },
        @{P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; N = 'DisableRealtimeMonitoring' },
        @{P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; N = 'NoAutoUpdate' },
        @{P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; N = 'EnableSmartScreen' },
        @{P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'EnableLUA' },
        @{P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; N = 'AllowTelemetry' },
        @{P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; N = 'GlobalUserDisabled' },
        @{P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; N = 'DisableFileSyncNGSC' },
        @{P = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; N = 'SmartScreenEnabled' },
        @{P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; N = 'LetAppsRunInBackground' }
    )
    foreach ($rc in $regChecks) {
        $val = (Get-ItemProperty -Path $rc.P -Name $rc.N -EA 0)
        if ($null -ne $val -and $null -ne $val.$($rc.N)) {
            $summary.ModifiedRegistry++
            $summary.RegistryDetails += "$($rc.P)\$($rc.N)"
        }
    }

    return $summary
}

# ============================================================================
# MANIFEST IMPORT (reads Debloat-Win11 v1.1.0 JSON undo manifests)
# ============================================================================

function Import-UndoManifest {
    param([string]$ManifestPath)

    $result = @{
        Success            = $false
        AppxPackages       = @()
        Services           = @()
        Tasks              = @()
        RegistryKeys       = @()
        RelevantCategories = @()
        Summary            = ''
        ManifestData       = $null
    }

    if (!(Test-Path $ManifestPath)) {
        $result.Summary = "File not found: $ManifestPath"
        return $result
    }

    try {
        $json = Get-Content -Path $ManifestPath -Raw -EA Stop | ConvertFrom-Json -EA Stop
    } catch {
        $result.Summary = "Invalid JSON: $($_.Exception.Message)"
        return $result
    }

    $result.ManifestData = $json

    # Extract AppX packages
    if ($json.PSObject.Properties['AppxPackages'] -or $json.PSObject.Properties['appx_packages'] -or $json.PSObject.Properties['removedApps']) {
        $appxProp = if ($json.PSObject.Properties['AppxPackages']) {
            $json.AppxPackages
        } elseif ($json.PSObject.Properties['appx_packages']) {
            $json.appx_packages
        } elseif ($json.PSObject.Properties['removedApps']) {
            $json.removedApps
        } else {
            @()
        }
        $result.AppxPackages = @($appxProp)
        if ($result.AppxPackages.Count -gt 0) {
            $result.RelevantCategories += 'chkAppx'
        }
    }

    # Extract services
    if ($json.PSObject.Properties['Services'] -or $json.PSObject.Properties['services'] -or $json.PSObject.Properties['disabledServices']) {
        $svcProp = if ($json.PSObject.Properties['Services']) {
            $json.Services
        } elseif ($json.PSObject.Properties['services']) {
            $json.services
        } elseif ($json.PSObject.Properties['disabledServices']) {
            $json.disabledServices
        } else {
            @()
        }
        $result.Services = @($svcProp)
        if ($result.Services.Count -gt 0) {
            $result.RelevantCategories += 'chkServices'
        }
    }

    # Extract tasks
    if ($json.PSObject.Properties['ScheduledTasks'] -or $json.PSObject.Properties['scheduled_tasks'] -or $json.PSObject.Properties['disabledTasks']) {
        $taskProp = if ($json.PSObject.Properties['ScheduledTasks']) {
            $json.ScheduledTasks
        } elseif ($json.PSObject.Properties['scheduled_tasks']) {
            $json.scheduled_tasks
        } elseif ($json.PSObject.Properties['disabledTasks']) {
            $json.disabledTasks
        } else {
            @()
        }
        $result.Tasks = @($taskProp)
        if ($result.Tasks.Count -gt 0) {
            $result.RelevantCategories += 'chkTasks'
        }
    }

    # Extract registry keys
    if ($json.PSObject.Properties['RegistryKeys'] -or $json.PSObject.Properties['registry_keys'] -or $json.PSObject.Properties['registryChanges']) {
        $regProp = if ($json.PSObject.Properties['RegistryKeys']) {
            $json.RegistryKeys
        } elseif ($json.PSObject.Properties['registry_keys']) {
            $json.registry_keys
        } elseif ($json.PSObject.Properties['registryChanges']) {
            $json.registryChanges
        } else {
            @()
        }
        $result.RegistryKeys = @($regProp)
    }

    # Map registry changes to relevant categories
    $regCatMap = @{
        'Windows Defender' = 'chkDefender'
        'Firewall'         = 'chkFirewall'
        'SmartScreen'      = 'chkSmartScreen'
        'WindowsUpdate'    = 'chkWindowsUpdate'
        'DataCollection'   = 'chkPrivacy'
        'AppPrivacy'       = 'chkPrivacy'
        'OneDrive'         = 'chkOneDrive'
        'Edge'             = 'chkEdge'
        'Chrome'           = 'chkChrome'
        'CloudContent'     = 'chkCDM'
    }
    foreach ($rk in $result.RegistryKeys) {
        $path = if ($rk.PSObject.Properties['Path']) {
            $rk.Path
        } elseif ($rk.PSObject.Properties['path']) {
            $rk.path
        } elseif ($rk -is [string]) {
            $rk
        } else {
            ''
        }
        foreach ($pattern in $regCatMap.Keys) {
            if ($path -match [regex]::Escape($pattern)) {
                if ($regCatMap[$pattern] -notin $result.RelevantCategories) {
                    $result.RelevantCategories += $regCatMap[$pattern]
                }
            }
        }
    }

    # Also check for specific categories mentioned in the manifest
    if ($json.PSObject.Properties['categories'] -or $json.PSObject.Properties['Categories']) {
        $cats = if ($json.PSObject.Properties['categories']) {
            $json.categories
        } else {
            $json.Categories
        }
        foreach ($c in $cats) {
            $catName = if ($c -is [string]) {
                $c
            } elseif ($c.PSObject.Properties['name']) {
                $c.name
            } else {
                ''
            }
            # Map category names to our checkbox keys
            $catKeyMap = @{
                'defender' = 'chkDefender'; 'firewall' = 'chkFirewall'; 'smartscreen' = 'chkSmartScreen'
                'update' = 'chkWindowsUpdate'; 'privacy' = 'chkPrivacy'; 'telemetry' = 'chkPrivacy'
                'edge' = 'chkEdge'; 'chrome' = 'chkChrome'; 'onedrive' = 'chkOneDrive'
                'cortana' = 'chkCopilot'; 'copilot' = 'chkCopilot'; 'network' = 'chkNetwork'
                'hosts' = 'chkHostsFile'; 'gaming' = 'chkGaming'; 'xbox' = 'chkGaming'
            }
            foreach ($mk in $catKeyMap.Keys) {
                if ($catName -match $mk -and $catKeyMap[$mk] -notin $result.RelevantCategories) {
                    $result.RelevantCategories += $catKeyMap[$mk]
                }
            }
        }
    }

    $result.RelevantCategories = @($result.RelevantCategories | Select-Object -Unique)
    $parts = @()
    if ($result.AppxPackages.Count) {
        $parts += "$($result.AppxPackages.Count) AppX"
    }
    if ($result.Services.Count) {
        $parts += "$($result.Services.Count) services"
    }
    if ($result.Tasks.Count) {
        $parts += "$($result.Tasks.Count) tasks"
    }
    if ($result.RegistryKeys.Count) {
        $parts += "$($result.RegistryKeys.Count) registry keys"
    }
    $result.Summary = "Manifest loaded: $($parts -join ', ') to restore"
    $result.Success = $true

    return $result
}

# ============================================================================
# HTML REPORT EXPORT
# ============================================================================

function Export-HtmlReport {
    param([string]$OutputPath)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $fixed = @($script:CategoryResults.Values | Where-Object { $_.Status -eq 'Fixed' }).Count
    $already = @($script:CategoryResults.Values | Where-Object { $_.Status -eq 'Already OK' }).Count
    $errored = @($script:CategoryResults.Values | Where-Object { $_.Status -eq 'Error' }).Count

    $rows = ''
    foreach ($cat in $script:CategoryResults.GetEnumerator()) {
        $statusColor = switch ($cat.Value.Status) {
            'Fixed' {
                '#3fb950'
            }
            'Already OK' {
                '#8b949e'
            }
            'Error' {
                '#f85149'
            }
            default {
                '#484f58'
            }
        }
        $statusLabel = switch ($cat.Value.Status) {
            'Fixed' {
                'FIXED'
            }
            'Already OK' {
                'OK'
            }
            'Error' {
                'FAILED'
            }
            default {
                'SKIPPED'
            }
        }
        $rows += '<tr>'
        $rows += "<td style='padding:8px 12px;border-bottom:1px solid #21262d;color:#c9d1d9;'>$($cat.Key)</td>"
        $rows += "<td style='padding:8px 12px;border-bottom:1px solid #21262d;color:$statusColor;font-weight:bold;'>$statusLabel</td>"
        $rows += "<td style='padding:8px 12px;border-bottom:1px solid #21262d;color:#8b949e;'>$($cat.Value.Changed) changes</td>"
        $rows += "<td style='padding:8px 12px;border-bottom:1px solid #21262d;color:$(if($cat.Value.Errors -gt 0){'#f85149'}else{'#8b949e'});'>$($cat.Value.Errors) errors</td>"
        $rows += "</tr>`n"
    }

    # Read the log file for detailed output
    $logContent = ''
    if (Test-Path $script:LogPath) {
        $logLines = Get-Content -Path $script:LogPath -EA 0
        foreach ($line in $logLines) {
            $escaped = [System.Net.WebUtility]::HtmlEncode($line)
            $color = '#8b949e'
            if ($escaped -match '\[Success\]') {
                $color = '#3fb950'
            } elseif ($escaped -match '\[Error\]') {
                $color = '#f85149'
            } elseif ($escaped -match '\[Warning\]') {
                $color = '#d29922'
            } elseif ($escaped -match '\[Section\]') {
                $color = '#bb86fc'
            }
            $logContent += "<div style='color:$color;margin:1px 0;'>$escaped</div>`n"
        }
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Windows Wiederherstellungstool – Bericht</title>
<style>
body { background:#0d1117; color:#c9d1d9; font-family:'Segoe UI',system-ui,sans-serif; margin:0; padding:20px; }
.header { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:20px; margin-bottom:20px; }
.header h1 { color:#e6edf3; margin:0 0 4px 0; font-size:22px; }
.header p { color:#8b949e; margin:4px 0; font-size:13px; }
.badge { display:inline-block; background:#238636; color:white; padding:2px 8px; border-radius:10px; font-size:11px; font-weight:bold; margin-left:8px; }
.summary { display:flex; gap:16px; margin-bottom:20px; }
.summary-card { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:16px; flex:1; text-align:center; }
.summary-card .number { font-size:28px; font-weight:bold; }
.summary-card .label { color:#8b949e; font-size:12px; margin-top:4px; }
.green { color:#3fb950; }
.gray { color:#8b949e; }
.red { color:#f85149; }
table { width:100%; border-collapse:collapse; background:#161b22; border:1px solid #30363d; border-radius:8px; overflow:hidden; margin-bottom:20px; }
th { background:#21262d; color:#8b949e; padding:10px 12px; text-align:left; font-size:12px; text-transform:uppercase; letter-spacing:0.5px; }
.log-section { background:#161b22; border:1px solid #30363d; border-radius:8px; padding:16px; }
.log-section h2 { color:#e6edf3; font-size:16px; margin:0 0 12px 0; }
.log-content { font-family:'Cascadia Mono','Consolas',monospace; font-size:11px; max-height:600px; overflow-y:auto; line-height:1.5; }
.footer { text-align:center; color:#484f58; font-size:11px; margin-top:20px; padding-top:16px; border-top:1px solid #21262d; }
</style>
</head>
<body>
<div class="header">
    <h1>Windows Restore Tool<span class="badge">v$($script:Version)</span></h1>
    <p>Report generated: $timestamp</p>
    <p>Computer: $env:COMPUTERNAME | User: $env:USERNAME | OS: $([System.Environment]::OSVersion.VersionString)</p>
</div>
<div class="summary">
    <div class="summary-card"><div class="number green">$fixed</div><div class="label">Kategorien behoben</div></div>
    <div class="summary-card"><div class="number gray">$already</div><div class="label">in Ordnung</div></div>
    <div class="summary-card"><div class="number red">$errored</div><div class="label">Fehler</div></div>
    <div class="summary-card"><div class="number" style="color:#58a6ff;">$($script:ChangesCount)</div><div class="label">Gesamtänderungen</div></div>
</div>
<table>
<thead><tr><th>Category</th><th>Status</th><th>Änderungen</th><th>Fehler</th></tr></thead>
<tbody>
$rows
</tbody>
</table>
<div class="log-section">
    <h2>Detailed Log</h2>
    <div class="log-content">
$logContent
    </div>
</div>
<div class="footer">
    Windows Wiederherstellungstool v$($script:Version) - Erstellt von Restore-WindowsDefaults.ps1
</div>
</body>
</html>
"@

    try {
        [System.IO.File]::WriteAllText($OutputPath, $html, [System.Text.Encoding]::UTF8)
        return $true
    } catch {
        return $false
    }
}

# ============================================================================
# GUI (100% static XAML - all dynamic content populated programmatically)
# ============================================================================

function Show-MainWindow {

    # ---- Run pre-scan ----
    $script:HealthReport = Get-SystemHealthReport
    $critCount = @($script:HealthReport.Values | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount = @($script:HealthReport.Values | Where-Object { $_.Severity -eq 'High' }).Count
    $totalIssues = ($script:HealthReport.Values | ForEach-Object { $_.IssueCount } | Measure-Object -Sum).Sum

    if ($critCount -gt 0) {
        $hColor = '#f85149'; $hText = "KRITISCH – $totalIssues Probleme gefunden ($critCount kritisch)"
    } elseif ($highCount -gt 0) {
        $hColor = '#d29922'; $hText = "WARNUNG – $totalIssues Probleme gefunden"
    } elseif ($totalIssues -gt 0) {
        $hColor = '#58a6ff'; $hText = "$totalIssues kleinere Probleme gefunden"
    } else {
        $hColor = '#3fb950'; $hText = 'Das System scheint einwandfrei zu funktionieren. Es wurden keine größeren Probleme festgestellt.'
    }

    # ---- Checkbox definitions ----
    $categories = @(
        @{K = 'chkDefender'; L = 'Windows Defender'; D = 'Aktiviert Virenschutz, Echtzeit-Scanning, Aktualisierungen und entsperrt ausführbare Dateien'; On = $true; G = 'Security' }
        @{K = 'chkFirewall'; L = 'Windows Firewall'; D = 'Aktiviert die Firewall für alle Netzwerkprofile erneut und stellt den BFE-Dienst wieder her'; On = $true; G = 'Security' }
        @{K = 'chkSmartScreen'; L = 'SmartScreen Schutz'; D = 'Aktiviert die Download-/Website-Sicherheitsüberprüfungen in Windows und Browsern wieder'; On = $true; G = 'Security' }
        @{K = 'chkWindowsUpdate'; L = 'Windows Update'; D = 'Stellt Aktualisierungsdienste wieder her, optimiert die Zustellung und registriert Komponenten neu'; On = $true; G = 'Security' }
        @{K = 'chkUAC'; L = 'Benutzerkontensteuerung'; D = 'Stellt Eingabeaufforderungen zur Erhöhung der Administratorrechte wieder her (verhindert unbeaufsichtigte Installationen)'; On = $true; G = 'Security' }
        @{K = 'chkCrypto'; L = 'TLS/SSL Sicherheitsprotokolle'; D = 'Stellt die SHANNEL-, Cipher-Suites-, .NET-Krypto-und WinRM-Standardeinstellungen wieder her'; On = $true; G = 'Security' }
        @{K = 'chkSecurityUI'; L = 'Windows Sicherheits-App'; D = 'Stellt Security Center-Abschnitte, das Taskleistensymbol und VBS/Device Guard wieder her'; On = $true; G = 'Security' }
        @{K = 'chkNetwork'; L = 'Netzwerk und Internet'; D = 'Behebt Konnektivitätserkennung, DNS, NCSI, Wi-Fi und Proxy-Einstellungen'; On = $true; G = 'System' }
        @{K = 'chkHostsFile'; L = 'Hosts-Dateiblöcke löschen'; D = 'Entfernen Sie Domänenblöcke, die Windows Update, Store und Aktivierung beeinträchtigenn'; On = $true; G = 'System' }
        @{K = 'chkServices'; L = 'Systemdienste (100+)'; D = 'Aktiviert kritische Dienste, die durch Debloat-Skripte deaktiviert wurden, wieder'; On = $true; G = 'System' }
        @{K = 'chkTasks'; L = 'Geplante Aufgaben (80+)'; D = 'Aktiviert wieder Windows-Wartungs-, Defragmentierungs-, Zustands- und Update-Aufgaben'; On = $true; G = 'System' }
        @{K = 'chkFeatures'; L = 'Windows Funktionen'; D = 'Aktiviert wieder Drucken in PDF, PowerShell, Medienwiedergabe und mehr'; On = $true; G = 'System' }
        @{K = 'chkErrorReport'; L = 'Fehlerberichterstattung'; D = 'Stellt Absturzberichte und den Windows-Fehlerberichtsdienst wieder her'; On = $true; G = 'System' }
        @{K = 'chkPrinting'; L = 'Drucken'; D = 'Stellt den Druckspoolerdienst und den Druckbenachrichtigungsdienst wieder her'; On = $true; G = 'System' }
        @{K = 'chkMisc'; L = 'Verschiedene Systemrichtlinien'; D = 'Snipping Tool, Copilot-Autolaunch, Standort, Karten, DEP'; On = $true; G = 'System' }
        @{K = 'chkClipboard'; L = 'Zwischenablageverlauf und Sync'; D = 'Stellt den Verlauf der Zwischenablage und die geräteübergreifenden Synchronisierungsfunktionen wieder her'; On = $true; G = 'System' }
        @{K = 'chkPrivacy'; L = 'Datenschutz und Telemetrie'; D = 'Stellt App-Berechtigungen, Diagnosedatenerfassung und Tracking-Standardeinstellungen wieder her'; On = $true; G = 'Privacy' }
        @{K = 'chkCopilot'; L = 'Copilot, Cortana und AI'; D = 'Entfernt Richtlinienblockaden für Windows KI und Sprachassistentenfunktionen'; On = $true; G = 'Privacy' }
        @{K = 'chkBing'; L = 'Such- und Webergebnisse'; D = 'Stellt die Bing-Suchintegration, Webvorschläge und Widgets wieder her'; On = $true; G = 'Privacy' }
        @{K = 'chkCDM'; L = 'App-Empfehlungen und Werbung'; D = 'Stellt Windows Spotlight, Startvorschläge und Funktionstipps wieder her'; On = $true; G = 'Privacy' }
        @{K = 'chkBgApps'; L = 'Background Apps'; D = 'Ermöglicht Apps, Daten zu aktualisieren und Benachrichtigungen im Hintergrund zu senden'; On = $true; G = 'Privacy' }
        @{K = 'chkSync'; L = 'Synchronisierungseinstellungen '; D = 'Stellt die Synchronisierung von Design, Passwort und Sprache auf Ihren Geräten wieder her'; On = $true; G = 'Privacy' }
        @{K = 'chkNotifications'; L = 'Benachrichtigungen'; D = 'Stellt Toastbenachrichtigungen, Sperrbildschirmwarnungen und Badge-Zähler wieder her'; On = $true; G = 'Privacy' }
        @{K = 'chkEnvVars'; L = 'Entwicklertelemetrie'; D = 'Entfernt die Variablen zum Deaktivieren der Telemetrie für die .NET-CLI und PowerShell'; On = $true; G = 'Privacy' }
        @{K = 'chkTaskbar'; L = 'Taskleistenlayout'; D = 'Stellt die Aufgabenansicht, Widgets, Chat und Personensymbole in der Taskleiste wieder her'; On = $true; G = 'LookFeel' }
        @{K = 'chkExplorer'; L = 'Datei-Explorer'; D = 'Stellt die Ordner, aktuellen Dateien, das OneDrive-Symbol und die Multifunktionsleiste dieses PCs wieder her'; On = $true; G = 'LookFeel' }
        @{K = 'chkStartMenu'; L = 'Start Menü'; D = 'Stellt App-Tracking, Empfehlungen und Layoutvorschläge wieder her'; On = $true; G = 'LookFeel' }
        @{K = 'chkContextMenus'; L = 'Rechtsklick-Menüs'; D = 'Stellt vollständige Kontextmenüs wieder her (macht die Optimierung des Win11-Kompaktmenüs rückgängig)'; On = $true; G = 'LookFeel' }
        @{K = 'chkOOBE'; L = 'Setup Erfahrung'; D = 'Stellt das Erstausführungserlebnis und die Aufforderungen zum Einverständnis zum Datenschutz wieder her'; On = $true; G = 'LookFeel' }
        @{K = 'chkTheme'; L = 'Auf Standard-Hell-Design zurücksetzen'; D = 'Wechselt zurück zum Standard-Windows-Light-Design (nur Kosmetik)'; On = $false; G = 'LookFeel' }
        @{K = 'chkEdge'; L = 'Microsoft Edge'; D = 'Entfernt Gruppenrichtlinien, stellt Updates, Erweiterungen und Funktionen wieder her'; On = $true; G = 'Apps' }
        @{K = 'chkChrome'; L = 'Chrome, Firefox und Google'; D = 'Entfernt Browserrichtlinien, stellt Updates und Software Reporter wieder her'; On = $true; G = 'Apps' }
        @{K = 'chkOffice'; L = 'Microsoft Office'; D = 'Stellt die Standardeinstellungen für Telemetrie, Feedback und Makrosicherheit wieder her'; On = $true; G = 'Apps' }
        @{K = 'chkOneDrive'; L = 'OneDrive'; D = 'Stellt die OneDrive-Integration, das Seitenleistensymbol und den Synchronisierungsdienst wieder her'; On = $true; G = 'Apps' }
        @{K = 'chkNvidia'; L = 'NVIDIA Telemetrie'; D = 'Stellt NVIDIA-Telemetrieaufgaben und geplante Dienste wieder her'; On = $true; G = 'Apps' }
        @{K = 'chk3rdParty'; L = 'App-Dienste von Drittanbietern'; D = 'Stellt Adobe-, Dropbox-, Razer-, Logitech-, CCleaner- und WMP-Dienste wieder her'; On = $true; G = 'Apps' }
        @{K = 'chkAppx'; L = 'Entfernte Windows-Apps neu installieren'; D = 'Versucht Rechner, Fotos, Store usw. wiederherzustellen. Kann mehr als 5 Minuten dauern'; On = $false; G = 'Apps' }
        @{K = 'chkBluetooth'; L = 'Bluetooth'; D = 'Stellt Bluetooth-Dienste und Audio-Gateway wieder her'; On = $true; G = 'Hardware' }
        @{K = 'chkBiometrics'; L = 'Biometrie (Windows Hello)'; D = 'Stellt den Fingerabdruck- und Gesichtserkennungsdienst wieder her'; On = $true; G = 'Hardware' }
        @{K = 'chkGaming'; L = 'Gaming und Xbox'; D = 'Stellt Xbox-Dienste, Game Bar und Game DVR wieder her'; On = $true; G = 'Hardware' }
        @{K = 'chkRemoteDesktop'; L = 'Remote Desktop'; D = 'Stellt RDP-Dienste für Remoteverbindungen wieder her'; On = $true; G = 'Hardware' }
        @{K = 'chkAccessibility'; L = 'Barrierefreiheit'; D = 'Stellt das Tablet-Eingabe und Strg+Alt+Entf-Verhalten wieder her'; On = $true; G = 'Hardware' }
        @{K = 'chkInput'; L = 'Eingabe und Tippen'; D = 'Stellt Handschrifterkennung, Freihandeingabe und Tippvorschläge wieder hers'; On = $true; G = 'Hardware' }
        @{K = 'chkPower'; L = 'Power und Ruhezustand'; D = 'Aktiviert den Ruhezustand wieder und stellt die Energieeinstellungen wieder her'; On = $true; G = 'Hardware' }
        @{K = 'chkMemory'; L = 'Memory und Leistung'; D = 'Stellt Prefetch-, Superfetch-und Auslagerungsdateieinstellungen wieder her'; On = $true; G = 'Hardware' }
        @{K = 'chkStorage'; L = 'Storage Sense'; D = 'Stellt die automatische Datenträgerbereinigung und den reservierten Speicher wieder her'; On = $true; G = 'Hardware' }
        @{K = 'chkInsider'; L = 'Windows Insider'; D = 'Stellt den Insider-Dienst und die Vorschau-Build Einstellungen wieder her'; On = $true; G = 'Hardware' }
    )
    $allChkNames = $categories | ForEach-Object { $_.K }

    $funcMap = @{
        chkPrivacy = { Restore-PrivacyTelemetry }; chkCopilot = { Restore-CopilotCortanaAI }
        chkBing = { Restore-BingSearchWidgets }; chkCDM = { Restore-ContentDeliveryManager }
        chkSync = { Restore-SyncSettings }; chkInsider = { Restore-WindowsInsiderSettings }
        chkBgApps = { Restore-BackgroundApps }; chkEnvVars = { Restore-EnvironmentVariables }
        chkNotifications = { Restore-NotificationSettings }; chkOOBE = { Restore-OOBESettings }
        chkTaskbar = { Restore-TaskbarUI }; chkExplorer = { Restore-ExplorerSettings }
        chkStartMenu = { Restore-StartMenuSettings }; chkTheme = { Restore-ThemeSettings }
        chkContextMenus = { Restore-ContextMenus }; chkMisc = { Restore-MiscPolicies }
        chkClipboard = { Restore-ClipboardSettings }
        chkWindowsUpdate = { Restore-WindowsUpdateSettings }; chkErrorReport = { Restore-ErrorReporting }
        chkEdge = { Restore-EdgeSettings }; chkChrome = { Restore-ChromeSettings }
        chkOffice = { Restore-OfficeSettings }; chkNvidia = { Restore-NvidiaTelemetry }
        chk3rdParty = { Restore-ThirdPartyServices }
        chkDefender = { Restore-DefenderSettings }; chkSmartScreen = { Restore-SmartScreenSettings }
        chkFirewall = { Restore-FirewallSettings }; chkUAC = { Restore-UACSettings }
        chkSecurityUI = { Restore-WindowsSecurityUI }
        chkBiometrics = { Restore-BiometricsSettings }; chkGaming = { Restore-GamingSettings }
        chkOneDrive = { Restore-OneDriveSettings }; chkRemoteDesktop = { Restore-RemoteDesktopSettings }
        chkNetwork = { Restore-NetworkSettings }; chkBluetooth = { Restore-BluetoothSettings }
        chkAccessibility = { Restore-AccessibilitySettings }; chkInput = { Restore-InputSettings }
        chkPrinting = { Restore-PrintingSettings }; chkPower = { Restore-PowerSettings }
        chkMemory = { Restore-MemoryPerformance }; chkStorage = { Restore-StorageSettings }
        chkServices = { Restore-Services }; chkTasks = { Restore-ScheduledTasks }
        chkHostsFile = { Restore-HostsFile }; chkCrypto = { Restore-CryptoProtocols }
        chkFeatures = { Restore-WindowsFeatures }; chkAppx = { Restore-AppxPackages }
    }
    $friendlyMap = @{}; $categories | ForEach-Object { $friendlyMap[$_.K] = $_.L }

    # ================================================================
    # STATIC XAML - single-quoted here-string prevents variable expansion
    # ================================================================
    $xamlString = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Restore Tool" Width="920" Height="880"
        WindowStartupLocation="CenterScreen" Background="#0d1117" ResizeMode="CanMinimize">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#21262d"/>
            <Setter Property="Foreground" Value="#e6edf3"/>
            <Setter Property="BorderBrush" Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#30363d"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#c9d1d9"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Margin" Value="0,2"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid x:Name="pageHome">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#161b22" Padding="20,14" BorderBrush="#30363d" BorderThickness="0,0,0,1">
                <StackPanel>
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="Windows Wiederherstellungstool" FontSize="20" FontWeight="Bold" Foreground="#e6edf3"/>
                        <Border Background="#238636" CornerRadius="10" Padding="8,2" Margin="10,0" VerticalAlignment="Center">
                            <TextBlock Text="v4.3" FontSize="10" Foreground="White" FontWeight="SemiBold"/>
                        </Border>
                    </StackPanel>
                    <TextBlock Text="Behebt Probleme bei PCs, die durch Debloat-Skripte, 'privacy.sexy' und Registrierungsänderungen beschädigt wurden" Foreground="#8b949e" FontSize="12" Margin="0,3,0,0"/>
                </StackPanel>
            </Border>
            <Border Grid.Row="1" Background="#0d1117" Padding="20,10,20,6">
                <StackPanel>
                    <DockPanel Margin="0,0,0,6">
                        <TextBlock Text="Systemprüfung" FontSize="13" FontWeight="SemiBold" Foreground="#c9d1d9" VerticalAlignment="Center"/>
                        <Button x:Name="btnImportManifest" Content="Manifest importieren" DockPanel.Dock="Right" HorizontalAlignment="Right" Padding="10,4" FontSize="11"/>
                    </DockPanel>
                    <Border x:Name="quickScanPanel" Background="#161b22" CornerRadius="6" Padding="12,8" Margin="0,0,0,6" BorderBrush="#30363d" BorderThickness="1">
                        <WrapPanel x:Name="quickScanStats"/>
                    </Border>
                    <Border x:Name="manifestBanner" Background="#1a3070" CornerRadius="6" Padding="12,8" Margin="0,0,0,6" BorderBrush="#1f6feb" BorderThickness="1" Visibility="Collapsed">
                        <TextBlock x:Name="txtManifestSummary" Foreground="#58a6ff" FontSize="12" TextWrapping="Wrap"/>
                    </Border>
                    <Border Background="#161b22" CornerRadius="6" Padding="12,8" BorderBrush="#30363d" BorderThickness="1">
                        <StackPanel>
                            <TextBlock x:Name="txtHealthSummary" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,4"/>
                            <ScrollViewer MaxHeight="200" VerticalScrollBarVisibility="Auto">
                                <StackPanel x:Name="scanResults"/>
                            </ScrollViewer>
                            <TextBlock x:Name="txtScanHint" Foreground="#484f58" FontSize="10" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Border>
            <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Padding="20,10">
                <StackPanel>
                    <TextBlock Text="Wähle aus, wie du deinen PC reparieren möchten:" FontSize="13" FontWeight="SemiBold" Foreground="#c9d1d9" Margin="0,0,0,8"/>
                    <Border x:Name="btnFixAll" Background="#161b22" CornerRadius="8" Padding="16,12" Margin="0,0,0,6" BorderBrush="#238636" BorderThickness="2" Cursor="Hand">
                        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <StackPanel>
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="Empfohlener Fix" FontSize="15" FontWeight="Bold" Foreground="#3fb950"/>
                                    <Border Background="#238636" CornerRadius="3" Padding="6,1" Margin="8,0" VerticalAlignment="Center">
                                        <TextBlock Text="SICHER" FontSize="9" Foreground="White" FontWeight="Bold"/></Border>
                                </StackPanel>
                                <TextBlock TextWrapping="Wrap" Foreground="#8b949e" FontSize="11" Margin="0,3,0,0" Text="Stellt alle Standard-Einstellungen für Sicherheit, Dienste und das System wieder her. Behält das dunkle Design bei. Deinstallierte Apps werden NICHT neu installiert."/>
                            </StackPanel>
                            <TextBlock Grid.Column="1" Text="&#xBB;" FontSize="24" Foreground="#3fb950" VerticalAlignment="Center" Margin="12,0,0,0"/>
                        </Grid>
                    </Border>
                    <Border x:Name="btnFixDetected" Background="#161b22" CornerRadius="8" Padding="16,12" Margin="0,0,0,6" BorderBrush="#d29922" BorderThickness="1" Cursor="Hand">
                        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <StackPanel>
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="Nur erkannte Probleme beheben" FontSize="15" FontWeight="Bold" Foreground="#d29922"/>
                                    <Border Background="#4a3000" CornerRadius="3" Padding="6,1" Margin="8,0" VerticalAlignment="Center">
                                        <TextBlock x:Name="txtDetectedCount" FontSize="9" Foreground="#d29922" FontWeight="Bold"/></Border>
                                </StackPanel>
                                <TextBlock TextWrapping="Wrap" Foreground="#8b949e" FontSize="11" Margin="0,3,0,0" Text="Behebt ausschließlich die vom Scanner festgestellten spezifischen Probleme. Klicke oben auf einen beliebigen Scan-Eintrag, um weitere Informationen zu erhalten."/>
                            </StackPanel>
                            <TextBlock Grid.Column="1" Text="&#xBB;" FontSize="24" Foreground="#d29922" VerticalAlignment="Center" Margin="12,0,0,0"/>
                        </Grid>
                    </Border>
                    <Border x:Name="btnFixSecurity" Background="#161b22" CornerRadius="8" Padding="16,12" Margin="0,0,0,6" BorderBrush="#30363d" BorderThickness="1" Cursor="Hand">
                        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <StackPanel>
                                <TextBlock Text="Nur Sicherheit" FontSize="15" FontWeight="Bold" Foreground="#58a6ff"/>
                                <TextBlock TextWrapping="Wrap" Foreground="#8b949e" FontSize="11" Margin="0,3,0,0" Text="Behebt ausschließlich Probleme mit Defender, der Firewall, SmartScreen, Windows Update, der Benutzerkontensteuerung (UAC) und den Sicherheitsprotokollen."/>
                            </StackPanel>
                            <TextBlock Grid.Column="1" Text="&#xBB;" FontSize="24" Foreground="#58a6ff" VerticalAlignment="Center" Margin="12,0,0,0"/>
                        </Grid>
                    </Border>
                    <Border x:Name="btnCustom" Background="#161b22" CornerRadius="8" Padding="16,12" Margin="0,0,0,6" BorderBrush="#30363d" BorderThickness="1" Cursor="Hand">
                        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <StackPanel>
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="Benutzerdefiniert" FontSize="15" FontWeight="Bold" Foreground="#8b949e"/>
                                    <Border Background="#1a3070" CornerRadius="3" Padding="6,1" Margin="8,0" VerticalAlignment="Center">
                                        <TextBlock Text="FORTGESCHRITTENE" FontSize="9" Foreground="#58a6ff" FontWeight="Bold"/></Border>
                                </StackPanel>
                                <TextBlock TextWrapping="Wrap" Foreground="#8b949e" FontSize="11" Margin="0,3,0,0" Text="Wähle aus 47 Kategorien genau aus, was wiederhergestellt werden soll. Volle Kontrolle über jede Einstellung."/>
                            </StackPanel>
                            <TextBlock Grid.Column="1" Text="&#xBB;" FontSize="24" Foreground="#8b949e" VerticalAlignment="Center" Margin="12,0,0,0"/>
                        </Grid>
                    </Border>
                    <Border x:Name="btnScanOnly" Background="#0d1117" CornerRadius="8" Padding="16,8" Margin="0,4,0,0" BorderBrush="#21262d" BorderThickness="1" Cursor="Hand">
                        <TextBlock HorizontalAlignment="Center" Foreground="#8b949e" FontSize="12" Text="Nur Vorschau – Zeigt was sich ändern würde, ohne etwas zu ändern"/>
                    </Border>
                </StackPanel>
            </ScrollViewer>
            <Border Grid.Row="3" Background="#161b22" Padding="14,8" BorderBrush="#30363d" BorderThickness="0,1,0,0">
                <DockPanel>
                    <CheckBox x:Name="chkAutoRestore" Content="Zuerst Wiederherstellungspunkt erstellen (dringend empfohlen)" IsChecked="True" DockPanel.Dock="Left" VerticalAlignment="Center"/>
                    <Button x:Name="btnClose" Content="Beenden" DockPanel.Dock="Right" HorizontalAlignment="Right" Padding="16,6" Background="#ff0808"/>
                </DockPanel>
            </Border>
        </Grid>
        <Grid x:Name="pageCustom" Visibility="Collapsed">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#161b22" Padding="14,10" BorderBrush="#30363d" BorderThickness="0,0,0,1">
                <DockPanel>
                    <Button x:Name="btnBack" Content="&#x2190; Zurück" DockPanel.Dock="Left" Padding="10,5" FontSize="12" Background="#238636"/>
                    <TextBlock Text="  Individuelle Restaurierung" FontSize="15" FontWeight="SemiBold" Foreground="#e6edf3" VerticalAlignment="Center"/>
                    <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
                        <Button x:Name="btnSelectAll" Content="Alle" Padding="8,4" FontSize="11" Margin="0,0,4,0"/>
                        <Button x:Name="btnSelectNone" Content="Keine" Padding="8,4" FontSize="11" Margin="0,0,4,0"/>
                        <Button x:Name="btnSelectSafe" Content="Sichere Standardwerte" Padding="8,4" FontSize="11"/>
                    </StackPanel>
                </DockPanel>
            </Border>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="16,0,16,8">
                <StackPanel x:Name="chkContainer"/>
            </ScrollViewer>
            <Border Grid.Row="2" Background="#161b22" Padding="14,8" BorderBrush="#30363d" BorderThickness="0,1,0,0">
                <DockPanel>
                    <CheckBox x:Name="chkAutoRestoreC" Content="Zuerst Wiederherstellungspunkt erstellen" IsChecked="True" DockPanel.Dock="Left" VerticalAlignment="Center"/>
                    <Button x:Name="btnRunCustom" DockPanel.Dock="Right" HorizontalAlignment="Right" Padding="16,8" Background="#238636" Foreground="White" BorderBrush="#238636">
                        <TextBlock Text="Gewählte Fixes starten " FontWeight="SemiBold"/></Button>
                </DockPanel>
            </Border>
        </Grid>
        <Grid x:Name="pageProgress" Visibility="Collapsed">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Border Grid.Row="0" Background="#161b22" Padding="20,14" BorderBrush="#30363d" BorderThickness="0,0,0,1">
                <StackPanel>
                    <TextBlock x:Name="txtProgressTitle" Text="Windows-Standardeinstellungen wiederherstellen..." FontSize="18" FontWeight="Bold" Foreground="#e6edf3"/>
                    <TextBlock x:Name="txtProgressSub" Text="Schließe dieses Fenster nicht" Foreground="#8b949e" FontSize="12" Margin="0,3,0,0"/>
                </StackPanel>
            </Border>
            <Border Grid.Row="1" Background="#0d1117" Padding="20,8">
                <StackPanel>
                    <ProgressBar x:Name="progressBar" Height="6" Minimum="0" Maximum="100" Value="0" Background="#21262d" Foreground="#238636" BorderThickness="0"/>
                    <DockPanel Margin="0,4,0,0">
                        <TextBlock x:Name="txtProgressPercent" Text="0%" Foreground="#8b949e" FontSize="11"/>
                        <TextBlock x:Name="txtProgressStep" Text="" Foreground="#484f58" FontSize="11" DockPanel.Dock="Right" HorizontalAlignment="Right"/>
                    </DockPanel>
                </StackPanel>
            </Border>
            <Border Grid.Row="2" Background="#0d1117" Padding="20,4,20,8">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Border Grid.Row="0" x:Name="categoryResultsPanel" Visibility="Collapsed" Background="#161b22" CornerRadius="6" Padding="8,6" Margin="0,0,0,6" BorderBrush="#30363d" BorderThickness="1">
                        <ScrollViewer MaxHeight="120" VerticalScrollBarVisibility="Auto">
                            <WrapPanel x:Name="categoryResultsList"/>
                        </ScrollViewer>
                    </Border>
                <Border Grid.Row="1" Background="#161b22" CornerRadius="6" Padding="2" BorderBrush="#30363d" BorderThickness="1">
                    <RichTextBox x:Name="txtConsole" IsReadOnly="True" Background="Transparent" BorderThickness="0"
                                 FontFamily="Cascadia Mono,Consolas,Courier New" FontSize="11"
                                 VerticalScrollBarVisibility="Auto" Padding="6">
                        <RichTextBox.Resources><Style TargetType="Paragraph"><Setter Property="Margin" Value="0"/></Style></RichTextBox.Resources>
                        <FlowDocument/>
                    </RichTextBox>
                </Border>
                </Grid>
            </Border>
            <Border Grid.Row="3" Background="#161b22" Padding="14,8" BorderBrush="#30363d" BorderThickness="0,1,0,0">
                <DockPanel>
                    <TextBlock x:Name="txtStatus" Text="" Foreground="#8b949e" FontSize="11" VerticalAlignment="Center"/>
                    <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
                        <Button x:Name="btnReboot" Visibility="Collapsed" Padding="14,8" Background="#238636" Foreground="White" BorderBrush="#238636">
                            <TextBlock Text="Jetzt neu starten" FontWeight="SemiBold"/></Button>
                        <Button x:Name="btnLater" Content="Schließen (später neu starten)" Visibility="Collapsed" Padding="14,8" Margin="6,0,0,0"/>
                        <Button x:Name="btnExportReport" Content="Bericht exportieren" Visibility="Collapsed" Padding="14,8" Margin="6,0,0,0"/>
                        <Button x:Name="btnViewLog" Content="Protokolldatei öffnen" Visibility="Collapsed" Padding="14,8" Margin="6,0,0,0"/>
                    </StackPanel>
                </DockPanel>
            </Border>
        </Grid>
    </Grid>
</Window>
'@

    # ---- Load window using Parse() which properly registers NameScope ----
    try {
        $window = [System.Windows.Markup.XamlReader]::Parse($xamlString)
        # codex-branding:start
        try {
            $brandingIconPath = Join-Path $PSScriptRoot 'icon.ico'
            if (Test-Path $brandingIconPath) {
                $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($brandingIconPath)))
            }
        } catch {
        }
        # codex-branding:end
    } catch {
        [System.Windows.MessageBox]::Show("Die Benutzeroberfläche konnte nicht geladen werden: $($_.Exception.Message)", 'Fehler', 'OK', 'Error')
        return
    }

    # ---- Find named controls ----
    # With XamlReader.Parse(), FindName works correctly
    $ui = @{}
    $controlNames = @(
        'pageHome', 'pageCustom', 'pageProgress',
        'txtHealthSummary', 'scanResults', 'txtScanHint', 'txtDetectedCount',
        'btnFixAll', 'btnFixDetected', 'btnFixSecurity', 'btnCustom', 'btnScanOnly',
        'chkAutoRestore', 'btnClose',
        'btnBack', 'btnSelectAll', 'btnSelectNone', 'btnSelectSafe',
        'chkContainer', 'chkAutoRestoreC', 'btnRunCustom',
        'txtProgressTitle', 'txtProgressSub', 'progressBar', 'txtProgressPercent', 'txtProgressStep',
        'txtConsole', 'txtStatus', 'btnReboot', 'btnLater', 'btnViewLog',
        'btnImportManifest', 'quickScanPanel', 'quickScanStats',
        'manifestBanner', 'txtManifestSummary',
        'categoryResultsPanel', 'categoryResultsList',
        'btnExportReport'
    )
    foreach ($name in $controlNames) {
        $ctrl = $window.FindName($name)
        if ($ctrl) {
            $ui[$name] = $ctrl
        }
    }
    $script:ConsoleBox = $ui.txtConsole
    $script:ConsoleWindow = $window

    # ================================================================
    # POPULATE ALL DYNAMIC CONTENT PROGRAMMATICALLY (safe from XML)
    # ================================================================
    $bc = [System.Windows.Media.BrushConverter]::new()

    # Health summary
    $ui.txtHealthSummary.Text = $hText
    $ui.txtHealthSummary.Foreground = $bc.ConvertFromString($hColor)

    # ---- Quick scan summary panel ----
    $quickScan = Get-QuickScanSummary
    $quickStats = @(
        @{Count = $quickScan.DisabledServices; Label = 'Dienste deaktiviert'; Color = if ($quickScan.DisabledServices) {
                '#d29922'
            } else {
                '#3fb950'
            }
        },
        @{Count = $quickScan.DisabledTasks; Label = 'Aufgaben deaktiviert'; Color = if ($quickScan.DisabledTasks) {
                '#d29922'
            } else {
                '#3fb950'
            }
        },
        @{Count = $quickScan.MissingAppx; Label = 'Apps fehlen'; Color = if ($quickScan.MissingAppx) {
                '#58a6ff'
            } else {
                '#3fb950'
            }
        },
        @{Count = $quickScan.ModifiedRegistry; Label = 'Registry geändert'; Color = if ($quickScan.ModifiedRegistry) {
                '#d29922'
            } else {
                '#3fb950'
            }
        }
    )
    foreach ($qs in $quickStats) {
        $statBorder = New-Object System.Windows.Controls.Border
        $statBorder.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
        $statBorder.Padding = [System.Windows.Thickness]::new(0)
        $statSP = New-Object System.Windows.Controls.StackPanel
        $statSP.Orientation = 'Horizontal'
        $countTB = New-Object System.Windows.Controls.TextBlock
        $countTB.Text = "$($qs.Count)"
        $countTB.FontSize = 14; $countTB.FontWeight = 'Bold'
        $countTB.Foreground = $bc.ConvertFromString($qs.Color)
        $countTB.VerticalAlignment = 'Center'
        $statSP.Children.Add($countTB) | Out-Null
        $labelTB = New-Object System.Windows.Controls.TextBlock
        $labelTB.Text = " $($qs.Label)"
        $labelTB.FontSize = 11
        $labelTB.Foreground = $bc.ConvertFromString('#8b949e')
        $labelTB.VerticalAlignment = 'Center'
        $statSP.Children.Add($labelTB) | Out-Null
        $statBorder.Child = $statSP
        $ui.quickScanStats.Children.Add($statBorder) | Out-Null
    }

    # ---- Manifest import state ----
    $script:ImportedManifest = $null

    # Scan results
    $sevOrder = @{Critical = 0; High = 1; Medium = 2; Low = 3; OK = 4 }
    $sevColors = @{Critical = '#f85149'; High = '#d29922'; Medium = '#58a6ff'; Low = '#8b949e'; OK = '#3fb950' }
    $sevLabels = @{Critical = 'KRITISCH'; High = 'WARNUNG'; Medium = 'GEÄNDERT'; Low = 'HINWEIS'; OK = 'OK' }

    $issueCategories = @()
    $script:HealthReport.GetEnumerator() | Sort-Object { $sevOrder[$_.Value.Severity] } | ForEach-Object {
        $cat = $_.Value; $sev = $cat.Severity
        if ($cat.IssueCount -gt 0) {
            $issueCategories += $_
        }

        $row = New-Object System.Windows.Controls.Border
        $row.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
        $row.Padding = [System.Windows.Thickness]::new(10, 5, 10, 5)
        $row.CornerRadius = [System.Windows.CornerRadius]::new(4)
        if ($sev -ne 'OK') {
            $row.Background = $bc.ConvertFromString('#161b22')
            $row.Cursor = [System.Windows.Input.Cursors]::Hand
        }

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = 'Horizontal'

        # Severity badge
        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = $bc.ConvertFromString($sevColors[$sev])
        $badge.CornerRadius = [System.Windows.CornerRadius]::new(3)
        $badge.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
        $badge.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $badge.VerticalAlignment = 'Center'; $badge.MinWidth = 58
        $bt = New-Object System.Windows.Controls.TextBlock
        $bt.Text = $sevLabels[$sev]; $bt.Foreground = $bc.ConvertFromString('White')
        $bt.FontSize = 10; $bt.FontWeight = 'Bold'; $bt.HorizontalAlignment = 'Center'
        $badge.Child = $bt
        $sp.Children.Add($badge) | Out-Null

        # Category name + summary
        $txt = New-Object System.Windows.Controls.TextBlock
        $txt.FontSize = 12; $txt.VerticalAlignment = 'Center'
        $nameRun = New-Object System.Windows.Documents.Run($cat.FriendlyName)
        $nameRun.FontWeight = 'SemiBold'
        $nameRun.Foreground = $bc.ConvertFromString($(if ($sev -ne 'OK') {
                    '#c9d1d9'
                } else {
                    '#484f58'
                }))
        $txt.Inlines.Add($nameRun) | Out-Null

        if ($cat.IssueCount -gt 0) {
            $sumText = " - $($cat.Issues[0])"
            if ($cat.IssueCount -gt 1) {
                $sumText += " (+$($cat.IssueCount-1) mehr)"
            }
            $sumRun = New-Object System.Windows.Documents.Run($sumText)
            $sumRun.Foreground = $bc.ConvertFromString('#8b949e')
            $txt.Inlines.Add($sumRun) | Out-Null
            # Click hint
            $hintRun = New-Object System.Windows.Documents.Run('  [details]')
            $hintRun.Foreground = $bc.ConvertFromString('#58a6ff'); $hintRun.FontSize = 10
            $txt.Inlines.Add($hintRun) | Out-Null
        }
        $sp.Children.Add($txt) | Out-Null
        $row.Child = $sp

        # Click handler for detail popup
        if ($cat.IssueCount -gt 0) {
            $detailLines = @("$($cat.FriendlyName) - $($cat.IssueCount) Problem(e) gefunden:", '')
            foreach ($d in $cat.Details) {
                $detailLines += "  - $d"
            }
            $row.Tag = ($detailLines -join "`n")
            $row.Add_MouseLeftButtonUp({ param($s, $e)
                    [System.Windows.MessageBox]::Show($s.Tag, 'Scandetails', 'OK', 'Information')
                })
        }

        $ui.scanResults.Children.Add($row) | Out-Null
    }

    # Scan hint and detected count
    if ($totalIssues -gt 0) {
        $ui.txtScanHint.Text = 'Klicke auf ein markiertes Element, um genau zu sehen, was geändert wurde'
    } else {
        $ui.txtScanHint.Text = ''
    }
    $ui.txtDetectedCount.Text = "$totalIssues gefunden"

    # Build detected fix keys
    $detectedKeys = @()
    foreach ($c in $script:HealthReport.Values) {
        if ($c.IssueCount -gt 0 -and $c.FixKeys) {
            $detectedKeys += $c.FixKeys
        }
    }
    $detectedKeys = @($detectedKeys | Select-Object -Unique)

    # ---- Build custom page checkboxes programmatically ----
    $groupMeta = [ordered]@{
        Security = @{Label = 'KRITISCHE SICHERHEIT'; Color = '#f85149'; Desc = 'Schützt deinen PC vor Viren, Hackern und unsicherer Software' }
        System   = @{Label = 'SYSTEMFUNKTIONALITÄT'; Color = '#d29922'; Desc = 'Wichtige Windows-Dienste und -Funktionen, die deinen PC am Laufen halten' }
        Privacy  = @{Label = 'DATENSCHUTZ UND PERSONALISIERUNG'; Color = '#58a6ff'; Desc = 'Datenerfassung, App-Berechtigungen und Personalisierungsfunktionen' }
        LookFeel = @{Label = 'LOOK UND FEEL'; Color = '#8b949e'; Desc = 'Taskleiste, Startmenü, Explorer und visuelle Anpassung' }
        Apps     = @{Label = 'APPS UND BROWSERS'; Color = '#8b949e'; Desc = 'Browsereinstellungen, Office-, OneDrive -und Drittanbieter-App Richtlinien' }
        Hardware = @{Label = 'HARDWARE UND GERÄTE'; Color = '#8b949e'; Desc = 'Bluetooth, Biometrie, Spiele, Stromversorgung, Speicher und Eingabegeräte' }
    }

    foreach ($grp in $groupMeta.GetEnumerator()) {
        # Group header
        $header = New-Object System.Windows.Controls.TextBlock
        $header.Margin = [System.Windows.Thickness]::new(0, 8, 0, 2)
        $r1 = New-Object System.Windows.Documents.Run($grp.Value.Label)
        $r1.FontSize = 11; $r1.FontWeight = 'Bold'; $r1.Foreground = $bc.ConvertFromString($grp.Value.Color)
        $header.Inlines.Add($r1) | Out-Null
        $r2 = New-Object System.Windows.Documents.Run("  $($grp.Value.Desc)")
        $r2.FontSize = 10; $r2.Foreground = $bc.ConvertFromString('#484f58')
        $header.Inlines.Add($r2) | Out-Null
        $ui.chkContainer.Children.Add($header) | Out-Null

        # Group border with WrapPanel
        $grpBorder = New-Object System.Windows.Controls.Border
        $grpBorder.Background = $bc.ConvertFromString('#161b22')
        $grpBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $grpBorder.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
        $grpBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $wp = New-Object System.Windows.Controls.WrapPanel

        $grpItems = $categories | Where-Object { $_.G -eq $grp.Key }
        foreach ($cat in $grpItems) {
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Width = 264; $sp.Margin = [System.Windows.Thickness]::new(0, 3, 8, 3)

            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $cat.L; $cb.IsChecked = $cat.On
            $cb.Foreground = $bc.ConvertFromString($(if ($cat.On) {
                        '#c9d1d9'
                    } else {
                        '#8b949e'
                    }))
            $cb.FontSize = 12; $cb.Cursor = [System.Windows.Input.Cursors]::Hand
            $sp.Children.Add($cb) | Out-Null

            $desc = New-Object System.Windows.Controls.TextBlock
            $desc.Text = $cat.D; $desc.FontSize = 10; $desc.TextWrapping = 'Wrap'
            $desc.Margin = [System.Windows.Thickness]::new(20, 0, 0, 0)
            $desc.Foreground = $bc.ConvertFromString($(if ($cat.K -eq 'chkAppx') {
                        '#d29922'
                    } else {
                        '#6e7681'
                    }))
            $sp.Children.Add($desc) | Out-Null

            $wp.Children.Add($sp) | Out-Null
            $ui[$cat.K] = $cb   # Store checkbox reference
        }

        $grpBorder.Child = $wp
        $ui.chkContainer.Children.Add($grpBorder) | Out-Null
    }

    # ================================================================
    # PRESETS AND RUN LOGIC
    # ================================================================
    $securityOnly = @('chkDefender', 'chkFirewall', 'chkSmartScreen', 'chkWindowsUpdate', 'chkUAC', 'chkSecurityUI', 'chkCrypto')
    $safeDefaults = $allChkNames | Where-Object { $_ -ne 'chkTheme' -and $_ -ne 'chkAppx' }

    $runRestore = {
        param($selectedKeys, $doRestorePoint, $scanOnlyMode)
        $ui.pageHome.Visibility = 'Collapsed'
        $ui.pageCustom.Visibility = 'Collapsed'
        $ui.pageProgress.Visibility = 'Visible'

        if ($scanOnlyMode) {
            $ui.txtProgressTitle.Text = 'Scannen (Vorschaumodus)...'
            $ui.txtProgressSub.Text = 'Es werden keine Änderungen vorgenommen'
        }
        $window.Dispatcher.Invoke([action] {}, 'Render')

        # Restore point
        if ($doRestorePoint -and !$scanOnlyMode) {
            $ui.txtProgressSub.Text = 'Wiederherstellungspunkt erstellen...'
            $window.Dispatcher.Invoke([action] {}, 'Render')
            Write-Log 'Systemwiederherstellungspunkt erstellen...' -Level Info
            try {
                Enable-ComputerRestore -Drive "$env:SystemDrive\" -EA 0
                Checkpoint-Computer -Description 'Vor Windows Restore Tool v4.3' -RestorePointType MODIFY_SETTINGS -EA Stop
                Write-Log 'Wiederherstellungspunkt erfolgreich erstellt' -Level Success
            } catch {
                Write-Log "Wiederherstellungspunkt konnte nicht erstellt werden: $($_.Exception.Message)" -Level Warning
                Write-Log 'Trotzdem weitermachen...' -Level Info
            }
            $ui.txtProgressSub.Text = 'Schließe dieses Fenster nicht'
            $window.Dispatcher.Invoke([action] {}, 'Render')
        }

        $mode = if ($scanOnlyMode) {
            'PREVIEW'
        } else {
            'RESTORE'
        }
        Write-Log "=== Windows Wiederherstellungstool v$($script:Version) - $mode MODUS ===" -Level Section
        Write-Log "Benutzer: $env:USERNAME | Computer: $env:COMPUTERNAME | OS: $([System.Environment]::OSVersion.VersionString)" -Level Info
        Write-Log "Kategorien ausgewählt: $($selectedKeys.Count)" -Level Info
        Write-Log '' -Level Info

        if ($scanOnlyMode) {
            Write-Log 'VORSCHAUMODUS: Es werden keine tatsächlichen Änderungen vorgenommen.' -Level Section
            Write-Log '' -Level Info
            foreach ($key in $selectedKeys) {
                $fn = $friendlyMap[$key]; if (!$fn) {
                    $fn = $key
                }
                Write-Log "Würde wiederherstellen: $fn" -Level Info
            }
            Write-Log '' -Level Info
            Write-Log '=== VORSCHAU Abgeschlossen ===' -Level Section
            $ui.txtProgressTitle.Text = 'Vorschau abgeschlossen'
            $ui.txtProgressSub.Text = "$($selectedKeys.Count) Kategorien würden wiederhergestellt"
            $ui.progressBar.Value = $ui.progressBar.Maximum
            $ui.txtProgressPercent.Text = 'Erledigt'
            $ui.txtStatus.Text = 'Es wurden keine Änderungen vorgenommen (nur Vorschau)'
            $ui.btnLater.Content = 'Schließen'; $ui.btnLater.Visibility = 'Visible'
            $ui.btnViewLog.Visibility = 'Visible'
            $window.Dispatcher.Invoke([action] {}, 'Render')
            return
        }

        # ---- ACTUAL RESTORATION ----
        $ui.progressBar.Maximum = $selectedKeys.Count
        $ui.categoryResultsPanel.Visibility = 'Visible'
        $total = $selectedKeys.Count; $i = 0

        # Pre-populate SKIPPED indicators for unchecked categories
        foreach ($ak in $allChkNames) {
            if ($ak -notin $selectedKeys) {
                $skFn = $friendlyMap[$ak]; if (!$skFn) {
                    $skFn = $ak
                }
                $skSP = New-Object System.Windows.Controls.StackPanel
                $skSP.Orientation = 'Horizontal'
                $skSP.Margin = [System.Windows.Thickness]::new(0, 2, 10, 2)
                $skLabel = New-Object System.Windows.Controls.TextBlock
                $skLabel.Text = "$skFn "; $skLabel.FontSize = 10
                $skLabel.Foreground = $bc.ConvertFromString('#484f58')
                $skSP.Children.Add($skLabel) | Out-Null
                $skStatus = New-Object System.Windows.Controls.TextBlock
                $skStatus.Text = 'ÜBERSPRUNGEN'; $skStatus.FontSize = 10; $skStatus.FontWeight = 'Bold'
                $skStatus.Foreground = $bc.ConvertFromString('#484f58')
                $skSP.Children.Add($skStatus) | Out-Null
                $ui.categoryResultsList.Children.Add($skSP) | Out-Null
            }
        }

        foreach ($key in $selectedKeys) {
            $i++
            $fn = $friendlyMap[$key]; if (!$fn) {
                $fn = $key
            }
            $pct = [math]::Round(($i / $total) * 100)
            $ui.progressBar.Value = $i
            $ui.txtProgressPercent.Text = "$pct%"
            $ui.txtProgressStep.Text = "($i von $total) $fn"
            $ui.txtProgressSub.Text = "Fixing: $fn"
            $window.Dispatcher.Invoke([action] {}, 'Render')

            $script:CurrentCategory = $fn
            $script:CategoryResults[$fn] = @{ Status = 'OK'; Changed = 0; Errors = 0 }
            try {
                & $funcMap[$key]
                if ($script:CategoryResults[$fn].Errors -gt 0 -and $script:CategoryResults[$fn].Changed -gt 0) {
                    $script:CategoryResults[$fn].Status = 'Partial'
                } elseif ($script:CategoryResults[$fn].Errors -gt 0) {
                    $script:CategoryResults[$fn].Status = 'Error'
                } elseif ($script:CategoryResults[$fn].Changed -gt 0) {
                    $script:CategoryResults[$fn].Status = 'Fixed'
                } else {
                    $script:CategoryResults[$fn].Status = 'Already OK'
                }
            } catch {
                $script:CategoryResults[$fn].Status = 'Error'
                $script:CategoryResults[$fn].Errors++
                Write-Log "Error in $fn : $($_.Exception.Message)" -Level Error
            }

            # Add category result indicator
            $catSP = New-Object System.Windows.Controls.StackPanel
            $catSP.Orientation = 'Horizontal'
            $catSP.Margin = [System.Windows.Thickness]::new(0, 2, 10, 2)
            $catLabel = New-Object System.Windows.Controls.TextBlock
            $catLabel.Text = "$fn "; $catLabel.FontSize = 10
            $catLabel.Foreground = $bc.ConvertFromString('#c9d1d9')
            $catSP.Children.Add($catLabel) | Out-Null
            $catStatus = New-Object System.Windows.Controls.TextBlock
            $catStatus.FontSize = 10; $catStatus.FontWeight = 'Bold'
            switch ($script:CategoryResults[$fn].Status) {
                'Fixed' {
                    $catStatus.Text = 'REPARIERT'; $catStatus.Foreground = $bc.ConvertFromString('#3fb950')
                }
                'Partial' {
                    $catStatus.Text = 'TEILWEISE'; $catStatus.Foreground = $bc.ConvertFromString('#d29922')
                }
                'Error' {
                    $catStatus.Text = 'FEHLGESCHLAGEN'; $catStatus.Foreground = $bc.ConvertFromString('#f85149')
                }
                'Already OK' {
                    $catStatus.Text = 'BEHOBEN'; $catStatus.Foreground = $bc.ConvertFromString('#3fb950')
                }
                default {
                    $catStatus.Text = 'ÜBERSPRUNGEN'; $catStatus.Foreground = $bc.ConvertFromString('#484f58')
                }
            }
            $catSP.Children.Add($catStatus) | Out-Null
            $ui.categoryResultsList.Children.Add($catSP) | Out-Null

            $window.Dispatcher.Invoke([action] {}, 'Render')
        }
        $script:CurrentCategory = ''

        # ---- SUMMARY ----
        Write-Log '' -Level Info
        Write-Log '=== ZUSAMMENFASSUNG DER RESTAURIERUNG ===' -Level Section
        $fixed = @($script:CategoryResults.Values | Where-Object { $_.Status -eq 'Fixed' -or $_.Status -eq 'Already OK' }).Count
        $partial = @($script:CategoryResults.Values | Where-Object { $_.Status -eq 'Partial' }).Count
        $already = @($script:CategoryResults.Values | Where-Object { $_.Status -eq 'Already OK' }).Count
        $errored = @($script:CategoryResults.Values | Where-Object { $_.Status -eq 'Error' }).Count
        Write-Log "Behoben: $fixed | Teilweise: $partial | Alles OK: $already | Fehler: $errored | Totale Änderungen: $script:ChangesCount" -Level Info
        Write-Log '' -Level Info
        foreach ($cat in $script:CategoryResults.GetEnumerator()) {
            $icon = switch ($cat.Value.Status) {
                'Fixed' {
                    '[FIXED]'
                }; 'Already OK' {
                    '[ OK ]'
                }; 'Partial' {
                    '[PART]'
                }; 'Error' {
                    '[FAIL]'
                }; default {
                    '[----]'
                }
            }
            $lvl = switch ($cat.Value.Status) {
                'Fixed' {
                    'Success'
                }; 'Partial' {
                    'Warning'
                }; 'Error' {
                    'Error'
                }; default {
                    'Info'
                }
            }
            $det = if ($cat.Value.Changed -gt 0) {
                " ($($cat.Value.Changed) changes)"
            } else {
                ''
            }
            Write-Log "$icon $($cat.Key)$det" -Level $lvl
        }
        Write-Log '' -Level Info
        Write-Log "Protokoll gespeichert: $(Split-Path $script:LogPath -Leaf)" -Level Info
        Write-Log '' -Level Section
        Write-Log 'WAS ALS NÄCHSTES ZU TUN IST:' -Level Section
        Write-Log "1. Klicken Sie auf 'Jetzt neu starten', um die Übernahme der Änderungen abzuschließen" -Level Info
        Write-Log '2. Überprüfe nach dem Neustart, ob Defender und Firewall aktiviert sind' -Level Info
        Write-Log '3. Führe Sie Windows Update aus, um die neuesten Sicherheitspatches zu erhalten' -Level Info
        Write-Log '4. Wenn etwas nicht stimmt, mache es mithilfe der Systemwiederherstellung rückgängig' -Level Info

        try {
            [System.Media.SystemSounds]::Exclamation.Play()
        } catch {
        }

        $ui.txtProgressTitle.Text = 'Alles erledigt! Dein PC wurde wiederhergestellt.'
        $parts = @()
        if ($fixed -gt 0) {
            $parts += "$fixiert behoben"
        }
        if ($partial -gt 0) {
            $parts += "Teilweise $partial"
        }
        if ($already -gt 0) {
            $parts += "$already schon OK"
        }
        if ($errored -gt 0) {
            $parts += "$errored Fehler"
        }
        $ui.txtProgressSub.Text = ($parts -join '  |  ')
        $ui.progressBar.Value = $ui.progressBar.Maximum
        $ui.txtProgressPercent.Text = 'Abgeschlossen'; $ui.txtProgressStep.Text = ''
        $ui.txtStatus.Text = 'Bitte starte neu, um die Übernahme der Änderungen abzuschließen'
        $ui.btnReboot.Visibility = 'Visible'; $ui.btnLater.Visibility = 'Visible'
        $ui.btnExportReport.Visibility = 'Visible'; $ui.btnViewLog.Visibility = 'Visible'
        $window.Dispatcher.Invoke([action] {}, 'Render')
    }

    # ================================================================
    # WIRE EVENTS
    # ================================================================
    $ui.btnFixAll.Add_MouseLeftButtonUp({
            $r = [System.Windows.MessageBox]::Show(
                "Dadurch wird dein PC auf die werkseitigen Windows-Standardeinstellungen zurückgesetzt.`n`nWas es bewirkt:`n  - Schaltet die Sicherheit wieder ein (Defender, Firewall, SmartScreen)`n  - Aktiviert Windows Update und Systemdienste erneut`n  - Entfernt Debloat-Registrierungsoptimierungen und Host-Blockaden`n  - Behält dein aktuelles dunkles Thema`n  - Installiert entfernte Apps NICHT neu`n`nZunächst wird ein Wiederherstellungspunkt erstellt, damit du den Vorgang rückgängig machen kannst.`n`nGeschätzte Zeit: 1-3 Minuten`n`nFortfahren?",
                'Empfohlener Fix', 'YesNo', 'Question')
            if ($r -eq 'Yes') {
                & $runRestore $safeDefaults $ui.chkAutoRestore.IsChecked $false
            }
        })

    $ui.btnFixDetected.Add_MouseLeftButtonUp({
            if (!$detectedKeys.Count) {
                [System.Windows.MessageBox]::Show("Der Scanner hat keine Probleme festgestellt.`nDein System sieht gesund aus!", 'Nichts zu reparieren', 'OK', 'Information')
                return
            }
            $msg = "Korrigiere nur die $($detectedKeys.Count) Kategorien, in denen Probleme gefunden wurden:`n`n"
            foreach ($k in $detectedKeys) {
                $fn = $friendlyMap[$k]; if ($fn) {
                    $msg += "  - $fn`n"
                }
            }
            $msg += "`nGeschätzte Zeit: Unter 1 Minute`n`nFortfahren?"
            $r = [System.Windows.MessageBox]::Show($msg, 'Erkannte Probleme beheben', 'YesNo', 'Question')
            if ($r -eq 'Yes') {
                & $runRestore $detectedKeys $ui.chkAutoRestore.IsChecked $false
            }
        })

    $ui.btnFixSecurity.Add_MouseLeftButtonUp({
            $r = [System.Windows.MessageBox]::Show(
                "Dadurch werden NUR deine Sicherheitseinstellungen korrigiert:`n`n  - Windows Defender (Virenschutz)`n  - Windows Firewall (Netzwerkschutz)`n  - SmartScreen (blockiert gefährliche Downloads)`n  - Windows Update (Hält deinen PC auf dem neuesten Stand)`n  - UAC (fragt, bevor große Änderungen vorgenommen werden)`n  - Sicherheitsprotokolle und Windows-Sicherheits-App`n`nAlles andere bleibt genau wie es ist.`n`nGeschätzte Zeit: Unter 1 Minute`n`nFortfahren?",
                'Sicherheitskorrektur', 'YesNo', 'Question')
            if ($r -eq 'Yes') {
                & $runRestore $securityOnly $ui.chkAutoRestore.IsChecked $false
            }
        })

    $ui.btnCustom.Add_MouseLeftButtonUp({
            $ui.pageHome.Visibility = 'Collapsed'; $ui.pageCustom.Visibility = 'Visible'
        })

    $ui.btnScanOnly.Add_MouseLeftButtonUp({ & $runRestore $safeDefaults $false $true })

    $ui.btnBack.Add_Click({ $ui.pageCustom.Visibility = 'Collapsed'; $ui.pageHome.Visibility = 'Visible' })

    $ui.btnRunCustom.Add_Click({
            $sel = @()
            foreach ($chk in $allChkNames) {
                if ($ui[$chk] -and $ui[$chk].IsChecked) {
                    $sel += $chk
                }
            }
            if (!$sel.Count) {
                [System.Windows.MessageBox]::Show('Wähle mindestens eine Kategorie aus.', 'Nichts ausgewählt', 'OK', 'Information'); return
            }
            $r = [System.Windows.MessageBox]::Show("$($sel.Count) Kategorien wiederherstellen?", 'Bestätigen', 'YesNo', 'Question')
            if ($r -eq 'Yes') {
                & $runRestore $sel $ui.chkAutoRestoreC.IsChecked $false
            }
        })

    $ui.btnSelectAll.Add_Click({ foreach ($c in $allChkNames) {
                if ($ui[$c]) {
                    $ui[$c].IsChecked = $true
                }
            } })
    $ui.btnSelectNone.Add_Click({ foreach ($c in $allChkNames) {
                if ($ui[$c]) {
                    $ui[$c].IsChecked = $false
                }
            } })
    $ui.btnSelectSafe.Add_Click({
            foreach ($c in $allChkNames) {
                if ($ui[$c]) {
                    $ui[$c].IsChecked = ($c -ne 'chkTheme' -and $c -ne 'chkAppx')
                }
            }
        })

    $ui.btnClose.Add_Click({ $window.Close() })
    $ui.btnReboot.Add_Click({
            $r = [System.Windows.MessageBox]::Show("Dein PC wird jetzt neu gestartet.`nStelle sicher, dass du alle deine offenen Arbeiten gespeichert hast.", 'Neustart', 'OKCancel', 'Warning')
            if ($r -eq 'OK') {
                $window.Close(); Restart-Computer -Force
            }
        })
    $ui.btnLater.Add_Click({ $window.Close() })
    $ui.btnViewLog.Add_Click({ if (Test-Path $script:LogPath) {
                Start-Process notepad.exe $script:LogPath
            } })

    # ---- Import Manifest button ----
    $ui.btnImportManifest.Add_Click({
            $ofd = New-Object Microsoft.Win32.OpenFileDialog
            $ofd.Title = 'Importiere das Debloat-Rückgängig Manifest'
            $ofd.Filter = 'JSON Dateien (*.json)|*.json|Alle Dateien (*.*)|*.*'
            $ofd.InitialDirectory = "$env:USERPROFILE\Desktop"
            if ($ofd.ShowDialog() -eq $true) {
                $manifest = Import-UndoManifest -ManifestPath $ofd.FileName
                if ($manifest.Success) {
                    $script:ImportedManifest = $manifest
                    $ui.manifestBanner.Visibility = 'Visible'
                    $ui.txtManifestSummary.Text = $manifest.Summary

                    # Auto-check only relevant categories, uncheck the rest
                    foreach ($c in $allChkNames) {
                        if ($ui[$c]) {
                            $ui[$c].IsChecked = ($c -in $manifest.RelevantCategories)
                        }
                    }
                    # Switch to custom page so user can see what's checked
                    $ui.pageHome.Visibility = 'Collapsed'
                    $ui.pageCustom.Visibility = 'Visible'
                } else {
                    [System.Windows.MessageBox]::Show($manifest.Summary, 'Manifest Import fehlgeschlagen', 'OK', 'Error')
                }
            }
        })

    # ---- Export Report button ----
    $ui.btnExportReport.Add_Click({
            $sfd = New-Object Microsoft.Win32.SaveFileDialog
            $sfd.Title = 'Wiederherstellungsbericht exportieren'
            $sfd.Filter = 'HTML files (*.html)|*.html'
            $sfd.InitialDirectory = "$env:USERPROFILE\Desktop"
            $sfd.FileName = "$ENV:COMPUTERNAME-WindowsRestore_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            if ($sfd.ShowDialog() -eq $true) {
                $success = Export-HtmlReport -OutputPath $sfd.FileName
                if ($success) {
                    Start-Process $sfd.FileName
                } else {
                    [System.Windows.MessageBox]::Show('Der Bericht konnte nicht gespeichert werden.', 'Exportfehler', 'OK', 'Error')
                }
            }
        })

    $window.ShowDialog() | Out-Null
}

# ============================================================================
# ENTRY POINT
# ============================================================================

Show-MainWindow
# SIG # Begin signature block
# MIIdDwYJKoZIhvcNAQcCoIIdADCCHPwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUjNaWnWTWvbz4lQ739O3biUYi
# vz+gghd9MIIEPzCCAiegAwIBAgIQE+RTnONk7ZdJzvz0auYGQzANBgkqhkiG9w0B
# AQ0FADAdMRswGQYDVQQDDBJQb3dlclNoZWxsIFJvb3QgQ0EwIBcNMjMwMzMwMTQ0
# OTMxWhgPMjA2MzAzMzAxNDU5MjZaMC8xLTArBgNVBAMMJE1pY2hhZWwgTWF5ZXIg
# KFBvd2Vyc2hlbGwgRGV2ZWxvcGVyKTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
# AQoCggEBALaag3wQJUviV4+SNvSBFv3EMu22cMSNxjdyVRRL3Y9s7g73ZoVc7Iwk
# bPkQqgr5HUaBOVWLA00wIEewS5LPqVl1zo2lkCQCz9ZgbTAbGJB/CI3h4N+xixYv
# AMpJ8VWlCJ6y7T9xY66b2xSsfoGZyjxWs/D/w5XCHcyheXPG/WoGLV5x/Ne0umTl
# Kgm02sRCWmO3OfUUK6m/jWoQKOCRMTij8ARQ4WYnoaTZSnh6son7Uexfx7RvSzIs
# lZmY+9Fev6jDmVEtDRGOnyzRmJ59yWlcxUS5K7VJXNIIgM6EceyRGMx2fGWCcQAB
# uUHEIH0eDSBqBNyqPvg7771yiMe3tX0CAwEAAaNnMGUwDgYDVR0PAQH/BAQDAgeA
# MBMGA1UdJQQMMAoGCCsGAQUFBwMDMB8GA1UdIwQYMBaAFIYSf6MflVuEn8+pkozG
# BgYpy7tmMB0GA1UdDgQWBBSxUU1kuybSN37fV+31KbyPUZ7KQjANBgkqhkiG9w0B
# AQ0FAAOCAgEAo+ApQ7zSu0N4oL4QdYbR7pDph4Iq7uJ1+FjqvRdHYTBg5gHDZbU5
# d4F/WJtgFhOsC/FGYIAY9B20J1seuoN0rKcqcLLiKPYTWGQGgiWSjfnax/+/Kc+X
# oH1awy8DRbJc1+BrRI5ft6X7rVZeB9RMkxUz19qai0s3ZUlN63K7qjSUW7AtcSGN
# 6acrwRch8BDW/fxKeJb0FUWv7mQRustneXGwjX8evJYTnCaVeKsn333KD2sO9Frb
# hyiJxpos3+CrqCEqeMKNa+YlosCwphfYPWUCne6BTCParSVdZR5ZqatEE54yj1JA
# o2tqEClLwGMk4vWzj7WaVCERgb6QNKnxsWvP65hrjukJwWHR4imvfHSwbEJBLlCJ
# h0gc6jJKNF/EZWwM3TxVA6d37FtBpSIQZBYlAgwR4ucPPb2JQBrViFzKRZAJ0i5A
# rTBaOL9DpKizBdTvt6a2yJTHrDyqhjsw+VjLFq9GoBIE4wsTqYY8tbUBdZyBwdrz
# YZqnSX1M6kEjEBOsABJWi0BJiY1fKhYdUDPg1FfGtXtz1ZC7rTbRYcgCjC+WzRvW
# 8TtKh/9/gCHd+1AZtxDAcuI5fb39W2N5gHpJQz9GMMRgxIvoTmB3nS+P+ZulDvY3
# VW9D8et+WMtpcwgT3if4C59xiuTXPq3+mOWJwTuCGVA+vgtXMZEmk6MwggWNMIIE
# daADAgECAhAOmxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNV
# BAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdp
# Y2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAe
# Fw0yMjA4MDEwMDAwMDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUw
# EwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20x
# ITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC
# 4SmnPVirdprNrnsbhA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWl
# fr6fqVcWWVVyr2iTcMKyunWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1j
# KS3O7F5OyJP4IWGbNOsFxl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dP
# pzDZVu7Ke13jrclPXuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3
# pC4FfYj1gj4QkXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJ
# pMLmqaBn3aQnvKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aa
# dMreSx7nDmOu5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXD
# j/chsrIRt7t/8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB
# 4Q+UDCEdslQpJYls5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ
# 33xMdT9j7CFfxCBRa2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amy
# HeUbAgMBAAGjggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC
# 0nFdZEzfLmc/57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823I
# DzAOBgNVHQ8BAf8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYD
# VR0fBD4wPDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# QXNzdXJlZElEUm9vdENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcN
# AQEMBQADggEBAHCgv0NcVec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxpp
# VCLtpIh3bb0aFPQTSnovLbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6
# mouyXtTP0UNEm0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPH
# h6jSTEAZNUZqaVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCN
# NWAcAgPLILCsWKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg6
# 2fC2h5b9W9FcrBjDTZ9ztwGpn1eqXijiuZQwgga0MIIEnKADAgECAhANx6xXBf8h
# mS5AQyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0z
# ODAxMTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcg
# UlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGP
# NRcybEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1I
# pYzTqpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj7GH8BLuxBG5A
# vftBdsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDRe
# b6e3mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBUR
# Jg6zMUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+8y9oHRaQT/ao
# fEnS5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQ
# skBBBnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJ
# lIqLXvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqIMRvUBDx6z1ev
# +7psNOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6B
# aaeEWvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IB
# XTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6yuKQ
# VvYv1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEE
# AjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9
# vgvItTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQM2qEJPe36zwb
# SI/mS83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTL
# xLgXf9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD
# 8liyrukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1UH410ANVk
# o43+Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRa
# Ps+2ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8
# cipDoq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRz
# W6AxnJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KC
# LPAlZ66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx9yHbxtl5TPau
# 1j/1MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPS
# xyZsq8WhbaM2tszWkPZPubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN8QWC0cR2p5V0
# aDANBgkqhkiG9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNl
# cnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1w
# aW5nIFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAwMDAwMFoXDTM2
# MDkwMzIzNTk1OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMTswOQYDVQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAg
# UmVzcG9uZGVyIDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# ANBGrC0Sxp7Q6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx+wvA69HFTBdw
# bHwBSOeLpvPnZ8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvNZh6wW2R6kSu9
# RJt/4QhguSssp3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlLnh00Cll8pjrU
# cCV3K3E0zz09ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmncOOMA3CoB/iU
# SROUINDT98oksouTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhwUmotuQhcg9tw
# 2YD3w6ySSSu+3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL4Q1OpbybpMe4
# 6YceNA0LfNsnqcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnDuSeHVZlc4seA
# O+6d2sC26/PQPdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCyFG1roSrgHjSH
# lq8xymLnjCbSLZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7aSUROwnu7zER6
# EaJ+AliL7ojTdS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+giAwW00aHzrDch
# Ic2bQhpp0IoKRR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGjggGVMIIBkTAM
# BgNVHRMBAf8EAjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBDz2GM6DAfBgNV
# HSMEGDAWgBTvb1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUF
# BzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6
# Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFt
# cGluZ1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5o
# dHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3Rh
# bXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwB
# BAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3xHCcEua5gQezR
# CESeY0ByIfjk9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh8/YmRDfxT7C0
# k8FUFqNh+tshgb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZSe2F8AQ/UdKFO
# tj7YMTmqPO9mzskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/JQ/EABgfZXLW
# U0ziTN6R3ygQBHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1uNnzQVTeLni2n
# HkX/QqvXnNb+YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq8/gVutDojBIF
# eRlqAcuEVT0cKsb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwiCZ85EE8LUkqR
# hoS3Y50OHgaY7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ+8Hggt8l2Yv7
# roancJIFcbojBcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1R9xJgKf47Cdx
# VRd/ndUlQ05oxYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstrniLvUxxVZE/r
# ptb7IRE2lskKPIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWuiC7POGT75qaL
# 6vdCvHlshtjdNXOCIUjsarfNZzGCBPwwggT4AgEBMDEwHTEbMBkGA1UEAwwSUG93
# ZXJTaGVsbCBSb290IENBAhAT5FOc42Ttl0nO/PRq5gZDMAkGBSsOAwIaBQCgeDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEW
# BBSH926/7vTOLEc4TMOsZKhWo0hWRDANBgkqhkiG9w0BAQEFAASCAQCyGHq8kGcS
# zSkBIYcI9B9hyDInlN8GrluhVqzf4/IoW0/HfUtjiXPlMYvfJQ3IgrIM/OGXEzP7
# Ftp5qYXUtxVxv8n5yUA7DC87Z9cXvLuqC2gWepSm6aTekuYbeFpJtkvU+DtMmAQb
# YUgJcL1/kPOoo1GaAMz5UQcp5hfCt9vBoCrONGP4Bk88G7akrb5CpsxGu5Ppeaix
# FnkZDPl5WGdRw/iKm9cvLy8Hv3ubdZIKyK2NUZWQgoY0LJfZzOeYpr6oc/zRKxKk
# JYUFipfJuv3rXbIxRo/rgzfb8HXLep3+KZeo0NHp1qlRPWKvzyvq83ARtcTn3X9G
# kOvrC+iIHtw7oYIDJjCCAyIGCSqGSIb3DQEJBjGCAxMwggMPAgEBMH0waTELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdp
# Q2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1
# IENBMQIQCoDvGEuN8QWC0cR2p5V0aDANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3
# DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI2MDcxOTEwNTIxMFow
# LwYJKoZIhvcNAQkEMSIEIB/QKgLzmLVG7x4aU3JWzzbc2eGGfZx8TnkOUhAr+CYB
# MA0GCSqGSIb3DQEBAQUABIICAHLTwK1g9ktp2t1hX2ciLhEsaA+12W4VG7jFqpnp
# 33k2UmZ8IROiV8C6FW9Fh1qwNYqYA/IDbmCHBEoe8q+ASnZYS7gjuZbRJLEwUKSc
# IsvBuecxJ9ZZzWi86D0oE2ViB49w+kiEkg+1PPCLV+J/bRXp1vUtIVFuovexcBQd
# 9VlWL9wAJ67fH0A85rwLLTbENAVXQGsszO+7p9Khm7p5KYBUgKnf9hD6sXJsgMaC
# gAfm2QOE+LbSqIAv8y3b/Ii071SR6bsqp2XR33rNgUoaeejGfkerTKFMzJV2Gg4t
# 4j9l+Oz/XwGFXVCfsRv1roqgTYBormUBwZPllzY1X7W26qFyCql3215+gWHG7gNV
# lXKZ16Z7e6GfxOiyQh9XTCS/UfMTQWZ6FHhVuw94wKSxwaB5aihPizVVj1FUuapi
# 6KA+/wJqjl9TNYqYoc/vgdHPhACvtG36YeYz5vHOQVgoG40Uvl37Drle6erJHFXA
# a75l/5BTQXh+68/zIO85ryHRu5miAJjrO4sl9e8hSng2ZoVXRX2IRZmAvYCCtrhL
# zPoKjHjprydJg5xBt2fVT0Ua3VAbNInh1Pd4I+/c0YS2FYKcLq7Sz1mCQ0i2X6xv
# YufDVptX/u3DmbGviqjjTdzrdBLrSAsCpPp7PzQsfME5SjcJx4FP080scvgERf9K
# Dknr
# SIG # End signature block
