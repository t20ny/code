<# silence                                            v1.0.5
   silence detect and analyse
#>
param(
    [string]$InputDir="F:\av\audio\downloads",
    [string]$InputFile="_source.mp3",
    [string]$logPath= 'logs',    
    [string]$OutputDir = 'F:\av\audio\done',
    [string]$OutputLog="_silence.log",
    [string]$OutputCsv = "_sil.csv",
    $mode=1,
    $debug=1
)
write-host $PSCommandPath -BackgroundColor cyan
Set-Location $InputDir
#& $silenceScript -dd $InputDir -logPath $silenceLog -InputFile $file.FullName -OutputLog "$baseName.sil.log"
if ($OutputCsv -notmatch "sil.csv"){
    $OutputCsv =$OutputCsv -replace ".csv",".sil.csv"
}
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($OutputCsv)
$OutputCsv="$OutputDir\logs\_sil.Csv"

# analyze the MP3 audio file
$ErrorActionPreference = 'Continue'
$modeText = [string]$mode
$modeKey = $modeText.Trim().ToLowerInvariant()
$resolvedMode = 1
switch ($modeKey) {
    '1' { $resolvedMode = 1 }
    'podcast' { $resolvedMode = 1 }
    'balanced' { $resolvedMode = 1 }
    '2' { $resolvedMode = 2 }
    'speech' { $resolvedMode = 2 }
    '3' { $resolvedMode = 3 }
    'quiet' { $resolvedMode = 3 }
    'quiet-room' { $resolvedMode = 3 }
    'traffic' { $resolvedMode = 3 }
    '4' { $resolvedMode = 4 }
    'sleep' { $resolvedMode = 4 }
    '5' { $resolvedMode = 5 }
    'crowd' { $resolvedMode = 5 }
    'noisy' { $resolvedMode = 5 }
    '6' { $resolvedMode = 6 }
    'speed' { $resolvedMode = 6 }
    'aggressive' { $resolvedMode = 6 }
    default {
        if ($modeText -match '^[0-9]+$') {
            $resolvedMode = [int]$modeText
        }
        else {
            $resolvedMode = 1
        }
    }
}


# adjust mode setting so final Trim  TOTAL 75 to 150 seconds
[string]$ModeName = 'podcast'
switch ($resolvedMode) {
    1 {
        # Standard podcast cleanup: trims dead air without chopping normal speech pauses.
        [double]$MinSilenceSeconds = 0.35
        [string]$Threshold = '-35dB'
        $ModeName = 'podcast'
    }
    2 {
        # Slightly more sensitive to short speech gaps and quiet breaths.
        [double]$MinSilenceSeconds = 0.25
        [string]$Threshold = '-30dB'
        $ModeName = 'speech'
    }
    3 {
        # Low-noise / quiet-room setting: preserves only real silence, avoids cleaning too much.
        [double]$MinSilenceSeconds = 0.50
        [string]$Threshold = '-40dB'
        $ModeName = 'quiet-room'
    }
    4 {
        # More aggressive dead-air removal for sleeping or low-content segments.
        [double]$MinSilenceSeconds = 1.00
        [string]$Threshold = '-45dB'
        $ModeName = 'sleep'
    }
    5 {
        # Noisy environment setting: removes longer loud sections but keeps speech audible.
        [double]$MinSilenceSeconds = 0.75
        [string]$Threshold = '-25dB'
        $ModeName = 'noisy'
    }
    6 {
        # Very aggressive cleanup for stripping filler and long gaps.
        [double]$MinSilenceSeconds = 0.12
        [string]$Threshold = '-20dB'
        $ModeName = 'aggressive'
    }
    7 {
        # Very aggressive 
        [double]$MinSilenceSeconds = 0.20
        [string]$Threshold = '-30dB'
        $ModeName = 'aggressive'
    }
    default {
        [double]$MinSilenceSeconds = 0.35
        [string]$Threshold = '-35dB'
        $ModeName = 'podcast'
    }
}
Write-Host "========= Silence mode $resolvedMode [$ModeName] threshold $Threshold, minimum silence $MinSilenceSeconds seconds" -ForegroundColor blue

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
    if ($debug){
        write-host $InputDir -ForegroundColor Cyan
        if (-not(test-path $filterLogPath)){Write-Host "PATH ERROR $filterLogPath" -ForegroundColor red }
        if (-not(test-path $fName)){Write-Host "PATH ERROR $fName" -ForegroundColor red}
        foreach($aa in $arguments){
            Write-Host $aa -ForegroundColor Yellow
        }
    }

    #$ErrorActionPreference = 'Continue'
    try {
        & ffmpeg @arguments 2>$null | Out-Null
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($LASTEXITCODE -ne 0) {
        write-host "ffmpeg silence analysis failed for '$fName' with exit code $LASTEXITCODE" -ForegroundColor red
       # throw "ffmpeg silence analysis failed for '$fName' with exit code $LASTEXITCODE"
    }
 
    if (-not (Test-Path -LiteralPath $fName -PathType Leaf)) {
        throw "Input file not found: $fName"
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
    $delete=1


    $logDirectory = Split-Path -Parent $logName
    if ($logDirectory) {
        $null = New-Item -ItemType Directory -Path $logDirectory -Force
    }

      if (-not $logName) {
        $logName = [System.IO.Path]::ChangeExtension("$fName", '.Silence.log')
    }

    if (Test-Path $logName){
        # log ok
    }
    else {
        write-host "missing expected log $logname" -ForegroundColor Yellow
    }

    if (-not $OutputCsv) {
        $OutputCsv = [System.IO.Path]::ChangeExtension("$fName", '.Silence.csv')
    }
  
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
            $delete=0
            $category = if ($speechDuration -gt 25) { 
                $delete=1
                'constant25' } 
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
                Delete= $delete
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
    
    if($debug){Write-Host "=========  Silence output   $OutputCsv " }
}
            
if($debug){
    Write-Host "========= analyze silence         ===========================================" -foregroundColor Blue
    Write-Host "Input   =  $InputFile"
}
AnalyzeSilence -Fname $InputFile -LogName $OutputLog
