<# interpolate the delete markers
-------------------------------------------------------------------------------------
    ensure delete sections in the delete file are continuous
#>

[CmdletBinding()]
param (
    [string]$dd = 'F:\av\audio\downloads',
    [string]$logPath = '\logs',
    [string]$InputFile = 'USDIESEL.mp3',
    [string]$DeleteFile = 'USDIESEL.RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputFile = 'USDIESEL.RMS2.csv'
)
   
    $startFrame = 0
    $minGap = 350 # interpolate only when gap is less than 200
    $maxGap = 500 # if gap is less than 500 then tag an reduce volume filter to be applied.
    $data = @(Import-Csv -LiteralPath $DeleteFile -Delimiter ',')
    if ($data.Count -eq 0) {
        throw "No rows found in: $DeleteFile"
    }

    foreach ($row in $data) {
        $deleteValue = if ($row.PSObject.Properties.Name -contains 'delete') {
            [int]$row.delete
        } else {
            0
        }

        if ($row.PSObject.Properties.Name -contains 'delete') {
            $row.delete = $deleteValue
        } else {
            $row | Add-Member -NotePropertyName delete -NotePropertyValue $deleteValue
        }
    }

    for ($index = 1; $index -lt ($data.Count - 1); $index++) {
        if ([int]$data[$index].delete -ne 0) {
            continue
        }

        $gapStart = $index
        while ($index -lt ($data.Count - 1) -and [int]$data[$index].delete -eq 0) {
            $index++
        }

        $gapLength = $index - $gapStart
        $hasDeleteBefore = [int]$data[$gapStart - 1].delete -ne 0
        $hasDeleteAfter = [int]$data[$index].delete -ne 0
        if ($hasDeleteBefore -and $hasDeleteAfter -and $gapLength -lt $minGap) {
            for ($gapIndex = $gapStart; $gapIndex -lt $index; $gapIndex++) {
                $data[$gapIndex].delete = 1
            }
        }
    }

    $outputDirectory = Split-Path -Parent $OutputFile
    if ($outputDirectory) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }


    remove-item $OutputFile # replace the output file with new interpolated version
    if (test-path $OutputFile){
        write-host "still exists $outputFile"
    }
    else {
        $data | Export-Csv -LiteralPath $OutputFile -NoTypeInformation
        Write-Host "interpolated CSV: $OutputFile"
    }


