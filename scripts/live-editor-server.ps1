#Requires -Version 5.1
<#
.SYNOPSIS
    Palworld Live Editor - HTTP Server
.DESCRIPTION
    PowerShell HTTP server (HttpListener on :8213) that serves the Live Editor
    web dashboard and proxies commands to the UE4SS LiveEditor Lua mod via
    file-based IPC, plus RCON for player listing.
.NOTES
    Bind to localhost only - no external access.
    Start via LiveEditor.bat or Monitor GUI button.
#>
param(
    [int]$Port = 0
)

$ErrorActionPreference = "Stop"
$script:BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ProjectRoot = Split-Path -Parent $script:BaseDir

# Load config
. (Join-Path $script:BaseDir "config-loader.ps1")
$script:Config = Get-ToolkitConfig
if ($Port -eq 0) {
    $Port = if ($script:Config -and $script:Config.live_editor_port) { $script:Config.live_editor_port } else { 8213 }
}
$script:WwwDir = [System.IO.Path]::GetFullPath((Join-Path $script:BaseDir "live-editor\www"))
$script:IpcDir = Join-Path $script:BaseDir "live-editor"
$script:CmdFile = Join-Path $script:IpcDir "commands.json"
$script:RspFile = Join-Path $script:IpcDir "responses.json"
$script:WaypointsFile = Join-Path $script:IpcDir "waypoints.json"

# ── Dot-source RCON client ──────────────────────────────────────────────────────
. (Join-Path $script:BaseDir "rcon-client.ps1")

# ── Data caches ─────────────────────────────────────────────────────────────────
$script:ItemsCache = $null
$script:PalsCache = $null
$script:PalDbCache = $null

# ── REST API helper ──────────────────────────────────────────────────────────────

function Get-AdminPassword {
    # Try config.json first
    if ($script:Config -and $script:Config.admin_password) {
        return $script:Config.admin_password
    }
    # Fallback: read from PalWorldSettings.ini
    $iniPath = Join-Path $script:ProjectRoot "server\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini"
    if (Test-Path $iniPath) {
        $content = Get-Content $iniPath -Raw
        if ($content -match 'AdminPassword="([^"]*)"') {
            return $Matches[1]
        }
    }
    return "admin"
}

function Invoke-RestApi {
    param([string]$Endpoint)

    $password = Get-AdminPassword
    $pair = "admin:$password"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $b64 = [Convert]::ToBase64String($bytes)
    $headers = @{ Authorization = "Basic $b64" }

    # Try known URL path formats
    $basePaths = @(
        "http://localhost:8212/v1/api",
        "http://localhost:8212/api"
    )

    foreach ($base in $basePaths) {
        $url = "$base/$Endpoint"
        try {
            $result = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 3 -ErrorAction Stop
            return $result
        } catch {
            Write-Host "[LiveEditor] REST API $url failed: $_" -ForegroundColor DarkGray
        }
    }
    return $null
}

# ── Load item data ──────────────────────────────────────────────────────────────
function Load-Items {
    Write-Host "[LiveEditor] Loading item data..." -ForegroundColor Cyan
    $items = @{}

    # Source 1: PSP items.json (metadata)
    $pspItemsPath = Join-Path $script:ProjectRoot "tools\PalworldSavePal\data\json\items.json"
    $pspL10nPath  = Join-Path $script:ProjectRoot "tools\PalworldSavePal\data\json\l10n\en\items.json"

    if (Test-Path $pspItemsPath) {
        $pspItems = Get-Content $pspItemsPath -Raw | ConvertFrom-Json
        $pspL10n  = if (Test-Path $pspL10nPath) { Get-Content $pspL10nPath -Raw | ConvertFrom-Json } else { $null }

        foreach ($prop in $pspItems.PSObject.Properties) {
            $id = $prop.Name
            $meta = $prop.Value
            if ($meta.disabled) { continue }

            $name = $id
            if ($pspL10n -and $pspL10n.PSObject.Properties[$id]) {
                $name = $pspL10n.$id.localized_name
            }

            $items[$id] = @{
                id        = $id
                name      = $name
                group     = $meta.group
                rarity    = $meta.rarity
                max_stack = $meta.max_stack_count
                sort_id   = $meta.sort_id
            }
        }
        Write-Host "[LiveEditor]   PSP: $($items.Count) items loaded" -ForegroundColor DarkGray
    }

    # Source 2: AdminCommands itemdata.lua (fallback for any missing)
    $itemLuaPath = Join-Path $script:ProjectRoot "server\Pal\Binaries\Win64\ue4ss\Mods\AdminCommands\Scripts\enums\itemdata.lua"
    if (Test-Path $itemLuaPath) {
        $luaContent = Get-Content $itemLuaPath -Raw
        $added = 0
        foreach ($match in [regex]::Matches($luaContent, '(\w+)\s*=\s*"([^"]*)"')) {
            $id   = $match.Groups[1].Value
            $name = $match.Groups[2].Value
            if (-not $items.ContainsKey($id)) {
                $items[$id] = @{
                    id        = $id
                    name      = $name
                    group     = "Unknown"
                    rarity    = 0
                    max_stack = 9999
                    sort_id   = 99999
                }
                $added++
            }
        }
        Write-Host "[LiveEditor]   Lua fallback: $added additional items" -ForegroundColor DarkGray
    }

    # Convert to sorted array
    $script:ItemsCache = $items.Values | Sort-Object { $_.sort_id }, { $_.name } | ForEach-Object {
        [PSCustomObject]@{
            id        = $_.id
            name      = $_.name
            group     = $_.group
            rarity    = $_.rarity
            max_stack = $_.max_stack
        }
    }
    Write-Host "[LiveEditor]   Total: $($script:ItemsCache.Count) items" -ForegroundColor Green
}

# ── Load pal data ───────────────────────────────────────────────────────────────
function Load-Pals {
    Write-Host "[LiveEditor] Loading pal data..." -ForegroundColor Cyan
    $pals = @()
    $palLuaPath = Join-Path $script:ProjectRoot "server\Pal\Binaries\Win64\ue4ss\Mods\AdminCommands\Scripts\enums\paldata.lua"

    if (Test-Path $palLuaPath) {
        $luaContent = Get-Content $palLuaPath -Raw
        foreach ($match in [regex]::Matches($luaContent, '(\w+)\s*=\s*"([^"]*)"')) {
            $id   = $match.Groups[1].Value
            $name = $match.Groups[2].Value
            $isBoss = $id -match '^BOSS_' -or $id -match '^Boss_'
            $pals += [PSCustomObject]@{
                id      = $id
                name    = $name
                is_boss = $isBoss
            }
        }
    }

    $script:PalsCache = $pals | Sort-Object name
    Write-Host "[LiveEditor]   Total: $($script:PalsCache.Count) pals" -ForegroundColor Green
}

# ── Load PalDb (PSP reference data) ──────────────────────────────────────────────
function Load-PalDb {
    Write-Host "[LiveEditor] Loading PalDb reference data..." -ForegroundColor Cyan

    $pspPalsPath   = Join-Path $script:ProjectRoot "tools\PalworldSavePal\data\json\pals.json"
    $pspPalsL10n   = Join-Path $script:ProjectRoot "tools\PalworldSavePal\data\json\l10n\en\pals.json"
    $elementsPath  = Join-Path $script:ProjectRoot "tools\PalworldSavePal\data\json\elements.json"
    $elementsL10n  = Join-Path $script:ProjectRoot "tools\PalworldSavePal\data\json\l10n\en\elements.json"
    $workL10nPath  = Join-Path $script:ProjectRoot "tools\PalworldSavePal\data\json\l10n\en\work_suitability.json"

    if (-not (Test-Path $pspPalsPath)) {
        Write-Host "[LiveEditor]   PalDb: pals.json not found, skipping" -ForegroundColor Yellow
        return
    }

    $palsData  = Get-Content $pspPalsPath -Raw | ConvertFrom-Json
    $palsL10n  = if (Test-Path $pspPalsL10n)  { Get-Content $pspPalsL10n  -Raw | ConvertFrom-Json } else { $null }
    $elemData  = if (Test-Path $elementsPath)  { Get-Content $elementsPath  -Raw | ConvertFrom-Json } else { $null }
    $elemL10n  = if (Test-Path $elementsL10n)  { Get-Content $elementsL10n  -Raw | ConvertFrom-Json } else { $null }
    $workL10n  = if (Test-Path $workL10nPath)  { Get-Content $workL10nPath  -Raw | ConvertFrom-Json } else { $null }

    $result = @()
    foreach ($prop in $palsData.PSObject.Properties) {
        $id = $prop.Name
        $pal = $prop.Value

        # Only include actual pals that are enabled
        if (-not $pal.is_pal) { continue }
        if ($pal.disabled) { continue }

        # Localized name and description
        $name = $id
        $desc = $null
        if ($palsL10n -and $palsL10n.PSObject.Properties[$id]) {
            $l10n = $palsL10n.$id
            if ($l10n.localized_name) { $name = $l10n.localized_name }
            if ($l10n.description) { $desc = $l10n.description }
        }

        # Elements with colours and localized names
        $elements = @()
        if ($pal.element_types) {
            foreach ($et in $pal.element_types) {
                $color = "#888888"
                $eName = $et
                if ($elemData -and $elemData.PSObject.Properties[$et]) {
                    $color = $elemData.$et.color
                }
                if ($elemL10n -and $elemL10n.PSObject.Properties[$et]) {
                    $eName = $elemL10n.$et.localized_name
                }
                $elements += @{ id = $et; name = $eName; color = $color }
            }
        }

        # Work suitability (non-zero only)
        $work = @{}
        if ($pal.work_suitability) {
            foreach ($wp in $pal.work_suitability.PSObject.Properties) {
                if ($wp.Value -gt 0) {
                    $wName = $wp.Name
                    if ($workL10n -and $workL10n.PSObject.Properties[$wp.Name]) {
                        $wName = $workL10n.($wp.Name).localized_name
                    }
                    $work[$wName] = $wp.Value
                }
            }
        }

        $result += [PSCustomObject]@{
            id             = $id
            name           = $name
            description    = $desc
            elements       = $elements
            rarity         = $pal.rarity
            hp             = if ($pal.scaling) { $pal.scaling.hp }      else { $null }
            attack         = if ($pal.scaling) { $pal.scaling.attack }  else { $null }
            defense        = if ($pal.scaling) { $pal.scaling.defense } else { $null }
            work           = $work
            is_boss        = $pal.is_boss
            pal_deck_index = $pal.pal_deck_index
            food_amount    = $pal.food_amount
        }
    }

    $script:PalDbCache = $result | Sort-Object name
    Write-Host "[LiveEditor]   PalDb: $($script:PalDbCache.Count) pals loaded" -ForegroundColor Green
}

# ── Server status helpers ───────────────────────────────────────────────────────
function Get-ServerProc {
    Get-Process -Name "PalServer-Win64-Shipping-Cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-ModStatus {
    $dllPath = Join-Path $script:ProjectRoot "server\Pal\Binaries\Win64\dwmapi.dll"
    $disPath = "$dllPath.disabled"
    if (Test-Path $dllPath)     { return "enabled" }
    elseif (Test-Path $disPath) { return "disabled" }
    else                        { return "not_installed" }
}

function Get-WatchdogPid {
    $procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.CommandLine -and $p.CommandLine -match 'startup\.ps1') {
            return $p.ProcessId
        }
    }
    return $null
}

# ── IPC with Lua mod ────────────────────────────────────────────────────────────
function Send-ModCommand {
    param(
        [string]$Id,
        [string]$Type,
        [hashtable]$Params = @{}
    )

    $cmd = @{
        id        = $Id
        type      = $Type
        params    = $Params
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json -Depth 4

    # Clear any stale response
    if (Test-Path $script:RspFile) { Remove-Item $script:RspFile -Force }

    # Write command (atomic: write .tmp then rename)
    $tmpFile = "$($script:CmdFile).tmp"
    [System.IO.File]::WriteAllText($tmpFile, $cmd, [System.Text.Encoding]::UTF8)
    if (Test-Path $script:CmdFile) { Remove-Item $script:CmdFile -Force }
    Rename-Item $tmpFile (Split-Path $script:CmdFile -Leaf)

    # Poll for response (5s timeout, check every 200ms)
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $script:RspFile) {
            Start-Sleep -Milliseconds 50  # small settle delay
            try {
                $rspContent = [System.IO.File]::ReadAllText($script:RspFile, [System.Text.Encoding]::UTF8)
                $rsp = $rspContent | ConvertFrom-Json
                Remove-Item $script:RspFile -Force -ErrorAction SilentlyContinue
                return $rsp
            } catch {
                # File might be mid-write, retry
            }
        }
        Start-Sleep -Milliseconds 200
    }

    # Clean up stale command file on timeout
    Remove-Item $script:CmdFile -Force -ErrorAction SilentlyContinue
    return @{ id = $Id; success = $false; message = "Timeout - mod did not respond within 5s. Is the server running with LiveEditor mod?" }
}

# ── MIME types ──────────────────────────────────────────────────────────────────
$script:MimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
}

# ── HTTP request handler ────────────────────────────────────────────────────────
function Handle-Request {
    param([System.Net.HttpListenerContext]$ctx)

    $req = $ctx.Request
    $rsp = $ctx.Response
    $path = $req.Url.AbsolutePath
    $method = $req.HttpMethod

    try {
        # ── API routes ──────────────────────────────────────────────────────
        if ($path -eq "/api/info" -and $method -eq "GET") {
            $serverName = "Palworld Server"
            if ($script:Config -and $script:Config.server_name) {
                $serverName = $script:Config.server_name
            }
            $body = @{ server_name = $serverName } | ConvertTo-Json
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/status" -and $method -eq "GET") {
            $proc = Get-ServerProc
            $srvPid    = $null
            $srvRam    = $null
            $srvUptime = $null
            if ($proc) {
                $srvPid = $proc.Id
                try { $srvRam    = [math]::Round($proc.WorkingSet64 / 1MB, 0) } catch {}
                try { $srvUptime = ((Get-Date) - $proc.StartTime).ToString("hh\:mm\:ss") } catch {}
            }
            $wdPid = $null
            try { $wdPid = Get-WatchdogPid } catch {}
            $body = @{
                server_running = ($null -ne $proc)
                server_pid     = $srvPid
                server_ram_mb  = $srvRam
                server_uptime  = $srvUptime
                mod_status     = (Get-ModStatus)
                watchdog_pid   = $wdPid
            } | ConvertTo-Json
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/players" -and $method -eq "GET") {
            $players = @()
            $source = "rcon"

            # Try REST API first (richer data: level, ping, location)
            try {
                $restResult = Invoke-RestApi -Endpoint "players"
                if ($restResult -and $restResult.PSObject.Properties['players']) {
                    $source = "rest_api"
                    foreach ($rp in $restResult.players) {
                        $players += @{
                            name        = $rp.name
                            accountName = $rp.account_name
                            playerId    = $rp.player_id
                            userId      = $rp.user_id
                            ping        = $rp.ping
                            location_x  = $rp.location_x
                            location_y  = $rp.location_y
                            level       = $rp.level
                        }
                    }
                }
            } catch {
                # REST API unavailable, fall through to RCON
            }

            # Fallback to RCON only if REST API was unavailable
            if ($source -eq "rcon") {
                try {
                    $result = Send-RconCommand -Cmd "ShowPlayers"
                    # Parse CSV: name,playeruid,steamid
                    foreach ($line in ($result -split "`n")) {
                        $line = $line.Trim()
                        if ($line -eq "" -or ($line -match '^name,')) { continue }
                        $parts = $line -split ","
                        if ($parts.Count -ge 3) {
                            $players += @{
                                name      = $parts[0].Trim()
                                playeruid = $parts[1].Trim()
                                steamid   = $parts[2].Trim()
                            }
                        }
                    }
                } catch {
                    # RCON failed - server might be down
                }
            }

            $body = @{ players = $players; source = $source } | ConvertTo-Json -Depth 3
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/items" -and $method -eq "GET") {
            $body = $script:ItemsCache | ConvertTo-Json -Depth 2
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/pals" -and $method -eq "GET") {
            $body = $script:PalsCache | ConvertTo-Json -Depth 2
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/paldb" -and $method -eq "GET") {
            if ($script:PalDbCache) {
                $body = $script:PalDbCache | ConvertTo-Json -Depth 4
            } else {
                $body = "[]"
            }
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/command" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $cmdData = $postBody | ConvertFrom-Json
            $cmdId = "cmd_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

            # Build params, only include non-null values
            $params = @{}
            @('target_player','item_id','quantity','pal_id','level','message',
              'amount','enable','x','y','z','hour','reason') | ForEach-Object {
                $val = $cmdData.$_
                if ($null -ne $val) { $params[$_] = $val }
            }

            $result = Send-ModCommand -Id $cmdId -Type $cmdData.type -Params $params

            $body = $result | ConvertTo-Json -Depth 3
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/rcon" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $cmdData = $postBody | ConvertFrom-Json
            $result = ""
            $success = $true
            try {
                $result = Send-RconCommand -Cmd $cmdData.command
            } catch {
                $result = "RCON error: $_"
                $success = $false
            }

            $body = @{
                success = $success
                result  = $result
            } | ConvertTo-Json
            Send-JsonResponse $rsp $body
            return
        }

        # ── Waypoints API ────────────────────────────────────────────────────
        if ($path -eq "/api/waypoints" -and $method -eq "GET") {
            if (Test-Path $script:WaypointsFile) {
                $body = [System.IO.File]::ReadAllText($script:WaypointsFile, [System.Text.Encoding]::UTF8)
            } else {
                $body = '{"waypoints":[]}'
            }
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/waypoints" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $reqData = $postBody | ConvertFrom-Json
            $action = $reqData.action

            # Load existing waypoints
            $wpData = if (Test-Path $script:WaypointsFile) {
                [System.IO.File]::ReadAllText($script:WaypointsFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            } else {
                @{ waypoints = @() }
            }

            $success = $true
            $msg = ""

            switch ($action) {
                "add" {
                    $wp = $reqData.waypoint
                    if (-not $wp -or -not $wp.name) {
                        $success = $false; $msg = "Missing waypoint data"
                    } else {
                        $newWp = @{
                            id       = if ($wp.id) { $wp.id } else { "wp_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
                            name     = $wp.name
                            x        = [double]$wp.x
                            y        = [double]$wp.y
                            z        = [double]$wp.z
                            category = if ($wp.category) { $wp.category } else { "custom" }
                            preset   = [bool]$wp.preset
                            created  = (Get-Date).ToString("yyyy-MM-dd")
                        }
                        $wpList = [System.Collections.ArrayList]@($wpData.waypoints)
                        $wpList.Add($newWp) | Out-Null
                        $wpData = @{ waypoints = $wpList.ToArray() }
                        $msg = "Waypoint added: $($newWp.name)"
                    }
                }
                "update" {
                    $wp = $reqData.waypoint
                    if (-not $wp -or -not $wp.id) {
                        $success = $false; $msg = "Missing waypoint id"
                    } else {
                        $wpList = [System.Collections.ArrayList]@($wpData.waypoints)
                        $found = $false
                        for ($i = 0; $i -lt $wpList.Count; $i++) {
                            if ($wpList[$i].id -eq $wp.id) {
                                $existing = $wpList[$i]
                                if ($wp.name)     { $existing.name     = $wp.name }
                                if ($null -ne $wp.x) { $existing.x    = [double]$wp.x }
                                if ($null -ne $wp.y) { $existing.y    = [double]$wp.y }
                                if ($null -ne $wp.z) { $existing.z    = [double]$wp.z }
                                if ($wp.category) { $existing.category = $wp.category }
                                $wpList[$i] = $existing
                                $found = $true
                                break
                            }
                        }
                        if ($found) {
                            $wpData = @{ waypoints = $wpList.ToArray() }
                            $msg = "Waypoint updated: $($wp.id)"
                        } else {
                            $success = $false; $msg = "Waypoint not found: $($wp.id)"
                        }
                    }
                }
                "delete" {
                    $wpId = $reqData.waypoint_id
                    if (-not $wpId) { $wpId = $reqData.waypoint.id }
                    if (-not $wpId) {
                        $success = $false; $msg = "Missing waypoint_id"
                    } else {
                        $wpList = @($wpData.waypoints | Where-Object { $_.id -ne $wpId })
                        $wpData = @{ waypoints = $wpList }
                        $msg = "Waypoint deleted: $wpId"
                    }
                }
                default {
                    $success = $false; $msg = "Unknown action: $action"
                }
            }

            if ($success) {
                $jsonOut = $wpData | ConvertTo-Json -Depth 4
                [System.IO.File]::WriteAllText($script:WaypointsFile, $jsonOut, [System.Text.Encoding]::UTF8)
            }

            $body = @{ success = $success; message = $msg } | ConvertTo-Json
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/waypoints/save-pos" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $reqData = $postBody | ConvertFrom-Json
            $wpName = $reqData.name
            $wpCategory = if ($reqData.category) { $reqData.category } else { "custom" }

            if (-not $wpName) {
                $body = @{ success = $false; message = "Missing waypoint name" } | ConvertTo-Json
                Send-JsonResponse $rsp $body
                return
            }

            # Get admin position from REST API
            $restResult = $null
            try {
                $restResult = Invoke-RestApi -Endpoint "players"
            } catch {}

            if (-not $restResult -or -not $restResult.PSObject.Properties['players']) {
                $body = @{ success = $false; message = "Cannot reach REST API to get player positions" } | ConvertTo-Json
                Send-JsonResponse $rsp $body
                return
            }

            # Find admin by UID from config
            $adminUid = $null
            if ($script:Config -and $script:Config.admin_uid) {
                $adminUid = $script:Config.admin_uid
            }

            $adminPlayer = $null
            foreach ($rp in $restResult.players) {
                if ($adminUid -and $rp.player_id -eq $adminUid) {
                    $adminPlayer = $rp
                    break
                }
            }
            # Fallback: use first player if admin not found by UID
            if (-not $adminPlayer -and $restResult.players.Count -gt 0) {
                $adminPlayer = $restResult.players[0]
            }

            if (-not $adminPlayer -or $null -eq $adminPlayer.location_x) {
                $body = @{ success = $false; message = "Admin player not found online or no location data" } | ConvertTo-Json
                Send-JsonResponse $rsp $body
                return
            }

            # Create waypoint from admin's position
            $newWp = @{
                id       = "wp_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                name     = $wpName
                x        = [double]$adminPlayer.location_x
                y        = [double]$adminPlayer.location_y
                z        = if ($null -ne $adminPlayer.location_z) { [double]$adminPlayer.location_z } else { 0 }
                category = $wpCategory
                preset   = $false
                created  = (Get-Date).ToString("yyyy-MM-dd")
            }

            # Load and append
            $wpData = if (Test-Path $script:WaypointsFile) {
                [System.IO.File]::ReadAllText($script:WaypointsFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            } else {
                @{ waypoints = @() }
            }
            $wpList = [System.Collections.ArrayList]@($wpData.waypoints)
            $wpList.Add($newWp) | Out-Null
            $wpData = @{ waypoints = $wpList.ToArray() }
            $jsonOut = $wpData | ConvertTo-Json -Depth 4
            [System.IO.File]::WriteAllText($script:WaypointsFile, $jsonOut, [System.Text.Encoding]::UTF8)

            $body = @{
                success  = $true
                message  = "Saved position as '$wpName'"
                waypoint = $newWp
            } | ConvertTo-Json -Depth 3
            Send-JsonResponse $rsp $body
            return
        }

        # ── Static file serving ─────────────────────────────────────────────
        if ($path -eq "/") { $path = "/index.html" }

        $filePath = Join-Path $script:WwwDir ($path.TrimStart("/").Replace("/", "\"))
        $filePath = [System.IO.Path]::GetFullPath($filePath)

        # Path traversal protection
        if (-not $filePath.StartsWith("$($script:WwwDir)\")) {
            $rsp.StatusCode = 403
            $rsp.Close()
            return
        }

        if (Test-Path $filePath) {
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $contentType = if ($script:MimeTypes.ContainsKey($ext)) { $script:MimeTypes[$ext] } else { "application/octet-stream" }
            $rsp.ContentType = $contentType

            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $rsp.ContentLength64 = $bytes.Length
            $rsp.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $rsp.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
            $rsp.OutputStream.Write($msg, 0, $msg.Length)
        }
    } catch {
        try {
            $rsp.StatusCode = 500
            $errMsg = [System.Text.Encoding]::UTF8.GetBytes("Internal Server Error: $_")
            $rsp.OutputStream.Write($errMsg, 0, $errMsg.Length)
        } catch {}
    } finally {
        try { $rsp.Close() } catch {}
    }
}

function Send-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$rsp,
        [string]$json
    )
    $rsp.ContentType = "application/json; charset=utf-8"
    $rsp.Headers.Add("Access-Control-Allow-Origin", "*")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $rsp.ContentLength64 = $bytes.Length
    $rsp.OutputStream.Write($bytes, 0, $bytes.Length)
    $rsp.Close()
}

# ── Main ────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  +==================================+" -ForegroundColor Cyan
Write-Host "  |   Palworld Live Editor Server    |" -ForegroundColor Cyan
Write-Host "  +==================================+" -ForegroundColor Cyan
Write-Host ""

# Load data
Load-Items
Load-Pals
Load-PalDb

# Ensure IPC directory exists
if (-not (Test-Path $script:IpcDir)) { New-Item -ItemType Directory -Path $script:IpcDir -Force | Out-Null }

# Start HTTP listener
$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "[LiveEditor] HTTP server listening on $prefix" -ForegroundColor Green
    Write-Host "[LiveEditor] Press Ctrl+C to stop." -ForegroundColor DarkGray
    Write-Host ""

    while ($listener.IsListening) {
        try {
            $ctx = $listener.GetContext()
            $reqPath = $ctx.Request.Url.AbsolutePath
            $reqMethod = $ctx.Request.HttpMethod
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $reqMethod $reqPath" -ForegroundColor DarkGray
            Handle-Request $ctx
        } catch [System.Net.HttpListenerException] {
            # Listener stopped
            break
        } catch {
            Write-Host "[LiveEditor] Request error: $_" -ForegroundColor Red
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-Host "[LiveEditor] Server stopped." -ForegroundColor Yellow
}
