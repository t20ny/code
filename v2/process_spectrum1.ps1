<# spectrum re-combine the RMS and Silence data for analysis                    v0.0.1
-------------------------------------------------------------------------------------
analyse the source data to and mark earh row with decision status to
aim is delete the sections with loud rms and suppress high pitch music
#>

param (
    [string]$InputPath = 'F:\av\audio\done',    
    [string]$dd = 'F:\av\audio\downloads',
    [string]$InputFile = 'source.mp3',
    [string]$logPath = 'F:\av\audio\done\logs',
    [string]$SilenceFile = 'sil.csv',
    [string]$RmsFile = 'RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputPath = 'F:\av\audio\done',    
    [string]$OutputFile = 'new.mp3'
)

    Set-Location -LiteralPath $dd
    $logname = Join-Path $logPath 'spectrum.log'
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
    if (-not (Test-Path -LiteralPath "$LogPath\$RmsFile" -PathType Leaf)) {
        throw "RMS CSV not found: $LogPath\$RmsFile"
    }
    
   
    
    try {
         Write-Host "========= load rms      =============================================" -ForegroundColor Blue
        write-host "reading =  $RmsFile"
        # import the csv data file with first row headers
        $data1 = @(Import-Csv -Path "$LogPath\$RmsFile" -Delimiter ",")

        Write-Host "========= load silence   =============================================" -ForegroundColor Blue
        write-host "reading =  $silenceFile"
        # import the csv data file with first row headers
        $data2 = @(Import-Csv -Path "$LogPath\$SilenceFile" -Delimiter ",")

        # Join by frame while keeping fields from both CSVs.
        if ($data1.Count -eq 0) {
            throw "No RMS rows found in: $LogPath\$RmsFile"
        }
        $rmsColumns = @($data1[0].PSObject.Properties.Name)
        $silenceColumnMap = @{}
        foreach ($column in $data2[0].PSObject.Properties.Name) {
            if ($column -in @('Frame', 'pts', 'pts_time') -or $column -notin $rmsColumns) {
                $silenceColumnMap[$column] = $column
            }
            else {
                $silenceColumnMap[$column] = "sil_$column"
            }
        }

        $silenceByFrame = @{}
        foreach ($row in $data2) {
            $silenceByFrame[[string]$row.Frame] = $row
        }

        $outputColumns = [System.Collections.Generic.List[string]]::new()
        foreach ($column in $rmsColumns) {
            $outputColumns.Add($column)
        }
        foreach ($column in $silenceColumnMap.Values) {
            if ($column -notin $outputColumns) {
                $outputColumns.Add($column)
            }
        }

        $mergedRows = [System.Collections.Generic.List[object]]::new()
        $matchedFrames = @{}
        foreach ($rmsRow in $data1) {
            $frameKey = [string]$rmsRow.Frame
            $mergedValues = [ordered]@{}
            foreach ($column in $outputColumns) {
                $mergedValues[$column] = $null
            }
            foreach ($property in $rmsRow.PSObject.Properties) {
                $mergedValues[$property.Name] = $property.Value
            }
            if ($silenceByFrame.ContainsKey($frameKey)) {
                foreach ($property in $silenceByFrame[$frameKey].PSObject.Properties) {
                    $mergedValues[$silenceColumnMap[$property.Name]] = $property.Value
                }
                $matchedFrames[$frameKey] = $true
            }
            $mergedRows.Add([pscustomobject]$mergedValues)
        }

        foreach ($silenceRow in $data2) {
            $frameKey = [string]$silenceRow.Frame
            if ($matchedFrames.ContainsKey($frameKey)) {
                continue
            }
            $mergedValues = [ordered]@{}
            foreach ($column in $outputColumns) {
                $mergedValues[$column] = $null
            }
            foreach ($property in $silenceRow.PSObject.Properties) {
                $mergedValues[$silenceColumnMap[$property.Name]] = $property.Value
            }
            $mergedRows.Add([pscustomobject]$mergedValues)
        }

        $data = $mergedRows | Sort-Object { [long]$_.Frame }
        $data | Export-Csv -Path "$LogPath\Spectrum.csv"
    
        # iterate each row and find the start frame of sections to be deleted
        foreach ($line in $data) {
            $thisFrame=$line.Frame

            if ($line.PSObject.Properties.Name -contains 'delete') {
                $toBeDeleted = [int]$line.delete # frame is to be deleted if value =1
            }  
            else {
                $toBeDeleted = 0
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
            #Join-Path $dd $OutputFile
            Join-Path $OutputPath $OutputFile
        }
        $outputDirectory = Split-Path -Parent $outputPath
        if ($outputDirectory) {
            $null = New-Item -ItemType Directory -Path $outputDirectory -Force
        }
        $EQUALIZ="equalizer=f=6000:width_type=h:width=2000:g=-6"
        $FILTER="$FILTER,$EQUALIZ"
        $EQUALIZ="equalizer=f=8000:width_type=h:width=2000:g=-26"
        $FILTER="$FILTER,$EQUALIZ"
        $EQUALIZ="equalizer=f=10000:width_type=h:width=2000:g=-80"
        $FILTER="$FILTER,$EQUALIZ"
        $EQUALIZ="equalizer=f=15000:width_type=h:width=3000:g=-80"
        $FILTER="$FILTER,$EQUALIZ"


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
        Write-Host "========= spectrum trim   =============================================" -ForegroundColor Blue
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

    <# Count contiguous runs of marked frames and summarize their lengths by seconds.
    $orderedData = @($data | Sort-Object { [long]$_.Frame })
    $frameDurationTotal = 0.0
    $frameDurationCount = 0
    for ($index = 1; $index -lt $orderedData.Count; $index++) {
        $previousRow = $orderedData[$index - 1]
        $currentRow = $orderedData[$index]
        if ([long]$currentRow.Frame -eq ([long]$previousRow.Frame + 1)) {
            $duration = [double]$currentRow.pts_time - [double]$previousRow.pts_time
            if ($duration -gt 0) {
                $frameDurationTotal += $duration
                $frameDurationCount++
            }
        }
    }
    $frameDurationSeconds = if ($frameDurationCount -gt 0) {
        $frameDurationTotal / $frameDurationCount
    } else {
        1 / 38
    }

    $pulseRecords = [System.Collections.Generic.List[object]]::new()
    $pulseLength = 0
    $pulseMinute = $null
    $previousFrame = $null

    foreach ($row in $orderedData) {
        $frame = [long]$row.Frame
        $isPulse = [int]$row.delet2 -eq 1

        if ($pulseLength -gt 0 -and (-not $isPulse -or $frame -ne ($previousFrame + 1))) {
            $pulseRecords.Add([pscustomobject]@{
                minute = $pulseMinute
                lengthSeconds = $pulseLength * $frameDurationSeconds
            })
            $pulseLength = 0
        }

        if ($isPulse) {
            if ($pulseLength -eq 0) {
                $pulseMinute = [int]$row.minute
            }
            $pulseLength++
        }
        $previousFrame = $frame
    }

    if ($pulseLength -gt 0) {
        $pulseRecords.Add([pscustomobject]@{
            minute = $pulseMinute
            lengthSeconds = $pulseLength * $frameDurationSeconds
        })
    }

    $minutePulseSummary = @(
        $pulseRecords |
            Group-Object -Property minute |
            Sort-Object { [int]$_.Name } |
            ForEach-Object {
                [pscustomobject]@{
                    minute = [int]$_.Name
                    pulseCount = $_.Count
                    averageLengthSeconds = [math]::Round((($_.Group | Measure-Object -Property lengthSeconds -Average).Average), 3)
                }
            }
    )

    $minutePulseSummary | Format-Table -AutoSize | Out-Host
    $overallAverageLength = if ($pulseRecords.Count -gt 0) {
        [math]::Round((($pulseRecords | Measure-Object -Property lengthSeconds -Average).Average), 3)
    } else {
        0
    }
    Write-Host "Total pulses: $($pulseRecords.Count); overall average length: $overallAverageLength seconds"
    #>
    Write-Host "Spec Log   $logName"


