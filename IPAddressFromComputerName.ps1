$Computer = $env:COMPUTERNAME

$computerNetwork = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName $Computer
Clear-Host
write-host "Netzwork:" -BackgroundColor DarkRed -ForegroundColor White
Write-Host "- IP-Adress: " $computerNetwork.IPAddress -ForegroundColor Yellow
Write-Host "- MAC-Adress:" $computerNetwork.MACAddress -ForegroundColor Yellow
Write-Host "- Gateway:     " $computerNetwork.DefaultIPGateway -ForegroundColor Yellow
Write-Host "- DNS Server:  " $computerNetwork.DNSServerSearchOrder -ForegroundColor Yellow

Write-Host " "

