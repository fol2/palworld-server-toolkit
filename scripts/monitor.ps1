#Requires -Version 5.1
<#
.SYNOPSIS
    Palworld Server Monitor GUI
.DESCRIPTION
    WinForms dark-theme dashboard for monitoring and controlling the Palworld
    dedicated server without using the CLI.  Double-click Monitor.bat to open.
#>

# ── Self-elevation (required for watchdog process detection) ──────────────────
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe `
        -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Paths ──────────────────────────────────────────────────────────────────────
$script:Base            = Split-Path -Parent $PSScriptRoot
$script:PSPExe          = "$($script:Base)\tools\PalworldSavePal\PSP.exe"
$script:SrvExe          = "$($script:Base)\server\Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe"
$script:StartupSc       = "$($script:Base)\scripts\startup.ps1"
$script:SafeBackSc      = "$($script:Base)\scripts\safe-backup.ps1"
$script:PauseFlag       = "$($script:Base)\logs\pause-updates.flag"
$script:SaveDir         = "$($script:Base)\server\Pal\Saved\SaveGames"
$script:HourlyDir       = "$($script:Base)\backups\hourly"
$script:SnapDir         = "$($script:Base)\backups\safe-backup"
$script:LogDir          = "$($script:Base)\logs"
$script:ModDll          = "$($script:Base)\server\Pal\Binaries\Win64\dwmapi.dll"
$script:ModDllDisabled  = "$($script:Base)\server\Pal\Binaries\Win64\dwmapi.dll.disabled"
$script:ModDisabledFlag = "$($script:Base)\logs\mod-disabled.flag"
$script:LiveEditorSc    = "$($script:Base)\scripts\live-editor-server.ps1"

# ── Colours ───────────────────────────────────────────────────────────────────
$script:cBg     = [System.Drawing.ColorTranslator]::FromHtml("#1C1C1E")
$script:cText   = [System.Drawing.Color]::White
$script:cDim    = [System.Drawing.ColorTranslator]::FromHtml("#8E8E93")
$script:cGreen  = [System.Drawing.ColorTranslator]::FromHtml("#34C759")
$script:cRed    = [System.Drawing.ColorTranslator]::FromHtml("#FF3B30")
$script:cOrange = [System.Drawing.ColorTranslator]::FromHtml("#FF9500")
$script:cBlue   = [System.Drawing.ColorTranslator]::FromHtml("#5AC8FA")
$script:cBtn    = [System.Drawing.ColorTranslator]::FromHtml("#3A3A3C")
$script:cBtnBdr = [System.Drawing.ColorTranslator]::FromHtml("#555558")
$script:cBtnHov = [System.Drawing.ColorTranslator]::FromHtml("#4A4A4C")
$script:cConFg  = [System.Drawing.ColorTranslator]::FromHtml("#A0A0A8")
$script:cConBg  = [System.Drawing.ColorTranslator]::FromHtml("#111113")

# ── Data helpers ──────────────────────────────────────────────────────────────
function Get-ServerProc {
    Get-Process -Name "PalServer-Win64-Shipping-Cmd" -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Get-WatchdogPid {
    try {
        $p = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*startup.ps1*" } |
            Select-Object -First 1
        if ($p) { return [int]$p.ProcessId }
    } catch {}
    return $null
}

function Get-LiveEditorPid {
    try {
        $p = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*live-editor-server.ps1*" } |
            Select-Object -First 1
        if ($p) { return [int]$p.ProcessId }
    } catch {}
    return $null
}

function Get-ModStatus {
    # Returns: "enabled", "disabled", "missing"
    if (Test-Path $script:ModDll)         { return "enabled"  }
    if (Test-Path $script:ModDllDisabled) { return "disabled" }
    return "missing"
}

function Get-LastGitCommit {
    try {
        $out = & git -C $script:SaveDir log -1 --format="%ci" 2>&1
        if ($out -and ($out -notmatch "^fatal") -and ($out -notmatch "^error")) {
            $str = $out.ToString().Trim()
            if ($str.Length -ge 19) {
                return ([datetime]::Parse($str.Substring(0, 19))).ToString("yyyy-MM-dd HH:mm")
            }
        }
    } catch {}
    return "-"
}

function Get-LastHourly {
    try {
        if (Test-Path $script:HourlyDir) {
            $d = Get-ChildItem $script:HourlyDir -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
            if ($d) {
                try {
                    $dt = [datetime]::ParseExact($d.Name, 'yyyy-MM-dd_HH-mm', $null)
                    return $dt.ToString("yyyy-MM-dd HH:mm")
                } catch {
                    return $d.Name
                }
            }
        }
    } catch {}
    return "-"
}

function Get-SnapCount {
    try {
        if (Test-Path $script:SnapDir) {
            return (Get-ChildItem $script:SnapDir -Directory -ErrorAction SilentlyContinue |
                Measure-Object).Count
        }
    } catch {}
    return 0
}

function Get-LogTail {
    try {
        $f = Get-ChildItem $script:LogDir -Filter "startup-*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) {
            $lines = Get-Content $f.FullName -Tail 5 -ErrorAction SilentlyContinue
            if ($lines) { return $lines -join "`n" }
        }
    } catch {}
    return "(no startup log found)"
}

function Format-RAM($proc) {
    $mb = $proc.WorkingSet64 / 1MB
    if ($mb -ge 1024) { return "{0:F1} GB" -f ($mb / 1024) }
    return "{0:F0} MB" -f $mb
}

function Format-Uptime($proc) {
    $u = (Get-Date) - $proc.StartTime
    return "{0}:{1:D2}" -f [int]$u.TotalHours, $u.Minutes
}

# ── Build form ────────────────────────────────────────────────────────────────
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text            = "Palworld Monitor"
$form.ClientSize      = New-Object System.Drawing.Size(420, 660)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox     = $false
$form.BackColor       = $script:cBg
$form.ForeColor       = $script:cText
$form.Font            = New-Object System.Drawing.Font("Segoe UI", 9)

# ── Builder helpers ───────────────────────────────────────────────────────────
function New-GB($text, $x, $y, $w, $h) {
    $gb = New-Object System.Windows.Forms.GroupBox
    $gb.Text      = $text
    $gb.Location  = New-Object System.Drawing.Point($x, $y)
    $gb.Size      = New-Object System.Drawing.Size($w, $h)
    $gb.ForeColor = $script:cDim
    $gb.BackColor = $script:cBg
    $form.Controls.Add($gb)
    return $gb
}

function New-Lbl($parent, $text, $x, $y, $w, $h, $clr, $fnt) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = New-Object System.Drawing.Point($x, $y)
    $l.Size      = New-Object System.Drawing.Size($w, $h)
    $l.ForeColor = if ($clr) { $clr } else { $script:cText }
    $l.BackColor = [System.Drawing.Color]::Transparent
    if ($fnt) { $l.Font = $fnt }
    $parent.Controls.Add($l)
    return $l
}

function New-Btn($parent, $text, $x, $y, $w, $h) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $text
    $b.Location  = New-Object System.Drawing.Point($x, $y)
    $b.Size      = New-Object System.Drawing.Size($w, $h)
    $b.BackColor = $script:cBtn
    $b.ForeColor = $script:cText
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor        = $script:cBtnBdr
    $b.FlatAppearance.MouseOverBackColor = $script:cBtnHov
    $b.FlatAppearance.MouseDownBackColor = $script:cBg
    $parent.Controls.Add($b)
    return $b
}

$dotFont = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)

# ── SERVER GroupBox  (y=8, h=100) - expanded for mod status row ───────────────
$gbSrv       = New-GB "SERVER" 8 8 404 100
$dotSrv      = New-Lbl $gbSrv "●"       10  20  16  20  $script:cRed $dotFont
$lblSrvState = New-Lbl $gbSrv "STOPPED" 30  22  120 18  $script:cRed $null
$lblSrvPID   = New-Lbl $gbSrv ""        158 22  235 18  $script:cDim $null
$lblSrvRAM   = New-Lbl $gbSrv "RAM: -"  10  44  180 18  $script:cDim $null
$lblSrvUp    = New-Lbl $gbSrv "Uptime: -" 195 44 190 18 $script:cDim $null
$lblModSrv   = New-Lbl $gbSrv "Mod: -"  10  66  384 18  $script:cDim $null

# ── WATCHDOG GroupBox  (y=114, h=52) ─────────────────────────────────────────
$gbWd      = New-GB "WATCHDOG" 8 114 404 52
$dotWd     = New-Lbl $gbWd "●"       10  20  16  20  $script:cRed $null
$dotWd.Font = $dotFont
$lblWdState = New-Lbl $gbWd "STOPPED" 30  22  120 18  $script:cRed $null
$lblWdPID   = New-Lbl $gbWd ""        158 22  235 18  $script:cDim $null

# ── BACKUPS GroupBox  (y=172, h=80) ──────────────────────────────────────────
$gbBk     = New-GB "BACKUPS" 8 172 404 80
$lblBkGit = New-Lbl $gbBk "Git:         -" 10 20 385 18 $script:cDim $null
$lblBkRob = New-Lbl $gbBk "Robocopy:  -"   10 39 385 18 $script:cDim $null
$lblBkSnp = New-Lbl $gbBk "Snapshots: -"   10 58 385 18 $script:cDim $null

# ── CONTROLS GroupBox  (y=258, h=212) - expanded for restart row ──────────────
$gbCtl      = New-GB "CONTROLS" 8 258 404 212
$btnSrv     = New-Btn $gbCtl "▶  Start Server"   8   22  192 28
$btnWd      = New-Btn $gbCtl "▶  Start Watchdog" 204 22  192 28
$btnPause   = New-Btn $gbCtl "||  Pause Updates" 8   56  192 28
$btnBackup  = New-Btn $gbCtl "Safe Backup"       204 56  192 28
$btnRefresh = New-Btn $gbCtl "↻  Refresh"        8   90  192 28
$btnPSP     = New-Btn $gbCtl "PSP"              204  90  192 28
$btnLiveEdit = New-Btn $gbCtl "▶  Live Editor"     8  120  192 22
$lblLiveEdit = New-Lbl $gbCtl "STOPPED"          204  122  100 18  $script:cRed $null
$btnLiveOpen = New-Btn $gbCtl "Open"             308  120   88 22
$btnMod     = New-Btn $gbCtl "◉  Mod: -"          8  148  388 22
$btnRestart = New-Btn $gbCtl "↻  Restart All"     8  178  388 28
$btnRestart.ForeColor = $script:cOrange

# ── LOG GroupBox  (y=476, h=176) ─────────────────────────────────────────────
$gbLog = New-GB "LOG  (startup)" 8 476 404 176

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Location    = New-Object System.Drawing.Point(8, 18)
$rtbLog.Size        = New-Object System.Drawing.Size(388, 150)
$rtbLog.BackColor   = $script:cConBg
$rtbLog.ForeColor   = $script:cConFg
$rtbLog.Font        = New-Object System.Drawing.Font("Consolas", 8)
$rtbLog.ReadOnly    = $true
$rtbLog.ScrollBars  = "Vertical"
$rtbLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbLog.WordWrap    = $false
$gbLog.Controls.Add($rtbLog)

# ── Log colour-coding ─────────────────────────────────────────────────────────
function Set-LogText($rawText) {
    $rtbLog.Clear()
    foreach ($line in ($rawText -split "`n")) {
        $clr = $script:cConFg
        if     ($line -match '\[ERROR\]') { $clr = $script:cRed    }
        elseif ($line -match '\[WARN\]')  { $clr = $script:cOrange }
        elseif ($line -match '\[INFO\]')  { $clr = $script:cBlue   }

        $start = $rtbLog.TextLength
        $rtbLog.AppendText($line + "`n")
        $rtbLog.Select($start, $line.Length)
        $rtbLog.SelectionColor = $clr
    }
    $rtbLog.SelectionStart = $rtbLog.TextLength
    $rtbLog.ScrollToCaret()
}

# ── Update-UI ─────────────────────────────────────────────────────────────────
function Update-UI {
    # Server
    $srv = Get-ServerProc
    if ($srv) {
        $dotSrv.ForeColor      = $script:cGreen
        $lblSrvState.ForeColor = $script:cGreen
        $lblSrvState.Text      = "RUNNING"
        $lblSrvPID.Text        = "PID: $($srv.Id)"
        $lblSrvRAM.Text        = "RAM: $(Format-RAM $srv)"
        $lblSrvUp.Text         = "Uptime: $(Format-Uptime $srv)"
        $btnSrv.Text           = "■  Stop Server"
        $btnSrv.ForeColor      = $script:cRed
    } else {
        $dotSrv.ForeColor      = $script:cRed
        $lblSrvState.ForeColor = $script:cRed
        $lblSrvState.Text      = "STOPPED"
        $lblSrvPID.Text        = ""
        $lblSrvRAM.Text        = "RAM: -"
        $lblSrvUp.Text         = "Uptime: -"
        $btnSrv.Text           = "▶  Start Server"
        $btnSrv.ForeColor      = $script:cText
    }

    # Watchdog
    $wdPid = Get-WatchdogPid
    if ($wdPid) {
        $dotWd.ForeColor      = $script:cOrange
        $lblWdState.ForeColor = $script:cOrange
        $lblWdState.Text      = "RUNNING"
        $lblWdPID.Text        = "PID: $wdPid"
        $btnWd.Text           = "■  Stop Watchdog"
        $btnWd.ForeColor      = $script:cOrange
    } else {
        $dotWd.ForeColor      = $script:cRed
        $lblWdState.ForeColor = $script:cRed
        $lblWdState.Text      = "STOPPED"
        $lblWdPID.Text        = ""
        $btnWd.Text           = "▶  Start Watchdog"
        $btnWd.ForeColor      = $script:cText
    }

    # Backups
    $lblBkGit.Text = "Git:         $(Get-LastGitCommit)"
    $lblBkRob.Text = "Robocopy:  $(Get-LastHourly)"
    $lblBkSnp.Text = "Snapshots: $(Get-SnapCount) saved"

    # Pause flag
    if (Test-Path $script:PauseFlag) {
        $btnPause.Text      = "▶  Resume Updates"
        $btnPause.ForeColor = $script:cOrange
    } else {
        $btnPause.Text      = "||  Pause Updates"
        $btnPause.ForeColor = $script:cText
    }

    # Live Editor
    $lePid = Get-LiveEditorPid
    if ($lePid) {
        $lblLiveEdit.Text      = "PID: $lePid"
        $lblLiveEdit.ForeColor = $script:cGreen
        $btnLiveEdit.Text      = "■  Live Editor"
        $btnLiveEdit.ForeColor = $script:cGreen
        $btnLiveOpen.Enabled   = $true
    } else {
        $lblLiveEdit.Text      = "STOPPED"
        $lblLiveEdit.ForeColor = $script:cRed
        $btnLiveEdit.Text      = "▶  Live Editor"
        $btnLiveEdit.ForeColor = $script:cText
        $btnLiveOpen.Enabled   = $false
    }

    # Mod status
    $modStatus = Get-ModStatus
    switch ($modStatus) {
        "enabled" {
            $lblModSrv.Text      = "Mod: ENABLED  (UE4SS + Admin Commands)"
            $lblModSrv.ForeColor = $script:cGreen
            $btnMod.Text         = "◉  Mod: ON - Click to Disable"
            $btnMod.ForeColor    = $script:cDim
            $btnMod.Enabled      = $true
        }
        "disabled" {
            $reason = ""
            if (Test-Path $script:ModDisabledFlag) {
                $reason = "  (" + ((Get-Content $script:ModDisabledFlag -Raw -ErrorAction SilentlyContinue).Trim() -replace '^Auto-disabled at ', 'auto-disabled ') + ")"
            }
            $lblModSrv.Text      = "Mod: DISABLED$reason"
            $lblModSrv.ForeColor = $script:cOrange
            $btnMod.Text         = "◉  Mod: OFF - Click to Re-enable"
            $btnMod.ForeColor    = $script:cOrange
            $btnMod.Enabled      = $true
        }
        "missing" {
            $lblModSrv.Text      = "Mod: NOT INSTALLED  (dwmapi.dll not found)"
            $lblModSrv.ForeColor = $script:cDim
            $btnMod.Text         = "◉  Mod: Not Installed"
            $btnMod.ForeColor    = $script:cDim
            $btnMod.Enabled      = $false
        }
    }

    # Log tail
    Set-LogText (Get-LogTail)
}

# ── Button events ─────────────────────────────────────────────────────────────

$btnSrv.Add_Click({
    $s = Get-ServerProc
    if ($s) {
        # Currently running - stop it
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "Stop the Palworld server (PID $($s.Id))?`nAll players will be disconnected.",
            "Confirm Stop", "YesNo", "Warning")
        if ($ans -eq "Yes") {
            Stop-Process -Id $s.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 1000
            Update-UI
        }
    } else {
        # Currently stopped - start it
        if (-not (Test-Path $script:SrvExe)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Server executable not found:`n$($script:SrvExe)",
                "Palworld Monitor", "OK", "Error") | Out-Null
            return
        }
        $modStatus = Get-ModStatus
        if ($modStatus -eq "disabled") {
            [System.Windows.Forms.MessageBox]::Show(
                "Note: Mod is currently DISABLED (was auto-disabled after repeated crashes).`n`nServer will start without mod.`nUse 'Mod: OFF - Click to Re-enable' button to restore mod.",
                "Mod Disabled", "OK", "Information") | Out-Null
        }
        Start-Process -FilePath $script:SrvExe -ArgumentList "-publiclobby" -WindowStyle Hidden
        Start-Sleep -Milliseconds 2000
        Update-UI
    }
})

$btnWd.Add_Click({
    $wdPid = Get-WatchdogPid
    if ($wdPid) {
        # Currently running - stop it
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "Stop the watchdog (PID $wdPid)?`nThe server will no longer auto-restart if it crashes.",
            "Confirm Stop", "YesNo", "Warning")
        if ($ans -eq "Yes") {
            Stop-Process -Id $wdPid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            Update-UI
        }
    } else {
        # Currently stopped - start it
        Start-Process powershell.exe `
            -ArgumentList "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($script:StartupSc)`"" `
            -WindowStyle Hidden
        Start-Sleep -Milliseconds 1500
        Update-UI
    }
})

$btnPause.Add_Click({
    if (Test-Path $script:PauseFlag) {
        Remove-Item $script:PauseFlag -Force -ErrorAction SilentlyContinue
        $btnPause.Text      = "||  Pause Updates"
        $btnPause.ForeColor = $script:cText
    } else {
        "Updates paused at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
            Set-Content $script:PauseFlag -Encoding UTF8
        $btnPause.Text      = "▶  Resume Updates"
        $btnPause.ForeColor = $script:cOrange
    }
})

$btnBackup.Add_Click({
    Start-Process powershell.exe `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$($script:SafeBackSc)`" -Reason `"manual from monitor`""
})

$btnRefresh.Add_Click({ Update-UI })

$btnPSP.Add_Click({
    if (-not (Test-Path $script:PSPExe)) {
        [System.Windows.Forms.MessageBox]::Show(
            "PSP not found:`n$($script:PSPExe)",
            "Palworld Monitor", "OK", "Error") | Out-Null
        return
    }
    Start-Process -FilePath $script:PSPExe -WorkingDirectory (Split-Path -Parent $script:PSPExe)
})

$btnLiveEdit.Add_Click({
    $lePid = Get-LiveEditorPid
    if ($lePid) {
        # Running - stop it
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "Stop Live Editor server (PID $lePid)?",
            "Confirm Stop", "YesNo", "Warning")
        if ($ans -eq "Yes") {
            Stop-Process -Id $lePid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            Update-UI
        }
    } else {
        # Stopped - start it and open browser
        if (-not (Test-Path $script:LiveEditorSc)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Live Editor script not found:`n$($script:LiveEditorSc)",
                "Palworld Monitor", "OK", "Error") | Out-Null
            return
        }
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $script:LiveEditorSc -WindowStyle Hidden
        Start-Sleep -Seconds 2
        Start-Process "http://localhost:8213"
        Update-UI
    }
})

$btnLiveOpen.Add_Click({
    Start-Process "http://localhost:8213"
})

$btnMod.Add_Click({
    $modStatus = Get-ModStatus
    switch ($modStatus) {
        "enabled" {
            $ans = [System.Windows.Forms.MessageBox]::Show(
                "Disable the mod (UE4SS)?`n`ndwmapi.dll will be renamed to .disabled.`nThe server must be restarted for this to take effect.",
                "Disable Mod", "YesNo", "Warning")
            if ($ans -eq "Yes") {
                try {
                    if (Test-Path $script:ModDllDisabled) { Remove-Item $script:ModDllDisabled -Force }
                    Rename-Item -Path $script:ModDll -NewName "dwmapi.dll.disabled" -Force
                    "Manually disabled at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')." |
                        Set-Content $script:ModDisabledFlag -Encoding UTF8
                } catch {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Failed to disable mod:`n$_", "Error", "OK", "Error") | Out-Null
                }
                Update-UI
            }
        }
        "disabled" {
            $ans = [System.Windows.Forms.MessageBox]::Show(
                "Re-enable the mod (UE4SS)?`n`ndwmapi.dll.disabled will be renamed back to dwmapi.dll.`nRestart the server afterwards for the mod to load.",
                "Re-enable Mod", "YesNo", "Question")
            if ($ans -eq "Yes") {
                try {
                    Rename-Item -Path $script:ModDllDisabled -NewName "dwmapi.dll" -Force
                    Remove-Item $script:ModDisabledFlag -Force -ErrorAction SilentlyContinue
                } catch {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Failed to re-enable mod:`n$_", "Error", "OK", "Error") | Out-Null
                }
                Update-UI
            }
        }
    }
})

$btnRestart.Add_Click({
    $srv = Get-ServerProc
    $lePid = Get-LiveEditorPid
    $parts = @()
    if ($srv)   { $parts += "PalServer (PID $($srv.Id))" }
    if ($lePid) { $parts += "Live Editor (PID $lePid)" }
    if ($parts.Count -eq 0) {
        # Nothing running -- just start everything
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "No services are running. Start PalServer + Live Editor?",
            "Restart All", "YesNo", "Question")
        if ($ans -ne "Yes") { return }
    } else {
        $ans = [System.Windows.Forms.MessageBox]::Show(
            "This will restart ALL services:`n$($parts -join ', ')`n`nAll players will be disconnected. Continue?",
            "Restart All", "YesNo", "Warning")
        if ($ans -ne "Yes") { return }
    }

    $btnRestart.Enabled = $false
    $btnRestart.Text = "↻  Restarting..."
    $form.Refresh()

    # 1. Stop Live Editor
    if ($lePid) {
        Stop-Process -Id $lePid -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    # 2. Stop PalServer
    if ($srv) {
        Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
        # Wait for process to fully exit (up to 15s)
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 500
            if (-not (Get-ServerProc)) { break }
        }
    }

    Start-Sleep -Seconds 1

    # 3. Start PalServer
    if (-not (Test-Path $script:SrvExe)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Server executable not found:`n$($script:SrvExe)",
            "Error", "OK", "Error") | Out-Null
        $btnRestart.Enabled = $true
        $btnRestart.Text = "↻  Restart All"
        return
    }
    Start-Process -FilePath $script:SrvExe -ArgumentList "-publiclobby" -WindowStyle Hidden
    Start-Sleep -Seconds 3

    # 4. Start Live Editor
    if (Test-Path $script:LiveEditorSc) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $script:LiveEditorSc -WindowStyle Hidden
        Start-Sleep -Seconds 2
    }

    $btnRestart.Enabled = $true
    $btnRestart.Text = "↻  Restart All"
    Update-UI

    [System.Windows.Forms.MessageBox]::Show(
        "All services restarted.",
        "Restart All", "OK", "Information") | Out-Null
})

# ── 15-second auto-refresh timer ─────────────────────────────────────────────
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000
$timer.Add_Tick({ Update-UI })
$timer.Start()

# ── System tray icon ─────────────────────────────────────────────────────────
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Text    = "Palworld Monitor"
$trayIcon.Visible = $false
try {
    $trayIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:SrvExe)
} catch {
    $trayIcon.Icon = [System.Drawing.SystemIcons]::Application
}

$trayMenu  = New-Object System.Windows.Forms.ContextMenuStrip
$trayShow  = $trayMenu.Items.Add("Show Monitor")
$traySep   = $trayMenu.Items.Add("-")
$trayExit  = $trayMenu.Items.Add("Exit")
$trayMenu.BackColor = $script:cBtn
$trayMenu.ForeColor = $script:cText
foreach ($item in $trayMenu.Items) {
    if ($item -is [System.Windows.Forms.ToolStripMenuItem]) {
        $item.BackColor = $script:cBtn
        $item.ForeColor = $script:cText
    }
}
$trayIcon.ContextMenuStrip = $trayMenu

$script:exitApp = $false

# Minimize → hide to tray
$form.Add_Resize({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.Hide()
        $trayIcon.Visible = $true
        $trayIcon.ShowBalloonTip(2000, "Palworld Monitor", "Still running in the background.", [System.Windows.Forms.ToolTipIcon]::Info)
    }
})

# X button → tray (not exit)
$form.Add_FormClosing({
    if (-not $script:exitApp) {
        $_.Cancel = $true
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
    }
})

# Double-click tray icon → restore
$trayIcon.Add_DoubleClick({
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
    $trayIcon.Visible = $false
})

$trayShow.Add_Click({
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
    $trayIcon.Visible = $false
})

$trayExit.Add_Click({
    $script:exitApp = $true
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    $form.Close()
})

# ── Initial draw & run ────────────────────────────────────────────────────────
Update-UI
$form.Add_FormClosed({ $timer.Stop(); $timer.Dispose(); $trayIcon.Visible = $false; $trayIcon.Dispose() })
[System.Windows.Forms.Application]::Run($form)
