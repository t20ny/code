 # unit test 1
 [string]$InputDir = 'F:\av\audio\downloads'
    [string]$OutputDir = 'F:\av\audio\done'
    
Set-Location "H:\data\dev\ai\audio"

# LATEST ONE ONLY
# .\'process_mp3_files.ps1' $InputDir $OutputDir -count 1


# ARRAY OF FILES
 $fileArray=@('WW 1000 Ensheepified - Patch Tuesday Shatters Vulnerability Fix Records.20193.mp3',
    'WW 999 Physical Goods - Acer SFF RTX Spark Desktop Design Showcased at IFA 2026.20194.mp3'
    )
# .\'process_mp3_files.ps1' $InputDir $OutputDir $fileArray


function trim {
   param($file)
    [string]$dd = 'F:\av\audio\downloads'
    [string]$logPath = "$InputDir\logs"
   # file mp3
    [string]$DeleteFile = "$file.csv"  # analysed rms levels result that show the sections to be deleted
    [string]$OutputFile = "$file.mp3"

    if (-not(test-path $logPath)){
      New-Item -Path $logPath -ItemType directory
    }
    .\'trim3.ps1' $InputDir $logpath "$file.mp3" $DeleteFile "$OutputDir\$OutputFile"
}
# trim 'BREAKING PENTAGON HID US TROOP DEATHS TRUMP BANS MAJOR NEWS OUTLETS w Col Larry Wilkerson.20268'
# trim 'US NEARLY STARTED WAR WITH CHINA AFTER AI GAVE FALSE INTEL DURING IRAN WAR w Malcolm Nance.20265'


$fileArray=@('3X HIROSHIMA TRUMPS 40000 BOMB SHIPMENT TO ISRAEL w Ana Kasparian.20277.mp3')
.\'process_mp3_files.ps1' $InputDir $OutputDir $fileArray
