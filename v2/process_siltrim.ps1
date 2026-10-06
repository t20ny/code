<# trim and delete                                              v2.0.0
-------------------------------------------------------------------------------------
aselect will select audio sections we want to keep. Aim to keep speech.
    delete the sections where there is NO silence marks like music.
    loud background sections in commercials are to be deleted.
#>

param (
    [string]$inputPath = "F:\av\audio\done",    
    [string]$InputFile = "source.mp3",
    [string]$dd = 'F:\av\audio\downloads',
    [string]$logPath = 'F:\av\audio\done\logs',
    [string]$RmsFile = 'RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$SilenceFile = 'sil.csv',
    [string]$OutputPath = 'F:\av\audio\done',    
    [string]$OutputFile = 'new.mp3',
    [string]$DeleteFile = 'sil.csv' # analysed silence result that show the sections to be deleted
)

    Set-Location -LiteralPath $OutputPath
    $logname = Join-Path $logPath 'delete.log'
    $ErrorActionPreference = 'Continue'
    $startFrame = 0
    $deleteRanges = [System.Collections.Generic.List[string]]::new()
    $pDStatus = $false
    
    $minDeleteSection = 10.0 # mininum section length to be deleted
    $maxInterpolate = 10 # maximum seconds allowed for this interpolate
     

    $inFile = if ([System.IO.Path]::IsPathRooted($InputFile)) {
        $InputFile
    }
    else {
        Join-Path $dd $InputFile
    }

    if (-not (Test-Path -LiteralPath $inFile -PathType Leaf)) {
        throw "Input file not found: $inFile"
    }
    $delFile="$logPath\$DeleteFile"
    if (-not (Test-Path -LiteralPath $DelFile -PathType Leaf)) {
        throw "Delete CSV not found: $DelFile"
    }
    
    Write-Host "========= sil trim and delete   =============================================" -ForegroundColor Blue
    write-host "reading =  $DelFile"

    
    try {
        $thisTime=1.0
        $prevTime=1.0
        $startSpeech=30.0 # first seconds of file are to be deleted. Speech starts after first 30 seconds have elapsed.
        $toBeDeleted =1
        # import the csv data file with first row headers
        $data = Import-Csv -LiteralPath $DelFile -Delimiter ","
        
        # iterate each row and find the sections to be deleted
        foreach ($line in $data) {
            $thisTime=$line.pts_time     # pts_time","start

            # first 30 seconds of file needs to be deleted
            if ($thisTime -gt $startSpeech){
                $toBeDeleted = [double]$line.pts_time # frame is to be deleted
            }

            # measure the lengeth of delete sectionss



            # interpolate small gaps in consecutive delete section
            if (($toBeDeleted) -and -not($DelStatus)) {
                $startFrame = [double]$line.end
            }

            if (-not($toBeDeleted) -and ($DelStatus)) {
                $DelStatus=1
                $endFrame = [double]$line.start
                $deleteRanges.Add("between(n,$startFrame,$endFrame)")
            }
            $prevTime = $thisTime
        }

        if ($DelStatus) {
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
    $EQUALIZ="equalizer=f=6000:width_type=h:width=2000:g=-6"
    $FILTER="$FILTER,$EQUALIZ"
    $EQUALIZ="equalizer=f=8000:width_type=h:width=2000:g=-6"
    $FILTER="$FILTER,$EQUALIZ"
    $EQUALIZ="equalizer=f=10000:width_type=h:width=2000:g=-10"
    $FILTER="$FILTER,$EQUALIZ"
    $EQUALIZ="equalizer=f=15000:width_type=h:width=3000:g=-15"
    $FILTER="$FILTER,$EQUALIZ"

    #$NROMALISE="compand=.3|.3:1|1:-90/-60|-60/-40|-40/-30|-20/-20:6:0:-90:0.2"
    #$FILTER="$FILTER,$NROMALISE"

   # afreqshift

    $args7 = @(
        '-y',
        '-hide_banner',
        '-i', $inFile,
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


