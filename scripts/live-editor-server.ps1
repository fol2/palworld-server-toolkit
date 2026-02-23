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
$script:ActiveSkillsCache = $null
$script:PassiveSkillsCache = $null
$script:IconMap = @{}
$script:FullBodyMap = @{}
$script:IconDir = $null
$script:PartnerSkills = $null

# Lua mod response cache (3s TTL)
$script:LuaPlayersCache = $null
$script:LuaPlayersCacheTime = [datetime]::MinValue

# Discovery status cache (updated from Lua mod responses)
$script:LuaDiscoveryStatus = "unknown"
$script:LuaDiscoveryFound = $null
$script:LuaDiscoveryTotal = $null

# ── Icon mapping ────────────────────────────────────────────────────────────────
function Build-IconMap {
    Write-Host "[LiveEditor] Building icon mapping..." -ForegroundColor Cyan
    $script:IconDir = Join-Path $script:ProjectRoot "tools\PalworldSavePal\ui\_app\immutable\assets"
    if (-not (Test-Path $script:IconDir)) {
        Write-Host "[LiveEditor]   Icon directory not found, skipping" -ForegroundColor Yellow
        return
    }

    $files = Get-ChildItem -Path $script:IconDir -Filter "*.webp" -File
    foreach ($f in $files) {
        # Strip hash: t_alpaca_icon_normal.CSixLxRP.webp → t_alpaca_icon_normal
        $baseName = $f.Name -replace '\.[A-Za-z0-9_-]+\.webp$', ''
        if ($baseName -and -not $script:IconMap.ContainsKey($baseName)) {
            $script:IconMap[$baseName] = $f.Name
        }
        # Full-body images: files whose base name does NOT start with t_ and does NOT contain _icon_
        if ($baseName -and $baseName -notmatch '^t_' -and $baseName -notmatch '_icon_') {
            $lowerBase = $baseName.ToLower()
            if (-not $script:FullBodyMap.ContainsKey($lowerBase)) {
                $script:FullBodyMap[$lowerBase] = $f.Name
            }
        }
    }
    Write-Host "[LiveEditor]   Mapped $($script:IconMap.Count) icons, $($script:FullBodyMap.Count) full-body images" -ForegroundColor Green
}

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

            $desc = $null
            if ($pspL10n -and $pspL10n.PSObject.Properties[$id]) {
                $desc = $pspL10n.$id.description
            }

            # Build dynamic sub-object if present
            $dynObj = $null
            if ($meta.dynamic) {
                $dynObj = @{
                    type          = $meta.dynamic.type
                    durability    = $meta.dynamic.durability
                    magazine_size = $meta.dynamic.magazine_size
                    passive_skills = if ($meta.dynamic.passive_skills) { @($meta.dynamic.passive_skills) } else { @() }
                }
            }

            # Build effect sub-object if present
            $effectObj = $null
            if ($meta.effect) {
                $mods = @()
                if ($meta.effect.modifiers) {
                    foreach ($m in $meta.effect.modifiers) {
                        $mods += @{ type = $m.type; value = $m.value }
                    }
                }
                $effectObj = @{
                    duration  = $meta.effect.duration
                    modifiers = $mods
                }
            }

            $items[$id] = @{
                id                = $id
                name              = $name
                group             = $meta.group
                rarity            = $meta.rarity
                max_stack         = $meta.max_stack_count
                sort_id           = $meta.sort_id
                weight            = $meta.weight
                price             = $meta.price
                rank              = $meta.rank
                icon              = $meta.icon
                description       = $desc
                type_a            = $meta.type_a
                type_b            = $meta.type_b
                damage            = $meta.damage
                defense           = $meta.defense
                corruption_factor = $meta.corruption_factor
                dynamic           = $dynObj
                effect            = $effectObj
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
                    id          = $id
                    name        = $name
                    group       = "Unknown"
                    rarity      = 0
                    max_stack   = 9999
                    sort_id     = 99999
                    weight      = $null
                    price       = $null
                    rank        = $null
                    icon        = $null
                    description = $null
                }
                $added++
            }
        }
        Write-Host "[LiveEditor]   Lua fallback: $added additional items" -ForegroundColor DarkGray
    }

    # Convert to sorted array
    $script:ItemsCache = $items.Values | Sort-Object { $_.sort_id }, { $_.name } | ForEach-Object {
        [PSCustomObject]@{
            id                = $_.id
            name              = $_.name
            group             = $_.group
            rarity            = $_.rarity
            max_stack         = $_.max_stack
            weight            = $_.weight
            price             = $_.price
            rank              = $_.rank
            icon              = $_.icon
            description       = $_.description
            type_a            = $_.type_a
            type_b            = $_.type_b
            damage            = $_.damage
            defense           = $_.defense
            corruption_factor = $_.corruption_factor
            dynamic           = $_.dynamic
            effect            = $_.effect
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

    # Load partner skills data
    $partnerSkillsPath = Join-Path $script:ProjectRoot "data\partner_skills.json"
    $partnerSkillsData = $null
    if (Test-Path $partnerSkillsPath) {
        $partnerSkillsData = Get-Content $partnerSkillsPath -Raw | ConvertFrom-Json
        Write-Host "[LiveEditor]   Partner skills: loaded" -ForegroundColor DarkGray
    }

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

        # Skill set (convert PSObject to hashtable)
        $skillSet = @{}
        if ($pal.skill_set) {
            foreach ($sp in $pal.skill_set.PSObject.Properties) {
                $skillSet[$sp.Name] = $sp.Value
            }
        }

        # Full-body image lookup
        $bodyImage = $null
        $idLower = $id.ToLower()
        if ($script:FullBodyMap.ContainsKey($idLower)) {
            $bodyImage = $idLower
        }

        # Partner skill lookup
        $psName = $null
        $psDesc = $null
        if ($partnerSkillsData) {
            try {
                $ps = $partnerSkillsData.$id
                if ($ps) {
                    $psName = $ps.name
                    $psDesc = $ps.description
                }
            } catch { }
        }

        $result += [PSCustomObject]@{
            id                   = $id
            name                 = $name
            description          = $desc
            elements             = $elements
            rarity               = $pal.rarity
            hp                   = if ($pal.scaling) { $pal.scaling.hp }      else { $null }
            attack               = if ($pal.scaling) { $pal.scaling.attack }  else { $null }
            defense              = if ($pal.scaling) { $pal.scaling.defense } else { $null }
            work                 = $work
            is_boss              = $pal.is_boss
            pal_deck_index       = $pal.pal_deck_index
            food_amount          = $pal.food_amount
            icon                 = $pal.icon
            image                = $bodyImage
            size                 = $pal.size
            nocturnal            = $pal.nocturnal
            predator             = $pal.predator
            genus_category       = $pal.genus_category
            male_probability     = $pal.male_probability
            combi_rank           = $pal.combi_rank
            capture_rate_correct = $pal.capture_rate_correct
            run_speed            = $pal.run_speed
            ride_sprint_speed    = $pal.ride_sprint_speed
            max_full_stomach     = $pal.max_full_stomach
            stamina              = $pal.stamina
            skill_set            = $skillSet
            partner_skill_name   = if ($psName) { $psName } else { "" }
            partner_skill_desc   = if ($psDesc) { $psDesc } else { "" }
        }
    }

    $script:PalDbCache = $result | Sort-Object name
    Write-Host "[LiveEditor]   PalDb: $($script:PalDbCache.Count) pals loaded" -ForegroundColor Green
}

# ── Load skill reference data ──────────────────────────────────────────────────
function Load-Skills {
    Write-Host "[LiveEditor] Loading skill reference data..." -ForegroundColor Cyan

    $dataDir = Join-Path $script:ProjectRoot "tools\PalworldSavePal\data\json"

    # Active skills
    $activeSkillsPath = Join-Path $dataDir "active_skills.json"
    $activeSkillsL10n = Join-Path $dataDir "l10n\en\active_skills.json"

    if (Test-Path $activeSkillsPath) {
        $rawActive = Get-Content $activeSkillsPath -Raw | ConvertFrom-Json
        $l10nActive = if (Test-Path $activeSkillsL10n) { Get-Content $activeSkillsL10n -Raw | ConvertFrom-Json } else { $null }

        $activeList = @()
        foreach ($prop in $rawActive.PSObject.Properties) {
            $rawId = $prop.Name
            $skill = $prop.Value
            # Strip EPalWazaID:: prefix for matching with pal skill_set
            $cleanId = $rawId -replace '^EPalWazaID::', ''

            $name = $cleanId
            $desc = $null
            if ($l10nActive -and $l10nActive.PSObject.Properties[$rawId]) {
                $l10n = $l10nActive.$rawId
                if ($l10n.localized_name) { $name = $l10n.localized_name }
                if ($l10n.description) { $desc = $l10n.description }
            }

            $activeList += [PSCustomObject]@{
                id          = $cleanId
                raw_id      = $rawId
                name        = $name
                description = $desc
                element     = $skill.element
                power       = $skill.power
                cool_time   = $skill.cool_time
            }
        }
        $script:ActiveSkillsCache = $activeList
        Write-Host "[LiveEditor]   Active skills: $($activeList.Count)" -ForegroundColor DarkGray
    }

    # Passive skills
    $passiveSkillsPath = Join-Path $dataDir "passive_skills.json"
    $passiveSkillsL10n = Join-Path $dataDir "l10n\en\passive_skills.json"

    if (Test-Path $passiveSkillsPath) {
        $rawPassive = Get-Content $passiveSkillsPath -Raw | ConvertFrom-Json
        $l10nPassive = if (Test-Path $passiveSkillsL10n) { Get-Content $passiveSkillsL10n -Raw | ConvertFrom-Json } else { $null }

        $passiveList = @()
        foreach ($prop in $rawPassive.PSObject.Properties) {
            $id = $prop.Name
            $skill = $prop.Value
            if ($skill.disabled) { continue }

            $name = $id
            $desc = $null
            if ($l10nPassive -and $l10nPassive.PSObject.Properties[$id]) {
                $l10n = $l10nPassive.$id
                if ($l10n.localized_name) { $name = $l10n.localized_name }
                if ($l10n.description) { $desc = $l10n.description }
            }

            $passiveList += [PSCustomObject]@{
                id          = $id
                name        = $name
                description = $desc
                rank        = $skill.rank
            }
        }
        $script:PassiveSkillsCache = $passiveList
        Write-Host "[LiveEditor]   Passive skills: $($passiveList.Count)" -ForegroundColor DarkGray
    }

    Write-Host "[LiveEditor]   Skills loaded" -ForegroundColor Green
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
        [hashtable]$Params = @{},
        [int]$TimeoutSec = 5
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

    # Poll for response (configurable timeout, check every 200ms)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
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
    return @{ id = $Id; success = $false; message = "Timeout - mod did not respond within ${TimeoutSec}s. Is the server running with LiveEditor mod?" }
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
    ".webp" = "image/webp"
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
                            location_z  = $rp.location_z
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
            $body = $script:ItemsCache | ConvertTo-Json -Depth 5
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

        if ($path -eq "/api/active-skills" -and $method -eq "GET") {
            if ($script:ActiveSkillsCache) {
                $body = $script:ActiveSkillsCache | ConvertTo-Json -Depth 3
            } else {
                $body = "[]"
            }
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/passive-skills" -and $method -eq "GET") {
            if ($script:PassiveSkillsCache) {
                $body = $script:PassiveSkillsCache | ConvertTo-Json -Depth 3
            } else {
                $body = "[]"
            }
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -match '^/api/icon/(.+)$' -and $method -eq "GET") {
            $iconName = $Matches[1]
            if ($script:IconMap.ContainsKey($iconName) -and $script:IconDir) {
                $iconFile = Join-Path $script:IconDir $script:IconMap[$iconName]
                if (Test-Path $iconFile) {
                    $rsp.ContentType = "image/webp"
                    $rsp.Headers.Add("Cache-Control", "public, max-age=86400")
                    $bytes = [System.IO.File]::ReadAllBytes($iconFile)
                    $rsp.ContentLength64 = $bytes.Length
                    $rsp.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $rsp.StatusCode = 404
                    $msg = [System.Text.Encoding]::UTF8.GetBytes("Icon file not found")
                    $rsp.OutputStream.Write($msg, 0, $msg.Length)
                }
            } else {
                $rsp.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("Icon not mapped")
                $rsp.OutputStream.Write($msg, 0, $msg.Length)
            }
            $rsp.Close()
            return
        }

        if ($path -match '^/api/pal-image/(.+)$' -and $method -eq "GET") {
            $imgName = $Matches[1].ToLower()
            if ($script:FullBodyMap.ContainsKey($imgName) -and $script:IconDir) {
                $imgFile = Join-Path $script:IconDir $script:FullBodyMap[$imgName]
                if (Test-Path $imgFile) {
                    $rsp.ContentType = "image/webp"
                    $rsp.Headers.Add("Cache-Control", "public, max-age=86400")
                    $bytes = [System.IO.File]::ReadAllBytes($imgFile)
                    $rsp.ContentLength64 = $bytes.Length
                    $rsp.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $rsp.StatusCode = 404
                    $msg = [System.Text.Encoding]::UTF8.GetBytes("Image file not found")
                    $rsp.OutputStream.Write($msg, 0, $msg.Length)
                }
            } else {
                $rsp.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("Image not mapped")
                $rsp.OutputStream.Write($msg, 0, $msg.Length)
            }
            $rsp.Close()
            return
        }

        if ($path -eq "/api/dump" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $cmdData = $postBody | ConvertFrom-Json
            $cmdId = "dump_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

            # Forward all params from request body
            $params = @{}
            foreach ($prop in $cmdData.PSObject.Properties) {
                if ($null -ne $prop.Value) { $params[$prop.Name] = $prop.Value }
            }

            # Use extended timeout for dump commands (10s)
            $result = Send-ModCommand -Id $cmdId -Type "dump_properties" -Params $params -TimeoutSec 10

            $body = $result | ConvertTo-Json -Depth 5
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/dump-functions" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $cmdData = $postBody | ConvertFrom-Json
            $cmdId = "dumpfn_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

            $params = @{}
            foreach ($prop in $cmdData.PSObject.Properties) {
                if ($null -ne $prop.Value) { $params[$prop.Name] = $prop.Value }
            }

            $result = Send-ModCommand -Id $cmdId -Type "dump_functions" -Params $params -TimeoutSec 10

            $body = $result | ConvertTo-Json -Depth 6
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/generate-sdk" -and $method -eq "POST") {
            $cmdId = "gensdk_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $result = Send-ModCommand -Id $cmdId -Type "generate_sdk" -Params @{} -TimeoutSec 30

            $body = $result | ConvertTo-Json -Depth 3
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/probe" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $params = @{}
            if ($postBody -and $postBody.Trim() -ne "") {
                $cmdData = $postBody | ConvertFrom-Json
                if ($cmdData.force) { $params["force"] = $true }
            }

            $cmdId = "probe_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $result = Send-ModCommand -Id $cmdId -Type "probe_properties" -Params $params -TimeoutSec 15

            $body = $result | ConvertTo-Json -Depth 5
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/discovery-log" -and $method -eq "GET") {
            $logFile = Join-Path $script:IpcDir "discovery-log.json"
            if (Test-Path $logFile) {
                $body = Get-Content -Path $logFile -Raw -Encoding UTF8
                Send-JsonResponse $rsp $body
            } else {
                Send-JsonResponse $rsp '{"error":"No discovery log found. Run Probe first."}'
            }
            return
        }

        if ($path -eq "/api/command" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $cmdData = $postBody | ConvertFrom-Json
            $cmdId = "cmd_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

            # Build params — forward all body properties except 'type'
            $params = @{}
            foreach ($prop in $cmdData.PSObject.Properties) {
                if ($prop.Name -ne 'type' -and $null -ne $prop.Value) {
                    $params[$prop.Name] = $prop.Value
                }
            }

            $result = Send-ModCommand -Id $cmdId -Type $cmdData.type -Params $params

            $body = $result | ConvertTo-Json -Depth 3
            Send-JsonResponse $rsp $body
            return
        }

        # ── Live player data (Lua mod + REST merge) ────────────────────────
        if ($path -eq "/api/players/live" -and $method -eq "GET") {
            $luaPlayers = $null
            $luaSource = $false

            # Check cache (3s TTL)
            if ($script:LuaPlayersCache -and ((Get-Date) - $script:LuaPlayersCacheTime).TotalSeconds -lt 3) {
                $luaPlayers = $script:LuaPlayersCache
                $luaSource = $true
            } else {
                # Fetch from Lua mod
                $cmdId = "live_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                $luaResult = Send-ModCommand -Id $cmdId -Type "get_players_live" -TimeoutSec 5
                if ($luaResult -and $luaResult.success) {
                    try {
                        $parsed = $luaResult.message | ConvertFrom-Json
                        if ($parsed.players) {
                            $luaPlayers = $parsed.players
                            $script:LuaPlayersCache = $luaPlayers
                            $script:LuaPlayersCacheTime = Get-Date
                            $luaSource = $true
                            # Cache discovery status fields
                            $script:LuaDiscoveryStatus = if ($parsed.discovery) { $parsed.discovery } else { "unknown" }
                            $script:LuaDiscoveryFound = $parsed.discovery_found
                            $script:LuaDiscoveryTotal = $parsed.discovery_total
                        }
                    } catch {}
                }
            }

            # Fetch REST API data for ping/location
            $restPlayers = @()
            try {
                $restResult = Invoke-RestApi -Endpoint "players"
                if ($restResult -and $restResult.PSObject.Properties['players']) {
                    $restPlayers = $restResult.players
                }
            } catch {}

            # Merge: Lua data + REST data
            $merged = @()
            $source = "rcon"

            if ($luaSource -and $luaPlayers) {
                $source = "lua_mod"
                foreach ($lp in $luaPlayers) {
                    $entry = @{
                        name            = $lp.name
                        level           = $lp.level
                        hp_rate         = $lp.hp_rate
                        attack          = $lp.attack
                        defense         = $lp.defense
                        fullstomach     = $lp.fullstomach
                        max_fullstomach = $lp.max_fullstomach
                        sanity          = $lp.sanity
                        max_sanity      = $lp.max_sanity
                        party_count     = $lp.party_count
                    }
                    # Merge REST data (ping, location)
                    foreach ($rp in $restPlayers) {
                        if ($rp.name -eq $lp.name) {
                            $entry.ping       = $rp.ping
                            $entry.location_x  = $rp.location_x
                            $entry.location_y  = $rp.location_y
                            $entry.location_z  = $rp.location_z
                            $entry.playerId    = $rp.player_id
                            $entry.userId      = $rp.user_id
                            break
                        }
                    }
                    $merged += $entry
                }
            } elseif ($restPlayers.Count -gt 0) {
                $source = "rest_api"
                foreach ($rp in $restPlayers) {
                    $merged += @{
                        name        = $rp.name
                        level       = $rp.level
                        ping        = $rp.ping
                        location_x  = $rp.location_x
                        location_y  = $rp.location_y
                        location_z  = $rp.location_z
                        playerId    = $rp.player_id
                        userId      = $rp.user_id
                    }
                }
            } else {
                # Fallback to RCON
                try {
                    $result = Send-RconCommand -Cmd "ShowPlayers"
                    foreach ($line in ($result -split "`n")) {
                        $line = $line.Trim()
                        if ($line -eq "" -or ($line -match '^name,')) { continue }
                        $parts = $line -split ","
                        if ($parts.Count -ge 3) {
                            $merged += @{
                                name      = $parts[0].Trim()
                                playeruid = $parts[1].Trim()
                                steamid   = $parts[2].Trim()
                            }
                        }
                    }
                } catch {}
            }

            $body = @{
                players         = $merged
                source          = $source
                discovery       = $script:LuaDiscoveryStatus
                discovery_found = $script:LuaDiscoveryFound
                discovery_total = $script:LuaDiscoveryTotal
            } | ConvertTo-Json -Depth 3
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -match '^/api/player/([^/]+)$' -and $method -eq "GET") {
            $playerName = [System.Uri]::UnescapeDataString($Matches[1])
            $cmdId = "detail_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $luaResult = Send-ModCommand -Id $cmdId -Type "get_player_detail" -Params @{ target_player = $playerName } -TimeoutSec 8

            if ($luaResult -and $luaResult.success) {
                try {
                    $parsed = $luaResult.message | ConvertFrom-Json
                    $body = $parsed | ConvertTo-Json -Depth 5
                    Send-JsonResponse $rsp $body
                } catch {
                    $body = @{ success = $false; message = "Parse error: $_" } | ConvertTo-Json
                    Send-JsonResponse $rsp $body
                }
            } else {
                $body = @{ success = $false; message = if ($luaResult) { $luaResult.message } else { "No response" } } | ConvertTo-Json
                Send-JsonResponse $rsp $body
            }
            return
        }

        if ($path -match '^/api/player/([^/]+)/pals$' -and $method -eq "GET") {
            $playerName = [System.Uri]::UnescapeDataString($Matches[1])

            $cmdId = "pals_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $luaResult = Send-ModCommand -Id $cmdId -Type "get_player_pals" -Params @{
                target_player = $playerName
            } -TimeoutSec 8

            if ($luaResult -and $luaResult.success) {
                try {
                    $parsed = $luaResult.message | ConvertFrom-Json
                    $body = $parsed | ConvertTo-Json -Depth 5
                    Send-JsonResponse $rsp $body
                } catch {
                    $body = @{ success = $false; message = "Parse error: $_" } | ConvertTo-Json
                    Send-JsonResponse $rsp $body
                }
            } else {
                $body = @{ success = $false; message = if ($luaResult) { $luaResult.message } else { "No response" } } | ConvertTo-Json
                Send-JsonResponse $rsp $body
            }
            return
        }

        if ($path -match '^/api/player/([^/]+)/all-pals$' -and $method -eq "GET") {
            $playerName = [System.Uri]::UnescapeDataString($Matches[1])
            $qs = $req.QueryString
            $page = if ($qs["page"]) { [int]$qs["page"] } else { 0 }
            $pageSize = if ($qs["page_size"]) { [int]$qs["page_size"] } else { 30 }

            $cmdId = "allpals_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $luaResult = Send-ModCommand -Id $cmdId -Type "get_all_pals" -Params @{
                target_player = $playerName
                page = $page
                page_size = $pageSize
            } -TimeoutSec 10

            if ($luaResult -and $luaResult.success) {
                try {
                    $parsed = $luaResult.message | ConvertFrom-Json
                    $body = $parsed | ConvertTo-Json -Depth 5
                    Send-JsonResponse $rsp $body
                } catch {
                    $body = @{ success = $false; message = "Parse error: $_" } | ConvertTo-Json
                    Send-JsonResponse $rsp $body
                }
            } else {
                $body = @{ success = $false; message = if ($luaResult) { $luaResult.message } else { "No response" } } | ConvertTo-Json
                Send-JsonResponse $rsp $body
            }
            return
        }

        if ($path -match '^/api/player/([^/]+)/inventory$' -and $method -eq "GET") {
            $playerName = [System.Uri]::UnescapeDataString($Matches[1])

            $cmdId = "inv_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $luaResult = Send-ModCommand -Id $cmdId -Type "get_player_inventory" -Params @{
                target_player = $playerName
            } -TimeoutSec 8

            if ($luaResult -and $luaResult.success) {
                try {
                    $parsed = $luaResult.message | ConvertFrom-Json
                    $body = $parsed | ConvertTo-Json -Depth 5
                    Send-JsonResponse $rsp $body
                } catch {
                    $body = @{ success = $false; message = "Parse error: $_" } | ConvertTo-Json
                    Send-JsonResponse $rsp $body
                }
            } else {
                $body = @{ success = $false; message = if ($luaResult) { $luaResult.message } else { "No response" } } | ConvertTo-Json
                Send-JsonResponse $rsp $body
            }
            return
        }

        if ($path -match '^/api/player/([^/]+)/pal/edit$' -and $method -eq "POST") {
            $playerName = [System.Uri]::UnescapeDataString($Matches[1])
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $cmdData = $postBody | ConvertFrom-Json
            $cmdId = "paledit_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

            $params = @{ target_player = $playerName }
            foreach ($prop in $cmdData.PSObject.Properties) {
                if ($null -ne $prop.Value) { $params[$prop.Name] = $prop.Value }
            }

            $result = Send-ModCommand -Id $cmdId -Type "edit_pal" -Params $params -TimeoutSec 8

            $body = $result | ConvertTo-Json -Depth 3
            Send-JsonResponse $rsp $body
            return
        }

        if ($path -eq "/api/player/stats/edit" -and $method -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $postBody = $reader.ReadToEnd()
            $reader.Close()

            $cmdData = $postBody | ConvertFrom-Json
            $cmdId = "pstat_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

            $params = @{}
            foreach ($prop in $cmdData.PSObject.Properties) {
                if ($null -ne $prop.Value) { $params[$prop.Name] = $prop.Value }
            }

            $result = Send-ModCommand -Id $cmdId -Type "edit_player_stats" -Params $params -TimeoutSec 8

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

            # Get admin position — try Lua mod first (has X,Y,Z), fallback to REST API (X,Y only)
            $adminX = $null
            $adminY = $null
            $adminZ = $null
            $adminName = $null

            # Attempt 1: Lua mod — get_admin_location returns precise X,Y,Z from pawn
            $luaResult = Send-ModCommand -Id "savepos_$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())" -Type "get_admin_location" -TimeoutSec 3
            if ($luaResult -and $luaResult.success) {
                try {
                    $locData = $luaResult.message | ConvertFrom-Json
                    if ($null -ne $locData.x -and $null -ne $locData.y) {
                        $adminX = [double]$locData.x
                        $adminY = [double]$locData.y
                        $adminZ = if ($null -ne $locData.z) { [double]$locData.z } else { 0 }
                        $adminName = $locData.name
                        Write-Host "[save-pos] Got location from Lua mod: X=$adminX Y=$adminY Z=$adminZ"
                    }
                } catch {
                    Write-Host "[save-pos] Lua mod response parse error: $_"
                }
            }

            # Attempt 2: REST API fallback (no Z coordinate available)
            if ($null -eq $adminX) {
                $restResult = $null
                try {
                    $restResult = Invoke-RestApi -Endpoint "players"
                } catch {}

                if (-not $restResult -or -not $restResult.PSObject.Properties['players']) {
                    $body = @{ success = $false; message = "Cannot reach Lua mod or REST API to get player positions" } | ConvertTo-Json
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

                $adminX = [double]$adminPlayer.location_x
                $adminY = [double]$adminPlayer.location_y
                $adminZ = if ($null -ne $adminPlayer.location_z) { [double]$adminPlayer.location_z } else { 0 }
                Write-Host "[save-pos] Got location from REST API: X=$adminX Y=$adminY Z=$adminZ (Z may be 0)"
            }

            # Create waypoint from admin's position
            $newWp = @{
                id       = "wp_" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                name     = $wpName
                x        = $adminX
                y        = $adminY
                z        = $adminZ
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
            # Prevent browser caching for dev files (HTML/JS/CSS)
            if ($ext -in @(".html", ".js", ".css")) {
                $rsp.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
            }

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
Build-IconMap
Load-Items
Load-Pals
Load-PalDb
Load-Skills

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
