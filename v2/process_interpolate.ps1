<# interpolate the delete markers                                             v1.0.0
-------------------------------------------------------------------------------------
    interpolate to ensure delete sections of 0-values in the rms.csv file are continuous
    short gaps between delete sections (1) are filled so delete sections stay continuous
    short speech sections (0) are also filled to avoid speech fragmentation
    long speech runs of 0-values
    short delete sections (1) inside speech are cleared back to 0 unless closely followed by another delete section.
    Both ends of the file should be marked as delete sections (1)
#>


param (
    [string]$inputDir = 'F:\av\audio\done',
    [string]$OutputDir = 'F:\av\audio\done',
    [string]$logPath = 'logs',
    [string]$InputFile = 'source.mp3',
    [string]$OutputCsv = 'rms.csv',
    [string]$DeleteFile = 'RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputFile = 'RMS.csv', # final output
    [string]$OutputLog = 'logs'

)
   $logsDir="$outputDir\$logPath"
    $framesPerSecond = 38
    $minGap       = $framesPerSecond * 5   # if two delete sections are only 4 seconds apart, fill the gap to keep a single pulse block
    $minDelete    = $framesPerSecond * 5   # anything shorter than 2 seconds is likely noise, flatten it back to speech
    $preDeleteRun = $framesPerSecond * 5   # pad 5 seconds before a valid delete run
    $minDeleteRun = $framesPerSecond * 8   # if valid delete seciton limit 10 seconds of additional delete padding to next section
    $startDelete  = $framesPerSecond * 60  # first 12 seconds of the file should be marked as delete
    $endDelete    = $framesPerSecond * 4   # end 4 seconds of the file should be marked as deletes
    $tightenDelete = [Math]::Floor($framesPerSecond * 5)  # anything under 5s is treated as a noise burst and collapsed back to speech
    $maxPulseCount= 6 # limit of count of pulse block in the final file. if more than 6 then file will need to be re-processed.
    $widePulseCount=0    # count the number of wide pulse blocks
    $tinyPulseCount=0    # count the number of narrow pulses 
    $sourceCandidates = @(
        $DeleteFile,
         (Join-Path $LogsDir $DeleteFile),
        (Join-Path $OutputDir $DeleteFile),
        (Join-Path $inputDir $DeleteFile),
        ($DeleteFile -replace '\.RMS\.csv$', '.csv'),
        ($DeleteFile -replace '\.csv$', '.RMS.csv')
    ) | Where-Object { $_ }

    $source = $sourceCandidates |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    Write-Host "========= interpolate       ==============================================" -ForegroundColor Blue
    write-host "reading =  $source"
    write-host "pad gaps=  $minGap mininum frames (6 secs) and run over $minDeleteRun frames (20 secs)."  
    if (-not $source) {
        throw "CSV file not found: $DeleteFile"
    }
    $data = @(Import-Csv -LiteralPath $source -Delimiter ',')
    if ($data.Count -eq 0) {
        throw "No rows found in: $source"
    }
   
function Set-DeleteState {
    param($data)

    foreach ($row in $data) {
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
        elseif (-not ($row.PSObject.Properties.Name -contains 'delet2')) {
            $row | Add-Member -NotePropertyName delet2 -NotePropertyValue $deleteValue
        }

        if ($row.PSObject.Properties.Name -contains 'delete') {
            $row.delete = $deleteValue
        }
        else {
            $row | Add-Member -NotePropertyName delete -NotePropertyValue $deleteValue
        }
    }

    return $data
}

function analyse{
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

    $widePulseCount = @($pulseRecords | Where-Object {
        [double]$_.lengthSeconds -gt ([double]$minDeleteRun / [double]$framesPerSecond)
    }).Count
    $tinyPulseCount = @($pulseRecords | Where-Object {
        [double]$_.lengthSeconds -le ([double]$minDeleteRun / [double]$framesPerSecond)
    }).Count

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
        Write-Host "wide pulse zero so no need to interpolate"
    }
    elseif ($tinyPulseCount -gt 0) {
        $ratio = $widePulseCount / $tinyPulseCount
        if ($ratio -gt 1) {
            Write-Host "interpolate is completed since ratio $ratio gt 1"
        }
    }
    return $ratio
}
   

   # analze the data
   analyse $data

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
    }
    


    # step 2
    # start of the file are marked as delete section
    $strtSectionLength = [Math]::Min($startDelete, $data.Count)
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

        if (($index - $runStart) -lt $tightenDelete) {
            for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                $data[$runIndex].delete = 0
                $data[$runIndex].delet2 = 0
                $data[$runIndex].cat = "ip3noise"
            }
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

        $gapLength = $index - $gapStart
        $hasDeleteBefore = $gapStart -gt 0 -and [int]$data[$gapStart - 1].delete -eq 1
        $hasDeleteAfter = $index -lt $data.Count -and [int]$data[$index].delete -eq 1
        if ($hasDeleteBefore -and $hasDeleteAfter -and $gapLength -lt $minGap) {
            for ($gapIndex = $gapStart; $gapIndex -lt $index; $gapIndex++) {
                $data[$gapIndex].delete = 1
                $data[$gapIndex].delet2 = 1
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

        $padStart = [Math]::Max(0, $runStart - $preDeleteRun)
        for ($padIndex = $padStart; $padIndex -lt $runStart; $padIndex++) {
            $data[$padIndex].delete = 1
            $data[$padIndex].delet2 = 1
            $data[$padIndex].cat = "ip6prePad"
            $prepadEnd = $padIndex
        }
    }

    # step 7
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


$newData = interpolate $data
$retryCount = 0

# while ((analyse $newData) -gt $maxPulseCount -and $retryCount -lt 10) {
while ((analyse $newData) -lt 1 -and $retryCount -lt 4) {
    write-host "retry interpolate"
    $newData = interpolate $newData
    $retryCount++
}

try {
    # step 9
    # save output
    $dest = if ([System.IO.Path]::IsPathRooted($OutputFile)) {
        $OutputFile
    }
    else {
        Join-Path $OutputDir $OutputFile
    }

    $outputDirectory = Split-Path -Parent $dest
    if ($outputDirectory) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    # replace the output file with new interpolated version
    if (Test-Path $dest) {
       # Write-Host "remove  =  $dest"
        Remove-Item $dest -Force
    }

    $newData | Export-Csv -LiteralPath $dest -NoTypeInformation
    Write-Host "ipolated=  $dest"
    # show the comparison result
    


}
catch {$error[0]}