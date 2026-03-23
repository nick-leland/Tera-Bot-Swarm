param(
    [Parameter(Mandatory=$true)]
    [string]$InputDir,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

# Make sure ffmpeg is in PATH
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg not found in PATH. Install it and try again."
    exit 1
}

# Create output directory if it doesn't exist
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# Get all .mp4 files in the input directory
$files = Get-ChildItem -Path $InputDir -Filter *.mp4
if ($files.Count -eq 0) {
    Write-Host "No .mp4 files found in $InputDir"
    exit 0
}

foreach ($file in $files) {
    $outputFile = Join-Path $OutputDir ($file.BaseName + ".webm")
    Write-Host "Converting $($file.Name) -> $outputFile"

    # Run ffmpeg
    & ffmpeg -i $file.FullName -c:v libvpx-vp9 -b:v 2M -c:a libopus $outputFile
}

Write-Host "All conversions complete. Output saved in $OutputDir"
