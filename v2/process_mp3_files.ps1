<# process main                                                          v2.0.0
-------------------------------------------------------------------------------------
    get RMS data points, analyse, mark delete sections,
    interpolate to ensure delete marks are continuous
    trim and delete THEN export final result.
#>
param(
    [string]$InputDir = 'F:\av\audio\downloads',
    [string]$OutputDir = 'F:\av\audio\done',
    [string]$dd = 'F:\av\audio\downloads',
    [string[]]$fileArray = @(),

    [switch]$Latest 
)
$scriptRoot = $PSScriptRoot
Set-Location -LiteralPath $scriptRoot

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dts = (Get-Date).ToString('yyyyMMdd.HHmmss')
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

function Get-Mp3Files {
    param(
        [string]$Directory,
        [switch]$NewestOnly
    )

    $files = @(Get-ChildItem -Path $Directory -File -Filter '*.mp3' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)

    if ($NewestOnly) {
        if ($files.Count -eq 0) { return @() }
        return @($files | Select-Object -Last 1)
    }

    return @($files)
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
    # $mp3Files = @(Get-Mp3Files -Directory $InputDir -NewestOnly:$Latest)
   $mp3Files = @(Get-Mp3Files -Directory $InputDir -NewestOnly $Latest)
}

if ($mp3Files.Count -eq 0) {
    throw "No MP3 files found in: $InputDir"
}

foreach ($file in $mp3Files) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
   # $outputFile = Join-Path $OutputDir ("{0}_cleaned.mp3" -f $baseName)
    $silenceLog = Join-Path $logDir ("{0}_silence.log" -f $baseName)
    #$auditLog = Join-Path $logDir ("{0}.log" -f $baseName)

    Write-Log "Inspecting: $($file.FullName)"
    Copy-Item ($file.FullName) -Destination "$dd\source.mp3" -force # download for spectrum process

    $probeArgs = @('-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', $file.FullName)
    $prevErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        write-host "#=#=#=#== probe ==#== $baseName ===== ===== =#=" -ForegroundColor blue
        $probeResult = & ffprobe @probeArgs 2>$null
    }
    finally {
        $ErrorActionPreference = $prevErrorPreference
    }
    if (-not $probeResult -or ($probeResult).Length -eq 0) {
        Write-Log "Skipping unreadable or invalid file: $($file.FullName)"
        continue
    }

    write-host "$probeResult seconds  $($probeResult/60) minutes" 

    # rms step will create rms.csv file of data to pass to the trim step
    $outLogDir = Join-Path $OutputDir 'logs'
    $rmsScript = Join-Path $scriptRoot 'process_rms_level1.ps1'
    $silenceScript = Join-Path $scriptRoot 'process_silence4.ps1'
    $inpScript = Join-Path $scriptRoot 'process_interpolate.ps1'
    # trim step will delete the sections identified and output a new completed mp3 file
    $deleteFile = Join-Path $InputDir "$baseName.RMS.csv"
    $trimScript = Join-Path $scriptRoot 'process_trim3.ps1'
    $spectrum01 = Join-Path $scriptRoot 'process_spectrum1.ps1'
    

    $allParams = @{
        inputDir  = $InputDir
        logPath   = $outLogDir
        InputFile = $file.FullName
        OutputCsv = "$baseName.csv"
        OutputLog = "$baseName.sil.log"
        DeleteFile = $deleteFile

        #-inputDir $InputDir -logPath $silenceLog -InputFile $file.FullName -OutputLog "$baseName.sil.log" -OutputCsv "$baseName.sil.csv"


    }
    
    # 1 RMS
    & $rmsScript @allParams
    # & $rmsScript -inputDir $InputDir -logPath $outLogDir -InputFile $file.FullName -OutputCsv "$baseName.csv"

   
    # 2 process silence 
    # & $silenceScript @allParams
    & $silenceScript -inputDir $InputDir -logPath $silenceLog -InputFile $file.FullName -OutputLog "$baseName.sil.log" -OutputCsv "$baseName.sil.csv"
    
    
    # 3  interpolate 
    & $inpScript -inputdir $InputDir -logPath $outLogDir -InputFile $file.FullName -DeleteFile $deleteFile -OutputFile $deleteFile


    # 4  spectrum alternate processing option
    & $spectrum01 -inputpath $inputDir -logPath "$outputDir\Logs" -InputFile $file.FullName -rmsFile "rms.csv" -SilenceFile "sil.csv" -OutputPath $OutputDir -OutputFile "new.mp3" -dd $dd


    # 5 trim and delete AND re-EXPORT result.
    $trimOutput = Join-Path $OutputDir "$baseName.mp3"
    & $trimScript -dd $InputDir -logPath $outLogDir -InputFile $file.FullName -DeleteFile $deleteFile -OutputFile $trimOutput

}

Write-Log "Finished processing $($mp3Files.Count) MP3 file(s)."
Write-Log "Cleaned output directory: $OutputDir"
