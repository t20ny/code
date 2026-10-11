<# trim and delete with silence                                              v2.0.1
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
    [string]$DeleteFile = 'sil.csv', # analysed silence result that show the sections to be deleted
    [switch]$Debug
)

    Set-Location -LiteralPath $OutputPath
    $logname = Join-Path $logPath 'delete.log'
    $ErrorActionPreference = 'Continue'
    $startblock = 0
    $deleteRanges = [System.Collections.Generic.List[string]]::new()
    $pDStatus = $false
    
    $minDeleteSection = 10.0 # mininum section length to be deleted
    $maxInterpolate = 10 # maximum seconds allowed for this interpolate
    $framesPerSecond = 38
    $minGap = 5.0
    $minDelete = 5.0
    $preDeleteRun = 5.0
    $minDeleteRun = $framesPerSecond * 8
    $startSpeech=31.0 # first seconds of file are to be deleted. Speech starts after first 30 seconds have elapsed.
    $endDelete = 0.0 # leave the remaining file intact; no trailing delete window
    $tightenDelete = 5.0
    $maxPulseCount = 6
    $widePulseCount = 0
    $tinyPulseCount = 0
     

    $inFile = if ([System.IO.Path]::IsPathRooted($InputFile )) {
        $InputFile   
    }
    else {
        Join-Path $dd $InputFile 
    }

    if (-not (Test-Path -LiteralPath $inFile -PathType Leaf)) {
        throw "Input file not found: $inFile"
    }
    $fname="$logPath\$DeleteFile"
    $fname="$logPath\$SilenceFile"
    if (-not (Test-Path -LiteralPath $fname -PathType Leaf)) {
        write-host "Delete CSV not found: $fname"
        # throw
    }
    
    $outputPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) {
        $OutputFile
    }
    else {
        if ($debug) {Join-Path $dd $OutputFile
        write-host "DEBUG out is $dd "}
        else {Join-Path $outputPath $OutputFile}
    }
    $outputDirectory = Split-Path -Parent $outputPath
    if ($outputDirectory) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    Write-Host "========= sil trim and delete   =============================================" -ForegroundColor Blue
    

 function getSilFile {
    param([string]$fName)

    Write-Host "reading =  $fName"

    try {
        return @(Import-Csv -LiteralPath $fName -Delimiter ",")
    }
    catch {
        Write-Host $error[0]
        return @()
    }
}


function Ensure-RowProperty {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Row,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName,
        [object]$Value
    )

    if ($null -eq $Row) { return $null }

    $propertyNames = @($Row.PSObject.Properties.Name)
    $existingProperty = $propertyNames | Where-Object { $_ -ieq $PropertyName } | Select-Object -First 1

    if ($existingProperty) {
        $Row.$existingProperty = $Value
        return $Row
    }

    $null = $Row | Add-Member -NotePropertyName $PropertyName -NotePropertyValue $Value -Force
    return $Row
}

function Get-RowPropertyValue {
    param(
        [psobject]$Row,
        [string]$PropertyName,
        [object]$Default = $null
    )

    if ($null -eq $Row) { return $Default }

    $propertyNames = @($Row.PSObject.Properties.Name)
    $existingProperty = $propertyNames | Where-Object { $_ -ieq $PropertyName } | Select-Object -First 1

    if (-not $existingProperty) { return $Default }

    $value = $Row.$existingProperty
    if ($null -eq $value) { return $Default }
    return $value
}

function Set-DeleteState {
    param($data)

    foreach ($row in @($data)) {
        if ($null -eq $row) { continue }

        $deleteValue = [int](Get-RowPropertyValue -Row $row -PropertyName 'delete' -Default 0)

        $row = Ensure-RowProperty -Row $row -PropertyName 'delete' -Value $deleteValue
        $row = Ensure-RowProperty -Row $row -PropertyName 'cat' -Value 'unset'

        $row.delete = $deleteValue
        $row.cat = [string](Get-RowPropertyValue -Row $row -PropertyName 'cat' -Default 'unset')
    }

    return @($data)
}

function Ensure-RowState {
    param($row)

    if ($null -eq $row) { return $null }

    $row = Ensure-RowProperty -Row $row -PropertyName 'delete' -Value 0
    $row = Ensure-RowProperty -Row $row -PropertyName 'cat' -Value 'unset'

    if ($null -eq $row.delete) { $row.delete = 0 }
    if ($null -eq $row.cat) { $row.cat = 'unset' }

    return $row
}

function interpolate{
        param($data)
    $thisTime=1.0
    $prevTime=1.0
    $toBeDeleted =1
    $data = Set-DeleteState $data
    $lastFrame = @($data).Count
    if ($lastFrame -eq 0) {
        return @()
    }
    # step 1
    # read the values in the data file as a PSobject table
    foreach ($row in $data) {
        if ($null -eq $row) { continue }

        # step 1        
        # read the delete column values 
        $deleteValue = [int](Get-RowPropertyValue -Row $row -PropertyName 'delete' -Default 0)

        $row = Ensure-RowProperty -Row $row -PropertyName 'delete' -Value $deleteValue
        $row.delete = [int]$deleteValue

        if ($debug){ write-host $row.Frame $row.start  $row.cat	 $row.Delete }

    }

    $adjacentCategoryDeleteIndexes = [System.Collections.Generic.List[int]]::new()
    for ($index = 0; $index -lt ($lastFrame - 1); $index++) {
        $currentRow = $data[$index]
        $nextRow = $data[$index + 1]
        #if ([string]$currentRow.cat -eq 'constant25' -and [int]$currentRow.delete -eq 1 -and [string]$nextRow.cat -eq 'constant15') {
        if ([string]$currentRow.cat -eq 'constant25' -and [int]$currentRow.delete -eq 1 -and [string]$nextRow.cat -match 'constant') {
            $adjacentCategoryDeleteIndexes.Add($index)
            $adjacentCategoryDeleteIndexes.Add($index + 1)
        }
    }
    
    # step 2
    # Mark sections that start before the initial time mark with 1-value
    $strtSectionLength = 0
    while ($strtSectionLength -lt $lastFrame -and [double]$data[$strtSectionLength].start -lt $startSpeech) {
        $strtSectionLength++
    }
    for ($index = 0; $index -lt $strtSectionLength; $index++) {
        $row = Ensure-RowState $data[$index]
        $row.delete = 1
     #   $row.delet2 = 1
        $row.cat = "ip1start"
        $data[$index] = $row
       if ($debug){ write-host "20  $($index)"}
    }

   
    # step 3
    # clear short noise bursts before filling short gaps between real delete runs
    # only after the start section has been marked
    for ($index = $strtSectionLength; $index -lt $lastFrame;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }
        if ($debug){ write-host "30  $($index)"}
        $runStart = $index
        while ($index -lt $lastFrame -and [int]$data[$index].delete -eq 1) {
            $index++
        }
        if ($debug){ write-host "31  $($index)"
            write-host $data[$index].Frame	$data[$index].start  $data[$index].end  $data[$index].cat	          $data[$index].Delete	
        }
        
        if ($debug){ write-host $row.Frame $row.start  $row.cat	 $row.Delete }

        $runDuration = [double]$data[$index - 1].end - [double]$data[$runStart].start
        if ($runDuration -lt $tightenDelete) {
            for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                $row = Ensure-RowState $data[$runIndex]
                $row.delete = 0
             #   $row.delet2 = 0
                $row.cat = "ip3noise"
                $data[$runIndex] = $row
            }
        }
    }

    if ($debug){ write-host "40  $($index)"}
    # step 4
    # Fill short speech gaps only when they are bounded by retained delete runs.
    for ($index = $strtSectionLength; $index -lt $lastFrame;) {
        if ([int]$data[$index].delete -eq 1) {
            $index++
            continue
        }
        if ($debug){ write-host "41  $($index)"}
        $gapStart = $index
        while ($index -lt $lastFrame -and [int]$data[$index].delete -eq 0) {
            $index++
        }
        if ($debug){ write-host "42  $($index)"}
        $hasDeleteBefore = $gapStart -gt 0 -and [int]$data[$gapStart - 1].delete -eq 1
        $hasDeleteAfter = $index -lt $lastFrame -and [int]$data[$index].delete -eq 1
        $gapDuration = [double]::PositiveInfinity
        if ($hasDeleteBefore -and $hasDeleteAfter) {
            $gapDuration = [Math]::Max(0.0, [double]$data[$index].start - [double]$data[$gapStart - 1].end)
        }
        if ($hasDeleteBefore -and $hasDeleteAfter -and $gapDuration -lt $minGap) {
            for ($gapIndex = $gapStart; $gapIndex -lt $index; $gapIndex++) {
                $row = Ensure-RowState $data[$gapIndex]
                $row.delete = 1
             #   $row.delet2 = 1
                $row.cat = "ip4gap"
                $data[$gapIndex] = $row
            }
        }
    }

    if ($debug){ write-host "50  $($index)"}
    # step 5
    # Remove short delete runs after the speech-gap fill.
    for ($index = $strtSectionLength; $index -lt $lastFrame;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $lastFrame -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        $runDuration = [double]$data[$index - 1].end - [double]$data[$runStart].start
        if (($runDuration -lt $minDelete) -and ([double]$data[$runStart].start -ge $startSpeech)) {
            for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                $row = Ensure-RowState $data[$runIndex]
                $row.delete = 0
             #   $row.delet2 = 0
                $row.cat = "ip5collapse"
                $data[$runIndex] = $row
            }
        }
    }

    if ($debug){ write-host "60  $($index)"}
    # step 6
    # pad before valid delete sections so they remain coherent blocks
    $prepadEnd = $strtSectionLength
    for ($index = $strtSectionLength; $index -lt $lastFrame;) {
        if ([int]$data[$index].delete -ne 1) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $lastFrame -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        $padBeforeTime = [double]$data[$runStart].start - $preDeleteRun
        for ($padIndex = $runStart - 1; $padIndex -ge 0 -and [double]$data[$padIndex].end -gt $padBeforeTime; $padIndex--) {
            $row = Ensure-RowState $data[$padIndex]
            $row.delete = 1
          #  $row.delet2 = 1
            $row.cat = "ip6prePad"
            $data[$padIndex] = $row
            $prepadEnd = $padIndex
        }
    }

    if ($debug){ write-host "70  $($index)"}
    # step 7
    # Mark sections that overlap the final time window.
    $fileEndTime = [double]$data[$lastFrame - 1].end
    $endDeleteFrom = $fileEndTime - $endDelete
    for ($index = 0; $index -lt $lastFrame; $index++) {
        if ([double]$data[$index].end -le $endDeleteFrom) { continue }
        $row = Ensure-RowState $data[$index]
        $row.delete = 1
     #   $row.delet2 = 1
        $row.cat = "ip7end"
        $data[$index] = $row
    }

    if ($debug){ write-host "80  $($index)"}
    # step 8 - tighten: clear short noise bursts that do not belong to a real pulse block.
    for ($index = 0; $index -lt $lastFrame;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $lastFrame -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        $runStartTime = [double]$data[$runStart].start
        $runEndTime = [double]$data[$index - 1].end
        $runDuration = $runEndTime - $runStartTime
        $isBorderPulse = ($runStartTime -lt $startSpeech) -or (($fileEndTime - $runEndTime) -lt $endDelete)
        if ($runDuration -lt $tightenDelete -and -not $isBorderPulse) {
            for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                $row = Ensure-RowState $data[$runIndex]
                $row.delete = 0
         #       $row.delet2 = 0
                $row.cat = "ip8tighten"
                $data[$runIndex] = $row
            }
        }
    }

    if ($debug){ write-host "100  $($index)"}
    foreach ($index in $adjacentCategoryDeleteIndexes) {
        $row = Ensure-RowState $data[$index]
        $row.delete = 1
     #   $row.delet2 = 1
        $row.cat = "ip9adjacent"
        $data[$index] = $row
        if ($debug){ write-host "101  $($index)"}
    }

    return $data
}




function analyze1{
    param($data)
    # analyse shape of the data. Expect mostly wide flat (0-value) sections with a few (1-value) square pulse blocks.
    # pulses should be contiguous blocks (8 to 150 seconds width). File always begins with a wide pulse block.
    # the file probably ends with a similiar pulse block. There are only a few pulse blocks in the file.
    # small pulses should be flattened to 0-values as these sections are probably speech with loud peaks.
    
    $data = Set-DeleteState $data
    $ratio=1
    # Count contiguous runs of marked frames and summarize their lengths by seconds.
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
    $pulseSeconds = 0
    $pulseMinute = 0
    $previousFrame = $null
    $previousStart=0

    foreach ($row in $orderedData) {
        $frame = [long]$row.Frame
        #$isPulse = [int]$row.delet2 -eq 1
        $isPulse = [int]$row.delete -eq 1
        $pulseSeconds=$row.start -  $previousStart

        if ($pulseSeconds -gt 0 -and  $isPulse ) {
            $pulseRecords.Add([pscustomobject]@{
                minute = $pulseMinute
                lengthSeconds = $pulseSeconds  #* $frameDurationSeconds
            })
            $pulseSeconds = 0
        }

        if ($isPulse) {
            if ($pulseSeconds -eq 0) {
                if ($row.PSObject.Properties.Name -contains 'minute') {
                    $pulseMinute = [int]$row.minute
                }
                else {
                    $pulseMinute = [int][Math]::Floor([double]$row.pts_time / 60)
                }
            }
           # $pulseSeconds++
        }
        $previousFrame = $frame
        $previousStart =$row.start
    }

    if ($pulseSeconds -gt 0) {
        $pulseRecords.Add([pscustomobject]@{
            minute = $pulseMinute
            lengthSeconds = $pulseSeconds # * $frameDurationSeconds
        })
    }

    $widePulseCount = @($pulseRecords | Where-Object {
        [double]$_.lengthSeconds -gt ([double]$minDeleteRun / [double]$framesPerSecond)
    }).Count
    $tinyPulseCount = @($pulseRecords | Where-Object {
        [double]$_.lengthSeconds -le ([double]$minDeleteRun / [double]$framesPerSecond)
    }).Count

    $pulseLengthSummary = @(
        $pulseRecords |
            Group-Object -Property minute |
            Sort-Object { [int]$_.Name } |
            ForEach-Object {
                $minute = [int]$_.Name
                foreach ($pulse in $_.Group) {
                    [pscustomobject]@{
                        minute = $minute
                        LengthSeconds = [math]::Round([double]$pulse.lengthSeconds, 3)
                    }
                }
            }
    )

    $pulseLengthSummary | Format-Table -AutoSize | Out-Host
    $overallAverageLength = if ($pulseRecords.Count -gt 0) {
        [math]::Round((($pulseRecords | Measure-Object -Property lengthSeconds -Average).Average), 1)
    } else {
        0
    }
    $PulseCount = $pulseRecords.Count
    Write-Host "Total pulses: $PulseCount; overall average length: $overallAverageLength seconds"
    if ($PulseCount -gt $maxPulseCount) {
         Write-Host "max pulse limit exceeded. recommend to re-process"
    }
    # analyze comments 
    Write-Host "wide pulse $widePulseCount vs narrow pulse $tinyPulseCount"
    if ($widePulseCount -eq 0) {
        Write-Host "wide pulse zero so no need to interpolate."
    }
    elseif ($tinyPulseCount -gt 0) {
        $ratio = $widePulseCount / $tinyPulseCount
        if ($ratio -gt 1) {
            Write-Host "interpolate is completed since ratio $ratio gt 1"
        }
    }
    return $ratio
}
   


function analyze2 {
    param($data)

    $deleteRanges = [System.Collections.Generic.List[string]]::new()
    $runStart = $null
    $runEnd = $null
    $previousTime =0 # initial delete section start at beginning of file

    foreach ($row in @($data)) {
        $isDelete = [int](Get-RowPropertyValue -Row $row -PropertyName 'delete' -Default 0) -eq 1
        $thisTime = [double](Get-RowPropertyValue -Row $row -PropertyName 'pts_time' -Default 0)

        if ($isDelete) {
            if ($null -eq $runStart) {
                $runStart = [double]$row.start
            }
            $runEnd = [double]$row.end
            continue
        }

        if ($null -ne $runStart -and $null -ne $runEnd -and $null -ne $previousTime) {
            $deleteRanges.Add([string]::Format(
                [System.Globalization.CultureInfo]::InvariantCulture,
                'between(t,{0:R},{1:R})',
                [Math]::Max(0.0, $previousTime),
                [Math]::Min([double]$row.start, [double]$runStart)
            ))
            $runStart = $null
            $runEnd = $null
        }

        $previousTime = $thisTime
    }

    if ($null -ne $runStart -and $null -ne $runEnd -and $null -ne $previousTime) {
        $deleteRanges.Add([string]::Format(
            [System.Globalization.CultureInfo]::InvariantCulture,
            'between(t,{0:R},{1:R})',
            [Math]::Max(0.0, $previousTime),
            [Math]::Max(0.0, $runStart)
        ))
    }

    # audio filter to output new audio file by selecting only the sections with speech.
    # ffmpeg time-based selectors use t in seconds, not frame indexes n.
    $deleteExpression = if ($deleteRanges.Count -gt 0) {
        $deleteRanges -join '+'
    } else {
        '0'
    }
    $FILTER = "aselect='not($deleteExpression)'"
    return $FILTER
}




function old1{   
    try {
        $thisTime=1.0
        $prevTime=1.0
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
        
    }catch{$error[0]}
}



function analyze3 {
    param($data)

    return analyze2 $data
}

function Get-TrimmedSeconds {
    param($data)

    $totalSeconds = 0.0
    $runStart = $null
    $runEnd = $null

    foreach ($row in @($data)) {
        if ($null -eq $row) { continue }

        $isDelete = [int](Get-RowPropertyValue -Row $row -PropertyName 'delete' -Default 0) -eq 1

        if ($isDelete) {
            if ($null -eq $runStart) {
                $runStart = [double]$row.start
            }
            $runEnd = [double]$row.end
            continue
        }

        if ($null -ne $runStart -and $null -ne $runEnd) {
            $totalSeconds += [Math]::Max(0.0, $runEnd - $runStart)
            $runStart = $null
            $runEnd = $null
        }
    }

    if ($null -ne $runStart -and $null -ne $runEnd) {
        $totalSeconds += [Math]::Max(0.0, $runEnd - $runStart)
    }

    return $totalSeconds
}


function trimBlocks{
    param($FILTER)
    try{
        write-host "in  mp3 =  $inFile"
        $FILTER
        write-host "out mp3 =  $outputPath"
        
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

}

$data =(getSilFile "$logPath\$SilenceFile")

$newData = interpolate $data
$newData | Export-Csv -Path "$LogPath\silnew_.csv"

# filter should remove the sections with delete marks
$filter = analyze3 $newData

$retryCount = 0

# while ((analyse $newData) -gt $maxPulseCount -and $retryCount -lt 10) {
while ((analyze1 $newData) -lt 1 -and $retryCount -lt 4) {
    write-host "retry $retryCount with analyze1" -ForegroundColor Cyan
    $newData = interpolate $newData
    $newData | Export-Csv -Path "$LogPath\silnew$retryCount.csv"
    $filter = analyze3 $newData

    $retryCount++
}

$trimmedSeconds = Get-TrimmedSeconds $newData
$trimmedSummary = "Total seconds trimmed: $([math]::Round($trimmedSeconds, 3))"
Write-Host $trimmedSummary
Add-Content -LiteralPath $logName -Value $trimmedSummary


    # step 9
    trimBlocks $filter


    Write-Host "Trim  and  $logName"


