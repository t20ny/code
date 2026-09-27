param(
    [string]$inputDir = 'F:\av\audio\downloads',
    [string]$OutputDir = 'F:\av\audio\done',
    [string]$logPath = 'logs',    
    [string]$InputFile = 'THE SECRET WAR FOR THE CONTROL OF HORMUZ WHO IS WINNING w Tanker Trackers Founder.20609.mp3',
    [string]$OutputCsv = 'rms.csv'
)
$debug=1
[int]$attemps=1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$logName="test.log"

$speechLvl=-60   # if rms level below Lvl then this window is speech   v1=-60
$windowSize=200  # Theil–Sen regression window 38 frames per second so v1=200 about 5 seconds

$speechLvl=-50   # if rms level below Lvl then this window is speech   v2=-50
$windowSize=240  # Theil–Sen regression window 38 frames per second so v2=240 about 6 seconds


function getRMS {
    param(
        [string]$fName,
        [string]$logName
    )
    write-host "fName   =  $fName"
    # write-host "get RMS $logName"
   
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
        # & ffmpeg @args4                        ## echos result on Terminal.
        # & ffmpeg @args4  | Out-Null              ## out-null  
        & ffmpeg @args4  2> "RMSerrors.log"         ## log error supresses Terminal   
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

    Write-Host "RMS log =  $logName"

}


function analyzeRMS {
    param(
        [string]$fName,
        [string]$logName,
        [string]$OutputCsv
    )
    
    $tsAvg=0
    $tsMed=0.005 # Theil–Sen gradient Median
    $tsMin=0
    $tsMax=1
    $spMin=0 # sound pressure mininum
    
    $TSWindow = [System.Collections.Generic.Queue[double]]::new()
    $spWindow = [System.Collections.Generic.Queue[double]]::new()
    $TSAvW = [System.Collections.Generic.Queue[double]]::new()
    $category="commercial"
    $pdct1 = 1      # predict commercial is true=1   
    $threshold=27   # if rms average of TSwindow is below threshold  v1=23

    $result = [System.Collections.Generic.List[object]]::new()
    $thisFrame = 0
    $pts = '0'
    $ptsTime = '0'
    $rmsprev=0

    if ($debug){  # write-host "fName      $fName"
        write-host "reading =  $logName"
        write-host "predics =  $speechLvl dB mininum over $windowSize frames is a commercial for deletion"
    }
    
    try {
        foreach ($line in Get-Content -LiteralPath $logName) {
            
            # x axis
            if ($line -match "frame:(?<frame>\d+)") { 
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
                    delet2=[int]$pdct1
                    minute=[int]($ptsTime/60)
                    tsM1=$tsMin
                    tsM2=$tsMax
                    spMin=$spMin
                })
                $rmsprev=$rmsValue
                
                 # IF dB window less than -mininum db threshold then speech
                $spWindow.Enqueue($rmsValue)
                if ($spWindow.Count -gt $windowSize) {
                    $null = $spWindow.Dequeue() 
                }
                $spMin = ($spWindow | Measure-Object -Minimum).Minimum
             
                # regression analysis of the gradient deltas
                # $tsWindow.Enqueue($diff)
                $tsWindow.Enqueue([math]::Abs($diff))   # absolute values of the gradients
                if ($tsWindow.Count -gt $windowSize) {
                    $null = $tsWindow.Dequeue() 
                }
                $tsAvg = ($tsWindow | Measure-Object -Average).Average
                $tsMin = ($TSWindow | Measure-Object -Minimum).Minimum
                $tsMax = ($TSWindow | Measure-Object -Maximum).Maximum

                # Median of the average
              
                #$tsAvW.Enqueue($tsAvg)  
                #if ($tsAvW.Count -gt $windowSize) {  $null = $tsAvW.Dequeue()    }
                #$tsMin = ($TSAvW | Measure-Object -Minimum).Minimum
                #$tsMax = ($TSAvW | Measure-Object -Maximum).Maximum

                $tsMed = ([double]$tsMin + [double]$tsMax)/2
     
                # prediction 1
                # $pdct1 = if ($tsAvg -ge $threshold) { 1 } else { 0 }
                $pdct1 = if ($spMin -lt $speechLvl) { 0 } 
                     elseif ($tsAvg -gt 0.001) { 1 } 
                    else { 0 }
             
                $category = if ($spMin -lt $speechLvl) { "speech" } 
                        elseif ($tsMed -gt 10) {  "comMed" }
                        else { "comElse" }
           
            }
        }
    }
    catch {
        $error[0]
        Write-Warning "Error processing frame $thisFrame  line= $_"
    }

    # show the Frame and RMS levels in a table
    # if ($debug) {$result | Format-Table -Property Frame, RMS, rmsa, dif, tsA, tsM, pts, pts_time,delete ,cat -AutoSize}

    # export to csv
    # $OutputCsv = $OutputCsv -replace '\.csv$', '.RMS.csv'
    $result | Export-Csv -LiteralPath "$inputDir\$OutputCsv" -NoTypeInformation
    Copy-Item "$inputDir\$OutputCsv" "$OutputDir\rms.csv" # copy for spectrum.xlsx visualisations
    Write-Host "Exported= $OutputCsv"

    # Show the sum of delet2 values for each minute 
    if ($debug) {
        $minuteHistogram = @(
            $result |
            Group-Object -Property minute |
            ForEach-Object {
                $frameCount = $_.Count
                $commercialFrames = [int](($_.Group | Measure-Object -Property delet2 -Sum).Sum)
                $commercialPercent = if ($frameCount -gt 0) {
                    [math]::Round(100 * $commercialFrames / $frameCount, 1)
                } else {
                    0
                }
                [PSCustomObject]@{
                    minute = [int]$_.Name
                    frames = $frameCount
                    commercial = $commercialFrames
                    percent = $commercialPercent
                    histogram = ('#' * [math]::Round($commercialPercent / 10))
                }
            } |
            Sort-Object -Property minute
        )

        $minuteHistogram |
            Format-Table -Property minute, frames, commercial, percent, histogram -AutoSize |
            Out-Host

        $totalFrames = ($minuteHistogram | Measure-Object -Property frames -Sum).Sum
        $totalCommercial = ($minuteHistogram | Measure-Object -Property commercial -Sum).Sum
        $overallPercent = if ($totalFrames -gt 0) {
            [math]::Round(100 * $totalCommercial / $totalFrames, 1)
        } else {
            0
        }
        $commercialMinutes = @($minuteHistogram | Where-Object { $_.percent -ge 50 }).Count
        $speechMinutes = @($minuteHistogram | Where-Object { $_.percent -lt 50 }).Count
        if ($overallPercent -ge 70) {
            $conclusion = 'The recording is predominantly predicted commercial. Recommend +10db change on speech level threshold and retry'
            $script:speechLvl = $speechLvl + 10
            $attemps = 1
        } elseif ($overallPercent -le 30) {
            $conclusion = 'The recording is predominantly predicted speech.'
        } else {
            $conclusion = 'The recording is mixed; inspect the minute boundaries before trimming. Recommend changes +10db on speech level threshold and +40 on regression window size and then retry'
            $script:speechLvl = $speechLvl + 10
            $script:windowSize = $windowSize + 40
            $attemps = 1
        }

        Write-Host ('Summary= {0} analyzed minutes, {1} commercial, {2} speech.' -f $minuteHistogram.Count, $commercialMinutes, $speechMinutes)
        Write-Host ('Overall commercial score= {0}% ({1}/{2} frames).' -f $overallPercent, $totalCommercial, $totalFrames)
        Write-Host "Conclusion= $conclusion"

    }
    return [int]$attemps
}


if (-not $InputFile) {
    throw "A file path is required to analyze RMS levels."
}

$inputPath = if ([System.IO.Path]::IsPathRooted($InputFile)) {
    $InputFile
} else {
    Join-Path $inputDir $InputFile
}

if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
    throw "Input file not found= $inputPath"
}

$logDirectory = if ([System.IO.Path]::IsPathRooted($logPath)) {
    $logPath
} else {
    Join-Path $inputDir $logPath
}
$null = New-Item -ItemType Directory -Path $logDirectory -Force
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
$logName = Join-Path $logDirectory ("{0}.rms.log" -f $baseName)
$logFileName = Split-Path -Leaf $logName

Write-Host "========= analyze RMS       ==============================================" -BackgroundColor Blue
#if ($debug){Write-Host "===== analyze RMS $inputPath   -analyzeLog $logName -OutputCsv $OutputCsv" -BackgroundColor Blue}
Push-Location -LiteralPath $logDirectory
try {
  Write-Host "[1]====== get RMS  "
  if (test-path $logFileName){
    Write-Host "[1]====== Use the existing RMS file  $logFileName " -forgroundcolor yellow
  }
  else {
    Write-Host "[1]====== get RMS  "
    getRMS -fName $inputPath -logName $logFileName
  }
}
finally {
    Pop-Location
}

while ($attemps -ge 1) {
    $attemps--
    Write-Host "[2]====== analysing the data ...  "
    $attemps = [int](analyzeRMS -fName $inputPath -logName $logName -OutputCsv $OutputCsv)
    if ($speechLvl -gt -50){exit}
}

