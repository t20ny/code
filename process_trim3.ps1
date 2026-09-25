<# trim3
-------------------------------------------------------------------------------------
aselect will select audio sections we want to keep
    delete the sections as per the delete file
#>

[CmdletBinding()]
param (
    [string]$dd = 'F:\av\audio\downloads',
    [string]$logPath = '\logs',
    [string]$InputFile = 'USDIESEL.mp3',
    [string]$DeleteFile = 'USDIESEL.RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputFile = 'USDIESEL2.mp3'
)
   
    Set-Location -LiteralPath $dd
    $logname = Join-Path $logPath 'deleted.log'
    $ErrorActionPreference = 'Continue'
    $startFrame = 0
    $deleteRanges = [System.Collections.Generic.List[string]]::new()
    $pDStatus = $false

    $inputPath = if ([System.IO.Path]::IsPathRooted($InputFile)) {
        $InputFile
    }
    else {
        Join-Path $dd $InputFile
    }

    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Input file not found: $inputPath"
    }
    if (-not (Test-Path -LiteralPath $DeleteFile -PathType Leaf)) {
        throw "Delete CSV not found: $DeleteFile"
    }
    
    
    try {
        # import the csv data file with first row headers
        $data = Import-Csv -LiteralPath $DeleteFile -Delimiter ","

        # iterate each row and find the start frame of sections to be deleted
        foreach ($line in $data) {
            $thisFrame=$line.Frame

            if ($line.PSObject.Properties.Name -contains 'delete') {
               
               # $toBeDeleted = [bool]$line.delete
                $toBeDeleted = [int]$line.delete # frame is to be deleted
            }   # elseif ($line.PSObject.Properties.Name -contains 'com') {   $toBeDeleted = ([int]$line.com -eq 1)}
            else {
                $toBeDeleted = $false
            }
           
           # write-host "$thisFrame $tobeDeleted"
            if (($toBeDeleted) -and -not($pDStatus)) {
                $startFrame = [int]$line.Frame
            }

            if (-not($toBeDeleted) -and ($pDStatus)) {
                $endFrame = [int]$line.Frame
                $deleteRanges.Add("between(n,$startFrame,$endFrame)")
            }
            $pDStatus = $toBeDeleted
        }

        if ($pDStatus) {
            $deleteRanges.Add("gte(n,$startFrame)")
        }
   
    # audio filter to output new audio file by selecting only the sections with speech
    $deleteExpression = if ($deleteRanges.Count -gt 0) {
        $deleteRanges -join '+'
    } else {
        '0'
    }
    $FILTER = "aselect='not($deleteExpression)'"

    $outputPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) {
        $OutputFile
    }
    else {
        Join-Path $dd $OutputFile
    }
    $outputDirectory = Split-Path -Parent $outputPath
    if ($outputDirectory) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    $args7 = @(
        '-y',
        '-hide_banner',
        '-i', $inputPath,
        '-af', $FILTER,
        '-c:a', 'libmp3lame',
        '-q:a', '4',
        $outputPath
    )

    $prevErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

        & ffmpeg @args7   2> "$logName" | Out-Null
    }
    finally {
        $ErrorActionPreference = $prevErrorPreference
    }

    if ($LASTEXITCODE -ne 0) {
        if ($LASTEXITCODE -eq -22) {
            throw "ffmpeg exited with code $LASTEXITCODE. This may be due to an unsupported file format or codec."
        }
        throw "ffmpeg exited with code $LASTEXITCODE"
    }

    Write-Host "Trim and delete log: $logName"


