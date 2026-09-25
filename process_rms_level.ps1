param(
    [string]$dd = 'F:\av\audio\downloads',
    [string]$logPath = '\logs',    
    [string]$InputFile = 'USDIESEL.mp3',
    [string]$OutputCsv = 'USDIESEL.csv'
)
$debug=0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$logName="test.log"



function getRMS {
    param(
        [string]$fName,
        [string]$logName
    )
    write-host "fName      $fName"
    write-host "analyzeLog $logName"
   


    # 1 second points
    #$filter = "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level"

    # 2 second points
   #$filter = "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level"
    $FILTER= "astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=$logName" #  verbose file output

    $args4 = @(
        '-hide_banner',
        '-i', $fName,
        '-af', $filter,
        '-f', 'null',
        '-'
    )

    $prevErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & ffmpeg @args4 # 2> $logName | Out-Null
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

    Write-Host "Exported analysis log: $logName"

}


function analyzeRMS {
    param(
        [string]$fName,
        [string]$logName,
        [string]$OutputCsv
    )
    write-host "fName      $fName"
    write-host "analyzeLog $logName"
    write-host "OutputCsv  $OutputCsv"

    
    $TSWindow = [System.Collections.Generic.Queue[double]]::new()
    $spWindow = [System.Collections.Generic.Queue[double]]::new()
    $TSAvW = [System.Collections.Generic.Queue[double]]::new()
    $windowSize=240  # Theil–Sen regression window 38 frames per second so 240 about 6 seconds
    $tsAvg=0
    $tsMed=1
    $pdct1 = 1      # predict commercial is true=1 
    $threshold=24   # if rms average of TSwindow is below threshold
    $speechLvl=-60   # if rms level below -60 then this window is speech
    $category="commercial"

    $result = [System.Collections.Generic.List[object]]::new()
    $thisFrame = 0
    $pts = '0'
    $ptsTime = '0'
    $rmsprev=0

    
    try {
        foreach ($line in Get-Content -LiteralPath $logName) {
            
            # x axis
            if ($line -match "frame:(?<frame>\d+)") { 
            #if ($line -match 'frame:(?<frame>\d+)\s+pts:(?<pts>\S+)\s+pts_time:(?<ptsTime>\S+)') { 
                $thisFrame = [int]$matches['frame']
                $pts=$line.Split('pts:')[1].Trim().Split(' ')[0]
                $ptstime=$line.Split('pts_time:')[1].Trim()
            }

            # y axis
            if ($line -match "^lavfi.astats.Overall.RMS_level=(?<rms>[-\d\.]+)") {
                $rmsText = $matches.rms
                IF ($rmsText -ne "-"){ $rmsValue = [double]$rmsText }else {$rmsValue = 0.0}
                $absRms = [math]::Abs($rmsValue)
                $diff=[double]($rmsprev - $rmsValue) # gradient is delta between two consecutive y points 
                # $category = if ($absRms -lt $threshold) { 'loud' } else { 'quiet' }
                
                $result.Add([PSCustomObject]@{
                    Frame = $thisFrame
                    pts = $pts
                    pts_time = $ptsTime
                    RMS = $rmsText
                    rmsa = $absRms
                    dif= $diff
                    tsA=$tsAvg
                    tsM=$tsMed
                    delete=$pdct1
                    cat = $category
                })
                $rmsprev=$rmsValue
                
                 # IF dB window less than -60 db threshold then speech
                $spWindow.Enqueue($rmsValue)
                if ($spWindow.Count -gt $windowSize) {
                    $null = $spWindow.Dequeue() 
                }
                $spMin = ($spWindow | Measure-Object -Minimum).Minimum
             
                # regression analysis of the gradient deltas
                $tsWindow.Enqueue($diff)
                if ($tsWindow.Count -gt $windowSize) {
                    $null = $tsWindow.Dequeue() 
                }
                $tsAvg = ($tsWindow | Measure-Object -Average).Average
                #$tsMin = ($TSWindow | Measure-Object -Minimum).Minimum
                #$tsMax = ($TSWindow | Measure-Object -Maximum).Maximum

                # Median of the average
                $tsAvW.Enqueue($tsAvg)  
                if ($tsAvW.Count -gt $windowSize) {
                    $null = $tsAvW.Dequeue() 
                }
                $tsMin = ($TSAvW | Measure-Object -Minimum).Minimum
                $tsMax = ($TSAvW | Measure-Object -Maximum).Maximum
                $tsMed = ([int]$tsMin + [int]$tsMax)/2
     
                # prediction 1
                # $pdct1 = if ($tsAvg -ge $threshold) { 1 } else { 0 }
                $pdct1 = if ($spMin -gt $speechLvl) { 1 } 
                     elseif ($tsMed -gt 0) { 1 } 
                    else { 0 }
             
                $category = if ($spMin -lt $speechLvl) { "speech" } 
                        elseif ($tsMed -gt 0) {  "comMed" }
                        else { "comElse" }
           
            }
        }
    }
    catch {
        $error[0]
        Write-Warning "Error processing frame $thisFrame  line: $_"
    }

    # show the Frame and RMS levels in a table
    if ($debug) {$result | Format-Table -Property Frame, RMS, rmsa, dif, tsA, tsM, pts, pts_time,delete ,cat -AutoSize}

    # export to csv
    $OutputCsv = $OutputCsv -replace '\.csv$', '.RMS.csv'
    $result | Export-Csv -LiteralPath "$dd\$OutputCsv" -NoTypeInformation
    
    Write-Host "Exported RMS CSV: $OutputCsv"
}


if (-not $InputFile) {
    throw "A file path is required to analyze RMS levels."
}

$inputPath = if ([System.IO.Path]::IsPathRooted($InputFile)) {
    $InputFile
} else {
    Join-Path $dd $InputFile
}

if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
    throw "Input file not found: $inputPath"
}

$logDirectory = if ([System.IO.Path]::IsPathRooted($logPath)) {
    $logPath
} else {
    Join-Path $dd $logPath
}
$null = New-Item -ItemType Directory -Path $logDirectory -Force
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
$logName = Join-Path $logDirectory ("{0}.rms.log" -f $baseName)
$logFileName = Split-Path -Leaf $logName

Write-Host "===== analyze RMS  $inputPath       ==============================================" -BackgroundColor Blue
Write-Host "===== analyze RMS -analyzeLog $logName -OutputCsv $OutputCsv" -BackgroundColor Blue
Push-Location -LiteralPath $logDirectory
try {
    getRMS -fName $inputPath -logName $logFileName
}
finally {
    Pop-Location
}
analyzeRMS -fName $inputPath -logName $logName -OutputCsv $OutputCsv




