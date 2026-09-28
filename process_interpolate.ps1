<# interpolate the delete markers                                             v0.1.0
-------------------------------------------------------------------------------------
    interpolate to ensure delete sections of 0-values in the rms1.csv file are continuous
    short gaps between delete sections (1) are filled so delete sections stay continuous
    short speech sections (0) are also filled to avoid speech fragmentation
    long speech runs of 0-values
    short delete sections (1) inside speech are cleared back to 0 unless closely followed by another delete section.
    Use the RMS3.csv file to identify the algorithm needed. RMS3 is the manually corrected file.
    Both ends of the file should be marked as delete sections (1)
#>

[CmdletBinding()]
param (
    [string]$inputDir = 'F:\av\audio\done',
    [string]$OutputDir = 'F:\av\audio\done',
    [string]$logPath = '\',
    [string]$InputFile = 'TH609.mp3',
    [string]$OutputCsv = 'rms.csv',
    [string]$DeleteFile = 'RMS1.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputFile = 'RMS5.csv' # final output
)
   
    $framesPerSecond = 38
    $minGap = $framesPerSecond * 6
    $minDeleteRun = $framesPerSecond * 20
    $endsDelete = $framesPerSecond * 6

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

    # read the values in the data file as a PSobject table
    foreach ($row in $data) {
        
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

    # Remove short false-positive delete runs before filling speech gaps.
    for ($index = 0; $index -lt $data.Count;) {
        if ([int]$data[$index].delete -eq 0) {
            $index++
            continue
        }

        $runStart = $index
        while ($index -lt $data.Count -and [int]$data[$index].delete -eq 1) {
            $index++
        }

        if (($index - $runStart) -lt $minDeleteRun) {
            for ($runIndex = $runStart; $runIndex -lt $index; $runIndex++) {
                $data[$runIndex].delete = 0
            }
        }
    }

    # Fill short speech gaps only when they are bounded by retained delete runs.
    for ($index = 0; $index -lt $data.Count;) {
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
            }
        }
    }

    $endSectionLength = [Math]::Min($endsDelete, $data.Count)
    for ($index = 0; $index -lt $endSectionLength; $index++) {
        $data[$index].delete = 1
    }
    for ($index = $data.Count - $endSectionLength; $index -lt $data.Count; $index++) {
        $data[$index].delete = 1
    }

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
        Write-Host "remove  =  $dest"
        Remove-Item $dest -Force
    }

    $data | Export-Csv -LiteralPath $dest -NoTypeInformation
    Write-Host "ioutput =  $dest"
