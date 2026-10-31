<# spectrum re-combine the RMS and Silence data for analysis                    v0.0.3
-------------------------------------------------------------------------------------
analyse the source data to and mark earh row with decision status to
aim is delete the sections with loud rms and suppress high pitch music
#>

param (
    [string]$InputPath = 'F:\av\audio\done',    
    [string]$dd = 'F:\av\audio\downloads',
    [string]$InputFile = '_source.mp3',
    [string]$logPath = 'F:\av\audio\done\logs',
    [string]$SilenceFile = '_sil.csv',
    [string]$RmsFile = '_RMS.csv', # analysed rms levels result that show the sections to be deleted
    [string]$OutputPath = 'F:\av\audio\done',    
    [string]$OutputFile = '_new.mp3',
    $debug=1
)
write-host $PSCommandPath -BackgroundColor cyan
    $logname = Join-Path $logPath '_spectrum.log'
    $startFrame = 0
    $deleteRanges = [System.Collections.Generic.List[string]]::new()
    $pDStatus = $false
    $RMSlogDate=""

    $inputPath = if ([System.IO.Path]::IsPathRooted($InputFile)) {
        $InputFile
    }
    else {
        Join-Path $dd $InputFile
    }

    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Input file not found: $inputPath"
    }
  
function getRMS{
    param( [string]$fName) # fullname
    $rmsScript = Join-Path $psscriptRoot 'process_rms_level1.ps1'
    $InputDir=$inputPath
    $outLogDir=$logPath
    try {
        if ($debug) {
            write-host "-inputDir $InputDir `n-logPath $outLogDir `n-InputFile $fName `n-OutputCsv $RmsFile" -ForegroundColor Yellow
        }
        & $rmsScript -inputDir $InputDir -logPath $outLogDir -InputFile $fName -OutputCsv $RmsFile   
    }
    catch {
        $Error[0]
    }      
}


# MAIN ############################################################### 
try {
        Write-Host "======= = load rms      =============================================" -ForegroundColor Blue
        if (test-path "$LogPath\$RmsFile" ){      
            $RMSlogDate=(Get-Item "$LogPath\$RmsFile").CreationTime
           # if ($RMSlogDate -lt ((get-date).AddMinutes(-1))){
                write-host "remove existing RMSlog $RMSlogDate" -ForegroundColor Yellow
                Remove-Item "$LogPath\$RmsFile"
                getRMS "$dd\$inputfile" "$LogPath\$RmsFile"
            #}   
        }
        else {
            write-host "get new RMSlog $RMSlogDate"
            getRMS "$dd\$inputfile" "$LogPath\$RmsFile"
        }
         if (test-path "$LogPath\$RmsFile" ){      
        write-host "reading = $LogPath\$RmsFile"         
         $data1 = @(Import-Csv -Path "$LogPath\$RmsFile" -Delimiter ",") # import rms csv data file with first row headers
         }
         else{
            exit
         }
        Write-Host "======= = load silence   =============================================" -ForegroundColor Blue
        write-host "reading =  $LogPath\$silenceFile"
        $data2 = @(Import-Csv -Path "$LogPath\$SilenceFile" -Delimiter ",") # import sil csv data file with first row headers

        # Join by frame while keeping fields from both CSVs.
        $RMSrows=$data1.Count
        if ($RMSrows -eq 0) {
            throw "No RMS rows found in: $LogPath\$RmsFile"
        }
        elseif ($debug) {
            write-host "$RMSrows rows in RMSlog to process"
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

}
catch {
    $Error[0]
}


 Write-Host "Spec Log   $logName"


