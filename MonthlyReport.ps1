# Simple Monthly Report – Lightweight Version

$ReportPath = "C:\Reports"
$ReportFile = "$ReportPath\MonthlyReport.html"

if (!(Test-Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory | Out-Null
}

# --- 1. Disk Space ---
$Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
 Select-Object DeviceID,
 @{n="SizeGB";e={[math]::Round($_.Size/1GB,2)}},
 @{n="FreeGB";e={[math]::Round($_.FreeSpace/1GB,2)}},
 @{n="Free%";e={[math]::Round(($_.FreeSpace/$_.Size)*100,2)}}

# --- 2. CPU + Memory Snapshot ---
$CPU = Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average | Select-Object -ExpandProperty Average
$Mem = Get-CimInstance Win32_OperatingSystem
$UsedMemGB = [math]::Round((($Mem.TotalVisibleMemorySize - $Mem.FreePhysicalMemory) / 1MB),2)
$TotalMemGB = [math]::Round(($Mem.TotalVisibleMemorySize / 1MB),2)

$Perf = [PSCustomObject]@{
    CPU_LoadPercent = $CPU
    Memory_UsedGB = $UsedMemGB
    Memory_TotalGB = $TotalMemGB
}

# --- 3. Windows Update + Reboot Pending ---
$PendingReboot = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"


$WUInfo = [PSCustomObject]@{
    PendingReboot = $PendingReboot
}

# --- 4. SentinelOne / AV Status ---
$AV = Get-Service | Where-Object {$_.Name -like "Sentinel*" } |
      Select-Object Name, Status

# --- 5. Event Logs (Critical/Errors/Warnings – last 7 days) ---
$Events = Get-WinEvent -FilterHashtable @{
    LogName = @("System","Application")
    Level = @(1,2,3)     # Critical=1, Error=2, Warning=3
    StartTime = (Get-Date).AddDays(-7)
} |
Select-Object TimeCreated, LevelDisplayName, ProviderName, Id, Message

# --- 6. Critical Services Status ---
$CriticalServices = "Dnscache","NTDS","LanmanServer","W32Time","Spooler"
$SvcStatus = foreach ($svc in $CriticalServices) {
    Get-Service $svc -ErrorAction SilentlyContinue |
    Select-Object Name, Status
}

# --- 7. Basic Disk I/O Performance ---
$DiskIO = [PSCustomObject]@{
    ReadLatencyMs  = (Get-Counter "\PhysicalDisk(_Total)\Avg. Disk sec/Read").Countersamples.CookedValue * 1000
    WriteLatencyMs = (Get-Counter "\PhysicalDisk(_Total)\Avg. Disk sec/Write").Countersamples.CookedValue * 1000
    DiskQueue      = (Get-Counter "\PhysicalDisk(_Total)\Avg. Disk Queue Length").Countersamples.CookedValue
}

# --- Build Simple HTML ---
$HTML = @"
<h1>Simple Monthly Server Report – $env:COMPUTERNAME</h1>

<h2>1. Disk Space</h2>
$($Disks | ConvertTo-Html -Fragment)

<h2>2. CPU & Memory</h2>
$($Perf | ConvertTo-Html -Fragment)

<h2>3. Windows Update / Reboot Pending</h2>
$($WUInfo | ConvertTo-Html -Fragment)

<h2>4. SentinelOne / AV Status</h2>
$($AV | ConvertTo-Html -Fragment)

<h2>5. Event Logs (Critical, Errors, Warnings – Last 7 Days)</h2>
$($Events | ConvertTo-Html -Fragment)

<h2>6. Critical Services</h2>
$($SvcStatus | ConvertTo-Html -Fragment)

<h2>7. Disk I/O (Basic)</h2>
$($DiskIO | ConvertTo-Html -Fragment)
"@

$HTML | Out-File $ReportFile -Encoding utf8
Write-Output "Report generated: $ReportFile"
