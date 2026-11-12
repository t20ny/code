<# equalize only                              v1.0.1
-------------------------------------------------------------------------------------
pre: mp3 input file 
Post: output mp3 file equalized with high pitch voices suppressed
#>

param (
    [string]$inputPath = "F:\av\audio\done",
    [string]$InputFile = "_source.mp3",
    [string]$dd = 'F:\av\audio\downloads',
    [string]$logPath = 'F:\av\audio\done\logs',
    [string]$RmsFile = '_RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$EqualzenceFile = '_Equalz.csv',
    [string]$OutputPath = 'F:\av\audio\done',
    [string]$OutputFile = '_new.mp3',
    [string]$DeleteFile = '_Equalz.csv', # analysed Equalzence result that show the sections to be deleted
    $debug = 0
)
write-host $PSCommandPath -BackgroundColor cyan
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$debug = 0
$scriptRoot = $PSScriptRoot
Set-Location -LiteralPath $scriptRoot


function Write-DebugLog {
    param($fun, $val)

    if ($debug) {
        if ($fun -match "ipol") {
            Write-Host "Debug $fun $val" -ForegroundColor DarkCyan
        }
        elseif ($fun -eq "delt") {
            Write-Host "Debug $fun $val" -ForegroundColor Yellow
        }
        else {
            Write-Host "Debug $fun $val" -ForegroundColor White
        }
    }
}

function Resolve-RelativePath {
    param(
        [string]$PathValue,
        [string]$BasePath,
        [string]$DefaultName = $null
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        if (-not [string]::IsNullOrWhiteSpace($DefaultName)) {
            return (Join-Path $BasePath $DefaultName)
        }
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return (Join-Path $BasePath $PathValue)
}


function New-AudioFilter {
    param(
      #  [Parameter(Mandatory = $true)][string]$BaseFilter
    )

    $audioFilter = @(
      #  $BaseFilter,
         'equalizer=f=130:width_type=h:width=100:g=1',
        'equalizer=f=230:width_type=h:width=100:g=-2',
        'equalizer=f=480:width_type=h:width=400:g=-3',
        'equalizer=f=980:width_type=h:width=600:g=-6',
        'equalizer=f=1780:width_type=h:width=1000:g=-12',
        'equalizer=f=2780:width_type=h:width=1000:g=-15',
        'equalizer=f=6400:width_type=h:width=6400:g=-21',
        'equalizer=f=15000:width_type=h:width=10800:g=-27',
        "speechnorm=e=12.5:r=0.0001:l=1"
    ) -join ','

    return $audioFilter
}

function trimBlocks {
    param($FILTER)

    $ffmpegCmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    $ffmpegPath = if ($ffmpegCmd) { $ffmpegCmd.Source } else { $null }
    if (-not $ffmpegPath) {
        throw "ffmpeg was not found on PATH. Install ffmpeg and retry."
    }

    $inputExists = Test-Path -LiteralPath $inFile -PathType Leaf
    $outputDirectory = Split-Path -Parent $outputPath
    if (-not $inputExists) {
        throw "Input file was not found: $inFile"
    }
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    Write-Host "in  mp3 =  $inFile"
    Write-Host "out mp3 =  $outputPath"

    $audioFilter = New-AudioFilter -BaseFilter $FILTER
    Write-DebugLog "f1" $audioFilter

    $args = @(
        '-y',
        '-hide_banner',
        '-nostdin',
        '-i', $inFile,
        '-af', $audioFilter,
        '-c:a', 'libmp3lame',
        '-q:a', '4',
        $outputPath
    )

    $previousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $ffmpegPath @args #2> "$logName" | Out-Null
    }
    finally {
        $ErrorActionPreference = $previousErrorPreference
    }

    if ($LASTEXITCODE -ne 0) {
        if ($LASTEXITCODE -eq -22) {
            throw "ffmpeg exited with code $LASTEXITCODE. This may be due to an unsupported file format or codec."
        }
        throw "ffmpeg exited with code $LASTEXITCODE"
    }
}

function Invoke-EqualzWorkflow {                           # MAIN WORKER
    Set-Location -LiteralPath $OutputPath

    $script:logName = Join-Path $logPath '_delete.log'
    $script:inFile = Resolve-RelativePath -PathValue $InputFile -BasePath $dd
    $script:outputPath = Resolve-RelativePath -PathValue $OutputFile -BasePath $OutputPath
 
    if (-not (Test-Path -LiteralPath $script:inFile -PathType Leaf)) {
        throw "Input file not found: $script:inFile"
    }


    $outputDirectory = Split-Path -Parent $script:outputPath
    if ($outputDirectory) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    if ([string]::Equals(
            [System.IO.Path]::GetFullPath($script:inFile),
            [System.IO.Path]::GetFullPath($script:outputPath),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Input and output paths must be different: $script:inFile"
    }

    Write-Host "========= equalizer   =============================================" -ForegroundColor Blue

    try {
        $filter = New-AudioFilter
        trimBlocks -FILTER $filter
        Write-Host "Equalized  $script:logName"
    }
    catch {
        throw "Equalz trim workflow failed: $($_.Exception.Message)"
    }
}

Invoke-EqualzWorkflow