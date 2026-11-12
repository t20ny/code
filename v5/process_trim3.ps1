<# trim and delete                                              v2.0.1
-------------------------------------------------------------------------------------
aselect will select audio sections we want to keep
    delete the sections as per the delete file
#>

param (
    [string]$dd = 'F:\av\audio\downloads',
    [string]$logPath = 'F:\av\audio\done\logs',
    [string]$InputFile = '_SOURCE.mp3',
    [string]$DeleteFile = '_RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputFile = '_New.mp3'
)

write-host $PSCommandPath -BackgroundColor cyan
    Set-Location -LiteralPath $dd
    $logname = Join-Path $logPath '_delete.log'
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
    
    Write-Host "========= trim and delete   =============================================" -ForegroundColor Blue
    write-host "reading =  $DeleteFile"

    
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

    $Filter = @(
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

   # afreqshift

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

    Write-Host "Trim  and  $logName"


