<# trim and delete with silence                                              v3.1.2
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
    [string]$InputFile = "_source.mp3",
    [string]$dd = 'F:\av\audio\downloads',
    [string]$logPath = 'F:\av\audio\done\logs',
    [string]$RmsFile = '_RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$SilenceFile = '_sil.csv',
    [string]$OutputPath = 'F:\av\audio\done',
    [string]$OutputFile = '_new.mp3',
    [string]$DeleteFile = '_sil.csv', # analysed silence result that show the sections to be deleted
    $debug = 0
)
write-host $PSCommandPath -BackgroundColor cyan
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$debug = 0
$script:tt=0

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

function Get-SilenceFile {
    param([string]$FilePath)

    Write-Host "reading =  $FilePath"

    try {
        return @(Import-Csv -LiteralPath $FilePath -Delimiter ",")
    }
    catch {
        throw "Failed to read CSV '$FilePath': $($_.Exception.Message)"
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
        $row.delete = $deleteValue

        if ($deleteValue -eq 1) {
            Write-DebugLog "delt" $row
        }
    }

    return @($data)
}

function interpolate {
    param($data)

    $data = Set-DeleteState $data

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

        [int]$minute = $row.pts_time / 60
        Write-DebugLog "ipol  $minute" $row
    }



    # step 2
    # start of the file are marked as delete section
    $startCutoffSeconds = 30.0
    $startSectionIndex = 0

    for ($index = 0; $index -lt $data.Count; $index++) {
        $row = $data[$index]
        $row.delete = 1
        $row.delet2 = 1
        $thisCat= $row.cat 
        $row.cat = "ip1start"
        $startSectionIndex = $index + 1

        if ([double]$row.pts_time -gt $startCutoffSeconds) {
            if ($thiscat -match "constant"){
                 $row.cat = "ip1constant"
            }   # keep applying delete marker at start until the audio queitens down.
            else {
                break
            }
        }
    }

    <# step 3
    # clear short noise bursts before filling short gaps between real delete runs
    for ($index = $startSectionIndex; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }
        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        } 
    }
    #>
    # step 4
    # Fill short speech gaps of 2 seconds when they are bounded by delete runs.
    for ($index = $startSectionIndex; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 1) {
            $index++
            continue
        }

        $gapStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 0) {
            $index++
        }

        $gapLength = $index - $gapStart
        $hasDeleteBefore = ($gapStart -gt 0) -and ([int]$data[$gapStart - 1].delete -eq 1)
        $hasDeleteAfter = ($index -lt $data.Count) -and ([int]$data[$index].delete -eq 1)

        if ($hasDeleteBefore -and $hasDeleteAfter -and $gapLength -lt 2) {
            for ($gapIndex = $gapStart; $gapIndex -lt $index; $gapIndex++) {
                $data[$gapIndex].delete = 1
                $data[$gapIndex].cat = "ip4gap"
            }
        }
    }

     # step 5
     # Remove very short 3 seconds delete runs after the gap fill.
    for ($index = $startSectionIndex; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        if (($index - $runStart) -lt 3 -and $index -gt 2000) {
            for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                $data[$runIndex].delete = 0
                $data[$runIndex].delet2 = 0
                $data[$runIndex].cat = "ip5collapse"
            }
        }
    }
    # step 6
    # Pad 1 second before valid delete sections to keep them coherent.
    for ($index = $startSectionIndex; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -ne 1) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        $padStart = [Math]::Max(0, $runStart - 1)
        for ($padIndex = $padStart; $padIndex -lt $runStart; $padIndex++) {
            $data[$padIndex].delete = 1
            $data[$padIndex].delet2 = 1
            $data[$padIndex].cat = "ip6prePad"
        }
    }
    # step 7
    # end 20 seconds of the file are marked as delete section
    $endDelete = 20
    $endSectionLength = [Math]::Min($endDelete, $data.Count)
    for ($index = $data.Count - $endSectionLength; $index -lt $data.Count; $index++) {
        $data[$index].delete = 1
        $data[$index].delet2 = 1
        $data[$index].cat = "ip7end"
    }

    # step 8 
    # Tighten short noise bursts that are not part of a real delete block.
    for ($index = $startSectionIndex; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStartIndex = $index
        $runStartTime = [double]$data[$index].end
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        if (($data.Count - $index) -lt $endSectionLength) {
            continue
        }

        # tighten Delete if less than 6 seconds
        $runLength = [double]$data[$index].pts_time - $runStartTime
        if ($runLength -lt 6) {
            for ($runIndex = $runStartIndex; $runIndex -lt $index; $runIndex++) {
                $data[$runIndex].delete = 0
                $data[$runIndex].delet2 = 0
                $data[$runIndex].cat = "ip8tighten"
            }
        }
    }

    return $data
}

function analyze1 {
    param($data)
   # analyse shape of the data. Expect mostly wide flat (0-value) sections with a few (1-value) square pulse blocks.
    # pulses should be contiguous blocks (8 to 150 seconds width). File always begins with a wide pulse block.
    # the file probably ends with a similiar pulse block. There are only a few pulse blocks in the file.
    # small pulses should be flattened to 0-values as these sections are probably speech with loud peaks.
    
    $data = Set-DeleteState $data
    $ratio = 1
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
    }
    else {
        1 / 38
    }

    $pulseRecords = [System.Collections.Generic.List[object]]::new()
    $pulseSeconds = 0
    $pulseMinute = 0
    $previousFrame = $null
    $previousStart = 0

    foreach ($row in $orderedData) {
        $frame = [long]$row.Frame
        $isPulse = [int]$row.delete -eq 1
        $pulseSeconds = $row.start - $previousStart

        if ($pulseSeconds -gt 0 -and $isPulse) {
            $pulseRecords.Add([pscustomobject]@{
                    minute = $pulseMinute
                    lengthSeconds = $pulseSeconds
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
        }

        $previousFrame = $frame
        $previousStart = $row.start
    }

    if ($pulseSeconds -gt 0) {
        $pulseRecords.Add([pscustomobject]@{
                minute = $pulseMinute
                lengthSeconds = $pulseSeconds
            })
    }

    $minDeleteRun = 3
    $framesPerSecond = 38
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
    }
    else {
        0
    }

    $maxPulseCount = 10
    $PulseCount = $pulseRecords.Count
    Write-DebugLog "f1" "Total pulses: $PulseCount; overall average length: $overallAverageLength seconds"

    if ($PulseCount -gt $maxPulseCount) {
        Write-Host "max pulse limit exceeded. recommend to re-process"
    }
    # analyze comments 
    Write-Host "wide pulse $widePulseCount vs narrow pulse $tinyPulseCount"
    if ($widePulseCount -eq 0) {
        Write-DebugLog "f1" "wide pulse zero so no need to interpolate."
    }
    elseif ($tinyPulseCount -gt 0) {
        $ratio = $widePulseCount / $tinyPulseCount
        if ($ratio -gt 1) {
            Write-DebugLog "f1" "interpolate is completed since ratio $ratio gt 1"
        }
    }

    return $ratio
}

function setFilter { # version 1.1
    param($data)

    $prevTime = 0
    $deleteRanges = [System.Collections.Generic.List[string]]::new()
    $trimSections = [System.Collections.Generic.List[object]]::new()
    $trimSectionStart = $null
    $trimSectionEnd = $null

    $resultHistory = [System.Collections.Generic.List[object]]::new()
    
    foreach ($row in $data) {
        $thisTime = [double]$row.pts_time

        if ([int]$row.delete -eq 1) {
            if ($null -eq $trimSectionStart) {
                $trimSectionStart = $prevTime
            }
            $trimSectionEnd = $thisTime

            $deleteRanges.Add([string]::Format(
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    'between(t,{0:R},{1:R})',
                    $prevTime,
                    $thisTime
                ))
        }
        elseif ($null -ne $trimSectionStart) {
            $trimSections.Add([pscustomobject]@{
                    Start = [double]$trimSectionStart
                    End = [double]$trimSectionEnd
                })
            $trimSectionStart = $null
            $trimSectionEnd = $null
        }

        $prevTime = $thisTime
    }

    if ($null -ne $trimSectionStart) {
        $trimSections.Add([pscustomobject]@{
                Start = [double]$trimSectionStart
                End = [double]$trimSectionEnd
            })
    }

    # Compare trim seconds with the RMS commercial score for each minute.
    Write-Host "Silence trim and rms level histograms by minute:"
    $trimSecondsByMinute = @{}
    $sectionCountByMinute = @{}
    foreach ($section in $trimSections) {
        $minute = [int][Math]::Floor($section.Start / 60)
        if (-not $sectionCountByMinute.ContainsKey($minute)) {
            $sectionCountByMinute[$minute] = 0
        }
        $sectionCountByMinute[$minute]++

        $cursor = [double]$section.Start
        while ($cursor -lt $section.End) {
            $minute = [int][Math]::Floor($cursor / 60)
            $minuteEnd = ($minute + 1) * 60
            $portionEnd = [Math]::Min([double]$section.End, [double]$minuteEnd)
            $seconds = $portionEnd - $cursor
            if (-not $trimSecondsByMinute.ContainsKey($minute)) {
                $trimSecondsByMinute[$minute] = 0.0
            }
            $trimSecondsByMinute[$minute] += $seconds
            $cursor = $portionEnd
        }
    }

    $rmsPercentByMinute = @{}
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $rmsCsvPath = Join-Path $dd "$baseName.rms.csv"
    if (Test-Path -LiteralPath $rmsCsvPath -PathType Leaf) {
        $rmsData = @(Import-Csv -LiteralPath $rmsCsvPath)
        foreach ($minuteGroup in ($rmsData | Group-Object -Property minute)) {
            $frameCount = $minuteGroup.Count
            $commercialFrames = [int](($minuteGroup.Group | Measure-Object -Property delet2 -Sum).Sum)
            $rmsPercentByMinute[[int]$minuteGroup.Name] = if ($frameCount -gt 0) {
                [Math]::Round(100 * $commercialFrames / $frameCount, 1)
            }
            else {
                0
            }
        }
    }
    else {
        Write-Warning "RMS histogram data not found: $rmsCsvPath"
    }

    $minutes = @($trimSecondsByMinute.Keys) + @($rmsPercentByMinute.Keys) |
        Sort-Object -Unique
    if ($minutes.Count -eq 0) {
        Write-Host "No trim sections or RMS histogram rows found."
    }
    else {
        $maxSeconds = if ($trimSecondsByMinute.Count -gt 0) {
            ($trimSecondsByMinute.Values | Measure-Object -Maximum).Maximum
        }
        else {
            0
        }

        foreach ($minute in $minutes) {
            $trimSeconds = if ($trimSecondsByMinute.ContainsKey([int]$minute)) {
                [double]$trimSecondsByMinute[[int]$minute]
            }
            else {
                0.0
            }
            $sectionCount = if ($sectionCountByMinute.ContainsKey([int]$minute)) {
                $sectionCountByMinute[[int]$minute]
            }
            else {
                0
            }
            $trimBarLength = if ($maxSeconds -gt 0 -and $trimSeconds -gt 0) {
                [Math]::Max(1, [int][Math]::Round(40 * $trimSeconds / $maxSeconds))
            }
            else {
                0
            }
            $rmsPercent = if ($rmsPercentByMinute.ContainsKey([int]$minute)) {
                [double]$rmsPercentByMinute[[int]$minute]
            }
            else {
                0.0
            }

            if ($trimSeconds -eq 0 -and $rmsPercent -eq 0) {
                continue
            }

            $resultHistory.Add([PSCustomObject]@{
                minute       = [int]$minute
                trimsecs     = $trimSeconds
                sections     = $sectionCount
                secondsBar   = '#' * $trimBarLength
                rmsPercent   = $rmsPercent
                rmsHistogram = '#' * [Math]::Round($rmsPercent / 10)
            })
            $script:tt+=$trimSeconds
        }

        $resultHistory |
            Format-Table -Property minute, trimsecs, sections, secondsBar, rmsPercent, rmsHistogram -AutoSize |
            Out-Host
    }

    # audio filter to output new audio file by selecting only the sections with speech.
    $deleteExpression = if ($deleteRanges.Count -gt 0) {
        $deleteRanges -join '+'
    }
    else {
        '0'
    }

    return "aselect='not($deleteExpression)'"
}

function aFilter1 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseFilter
    )
# -af asetrate=44100*0.9,aresample=44100,atempo=1/0.9 output.mp3
    $audioFilter = @(
        $BaseFilter,
        'equalizer=f=130:width_type=h:width=100:g=1',
        'equalizer=f=230:width_type=h:width=100:g=-2',
        'equalizer=f=480:width_type=h:width=400:g=-3',
        'equalizer=f=980:width_type=h:width=600:g=-6',
        'equalizer=f=1780:width_type=h:width=1000:g=-12',
        'equalizer=f=2780:width_type=h:width=1000:g=-15',
        'equalizer=f=6400:width_type=h:width=6400:g=-21',
        'equalizer=f=15000:width_type=h:width=10800:g=-27',
        "atempo=0.8",
        "speechnorm=e=12.5:r=0.0001:l=1"
    ) -join ','

    # Moderate and slow amplification     speechnorm=e=6.25:r=0.00001:l=1
    # Strong   and fast amplification     speechnorm=e=12.5:r=0.0001:l=1
    # https://ffmpeg.org/ffmpeg-all.html#Examples-81
    # Slow down audio to 80% tempo: atempo=0.8
    #  Male voices average 85-180 Hz; female voices 165-255 Hz
    return $audioFilter
}




function aFilter2 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseFilter
    )
# -af "rubberband=pitch=0.8" output.mp3
# https://ffmpegbyexample.com/examples/749f6u35/timestretch_audio_and_video_using_rubberband_filter/
# https://salivity.github.io/ffmpeg/article/how-to-use-f-fmpeg-rubberband-for-audio-pitch-shifting
# $audioFilter= "rubberband=pitch=0.7937" # down 4 semitones
#  "rubberband=tempo=0.8:pitch=0.7937",
# 0.89090 down 2 semitones
# $audioFilter= "rubberband=pitch=0.94387" # down 1 semitone
# rubberband=tempo=0.5:pitch=0.5    #: tempo=0.5 slow down the audio to half speed and pitch=0.5 lower the pitch by one octave.

    $audioFilter = @(
        $BaseFilter,
        "rubberband=tempo=0.75:pitch=0.995",
        'equalizer=f=130:width_type=h:width=100:g=1',
        'equalizer=f=230:width_type=h:width=100:g=-2',
        'equalizer=f=480:width_type=h:width=400:g=-3',
        'equalizer=f=980:width_type=h:width=600:g=-6',
        'equalizer=f=1780:width_type=h:width=1000:g=-12',
        'equalizer=f=2780:width_type=h:width=1000:g=-15',
        'equalizer=f=6400:width_type=h:width=6400:g=-21',
        'equalizer=f=15000:width_type=h:width=10800:g=-27',
        "speechnorm=e=6.25:r=0.00001:l=1"
    ) -join ','
    return $audioFilter
}



function trimBlocks {
    param($FILTER)

    $ffmpegPath = (Get-Command ffmpeg -ErrorAction SilentlyContinue)?.Source
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

    $audioFilter = aFilter1 -BaseFilter $FILTER
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
        & $ffmpegPath @args 2> "$logName" | Out-Null
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

function Invoke-SilTrimWorkflow {                           # MAIN WORKER
    Set-Location -LiteralPath $OutputPath

    $script:logName = Join-Path $logPath 'delete.log'
    $script:inFile = Resolve-RelativePath -PathValue $InputFile -BasePath $dd
    $script:outputPath = Resolve-RelativePath -PathValue $OutputFile -BasePath $OutputPath
    $deleteCsvPath = Resolve-RelativePath -PathValue $DeleteFile -BasePath $logPath
    $silenceCsvPath = Resolve-RelativePath -PathValue $SilenceFile -BasePath $logPath

    if (-not (Test-Path -LiteralPath $script:inFile -PathType Leaf)) {
        throw "Input file not found: $script:inFile"
    }

    if (-not (Test-Path -LiteralPath $silenceCsvPath -PathType Leaf)) {
        throw "Silence CSV not found: $silenceCsvPath"
    }

    if (-not (Test-Path -LiteralPath $deleteCsvPath -PathType Leaf)) {
        Write-Host "Delete CSV not found: $deleteCsvPath"
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

    Write-Host "========= sil trim and delete   =============================================" -ForegroundColor Blue

    try {
        $data = Get-SilenceFile -FilePath $silenceCsvPath
        $newData = interpolate $data
        $exportPath = Join-Path $logPath '_silnew.csv'
        $newData | Export-Csv -Path $exportPath -NoTypeInformation

        $filter = setFilter $newData
        trimBlocks -FILTER $filter
        Write-Host "Trim  and  $script:logName TOTAL $script:tt"
    }
    catch {
        throw "Sil trim workflow failed: $($_.Exception.Message)"
    }
}

Invoke-SilTrimWorkflow
