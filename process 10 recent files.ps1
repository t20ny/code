# process recent files
param(
    [string]$InputDir = 'F:\av\audio\downloads',
    [string]$OutputDir = 'F:\av\audio\done',
    [string[]]$FileArray = @(),
    [string]$LogFile = '',
    [int]$count=10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
Set-Location -LiteralPath $scriptRoot

function Get-RecentMp3Files {
    param(
        [string]$Directory,
        [switch]$NewestOnly
    )

    $files = @(Get-ChildItem -Path $Directory -File -Filter '*.mp3' -ErrorAction SilentlyContinue  | Sort-Object LastWriteTime)
    if (-not $files) { return @() }
    # get 10 recent files
    return @($files | Select-Object -Last $count)
}


function Write-ResultEntry {
    param(
        [string]$Path,
        [string]$Message
    )

    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -Path $Path -Value "[$stamp] $Message"
}

if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
    throw "Input directory not found: $InputDir"
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $InputDir 'processed'
}

$null = New-Item -Path $OutputDir -ItemType Directory -Force
$logDir = Join-Path $OutputDir 'logs'
$null = New-Item -Path $logDir -ItemType Directory -Force

if (-not $LogFile) {
    $runStamp = (Get-Date).ToString('yyyyMMdd.HHmmss')
    $LogFile = Join-Path $logDir "process_recent_$runStamp.log"
}

$resolvedFiles = @()
if ($FileArray.Count -gt 0) {
    foreach ($item in $FileArray) {
        $candidate = if ([System.IO.Path]::IsPathRooted($item)) { $item } else { Join-Path $InputDir $item }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $resolvedFiles += Get-Item -LiteralPath $candidate
        }
        else {
            Write-ResultEntry -Path $LogFile -Message "SKIP missing file: $candidate"
        }
    }
}
else {
    $resolvedFiles = @(Get-RecentMp3Files -Directory $InputDir -NewestOnly:$Latest)
}

if ($resolvedFiles.Count -eq 0) {
    Write-ResultEntry -Path $LogFile -Message "No MP3 files found in $InputDir"
    throw "No MP3 files found in: $InputDir"
}

$results = @()
foreach ($file in $resolvedFiles) {
    $name = $file.Name
    $fullName = $file.FullName
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $cleanedOutput = Join-Path $OutputDir ("{0}_cleaned.mp3" -f $baseName)
    $trimmedOutput = Join-Path $OutputDir ("{0}.mp3" -f $baseName)

    $record = [ordered]@{
        FileName = $name
        FullPath = $fullName
        Status   = 'Failed'
        Message  = ''
    }

    if ((Test-Path -LiteralPath $cleanedOutput -PathType Leaf) -or (Test-Path -LiteralPath $trimmedOutput -PathType Leaf)) {
        $record.Status = 'Skipped'
        $record.Message = 'Already processed'
        Write-ResultEntry -Path $LogFile -Message "SKIP $fullName (already processed)"
        $results += [pscustomobject]$record
        continue
    }

    Write-ResultEntry -Path $LogFile -Message "START $fullName"

    try {
        & (Join-Path $scriptRoot 'process_mp3_files.ps1') -InputDir $InputDir -OutputDir $OutputDir -FileArray @($fullName)
        $record.Status = 'Succeeded'
        $record.Message = 'Processed successfully'
        Write-ResultEntry -Path $LogFile -Message "SUCCESS $fullName"
    }
    catch {
        $record.Message = $_.Exception.Message
        Write-ResultEntry -Path $LogFile -Message "ERROR $fullName : $($_.Exception.Message)"
    }

    $results += [pscustomobject]$record
}

$summaryFile = Join-Path $logDir 'process_recent_summary.json'
$results | ConvertTo-Json -Depth 3 | Set-Content -Path $summaryFile
Write-ResultEntry -Path $LogFile -Message "Finished processing $($results.Count) file(s). Summary: $summaryFile"

Write-Output $results

