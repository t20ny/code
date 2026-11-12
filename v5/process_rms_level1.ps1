<# process RMS                                                          v2.1.5
-------------------------------------------------------------------------------------
    get RMS data points, analyse, mark delete sections                 
#>
param(
    [string]$inputDir = 'F:\av\audio\downloads',
    [string]$inputPath ="F:\av\audio\downloads",
    [string]$OutputDir = 'F:\av\audio\done',
    [string]$logPath = 'F:\av\audio\done\logs',    
    [string]$InputFile = '_source.mp3', 
    [string]$OutputCsv = '_rms.csv',
    $mode=1,
    $debug=0
)
Set-Location $inputDir
write-host $PSCommandPath -BackgroundColor cyan
[int]$attemps=2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$logName="_process_rms.log"


$speechLvl=-60   # if rms level below Lvl then this window is speech   v1=-60
$windowSize=200  # Theil–Sen regression window 38 frames per second so v1=200 about 5 seconds

$speechLvl=-50   # if rms level below Lvl then this window is speech   v2=-50
$windowSize=240  # Theil–Sen regression window 38 frames per second so v2=240 about 6 seconds

$speechLvl=-60   # if rms level below Lvl then this window is speech   v3=-50
$windowSize=160  # Theil–Sen regression window 38 frames per second so v3=120 about 3 seconds

function getRMS {
    param(
        [string]$fName,
        [string]$logName
    )
    IF ($DEBUG){
        write-host "fName   =  $fName"
        write-host "logName =  $logName"
    }
   # https://ffmpeg.org/ffmpeg-filters.html#Filtergraph-syntax-1
   # https://ffmpeg-cookbook.com/en/articles/astats/
   # metadata=1   astats attaches its statistics to every audio frame
   # reset=N      clears the statistics every N frames, not every N samples. (A decoded AAC frame holds 1024 samples.
   # "asetnsamples=n=44100,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-"
   # $a0= 'ffmpeg -i input.mp4 -af "astats=measure_perchannel=RMS_level+Peak_level:measure_overall=RMS_level+Peak_level" -f null /dev/null'
   # with metadata=1, astats attaches its statistics to every audio frame as metadata. Each value covers the audio from the start up to that frame;
   # use reset to get values for shorter intervals. The ametadata filter prints the values:
   # Segment-by-Segment Statistics (reset Parameter)
   $filter = "asetnsamples=n=8192,"
   $filter+= "astats=metadata=1:reset=1,"
   $FILTER+= "ametadata=print:key=lavfi.astats.Overall.RMS_level:file=$logName" #  verbose file output
  
   # $FILTER+= ",aspectralstats,ametadata=print:file=_spec.log " # hangs

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
        # & ffmpeg @args4  | Out-Null            ## out-null  
         $ffResult = & ffmpeg @args4  2> "_RMSerrors1.log"         ## log error supresses Terminal   
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
    if ($ffResult){
        Write-Host "ff result=  $ffResult"
    }
}


function analyzeRMS {
    param(
        [string]$fName,
        [string]$logName,
        [string]$OutputCsv
    )
    
    $spMin=0 # sound pressure mininum
    $spAvg=0

    $spWindow = [System.Collections.Generic.Queue[double]]::new()
    $category="commercial"
    $pdct1 = 1      # predict commercial is true=1   

    $result = [System.Collections.Generic.List[object]]::new()
    $thisFrame = 0
    $pts = '0'
    $ptsTime = '0'

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
                IF ($rmsText -ne "-"){ 
                    $rmsValue = [double]$rmsText 
                }else {
                    $rmsValue = 0.0
                    }
               $absRms = [math]::Abs($rmsValue)
          
                $result.Add([PSCustomObject]@{
                    Frame = $thisFrame
                    pts = $pts
                    pts_time = $ptsTime
                    RMS = $rmsText
                   rmsa = $absRms
                    delete=$pdct1
                    cat = $category
                    delet2=[int]$pdct1
                    minute=[int]($ptsTime/60)
                    spMin=$spMin
                    spAvg=$spAvg
                })
        
                 # IF dB window less than -mininum db threshold then speech
                $spWindow.Enqueue($rmsValue)
                if ($spWindow.Count -gt $windowSize) {
                    $null = $spWindow.Dequeue() 
                }
                $spMin = ($spWindow | Measure-Object -Minimum).Minimum
                $spAvg = ($spWindow | Measure-Object -Average).Average
     
                # prediction 1
                $pdct1 = if ($spMin -lt $speechLvl) { 0 } 
                     elseif ($spAvg -lt $speechLvl) { 0 } 
                       else { 1 }
             
                $category = if ($spMin -lt $speechLvl) { "speechSp" } 
                        elseif ($spAvg -lt $speechLvl) { "speechAvg" } 
                        else { "comElse" }
           
            }
        }
    }
    catch {
        $error[0]
        Write-Warning "Error processing frame $thisFrame  line= $_"
    }

    # show the Frame and RMS levels in a table
    if ($debug) {$result | Format-Table #-Property Frame, RMS, rmsa, dif, tsA, tsM, pts, pts_time,delete ,cat -AutoSize
        }

    # export to csv
    $result | Export-Csv -LiteralPath $ExportFile -NoTypeInformation
    Copy-Item $ExportFile "$LogDir\_rms.csv" # copy for spectrum.xlsx visualisations
    Write-Host "Exported=  $ExportFile"
    if ($debug){Write-Host "copied-->  $LogDir\_rms.csv" -ForegroundColor cyan}

    # Show the sum of delet2 values for each minute 
    $doAgain=0
    if ($debug -eq 0) {
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
        IF ($DEBUG){        # show result histogram     
            $minuteHistogram |
                Where-Object { $_.commercial -gt 10 } |
                Format-Table -Property minute, frames, commercial, percent, histogram -AutoSize |
                Out-Host 
        }
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
            $doAgain = 1
        } elseif ($overallPercent -le 30) {
            $conclusion = 'The recording is predominantly predicted speech.'
        } else {
            $conclusion = 'The recording is mixed; inspect the minute boundaries before trimming. Recommend changes +10db on speech level threshold and +40 on regression window size and then retry'
            $script:speechLvl = $speechLvl + 10
            $script:windowSize = $windowSize + 40
            $doAgain = 1
        }

        IF ($DEBUG){
        Write-Host ('Overall commercial score= {0}% ({1}/{2} frames).' -f $overallPercent, $totalCommercial, $totalFrames)
        Write-Host "Conclusion= $conclusion"
        }
       #Write-Host ('Summary= {0} analyzed minutes, {1} commercial, {2} speech. At speech level {3}db' -f $minuteHistogram.Count, $commercialMinutes, $speechMinutes,$speechLvl)
        Write-Host ('{3}db has  {0} minutes with {1} commercial, {2} speech.' -f $minuteHistogram.Count, $commercialMinutes, $speechMinutes,$speechLvl)
       # $doAgain
    }
    $Script:attemps=$doAgain
}


# MAIN ###################################################
# input file ---------------------------------------
if (-not $InputFile) {
    throw "A file path is required to analyze RMS levels."
}
elseif($debug) {
    write-host "InputFile: $InputFile" -ForegroundColor Yellow
}
$resolvedInputFile = if ([System.IO.Path]::IsPathRooted($InputFile)) {
    [System.IO.Path]::GetFullPath($InputFile)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $inputDir $InputFile))
}
if (-not (Test-Path -LiteralPath $resolvedInputFile -PathType Leaf)) {
    throw "Input file not found: $resolvedInputFile"
}
if (-not $InputPath) {
    $inputPath = if ([System.IO.Path]::IsPathRooted($InputFile)) {
        $InputFile
    } else {
        Join-Path $inputDir $InputFile
    }
}

# output file ---------------------------------------
if ($OutputCsv -notmatch "rms"){
    $OutputCsv =$OutputCsv -replace ".csv",".rms.csv"
}
#$ExportFile="$inputDir\$OutputCsv"
$ExportFile="$inputPath\$OutputCsv"
if ($debug) {}

# log file ---------------------------------------
$LogDir=$logpath
$logDir = if ([System.IO.Path]::IsPathRooted($logPath)) {
    $logPath
} else {
    Join-Path $inputDir $logPath
}
$null = New-Item -ItemType Directory -Path $logDir -Force
$baseName = [System.IO.Path]::GetFileNameWithoutExtension("$InputFile")
$logName = Join-Path $logDir ("{0}.rms.log" -f $baseName)
$RMSlog = Split-Path -Leaf $logName
Push-Location -LiteralPath $logDir

if ($debug){Write-Host "========= analyze RMS       ==============================================" -foregroundColor Blue}
if ($debug){Write-Host "analyze RMS  $InputFile   `n-analyzeLog  $logName " -foregroundColor Blue
            #Remove-Item $inputPath 
            if (test-path $RMSlog){Remove-Item $RMSlog}
            write-host "ExportFile $ExportFile " -ForegroundColor Yellow
}

try {
  if (test-path $RMSlog){
    Write-Host "[1]==== = Use the existing RMS log  $RMSlog " -foregroundcolor yellow
  }
  else {
    Write-Host "[1]==== = get RMS  "
  # getRMS -fName $inputPath -logName $RMSlog
    getRMS -fName $resolvedInputFile -logName $RMSlog
  }
}
finally {
    Pop-Location
}

while ($attemps -ge 1) {
    $attemps--
    if ($debug){Write-Host "[2]==== = analysing the data ($attemps attemps)  "}
    try {
     analyzeRMS -fName $inputPath -logName $logName -OutputCsv $OutputCsv
    }
    catch {
        $error[0]
    }
    if ($speechLvl -ge -30){exit}
}
