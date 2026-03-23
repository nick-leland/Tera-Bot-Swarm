$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    $infPath = 'C:\Windows\System32\HostDriverStore\FileRepository\nv_dispi.inf_amd64_6d8eaa80a18aada4\nv_dispi.inf'

    $bytes = [System.IO.File]::ReadAllBytes($infPath)
    $hasUTF16 = ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)
    Write-Host "File size: $($bytes.Length), UTF-16: $hasUTF16"

    $content = if ($hasUTF16) {
        [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) -split "`r?`n"
    } else {
        [System.Text.Encoding]::ASCII.GetString($bytes) -split "`r?`n"
    }
    Write-Host "Lines: $($content.Count)"

    # Find DEV_2B85
    $found = $false
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -like '*DEV_2B85*' -and $content[$i] -like '*Section*') {
            $lineNum = $i
            $lineText = $content[$i]
            Write-Host "Found DEV_2B85 at line ${lineNum}: ${lineText}"
            $found = $true
        }
    }
    if (!$found) { Write-Host 'DEV_2B85 NOT FOUND in this INF (wrong driver version?)' }

    # Show first few manufacturer section headers
    Write-Host '=== NTamd64 sections ==='
    for ($i = 0; $i -lt [Math]::Min($content.Count, 400); $i++) {
        if ($content[$i] -match '^\[NVidia.*NTamd64') {
            $lineNum = $i; $lineText = $content[$i]
            Write-Host "Line ${lineNum}: ${lineText}"
        }
    }
}
