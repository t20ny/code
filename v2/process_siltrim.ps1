<# trim and delete with silence                                              v3.0.3
-------------------------------------------------------------------------------------
pre: mp3 input file together with a csv of silence marks. The rows show the time of silence with start end length of the silence.
Post: output mp3 file trimmed of the loud sections. 
How: aselect will select audio sections we want to keep. Aim to keep speech.
    delete the long sections where there is NO silence marks (loud background sections in commercials are to be deleted)
    cat tags: show silence marks where the loud sections End.
    cat=quiet      keep quiet sections
    cat=constant25 is a mark at end of 25 second loud section we will delete. 
    cat=constant15 is a mark at end of 15 second loud section we will delete if adjacent to another constant N
    cat=constant5 is a  mark at end of a short loud section but on its own is not long enough to delete
    cat=breath    is a  mark of a short quiet section is possibly only a pause is loud section.
    cat=ip N tag from interpolate function 

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

function dbug{
    param($fun, $val)
    if ($fun -eq "ipol"){
    Write-Host "Debug $fun $val" -ForegroundColor DarkCyan
    }
    elseif ($fun -eq "delt"){
    Write-Host "Debug $fun $val" -ForegroundColor Yellow
    }
    else{
    Write-Host "Debug $fun $val" -ForegroundColor white
    }
}

    Set-Location -LiteralPath $OutputPath
    $logname = Join-Path $logPath 'delete.log'
    $ErrorActionPreference = 'Continue'
    $startblock = 0
    $deleteRanges = [System.Collections.Generic.List[string]]::new()
    $pDStatus = $false
    
    $minDeleteSection = 10.0 # mininum section length to be deleted
    $maxInterpolate = 10 # maximum seconds allowed for this interpolate
     

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
        Join-Path $dd $OutputFile
    }
    $outputDirectory = Split-Path -Parent $outputPath
    if ($outputDirectory) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    Write-Host "========= sil trim and delete   =============================================" -ForegroundColor Blue
    
 function getSilFile {
    param( [string]$fName)

    write-host "reading =  $fname"
    
    try {
        # import the csv data file with first row headers
        $data = Import-Csv -LiteralPath $fname -Delimiter ","
    }
    catch{$error[0]}
    return $data
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
        #$row = Ensure-RowProperty -Row $row -PropertyName 'cat' -Value 'unset'

        $row.delete = $deleteValue
        #$row.cat = [string](Get-RowPropertyValue -Row $row -PropertyName 'cat' -Default 'unset')
        if ($deleteValue -eq 1){dbug "delt" $row}
    }

    return @($data)
}


function interpolate{
        param($data)

    $data = Set-DeleteState $data

    # step 1
    # read the values in the data file as a PSobject table
    foreach ($row in $data) {
        # step 1        
        # read the delete column values 
        $deleteValue = if ($row.PSObject.Properties.Name -contains 'delet2') {
            [int]$row.delet2
        }
        elseif ($row.PSObject.Properties.Name -contains 'delete') {
            [int]$row.delete
        }
        else {
            0
        }

        if ($row.PSObject.Properties.Name -contains 'delet2') {
            $row.delet2 = $deleteValue
        }
        else {
            $row | Add-Member -NotePropertyName delet2 -NotePropertyValue $deleteValue
        }

        if ($row.PSObject.Properties.Name -contains 'delete') {
            $row.delete = $deleteValue
        }
        else {
            $row | Add-Member -NotePropertyName delete -NotePropertyValue $deleteValue
        }
        dbug "ipol" $row
    }
    


    # step 2
    # start of the file are marked as delete section
    $strtSectionLength =0
    for ($index = 0; $index -lt $strtSectionLength; $index++) {
        $data[$index].delete = 1
        $data[$index].delet2 = 1
        $data[$index].cat = "ip1start"
    }

    # step 3
    # clear short noise bursts before filling short gaps between real delete runs
    for ($index = $strtSectionLength; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }

 
    }

    # step 4
    # Fill short speech gaps only when they are bounded by retained delete runs.
    for ($index = $strtSectionLength; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 1) {
            $index++
            continue
        }

        $gapStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 0) {
            $index++
        }
    
        $minGap=2
        $gapLength = $index - $gapStart
        $hasDeleteBefore = $gapStart -gt 0 -and [int]$data[$gapStart - 1].delete -eq 1
        $hasDeleteAfter = $index -lt $data.Count -and [int]$data[$index].delete -eq 1
        if ($hasDeleteBefore -and $hasDeleteAfter -and $gapLength -lt $minGap) {
            for ($gapIndex = $gapStart; $gapIndex -lt $index; $gapIndex++) {
                $data[$gapIndex].delete = 1
                #$data[$gapIndex].delet2 = 1
                $data[$gapIndex].cat = "ip4gap"
            }
        }
    }

    # step 5
    # Remove short delete runs after the speech-gap fill.
    for ($index = $strtSectionLength; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        $minDelete=3
        if (($index - $runStart) -lt $minDelete -and $index -gt 2000) {
            for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                $data[$runIndex].delete = 0
                $data[$runIndex].delet2 = 0
                $data[$runIndex].cat = "ip5collapse"
            }
        }
    }

    # step 6
    # pad before valid delete sections so they remain coherent blocks
    $prepadEnd = $strtSectionLength
    for ($index = $strtSectionLength; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -ne 1) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        $preDeleteRun=1
        $padStart = [Math]::Max(0, $runStart - $preDeleteRun)
        for ($padIndex = $padStart; $padIndex -lt $runStart; $padIndex++) {
            $data[$padIndex].delete = 1
            $data[$padIndex].delet2 = 1
            $data[$padIndex].cat = "ip6prePad"
            $prepadEnd = $padIndex
        }
    }

    # step 7
    $endDelete=3
    # end of the file are marked as delete section
    $endSectionLength = [Math]::Min($endDelete, $data.Count)
    for ($index = $data.Count - $endSectionLength; $index -lt $data.Count; $index++) {
        $data[$index].delete = 1
        $data[$index].delet2 = 1
        $data[$index].cat = "ip7end"
    }

    # step 8 - tighten: clear short noise bursts that do not belong to a real pulse block.
    for ($index = 0; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        $startDelete=3
        $tightenDelete =5
        $runLength = $index - $runStart
        $isBorderPulse = ($runStart -lt $startDelete) -or (($data.Count - $index) -lt $endDelete)
        if ($runLength -lt $tightenDelete -and -not $isBorderPulse) {
            for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                $data[$runIndex].delete = 0
                $data[$runIndex].delet2 = 0
                $data[$runIndex].cat = "ip8tighten"
            }
        }
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

    $minDeleteRun=3
    $framesPerSecond=38
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
    $maxPulseCount=10
    $PulseCount = $pulseRecords.Count
    dbug "f1" "Total pulses: $PulseCount; overall average length: $overallAverageLength seconds"
    if ($PulseCount -gt $maxPulseCount) {
         Write-Host "max pulse limit exceeded. recommend to re-process"
    }
    # analyze comments 
    Write-Host "wide pulse $widePulseCount vs narrow pulse $tinyPulseCount"
    if ($widePulseCount -eq 0) {
        dbug "f1" "wide pulse zero so no need to interpolate."
    }
    elseif ($tinyPulseCount -gt 0) {
        $ratio = $widePulseCount / $tinyPulseCount
        if ($ratio -gt 1) {
            dbug "f1" "interpolate is completed since ratio $ratio gt 1"
        }
    }
    return $ratio
}
   


function setFilter {
    param(     $data    )
        $toBeDeleted = $false
        $thisTime = 1.0
        $prevTime = 1.0
        $startSpeech = 30.0 # first seconds of file are to be deleted. Speech starts after first 30 seconds have elapsed.
        $DelStatus = $false

        # iterate each row and find the sections to be deleted
        foreach ($line in $data) {
            $thisTime = [double]$line.pts_time
            $sectionStart = [double]$line.start # start of quiet section.
            $sectionEnd = [double]$line.end     # end   of quiet section
            #$sectionLength = $sectionEnd - $sectionStart
            # Delete between the quiet sections
            # Delete the loud section between the previous section End and this quiet section Start
            $sectionLength = $sectionEnd - $sectionStart


            # first 30 seconds of file needs to be deleted, then only keep
            # silence blocks that are long enough to be treated as true delete sections.
            $isDeleteSection = ($thisTime -gt $startSpeech) -and ($sectionLength -ge $minDeleteSection)

            if ($isDeleteSection) {
                if (-not $toBeDeleted) {
                     $prevTime = $sectionStart
                }
                $endblock = $sectionEnd
                $toBeDeleted = $true
            }
            elseif ($toBeDeleted) {
                $DelStatus = 1
                $deleteRanges.Add("between(n,$startblock,$endblock)")
                $toBeDeleted = $false
            }

            # interpolate small gaps in consecutive delete sections
            $prevTime = $thisTime
        }

        if ($DelStatus) {
              $deleteRanges.Add("gte(n,$startblock)")
        }
   
    # audio filter to output new audio file by selecting only the sections with speech
    $deleteExpression = if ($deleteRanges.Count -gt 0) {
        $deleteRanges -join '+'
    } else {
        '0'
    }
    $FILTER = "aselect='not($deleteExpression)'"
    return $FILTER
}


function trimBlocks{
    param($FILTER)
    try{
        write-host "in  mp3 =  $inFile"
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
        dbug "f1" $FILTER
    
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
$filter = setFilter $newData

$retryCount = 0

# while ((analyse $newData) -gt $maxPulseCount -and $retryCount -lt 10) {
while ((analyze1 $newData) -lt 1 -and $retryCount -lt 4) {
    dbug "f1" "retry analyze1"
    $newData = interpolate $newData
    $filter=setFilter $data

    $retryCount++
}


    # step 9
    trimBlocks $filter


    Write-Host "Trim  and  $logName"


