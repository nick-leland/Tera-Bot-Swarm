# Analyze nvlddmkm.sys to find hypervisor detection and vendor ID check bytes
$sysPath = 'C:\Windows\System32\DriverStore\FileRepository\nv_dispi.inf_amd64_4bf4c17fa8a478b5\nvlddmkm.sys'
$workDir = 'C:\Windows\Temp\nvpatch'
New-Item -Path $workDir -ItemType Directory -Force | Out-Null
$workFile = "$workDir\nvlddmkm.sys"
Copy-Item $sysPath $workFile -Force
Write-Host "Copied nvlddmkm.sys ($([math]::Round((Get-Item $workFile).Length/1MB,1)) MB)"

$bytes = [System.IO.File]::ReadAllBytes($workFile)
$len = $bytes.Length
Write-Host "Loaded $len bytes"

function Find-Pattern {
    param([byte[]]$haystack, [byte[]]$needle, [int]$maxHits = 20)
    $hits = [System.Collections.Generic.List[int]]::new()
    $n = $needle.Length
    for ($i = 0; $i -le $haystack.Length - $n; $i++) {
        $match = $true
        for ($j = 0; $j -lt $n; $j++) {
            if ($haystack[$i+$j] -ne $needle[$j]) { $match = $false; break }
        }
        if ($match) {
            $hits.Add($i)
            if ($hits.Count -ge $maxHits) { break }
        }
    }
    return $hits
}

function Show-Context {
    param([byte[]]$bytes, [int]$offset, [int]$before=8, [int]$after=24)
    $start = [Math]::Max(0, $offset - $before)
    $end   = [Math]::Min($bytes.Length-1, $offset + $after)
    $hex = ($start..$end | ForEach-Object {
        if ($_ -eq $offset) { "[$($bytes[$_].ToString('X2'))]" }
        else { $bytes[$_].ToString('X2') }
    }) -join ' '
    return "0x{0:X8}: {1}" -f $offset, $hex
}

Write-Host ""
Write-Host "=== Search 1: CPUID instruction (0F A2) ==="
$cpuidPattern = [byte[]]@(0x0F, 0xA2)
$cpuidHits = Find-Pattern $bytes $cpuidPattern 50
Write-Host "Found $($cpuidHits.Count) CPUID instructions"

# For each CPUID, look at context for hypervisor-related patterns
$hvCpuidHits = @()
foreach ($offset in $cpuidHits) {
    # Check surrounding 32 bytes for hypervisor bit test patterns
    $start = [Math]::Max(0, $offset - 16)
    $end   = [Math]::Min($len-1, $offset + 32)
    $ctx = $bytes[$start..$end]
    # Look for TEST ECX, 80000000h: F7 C1 00 00 00 80
    # Look for MOV EAX, 1: B8 01 00 00 00
    # Look for MOV EAX, 40000000h: B8 00 00 40 00
    $hasHv1 = ($ctx | Where-Object { $_ -eq 0xB8 }) -ne $null
    $ctxStr = ($ctx | ForEach-Object { $_.ToString('X2') }) -join ' '
    if ($ctxStr -match 'B8 01 00 00 00|B8 00 00 40 00|F7 C1|F6 C1|0F BA|A9 00 00 00 80') {
        $hvCpuidHits += $offset
        Write-Host (Show-Context $bytes $offset 16 40)
        Write-Host ""
    }
}
Write-Host "Hypervisor-likely CPUID hits: $($hvCpuidHits.Count)"

Write-Host ""
Write-Host "=== Search 2: 'Microsoft Hv' hypervisor vendor string ==="
# "Micr" in LE DWORD comparison: CMP EBX, 0x7263694D → bytes: 81 FB 4D 69 63 72
$msHvPattern = [byte[]]@(0x81, 0xFB, 0x4D, 0x69, 0x63, 0x72)
$msHvHits = Find-Pattern $bytes $msHvPattern 10
Write-Host "Found $($msHvHits.Count) 'CMP EBX, Micr' patterns:"
foreach ($offset in $msHvHits) {
    Write-Host (Show-Context $bytes $offset 16 48)
    Write-Host ""
}

# Also search for the raw string "Microsoft Hv"
$msHvStr = [System.Text.Encoding]::ASCII.GetBytes("Microsoft Hv")
$msHvStrHits = Find-Pattern $bytes $msHvStr 10
Write-Host "Found $($msHvStrHits.Count) literal 'Microsoft Hv' strings:"
foreach ($offset in $msHvStrHits) {
    Write-Host (Show-Context $bytes $offset 4 20)
}

Write-Host ""
Write-Host "=== Search 3: TEST ECX, 0x80000000 (hypervisor bit check) ==="
$testPattern = [byte[]]@(0xF7, 0xC1, 0x00, 0x00, 0x00, 0x80)
$testHits = Find-Pattern $bytes $testPattern 20
Write-Host "Found $($testHits.Count) hits:"
foreach ($offset in $testHits) {
    # Show instruction + following conditional jump
    Write-Host (Show-Context $bytes $offset 12 16)
    Write-Host ""
}

Write-Host ""
Write-Host "=== Search 4: 0x10DE (NVIDIA vendor ID) comparisons ==="
# CMP r16, 10DEh: 66 81 F8 DE 10 or 66 81 FB DE 10 or 66 81 FF DE 10
$vendorPatterns = @(
    @{Name="CMP AX,10DE";   Bytes=[byte[]]@(0x66, 0x81, 0xF8, 0xDE, 0x10)},
    @{Name="CMP BX,10DE";   Bytes=[byte[]]@(0x66, 0x81, 0xFB, 0xDE, 0x10)},
    @{Name="CMP CX,10DE";   Bytes=[byte[]]@(0x66, 0x81, 0xF9, 0xDE, 0x10)},
    @{Name="CMP DX,10DE";   Bytes=[byte[]]@(0x66, 0x81, 0xFA, 0xDE, 0x10)},
    @{Name="CMP [mem],10DE";Bytes=[byte[]]@(0x66, 0x81, 0x3D)},
    @{Name="MOV+10DE DWORD";Bytes=[byte[]]@(0xDE, 0x10, 0x00, 0x00)},
    @{Name="10DE word";     Bytes=[byte[]]@(0xDE, 0x10)}
)
foreach ($pat in $vendorPatterns) {
    $hits = Find-Pattern $bytes $pat.Bytes 5
    if ($hits.Count -gt 0) {
        Write-Host "$($pat.Name): $($hits.Count) hits"
        foreach ($offset in ($hits | Select-Object -First 3)) {
            Write-Host "  $(Show-Context $bytes $offset 8 20)"
        }
    }
}

Write-Host ""
Write-Host "=== Search 5: 0x1414 (VEN_1414 check) ==="
$v1414Patterns = @(
    @{Name="CMP AX,1414";   Bytes=[byte[]]@(0x66, 0x81, 0xF8, 0x14, 0x14)},
    @{Name="0x1414 word";   Bytes=[byte[]]@(0x14, 0x14, 0x00, 0x00)},
    @{Name="1414 raw";      Bytes=[byte[]]@(0x14, 0x14)}
)
foreach ($pat in $v1414Patterns) {
    $hits = Find-Pattern $bytes $pat.Bytes 5
    if ($hits.Count -gt 0) {
        Write-Host "$($pat.Name): $($hits.Count) hits"
        foreach ($offset in ($hits | Select-Object -First 3)) {
            Write-Host "  $(Show-Context $bytes $offset 8 20)"
        }
    }
}

Write-Host ""
Write-Host "=== Search 6: KeBugCheckEx call patterns ==="
# KeBugCheckEx is called with specific bugcheck codes for GPU failures
# Common codes: 0x116 (VIDEO_TDR_FAILURE), 0x119 (VIDEO_SCHEDULER_INTERNAL_ERROR)
$bugPatterns = @(
    @{Name="BugCheck 0x116"; Bytes=[byte[]]@(0x16, 0x01, 0x00, 0x00)},
    @{Name="BugCheck 0x119"; Bytes=[byte[]]@(0x19, 0x01, 0x00, 0x00)},
    @{Name="BugCheck 0xDEAD";Bytes=[byte[]]@(0xAD, 0xDE)}
)
foreach ($pat in $bugPatterns) {
    $hits = Find-Pattern $bytes $pat.Bytes 5
    if ($hits.Count -gt 0) {
        Write-Host "$($pat.Name): $($hits.Count) hits"
        $hits | Select-Object -First 2 | ForEach-Object { Write-Host "  $(Show-Context $bytes $_ 8 20)" }
    }
}

Write-Host ""
Write-Host "Analysis complete. Work file: $workFile"
