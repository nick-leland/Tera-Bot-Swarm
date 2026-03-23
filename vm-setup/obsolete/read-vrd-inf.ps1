## Read vrd.inf to understand what it sets for the GPU-P device
$VMName = 'TeraBot1'
$VMCred = New-Object System.Management.Automation.PSCredential('bot', (ConvertTo-SecureString 'bot123' -AsPlainText -Force))

Invoke-Command -VMName $VMName -Credential $VMCred -ScriptBlock {
    # Find vrd.inf
    $vrd = Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Filter 'vrd.inf' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (!$vrd) {
        $vrd = Get-ChildItem 'C:\Windows\INF' -Filter 'vrd.inf' -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($vrd) {
        Write-Host "Found: $($vrd.FullName)"
        Get-Content $vrd.FullName
    } else {
        Write-Host 'vrd.inf not found - searching...'
        Get-ChildItem 'C:\Windows' -Filter 'vrd*' -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
    }
}
