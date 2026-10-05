<# silence                                            v1.0.4
   silence detect and analyse
#>
param(
    [string]$InputDir="F:\av\audio\downloads",
    [string]$InputFile="EUE.mp3",
    [string]$logPath= '\logs',    
    [string]$OutputLog="silence.log",
    [string]$OutputCsv = "EUE.csv"
)
$debug=0
Set-Location $InputDir
#& $silenceScript -dd $InputDir -logPath $silenceLog -InputFile $file.FullName -OutputLog "$baseName.sil.log"

# analyze the MP3 audio file
$ErrorActionPreference = 'Continue'
[double]$MinSilenceSeconds = 0.35
[string]$Threshold = '-35dB'
$ymd = (Get-Date).ToString('yyyyMMdd')
$script:LogDirectory = Join-Path $InputDir 'logs'
$script:DailyLogFile = Join-Path $script:LogDirectory "$ymd.txt"



function Write-Log {
    param([string]$Message)
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $targetLog = if ($script:LogDirectory) { Join-Path $script:LogDirectory "$ymd.txt" } else { $script:DailyLogFile }
    $null = New-Item -Path (Split-Path -Path $targetLog -Parent) -ItemType Directory -Force
    Add-Content -Path $targetLog -Value "[$stamp] $Message"
}

function AnalyzeSilence {
    param([string]$fName, [string]$logName)

    $filterLogPath = ($logName -replace '\\', '/') -replace ':', '\:'
    $filter = "silencedetect=noise=$Threshold`:d=$MinSilenceSeconds,ametadata=mode=print:file='$filterLogPath'"
    $arguments = @(
        '-hide_banner', 
        '-nostats', 
        '-i', $fName, 
        '-af', $filter, 
        '-f', 'null', '-'
        )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & ffmpeg @arguments 2>$null | Out-Null
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg silence analysis failed for '$fName' with exit code $LASTEXITCODE"
    }


    if (-not (Test-Path -LiteralPath $fName -PathType Leaf)) {
        throw "Input file not found: $fName"
    }

    $logDirectory = Split-Path -Parent $logName
    if ($logDirectory) {
        $null = New-Item -ItemType Directory -Path $logDirectory -Force
    }

      if (-not $logName) {
        $logName = [System.IO.Path]::ChangeExtension("$fName", '.Silence.log')
    }

    if (-not $OutputCsv) {
        $OutputCsv = [System.IO.Path]::ChangeExtension("$fName", '.Silence.csv')
    }


    $outputDirectory = Split-Path -Parent $OutputCsv
    if ($outputDirectory) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

   # process results from the analysis log and categorize silence segments
    $result = [System.Collections.Generic.List[object]]::new()
    $currentFrame = 0
    $currentPts = $null
    $currentPtsTime = $null
    $silenceStart = $null
    $previousSilenceEnd = 0.0
    $speechDuration = 0.0
    $category = 'none'

    foreach ($line in Get-Content -LiteralPath $logName) {
        if ($line -match '^frame:(?<frame>\d+)\s+pts:(?<pts>\S+)\s+pts_time:(?<ptsTime>\S+)') {
            $currentFrame = [int]$matches.frame
            $currentPts = $matches.pts
            $currentPtsTime = $matches.ptsTime
            continue
        }

        if ($line -match '^lavfi\.silence_start=(?<start>-?\d+(?:\.\d+)?)$') {
            $silenceStart = [double]$matches.start
            $speechDuration = $silenceStart - $previousSilenceEnd
            $category = if ($speechDuration -gt 25) { 'constant25' } 
            elseif ($speechDuration -gt 15) { 'constant15' } 
            elseif ($speechDuration -gt 5) { 'constant5' } 
            else { 'none' }
            continue
        }

        if ($line -match '^lavfi\.silence_end=(?<end>-?\d+(?:\.\d+)?)$') {
            $silenceEnd = [double]$matches.end
            $silenceDuration = $null
            continue
        }

        if ($line -match '^lavfi\.silence_duration=(?<duration>-?\d+(?:\.\d+)?)$' -and $null -ne $silenceStart) {
            $silenceDuration = [double]$matches.duration
            if ($category -eq 'none') {
                $category = if ($silenceDuration -lt 0.5) { 'breath' } else { 'quiet' }
            }

            $result.Add([PSCustomObject]@{
                Frame = $currentFrame
                pts = $currentPts
                pts_time = $currentPtsTime
                start = $silenceStart
                end = $silenceEnd
                dura = $silenceDuration
                cat = $category
            })

            $previousSilenceEnd = $silenceEnd
            $silenceStart = $null
            $category = 'none'
        }
      #  Write-Host $line
    }

    if ($debug) {$result | Format-Table -Property Frame, pts, pts_time, start, end, dura, cat -AutoSize}
    #$OutputCsv = $OutputCsv -replace '\.csv$', '.silence.csv'
    $result | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation
    
    Write-Host "=========  Silence output   $OutputCsv " 
}
    Write-Host "========= analyze silence   ===========================================" -foregroundColor Blue
    Write-Host "Input   =  $InputFile"
AnalyzeSilence -Fname $InputFile -LogName $OutputLog
