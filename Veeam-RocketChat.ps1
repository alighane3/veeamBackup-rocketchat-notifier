# =====================================================================
# Veeam Backup & Replication to Rocket.Chat Webhook Notification Script
# Compatible with Veeam B&R v11 & v12+
# =====================================================================

$WebhookUrl = "https://YOUR_ROCKETCHAT_DOMAIN/hooks/YOUR_TOKEN_HERE"

# Forcing PowerShell to Use TLS 1.2 to Prevent SSL Errors on Windows Server
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Loading the Veeam module (if required for older versions)
if (-not (Get-Module -ListAvailable -Name Veeam.Backup.PowerShell)) {
    Add-PSSnapin VeeamPSSnapin -ErrorAction SilentlyContinue
}

try {
    # Finding the Current Job via the Parent Process in Veeam
    $ParentPID = (Get-WmiObject Win32_Process -Filter "processid='$PID'").ParentProcessId
    $ParentCmd = (Get-WmiObject Win32_Process -Filter "processid='$ParentPID'").CommandLine

    $JobObject = $null
    if ($ParentCmd -match '\{[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}\}') {
        $JobId = $Matches[0]
        $JobObject = Get-VBRJob | Where-Object { $_.Id.ToString() -eq $JobId }
    }

      # Filtering sessions with a year less than 2040 and selecting the most recently executed job
    if (-not $JobObject) {
        $LastSession = Get-VBRBackupSession | Where-Object { $_.CreationTime.Year -lt 2040 } | Sort-Object CreationTime -Descending | Select-Object -First 1
    } else {
        $LastSession = Get-VBRBackupSession | Where-Object { $_.JobId -eq $JobObject.Id -and $_.CreationTime.Year -lt 2040 } | Sort-Object CreationTime -Descending | Select-Object -First 1
    }

    if (-not $LastSession) {
        throw "No Veeam Backup Session found."
    }

      # A brief pause to ensure the status of tasks is fully recorded in the Veeam database
    Start-Sleep -Seconds 5

    # Extracting the actual status from the Tasks (since the Session itself is still in a 'Working' state at the moment the script is executed)
    $TaskSessions = @(Get-VBRTaskSession -Session $LastSession)
    $FailedTasks = @($TaskSessions | Where-Object { $_.Status -eq 'Failed' })
    $WarningTasks = @($TaskSessions | Where-Object { $_.Status -eq 'Warning' })
    $SuccessTasks = @($TaskSessions | Where-Object { $_.Status -eq 'Success' })

    if ($FailedTasks.Count -gt 0) {
        $FinalStatus = "Failed"
        $Color = "#e74c3c" # Red
        $Emoji = "❌"
    } elseif ($WarningTasks.Count -gt 0) {
        $FinalStatus = "Warning"
        $Color = "#f39c12" # Orange
        $Emoji = "⚠️"
    } elseif ($TaskSessions.Count -eq 0 -and $LastSession.Result -eq 'Failed') {
        $FinalStatus = "Failed (Job Level)"
        $Color = "#e74c3c"
        $Emoji = "❌"
    } else {
        $FinalStatus = "Success"
        $Color = "#2ecc71" # Green
        $Emoji = "✅"
    }

    # Calculating Backup Time and Size
    $JobName = $LastSession.OrigJobName
    $ServerName = $env:COMPUTERNAME
    $StartTime = $LastSession.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
    $DurationSpan = (Get-Date) - $LastSession.CreationTime
    $Duration = "{0:D2}:{1:D2}:{2:D2}" -f $DurationSpan.Hours, $DurationSpan.Minutes, $DurationSpan.Seconds

    $TotalSizeGB = [math]::Round(($LastSession.BackupStats.DataSize / 1GB), 2)
    $TransferredGB = [math]::Round(($LastSession.Progress.TransferedSize / 1GB), 2)
    $DedupeRatio = $LastSession.BackupStats.DedupRatio
    $CompressRatio = $LastSession.BackupStats.CompressRatio

   # Collecting details of errors or warnings (if any)
    $DetailsText = ""
    if ($FailedTasks.Count -gt 0 -or $WarningTasks.Count -gt 0) {
        $ProblemTasks = $FailedTasks + $WarningTasks
        $DetailsList = foreach ($Task in $ProblemTasks) {
            $Reason = $Task.GetDetails() -replace '<br\s*/?>', ' - '
            if ([string]::IsNullOrWhiteSpace($Reason)) { $Reason = "Check Veeam Console for details." }
            "- **$($Task.Name)** ($($Task.Status)): $Reason"
        }
        $DetailsText = ($DetailsList -join "`n")
    } else {
        $DetailsText = "All $($SuccessTasks.Count) VM(s)/Task(s) processed successfully."
    }

    # Creating a Standard Payload for Rocket.Chat
    $Payload = @{
        username = "Veeam Backup ($ServerName)"
        text     = "$Emoji **Veeam Backup Report: $JobName**"
        attachments = @(
            @{
                color  = $Color
                fields = @(
                    @{ title = "Status"; value = $FinalStatus; short = $true },
                    @{ title = "Duration"; value = $Duration; short = $true },
                    @{ title = "Processed Size"; value = "$TotalSizeGB GB"; short = $true },
                    @{ title = "Transferred"; value = "$TransferredGB GB"; short = $true },
                    @{ title = "VM Summary"; value = "Success: $($SuccessTasks.Count) | Warning: $($WarningTasks.Count) | Failed: $($FailedTasks.Count)"; short = $false },
                    @{ title = "Details"; value = $DetailsText; short = $false }
                )
                footer = "Veeam B&R on $ServerName | Started: $StartTime"
            }
        )
    }

    # Convert to JSON with UTF-8 encoding and send to Rocket.Chat
    $JsonPayload = $Payload | ConvertTo-Json -Depth 6 -Compress
    $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonPayload)

    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $Utf8Bytes -ContentType "application/json; charset=utf-8" -ErrorAction Stop

} catch {
    # Log errors in the local log file if there is a problem executing the script.
    $ErrorMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Error: $($_.Exception.Message)"
    Add-Content -Path "$PSScriptRoot\Veeam-Webhook-Error.log" -Value $ErrorMsg
}