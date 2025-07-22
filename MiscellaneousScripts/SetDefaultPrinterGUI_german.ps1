<#
.ZUSAMMENFASSUNG
	PS GUI zum Wechseln des Standarddrucker auf einem lokalen Windows-PC
.BESCHREIBUNG
	PS GUI zum Wechseln des Standarddrucker auf einem lokalen Windows-PC
	getestet unter Windows 10 / 11 Powershell 5.1 und 7.2.6
.BEISPIEL
	PS> ./SetDefaultPrinterGUI_german.ps1
.LINK
	https://github.com/AirForceOneLD/MiscellaneousScripts/SetDefaultPrinterGUI_german.ps1
.ANMERKUNG
	Author: Michael Mayer


#>

#Momentan eingestellter Standarddrucker ermitteln
#Druckername
$CurrentDefaultPrinter = (Get-CimInstance -Class Win32_Printer  | where-Object { $_.default -eq "true" } | Select-Object -expandProperty Name)
#Druckeranschluss
$CurrentDefaultPrinterPort = (Get-CimInstance -Class Win32_Printer  | where-Object { $_.default -eq "true" } | Select-Object -expandProperty PortName)


#Deklaration der Form
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$objForm = New-Object System.Windows.Forms.Form
$objForm.BackColor = "White"
$objForm.BackgroundImageLayout = 1
$objForm.Size = New-Object System.Drawing.Size(500, 220)
$objForm.Text = "Standardrucker festlegen ....."
$objForm.StartPosition = "CenterScreen"
$objForm.TopMost = $true
$objForm.MaximizeBox = $false


# Drucker Auswählen
#Deklaration Label 1
$objLabel = New-Object System.Windows.Forms.Label
$objLabel.Location = New-Object System.Drawing.Size(20, 35)
$objLabel.Size = New-Object System.Drawing.Size(250, 15)
$objLabel.Text = "Bitte wähle einen Drucker aus:"
$objForm.Controls.Add($objLabel)

#Deklaration Label Datum
$objLabelDatum = New-Object System.Windows.Forms.Label
$objLabelDatum.Location = New-Object System.Drawing.Size(400, 10)
$objLabelDatum.Size = New-Object System.Drawing.Size(70, 15)
$objLabelDatum.Text = Get-Date -Format 'dd.MM.yyyy'
$objLabelDatum.BackColor = [System.Drawing.Color]::FromName("Yellow")
$objLabelDatum.ForeColor = [System.Drawing.Color]::FromName("Black")
$objLabelDatum.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$objForm.Controls.Add($objLabelDatum)

#Deklaration Standarddrucker
$objLabelDefaultPrinter = New-Object System.Windows.Forms.Label
$objLabelDefaultPrinter.Location = New-Object System.Drawing.Size(20, 130)
$objLabelDefaultPrinter.Size = New-Object System.Drawing.Size(300, 35)
$objLabelDefaultPrinter.Text = "Aktueller Standarddrucker:`n" + $CurrentDefaultPrinter + "     Anschluss: " + $CurrentDefaultPrinterPort
$objForm.Controls.Add($objLabelDefaultPrinter)

#Deklaration ComboBox
$objComboBoxD = New-Object System.Windows.Forms.ComboBox
$objComboBoxD.Location = New-Object System.Drawing.Size(20, 60)
$objComboBoxD.Size = New-Object System.Drawing.Size(240, 70)
$objComboBoxD.Height = 70
$objComboBoxD.Sorted = $true
$objForm.Controls.Add($objComboBoxD)


#Drucker auflisten die lokal installiert sind
#ComboBox mit Daten füllen
$objForm.Add_Load({
        $objComboBoxD.Items.AddRange((Get-Printer | Select-Object -Expand Name))
    })

# MSG-Box Informationen über den ausgewählten Drucker (Kann man starten, wenn man die Infos will)
#$objComboBoxD.Add_SelectedIndexChanged({[System.Windows.Forms.MessageBox]::Show((Get-Printer -Name $objComboBoxD.SelectedItem | Format-List * | out-string))})

# Schaltfläche 'Drucker festlegen'
$StartButton = New-Object System.Windows.Forms.Button
$StartButton.Location = New-Object System.Drawing.Size(270, 55)
$StartButton.Size = New-Object System.Drawing.Size (95, 30)
$StartButton.Text = "Übernehmen"
$objForm.Controls.Add($StartButton)
$StartButton.Add_Click({
        try {
            $MYPRINTER = $objComboBoxD.SelectedItem
            $PRINTERTMP = (Get-CimInstance -ClassName CIM_Printer | Where-Object { $_.Name -eq $MYPRINTER }[0])
            $PRINTERTMP | Invoke-CimMethod -MethodName SetDefaultPrinter | Out-Null
            $ChangeDefaultPrinter = (Get-CimInstance -Class Win32_Printer  | where-Object { $_.default -eq "true" } | Select-Object -expandProperty Name)
            $ChangeDefaultPrinterPort = (Get-CimInstance -Class Win32_Printer  | where-Object { $_.default -eq "true" } | Select-Object -expandProperty PortName)
            $objLabelDefaultPrinter.Text = "Aktueller Standarddrucker:`n" + $ChangeDefaultPrinter + "     Anschluss: " + $ChangeDefaultPrinterPort
            $objComboBoxD.Text = ""
            Write-Host "`n`tDer Standarddrucker wurde erfolgreich in >$MYPRINTER<  geändert." -BackgroundColor DarkCyan -ForegroundColor White
        }
        catch {
            Write-Warning "Fehler!`n Fehlerdetails:`n" + $error
            $objForm.Close()
            $objForm.Dispose()
        }
    })

# Schältfläche 'Beenden'
$CancelButton = New-Object System.Windows.Forms.Button
$CancelButton.Location = New-Object System.Drawing.Size(380, 55)
$CancelButton.Size = New-Object System.Drawing.Size(95, 30)
$CancelButton.Text = "Beenden"
$objForm.Controls.Add($CancelButton)
$CancelButton.Add_Click(
    {
        $objForm.Close()
        $objForm.Dispose()
    })


#Form anzeigen
$objForm.ShowDialog($objForm.Dialog.Result)


# SIG # Begin signature block
# MIIEKQYJKoZIhvcNAQcCoIIEGjCCBBYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUvycAuXriJoW3V+4bWEV0kD3o
# DD2gggI6MIICNjCCAaOgAwIBAgIQzBpGWAgJKpBOR7UVer1RyjAJBgUrDgMCHQUA
# MCUxIzAhBgNVBAMTGlBvd2VyU2hlbGwgQ29kZUNlcnRpZmljYXRlMB4XDTIxMDgw
# MzE3MTExMloXDTM5MTIzMTIzNTk1OVowJTEjMCEGA1UEAxMaUG93ZXJTaGVsbCBD
# b2RlQ2VydGlmaWNhdGUwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAMKYNd+Y
# PrdL/9wC3kIl+NV8t4eZKfyyiQJgG9fg2j5NyTYRCWkgytZQSgaTWAQyawwMJ0da
# bVPTMGLi5Gz7MF6KTA22whxuhedskX53Tpc0A1JPAwPKf/RAEygUTkzubw/exmL0
# eG5avyszcVotQP1ING6VkIpOBuUvKCvFBZ8dAgMBAAGjbzBtMBMGA1UdJQQMMAoG
# CCsGAQUFBwMDMFYGA1UdAQRPME2AEL4soXO6jrrPotjQD4mhdGGhJzAlMSMwIQYD
# VQQDExpQb3dlclNoZWxsIENvZGVDZXJ0aWZpY2F0ZYIQzBpGWAgJKpBOR7UVer1R
# yjAJBgUrDgMCHQUAA4GBAGJ2wcJDM7rVWFKXXQtrckvwdSs9MEyOdJhpnTA9lckh
# KZ90bLXR+2HDpBXDY8oV+XQJq/uJnrzNI4KQzsHITuaiOWokxpNX2brHJOyNQODH
# 2JWZAXEdTIKy3DJOXF9CkvIyFe1H8bUVdm8olEGAhNUzKcm7CyN2NLjd1PmH0VQ7
# MYIBWTCCAVUCAQEwOTAlMSMwIQYDVQQDExpQb3dlclNoZWxsIENvZGVDZXJ0aWZp
# Y2F0ZQIQzBpGWAgJKpBOR7UVer1RyjAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIB
# DDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU6kbz6WPhss+y
# dbpZpmgdclp7AYEwDQYJKoZIhvcNAQEBBQAEgYCMYw1xn02EZbSqXT4VMenSnZ+D
# z5RMFzNKfGx+lmZYgAkaIx/3tsACyL+HC7b/EfF+VDPD0SNuca/aJdbsEEn7a/Yd
# JlrbjZGDhOEeUfaIwtZ4QCe9LKEC7PlNUbKKCEQfeeCmEx6EeBxoXfd+HoND3V5o
# jbEgGi8AFmEkv6Az6A==
# SIG # End signature block
