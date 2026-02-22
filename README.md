# Palworld Server Toolkit

A comprehensive suite of PowerShell scripts, a web-based admin dashboard, a GUI monitor, and a UE4SS Lua mod for managing a Palworld Dedicated Server on Windows.

## Features

- **GUI Monitor** — Dark-theme WinForms dashboard showing server status, watchdog state, mod status, backup info, and live log tailing
- **Live Editor** — Web-based admin dashboard for giving items, spawning pals, managing players, with a searchable pal database and RCON console
- **Watchdog** — Crash detection with auto-restart, mod crash auto-disable (disables UE4SS after consecutive fast crashes)
- **Auto-Updates** — Server updates via SteamCMD, UE4SS mod updates via GitHub API, with pause flag support
- **Multi-Layer Backup** — Git commits, robocopy snapshots, VSS shadow copies, and manual safety backups
- **RCON Client** — Pure PowerShell implementation of the Source RCON protocol, no external dependencies
- **LiveEditor Mod** — UE4SS Lua mod providing file-based IPC for admin commands (give items, spawn pals)

## Requirements

- Windows 10/11 or Windows Server 2019+
- PowerShell 5.1+ (included with Windows)
- [Git for Windows](https://git-scm.com/download/win)
- [Palworld Dedicated Server](https://store.steampowered.com/app/2394010/Palworld_Dedicated_Server/) (installed via SteamCMD)
- [UE4SS Palworld Fork](https://github.com/Okaetsu/RE-UE4SS) (for LiveEditor mod and admin commands)
- [AdminCommands Mod](https://www.curseforge.com/palworld/mods/admin-commands) (for give/spawn functionality)

## Quick Start

1. **Clone the repository:**
   ```
   git clone https://github.com/YOUR_USERNAME/palworld-server-toolkit.git
   cd palworld-server-toolkit
   ```

2. **Install the Palworld server:**
   ```
   steamcmd\steamcmd.exe +force_install_dir "FULL_PATH_TO\server" +login anonymous +app_update 2394010 validate +quit
   ```

3. **Configure:**
   ```
   copy config.example.json config.json
   ```
   Edit `config.json` with your server name, admin password, and player UID.

4. **Run setup (as Administrator):**
   ```
   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
   ```
   This creates `config.json` (if missing), initialises the backup git repo, installs the LiveEditor mod, and registers Task Scheduler tasks.

5. **Start the server:**
   ```
   Start-ScheduledTask -TaskName '\Palworld\Startup'
   ```
   Or launch `Monitor.bat` for the GUI dashboard.

## Directory Structure

```
palworld-server-toolkit/
├── config.example.json      # Configuration template
├── config.json              # Your config (git-ignored, contains passwords)
├── Monitor.bat              # Launch GUI monitor
├── LiveEditor.bat           # Launch web admin dashboard
├── CLAUDE.md                # AI assistant instructions
├── scripts/
│   ├── setup.ps1            # One-time setup (run as admin)
│   ├── startup.ps1          # Boot watchdog: update + start + crash loop
│   ├── daily-update.ps1     # Daily 04:00: stop + update + restart
│   ├── backup.ps1           # Hourly git commit of SaveGames
│   ├── backup-robocopy.ps1  # Hourly robocopy snapshot (immune to git)
│   ├── safe-backup.ps1      # Manual pre-operation safety backup
│   ├── update-mods.ps1      # Auto-update UE4SS from GitHub
│   ├── monitor.ps1          # WinForms GUI dashboard
│   ├── rcon-client.ps1      # Pure PowerShell RCON client
│   ├── live-editor-server.ps1  # HTTP server for Live Editor
│   ├── config-loader.ps1    # Shared config.json loader
│   ├── health-check.ps1     # Server health and folder analysis
│   ├── enable-vss.ps1       # Enable Volume Shadow Copy
│   └── live-editor/
│       └── www/             # Live Editor web frontend
│           ├── index.html
│           ├── style.css
│           └── app.js
├── mods/
│   └── LiveEditor/          # UE4SS Lua mod (installed by setup.ps1)
│       ├── enabled.txt
│       └── Scripts/
│           ├── main.lua     # IPC command handler
│           └── Json.lua     # JSON library (dkjson)
├── server/                  # Palworld server files (git-ignored)
├── steamcmd/                # SteamCMD (git-ignored)
├── backups/                 # Backup storage (git-ignored)
└── logs/                    # Log files (git-ignored)
```

## Configuration

Edit `config.json` (copied from `config.example.json` during setup):

| Field | Description | Default |
|---|---|---|
| `server_name` | Display name shown in Live Editor | `My Palworld Server` |
| `admin_password` | AdminPassword for RCON/REST API auth | `CHANGE_ME` |
| `admin_uid` | Your player UID (hex) for admin commands | `YOUR_PLAYER_UID_HERE` |
| `rcon_port` | RCON port | `25575` |
| `rest_api_port` | REST API port | `8212` |
| `live_editor_port` | Live Editor web server port | `8213` |
| `server_port` | Game server port (UDP) | `8211` |
| `public_ip` | Public IP or domain (for server config) | (empty) |
| `server_dir` | Relative path to server directory | `server` |

## Scripts Reference

| Script | Purpose |
|---|---|
| `setup.ps1` | One-time setup: creates config, git repo, Task Scheduler tasks, installs mod |
| `startup.ps1` | Boot watchdog: SteamCMD update, mod update, start server, crash detection loop |
| `daily-update.ps1` | Daily maintenance: graceful shutdown, update, restart |
| `backup.ps1` | Git commit SaveGames directory (hourly via Task Scheduler) |
| `backup-robocopy.ps1` | Robocopy snapshot to `backups/hourly/` (48h rolling window) |
| `safe-backup.ps1` | Manual safety backup before any save file operation |
| `update-mods.ps1` | Check GitHub API for UE4SS updates, install if newer |
| `monitor.ps1` | WinForms GUI: server status, watchdog, mod toggle, backup info, log tail |
| `rcon-client.ps1` | Source RCON protocol client (interactive or single-command mode) |
| `live-editor-server.ps1` | HTTP server for the web-based Live Editor dashboard |
| `health-check.ps1` | Console health check: process, tasks, backups, folder sizes |
| `enable-vss.ps1` | Enable Windows Volume Shadow Copy on the drive |
| `config-loader.ps1` | Shared helper: loads `config.json` for other scripts |

## Network Ports

| Port | Protocol | Service |
|---|---|---|
| 8211 | UDP | Palworld game server |
| 25575 | TCP | RCON (remote console) |
| 8212 | TCP | REST API |
| 8213 | TCP | Live Editor web dashboard (localhost only) |

## Backup System

Four independent layers provide redundant save protection:

| Layer | Method | Schedule | Location | Resilience |
|---|---|---|---|---|
| Git | `backup.ps1` | Hourly | `SaveGames/.git` | Full history, can be affected by git operations |
| Robocopy | `backup-robocopy.ps1` | Hourly | `backups/hourly/` | Immune to git operations, 48h rolling window |
| Safety | `safe-backup.ps1` | Manual | `backups/safe-backup/` | Run before any save file operation |
| VSS | Windows Shadow Copy | Daily | System shadow storage | OS-level, browse via Explorer > Previous Versions |

Recovery priority: `backups/safe-backup/` > `backups/hourly/` > git log > Palworld internal backups > VSS

## Troubleshooting

**Server won't start:**
- Check `logs/` for error output
- Verify the server executable exists: `server\Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe`
- Run SteamCMD update with `+force_install_dir` pointing to the `server` directory

**Mod crashes the server:**
- The watchdog auto-disables mods after 2 consecutive fast crashes (within 8 minutes)
- Manually disable: rename `server\Pal\Binaries\Win64\dwmapi.dll` to `dwmapi.dll.disabled`
- UE4SS may need updating after Palworld patches

**Live Editor not responding:**
- Ensure the server is running with UE4SS and LiveEditor mod enabled
- Check that `config.json` has the correct `admin_uid`
- The IPC timeout is 5 seconds — commands fail if the server doesn't respond

**RCON connection refused:**
- Verify RCON is enabled in `PalWorldSettings.ini` (`RCONEnabled=True`)
- Check the port matches `config.json`
- The server must be fully started before RCON accepts connections

## Licence

This project is licensed under the [GNU General Public License v3.0](LICENSE).
