<# preppolate the delete markers
-------------------------------------------------------------------------------------
    ensure delete section that the pre deletes are fully identified
#>

[CmdletBinding()]
param (
    [string]$dd = 'F:\av\audio\downloads',
    [string]$logPath = '\logs',
    [string]$InputFile = 'USDIESEL.mp3',
    [string]$DeleteFile = 'DELETE1.RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputFile = 'DELETE2.RMS.csv'  # RESULT IS OUTPUT 
)
   
    $debug=1
    $startFrame = 0   # about 38 frames per second
    $minGap = 350 # preppolate only when gap is less than 200
    $maxGap = 500 # if gap is less than 500 then tag an reduce volume filter to be applied.
    $sectionLength=0
    $data = @(Import-Csv -LiteralPath $DeleteFile -Delimiter ',')
    if ($data.Count -eq 0) {
        throw "No rows found in: $DeleteFile"
    }

    # read the values in the data file as a PSobject table
    foreach ($row in $data) {
        
        if ($debug){
            $frm=$row.Frame
            $secs=[int]($row.pts_time/60)
            $del=$row.delete
            if ($del -ne 1){
                $sequence0Count++
                $sequence1Count=0
                if ($sequence0Count -gt 9999){ write-host "$frm $secs $del $sequence0Count" -BackgroundColor green -ForegroundColor black}
                 else {write-host "$frm $secs $del $sequence0Count" -BackgroundColor Black -ForegroundColor green}
            }
            if ($del -eq 1){
                $sequence0Count=0
                $sequence1Count++
                if ($sequence1Count -gt 999){ write-host "$frm $secs $del $sequence1Count" -BackgroundColor red -ForegroundColor black}
                 else {write-host "$frm $secs $del $sequence0Count" -BackgroundColor Black -ForegroundColor red}

                write-host "$frm $secs $del $sequence1Count" -BackgroundColor red
            }           
        }
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


    remove-item $OutputFile # replace the output file with new preppolated version
    if (test-path $OutputFile){
        write-host "still exists $outputFile"
    }
    else {
        $data | Export-Csv -LiteralPath $OutputFile -NoTypeInformation
        Write-Host "preppolated CSV: $OutputFile"
    }


