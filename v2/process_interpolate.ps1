<# interpolate the delete markers                                             v0.1.2
-------------------------------------------------------------------------------------
    interpolate to ensure delete sections of 0-values in the rms1.csv file are continuous
    short gaps between delete sections (1) are filled so delete sections stay continuous
    short speech sections (0) are also filled to avoid speech fragmentation
    long speech runs of 0-values
    short delete sections (1) inside speech are cleared back to 0 unless closely followed by another delete section.
    Both ends of the file should be marked as delete sections (1)
#>

[CmdletBinding()]
param (
    [string]$inputDir = 'F:\av\audio\done',
    [string]$OutputDir = 'F:\av\audio\done',
    [string]$logPath = 'logs',
    [string]$InputFile = 'TH609.mp3',
    [string]$OutputCsv = 'rms.csv',
    [string]$DeleteFile = 'RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputFile = 'RMS5.csv' # final output
)
   
    $framesPerSecond = 38
    $minGap       = $framesPerSecond * 6    # if two delete sections 6 seconds mininum apart then fill this gap (with 1 marks)
    $minDelete    = $framesPerSecond * 3    # if delete section 3 seconds mininum then assume its not valid (flatten with 0 marks)
    $preDeleteRun = $framesPerSecond * 4    # if valid delete section the pad up to 4 seconds before it.
    $minDeleteRun = $framesPerSecond * 10   # if valid delete seciton limit 10 seconds of additional delete padding to next section
    $startDelete   = $framesPerSecond * 15  # first 15 seconds of the file should be marked as delete
    $endDelete   = $framesPerSecond * 6     # end 6 seconds of the file shoudl be marked as deletes
    
    $sourceCandidates = @(
        $DeleteFile,
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
    # step 1
    # read the values in the data file as a PSobject table
    foreach ($row in $data) {
        # step 1        
        # read the delete column values 
        $deleteValue = if ($row.PSObject.Properties.Name -contains 'delete') {
            [int]$row.delete
        } else {
            0
        }
        
        # 
        if ($row.PSObject.Properties.Name -contains 'delete') {
            $row.delete = $deleteValue
        } else {
            $row | Add-Member -NotePropertyName delete -NotePropertyValue $deleteValue
        }
    }
    
    # step 1.5
    # start of the file are marked as delete section
    $strtSectionLength = [Math]::Min($startDelete, $data.Count)
    for ($index = 0; $index -lt $strtSectionLength; $index++) {
        $data[$index].delete = 1
        $data[$index].cat = "ip1start"
    }

    # step 2
    # pad preDelete to leading edge of the delete sections
    $prepadEnd=$strtSectionLength
    for ($index =  $strtSectionLength; $index -lt $data.Count;) {
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
            $data[$padIndex].cat = "ip2prePad"
            $prepadEnd=$padIndex
        }
    }
    # step 3
    # Remove short (not valid)) delete runs before filling speech gaps.
    $runEnded=$padStart
    for ($index = $prepadEnd; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }
        
        if ($index -gt 2000){ # dont apply too early in the file
            if (($index - $runStart) -lt $minDelete) {
                for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                    $data[$runIndex].delete = 0
                    $data[$runindex].cat = "ip3run"
                    $runEnded=$runindex
                }
            }
        }
    }
    # step 4
    # Fill short speech gaps only when they are bounded by retained delete runs.
    for ($index = $runEnded; $index -lt $data.Count;) {
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
                $data[$gapindex].cat = "ip4gap"
            }
        }
    }
    # step 5
    # end of the file are marked as delete section
    $endSectionLength = [Math]::Min($endDelete, $data.Count)
    for ($index = $data.Count - $endSectionLength; $index -lt $data.Count; $index++) {
        $data[$index].delete = 1
        $data[$index].cat = "ip5end"
    }
    # step 6
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

    $data | Export-Csv -LiteralPath $dest -NoTypeInformation
    Write-Host "ipolated=  $dest"
