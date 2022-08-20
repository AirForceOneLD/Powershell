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

