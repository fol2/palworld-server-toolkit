# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Palworld Dedicated Server toolkit for Windows — a collection of PowerShell scripts, a web dashboard (Live Editor), a GUI monitor, and a UE4SS Lua mod for managing a Palworld dedicated server.

## Directory Structure

- `config.example.json` — Configuration template (copy to `config.json` and edit)
- `config.json` — Active configuration (git-ignored, contains passwords)
- `scripts/` — All PowerShell automation scripts
  - `config-loader.ps1` — Shared config.json loader (dot-source in other scripts)
  - `setup.ps1` — One-time setup (run as Administrator)
  - `startup.ps1` — Boot watchdog: update + start + crash detection loop
  - `daily-update.ps1` — Daily 04:00: stop + update + restart
  - `backup.ps1` — Hourly git commit SaveGames
  - `backup-robocopy.ps1` — Hourly robocopy snapshot (immune to git)
  - `safe-backup.ps1` — Manual pre-operation safety backup
  - `update-mods.ps1` — Auto-update UE4SS from GitHub
  - `monitor.ps1` — WinForms GUI dashboard
  - `rcon-client.ps1` — Pure PowerShell RCON client
  - `live-editor-server.ps1` — HTTP server for Live Editor web dashboard
  - `live-editor/www/` — Live Editor frontend (HTML/CSS/JS)
  - `live-editor/waypoints.json` — Saved teleport waypoints (CRUD via API)
- `mods/LiveEditor/` — UE4SS Lua mod (file-based IPC for admin commands, v2.0 — 22 command types)
- `server/` — Palworld server files (git-ignored, installed via SteamCMD)
- `steamcmd/` — SteamCMD installation (git-ignored)

## Common Commands

### Starting the Server
```batch
server\PalServer.exe
```
Or with command-line options:
```batch
server\Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe
```

### Updating the Server via SteamCMD
```batch
steamcmd\steamcmd.exe +force_install_dir "FULL_PATH\server" +login anonymous +app_update 2394010 validate +quit
```
**IMPORTANT:** `+force_install_dir` MUST come BEFORE `+login anonymous`.

## Configuration

All scripts read settings from `config.json` in the project root. See `config.example.json` for the template.

The active Palworld server configuration is at:
```
server\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini
```

Key settings include:
- `ServerName` — Display name of the server
- `ServerPassword` — Password required to join (empty = no password)
- `AdminPassword` — Password for admin commands and RCON/REST API
- `PublicPort` — Server port (default: 8211)
- `PublicIP` — Public IP or domain for the server
- `ServerPlayerMaxNum` — Maximum players (default: 32)
- `bIsMultiplay` — Must be `True` for multiplayer
- `RCONEnabled` / `RCONPort` — Remote console settings

## Network Ports

- **8211** (UDP) — Game server port
- **25575** (TCP) — RCON port (if enabled)
- **8212** (TCP) — REST API port (if enabled)
- **8213** (TCP) — Live Editor web dashboard (localhost only)

## Live Editor (Admin Dashboard)

The Live Editor is a localhost web dashboard (port 8213) that sends commands to the AdminCommands UE4SS mod via file-based IPC. It supports 22 command types:

### Command Reference (via LiveEditor Lua mod)

| Command Type | Mod Command | Parameters |
|---|---|---|
| `give_item` | `!give` / `!giveme` | target_player, item_id, quantity |
| `spawn_pal` | `!spawn` | pal_id, level |
| `give_exp` | `!exp` / `!giveexp` | target_player, amount |
| `fly_toggle` | `!fly` | enable (bool) |
| `goto_coords` | `!goto` | x, y, z |
| `bring_player` | `!bring` | target_player |
| `bring_all` | `!bringall` | (none) |
| `unstuck` | `!unstuck` | (none) |
| `set_time` | `!settime` | hour (0-23) |
| `get_time` | `!time` | (none, fire-and-forget) |
| `announce` | `!announce` | message |
| `slay_player` | `!slay` | target_player |
| `freeze_player` | `!freeze` | target_player |
| `unfreeze_player` | `!unfreeze` | target_player |
| `spectate` | `!spectate` | (none) |
| `kick_player` | `!kick` | target_player |
| `ban_player` | `!ban` | target_player, reason |
| `unban_player` | `!unban` | target_player |
| `get_pos` | `!getpos` | target_player (fire-and-forget) |
| `teleport_player` | `!goto` + `!bring` | target_player, x, y, z (compound) |
| `list_players` | (UE4SS API) | (none) |
| `echo` | (test) | message |

### Waypoint System

- Stored in `scripts/live-editor/waypoints.json`
- API: `GET /api/waypoints`, `POST /api/waypoints` (CRUD), `POST /api/waypoints/save-pos`
- Categories: boss, dungeon, town, base, resource, custom
- Save-pos uses REST API to read admin's current in-game coordinates

### Teleport Flows

- Admin to waypoint: `goto_coords` with waypoint x,y,z
- Admin to player: `goto_coords` with player's REST API coordinates
- Bring player to admin: `bring_player`
- Send player to waypoint: `teleport_player` (compound: goto + bring)
- Bring all: `bring_all`
- **Requirement:** Admin must be online in-game for teleport commands

---

## MANDATORY: Pre-Operation Safety Rules for Claude

**CRITICAL — follow these rules every session, no exceptions.**

### Before ANY file operation on SaveGames:

1. **Run safe-backup.ps1 first:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File "scripts\safe-backup.ps1" -Reason "describe why"
   ```
   If it exits with code 1, STOP and tell the user. Do not proceed.

2. **NEVER run `git checkout` on SaveGames files** without explicitly confirming with the user first and running safe-backup.ps1 beforehand. `git checkout` silently overwrites working files with no undo.

3. **NEVER run `git restore`, `git reset --hard`, or any destructive git command** on SaveGames without:
   - Confirming with the user
   - Running safe-backup.ps1 first

4. **Before any restore operation** (restoring from Palworld backup folder, copying files over current saves), always run safe-backup.ps1.

### Backup system overview:

| Layer | Script | Schedule | Location | Notes |
|---|---|---|---|---|
| Git backup | `backup.ps1` | Hourly | `SaveGames/.git` | Can be overwritten by git ops |
| Robocopy snapshots | `backup-robocopy.ps1` | Hourly | `backups/hourly/` | **Immune to git ops** |
| Pre-op safety | `safe-backup.ps1` | Manual | `backups/safe-backup/` | Run before every operation |
| Windows VSS | (OS-level) | Daily | Shadow storage | Explorer > Previous Versions |

### If saves are lost/corrupted, check in this order:
1. `backups/safe-backup/` — most recent pre-operation snapshot
2. `backups/hourly/` — hourly robocopy (48h rolling)
3. `server/Pal/Saved/SaveGames/.git` — git log
4. `server/Pal/Saved/SaveGames/0/{worldID}/backup/world/` — Palworld internal backups
5. Windows Previous Versions (VSS) via Explorer
