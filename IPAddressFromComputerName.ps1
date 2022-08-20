$Computer = $env:COMPUTERNAME

$computerNetwork = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE -ComputerName $Computer
Clear-Host
write-host "Network:" -BackgroundColor DarkRed -ForegroundColor White
Write-Host "- IP-Adress: " $computerNetwork.IPAddress -ForegroundColor Yellow
Write-Host "- MAC-Adress:" $computerNetwork.MACAddress -ForegroundColor Yellow
Write-Host "- Gateway:     " $computerNetwork.DefaultIPGateway -ForegroundColor Yellow
Write-Host "- DNS Server:  " $computerNetwork.DNSServerSearchOrder -ForegroundColor Yellow

Write-Host " "


# SIG # Begin signature block
# MIIEKQYJKoZIhvcNAQcCoIIEGjCCBBYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUGkoztBRz6k4gsYqn3v4Y+ajD
# vgagggI6MIICNjCCAaOgAwIBAgIQzBpGWAgJKpBOR7UVer1RyjAJBgUrDgMCHQUA
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
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUm6Iv8FIdvSMK
# YFCZkEZ5uPjTOegwDQYJKoZIhvcNAQEBBQAEgYA/iN436uRyb7ubRMPjETuMDcQL
# 5wbaBqunY7J/pIEBLc90loyLuk+YV+xyoAPDtMTCK1f+vD8BD7NcT4KaN6ri6HjK
# 1uDPDvBH4CBLP+S58lPILRMuB6f/HKXui/knK6laJcRsDXJxuhG9BT5ZGN9T7Cxx
# 7C74K9SuxD0Qn0vAgA==
# SIG # End signature block
