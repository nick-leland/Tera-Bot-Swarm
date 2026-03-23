$path = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_6d8eaa80a18aada4\nv_dispi.inf'
$bytes = [System.IO.File]::ReadAllBytes($path)
$b0 = $bytes[0]; $b1 = $bytes[1]; $b2 = $bytes[2]
Write-Host "First 3 bytes: $($b0.ToString('X2')) $($b1.ToString('X2')) $($b2.ToString('X2'))"
if ($b0 -eq 0xFF -and $b1 -eq 0xFE) { Write-Host "Encoding: UTF-16 LE (BOM FF FE)" }
elseif ($b0 -eq 0xEF -and $b1 -eq 0xBB -and $b2 -eq 0xBF) { Write-Host "Encoding: UTF-8 with BOM" }
else { Write-Host "Encoding: ANSI/ASCII (no BOM)" }
