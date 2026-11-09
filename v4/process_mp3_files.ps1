<# process main                                                          v2.0.0
-------------------------------------------------------------------------------------
    get RMS data points, analyse, mark delete sections,
    interpolate to ensure delete marks are continuous
    trim and delete THEN export final result.
#>
param(
    [string]$InputDir = 'F:\av\audio\downloads',
    [string]$dd = 'F:\av\audio\downloads',
    [string]$OutputDir = 'F:\av\audio\done',
    [string[]]$fileArray = @(),
    $debug=0,
    [switch]$Latest ,
    [Alias('M')]
    $mode = 1,
    [string]$ModeName = 'Podcast'
)
write-host $PSCommandPath -BackgroundColor cyan
$scriptRoot = $PSScriptRoot
$scriptCaller = $$
Set-Location -LiteralPath $scriptRoot

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$dbug="InputDir {0,-68}" -f  $InputDir 
write-host $dbug  -ForegroundColor Yellow
$InputPath = $InputDir

$dts = (Get-Date).ToString('yyyyMMdd.HHmmss')
$ymd = (Get-Date).ToString('yyyyMMdd')
$script:LogDirectory = Join-Path $OutputDir 'logs'
$script:DailyLogFile = Join-Path $script:LogDirectory "_process_mp3_$ymd.txt"


function Write-Log {
    param([string]$Message)
    $stamp = (Get-Date).ToString('HH:mm:ss')
    $targetLog = if ($script:LogDirectory) { Join-Path $script:LogDirectory "$ymd.txt" } else { $script:DailyLogFile }
    $null = New-Item -Path (Split-Path -Path $targetLog -Parent) -ItemType Directory -Force
    Add-Content -Path $targetLog -Value "[$stamp] $Message"
    write-host $Message -ForegroundColor DarkCyan
}
Write-Log "START ##-by-->  $scriptCaller" 


function Get-Mp3Files {
    param(
        [string]$Directory,
        [switch]$NewestOnly
    )
    $files = @(Get-ChildItem -Path $Directory -File -Filter '*.mp3' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime )
    if ($NewestOnly) {
        if ($files.Count -eq 0) { return @() }
        return @($files | Select-Object -Last 1)
    }
    return @($files)
}


$modeKey = [string]$mode
if ($modeKey -and $modeKey -notmatch '^[0-9]+$') {
    $normalizedMode = $modeKey.Trim().ToLowerInvariant()
    $names = @{
        'podcast' = 1
        'balanced' = 1
        'speech' = 2
        'quiet' = 3
        'quiet-room' = 3
        'traffic' = 3
        'sleep' = 4
        'crowd' = 5
        'noisy' = 5
        'speed' = 6
        'aggressive' = 6
    }
    if ($names.ContainsKey($normalizedMode)) {
        $mode = [int]$names[$normalizedMode]
    }
    else {
        $mode = 1
    }
}
elseif (-not $mode) {
    $mode = 1
}

# MAIN ##################################
if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) {
    throw "Input directory not found: $InputDir"
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $InputDir 'processed'
}
$null = New-Item -Path $OutputDir -ItemType Directory -Force
$logDir = Join-Path $OutputDir 'logs'
$null = New-Item -Path $logDir -ItemType Directory -Force
$script:LogDirectory = $logDir
$script:DailyLogFile = Join-Path $script:LogDirectory "$ymd.txt"

if ($fileArray.Count -gt 0) {
    $mp3Files = @(
        foreach ($file in $fileArray) {
            $path = if ([System.IO.Path]::IsPathRooted($file)) {
                $file
            }
            else {
                Join-Path $InputDir $file
            }

            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "MP3 file not found: $path"
            }
            Get-Item -LiteralPath $path
        }
    )
}
else {
   $mp3Files = @(Get-Mp3Files -Directory $InputDir -NewestOnly $Latest)
}

if ($mp3Files.Count -eq 0) {
    throw "No MP3 files found in: $InputDir"
}

foreach ($file in $mp3Files) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)

    Write-Log "Inspecting: $($file.FullName)"
    if ($file.Name -notmatch "_source.mp3"){ 
        Copy-Item ($file.FullName) -Destination "$dd\_source.mp3" -force # download for spectrum process
    }
    # https://ffmpeg.org/ffprobe.html#Main-options

    # aspectralstats    https://stackoverflow.com/questions/74329155/how-get-centroid-value-of-an-audio-file-using-ffmpeg-aspectralstats

  # atilt          https://ffmpeg.org/ffprobe-all.html#atilt
  #  -af atilt=freq=230:width=100:slope=-1
  # https://www.mathworks.com/help/audio/ref/spectralrolloffpoint.html

    $probeArgs = @(
        '-v', 'error', 
        '-show_entries', 'format=duration', 
        '-output_format', 'default=noprint_wrappers=1:nokey=1', 
        $file.FullName
        )
    $prevErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        write-host "#=#=#=#== probe ==#== $baseName ===== ===== =#=" -ForegroundColor blue
        [int]$probeResult = & ffprobe @probeArgs 2>$null
    }
    finally {
        $ErrorActionPreference = $prevErrorPreference
    }
  #  if (-not $probeResult -or ($probeResult).Length -eq 0) {
    if (-not $probeResult ) {
        Write-Log "Skipping unreadable or invalid file: $($file.FullName)"
        continue
    }

    write-host "$probeResult seconds  $($probeResult/60) minutes - Mode $mode" 

    # rms step will create rms.csv file of data to pass to the trim step
    $outLogDir = Join-Path $OutputDir 'logs'
    $rmsScript = Join-Path $scriptRoot 'process_rms_level1.ps1'
    $silenceScript = Join-Path $scriptRoot 'process_silence4.ps1'
    $inpScript = Join-Path $scriptRoot 'process_interpolate.ps1'
    # trim step will delete the sections identified and output a new completed mp3 file
    $deleteFile = Join-Path $InputDir "$baseName.RMS.csv"
    $trimScript = Join-Path $scriptRoot 'process_trim3.ps1'
    $silencetrim = Join-Path $scriptRoot 'process_siltrim.ps1'
    $spectrum01 = Join-Path $scriptRoot 'process_spectrum1.ps1'
    

    $allParams = @{
        inputDir  = $InputDir
        inputPath  = $InputPath
        logPath   = $outLogDir
        InputFile = $file.Name
        OutputCsv = "$baseName.csv"
        OutputLog = "$baseName.log"
        DeleteFile = $deleteFile
        OutputPath= $OutputDir
        OutputFile = "$baseName.mp3"
        SilenceFile = '_sil.csv'
        RmsFile = '_RMS.csv'
        mode=$mode
        debug=$debug
    }
    
    if ($debug){ # FULL RMS ANALYSIS and PROCESSING Trim #
        # 1 RMS
        & $rmsScript @allParams

        # 2 process silence 
        & $silenceScript @allParams    
        
        # 3  interpolate 
        & $inpScript @allParams

        # 4  spectrum alternate processing option
        & $spectrum01 @allParams

        # 5 trim and delete AND re-EXPORT result.
        $trimOutput = Join-Path $OutputDir "$baseName.mp3"
        & $trimScript -dd $InputDir -logPath $outLogDir -InputFile $file.FullName -DeleteFile $deleteFile -OutputFile $trimOutput

    }
    else { # SILENCE PROCESSING ONLY #

        # Generate the RMS data used for the side-by-side histogram in siltrim.
        & $rmsScript @allParams

        # 2 process silence 
        & $silenceScript @allParams
        
        # 5 trim and delete AND re-EXPORT result.
        & $silencetrim @allParams

        # & $spectrum01 @allParams
    }
}

Write-Log "Finished processing $($mp3Files.Count) MP3 file(s)."
Write-Log "Cleaned output directory: $OutputDir"
