#Requires -Version 5.1
<#
.SYNOPSIS
    Palworld RCON Client — Pure PowerShell, no external dependencies.
.DESCRIPTION
    Implements the Source RCON protocol over TCP.
    Can be used interactively or dot-sourced for scripting.
.PARAMETER Command
    If provided, sends a single command and exits (non-interactive).
.EXAMPLE
    # Interactive mode
    powershell -ExecutionPolicy Bypass -File scripts\rcon-client.ps1

    # Single command mode
    powershell -ExecutionPolicy Bypass -File scripts\rcon-client.ps1 -Command "ShowPlayers"
    powershell -ExecutionPolicy Bypass -File scripts\rcon-client.ps1 -Command "Save"
    powershell -ExecutionPolicy Bypass -File scripts\rcon-client.ps1 -Command "Broadcast Hello_World"

    # Dot-source for scripting
    . scripts\rcon-client.ps1
    Send-RconCommand "ShowPlayers"
#>
param(
    [string]$Command = ""
)

# Load config
. (Join-Path $PSScriptRoot "config-loader.ps1")
$_cfg = Get-ToolkitConfig

$RconServer   = "127.0.0.1"
$RconPort     = if ($_cfg -and $_cfg.rcon_port) { $_cfg.rcon_port } else { 25575 }
$RconPassword = if ($_cfg -and $_cfg.admin_password) { $_cfg.admin_password } else { "admin" }

$ErrorActionPreference = "Stop"

# ── RCON Packet ────────────────────────────────────────────────────────────────
class RconPacket {
    hidden [byte[]] $pktSize
    [byte[]] $PktId
    [byte[]] $PktCmdType
    [byte[]] $PktCmdPayload

    RconPacket([int]$Type, [string]$Cmd) {
        $enc = [System.Text.Encoding]::UTF8
        if ($Type -lt 0 -or $Type -gt 4) { throw "Invalid RCON type: $Type" }

        $this.PktId         = $enc.GetBytes(([guid]::NewGuid()).Guid.Split("-")[1])
        $this.PktCmdType    = [byte[]]::new(4)
        $this.PktCmdType[0] = [byte]$Type
        $this.PktCmdPayload = $enc.GetBytes($Cmd) + [byte]0x00
        $this.pktSize       = [BitConverter]::GetBytes($this.PktCmdPayload.Length + 9)
    }

    [byte[]] Construct() {
        return $this.pktSize + $this.PktId + $this.PktCmdType + $this.PktCmdPayload + [byte]0x00
    }
}

# ── RCON Client ────────────────────────────────────────────────────────────────
class RconClient {
    hidden [System.Net.Sockets.Socket] $_socket
    hidden [bool] $_authed
    [string] $Server
    [int]    $Port

    RconClient([string]$Server, [int]$Port) {
        $this.Server  = $Server
        $this.Port    = $Port
        $this._authed = $false
        $this._socket = [System.Net.Sockets.Socket]::new(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Stream,
            [System.Net.Sockets.ProtocolType]::TCP
        )
        $this._socket.Connect($Server, $Port)
    }

    Authenticate([string]$Password) {
        if ($this._authed) { throw "Already authenticated." }
        $pkt      = [RconPacket]::new(3, $Password)
        $response = $this._Send($pkt)
        # Auth failure: server returns 0xFFFFFFFF in bytes 4-7
        $isOK = (Compare-Object $response[4..7] @(0xFF, 0xFF, 0xFF, 0xFF)).Count -gt 0
        if ($isOK) {
            $this._authed = $true
        } else {
            throw "RCON authentication failed. Check AdminPassword."
        }
    }

    [string] SendCommand([string]$Cmd) {
        if (-not $this._socket.Connected) { throw "Socket disconnected." }
        if (-not $this._authed)           { throw "Not authenticated." }
        $pkt      = [RconPacket]::new(2, $Cmd)
        $response = $this._Send($pkt)
        if ($response.Length -le 12) { return "" }
        return [System.Text.Encoding]::UTF8.GetString($response[12..($response.Length - 1)]).TrimEnd([char]0)
    }

    Disconnect() {
        if ($this._socket.Connected) { $this._socket.Close() }
    }

    hidden [byte[]] _Send([RconPacket]$Packet) {
        $buf      = [byte[]]::new(4096)
        $this._socket.Send($Packet.Construct()) | Out-Null
        $received = $this._socket.Receive($buf)
        return $buf[0..($received - 1)]
    }
}

# ── Helper function (usable after dot-sourcing) ────────────────────────────────
function Send-RconCommand {
    param(
        [Parameter(Mandatory)][string]$Cmd,
        [string]$Server   = $RconServer,
        [int]   $Port     = $RconPort,
        [string]$Password = $RconPassword
    )
    $client = $null
    try {
        $client = [RconClient]::new($Server, $Port)
        $client.Authenticate($Password)
        $result = $client.SendCommand($Cmd)
        return $result
    } finally {
        if ($client) { $client.Disconnect() }
    }
}

# ── Entry point ────────────────────────────────────────────────────────────────
if ($Command -ne "") {
    # Single-command mode
    try {
        $result = Send-RconCommand -Cmd $Command
        Write-Host $result
    } catch {
        Write-Error "RCON error: $_"
        exit 1
    }
    exit 0
}

if ($MyInvocation.InvocationName -ne '.') {
    # Interactive mode
    Write-Host "Connecting to ${RconServer}:${RconPort}..." -ForegroundColor Cyan
    $client = $null
    try {
        $client = [RconClient]::new($RconServer, $RconPort)
        $client.Authenticate($RconPassword)
        Write-Host "Connected. Type commands below (no leading /). Type 'quit' to exit." -ForegroundColor Green
        Write-Host "Available commands: Info, ShowPlayers, Save, Broadcast <msg>, KickPlayer <id>, Shutdown <sec> <msg>" -ForegroundColor DarkGray
        while ($true) {
            Write-Host "> " -NoNewline -ForegroundColor White
            $cmd = $Host.UI.ReadLine()
            if ($cmd -eq 'quit' -or $cmd -eq 'exit') { break }
            if ([string]::IsNullOrWhiteSpace($cmd))  { continue }
            try {
                $out = $client.SendCommand($cmd)
                Write-Host $out -ForegroundColor Yellow
            } catch {
                Write-Host "Error: $_" -ForegroundColor Red
            }
        }
    } catch {
        Write-Error "Failed to connect: $_"
        exit 1
    } finally {
        if ($client) { $client.Disconnect() }
        Write-Host "Disconnected." -ForegroundColor Gray
    }
}
