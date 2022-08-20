<# 
.SYNOPSIS
	sign your code with your own certificate 
.DESCRIPTION
	This Powershell script is used to sign your code with your own certificate. 
	You can select one or more files to sign via a file dialog.
.EXAMPLE
	PS> ./check-operating-system
.LINK
	https://github.com/AirForceOneLD/Powershell_Functions
.NOTES
	Author: Michael Mayer 
	By using this script, it`s important that a script signing certificate is already installed on the computer.
	You can check this with the following command:  Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | fl

#>
# Displays a dialog for opening files and returns the file selected by the user
function Read-OpenFileDialog([string]$InitialDirectory, [switch]$AllowMultiSelect)
	{
	Add-Type -AssemblyName System.Windows.Forms
	$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$openFileDialog.initialDirectory = $InitialDirectory
	$openFileDialog.filter = "Powershell Script Files (*.ps1)|*.ps1|Powershell Modul Files (*.psm1)|*.psm1|Powershell Data Files (*.psd1)|*.psd1|All Files (*.*)|*.*"
	if ($AllowMultiSelect) { $openFileDialog.MultiSelect = $true }
	$openFileDialog.ShowDialog() > $null
	if ($allowMultiSelect) { return $openFileDialog.Filenames } else { return $openFileDialog.Filename }
	}
#Select file or multiple files in the dialog box
$SelectedFile = Read-OpenFileDialog -InitialDirectory C:\ -AllowMultiSelect

try{
	
	$Result = [System.Windows.Forms.MessageBox]::Show("Should the selected files`n`n$SelectedFile`n`nbe signed?","User question",4,[System.Windows.Forms.MessageBoxIcon]::Question,256)

				If ($Result -eq "Yes")
				{
				  #Get your Certicate
					$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert
					#sign selected script file/s
					Set-AuthenticodeSignature -FilePath $SelectedFile -Certificate $cert
					Write-Host "`n`tSuccess...`n" -ForegroundColor Yellow
					exit 0
				}
			elseif ($Result -eq "No")
			#aborted
			{write-host "`n`tProcess was canceled by user`n" -ForegroundColor Red}
}
catch{
	write-host "⚠️ Error in line $($_.InvocationInfo.ScriptLineNumber):`n $($Error[0])" -BackgroundColor Red -ForegroundColor White
	exit 1
}


# SIG # Begin signature block
# MIIEKQYJKoZIhvcNAQcCoIIEGjCCBBYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUwYEDbe7yNLWDD+XTZY2UeqFk
# JC6gggI6MIICNjCCAaOgAwIBAgIQzBpGWAgJKpBOR7UVer1RyjAJBgUrDgMCHQUA
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUzRIUkWxWe3Vi
# 9kmwrQZXhtCqF54wDQYJKoZIhvcNAQEBBQAEgYC7NF5VaffRCLws0DEL1RRTrVYa
# M/xUItKHQ7okqHlbjnEFm6QLJvjdCz22O+Xbk1ckx52x81eL4A/vrXL3uvwbq/g8
# 9cVjRF3ray4wras/4r465cWFh6NAHqWpusP13x0nmMUcbGsHHAjFJGoSz0jp4Jtq
# VfBjX7pQSrPbNcaGng==
# SIG # End signature block
